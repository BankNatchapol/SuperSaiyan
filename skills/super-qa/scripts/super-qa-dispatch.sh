#!/usr/bin/env bash
# super-qa-dispatch.sh — dispatch one super-qa iteration to a headless worker.
#
# Contract (per .claude/skills/super-qa/SKILL.md, "2b. Dispatch iteration worker"):
#   - Arg: iteration number N
#   - Env: REPO_DIR       (optional) — defaults to PWD; the working repo root
#          SKILL_DIR      (optional) — defaults to the dir this script lives in's parent
#          MAX_TURNS      (optional) — default 250 (claude-p backend only)
#          WORKER_BACKEND (optional) — default "claude-p"; also "codex-exec"/"cursor-agent".
#                          See .claude/skills/super-board/references/backends.md.
#   - Side effects:
#       * runs the configured backend's worker CLI in the CURRENT repo root — no worktree,
#         no branch creation (unlike super-build-dispatch.sh); the worker commits directly
#         to whichever branch the orchestrator already has checked out.
#       * exports SUPER_QA_FORENSICS=1 for the worker (gates forensics disk writes — see
#         iteration-preamble.md "Forensics capture per spec").
#       * captures stdout+stderr to .planning/super-build-logs/super-qa-iter-N.log
#   - Exit codes:
#       0  success           — worker produced `super-qa: iter N` close-out commit
#       2  worker non-zero   — worker exited non-zero AND no recognizable done/wip marker
#       3  no done-commit    — worker exited zero but no `super-qa: iter N` commit and no
#                              `wip: super-qa iter N` commit either (nothing salvageable)
#       4  HUMAN GATE        — log contains `HUMAN GATE TRIPPED:`
#       5  WIP-CHECKPOINT    — wall-clock hit before the close-out commit could be written,
#                              but a `wip: super-qa iter N` commit exists — time-clipped, not
#                              a real failure. Orchestrator picks up the next iteration; the
#                              still-red spec is caught by the next iter's regression pass.
#
# Notes:
#   - No worktree is created: super-qa is sequential by design (shared docs/super-qa/queue.md
#     — see SKILL.md), so there's no concurrent-worker isolation need the way super-build has.
#   - This script never merges, closes issues, or advances the iteration counter — the
#     orchestrator handles all of that after inspecting the exit code and the close-out commit.

set -uo pipefail

N="${1:-}"
if [[ -z "$N" ]]; then
  echo "usage: $0 <iteration-number>" >&2
  exit 64
fi

if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  echo "error: iteration number must be numeric, got: $N" >&2
  exit 64
fi

REPO_DIR="${REPO_DIR:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SKILL_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MAX_TURNS="${MAX_TURNS:-250}"
WORKER_BACKEND="${WORKER_BACKEND:-claude-p}"

# Backend contract (see .claude/skills/super-board/references/backends.md). Same resolution
# order as super-build-dispatch.sh: new-installed layout, then old-installed layout (installs
# from before the .claude/ -> vendor-neutral migration), then dev-repo fallback.
BACKEND_FILE="$REPO_DIR/.supersaiyan/bin/backends/${WORKER_BACKEND}.sh"
if [[ ! -f "$BACKEND_FILE" ]]; then
  BACKEND_FILE="$REPO_DIR/.claude/bin/backends/${WORKER_BACKEND}.sh"
fi
if [[ ! -f "$BACKEND_FILE" ]]; then
  BACKEND_FILE="$SCRIPT_DIR/../../../scripts/backends/${WORKER_BACKEND}.sh"
fi
if [[ ! -f "$BACKEND_FILE" ]]; then
  echo "error: backend contract not found for worker_backend=${WORKER_BACKEND} (looked in .supersaiyan/bin/backends/, .claude/bin/backends/, and scripts/backends/)" >&2
  exit 64
fi
# shellcheck disable=SC1090
source "$BACKEND_FILE"

if ! backend_auth_check; then
  echo "error: backend '${WORKER_BACKEND}' failed its auth check — see message above." >&2
  exit 64
fi

PREAMBLE="$SKILL_DIR/references/iteration-preamble.md"
if [[ ! -f "$PREAMBLE" ]]; then
  echo "error: iteration preamble not found at $PREAMBLE" >&2
  exit 64
fi

