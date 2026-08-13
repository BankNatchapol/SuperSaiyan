#!/usr/bin/env bash
# Fixture tests for the bundled supersaiyan prepare helper.
# No live GitHub writes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREPARE="$ROOT/skills/supersaiyan/scripts/prepare.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_expect() {
  local expected="$1"
  shift
  local rc=0
  "$@" > "$TMP/out" 2> "$TMP/err" || rc=$?
  [ "$rc" -eq "$expected" ] ||
    fail "expected exit $expected, got $rc: $(cat "$TMP/err")"
}

write_task() {
  local path="$1" title="$2" order="$3" dep="$4"
  cat > "$path" <<EOF
---
title: $title
order: $order
depends_on_task: $dep
feature: demo
design: docs/superpowers/specs/demo-design.md
plan:
plan_task: Requirements
skills: superpowers:verification-before-completion
---

## Goal

The task exists.

## Acceptance Criteria

- [ ] The observable result exists.
- [ ] The test command passes.
EOF
}

install_fake_helper() {
  local app="$1"
  cat > "$app/.supersaiyan/bin/tasks-to-issues.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
feature="$1"
dir="docs/superpowers/tasks/$feature"
map="$dir/.issue-map.json"
state="${FAKE_GH_STATE:?}"
echo "HELPER_ARGS $*" >> "$state/log"
[ -f "$map" ] || printf '{}\n' > "$map"
for file in "$dir"/*.md; do
  stem=$(basename "$file" .md)
  if [ -z "$(jq -r --arg stem "$stem" '.[$stem].number // empty' "$map")" ]; then
    number=$(cat "$state/next")
    echo $((number + 1)) > "$state/next"
    url="https://github.com/owner/repo/issues/$number"
    tmp=$(mktemp)
    jq --arg stem "$stem" --argjson number "$number" --arg url "$url" \
      '. + {($stem): {number: $number, url: $url, order: $number}}' "$map" > "$tmp"
    mv "$tmp" "$map"
    printf 'OPEN\n%s\nGenerated body\n' "$url" > "$state/issues/$number"
    echo "CREATE $number $stem" >> "$state/log"
  fi
done
EOF
  chmod +x "$app/.supersaiyan/bin/tasks-to-issues.sh"
}

install_real_helper() {
  local app="$1"
  mkdir -p "$app/.claude/bin/platforms"
  cp "$ROOT/scripts/tasks-to-issues.sh" "$app/.claude/bin/tasks-to-issues.sh"
  cp "$ROOT/scripts/platform-config.sh" "$app/.claude/bin/platform-config.sh"
  cp "$ROOT/scripts/config-resolve.sh" "$app/.claude/bin/config-resolve.sh"
  cp "$ROOT/scripts/platforms/github.sh" "$app/.claude/bin/platforms/github.sh"
  chmod +x "$app/.claude/bin/tasks-to-issues.sh"
}

install_fake_gh() {
  local bin="$1"
  cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${FAKE_GH_STATE:?}"
cmd="${1:-}"; sub="${2:-}"

if [ "$cmd $sub" = "auth status" ]; then
  case "$*" in
    *"--json hosts"*)
      echo '{"hosts":{"github.com":[{"active":true,"host":"github.com","login":"octocat","scopes":"gist, project, read:org, repo"}]}}'
      ;;
  esac
  exit 0
fi
if [ "$cmd $sub" = "repo view" ]; then echo "https://github.com/owner/repo"; exit 0; fi

if [ "$cmd $sub" = "issue view" ]; then
  number="$3"
  file="$state/issues/$number"
  [ -f "$file" ] || { echo "HTTP 404: Not Found" >&2; exit 1; }
  issue_state=$(sed -n '1p' "$file")
  case "$issue_state" in
    ERROR_401) echo "HTTP 401: Bad credentials" >&2; exit 1 ;;
    ERROR_403) echo "HTTP 403: Resource not accessible" >&2; exit 1 ;;
    ERROR_NETWORK) echo "failed to connect to github.com" >&2; exit 1 ;;
    ERROR_MALFORMED) echo '{not-json'; exit 0 ;;
  esac
  url=$(sed -n '2p' "$file")
  body=$(sed -n '3,$p' "$file")
  args="$*"
  case "$args" in
    *"--jq .state"*) echo "$issue_state" ;;
    *"--jq .body"*) echo "$body" ;;
    *"--json state,url"*) jq -n --arg state "$issue_state" --arg url "$url" \
      '{state:$state,url:$url}' ;;
    *) jq -n --argjson number "$number" --arg state "$issue_state" --arg body "$body" \
      '{number:$number,title:("Issue " + ($number | tostring)),body:$body,labels:[],state:$state}' ;;
  esac
  exit 0
fi

if [ "$cmd $sub" = "issue edit" ]; then
  echo "ISSUE_EDIT $3" >> "$state/log"
  exit 0
fi

if [ "$cmd $sub" = "project view" ]; then echo "PROJECT_ID"; exit 0; fi
if [ "$cmd $sub" = "project field-list" ]; then
  echo '{"fields":[{"id":"STATUS_ID","name":"Status","options":[{"id":"READY_ID","name":"Ready"}]}]}'
  exit 0
fi
if [ "$cmd $sub" = "project item-list" ]; then
  echo "ITEM_LIST $*" >> "$state/log"
  jq -n --slurpfile items "$state/items.json" '{items:$items[0]}'
  exit 0
fi
if [ "$cmd $sub" = "project item-add" ]; then
  echo "ITEM_ADD $*" >> "$state/log"
  url=""
  while [ $# -gt 0 ]; do
    [ "$1" = "--url" ] && { url="$2"; break; }
    shift
  done
  number=${url##*/}
  id="ITEM_$number"
  tmp=$(mktemp)
  jq --arg id "$id" --argjson number "$number" --arg url "$url" \
    '. + [{id:$id,status:"",content:{type:"Issue",repository:"owner/repo",number:$number,url:$url}}]' \
    "$state/items.json" > "$tmp"
  mv "$tmp" "$state/items.json"
  echo "$id"
  exit 0
