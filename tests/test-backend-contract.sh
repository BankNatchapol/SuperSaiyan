#!/usr/bin/env bash
# test-backend-contract.sh — static check that every scripts/backends/*.sh implements the
# full Backend contract (see skills/super-board/references/backends.md). No live CLI calls —
# safe to run without codex/cursor-agent/claude installed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKENDS_DIR="$ROOT/scripts/backends"

REQUIRED_FUNCTIONS=(backend_launch backend_run_sync backend_orphan_pattern backend_auth_check backend_skills_dir backend_worker_addendum)

FAIL=0

shopt -s nullglob
BACKEND_FILES=("$BACKENDS_DIR"/*.sh)
shopt -u nullglob

if [ "${#BACKEND_FILES[@]}" -eq 0 ]; then
  echo "error: no backend files found in $BACKENDS_DIR" >&2
  exit 1
fi

for f in "${BACKEND_FILES[@]}"; do
  name="$(basename "$f")"
  echo "checking $name"

  if ! bash -n "$f"; then
    echo "  FAIL: $name has a syntax error" >&2
    FAIL=1
    continue
  fi

  # Source in a subshell so functions from one backend never leak into the next check.
  MISSING=""
  for fn in "${REQUIRED_FUNCTIONS[@]}"; do
    if ! ( source "$f"; declare -f "$fn" >/dev/null 2>&1 ); then
      MISSING="$MISSING $fn"
    fi
  done

  if [ -n "$MISSING" ]; then
    echo "  FAIL: $name is missing:$MISSING" >&2
    FAIL=1
  else
    echo "  ✓ all ${#REQUIRED_FUNCTIONS[@]} contract functions defined"
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "error: one or more backend files failed the contract check" >&2
  exit 1
fi

echo "PASS: test-backend-contract.sh"
