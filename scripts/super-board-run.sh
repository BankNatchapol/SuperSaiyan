#!/usr/bin/env bash
# super-board-run.sh — headless autonomous runner.
# Spawned as `nohup scripts/super-board-run.sh <config-slug> &`.
# Pure shell while-loop. Dispatches `claude -p` workers per lane.
# Holds NO Claude session state — re-reads GitHub on every tick.
#
# Anti-zombie controls (added 2026-05-22 after #381 worker-storm incident):
#   1. Orphan scan on startup — refuses to start if super-board claude workers already running.
#   2. Issue-level lock files in <config-root>/inflight/<N> — survives runner restart.
#   3. Atomic GitHub assignee claim BEFORE spawning worker (closes 10-30s claude -p cold-start race).
#   4. Rate-limit guard — sleeps until reset when GraphQL remaining < 200.
#   5. Per-tick project-items cache — one gh call per tick, not per column lookup.
#   6. Tick interval bumped from 30s → 120s (GraphQL ProjectsV2 query is ~103 pts; 120s keeps usage <3.1k/hr vs 5k budget).
#   7. Lane-zombie watchdog (added 2026-05-24 after fitbox-v4 first-run hang) — kills lane PIDs whose
#      claimed issue has already moved out of the lane's expected source column. The worker's logical
#      work is done; if the claude -p process lingers, lane appears busy forever and downstream cards
#      pile up unprocessed. Uses the project-items cache so it costs zero extra API calls per tick.

set -euo pipefail

# ───────────────────────────── args + paths ─────────────────────────────
# Root search order, highest priority first: vendor-neutral (new onboards write only here),
# then the two Claude-Code-branded roots this project used before multi-tool worker_backend
# support (current, then legacy). See scripts/super-board-status.py's config_roots() — same
# fallback chain, independent Python implementation — and references/config-schema.json.
CONFIG_ROOTS=".supersaiyan .claude/supersaiyan .claude/super-board"

CONFIG_SLUG="${1:-}"
if [ -z "$CONFIG_SLUG" ]; then
  # No slug given: the active pointer supplies it. Probe roots for a readable `active` file —
  # whichever root wins is ALSO the root the config lives under (one onboard always writes
  # `active` and `configs/` to the same root together), so CONFIG_ROOT is settled here, not
  # re-derived from config existence below.
  CONFIG_ROOT=""
  for root in $CONFIG_ROOTS; do
    if [ -f "$root/active" ]; then
      CONFIG_ROOT="$root"
      CONFIG_SLUG=$(cat "$root/active")
      break
    fi
  done
  if [ -z "$CONFIG_SLUG" ]; then
    echo "usage: $0 <config-slug>  (or set .supersaiyan/active)" >&2
    exit 64
  fi
else
  # Slug given explicitly (the documented preferred path — see references/onboard.md: "Always
  # pass the slug explicitly"): probe roots for that slug's config directly.
  CONFIG_ROOT=""
  for root in $CONFIG_ROOTS; do
    if [ -f "$root/configs/${CONFIG_SLUG}.json" ]; then
      CONFIG_ROOT="$root"
      break
    fi
  done
  : "${CONFIG_ROOT:=.supersaiyan}"   # not found under any root — new run; error follows below
fi

CONFIG_PATH="$CONFIG_ROOT/configs/${CONFIG_SLUG}.json"
if [ ! -f "$CONFIG_PATH" ]; then
  echo "config not found: $CONFIG_PATH" >&2
  exit 66
fi

# scripts/backends/<name>.sh in this dev repo, .supersaiyan/bin/backends/<name>.sh once
# installed (install.sh copies scripts/backends/, scripts/platforms/, and
# scripts/config-resolve.sh alongside this script). Computed early so config-resolve.sh can be
# sourced before any field is read; reused again below for the backend/platform contract files.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve an optional `extends` link (shared base config for multi-tool boards — see
# references/config-schema.json) before ANY field below is read, via the shared
# persist_resolved_config() — same function the workflow-backend orchestrator calls through
# this file's CLI mode (references/run-workflow.md), so both backends resolve identically.
# Always returns an ABSOLUTE path: with no `extends` that's just CONFIG_PATH's absolute form;
# with `extends` it's a persisted, stable path (not an mktemp file this process's own EXIT trap
# would remove) — required because dispatch_lane embeds CONFIG_PATH verbatim in every worker
# prompt, and workers run from a git worktree, a different cwd than this process, and routinely
# outlive it (a crashed dispatcher leaves orphan workers behind — see references/stop.md).
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config-resolve.sh"
CONFIG_PATH=$(persist_resolved_config "$CONFIG_PATH") || exit 66

