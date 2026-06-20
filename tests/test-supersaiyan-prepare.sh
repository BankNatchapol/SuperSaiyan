#!/usr/bin/env bash
# Fixture tests for the bundled supersaiyan prepare helper.
# No live GitHub writes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREPARE="$ROOT/.claude/skills/supersaiyan/scripts/prepare.sh"
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
  cat > "$app/.claude/bin/tasks-to-issues.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
feature="$1"
dir="docs/superpowers/tasks/$feature"
map="$dir/.issue-map.json"
state="${FAKE_GH_STATE:?}"
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
  chmod +x "$app/.claude/bin/tasks-to-issues.sh"
}

install_fake_gh() {
  local bin="$1"
  cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${FAKE_GH_STATE:?}"
cmd="${1:-}"; sub="${2:-}"

if [ "$cmd $sub" = "auth status" ]; then exit 0; fi
if [ "$cmd $sub" = "repo view" ]; then echo "owner/repo"; exit 0; fi

if [ "$cmd $sub" = "issue view" ]; then
  number="$3"
  file="$state/issues/$number"
  [ -f "$file" ] || { echo "issue not found" >&2; exit 1; }
  issue_state=$(sed -n '1p' "$file")
  url=$(sed -n '2p' "$file")
  body=$(sed -n '3,$p' "$file")
  args="$*"
  case "$args" in
    *"--jq .state"*) echo "$issue_state" ;;
    *"--jq .body"*) echo "$body" ;;
    *"--json state,url"*) jq -n --arg state "$issue_state" --arg url "$url" \
      '{state:$state,url:$url}' ;;
    *) jq -n --argjson number "$number" --arg state "$issue_state" --arg url "$url" \
      '{number:$number,state:$state,url:$url}' ;;
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
  jq -n --slurpfile items "$state/items.json" '{items:$items[0]}'
  exit 0
fi
if [ "$cmd $sub" = "project item-add" ]; then
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
  echo "ITEM_ADD $number" >> "$state/log"
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
    "$APP/.claude/bin" "$APP/.claude/super-board/configs" \
    "$STATE/issues" "$BIN"
  echo 100 > "$STATE/next"
  : > "$STATE/log"
  echo '[]' > "$STATE/items.json"
  echo '# Demo design' > "$APP/docs/superpowers/specs/demo-design.md"
  write_task "$APP/docs/superpowers/tasks/demo/01-first.md" "First task" 1 null
  write_task "$APP/docs/superpowers/tasks/demo/02-second.md" "Second task" 2 01-first
  cat > "$APP/.claude/super-board/configs/demo-board.json" <<'EOF'
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
cp "$APP/.claude/super-board/configs/demo-board.json" \
  "$APP/.claude/super-board/configs/other.json"
run_expect 75 run_prepare --check-only
echo demo-board > "$APP/.claude/super-board/active"
run_prepare --check-only >/dev/null || fail "active config was not selected"

# 3. Missing config requests inline onboarding.
new_fixture missing-config
rm "$APP/.claude/super-board/configs/demo-board.json"
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
out=$(run_prepare)
echo "$out" | grep -q 'created=0' || fail "repeat run created issues"
[ "$(grep -c '^CREATE ' "$STATE/log")" -eq 2 ] || fail "repeat was not idempotent"
[ "$(grep -c '^ITEM_ADD ' "$STATE/log")" -eq 2 ] || fail "repeat re-added cards"

# 7. Confirmed-deleted mappings are repaired.
new_fixture stale
cat > "$APP/docs/superpowers/tasks/demo/.issue-map.json" <<'EOF'
{"01-first":{"number":50,"url":"https://github.com/owner/repo/issues/50","order":1}}
EOF
out=$(run_prepare)
echo "$out" | grep -q 'repaired=1' || fail "stale mapping was not repaired"
[ "$(jq -r '."01-first".number' "$APP/docs/superpowers/tasks/demo/.issue-map.json")" != 50 ] ||
  fail "stale issue number remains mapped"

# 8. Backlog generated cards move to Ready; active/final/manual cards are preserved.
new_fixture statuses
write_task "$APP/docs/superpowers/tasks/demo/03-closed.md" "Closed task" 3 02-second
git -C "$APP" add docs/superpowers/tasks/demo/03-closed.md
git -C "$APP" commit -m closed-task >/dev/null
git -C "$APP" push >/dev/null
cat > "$APP/docs/superpowers/tasks/demo/.issue-map.json" <<'EOF'
{
  "01-first":{"number":10,"url":"https://github.com/owner/repo/issues/10","order":1},
  "02-second":{"number":11,"url":"https://github.com/owner/repo/issues/11","order":2},
  "03-closed":{"number":12,"url":"https://github.com/owner/repo/issues/12","order":3}
}
EOF
printf 'OPEN\nhttps://github.com/owner/repo/issues/10\nBody\n' > "$STATE/issues/10"
printf 'OPEN\nhttps://github.com/owner/repo/issues/11\n- Depends on: #10\n' > "$STATE/issues/11"
printf 'CLOSED\nhttps://github.com/owner/repo/issues/12\n- Depends on: #11\n' > "$STATE/issues/12"
cat > "$STATE/items.json" <<'EOF'
[
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
[ "$(jq -r '.[] | select(.id=="ITEM_99") | .status' "$STATE/items.json")" = Backlog ] ||
  fail "manual card was changed"

# 9. Publishable skill keeps onboarding and GSD fallback in the orchestration layer.
grep -q 'exits `78`' "$ROOT/.claude/skills/supersaiyan/SKILL.md" ||
  fail "skill does not route missing config to inline onboarding"
grep -q 'gsd-discuss-phase.*optional' \
  "$ROOT/.claude/skills/supersaiyan/references/prepare.md" ||
  fail "skill does not document the GSD fallback"

echo "PASS: test-supersaiyan-prepare.sh (9 scenarios)"
