#!/usr/bin/env bash
# test-tasks-wave-dispatch-platform-rewire.sh — verifies issue #4 / gitlab-integration
# task 04: tasks-to-issues.sh, super-board-wave-plan.sh, and super-build-dispatch.sh
# route their remaining direct gh board/issue calls through platform_*.
# Contract, syntax, and fake-adapter behavior only — no live board traffic.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS="$ROOT/scripts/tasks-to-issues.sh"
WAVE="$ROOT/scripts/super-board-wave-plan.sh"
DISPATCH="$ROOT/skills/super-build/scripts/super-build-dispatch.sh"
PREPARE="$ROOT/skills/supersaiyan/scripts/prepare.sh"
GITHUB_PLATFORM="$ROOT/scripts/platforms/github.sh"
CONFIG_RESOLVER="$ROOT/scripts/platform-config.sh"
CONFIG_RESOLVE_SH="$ROOT/scripts/config-resolve.sh"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

for f in "$TASKS" "$WAVE" "$DISPATCH" "$PREPARE" "$GITHUB_PLATFORM"; do
  if [ ! -f "$f" ]; then
    echo "error: $f not found" >&2
    exit 1
  fi
done

[ -f "$CONFIG_RESOLVER" ] || fail "shared platform config resolver is missing"

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
grep -q 'platform_board_ensure' "$GITHUB_PLATFORM" \
  || fail "GitHub adapter missing Project Status metadata validation"

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
grep -q 'platform_config_resolve_platform' "$DISPATCH" \
  || fail "super-build-dispatch.sh does not use the shared platform resolver"
if grep -vE '^\s*#' "$DISPATCH" | grep -qE 'gh[[:space:]]+issue[[:space:]]+view'; then
  fail "super-build-dispatch.sh still has inline 'gh issue view'"
