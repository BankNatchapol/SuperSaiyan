#!/usr/bin/env bash
# scripts/platforms/gitlab.sh — Platform interface for git_platform "gitlab".
# Sourced (not executed) by dispatcher/helpers. Thin wrappers around `glab`.
# Contract: docs/superpowers/specs/gitlab-integration-design.md § Platform interface.
#
# Groups A–K are implemented (issues #7–#13).
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

_gitlab_glab() {
  # $1 = host, $2 = full_path repo, remaining = glab argv starting at issue|mr.
  # Run from a non-git cwd so a GitHub-origin SuperSaiyan checkout does not
  # make glab refuse GitLab --repo targets. -R must come before the verb.
  local host="${1:-}" repo="${2:-}"
  shift 2
  local tmp="${TMPDIR:-/tmp}"
  if [ -n "$host" ] && [ "$host" != "gitlab.com" ]; then
    ( cd "$tmp" && GITLAB_HOST="$host" glab -R "$repo" "$@" )
  else
    ( cd "$tmp" && glab -R "$repo" "$@" )
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
  # BSD awk (macOS) has no IGNORECASE; glab may canonicalize header names.
  _GITLAB_RATE_REMAINING=$(printf '%s\n' "$raw" | awk '
    /^$/ { exit }
    tolower($0) ~ /^ratelimit-remaining:/ { print $2; exit }
  ')
  _GITLAB_RATE_RESET=$(printf '%s\n' "$raw" | awk '
    /^$/ { exit }
    tolower($0) ~ /^ratelimit-reset:/ { print $2; exit }
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
  # --paginate emits one JSON array per page; slurp+add before projecting.
  printf '%s' "$issues" | jq -s 'add // []' | jq --arg repo "$full_path" "${_GITLAB_STATUS_JQ}"'
    {items: [ .[] | {
      number: .iid,
      title: .title,
      url: .web_url,
      state: (if (.state | ascii_downcase) == "closed" then "CLOSED" else "OPEN" end),
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
  echo "$snapshot" | jq --arg col "$col" '
    [.items[]
     | select(.status == $col)
     | select(
         ($col != "Ready" and $col != "Building" and $col != "QA" and $col != "Review")
         or ((.state // "OPEN") | ascii_upcase) != "CLOSED"
       )] | length'
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
    | select(
        ($col != "Ready" and $col != "Building" and $col != "QA" and $col != "Review")
        or ((.state // "OPEN") | ascii_upcase) != "CLOSED"
      )
    | select((.content.assignees // []) | length == 0)
    | .content.number' | head -1
}

# ───────────────────────────── Group D — Board write / move-card ─────────────────────────────

platform_gitlab_label_from_status() {
  # Inverse of platform_gitlab_status_from_labels. Backlog = no status:: label.
  case "${1:-}" in
    Ready) printf 'status::ready\n' ;;
    Building) printf 'status::building\n' ;;
    QA) printf 'status::qa\n' ;;
    Review) printf 'status::review\n' ;;
    Done) printf 'status::done\n' ;;
    Blocked) printf 'status::blocked\n' ;;
    Skipped) printf 'status::skipped\n' ;;
    Backlog|"") printf '\n' ;;
    *)
      echo "platform_gitlab_label_from_status: unknown column '$1'" >&2
      return 64
      ;;
  esac
}

_gitlab_iid_from_url() {
  local url="${1:-}" tail
  tail="${url##*/}"
  printf '%s\n' "$tail"
}

_gitlab_issue_get() {
  local host="$1" encoded="$2" iid="$3"
  _gitlab_api "$host" "projects/${encoded}/issues/${iid}"
}

_gitlab_status_labels_csv() {
  # stdin = issue JSON. Prints comma-joined status::* labels (may be empty).
  jq -r '[.labels[]? | (if type == "object" then .name else . end) | select(startswith("status::"))] | join(",")'
}

platform_card_move_verify() {
  # $1 = issue iid, $2 = expected column (Ready/QA/…). Exactly one status::*
  # and it must project to $2. Used after every card-move write.
  local iid="$1" expected="$2"
  local cfg="" host="" full_path="" encoded raw labels status
  cfg=$(_gitlab_config_path) || {
    echo "platform_card_move_verify: GitLab config required" >&2
    return 65
  }
  host=$(_gitlab_host_from_config "$cfg")
  full_path=$(_gitlab_full_path_from_config "$cfg")
  encoded=$(_gitlab_project_api_id "$full_path")
  raw=$(_gitlab_issue_get "$host" "$encoded" "$iid") || return 1
  labels=$(printf '%s' "$raw" | _gitlab_status_labels_csv)
  case "$labels" in
    ""|*","*) return 1 ;;
  esac
  status=$(printf '%s' "[\"$labels\"]" | platform_gitlab_status_from_labels)
  [ "$status" = "$expected" ]
}

_gitlab_put_issue_labels() {
  local host="$1" encoded="$2" iid="$3" remove="$4" add="$5"
  if [ -n "$remove" ] && [ -n "$add" ]; then
    _gitlab_api "$host" --method PUT "projects/${encoded}/issues/${iid}" \
      -f "remove_labels=${remove}" -f "add_labels=${add}"
  elif [ -n "$remove" ]; then
    _gitlab_api "$host" --method PUT "projects/${encoded}/issues/${iid}" \
      -f "remove_labels=${remove}"
  elif [ -n "$add" ]; then
    _gitlab_api "$host" --method PUT "projects/${encoded}/issues/${iid}" \
      -f "add_labels=${add}"
  else
    return 0
  fi
}

_gitlab_with_cardmove_lock() {
  # Serialize same-issue moves on this machine (mkdir lock). Does not raise
  # the API retry count — it keeps two local writers from interleaving
  # verify/retry against gitlab-org/gitlab#207269.
  local encoded="$1" iid="$2"
  shift 2
  local lockdir="${TMPDIR:-/tmp}/ss-gitlab-move-${encoded}-${iid}"
  local i=0 holder missing=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    if [ -f "$lockdir/pid" ]; then
      missing=0
      holder=$(cat "$lockdir/pid" 2>/dev/null || true)
      if [ -z "$holder" ] || ! kill -0 "$holder" 2>/dev/null; then
        rm -rf "$lockdir"
        continue
      fi
    else
      # mkdir-to-pid write is not atomic; do not reap on the first miss.
      missing=$((missing + 1))
      if [ "$missing" -ge 5 ]; then
        rm -rf "$lockdir"
        missing=0
        continue
      fi
    fi
    i=$((i + 1))
    [ "$i" -lt 50 ] || {
      echo "platform_card_status_set: timed out waiting for move lock on #$iid" >&2
      return 1
    }
    sleep 0.1
  done
  printf '%s\n' "$$" > "$lockdir/pid"
  "$@"
  local rc=$?
  rm -f "$lockdir/pid"
  rmdir "$lockdir" 2>/dev/null || true
  return "$rc"
}

_gitlab_card_status_set_locked() {
  local host="$1" encoded="$2" iid="$3" target="$4" want="$5"
  local raw old
  raw=$(_gitlab_issue_get "$host" "$encoded" "$iid") || return 1
  old=$(printf '%s' "$raw" | _gitlab_status_labels_csv)
  _gitlab_put_issue_labels "$host" "$encoded" "$iid" "$old" "$want" >/dev/null || return 1
  if platform_card_move_verify "$iid" "$target"; then
    return 0
  fi
  # Retry once: explicit two-step remove-then-add (remove verified first).
  raw=$(_gitlab_issue_get "$host" "$encoded" "$iid") || return 1
  old=$(printf '%s' "$raw" | _gitlab_status_labels_csv)
  if [ -n "$old" ]; then
    _gitlab_put_issue_labels "$host" "$encoded" "$iid" "$old" "" >/dev/null || return 1
    raw=$(_gitlab_issue_get "$host" "$encoded" "$iid") || return 1
    old=$(printf '%s' "$raw" | _gitlab_status_labels_csv)
    if [ -n "$old" ]; then
      echo "platform_card_status_set: remove-step left status labels: $old" >&2
      return 1
    fi
  fi
  if [ -n "$want" ]; then
    _gitlab_put_issue_labels "$host" "$encoded" "$iid" "" "$want" >/dev/null || return 1
  fi
  platform_card_move_verify "$iid" "$target"
}

platform_card_status_set() {
  # Usage A: <iid> <target-column>
  # Usage B: --add <config-path> <issue-url> <target-column>
  # Combined remove+add PUT, then verify. On mismatch, one two-step retry
  # (remove confirmed, then add). Continued failure → non-zero.
  # See gitlab-org/gitlab#207269 — scoped labels are not atomic.
  local iid="" target="" cfg="" host="" full_path="" encoded want
  if [ "${1:-}" = "--add" ]; then
    shift
    cfg="${1:-}"
    iid=$(_gitlab_iid_from_url "${2:-}")
    target="${3:-}"
  else
    iid="${1:-}"
    target="${2:-}"
  fi
  [ -n "$iid" ] && [ -n "$target" ] || {
    echo "platform_card_status_set: usage: <iid> <column> | --add <config> <url> <column>" >&2
    return 64
  }
  cfg=$(_gitlab_config_path "$cfg") || {
    echo "platform_card_status_set: GitLab config required" >&2
    return 65
  }
  host=$(_gitlab_host_from_config "$cfg")
  full_path=$(_gitlab_full_path_from_config "$cfg")
  encoded=$(_gitlab_project_api_id "$full_path")
  want=$(platform_gitlab_label_from_status "$target") || return
  _gitlab_with_cardmove_lock "$encoded" "$iid" \
    _gitlab_card_status_set_locked "$host" "$encoded" "$iid" "$target" "$want"
}

# ───────────────────────────── Group E — Claim / release mutex ─────────────────────────────

_gitlab_user_id() {
  local host="$1" username="$2" id
  id=$(_gitlab_api "$host" "users?username=${username}" 2>/dev/null | jq -r 'if type=="array" then .[0].id // empty else .id // empty end')
  [ -n "$id" ] && printf '%s\n' "$id"
}

platform_claim_issue() {
  # $1 = issue iid, $2 = bot username.
  # GitLab assignee PUT replaces the whole set. Refuse (exit 1) if any
  # assignee other than the claiming bot is already present. Always send a
  # single-element assignee_ids[] — the comma-joined form is broken
  # (gitlab-org/gitlab-foss#59302).
  local iid="$1" bot="$2"
  local cfg="" host="" full_path="" encoded raw others bot_id
  cfg=$(_gitlab_config_path) || {
    echo "platform_claim_issue: GitLab config required" >&2
    return 65
  }
  host=$(_gitlab_host_from_config "$cfg")
  full_path=$(_gitlab_full_path_from_config "$cfg")
  encoded=$(_gitlab_project_api_id "$full_path")
  raw=$(_gitlab_issue_get "$host" "$encoded" "$iid") || return 1
  others=$(printf '%s' "$raw" | jq -r --arg bot "$bot" \
    '[.assignees[]? | .username | select(. != $bot)] | length')
  if [ "${others:-0}" -gt 0 ]; then
    echo "platform_claim_issue: already claimed by a non-bot assignee" >&2
    return 1
  fi
  # REST `-F assignee_ids[]=<id>` is HTTP 400 on work_items-backed issues
  # (glab drops the field). `glab issue update --assignee` is the spec's
  # allowed single-assignee wrapper and works for both issues and work_items.
  _gitlab_glab "$host" "$full_path" issue update "$iid" --assignee "$bot" >/dev/null
}

platform_release_issue() {
  # $1 = issue iid, $2 = bot username (unused for the write; GitLab replace-
  # semantics clear the whole assignee set).
  #
  # Open Judgment Call 3 (accepted, not engineered around): unassign uses
  # assignee_ids=0, which evicts every assignee, including a human who added
  # themselves as a co-assignee while the bot held the claim. Same risk
  # class as GitHub's --remove-assignee on a multi-assignee issue.
  local iid="$1"
  local cfg="" host="" full_path="" encoded
  cfg=$(_gitlab_config_path) || {
    echo "platform_release_issue: GitLab config required" >&2
    return 65
  }
  host=$(_gitlab_host_from_config "$cfg")
  full_path=$(_gitlab_full_path_from_config "$cfg")
  encoded=$(_gitlab_project_api_id "$full_path")
  # assignee_ids=0 is GitLab's documented "unassign all" (empty []= is 400).
  _gitlab_api "$host" --method PUT "projects/${encoded}/issues/${iid}" \
    -F "assignee_ids=0" >/dev/null
}
# ───────────────────────────── Group F — Issue CRUD ─────────────────────────────

_gitlab_ctx() {
  # Sets _g_cfg _g_host _g_path _g_enc from PLATFORM_CONFIG_PATH / optional $1.
  _g_cfg=$(_gitlab_config_path "${1:-}") || {
    echo "gitlab platform: config required" >&2
    return 65
  }
  _g_host=$(_gitlab_host_from_config "$_g_cfg")
  _g_path=$(_gitlab_full_path_from_config "$_g_cfg")
  _g_enc=$(_gitlab_project_api_id "$_g_path")
}

platform_issue_create() {
  # $1 = title, $2 = body-file. Echoes the created issue URL.
  local title="$1" body_file="$2" out
  _gitlab_ctx || return
  out=$(_gitlab_glab "$_g_host" "$_g_path" issue create --title "$title" \
    --description "$(cat "$body_file")" --yes) || return 1
  printf '%s\n' "$out" | awk '/https?:\/\//{print; exit}'
}

platform_issue_view() {
  # $1 = iid. Normalized {number,title,body,labels:string[],state:OPEN|CLOSED}.
  # Exits: 0 found, 44 not-found, 69 auth, 70 other/malformed.
  local iid="$1" raw err errfile
  _gitlab_ctx || return 70
  errfile=$(mktemp)
  if ! raw=$(_gitlab_api "$_g_host" "projects/${_g_enc}/issues/${iid}" 2>"$errfile"); then
    err=$(cat "$errfile" 2>/dev/null || true)
    rm -f "$errfile"
    printf '%s\n' "$err" >&2
    case "$err" in
      *"404"*|*"Not Found"*) return 44 ;;
      *"401"*|*"403"*|*"Unauthorized"*|*"Forbidden"*) return 69 ;;
      *) return 70 ;;
    esac
  fi
  rm -f "$errfile"
  printf '%s' "$raw" | jq -ce '
    if type == "object" and (.iid | type == "number") then
      {
        number: .iid,
        title: (.title // ""),
        body: (.description // ""),
        labels: [(.labels // [])[] | (if type == "object" then .name else . end)],
        state: (if .state == "closed" then "CLOSED" else "OPEN" end)
      }
    else error("invalid issue shape")
    end
  ' || return 70
}

platform_issue_comment() {
  local iid="$1" body="$2"
  _gitlab_ctx || return
  _gitlab_glab "$_g_host" "$_g_path" issue note "$iid" -m "$body"
}

platform_issue_close() {
  local iid="$1" comment="${2:-}"
  _gitlab_ctx || return
  if [ -n "$comment" ]; then
    _gitlab_glab "$_g_host" "$_g_path" issue note "$iid" -m "$comment" >/dev/null || true
  fi
  _gitlab_glab "$_g_host" "$_g_path" issue close "$iid"
}

platform_issue_edit_labels() {
  # Translates GitHub-shaped --add-label / --remove-label to glab --label / --unlabel.
  local iid="$1"
  shift
  local add="" rem="" extra=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --add-label) add="${add:+$add,}$2"; shift 2 ;;
      --remove-label) rem="${rem:+$rem,}$2"; shift 2 ;;
      --label) add="${add:+$add,}$2"; shift 2 ;;
      --unlabel) rem="${rem:+$rem,}$2"; shift 2 ;;
      *) extra="$extra $1"; shift ;;
    esac
  done
  _gitlab_ctx || return
  if [ -n "$add" ] && [ -n "$rem" ]; then
    _gitlab_glab "$_g_host" "$_g_path" issue update "$iid" --label "$add" --unlabel "$rem"
  elif [ -n "$add" ]; then
    _gitlab_glab "$_g_host" "$_g_path" issue update "$iid" --label "$add"
  elif [ -n "$rem" ]; then
    _gitlab_glab "$_g_host" "$_g_path" issue update "$iid" --unlabel "$rem"
  else
    return 0
  fi
}