# ───────────────────────────── config read ─────────────────────────────
VARIANT=$(jq -r '.variant' "$CONFIG_PATH")
PROJECT_OWNER=$(jq -r '.project.owner' "$CONFIG_PATH")
PROJECT_NUMBER=$(jq -r '.project.number' "$CONFIG_PATH")
BASE_BRANCH=$(jq -r '.base_branch // "main"' "$CONFIG_PATH")
HUMAN_APPROVES=$(jq -r '.human_approves_merge // false' "$CONFIG_PATH")
REBUILD_CAP=$(jq -r '.rebuild_cap // 2' "$CONFIG_PATH")
BLOCK_ALERT_PCT=$(jq -r '.block_rate_alert_pct // 30' "$CONFIG_PATH")
TICK_SECONDS=$(jq -r '.tick_seconds // 120' "$CONFIG_PATH")
MAX_WORKERS=$(jq -r '.max_workers // 3' "$CONFIG_PATH")
BOT_LOGIN=$(jq -r '.notifications.bot_identity // .bot_identity // ""' "$CONFIG_PATH")
GIT_PLATFORM=$(jq -r '.git_platform // "github"' "$CONFIG_PATH")

# worker_backend is either a single string (back-compat — one backend for every lane) or an
# object mapping lane -> backend name (per-lane routing; see references/backends.md).
# Branch on `type` first: `jq -r` only unquotes top-level JSON *strings*, so reading an object
# with a plain `jq -r '.worker_backend'` yields compact JSON text, not a usable backend name.
WORKER_BACKEND_TYPE=$(jq -r '(.worker_backend // "workflow") | type' "$CONFIG_PATH")
if [ "$WORKER_BACKEND_TYPE" = "object" ]; then
  # No single WORKER_BACKEND value exists in this shape — the three lane scalars below are
  # the only backend identity, and the startup log reports them via BACKEND_SUMMARY.
  BUILD_BACKEND=$(jq -r '.worker_backend.build // "claude-p"' "$CONFIG_PATH")
  QA_BACKEND=$(jq -r '.worker_backend.qa // "claude-p"' "$CONFIG_PATH")
  REVIEW_BACKEND=$(jq -r '.worker_backend.review // "claude-p"' "$CONFIG_PATH")
else
  WORKER_BACKEND=$(jq -r '.worker_backend // "workflow"' "$CONFIG_PATH")
  BUILD_BACKEND="$WORKER_BACKEND"
  QA_BACKEND="$WORKER_BACKEND"
  REVIEW_BACKEND="$WORKER_BACKEND"
fi

# Workflow is the default backend (v1.6.0). This dispatcher only runs when the config opts
# into one of the bash-dispatcher backends explicitly — never by accident or stale habit.
# See references/backends.md for the full contract.
validate_backend_name() {
  case "$1" in
    claude-p|codex-exec|cursor-agent) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$WORKER_BACKEND_TYPE" = "object" ]; then
  # Validate only the lanes this variant actually dispatches — a qa-only board never uses
  # BUILD_BACKEND, so a missing/stray "build" key there is not fatal.
  REQUIRED_LANES="qa review"
  [ "$VARIANT" = "full" ] && REQUIRED_LANES="build qa review"
  for lane in $REQUIRED_LANES; do
    case "$lane" in
      build)  lane_backend="$BUILD_BACKEND" ;;
      qa)     lane_backend="$QA_BACKEND" ;;
      review) lane_backend="$REVIEW_BACKEND" ;;
    esac
    if ! validate_backend_name "$lane_backend"; then
      echo "🛑 board '${CONFIG_SLUG}' worker_backend.${lane}=\"${lane_backend}\" is not a valid bash-dispatcher backend." >&2
      echo "    Set worker_backend.${lane} to \"claude-p\", \"codex-exec\", or \"cursor-agent\"." >&2
      echo "    \"workflow\" is Claude-Code-session-bound and is never valid per-lane (see references/run-workflow.md)." >&2
      exit 78
    fi
  done
