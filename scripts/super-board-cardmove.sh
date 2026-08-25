#!/usr/bin/env bash
# super-board-cardmove.sh — move one card to one column, through the platform contract.
#
# Thin CLI wrapper around `platform_card_status_set <issue> <column>`. It exists for the
# workflow backend: that orchestrator is a Claude session running shell one-liners
# (references/run-workflow.md), and it has no clean way to source platform-config.sh plus the
# right adapter inline. The bash dispatcher calls the platform function directly and does not
# need this file.
#
# Usage:
#   super-board-cardmove.sh <issue> <column> [--config <path>]
#
# Exit codes: 0 moved · 64 usage · 66 config/resolver not found · 69 missing jq / auth
#             · 77 unknown git_platform · anything else propagated from the adapter.

set -euo pipefail

ISSUE=""
COLUMN=""
CLI_CONFIG_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CLI_CONFIG_PATH="${2:-}"; shift 2 ;;
    --config=*) CLI_CONFIG_PATH="${1#--config=}"; shift ;;
    -h|--help)
      echo "Usage: $0 <issue> <column> [--config path]"
      exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 64 ;;
    *)
      if [ -z "$ISSUE" ]; then ISSUE="$1"
      elif [ -z "$COLUMN" ]; then COLUMN="$1"
      else echo "unexpected argument: $1" >&2; exit 64
      fi
      shift ;;
  esac
done

if [ -z "$ISSUE" ] || [ -z "$COLUMN" ]; then
  echo "Usage: $0 <issue> <column> [--config path]" >&2
  exit 64
fi
case "$ISSUE" in
  ''|*[!0-9]*) echo "issue must be a number: $ISSUE" >&2; exit 64 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required" >&2
  exit 69
fi

# Same loader sequence as scripts/tasks-to-issues.sh: resolve config → resolve platform →
# source that adapter. scripts/ in a toolkit checkout, .supersaiyan/bin/ once installed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_RESOLVER="$SCRIPT_DIR/platform-config.sh"
[ -f "$CONFIG_RESOLVER" ] || {
  echo "platform config resolver not found: $CONFIG_RESOLVER" >&2
  exit 66
}
# shellcheck disable=SC1090
source "$CONFIG_RESOLVER"
CONFIG_PATH=$(platform_config_resolve "$PWD" "$CLI_CONFIG_PATH") || exit $?
EFFECTIVE=$(platform_config_effective "$CONFIG_PATH") || exit 66
GIT_PLATFORM=$(platform_config_resolve_platform "$EFFECTIVE" "${GIT_PLATFORM:-}") || exit $?
PLATFORM_FILE="$SCRIPT_DIR/platforms/${GIT_PLATFORM}.sh"
if [ ! -f "$PLATFORM_FILE" ]; then
  echo "platform contract not found: $PLATFORM_FILE (git_platform=${GIT_PLATFORM})" >&2
  exit 77
fi
# shellcheck disable=SC1090
source "$PLATFORM_FILE"

export PLATFORM_CONFIG_PATH="$EFFECTIVE"
platform_auth_check board || {
  echo "${GIT_PLATFORM} platform authentication check failed (board access required)" >&2
  exit 69
}

platform_card_status_set "$ISSUE" "$COLUMN" >/dev/null
echo "#${ISSUE} → ${COLUMN}"
