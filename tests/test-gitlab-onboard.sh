#!/usr/bin/env bash
# test-gitlab-onboard.sh — issue #13 Group K + fail-open board_id.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLAB_SH="$ROOT/scripts/platforms/gitlab.sh"
SANDBOX="${GITLAB_ONBOARD:-BankNatchapol/supersaiyan-gitlab-onboard}"
FAIL=0
tfail() { echo "  FAIL: $1" >&2; FAIL=1; }

echo "checking gitlab.sh Group K (onboard labels/board)"
bash -n "$GITLAB_SH" || tfail "syntax"
# shellcheck disable=SC1090
. "$GITLAB_SH"

grep -q 'glab label list' "$GITLAB_SH" || grep -q 'projects/.*/labels' "$GITLAB_SH" \
  || tfail "label_ensure does not list before create"
grep -q '_gitlab_board_ui_steps' "$GITLAB_SH" || tfail "missing UI fallback"
grep -q 'GITLAB_BOARD_ENSURE_FAIL' "$GITLAB_SH" || tfail "missing force-fail hook"

TD=$(mktemp -d)
CFG="$TD/cfg.json"
cat > "$CFG" <<EOF
{"git_platform":"gitlab","variant":"full","project":{"host":"gitlab.com","full_path":"$SANDBOX","board_id":null}}
EOF
export PLATFORM_CONFIG_PATH="$CFG"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

forced=$(GITLAB_BOARD_ENSURE_FAIL=1 platform_board_ensure "$CFG" 2>"$TD/ui.txt")
[ "$forced" = "null" ] || tfail "force-fail printed '$forced' not null"
grep -q 'Issue boards' "$TD/ui.txt" || tfail "force-fail did not print UI steps"

if command -v glab >/dev/null && glab auth status >/dev/null 2>&1; then
  # Create the empty onboard project if missing.
  if ! glab api "projects/$(printf '%s' "$SANDBOX" | sed 's|/|%2F|g')" >/dev/null 2>&1; then
    ( cd "${TMPDIR:-/tmp}" && glab repo create "$SANDBOX" --public --skipGitInit \
      --description "empty SuperSaiyan #13 onboard sandbox" ) \
      || tfail "could not create $SANDBOX"
  fi
  bid=$(platform_board_ensure "$CFG" 2>"$TD/ensure.err" || true)
  if [ -z "$bid" ] || [ "$bid" = "null" ]; then
    tfail "live board_ensure failed: $(cat "$TD/ensure.err")"
  else
    echo "  live board_id=$bid"
    written=$(jq -r '.project.board_id' "$CFG")
    [ "$written" = "$bid" ] || tfail "config board_id=$written expected $bid"
    lists=$(glab api "projects/$(printf '%s' "$SANDBOX" | sed 's|/|%2F|g')/boards/${bid}/lists")
    count=$(printf '%s' "$lists" | jq 'length')
    [ "$count" -ge 7 ] || tfail "expected ≥7 lists, got $count"
  fi
  forced2=$(GITLAB_BOARD_ENSURE_FAIL=1 platform_board_ensure "$CFG" 2>"$TD/ui2.txt")
  [ "$forced2" = "null" ] || tfail "second force-fail printed '$forced2'"
else
  echo "  skip live onboard project (glab not authenticated)"
fi

rm -rf "$TD"
[ "$FAIL" -eq 0 ] || { echo "error: gitlab onboard check failed" >&2; exit 1; }
echo "  ✓ Group K: label list-then-create, board ensure, fail-open null"
echo "PASS: test-gitlab-onboard.sh"
