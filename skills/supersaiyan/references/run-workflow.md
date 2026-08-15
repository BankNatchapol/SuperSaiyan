<!-- GENERATED FILE — edit skills/super-board/references/run-workflow.md, then run scripts/generate-supersaiyan-references.sh to regenerate. Do not hand-edit. -->

# super-board run — workflow backend contract

The DEFAULT backend (v1.6.0+): used when the active config sets
`"worker_backend": "workflow"` or omits the key. The bash dispatcher
(`.supersaiyan/bin/super-board-run.sh`, see `run.md`) runs on explicit
`"worker_backend": "claude-p"`, `"codex-exec"`, `"cursor-agent"`, or a
per-lane object mapping lane → one of those three; this file ONLY changes
who dispatches workers. Lane lifecycles, branch/PR model, comment cadence,
Block templates, halt gates, and done conditions are all inherited from
`run.md` unchanged.

## Orchestrator delegation contract (NON-NEGOTIABLE, adapted)

The interactive session that runs this backend is the orchestrator. It:
- polls the board, claims assignees, launches workflow waves, reconciles
  results, posts notifications, and reports to the user between waves;
- does NOT do product work, patch lane skills mid-run, or hold per-card
  build context. Lane agents inside the workflow do all product work.

## Preconditions (before the first wave)

