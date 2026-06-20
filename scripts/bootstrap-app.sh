#!/usr/bin/env bash
# bootstrap-app.sh — one-command SuperSaiyan setup for an app repository.
#
# Run from the app repo:
#   ~/Documents/SuperSaiyan/scripts/bootstrap-app.sh
#
# Check only, without installing or changing the app:
#   ~/Documents/SuperSaiyan/scripts/bootstrap-app.sh --check
#
# An explicit app path is also accepted:
#   ~/Documents/SuperSaiyan/scripts/bootstrap-app.sh /path/to/app
set -euo pipefail

SAIYAN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$PWD"
CHECK_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    -*) echo "Unknown flag: $arg" >&2; exit 64 ;;
    *) TARGET="$arg" ;;
  esac
done

if [ ! -d "$TARGET" ]; then
  echo "Target app not found: $TARGET" >&2
  exit 66
fi

TARGET="$(cd "$TARGET" && pwd)"
MISSING=0
WARNINGS=0

ok() {
  echo "  ✓ $1"
}

warn() {
  echo "  ! $1" >&2
  WARNINGS=$((WARNINGS + 1))
}

fail() {
  echo "  ✗ $1" >&2
  MISSING=$((MISSING + 1))
}

install_brew_package() {
  local command_name="$1" package_name="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$command_name already installed"
    return
  fi

  if [ "$CHECK_ONLY" = true ]; then
    fail "$command_name is not installed"
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    echo "  → installing $package_name with Homebrew"
    brew install "$package_name"
  else
    fail "$command_name is missing and Homebrew is unavailable"
    return
  fi

  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$command_name installed"
  else
    fail "$command_name installation did not expose the command on PATH"
  fi
}

install_claude() {
  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code already installed"
    return
  fi

  if [ "$CHECK_ONLY" = true ]; then
    fail "Claude Code is not installed"
    return
  fi

  echo "  → installing Claude Code with the official installer"
  local installer
  installer=$(mktemp)
  curl -fsSL https://claude.ai/install.sh -o "$installer"
  bash "$installer"
  rm -f "$installer"
  hash -r

  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code installed"
  else
    fail "Claude Code installed but is not on PATH; restart the terminal"
  fi
}

enable_dynamic_workflows() {
  local settings_dir="$HOME/.claude"
  local settings_file="$settings_dir/settings.json"
  local tmp

  if [ -f "$settings_file" ]; then
    if ! jq -e 'type == "object"' "$settings_file" >/dev/null 2>&1; then
      fail "Claude settings are not valid JSON: $settings_file"
      return
    fi
    if [ "$(jq -r '.enableWorkflows // false' "$settings_file")" = "true" ]; then
      ok "Claude dynamic workflows already enabled"
      return
    fi
  fi

  if [ "$CHECK_ONLY" = true ]; then
    fail "Claude dynamic workflows are not enabled"
    return
  fi

  mkdir -p "$settings_dir"
  tmp=$(mktemp "$settings_dir/settings.json.tmp.XXXXXX")

  if [ -f "$settings_file" ]; then
    jq '.enableWorkflows = true' "$settings_file" > "$tmp"
  else
    jq -n '{enableWorkflows: true}' > "$tmp"
  fi

  chmod 600 "$tmp"
  mv "$tmp" "$settings_file"

  if [ "$(jq -r '.enableWorkflows // false' "$settings_file")" = "true" ]; then
    ok "Claude dynamic workflows enabled"
  else
    fail "Could not enable Claude dynamic workflows"
  fi
}

check_authentication() {
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      ok "GitHub CLI authenticated"
      local scopes
      scopes=$(gh auth status --active --json hosts --jq \
        '.hosts | add | map(select(.active == true))[0].scopes // ""' 2>/dev/null || true)
      case ",${scopes// /}," in
        *,project,*) ok "GitHub Project read/write scope available" ;;
        *)
          warn "GitHub Project write scope missing; run: gh auth refresh -s project,read:project,repo"
          ;;
      esac
    else
      warn "GitHub CLI is not authenticated; run: gh auth login"
    fi
  fi

  if command -v claude >/dev/null 2>&1; then
    if claude auth status >/dev/null 2>&1; then
      ok "Claude Code authenticated"
    else
      warn "Claude Code is not authenticated; run: claude auth login"
    fi
  fi
}

