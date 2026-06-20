# Card Lifecycle: Issue #47 Through super-board

Thesis-oriented trace of one card from `Ready` → `Done`, mapping **wave conductor code** (`super-board-wave.js`) to **lane contracts** (`run.md`).

## Example card

| Field | Value |
|-------|-------|
| Issue | #47 |
| Title | "Add chat streaming endpoint" |
| Starting column | `Ready` |
| Branch | `issue-47-add-chat-streaming` |
| Config | `variant: full`, `human_approves_merge: false` |

## Agentic patterns on this card

| Pattern | When on #47 |
|---------|-------------|
| **Routing** | Classify agent reads issue via `gh issue view`; returns `{ kind: "feature", complexity: "medium" }` → model tier from ladder |
| **Prompt chaining** | Build → QA → Review only if each lane returns `status: advanced` |
| **Parallelization** | #47 can be in Review while another card is in Build (different lanes) |
| **Evaluator–optimizer** | QA fail bounces #47 to `Ready` with `loop:rebuild-1`; next wave rebuilds with feedback |
| **Orchestrator–workers** | Interactive session plans wave; lane agents inside workflow do all coding |
| **Autonomous loop** | Orchestrator repeats waves until board empty or halt gate |

## Phase 0 — Wave selection (orchestrator, not wave.js)

Before `super-board-wave.js` runs, `super-board-wave-plan.sh` picks cards:

- Downstream-first: Review → QA → Ready (one card per non-empty lane)
- Fills remaining `max_workers` slots from most backlogged column
- Skips cards already assigned to another bot

If #47 is the only `Ready` card and other lanes are empty, the wave may contain only `[{ number: 47, status: "Ready", ... }]`.

## Phase 1 — Classify (`super-board-wave.js` lines 117–125)

**Trigger:** `card.status === 'Ready'`

**Agent prompt:** Read issue body + comments; classify `kind` (feature|bug|docs|chore) and `complexity` (low|medium|high).

**Model:** haiku (default tier) or sonnet (`--high` run).

**Output schema:** `CLASSIFY_SCHEMA` → e.g. `{ kind: "feature", complexity: "medium" }`

**Effect:** Indexes into model ladder for subsequent lanes (`tierFor(cls)` → sonnet/opus/session).

Cards entering at QA or Review skip classify (`cls: null` → session model).

## Phase 2 — Builder lane (`run.md` § Builder first pass)

**Wave entry:** `at === 'Ready' && variant === 'full'` → `runLane('build', ...)`

**Worker skill:** `super-build` — must follow `run.md` "Builder (first pass)" exactly.

### Builder steps (run.md)

1. Worktree `.worktrees/issue-47-build/` off `base_branch`
2. Branch `issue-47-add-chat-streaming`
3. Read issue + comments + PROJECT.md
4. Implement smallest safe change for ACs
5. Commit + push
6. Open **draft PR** with PR description template
7. Post 🔨 PR timeline + issue comments
8. Clean up worktree; keep branch + PR
9. Move card `Building` → `QA`

### External deps at build time

- **superpowers:** `test-driven-development`, `verification-before-completion` (via Skill tool)
- **gstack:** `/plan-ceo-review`, `/plan-eng-review`, `/cso`, `/plan-design-review` on ambiguous decisions (majority vote)

### Structured exit

```json
{ "status": "advanced", "column": "QA", "detail": "...", "prUrl": "...", "branch": "issue-47-add-chat-streaming" }
```

If `status !== 'advanced'`, chain **stops**; board holds card wherever worker left it; next wave picks up from there.

## Phase 3 — Tester lane (`run.md` § Tester first pass)

**Wave entry:** only if Build returned `advanced`; `at = 'QA'`

**Worker skill:** `super-qa`

### Tester steps (pass path)

1. Worktree `.worktrees/issue-47-qa/` on same branch
2. Build test plan: one observable test per AC
3. Run tests; capture evidence to `docs/super-board/runs/issue-47-qa-v1/`
4. Screenshots at 1920×1080, 1024×768, 375×667 — committed before comment
5. Commit tests + push
6. 🔍 PR + issue comments with inline screenshot embeds
7. Move card `QA` → `Review`

### Tester steps (fail path — evaluator loop)

7. **Fail** → per-AC expected/actual + evidence → `loop:rebuild-N` label → move `QA` → `Ready`

Wave chain stops. Next wave: #47 re-enters at `Ready` → **Builder rebuild** (not classify-only skip if still Ready).

## Phase 4 — Reviewer lane (`run.md` § Reviewer)

**Wave entry:** only if QA returned `advanced`; `at = 'Review'`

**Mutex:** If `humanApprovesMerge: false`, `withReviewLock()` serializes Review agents (merge-race guard).

**Model:** always session model (strongest available).

### Reviewer gates

1. **Thread scan** — unresolved `[builder]` → bounce to Ready; `[QA]` → bounce to QA
2. Read PR, spot-check Tester evidence
3. **Rerun tests** in review worktree (closes self-verification gap)
4. **Adversarial mode** (`truth_gate: non-trivial`) — code-grounder + historian sub-agents → confidence score vs `truth_threshold` (70)
5. **Decide:**
   - Clean + green → squash-merge, close issue, `Review` → `Done`
   - Code finding → `[builder]` thread, `Review` → `Ready`
   - Test finding → `[QA]` thread, `Review` → `QA`
   - Truth fail / human gate → `Blocked`

### With `human_approves_merge: true`

Reviewer marks PR ready but does **not** merge; human clicks merge; card moves to Done when PR merges externally.

## End-to-end column path (happy path)

```
Ready → Building → QA → Review → Done
         (build)   (qa)  (review) (merge)
```

## Wave summary output

After all cards in the wave:

```javascript
{
  number: 47,
  finalStatus: "advanced",
  lastLane: "review",
  column: "Done",
  lanesRun: "build:advanced → qa:advanced → review:advanced"
}
```

Orchestrator releases assignee, appends run manifest line, reports one status line to user, loops to next wave.

## State: board is the database

Nothing critical lives in `super-board-wave.js` memory between waves:

- Column position on GitHub Project
- Issue/PR comments (handoff protocol)
- PR review threads (`[builder]` / `[QA]` prefixes)
- Labels (`loop:rebuild-N`)
- Branch + single PR per issue

Resume after crash: `/super-board run <slug>` again.

## Code map

| Concern | File |
|---------|------|
| Classify + lane chain | `workflows/super-board-wave.js` |
| Lane lifecycle spec | `skills/super-board/references/run.md` |
| Wave card selection | `scripts/super-board-wave-plan.sh` |
| Builder worker deps | `skills/super-build/references/worker-preamble.md` |
| QA skill deps | `skills/super-qa/SKILL.md` (Skill dependencies) |
| Review truth gate | `skills/super-review/SKILL.md`, `run.md` § Reviewer step 6 |