# ───────────────────────────── Group G — MR CRUD ─────────────────────────────

platform_mr_create_draft() {
  # GitHub-shaped flags (--base --head --title --body-file/--body) plus glab-native.
  # Always --draft, never --wip (removed in GitLab 14.8).
  local base="" head="" title="" body_file="" body="" extra=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --base|--target-branch) base="$2"; shift 2 ;;
      --head|--source-branch) head="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      --body-file|--description-file) body_file="$2"; shift 2 ;;
      --body) body="$2"; shift 2 ;;
      --draft) shift ;;
      *) extra="$extra $1"; shift ;;
    esac
  done
  _gitlab_ctx || return
  if [ -n "$body_file" ]; then
    body=$(cat "$body_file")
  fi
  _gitlab_glab "$_g_host" "$_g_path" mr create --draft \
    --source-branch "$head" --target-branch "$base" \
    --title "$title" --description "${body:-.}" --yes --no-editor
}

platform_mr_mark_ready() {
  local mr="$1"
  _gitlab_ctx || return
  _gitlab_glab "$_g_host" "$_g_path" mr update "$mr" --ready
}

platform_mr_comment() {
  local mr="$1" body="$2"
  _gitlab_ctx || return
  _gitlab_glab "$_g_host" "$_g_path" mr note create "$mr" -m "$body"
}