fi
if grep -E 'platform_issue_view.*--json' "$DISPATCH" "$PREPARE" >/dev/null; then
  fail "platform_issue_view callers still leak GitHub CLI flags across the adapter boundary"
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
    },
    {
      "id": "ITEM_CLOSED",
      "status": "Ready",
      "state": "CLOSED",
      "content": {
        "type": "Issue",
        "number": 99,
        "title": "Closed leftover",
        "body": "must not be planned",
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
cp "$ROOT/scripts/config-resolve.sh" "$SMOKE_DIR/config-resolve.sh"
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

# ── 8. Real tasks-to-issues enqueue behavior ───────────────────────────────
# Static grep cannot prove the adapter receives the config and performs the
# project bootstrap/add/edit sequence. Run the real caller against a fake gh.
ENQUEUE_DIR=$(mktemp -d)
mkdir -p "$ENQUEUE_DIR/app/docs/superpowers/tasks/demo" \
  "$ENQUEUE_DIR/app/platforms" "$ENQUEUE_DIR/bin" "$ENQUEUE_DIR/state"
cp "$TASKS" "$ENQUEUE_DIR/app/tasks-to-issues.sh"
cp "$CONFIG_RESOLVER" "$ENQUEUE_DIR/app/platform-config.sh"
cp "$CONFIG_RESOLVE_SH" "$ENQUEUE_DIR/app/config-resolve.sh"
cp "$GITHUB_PLATFORM" "$ENQUEUE_DIR/app/platforms/github.sh"
cat > "$ENQUEUE_DIR/app/docs/superpowers/tasks/demo/01-first.md" <<'EOF'
---
title: First task
order: 1
depends_on_task: null
design: docs/superpowers/specs/demo.md
---

## Goal

Create one issue and enqueue it in Ready.

## Acceptance Criteria

- [ ] The issue is created and placed on the board.
EOF
cat > "$ENQUEUE_DIR/app/config.json" <<'EOF'
{"project":{"owner":"owner","number":7},"git_platform":"github"}
EOF
: > "$ENQUEUE_DIR/state/log"
cat > "$ENQUEUE_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="${FAKE_PLATFORM_STATE:?}"
cmd="${1:-}"; sub="${2:-}"
if [ "$cmd $sub" = "auth status" ]; then
  case "$*" in
    *"--json hosts"*)
      echo '{"hosts":{"github.com":[{"active":true,"host":"github.com","login":"octocat","scopes":"gist, project, read:org, repo"}]}}'
      ;;
  esac
  exit 0
fi
if [ "$cmd $sub" = "repo view" ]; then
  echo "https://github.com/owner/repo"
  exit 0
fi
if [ "$cmd $sub" = "label create" ]; then
  echo "LABEL_ENSURE $3" >> "$state/log"
  exit 0
fi
if [ "$cmd $sub" = "issue create" ]; then
  echo "ISSUE_CREATE" >> "$state/log"
  echo "https://github.com/owner/repo/issues/42"
  exit 0
fi
if [ "$cmd $sub" = "project view" ]; then
  echo "PROJECT_VIEW" >> "$state/log"
  echo "PROJECT_ID"
  exit 0
fi
if [ "$cmd $sub" = "project field-list" ]; then
  echo "FIELD_LIST" >> "$state/log"
  echo '{"fields":[{"id":"STATUS_ID","name":"Status","options":[{"id":"READY_ID","name":"Ready"}]}]}'
  exit 0
fi
if [ "$cmd $sub" = "project item-list" ]; then
  echo '{"items":[]}'
  exit 0
fi
if [ "$cmd $sub" = "project item-add" ]; then
  echo "ITEM_ADD" >> "$state/log"
  echo "ITEM_42"
  exit 0
fi
if [ "$cmd $sub" = "project item-edit" ]; then
  echo "ITEM_EDIT" >> "$state/log"
  exit 0
fi
echo "unsupported fake gh call: $*" >&2
exit 2
EOF
chmod +x "$ENQUEUE_DIR/bin/gh"
(
  cd "$ENQUEUE_DIR/app"
  PATH="$ENQUEUE_DIR/bin:$PATH" FAKE_PLATFORM_STATE="$ENQUEUE_DIR/state" \
    ./tasks-to-issues.sh demo --board --config "$ENQUEUE_DIR/app/config.json" >/dev/null
)
grep -q '^ISSUE_CREATE$' "$ENQUEUE_DIR/state/log" \
  || fail "real tasks-to-issues caller did not create an issue"
grep -q '^PROJECT_VIEW$' "$ENQUEUE_DIR/state/log" \
  || fail "real tasks-to-issues caller did not validate the Project"
grep -q '^FIELD_LIST$' "$ENQUEUE_DIR/state/log" \
  || fail "real tasks-to-issues caller did not validate the Ready option"
grep -q '^ITEM_ADD$' "$ENQUEUE_DIR/state/log" \
  || fail "real tasks-to-issues caller did not add a board item"
grep -q '^ITEM_EDIT$' "$ENQUEUE_DIR/state/log" \
  || fail "real tasks-to-issues caller did not set Ready"
rm -rf "$ENQUEUE_DIR"

# ── 8b. Failed Ready enqueue is recoverable on retry ─────────────────────
# Issue creation and map persistence happen before the remote board write. A
# retry with --board must reconcile the mapped issue instead of skipping it.
RETRY_DIR=$(mktemp -d)
mkdir -p "$RETRY_DIR/app/docs/superpowers/tasks/demo" \
  "$RETRY_DIR/app/platforms" "$RETRY_DIR/state"
cp "$TASKS" "$RETRY_DIR/app/tasks-to-issues.sh"
cp "$CONFIG_RESOLVER" "$RETRY_DIR/app/platform-config.sh"
cp "$CONFIG_RESOLVE_SH" "$RETRY_DIR/app/config-resolve.sh"
cat > "$RETRY_DIR/app/config.json" <<'EOF'
{"project":{"owner":"owner","number":7},"git_platform":"github"}
EOF
cat > "$RETRY_DIR/app/docs/superpowers/tasks/demo/01-first.md" <<'EOF'
---
title: Retry enqueue task
order: 1
depends_on_task: null
---

## Goal

Recover Ready enqueue without creating a duplicate issue.
EOF
cat > "$RETRY_DIR/app/platforms/github.sh" <<'EOF'
platform_auth_check() { return 0; }
platform_issue_view() {
  echo '{"number":42,"title":"Retry enqueue task","body":"","labels":[],"state":"OPEN"}'
}
platform_issue_create() {
  count=$(cat "$FAKE_PLATFORM_STATE/create-count")
  echo $((count + 1)) > "$FAKE_PLATFORM_STATE/create-count"
  echo "https://github.com/owner/repo/issues/42"
}
platform_card_status_set() {
  count=$(cat "$FAKE_PLATFORM_STATE/board-count")
  echo $((count + 1)) > "$FAKE_PLATFORM_STATE/board-count"
  if [ ! -f "$FAKE_PLATFORM_STATE/failed-once" ]; then
    touch "$FAKE_PLATFORM_STATE/failed-once"
    return 42
  fi
  touch "$FAKE_PLATFORM_STATE/ready-done"
  return 0
}
platform_board_snapshot() {
  if [ -f "$FAKE_PLATFORM_STATE/ready-done" ]; then
    echo '{"items":[{"id":"ITEM_42","status":"Ready","content":{"number":42,"url":"https://github.com/owner/repo/issues/42"}}]}'
  elif [ -f "$FAKE_PLATFORM_STATE/failed-once" ]; then
    echo '{"items":[{"id":"ITEM_42","status":null,"content":{"number":42,"url":"https://github.com/owner/repo/issues/42"}}]}'
  else
    echo '{"items":[]}'
  fi
}
EOF
echo 0 > "$RETRY_DIR/state/create-count"
echo 0 > "$RETRY_DIR/state/board-count"
set +e
(
  cd "$RETRY_DIR/app"
  FAKE_PLATFORM_STATE="$RETRY_DIR/state" \
    ./tasks-to-issues.sh demo --board --config "$RETRY_DIR/app/config.json" >/dev/null 2>&1
)
FIRST_ENQUEUE_RC=$?
set -e
[ "$FIRST_ENQUEUE_RC" -ne 0 ] || fail "first simulated Ready failure returned success"
[ "$(cat "$RETRY_DIR/state/create-count")" -eq 1 ] \
  || fail "first enqueue attempt did not create exactly one issue"
jq -e '."01-first".number == 42' \
  "$RETRY_DIR/app/docs/superpowers/tasks/demo/.issue-map.json" >/dev/null \
  || fail "failed enqueue did not preserve the created issue mapping"
(
  cd "$RETRY_DIR/app"
  FAKE_PLATFORM_STATE="$RETRY_DIR/state" \
    ./tasks-to-issues.sh demo --board --config "$RETRY_DIR/app/config.json" >/dev/null
) || fail "retry after failed Ready enqueue did not recover"
[ "$(cat "$RETRY_DIR/state/create-count")" -eq 1 ] \
  || fail "Ready retry created a duplicate issue"
[ "$(cat "$RETRY_DIR/state/board-count")" -eq 2 ] \
  || fail "Ready retry did not reconcile the mapped issue"
(
  cd "$RETRY_DIR/app"
  FAKE_PLATFORM_STATE="$RETRY_DIR/state" \
    ./tasks-to-issues.sh demo --board --config "$RETRY_DIR/app/config.json" >/dev/null
) || fail "idempotent Ready reconciliation failed"
[ "$(cat "$RETRY_DIR/state/board-count")" -eq 2 ] \
  || fail "already-Ready mapped issue was mutated again"
rm -rf "$RETRY_DIR"

# ── 9. Dispatch discovers a sole config without an active pointer ──────────
# A standalone dispatch must honor a single GitLab config instead of silently
# defaulting to GitHub. The fake backend creates the required close commit.
DISPATCH_DIR=$(mktemp -d)
mkdir -p "$DISPATCH_DIR/.claude/supersaiyan/configs" \
  "$DISPATCH_DIR/.claude/bin/backends" "$DISPATCH_DIR/.claude/bin/platforms"
git -C "$DISPATCH_DIR" init -b main >/dev/null
git -C "$DISPATCH_DIR" config user.email test@example.com
git -C "$DISPATCH_DIR" config user.name Test
touch "$DISPATCH_DIR/README.md"
git -C "$DISPATCH_DIR" add README.md
git -C "$DISPATCH_DIR" commit -m fixture >/dev/null
cat > "$DISPATCH_DIR/.claude/supersaiyan/configs/only.json" <<'EOF'
{"git_platform":"gitlab","project":{"full_path":"group/repo"}}
EOF
cat > "$DISPATCH_DIR/.claude/bin/platforms/gitlab.sh" <<EOF
platform_issue_view() {
  [ "\$#" -eq 1 ] || {
    echo "platform_issue_view expects only an issue reference" >&2
    return 64
  }
  [ -n "\${PLATFORM_CONFIG_PATH:-}" ] && [ -f "\$PLATFORM_CONFIG_PATH" ] || {
    echo "platform_issue_view requires readable PLATFORM_CONFIG_PATH" >&2
    return 65
  }
  [ "\$(jq -r '.git_platform' "\$PLATFORM_CONFIG_PATH")" = "gitlab" ] || return 65
  printf '%s\\n' '{"iid":7,"title":"dispatch smoke","description":"GitLab normalized body","labels":["status::ready"],"state":"opened"}' \\
    | jq '{number:.iid,title,body:.description,labels,state:(if .state == "opened" then "OPEN" else "CLOSED" end)}'
  printf '%s\\n' used > "$DISPATCH_DIR/platform-selected"
}
EOF
cat > "$DISPATCH_DIR/.claude/bin/backends/fake.sh" <<'EOF'
backend_auth_check() { return 0; }
backend_worker_addendum() { :; }
backend_run_sync() {
  case "$1" in
    *"GitLab normalized body"*) ;;
    *) echo "normalized issue body missing from worker prompt" >&2; return 98 ;;
  esac
  git config user.email test@example.com
  git config user.name Test
  git commit --allow-empty -m 'chore(loop): close #7' >/dev/null
}
EOF
set +e
BASE_BRANCH=main REPO_DIR="$DISPATCH_DIR" WORKER_BACKEND=fake \
  "$DISPATCH" 7 >"$DISPATCH_DIR/dispatch.log" 2>&1
