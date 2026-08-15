#!/usr/bin/env bash
# test-gitlab-issue-mr-crud.sh — issue #9 / gitlab-integration task 09.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLAB_SH="$ROOT/scripts/platforms/gitlab.sh"
SANDBOX="${GITLAB_SANDBOX:-BankNatchapol/supersaiyan-gitlab-sandbox}"

FAIL=0
tfail() { echo "  FAIL: $1" >&2; FAIL=1; }

echo "checking gitlab.sh Groups F–G (issue + MR CRUD)"
[ -f "$GITLAB_SH" ] || { echo "error: $GITLAB_SH not found" >&2; exit 1; }
bash -n "$GITLAB_SH" || tfail "bash -n reported a syntax error"
# shellcheck disable=SC1090
. "$GITLAB_SH"

if grep -vE '^\s*#' "$GITLAB_SH" | grep -qE -- '--wip\b'; then
  tfail "gitlab.sh still uses removed --wip (must use --draft)"
fi
grep -q -- '--draft' "$GITLAB_SH" || tfail "platform_mr_create_draft does not use --draft"

# ── stubbed glab ───────────────────────────────────────────────────────────
TD=$(mktemp -d)
GLAB_LOG="$TD/glab.log"
mkdir -p "$TD/bin"
cat > "$TD/bin/glab" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GLAB_LOG:?}"
# Drop -R/--repo/--hostname before the verb (issue|mr|api).
while [ $# -gt 0 ]; do
  case "$1" in
    -R|--repo|--hostname) shift 2 ;;
    *) break ;;
  esac
done
cmd="${1:-}"; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --hostname|--repo|-R|--source-branch|--target-branch|--title|--description-file|--description|--base|--head|--body-file|--body|--note|-m|--assignee|--label|--unlabel|--add-label|--remove-label) shift 2 ;;
    --draft|--ready|--squash|--remove-source-branch|--yes|-y|--no-editor) shift ;;
    -*) shift ;;
    *) break ;;
  esac
done
case "$cmd" in
  issue)
    sub="${1:-}"
    case "$sub" in
      create) echo "Created issue https://gitlab.com/group/demo/-/issues/42" ;;
      note|close|update) echo "ok" ;;
      *) echo "ok" ;;
    esac
    ;;
  mr)
    sub="${1:-}"
    case "$sub" in
      create) echo "Created merge request https://gitlab.com/group/demo/-/merge_requests/3" ;;
      *) echo "ok" ;;
    esac
    ;;
  api)
    path=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --hostname|--method|-X|--output) shift 2 ;;
        -f|-F|--include|--paginate|-i) shift ;;
        -*) shift ;;
        *) path="$1"; shift ;;
      esac
    done
    case "$path" in
      */issues/404) echo '{"message":"404 Not Found"}' >&2; exit 1 ;;
      */issues/*)
        echo '{"iid":42,"title":"T","description":"B","labels":["bug"],"state":"opened"}'
        ;;
      */merge_requests*)
        echo '[{"iid":3,"source_branch":"feat","title":"T","draft":true}]'
        ;;
      *) echo '{}' ;;
    esac
    ;;
  *) echo "ok" ;;
esac
EOF
chmod +x "$TD/bin/glab"
CFG="$TD/cfg.json"
cat > "$CFG" <<'EOF'
{"git_platform":"gitlab","project":{"host":"gitlab.com","full_path":"group/demo"}}
EOF
export PLATFORM_CONFIG_PATH="$CFG" PATH="$TD/bin:$PATH" GLAB_LOG

body="$TD/body.md"
echo "hello" > "$body"
url=$(platform_issue_create "Title" "$body") || tfail "issue_create failed"
[ "$url" = "https://gitlab.com/group/demo/-/issues/42" ] || tfail "issue_create url=$url"

view=$(platform_issue_view 42) || tfail "issue_view failed"
echo "$view" | jq -e '.number==42 and .state=="OPEN" and .body=="B" and (.labels|index("bug"))' >/dev/null \
  || tfail "issue_view shape: $view"

rc=0
platform_issue_view 404 >/dev/null 2>&1 || rc=$?
[ "$rc" = 44 ] || tfail "missing issue exit $rc (want 44)"

platform_issue_comment 42 "hi" >/dev/null || tfail "issue_comment failed"
platform_issue_close 42 "done" >/dev/null || tfail "issue_close failed"
platform_issue_edit_labels 42 --add-label loop:in-progress --remove-label bug >/dev/null \
  || tfail "issue_edit_labels failed"
grep -q -- '--label' "$GLAB_LOG" || tfail "edit_labels did not translate --add-label to --label"
grep -q -- '--unlabel' "$GLAB_LOG" || tfail "edit_labels did not translate --remove-label to --unlabel"

: > "$GLAB_LOG"
mr_url=$(platform_mr_create_draft --base main --head feat --title "T" --body-file "$body") \
  || tfail "mr_create_draft failed"
[ "$mr_url" = "https://gitlab.com/group/demo/-/merge_requests/3" ] \
  || tfail "mr_create_draft url=$mr_url"
grep -q -- '--draft' "$GLAB_LOG" || tfail "mr_create_draft did not pass --draft"
grep -q -- '--wip' "$GLAB_LOG" && tfail "mr_create_draft passed --wip"
grep -q -- '--source-branch' "$GLAB_LOG" || tfail "mr_create_draft did not map --head to --source-branch"
grep -q -- '--target-branch' "$GLAB_LOG" || tfail "mr_create_draft did not map --base to --target-branch"

