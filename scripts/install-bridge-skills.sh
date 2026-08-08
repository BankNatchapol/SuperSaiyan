#!/usr/bin/env bash
# install-bridge-skills.sh — copy SuperSaiyan bridge-only doc templates into an app repo.
#
# Skills are installed by the root installer (install.sh), which is plugin-aware
# (it skips local .claude/skills/ copies when the supersaiyan Claude Code plugin
# is installed, to avoid duplicate skill definitions). This script only copies
# the doc assets install.sh does not own.
#
# Usage:
#   cd /path/to/your-app
#   /path/to/SuperSaiyan/scripts/install-bridge-skills.sh
#
# Or pass the app repo explicitly:
#   /path/to/SuperSaiyan/scripts/install-bridge-skills.sh /path/to/your-app
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-$PWD}"

if [ ! -d "$TARGET" ]; then
  echo "Target not found: $TARGET" >&2
  exit 66
fi

TARGET="$(cd "$TARGET" && pwd)"

echo "Target app: $TARGET"

mkdir -p "$TARGET/docs/templates" "$TARGET/docs/superpowers/tasks"

same_path() {
  local left="$1" right="$2"
  [ "$(cd "$(dirname "$left")" && pwd)/$(basename "$left")" = \
    "$(cd "$(dirname "$right")" && pwd)/$(basename "$right")" ]
}

echo "→ doc templates"
src="$REPO_ROOT/docs/templates/issue.md"
dest="$TARGET/docs/templates/issue.md"
if [ -f "$src" ]; then
  if same_path "$src" "$dest"; then
    echo "    · docs/templates/issue.md already at target"
  else
    cp "$src" "$dest"
    echo "    ✓ docs/templates/issue.md"
  fi
fi

src="$REPO_ROOT/docs/superpowers/tasks/README.md"
dest="$TARGET/docs/superpowers/tasks/README.md"
if [ -f "$src" ]; then
  if same_path "$src" "$dest"; then
    echo "    · docs/superpowers/tasks/README.md already at target"
  else
    cp "$src" "$dest"
    echo "    ✓ docs/superpowers/tasks/README.md"
  fi
fi

echo
echo "✓ Bridge doc templates installed."
echo "  Skills come from install.sh (or the supersaiyan plugin)."
echo "  After office-hours, run: Use refining-spec for <path-to-design-doc>"
echo "  After spec in repo, run: Use writing-board-tasks for docs/superpowers/specs/<feature-slug>-design.md"
echo "  After board tasks exist, run: /supersaiyan prepare <feature-slug>"