fi
if [ "$cmd $sub" = "project item-edit" ]; then
  id=""
  while [ $# -gt 0 ]; do
    [ "$1" = "--id" ] && id="$2"
    shift
  done
  tmp=$(mktemp)
  jq --arg id "$id" 'map(if .id == $id then .status = "Ready" else . end)' \
    "$state/items.json" > "$tmp"
  mv "$tmp" "$state/items.json"
  echo "ITEM_EDIT $id" >> "$state/log"
  exit 0
fi

echo "unsupported fake gh call: $*" >&2
exit 2
EOF
  chmod +x "$bin/gh"
}

new_fixture() {
  local name="$1"
  APP="$TMP/$name"
  ORIGIN="$TMP/$name-origin.git"
  STATE="$TMP/$name-state"
  BIN="$TMP/$name-bin"
  mkdir -p "$APP/docs/superpowers/tasks/demo" "$APP/docs/superpowers/specs" \
    "$APP/.supersaiyan/bin" "$APP/.supersaiyan/configs" \
    "$STATE/issues" "$BIN"
  echo 100 > "$STATE/next"
  : > "$STATE/log"
  echo '[]' > "$STATE/items.json"
  echo '# Demo design' > "$APP/docs/superpowers/specs/demo-design.md"
  write_task "$APP/docs/superpowers/tasks/demo/01-first.md" "First task" 1 null
  write_task "$APP/docs/superpowers/tasks/demo/02-second.md" "Second task" 2 01-first
  cat > "$APP/.supersaiyan/configs/demo-board.json" <<'EOF'
{
  "project": {"owner": "owner", "number": 7},
  "base_branch": "main"
}
EOF
  install_fake_helper "$APP"
  install_fake_gh "$BIN"
  git -C "$APP" init -b main >/dev/null
  git -C "$APP" config user.email test@example.com
  git -C "$APP" config user.name Test
  git -C "$APP" add .
  git -C "$APP" commit -m fixture >/dev/null
  git init --bare "$ORIGIN" >/dev/null
  git -C "$APP" remote add origin "$ORIGIN"
  git -C "$APP" push -u origin main >/dev/null
}

