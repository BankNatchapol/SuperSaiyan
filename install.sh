#!/usr/bin/env bash
# SuperSaiyan installer — copies skills + pipeline scripts into any repo.
#
# Usage:
#   ./install.sh                     # install into current directory
#   ./install.sh /path/to/app        # install into specific repo
#   ./install.sh --check             # verify install without changing files
#   ./install.sh --keep-local-skills # keep/copy .claude/skills/ locally even if the
#                                       Claude Code plugin is installed — required when any
#                                       board config uses worker_backend "codex-exec" or
#                                       "cursor-agent", since those CLIs have no plugin skill
#                                       cache and can only read files that physically exist in
#                                       the target repo. Re-run with this flag any time after
#                                       onboarding a non-Claude backend (see
#                                       references/onboard.md step 2 and references/backends.md).
#
# After install, open Claude Code in the target repo and run:
#   /supersaiyan setup

set -euo pipefail

SAIYAN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$PWD"
CHECK_ONLY=false
KEEP_LOCAL_SKILLS=false

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --keep-local-skills) KEEP_LOCAL_SKILLS=true ;;
    -*) echo "Unknown flag: $arg" >&2; exit 64 ;;
    *) TARGET="$arg" ;;
  esac
done

[ -d "$TARGET" ] || { echo "Target not found: $TARGET" >&2; exit 66; }
TARGET="$(cd "$TARGET" && pwd)"

PASS=0; FAIL=0

ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL + 1)); }

echo "SuperSaiyan installer"
echo "  Source:  $SAIYAN"
echo "  Target:  $TARGET"
echo

# ── Prerequisites ─────────────────────────────────────────────────────────────

echo "Prerequisites"

for cmd in git gh; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd found"
  else
    fail "$cmd is required but not installed"
  fi
done

if command -v claude >/dev/null 2>&1; then
  ok "claude found"
else
  fail "Claude Code is required — install from https://claude.ai/code"
fi

[ "$FAIL" -gt 0 ] && { echo; echo "Fix the errors above before installing." >&2; exit 1; }

[ "$CHECK_ONLY" = true ] && { echo; echo "Prerequisite check passed (--check mode, no files written)."; exit 0; }

# ── Skills ────────────────────────────────────────────────────────────────────

echo
echo "Installing skills"

mkdir -p "$TARGET/.claude/skills" "$TARGET/.supersaiyan/bin" "$TARGET/.supersaiyan/workflows"

same_path() {
  [ "$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")" = \
    "$(cd "$(dirname "$2")" 2>/dev/null && pwd)/$(basename "$2")" ]
}

PLUGIN_INSTALLED=false
if claude plugin list 2>/dev/null | grep -q "supersaiyan"; then
  PLUGIN_INSTALLED=true
  if [ "$KEEP_LOCAL_SKILLS" = true ]; then
    echo "  (supersaiyan plugin detected, but --keep-local-skills given — copying anyway for codex-exec/cursor-agent workers)"
  else
    echo "  (supersaiyan plugin detected — skipping local skill copies to avoid duplicates)"
  fi
fi

if [ "$PLUGIN_INSTALLED" = false ] || [ "$KEEP_LOCAL_SKILLS" = true ]; then
  for skill in supersaiyan super-board super-build super-qa super-review refining-spec writing-board-tasks test-driven-development verification-before-completion; do
    src="$SAIYAN/skills/$skill"
    dst="$TARGET/.claude/skills/$skill"
    if [ ! -d "$src" ]; then
      fail "$skill: source not found at $src"
      continue
    fi
    if same_path "$src" "$dst"; then
      ok "$skill (same path — skipped)"
      continue
    fi
    rm -rf "$dst"
    cp -RL "$src" "$dst"
    if [ -f "$dst/scripts/prepare.sh" ]; then chmod +x "$dst/scripts/prepare.sh"; fi
    ok "$skill"
  done
else
  # Plugin provides all skills. Remove any stale local copies that would cause duplicates.
  for skill in supersaiyan super-board super-build super-qa super-review refining-spec writing-board-tasks test-driven-development verification-before-completion; do
    dst="$TARGET/.claude/skills/$skill"
    if [ -d "$dst" ] && ! same_path "$SAIYAN/skills/$skill" "$dst"; then
      rm -rf "$dst"
      ok "$skill (removed local copy — plugin provides it)"
    else
      ok "$skill (plugin)"
    fi
  done
fi

