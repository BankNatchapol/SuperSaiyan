# Project Mode — Multi-Phase Decomposition

Runs when `references/spec.md` Phase 5 determines the work is too large for a single feature.

Announce: "Switching to project mode. I'll decompose this into phases, each independently shippable."

**Input:** Confirmed technical approach and answers from spec.md Phases 1–4.

---

## Phase A — Propose Phase Breakdown

Read the design doc and the confirmed technical approach. Propose a phase breakdown:

```
| Phase | Name | Goal (one sentence) | Produces | Depends on |
|-------|------|---------------------|----------|------------|
| 1     | ... | ... | API endpoints, DB schema | — |
| 2     | ... | ... | UI components | Phase 1 |
| 3     | ... | ... | Notifications, polish | Phase 2 |
```

**Phase sizing rules:**
- Each phase must produce something independently shippable and testable
- 2–5 phases is ideal; if you need more than 7, suggest splitting into separate projects
- Phase 1 is always the foundation: auth, data model, core API — whatever Phase 2 can't exist without
- No phase should be "everything else" — give each a focused, nameable goal
- Setup and configuration fold into the phase whose deliverable needs them

Ask: **"Does this breakdown look right? Any phases to merge, split, or reorder?"**

Do not write any files until the user approves the breakdown.

---

## Phase B — Write PROJECT.md

After approval, write `docs/superpowers/projects/<project-slug>/PROJECT.md`:

```markdown
# Project: <Name>

**Slug:** <project-slug>
**Started:** <date>
**Design:** docs/supersaiyan/designs/<project-slug>-design.md

## Goal

[One paragraph: what this project delivers end-to-end and why it matters]

## Architecture

[Key technical decisions that apply across ALL phases — stack, patterns, conventions, non-negotiables from CLAUDE.md]

## Constraints

[Project-wide requirements from CLAUDE.md + codebase. Copy exact values — version floors, env vars, naming rules, platform constraints]

## Phases

| Phase | Name | Goal | Produces | Depends on | Status |
|-------|------|------|----------|------------|--------|
| 1 | ... | ... | ... | — | Ready |
| 2 | ... | ... | ... | Phase 1 | Queued |
| 3 | ... | ... | ... | Phase 2 | Queued |

## Running the Project

Each phase runs through the autonomous loop independently:

```
/supersaiyan run <project-slug>-phase-1   # drains Phase 1 tasks
# when Phase 1 is Done:
/supersaiyan prepare <project-slug> --phase 2   # unlocks Phase 2
/supersaiyan run <project-slug>-phase-2
```

## Source

- Design: docs/supersaiyan/designs/<project-slug>-design.md
- Phases: docs/superpowers/projects/<project-slug>/phase-N/
```

---

## Phase C — Write Per-Phase Specs

For each phase (in order), write a PHASE.md spec. Use the same technical interrogation discipline as `references/spec.md` Phases 1–3, but scoped to this phase only.

For Phase 1: use the full codebase context from spec.md Phase 3 reads.
For Phase 2+: read what Phase N-1's PHASE.md says it produces, then ask about the delta only.

Write `docs/superpowers/projects/<project-slug>/phase-N/PHASE.md`:

```markdown
# Phase <N>: <Name>

**Project:** <project-slug>
**Goal:** [One sentence — what exists and works when this phase merges]
**Depends on:** Phase <N-1> | None

## Scope

[What this phase builds — specific, verifiable]

## Out of Scope

[What's deferred to later phases — prevents agent scope creep]

## Consumes from Prior Phase

[Specific interfaces, files, API endpoints, DB tables produced by Phase N-1 that this phase builds on. "None" for Phase 1.]

## Produces for Next Phase

[What Phase N+1 will consume from this phase. "None" for last phase.]

## Architecture

[Phase-specific technical decisions — patterns, key files, data flow]

## Requirements

1. [Numbered requirement — user-visible or technical, verifiable]
2. ...

## Acceptance

[Observable outcomes that prove this phase is complete: endpoints, test commands, UI states]

## Source

- Project: docs/superpowers/projects/<project-slug>/PROJECT.md
- Phase spec date: <date>
```

**No placeholders.** Never write TBD, "as needed", "handle edge cases". Every requirement is verifiable. Every path is real.

**Self-review after each PHASE.md:**
- Every requirement is observable (testable by an agent who only has this file)
- Produces/Consumes fields are consistent with adjacent phases
- Could `writing-board-tasks` decompose this without asking scope questions?

---

## Phase D — Write Tasks Per Phase

For each phase, invoke the `writing-board-tasks` skill with this additional context:

> "You are writing tasks for **Phase <N>** of project **<project-slug>**.
> - The phase spec is at: `docs/superpowers/projects/<project-slug>/phase-N/PHASE.md`
> - The project guide is at: `docs/superpowers/projects/<project-slug>/PROJECT.md`
> - Phase N depends on Phase N-1 being fully merged before any of these tasks begin.
> - Tasks must reference what they consume from Phase N-1 (see PHASE.md Consumes section).
> - Save task files to: `docs/superpowers/projects/<project-slug>/phase-N/NN-task-name.md`"

Task frontmatter for project tasks:

```yaml
---
title: Verb + concrete outcome
order: 1
depends_on_task: null
project: <project-slug>
phase: <N>
depends_on_phase: <N-1>   # null for Phase 1
design: docs/superpowers/projects/<project-slug>/phase-N/PHASE.md
plan_task: Requirements 1–2
skills: test-driven-development, verification-before-completion
---
```

---

## Phase E — Commit and File Issues

```bash
git add docs/superpowers/projects/<project-slug>/
git commit -m "docs: <project-slug> project spec — <N> phases, <M> tasks"
git push
```

Then follow `references/prepare.md` for **Phase 1 only**:
- File Phase 1 tasks as GitHub issues → add to board Ready queue
- Label Phase 2+ tasks as `phase-2`, `phase-3`, etc. in GitHub → do NOT add to Ready yet

---

## Phase F — Next Steps Handoff

Print this after setup is complete:

```
✅ <project-slug> project ready.

   PROJECT.md: docs/superpowers/projects/<project-slug>/PROJECT.md
   Phases:     <N> phases defined
   Tasks:      Phase 1 → Ready queue (<M> issues)
               Phase 2+ → Queued (labeled, not yet Ready)

── Phase 1 ──────────────────────────────────────────────
Run the autonomous loop:

   /supersaiyan run <config-slug>

Watch Phase 1 cards move: Ready → Building → QA → Review → Done.
Stop at any time: /supersaiyan stop

── When Phase 1 is Done ─────────────────────────────────
Unlock Phase 2:

   /supersaiyan prepare <project-slug> --phase 2

This files Phase 2 issues to Ready and runs pre-flight lint.
Then run again: /supersaiyan run <config-slug>

── Repeat for each phase ────────────────────────────────
Each phase follows the same pattern:
   /supersaiyan prepare <project-slug> --phase N
   /supersaiyan run <config-slug>
```

---

## Prepare — Phase Unlock (for `supersaiyan prepare <slug> --phase N`)

When `prepare` is called with `--phase N`:

1. Read `docs/superpowers/projects/<project-slug>/PROJECT.md` — confirm Phase N-1 status
2. Check GitHub: are all Phase N-1 issues closed? If not, list open ones and stop.
3. Read task files from `docs/superpowers/projects/<project-slug>/phase-N/`
4. Follow `references/prepare.md` for Phase N tasks — file as GitHub issues, add to Ready
5. Print:

```
✅ Phase <N> unlocked.
   Issues filed: <M>
   Board: Ready queue updated
   Next: /supersaiyan run <config-slug>
```
