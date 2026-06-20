#!/usr/bin/env bash
# install-bridge-skills.sh — copy SuperSaiyan bridge skills + doc templates into app repo.
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

mkdir -p "$TARGET/.claude/skills" "$TARGET/.claude/bin" \
  "$TARGET/docs/templates" "$TARGET/docs/superpowers/tasks"

same_path() {
  local left="$1" right="$2"
  [ "$(cd "$(dirname "$left")" && pwd)/$(basename "$left")" = \
    "$(cd "$(dirname "$right")" && pwd)/$(basename "$right")" ]
}

echo "→ skills"
for skill in writing-board-tasks refining-spec supersaiyan; do
  src="$REPO_ROOT/.claude/skills/$skill"
  dest="$TARGET/.claude/skills/$skill"
  if [ -d "$src" ]; then
    if same_path "$src" "$dest"; then
      echo "    · $skill already at target"
    else
      cp -R "$src" "$TARGET/.claude/skills/"
      if [ -f "$dest/scripts/prepare.sh" ]; then
        chmod +x "$dest/scripts/prepare.sh"
      fi
      echo "    ✓ $skill"
    fi
  fi
done

echo "→ command helpers"
src="$REPO_ROOT/scripts/tasks-to-issues.sh"
dest="$TARGET/.claude/bin/tasks-to-issues.sh"
if same_path "$src" "$dest"; then
  echo "    · .claude/bin/tasks-to-issues.sh already at target"
else
  cp "$src" "$dest"
  chmod +x "$dest"
  echo "    ✓ tasks-to-issues.sh"
fi

echo "→ doc templates"
for f in task-file.md issue.md; do
  src="$REPO_ROOT/docs/templates/$f"
  dest="$TARGET/docs/templates/$f"
  if [ -f "$src" ]; then
    if same_path "$src" "$dest"; then
      echo "    · docs/templates/$f already at target"
      continue
    fi
    cp "$src" "$dest"
    echo "    ✓ docs/templates/$f"
  fi
done

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
echo "✓ Bridge skills installed."
echo "  After office-hours, run: Use refining-spec for <path-to-design-doc>"
echo "  After spec in repo, run: Use writing-board-tasks for docs/superpowers/specs/<feature-slug>-design.md"
echo "  After board tasks exist, run: /supersaiyan prepare <feature-slug>"
