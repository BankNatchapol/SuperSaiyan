#!/usr/bin/env bash
# test-tasks-wave-dispatch-platform-rewire.sh — verifies issue #4 / gitlab-integration
# task 04: tasks-to-issues.sh, super-board-wave-plan.sh, and super-build-dispatch.sh
# route their remaining direct gh board/issue calls through platform_*.
# Static contract + syntax only — no live board traffic.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS="$ROOT/scripts/tasks-to-issues.sh"
WAVE="$ROOT/scripts/super-board-wave-plan.sh"
DISPATCH="$ROOT/skills/super-build/scripts/super-build-dispatch.sh"
GITHUB_PLATFORM="$ROOT/scripts/platforms/github.sh"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

for f in "$TASKS" "$WAVE" "$DISPATCH" "$GITHUB_PLATFORM"; do
  if [ ! -f "$f" ]; then
    echo "error: $f not found" >&2
    exit 1
  fi
done

echo "checking issue #4 platform rewire (tasks-to-issues / wave-plan / dispatch)"

# ── 1. Syntax ──────────────────────────────────────────────────────────────
for f in "$TASKS" "$WAVE" "$DISPATCH"; do
  if ! bash -n "$f"; then
    fail "bash -n reported a syntax error in $(basename "$f")"
  fi
done

# ── 2. Each script sources platforms/\${GIT_PLATFORM}.sh ───────────────────
for f in "$TASKS" "$WAVE" "$DISPATCH"; do
  grep -q 'platforms/${GIT_PLATFORM}.sh' "$f" \
    || fail "$(basename "$f") does not source platforms/\${GIT_PLATFORM}.sh"
done

# ── 3. tasks-to-issues: board bootstrap + Ready set via platform_* ─────────
grep -q 'platform_card_status_set' "$TASKS" \
  || fail "tasks-to-issues.sh missing platform_card_status_set"
grep -q -- 'platform_card_status_set --add' "$TASKS" \
  || fail "tasks-to-issues.sh missing logical Ready enqueue"
grep -qE 'platform_(board_ensure|label_ensure)' "$GITHUB_PLATFORM" \
  || fail "GitHub adapter missing board metadata validation"

if grep -vE '^\s*#' "$TASKS" | grep -qE 'gh[[:space:]]+project[[:space:]]+view'; then
  fail "tasks-to-issues.sh still has inline 'gh project view'"
fi
if grep -vE '^\s*#' "$TASKS" | grep -qE 'gh[[:space:]]+project[[:space:]]+field-list'; then
  fail "tasks-to-issues.sh still has inline 'gh project field-list'"
fi
if grep -vE '^\s*#' "$TASKS" | grep -qE 'gh[[:space:]]+project[[:space:]]+item-add'; then
  fail "tasks-to-issues.sh still has inline 'gh project item-add' (use platform_card_status_set --add)"
fi
if grep -vE '^\s*#' "$TASKS" | grep -qE 'gh[[:space:]]+project[[:space:]]+item-edit'; then
  fail "tasks-to-issues.sh still has inline 'gh project item-edit' (use platform_card_status_set)"
fi

# ── 4. wave-plan: board snapshot via platform_board_snapshot ───────────────
grep -q 'platform_board_snapshot' "$WAVE" \
  || fail "super-board-wave-plan.sh missing platform_board_snapshot"
# Depends-on jq must remain (output-shape contract).
grep -q 'Depends on' "$WAVE" \
  || fail "super-board-wave-plan.sh lost Depends-on jq dependency parsing"
if grep -vE '^\s*#' "$WAVE" | grep -qE 'gh[[:space:]]+project[[:space:]]+item-list'; then
  fail "super-board-wave-plan.sh still has inline 'gh project item-list'"
fi

# ── 5. dispatch: issue view via platform_issue_view ────────────────────────
grep -q 'platform_issue_view' "$DISPATCH" \
  || fail "super-build-dispatch.sh missing platform_issue_view"
grep -q 'CONFIG_PATH' "$DISPATCH" \
  || fail "super-build-dispatch.sh does not accept config context"
grep -q '\.git_platform // "github"' "$DISPATCH" \
  || fail "super-build-dispatch.sh does not resolve git_platform from config"
if grep -vE '^\s*#' "$DISPATCH" | grep -qE 'gh[[:space:]]+issue[[:space:]]+view'; then
  fail "super-build-dispatch.sh still has inline 'gh issue view'"
fi

# ── 6. Smoke: wave-plan with --items still plans (no live fetch) ───────────
SMOKE_DIR=$(mktemp -d)
trap 'rm -rf "$SMOKE_DIR"' EXIT

cat > "$SMOKE_DIR/config.json" <<'EOF'
{
  "variant": "full",
  "max_workers": 3,
  "human_approves_merge": true,
  "git_platform": "github",
  "project": {"owner": "octocat", "number": 1}
}
EOF

cat > "$SMOKE_DIR/items.json" <<'EOF'
{
  "items": [
    {
      "id": "ITEM_1",
      "status": "Ready",
      "content": {
        "type": "Issue",
        "number": 1,
        "title": "First",
        "body": "No deps",
        "repository": "octocat/demo",
        "assignees": []
      }
    }
  ]
}
EOF

# Copy platforms next to a copy of wave-plan so BASH_SOURCE-relative source works
# the same way install.sh lays out .claude/bin/{script,platforms/}.
mkdir -p "$SMOKE_DIR/platforms"
cp "$ROOT/scripts/platforms/github.sh" "$SMOKE_DIR/platforms/github.sh"
cp "$WAVE" "$SMOKE_DIR/super-board-wave-plan.sh"
chmod +x "$SMOKE_DIR/super-board-wave-plan.sh"

PLAN_OUT=$(
  bash "$SMOKE_DIR/super-board-wave-plan.sh" \
    --config "$SMOKE_DIR/config.json" \
    --items "$SMOKE_DIR/items.json"
)

echo "$PLAN_OUT" | jq -e '.cards | length == 1 and .[0].number == 1' >/dev/null \
  || fail "wave-plan --items smoke failed: $PLAN_OUT"

# ── 7. Live board-fetch failures must stay failures ────────────────────────
# A failed platform call must not be turned into an empty plan: that masks
# auth/network outages as a drained board.
mkdir -p "$SMOKE_DIR/bin"
printf '#!/usr/bin/env bash\nexit 42\n' > "$SMOKE_DIR/bin/gh"
chmod +x "$SMOKE_DIR/bin/gh"
set +e
FETCH_OUT=$(PATH="$SMOKE_DIR/bin:$PATH" bash "$SMOKE_DIR/super-board-wave-plan.sh" \
  --config "$SMOKE_DIR/config.json" 2>&1)
FETCH_RC=$?
set -e
if [ "$FETCH_RC" -eq 0 ]; then
  fail "live board-fetch failure was converted into success: $FETCH_OUT"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "error: issue #4 platform-rewire contract check failed" >&2
  exit 1
fi

echo "  ✓ platform source + call sites + wave-plan --items smoke"
echo "PASS: test-tasks-wave-dispatch-platform-rewire.sh"