DISPATCH_RC=$?
set -e
[ "$DISPATCH_RC" -eq 0 ] && [ -f "$DISPATCH_DIR/platform-selected" ] \
  || fail "dispatch did not select the sole GitLab config"
rm -rf "$DISPATCH_DIR"

# ── 10. Dispatch rejects an explicitly missing config before adapter choice ──
# A stale CONFIG_PATH must never fall back to GitHub: that can dispatch a task
# against the wrong forge. The failure must happen before platform_issue_view.
STALE_DISPATCH_DIR=$(mktemp -d)
mkdir -p "$STALE_DISPATCH_DIR/.claude/bin/backends" \
  "$STALE_DISPATCH_DIR/.claude/bin/platforms"
git -C "$STALE_DISPATCH_DIR" init -b main >/dev/null
git -C "$STALE_DISPATCH_DIR" config user.email test@example.com
git -C "$STALE_DISPATCH_DIR" config user.name Test
touch "$STALE_DISPATCH_DIR/README.md"
git -C "$STALE_DISPATCH_DIR" add README.md
git -C "$STALE_DISPATCH_DIR" commit -m fixture >/dev/null
cat > "$STALE_DISPATCH_DIR/.claude/bin/platforms/github.sh" <<'EOF'
platform_issue_view() {
  printf '%s\n' used > "$REPO_DIR/wrong-forge-selected"
  printf '%s\n' '{"number":7,"title":"wrong forge","body":"","labels":[],"state":"OPEN"}'
}
EOF
cat > "$STALE_DISPATCH_DIR/.claude/bin/backends/fake.sh" <<'EOF'
backend_auth_check() { return 0; }
backend_worker_addendum() { :; }
backend_run_sync() { return 99; }
EOF
set +e
CONFIG_PATH="$STALE_DISPATCH_DIR/missing.json" \
  GIT_PLATFORM= \
  BASE_BRANCH=main REPO_DIR="$STALE_DISPATCH_DIR" WORKER_BACKEND=fake \
  "$DISPATCH" 7 >"$STALE_DISPATCH_DIR/dispatch.log" 2>&1