else
  if ! validate_backend_name "$WORKER_BACKEND"; then
    echo "🛑 board '${CONFIG_SLUG}' uses the workflow backend (worker_backend=${WORKER_BACKEND})." >&2
    echo "    Run it in-session: /super-board run ${CONFIG_SLUG}  (see references/run-workflow.md)" >&2
    echo "    To use this dispatcher, set \"worker_backend\" to \"claude-p\", \"codex-exec\", \"cursor-agent\", or a per-lane object in the config." >&2
    exit 78
  fi
fi

# Backend contract: scripts/backends/<name>.sh in this dev repo, .supersaiyan/bin/backends/<name>.sh
# once installed (install.sh copies scripts/backends/ alongside this script). SCRIPT_DIR was
# already computed above, before extends resolution.

# `source`-ing a backend file overwrites every backend_* function in the current shell —
# the contract has no namespacing. load_backend() is therefore the ONLY place that sources a
# backend file, and every call site must call it for the lane's backend IMMEDIATELY before
# invoking any backend_* function, in the same synchronous flow. Sourcing one "for later" is
# never valid: only the most-recently-sourced file's functions are live.
load_backend() {
  # Two statements, not one `local a=... b=...$a...`: bash expands every word on a `local`
  # line before the builtin runs, so referencing $name in the same statement that declares it
  # is an unbound-variable error under `set -u`.
  local name="$1"
  local file="$SCRIPT_DIR/backends/${name}.sh"
  if [ ! -f "$file" ]; then
    echo "🛑 backend contract not found: $file (worker_backend=${name})" >&2
    exit 77
  fi
  # shellcheck disable=SC1090
  source "$file"
}

# Per-tool model overrides — one setting per TOOL, applied wherever that tool is used across
# lanes (not per lane x tool). An env var already set by the caller wins; otherwise fall back
# to the board config. Exported so the backend files pick them up; each backend still reads
# them with inline `${VAR:-}` defaulting, so callers that never set them (super-build-dispatch,
# super-qa-dispatch) keep working unchanged under `set -u`.
CODEX_MODEL="${CODEX_MODEL:-}"
CODEX_REASONING_EFFORT="${CODEX_REASONING_EFFORT:-}"
CURSOR_MODEL="${CURSOR_MODEL:-}"
[ -z "$CODEX_MODEL" ] && CODEX_MODEL=$(jq -r '.codex.model // ""' "$CONFIG_PATH")
[ -z "$CODEX_REASONING_EFFORT" ] && CODEX_REASONING_EFFORT=$(jq -r '.codex.reasoning_effort // ""' "$CONFIG_PATH")
[ -z "$CURSOR_MODEL" ] && CURSOR_MODEL=$(jq -r '.cursor.model // ""' "$CONFIG_PATH")
export CODEX_MODEL CODEX_REASONING_EFFORT CURSOR_MODEL

# Distinct backends actually in use this run, scoped to the lanes this variant dispatches.
# bash 3.2 (macOS default) has no associative arrays; with at most three known lane scalars,
# `sort -u` is simpler and safer than hand-rolled array dedup.
if [ "$VARIANT" = "full" ]; then
  DISTINCT_BACKENDS=$(printf '%s\n' "$BUILD_BACKEND" "$QA_BACKEND" "$REVIEW_BACKEND" | sort -u)
else
  DISTINCT_BACKENDS=$(printf '%s\n' "$QA_BACKEND" "$REVIEW_BACKEND" | sort -u)
fi

for backend_name in $DISTINCT_BACKENDS; do
  load_backend "$backend_name"
  if ! backend_auth_check; then
    echo "🛑 backend '${backend_name}' failed its auth check — see message above." >&2
    exit 76
  fi
done

# Platform contract: scripts/platforms/<name>.sh in this dev repo, .supersaiyan/bin/platforms/<name>.sh
# once installed (install.sh copies scripts/platforms/ alongside this script).
# Sibling of the backends/ axis above — not an alternative. git_platform and worker_backend compose.
PLATFORM_FILE="$SCRIPT_DIR/platforms/${GIT_PLATFORM}.sh"
if [ ! -f "$PLATFORM_FILE" ]; then
  echo "🛑 platform contract not found: $PLATFORM_FILE (git_platform=${GIT_PLATFORM})" >&2
  exit 77
