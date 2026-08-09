#!/usr/bin/env bash
# prepare.sh — file GitHub issues from task files and reconcile board Ready column.
#
# Usage (run from the app repo root):
#   .claude/skills/supersaiyan/scripts/prepare.sh <slug> [--check-only] [--phase N]
#
# Exit codes:
#   0  — success
#   64 — bad arguments
#   65 — validation error (uncommitted/unpushed changes, missing or cyclic deps)
#   66 — file or directory not found
#   75 — multiple configs found with no active pointer
#   78 — no board config exists (run supersaiyan setup first)
set -euo pipefail

SLUG="${1:-}"
CHECK_ONLY=false
PHASE=""

shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=true; shift ;;
    --phase)      PHASE="${2:-}"; shift 2 ;;
    --phase=*)    PHASE="${1#--phase=}"; shift ;;
    *)            echo "Unknown flag: $1" >&2; exit 64 ;;
  esac
done

if [ -z "$SLUG" ]; then
  echo "Usage: $0 <slug> [--check-only] [--phase N]" >&2
  exit 64
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 69; }

TMP_DEP=""
TMP_WORK=""
cleanup() {
  [ -n "${TMP_DEP:-}" ] && rm -f "$TMP_DEP" 2>/dev/null
  [ -n "${TMP_WORK:-}" ] && rm -f "$TMP_WORK" 2>/dev/null
  true
}
trap cleanup EXIT

# ── Config discovery ───────────────────────────────────────────────────────────

CONFIGS_DIR=".claude/supersaiyan/configs"
if [ ! -d "$CONFIGS_DIR" ]; then
  echo "NEEDS_ONBOARD"
  exit 78
fi

config_count=0
first_config=""
while IFS= read -r f; do
  config_count=$((config_count + 1))
  [ "$config_count" -eq 1 ] && first_config="$f"
done < <(find "$CONFIGS_DIR" -maxdepth 1 -name "*.json" 2>/dev/null | sort)

if [ "$config_count" -eq 0 ]; then
  echo "NEEDS_ONBOARD"
  exit 78
fi

CONFIG_SLUG=""
if [ "$config_count" -eq 1 ]; then
  CONFIG_SLUG=$(basename "$first_config" .json)
else
  ACTIVE_FILE=".claude/supersaiyan/active"
  if [ ! -f "$ACTIVE_FILE" ]; then
    echo "Multiple board configs found. Write the active slug to $ACTIVE_FILE." >&2
    exit 75
  fi
  CONFIG_SLUG=$(tr -d '[:space:]' < "$ACTIVE_FILE")
fi

CONFIG_FILE="$CONFIGS_DIR/$CONFIG_SLUG.json"
[ -f "$CONFIG_FILE" ] || { echo "Config not found: $CONFIG_FILE" >&2; exit 66; }

PROJECT_OWNER=$(jq -r '.project.owner // "@me"' "$CONFIG_FILE")
PROJECT_NUMBER=$(jq -r '.project.number' "$CONFIG_FILE")
GIT_PLATFORM=$(jq -r '.git_platform // "github"' "$CONFIG_FILE")

# ── Resolve task directory ─────────────────────────────────────────────────────

if [ -n "$PHASE" ]; then
  TASK_DIR="docs/superpowers/projects/$SLUG/phase-$PHASE"
else
  TASK_DIR="docs/superpowers/tasks/$SLUG"
fi

# ── Frontmatter helper ─────────────────────────────────────────────────────────

get_fm() {
  local key="$1" file="$2"
  awk -v k="$key" '
    BEGIN { in_fm=0 }
    /^---$/ { in_fm++; next }
    in_fm==1 { if ($0 ~ "^" k ": *") { sub("^" k ": *",""); print; exit } }
    in_fm>=2  { exit }
  ' "$file"
}

# ── Check-only mode ────────────────────────────────────────────────────────────

if [ "$CHECK_ONLY" = true ]; then
  # Verify git state: no uncommitted changes and no unpushed commits
  if ! git diff --quiet HEAD 2>/dev/null; then
    echo "Uncommitted changes in working tree. Commit or stash before preparing." >&2
    exit 65
  fi
  if [ -n "$(git log '@{u}..HEAD' 2>/dev/null)" ]; then
    echo "Unpushed commits detected. Push before preparing." >&2
    exit 65
  fi

  [ -d "$TASK_DIR" ] || { echo "Task directory not found: $TASK_DIR" >&2; exit 66; }

  # Build stem→dep map: one "stem dep" line per task (dep is empty for null)
  TMP_DEP=$(mktemp)
  while IFS= read -r f; do
    [ "$(basename "$f")" = "README.md" ] && continue
    stem=$(basename "$f" .md)
    dep=$(get_fm "depends_on_task" "$f")
    [ "$dep" = "null" ] && dep=""
    printf '%s %s\n' "$stem" "$dep" >> "$TMP_DEP"
  done < <(find "$TASK_DIR" -maxdepth 1 -name "*.md" ! -name "README.md" 2>/dev/null | sort)

  # Check for missing dependencies
  while IFS=' ' read -r stem dep; do
    [ -z "$dep" ] && continue
    if ! grep -q "^${dep} " "$TMP_DEP"; then
      echo "Task $stem has unknown dependency: $dep" >&2
      exit 65
    fi
  done < "$TMP_DEP"

  # Check for cyclic dependencies using path-following from each node
  while IFS=' ' read -r start _; do
    current="$start"
    visited="$start"
    while true; do
      dep=$(grep "^${current} " "$TMP_DEP" | awk '{print $2}')
      [ -z "$dep" ] && break
      case " $visited " in
        *" $dep "*)
          echo "Cyclic dependency detected: $dep appears in chain from $start" >&2
          exit 65
          ;;
      esac
      visited="$visited $dep"
      current="$dep"
    done
  done < "$TMP_DEP"

  echo "CHECK_OK config=$CONFIG_SLUG"
  exit 0
