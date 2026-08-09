#!/usr/bin/env bash
# tasks-to-issues.sh — create one platform issue per task markdown file.
#
# Run from your APP REPO root (git remote = target repo). Requires the selected
# platform CLI to be authenticated.
#
# Usage (run from the app repo):
#   tasks-to-issues.sh <feature-slug> [--config path] [--board] [--dry-run] [--force]
#   tasks-to-issues.sh <task-folder> [--config path] [--board] [--dry-run] [--force]
#   tasks-to-issues.sh <task-file.md> [--config path] [--board] [--dry-run] [--force]
#
# Env (optional):
#   GH_PROJECT_OWNER=@me   GH_PROJECT_NUMBER=3   → legacy context used with --board
#   PLATFORM_CONFIG_PATH=...                    → platform config path
#   TASKS_DIR=docs/superpowers/tasks
#
# A slug resolves to docs/superpowers/tasks/<feature-slug>/.
# A folder submits every *.md file except README.md.
# A file submits only that task.
# Writes or updates: <task-folder>/.issue-map.json
set -euo pipefail

SOURCE="${1:-}"
DRY_RUN=false
FORCE=false
BOARD=false
CLI_CONFIG_PATH=""

shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --board) BOARD=true; shift ;;
    --config)
      [ $# -ge 2 ] || { echo "--config requires a path" >&2; exit 64; }
      CLI_CONFIG_PATH="$2"; shift 2 ;;
    --config=*) CLI_CONFIG_PATH="${1#--config=}"; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 64 ;;
  esac
done

if [ -z "$SOURCE" ]; then
  echo "Usage: $0 <feature-slug|task-folder|task-file.md> [--config path] [--board] [--dry-run] [--force]" >&2
  exit 64
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq required" >&2
  exit 69
fi

# Platform contract: scripts/platforms/<name>.sh in this repo, .claude/bin/platforms/
# once installed (install.sh copies platforms/ alongside this script).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_RESOLVER="$SCRIPT_DIR/platform-config.sh"
[ -f "$CONFIG_RESOLVER" ] || {
  echo "platform config resolver not found: $CONFIG_RESOLVER" >&2
  exit 66
}
# shellcheck disable=SC1090
source "$CONFIG_RESOLVER"
CONFIG_PATH=$(platform_config_resolve "$PWD" "$CLI_CONFIG_PATH") || exit $?
GIT_PLATFORM=$(platform_config_resolve_platform "$CONFIG_PATH" "${GIT_PLATFORM:-}") || exit $?
PLATFORM_FILE="$SCRIPT_DIR/platforms/${GIT_PLATFORM}.sh"
if [ ! -f "$PLATFORM_FILE" ]; then
  echo "platform contract not found: $PLATFORM_FILE (git_platform=${GIT_PLATFORM})" >&2
  exit 77
fi
# shellcheck disable=SC1090
source "$PLATFORM_FILE"

export PLATFORM_CONFIG_PATH="$CONFIG_PATH"
if [ "$BOARD" = true ] && [ -z "$CONFIG_PATH" ] && [ -z "${GH_PROJECT_NUMBER:-}" ]; then
  echo "--board requires --config, PLATFORM_CONFIG_PATH, an onboarded config, or GH_PROJECT_NUMBER" >&2
  exit 64
fi
AUTH_MODE=issue
[ "$BOARD" = true ] && AUTH_MODE=board
platform_auth_check "$AUTH_MODE" || {
  echo "${GIT_PLATFORM} platform authentication check failed (${AUTH_MODE} access required)" >&2
  exit 69
}

TASKS_DIR="${TASKS_DIR:-docs/superpowers/tasks}"
SINGLE_FILE=""

if [ -f "$SOURCE" ]; then
  case "$SOURCE" in
    *.md) SINGLE_FILE="$SOURCE"; DIR=$(dirname "$SOURCE") ;;
    *) echo "Task file must end in .md: $SOURCE" >&2; exit 65 ;;
  esac
elif [ -d "$SOURCE" ]; then
  DIR="${SOURCE%/}"
else
  DIR="$TASKS_DIR/$SOURCE"
fi

if [ ! -d "$DIR" ]; then
  echo "Task folder not found: $DIR" >&2
  exit 66
fi

MAP_FILE="$DIR/.issue-map.json"

# --- frontmatter helpers ---
get_fm() {
  local key="$1" file="$2"
  awk -v k="$key" '
    BEGIN { in_fm=0 }
    /^---$/ { in_fm++; next }
    in_fm==1 && $0 ~ "^" k ": *" {
      sub("^" k ": *", "")
      print
      exit
    }
  ' "$file"
}

body_after_fm() {
  awk 'BEGIN { n=0 } /^---$/ { n++; next } n>=2 { print }' "$1"
}

lookup_issue() {
  local stem="$1"
  [ -f "$STEM_MAP" ] || return 1
  awk -F= -v s="$stem" '$1 == s { print $2; exit }' "$STEM_MAP"
}

remember_issue() {
  local stem="$1" num="$2"
  local tmp
  tmp=$(mktemp)
  awk -F= -v s="$stem" '$1 != s' "$STEM_MAP" > "$tmp"
  echo "$stem=$num" >> "$tmp"
  mv "$tmp" "$STEM_MAP"
}

