#!/usr/bin/env bash
# test-gitlab-live-gate.sh — shared GITLAB_LIVE=1 helper (issue #41 follow-up).
# The helper is the single gate; GitLab contract tests source it instead of
# duplicating PATH-prepend / auth-status opt-out.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/tests/lib/gitlab-live-gate.sh"

FAIL=0
tfail() { echo "  FAIL: $1" >&2; FAIL=1; }

echo "checking tests/lib/gitlab-live-gate.sh"

[ -f "$LIB" ] || tfail "tests/lib/gitlab-live-gate.sh is missing"
if [ -f "$LIB" ]; then
  bash -n "$LIB" || tfail "bash -n reported a syntax error in gitlab-live-gate.sh"
  if grep -vE '^\s*#' "$LIB" | grep -qE 'declare -A|mapfile|readarray'; then
    tfail "gitlab-live-gate.sh uses a bash-4-only construct"
  fi
  # shellcheck disable=SC1090
  . "$LIB"
fi

if ! declare -f gitlab_live_enabled >/dev/null 2>&1; then
  tfail "gitlab_live_enabled is not defined"
  echo "error: gitlab live-gate helper check failed" >&2
  exit 1
fi
if ! declare -f gitlab_live_gate_assert >/dev/null 2>&1; then
  tfail "gitlab_live_gate_assert is not defined"
fi
if ! declare -f _glg_fail >/dev/null 2>&1; then
  tfail "_glg_fail is not defined at file scope (must not leak from inside gitlab_live_gate_assert)"
fi

TD=$(mktemp -d)
mkdir -p "$TD/bin"
cat > "$TD/bin/glab" <<'EOF'
#!/usr/bin/env bash
exit "${STUB_AUTH_RC:-0}"
EOF
chmod +x "$TD/bin/glab"
ORIG_PATH="$PATH"
export PATH="$TD/bin:$PATH"
hash -r 2>/dev/null || true

unset GITLAB_LIVE || true
if gitlab_live_enabled; then
  tfail "gitlab_live_enabled succeeded with GITLAB_LIVE unset (stub glab authenticated)"
fi
GITLAB_LIVE=0
if gitlab_live_enabled; then
  tfail "gitlab_live_enabled succeeded with GITLAB_LIVE=0"
fi
GITLAB_LIVE=1
export STUB_AUTH_RC=1
if gitlab_live_enabled; then
  tfail "gitlab_live_enabled succeeded when glab auth status fails"
fi
export STUB_AUTH_RC=0
if ! gitlab_live_enabled; then
  tfail "gitlab_live_enabled failed with GITLAB_LIVE=1 and stub glab auth ok"
fi
export PATH="$ORIG_PATH"
unset GITLAB_LIVE STUB_AUTH_RC

# Assert: missing gate — tfail, but return 0 so set -e callers keep going
BAD="$TD/nongate.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo hi' > "$BAD"
captured=""
tfail() { captured="$captured|$1"; }
continued=0
gitlab_live_gate_assert "$BAD"
continued=1
[ "$continued" = 1 ] \
  || { echo "  FAIL: gitlab_live_gate_assert aborted the caller under set -e" >&2; FAIL=1; }
echo "$captured" | grep -q 'gitlab_live_enabled' \
  || { echo "  FAIL: assert did not mention gitlab_live_enabled: $captured" >&2; FAIL=1; }
echo "$captured" | grep -q 'gitlab-live-gate.sh' \
  || { echo "  FAIL: assert did not require sourcing the helper: $captured" >&2; FAIL=1; }

# Empty args under set -u must not unbound $1
captured=""
gitlab_live_gate_assert
echo "$captured" | grep -q 'missing file' \
  || { echo "  FAIL: no-arg assert did not report missing file (unbound \$1?): $captured" >&2; FAIL=1; }

# Assert: gate + optional flags
GOOD="$TD/gated.sh"
cat > "$GOOD" <<'EOF'
#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$ROOT/tests/lib/gitlab-live-gate.sh"
ORIG_PATH="$PATH"
export PATH="$ORIG_PATH"
  auth)
    exit 1
    ;;
[ "${GLAB_AUTH_OK:-0}" = 1 ] || exit 1
export GLAB_AUTH_OK=0
if gitlab_live_enabled; then
  echo live
fi
EOF
captured=""
if ! gitlab_live_gate_assert "$GOOD" --orig-path --stub-auth --auth-ok-closed; then
  echo "  FAIL: gitlab_live_gate_assert failed on a complete fixture: $captured" >&2
  FAIL=1
fi
[ -z "$captured" ] || { echo "  FAIL: unexpected tfail on complete fixture: $captured" >&2; FAIL=1; }

# --orig-path required
captured=""
THIN="$TD/thin.sh"
cat > "$THIN" <<'EOF'
#!/usr/bin/env bash
. "$ROOT/tests/lib/gitlab-live-gate.sh"
if gitlab_live_enabled; then echo live; fi
EOF
gitlab_live_gate_assert "$THIN" --orig-path >/dev/null 2>&1 || true
echo "$captured" | grep -q 'ORIG_PATH' \
  || { echo "  FAIL: --orig-path did not trip: $captured" >&2; FAIL=1; }

rm -rf "$TD"
tfail() { echo "  FAIL: $1" >&2; FAIL=1; }

if [ "$FAIL" -ne 0 ]; then
  echo "error: gitlab live-gate helper check failed" >&2
  exit 1
fi
echo "  ✓ gitlab_live_enabled is opt-in; gitlab_live_gate_assert tripwires fire"
echo "PASS: test-gitlab-live-gate.sh"