# ── Skills for Codex + Cursor ──────────────────────────────────────────────────
# `.agents/skills/` is the vendor-neutral path in the Agent Skills open standard. Codex scans
# it from cwd up to the repo root, and Cursor picks it up anywhere in the repo — so one real
# copy gives both tools the same auto-discovery Claude Code gets from its plugin cache.
# SKILL.md is identical across all three (open standard), so nothing is per-tool here.
#
# Always populated, unlike .claude/skills/ above: Claude Code can fall back to the plugin
# cache, but Codex and Cursor have no cache and can only read files that exist in the repo.
echo
echo "Installing skills for Codex + Cursor (.agents/skills/)"

mkdir -p "$TARGET/.agents/skills"
for skill in supersaiyan super-board super-build super-qa super-review refining-spec writing-board-tasks test-driven-development verification-before-completion; do
  src="$SAIYAN/skills/$skill"
  dst="$TARGET/.agents/skills/$skill"
  if [ ! -d "$src" ]; then
    fail "$skill: source not found at $src"
    continue
  fi
  if same_path "$src" "$dst"; then
    ok "$skill (same path — skipped)"
    continue
  fi
  rm -rf "$dst"
  cp -RL "$src" "$dst"
  if [ -f "$dst/scripts/prepare.sh" ]; then chmod +x "$dst/scripts/prepare.sh"; fi
  ok "$skill"
done

# ── Pipeline scripts ───────────────────────────────────────────────────────────

echo
echo "Installing pipeline scripts"

if [ -d "$SAIYAN/scripts/platforms" ]; then
  rm -rf "$TARGET/.supersaiyan/bin/platforms"
  cp -RL "$SAIYAN/scripts/platforms" "$TARGET/.supersaiyan/bin/platforms"
  # Bash platform contracts are sourced; Python status_adapter is imported by
  # super-board-status.py from this same directory.
  chmod +x "$TARGET/.supersaiyan/bin/platforms/"*.sh 2>/dev/null || true
  ok "platforms/ (git_platform contract + status_adapter.py)"
else
  fail "scripts/platforms/ not found"
fi

if [ -d "$SAIYAN/scripts/backends" ]; then
  rm -rf "$TARGET/.supersaiyan/bin/backends"
  cp -RL "$SAIYAN/scripts/backends" "$TARGET/.supersaiyan/bin/backends"
  chmod +x "$TARGET/.supersaiyan/bin/backends/"*.sh
  ok "backends/ (worker_backend contract: claude-p, codex-exec, cursor-agent)"
else
  fail "scripts/backends/ not found"
fi

for script in super-board-run.sh super-board-gh-guard.sh super-board-status.py super-board-wave-plan.sh config-resolve.sh platform-config.sh tasks-to-issues.sh; do
  src="$SAIYAN/scripts/$script"
  dst="$TARGET/.supersaiyan/bin/$script"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    ok "$script"
  else
    fail "$script not found in scripts/"
  fi
done

if [ -f "$SAIYAN/scripts/super-board-wave.js" ]; then
  cp "$SAIYAN/scripts/super-board-wave.js" "$TARGET/.supersaiyan/workflows/"
  ok "super-board-wave.js"
else
  fail "scripts/super-board-wave.js not found"
fi

# ── Docs layout ───────────────────────────────────────────────────────────────

echo
echo "Creating docs layout"

for d in docs/superpowers/specs docs/superpowers/tasks docs/supersaiyan/designs docs/supersaiyan/specs docs/templates; do
  mkdir -p "$TARGET/$d"
  ok "$d/"
done

# Task file template
if [ ! -f "$TARGET/docs/templates/task-file.md" ] && [ -f "$SAIYAN/docs/templates/task-file.md" ]; then
  cp "$SAIYAN/docs/templates/task-file.md" "$TARGET/docs/templates/"
  ok "docs/templates/task-file.md"
fi

# ── Agent instructions ────────────────────────────────────────────────────────
# Canonical target is AGENTS.md: Codex and Cursor read it natively, with zero config. Claude
# Code does not read AGENTS.md, so it gets a CLAUDE.md pointer. One source
# (docs/templates/agent-blocks/pipeline-paths.md) reaches all three tools.

# shellcheck disable=SC1091
source "$SAIYAN/scripts/lib/md-block.sh"

AGENTS="$TARGET/AGENTS.md"
CLAUDE="$TARGET/CLAUDE.md"
BLOCK_SRC="$SAIYAN/docs/templates/agent-blocks/pipeline-paths.md"

if md_block_upsert "$AGENTS" pipeline-paths "$BLOCK_SRC"; then
  ok "AGENTS.md — SuperSaiyan pipeline paths"
