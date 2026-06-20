# Task file template — one GitHub issue per file

Save under: `docs/superpowers/tasks/<feature-slug>/NN-short-name.md`

The submit script (`SuperSaiyan/scripts/tasks-to-issues.sh`) accepts either one
task file or the task folder. A file creates one issue; a folder creates one
issue per `*.md` file except `README.md`. Run it from your **app repo** root.

---

## File format

```markdown
---
title: Add Supabase client module
order: 1
depends_on_task: null
feature: chat-bubble
design: docs/superpowers/specs/chat-bubble-design.md
plan: docs/superpowers/plans/2026-06-19-chat-bubble.md
plan_task: Task 1
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

One sentence: what exists when this task's PR merges.

## Acceptance Criteria

- [ ] Observable outcome 1
- [ ] Observable outcome 2
- [ ] Tests pass (`npm test` — document path in PR)

## Implementation notes

Optional: copy the **Files** / key steps from writing-plans for the Builder agent.
Agents primarily use Goal + ACs; this section is extra context.
```

---

## Field reference

| Frontmatter | Required | Meaning |
|-------------|----------|---------|
| `title` | yes | GitHub issue title |
| `order` | yes | Submit order (`1`, `2`, …) — used for `Depends on:` |
| `depends_on_task` | no | Stem of prior task file without `.md` (e.g. `01-supabase-client`) |
| `feature` | yes | Feature slug (folder name) |
| `design` | yes | Path to spec on `main` |
| `plan` | no | Master plan file |
| `plan_task` | no | Label from writing-plans (`Task 1`, etc.) |
| `skills` | no | Defaults to TDD + verification |

**Filename convention:** `01-supabase-client.md`, `02-messages-table.md` — numeric prefix must match `order`.

---

## After submit

Script writes `docs/superpowers/tasks/<feature>/.issue-map.json`:

```json
{
  "01-supabase-client": { "number": 12, "url": "https://github.com/..." },
  "02-messages-table": { "number": 13, "url": "..." }
}
```

Re-run is skipped if `.issue-map.json` exists unless you pass `--force`.
