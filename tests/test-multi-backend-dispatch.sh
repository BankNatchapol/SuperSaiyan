#!/usr/bin/env bash
# test-multi-backend-dispatch.sh — verifies scripts/super-board-run.sh resolves worker_backend
# per lane (Build/QA/Review may each use a different CLI backend in one run), keeps the
# single-string shape working unchanged, and that the backend files assemble per-tool model
# flags. No live board traffic; CLI binaries are stubbed on PATH.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SH="$ROOT/scripts/super-board-run.sh"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

if [ ! -f "$RUN_SH" ]; then
  echo "error: $RUN_SH not found" >&2
  exit 1
fi

echo "checking scripts/super-board-run.sh per-lane backend routing"

# ── 1. Syntax ──────────────────────────────────────────────────────────────
bash -n "$RUN_SH" || fail "bash -n reported a syntax error in super-board-run.sh"
for b in claude-p codex-exec cursor-agent; do
  bash -n "$ROOT/scripts/backends/$b.sh" || fail "bash -n reported a syntax error in backends/$b.sh"
done

# ── 2. Per-lane resolution primitives present ──────────────────────────────
grep -q 'load_backend()' "$RUN_SH" \
  || fail "missing load_backend() — the single sourcing point for backend contracts"
grep -qE 'WORKER_BACKEND_TYPE=.*\| type' "$RUN_SH" \
  || fail "does not branch on the JSON type of .worker_backend (string vs object)"
for v in BUILD_BACKEND QA_BACKEND REVIEW_BACKEND DISTINCT_BACKENDS; do
  grep -q "$v" "$RUN_SH" || fail "missing per-lane resolution variable $v"
done
# bash 3.2 (macOS default) has no associative arrays — guard against a regression that
# reintroduces them for the lane->backend map.
if grep -vE '^\s*#' "$RUN_SH" | grep -qE 'declare -A|mapfile|readarray'; then
  fail "uses a bash-4-only construct (declare -A / mapfile / readarray); repo targets bash 3.2"
fi

# ── 3. load_backend really swaps the live backend_* functions ──────────────
# The contract has no namespacing: sourcing a second backend overwrites the first's
# functions. This is the crux of per-lane dispatch, so assert the swap directly.
SWAP_OUT=$(
  cd "$ROOT" && bash -c '
    set -euo pipefail
    source scripts/backends/claude-p.sh
    first=$(backend_orphan_pattern)
    source scripts/backends/codex-exec.sh
    second=$(backend_orphan_pattern)
    source scripts/backends/cursor-agent.sh
    third=$(backend_orphan_pattern)
    echo "${first}||${second}||${third}"
  '
)
case "$SWAP_OUT" in
  *'claude -p'*'codex exec'*'agent'*) ;;
  *) fail "re-sourcing backends did not swap backend_orphan_pattern (got: $SWAP_OUT)" ;;
esac

# ── 4. Per-tool model flags reach the CLI argv ─────────────────────────────
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR" "$SMOKE_DIR"' EXIT
mkdir -p "$STUB_DIR/bin"

# codex stub: `codex login status` must succeed (auth check); any exec run records its argv.
cat > "$STUB_DIR/bin/codex" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "login" ]; then exit 0; fi
printf '%s\n' "\$@" > "$STUB_DIR/codex-argv.txt"
EOF
# cursor stub: bare \`agent status\` must succeed; any -p run records its argv.
cat > "$STUB_DIR/bin/agent" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "status" ]; then echo "Logged in as test@example.com"; exit 0; fi
printf '%s\n' "\$@" > "$STUB_DIR/agent-argv.txt"
EOF
# claude stub: claude-p's auth check is just \`command -v claude\`, so existence is enough.
cat > "$STUB_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB_DIR/bin/codex" "$STUB_DIR/bin/agent" "$STUB_DIR/bin/claude"

