#!/usr/bin/env bash
# test-run-platform-rewire.sh — verifies scripts/super-board-run.sh sources the Platform
# interface by git_platform and routes the inline gh / production-CI call sites through
# platform_* (issue #3 / gitlab-integration task 03). No live board traffic.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SH="$ROOT/scripts/super-board-run.sh"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

if [ ! -f "$RUN_SH" ]; then
  echo "error: $RUN_SH not found" >&2
  exit 1
fi

echo "checking scripts/super-board-run.sh platform rewire"

# ── 1. Syntax ──────────────────────────────────────────────────────────────
if ! bash -n "$RUN_SH"; then
  fail "bash -n reported a syntax error"
fi

# ── 2. GIT_PLATFORM read + BASH_SOURCE-relative platforms/ source ──────────
grep -qE "GIT_PLATFORM=.*jq -r '\\.git_platform // \"github\"'" "$RUN_SH" \
  || fail "does not read GIT_PLATFORM from config via jq '.git_platform // \"github\"'"

grep -q 'dirname "${BASH_SOURCE\[0\]}"' "$RUN_SH" \
  || fail "missing BASH_SOURCE-relative SCRIPT_DIR for platform sourcing"

grep -q 'platforms/${GIT_PLATFORM}.sh' "$RUN_SH" \
  || fail "does not source platforms/\${GIT_PLATFORM}.sh"

# ── 3. Required platform_* call sites present ──────────────────────────────
for fn in platform_board_snapshot platform_rate_remaining platform_claim_issue \
          platform_release_issue platform_detect_production_ci; do
  grep -q "$fn" "$RUN_SH" || fail "missing call to $fn"
done

# ── 4. Replaced raw call sites must be gone ────────────────────────────────
# Allow mentions inside comments, but not as executable call sites.
if grep -vE '^\s*#' "$RUN_SH" | grep -qE 'gh[[:space:]]+project[[:space:]]+item-list'; then
  fail "still has inline 'gh project item-list' (use platform_board_snapshot)"
fi
if grep -vE '^\s*#' "$RUN_SH" | grep -qE 'gh[[:space:]]+api[[:space:]]+rate_limit'; then
  fail "still has inline 'gh api rate_limit' (use platform_rate_remaining)"
fi
if grep -vE '^\s*#' "$RUN_SH" | grep -qE 'gh[[:space:]]+issue[[:space:]]+edit.*--add-assignee'; then
  fail "still has inline 'gh issue edit --add-assignee' (use platform_claim_issue)"
fi
if grep -vE '^\s*#' "$RUN_SH" | grep -qE 'gh[[:space:]]+issue[[:space:]]+edit.*--remove-assignee'; then
  fail "still has inline 'gh issue edit --remove-assignee' (use platform_release_issue)"
fi
if grep -vE '^\s*#' "$RUN_SH" | grep -qE "rg -qU 'on:\\\\s\*\\\\n\?\\\\s\*push:"; then
  fail "still has inline production-merge rg grep (use platform_detect_production_ci)"
fi

# ── 5. Smoke: temp repo + config exits cleanly with startup log shape ──────
# Uses a pre-existing workflow-wave.lock so the dispatcher refuses at the
# mutual-exclusion gate (exit 74) after sourcing the platform — same shape as
# before the rewire, without entering the infinite tick loop.
SMOKE_DIR=$(mktemp -d)
trap 'rm -rf "$SMOKE_DIR"' EXIT

mkdir -p "$SMOKE_DIR/.supersaiyan/configs" \
         "$SMOKE_DIR/.supersaiyan/inflight" \
         "$SMOKE_DIR/docs/supersaiyan/runs" \
         "$SMOKE_DIR/.worktrees" \
         "$SMOKE_DIR/scripts/platforms" \
         "$SMOKE_DIR/scripts/backends"

# Installed-layout mirror: run.sh beside platforms/ + backends/ (install.sh copies all three
# into .supersaiyan/bin/). worker_backend gate runs before the platform gate, so both contracts
# must be present for the smoke run to reach the platform-rewire behavior under test.
cp "$RUN_SH" "$SMOKE_DIR/scripts/super-board-run.sh"
cp "$ROOT/scripts/config-resolve.sh" "$SMOKE_DIR/scripts/config-resolve.sh"
cp "$ROOT/scripts/platforms/github.sh" "$SMOKE_DIR/scripts/platforms/github.sh"
cp "$ROOT/scripts/backends/claude-p.sh" "$SMOKE_DIR/scripts/backends/claude-p.sh"
chmod +x "$SMOKE_DIR/scripts/super-board-run.sh"

cat > "$SMOKE_DIR/.supersaiyan/configs/smoke.json" <<'EOF'
{
  "variant": "full",
  "base_branch": "develop",
  "human_approves_merge": true,
  "max_workers": 1,
  "tick_seconds": 120,
  "rebuild_cap": 2,
  "block_rate_alert_pct": 30,
  "git_platform": "github",
  "worker_backend": "claude-p",
  "project": {
    "owner": "octocat",
    "number": 1,
    "status_field_id": "PVTSSF_test",
    "status_option_ids": {}
  },
  "notifications": { "bot_identity": "" }
}
EOF

printf 'SLUG=smoke\nSTARTED=1970-01-01T00:00:00Z\n' \
  > "$SMOKE_DIR/.supersaiyan/inflight/workflow-wave.lock"

set +e
SMOKE_OUT=$(
  cd "$SMOKE_DIR" && bash scripts/super-board-run.sh smoke 2>&1
)
SMOKE_RC=$?
set -e

echo "$SMOKE_OUT" | grep -q 'super-board run started — config=smoke' \
  || fail "smoke log missing startup line (rc=${SMOKE_RC}): $(echo "$SMOKE_OUT" | head -5)"

echo "$SMOKE_OUT" | grep -q 'refusing to start: workflow-backend wave in flight' \
  || fail "smoke log missing wave-lock refuse line (rc=${SMOKE_RC})"

if [ "$SMOKE_RC" -ne 74 ]; then
  fail "smoke expected exit 74 (wave lock), got ${SMOKE_RC}"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "error: super-board-run.sh failed the platform-rewire contract check" >&2
  exit 1
fi

echo "  ✓ GIT_PLATFORM source + platform_* call sites + smoke exit 74"
echo "PASS: test-run-platform-rewire.sh"