Run the same preconditions as `run.md` §Preconditions, minus PID checks:
1. Config exists and validates against `config-schema.json`. Resolve `extends` via
   `bash .supersaiyan/bin/config-resolve.sh --effective-path <config-path>` — prints an
   absolute path to stdout and exits 0. Read every field from THIS point on — `variant`,
   `human_approves_merge`, `tier`/`model_tier`, and the `configPath` passed to Launch in step
   4 — from the printed path, never from the raw `configs/<slug>.json`. Halt if the command
   exits non-zero (its stderr names the problem: missing base, or the base itself setting
   `extends` — chains aren't supported).

   Use the CLI, not the raw config, even though `configs/<slug>.json` "looks" readable:
   without `extends` the printed path is just that file's absolute form (no behavior change),
   but with `extends` the raw file is missing every inherited field (`project`,
   `base_branch`, ...) — reading it directly silently drops them.

   **Always pass the raw `configs/<slug>.json` as the CLI's INPUT — never feed it a path it
   printed earlier.** The distinction is input vs output: the printed path is what you *read
   fields from*; `configs/<slug>.json` is what you *resolve from*, every time. This matters
   because you re-run these preconditions on every `/loop` re-entry. Re-resolving an already-
   resolved file is silently a no-op — the merge strips `extends`, so a second pass sees a
   config with no link to follow and hands the same path straight back without re-reading the
   base. Feed back your own output and you pin the run to whatever the base said the first
   time: edit `rebuild_cap` in the base between waves and the change is silently ignored,
   breaking the guarantee in `references/onboard.md` step 2 that "every tool's next dispatcher
   run picks it up". The CLI now refuses paths whose parent directory is named `resolved/`
   (nonzero, stderr names the raw overlay) so that mix-up fails loudly instead of succeeding
   with a stale merge. The legacy dispatcher is immune by construction — `super-board-run.sh`
   always starts from `$CONFIG_ROOT/configs/<slug>.json` — so this is an
   orchestrator-discipline rule, not a resolver bug.

   `scripts/super-board-run.sh` (the legacy dispatcher) resolves `extends` the same way —
   via `persist_resolved_config()` — before handing a config path to a worker; the
   orchestrator here shells out to it via the CLI instead of sourcing it because it is a
   Claude Code session, not a bash script. `scripts/super-board-wave-plan.sh` (step 2 below)
   resolves the same `extends` link too, but via `resolve_config_extends()` directly rather
   than `persist_resolved_config()` — it only reads fields for its own JSON output and never
   hands the path to anything else, so it wants that function's plain temp-and-clean
   semantics (and needs its FIFO test-mode support, which `persist_resolved_config()`'s
   real-file requirement doesn't provide).

   **`<config-root>` (used in step 5a and Stop/resume below) is NOT derived from this
   effective path.** The effective path from `--effective-path` is for *reading config
   fields* only — with `extends` it may point under `<root>/resolved/`, which is a
   subdirectory, not the root itself. `<config-root>` stays whatever directory directly
   contains `configs/` for this config (`.supersaiyan/`, or a legacy root — see
   `scripts/super-board-run.sh`'s `CONFIG_ROOTS` probe) — the SAME value both backends must
   agree on for the mutual-exclusion lock in step 5a to actually exclude anything.
2. Production-merge guard: refuse `base_branch: main` + `human_approves_merge:
   false` when deploy markers exist (same rule as super-board-run.sh).
3. Stale-worktree scan: remove `.worktrees/*` whose branch is gone.
4. `node --check` passes on a wrapped copy of
   `.supersaiyan/workflows/super-board-wave.js` (catches a broken script before
   burning tokens):
   `{ echo '(async function(){'; sed 's/^export const meta/const meta/' .supersaiyan/workflows/super-board-wave.js; echo '})'; } | node --check --input-type=module`
5. Wave marker FIRST, then the legacy check (lock-before-look closes the
   TOCTOU window where both backends pass each other's checks at once):
   a. Atomically create `<config-root>/inflight/workflow-wave.lock` — under the config root
      as defined in step 1 above (the directory containing `configs/`; `.supersaiyan/` for a
      fresh onboard, or a legacy root for a pre-migration install — NOT the `resolved/`
      subdirectory the effective config path may live under)
      (mkdir -p the directory) containing the config slug and start time:
      `(set -C; printf 'SLUG=%s\nSTARTED=%s\n' <slug> "$(date -u +%FT%TZ)" > <lock>)`.
      If it already exists and `/workflows` shows no running
      super-board-wave, it is stale from a crashed run — replace it.
      Remove the lock when the run ends or stops. The legacy dispatcher
      refuses to start (and halts mid-run) while it exists.
   b. THEN verify no legacy run is active: BOTH
      `pgrep -f 'super-board-run.sh'` (the legacy dispatcher idles between
      dispatches with zero workers alive) and
      `pgrep -f 'claude -p .*super-board run'` are empty, AND `/workflows`
      shows no running super-board-wave. If a legacy run is detected,
      remove the lock just created and stop — the legacy run won.
6. Crash-recovery sweep (the workflow backend's equivalent of the legacy
   reaper): with no wave running, strip `bot_identity` from any
   Review/QA/Ready/Building card that still carries it
   (`gh issue edit <n> --remove-assignee <bot_identity>`). A crashed
   orchestrator releases nothing — leaked assignees make the planner skip
   those cards forever and the board silently stops draining.

## The wave loop

Repeat until a done condition or halt gate fires:

1. **Rate guard** — `gh api rate_limit`; if GraphQL remaining < 200, wait for
   reset (same thresholds as run.md).
2. **Plan the wave** —
   `bash .supersaiyan/bin/super-board-wave-plan.sh --config <config-path>` →
   `{cards: [...]}`. Selection is backlog-aware: one card per non-empty
   column downstream-first (Review → QA → Ready), then remaining
   `max_workers` slots fill from the most backlogged column; extra Review
   cards only when `human_approves_merge: true` (merge-race guard). If
   `cards` is empty and Building/QA/Review counts are 0 → done. If empty
   but cards sit in Blocked only → report and stop.
3. **Claim** — for each card, `gh issue edit <n> --add-assignee <bot_identity>`,
   then VERIFY: re-read assignees (`gh issue view <n> --json assignees`) and
   proceed only if the list is exactly `[<bot_identity>]`. Adding an assignee
   does NOT fail when someone else already claimed (issues accept up to 10
   assignees), so the add alone is not a mutex — on any other assignee set,
   remove own assignee and skip the card (race lost). Skipped when
   bot_identity is unset — accepted single-orchestrator risk: without it
   there is no cross-session claim at all, so never run two orchestrators
   (or /loop re-entries) against the same board without bot_identity.
4. **Launch** — Workflow tool with
   `scriptPath: .supersaiyan/workflows/super-board-wave.js` and
   `args: { configPath, variant, cards, humanApprovesMerge, tier, gitPlatform }`. `gitPlatform`
   is `config.git_platform` (`github` default) so classify/lane prompts say `platform_issue_view`
   instead of `gh issue view`. `configPath` MUST be the
   effective path from Preconditions step 1 (`config-resolve.sh --effective-path`'s output),
   never the raw `configs/<slug>.json` path — `super-board-wave.js` is a Workflow script with
   no filesystem access, so it cannot resolve `extends` itself; it only forwards whatever
   `configPath` it's given straight into every lane agent's prompt. Passing the raw overlay
   path there would hand lane workers a config missing every field the overlay inherits from
   its base. Runs in the background; the
   orchestrator stays responsive. `humanApprovesMerge` comes from the (resolved) config; when false the workflow serializes Review-lane agents (merge-race guard, execution side).
   `tier` is the run's model ladder: `'low'` when the user invoked
   `super-board run --low` (haiku/sonnet/opus by card complexity), `'high'`
   for `run --high` (opus floor, session model above), omitted/`'medium'`
   otherwise (sonnet/opus/session — the default). A `model_tier` key in the
   config sets the default; an explicit flag wins over config.
5. **Reconcile** (when the run completes) — read the returned `cards`
   summary. For EVERY card in the wave, release the assignee
   (`gh issue edit <n> --remove-assignee <bot_identity>`, idempotent).
   Append one line per card to the run manifest
   `docs/supersaiyan/runs/<date>-<slug>.md`:
   `| #N | <lanesRun> | <finalStatus> | <column> | <detail> |`.
6. **Report** — one short status line to the user per wave (and Telegram if
   notifications are enabled; currently disabled per CLAUDE.md). Surface any
   `human-gate`/`blocked` cards explicitly — these are the human's queue.
7. **Halt gates** — stop with a report if: 3 consecutive waves made zero
   progress (every card bounced/failed); block-rate exceeds
   `block_rate_alert_pct` of initial Ready; or the user says stop.
8. Loop to 1. For unattended cadence, the user may wrap this loop in /loop;
   the orchestrator must still stop at halt gates.

## Stop / resume

- Stop: `x` on the run in `/workflows` (or TaskStop), then release assignees
  for in-flight cards and post "stopped mid-flight" comments (same protocol
  as `references/stop.md`). Remove `<config-root>/inflight/workflow-wave.lock` (the same
  config root — the directory containing `configs/`, not `resolved/` — the wave used to
  create it; see step 5a above).
- Resume: just run again — board state is the only state. A workflow stopped
  mid-wave can also be resumed in-session via `resumeFromRunId` (completed
  lane agents return cached results).
- Cards stranded in `Building` (wave stopped after the Builder moved
  Ready → Building): the wave planner only selects from Review/QA/Ready,
  so drag stranded Building cards back to Ready before re-running.

## Mid-run permission prompts

Lane agents inherit the session allowlist and run in acceptEdits. Add these
to your project's `.claude/settings.json` → `permissions.allow` so waves
don't stall on prompts:

    "Bash(gh issue view:*)", "Bash(gh issue edit:*)", "Bash(gh issue comment:*)",
    "Bash(gh pr view:*)", "Bash(gh pr diff:*)", "Bash(gh pr checks:*)", "Bash(gh pr comment:*)",
    "Bash(gh pr create:*)", "Bash(gh pr ready:*)", "Bash(gh project item-edit:*)",
    "Bash(gh project item-list:*)", "Bash(gh api:*)", "Bash(git worktree:*)",
    "Bash(git checkout:*)", "Bash(git add:*)", "Bash(git commit:*)",
    "Bash(git push:*)", "Bash(git pull:*)", "Bash(git fetch:*)", "Bash(git blame:*)",
    "Bash(mkdir:*)", "Bash(pgrep:*)", "Bash(node --check:*)",
    "Bash(bash .supersaiyan/bin/super-board-wave-plan.sh:*)",
    "Bash(bash .supersaiyan/bin/config-resolve.sh:*)",
    plus your project's test runners (e.g. "Bash(npm test:*)", "Bash(npx playwright:*)").

`gh pr merge` is deliberately NOT in the list — Reviewer merges remain
gated by an interactive prompt, and by `human_approves_merge` for boards
that require a human click. Consequence: on auto-merge boards
(`human_approves_merge: false`) every Reviewer squash-merge pauses for one
interactive approval, so this backend is **attended-only** by default.
For genuinely unattended auto-merge runs you must consciously add
`"Bash(gh pr merge:*)"` yourself — doing so removes the last human gate
before the base branch, so pair it with a non-production `base_branch`.