STALE_DISPATCH_RC=$?
set -e
[ "$STALE_DISPATCH_RC" -ne 0 ] \
  && [ ! -f "$STALE_DISPATCH_DIR/wrong-forge-selected" ] \
  || fail "dispatch silently fell back to GitHub for a missing CONFIG_PATH"

cat > "$STALE_DISPATCH_DIR/gitlab.json" <<'EOF'
{"git_platform":"gitlab","project":{"full_path":"group/repo"}}
EOF
cat > "$STALE_DISPATCH_DIR/.claude/bin/platforms/gitlab.sh" <<'EOF'
platform_issue_view() {
  printf '%s\n' used > "$REPO_DIR/wrong-forge-selected"
  return 99
}
EOF
set +e
CONFIG_PATH="$STALE_DISPATCH_DIR/gitlab.json" \
  GIT_PLATFORM=github \
  BASE_BRANCH=main REPO_DIR="$STALE_DISPATCH_DIR" WORKER_BACKEND=fake \
  "$DISPATCH" 7 >"$STALE_DISPATCH_DIR/dispatch.log" 2>&1
DISPATCH_MISMATCH_RC=$?
set -e
[ "$DISPATCH_MISMATCH_RC" -ne 0 ] \
  && grep -q 'GIT_PLATFORM.*git_platform\|platform mismatch' "$STALE_DISPATCH_DIR/dispatch.log" \
  && [ ! -f "$STALE_DISPATCH_DIR/wrong-forge-selected" ] \
  || fail "dispatch accepted a GIT_PLATFORM/config mismatch or sourced an adapter"
rm -rf "$STALE_DISPATCH_DIR"

# ── 11. Wave planner passes platform-neutral config context ───────────────
# GitLab configs do not have GitHub's project.owner/project.number fields. The
# adapter must receive a readable config reference so it can resolve full_path,
# host, and board_id itself.
WAVE_GITLAB_DIR=$(mktemp -d)
mkdir -p "$WAVE_GITLAB_DIR/platforms"
cp "$WAVE" "$WAVE_GITLAB_DIR/super-board-wave-plan.sh"
cp "$ROOT/scripts/config-resolve.sh" "$WAVE_GITLAB_DIR/config-resolve.sh"
cat > "$WAVE_GITLAB_DIR/config.json" <<'EOF'
{
  "variant": "full",
  "max_workers": 3,
  "human_approves_merge": true,
  "git_platform": "gitlab",
  "project": {
    "host": "gitlab.example.com",
    "full_path": "group/demo",
    "board_id": 9
  }
}
EOF
cat > "$WAVE_GITLAB_DIR/platforms/gitlab.sh" <<'EOF'
platform_board_snapshot() {
  config_path="${1:-}"
  [ -f "$config_path" ] || {
    echo "expected readable config path, got: ${config_path:-<empty>}" >&2
    return 65
  }
  [ "$(jq -r '.project.full_path' "$config_path")" = "group/demo" ] || return 65
  cat <<'JSON'
{"items":[{"id":"ITEM_8","status":"Ready","content":{"type":"Issue","number":8,"title":"GitLab card","body":"","repository":"group/demo","assignees":[]}}]}
JSON
}
EOF
GITLAB_PLAN_OUT=$(bash "$WAVE_GITLAB_DIR/super-board-wave-plan.sh" \
  --config <(cat "$WAVE_GITLAB_DIR/config.json") 2>"$WAVE_GITLAB_DIR/error.log") || true
echo "$GITLAB_PLAN_OUT" | jq -e '.cards | length == 1 and .[0].number == 8' >/dev/null 2>&1 \
  || fail "wave planner did not pass GitLab config context: $(cat "$WAVE_GITLAB_DIR/error.log")"
rm -rf "$WAVE_GITLAB_DIR"

# ── 11. Standalone tasks-to-issues config discovery is forge-safe ─────────
# Match prepare/dispatch semantics: one config is selected automatically, while
# an explicitly invalid config path fails before authenticating or creating.
TASK_CONFIG_DIR=$(mktemp -d)
mkdir -p "$TASK_CONFIG_DIR/app/docs/superpowers/tasks/demo" \
  "$TASK_CONFIG_DIR/app/.claude/supersaiyan/configs" \
  "$TASK_CONFIG_DIR/app/platforms" "$TASK_CONFIG_DIR/state"
cp "$TASKS" "$TASK_CONFIG_DIR/app/tasks-to-issues.sh"
cp "$CONFIG_RESOLVER" "$TASK_CONFIG_DIR/app/platform-config.sh"
cp "$CONFIG_RESOLVE_SH" "$TASK_CONFIG_DIR/app/config-resolve.sh"
cat > "$TASK_CONFIG_DIR/app/docs/superpowers/tasks/demo/01-first.md" <<'EOF'
---
title: First task
order: 1
depends_on_task: null
---

## Goal

