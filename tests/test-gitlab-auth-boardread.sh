#!/usr/bin/env bash
# test-gitlab-auth-boardread.sh — issue #7 / gitlab-integration task 07.
# Groups A–C of scripts/platforms/gitlab.sh: auth, bot identity, rate-limit
# (fail open), and board snapshot with status:: derivation.
# Offline stubs always run. Live sandbox checks run when glab is logged in.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLAB_SH="$ROOT/scripts/platforms/gitlab.sh"
CONTRACT="$ROOT/tests/test-platform-contract.sh"
SANDBOX="${GITLAB_SANDBOX:-BankNatchapol/supersaiyan-gitlab-sandbox}"

FAIL=0
tfail() { echo "  FAIL: $1" >&2; FAIL=1; }

echo "checking gitlab.sh Groups A–C (auth, rate-limit, board-read)"

[ -f "$GITLAB_SH" ] || { echo "error: $GITLAB_SH not found" >&2; exit 1; }
bash -n "$GITLAB_SH" || tfail "bash -n reported a syntax error in gitlab.sh"
if grep -vE '^\s*#' "$GITLAB_SH" | grep -qE 'declare -A|mapfile|readarray'; then
  tfail "gitlab.sh uses a bash-4-only construct"
fi

# ── 1. Contract includes gitlab.sh ─────────────────────────────────────────
if [ -x "$CONTRACT" ] || [ -f "$CONTRACT" ]; then
  if ! bash "$CONTRACT" >/tmp/test-platform-contract.out 2>&1; then
    tfail "test-platform-contract.sh failed with gitlab.sh present"
    cat /tmp/test-platform-contract.out >&2 || true
  elif ! grep -q 'checking gitlab.sh' /tmp/test-platform-contract.out; then
    tfail "test-platform-contract.sh did not check gitlab.sh"
  fi
else
  tfail "tests/test-platform-contract.sh missing"
fi

# shellcheck disable=SC1090
. "$GITLAB_SH"

# ── 2. status:: derivation (single place, no API) ──────────────────────────
if ! declare -f platform_gitlab_status_from_labels >/dev/null 2>&1; then
  tfail "platform_gitlab_status_from_labels is missing (status derivation must live in one helper)"
else
  assert_status() {
    local labels="$1" want="$2" got
    got=$(printf '%s\n' "$labels" | platform_gitlab_status_from_labels)
    [ "$got" = "$want" ] || tfail "status_from_labels $labels → $got (want $want)"
  }
  assert_status '[]' "Backlog"
  assert_status '["bug"]' "Backlog"
  assert_status '["status::ready"]' "Ready"
  assert_status '["status::building"]' "Building"
  assert_status '["status::qa"]' "QA"
  assert_status '["status::review"]' "Review"
  assert_status '["status::done"]' "Done"
  assert_status '["status::blocked"]' "Blocked"
  assert_status '["status::skipped"]' "Skipped"
  assert_status '["bug","status::ready","status::qa"]' "Ready"
  assert_status '["Status::Ready"]' "Ready"
fi

# ── 3. Stubbed glab: auth, identity, rate, snapshot ────────────────────────
TD=$(mktemp -d)
GLAB_LOG="$TD/glab.log"
mkdir -p "$TD/bin"
cat > "$TD/bin/glab" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GLAB_LOG:?}"
# Drop flag pairs so $1 is the subcommand.
while [ $# -gt 0 ]; do
  case "$1" in
    --hostname|--output) shift 2 ;;
    --include|--paginate|-i) shift ;;
    *) break ;;
  esac