platform_mr_mark_ready 3 >/dev/null || tfail "mr_mark_ready failed"
platform_mr_comment 3 "note" >/dev/null || tfail "mr_comment failed"
platform_mr_view 3 >/dev/null || tfail "mr_view failed"
platform_mr_list_by_branch feat >/dev/null || tfail "mr_list_by_branch failed"
platform_mr_merge_squash 3 >/dev/null || tfail "mr_merge_squash failed"
grep -q -- '--squash' "$GLAB_LOG" || tfail "mr_merge_squash missing --squash"
grep -q -- '--remove-source-branch' "$GLAB_LOG" || tfail "mr_merge_squash missing --remove-source-branch"

# ── live ───────────────────────────────────────────────────────────────────
unset PLATFORM_CONFIG_PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
if [ "${GITLAB_LIVE:-}" = "1" ] && command -v glab >/dev/null 2>&1 && glab auth status >/dev/null 2>&1; then
  LIVE="$TD/live.json"
  cat > "$LIVE" <<EOF
{"git_platform":"gitlab","project":{"host":"gitlab.com","full_path":"$SANDBOX"}}
EOF
  export PLATFORM_CONFIG_PATH="$LIVE"
  echo "live issue body" > "$body"
  live_url=$(platform_issue_create "crud-#9 $(date +%H%M%S)" "$body") || tfail "live issue_create failed"
  live_iid="${live_url##*/}"
  live_view=$(platform_issue_view "$live_iid") || tfail "live issue_view failed"
  echo "$live_view" | jq -e '.state=="OPEN" and (.number|type=="number")' >/dev/null \
    || tfail "live view $live_view"
  platform_issue_comment "$live_iid" "note from #9" >/dev/null || tfail "live comment failed"
  platform_issue_edit_labels "$live_iid" --add-label "status::ready" >/dev/null \
    || tfail "live edit_labels failed"
  # MR: branch + commit in a temp clone
  CLONE="$TD/clone"
  git clone -q "https://gitlab.com/${SANDBOX}.git" "$CLONE"
  git -C "$CLONE" checkout -q -b "issue-9-crud-$$"
  echo "crud $$" >> "$CLONE/README.md"
  git -C "$CLONE" add README.md
  git -C "$CLONE" -c user.email=test@example.com -c user.name=test \
    commit -q -m "issue-9 crud"
  git -C "$CLONE" push -q -u origin "issue-9-crud-$$"
  src9="issue-9-crud-$$"
  mr_url=$(platform_mr_create_draft --base main --head "$src9" --title "draft #9" --body-file "$body") \
    || tfail "live mr_create_draft failed"
  mr_iid="${mr_url##*/}"
  [ -n "$mr_iid" ] || tfail "could not parse MR iid from $mr_url"
  draft_json=$(glab api "projects/$(printf '%s' "$SANDBOX" | sed 's|/|%2F|g')/merge_requests/${mr_iid}")
  echo "$draft_json" | jq -e '.draft==true or .work_in_progress==true' >/dev/null \
    || tfail "created MR is not draft: $draft_json"
  platform_mr_mark_ready "$mr_iid" >/dev/null || tfail "live mark_ready failed"
  platform_mr_comment "$mr_iid" "mr note #9" >/dev/null || tfail "live mr_comment failed"
  platform_mr_view "$mr_iid" >/dev/null || tfail "live mr_view failed"
  listed=$(platform_mr_list_by_branch "$src9") || tfail "live list_by_branch failed"
  echo "$listed" | jq -e --argjson n "$mr_iid" 'if type=="array" then any(.[]; .iid==$n or .iid==($n|tonumber)) else .iid==($n|tonumber) end' >/dev/null \
    || tfail "list_by_branch missed MR $mr_iid: $listed"
  platform_mr_merge_squash "$mr_iid" >/dev/null || tfail "live merge_squash failed"
  # Second draft MR left open for #10
  git -C "$CLONE" checkout -q -b "issue-10-threads-$$"
  echo "threads $$" >> "$CLONE/README.md"
  git -C "$CLONE" add README.md
  git -C "$CLONE" -c user.email=test@example.com -c user.name=test \
    commit -q -m "issue-10 threads seed"
  git -C "$CLONE" push -q -u origin "issue-10-threads-$$"
  keep_url=$(platform_mr_create_draft --base main --head "issue-10-threads-$$" --title "draft #10 threads" --body-file "$body") \
    || tfail "could not leave draft MR for #10"
  keep_iid="${keep_url##*/}"
  printf '%s\n' "$keep_iid" > "$TD/draft-mr-iid.txt"
  printf '%s\n' "$keep_url" > "$TD/draft-mr-url.txt"
  platform_issue_close "$live_iid" "closing #9 live issue" >/dev/null || tfail "live close failed"
  unset PLATFORM_CONFIG_PATH
else
  echo "  skip live sandbox checks (set GITLAB_LIVE=1 with glab auth to run)"
fi

rm -rf "$TD"
if [ "$FAIL" -ne 0 ]; then
  echo "error: gitlab issue/MR CRUD check failed" >&2
  exit 1
fi
echo "  ✓ gitlab.sh Groups F–G: issue CRUD, draft MR, squash-merge"
echo "PASS: test-gitlab-issue-mr-crud.sh"