run_prepare() {
  (
    cd "$APP"
    PATH="$BIN:$PATH" FAKE_GH_STATE="$STATE" "$PREPARE" demo "$@"
  )
}

# 1. One config is selected automatically.
new_fixture single
run_prepare --check-only | grep -q 'CHECK_OK.*config=demo-board' ||
  fail "single config check failed"

# 2. Multiple configs require an active pointer.
cp "$APP/.supersaiyan/configs/demo-board.json" \
  "$APP/.supersaiyan/configs/other.json"
run_expect 75 run_prepare --check-only
echo demo-board > "$APP/.supersaiyan/active"
run_prepare --check-only >/dev/null || fail "active config was not selected"

# 3. Missing config requests inline onboarding.
new_fixture missing-config
rm "$APP/.supersaiyan/configs/demo-board.json"
run_expect 78 run_prepare --check-only
grep -q NEEDS_ONBOARD "$TMP/out" || fail "missing config did not signal onboarding"

# 4. Uncommitted and unpushed task files stop before GitHub mutation.
new_fixture git-safety
echo "dirty" >> "$APP/docs/superpowers/tasks/demo/01-first.md"
run_expect 65 run_prepare --check-only
git -C "$APP" add .
git -C "$APP" commit -m unpushed >/dev/null
run_expect 65 run_prepare --check-only

# 5. Missing and cyclic dependencies fail validation.
new_fixture dependencies
sed -i.bak 's/depends_on_task: 01-first/depends_on_task: missing/' \
  "$APP/docs/superpowers/tasks/demo/02-second.md"
rm "$APP/docs/superpowers/tasks/demo/02-second.md.bak"
run_expect 65 run_prepare --check-only
sed -i.bak 's/depends_on_task: null/depends_on_task: 02-second/' \
  "$APP/docs/superpowers/tasks/demo/01-first.md"
sed -i.bak 's/depends_on_task: missing/depends_on_task: 01-first/' \
  "$APP/docs/superpowers/tasks/demo/02-second.md"
rm "$APP/docs/superpowers/tasks/demo/"*.bak
run_expect 65 run_prepare --check-only

# 6. Fresh preparation creates issues and Ready cards; repeat is idempotent.
new_fixture fresh
out=$(run_prepare)
echo "$out" | grep -q 'created=2' || fail "fresh run did not create two issues"
[ "$(grep -c '^CREATE ' "$STATE/log")" -eq 2 ] || fail "wrong create count"
[ "$(grep -c '^ITEM_ADD ' "$STATE/log")" -eq 2 ] || fail "wrong item-add count"
grep -q '^HELPER_ARGS demo --board --config ' "$STATE/log" ||
  fail "prepare did not request explicit board enqueue from tasks-to-issues"
out=$(run_prepare)
echo "$out" | grep -q 'created=0' || fail "repeat run created issues"
[ "$(grep -c '^CREATE ' "$STATE/log")" -eq 2 ] || fail "repeat was not idempotent"
[ "$(grep -c '^ITEM_ADD ' "$STATE/log")" -eq 2 ] || fail "repeat re-added cards"

# 7. Only confirmed-deleted mappings are repaired; other lookup failures
# abort and preserve the map.
new_fixture stale
cat > "$APP/docs/superpowers/tasks/demo/.issue-map.json" <<'EOF'
{"01-first":{"number":50,"url":"https://github.com/owner/repo/issues/50","order":1}}
EOF
out=$(run_prepare)
echo "$out" | grep -q 'repaired=1' || fail "stale mapping was not repaired"
[ "$(jq -r '."01-first".number' "$APP/docs/superpowers/tasks/demo/.issue-map.json")" != 50 ] ||
  fail "stale issue number remains mapped"

