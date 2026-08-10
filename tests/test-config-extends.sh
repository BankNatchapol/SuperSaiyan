#!/usr/bin/env bash
# test-config-extends.sh — verifies the `extends` config-linking mechanism: a config may
# inherit shared fields from a base config in the same directory (scripts/config-resolve.sh,
# references/config-schema.json `extends`). Covers the shared resolver directly, then its
# integration into scripts/super-board-run.sh and scripts/super-board-wave-plan.sh. No live
# board traffic.

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
cat > "$SMOKE_DIR/.supersaiyan/configs/smoke-base.json" <<'EOF'
{
  "variant": "full",
  "base_branch": "develop",
  "human_approves_merge": true,
  "max_workers": 1,
  "tick_seconds": 120,
  "git_platform": "github",
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
