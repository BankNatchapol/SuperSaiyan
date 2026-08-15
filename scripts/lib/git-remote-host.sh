#!/usr/bin/env bash
# scripts/lib/git-remote-host.sh — parse a git remote URL to a host token and
# decide github vs gitlab. Sourced (not executed) by scripts/bootstrap-app.sh.
#
# Match the HOST, never a substring of the path — otherwise
# https://github.com/org/gitlab.git looks like GitLab.
#
# bash 3.2 (macOS default) — no mapfile, no declare -A, no readarray.

git_remote_host() {
  local url="${1:-}" host
  [ -n "$url" ] || return 1
  case "$url" in
    *://*)
      host=$(printf '%s' "$url" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/@]+@)?([^/:]+).*#\2#')
      ;;
    *:*)
      host=$(printf '%s' "$url" | sed -E 's#^([^@]+@)?([^:]+):.*#\2#')
      ;;
    *)
      return 1
      ;;
  esac
  if [ -z "$host" ] || [ "$host" = "$url" ]; then
    return 1
  fi
  printf '%s\n' "$host"
}

git_remote_is_gitlab_host() {
  case "${1:-}" in
    gitlab.com|gitlab.*) return 0 ;;
    *) return 1 ;;
  esac
}

git_remote_platform() {
  local host
  host=$(git_remote_host "${1:-}") || {
    printf 'github\n'
    return 0
  }
  if git_remote_is_gitlab_host "$host"; then
    printf 'gitlab\n'
  else
    printf 'github\n'
  fi
}
