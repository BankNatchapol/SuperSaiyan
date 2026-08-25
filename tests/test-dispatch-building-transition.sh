#!/usr/bin/env bash
# test-dispatch-building-transition.sh — the Ready → Building transition belongs to the
# dispatch layer, not the Builder.
#
# Regression guard for a defect where nobody performed it: references/run.md declared
# `Builder: Ready → Building → QA`, but dispatch_lane made no board mutation and super-build
# accepted `Ready/Building → QA`, so `Building` was created at onboard, counted in the tick
# log and the drain-exit guard, and rendered by super-board status — while no code path ever
# wrote it. Cards sat in `Ready` for the whole Build lane.
#
# dispatch_lane is extracted from super-board-run.sh and run against stubs; sourcing the whole
# script would start the tick loop. No live board traffic.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SH="$ROOT/scripts/super-board-run.sh"
PLAN_SH="$ROOT/scripts/super-board-wave-plan.sh"
WAVE_JS="$ROOT/scripts/super-board-wave.js"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

for f in "$RUN_SH" "$PLAN_SH" "$WAVE_JS"; do
  [ -f "$f" ] || { echo "error: $f not found" >&2; exit 1; }
done

echo "checking Ready → Building dispatch ownership"

bash -n "$RUN_SH" || fail "bash -n reported a syntax error in super-board-run.sh"

DISPATCH_FN=$(awk '/^dispatch_lane\(\) \{$/,/^\}$/' "$RUN_SH")
[ -n "$DISPATCH_FN" ] || { echo "error: could not extract dispatch_lane() from $RUN_SH" >&2; exit 1; }

# Harness: everything dispatch_lane touches, stubbed. The stubs append to a TRACE file rather
# than stdout, because dispatch_lane deliberately runs the board mutation under
# `>/dev/null 2>&1` and backend_launch's stdout is consumed as the worker PID. The trace also
# gives us call ordering, which matters here (see case 1).
run_dispatch() {
  # $1 = lane, $2 = variant, $3 = "ok" | "fail" (platform_card_status_set outcome)
  # Echoes the dispatcher's log lines followed by the trace, one event per line.
  local lane="$1" variant="$2" move_outcome="$3"
  local tmp
  tmp=$(mktemp -d)
  DISPATCH_FN="$DISPATCH_FN" lane="$lane" VARIANT="$variant" MOVE_OUTCOME="$move_outcome" \
  INFLIGHT_DIR="$tmp" TRACE="$tmp/trace" bash -c '
    set -euo pipefail
    BUILD_BACKEND=claude-p; QA_BACKEND=claude-p; REVIEW_BACKEND=claude-p
    CONFIG_PATH=/tmp/does-not-matter.json
    BOT_LOGIN=testbot
    BUILD_PID=""; QA_PID=""; REVIEW_PID=""
    BUILD_ISSUE=""; QA_ISSUE=""; REVIEW_ISSUE=""
    : > "$TRACE"

    log() { echo "LOG: $*"; }
    issue_locked() { return 1; }
    try_claim_assignee() { return 0; }
    load_backend() { :; }
    backend_worker_addendum() { :; }
    backend_launch() { echo "LAUNCHED" >> "$TRACE"; echo 4242; }
    platform_card_status_set() {
      echo "CARD_MOVE: $*" >> "$TRACE"
      [ "$MOVE_OUTCOME" = "ok" ]
    }

    eval "$DISPATCH_FN"
    dispatch_lane "$lane" 77
    cat "$TRACE"
  '
  rm -rf "$tmp"
}

# ── 1. Full variant, build lane: the card moves to Building before the worker starts ──
OUT=$(run_dispatch build full ok)
echo "$OUT" | grep -q 'CARD_MOVE: 77 Building' \
  || fail "full/build did not call platform_card_status_set 77 Building"
# Ordering: the move must precede backend_launch so the worker's first board read already
# shows Building, and a crash in the claim→launch window leaves the card visibly mid-flight.
MOVE_LINE=$(echo "$OUT" | grep -n 'CARD_MOVE: 77 Building' | head -1 | cut -d: -f1)
LAUNCH_LINE=$(echo "$OUT" | grep -n 'LAUNCHED' | head -1 | cut -d: -f1)
if [ -z "$MOVE_LINE" ] || [ -z "$LAUNCH_LINE" ] || [ "$MOVE_LINE" -ge "$LAUNCH_LINE" ]; then
  fail "Building move must happen before backend_launch (move=$MOVE_LINE launch=$LAUNCH_LINE)"
fi

