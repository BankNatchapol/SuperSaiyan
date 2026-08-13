#!/usr/bin/env bash
# super-board-wave-plan.sh — compute the next workflow-backend wave from board state.
# Read-only: no gh writes, no locks. Mirrors run.md's lane-allocation model:
# base picks are one card per non-empty eligible column, downstream-first
# (Review → QA → Ready); remaining max_workers slots fill with extra cards
# from the most backlogged column first. Cards with assignees are skipped
# (assignee is the cross-machine mutex, claimed by the orchestrator before
# launch). Extra Review cards beyond the base pick are gated behind
# config.human_approves_merge (merge-race guard).
#
# Usage:
#   super-board-wave-plan.sh --config <config.json> [--items <project-items.json>]
# Without --items, fetches live board state via platform_board_snapshot.
# Stdout: {"cards":[{"number":10,"status":"Review","title":"..."}]}
set -euo pipefail

CONFIG=""; ITEMS_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --items)  ITEMS_FILE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[ -n "$CONFIG" ] && [ -e "$CONFIG" ] || { echo "config not found: ${CONFIG:-<unset>}" >&2; exit 66; }

# Every temp file this script creates, cleaned up by ONE EXIT trap. A second `trap ... EXIT`
# replaces the first rather than adding to it, so each temp path gets its own variable here and
# the trap is installed exactly once — an earlier version set a trap per temp file and silently
# leaked the resolved config, which holds the board's project and notification settings.
#
# CONFIG_SOURCE is captured BEFORE the trap is installed: `resolve_config_extends` returns the
# INPUT path unchanged when there is no `extends`, so without this guard the cleanup would
# delete the user's actual committed config file.
CONFIG_SOURCE="$CONFIG"
RESOLVED_CONFIG=""
CONFIG_REF=""
cleanup_temps() {
  [ -n "$RESOLVED_CONFIG" ] && [ "$RESOLVED_CONFIG" != "$CONFIG_SOURCE" ] && rm -f "$RESOLVED_CONFIG"
  [ -n "$CONFIG_REF" ] && rm -f "$CONFIG_REF"
  return 0
}
trap cleanup_temps EXIT

# Resolve an optional `extends` link (see references/config-schema.json) before the config is
# read — only when $CONFIG is a real regular file. Test mode passes a process-substitution
# FIFO, which `resolve_config_extends` would consume with its own `.extends` check, leaving
# nothing for the read below (a FIFO can only be read once); skipping resolution there is safe
# because extends requires locating a sibling file by directory, which a synthetic test
# fixture never has anyway.
if [ -f "$CONFIG" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/config-resolve.sh"
  RESOLVED_CONFIG=$(resolve_config_extends "$CONFIG") || exit 66
  CONFIG="$RESOLVED_CONFIG"
fi

# Read the config ONCE — $CONFIG may be a process substitution (test mode),
# which is a FIFO and cannot be read twice.
CONFIG_JSON=$(cat "$CONFIG")
VARIANT=$(echo "$CONFIG_JSON" | jq -r '.variant')
MAX_WORKERS=$(echo "$CONFIG_JSON" | jq -r '.max_workers // 3')
GIT_PLATFORM=$(echo "$CONFIG_JSON" | jq -r '.git_platform // "github"')

# Platform contract: scripts/platforms/<name>.sh in this repo, .supersaiyan/bin/platforms/
# once installed (install.sh copies platforms/ alongside this script).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_FILE="$SCRIPT_DIR/platforms/${GIT_PLATFORM}.sh"
if [ ! -f "$PLATFORM_FILE" ]; then
  echo "platform contract not found: $PLATFORM_FILE (git_platform=${GIT_PLATFORM})" >&2
  exit 77
fi
# shellcheck disable=SC1090
source "$PLATFORM_FILE"

if [ -n "$ITEMS_FILE" ]; then
  ITEMS=$(cat "$ITEMS_FILE")
else
  # The input may be a one-shot process substitution, so persist the JSON that
  # was already read and pass a platform-neutral config reference. GitHub reads
  # owner/number from it; GitLab reads host/full_path/board_id.
  CONFIG_REF=$(mktemp)
  printf '%s\n' "$CONFIG_JSON" > "$CONFIG_REF"
  ITEMS=$(platform_board_snapshot "$CONFIG_REF")
fi

# Validate loudly: a typo (or missing key → literal "null") must not silently
# drop the QA column from selection and strand cards there.
case "$VARIANT" in
  full)    COLUMNS='["Review","QA","Ready"]' ;;
  qa-only) COLUMNS='["Review","Ready"]' ;;
  *) echo "invalid variant in config: ${VARIANT} (expected full|qa-only)" >&2; exit 65 ;;
esac

# Merge-race guard: concurrent auto-merges into the same base branch can
# race, so extra Review cards (beyond the base 1) are only eligible when a
# human approves merges (config.human_approves_merge = true).
ALLOW_REVIEW_EXTRAS=$(echo "$CONFIG_JSON" | jq -r '.human_approves_merge // false')

echo "$ITEMS" | jq --argjson cols "$COLUMNS" --argjson cap "$MAX_WORKERS" --argjson revx "$ALLOW_REVIEW_EXTRAS" '
  def dependency_numbers:
    [(.content.body // ""
      | scan("(?i)Depends on:[^\\n]*")
      | scan("#[0-9]+")
      | ltrimstr("#")
      | tonumber)];
  .items as $all
  | [ $cols[] as $col
    | { col: $col,
        cands: [ .items[]
                 | select(.status == $col and .content.type == "Issue")
                 | select((.content.assignees // []) | length == 0)
                 | . as $candidate
                 | select(
                     ($candidate | dependency_numbers | length) == 0
                     or all(($candidate | dependency_numbers)[];
                       . as $dep
                       | any($all[];
                           .content.type == "Issue"
                           and .content.repository == $candidate.content.repository
                           and .content.number == $dep
                           and .status == "Done")))
                 | { number: .content.number, status: $col, title: .content.title } ] }
  ] as $bycol
  | [ $bycol[] | select((.cands | length) > 0) | .cands[0] ] as $base
  | ( [ $bycol[]
        | select(.col != "Review" or $revx)
        | { backlog: ((.cands | length) - 1), rest: .cands[1:] }
        | select(.backlog > 0)
      ]
      | sort_by(-.backlog)
      | map(.rest)
      | add // []
    ) as $extras
  | { cards: (($base + $extras) | .[:$cap]) }'