fi
# shellcheck disable=SC1090
source "$PLATFORM_FILE"
# GitLab adapters resolve host/full_path from this path. GitHub ignores it
# when owner/number are passed explicitly. Export before any platform_* call.
export PLATFORM_CONFIG_PATH="$CONFIG_PATH"

RUN_DATE=$(date +%Y-%m-%d)
RUN_MANIFEST="docs/supersaiyan/runs/${RUN_DATE}-${CONFIG_SLUG}.md"
# Colocated with CONFIG_PATH's resolved root, not always .supersaiyan — inflight locks are a
# byproduct of a specific run of a specific config; splitting config-root from state-root would
# let two invocations against an old-root config race on locks nobody's watching in the new root.
INFLIGHT_DIR="$CONFIG_ROOT/inflight"
mkdir -p "docs/supersaiyan/runs" .worktrees "$INFLIGHT_DIR"

# ───────────────────────────── helpers ─────────────────────────────
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$RUN_MANIFEST"; }

PROJECT_ITEMS_JSON=""
fetch_project_items() {
  # One board snapshot per tick; all column lookups read from this cache.
  PROJECT_ITEMS_JSON=$(platform_board_snapshot "$CONFIG_PATH")
}

column_count() {
  # Active lanes ignore CLOSED cards (GitLab scope=all keeps leftover status::*
  # on closed issues). Done/Blocked/Skipped still count every state.
  echo "$PROJECT_ITEMS_JSON" | jq --arg col "$1" '
    [.items[]
     | select(.status == $col)
     | select(
         ($col != "Ready" and $col != "Building" and $col != "QA" and $col != "Review")
         or ((.state // "OPEN") | ascii_upcase) != "CLOSED"
       )] | length'
}

top_card_in_column() {
  # Returns the FIRST issue number in $1 with no assignee AND no local in-flight lock.
  local col="$1" issue
  for issue in $(echo "$PROJECT_ITEMS_JSON" | jq -r --arg col "$col" '
        .items[]
        | select(.status == $col and .content.type == "Issue")
        | select(((.state // "OPEN") | ascii_upcase) != "CLOSED")
        | select((.content.assignees // []) | length == 0)
        | .content.number'); do
    if ! issue_locked "$issue"; then
      echo "$issue"
      return 0
    fi
  done
}

read_lock() {
  # Reads $INFLIGHT_DIR/$1 (bash-assignment format) into PID/LANE/STARTED.
  # Sets empty strings if the file is missing or legacy single-PID format.
  local lock="$INFLIGHT_DIR/$1"
  PID=""; LANE=""; STARTED=""
  [ -f "$lock" ] || return 1
  if grep -q '^PID=' "$lock" 2>/dev/null; then
    # shellcheck disable=SC1090
    . "$lock" 2>/dev/null || true
  else
    # Legacy format (pre v1.3.0): single line PID only.
    PID=$(cat "$lock" 2>/dev/null || echo "")
  fi
  return 0
}

issue_locked() {
  # Returns 0 if the issue has a live in-flight lock; cleans stale locks.
  local issue="$1" lock="$INFLIGHT_DIR/$1"
  [ -f "$lock" ] || return 1
  read_lock "$issue"
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    return 0
  fi
  rm -f "$lock"
  return 1
}

lane_idle() {
  local pid="${1:-}"
  [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null
}

gh_rate_guard() {
  # Sleep until rate limit resets if GraphQL remaining < 200.
  # Remaining comes from the platform; sleep/reset math lives in platform_rate_guard
  # (reset timestamp is not part of platform_rate_remaining's return value).
  local remaining
  remaining=$(platform_rate_remaining graphql)
  # GitLab often prints "unknown" (headers omitted). Non-digits fail-open.
  case "$remaining" in
    ''|*[!0-9]*) return 0 ;;
  esac
  if [ "$remaining" -lt 200 ]; then
    log "⚠ GraphQL rate limit low (${remaining} left) — sleeping until reset"
    platform_rate_guard 200
  fi
}

try_claim_assignee() {
  # Atomic claim. Returns 0 if we won the claim, 1 if someone else beat us.
  # Skipped when bot_identity is unset (solo single-user runs rely on local locks only).
  # We rely on `top_card_in_column` having already filtered out cards with assignees
  # from the cached project item-list — so we attempt the edit directly without a
  # pre-check `gh issue view`. Saves one GraphQL call per dispatch. The edit is
  # idempotent for self-assign; on race-loss, gh returns non-zero and we skip.
  local issue="$1"
  [ -z "$BOT_LOGIN" ] && return 0
  platform_claim_issue "$issue" "$BOT_LOGIN" >/dev/null 2>&1 || {
    log "claim failed on #${issue} (race or gh api error) — skipping this tick"
    return 1
  }
  return 0
}

dispatch_lane() {
  # $1 = lane (build|qa|review); $2 = issue number
  local lane="$1" issue="$2" prompt pid backend
  if issue_locked "$issue"; then
    log "skip dispatch lane=${lane} issue=#${issue} — already locked"
    return 0
  fi
  if ! try_claim_assignee "$issue"; then
    return 0
  fi
  case "$lane" in
    build)  backend="$BUILD_BACKEND" ;;
    qa)     backend="$QA_BACKEND" ;;
    review) backend="$REVIEW_BACKEND" ;;
    *) log "unknown lane: $lane"; return 1 ;;
  esac
  # Re-source this lane's backend immediately before use (see load_backend's contract note).
  # Safe because dispatch_lane calls never overlap: the main loop invokes it synchronously,
  # at most once per lane per tick, and only the launched worker backgrounds — so there is no
  # window in which another lane's backend_* functions are live during this dispatch.
  load_backend "$backend"
  case "$lane" in
    build)  prompt="Run super-build on issue #${issue} for super-board run. Read .claude/skills/super-board/references/run.md → Builder lifecycle. Config: ${CONFIG_PATH}." ;;
    qa)     prompt="Run super-qa on issue #${issue} for super-board run. Read .claude/skills/super-board/references/run.md → Tester lifecycle. Config: ${CONFIG_PATH}." ;;
    review) prompt="Run super-review on issue #${issue} for super-board run. Read .claude/skills/super-board/references/run.md → Reviewer lifecycle. Config: ${CONFIG_PATH}." ;;
  esac
  pid=$(backend_launch "$(backend_worker_addendum)${prompt}")
  # v1.3.0+ lock format: bash-assignment style so `super-board stop` can source it
  # to recover lane + dispatch time. issue_locked()/reap_finished_locks() still work
  # because PID= is the first line.
  printf 'PID=%s\nLANE=%s\nSTARTED=%s\n' "$pid" "$lane" "$(date -u +%FT%TZ)" > "$INFLIGHT_DIR/$issue"
  case "$lane" in
    build) BUILD_PID="$pid"; BUILD_ISSUE="$issue" ;;
    qa) QA_PID="$pid"; QA_ISSUE="$issue" ;;
    review) REVIEW_PID="$pid"; REVIEW_ISSUE="$issue" ;;
  esac
  log "dispatch lane=${lane} issue=#${issue} backend=${backend} pid=${pid} claim=${BOT_LOGIN:-local-only}"
}

