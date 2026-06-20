---
name: refining-spec
description: Use after gstack /office-hours to technically refine a design into docs/superpowers/specs/ for writing-board-tasks. Fork of gstack /spec phases 1–4 — feature-level repo spec, NOT a GitHub issue. Run before Step 17.
---

# Refining Spec

**Derived from gstack `/spec` phases 1–4.** Same interrogation discipline — different output: a **feature-level design spec** in the repo for `writing-plans`, not a single backlog issue.

**Derived from superpowers `brainstorming` output shape.** Saves where `writing-plans` expects input.

## Overview

Turn an **office-hours design** (product framing, wedge, approach) into a **technically grounded spec** for **writing-board-tasks**.

**Announce at start:** "I'm using the refining-spec skill to refine the design into a writing-board-tasks-ready spec."

**REQUIRED INPUT:** An office-hours design doc. Check in order:

1. `docs/gstack/designs/<feature-slug>-design.md` (repo copy — preferred)
2. `docs/superpowers/specs/<feature-slug>-design.md` (if already refined)
3. `~/.gstack/projects/<slug>/*-design-*.md` (gstack default — fallback)

**Save refined spec to:** `docs/superpowers/specs/<feature-slug>-design.md`

**Do NOT:** File a GitHub issue, run `writing-plans`, write code, or spawn agents. Those are later steps.

## When to use

| Situation | Use this skill? |
|-----------|-----------------|
| After `/office-hours`, before `writing-board-tasks` | **Yes** — recommended refinement step |
| After superpowers `brainstorming` (already in repo) | **Optional** — only if spec needs code-grounded tightening |
| Ready for one GitHub issue, skip plan | **No** — use gstack `/spec` instead |
| No design doc yet | **No** — run `/office-hours` or `brainstorming` first |

## gstack pipeline position

```text
/office-hours          →  product design (~/.gstack/.../*-design-*.md)
refining-spec          →  feature spec (docs/superpowers/specs/<slug>-design.md)
writing-board-tasks    →  board task files (docs/superpowers/tasks/<slug>/)
tasks-to-issues.sh     →  GitHub issues
super-board run        →  PRs
```

gstack's own handoff is `/office-hours` → `/spec` (issue). **This skill is the superpowers fork** — same rigor, repo spec output, feature-wide scope for `writing-plans`.

---

## Phase 1: Understand the "Why" (from office-hours)

Read the office-hours design doc fully. Confirm you can crisply answer:

1. **Who** is affected?
2. **What** is the current behavior? (verified, not assumed)
3. **What** should behavior be instead?
4. **Why now?**
5. **How will we know the feature is done?** (feature-level, not one PR)

If the design doc leaves gaps, ask **one question at a time** until answered. Do not re-run office-hours product theater — fill technical and scope gaps only.

---

## Phase 2: Scope and Boundaries

Lock before drafting:

1. **What is explicitly out of scope?** (carry forward from office-hours; tighten)
2. **What existing systems does this touch?** Files, tables, services, endpoints
3. **Ordering constraints?** What must land before what?
4. **Smallest version that delivers value?** MVP cut for the **whole feature**
5. **Failure modes and rollback?**

**Feature scope rule:** This spec describes the **entire feature** `writing-plans` will decompose — not a single super-board issue. Defer per-PR slices to `writing-board-tasks` later.

---

## Phase 3: Technical Interrogation (read code first)

**Mandatory:** Before asking Phase 3 questions, read evidence from the codebase via Grep, Glob, or Read. Cite `path:line` in questions.

Mapping (from gstack `/spec`):

- **Concrete file/symbol mentioned** → Grep, Read, cite in first question
- **Project-level prompt** → Read `package.json` / stack files, relevant dirs, existing docs
- **Greenfield** → say explicitly what you searched and found nothing

Then ask about applicable categories: data model, API, UI, infra, testing. Don't ask what the code already answers.

---

## Phase 4: Draft Review

Present the full refined spec (structure below). Ask: **"Does this accurately capture what we're building? What did I get wrong?"**

Iterate until the user confirms. Then write the file.

**Skip gstack `/spec` Phase 5** (no `gh issue create`, no `~/.gstack/.../specs/` archive as primary output). The repo file **is** the deliverable.

---

## Spec Document Structure

**Every refined spec MUST include these sections:**

```markdown
# <Feature Name>

**Goal:** [One sentence — whole feature outcome]

**Architecture:** [2–3 sentences — approach from office-hours, technically tightened]

**Tech Stack:** [Key technologies/libraries — verified against repo]

## Global Constraints

[Project-wide requirements — version floors, env vars, naming, platform rules. Copy exact values from design + codebase.]

## Current State

[What exists today in the repo — files, endpoints, gaps. Evidence from Phase 3 reads.]

## Requirements

[Numbered user-visible and technical requirements the feature must satisfy]

## Out of Scope

[Explicit exclusions — prevents writing-plans and agents from scope creep]

## Recommended Approach

[Synthesized from office-hours + Phase 3 — the path writing-plans should follow]

## Open Questions

[Unresolved items, or "None" if locked]

## Source

- Office-hours design: `<path to gstack design doc>`
- Refined: <date>
```

Adapt section depth to feature size. Simple features can be shorter; complex ones need full sections.

---

## No Placeholders

Never write: "TBD", "appropriate error handling", "as needed", "implement properly", "etc." without specifics. Same bar as gstack `/spec` anti-patterns.

---

## Self-Review

After writing the spec file:

1. **Design coverage** — does every office-hours commitment appear in Requirements or Out of Scope?
2. **Placeholder scan** — fix vague language
3. **Code consistency** — do file paths and stack choices match what you read in Phase 3?
4. **writing-board-tasks readiness** — could `writing-board-tasks` decompose this without asking scope questions?

Fix inline before finishing.

---

## Execution Handoff

After saving `docs/superpowers/specs/<feature-slug>-design.md`:

```text
Refined spec saved. Next:
1. git add docs/superpowers/specs/ && git commit && git push
2. Use writing-board-tasks for docs/superpowers/specs/<feature-slug>-design.md
3. Then writing-board-tasks → `/supersaiyan prepare <feature-slug>` → `/super-board run <slug>`
```

**Do NOT offer gstack `/spec`** for the same work — that files a single issue.

---

## Relationship to gstack and superpowers

| Tool | Role |
|------|------|
| gstack `/office-hours` | **Before** — product design, wedge, demand |
| gstack `/spec` | **Alternative path** — one GitHub issue, skip writing-board-tasks |
| **refining-spec** | **Bridge** — office-hours → repo spec for writing-board-tasks |
| superpowers `brainstorming` | **Alternative to office-hours** — already saves to specs/; refining-spec optional |
| **writing-board-tasks** | **After** — reads `docs/superpowers/specs/…` (Step 17) |