write_map_entry() {
  local stem="$1" num="$2" url="$3" order="$4"
  local tmp
  tmp=$(mktemp)

  if [ -f "$MAP_FILE" ]; then
    jq --arg stem "$stem" \
       --argjson number "$num" \
       --arg url "$url" \
       --argjson order "$order" \
       '. + {($stem): {number: $number, url: $url, order: $order}}' \
       "$MAP_FILE" > "$tmp"
  else
    jq -n --arg stem "$stem" \
       --argjson number "$num" \
       --arg url "$url" \
       --argjson order "$order" \
       '{($stem): {number: $number, url: $url, order: $order}}' > "$tmp"
  fi

  mv "$tmp" "$MAP_FILE"
}

build_issue_body() {
  local file="$1" dep_issue="${2:-}" extra_notes="$3"
  local design plan plan_task skills task_rel

  design=$(get_fm design "$file")
  plan=$(get_fm plan "$file")
  plan_task=$(get_fm plan_task "$file")
  skills=$(get_fm skills "$file")
  task_rel="${file#${TASKS_DIR}/}"
  [ -z "$skills" ] && skills="superpowers:test-driven-development, superpowers:verification-before-completion"

  body_after_fm "$file"
  echo
  echo "## Notes"
  echo
  echo "- Task file: \`$task_rel\`"
  if [ -n "$design" ]; then
    echo "- Design: \`$design\`"
  fi
  if [ -n "$plan" ]; then
    echo "- Plan: \`$plan\`"
  fi
  if [ -n "$plan_task" ]; then
    echo "- Plan task: $plan_task"
  fi
  echo "- Skills: $skills"
  if [ -n "$dep_issue" ]; then
    echo "- Depends on: #$dep_issue"
  fi
  if [ -n "$extra_notes" ]; then
    echo "$extra_notes"
  fi
}

STEM_MAP=$(mktemp)
trap 'rm -f "$STEM_MAP"' EXIT
: > "$STEM_MAP"

if [ -f "$MAP_FILE" ]; then
  if ! jq -e 'type == "object"' "$MAP_FILE" >/dev/null 2>&1; then
    echo "Invalid issue map JSON: $MAP_FILE" >&2
    exit 65
  fi
  jq -r 'to_entries[] | "\(.key)=\(.value.number)"' "$MAP_FILE" > "$STEM_MAP"
fi

CREATED=0
SKIPPED=0

list_task_files() {
  if [ -n "$SINGLE_FILE" ]; then
    printf '%s\n' "$SINGLE_FILE"
  else
    find "$DIR" -maxdepth 1 -name '*.md' ! -name 'README.md' | sort
  fi
}

while IFS= read -r file; do
  [ -n "$file" ] || continue
  stem=$(basename "$file" .md)
  title=$(get_fm title "$file")
  order=$(get_fm order "$file")
  dep_task=$(get_fm depends_on_task "$file")

  if [ -z "$title" ]; then
    echo "Skip (no title in frontmatter): $file" >&2
    continue
  fi

  existing_issue=$(lookup_issue "$stem" || true)
  if [ -n "$existing_issue" ] && [ "$FORCE" != true ]; then
    echo "Skip #$existing_issue (already mapped): $file"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  dep_issue=""
  if [ -n "$dep_task" ] && [ "$dep_task" != "null" ]; then
    dep_issue=$(lookup_issue "$dep_task" || true)
    if [ -z "$dep_issue" ]; then
      echo "Warning: depends_on_task '$dep_task' not filed yet for $stem" >&2
    fi
  fi

  body_file=$(mktemp)
  build_issue_body "$file" "$dep_issue" "" > "$body_file"

  if [ "$DRY_RUN" = true ]; then
    echo "---"
    echo "Would create: $title"
    echo "  from: $file"
    if [ -n "$dep_issue" ]; then
      echo "  depends: #$dep_issue"
    fi
    head -20 "$body_file" | sed 's/^/  /'
    rm -f "$body_file"
    continue
  fi

  url=$(platform_issue_create "$title" "$body_file")
  rm -f "$body_file"
  num=$(echo "$url" | sed -E 's|.*/issues/([0-9]+)$|\1|')
  remember_issue "$stem" "$num"
  write_map_entry "$stem" "$num" "$url" "${order:-0}"
  CREATED=$((CREATED + 1))
  echo "Created #$num — $title"

  if [ "$BOARD" = true ]; then
    platform_card_status_set --add "$CONFIG_PATH" "$url" "Ready" >/dev/null
    echo "  → added to platform board in Ready"
  fi
done < <(list_task_files)

if [ "$DRY_RUN" = true ]; then
  echo
  echo "Dry run complete. Re-run without --dry-run to file issues."
  exit 0
fi

if [ "$CREATED" -eq 0 ] && [ "$SKIPPED" -eq 0 ]; then
  echo "No issues created." >&2
  exit 1
fi

echo
if [ "$CREATED" -gt 0 ]; then
  echo "Updated $MAP_FILE"
else
  echo "No new issues; all selected tasks were already mapped in $MAP_FILE"
fi
echo "Next:"
if [ "$BOARD" = true ]; then
  echo "  1. Open the configured board → confirm generated cards are in Ready"
else
  echo "  1. Issues were filed only; pass --board to enqueue them in Ready"
fi
echo "  2. Preferred: run /supersaiyan prepare <feature-slug> for reconciliation + lint"
echo "  3. Then run /super-board run <slug>"
