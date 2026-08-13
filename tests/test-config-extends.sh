#!/usr/bin/env bash
# test-config-extends.sh — verifies the `extends` config-linking mechanism: a config may
# inherit shared fields from a base config in the same directory (scripts/config-resolve.sh,
# references/config-schema.json `extends`). Covers the shared resolver directly, its
# persist_resolved_config()/`--effective-path` CLI wrapper (what the workflow-backend
# orchestrator shells out to — references/run-workflow.md), and integration into
# scripts/super-board-run.sh and scripts/super-board-wave-plan.sh. No live board traffic.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVE_SH="$ROOT/scripts/config-resolve.sh"
RUN_SH="$ROOT/scripts/super-board-run.sh"
WAVE_PLAN_SH="$ROOT/scripts/super-board-wave-plan.sh"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

for f in "$RESOLVE_SH" "$RUN_SH" "$WAVE_PLAN_SH"; do
  [ -f "$f" ] || { echo "error: $f not found" >&2; exit 1; }
done

echo "checking extends config-linking"

# ── 1. Syntax ──────────────────────────────────────────────────────────────
bash -n "$RESOLVE_SH" || fail "bash -n reported a syntax error in config-resolve.sh"
bash -n "$RUN_SH" || fail "bash -n reported a syntax error in super-board-run.sh"
bash -n "$WAVE_PLAN_SH" || fail "bash -n reported a syntax error in super-board-wave-plan.sh"
grep -q 'resolve_config_extends()' "$RESOLVE_SH" \
  || fail "missing resolve_config_extends() in config-resolve.sh"
for consumer in "$RUN_SH" "$WAVE_PLAN_SH"; do
  grep -q 'config-resolve.sh' "$consumer" \
    || fail "$consumer does not source config-resolve.sh"
done

TD=$(mktemp -d)
trap 'rm -rf "$TD"' EXIT

# The smoke configs below use worker_backend "claude-p", whose backend_auth_check is
# `command -v claude`. CI runners don't have Claude Code installed, and this test is about
# `extends` resolution, not CLI availability — so stub it and stay hermetic.
STUB_BIN="$TD/stub-bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB_BIN/claude"
export PATH="$STUB_BIN:$PATH"

cat > "$TD/base.json" <<'EOF'
{"project":{"owner":"o","number":1},"variant":"full","rebuild_cap":2,"notifications":{"bot_identity":"bob"}}
EOF
cat > "$TD/overlay.json" <<'EOF'
{"extends":"base","description":"overlay","worker_backend":"codex-exec","notifications":{"channel":"slack"}}
EOF
cat > "$TD/plain.json" <<'EOF'
{"project":{"owner":"o","number":9},"worker_backend":"claude-p"}
EOF
cat > "$TD/broken.json" <<'EOF'
{"extends":"does-not-exist","worker_backend":"claude-p"}
EOF
cat > "$TD/chain-a.json" <<'EOF'
{"extends":"chain-b","worker_backend":"claude-p"}
EOF
cat > "$TD/chain-b.json" <<'EOF'
{"extends":"base","project":{"owner":"o","number":3}}
EOF

# ── 2. resolve_config_extends() directly ────────────────────────────────────
# shellcheck disable=SC1090
source "$RESOLVE_SH"

RESOLVED=$(resolve_config_extends "$TD/overlay.json") || fail "resolve_config_extends failed on a valid overlay"
if [ "$RESOLVED" = "$TD/overlay.json" ]; then
  fail "expected a merged temp file, got the original overlay path unchanged"
fi
MERGED_JSON=$(cat "$RESOLVED")
echo "$MERGED_JSON" | jq -e '.project.number == 1' >/dev/null || fail "merged config missing inherited project.number"
echo "$MERGED_JSON" | jq -e '.notifications.bot_identity == "bob"' >/dev/null || fail "merged config lost inherited notifications.bot_identity"
echo "$MERGED_JSON" | jq -e '.notifications.channel == "slack"' >/dev/null || fail "merged config did not apply overlay's notifications.channel"
echo "$MERGED_JSON" | jq -e '.worker_backend == "codex-exec"' >/dev/null || fail "merged config lost overlay's own worker_backend"
echo "$MERGED_JSON" | jq -e 'has("extends") | not' >/dev/null || fail "merged config still has extends key (should be stripped)"
rm -f "$RESOLVED"

