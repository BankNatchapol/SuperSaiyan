#!/usr/bin/env bash
# super-build-dispatch.sh — dispatch a single GitHub issue to a headless worker.
#
# Contract (per .claude/skills/super-build/SKILL.md):
#   - Arg: issue number N
#   - Env: BASE_BRANCH    (required) — the branch the worktree is created from
#          REPO_DIR       (optional) — defaults to PWD; the working repo root
#          SKILL_DIR      (optional) — defaults to the dir this script lives in's parent
#          MAX_TURNS      (optional) — default 250 (claude-p backend only)
#          WORKER_BACKEND (optional) — default "claude-p"; also "codex-exec"/"cursor-agent".
#                          See .claude/skills/super-board/references/backends.md.
#          CONFIG_PATH    (optional) — platform/backend config JSON; active config is detected
#                          when omitted.
#   - Side effects:
#       * git worktree add -b loop/issue-N .worktrees/issue-N BASE_BRANCH
#       * runs the configured backend's worker CLI inside that worktree with the composed prompt
#       * captures stdout+stderr to .planning/super-build-logs/issue-N.log
#   - Exit codes:
#       0  success           — worker produced `chore(loop): close #N` commit on loop/issue-N
#       2  worker non-zero   — worker exited non-zero AND no recognizable done/WIP marker
#       3  no done-commit    — worker exited zero but no `chore(loop): close #N` commit
#       4  HUMAN GATE        — log contains `HUMAN GATE TRIPPED:`
#       5  WIP-PARTIAL       — log final assistant message starts with `WIP-PARTIAL:` AND
#                              a `wip(loop): #N partial` commit exists on the branch
#
# Notes:
#   - The dispatcher never merges, never closes the issue, never edits labels — those
#     are the orchestrator's job. This script just runs the worker and reports outcome.
#   - The worktree is left intact in all exit paths so a human can inspect it.

set -uo pipefail

N="${1:-}"
if [[ -z "$N" ]]; then
  echo "usage: $0 <issue-number>" >&2
  exit 64
fi

if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  echo "error: issue number must be numeric, got: $N" >&2
  exit 64
fi

BASE_BRANCH="${BASE_BRANCH:-}"
if [[ -z "$BASE_BRANCH" ]]; then
  echo "error: BASE_BRANCH env var is required" >&2
  exit 64
fi

REPO_DIR="${REPO_DIR:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SKILL_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MAX_TURNS="${MAX_TURNS:-250}"
WORKER_BACKEND="${WORKER_BACKEND:-claude-p}"
EXPLICIT_CONFIG_PATH="${CONFIG_PATH:-}"
CONFIG_RESOLVER="$REPO_DIR/.supersaiyan/bin/platform-config.sh"
if [[ ! -f "$CONFIG_RESOLVER" ]]; then
  CONFIG_RESOLVER="$REPO_DIR/.claude/bin/platform-config.sh"
fi
if [[ ! -f "$CONFIG_RESOLVER" ]]; then
  CONFIG_RESOLVER="$SCRIPT_DIR/../../../scripts/platform-config.sh"
fi
if [[ ! -f "$CONFIG_RESOLVER" ]]; then
  echo "error: platform config resolver not found" >&2
  exit 66
fi
# shellcheck disable=SC1090
source "$CONFIG_RESOLVER"
CONFIG_PATH=$(platform_config_resolve "$REPO_DIR" "$EXPLICIT_CONFIG_PATH") || exit $?
EFFECTIVE=$(platform_config_effective "$CONFIG_PATH") || exit 66
GIT_PLATFORM=$(platform_config_resolve_platform "$EFFECTIVE" "${GIT_PLATFORM:-}") || exit $?
export PLATFORM_CONFIG_PATH="$EFFECTIVE"

# Backend contract (see .claude/skills/super-board/references/backends.md). Three-tier lookup,
# repo-root-relative: .supersaiyan/bin/backends/<name>.sh (new installs, install.sh's current
# copy target) -> .claude/bin/backends/<name>.sh (installs from before the .claude/ -> vendor-
# neutral migration that haven't re-run install.sh yet) -> scripts/backends/<name>.sh relative
# to this script's own location (dev-repo fallback: skills/super-build/scripts/ -> repo root ->
# scripts/backends/).
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