else
  fail "AGENTS.md — could not write the pipeline-paths block"
fi

# Migrate the pre-fence section this installer used to append straight to CLAUDE.md. Leaving it
# would duplicate the content now living in AGENTS.md; deleting it outright could destroy a
# hand-edit, so back it up first and say where it went.
MIGRATION_DIR="$TARGET/docs/supersaiyan/migrations"
LEGACY_BACKUP="$MIGRATION_DIR/CLAUDE.md-pipeline-paths-$(date -u +%Y%m%dT%H%M%SZ).md"
if md_block_excise_legacy "$CLAUDE" "SuperSaiyan pipeline paths" "$LEGACY_BACKUP" 2>/dev/null; then
  ok "CLAUDE.md — moved legacy pipeline-paths section to AGENTS.md (backup: ${LEGACY_BACKUP#"$TARGET"/})"
fi

# Claude pointer. A bare `@AGENTS.md` when we own the file; a fenced block appended at the end
# when the user has their own content, so their structure is left alone.
if [ ! -f "$CLAUDE" ]; then
  printf '@AGENTS.md\n' > "$CLAUDE"
  ok "CLAUDE.md — created as an @AGENTS.md pointer"
elif [ "$(grep -cvE '^\s*$' "$CLAUDE")" -eq 1 ] && grep -qE '^\s*@AGENTS\.md\s*$' "$CLAUDE"; then
  ok "CLAUDE.md — already an @AGENTS.md pointer"
else
  POINTER_SRC="$(mktemp)"
  cat > "$POINTER_SRC" << 'EOF'
<!-- Claude Code does not read AGENTS.md natively; this import bridges it. SuperSaiyan's
     canonical agent instructions live in AGENTS.md, which Codex and Cursor read directly. -->
@AGENTS.md
EOF
  if md_block_upsert "$CLAUDE" claude-pointer "$POINTER_SRC"; then
    ok "CLAUDE.md — @AGENTS.md pointer block"
  else
    fail "CLAUDE.md — could not write the pointer block"
  fi
  rm -f "$POINTER_SRC"
fi

# ── Dynamic workflows ──────────────────────────────────────────────────────────

SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"

if [ -f "$SETTINGS" ] && jq -e '.enableWorkflows == true' "$SETTINGS" >/dev/null 2>&1; then
  ok "Claude dynamic workflows already enabled"
else
  TMP=$(mktemp)
  if [ -f "$SETTINGS" ] && jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1; then
    jq '.enableWorkflows = true' "$SETTINGS" > "$TMP"
  else
    jq -n '{enableWorkflows: true}' > "$TMP"
  fi
  mv "$TMP" "$SETTINGS"
  ok "Claude dynamic workflows enabled"
fi

# ── Verify ─────────────────────────────────────────────────────────────────────

echo
echo "Verification"

SKILL_PATHS=""
if [ "$PLUGIN_INSTALLED" = false ]; then
  SKILL_PATHS="\
  .claude/skills/supersaiyan/SKILL.md \
  .claude/skills/super-board/SKILL.md \
  .claude/skills/super-build/SKILL.md \
  .claude/skills/super-qa/SKILL.md \
  .claude/skills/super-review/SKILL.md \
  .claude/skills/refining-spec/SKILL.md \
  .claude/skills/writing-board-tasks/SKILL.md \
  .claude/skills/test-driven-development/SKILL.md \
  .claude/skills/verification-before-completion/SKILL.md"
fi

for path in \
  $SKILL_PATHS \
  ".supersaiyan/bin/super-board-wave-plan.sh" \
  ".supersaiyan/bin/tasks-to-issues.sh" \
  ".supersaiyan/bin/platform-config.sh" \
  ".supersaiyan/workflows/super-board-wave.js"; do
  if [ -e "$TARGET/$path" ]; then
    ok "$path"
  else
    fail "$path"
  fi
done

echo
if [ "$FAIL" -gt 0 ]; then
  echo "Install incomplete: $FAIL check(s) failed." >&2
  exit 1
fi

echo "✓ SuperSaiyan installed ($PASS checks passed)."
echo
echo "Next steps:"
echo "  1. cd \"$TARGET\""
echo "  2. claude .                  # open Claude Code in your repo"
echo "  3. /supersaiyan setup        # one-time GitHub Project + board config"
echo "  4. /supersaiyan new <slug>   # define a feature and queue it"
echo "  5. /supersaiyan run          # autonomous Build → QA → Review"
