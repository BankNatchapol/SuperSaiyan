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

# --- Agent instructions ---
# Same contract as install.sh: canonical block goes to AGENTS.md (read natively by Codex and
# Cursor), Claude Code gets a pointer. Source of truth is
# docs/templates/agent-blocks/gstack-paths.md — this script no longer embeds the prose.

# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/lib/md-block.sh"

AGENTS="$TARGET/AGENTS.md"
CLAUDE="$TARGET/CLAUDE.md"

if md_block_upsert "$AGENTS" gstack-paths "$REPO_ROOT/docs/templates/agent-blocks/gstack-paths.md"; then
  echo "    ✓ gstack paths block in AGENTS.md"
else
  echo "    ✗ could not write the gstack-paths block to AGENTS.md" >&2
  exit 1
fi

# Migrate the pre-fence section this script used to append directly to CLAUDE.md (backup first
# — a user may have hand-edited inside it).
LEGACY_BACKUP="$TARGET/docs/supersaiyan/migrations/CLAUDE.md-gstack-paths-$(date -u +%Y%m%dT%H%M%SZ).md"
if md_block_excise_legacy "$CLAUDE" "gstack artifact paths (SuperSaiyan)" "$LEGACY_BACKUP" 2>/dev/null; then
  echo "    ✓ moved legacy gstack section out of CLAUDE.md (backup: ${LEGACY_BACKUP#"$TARGET"/})"
fi

if [ ! -f "$CLAUDE" ]; then
  printf '@AGENTS.md\n' > "$CLAUDE"
  echo "    ✓ created CLAUDE.md as an @AGENTS.md pointer"
elif [ "$(grep -cvE '^\s*$' "$CLAUDE")" -eq 1 ] && grep -qE '^\s*@AGENTS\.md\s*$' "$CLAUDE"; then
  echo "    · CLAUDE.md already an @AGENTS.md pointer"
else
  POINTER_SRC="$(mktemp)"
  cat > "$POINTER_SRC" << 'EOF'
<!-- Claude Code does not read AGENTS.md natively; this import bridges it. SuperSaiyan's
     canonical agent instructions live in AGENTS.md, which Codex and Cursor read directly. -->
@AGENTS.md
EOF
  md_block_upsert "$CLAUDE" claude-pointer "$POINTER_SRC" \
    && echo "    ✓ @AGENTS.md pointer block in CLAUDE.md"
  rm -f "$POINTER_SRC"
fi

# The old docs/gstack/CLAUDE-snippet.md was an implementation detail of the previous
# materialize-then-append approach. Don't delete it (users may link to it), just say it's dead.
if [ -f "$TARGET/docs/gstack/CLAUDE-snippet.md" ]; then
  echo "    · docs/gstack/CLAUDE-snippet.md is obsolete (content now in AGENTS.md); safe to delete"
fi

echo "→ created docs/gstack/{designs,specs}/"
echo "→ created docs/superpowers/specs/ (pipeline)"
echo "→ created scripts/gstack-env.sh (optional GSTACK_HOME=.gstack)"
echo ""
echo "✓ Done. Before claude (optional):"
echo "  cd $TARGET && source scripts/gstack-env.sh"
echo ""
echo "Tell /office-hours: save a copy to docs/gstack/designs/<feature-slug>-design.md"