# ── 2. Non-build lanes never touch the board ────────────────────────────────────────
for lane in qa review; do
  OUT=$(run_dispatch "$lane" full ok)
  echo "$OUT" | grep -q 'CARD_MOVE:' \
    && fail "full/$lane moved a card — only the build lane owns an entry transition"
  echo "$OUT" | grep -q 'LAUNCHED' || fail "full/$lane did not launch a worker"
done

# ── 3. qa-only boards have no Building column — never attempt the move ──────────────
OUT=$(run_dispatch build qa-only ok)
echo "$OUT" | grep -q 'CARD_MOVE:' \
  && fail "qa-only/build attempted a Building move; that variant has no Building column"

# ── 4. A failed move is non-fatal: warn, launch anyway ──────────────────────────────
# super-build accepts `Ready/Building → QA` and check_lane_zombie's build lane accepts both
# columns, so a card left in Ready still completes. A board-API hiccup must not stall the drain.
OUT=$(run_dispatch build full fail)
echo "$OUT" | grep -q 'LAUNCHED' \
  || fail "a failed Building move aborted the dispatch — it must warn and launch anyway"
echo "$OUT" | grep -q 'could not move #77 Ready → Building' \
  || fail "a failed Building move did not log a warning"
echo "$OUT" | grep -q 'dispatch lane=build issue=#77' \
  || fail "a failed Building move suppressed the dispatch log line"

# ── 5. The build lane's zombie watchdog must keep accepting BOTH columns ────────────
# It is the safety net for case 4; narrowing it to Building alone would kill live builders
# whose move failed.
grep -q 'check_lane_zombie build  *"Ready Building"' "$RUN_SH" \
  || fail "check_lane_zombie build must accept both Ready and Building as source columns"

# ── 6. Workflow backend parity — the planner must be able to re-select a Building card ──
# The orchestrator moves Ready → Building at claim time (references/run-workflow.md step 3).
# Without Building in the full-variant selection, a wave that stops mid-build strands the card
# in a column nothing reads.
PLAN_TMP=$(mktemp -d)
cat > "$PLAN_TMP/items.json" <<'JSON'
{"items":[
  {"id":"i1","status":"Building","content":{"type":"Issue","number":11,"title":"stranded builder","body":"","url":"u","repository":"acme/demo","assignees":[]}},
  {"id":"i2","status":"Ready","content":{"type":"Issue","number":12,"title":"fresh","body":"","url":"u","repository":"acme/demo","assignees":[]}}
]}
JSON
printf '%s\n' '{"variant":"full","max_workers":3,"git_platform":"github","human_approves_merge":true}' > "$PLAN_TMP/full.json"
printf '%s\n' '{"variant":"qa-only","max_workers":3,"git_platform":"github","human_approves_merge":true}' > "$PLAN_TMP/qa.json"

PLAN_FULL=$(bash "$PLAN_SH" --config "$PLAN_TMP/full.json" --items "$PLAN_TMP/items.json")
echo "$PLAN_FULL" | jq -e '[.cards[] | select(.number == 11 and .status == "Building")] | length == 1' >/dev/null \
  || fail "full-variant planner did not select the Building card (got: $PLAN_FULL)"
echo "$PLAN_FULL" | jq -e '[.cards[] | select(.number == 12)] | length == 1' >/dev/null \
  || fail "full-variant planner dropped the Ready card when Building became selectable"

PLAN_QA=$(bash "$PLAN_SH" --config "$PLAN_TMP/qa.json" --items "$PLAN_TMP/items.json")
echo "$PLAN_QA" | jq -e '[.cards[] | select(.status == "Building")] | length == 0' >/dev/null \
  || fail "qa-only planner selected a Building card; that variant has no Building column"
rm -rf "$PLAN_TMP"

# ── 7. …and the wave must route those cards back into the build lane ───────────────
grep -qE "at === 'Ready' \|\| at === 'Building'" "$WAVE_JS" \
  || fail "super-board-wave.js must treat Building as a build-lane entry point"

# ── 8. Docs must name the owner of the transition ──────────────────────────────────
RUN_MD="$ROOT/skills/super-board/references/run.md"
grep -q 'not the Builder' "$RUN_MD" \
  || fail "references/run.md must state that Ready → Building is not the Builder's transition"
WF_MD="$ROOT/skills/super-board/references/run-workflow.md"
grep -q 'super-board-cardmove.sh' "$WF_MD" \
  || fail "references/run-workflow.md claim step must move Ready cards to Building"

if [ "$FAIL" -ne 0 ]; then
  echo "error: Ready → Building dispatch ownership check failed" >&2
  exit 1
fi

echo "PASS: test-dispatch-building-transition.sh"
