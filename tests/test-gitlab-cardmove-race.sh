#!/usr/bin/env bash
# test-gitlab-cardmove-race.sh — issue #8 / gitlab-integration task 08.
# Race-safe card-move (combined PUT + verify + one two-step retry) and
# claim/release (refuse if another human is assigned; single-element assignee_ids[]).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLAB_SH="$ROOT/scripts/platforms/gitlab.sh"
SANDBOX="${GITLAB_SANDBOX:-BankNatchapol/supersaiyan-gitlab-sandbox}"

FAIL=0
tfail() { echo "  FAIL: $1" >&2; FAIL=1; }

echo "checking gitlab.sh Groups D–E (card-move, claim/release)"

[ -f "$GITLAB_SH" ] || { echo "error: $GITLAB_SH not found" >&2; exit 1; }
bash -n "$GITLAB_SH" || tfail "bash -n reported a syntax error in gitlab.sh"
# shellcheck disable=SC1090
. "$GITLAB_SH"

# issue #41: leftover stub glab must not be treated as an authenticated live CLI.
# These greps inspect this file's live-gate / PATH restore / stub auth handler.
# They must not match themselves — patterns are the implemented forms, not the regex.
if ! grep -Eq '\[ "\$\{GITLAB_LIVE:-\}" = "1" \]' "$0"; then
  tfail "live sandbox is not gated on GITLAB_LIVE=1"
fi
if ! awk '/^ORIG_PATH=/{s=1} /PATH="\$ORIG_PATH"/{r=1} END{exit !(s && r)}' "$0"; then
  tfail "does not save and restore ORIG_PATH around stub glab"
fi
if ! grep -Eq '^[[:space:]]+auth\)' "$0"; then
  tfail "stub glab has no auth) handler (must exit 1 so leftover PATH cannot impersonate a login)"
fi

# ── 1. column ↔ status:: label ─────────────────────────────────────────────
if ! declare -f platform_gitlab_label_from_status >/dev/null 2>&1; then
  tfail "platform_gitlab_label_from_status is missing"
else
  [ "$(platform_gitlab_label_from_status Ready)" = "status::ready" ] \
    || tfail "Ready → $(platform_gitlab_label_from_status Ready) (want status::ready)"
  [ "$(platform_gitlab_label_from_status QA)" = "status::qa" ] \
    || tfail "QA → $(platform_gitlab_label_from_status QA) (want status::qa)"
  [ "$(platform_gitlab_label_from_status Backlog)" = "" ] \
    || tfail "Backlog must map to empty label (got $(platform_gitlab_label_from_status Backlog))"
fi

# ── 2. Stubbed glab ────────────────────────────────────────────────────────
TD=$(mktemp -d)
GLAB_LOG="$TD/glab.log"
STATE="$TD/state.json"
cat > "$STATE" <<'EOF'
{"iid":7,"labels":["status::ready"],"assignees":[]}
EOF
mkdir -p "$TD/bin"
cat > "$TD/bin/glab" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GLAB_LOG:?}"
# Drop flag pairs so $1 is the subcommand. Stub is never authenticated
# (issue #41): leftover PATH must not impersonate `glab auth status`.
while [ $# -gt 0 ]; do
  case "$1" in
    --hostname|--output|-R|--repo) shift 2 ;;
    --include|--paginate|-i) shift ;;
    *) break ;;
  esac
done
case "${1:-}" in
  auth)
    exit 1
    ;;
esac
method="GET"
path=""
add_labels=""
remove_labels=""
assignee_csv=""
while [ $# -gt 0 ]; do
  case "$1" in
    --hostname|--output|-R|--repo) shift 2 ;;
    --method|-X) method="$2"; shift 2 ;;
    --include|--paginate|-i) shift ;;
    -f|-F)
      kv="$2"; shift 2
      case "$kv" in
        add_labels=*) add_labels="${kv#add_labels=}" ;;
        remove_labels=*) remove_labels="${kv#remove_labels=}" ;;
        assignee_ids=*)
          echo "used comma-joined assignee_ids= form" >> "${GLAB_LOG}"
          ;;
        assignee_ids[]=*)
          assignee_csv="${kv#assignee_ids[]=}"
          ;;
      esac
      ;;
    -*) shift ;;
    *) path="$1"; shift ;;
  esac
done