issue_status() {
  # Lookup issue #$1 in the cached project items; emit its current column name (or empty).
  echo "$PROJECT_ITEMS_JSON" | jq -r --arg n "$1" '
    .items[] | select(.content.number == ($n | tonumber)) | .status' | head -1
}

check_lane_zombie() {
  # $1 = lane name (build|qa|review); $2 = space-separated list of expected source columns.
  # If the lane's worker PID is alive but its claimed issue has already moved to a column
  # NOT in the expected source set, the worker's logical work is done — kill the zombie
  # process and free the lane. Uses cached project items only (no extra API calls).
  local lane="$1" expected="$2" pid="" issue=""
  case "$lane" in
    build)  pid="$BUILD_PID";  issue="$BUILD_ISSUE" ;;
    qa)     pid="$QA_PID";     issue="$QA_ISSUE" ;;
    review) pid="$REVIEW_PID"; issue="$REVIEW_ISSUE" ;;
    *) return 1 ;;
  esac
  [ -z "$pid" ] && return 0
  [ -z "$issue" ] && return 0
  kill -0 "$pid" 2>/dev/null || return 0   # already dead → reap_finished_locks handles it
  local cur found=0 col
  cur=$(issue_status "$issue")
  [ -z "$cur" ] && return 0                # not in cache (closed/deleted/race) → don't kill
  for col in $expected; do
    [ "$cur" = "$col" ] && found=1
  done
  if [ "$found" -eq 0 ]; then
    log "💀 zombie ${lane} worker on #${issue} (pid=${pid}) — card moved to '${cur}'; killing"
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$INFLIGHT_DIR/$issue"
    [ -n "$BOT_LOGIN" ] && platform_release_issue "$issue" "$BOT_LOGIN" >/dev/null 2>&1 || true
    case "$lane" in
      build)  BUILD_PID="";  BUILD_ISSUE="" ;;
      qa)     QA_PID="";     QA_ISSUE="" ;;
      review) REVIEW_PID=""; REVIEW_ISSUE="" ;;
    esac
  fi
}

