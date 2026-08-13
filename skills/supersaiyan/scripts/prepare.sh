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
# Delegated to platform_config_resolve (scripts/platform-config.sh), which owns the config
# root search order for every consumer: `.supersaiyan/` first, then the two legacy
# Claude-Code-branded roots. This replaces an inline root-probe loop that used to live here —
# one resolver beats three copies of the same precedence rules.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Installed layout first (new root, then pre-migration root), then dev-repo checkout.
CONFIG_RESOLVER=".supersaiyan/bin/platform-config.sh"
if [ ! -f "$CONFIG_RESOLVER" ]; then
  CONFIG_RESOLVER=".claude/bin/platform-config.sh"
fi
if [ ! -f "$CONFIG_RESOLVER" ]; then
  CONFIG_RESOLVER="$SCRIPT_DIR/../../../scripts/platform-config.sh"
fi
[ -f "$CONFIG_RESOLVER" ] || {
  echo "platform config resolver not found: $CONFIG_RESOLVER" >&2
  exit 66
}
# shellcheck disable=SC1090
source "$CONFIG_RESOLVER"
CONFIG_FILE=$(platform_config_resolve "$PWD" "${CONFIG_PATH:-}") || exit $?
if [ -z "$CONFIG_FILE" ]; then
  echo "NEEDS_ONBOARD"
  exit 78
fi
CONFIG_SLUG=$(basename "$CONFIG_FILE" .json)
EFFECTIVE=$(platform_config_effective "$CONFIG_FILE") || exit 66

PROJECT_OWNER=$(jq -r '.project.owner // "@me"' "$EFFECTIVE")
PROJECT_NUMBER=$(jq -r '.project.number' "$EFFECTIVE")
GIT_PLATFORM=$(platform_config_resolve_platform "$EFFECTIVE" "${GIT_PLATFORM:-}") || exit $?

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

  echo "CHECK_OK config=$CONFIG_SLUG project=$PROJECT_OWNER/$PROJECT_NUMBER"
  exit 0
fi

# ── Platform contract ────────────────────────────────────────────────────────

# Three-tier lookup, matching the config resolver above: new-installed layout, then
# pre-migration installed layout, then dev-repo checkout.
PLATFORM_FILE=".supersaiyan/bin/platforms/${GIT_PLATFORM}.sh"
if [ ! -f "$PLATFORM_FILE" ]; then
  PLATFORM_FILE=".claude/bin/platforms/${GIT_PLATFORM}.sh"
fi
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
platform_auth_check board || {
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
    lookup_rc=0
    platform_issue_view "$issue_num" >/dev/null 2>&1 || lookup_rc=$?
    case "$lookup_rc" in
      0) ;;
      44)
        TMP_WORK=$(mktemp)
        jq --arg s "$stem" 'del(.[$s])' "$MAP_FILE" > "$TMP_WORK"
        mv "$TMP_WORK" "$MAP_FILE"
        TMP_WORK=""
        REPAIRED=$((REPAIRED + 1))
        ;;
      69|70)
        echo "issue lookup failed for mapped issue #$issue_num (exit $lookup_rc); issue map left unchanged" >&2
        exit "$lookup_rc"
        ;;
      *)
        echo "issue lookup returned unsupported exit $lookup_rc for mapped issue #$issue_num; issue map left unchanged" >&2
        exit 70
        ;;
    esac
  done < <(jq -r 'keys[]' "$MAP_FILE" 2>/dev/null)
fi

# Create missing issues via tasks-to-issues.sh. Same three-tier idea as the backend-contract
# lookups in super-build-dispatch.sh/super-qa-dispatch.sh: new-installed layout first, then
# old-installed (pre-migration installs that haven't re-run install.sh yet).
if [ -z "${TASKS_TO_ISSUES:-}" ]; then
  if [ -x ".supersaiyan/bin/tasks-to-issues.sh" ]; then
    TASKS_TO_ISSUES=".supersaiyan/bin/tasks-to-issues.sh"
  else
    TASKS_TO_ISSUES=".claude/bin/tasks-to-issues.sh"
  fi
fi
[ -x "$TASKS_TO_ISSUES" ] || { echo "tasks-to-issues.sh not executable: $TASKS_TO_ISSUES" >&2; exit 66; }

if [ -n "$PHASE" ]; then
  "$TASKS_TO_ISSUES" "$TASK_DIR" --board --config "$CONFIG_FILE"
else
  "$TASKS_TO_ISSUES" "$SLUG" --board --config "$CONFIG_FILE"
fi

AFTER_COUNT=0
[ -f "$MAP_FILE" ] && AFTER_COUNT=$(jq 'length' "$MAP_FILE")
CREATED=$(( AFTER_COUNT - BEFORE_COUNT + REPAIRED ))

# Reconcile board: add mapped open issues that are absent or still in Backlog.
if [ "$AFTER_COUNT" -gt 0 ]; then
  items=$(platform_board_snapshot "$EFFECTIVE")
  while IFS=$(printf '\t') read -r issue_num issue_url; do
    [ -z "$issue_num" ] && continue
    existing_status=$(printf '%s' "$items" | jq -r --arg url "$issue_url" \
      '[.items[] | select(.content.url == $url)] | if length > 0 then .[0].status else "" end')
    if [ "$existing_status" = "Backlog" ] || [ -z "$existing_status" ]; then
      lookup_rc=0
      issue_json=$(platform_issue_view "$issue_num") || lookup_rc=$?
      case "$lookup_rc" in
        0) ;;
        44|69|70)
          echo "issue lookup failed during Ready reconciliation for #$issue_num (exit $lookup_rc)" >&2
          exit "$lookup_rc"
          ;;
        *)
          echo "issue lookup returned unsupported exit $lookup_rc during Ready reconciliation for #$issue_num" >&2
          exit 70
          ;;
      esac
      issue_state=$(printf '%s' "$issue_json" | jq -er '.state | strings') || {
        echo "issue #$issue_num returned a malformed normalized state during Ready reconciliation" >&2
        exit 70
      }
      if [ "$issue_state" = "OPEN" ]; then
        platform_card_status_set --add "$EFFECTIVE" "$issue_url" "Ready" >/dev/null
      elif [ "$issue_state" != "CLOSED" ]; then
        echo "issue #$issue_num returned unsupported state during Ready reconciliation: $issue_state" >&2
        exit 70
      fi
    fi
  done < <(jq -r 'to_entries[] | [(.value.number | tostring), .value.url] | @tsv' \
             "$MAP_FILE" 2>/dev/null)
fi

echo "created=$CREATED repaired=$REPAIRED"