Create one issue through the selected forge.
EOF
cat > "$TASK_CONFIG_DIR/app/.claude/supersaiyan/configs/only.json" <<'EOF'
{"git_platform":"gitlab","project":{"host":"gitlab.example.com","full_path":"group/demo","board_id":9}}
EOF
cat > "$TASK_CONFIG_DIR/app/platforms/gitlab.sh" <<'EOF'
platform_auth_check() { echo "GITLAB_AUTH" >> "$FAKE_PLATFORM_STATE/log"; }
platform_issue_create() {
  echo "GITLAB_ISSUE_CREATE" >> "$FAKE_PLATFORM_STATE/log"
  echo "https://gitlab.example.com/group/demo/-/issues/42"
}
platform_card_status_set() { echo "GITLAB_READY" >> "$FAKE_PLATFORM_STATE/log"; }
EOF
cat > "$TASK_CONFIG_DIR/app/platforms/github.sh" <<'EOF'
platform_auth_check() { echo "WRONG_GITHUB_ADAPTER" >> "$FAKE_PLATFORM_STATE/log"; }
platform_issue_create() { return 99; }
platform_card_status_set() { return 99; }
EOF
: > "$TASK_CONFIG_DIR/state/log"
set +e
(
  cd "$TASK_CONFIG_DIR/app"
  FAKE_PLATFORM_STATE="$TASK_CONFIG_DIR/state" ./tasks-to-issues.sh demo >/dev/null 2>&1
)
TASK_CONFIG_RC=$?
set -e
[ "$TASK_CONFIG_RC" -eq 0 ] \
  && grep -q '^GITLAB_ISSUE_CREATE$' "$TASK_CONFIG_DIR/state/log" \
  && ! grep -q '^GITLAB_READY$' "$TASK_CONFIG_DIR/state/log" \
  && ! grep -q '^WRONG_GITHUB_ADAPTER$' "$TASK_CONFIG_DIR/state/log" \
  || fail "onboarded GitLab issue-only filing used the wrong adapter or mutated board status"

: > "$TASK_CONFIG_DIR/state/log"
set +e
(
  cd "$TASK_CONFIG_DIR/app"
  FAKE_PLATFORM_STATE="$TASK_CONFIG_DIR/state" \
    ./tasks-to-issues.sh demo --config missing.json >"$TASK_CONFIG_DIR/out" 2>"$TASK_CONFIG_DIR/err"
)
MISSING_CONFIG_RC=$?
set -e
[ "$MISSING_CONFIG_RC" -ne 0 ] \
  && grep -q 'config not found' "$TASK_CONFIG_DIR/err" \
  && [ ! -s "$TASK_CONFIG_DIR/state/log" ] \
  || fail "explicit missing tasks-to-issues config did not fail before adapter use"

cp "$TASK_CONFIG_DIR/app/.claude/supersaiyan/configs/only.json" \
  "$TASK_CONFIG_DIR/app/.claude/supersaiyan/configs/second.json"
: > "$TASK_CONFIG_DIR/state/log"
set +e
(
  cd "$TASK_CONFIG_DIR/app"
  FAKE_PLATFORM_STATE="$TASK_CONFIG_DIR/state" \
    ./tasks-to-issues.sh demo >"$TASK_CONFIG_DIR/out" 2>"$TASK_CONFIG_DIR/err"
)
MULTIPLE_CONFIG_RC=$?
set -e
[ "$MULTIPLE_CONFIG_RC" -ne 0 ] \
  && grep -q 'multiple supersaiyan configs' "$TASK_CONFIG_DIR/err" \
  && [ ! -s "$TASK_CONFIG_DIR/state/log" ] \
  || fail "ambiguous tasks-to-issues config did not fail before adapter use"

# A stale active pointer is an explicit, invalid selection. It must not fall
# back to another sole config, and it must fail before adapter authentication.
rm "$TASK_CONFIG_DIR/app/.claude/supersaiyan/configs/second.json"
echo missing > "$TASK_CONFIG_DIR/app/.claude/supersaiyan/active"
: > "$TASK_CONFIG_DIR/state/log"
set +e
(
  cd "$TASK_CONFIG_DIR/app"
  FAKE_PLATFORM_STATE="$TASK_CONFIG_DIR/state" \
    ./tasks-to-issues.sh demo >"$TASK_CONFIG_DIR/out" 2>"$TASK_CONFIG_DIR/err"
)
STALE_ACTIVE_RC=$?
set -e
[ "$STALE_ACTIVE_RC" -ne 0 ] \
  && grep -q 'active.*missing\|config not found' "$TASK_CONFIG_DIR/err" \
  && [ ! -s "$TASK_CONFIG_DIR/state/log" ] \
  || fail "stale active config pointer fell back or reached an adapter"

# A selected config owns the forge decision. An inherited, contradictory
# GIT_PLATFORM must fail before sourcing either adapter; a matching value passes.
rm "$TASK_CONFIG_DIR/app/.claude/supersaiyan/active"
: > "$TASK_CONFIG_DIR/state/log"
set +e
(
  cd "$TASK_CONFIG_DIR/app"
  GIT_PLATFORM=github FAKE_PLATFORM_STATE="$TASK_CONFIG_DIR/state" \
    ./tasks-to-issues.sh demo --force >"$TASK_CONFIG_DIR/out" 2>"$TASK_CONFIG_DIR/err"
)
PLATFORM_MISMATCH_RC=$?
set -e
[ "$PLATFORM_MISMATCH_RC" -ne 0 ] \
  && grep -q 'GIT_PLATFORM.*git_platform\|platform mismatch' "$TASK_CONFIG_DIR/err" \
  && [ ! -s "$TASK_CONFIG_DIR/state/log" ] \
  || fail "conflicting inherited GIT_PLATFORM did not fail before adapter use"