for lookup_failure in ERROR_401 ERROR_403 ERROR_NETWORK ERROR_MALFORMED; do
  new_fixture "lookup-$lookup_failure"
  cat > "$APP/docs/superpowers/tasks/demo/.issue-map.json" <<'EOF'
{"01-first":{"number":50,"url":"https://github.com/owner/repo/issues/50","order":1}}
EOF
  printf '%s\nhttps://github.com/owner/repo/issues/50\nBody\n' "$lookup_failure" \
    > "$STATE/issues/50"
  case "$lookup_failure" in
    ERROR_401|ERROR_403) expected_lookup_rc=69 ;;
    *) expected_lookup_rc=70 ;;
  esac
  run_expect "$expected_lookup_rc" run_prepare
  [ "$(jq -r '."01-first".number' "$APP/docs/superpowers/tasks/demo/.issue-map.json")" = 50 ] ||
    fail "$lookup_failure removed a mapped issue without a confirmed 404"
done

# 8. The real filing helper moves only OPEN mapped issues in this repository.
# CLOSED mapped issues remain untouched whether they are in Backlog or absent,
# and an issue with the same number from another repository cannot mask the
# target card's status in a shared Project.
new_fixture statuses
write_task "$APP/docs/superpowers/tasks/demo/03-closed.md" "Closed task" 3 02-second
write_task "$APP/docs/superpowers/tasks/demo/04-closed-absent.md" "Closed absent task" 4 03-closed
install_real_helper "$APP"
git -C "$APP" add docs/superpowers/tasks/demo/03-closed.md \
  docs/superpowers/tasks/demo/04-closed-absent.md .claude/bin
git -C "$APP" commit -m closed-task >/dev/null
git -C "$APP" push >/dev/null
cat > "$APP/docs/superpowers/tasks/demo/.issue-map.json" <<'EOF'
{
  "01-first":{"number":10,"url":"https://github.com/owner/repo/issues/10","order":1},
  "02-second":{"number":11,"url":"https://github.com/owner/repo/issues/11","order":2},
  "03-closed":{"number":12,"url":"https://github.com/owner/repo/issues/12","order":3},
  "04-closed-absent":{"number":13,"url":"https://github.com/owner/repo/issues/13","order":4}
}
EOF
printf 'OPEN\nhttps://github.com/owner/repo/issues/10\nBody\n' > "$STATE/issues/10"
printf 'OPEN\nhttps://github.com/owner/repo/issues/11\n- Depends on: #10\n' > "$STATE/issues/11"
printf 'CLOSED\nhttps://github.com/owner/repo/issues/12\n- Depends on: #11\n' > "$STATE/issues/12"
printf 'CLOSED\nhttps://github.com/owner/repo/issues/13\n- Depends on: #12\n' > "$STATE/issues/13"
cat > "$STATE/items.json" <<'EOF'
[
  {"id":"OTHER_ITEM_10","status":"Ready","content":{"type":"Issue","repository":"other/repo","number":10,"url":"https://github.com/other/repo/issues/10"}},
  {"id":"ITEM_10","status":"Backlog","content":{"type":"Issue","repository":"owner/repo","number":10,"url":"https://github.com/owner/repo/issues/10"}},
  {"id":"ITEM_11","status":"Building","content":{"type":"Issue","repository":"owner/repo","number":11,"url":"https://github.com/owner/repo/issues/11"}},
  {"id":"ITEM_12","status":"Backlog","content":{"type":"Issue","repository":"owner/repo","number":12,"url":"https://github.com/owner/repo/issues/12"}},
  {"id":"ITEM_99","status":"Backlog","content":{"type":"Issue","repository":"owner/repo","number":99,"url":"https://github.com/owner/repo/issues/99"}}
]
EOF
run_prepare >/dev/null
[ "$(jq -r '.[] | select(.id=="ITEM_10") | .status' "$STATE/items.json")" = Ready ] ||
  fail "generated Backlog card did not move to Ready"
[ "$(jq -r '.[] | select(.id=="ITEM_11") | .status' "$STATE/items.json")" = Building ] ||
  fail "active generated card was changed"
[ "$(jq -r '.[] | select(.id=="ITEM_12") | .status' "$STATE/items.json")" = Backlog ] ||
  fail "closed generated card was changed"
