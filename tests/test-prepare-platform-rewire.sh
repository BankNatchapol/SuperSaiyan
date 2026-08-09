#!/usr/bin/env bash
# Verifies prepare/tasks-to-issues use the platform contract for auth, issue
# CRUD, board snapshots, and logical status writes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS="$ROOT/scripts/tasks-to-issues.sh"
PREPARE="$ROOT/skills/supersaiyan/scripts/prepare.sh"
FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

for f in "$TASKS" "$PREPARE"; do
  bash -n "$f" || fail "bash -n failed for $f"
done

grep -q 'platform_auth_check' "$TASKS" \
  || fail "tasks-to-issues.sh does not use platform_auth_check"
grep -q 'platform_issue_create' "$TASKS" \
  || fail "tasks-to-issues.sh does not use platform_issue_create"
grep -q 'platform_card_status_set' "$TASKS" \
  || fail "tasks-to-issues.sh does not use platform_card_status_set"
grep -q -- '--config' "$TASKS" \
  || fail "tasks-to-issues.sh has no --config input"

if grep -vE '^\s*#' "$TASKS" | grep -qE '\bgh\s+(auth|issue)\b'; then
  fail "tasks-to-issues.sh still has direct gh auth/issue calls"
fi

grep -q 'platform_issue_view' "$PREPARE" \
  || fail "prepare.sh does not use platform_issue_view"
grep -q 'platform_board_snapshot' "$PREPARE" \
  || fail "prepare.sh does not use platform_board_snapshot"
grep -q 'platform_card_status_set' "$PREPARE" \
  || fail "prepare.sh does not use platform_card_status_set"
grep -q -- '--config' "$PREPARE" \
  || fail "prepare.sh does not pass config context"

if grep -vE '^\s*#' "$PREPARE" | grep -qE '\bgh\s+(issue|project)\b'; then
  fail "prepare.sh still has direct gh issue/project calls"
fi

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: test-prepare-platform-rewire.sh"