done
cmd="${1:-}"
shift || true
case "$cmd" in
  auth)
    [ "${GLAB_AUTH_OK:-1}" = 1 ] || exit 1
    exit 0
    ;;
  api)
    path=""
    include=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --hostname|--output|--method|-X) shift 2 ;;
        --include|-i) include=1; shift ;;
        --paginate) shift ;;
        -*) shift ;;
        *) path="$1"; shift ;;
      esac
    done
    if [ "$include" = 1 ] && [ -n "${GLAB_INCLUDE_HEADERS:-}" ]; then
      printf '%s\n' "$GLAB_INCLUDE_HEADERS"
      printf '\n'
    fi
    case "$path" in
      personal_access_tokens/self)
        [ "${GLAB_TOKEN_EXIT:-0}" = 0 ] || exit "${GLAB_TOKEN_EXIT}"
        printf '%s\n' "${GLAB_TOKEN_JSON}"
        ;;
      user)
        printf '%s\n' "${GLAB_USER_JSON}"
        ;;
      */issues*)
        printf '%s\n' "${GLAB_ISSUES_JSON}"
        ;;
      projects/*)
        [ "${GLAB_PROJECT_EXIT:-0}" = 0 ] || exit "${GLAB_PROJECT_EXIT}"
        printf '%s\n' "${GLAB_PROJECT_JSON}"
        ;;
      *)
        echo "unexpected glab api path: $path" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "unexpected glab command: $cmd" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$TD/bin/glab"

CFG="$TD/config.json"
cat > "$CFG" <<EOF
{
  "git_platform": "gitlab",
  "project": {
    "host": "gitlab.com",
    "full_path": "group/demo",
    "board_id": 1
  }
}
EOF
export PLATFORM_CONFIG_PATH="$CFG"
export PATH="$TD/bin:$PATH"
export GLAB_LOG
export GLAB_AUTH_OK=1
export GLAB_TOKEN_EXIT=0
export GLAB_TOKEN_JSON='{"scopes":["api","write_repository"]}'
export GLAB_USER_JSON='{"username":"alice","bot":false}'
export GLAB_PROJECT_EXIT=0
export GLAB_PROJECT_JSON='{"path_with_namespace":"group/demo","permissions":{"project_access":{"access_level":50}}}'
export GLAB_ISSUES_JSON='[]'
export GLAB_INCLUDE_HEADERS=""

# 3a. glab missing
mkdir -p "$TD/empty"
if (
  PATH="$TD/empty"
  platform_auth_check issue
) >/dev/null 2>&1; then
  tfail "platform_auth_check issue succeeded with glab missing from PATH"
fi

# 3b. auth status failure
GLAB_AUTH_OK=0
if platform_auth_check issue >/dev/null 2>&1; then
  tfail "platform_auth_check issue succeeded when glab auth status fails"
fi
GLAB_AUTH_OK=1

# 3c. unknown mode
if platform_auth_check banana >/dev/null 2>&1; then
  tfail "platform_auth_check accepted unknown mode"
else
  rc=0
  platform_auth_check banana >/dev/null 2>&1 || rc=$?
  [ "$rc" = 64 ] || tfail "platform_auth_check unknown mode exit $rc (want 64)"
fi

# 3d. issue mode: project GET succeeds
GLAB_PROJECT_EXIT=0
if ! platform_auth_check issue >/dev/null 2>&1; then
  tfail "platform_auth_check issue failed against stubbed reachable project"
fi

# 3e. issue mode: project GET fails
GLAB_PROJECT_EXIT=1
if platform_auth_check issue >/dev/null 2>&1; then
  tfail "platform_auth_check issue succeeded when project GET fails"
fi
GLAB_PROJECT_EXIT=0

# 3f. board mode: PAT missing write_repository
GLAB_TOKEN_EXIT=0
GLAB_TOKEN_JSON='{"scopes":["read_api"]}'
if platform_auth_check board >/dev/null 2>&1; then
  tfail "platform_auth_check board succeeded with PAT scopes=[read_api]"
fi

# 3g. board mode: PAT has api + write_repository
GLAB_TOKEN_JSON='{"scopes":["api","write_repository"]}'
if ! platform_auth_check board >/dev/null 2>&1; then
  tfail "platform_auth_check board failed with PAT scopes=[api,write_repository]"
fi

# 3h. board mode: OAuth (PAT endpoint 400) + Developer access
GLAB_TOKEN_EXIT=400
GLAB_PROJECT_JSON='{"path_with_namespace":"group/demo","permissions":{"project_access":{"access_level":30}}}'
if ! platform_auth_check board >/dev/null 2>&1; then
  tfail "platform_auth_check board failed for OAuth token with Developer access"
fi

# 3i. board mode: OAuth + Guest access
GLAB_PROJECT_JSON='{"path_with_namespace":"group/demo","permissions":{"project_access":{"access_level":10}}}'
if platform_auth_check board >/dev/null 2>&1; then
  tfail "platform_auth_check board succeeded for OAuth token with Guest access"
fi
GLAB_TOKEN_EXIT=0
GLAB_TOKEN_JSON='{"scopes":["api","write_repository"]}'
GLAB_PROJECT_JSON='{"path_with_namespace":"group/demo","permissions":{"project_access":{"access_level":50}}}'

# 3j. bot identity — personal vs project-access-token bot
GLAB_USER_JSON='{"username":"alice","bot":false}'
got=$(platform_bot_identity_resolve) || tfail "platform_bot_identity_resolve failed for personal user"
[ "$got" = "alice" ] || tfail "bot identity personal → $got (want alice)"

GLAB_USER_JSON='{"username":"project_12_bot_ab","bot":true}'
got=$(platform_bot_identity_resolve) || tfail "platform_bot_identity_resolve failed for project bot"
[ "$got" = "project_12_bot_ab" ] || tfail "bot identity project bot → $got (want project_12_bot_ab)"

# 3k. rate remaining parses headers
GLAB_INCLUDE_HEADERS=$'HTTP/2.0 200 OK\nRateLimit-Remaining: 321\nRateLimit-Reset: 9999999999'
got=$(platform_rate_remaining)
[ "$got" = "321" ] || tfail "platform_rate_remaining → $got (want 321)"

# 3l. rate remaining fail-open: absent headers are unknown, never 0
GLAB_INCLUDE_HEADERS=$'HTTP/2.0 200 OK\nCache-Control: private'
got=$(platform_rate_remaining)
if [ "$got" = "0" ]; then
  tfail "platform_rate_remaining treated missing headers as 0"
elif [ -z "$got" ] || [ "$got" = "unknown" ]; then
  :
else
  # numeric non-zero also fail-open-ish, but spec says unknown
  case "$got" in
    unknown|"") ;;
    *) tfail "platform_rate_remaining missing headers → $got (want unknown or empty)" ;;
  esac
fi

# 3m. rate guard fail-open: no sleep when headers absent
mkdir -p "$TD/sleepbin"
cat > "$TD/sleepbin/sleep" <<'EOF'
#!/usr/bin/env bash
echo "slept $*" >> "${SLEEP_LOG:?}"
exit 0
EOF
chmod +x "$TD/sleepbin/sleep"
SLEEP_LOG="$TD/sleep.log"
: > "$SLEEP_LOG"
export SLEEP_LOG
GLAB_INCLUDE_HEADERS=$'HTTP/2.0 200 OK\nCache-Control: private'
if ! PATH="$TD/sleepbin:$TD/bin:$PATH" platform_rate_guard 200; then
  tfail "platform_rate_guard failed open on missing headers"
fi
if [ -s "$SLEEP_LOG" ]; then
  tfail "platform_rate_guard slept on missing headers ($(cat "$SLEEP_LOG"))"
fi

# 3n. self-hosted --hostname on auth + rate probe
SELF_CFG="$TD/selfhosted.json"
cat > "$SELF_CFG" <<'EOF'
{
  "git_platform": "gitlab",
  "project": {
    "host": "gitlab.example.com",
    "full_path": "g/p"
  }
}
EOF
: > "$GLAB_LOG"
PLATFORM_CONFIG_PATH="$SELF_CFG" platform_auth_check issue >/dev/null 2>&1 || true
if ! grep -q -- '--hostname gitlab.example.com' "$GLAB_LOG"; then
  tfail "self-hosted config did not pass --hostname gitlab.example.com to glab (got: $(tr '\n' ' ' < "$GLAB_LOG"))"
fi

# 3o. board snapshot shape + status derivation
GLAB_ISSUES_JSON='[
  {"iid":1,"title":"Ready card","web_url":"https://gitlab.example.com/g/p/-/issues/1","state":"opened","labels":["status::ready"],"assignees":[],"description":"seed"},
  {"iid":2,"title":"Unlabeled card","web_url":"https://gitlab.example.com/g/p/-/issues/2","state":"opened","labels":[],"assignees":[{"username":"bob"}],"description":""}
]'
PLATFORM_CONFIG_PATH="$CFG"
snap=$(platform_board_snapshot "$CFG") || tfail "platform_board_snapshot failed on stub issues"
echo "$snap" | jq -e '
  (.items | length == 2)
  and (.items[] | select(.content.number == 1)
        | .status == "Ready"
          and .number == 1
          and .title == "Ready card"
          and .url == "https://gitlab.example.com/g/p/-/issues/1"
          and .state == "opened"
          and .repository == "group/demo"
          and (.assignees | type == "array")
          and (.labels | index("status::ready"))
          and .content.type == "Issue"
          and .content.repository == "group/demo")
  and (.items[] | select(.content.number == 2)
        | .status == "Backlog"
          and .number == 2
          and .content.type == "Issue"
          and (.content.assignees | length == 1))
' >/dev/null 2>&1 || tfail "board snapshot shape/status mismatch: $snap"

ready_n=$(platform_column_count Ready "$snap")
[ "$ready_n" = "1" ] || tfail "platform_column_count Ready → $ready_n (want 1)"
backlog_n=$(platform_column_count Backlog "$snap")
[ "$backlog_n" = "1" ] || tfail "platform_column_count Backlog → $backlog_n (want 1)"
top=$(platform_top_unclaimed_card Ready "$snap")
[ "$top" = "1" ] || tfail "platform_top_unclaimed_card Ready → $top (want 1)"

# ── 4. Live sandbox (skip when glab is not authenticated) ──────────────────
unset PLATFORM_CONFIG_PATH
# Restore real glab (stub was first on PATH).
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if command -v glab >/dev/null 2>&1 && glab auth status >/dev/null 2>&1; then
  LIVE_CFG="$TD/live.json"
  cat > "$LIVE_CFG" <<EOF
{
  "git_platform": "gitlab",
  "project": {
    "host": "gitlab.com",
    "full_path": "$SANDBOX"
  }
}
EOF
  export PLATFORM_CONFIG_PATH="$LIVE_CFG"
  # Re-source so helpers see a clean environment; functions already defined.
  if ! platform_auth_check issue; then
    tfail "live platform_auth_check issue failed against $SANDBOX"
  fi
  if ! platform_auth_check board; then
    tfail "live platform_auth_check board failed against $SANDBOX"
  fi
  ident=$(platform_bot_identity_resolve) || tfail "live platform_bot_identity_resolve failed"
  [ -n "$ident" ] || tfail "live bot identity was empty"
  live_rem=$(platform_rate_remaining)
  [ "$live_rem" != "0" ] || tfail "live platform_rate_remaining returned 0 (must fail open if headers absent)"
  if ! platform_rate_guard 200; then
    tfail "live platform_rate_guard failed"
  fi
  live_snap=$(platform_board_snapshot "$LIVE_CFG") || tfail "live platform_board_snapshot failed"
  echo "$live_snap" | jq -e --arg repo "$SANDBOX" '
    ([.items[] | select(.status == "Ready" and .content.type == "Issue")] | length) >= 1
    and ([.items[] | select(.status == "Backlog" and .content.type == "Issue")] | length) >= 1
    and all(.items[];
      (.number | type == "number")
      and (.title | type == "string")
      and (.url | type == "string")
      and (.state | type == "string")
      and .repository == $repo
      and (.assignees | type == "array")
      and (.labels | type == "array")
      and (.status | type == "string")
      and .content.type == "Issue"
      and .content.number == .number
      and .content.repository == $repo)
  ' >/dev/null 2>&1 || tfail "live snapshot missing Ready/Backlog or normalized fields: $live_snap"
  unset PLATFORM_CONFIG_PATH
else
  echo "  skip live sandbox checks (glab not authenticated)"
fi

rm -rf "$TD"

if [ "$FAIL" -ne 0 ]; then
  echo "error: gitlab auth/board-read contract check failed" >&2
  exit 1
fi

echo "  ✓ gitlab.sh Groups A–C: auth, fail-open rate, status:: snapshot"
echo "PASS: test-gitlab-auth-boardread.sh"