ARGV_OUT=$(
  cd "$ROOT" && PATH="$STUB_DIR/bin:$PATH" bash -c '
    set -euo pipefail
    source scripts/backends/codex-exec.sh
    export CODEX_MODEL=gpt-5.6-sol CODEX_REASONING_EFFORT=high
    backend_run_sync "PROMPT-A" >/dev/null 2>&1
    source scripts/backends/cursor-agent.sh
    export CURSOR_MODEL=cursor-grok-4.5-high
    backend_run_sync "PROMPT-B" >/dev/null 2>&1
  ' && cat "$STUB_DIR/codex-argv.txt" "$STUB_DIR/agent-argv.txt"
)
echo "$ARGV_OUT" | grep -q -- '--model' \
  || fail "backend flags did not include --model when the model env/config was set"
echo "$ARGV_OUT" | grep -q 'gpt-5.6-sol' \
  || fail "codex argv missing the configured model"
echo "$ARGV_OUT" | grep -q 'model_reasoning_effort="high"' \
  || fail "codex argv missing -c model_reasoning_effort"
echo "$ARGV_OUT" | grep -q 'cursor-grok-4.5-high' \
  || fail "cursor argv missing the configured model"
echo "$ARGV_OUT" | grep -q 'PROMPT-A' \
  || fail "codex argv lost the prompt positional"

# Unset model config must NOT emit a bare/empty --model flag.
ARGV_BARE=$(
  cd "$ROOT" && PATH="$STUB_DIR/bin:$PATH" bash -c '
    set -euo pipefail
    source scripts/backends/codex-exec.sh
    backend_run_sync "PROMPT-C" >/dev/null 2>&1
  ' && cat "$STUB_DIR/codex-argv.txt"
)
if echo "$ARGV_BARE" | grep -q -- '--model'; then
  fail "codex emitted --model with no model configured (would break the CLI invocation)"
fi

# ── 5. Smoke: three distinct backends resolve in one run ───────────────────
# A pre-placed workflow-wave.lock halts the dispatcher at the mutual-exclusion gate (exit 74)
# right AFTER per-lane resolution, auth checks, and the orphan guard have all run — proving
# those paths work without entering the infinite tick loop or touching a real board.
SMOKE_DIR=$(mktemp -d)

