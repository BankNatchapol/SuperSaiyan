#!/usr/bin/env bash
# setup-gstack-artifacts-path.sh — store gstack design/spec copies in the repo.
#
# gstack upstream saves to ~/.gstack/projects/<slug>/ (not configurable per skill).
# This script sets SuperSaiyan conventions so artifacts also live under docs/gstack/
# in your app repo, and optionally relocates GSTACK_HOME to <repo>/.gstack.
#
# Usage:
#   /path/to/SuperSaiyan/scripts/setup-gstack-artifacts-path.sh /path/to/your-app
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "Usage: $0 /path/to/your-app" >&2
  exit 64
fi

if [ ! -d "$TARGET" ]; then
  echo "Target not found: $TARGET" >&2
  exit 66
fi

mkdir -p "$TARGET/docs/gstack/designs" \
         "$TARGET/docs/gstack/specs" \
         "$TARGET/docs/superpowers/specs" \
         "$TARGET/docs/superpowers/tasks"

# Optional: full gstack state inside repo (sessions, analytics, projects mirror)
mkdir -p "$TARGET/.gstack"

# --- .gitignore ---
GITIGNORE="$TARGET/.gitignore"
touch "$GITIGNORE"
add_ignore() {
  local line="$1"
  grep -qxF "$line" "$GITIGNORE" 2>/dev/null || echo "$line" >> "$GITIGNORE"
}
add_ignore ""
add_ignore "# gstack local state (optional GSTACK_HOME=.gstack)"
add_ignore ".gstack/sessions/"
add_ignore ".gstack/analytics/"
add_ignore ".gstack/config.yaml"

mkdir -p "$TARGET/scripts"

# --- env helper (source before claude) ---
cat > "$TARGET/scripts/gstack-env.sh" << 'EOF'
#!/usr/bin/env bash
# Source before `claude` to keep gstack state in this repo.
#   source scripts/gstack-env.sh
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GSTACK_HOME="$ROOT/.gstack"
export GSTACK_STATE_ROOT="$GSTACK_HOME"
echo "GSTACK_HOME=$GSTACK_HOME"
EOF
chmod +x "$TARGET/scripts/gstack-env.sh"

# --- CLAUDE.md snippet ---
SNIPPET_FILE="$TARGET/docs/gstack/CLAUDE-snippet.md"
cat > "$SNIPPET_FILE" << 'EOF'
## gstack artifact paths (SuperSaiyan)

When you run **gstack** `/office-hours` or `/spec` in this repo, **also save a copy** in the repo:

| Skill | Primary gstack path (default) | **Repo copy (required)** |
|-------|------------------------------|---------------------------|
| `/office-hours` | `~/.gstack/projects/<slug>/*-design-*.md` | `docs/gstack/designs/<feature-slug>-design.md` |
| `/spec` | `~/.gstack/projects/<slug>/specs/*.md` | `docs/gstack/specs/<feature-slug>-spec.md` |

**Super-board / superpowers pipeline** uses the refined spec at:

`docs/superpowers/specs/<feature-slug>-design.md`

After `/office-hours`, run **refining-spec** (or copy) so that file exists before **writing-board-tasks**.

Do not skip the repo copy — agents and git only see files under this repository.
EOF

CLAUDE="$TARGET/CLAUDE.md"
if [ ! -f "$CLAUDE" ]; then
  cat > "$CLAUDE" << 'EOF'
# Agent notes

EOF
fi
if ! grep -q "gstack artifact paths (SuperSaiyan)" "$CLAUDE" 2>/dev/null; then
  {
    echo ""
    cat "$SNIPPET_FILE"
  } >> "$CLAUDE"
  echo "    ✓ appended gstack paths to CLAUDE.md"
else
  echo "    · CLAUDE.md already has gstack paths section"
fi

echo "→ created docs/gstack/{designs,specs}/"
echo "→ created docs/superpowers/specs/ (pipeline)"
echo "→ created scripts/gstack-env.sh (optional GSTACK_HOME=.gstack)"
echo ""
echo "✓ Done. Before claude (optional):"
echo "  cd $TARGET && source scripts/gstack-env.sh"
echo ""
echo "Tell /office-hours: save a copy to docs/gstack/designs/<feature-slug>-design.md"