: > "$TASK_CONFIG_DIR/state/log"
(
  cd "$TASK_CONFIG_DIR/app"
  GIT_PLATFORM=gitlab FAKE_PLATFORM_STATE="$TASK_CONFIG_DIR/state" \
    ./tasks-to-issues.sh demo --force >/dev/null
) || fail "matching inherited GIT_PLATFORM was rejected"
grep -q '^GITLAB_ISSUE_CREATE$' "$TASK_CONFIG_DIR/state/log" \
  || fail "matching GIT_PLATFORM did not use the selected config adapter"
rm -rf "$TASK_CONFIG_DIR"

# ── 14. Issue-only filing does not require Project scope ────────────────────
# Board enqueue is optional for standalone tasks-to-issues. A repo-scoped token
# must still be able to create issues when no config or GH_PROJECT_NUMBER exists.
NO_BOARD_DIR=$(mktemp -d)
mkdir -p "$NO_BOARD_DIR/app/docs/superpowers/tasks/demo" \
  "$NO_BOARD_DIR/app/platforms" "$NO_BOARD_DIR/bin" "$NO_BOARD_DIR/state"
cp "$TASKS" "$NO_BOARD_DIR/app/tasks-to-issues.sh"
cp "$CONFIG_RESOLVER" "$NO_BOARD_DIR/app/platform-config.sh"
cp "$CONFIG_RESOLVE_SH" "$NO_BOARD_DIR/app/config-resolve.sh"
cp "$GITHUB_PLATFORM" "$NO_BOARD_DIR/app/platforms/github.sh"
cat > "$NO_BOARD_DIR/app/docs/superpowers/tasks/demo/01-first.md" <<'EOF'
---
title: Issue-only task
order: 1
depends_on_task: null
---

## Goal

Create an issue without a project board.
EOF
cat > "$NO_BOARD_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-} ${2:-}" = "auth status" ]; then
  case "$*" in
    *"--json hosts"*)
      echo '{"hosts":{"github.com":[{"active":true,"host":"github.com","login":"octocat","scopes":"repo"}]}}'
      ;;
  esac
  exit 0
fi
if [ "${1:-} ${2:-}" = "repo view" ]; then
  echo "https://github.com/owner/repo"
  exit 0
fi
if [ "${1:-} ${2:-}" = "issue create" ]; then
  echo "https://github.com/owner/repo/issues/43"
  exit 0
fi
echo "unexpected gh call: $*" >&2
exit 2
EOF
chmod +x "$NO_BOARD_DIR/bin/gh"
set +e
(
  cd "$NO_BOARD_DIR/app"
  PATH="$NO_BOARD_DIR/bin:$PATH" ./tasks-to-issues.sh demo \
    >"$NO_BOARD_DIR/out" 2>"$NO_BOARD_DIR/err"
)
NO_BOARD_RC=$?
set -e
[ "$NO_BOARD_RC" -eq 0 ] \
  || fail "issue-only tasks-to-issues rejected a repo-scoped token without Project scope"
rm -rf "$NO_BOARD_DIR"

# ── 15. Onboarded GitHub filing is issue-only unless --board is explicit ───
ONBOARDED_DIR=$(mktemp -d)
mkdir -p "$ONBOARDED_DIR/app/docs/superpowers/tasks/demo" \
  "$ONBOARDED_DIR/app/.claude/supersaiyan/configs" \
  "$ONBOARDED_DIR/app/platforms" "$ONBOARDED_DIR/state"
cp "$TASKS" "$ONBOARDED_DIR/app/tasks-to-issues.sh"
cp "$CONFIG_RESOLVER" "$ONBOARDED_DIR/app/platform-config.sh"
cp "$CONFIG_RESOLVE_SH" "$ONBOARDED_DIR/app/config-resolve.sh"
cp "$GITHUB_PLATFORM" "$ONBOARDED_DIR/app/platforms/github.sh"
cat > "$ONBOARDED_DIR/app/docs/superpowers/tasks/demo/01-first.md" <<'EOF'
---
title: Onboarded issue-only task
order: 1
depends_on_task: null
---

## Goal

Create an issue without touching the configured Project.
EOF
cat > "$ONBOARDED_DIR/app/.claude/supersaiyan/configs/only.json" <<'EOF'
{"git_platform":"github","project":{"owner":"owner","number":7}}
EOF
cat > "$ONBOARDED_DIR/app/platforms/github.sh" <<'EOF'
platform_auth_check() { echo "AUTH $1" >> "$FAKE_PLATFORM_STATE/log"; }
platform_issue_create() {
  echo "ISSUE_CREATE" >> "$FAKE_PLATFORM_STATE/log"
  echo "https://github.com/owner/repo/issues/44"
}
platform_card_status_set() { echo "PROJECT_MUTATION" >> "$FAKE_PLATFORM_STATE/log"; }
EOF
: > "$ONBOARDED_DIR/state/log"
(
  cd "$ONBOARDED_DIR/app"
  FAKE_PLATFORM_STATE="$ONBOARDED_DIR/state" ./tasks-to-issues.sh demo >/dev/null
) || fail "onboarded GitHub issue-only filing failed"
grep -q '^AUTH issue$' "$ONBOARDED_DIR/state/log" \
  || fail "onboarded issue-only filing did not request issue authentication"
