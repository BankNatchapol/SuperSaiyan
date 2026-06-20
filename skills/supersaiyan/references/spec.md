# Spec — Technical Interrogation

Turns a design doc into a precise technical spec. Runs after `references/brainstorm.md`.

Announce at start: "Moving to spec phase. I'll interrogate the technical details before writing anything."

**REQUIRED INPUT:** Design doc at `docs/supersaiyan/designs/<name>-design.md` (written by brainstorm phase).

If no design doc exists: tell the user to run `supersaiyan new <slug>` from the beginning to complete the brainstorm phase first.

---

## Phase 1 — Understand the Why

Read the design doc fully. Confirm you can answer all five without guessing:

1. **Who** is affected? (specific role or user type)
2. **What** is the current behavior? (verified from codebase, not assumed)
3. **What** should the behavior be instead?
4. **Why now?** (blocking something? costing money? correctness gap?)
5. **How will we know it's done?** (observable, measurable outcome)

Ask one question at a time for any gaps. Do NOT re-run product theater from the brainstorm — fill only technical and scope gaps.

Do NOT proceed until all five are answered without hand-waving.

---

## Phase 2 — Scope and Boundaries

Lock before drafting:

1. **What is explicitly out of scope?** (carry forward from design doc; tighten to be codebase-specific)
2. **What existing systems does this touch?** Files, tables, services, endpoints — name them.
3. **Are there ordering constraints?** What must land before what?
4. **What's the smallest version that delivers value?** MVP cut for the whole feature.
5. **What are the failure modes and rollback options?** What breaks if shipped wrong?

Do NOT proceed until scope is locked.

---

## Phase 3 — Technical Interrogation

**Mandatory:** Before asking any Phase 3 question, read at least one piece of evidence from the codebase. Do NOT ask "what file should I look at?" — find it yourself.

Mapping to evidence:
- **Specific file/symbol mentioned** → Grep for it, Read the file, cite `path:line` in your first question
- **Project-level change** → Read `package.json` / stack file, relevant directories, existing docs. Say what you found.
- **Genuinely greenfield** → say: "I searched for X, Y, Z and found nothing. Treating this as greenfield." Then proceed.

Then ask about whichever apply (skip ones clearly irrelevant):
- **Data model** — new tables, columns, migrations, indexes
- **API** — new endpoints, modified responses, backwards compatibility
- **UI** — new pages, components, state management
- **Background processing** — jobs, queues, idempotency, failure handling
- **Infrastructure** — IaC, secrets, cost impact
- **Testing** — test approach at each layer, regression risk

Don't ask questions you can answer by reading the code. Read first.

---

## Phase 4 — Draft Review

Present the full technical approach in 2-3 sentences: architecture, key files, data flow.

Ask: **"Does this accurately capture what we're building? What did I get wrong?"**

Iterate until the user confirms.

---

## Phase 5 — Scope Routing

After the user confirms the technical approach, assess scope and route:

> "Based on what I've read and what we've discussed — how big is this?"
>
> A) **Single task** — one targeted change, one PR, trivial scope (a bug fix, config edit, small addition)
> B) **Single feature** — a coherent deliverable spanning multiple files/concerns, one board run
> C) **Multi-phase project** — too large for one PR sequence; needs Phase 1 → Phase 2 → ... each independently shippable

If the design doc came from Quick mode (mode: "Quick fix"), default to suggesting A. If it came from a full brainstorm, suggest B or C based on the scope. The user confirms.

**If A — Single task:**

Write one task file directly to `docs/superpowers/tasks/<slug>/01-<slug>.md`:

```markdown
---
title: Verb + concrete outcome
order: 1
depends_on_task: null
feature: <slug>
design: docs/supersaiyan/designs/<slug>-design.md
plan_task: null
skills: test-driven-development, verification-before-completion
---

## Goal

[One sentence: what exists and works when this PR merges]

## Acceptance Criteria

- [ ] [Observable outcome — exact behavior, HTTP status, UI text, test output]
- [ ] [Exact test command: `<command>`]

## Implementation notes

**Files:**
- Modify: `exact/path/from/codebase`

## Out of scope

[What this task explicitly does NOT include]
```

Then commit and follow `references/prepare.md`. Announce:
```
✅ <slug> queued as a single task.
   Issue: #<N> → Ready queue

Next: /supersaiyan run
```

**If B — Single feature:**

Write `docs/superpowers/specs/<slug>-design.md` using the structure below, then announce:
```
Spec saved. Next: I'll break this into board tasks.
```

**If C — Multi-phase project:**

Say: "Got it. I'll switch to project mode — this will produce a PROJECT.md plus a spec and task set per phase."

Read `references/project.md` and follow it exactly. Pass the confirmed technical approach and all Phase 1-4 answers as context.

---

## Spec Document Structure (single feature)

```markdown
# <Feature Name>

**Goal:** [One sentence — whole feature outcome]

**Architecture:** [2–3 sentences — approach and data flow, technically grounded]

**Tech Stack:** [Key technologies verified against the codebase]

## Global Constraints

[Project-wide requirements from CLAUDE.md + codebase — exact values, no paraphrasing]

## Current State

[What exists today: files, endpoints, gaps. Cite exact paths from Phase 3 reads.]

## Requirements

1. [Numbered user-visible or technical requirement]
2. ...

## Out of Scope

- [Explicit exclusion — prevents agents from scope creep]

## Recommended Approach

[Synthesized from design doc + codebase: the path the Build lane should follow]

## Open Questions

[Unresolved items, or "None"]

## Source

- Design: docs/supersaiyan/designs/<slug>-design.md
- Spec date: <date>
```

## No Placeholders

Never write: TBD, "as needed", "appropriate", "handle edge cases", "etc." without specifics. If you don't know something, say so explicitly and list it under Open Questions.

## Self-Review Before Continuing

- Every Phase 1 commitment appears in Requirements or Out of Scope
- No placeholder language
- File paths match what you actually read in Phase 3
- Could `writing-board-tasks` decompose this without asking scope questions?

Fix anything that fails. Then announce next step.