# Platform contract (sibling of backends/). Same three-tier lookup as the backend contract
# above: new-installed layout, then pre-migration installed layout, then dev-repo checkout.
PLATFORM_FILE="$REPO_DIR/.supersaiyan/bin/platforms/${GIT_PLATFORM}.sh"
if [[ ! -f "$PLATFORM_FILE" ]]; then
  PLATFORM_FILE="$REPO_DIR/.claude/bin/platforms/${GIT_PLATFORM}.sh"
fi
if [[ ! -f "$PLATFORM_FILE" ]]; then
  PLATFORM_FILE="$SCRIPT_DIR/../../../scripts/platforms/${GIT_PLATFORM}.sh"
fi
if [[ ! -f "$PLATFORM_FILE" ]]; then
  echo "error: platform contract not found for git_platform=${GIT_PLATFORM} (looked in .supersaiyan/bin/platforms/, .claude/bin/platforms/, and scripts/platforms/)" >&2
  exit 64
fi
# shellcheck disable=SC1090
source "$PLATFORM_FILE"

if ! backend_auth_check; then
  echo "error: backend '${WORKER_BACKEND}' failed its auth check — see message above." >&2
  exit 64
fi

PREAMBLE="$SKILL_DIR/references/worker-preamble.md"
if [[ ! -f "$PREAMBLE" ]]; then
  echo "error: worker preamble not found at $PREAMBLE" >&2
  exit 64
fi

cd "$REPO_DIR" || { echo "error: cannot cd to REPO_DIR=$REPO_DIR" >&2; exit 64; }

# Verify we're in a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: $REPO_DIR is not a git repository" >&2
  exit 64
fi

# Verify base branch exists locally or on origin
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  if ! git rev-parse --verify "origin/$BASE_BRANCH" >/dev/null 2>&1; then
    echo "error: base branch '$BASE_BRANCH' not found locally or on origin" >&2
    exit 64
  fi
fi

WORKTREE_DIR=".worktrees/issue-$N"
WORKER_BRANCH="loop/issue-$N"
LOG_DIR="$REPO_DIR/.planning/super-build-logs"
LOG_FILE="$LOG_DIR/issue-$N.log"
PROMPT_FILE="$LOG_DIR/issue-$N.prompt.md"

mkdir -p "$LOG_DIR"

# Refuse to clobber an existing worktree/branch silently
if [[ -e "$WORKTREE_DIR" ]]; then
  echo "error: worktree path $WORKTREE_DIR already exists — refusing to clobber" >&2
  echo "       (remove with: git worktree remove $WORKTREE_DIR && git branch -D $WORKER_BRANCH)" >&2
  exit 64
fi
if git rev-parse --verify "$WORKER_BRANCH" >/dev/null 2>&1; then
  echo "error: branch $WORKER_BRANCH already exists — refusing to clobber" >&2
  exit 64
fi

# Compose the worker prompt: preamble + issue body + working-dir footer
ISSUE_JSON=$(platform_issue_view "$N" 2>&1) || {
  echo "error: platform_issue_view #$N failed:" >&2
  echo "$ISSUE_JSON" >&2
  exit 64
}

ISSUE_TITLE=$(printf '%s' "$ISSUE_JSON" | jq -r '.title')
ISSUE_BODY=$(printf '%s' "$ISSUE_JSON" | jq -r '.body')

{
  printf '%s' "$(backend_worker_addendum)"
  cat "$PREAMBLE"
  printf '\n# Issue #%s — %s\n\n' "$N" "$ISSUE_TITLE"
  printf '%s\n' "$ISSUE_BODY"
  printf '\n---\n\n'
  printf 'Working directory: %s/%s (branch %s, based on %s)\n' "$REPO_DIR" "$WORKTREE_DIR" "$WORKER_BRANCH" "$BASE_BRANCH"
  printf 'Log file: %s/%s\n' "$REPO_DIR" "$LOG_FILE"
} > "$PROMPT_FILE"