setup_smoke() {
  # $1 = config JSON body
  rm -rf "${SMOKE_DIR:?}"/*
  mkdir -p "$SMOKE_DIR/.claude/supersaiyan/configs" \
           "$SMOKE_DIR/.claude/supersaiyan/inflight" \
           "$SMOKE_DIR/docs/supersaiyan/runs" \
           "$SMOKE_DIR/.worktrees" \
           "$SMOKE_DIR/scripts/platforms" \
           "$SMOKE_DIR/scripts/backends"
  # Installed-layout mirror: run.sh beside platforms/ + backends/ (install.sh copies all three
  # into .claude/bin/). All three backend contracts must be present for a per-lane config.
  cp "$RUN_SH" "$SMOKE_DIR/scripts/super-board-run.sh"
  cp "$ROOT/scripts/config-resolve.sh" "$SMOKE_DIR/scripts/config-resolve.sh"
  cp "$ROOT/scripts/platforms/github.sh" "$SMOKE_DIR/scripts/platforms/github.sh"
  cp "$ROOT"/scripts/backends/*.sh "$SMOKE_DIR/scripts/backends/"
  chmod +x "$SMOKE_DIR/scripts/super-board-run.sh"
  printf '%s' "$1" > "$SMOKE_DIR/.claude/supersaiyan/configs/smoke.json"
  printf 'SLUG=smoke\nSTARTED=1970-01-01T00:00:00Z\n' \
    > "$SMOKE_DIR/.claude/supersaiyan/inflight/workflow-wave.lock"
}

run_smoke() {
  set +e
  SMOKE_OUT=$(cd "$SMOKE_DIR" && PATH="$STUB_DIR/bin:$PATH" bash scripts/super-board-run.sh smoke 2>&1)
  SMOKE_RC=$?
  set -e
}

# Scenario A — per-lane object, three distinct backends, with per-tool model config.
setup_smoke '{
  "variant": "full",
  "base_branch": "develop",
  "human_approves_merge": true,
  "max_workers": 1,
  "tick_seconds": 120,
  "git_platform": "github",
  "worker_backend": { "build": "codex-exec", "qa": "cursor-agent", "review": "claude-p" },
  "codex": { "model": "gpt-5.6-sol", "reasoning_effort": "high" },
  "cursor": { "model": "cursor-grok-4.5-high" },
  "project": { "owner": "octocat", "number": 1, "status_field_id": "PVTSSF_test", "status_option_ids": {} },
  "notifications": { "bot_identity": "" }
}'
run_smoke
echo "$SMOKE_OUT" | grep -q 'backends: build=codex-exec qa=cursor-agent review=claude-p' \
  || fail "scenario A: startup log missing per-lane backend summary (rc=${SMOKE_RC}): $(echo "$SMOKE_OUT" | head -3)"
[ "$SMOKE_RC" -eq 74 ] || fail "scenario A: expected exit 74 (wave lock), got ${SMOKE_RC}: $(echo "$SMOKE_OUT" | tail -3)"

# Scenario B — plain-string worker_backend still applies to every lane (back-compat guard).
setup_smoke '{
  "variant": "full",
  "base_branch": "develop",
  "human_approves_merge": true,
  "max_workers": 1,
  "tick_seconds": 120,
  "git_platform": "github",
  "worker_backend": "claude-p",
  "project": { "owner": "octocat", "number": 1, "status_field_id": "PVTSSF_test", "status_option_ids": {} },
  "notifications": { "bot_identity": "" }
}'
run_smoke
echo "$SMOKE_OUT" | grep -q 'backends: build=claude-p qa=claude-p review=claude-p' \
  || fail "scenario B: string backend did not fan out to all lanes (rc=${SMOKE_RC})"
[ "$SMOKE_RC" -eq 74 ] || fail "scenario B: expected exit 74 (wave lock), got ${SMOKE_RC}"

# Scenario C — an invalid per-lane value is rejected, naming the offending lane.
setup_smoke '{
  "variant": "qa-only",
  "base_branch": "develop",
  "human_approves_merge": true,
  "max_workers": 1,
  "git_platform": "github",
  "worker_backend": { "qa": "not-a-real-backend", "review": "claude-p" },
  "project": { "owner": "octocat", "number": 1, "status_field_id": "PVTSSF_test", "status_option_ids": {} },
  "notifications": { "bot_identity": "" }
}'
run_smoke
[ "$SMOKE_RC" -eq 78 ] || fail "scenario C: expected exit 78 for an invalid per-lane backend, got ${SMOKE_RC}"
echo "$SMOKE_OUT" | grep -q 'worker_backend.qa' \
  || fail "scenario C: rejection message does not name the offending lane"

# Scenario D — "workflow" is not a valid per-lane value (it is Claude-Code-session-bound).
setup_smoke '{
  "variant": "qa-only",
  "base_branch": "develop",
  "human_approves_merge": true,
  "max_workers": 1,
  "git_platform": "github",
  "worker_backend": { "qa": "workflow", "review": "claude-p" },
  "project": { "owner": "octocat", "number": 1, "status_field_id": "PVTSSF_test", "status_option_ids": {} },
  "notifications": { "bot_identity": "" }
}'
run_smoke
[ "$SMOKE_RC" -eq 78 ] || fail "scenario D: expected exit 78 for worker_backend.qa=workflow, got ${SMOKE_RC}"

# Scenario E — qa-only ignores an unusable build key (that lane never dispatches).
setup_smoke '{
  "variant": "qa-only",
  "base_branch": "develop",
  "human_approves_merge": true,
  "max_workers": 1,
  "tick_seconds": 120,
  "git_platform": "github",
  "worker_backend": { "qa": "codex-exec", "review": "claude-p" },
  "project": { "owner": "octocat", "number": 1, "status_field_id": "PVTSSF_test", "status_option_ids": {} },
  "notifications": { "bot_identity": "" }
}'
run_smoke
[ "$SMOKE_RC" -eq 74 ] || fail "scenario E: qa-only with no build key should reach the wave gate, got ${SMOKE_RC}"
echo "$SMOKE_OUT" | grep -q 'backends: qa=codex-exec review=claude-p' \
  || fail "scenario E: qa-only summary should omit the build lane (rc=${SMOKE_RC})"

if [ "$FAIL" -ne 0 ]; then
  echo "error: super-board-run.sh failed the per-lane backend contract check" >&2
  exit 1
fi

echo "  ✓ per-lane resolution + backend swap + model flags + 5 smoke scenarios"
echo "PASS: test-multi-backend-dispatch.sh"