install_superpowers() {
  if ! command -v claude >/dev/null 2>&1; then
    fail "Cannot install Superpowers without Claude Code"
    return
  fi

  if claude plugin list --json 2>/dev/null |
      jq -e '.. | strings | select(. == "superpowers@claude-plugins-official")' >/dev/null 2>&1; then
    ok "Superpowers plugin already installed"
    return
  fi

  if [ "$CHECK_ONLY" = true ]; then
    fail "Superpowers plugin is not installed"
    return
  fi

  echo "  → installing Superpowers plugin"
  claude plugin install superpowers@claude-plugins-official --scope user

  if claude plugin list --json 2>/dev/null |
      jq -e '.. | strings | select(. == "superpowers@claude-plugins-official")' >/dev/null 2>&1; then
    ok "Superpowers plugin installed"
  else
    fail "Superpowers plugin installation could not be verified"
  fi
}

install_gstack() {
  if [ -f "$HOME/.claude/skills/office-hours/SKILL.md" ]; then
    ok "gstack already installed"
    return
  fi

  if [ "$CHECK_ONLY" = true ]; then
    fail "gstack is not installed"
    return
  fi

  if ! command -v bun >/dev/null 2>&1; then
    fail "Cannot install gstack without Bun"
    return
  fi

  echo "  → installing gstack from $SAIYAN_ROOT/gstack"
  (
    cd "$SAIYAN_ROOT/gstack"
    ./setup --host claude --no-prefix --no-plan-tune-hooks --quiet
  )

  if [ -f "$HOME/.claude/skills/office-hours/SKILL.md" ]; then
    ok "gstack installed"
  else
    fail "gstack installation could not be verified"
  fi
}

verify_app_install() {
  local path
  for path in \
    ".claude/skills/super-board/SKILL.md" \
    ".claude/skills/refining-spec/SKILL.md" \
    ".claude/skills/writing-board-tasks/SKILL.md" \
    ".claude/skills/supersaiyan/SKILL.md" \
    ".claude/skills/supersaiyan/references/prepare.md" \
    ".claude/skills/supersaiyan/scripts/prepare.sh" \
    ".claude/bin/tasks-to-issues.sh" \
    ".claude/workflows/super-board-wave.js" \
    "docs/templates/task-file.md" \
    "scripts/gstack-env.sh" \
    "CLAUDE.md"; do
    if [ -e "$TARGET/$path" ]; then
      ok "$path"
    else
      fail "$path missing"
    fi
  done
}

check_app_git() {
  if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    warn "App is not a Git repository yet; initialize or clone it before super-board"
    return
  fi
  ok "App is a Git repository"

  if git -C "$TARGET" remote get-url origin >/dev/null 2>&1; then
    ok "App has an origin remote"
  else
    warn "App has no origin remote; add one and push main before super-board"
  fi
}

echo "SuperSaiyan bootstrap"
echo "Toolkit: $SAIYAN_ROOT"
echo "App:     $TARGET"
echo

echo "Machine prerequisites"
install_brew_package git git
install_brew_package gh gh
install_brew_package jq jq
install_claude
enable_dynamic_workflows
install_brew_package bun bun
check_authentication
install_superpowers
install_gstack

echo
if [ "$CHECK_ONLY" = false ]; then
  echo "App-repo setup"
  SUPER_BOARD_EMBEDDED_INSTALL=true \
    "$SAIYAN_ROOT/super-board/install.sh" "$TARGET"
  "$SAIYAN_ROOT/scripts/install-bridge-skills.sh" "$TARGET"
  "$SAIYAN_ROOT/scripts/setup-gstack-artifacts-path.sh" "$TARGET"
fi

echo
echo "App verification"
verify_app_install
check_app_git

echo
if [ "$MISSING" -gt 0 ]; then
  echo "Bootstrap incomplete: $MISSING required check(s) failed." >&2
  exit 1
fi

echo "✓ Bootstrap complete."
if [ "$WARNINGS" -gt 0 ]; then
  echo "  Resolve the $WARNINGS interactive warning(s) above before running super-board."
fi
echo
echo "What bootstrap finished:"
echo "  ✓ machine tools and Claude dependencies"
echo "  ✓ dynamic workflows in ~/.claude/settings.json"
echo "  ✓ super-board + bridge skills in this app repo"
echo
echo "What you still need to do:"
echo "  1. Ensure this app is a Git repo with an origin remote and a pushed main branch"
echo "  2. From SuperSaiyan, open Claude Code on the app: claude \"$TARGET\""
echo "  3. Define the feature: /office-hours → refining-spec → writing-board-tasks"
echo "  4. Run /supersaiyan prepare <feature-slug>"
echo "     (onboards the Project if needed, files issues to Ready, and runs lint)"
echo "  5. Run /super-board run <slug>"