# Create the worktree on a fresh branch off BASE_BRANCH
if ! git worktree add -b "$WORKER_BRANCH" "$WORKTREE_DIR" "$BASE_BRANCH" >>"$LOG_FILE" 2>&1; then
  echo "error: git worktree add failed — see $LOG_FILE" >&2
  exit 64
fi

# Record the base SHA so we can diff afterward
BASE_SHA=$(git -C "$WORKTREE_DIR" rev-parse HEAD)

echo "▶︎ dispatching worker for issue #$N — worktree $WORKTREE_DIR — base $BASE_BRANCH @ ${BASE_SHA:0:7}" | tee -a "$LOG_FILE"

# Run the worker via the backend contract (worker_backend=$WORKER_BACKEND). The composed
# prompt is passed as a CLI arg, not stdin — codex exec / agent -p both require this, and
# claude -p accepts it identically. stdout+stderr both stream to the log. We do NOT use
# --output-format stream-json here because we want a plain-text log we can grep for the
# HUMAN GATE / WIP-PARTIAL markers. The orchestrator gets the same log.
PROMPT_TEXT="$(cat "$PROMPT_FILE")"
WORKER_EXIT=0
(
  cd "$WORKTREE_DIR" || exit 99
  backend_run_sync "$PROMPT_TEXT"
) >>"$LOG_FILE" 2>&1 || WORKER_EXIT=$?

echo "▶︎ worker for issue #$N exited with code $WORKER_EXIT" | tee -a "$LOG_FILE"

# Inspect outcome on the worker branch
HEAD_SHA=$(git -C "$WORKTREE_DIR" rev-parse HEAD)
COMMITS_RANGE="${BASE_SHA}..${HEAD_SHA}"

CLOSE_COMMIT=""
WIP_COMMIT=""
if [[ "$BASE_SHA" != "$HEAD_SHA" ]]; then
  CLOSE_COMMIT=$(git -C "$WORKTREE_DIR" log --format="%H %s" "$COMMITS_RANGE" 2>/dev/null \
    | grep -E "^[0-9a-f]+ chore\(loop\): close #$N( |$)" | head -1 || true)
  WIP_COMMIT=$(git -C "$WORKTREE_DIR" log --format="%H %s" "$COMMITS_RANGE" 2>/dev/null \
    | grep -E "^[0-9a-f]+ wip\(loop\): #$N partial" | head -1 || true)
fi

# Detect HUMAN GATE in log
if grep -q "HUMAN GATE TRIPPED:" "$LOG_FILE"; then
  echo "▶︎ HUMAN GATE TRIPPED detected in log for issue #$N" | tee -a "$LOG_FILE"
  exit 4
fi

# Detect WIP-PARTIAL: requires both the literal log marker AND a wip commit
if [[ -n "$WIP_COMMIT" ]] && grep -q "^WIP-PARTIAL:" "$LOG_FILE"; then
  echo "▶︎ WIP-PARTIAL detected for issue #$N: $WIP_COMMIT" | tee -a "$LOG_FILE"
  exit 5
fi

# Detect success: chore(loop): close commit present
if [[ -n "$CLOSE_COMMIT" ]]; then
  if [[ "$WORKER_EXIT" -ne 0 ]]; then
    echo "▶︎ worker exited non-zero ($WORKER_EXIT) but produced close-commit; treating as success" | tee -a "$LOG_FILE"
  fi
  echo "▶︎ success: $CLOSE_COMMIT" | tee -a "$LOG_FILE"
  exit 0
fi

# No done-commit
if [[ "$WORKER_EXIT" -ne 0 ]]; then
  echo "▶︎ worker failed (exit $WORKER_EXIT) with no done-commit" | tee -a "$LOG_FILE"
  exit 2
fi

echo "▶︎ worker exited 0 but produced no chore(loop): close #$N commit" | tee -a "$LOG_FILE"
exit 3
