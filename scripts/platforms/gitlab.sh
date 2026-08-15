#!/usr/bin/env bash
# scripts/platforms/gitlab.sh — Platform interface for git_platform "gitlab".
# Sourced (not executed) by dispatcher/helpers. Thin wrappers around `glab`.
# Contract: docs/superpowers/specs/gitlab-integration-design.md § Platform interface.
#
# Groups A–C (auth, rate-limit, board-read) are implemented here (issue #7).
# Groups D–K are stubs until later gitlab-integration tasks.
#
# bash 3.2 (macOS default) — no mapfile, no declare -A, no readarray.

# ───────────────────────────── internals ─────────────────────────────

# Single status:: projection (Open Judgment Call 4). Used by
# platform_gitlab_status_from_labels and platform_board_snapshot.
# First status::* label wins; zero matches → Backlog. Column names match
# GitHub's Status options so wave-plan jq (Ready/QA/…) needs no change.
_GITLAB_STATUS_JQ='
  def column_name:
    if . == "ready" then "Ready"
    elif . == "building" then "Building"
    elif . == "qa" then "QA"
    elif . == "review" then "Review"
    elif . == "done" then "Done"
    elif . == "blocked" then "Blocked"
    elif . == "skipped" then "Skipped"
    else (.[0:1] | ascii_upcase) + .[1:]
    end;
  def status_from_labels:
    ([.[]?
      | (if type == "object" then .name else . end)
      | select(type == "string")
      | ascii_downcase
      | select(startswith("status::"))
      | ltrimstr("status::")
      | column_name] | .[0] // "Backlog");
'

platform_gitlab_status_from_labels() {
  # stdin or $1 = JSON array of label names. Prints one column name.
  local input
  if [ -n "${1:-}" ]; then
    input="$1"
  else
    input=$(cat)
  fi
  printf '%s' "$input" | jq -r "${_GITLAB_STATUS_JQ} status_from_labels"
}

_gitlab_config_path() {
  if [ -n "${1:-}" ] && [ -f "$1" ]; then
    printf '%s\n' "$1"
    return 0
  fi
  if [ -n "${PLATFORM_CONFIG_PATH:-}" ] && [ -f "$PLATFORM_CONFIG_PATH" ]; then
    printf '%s\n' "$PLATFORM_CONFIG_PATH"
    return 0
  fi
  return 1
}

_gitlab_host_from_config() {
  local cfg="${1:-}"
  [ -n "$cfg" ] && [ -f "$cfg" ] || return 0
  jq -r '.project.host // empty' "$cfg" 2>/dev/null || true
}

_gitlab_full_path_from_config() {
  local cfg="${1:-}"
  [ -n "$cfg" ] && [ -f "$cfg" ] || return 0
  jq -r '.project.full_path // empty' "$cfg" 2>/dev/null || true
}

_gitlab_project_api_id() {
  printf '%s' "${1:-}" | sed 's|/|%2F|g'
}

_gitlab_auth_status() {
  local host="${1:-}"
  if [ -n "$host" ] && [ "$host" != "gitlab.com" ]; then
    glab auth status --hostname "$host"
  else
    glab auth status
  fi
}

_gitlab_api() {
  local host="${1:-}"
  shift
  if [ -n "$host" ] && [ "$host" != "gitlab.com" ]; then
    glab api --hostname "$host" "$@"
  else
    glab api "$@"
  fi
}

_gitlab_not_implemented() {
  echo "$1 is not implemented until a later gitlab-integration task" >&2
  return 78
}

# ───────────────────────────── Group A — Auth & identity ─────────────────────────────

platform_auth_check() {
  # Modes: issue (default) requires repository API access;
  # board additionally requires board-write capability (PAT scopes api +
  # write_repository, or OAuth/session with Developer+ on the target project).
  local mode="${1:-issue}"
  case "$mode" in
    issue|board) ;;
    *)
      echo "platform_auth_check: unknown auth mode '$mode'" >&2
      return 64
      ;;
  esac
  command -v glab >/dev/null 2>&1 || {
    echo "glab CLI not found on PATH — install: brew install glab" >&2
    return 1
  }
  local cfg="" host="" full_path="" encoded token_json scopes access
  cfg=$(_gitlab_config_path) || true
  host=$(_gitlab_host_from_config "$cfg")
  full_path=$(_gitlab_full_path_from_config "$cfg")
  if ! _gitlab_auth_status "$host" >/dev/null 2>&1; then
    if [ -n "$host" ] && [ "$host" != "gitlab.com" ]; then
      echo "glab not authenticated for $host — run: glab auth login --hostname $host" >&2
    else
      echo "glab not authenticated — run: glab auth login" >&2
    fi
    return 1
  fi
  if [ -n "$full_path" ]; then
    encoded=$(_gitlab_project_api_id "$full_path")
    if ! _gitlab_api "$host" "projects/${encoded}" >/dev/null 2>&1; then
      echo "GitLab token cannot access the target project: $full_path" >&2
      return 1
    fi
  else
    if ! _gitlab_api "$host" user >/dev/null 2>&1; then
      echo "GitLab token cannot call the API — run: glab auth login" >&2
      return 1
    fi
  fi
  [ "$mode" = board ] || return 0

  token_json=$(_gitlab_api "$host" personal_access_tokens/self 2>/dev/null) || token_json=""
  if [ -n "$token_json" ] && printf '%s' "$token_json" | jq -e 'type == "object" and has("scopes")' >/dev/null 2>&1; then
    scopes=$(printf '%s' "$token_json" | jq -c '.scopes // []')
    if printf '%s' "$scopes" | jq -e 'any(. == "api") and any(. == "write_repository")' >/dev/null 2>&1; then
      return 0
    fi
    echo "GitLab token missing board-write scopes (need api, write_repository); run: glab auth login" >&2
    return 1
  fi

  # OAuth / session tokens cannot hit personal_access_tokens/self. Prove
  # board-write via project membership (Developer=30 or higher can edit labels).
  if [ -z "$full_path" ]; then
    echo "GitLab board auth needs project.full_path (OAuth token has no PAT scope list)" >&2
    return 1
  fi
  encoded=$(_gitlab_project_api_id "$full_path")
  access=$(_gitlab_api "$host" "projects/${encoded}" 2>/dev/null | jq -r \
    '[.permissions.project_access.access_level // 0, .permissions.group_access.access_level // 0] | max' \
    2>/dev/null) || access=0
  case "$access" in
    ''|*[!0-9]*) access=0 ;;
  esac
  if [ "$access" -ge 30 ]; then
    return 0
  fi
  echo "GitLab token lacks Developer+ access on $full_path (needed to move board cards)" >&2
  return 1
}

