#!/usr/bin/env bash
# tests/lib/gitlab-live-gate.sh — shared GITLAB_LIVE=1 gate for GitLab contract tests.
# Source from a test. Do not execute. bash 3.2 compatible (no mapfile / declare -A).
#
# Live sandbox checks must be opt-in. `glab auth status` alone is not a gate:
# leftover stub glab on PATH can impersonate a login (issue #41).

gitlab_live_enabled() {
  [ "${GITLAB_LIVE:-}" = "1" ] || return 1
  # Drop a hashed stub glab from an earlier PATH="$TD/bin:$PATH".
  hash -r 2>/dev/null || true
  command -v glab >/dev/null 2>&1 || return 1
  glab auth status >/dev/null 2>&1
}

_glg_fail() {
  if declare -f tfail >/dev/null 2>&1; then
    tfail "$1"
  else
    echo "  FAIL: $1" >&2
  fi
}

# gitlab_live_gate_assert FILE [--orig-path] [--stub-auth] [--auth-ok-closed]
# Calls tfail when a required pattern is missing. Always returns 0 so a
# bare call under set -e still runs the rest of the test and the summary.
gitlab_live_gate_assert() {
  local file="${1:-}"
  local want_orig=0 want_stub_auth=0 want_auth_ok=0
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --orig-path) want_orig=1 ;;
      --stub-auth) want_stub_auth=1 ;;
      --auth-ok-closed) want_auth_ok=1 ;;
      *)
        echo "gitlab_live_gate_assert: unknown flag $1" >&2
        return 0
        ;;
    esac
    shift
  done

  if [ -z "$file" ] || [ ! -f "$file" ]; then
    _glg_fail "gitlab_live_gate_assert: missing file ${file:-?}"
    return 0
  fi

  grep -q 'lib/gitlab-live-gate.sh' "$file" \
    || _glg_fail "does not source tests/lib/gitlab-live-gate.sh"
  grep -q 'gitlab_live_enabled' "$file" \
    || _glg_fail "live sandbox is not gated via gitlab_live_enabled"

  if [ "$want_orig" = 1 ]; then
    awk '/^ORIG_PATH=/{s=1} /PATH="\$ORIG_PATH"/{r=1} END{exit !(s && r)}' "$file" \
      || _glg_fail "does not save and restore ORIG_PATH around stub glab"
  fi
  if [ "$want_stub_auth" = 1 ]; then
    grep -Eq '^[[:space:]]+auth\)' "$file" \
      || _glg_fail "stub glab has no auth) handler (must exit 1 so leftover PATH cannot impersonate a login)"
  fi
  if [ "$want_auth_ok" = 1 ]; then
    grep -Eq '\$\{GLAB_AUTH_OK:-0\}' "$file" \
      || _glg_fail "stub auth defaults to authenticated (want GLAB_AUTH_OK:-0)"
    grep -Eq '^export GLAB_AUTH_OK=0$' "$file" \
      || _glg_fail "does not export GLAB_AUTH_OK=0 before the live gate"
  fi
  return 0
}