NOOP=$(resolve_config_extends "$TD/plain.json") || fail "resolve_config_extends failed on a plain config"
[ "$NOOP" = "$TD/plain.json" ] || fail "expected the unchanged path for a config with no extends, got: $NOOP"

if resolve_config_extends "$TD/broken.json" >/dev/null 2>/tmp/extends-err.txt; then
  fail "resolve_config_extends should fail when the extends target is missing"
fi
grep -q 'does-not-exist' /tmp/extends-err.txt || fail "missing-base error does not name the target"

if resolve_config_extends "$TD/chain-a.json" >/dev/null 2>/tmp/extends-err.txt; then
  fail "resolve_config_extends should reject chained extends"
fi
grep -qi 'chain' /tmp/extends-err.txt || fail "chained-extends error message does not mention chaining"
rm -f /tmp/extends-err.txt

# ── 2b. persist_resolved_config() / `--effective-path` CLI: absolute, stable paths ──────────
# This is the regression that let a real defect through review of an earlier version of this
# fix: super-board-run.sh persisted the resolved config to a RELATIVE path
# (<config-root>/resolved/<slug>.json where <config-root> is e.g. ".supersaiyan"). Every
# assertion up to this point in the file checks the persisted file's CONTENT, which passes
# whether the path handed to a worker is relative or absolute. A worker's actual cwd is a git
# worktree (references/run.md), not this repo root — a relative path resolves fine from here
# and is ENOENT there. So every check below additionally asserts absoluteness and
# from-elsewhere readability, not just existence-from-the-test's-own-cwd.
#
# Layout matches real usage — <root>/configs/<slug>.json — because persist_resolved_config
# derives <root>/resolved/ by walking up from the config's own directory; a flat directory of
# configs (as $TD is, for the resolve_config_extends() calls above) would compute a
# resolved/ dir one level too high to be meaningful here.
PERSIST_ROOT="$TD/persist-root"
mkdir -p "$PERSIST_ROOT/configs"
cat > "$PERSIST_ROOT/configs/base.json" <<'EOF'
{"project":{"owner":"o","number":1},"base_branch":"develop"}
EOF
cat > "$PERSIST_ROOT/configs/overlay.json" <<'EOF'
{"extends":"base","worker_backend":"codex-exec"}
EOF
cat > "$PERSIST_ROOT/configs/plain2.json" <<'EOF'
{"project":{"owner":"o","number":9}}
EOF

NOOP_EFFECTIVE=$(bash "$RESOLVE_SH" --effective-path "$PERSIST_ROOT/configs/plain2.json") \
  || fail "config-resolve.sh --effective-path failed on a no-extends config"