platform_bot_identity_resolve() {
  # Project/Group Access Token → auto-created bot user (project_<id>_bot_*).
  # Personal / OAuth token → the authenticated username. Echoes that login.
  local cfg="" host="" login
  cfg=$(_gitlab_config_path) || true
  host=$(_gitlab_host_from_config "$cfg")
  login=$(_gitlab_api "$host" user 2>/dev/null | jq -r '.username // empty') || login=""
  if [ -z "$login" ]; then
    echo "could not resolve bot identity — glab auth / user endpoint unavailable" >&2
    return 1
  fi
  printf '%s\n' "$login"
}

# ───────────────────────────── Group B — Rate limit / quota ─────────────────────────────

_gitlab_rate_probe() {
  # Sets _GITLAB_RATE_REMAINING (digits or "unknown") and _GITLAB_RATE_RESET
  # (unix timestamp or empty). Absent headers → unknown, never 0.
  # Probe REST `user --include`, not GraphQL — GraphQL often omits these headers.
  local cfg="" host="" raw
  cfg=$(_gitlab_config_path) || true
  host=$(_gitlab_host_from_config "$cfg")
  _GITLAB_RATE_REMAINING="unknown"
  _GITLAB_RATE_RESET=""
  raw=$(_gitlab_api "$host" --include user 2>/dev/null) || raw=""
  [ -n "$raw" ] || return 0
  _GITLAB_RATE_REMAINING=$(printf '%s\n' "$raw" | awk '
    BEGIN { IGNORECASE=1 }
    /^$/ { exit }
    /^RateLimit-Remaining:/ { print $2; exit }
  ')
  _GITLAB_RATE_RESET=$(printf '%s\n' "$raw" | awk '
    BEGIN { IGNORECASE=1 }
    /^$/ { exit }
    /^RateLimit-Reset:/ { print $2; exit }
  ')
  case "${_GITLAB_RATE_REMAINING}" in
    ''|*[!0-9]*) _GITLAB_RATE_REMAINING="unknown" ;;
  esac
}

platform_rate_remaining() {
  # $1 = resource bucket (ignored on GitLab — one family of headers).
  _gitlab_rate_probe
  printf '%s\n' "${_GITLAB_RATE_REMAINING}"
}

platform_rate_guard() {
  # Sleep until quota recovers. MUST fail open (no-op) when headers are absent.
  # $1 = optional minimum-remaining threshold (default 200).
  local min="${1:-200}" rem reset now wait
  _gitlab_rate_probe
  rem="${_GITLAB_RATE_REMAINING}"
  case "$rem" in
    ''|unknown|*[!0-9]*) return 0 ;;
  esac
  if [ "$rem" -lt "$min" ]; then
    reset="${_GITLAB_RATE_RESET}"
    case "$reset" in
      ''|*[!0-9]*) wait=60 ;;
      *)
        now=$(date +%s)
        wait=$((reset - now + 10))
        [ "$wait" -lt 60 ] && wait=60
        [ "$wait" -gt 3600 ] && wait=3600
        ;;
    esac
    echo "[platform-rate-guard] GitLab low: ${rem} left (<${min}); sleeping ${wait}s" >&2
    sleep "$wait"
  fi
  return 0
}

