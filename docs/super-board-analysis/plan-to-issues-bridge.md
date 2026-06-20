# Plan → Issues bridge (superpowers → super-board)

How to turn `docs/superpowers/plans/…` into GitHub issues that `/super-board run` can drain.

**Related:** [GETTING-STARTED.md](../GETTING-STARTED.md) (Steps 17–23), [idea-to-merged-playbook.md](idea-to-merged-playbook.md) Phase B, [issue template](../templates/issue.md).

---

## The gap in one picture

```text
PHASE A — superpowers (repo markdown)
  spec  →  writing-plans  →  docs/superpowers/plans/YYYY-MM-DD-feature.md
                                    │
                                    │  ??? (no auto bridge)
                                    ▼
PHASE B — GitHub (board state)
  issues + Project columns  →  /super-board onboard (once)
                            →  /super-board lint  →  /super-board run
```

| Layer | Artifact | Granularity | Executor reads it? |
|-------|----------|-------------|-------------------|
| Design | `docs/superpowers/specs/<slug>-design.md` | Whole feature | Builder *may* read on `main` |
| **Plan** | `docs/superpowers/plans/<date>-<name>.md` | **Tasks** (file-level steps, TDD micro-steps) | **SDD yes; super-board no** |
| **Issue** | GitHub `#N` + Project card | **PR-sized slice** (observable ACs) | **super-board yes** (primary contract) |
| Context | `docs/super-board/PROJECT.md` | Repo-wide | All lanes (onboard) |

`writing-plans` ends by offering **subagent-driven-development** — same session, same file.  
`super-board run` ends by polling **`content.type == "Issue"`** on the Project — not plan tasks.

---

## Two different “task” concepts

### Plan task (`### Task N:` in writing-plans)

From superpowers `writing-plans`:

- **Files** to create/modify/test (exact paths)
- **Interfaces** between tasks
- **Steps** — 2–5 minute TDD loop (failing test → implement → commit)
- Audience: implementer subagent in **one plan execution**

### super-board issue

From super-build dispatch:

- **Goal** — one sentence outcome
- **Acceptance criteria** — observable, checkbox, headless-worker testable
- **Notes** — `Skills:`, `Depends on: #N`, links to spec/plan
- Audience: **Builder → QA → Review** lanes, each a separate headless worker

| Plan task | Issue |
|-----------|-------|
| “Modify `src/api/health.ts` lines 12–40” | “`GET /api/health` returns 200 + JSON” |
| 5 commit-sized steps | 3–5 **outcome** checkboxes |
| Sequential within SDD | One branch + one PR per issue |
| Reviewer reads task spec | QA + Review read **issue ACs** |

**You are translating** from *how to code* → *what done looks like*.

---

## Mapping strategies

Pick one per feature. Mixing styles on one board confuses ordering.

### Strategy 1 — Vertical slice (recommended for first run)

**Many plan tasks → one issue → one PR**

| Plan | Issues |
|------|--------|
| Task 1–4 (scaffold + endpoint + test) | **Issue #1** — smallest end-to-end behavior |

**Notes field:**

```markdown
- Plan: docs/superpowers/plans/2026-06-19-chat-bubble.md (Tasks 1–4)
- Design: docs/superpowers/specs/chat-bubble-design.md
- Skills: superpowers:test-driven-development, superpowers:verification-before-completion
```

Builder may read the plan; **ACs on the issue** are still what QA/Review enforce.

**When:** Tutorial, MVP, proving super-board pipeline.

---

### Strategy 2 — One issue per plan task (task-as-ticket)

**`### Task N` → Issue #N**

| Plan | Issues |
|------|--------|
| Task 1: Supabase client setup | Issue #1 |
| Task 2: `messages` migration | Issue #2 `Depends on: #1` |
| Task 3: `index.html` UI | Issue #3 `Depends on: #2` |

**ACs:** Derive from task **deliverable**, not every micro-step:

```markdown
## Acceptance Criteria
- [ ] `shared/supabase.ts` exports a configured client (path in PR)
- [ ] `npm test` passes for `tests/supabase-client.test.ts`
```

**When:** Large plan, want **board visibility per task**, unattended drain over days.

**super-board supports ordering:**

- `Depends on: #12, #15` in issue body (case-insensitive) — skipped until deps closed
- **Board drag order** in Ready — tiebreaker after deps satisfied

---

### Strategy 3 — Epic + children (tracking only)

**Parent issue = initiative; children = runnable work**