sweep_lane_zombies() {
  check_lane_zombie build  "Ready Building"
  check_lane_zombie qa     "QA"
  check_lane_zombie review "Review"
}

reap_finished_locks() {
  # Sweep inflight/ for dead PIDs; remove locks AND sweep stale assignees so the
  # next dispatch can re-claim the card if the worker crashed without releasing.
  # The assignee remove is idempotent — no-op if the worker exited cleanly.
  local lock issue
  for lock in "$INFLIGHT_DIR"/*; do
    [ -f "$lock" ] || continue
    issue=$(basename "$lock")
    # Issue locks only: basenames are issue numbers. Anything else (e.g. the
    # workflow backend's workflow-wave.lock) is not ours to reap — deleting it
    # would dissolve the backend mutual exclusion mid-run.
    case "$issue" in *[!0-9]*|'') continue ;; esac
    read_lock "$issue"
    if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
      rm -f "$lock"
      if [ -n "$BOT_LOGIN" ]; then
        platform_release_issue "$issue" "$BOT_LOGIN" >/dev/null 2>&1 || true
        log "reaped stale lock + swept assignee on #${issue} (pid=${PID:-empty})"
      else
        log "reaped stale lock for #${issue} (pid=${PID:-empty})"
      fi
    fi
  done
}

# ───────────────────────────── preconditions ─────────────────────────────
BACKEND_SUMMARY="qa=${QA_BACKEND} review=${REVIEW_BACKEND}"
[ "$VARIANT" = "full" ] && BACKEND_SUMMARY="build=${BUILD_BACKEND} ${BACKEND_SUMMARY}"
log "super-board run started — config=${CONFIG_SLUG} variant=${VARIANT} base=${BASE_BRANCH} tick=${TICK_SECONDS}s max_workers=${MAX_WORKERS} backends: ${BACKEND_SUMMARY}"
log "worker config path (embedded in every dispatch_lane prompt): ${CONFIG_PATH}"

# Orphan-worker guard — one scan per distinct backend in use this run, since a per-lane
# config can have up to three live at once and each has its own pgrep pattern.
# `|| true` defends against pipefail when pgrep finds nothing.
ORPHAN_TOTAL=0
ORPHAN_HINTS=()
for backend_name in $DISTINCT_BACKENDS; do
  load_backend "$backend_name"
  ORPHAN_PATTERN="$(backend_orphan_pattern)"
  ORPHANS=$(pgrep -f "$ORPHAN_PATTERN" 2>/dev/null | grep -v "^$$\$" | wc -l | tr -d ' ' || true)
  ORPHANS=${ORPHANS:-0}
  if [ "$ORPHANS" -gt 0 ]; then
    log "🛑 ${ORPHANS} ${backend_name} worker(s) already running (pattern: ${ORPHAN_PATTERN})"
    ORPHAN_TOTAL=$((ORPHAN_TOTAL + ORPHANS))
    ORPHAN_HINTS+=("pkill -f '${ORPHAN_PATTERN}'")
  fi
done
if [ "$ORPHAN_TOTAL" -gt 0 ]; then
  # ORPHAN_HINTS is only expanded inside this branch, where it is guaranteed non-empty —
  # bash 3.2 treats expanding an empty array under `set -u` as an unbound-variable error.
  log "🛑 refusing to start: ${ORPHAN_TOTAL} worker(s) already running."
  for orphan_hint in "${ORPHAN_HINTS[@]}"; do
    log "    Stop them first: ${orphan_hint}"
  done
  log "    Then re-run: $0 $CONFIG_SLUG"
  exit 73
fi

# Workflow-backend mutual exclusion (see references/run-workflow.md §Preconditions).
# Colocated with the resolved CONFIG_ROOT (see INFLIGHT_DIR above) — the workflow backend and
# this bash dispatcher must contend for the same lock file regardless of which root a given
# board's config happens to live under.
WAVE_LOCK="$INFLIGHT_DIR/workflow-wave.lock"
if [ -f "$WAVE_LOCK" ]; then
  log "🛑 refusing to start: workflow-backend wave in flight ($WAVE_LOCK exists)."
  log "    If no wave is actually running, remove the stale lock: rm $WAVE_LOCK"
  exit 74
fi

# Production-merge guard.
if [ "$BASE_BRANCH" = "main" ] && [ "$HUMAN_APPROVES" = "false" ]; then
  if platform_detect_production_ci; then
    log "🛡 refusing to start: would auto-merge to production main."
    exit 75
  fi
fi

# Stale-worktree scan.
if [ -d .worktrees ]; then
  for wt in .worktrees/*/; do
    [ -d "$wt" ] || continue
    branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ -z "$branch" ] || ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
      log "stale worktree: $wt (branch '$branch' missing) — removing"
      git worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    fi
  done
