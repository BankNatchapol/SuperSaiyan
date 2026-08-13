---
name: super-build
description: Super Build canonical workflow — the Build lane inside the supersaiyan / super-board pipeline. Headless parallel GitHub Project executor that reads issues whose `Status` field is `Ready`, dispatches each as a headless `claude -p` worker in its own git worktree (max 3 in parallel), and opens a PR per issue. DEFAULT IS SAFE: it does not merge, close the issue, or move the card to `Done` on its own — that only happens for a worker explicitly dispatched by the supersaiyan/super-board pipeline's Reviewer lane, or in the explicit opt-in Standalone Auto-Merge mode (see Autonomy preflight). Notifies Telegram on each completion. The project board is the single curation surface — drag a card to `Ready` and Super Build picks it up. Prefer the supersaiyan skill for plain-English "fix the issue" / board-task asks; use this when the user says "Super Build", "/super-build", or when supersaiyan / super-board has routed work to the Build lane.
---

# Super Build / Super Build — Headless Parallel GitHub-Project Executor

You are the orchestrator. The source of truth is the **`Ready` column of the configured GitHub Project board**. Your job: dispatch every issue in `Ready` (in board order) as a parallel headless `claude -p` worker in a git worktree, push the branch, and open a PR per issue — then stop. By default you do **not** merge results back, close the issue, or advance its project card to `Done` yourself; ping Telegram on each completion regardless. See **Autonomy preflight** below before doing anything past "open a PR."

**Curation contract:** the human moves cards into `Ready` when they should be worked. The loop never reads `Backlog`, `In Progress`, or `Done` cards. If `Ready` is empty, the loop reports "queue empty" and exits cleanly — no error.

**This skill is single-purpose: EXECUTE curated GitHub Project `Ready` issues.** It is INDEPENDENT of `/super-qa` / **Super QA** (the autonomous bug-bash loop that hardens shipped code). They share no state unless **Super Orchestrator** explicitly sequences them. Run **Super Build** to make forward progress on the issue queue; run **Super QA** to bug-bash the existing codebase. They CAN run concurrently in different orchestrator sessions, but expect merge conflicts if both touch the same files.

## Role boundary

Super Build is the canonical builder. Do not use a separate `build-feature` workflow. If the user wants a one-off feature, first create or curate a GitHub issue/card with clear acceptance criteria, move it to `Ready`, then let Super Build execute it.