GitHub issue #1 (epic): “Chat MVP” — **not** moved to Ready  
Issues #2–#5: children with `Depends on:` chain — only children go Ready

**Today:** Manual epic linking (title prefix or “Parent: #1” in Notes).  
**Future:** gstack `/spec --epic` (planned P2 in gstack `TODOS.md`) — multiple `gh issue create` in one session.

**When:** Multi-week initiative, you want GitHub hierarchy without one giant card.

---

### Strategy 4 — Skip plan for board (gstack `/spec` path)

**Conversation → single issue, no plan file**

```text
/office-hours → /plan-eng-review → /spec → gh issue create
```

Issue body is the contract; optional plan written later for humans only.

**When:** You like issues-first; plan is optional documentation.

---

## What super-board actually reads from an issue

Parsed by super-build (see `super-build/SKILL.md`):

| Field | Location | Effect |
|-------|----------|--------|
| Title + body | GitHub issue | Worker prompt |
| `## Acceptance Criteria` | Body | Definition of done; lint enforces quality |
| `Skills: a, b` | Body (Notes) | Which superpowers skills Builder loads |
| `Depends on: #N` | Body | Block dispatch until #N closed |
| `[P1]`…`[P4]` in title | Title | Priority tiebreaker in Ready |
| Comments | Issue thread | QA/Review evidence trail |
| Labels | `loop:*`, `human-gated` | Dispatch mutex / skip |

**Not parsed today:**

- `Plan: docs/superpowers/plans/…` (convention only — Builder may read file if agent chooses)
- Plan task checkboxes
- `### Task N` headings

**Implication:** Linking the plan in Notes helps humans and agents; **ACs must stand alone** for unattended QA/Review.

---

## Workflows today (plan → board)

### A — Manual (tutorial default)

1. Finish `writing-plans` → plan on `main`
2. Read `### Task` sections; choose Strategy 1 or 2
3. Create issues ([issue.md](../templates/issue.md))
4. Add to Project → **Backlog**
5. `/supersaiyan prepare <feature-slug>` (onboard if needed, issues, Ready, lint)
6. `/super-board run <slug>`

### B — Claude drafts issues (semi-auto)

In `claude` on app repo:

```text
Read docs/superpowers/plans/<plan-file>.md and docs/superpowers/specs/<spec-file>.md.

Propose GitHub issues using Strategy 2 (one issue per plan task).
For each issue output:
- Title
- Goal + Acceptance Criteria + Notes (Skills + Depends on + Plan task reference)
Use docs/templates/issue.md shape. Do not file yet.
```

You review, edit, paste into GitHub (or approve `gh issue create` commands).

### C — gstack `/spec` (issue without plan)

Skips plan file; files one issue with `gh issue create`. Good when scope is already clear. Does **not** read `writing-plans` output.

### D — `/super-board lint` (after issues exist)

Does **not** create issues from plan.  
**Does** rewrite vague ACs, suggest splits, align with `PROJECT.md`. Run after filing, before first `run`.

---

## Converting a plan task → issue (recipe)

For each `### Task N: <name>` you want as its own card:

1. **Title:** `Add <outcome>` (verb + user-visible or mergeable artifact)
2. **Goal:** One sentence — what exists when this task’s PR merges
3. **ACs (3–5):** Observable only:
   - Files that must exist (from plan **Files** block)
   - Test command + pass (from plan **Step 4**)
   - Behavior a QA agent can verify without reading the plan
4. **Notes:**
   ```markdown
   - Plan: docs/superpowers/plans/<file>.md (Task N)
   - Design: docs/superpowers/specs/<slug>-design.md
   - Skills: superpowers:test-driven-development, superpowers:verification-before-completion
   - Depends on: #<prev>   # if Task N needs prior merge
   ```
5. **Out of scope:** Copy from plan if task borders another Task N+1

**Anti-pattern:** Paste the whole `### Task N` step list into the issue. QA lane expects **outcomes**, not commit choreography.

---

## Example: 3-task plan → 3 issues

**Plan excerpt:**

```markdown
### Task 1: Supabase client module
**Files:** Create `lib/supabase.ts`, `tests/supabase.test.ts`
…

### Task 2: messages table + RLS
**Files:** Create `supabase/migrations/001_messages.sql`
…

### Task 3: Chat UI submit
**Files:** Modify `index.html`, `lib/chat.ts`
…
```

**Issue #1** — `Add Supabase client module`

```markdown
## Acceptance Criteria
- [ ] `lib/supabase.ts` exists and reads URL/key from env documented in PR
- [ ] `tests/supabase.test.ts` passes (`npm test`)
```

**Issue #2** — `Add messages table and RLS`

```markdown
## Acceptance Criteria
- [ ] Migration `001_messages.sql` applies cleanly
- [ ] Insert into `messages` succeeds with anon key (steps in PR)
## Notes
- Depends on: #1
- Plan: …/plans/chat.md (Task 2)
```

**Issue #3** — `Add chat bubble submit UI`

```markdown
## Acceptance Criteria
- [ ] `index.html` shows input + send control
- [ ] Submit inserts row into `messages` (manual or test steps in PR)
## Notes
- Depends on: #2
- Plan: …/plans/chat.md (Task 3)
```

**Board:** generated tasks enter Ready together; dependency-gated wave planning
waits for each prerequisite card to reach Done.

---

## Tooling map (what exists vs missing)

| Tool | Creates issues? | From plan file? | Multi-issue? | Adds to Project? |
|------|-----------------|-----------------|--------------|------------------|
| `writing-plans` | No | Writes plan | N/A | No |
| `subagent-driven-development` | No | Executes plan | N/A | No |
| **`writing-board-tasks`** skill | No | **Re-decomposes plan** | **One .md per board task** | No |
| **`split-plan-to-tasks.sh`** | No | **Mechanical `### Task` split (stubs)** | One .md per plan task | No |
| **`tasks-to-issues.sh`** | **Yes** (`gh issue create`) | **From task .md files** | **Yes** | **Optional** (`GH_PROJECT_*`) |
| gstack `/spec` | **Yes** (`gh issue create`) | No | 1 (today) | No |
| gstack `/spec --epic` | Planned | No | **Epic + children** | No |
| Claude draft + `gh issue create` | You publish | **Yes** (prompt) | You decide | Manual |
| `/super-board lint` | No | No | Suggests split | No |
| `/super-board run` | No | No | Drains existing | N/A |

**Implemented bridge (SuperSaiyan):**

```text
writing-plans → docs/superpowers/plans/…
  → writing-board-tasks skill (recommended) OR split-plan-to-tasks.sh (stubs only)
  → docs/superpowers/tasks/<feature>/*.md
  → tasks-to-issues.sh → GitHub issues + .issue-map.json
  → /supersaiyan prepare → Project Ready (dependency-gated) → /super-board run
```

Install skill: `scripts/install-bridge-skills.sh`. Scripts: `scripts/tasks-to-issues.sh`. See [docs/superpowers/tasks/README.md](../superpowers/tasks/README.md).

**Still missing (optional):**

1. **`plan-to-issues` skill** — single superpowers skill wrapping the two scripts
2. **Lint phase** — optional “import plan path → propose issues”
3. **Worker preamble** — require reading `Plan:` path from issue Notes

---

## Decision guide

| You want… | Do this |
|-----------|---------|
| Fastest first super-board smoke test | Strategy 1 — one issue, plan in Notes |
| Plan has 5+ tasks, unattended over a week | Strategy 2 — one issue per task + `Depends on:` |
| No plan file, issue-native | `/spec` or manual issue |
| Interactive coding now, board later | SDD on plan first; file issues after Task 1 merges |
| Strict AC quality before run | File issues → `/super-board lint` → Ready |

---

## Suggested pipeline (hybrid)

```text
/office-hours
  → copy spec to docs/superpowers/specs/
  → writing-plans
  → task files in docs/superpowers/tasks/<feature>/ (Step 8)
  → tasks-to-issues.sh (Step 11)
  → commit docs/ (plan + tasks on main for reference)
  → GitHub Project + Backlog
  → /super-board onboard
  → /super-board lint
  → Ready (one card) → /super-board run
```

**Rule of thumb:** Plan = **backlog decomposition**. Issue = **dispatch unit**. One plan execution (SDD) ≠ one super-board run; one issue ≈ one PR through Build/QA/Review.

---

## Future integration (SuperSaiyan direction)

From [integration-decision.md](integration-decision.md):

- Keep super-board’s **board-as-state** protocol
- **Bridge shipped:** `writing-board-tasks` skill + `tasks-to-issues.sh` (see [GETTING-STARTED Steps 8–11](../GETTING-STARTED.md))
- Stub fallback: `split-plan-to-tasks.sh` (mechanical — not recommended alone)
- Optional next: superpowers **skill** wrapper; worker **requires** plan task scope from Notes

---

*SuperSaiyan — plan-to-issues bridge notes*