case "$path" in
  users*)
    printf '%s\n' '{"id":99,"username":"bot-user"}'
    exit 0
    ;;
esac

# Issue GET/PUT
if [ ! -f "${STATE:?}" ]; then
  echo '{"iid":7,"labels":[],"assignees":[]}' > "$STATE"
fi
labels=$(jq -c '.labels' "$STATE")
assignees=$(jq -c '.assignees' "$STATE")

if [ "$method" = "PUT" ]; then
  if [ -n "$remove_labels" ]; then
    labels=$(printf '%s' "$labels" | jq -c --arg r "$remove_labels" '
      ($r | split(",")) as $rm
      | [.[] | select(. as $l | ($rm | index($l) | not))]
    ')
  fi
  if [ -n "$add_labels" ]; then
    labels=$(printf '%s' "$labels" | jq -c --arg a "$add_labels" '. + [$a]')
  fi
  if [ -f "${FORCE_DUP_FILE:-}" ]; then
    labels=$(printf '%s' "$labels" | jq -c '. + ["status::ready"]')
    rm -f "$FORCE_DUP_FILE"
  fi
  if [ "$assignee_csv" = "" ] && grep -q 'assignee_ids' "$GLAB_LOG" && [ "$method" = "PUT" ]; then
    :
  fi
  if printf '%s\n' "$*" | grep -q 'assignee_ids\[\]='; then
    :
  fi
  if [ -n "$assignee_csv" ]; then
    if [ "$assignee_csv" = "" ]; then
      assignees='[]'
    else
      assignees=$(jq -nc --arg u "${ASSIGNEE_USERNAME:-bot-user}" '[{"username":$u,"id":99}]')
    fi
  fi
  # Empty assignee_ids[]= (release)
  if grep -E -q 'assignee_ids\[\]=$|assignee_ids\[\]=""' "$GLAB_LOG" 2>/dev/null; then
    :
  fi
  jq --argjson l "$labels" --argjson a "$assignees" \
    '.labels=$l | .assignees=$a' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
fi

# Explicit release: PUT with empty assignee list encoded as assignee_ids[]=
if [ "$method" = "PUT" ] && grep -q 'assignee_ids' "${GLAB_LOG}"; then
  if awk 'END{print}' "$GLAB_LOG" | grep -q 'assignee_ids\[\]=$'; then
    jq '.assignees=[]' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  fi
fi

cat "$STATE"
EOF
chmod +x "$TD/bin/glab"

CFG="$TD/config.json"
cat > "$CFG" <<EOF
{
  "git_platform": "gitlab",
  "project": {"host": "gitlab.com", "full_path": "group/demo"}
}
EOF
export PLATFORM_CONFIG_PATH="$CFG"
ORIG_PATH="$PATH"
export PATH="$TD/bin:$PATH"
export GLAB_LOG STATE

# 2a. combined PUT then verify
if ! platform_card_status_set 7 QA >/dev/null 2>&1; then
  tfail "platform_card_status_set 7 QA failed on stub"
fi
if ! grep -q 'add_labels=status::qa' "$GLAB_LOG"; then
  tfail "card-move did not send add_labels=status::qa"
fi
if ! grep -q 'remove_labels=status::ready' "$GLAB_LOG"; then
  tfail "card-move did not send remove_labels=status::ready"
fi
if ! platform_card_move_verify 7 QA >/dev/null 2>&1; then
  tfail "platform_card_move_verify 7 QA failed after stub move"
fi
got=$(jq -r '.labels | map(select(startswith("status::"))) | join(",")' "$STATE")
[ "$got" = "status::qa" ] || tfail "after move labels=$got (want status::qa)"

# 2a2. Backlog = no status::* and must report success
jq '.labels=["status::qa"]' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
if ! platform_card_status_set 7 Backlog >/dev/null 2>&1; then
  tfail "platform_card_status_set 7 Backlog failed (empty status::* must verify)"
fi
got=$(jq -r '.labels | map(select(startswith("status::"))) | join(",")' "$STATE")
[ -z "$got" ] || tfail "after Backlog move labels=$got (want empty)"

# 2b. --add parses work_items URL
: > "$GLAB_LOG"
jq '.labels=["bug"]' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
if ! platform_card_status_set --add "$CFG" "https://gitlab.com/group/demo/-/work_items/7" Ready >/dev/null 2>&1; then
  tfail "platform_card_status_set --add failed"
fi
if ! grep -q 'add_labels=status::ready' "$GLAB_LOG"; then
  tfail "--add did not add status::ready"
fi

# 2b2. --add with CONFIG_PATH != EFFECTIVE must not verify against an empty project id
# shellcheck disable=SC1091
. "$ROOT/scripts/platform-config.sh"
EXT_ROOT="$TD/extends-root"
mkdir -p "$EXT_ROOT/configs"
cat > "$EXT_ROOT/configs/base.json" <<'EOF'
{
  "git_platform": "gitlab",
  "project": {"host": "gitlab.com", "full_path": "grp/realproj"}
}
EOF
printf '%s\n' '{"extends":"base"}' > "$EXT_ROOT/configs/overlay.json"
EXT_EFFECTIVE=$(platform_config_effective "$EXT_ROOT/configs/overlay.json") \
  || tfail "platform_config_effective failed on extends overlay"
: > "$GLAB_LOG"
jq '.labels=["bug"]' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
export PLATFORM_CONFIG_PATH="$EXT_ROOT/configs/overlay.json"
if ! platform_card_status_set --add "$EXT_EFFECTIVE" \
  "https://gitlab.com/grp/realproj/-/work_items/7" Ready >/dev/null 2>&1; then
  tfail "--add with overlay PLATFORM_CONFIG_PATH and effective --add config failed"
fi
if grep -q 'projects//issues' "$GLAB_LOG"; then
  tfail "--add verify used empty project id (projects//issues) under extends overlay"
fi
if ! grep -q 'projects/grp%2Frealproj/issues/7' "$GLAB_LOG"; then
  tfail "--add under extends did not hit projects/grp%2Frealproj/issues/7"
fi
export PLATFORM_CONFIG_PATH="$CFG"

# 2c. retry-once on verify mismatch (force a duplicate on the first PUT only)
jq '.labels=["status::ready"]' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
: > "$GLAB_LOG"
FORCE_DUP_FILE="$TD/force-dup"
export FORCE_DUP_FILE
: > "$FORCE_DUP_FILE"
if ! platform_card_status_set 7 Building >/dev/null 2>&1; then
  :
fi
status_n=$(jq '[.labels[] | select(startswith("status::"))] | length' "$STATE")
[ "$status_n" = "1" ] || tfail "after retry, status label count=$status_n (want 1)"
unset FORCE_DUP_FILE

# 2d. claim refuses when another human is assigned
jq '.assignees=[{"username":"BankNatchapol","id":1}] | .labels=["status::ready"]' "$STATE" \
  > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
: > "$GLAB_LOG"
if platform_claim_issue 7 bot-user >/dev/null 2>&1; then
  tfail "platform_claim_issue succeeded while a different human is assigned"
fi
if grep -q 'assignee_ids=1,2' "$GLAB_LOG"; then
  tfail "claim used comma-joined assignee_ids=1,2"
fi

# 2e. claim writes single-element assignee_ids[] when unassigned
jq '.assignees=[]' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
: > "$GLAB_LOG"
if ! platform_claim_issue 7 bot-user >/dev/null 2>&1; then
  tfail "platform_claim_issue failed on unassigned stub issue"
fi
if grep -q 'assignee_ids=1,2' "$GLAB_LOG" || grep -qE 'assignee_ids=[0-9]+,[0-9]+' "$GLAB_LOG"; then
  tfail "claim used comma-joined assignee_ids"
fi
if ! grep -q -- '--assignee' "$GLAB_LOG" && ! grep -q 'assignee_ids\[\]=' "$GLAB_LOG"; then
  tfail "claim did not use issue update --assignee (or assignee_ids[]=)"
fi

# 2f. release empties assignees (OJC 3 documented in source)
if ! grep -q 'Open Judgment Call 3' "$GITLAB_SH"; then
  tfail "platform_release_issue is missing the Open Judgment Call 3 comment"
fi
if ! platform_release_issue 7 bot-user >/dev/null 2>&1; then
  tfail "platform_release_issue failed"
fi

# 2g. concurrent writers leave exactly one status::* (task 08 AC, CI-safe)
jq '.labels=["status::ready"] | .assignees=[]' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
: > "$GLAB_LOG"
platform_card_status_set 7 Ready >/dev/null 2>&1 &
pid_a=$!
platform_card_status_set 7 Building >/dev/null 2>&1 &
pid_b=$!
wait "$pid_a" || true
wait "$pid_b" || true
status_n=$(jq '[.labels[] | select(startswith("status::"))] | length' "$STATE")
[ "$status_n" = "1" ] || tfail "stub concurrent move left status count=$status_n (want 1)"
got=$(jq -r '.labels | map(select(startswith("status::"))) | join(",")' "$STATE")
case "$got" in
  status::ready|status::building) ;;
  *) tfail "stub concurrent move landed on unexpected $got" ;;
