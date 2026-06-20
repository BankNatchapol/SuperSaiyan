---
name: writing-board-tasks
description: Use when you have a feature design spec and want super-board GitHub issues — decompose the spec into PR-sized board task files with observable acceptance criteria. Run after refining-spec (or Step 16 spec), before tasks-to-issues.sh. Replaces writing-plans in the super-board pipeline.
---

# Writing Board Tasks

**Derived from superpowers:writing-plans.** Same decomposition discipline and self-review habits — reads the **design spec** directly and outputs **task files** for GitHub issues (skips the intermediate plan file).

## Overview

Decompose a **feature design spec** into **board task files**. Each file becomes one GitHub issue and one PR through super-board Build → QA → Review.

Assume the Builder agent has **only the issue body** plus `PROJECT.md` — not your session history. The spec on `main` is background; the task file is the **dispatch contract**.

**Announce at start:** "I'm using the writing-board-tasks skill to create super-board task files."

**REQUIRED INPUT:** Design spec at `docs/superpowers/specs/<feature-slug>-design.md` (from Step 16 — refining-spec, office-hours copy, or brainstorming).

**OPTIONAL INPUT:** An existing `docs/superpowers/plans/…` file if the user already ran `writing-plans` — use it as extra detail, but do not require it.

**Save task files to:** `docs/superpowers/tasks/<feature-slug>/NN-short-name.md`
- One file per board task (PR-sized — not micro-steps)
- Template: `docs/templates/task-file.md`
- Issue quality bar: `docs/templates/issue.md`

## Scope Check

If the spec covers multiple independent subsystems, suggest separate feature slugs — one task folder per subsystem.

Each board task should produce working, testable software on its own **after its dependencies merge**.

## Decomposition (writing-plans discipline, spec input)

Read the spec's **Requirements**, **Recommended Approach**, **Architecture**, and **Out of Scope** first. Map which files will be created or modified. Your job is to decompose into PR-sized board tasks — the same judgment `writing-plans` would apply, but you **skip writing the plan file** and go straight to issue-ready task files.

**Task Right-Sizing** (from writing-plans — still applies):

A board task is the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate. When drawing boundaries: fold setup, configuration, scaffolding, and documentation steps into the task whose deliverable needs them; split only where a reviewer could meaningfully reject one task while approving its neighbor. Each task ends with an independently testable deliverable.

**Output shape for super-board:**

| writing-plans (not used in this pipeline) | writing-board-tasks |
|-------------------------------------------|---------------------|
| `### Task N:` with micro-steps (2–5 min each) | One markdown file per **PR** |
| Full code in every step | Goal + observable ACs; Implementation notes hold file paths |
| Executor: subagent-driven-development | Executor: super-board Builder + QA + Review |
| Saves `docs/superpowers/plans/…` | Saves `docs/superpowers/tasks/…/*.md` |

**You may merge** related requirements into one board task. **You may split** when one spec section would produce an oversized PR. **You may reorder** when dependencies allow.

See `references/plan-to-board-examples.md` for decomposition examples.

## Board Task Granularity

**Each acceptance criterion is one observable check** — not one implementation step.

Good AC granularity:
- "GET /api/health returns 200 and `{ \"status\": \"ok\" }`" — criterion
- "`npm test -- health` passes" — criterion

Bad (these are implementation **steps**, not board ACs):
- "Write the failing test" — step
- "Run it to make sure it fails" — step
- "Implement minimal code" — step
- "Commit" — step

**Target 3–5 ACs per board task.**

## Task File Structure

**Every task file MUST follow this structure** (YAML frontmatter + body):

````markdown
---
title: Verb + concrete outcome
order: 1
depends_on_task: null
feature: <feature-slug>
design: docs/superpowers/specs/<feature-slug>-design.md
plan:
plan_task: Requirements 1–2
skills: test-driven-development, verification-before-completion
---

## Goal

[One sentence: what exists when this PR merges]

## Acceptance Criteria

- [ ] [Observable outcome — HTTP status, JSON field, DOM text, DB row, file exists]
- [ ] [Observable outcome 2]
- [ ] [Tests pass — exact command or test path, e.g. `npm test -- chat`]

## Implementation notes

**Files:**
- Create: `exact/path/from/spec`
- Modify: `exact/path/from/spec`
- Test: `tests/exact/path/from/spec`

**Interfaces:**
- Consumes: [what this task uses from earlier merged PRs]
- Produces: [what later tasks rely on]

## Out of scope

[What this task explicitly does NOT include — cite spec Out of Scope where relevant]
````

**Filename:** `NN-kebab-slug.md` where `NN` matches `order` (e.g. `01-supabase-client.md`).

**Dependencies:** `depends_on_task` is the stem of the prior file without `.md` (e.g. `01-supabase-client`). First task uses `null`.

**`plan_task`:** cite spec sections (e.g. `Requirements 3`, `Recommended Approach`) — not `### Task N` unless a plan file was provided.

## Breakdown Checkpoint

Before writing files, show a short table and ask for approval:

```markdown
| # | Board task title | Maps from spec | Why this grouping |
|---|------------------|----------------|-------------------|
| 1 | ... | Req 1–2 | scaffold folded into client module |
```

**"Does this breakdown look right before I write task files?"**

Skip the ask if the user already approved or said to proceed.

## No Placeholders

Every task file must contain real content an agent can execute against. These are **task failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details", `<Edit: ...>`
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests" (without test path or command)
- "Similar to Task N" (repeat the observable checks — reviewers read issues out of order)
- ACs that describe steps instead of outcomes ("implement X", "refactor Y")
- Pasting the whole spec into the body

## Remember
- Exact file paths always (from spec + codebase reads)
- Observable ACs — verifiable without judgment
- `plan_task` cites spec sections each board task covers
- DRY, YAGNI — same spirit as writing-plans
- Skills line in frontmatter for super-board workers

## Self-Review

After writing all task files, look at the spec with fresh eyes. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each requirement in the spec. Can you point to a board task that implements it? List any gaps.

**2. Placeholder scan:** Search task files for red flags — any pattern from "No Placeholders" above. Fix them.

**3. Interface consistency:** Do file paths and interfaces in later tasks match what earlier tasks produce?

**4. Lint readiness:** Would `/super-board lint` accept each issue? Goal present, 3–5 checkboxes, no vague words, Skills in frontmatter.

If you find issues, fix them inline. If you find a spec requirement with no board task, add the task.

## Execution Handoff

After saving task files, offer the super-board path:

**"Board tasks complete and saved under `docs/superpowers/tasks/<feature-slug>/`. Next steps:**

**1. Commit and push** — `git add docs/ && git commit && git push`

**2. Prepare** — run `/supersaiyan prepare <feature-slug>`; it onboards when
needed, files/reconciles generated issues in Ready, validates dependencies, and
runs lint.

**3. Run** — `/super-board run <slug>`**

**Do NOT offer subagent-driven-development, executing-plans, or writing-plans** — this skill replaces `writing-plans` in the super-board pipeline.

## Relationship to other skills

| Skill | Role in super-board pipeline |
|-------|------------------------------|
| **refining-spec** | **Before** — tightens spec (Step 16) |
| **writing-board-tasks** | **After spec** — PR-sized task files (Step 17) |
| superpowers:writing-plans | **Not used** — optional; only if you want a plan file for humans |
| superpowers:subagent-driven-development | Alternative path — interactive, no GitHub issues |
| super-board | **After issues filed** — drains Ready cards |