! grep -q '^PROJECT_MUTATION$' "$ONBOARDED_DIR/state/log" \
  || fail "onboarded issue-only filing mutated the Project without --board"
rm -rf "$ONBOARDED_DIR"

# ── 16. GitHub auth modes enforce repo and board capabilities ─────────────
AUTH_DIR=$(mktemp -d)
mkdir -p "$AUTH_DIR/bin"
cat > "$AUTH_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-} ${2:-}" = "auth status" ]; then
  case "$*" in
    *"--json hosts"*)
      jq -n --arg scopes "${FAKE_SCOPES:-}" \
        '{hosts:{"github.com":[{active:true,host:"github.com",login:"octocat",scopes:$scopes}]}}'
      ;;
  esac
  exit 0
fi
if [ "${1:-} ${2:-}" = "repo view" ]; then
  [ "${FAKE_REPO_ACCESS:-yes}" = yes ] && { echo https://github.com/owner/repo; exit 0; }
  echo "HTTP 403: Resource not accessible" >&2
  exit 1
fi
echo "unexpected gh call: $*" >&2
exit 2
EOF
chmod +x "$AUTH_DIR/bin/gh"
(
  PATH="$AUTH_DIR/bin:$PATH" FAKE_SCOPES=repo FAKE_REPO_ACCESS=yes \
    bash -c 'source "$1"; platform_auth_check issue' _ "$GITHUB_PLATFORM"
) || fail "issue auth rejected repo scope with repository access"
if (
  PATH="$AUTH_DIR/bin:$PATH" FAKE_SCOPES=project FAKE_REPO_ACCESS=yes \
    bash -c 'source "$1"; platform_auth_check issue' _ "$GITHUB_PLATFORM"
); then
  fail "issue auth accepted a token without repo scope"
fi
if (
  PATH="$AUTH_DIR/bin:$PATH" FAKE_SCOPES=repo FAKE_REPO_ACCESS=no \
    bash -c 'source "$1"; platform_auth_check issue' _ "$GITHUB_PLATFORM"
); then
  fail "issue auth accepted a token without target repository access"
fi
(
  PATH="$AUTH_DIR/bin:$PATH" FAKE_SCOPES='repo, project' FAKE_REPO_ACCESS=yes \
    bash -c 'source "$1"; platform_auth_check board' _ "$GITHUB_PLATFORM"
) || fail "board auth rejected repo+project without separate read:project"
if (
  PATH="$AUTH_DIR/bin:$PATH" FAKE_SCOPES=repo FAKE_REPO_ACCESS=yes \
    bash -c 'source "$1"; platform_auth_check board' _ "$GITHUB_PLATFORM"
); then
  fail "board auth accepted a token without project scope"
fi
rm -rf "$AUTH_DIR"

# Auth scope selection must be bound to the repository's target host. The
# unrelated github.com login is intentionally first and lacks repo scope.
MULTI_HOST_DIR=$(mktemp -d)
mkdir -p "$MULTI_HOST_DIR/bin"
cat > "$MULTI_HOST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-} ${2:-}" = "repo view" ]; then
  echo "https://ghe.example.com/owner/repo"
  exit 0
fi
if [ "${1:-} ${2:-}" = "auth status" ]; then
  case "$*" in
    *"--json hosts"*)
      jq -n --arg target_scopes "${FAKE_TARGET_SCOPES:-repo}" \
        --arg other_scopes "${FAKE_OTHER_SCOPES:-project}" \
        '{hosts:{
          "github.com":[{active:true,host:"github.com",login:"wrong",scopes:$other_scopes}],
          "ghe.example.com":[{active:true,host:"ghe.example.com",login:"target",scopes:$target_scopes}]
        }}'
      ;;
  esac
  exit 0
fi
echo "unexpected gh call: $*" >&2
exit 2
EOF
chmod +x "$MULTI_HOST_DIR/bin/gh"
(
  PATH="$MULTI_HOST_DIR/bin:$PATH" FAKE_TARGET_SCOPES=repo \
    bash -c 'source "$1"; platform_auth_check issue' _ "$GITHUB_PLATFORM"
) || fail "multi-host auth rejected valid credentials for the target repository host"
if (
  PATH="$MULTI_HOST_DIR/bin:$PATH" FAKE_OTHER_SCOPES=repo FAKE_TARGET_SCOPES=project \
    bash -c 'source "$1"; platform_auth_check issue' _ "$GITHUB_PLATFORM"
); then
  fail "multi-host auth accepted repo scope from a non-target host"
fi
rm -rf "$MULTI_HOST_DIR"

# ── 17. GitHub issue lookup normalizes not-found/auth/transport failures ───
LOOKUP_DIR=$(mktemp -d)
mkdir -p "$LOOKUP_DIR/bin"
cat > "$LOOKUP_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_LOOKUP:-ok}" in
  ok) echo '{"number":4,"title":"T","body":"B","labels":[{"id":"L1","name":"bug","color":"d73a4a"}],"state":"OPEN"}' ;;
  404) echo 'HTTP 404: Not Found' >&2; exit 1 ;;
  401) echo 'HTTP 401: Bad credentials' >&2; exit 1 ;;
  403) echo 'HTTP 403: Resource not accessible' >&2; exit 1 ;;
  network) echo 'failed to connect to github.com' >&2; exit 1 ;;
  malformed) echo '{not-json' ;;
