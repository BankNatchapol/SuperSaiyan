#!/usr/bin/env bash
# SuperSaiyan installer — copies skills + pipeline scripts into any repo.
#
# Usage:
#   ./install.sh                  # install into current directory
#   ./install.sh /path/to/app     # install into specific repo
#   ./install.sh --check          # verify install without changing files
#
# After install, open Claude Code in the target repo and run:
#   /supersaiyan setup

set -euo pipefail

SAIYAN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$PWD"
CHECK_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
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

mkdir -p "$TARGET/.claude/skills" "$TARGET/.claude/bin" "$TARGET/.claude/workflows"

same_path() {
  [ "$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")" = \
    "$(cd "$(dirname "$2")" 2>/dev/null && pwd)/$(basename "$2")" ]
}

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

# ── Pipeline scripts ───────────────────────────────────────────────────────────

echo
echo "Installing pipeline scripts"

for script in super-board-run.sh super-board-gh-guard.sh super-board-status.py super-board-wave-plan.sh tasks-to-issues.sh; do
  src="$SAIYAN/scripts/$script"
  dst="$TARGET/.claude/bin/$script"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    ok "$script"
  else
    fail "$script not found in scripts/"
  fi
done

if [ -f "$SAIYAN/scripts/super-board-wave.js" ]; then
  cp "$SAIYAN/scripts/super-board-wave.js" "$TARGET/.claude/workflows/"
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

# ── CLAUDE.md ─────────────────────────────────────────────────────────────────

CLAUDE="$TARGET/CLAUDE.md"
SNIPPET="## SuperSaiyan pipeline paths"

[ -f "$CLAUDE" ] || printf '# Agent notes\n' > "$CLAUDE"

if ! grep -q "$SNIPPET" "$CLAUDE" 2>/dev/null; then
  cat >> "$CLAUDE" << 'EOF'

## SuperSaiyan pipeline paths

| Artifact | Path |
|----------|------|
| Feature specs | `docs/superpowers/specs/<slug>-design.md` |
| Board tasks | `docs/superpowers/tasks/<slug>/NN-*.md` |
| Issue map | `docs/superpowers/tasks/<slug>/.issue-map.json` |
| Designs | `docs/supersaiyan/designs/<slug>-design.md` |

When saving design docs from external tools, also save a copy to
`docs/supersaiyan/designs/<name>-design.md`.
EOF
  ok "CLAUDE.md — SuperSaiyan paths added"
else
  ok "CLAUDE.md — already has SuperSaiyan paths"
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

for path in \
  ".claude/skills/supersaiyan/SKILL.md" \
  ".claude/skills/super-board/SKILL.md" \
  ".claude/skills/super-build/SKILL.md" \
  ".claude/skills/super-qa/SKILL.md" \
  ".claude/skills/super-review/SKILL.md" \
  ".claude/skills/refining-spec/SKILL.md" \
  ".claude/skills/writing-board-tasks/SKILL.md" \
  ".claude/skills/test-driven-development/SKILL.md" \
  ".claude/skills/verification-before-completion/SKILL.md" \
  ".claude/bin/super-board-wave-plan.sh" \
  ".claude/bin/tasks-to-issues.sh" \
  ".claude/workflows/super-board-wave.js"; do
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