fi

# Reap any leftover stale locks from a previous crashed run.
reap_finished_locks

# ───────────────────────────── main loop ─────────────────────────────
gh_rate_guard
fetch_project_items
INITIAL_READY=$(column_count "Ready")
log "initial Ready count: $INITIAL_READY"

NO_PROGRESS_TICKS=0
BUILD_PID=""; BUILD_ISSUE=""
QA_PID=""; QA_ISSUE=""
REVIEW_PID=""; REVIEW_ISSUE=""

while true; do
  # Workflow-backend mutual exclusion, re-checked every tick: the startup
  # check alone leaves a TOCTOU window where a workflow run starting at the
  # same moment as this dispatcher is never detected by either side.
  if [ -f "$WAVE_LOCK" ]; then
    log "🛑 workflow-backend wave appeared mid-run ($WAVE_LOCK) — halting for mutual exclusion."
    log "    Resume after the wave: $0 $CONFIG_SLUG"
    exit 74
  fi

  reap_finished_locks  # cheap local sweep; runs every tick

  # ── Zombie sweep against the LAST cached project state (no extra API).
  #    Catches workers whose card already moved out of the lane's source column
  #    but whose claude -p process didn't exit. Runs every tick, even cheap ones,
  #    so a cap-reached pipeline can still self-heal when one lane is a zombie.
  sweep_lane_zombies

  # ── Free pre-check: count active lanes from local PIDs (no API calls).
  BUILD_IDLE=1; QA_IDLE=1; REVIEW_IDLE=1
  lane_idle "$BUILD_PID" || BUILD_IDLE=0
  lane_idle "$QA_PID" || QA_IDLE=0
  lane_idle "$REVIEW_PID" || REVIEW_IDLE=0

  ACTIVE_WORKERS=0
  [ "$BUILD_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
  [ "$QA_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
  [ "$REVIEW_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))

  # ── Cheap-tick path: workers at cap → skip GraphQL fetch entirely.
  #    The board can't change in a way that helps us until a lane frees up.
  if [ "$ACTIVE_WORKERS" -ge "$MAX_WORKERS" ]; then
    log "tick — cap reached (${ACTIVE_WORKERS}/${MAX_WORKERS} busy) — skipping GraphQL fetch, sleeping ${TICK_SECONDS}s"
    sleep "$TICK_SECONDS"
    continue
  fi

  # ── Expensive-tick path: we have capacity, fetch real state.
  gh_rate_guard
  fetch_project_items

  # Re-sweep zombies against fresh cache; the previous sweep used stale data.
  sweep_lane_zombies
  BUILD_IDLE=1; QA_IDLE=1; REVIEW_IDLE=1
  lane_idle "$BUILD_PID" || BUILD_IDLE=0
  lane_idle "$QA_PID" || QA_IDLE=0
  lane_idle "$REVIEW_PID" || REVIEW_IDLE=0
  ACTIVE_WORKERS=0
  [ "$BUILD_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
  [ "$QA_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
  [ "$REVIEW_IDLE" -eq 1 ] || ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))

  READY=$(column_count "Ready")
  BUILDING=0
  [ "$VARIANT" = "full" ] && BUILDING=$(column_count "Building")
  QA=$(column_count "QA")
  REVIEW=$(column_count "Review")
  BLOCKED=$(column_count "Blocked")

  log "tick — Ready=$READY Building=$BUILDING QA=$QA Review=$REVIEW Blocked=$BLOCKED lanes: b_idle=$BUILD_IDLE(#${BUILD_ISSUE:-_}) q_idle=$QA_IDLE(#${QA_ISSUE:-_}) r_idle=$REVIEW_IDLE(#${REVIEW_ISSUE:-_})"

  if [ "$READY" -eq 0 ] && [ "$BUILDING" -eq 0 ] && [ "$QA" -eq 0 ] && [ "$REVIEW" -eq 0 ] \
     && [ "$BUILD_IDLE" -eq 1 ] && [ "$QA_IDLE" -eq 1 ] && [ "$REVIEW_IDLE" -eq 1 ]; then
    log "✅ all active-pipeline columns empty and all lanes idle — exiting cleanly"
    break
  fi

  if [ "${BLOCK_ALERT_SENT:-0}" -eq 0 ] && [ "$INITIAL_READY" -gt 0 ] && [ "$BLOCK_ALERT_PCT" -gt 0 ]; then
    PCT=$(( BLOCKED * 100 / INITIAL_READY ))
    if [ "$PCT" -ge "$BLOCK_ALERT_PCT" ]; then
      log "⚠ block-rate alert: ${BLOCKED}/${INITIAL_READY} (${PCT}%)"
      BLOCK_ALERT_SENT=1
    fi
  fi

  PROGRESS=0

  # ACTIVE_WORKERS already computed at top of loop (free pre-check).
  can_dispatch() {
    [ "$ACTIVE_WORKERS" -lt "$MAX_WORKERS" ]
  }

  if can_dispatch && [ "$REVIEW" -gt 0 ] && [ "$REVIEW_IDLE" -eq 1 ]; then
    card=$(top_card_in_column "Review")
    if [ -n "${card:-}" ]; then
      dispatch_lane review "$card"
      PROGRESS=1
      ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
    fi
  fi
  if can_dispatch && [ "$QA" -gt 0 ] && [ "$QA_IDLE" -eq 1 ]; then
    card=$(top_card_in_column "QA")
    if [ -n "${card:-}" ]; then
      dispatch_lane qa "$card"
      PROGRESS=1
      ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
    fi
  fi
  if can_dispatch && [ "$VARIANT" = "full" ] && [ "$READY" -gt 0 ] && [ "$BUILD_IDLE" -eq 1 ]; then
    card=$(top_card_in_column "Ready")
    if [ -n "${card:-}" ]; then
      dispatch_lane build "$card"
      PROGRESS=1
      ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
    fi
  fi
  if can_dispatch && [ "$VARIANT" = "qa-only" ] && [ "$READY" -gt 0 ] && [ "$QA_IDLE" -eq 1 ]; then
    card=$(top_card_in_column "Ready")
    if [ -n "${card:-}" ]; then
      dispatch_lane qa "$card"
      PROGRESS=1
      ACTIVE_WORKERS=$((ACTIVE_WORKERS + 1))
    fi
  fi

  if [ "$PROGRESS" -eq 0 ]; then
    if [ "$BUILD_IDLE" -eq 0 ] || [ "$QA_IDLE" -eq 0 ] || [ "$REVIEW_IDLE" -eq 0 ]; then
      NO_PROGRESS_TICKS=0
    else
      NO_PROGRESS_TICKS=$((NO_PROGRESS_TICKS + 1))
      if [ "$NO_PROGRESS_TICKS" -ge 3 ]; then
        log "🛑 halt — no card progressed for 3 ticks while all lanes idle"
        break
      fi
    fi
  else
    NO_PROGRESS_TICKS=0
  fi

  sleep "$TICK_SECONDS"
done

log "super-board run finished. manifest: $RUN_MANIFEST"