platform_mr_merge_squash() {
  local mr="$1"
  _gitlab_ctx || return
  _gitlab_glab "$_g_host" "$_g_path" mr merge "$mr" --squash --remove-source-branch --yes
}

platform_mr_view() {
  local mr="$1"
  shift
  _gitlab_ctx || return
  _gitlab_api "$_g_host" "projects/${_g_enc}/merge_requests/${mr}"
}

platform_mr_list_by_branch() {
  local branch="$1"
  case "$branch" in
    head:*) branch="${branch#head:}" ;;
  esac
  _gitlab_ctx || return
  _gitlab_api "$_g_host" "projects/${_g_enc}/merge_requests?source_branch=${branch}"
}
# ───────────────────────────── Group H — Review-thread resolve/create ─────────────────────────────
#
# Open Judgment Call 5 (resolved): GitLab Block signal = a non-resolvable
# top-level MR note whose body has no [QA]/[Review]/lane prefix and whose
# author is not notifications.bot_identity. Resolvable discussions are Gate 1
# review threads (platform_thread_list_unresolved / platform_thread_resolve).
# Do not treat resolvable-but-human notes as Block — those stay in Gate 1.

platform_thread_list_unresolved() {
  # $1 = owner/repo (full_path), $2 = MR iid.
  # Emits GraphQL discussion IDs that are unresolved AND notes[0].resolvable.
  local repo="${1:-}" mr="$2"
  _gitlab_ctx || return
  [ -n "$repo" ] || repo="$_g_path"
  _gitlab_api "$_g_host" graphql -f query='
    query($path: ID!, $iid: String!) {
      project(fullPath: $path) {
        mergeRequest(iid: $iid) {
          discussions { nodes { id resolved notes { nodes { resolvable } } } }
        }
      }
    }' \
    -f "path=${repo}" -f "iid=${mr}" \
    | jq -r '.data.project.mergeRequest.discussions.nodes[]
      | select(.resolved == false and .notes.nodes[0].resolvable == true)
      | .id'
}

