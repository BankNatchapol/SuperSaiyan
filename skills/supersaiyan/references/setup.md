# supersaiyan setup

One-time initialization. Run this before `supersaiyan new`.

Announce: "Running SuperSaiyan setup for this repository."

---

## Step 1 — Prerequisites

```bash
# Git
git rev-parse --is-inside-work-tree 2>/dev/null || echo "NOT_GIT"

# GitHub CLI
gh --version >/dev/null 2>&1 || echo "GH_MISSING"
gh auth status --active >/dev/null 2>&1 || echo "GH_NOT_AUTHED"

# Claude Code
claude --version >/dev/null 2>&1 || echo "CLAUDE_MISSING"
```

**If not a git repo:**
Ask: "This folder isn't a git repository. Initialize one? [y/n]"
On yes: `git init -b main && git add . && git commit -m "chore: initial commit"`.
Then ask if they want a GitHub remote: `gh repo create --public --source=. --push`.

**If `gh` missing:** "Install the GitHub CLI from https://cli.github.com then rerun setup."

**If `gh` not authenticated:** Run `gh auth login` interactively, then:
```bash
gh auth refresh -s project,read:project,repo
```
Verify: `gh auth status` shows `project`, `read:project`, `repo` scopes.

**If `claude` missing:** "Install Claude Code from https://claude.ai/code then rerun setup."

---

## Step 2 — Docs layout

Create directories (idempotent):

```bash
mkdir -p docs/superpowers/specs
mkdir -p docs/superpowers/tasks
mkdir -p docs/gstack/designs
mkdir -p docs/gstack/specs
mkdir -p docs/templates
```

If `docs/templates/task-file.md` does not exist, create it:

```markdown
---
title: Verb + concrete outcome
order: 1
depends_on_task: null
feature: <feature-slug>
design: docs/superpowers/specs/<feature-slug>-design.md
plan:
plan_task: Requirements 1
skills: test-driven-development, verification-before-completion
---

## Goal

[One sentence: what exists when this PR merges]

## Acceptance Criteria

- [ ] [Observable outcome]
- [ ] [Test command: `<exact command>`]

## Implementation notes

**Files:**
- Create: `path/to/new/file.ts`
- Modify: `path/to/existing/file.ts`

**Interfaces:**
- Consumes: [nothing, or prior task output]
- Produces: [what later tasks depend on]

## Out of scope

[Explicit exclusions]
```

---

## Step 3 — CLAUDE.md

Check if `CLAUDE.md` exists at the repo root. If not, create it with:

```markdown
# Agent notes
```

Add this section if not already present (check with grep):

```markdown
## SuperSaiyan pipeline paths

| Artifact | Path |
|----------|------|
| Feature specs | `docs/superpowers/specs/<slug>-design.md` |
| Board tasks | `docs/superpowers/tasks/<slug>/NN-*.md` |
| Issue map | `docs/superpowers/tasks/<slug>/.issue-map.json` |
| Designs | `docs/gstack/designs/<slug>-design.md` |

When saving design docs from `/office-hours` or similar tools, also save a
copy to `docs/gstack/designs/<feature-slug>-design.md`.
```

---

## Step 4 — Super-board config

Follow `references/onboard.md` exactly (the interactive super-board onboarding wizard).

This creates `.claude/super-board/configs/<slug>.json` and links it to a GitHub Project.

When onboarding prompts for variant, recommend:
- `variant: full` (Build + QA + Review) for new features
- `human_approves_merge: true` on first run

---

## Step 5 — Done

```
✅ SuperSaiyan setup complete.
   Config: .claude/super-board/configs/<slug>.json
   Project: <GitHub Project URL>
   Docs:    docs/superpowers/{specs,tasks}/

Next: /supersaiyan new <feature-slug>
```