esac
EOF
chmod +x "$LOOKUP_DIR/bin/gh"
lookup_rc() {
  local mode="$1" rc=0
  PATH="$LOOKUP_DIR/bin:$PATH" FAKE_LOOKUP="$mode" \
    bash -c 'source "$1"; platform_issue_view 4 >/dev/null' _ "$GITHUB_PLATFORM" || rc=$?
  echo "$rc"
}
[ "$(lookup_rc ok)" -eq 0 ] || fail "successful issue lookup did not return 0"
[ "$(lookup_rc 404)" -eq 44 ] || fail "HTTP 404 issue lookup did not return 44"
[ "$(lookup_rc 401)" -eq 69 ] || fail "HTTP 401 issue lookup did not return 69"
[ "$(lookup_rc 403)" -eq 69 ] || fail "HTTP 403 issue lookup did not return 69"
[ "$(lookup_rc network)" -eq 70 ] || fail "network issue lookup did not return 70"
[ "$(lookup_rc malformed)" -eq 70 ] || fail "malformed issue lookup did not return 70"
normalized_labels=$(
  PATH="$LOOKUP_DIR/bin:$PATH" FAKE_LOOKUP=ok \
    bash -c 'source "$1"; platform_issue_view 4' _ "$GITHUB_PLATFORM" | jq -c '.labels'
)
[ "$normalized_labels" = '["bug"]' ] \
  || fail "GitHub issue labels were not normalized to a string array: $normalized_labels"
rm -rf "$LOOKUP_DIR"

# ── 18. Shared config precedence is deterministic ────────────────────────
RESOLVE_DIR=$(mktemp -d)
mkdir -p "$RESOLVE_DIR/.claude/supersaiyan/configs"
cat > "$RESOLVE_DIR/.claude/supersaiyan/configs/sole.json" <<'EOF'
{"git_platform":"github"}
EOF
cat > "$RESOLVE_DIR/env.json" <<'EOF'
{"git_platform":"gitlab"}
EOF
cat > "$RESOLVE_DIR/explicit.json" <<'EOF'
{"git_platform":"github"}
EOF
source "$CONFIG_RESOLVER"
resolved=$(PLATFORM_CONFIG_PATH="$RESOLVE_DIR/env.json" \
  platform_config_resolve "$RESOLVE_DIR" "$RESOLVE_DIR/explicit.json")
[ "$resolved" = "$RESOLVE_DIR/explicit.json" ] \
  || fail "explicit config did not override PLATFORM_CONFIG_PATH"
echo sole > "$RESOLVE_DIR/.claude/supersaiyan/active"
resolved=$(PLATFORM_CONFIG_PATH="$RESOLVE_DIR/env.json" \
  platform_config_resolve "$RESOLVE_DIR")
[ "$resolved" = "$RESOLVE_DIR/env.json" ] \
  || fail "PLATFORM_CONFIG_PATH did not override the active pointer"
unset PLATFORM_CONFIG_PATH
resolved=$(platform_config_resolve "$RESOLVE_DIR")
[ "$resolved" = "$RESOLVE_DIR/.claude/supersaiyan/configs/sole.json" ] \
  || fail "valid active pointer was not selected"
rm "$RESOLVE_DIR/.claude/supersaiyan/active"
resolved=$(platform_config_resolve "$RESOLVE_DIR")
[ "$resolved" = "$RESOLVE_DIR/.claude/supersaiyan/configs/sole.json" ] \
  || fail "sole config was not selected"
if platform_config_resolve_platform "$RESOLVE_DIR/explicit.json" invalid >/dev/null 2>&1; then
  fail "config/platform mismatch was accepted by the shared resolver"
fi
cat > "$RESOLVE_DIR/invalid.json" <<'EOF'
{"git_platform":"bitbucket"}
EOF
if platform_config_resolve_platform "$RESOLVE_DIR/invalid.json" >/dev/null 2>&1; then
  fail "unsupported git_platform was accepted"
fi
rm -rf "$RESOLVE_DIR"

# ── 19. Installer copies the shared resolver beside pipeline scripts ──────
INSTALL_DIR=$(mktemp -d)
mkdir -p "$INSTALL_DIR/app" "$INSTALL_DIR/bin" "$INSTALL_DIR/home"
cat > "$INSTALL_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$INSTALL_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "plugin list") exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$INSTALL_DIR/bin/gh" "$INSTALL_DIR/bin/claude"
PATH="$INSTALL_DIR/bin:$PATH" HOME="$INSTALL_DIR/home" \
  bash "$ROOT/install.sh" "$INSTALL_DIR/app" >/dev/null \
  || fail "installer smoke failed"
# install.sh's copy target moved from .claude/bin/ to the vendor-neutral .supersaiyan/bin/.
# Consumers still fall back to the old path for installs that predate that move, so the
# assertion tracks where the installer WRITES today, not where readers may also look.
[ -f "$INSTALL_DIR/app/.supersaiyan/bin/platform-config.sh" ] \
  || fail "installer did not copy the shared config resolver"
grep -q '".supersaiyan/bin/platform-config.sh"' "$ROOT/scripts/bootstrap-app.sh" \
  || fail "bootstrap verification does not require the installed shared resolver"
rm -rf "$INSTALL_DIR"

if [ "$FAIL" -ne 0 ]; then
  echo "error: issue #4 platform-rewire contract check failed" >&2
  exit 1
fi

echo "  ✓ platform source + call sites + wave-plan --items smoke"
echo "PASS: test-tasks-wave-dispatch-platform-rewire.sh"