[ "$(jq '[.[] | select(.content.url=="https://github.com/owner/repo/issues/13")] | length' "$STATE/items.json")" -eq 0 ] ||
  fail "closed mapped issue absent from the board was re-enqueued"
[ "$(jq -r '.[] | select(.id=="OTHER_ITEM_10") | .status' "$STATE/items.json")" = Ready ] ||
  fail "same-number card from another repository was changed"
[ "$(jq -r '.[] | select(.id=="ITEM_99") | .status' "$STATE/items.json")" = Backlog ] ||
  fail "manual card was changed"

# 9. Publishable skill keeps onboarding and GSD fallback in the orchestration layer.
grep -q 'exits `78`' "$ROOT/skills/supersaiyan/SKILL.md" ||
  fail "skill does not route missing config to inline onboarding"
grep -q 'gsd-discuss-phase.*optional' \
  "$ROOT/skills/supersaiyan/references/prepare.md" ||
  fail "skill does not document the GSD fallback"

# 10. An extends overlay inherits project.owner/number from the base for field
# reads; CHECK_OK still reports the overlay slug (identity stays the raw file).
new_fixture extends-inherit
cat > "$APP/.supersaiyan/configs/shared.json" <<'EOF'
{
  "project": {"owner": "inherited-owner", "number": 99},
  "base_branch": "main"
}
EOF
cat > "$APP/.supersaiyan/configs/overlay.json" <<'EOF'
{
  "extends": "shared",
  "worker_backend": "codex-exec"
}
EOF
rm -f "$APP/.supersaiyan/configs/demo-board.json"
echo overlay > "$APP/.supersaiyan/active"
git -C "$APP" add .supersaiyan
git -C "$APP" commit -m extends-overlay >/dev/null
git -C "$APP" push >/dev/null
run_prepare --check-only > "$TMP/out" 2> "$TMP/err" ||
  fail "extends overlay check-only exited $?: $(cat "$TMP/out" "$TMP/err")"
grep -q 'CHECK_OK config=overlay project=inherited-owner/99' "$TMP/out" ||
  fail "extends overlay did not inherit project from the base: $(cat "$TMP/out" "$TMP/err")"

# 11. A broken extends target fails loudly instead of falling back to @me/null.
new_fixture extends-broken
cat > "$APP/.supersaiyan/configs/overlay.json" <<'EOF'
{
  "extends": "does-not-exist",
  "worker_backend": "codex-exec"
}
EOF
rm -f "$APP/.supersaiyan/configs/demo-board.json"
echo overlay > "$APP/.supersaiyan/active"
git -C "$APP" add .supersaiyan
git -C "$APP" commit -m broken-extends >/dev/null
git -C "$APP" push >/dev/null
run_expect 66 run_prepare --check-only
grep -qiE 'does-not-exist|extends' "$TMP/err" ||
  fail "broken extends did not name the missing base: $(cat "$TMP/err")"
grep -q '@me' "$TMP/out" &&
  fail "broken extends silently fell back to @me: $(cat "$TMP/out")"

# 12. The filing path (board snapshot + Ready enqueue) uses the inherited
# project, not @me/empty. --check-only is not enough: github.sh jq's .project
# off the path it is given.
new_fixture extends-write
cat > "$APP/.supersaiyan/configs/shared.json" <<'EOF'
{
  "project": {"owner": "inherited-owner", "number": 99},
  "base_branch": "main"
}
EOF
cat > "$APP/.supersaiyan/configs/overlay.json" <<'EOF'
{
  "extends": "shared",
  "worker_backend": "codex-exec"
}
EOF
rm -f "$APP/.supersaiyan/configs/demo-board.json"
echo overlay > "$APP/.supersaiyan/active"
install_real_helper "$APP"
run_prepare > "$TMP/out" 2> "$TMP/err" ||
  fail "extends overlay prepare exited $?: $(cat "$TMP/out" "$TMP/err")"
grep -q 'ITEM_LIST project item-list 99 --owner inherited-owner' "$STATE/log" ||
  fail "board snapshot did not use inherited project: $(cat "$STATE/log")"
grep -q 'ITEM_ADD project item-add 99 --owner inherited-owner' "$STATE/log" ||
  fail "Ready enqueue did not use inherited project: $(cat "$STATE/log")"

echo "PASS: test-supersaiyan-prepare.sh (12 scenarios)"
