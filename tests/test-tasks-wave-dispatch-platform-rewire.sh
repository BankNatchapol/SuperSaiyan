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

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

for f in "$TASKS" "$WAVE" "$DISPATCH" "$PREPARE" "$GITHUB_PLATFORM"; do
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
grep -q '\.git_platform // "github"' "$DISPATCH" \
  || fail "super-build-dispatch.sh does not resolve git_platform from config"
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

# ── 8. Real tasks-to-issues enqueue behavior ───────────────────────────────
# Static grep cannot prove the adapter receives the config and performs the
# project bootstrap/add/edit sequence. Run the real caller against a fake gh.
ENQUEUE_DIR=$(mktemp -d)
mkdir -p "$ENQUEUE_DIR/app/docs/superpowers/tasks/demo" \
  "$ENQUEUE_DIR/app/platforms" "$ENQUEUE_DIR/bin" "$ENQUEUE_DIR/state"
cp "$TASKS" "$ENQUEUE_DIR/app/tasks-to-issues.sh"
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
    ./tasks-to-issues.sh demo --config "$ENQUEUE_DIR/app/config.json" >/dev/null
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
rm -rf "$STALE_DISPATCH_DIR"

# ── 11. Wave planner passes platform-neutral config context ───────────────
# GitLab configs do not have GitHub's project.owner/project.number fields. The
# adapter must receive a readable config reference so it can resolve full_path,
# host, and board_id itself.
WAVE_GITLAB_DIR=$(mktemp -d)
mkdir -p "$WAVE_GITLAB_DIR/platforms"
cp "$WAVE" "$WAVE_GITLAB_DIR/super-board-wave-plan.sh"
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
  && ! grep -q '^WRONG_GITHUB_ADAPTER$' "$TASK_CONFIG_DIR/state/log" \
  || fail "tasks-to-issues did not auto-select the sole GitLab config"

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
rm -rf "$TASK_CONFIG_DIR"

# ── 14. Issue-only filing does not require Project scope ────────────────────
# Board enqueue is optional for standalone tasks-to-issues. A repo-scoped token
# must still be able to create issues when no config or GH_PROJECT_NUMBER exists.
NO_BOARD_DIR=$(mktemp -d)
mkdir -p "$NO_BOARD_DIR/app/docs/superpowers/tasks/demo" \
  "$NO_BOARD_DIR/app/platforms" "$NO_BOARD_DIR/bin" "$NO_BOARD_DIR/state"
cp "$TASKS" "$NO_BOARD_DIR/app/tasks-to-issues.sh"
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

if [ "$FAIL" -ne 0 ]; then
  echo "error: issue #4 platform-rewire contract check failed" >&2
  exit 1
fi

echo "  ✓ platform source + call sites + wave-plan --items smoke"
echo "PASS: test-tasks-wave-dispatch-platform-rewire.sh"