platform_thread_resolve() {
  # $1 = GraphQL discussion ID. discussionToggleResolve is idempotent.
  local thread_id="$1"
  _gitlab_ctx || return
  _gitlab_api "$_g_host" graphql -f query='
    mutation($id: DiscussionID!) {
      discussionToggleResolve(input: {id: $id, resolve: true}) {
        discussion { id resolved }
      }
    }' -f "id=${thread_id}"
}

platform_thread_create() {
  # Create a line-level MR discussion.
  # $1 = owner/repo, $2 = MR iid, $3 = commit SHA (used as head_sha fallback),
  # $4 = path, $5 = line, $6 = body.
  #
  # Spike finding (gitlab.com, 2026-08-15): JSON --input with a position
  # object returns 400 "line_code can't be blank". Form fields work:
  #   POST projects/:id/merge_requests/:iid/discussions
  #   -f body=... -f position[base_sha]= -f position[start_sha]=
  #   -f position[head_sha]= -f position[old_path]= -f position[new_path]=
  #   -f position[position_type]=text -F position[new_line]=N
  # SHAs come from merge_request.diff_refs (base_sha/start_sha/head_sha).
  local repo="${1:-}" mr="$2" commit="$3" path="$4" line="$5" body="$6"
  local refs base start head enc
  _gitlab_ctx || return
  [ -n "$repo" ] || repo="$_g_path"
  enc=$(_gitlab_project_api_id "$repo")
  refs=$(_gitlab_api "$_g_host" "projects/${enc}/merge_requests/${mr}") || return 1
  base=$(printf '%s' "$refs" | jq -r '.diff_refs.base_sha // empty')
  start=$(printf '%s' "$refs" | jq -r '.diff_refs.start_sha // empty')
  head=$(printf '%s' "$refs" | jq -r '.diff_refs.head_sha // empty')
  [ -n "$head" ] || head="$commit"
  _gitlab_api "$_g_host" --method POST "projects/${enc}/merge_requests/${mr}/discussions" \
    -f "body=${body}" \
    -f "position[base_sha]=${base}" \
    -f "position[start_sha]=${start}" \
    -f "position[head_sha]=${head}" \
    -f "position[old_path]=${path}" \
    -f "position[new_path]=${path}" \
    -f "position[position_type]=text" \
    -F "position[new_line]=${line}"
}
# ───────────────────────────── Group I — Production/CI detection ─────────────────────────────

