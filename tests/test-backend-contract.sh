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

# ── backend_skills_dir agreement ───────────────────────────────────────────────────────────
# The function has no callers today (every real path is a hardcoded `.claude/skills/...`
# string) — it is a reserved seam. The invariant actually worth protecting is that all three
# backends AGREE, so a future caller can rely on it without auditing each file.
SKILLS_DIRS=""
for f in "${BACKEND_FILES[@]}"; do
  d=$( source "$f"; backend_skills_dir )
  SKILLS_DIRS="$SKILLS_DIRS$d
"
done
if [ "$(printf '%s' "$SKILLS_DIRS" | sort -u | grep -c .)" -ne 1 ]; then
  echo "  FAIL: backends disagree on backend_skills_dir:" >&2
  printf '%s' "$SKILLS_DIRS" | sort -u >&2
  FAIL=1
else
  echo "  ✓ all backends agree on backend_skills_dir"
fi

# ── Orphan-guard round-trip ────────────────────────────────────────────────────────────────
# backend_orphan_pattern is what `pgrep -f` / `pkill` / the dashboard worker-count match
# against a LIVE PROCESS — i.e. the CLI invocation plus the prompt, not the prompt alone.
# (Note codex's pattern needs the literal `codex exec ` from the command itself; asserting
# against the addendum text alone would fail even on a correct backend.) Simulate the argv a
# dispatched worker really presents and assert the backend can still find its own workers —
# the guard that matters when the addendum text is regenerated from a shared template.
for f in "${BACKEND_FILES[@]}"; do
  name="$(basename "$f" .sh)"
  case "$name" in
    claude-p) cmd="claude -p --dangerously-skip-permissions" ;;
    codex-exec) cmd="codex exec --sandbox danger-full-access" ;;
    cursor-agent) cmd="agent -p --trust --force --sandbox disabled" ;;
    *) echo "  FAIL: no simulated argv known for backend '$name'" >&2; FAIL=1; continue ;;
  esac
  # claude-p's addendum is deliberately empty; its marker lives in the dispatch prompt instead.
  if [ "$name" = "claude-p" ]; then
    argv="$cmd Run super-build on issue #1 for super-board run."
  else
    argv="$cmd $( source "$f"; backend_worker_addendum | tr '\n' ' ' )"
  fi
  pattern=$( source "$f"; backend_orphan_pattern )
  if printf '%s' "$argv" | grep -qE "$pattern"; then
    echo "  ✓ $name orphan pattern matches a simulated live worker argv"
  else
    echo "  FAIL: $name orphan_pattern ('$pattern') does not match its own dispatched argv —" >&2
    echo "        orphan detection, pkill, and worker counts would silently find nothing" >&2
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "error: one or more backend files failed the contract check" >&2
  exit 1
fi

echo "PASS: test-backend-contract.sh"