esac

# ── 3. Live sandbox (opt-in; never run against leftover stub glab) ─────────
unset PLATFORM_CONFIG_PATH FORCE_DUP_STATUS
export PATH="$ORIG_PATH"

if [ "${GITLAB_LIVE:-}" = "1" ] && command -v glab >/dev/null 2>&1 && glab auth status >/dev/null 2>&1; then
  LIVE_CFG="$TD/live.json"
  cat > "$LIVE_CFG" <<EOF
{
  "git_platform": "gitlab",
  "project": {"host": "gitlab.com", "full_path": "$SANDBOX"}
}
EOF
  export PLATFORM_CONFIG_PATH="$LIVE_CFG"
  # Dedicated issue so we do not corrupt the #1/#2 seed cards permanently.
  live_url=$(glab issue create --repo "$SANDBOX" -t "cardmove-race #8" -d "ephemeral #8 test" 2>/dev/null | tail -1) || live_url=""
  live_iid="${live_url##*/}"
  if [ -z "$live_iid" ]; then
    tfail "could not create live sandbox issue for card-move"
  else
    if ! platform_card_status_set "$live_iid" Ready; then
      tfail "live platform_card_status_set $live_iid Ready failed"
    fi
    if ! platform_card_move_verify "$live_iid" Ready; then
      tfail "live verify Ready failed"
    fi
    if ! platform_card_status_set --add "$LIVE_CFG" "$live_url" QA; then
      tfail "live --add QA failed"
    fi
    if ! platform_card_move_verify "$live_iid" QA; then
      tfail "live verify QA after --add failed"
    fi
    # Concurrent writes
    platform_card_status_set "$live_iid" Ready >/tmp/cm-a.err 2>&1 &
    pid_a=$!
    platform_card_status_set "$live_iid" Building >/tmp/cm-b.err 2>&1 &
    pid_b=$!
    wait "$pid_a" || true
    wait "$pid_b" || true
    labels=$(glab api "projects/$(printf '%s' "$SANDBOX" | sed 's|/|%2F|g')/issues/${live_iid}" | jq -r '[.labels[] | select(startswith("status::"))] | join(",")')
    n=$(printf '%s' "$labels" | awk -F, '{print NF}')
    [ "$n" = "1" ] || tfail "concurrent move left status labels='$labels' (want exactly one)"
    case "$labels" in
      status::ready|status::building) ;;
      *) tfail "concurrent move landed on unexpected $labels" ;;
    esac
    # Claim refuse: assign the human, then claim as a different bot
    glab issue update --repo "$SANDBOX" "$live_iid" --assignee BankNatchapol >/dev/null 2>&1 \
      || tfail "could not pre-assign BankNatchapol on #$live_iid"
    if platform_claim_issue "$live_iid" "definitely-not-the-human-bot"; then
      tfail "live claim succeeded while BankNatchapol is assigned"
    fi
    # Release (clears assignees)
    if ! platform_release_issue "$live_iid" "BankNatchapol"; then
      tfail "live platform_release_issue failed"
    fi
    glab issue close --repo "$SANDBOX" "$live_iid" >/dev/null 2>&1 || true
  fi
  unset PLATFORM_CONFIG_PATH
else
  echo "  skip live sandbox checks (set GITLAB_LIVE=1 with glab auth to run)"
fi

rm -rf "$TD"

if [ "$FAIL" -ne 0 ]; then
  echo "error: gitlab card-move/claim contract check failed" >&2
  exit 1
fi

echo "  ✓ gitlab.sh Groups D–E: combined PUT+verify, --add, claim refuse, single assignee_ids[]"
echo "PASS: test-gitlab-cardmove-race.sh"