# ───────────────────────────── Group C — Board read ─────────────────────────────

platform_board_snapshot() {
  # Usage: <config-path> (wave-plan / prepare). Falls back to PLATFORM_CONFIG_PATH.
  # Emits GitHub-compatible {items:[{status, content:{type,number,title,...}}]}
  # plus the normalized flat fields from the spec on each item.
  # .status is derived here only — callers must not re-scan labels.
  local cfg="" host="" full_path="" encoded issues
  cfg=$(_gitlab_config_path "${1:-}") || {
    echo "platform_board_snapshot: readable GitLab config path required" >&2
    return 65
  }
  host=$(_gitlab_host_from_config "$cfg")
  full_path=$(_gitlab_full_path_from_config "$cfg")
  if [ -z "$full_path" ]; then
    echo "platform_board_snapshot: project.full_path missing in $cfg" >&2
    return 65
  fi
  encoded=$(_gitlab_project_api_id "$full_path")
  issues=$(_gitlab_api "$host" --paginate "projects/${encoded}/issues?scope=all&per_page=100") || {
    echo "platform_board_snapshot: failed to list issues for $full_path" >&2
    return 1
  }
  printf '%s' "$issues" | jq --arg repo "$full_path" "${_GITLAB_STATUS_JQ}"'
    {items: [ .[] | {
      number: .iid,
      title: .title,
      url: .web_url,
      state: .state,
      repository: $repo,
      assignees: [(.assignees // [])[] | (if type == "object" then .username else . end)],
      labels: [(.labels // [])[] | (if type == "object" then .name else . end)],
      status: ((.labels // []) | status_from_labels),
      content: {
        type: "Issue",
        number: .iid,
        title: .title,
        body: (.description // ""),
        url: .web_url,
        repository: $repo,
        assignees: [(.assignees // [])[] | (if type == "object" then .username else . end)]
      }
    }]}
  '
}

platform_column_count() {
  # $1 = column name, $2 = snapshot JSON from platform_board_snapshot.
  local col="$1" snapshot="${2:-}"
  if [ -z "$snapshot" ]; then
    snapshot=$(cat)
  fi
  echo "$snapshot" | jq --arg col "$col" '[.items[] | select(.status == $col)] | length'
}

platform_top_unclaimed_card() {
  # $1 = column name, $2 = snapshot JSON. Emits first unassigned Issue number.
  local col="$1" snapshot="${2:-}"
  if [ -z "$snapshot" ]; then
    snapshot=$(cat)
  fi
  echo "$snapshot" | jq -r --arg col "$col" '
    .items[]
    | select(.status == $col and .content.type == "Issue")
    | select((.content.assignees // []) | length == 0)
    | .content.number' | head -1
}

# ───────────────────────────── Groups D–K — stubs (later tasks) ─────────────────────────────

platform_card_status_set() { _gitlab_not_implemented platform_card_status_set; }
platform_card_move_verify() { _gitlab_not_implemented platform_card_move_verify; }
platform_claim_issue() { _gitlab_not_implemented platform_claim_issue; }
platform_release_issue() { _gitlab_not_implemented platform_release_issue; }
platform_issue_create() { _gitlab_not_implemented platform_issue_create; }
platform_issue_view() { _gitlab_not_implemented platform_issue_view; }
platform_issue_comment() { _gitlab_not_implemented platform_issue_comment; }
platform_issue_close() { _gitlab_not_implemented platform_issue_close; }
platform_issue_edit_labels() { _gitlab_not_implemented platform_issue_edit_labels; }
platform_mr_create_draft() { _gitlab_not_implemented platform_mr_create_draft; }
platform_mr_mark_ready() { _gitlab_not_implemented platform_mr_mark_ready; }
platform_mr_comment() { _gitlab_not_implemented platform_mr_comment; }
platform_mr_merge_squash() { _gitlab_not_implemented platform_mr_merge_squash; }
platform_mr_view() { _gitlab_not_implemented platform_mr_view; }
platform_mr_list_by_branch() { _gitlab_not_implemented platform_mr_list_by_branch; }
platform_thread_list_unresolved() { _gitlab_not_implemented platform_thread_list_unresolved; }
platform_thread_resolve() { _gitlab_not_implemented platform_thread_resolve; }
platform_thread_create() { _gitlab_not_implemented platform_thread_create; }
platform_detect_production_ci() { _gitlab_not_implemented platform_detect_production_ci; }
platform_detect_branch_protection() { _gitlab_not_implemented platform_detect_branch_protection; }
platform_raw_file_url() { _gitlab_not_implemented platform_raw_file_url; }
platform_repo_create() { _gitlab_not_implemented platform_repo_create; }
platform_label_ensure() { _gitlab_not_implemented platform_label_ensure; }
platform_board_ensure() { _gitlab_not_implemented platform_board_ensure; }
