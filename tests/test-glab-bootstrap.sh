#!/usr/bin/env bash
# test-glab-bootstrap.sh — issue #6 / gitlab-integration task 06.
# bootstrap-app.sh must install glab unconditionally and branch auth on
# git_platform. install.sh --check must stay GitHub-prereq-only (no glab).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$ROOT/scripts/bootstrap-app.sh"
INSTALL="$ROOT/install.sh"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

[ -f "$BOOTSTRAP" ] || { echo "error: $BOOTSTRAP not found" >&2; exit 1; }
[ -f "$INSTALL" ] || { echo "error: $INSTALL not found" >&2; exit 1; }

echo "checking glab install + platform-conditional auth in bootstrap"

bash -n "$BOOTSTRAP" || fail "bash -n reported a syntax error in bootstrap-app.sh"

# ── 1. glab installed unconditionally alongside gh ─────────────────────────
grep -qE 'install_brew_package[[:space:]]+glab[[:space:]]+glab' "$BOOTSTRAP" \
  || fail "bootstrap-app.sh does not install glab via install_brew_package glab glab"

# Must appear after the gh install so a first-run machine gets both CLIs.
GH_LINE=$(grep -nE 'install_brew_package[[:space:]]+gh[[:space:]]+gh' "$BOOTSTRAP" | head -1 | cut -d: -f1 || true)
GLAB_LINE=$(grep -nE 'install_brew_package[[:space:]]+glab[[:space:]]+glab' "$BOOTSTRAP" | head -1 | cut -d: -f1 || true)
if [ -n "$GH_LINE" ] && [ -n "$GLAB_LINE" ] && [ "$GLAB_LINE" -le "$GH_LINE" ]; then
  fail "glab install must come after the existing gh install"
fi

# ── 2. check_authentication branches on git_platform ───────────────────────
grep -q 'platform_config_resolve' "$BOOTSTRAP" \
  || fail "check_authentication does not use platform_config_resolve"
grep -q 'platform_config_resolve_platform' "$BOOTSTRAP" \
  || fail "check_authentication does not use platform_config_resolve_platform"
grep -q 'glab auth status' "$BOOTSTRAP" \
  || fail "check_authentication does not check glab auth status for GitLab"
grep -q 'glab auth login' "$BOOTSTRAP" \
  || fail "GitLab auth remediation message missing (expected glab auth login)"

# No-config / to-be-onboarded: sniff origin host for GitLab (not just
# check_app_git's existing "has an origin" warning).
grep -qE 'gitlab\.com' "$BOOTSTRAP" \
  || fail "no-config path does not detect a GitLab origin host (gitlab.com)"

# ── 3. install.sh --check stays GitHub-only (output must not require glab) ─
# install.sh already copies platforms/ to .supersaiyan/bin/platforms/; do not
# add glab as a hard prerequisite (that would change --check output).
if grep -A20 '^echo "Prerequisites"' "$INSTALL" | grep -qE '\bglab\b'; then
  fail "install.sh Prerequisites block now mentions glab (would change --check output)"
fi
grep -qE 'for cmd in git gh;' "$INSTALL" \
  || fail "install.sh prerequisite loop is no longer 'git gh' only"

if [ "$FAIL" -ne 0 ]; then
  echo "error: glab bootstrap contract check failed" >&2
  exit 1
fi

echo "  ✓ glab installed unconditionally; auth branches on git_platform; install.sh --check unchanged"
echo "PASS: test-glab-bootstrap.sh"
