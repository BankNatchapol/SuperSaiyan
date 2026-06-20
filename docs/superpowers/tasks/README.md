# Task folders — one markdown file → one GitHub issue

Used with the **gstack spec → Writing Board Tasks → issues → super-board** pipeline.

## Layout

```text
docs/superpowers/
  specs/<feature-slug>-design.md      ← from office-hours / refining-spec (Step 7)
  tasks/<feature-slug>/
    01-first-task.md
    02-second-task.md
    .issue-map.json                   ← created by scripts/tasks-to-issues.sh
```

## Workflow

1. **gstack** `/office-hours` → **refining-spec** (or copy) → `docs/superpowers/specs/`
2. **`writing-board-tasks`** → task files (Step 8 — replaces `writing-plans`)
3. **`/supersaiyan prepare <feature-slug>`** → onboard if needed, GitHub
   issues, Project **Ready**, dependency validation, and lint
4. **`/super-board run <slug>`** → Build → QA → Review

Template: [docs/templates/task-file.md](../../templates/task-file.md)

## Create task files

Install once while your terminal is in the app repo. The installer uses the
current directory as its target:

```bash
cd ~/Documents/my-first-agent-app
~/Documents/SuperSaiyan/scripts/install-bridge-skills.sh
```

After the Step 7 spec exists, in `claude` on the app repo:

```text
Use writing-board-tasks for docs/superpowers/specs/<feature-slug>-design.md
Feature slug: <feature-slug>
```

## Prepare the feature

From Claude Code targeting the app repo:

```text
/supersaiyan prepare <feature-slug>
```

The command requires task/spec files to be committed and pushed. It creates
missing issues, reuses valid mappings, repairs confirmed-deleted mappings, and
runs lint. It never starts workers.

## File issues manually (advanced)

From your **app repo** root (where `gh` points):

```bash
# One task file → one issue
~/Documents/SuperSaiyan/scripts/tasks-to-issues.sh \
  docs/superpowers/tasks/<feature-slug>/01-first-task.md --dry-run

export GH_PROJECT_OWNER=@me GH_PROJECT_NUMBER=3
~/Documents/SuperSaiyan/scripts/tasks-to-issues.sh \
  docs/superpowers/tasks/<feature-slug>/01-first-task.md

# Task folder → one issue for every task .md file
~/Documents/SuperSaiyan/scripts/tasks-to-issues.sh \
  docs/superpowers/tasks/<feature-slug>
```

Passing only `<feature-slug>` remains supported as shorthand for the task
folder.

See [plan-to-issues-bridge.md](../../super-board-analysis/plan-to-issues-bridge.md).