fi

# ── Platform contract ────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_FILE=".claude/bin/platforms/${GIT_PLATFORM}.sh"
if [ ! -f "$PLATFORM_FILE" ]; then
  PLATFORM_FILE="$SCRIPT_DIR/../../../scripts/platforms/${GIT_PLATFORM}.sh"
fi
[ -f "$PLATFORM_FILE" ] || {
  echo "platform contract not found: $PLATFORM_FILE (git_platform=$GIT_PLATFORM)" >&2
  exit 77
}
# shellcheck disable=SC1090
source "$PLATFORM_FILE"
export PLATFORM_CONFIG_PATH="$CONFIG_FILE"
platform_auth_check project || {
  echo "${GIT_PLATFORM} platform authentication check failed (Project access required)" >&2
  exit 69
}

# ── Main run: repair → create → reconcile ─────────────────────────────────────

# Remote platform failures are intentionally fatal here. Reporting prepare as
# successful after issue creation or Ready reconciliation failed would leave the
# board partially queued and make a later run appear safely idle.
[ -d "$TASK_DIR" ] || { echo "Task directory not found: $TASK_DIR" >&2; exit 66; }

MAP_FILE="$TASK_DIR/.issue-map.json"

# Count issues before repair
BEFORE_COUNT=0
[ -f "$MAP_FILE" ] && BEFORE_COUNT=$(jq 'length' "$MAP_FILE")

# Repair stale issue mappings (mapped issue was deleted from the platform)
REPAIRED=0
if [ -f "$MAP_FILE" ] && [ "$BEFORE_COUNT" -gt 0 ]; then
  while IFS= read -r stem; do
    issue_num=$(jq -r --arg s "$stem" '.[$s].number' "$MAP_FILE")
    if ! platform_issue_view "$issue_num" >/dev/null 2>&1; then
      TMP_WORK=$(mktemp)
      jq --arg s "$stem" 'del(.[$s])' "$MAP_FILE" > "$TMP_WORK"
      mv "$TMP_WORK" "$MAP_FILE"
      TMP_WORK=""
      REPAIRED=$((REPAIRED + 1))
    fi
  done < <(jq -r 'keys[]' "$MAP_FILE" 2>/dev/null)
fi

# Create missing issues via tasks-to-issues.sh
TASKS_TO_ISSUES="${TASKS_TO_ISSUES:-.claude/bin/tasks-to-issues.sh}"
[ -x "$TASKS_TO_ISSUES" ] || { echo "tasks-to-issues.sh not executable: $TASKS_TO_ISSUES" >&2; exit 66; }

if [ -n "$PHASE" ]; then
  "$TASKS_TO_ISSUES" "$TASK_DIR" --config "$CONFIG_FILE"
else
  "$TASKS_TO_ISSUES" "$SLUG" --config "$CONFIG_FILE"
fi

AFTER_COUNT=0
[ -f "$MAP_FILE" ] && AFTER_COUNT=$(jq 'length' "$MAP_FILE")
CREATED=$(( AFTER_COUNT - BEFORE_COUNT + REPAIRED ))

# Reconcile board: add mapped open issues that are absent or still in Backlog.
if [ "$AFTER_COUNT" -gt 0 ]; then
  items=$(platform_board_snapshot "$CONFIG_FILE")
  while IFS=$(printf '\t') read -r issue_num issue_url; do
    [ -z "$issue_num" ] && continue
    existing_status=$(printf '%s' "$items" | jq -r --argjson n "$issue_num" \
      '[.items[] | select(.content.number == $n)] | if length > 0 then .[0].status else "" end')
    if [ "$existing_status" = "Backlog" ] || [ -z "$existing_status" ]; then
      issue_state=$(platform_issue_view "$issue_num" | jq -r '.state')
      if [ "$issue_state" = "OPEN" ]; then
        platform_card_status_set --add "$CONFIG_FILE" "$issue_url" "Ready" >/dev/null
      fi
    fi
  done < <(jq -r 'to_entries[] | [(.value.number | tostring), .value.url] | @tsv' \
             "$MAP_FILE" 2>/dev/null)
fi

echo "created=$CREATED repaired=$REPAIRED"
