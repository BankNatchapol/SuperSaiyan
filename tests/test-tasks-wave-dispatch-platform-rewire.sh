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

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

for f in "$TASKS" "$WAVE" "$DISPATCH"; do
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
# AC names platform_label_ensure (GitLab status::ready) — on GitHub the skeleton
# maps that gate to platform_board_ensure (see github.sh comment). Accept either
# name so the contract stays honest about both the AC text and the GitHub adapter.
if ! grep -qE 'platform_(board_ensure|label_ensure)' "$TASKS"; then
  fail "tasks-to-issues.sh missing platform_board_ensure / platform_label_ensure"
fi
grep -q 'platform_card_status_set' "$TASKS" \
  || fail "tasks-to-issues.sh missing platform_card_status_set"

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

if [ "$FAIL" -ne 0 ]; then
  echo "error: issue #4 platform-rewire contract check failed" >&2
  exit 1
fi

echo "  ✓ platform source + call sites + wave-plan --items smoke"
echo "PASS: test-tasks-wave-dispatch-platform-rewire.sh"