Super Build may implement, test, commit, and push. **By default it stops at "open a PR."** It does NOT merge worker branches, close issues, or move project cards to `Done` on its own — that is QA's and Reviewer's job (or a human's). Super Build only merges + closes autonomously inside the explicit, opt-in Standalone Auto-Merge mode below — never as a fallback, never because a signal was ambiguous or missing. It should not invent new product scope beyond the issue body. If the issue needs product/design/security judgment, apply the human-gate or WIP-partial path instead of guessing.

**Never implement issue work directly on the default branch in the primary worktree.** Every issue gets its own branch (`loop/issue-N` in standalone mode, `issue-<N>-<slug>` when pipeline-dispatched) inside an isolated `git worktree`, created *before* implementation starts — see `### 3. Dispatch wave` below. This isn't optional even for a single `--only N` run. (This same rule applies to ad hoc interactive issue work that never invokes this skill at all — see `supersaiyan/SKILL.md` → "Golden rule: never implement issue work directly on the primary branch.")

## Autonomy preflight (read before ANY merge, close, or move-to-Done action)

Applies everywhere in this file. Before you run `git merge`, `gh pr merge`, `gh issue close`, or move a card to `Done` for any issue, run:

```bash
git rev-parse --show-toplevel | xargs basename
ls .supersaiyan/configs/*.json .claude/supersaiyan/configs/*.json .claude/super-board/configs/*.json 2>/dev/null
```

(Three roots, highest priority first: `.supersaiyan/` is where new onboards write; `.claude/supersaiyan/` and `.claude/super-board/` are pre-migration/legacy roots that still work via fallback — see `references/config-schema.json` and `scripts/config-resolve.sh`. Any one of the three having a match means "onboarded.")

Then classify this run:

1. **Pipeline-dispatched.** Your invocation explicitly told you to read `.claude/skills/super-board/references/run.md` → a named lane lifecycle (Builder/Tester/Reviewer), and/or named a `Config: <path>` under `.supersaiyan/configs/` (or a legacy `.claude/supersaiyan/configs/`/`.claude/super-board/configs/` path — or, for a config with `extends` set, `.supersaiyan/resolved/`/`.claude/supersaiyan/resolved/`, the persisted merged view; see `references/config-schema.json` `extends`). → Follow **## Pipeline-dispatched mode** below. This always wins, even if an opt-in phrase (case 4) is also present.
2. **Repo-identity guard.** The toplevel basename is `SuperSaiyan` (the toolkit source repo). → STOP before dispatching any worker. This repo has no GitHub Project `Ready` column to drive and its own `AGENTS.md` documents that the pipeline runs in app repos only. Tell the user: `🛑 This is the SuperSaiyan toolkit repo — it does not run the Build/QA/Review pipeline (see AGENTS.md).` Do not proceed.
3. **Onboarded but not explicitly dispatched.** A config exists under any of the three roots above, but this invocation wasn't the explicit pipeline dispatch from case 1. → Tell the user: `🛑 This repo has an onboarded supersaiyan pipeline. Route this through supersaiyan (/supersaiyan run) instead of invoking Super Build standalone.` Still implement, test, commit, push, and open the PR (the default success path below) — just don't merge or close.
4. **Explicit opt-in.** No onboarded config under any root (case 3 doesn't apply), and the user's current turn contains the exact literal phrase `--standalone-automerge-i-understand-the-risk`. → You may enter **## Standalone Auto-Merge mode** below. Restate the consequence once (no QA, no Review, this session merges and closes on its own) before the first merge/close.
5. **Anything else** — bare `/super-build`, "Super Build", plain-English "fix the issue," or any other ambiguous match, with none of cases 1–4 applying. → **The default.** Implement, test, commit, push, open a PR, stop. Do not merge or close.

## Configuration

The orchestrator needs to know which project board to read. There are two modes:

### Standalone mode (default — feature queue)

Reads `Ready` from the repo's feature project. Resolution order:

1. **`BUILD_LOOP_PROJECT`** env var — project number (e.g. `2`)
2. **`BUILD_LOOP_OWNER`** env var — project owner (e.g. `EricTechPro`)
3. **Auto-discovery fallback:** if env vars unset, run `gh project list --owner $(gh repo view --json owner -q .owner.login) --format json` and pick the project whose `title` matches the repo name (`Fitbox Admin` for this project), or the only open project if there's exactly one.

Surface: `🎯 Reading project: EricTechPro/Fitbox Admin (#2), column "Ready"`.

### QA-loop mode (orchestrator-driven — drain `Bug` column)

When invoked by `super-orchestrator` as part of the QA↔Build loop, Super Build drains the `Bug` column on the **Super Ultimate QA** project rather than `Ready` on the feature project. Enabled by:

- `BUILD_LOOP_QA_MODE=1` env var, **or**
- `super-orchestrator` exporting it via the dispatch wrapper.

Resolution:

1. Project resolved by `SUPER_QA_PROJECT_TITLE` (default: `Super Ultimate QA`) at the configured owner — same logic as super-qa.
2. Source column: `Bug` (override with `BUILD_LOOP_SOURCE_COLUMN`).
3. Target column on success: `Done` on the same QA project.

Surface: `🎯 QA-loop mode — reading project: EricTechPro/Super Ultimate QA (#5), column "Bug"`.

Standalone and QA-loop mode never run in the same orchestrator session by default — pick one per run. They can run concurrently in different sessions because they read different boards.

## Algorithm

### 0. Pre-flight

Before reading the board:

- Confirm the main worktree is clean: `git status --porcelain` must be empty.
- Confirm `gh auth status` works and the repo remote points at the expected GitHub repo.
- Confirm `jq`, `git`, and `claude` are available.
- Resolve and print `BUILD_LOOP_OWNER` and `BUILD_LOOP_PROJECT`.
- Run `git fetch origin` and identify the base branch from the current checkout; do **not** assume `main`.
- If this run is part of Super Orchestrator, update the run manifest with preset `Build Queue`, input project, base branch, and done definition.

### 1. Read the source column

Source column is `Ready` in standalone mode, `Bug` in QA-loop mode (override with `BUILD_LOOP_SOURCE_COLUMN`):

```bash
SOURCE_COLUMN="${BUILD_LOOP_SOURCE_COLUMN:-${BUILD_LOOP_QA_MODE:+Bug}}"
SOURCE_COLUMN="${SOURCE_COLUMN:-Ready}"

gh project item-list "$BUILD_LOOP_PROJECT" --owner "$BUILD_LOOP_OWNER" --limit 200 --format json \
  | jq --arg col "$SOURCE_COLUMN" '.items[] | select(.status == $col and .content.type == "Issue")'
```

For each Ready item:
- Capture `content.number` (issue #), `content.title`, `content.body`, `content.labels` (via separate `gh issue view N --json labels` if `item-list` doesn't include them).
- **Skip** issues with the `loop:in-progress` label (in flight in another orchestrator) or `loop:halted` label (manually paused) or `human-gated` label (requires manual handling).
- Parse `body` for `Depends on: #N1, #N2` lines (case-insensitive). If any dependency is still open, the issue is blocked — leave it for a future run even when both cards are in Ready.
- Parse `body` for an optional `Skills:` line (e.g. `Skills: superpowers:test-driven-development, superpowers:verification-before-completion`). If absent, the worker uses defaults from the preamble.

**Ordering:**
1. **Board order first** — `gh project item-list` returns items in the human's manual board order. Respect that. If the user wants Issue X before Issue Y, they drag X above Y on the board.
2. **Tiebreaker (rare):** within the same drag-position, sort by priority extracted from title regex `^\[?(P[1-4])\]?`: `P1` < `P2` < `P4` < `P3` < no priority. Then issue number ascending.

If `Ready` is empty: print `📭 Project board "Ready" column is empty — nothing to dispatch.` and exit 0. This is not an error; it means the human hasn't curated work yet.

### 2. Ensure required labels exist (idempotent)

Once per run, before first dispatch:
```bash
gh label create loop:in-progress --color FFA500 --description "Currently being worked on by /super-build" 2>/dev/null || true
gh label create loop:halted --color B60205 --description "Manually paused — /super-build will skip" 2>/dev/null || true
gh label create human-gated --color B60205 --description "Requires manual handling — /super-build will not auto-execute" 2>/dev/null || true
```

### 3. Dispatch wave (max 3 concurrent)

Notify Telegram once per wave: `▶️ Super Build dispatching: Issues [#N1, #N2, #N3] (parallel)`

For each issue N in the ready set (up to 3 at a time):

a. **Lock the issue:**
```bash
gh issue edit N --add-label loop:in-progress
```

b. **Announce on the issue** (so a human reading the issue page knows it's being worked):
```bash
gh issue comment N --body "🤖 Dispatched by /super-build — worker spinning up in worktree \`.worktrees/issue-N\` on branch \`loop/issue-N\`. Skills: <skills-line-from-body-or-defaults>."
```

c. **Dispatch:**
```bash
bash scripts/super-build-dispatch.sh N
```
…via Bash with `run_in_background: true`. Capture each shell ID.

The dispatcher (at `scripts/super-build-dispatch.sh`) handles:
- `git worktree add -b loop/issue-N .worktrees/issue-N <base-branch>`
- `gh issue view N --json title,body,labels` to compose the worker prompt
- prepend `references/worker-preamble.md` + append working-directory footer
- `cd` into worktree and exec `claude -p --dangerously-skip-permissions --output-format stream-json --verbose --max-turns 250`
- verify the worker produced a `chore(loop): close #N` commit on its branch
- exit 0 (success) / 2 (worker non-zero) / 3 (no done-commit) / 4 (HUMAN GATE TRIPPED)

**Base branch:** the orchestrator's currently-checked-out branch (e.g. `frontend-rebuild`). Pass via `BASE_BRANCH` env var to the dispatcher. Don't assume `main`.

### 4. Wait + reconcile

Poll BashOutput on each in-flight shell. As each finishes:

**On dispatcher exit 0 (success) — DEFAULT: open a PR, do not merge or close.** This is the outcome unless Autonomy preflight case 4 (Standalone Auto-Merge mode) applies to this run:
- `cd <repo-root>`
- `git push origin loop/issue-N`
- `gh pr create --base "$BASE_BRANCH" --head loop/issue-N --draft --title "<issue title>" --body "Closes #N\n\n<summary of what changed>\n\n🤖 Opened by /super-build — awaiting QA/Review. Does not merge or close on its own; see Autonomy preflight in skills/super-build/SKILL.md."`
- `gh issue comment N --body "🔨 Super Build opened PR #<pr> — implementation done, awaiting QA/Review (or a human merge). Issue stays open until the PR merges."`
- `gh issue edit N --remove-label loop:in-progress --add-label needs-review`
- `git worktree remove .worktrees/issue-N` (leave `loop/issue-N` on origin — don't delete; it's cleaned up when the PR merges or closes)
- Notify Telegram: `✅ Super Build opened PR #<pr> for issue #N — awaiting QA/Review`
- Recompute ready set; if new issues are now unblocked, dispatch in the next wave (respecting the 3-concurrent throttle)

If Autonomy preflight case 4 applies, use the merge+close sequence in **## Standalone Auto-Merge mode** instead of the steps above.

**On dispatcher exit 5 (intentional WIP-PARTIAL — merge as partial, do NOT close):**
- `cd <repo-root>`
- `git merge --no-ff loop/issue-N -m "merge: loop/issue-N partial — <slice from worker's final message> (#N)"` — the issue number reference (no `closes #` keyword) means GitHub will not auto-close the issue.
- `gh issue edit N --remove-label loop:in-progress --add-label human-gated`
- `gh issue comment N --body "✅ Foundation/partial slice merged to main as $(git rev-parse --short HEAD). Issue stays open with \`human-gated\` label until the rest of the implementation lands. Worker's reason for stopping at a partial:\n\n> $(<final assistant message excerpt>)"`
- Before cleanup, archive the branch as a tag: `git tag archive/loop-issue-N-$(date +%Y%m%d-%H%M%S) loop/issue-N` (so `git branch -D` is recoverable)
- `git worktree remove .worktrees/issue-N`
- `git branch -D loop/issue-N`
- Notify Telegram: `🟡 Issue #N partial merged — issue stays open (human-gated)`
- **Continue dispatching the next issue in the wave.** A WIP-PARTIAL is NOT a halt. The worker did intentional, scoped work and the orchestrator advances.

**On dispatcher exit 2 or 3 (worker failed or no done-commit):**
- `gh issue edit N --remove-label loop:in-progress`
- `gh issue comment N --body "❌ /super-build worker failed (exit code <X>). Last 50 lines of log:\n\n\`\`\`\n$(tail -50 .planning/super-build-logs/issue-N.log)\n\`\`\`\nWorktree at \`.worktrees/issue-N\` left intact for human inspection."`
- Notify Telegram with `tail -50` of `.planning/super-build-logs/issue-N.log`
- Do NOT merge; leave the worktree intact for human inspection
- Halt the loop

**On dispatcher exit 4 (HUMAN GATE TRIPPED):**
- `gh issue edit N --remove-label loop:in-progress --add-label human-gated`
- `gh issue comment N --body "🔴 HUMAN GATE TRIPPED — needs manual handling. See worktree \`.worktrees/issue-N\`."`
- Notify Telegram: `🔴 Issue #N tripped HUMAN GATE — needs manual handling`
- Halt the loop

### 5. Final report

When the selected GitHub Project `Ready` queue is empty, or only blocked/skipped cards remain: send a Telegram summary listing PRs opened this run (awaiting QA/Review), issues closed this run (Standalone Auto-Merge mode only), issues still skipped (`human-gated` / `loop:halted` / blocked dependencies), and any halts. Suggest: "Run Super QA against the opened PRs, then Super Review to merge."

## Issue contract

Every Ready issue should be executable without live clarification. Preferred issue body shape:

```markdown
## Goal
<one-sentence outcome>

## Acceptance Criteria
- [ ] <observable behavior or artifact>
- [ ] <test/verification expectation>

## Notes / Constraints
- Depends on: #123, #456
- Skills: superpowers:test-driven-development, superpowers:verification-before-completion
- Human gates: <deploy, destructive DB action, product decision, etc.>
```

Super Build treats acceptance criteria as the completion contract. Workers must not edit checkboxes to make the issue look complete. If the issue is too vague to execute, label/comment it as human-gated instead of guessing.

## Constraints

- **Maximum 3 parallel workers** at a time (resource throttle).
- **Never auto-touch issues with `human-gated` label** (production cutover, secrets, irreversible ops).
- **Never modify code in the main worktree** while workers are running. Only run `gh issue` commands and merge/cleanup operations.
- **Merge conflicts** between concurrent workers' branches → halt loop, notify Telegram with conflict files, leave `loop:in-progress` label so a human can resolve. Don't auto-resolve.
- **Telegram cadence:** 1 message at start, 1 per dispatch wave, 1 per completion (success/fail), 1 final summary. Don't spam.
- **Workers MUST use the right skills.** The worker preamble enforces: workers parse the `Skills:` line from the issue body if present, otherwise use defaults (`superpowers:test-driven-development`, `superpowers:verification-before-completion`). All decision points use gstack advisors (`/plan-ceo-review`, `/plan-eng-review`, `/cso`, `/plan-design-review`) with majority vote (tie → smallest blast radius). See `references/gstack-voting.md` for when to invoke vs. when to escalate, and the required `--- gstack-vote ---` commit trailer.

## Worker preamble

The preamble at `references/worker-preamble.md` is the worker contract: decision policy, HUMAN GATE handling, the per-issue 14-gate contract, and final-commit format. The dispatcher prepends it to every worker prompt. See that file for the verbatim text.

## Recovery / re-entry

If the user invokes `/super-build` after a partial run:
- Re-read `gh issue list`. Issues already closed are skipped automatically.
- If issue N already has an open PR from a prior `loop/issue-N` branch: skip re-dispatch, report the existing PR URL instead — don't open a duplicate PR.
- If `.worktrees/issue-N` exists for an N that's still open: a previous worker was interrupted. Default: notify the user and ask before auto-resuming (a re-dispatch overwrites the previous attempt's branch).
- If the `loop:in-progress` label is set on issue N but no worktree exists: stale lock from a crashed orchestrator. Remove the label and treat as ready.

## Stop conditions

- Selected GitHub Project `Ready` queue is empty, or all remaining Ready cards are blocked / `human-gated` / `loop:halted`.
- Any worker fails (dispatcher exit 2 or 3).
- HUMAN GATE TRIPPED (dispatcher exit 4).
- Merge conflict.
- User interrupts.

**Not a stop condition:** WIP-PARTIAL (dispatcher exit 5). The orchestrator merges the partial, leaves the issue open with `human-gated`, and continues dispatching the next issue in the wave. WIP-PARTIAL is intentional, bounded work.

## Invocation patterns

- `Super Build` / `/super-build` → process all GitHub Project `Ready` issues in board order. **Default outcome per issue: an open PR, no merge, no close** (see Autonomy preflight).
- `/super-build --only N` → same PR-only default, scoped to a single issue (smoke-test mode, ignores `loop:in-progress` label on that issue if you set `FORCE=1`). `--only` scopes which issue, not merge authority.
- `/super-build --dry-run` → print the dispatch plan (issues, order, parallelism waves) without invoking workers, without setting labels, without commenting
- `/super-build --only N --standalone-automerge-i-understand-the-risk` → the only way to get the old merge+close+Done behavior for issue N. Requires no onboarded config under `.supersaiyan/configs/` (or the legacy roots) and one explicit confirmation (Autonomy preflight case 4).

## Standalone Auto-Merge mode (opt-in, unsafe)

**Do not enter this section unless Autonomy preflight case 4 applies to this run.** This reproduces the pre-fix behavior: merges and closes issues with no QA or Review step. It exists for a genuinely single-lane setup with no QA/Review columns, used knowingly — not as a default or fallback.

When active, replace the default "On dispatcher exit 0" steps in **### 4. Wait + reconcile** with:
- `cd <repo-root>`
- `git merge --no-ff loop/issue-N -m "merge: loop/issue-N (closes #N)"`
- `gh issue close N --comment "Closed by /super-build (standalone auto-merge) in $(git rev-parse --short HEAD)"`
- `gh issue edit N --remove-label loop:in-progress`
- `git worktree remove .worktrees/issue-N`
- `git branch -D loop/issue-N`
- Move the project item/card to `Done` if GitHub does not do it automatically on issue close.
- Notify Telegram: `✅ Super Build issue #N closed (merged) — standalone auto-merge mode`

The WIP-PARTIAL, worker-failure, and HUMAN GATE reconcile branches are unchanged in this mode.

## Companion skill

`/super-qa` / **Super QA** is the autonomous bug-bash iteration loop. It is **independent of this skill** unless Super Orchestrator explicitly sequences them. Run **Super Build** for forward progress on Ready issues; run **Super QA** to harden the existing codebase by hunting bugs.

## Pipeline-dispatched mode

This is how supersaiyan/super-board actually calls you — treat it as the common case, not a special one. Enter this mode whenever ANY of these is true:
- Your invocation explicitly instructs you to read `.claude/skills/super-board/references/run.md` and follow a named lane lifecycle (Builder/Tester/Reviewer). **Both dispatch backends always say this** (`super-board-run.sh`'s legacy dispatcher and the default `super-board-wave.js` workflow backend) — this is the authoritative, always-present signal. Prefer it over the signals below.
- Your invocation names a `Config: <path>` under `.supersaiyan/configs/` (or a legacy `.claude/supersaiyan/configs/`/`.claude/super-board/configs/` path — or, for a config with `extends` set, `.supersaiyan/resolved/`/`.claude/supersaiyan/resolved/`, the persisted merged view both dispatch backends resolve `extends` into before handing you a path; see `references/config-schema.json` `extends`).
- Env `SUPER_BOARD_RUN=1` is set, or the invocation text contains `"super-board run"` or `"super-board workflow wave"` (both real strings the two backends send; kept as back-compat signals — don't rely on these alone).

When any of the above holds, follow these rules instead of the standalone defaults:

### State protocol
- Read context from: issue body + ALL issue comments + linked PR description + PR comments + PR review threads. NEVER from local state files for inter-lane coordination.
- Respect the worktree path super-board hands you (typically `.worktrees/issue-<N>-build/`). Don't create your own.
- Respect the single branch super-board hands you (`issue-<N>-<slug>`). Don't create alternate branches.

### Lifecycle (Builder, first pass)
Follow spec `.claude/skills/super-board/references/run.md` → Builder (first pass). Summary:
1. Worktree off `config.base_branch`.
2. Branch `issue-<N>-<slug>` from `config.base_branch`.
3. Implement smallest safe change covering ACs.
4. Commit + push (always).
5. Open **draft PR** with the PR description template from `run.md`.
6. Post 🔨 PR timeline comment + short issue comment with PR URL.
7. Move card Ready/Building → QA.

### Lifecycle (Builder, rebuild)
Triggered when card returns to Ready/Building with `loop:rebuild-N` label.
1. Read PR review threads on this branch's PR; filter `[builder]` prefix.
2. For each unresolved `[builder]` thread: read file:line + suggested fix → apply → resolve thread via:
   ```bash
   gh api graphql -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}' -f threadId="<thread-id>"
   ```
3. Address any new failure feedback from Tester's latest ❌ comment.
4. Commit + push to same branch. Verify ALL `[builder]` threads are resolved before exit.
5. 🔨 PR + issue comments. Move card Ready/Building → QA.

### Failure → handoff comment must include `root-cause-hash:` line
On any failure-handoff comment, include:
```
root-cause-hash: <sha256 first 12 hex chars>
```
Hash inputs (joined with `|`): lane (`build`) | error class | first 3 unique normalized file:line frames. See `.claude/skills/super-board/references/run.md` → Root-cause hash.

### Never merge
Builder NEVER squash-merges. Reviewer owns merge.

### Block/Skip exits use the §4 mandatory template
When moving a card to Blocked or Skipped, populate the full template from `.claude/skills/super-board/references/block-template.md`. A 1-line "needs creds" comment is a contract violation.