_gitlab_ci_has_prod_job() {
  # $1 = file path. Exit 0 if a job has environment: plus a main-branch rule.
  local f="$1"
  [ -f "$f" ] || return 1
  grep -q 'environment:' "$f" || return 1
  grep -q 'CI_COMMIT_BRANCH' "$f" || return 1
  grep -E '==[[:space:]]*["'"'"']main["'"'"']|CI_DEFAULT_BRANCH' "$f" >/dev/null
}

platform_detect_production_ci() {
  local root="${1:-.}"
  if [ -f "$root/vercel.json" ] || [ -f "$root/netlify.toml" ]; then
    return 0
  fi
  local f="$root/.gitlab-ci.yml"
  [ -f "$f" ] || return 1
  if _gitlab_ci_has_prod_job "$f"; then
    return 0
  fi
  # One level of local include: (paths after `-` or `- local:`).
  local inc i
  inc=$(sed -n '/^[[:space:]]*include:/,/^[^[:space:]#]/p' "$f" \
    | sed -n 's/^[[:space:]]*-[[:space:]]*//p' \
    | sed 's/^local:[[:space:]]*//' \
    | tr -d "'\"" \
    | grep -v '^https\?:' \
    | grep -v '^$' || true)
  [ -n "$inc" ] || return 1
  for i in $inc; do
    case "$i" in
      /*) _gitlab_ci_has_prod_job "$i" && return 0 ;;
      *) _gitlab_ci_has_prod_job "$root/$i" && return 0 ;;
    esac
  done
  return 1
}

platform_detect_branch_protection() {
  local base="${1:-main}"
  _gitlab_ctx || return 1
  _gitlab_api "$_g_host" "projects/${_g_enc}/protected_branches/${base}" >/dev/null 2>&1
}

# ───────────────────────────── Group J — Raw-URL screenshot embed ─────────────────────────────

platform_raw_file_url() {
  # $1 = owner/repo, $2 = branch, $3 = path. Host from config, never hardcoded.
  local repo="$1" branch="$2" path="$3" host cfg
  cfg=$(_gitlab_config_path) || true
  host=$(_gitlab_host_from_config "$cfg")
  [ -n "$host" ] || host="gitlab.com"
  printf 'https://%s/%s/-/raw/%s/%s\n' "$host" "$repo" "$branch" "$path"
}
# ───────────────────────────── Group K — Repo/label/board bootstrap ─────────────────────────────

platform_repo_create() {
  local tmp="${TMPDIR:-/tmp}"
  ( cd "$tmp" && glab repo create "$@" )
}

platform_label_ensure() {
  # $1 = name, $2 = color (hex without #), $3 = description.
  # List first; create only if missing. Do not suppress-and-ignore.
  local name="$1" color="${2:-428BCA}" description="${3:-}"
  _gitlab_ctx || return 1
  local labels
  labels=$(_gitlab_api "$_g_host" "projects/${_g_enc}/labels?per_page=100") || return 1
  if printf '%s' "$labels" | jq -e --arg n "$name" '.[] | select(.name == $n)' >/dev/null; then
    return 0
  fi
  _gitlab_api "$_g_host" --method POST "projects/${_g_enc}/labels" \
    -f "name=${name}" -f "color=#${color}" -f "description=${description}" >/dev/null
}

_gitlab_board_ui_steps() {
  cat >&2 <<'EOF'
GitLab board API failed. Create the board by hand:
  1. Open the project → Plan → Issue boards → New board
  2. Name it SuperSaiyan
  3. Add one list per status label, in order:
     status::ready, status::building (full only), status::qa,
     status::review, status::done, status::blocked, status::skipped
  4. Re-run onboard and set project.board_id to that board's id
     (the number in the board URL), or leave board_id null.
EOF
}

platform_board_ensure() {
  # Ensure status::* labels + an Issue Board with one list per column.
  # Usage: platform_board_ensure [config-path]
  # Prints the board id, or "null" on API failure (does not hard-fail).
  # GITLAB_BOARD_ENSURE_FAIL=1 forces the graceful-null path (tests).
  local cfg variant col label color
  cfg=$(_gitlab_config_path "${1:-}") || {
    echo "platform_board_ensure: readable GitLab config path required" >&2
    echo "null"
    return 0
  }
  export PLATFORM_CONFIG_PATH="$cfg"
  _gitlab_ctx || {
    _gitlab_board_ui_steps
    echo "null"
    return 0
  }
  variant=$(jq -r '.variant // "full"' "$cfg")

  if [ "${GITLAB_BOARD_ENSURE_FAIL:-}" = "1" ]; then
    _gitlab_board_ui_steps
    echo "null"
    return 0
  fi

  for col in Ready Building QA Review Done Blocked Skipped; do
    if [ "$variant" = "qa-only" ] && [ "$col" = "Building" ]; then
      continue
    fi
    label=$(platform_gitlab_label_from_status "$col")
    [ -n "$label" ] || continue
    case "$col" in
      Ready) color="0E8A16" ;;
      Building) color="1D76DB" ;;
      QA) color="FBCA04" ;;
      Review) color="5319E7" ;;
      Done) color="0E8A16" ;;
      Blocked) color="B60205" ;;
      Skipped) color="C5DEF5" ;;
      *) color="428BCA" ;;
    esac
    if ! platform_label_ensure "$label" "$color" "super-board column $col"; then
      _gitlab_board_ui_steps
      echo "null"
      return 0
    fi
  done

  local boards board_id name="SuperSaiyan" labels label_id list_ids existing
  boards=$(_gitlab_api "$_g_host" "projects/${_g_enc}/boards") || {
    _gitlab_board_ui_steps
    echo "null"
    return 0
  }
  board_id=$(printf '%s' "$boards" | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)
  if [ -z "$board_id" ] || [ "$board_id" = "null" ]; then
    board_id=$(_gitlab_api "$_g_host" --method POST "projects/${_g_enc}/boards" \
      -f "name=${name}" | jq -r '.id // empty') || true
  fi
  if [ -z "$board_id" ] || [ "$board_id" = "null" ]; then
    _gitlab_board_ui_steps
    echo "null"
    return 0
  fi

  labels=$(_gitlab_api "$_g_host" "projects/${_g_enc}/labels?per_page=100") || {
    _gitlab_board_ui_steps
    echo "null"
    return 0
  }
  existing=$(_gitlab_api "$_g_host" "projects/${_g_enc}/boards/${board_id}/lists") || existing="[]"
  for col in Ready Building QA Review Done Blocked Skipped; do
    if [ "$variant" = "qa-only" ] && [ "$col" = "Building" ]; then
      continue
    fi
    label=$(platform_gitlab_label_from_status "$col")
    [ -n "$label" ] || continue
    label_id=$(printf '%s' "$labels" | jq -r --arg n "$label" '.[] | select(.name == $n) | .id' | head -1)
    [ -n "$label_id" ] && [ "$label_id" != "null" ] || continue
    if printf '%s' "$existing" | jq -e --argjson id "$label_id" \
      '.[] | select(.label.id == $id)' >/dev/null 2>&1; then
      continue
    fi
    if ! _gitlab_api "$_g_host" --method POST "projects/${_g_enc}/boards/${board_id}/lists" \
      -F "label_id=${label_id}" >/dev/null; then
      _gitlab_board_ui_steps
      echo "null"
      return 0
    fi
  done

  # Persist board_id when the config is writable.
  if [ -w "$cfg" ]; then
    local tmp
    tmp=$(mktemp)
    jq --argjson id "$board_id" '.project.board_id = $id' "$cfg" > "$tmp" && mv "$tmp" "$cfg" || rm -f "$tmp"
  fi
  printf '%s\n' "$board_id"
}
