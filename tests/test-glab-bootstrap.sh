#!/usr/bin/env bash
# test-glab-bootstrap.sh — issue #6 / gitlab-integration task 06.
# bootstrap-app.sh must install glab unconditionally and branch auth on
# git_platform. Origin sniff matches a host token, not a path substring.
# install.sh --check must stay GitHub-prereq-only (no glab).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$ROOT/scripts/bootstrap-app.sh"
INSTALL="$ROOT/install.sh"
LIB="$ROOT/scripts/lib/git-remote-host.sh"

FAIL=0
tfail() { echo "  FAIL: $1" >&2; FAIL=1; }

[ -f "$BOOTSTRAP" ] || { echo "error: $BOOTSTRAP not found" >&2; exit 1; }
[ -f "$INSTALL" ] || { echo "error: $INSTALL not found" >&2; exit 1; }

echo "checking glab install + platform-conditional auth in bootstrap"

bash -n "$BOOTSTRAP" || tfail "bash -n reported a syntax error in bootstrap-app.sh"

# ── 1. glab installed unconditionally alongside gh ─────────────────────────
grep -qE 'install_brew_package[[:space:]]+glab[[:space:]]+glab' "$BOOTSTRAP" \
  || tfail "bootstrap-app.sh does not install glab via install_brew_package glab glab"

GH_LINE=$(grep -nE 'install_brew_package[[:space:]]+gh[[:space:]]+gh' "$BOOTSTRAP" | head -1 | cut -d: -f1 || true)
GLAB_LINE=$(grep -nE 'install_brew_package[[:space:]]+glab[[:space:]]+glab' "$BOOTSTRAP" | head -1 | cut -d: -f1 || true)
if [ -n "$GH_LINE" ] && [ -n "$GLAB_LINE" ] && [ "$GLAB_LINE" -le "$GH_LINE" ]; then
  tfail "glab install must come after the existing gh install"
fi

# ── 2. check_authentication branches on git_platform ───────────────────────
grep -q 'platform_config_resolve' "$BOOTSTRAP" \
  || tfail "check_authentication does not use platform_config_resolve"
grep -q 'platform_config_resolve_platform' "$BOOTSTRAP" \
  || tfail "check_authentication does not use platform_config_resolve_platform"
grep -q 'glab auth status' "$BOOTSTRAP" \
  || tfail "check_authentication does not check glab auth status for GitLab"
grep -q 'glab auth login' "$BOOTSTRAP" \
  || tfail "GitLab auth remediation message missing (expected glab auth login)"
grep -q 'git-remote-host.sh' "$BOOTSTRAP" \
  || tfail "bootstrap-app.sh does not source scripts/lib/git-remote-host.sh"
if grep -vE '^\s*#' "$BOOTSTRAP" | grep -qE '\*gitlab\.com\*|\*gitlab\.\*'; then
  tfail "bootstrap still substring-matches the whole origin URL (*gitlab.com*|*gitlab.*)"
fi

# ── 3. install.sh --check stays GitHub-only ────────────────────────────────
if grep -A20 '^echo "Prerequisites"' "$INSTALL" | grep -qE '\bglab\b'; then
  tfail "install.sh Prerequisites block now mentions glab (would change --check output)"
fi
grep -qE 'for cmd in git gh;' "$INSTALL" \
  || tfail "install.sh prerequisite loop is no longer 'git gh' only"

# ── 4. Host-token sniff (behavioral) ───────────────────────────────────────
if [ ! -f "$LIB" ]; then
  tfail "scripts/lib/git-remote-host.sh is missing"