case "$NOOP_EFFECTIVE" in
  /*) ;;
  *) fail "--effective-path did not return an absolute path for a no-extends config: $NOOP_EFFECTIVE" ;;
esac
[ -f "$NOOP_EFFECTIVE" ] || fail "--effective-path's no-extends output does not point at a real file: $NOOP_EFFECTIVE"

EXT_EFFECTIVE=$(bash "$RESOLVE_SH" --effective-path "$PERSIST_ROOT/configs/overlay.json") \
  || fail "config-resolve.sh --effective-path failed on an extends config"
case "$EXT_EFFECTIVE" in
  /*) ;;
  *) fail "--effective-path did not return an absolute path for an extends config: $EXT_EFFECTIVE" ;;
esac
case "$EXT_EFFECTIVE" in
  "$PERSIST_ROOT"/resolved/*) ;;
  *) fail "--effective-path persisted an extends config outside <root>/resolved/: $EXT_EFFECTIVE" ;;
esac
jq -e '.base_branch == "develop"' "$EXT_EFFECTIVE" >/dev/null \
  || fail "--effective-path's persisted config lost the inherited base_branch"
jq -e 'has("extends") | not' "$EXT_EFFECTIVE" >/dev/null \
  || fail "--effective-path's persisted config still carries the extends key"

# The actual failure mode: readable from a completely different cwd, simulating a worker
# running from .worktrees/issue-N-<lane>/ rather than this repo root.
( cd / && [ -f "$EXT_EFFECTIVE" ] ) \
  || fail "--effective-path's persisted config is not readable from a different cwd (relative path?): $EXT_EFFECTIVE"

# No .tmp.* staging residue left behind — guards the atomic cp-then-same-dir-mv write.
TMP_RESIDUE=$(find "$PERSIST_ROOT/resolved" -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
[ "$TMP_RESIDUE" -eq 0 ] \
  || fail "config-resolve.sh --effective-path left ${TMP_RESIDUE} .tmp.* staging file(s) behind in resolved/"

# Regression guard: persist_resolved_config()'s staged `mv` must be checked. This file sets
# no `set -e` at all (see its header), so an unchecked `mv` would fall through, RETURN 0, and
# print a path that may not exist — every real caller depends on the exit code alone to catch
# a resolution failure (super-board-run.sh:82 is `... || exit 66`). Shadow `mv` with a shell
# function to force the failure deterministically; a REAL mv failure isn't cleanly forceable
# here (`mv file existing-dir/` moves INTO the dir rather than failing, and making `cp`
# succeed while `mv` fails needs exotic permissions), so this exercises the function's own
# error path directly rather than fabricate a filesystem scenario to trigger it indirectly.
# Calls the already-sourced persist_resolved_config() (section 2 above), not the CLI: a
# subprocess wouldn't see this shell's function shadow without `export -f`.
mv() { return 1; }
if persist_resolved_config "$PERSIST_ROOT/configs/overlay.json" >/tmp/mv-fail-out.txt 2>/tmp/mv-fail-err.txt; then
  fail "persist_resolved_config must fail (nonzero) when the staged mv fails"
fi
[ -s /tmp/mv-fail-out.txt ] \
  && fail "persist_resolved_config printed a path on stdout despite the mv failing: $(cat /tmp/mv-fail-out.txt)"
unset -f mv
rm -f /tmp/mv-fail-out.txt /tmp/mv-fail-err.txt
MV_FAIL_RESIDUE=$(find "$PERSIST_ROOT/resolved" -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
[ "$MV_FAIL_RESIDUE" -eq 0 ] \
  || fail "persist_resolved_config left ${MV_FAIL_RESIDUE} .tmp.* file(s) behind after a failed mv"

# CLI usage/error handling.
if bash "$RESOLVE_SH" --effective-path >/dev/null 2>/tmp/cli-err.txt; then
  fail "--effective-path with no config-path argument should fail (usage error)"
fi
rm -f /tmp/cli-err.txt

if bash "$RESOLVE_SH" --effective-path "$TD/broken.json" >/dev/null 2>/tmp/cli-err.txt; then
  fail "--effective-path should fail when the extends target is missing"
fi
grep -q 'does-not-exist' /tmp/cli-err.txt || fail "--effective-path's missing-base error does not name the target"
rm -f /tmp/cli-err.txt

# ── 3. super-board-wave-plan.sh: extends resolved, process-substitution (test) mode untouched ──
WAVE_ITEMS='{"items":[{"content":{"number":5,"type":"Issue","title":"t","assignees":[]},"status":"Ready"}]}'

WAVE_OUT=$("$WAVE_PLAN_SH" --config "$TD/overlay.json" --items <(echo "$WAVE_ITEMS"))
echo "$WAVE_OUT" | jq -e '.cards[0].number == 5' >/dev/null \
  || fail "wave-plan with an extends overlay did not select the expected card (inherited project/variant not resolved?)"

FIFO_OUT=$("$WAVE_PLAN_SH" --config <(cat "$TD/base.json") --items <(echo "$WAVE_ITEMS"))
echo "$FIFO_OUT" | jq -e '.cards[0].number == 5' >/dev/null \
  || fail "wave-plan process-substitution (FIFO) mode regressed"

if "$WAVE_PLAN_SH" --config "$TD/broken.json" --items <(echo '{"items":[]}') >/dev/null 2>/tmp/wave-err.txt; then
  fail "wave-plan should fail on a broken extends target"
fi
grep -q 'does-not-exist' /tmp/wave-err.txt || fail "wave-plan's extends error does not name the target"
rm -f /tmp/wave-err.txt

# Regression: the merged-config temp file must not outlive the process. On the live-fetch path
# wave-plan sets TWO EXIT traps — resolved-config cleanup, then CONFIG_REF cleanup — and a
# second `trap ... EXIT` REPLACES the first rather than adding to it. That leaked one fully
# resolved config (project owner/number, notifications, bot identity) per wave tick.
#
# Probing by content, not by pointing TMPDIR at a scratch dir: macOS `mktemp` ignores TMPDIR
# (Darwin resolves _CS_DARWIN_USER_TEMP_DIR instead), so a TMPDIR-based probe silently passes
# on the very platform this repo targets. Tagging the config with a unique sentinel and
# searching the real mktemp directory works on both platforms and can't be confused by
# unrelated temp files from other processes.
MKTEMP_PROBE=$(mktemp)
MKTEMP_DIR=$(dirname "$MKTEMP_PROBE")
rm -f "$MKTEMP_PROBE"
leaked_temps() {
  # $1 = sentinel. Lists surviving mktemp files that contain it, scoped to this test's own
  # user: on Linux, mktemp's default dir is often a shared /tmp, and this function's callers
  # `rm -f` what it finds — unscoped, a busy shared box means both slower scans and a real
  # risk of deleting another user's live temp file. `-exec ... \;` (not `+`): with `+` and
  # zero matches, grep would run with no file operands and block reading stdin.
  find "$MKTEMP_DIR" -maxdepth 1 -type f -name 'tmp.*' -user "$(id -u)" -exec grep -lF "$1" {} \; 2>/dev/null
}

cat > "$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo '{"items":[]}'
EOF
chmod +x "$STUB_BIN/gh"

WAVE_SENTINEL="wave-plan-extends-leak-probe-$$"
cat > "$TD/leak-base.json" <<EOF
{"project":{"owner":"o","number":1},"variant":"full","description":"$WAVE_SENTINEL"}
EOF
cat > "$TD/leak-overlay.json" <<'EOF'
{"extends":"leak-base","worker_backend":"codex-exec"}
EOF
# No --items, so the CONFIG_REF branch (and therefore the second trap) is live.
"$WAVE_PLAN_SH" --config "$TD/leak-overlay.json" >/dev/null 2>&1 || true
WAVE_LEAKED=$(leaked_temps "$WAVE_SENTINEL" | wc -l | tr -d ' ')
[ "$WAVE_LEAKED" -eq 0 ] \
  || fail "wave-plan leaked ${WAVE_LEAKED} temp file(s) holding the resolved config — a second EXIT trap replaced the first"
leaked_temps "$WAVE_SENTINEL" | while IFS= read -r f; do rm -f "$f"; done

# The flip side of that cleanup: resolve_config_extends returns the INPUT path unchanged when
# a config has no `extends`, so a cleanup that doesn't distinguish "temp file I made" from
# "the file the user passed in" would delete a real committed config.
"$WAVE_PLAN_SH" --config "$TD/plain.json" >/dev/null 2>&1 || true
[ -f "$TD/plain.json" ] \
  || fail "wave-plan DELETED a no-extends config file — cleanup must not touch the caller's own path"

# ── 4. super-board-run.sh smoke: extends-linked config reaches the wave-lock gate ───────────
SMOKE_DIR=$(mktemp -d)

mkdir -p "$SMOKE_DIR/.supersaiyan/configs" \
         "$SMOKE_DIR/.supersaiyan/inflight" \
         "$SMOKE_DIR/docs/supersaiyan/runs" \
         "$SMOKE_DIR/.worktrees" \
         "$SMOKE_DIR/scripts/platforms" \
         "$SMOKE_DIR/scripts/backends"
cp "$RUN_SH" "$SMOKE_DIR/scripts/super-board-run.sh"
cp "$RESOLVE_SH" "$SMOKE_DIR/scripts/config-resolve.sh"
cp "$ROOT/scripts/platforms/github.sh" "$SMOKE_DIR/scripts/platforms/github.sh"
cp "$ROOT/scripts/backends/claude-p.sh" "$SMOKE_DIR/scripts/backends/claude-p.sh"
chmod +x "$SMOKE_DIR/scripts/super-board-run.sh"

# Base carries the fields that matter for the startup log + gating; the overlay only sets
# description/worker_backend/extends, proving the dispatcher actually reads through the link.
# SMOKE_SENTINEL is $$-scoped (not a fixed literal) so leaked_temps() below can't match a
# leftover from a different, concurrent run of this same test file.
SMOKE_SENTINEL="super-board-run-extends-leak-probe-$$"
cat > "$SMOKE_DIR/.supersaiyan/configs/smoke-base.json" <<EOF
{
  "variant": "full",
  "base_branch": "develop",
  "human_approves_merge": true,
  "max_workers": 1,
  "tick_seconds": 120,
  "git_platform": "github",
  "description": "${SMOKE_SENTINEL}",
  "project": { "owner": "octocat", "number": 1, "status_field_id": "PVTSSF_test", "status_option_ids": {} },
  "notifications": { "bot_identity": "" }
}
EOF
cat > "$SMOKE_DIR/.supersaiyan/configs/smoke.json" <<'EOF'
{ "extends": "smoke-base", "description": "overlay smoke", "worker_backend": "claude-p" }
EOF
printf 'SLUG=smoke\nSTARTED=1970-01-01T00:00:00Z\n' \
  > "$SMOKE_DIR/.supersaiyan/inflight/workflow-wave.lock"

set +e
SMOKE_OUT=$(cd "$SMOKE_DIR" && bash scripts/super-board-run.sh smoke 2>&1)
SMOKE_RC=$?
set -e

echo "$SMOKE_OUT" | grep -q 'super-board run started — config=smoke variant=full base=develop' \
  || fail "extends-linked config did not resolve base_branch/variant from the base file (rc=${SMOKE_RC}): $(echo "$SMOKE_OUT" | head -3)"
[ "$SMOKE_RC" -eq 74 ] || fail "expected exit 74 (wave lock) for an extends-linked config, got ${SMOKE_RC}: $(echo "$SMOKE_OUT" | tail -3)"

# Regression: with `extends`, CONFIG_PATH must name a STABLE file that outlives this process.
# dispatch_lane embeds CONFIG_PATH verbatim in every worker prompt, and workers routinely
# outlive the dispatcher (a crashed dispatcher leaves orphan workers behind — see
# references/stop.md), so a mktemp path deleted by our own EXIT trap would vanish out from
# under a worker that reads its config lazily.
RESOLVED_FILE="$SMOKE_DIR/.supersaiyan/resolved/smoke.json"
if [ -f "$RESOLVED_FILE" ]; then
  jq -e '.base_branch == "develop"' "$RESOLVED_FILE" >/dev/null \
    || fail "persisted resolved config did not inherit base_branch from its base file"
  jq -e 'has("extends") | not' "$RESOLVED_FILE" >/dev/null \
    || fail "persisted resolved config still carries the extends key"
else
  fail "extends-linked run left no resolved config at .supersaiyan/resolved/smoke.json — workers would be handed a deleted temp path"
fi

# Regression (the specific bug that shipped in an earlier version of this fix): the path
# LOGGED — i.e. the same value dispatch_lane would embed in a worker's prompt — must be
# absolute. It previously was "<config-root>/resolved/smoke.json" with a RELATIVE
# config-root (".supersaiyan"), which only resolves from this repo's own root. A real
# worker's cwd is a git worktree (references/run.md), not this repo root — checking the file
# exists via a path this test builds from $SMOKE_DIR (as above) passes either way and would
# NOT have caught that. This assertion targets the actual failure mode instead.
DISPATCH_PATH_LINE=$(echo "$SMOKE_OUT" | grep 'worker config path (embedded in every dispatch_lane prompt):' || true)
[ -n "$DISPATCH_PATH_LINE" ] || fail "super-board-run.sh did not log the worker-facing config path"
DISPATCH_PATH=$(echo "$DISPATCH_PATH_LINE" | sed 's/.*worker config path (embedded in every dispatch_lane prompt): //')
case "$DISPATCH_PATH" in
  /*) ;;
  *) fail "worker-facing config path is not absolute — a worker cd'd into a worktree would get ENOENT: $DISPATCH_PATH" ;;
esac
( cd / && [ -f "$DISPATCH_PATH" ] ) \
  || fail "worker-facing config path is not readable from a different cwd (simulates a worker running from .worktrees/…): $DISPATCH_PATH"

# The resolved copy must NOT land in configs/: every consumer (platform-config.sh's config
# count, super-board-status.py's configs/*.json glob, control-core's discoverConfigs) treats
# each file there as a board, so a copy would register as a phantom extra board.
CFG_COUNT=$(find "$SMOKE_DIR/.supersaiyan/configs" -name '*.json' | wc -l | tr -d ' ')
[ "$CFG_COUNT" -eq 2 ] \
  || fail "expected 2 files in configs/ (base + overlay), found ${CFG_COUNT} — the resolved copy must not be written there"

# Persisting the resolved view must consume the mktemp file, not copy it and leave the
# original behind. Same content-sentinel probe as the wave-plan check above; SMOKE_SENTINEL
# is $$-scoped so this can't false-positive (or, worse, delete a live temp file) against a
# concurrent run of this same test.
SMOKE_LEAKED=$(leaked_temps "$SMOKE_SENTINEL" | wc -l | tr -d ' ')
[ "$SMOKE_LEAKED" -eq 0 ] \
  || fail "super-board-run.sh left ${SMOKE_LEAKED} temp file(s) behind after resolving an extends config"
leaked_temps "$SMOKE_SENTINEL" | while IFS= read -r f; do rm -f "$f"; done

# No .tmp.* staging residue in the persisted resolved/ dir — guards the atomic write there too.
RESOLVED_TMP_RESIDUE=$(find "$SMOKE_DIR/.supersaiyan/resolved" -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
[ "$RESOLVED_TMP_RESIDUE" -eq 0 ] \
  || fail "super-board-run.sh left ${RESOLVED_TMP_RESIDUE} .tmp.* staging file(s) behind in resolved/"

# Scenario: overlay's extends target is missing entirely — must fail loudly, not silently
# fall back to workflow-backend defaults.
cat > "$SMOKE_DIR/.supersaiyan/configs/smoke.json" <<'EOF'
{ "extends": "no-such-base", "worker_backend": "claude-p" }
EOF
set +e
BROKEN_OUT=$(cd "$SMOKE_DIR" && bash scripts/super-board-run.sh smoke 2>&1)
BROKEN_RC=$?
set -e
[ "$BROKEN_RC" -eq 66 ] || fail "expected exit 66 for a config extending a missing base, got ${BROKEN_RC}"
echo "$BROKEN_OUT" | grep -q 'no-such-base' || fail "missing-base error does not name the target"

if [ "$FAIL" -ne 0 ]; then
  echo "error: extends config-linking failed one or more checks" >&2
  exit 1
fi

echo "  ✓ resolver unit cases + wave-plan integration (incl. FIFO test mode) + super-board-run.sh smoke"
echo "PASS: test-config-extends.sh"