cd "$REPO_DIR" || { echo "error: cannot cd to REPO_DIR=$REPO_DIR" >&2; exit 64; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: $REPO_DIR is not a git repository" >&2
  exit 64
fi

ACTIVE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE_SHA=$(git rev-parse HEAD)
ITER_FILE="docs/super-qa/iter/iteration-${N}.md"
LOG_DIR="$REPO_DIR/.planning/super-build-logs"
LOG_FILE="$LOG_DIR/super-qa-iter-${N}.log"
PROMPT_FILE="$LOG_DIR/super-qa-iter-${N}.prompt.md"

mkdir -p "$LOG_DIR" "$(dirname "$ITER_FILE")"

# Compose the worker prompt: backend addendum (non-Claude backends only) + iteration preamble
# + per-iteration footer.
{
  printf '%s' "$(backend_worker_addendum)"
  cat "$PREAMBLE"
  printf '\n# Iteration %s\n\n' "$N"
  printf 'Iteration number: %s\n' "$N"
  printf 'Working directory: %s (repo root, no worktree)\n' "$REPO_DIR"
  printf 'Active branch: %s\n' "$ACTIVE_BRANCH"
  printf 'Base commit SHA: %s\n' "$BASE_SHA"
  printf 'Iteration file you MUST create: %s\n' "$ITER_FILE"
  printf 'Log file: %s\n' "$LOG_FILE"
  printf '\nMandatory final commit format: `super-qa: iter %s (X bugs, Y items, Z PRs opened)`\n' "$N"
} > "$PROMPT_FILE"

echo "▶︎ dispatching super-qa iteration #$N — repo root — branch $ACTIVE_BRANCH @ ${BASE_SHA:0:7}" | tee -a "$LOG_FILE"

PROMPT_TEXT="$(cat "$PROMPT_FILE")"

# Forensics disk writes are gated behind this flag — see iteration-preamble.md.
export SUPER_QA_FORENSICS=1

WORKER_EXIT=0
backend_run_sync "$PROMPT_TEXT" >>"$LOG_FILE" 2>&1 || WORKER_EXIT=$?

echo "▶︎ worker for iteration #$N exited with code $WORKER_EXIT" | tee -a "$LOG_FILE"

HEAD_SHA=$(git rev-parse HEAD)
COMMITS_RANGE="${BASE_SHA}..${HEAD_SHA}"

CLOSE_COMMIT=""
WIP_COMMIT=""
if [[ "$BASE_SHA" != "$HEAD_SHA" ]]; then
  CLOSE_COMMIT=$(git log --format="%H %s" "$COMMITS_RANGE" 2>/dev/null \
    | grep -E "^[0-9a-f]+ super-qa: iter $N( |\()" | head -1 || true)
  WIP_COMMIT=$(git log --format="%H %s" "$COMMITS_RANGE" 2>/dev/null \
    | grep -E "^[0-9a-f]+ wip: super-qa iter $N( |$)" | head -1 || true)
fi

# Detect HUMAN GATE in log
if grep -q "HUMAN GATE TRIPPED:" "$LOG_FILE"; then
  echo "▶︎ HUMAN GATE TRIPPED detected in log for iteration #$N" | tee -a "$LOG_FILE"
  exit 4
fi

# Detect success: close-out commit present (a wip: commit alongside it is fine — the
# preamble's own failure-mode contract makes both commits when time is clipped mid-fix and
# still treats that as a successful iter).
if [[ -n "$CLOSE_COMMIT" ]]; then
  if [[ "$WORKER_EXIT" -ne 0 ]]; then
    echo "▶︎ worker exited non-zero ($WORKER_EXIT) but produced close-out commit; treating as success" | tee -a "$LOG_FILE"
  fi
  echo "▶︎ success: $CLOSE_COMMIT" | tee -a "$LOG_FILE"
  exit 0
fi

# No close-out commit, but a wip: checkpoint exists — time was clipped before the close-out
# could be written. Salvageable; the orchestrator advances to the next iteration.
if [[ -n "$WIP_COMMIT" ]]; then
  echo "▶︎ WIP-CHECKPOINT detected for iteration #$N: $WIP_COMMIT" | tee -a "$LOG_FILE"
  exit 5
fi

# No recognizable commit at all.
if [[ "$WORKER_EXIT" -ne 0 ]]; then
  echo "▶︎ worker failed (exit $WORKER_EXIT) with no close-out or wip commit" | tee -a "$LOG_FILE"
  exit 2
fi

echo "▶︎ worker exited 0 but produced no super-qa: iter $N commit" | tee -a "$LOG_FILE"
exit 3