else
  bash -n "$LIB" || tfail "bash -n reported a syntax error in git-remote-host.sh"
  if grep -vE '^\s*#' "$LIB" | grep -qE 'declare -A|mapfile|readarray'; then
    tfail "git-remote-host.sh uses a bash-4-only construct"
  fi
  # shellcheck disable=SC1090
  . "$LIB"

  assert_host() {
    local url="$1" want="$2" got
    got=$(git_remote_host "$url") || { tfail "git_remote_host failed on $url"; return; }
    [ "$got" = "$want" ] || tfail "git_remote_host $url → $got (want $want)"
  }
  assert_platform() {
    local url="$1" want="$2" got
    got=$(git_remote_platform "$url")
    [ "$got" = "$want" ] || tfail "git_remote_platform $url → $got (want $want)"
  }

  assert_host "https://github.com/org/gitlab.git" "github.com"
  assert_platform "https://github.com/org/gitlab.git" "github"
  assert_host "https://github.com/gitlab-org/gitlab.git" "github.com"
  assert_platform "https://github.com/gitlab-org/gitlab.git" "github"
  assert_host "https://gitlab.com/org/repo.git" "gitlab.com"
  assert_platform "https://gitlab.com/org/repo.git" "gitlab"
  assert_host "git@gitlab.com:org/repo.git" "gitlab.com"
  assert_platform "git@gitlab.com:org/repo.git" "gitlab"
  assert_host "https://gitlab.example.com/g/p.git" "gitlab.example.com"
  assert_platform "https://gitlab.example.com/g/p.git" "gitlab"
  assert_host "git@gitlab.example.com:g/p.git" "gitlab.example.com"
  assert_platform "git@gitlab.example.com:g/p.git" "gitlab"
  assert_host "ssh://git@gitlab.example.com/g/p.git" "gitlab.example.com"
  assert_platform "ssh://git@gitlab.example.com/g/p.git" "gitlab"
  assert_platform "https://git.company.com/g/p.git" "github"
fi

# ── 5. check_gitlab_auth passes --hostname for sniffed self-hosted origin ───
TD=$(mktemp -d)
GLAB_LOG="$TD/glab.log"
mkdir -p "$TD/bin" "$TD/selfhosted" "$TD/saas"
cat > "$TD/bin/glab" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GLAB_LOG"
exit 1
EOF
chmod +x "$TD/bin/glab"

git init -q "$TD/selfhosted"
git -C "$TD/selfhosted" remote add origin "https://gitlab.example.com/g/p.git"
git init -q "$TD/saas"
git -C "$TD/saas" remote add origin "https://gitlab.com/org/repo.git"

# Source bootstrap helpers without running the installer body.
# shellcheck disable=SC2034
SAIYAN_ROOT="$ROOT"
# shellcheck disable=SC2034
CHECK_ONLY=true
ok() { :; }
warn() { :; }
# bootstrap defines fail() for installer accounting; assertions use tfail.
MISSING=0
WARNINGS=0

if grep -q 'BOOTSTRAP_SOURCE_ONLY' "$BOOTSTRAP"; then
  # shellcheck disable=SC1090
  BOOTSTRAP_SOURCE_ONLY=1 . "$BOOTSTRAP"
  ok() { :; }
  warn() { :; }
  TARGET="$TD/selfhosted"
  : > "$GLAB_LOG"
  PATH="$TD/bin:$PATH" check_gitlab_auth
  if ! grep -q -- '--hostname gitlab.example.com' "$GLAB_LOG"; then
    tfail "sniffed gitlab.example.com origin did not pass --hostname gitlab.example.com (got: $(tr '\n' ' ' < "$GLAB_LOG"))"
  fi
  TARGET="$TD/saas"
  : > "$GLAB_LOG"
  PATH="$TD/bin:$PATH" check_gitlab_auth
  if grep -q -- '--hostname' "$GLAB_LOG"; then
    tfail "gitlab.com origin must not pass --hostname (got: $(tr '\n' ' ' < "$GLAB_LOG"))"
  fi
else
  tfail "bootstrap-app.sh has no BOOTSTRAP_SOURCE_ONLY guard for helper tests"
fi
rm -rf "$TD"

if [ "$FAIL" -ne 0 ]; then
  echo "error: glab bootstrap contract check failed" >&2
  exit 1
fi

echo "  ✓ glab installed; host-token sniff; self-hosted --hostname; install.sh --check unchanged"
echo "PASS: test-glab-bootstrap.sh"
