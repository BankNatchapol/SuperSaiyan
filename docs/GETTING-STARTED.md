# Getting Started with SuperSaiyan

Go from **idea to merged PR** using a single command set. No context-switching between tools.

**Time:** ~30 minutes first run (includes GitHub Project setup).

---

## What you need

| Tool | Install |
|------|---------|
| [Claude Code](https://claude.ai/code) | Required |
| [GitHub CLI](https://cli.github.com) | Required |
| Git | Required |

---

## Install

**Option A — Plugin (recommended)**

```bash
claude plugin install github:BankNatchapol/SuperSaiyan
```

Installs `supersaiyan` globally. Open Claude Code in any repo and `/supersaiyan` is available.

**Option B — Direct install into a repo**

```bash
git clone https://github.com/BankNatchapol/SuperSaiyan.git
SuperSaiyan/install.sh /path/to/your-app
```

---

## Open Claude Code in your repo

All `/supersaiyan` commands run **inside** a Claude Code session. Before the steps below, open Claude Code in the repo you want to use:

```bash
cd /path/to/your-app
claude .
```

Then type the slash commands directly in the Claude Code chat.

---

## Step 1 — Setup (once per repo)

```
/supersaiyan setup
```

This will:
- Verify `git`, `gh`, and Claude are authenticated
- Create `docs/superpowers/specs/`, `docs/superpowers/tasks/`, and related directories
- Walk you through creating a **GitHub Project board** (or linking to an existing one)
- Write a board config to `.claude/super-board/configs/<slug>.json`

**What's next:** Run `supersaiyan new <feature>` to start your first feature or project.

---

## Step 2 — Define what to build

```
/supersaiyan new <name>
```

`<name>` is a short kebab-case slug for anything you want to build:

| What you're building | Example slug |
|---------------------|--------------|
| A single feature | `health-endpoint`, `dark-mode` |
| A product or app from scratch | `my-saas-app`, `task-manager` |
| A large system within a repo | `auth-system`, `chat-feature` |

The brainstorm phase asks what context you're working in and adjusts accordingly. A new app from scratch? Startup mode. A side project? Builder mode. A large system? Project mode with phases.

### What happens inside `new`

SuperSaiyan runs a four-phase pipeline:

**Phase 1 — Brainstorm** (office-hours methodology)

Asks you one question to set the mode:
- **Startup mode** — YC-style diagnostic: six forcing questions about demand, status quo, target user, wedge, observation, and future-fit. Pushes back until answers are specific and evidence-based.
- **Builder mode** — creative partner: five generative questions to find the most exciting version of the idea.

Then: optional landscape search (with your permission), premise challenge, save design doc.

**Phase 2 — Spec** (gstack /spec methodology)

Reads your codebase first — never asks questions the code already answers. Then:
1. Confirm the Why (who, current behavior, target behavior, why now, how done?)
2. Lock scope and boundaries (out of scope, systems touched, ordering, MVP cut)
3. Technical interrogation with evidence (reads real files, cites `path:line`)
4. Draft review — you confirm before anything is written

At the end, asks: **single feature or multi-phase project?**

**Phase 3 — Tasks**

Decomposes the spec into PR-sized board tasks with observable acceptance criteria, TDD discipline, and verification gates. Each task becomes one GitHub issue.

**Phase 4 — Queue**

Commits docs, files GitHub issues, adds to the board's Ready queue, runs pre-flight lint.

**What's next after `new`:**
```
/supersaiyan run     ← single feature: start the autonomous loop
```
For multi-phase projects, see below.

---

## Step 3 — Run the autonomous loop

```
/supersaiyan run
```

The pipeline runs unattended:

| Column | Who | What |
|--------|-----|------|
| **Ready** | You | Issues you approved |
| **Building** | Builder agent | Branch, code, tests (TDD), draft PR |
| **QA** | QA agent | Runs tests, captures evidence |
| **Review** | Reviewer agent | Reruns tests, merge readiness |
| **Done** | Agents (or you) | Merged |

Watch progress on the GitHub Project board and in issue comments.

**Stop at any time:**
```
/supersaiyan stop
```

**Resume:**
```
/supersaiyan run
```

**What's next after run completes:** All issues are Done and merged. For a project with phases, unlock the next phase (see below).

---

## Multi-phase projects

When `supersaiyan new` determines the work is too large for one PR sequence, it switches to **project mode** automatically. This produces:

```
docs/superpowers/projects/<slug>/
  PROJECT.md              ← top-level guide: goal, phase table, architecture, constraints
  phase-1/
    PHASE.md              ← phase spec: goal, scope, what it produces for Phase 2
    01-task.md
    02-task.md
  phase-2/
    PHASE.md              ← knows what Phase 1 produced
    01-task.md
```

### Running a project phase by phase

```bash
# Phase 1 is already in Ready after `supersaiyan new`
/supersaiyan run                         # run Phase 1 autonomously

# When Phase 1 board is empty (all Done):
/supersaiyan prepare <slug> --phase 2    # checks Phase 1 is complete, files Phase 2 issues to Ready
/supersaiyan run                         # run Phase 2

# Repeat for each phase:
/supersaiyan prepare <slug> --phase 3
/supersaiyan run
```

**Why step-by-step?** Each phase depends on the prior phase being merged. You stay in control of when phases unlock — which also lets you review what was built before the next phase starts.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `command not found: claude` | Install from [claude.ai/code](https://claude.ai/code) |
| `gh auth` errors | `gh auth login` then `gh auth refresh -s project,read:project,repo` |
| "No config" on run | Run `/supersaiyan setup` first |
| Card stuck in **Blocked** | Read issue comments — usually a merge conflict. Run `/supersaiyan stop`, fix the branch, then resume |
| QA keeps failing | Read QA comment on the issue; adjust acceptance criteria with `/supersaiyan lint` |
| Want to requeue a feature | `git push` any spec/task changes then `/supersaiyan prepare <slug>` |
| Phase 2 not unlocking | Check all Phase 1 issues are closed in GitHub, then run `prepare --phase 2` again |

---

## Other commands

| Command | When to use |
|---------|-------------|
| `/supersaiyan status` | Read-only board snapshot — see what's blocked |
| `/supersaiyan lint` | Re-run pre-flight after editing issues |
| `/supersaiyan prepare <slug>` | Re-sync issues without redefining the feature |
| `/supersaiyan prepare <slug> --phase N` | Unlock the next phase after prior phase is Done |

---

## Full workflow recap

**Single feature:**
```
/supersaiyan setup
      │
      ▼
/supersaiyan new my-feature    (brainstorm → spec → tasks → queue)
      │
      ▼
/supersaiyan run               (Build → QA → Review → Done)
      │
      ▼
   PR merged ✓
```

**Multi-phase project:**
```
/supersaiyan setup
      │
      ▼
/supersaiyan new my-project    (brainstorm → spec → PROJECT.md → phase specs → tasks)
      │
      ▼
/supersaiyan run               (Phase 1: Build → QA → Review → Done)
      │
      ▼
/supersaiyan prepare my-project --phase 2
      │
      ▼
/supersaiyan run               (Phase 2: Build → QA → Review → Done)
      │
      ▼
   ... repeat per phase ...
      │
      ▼
   All phases merged ✓
```

---

## What's in the repo after setup

```
your-app/
  CLAUDE.md                              ← pipeline path conventions
  docs/
    gstack/
      designs/<slug>-design.md          ← brainstorm output (SuperSaiyan writes)
    superpowers/
      specs/<slug>-design.md            ← single feature spec (SuperSaiyan writes)
      tasks/<slug>/
        01-task.md                      ← board task files (SuperSaiyan writes)
        .issue-map.json                 ← issue → file mapping (auto-managed)
      projects/<slug>/
        PROJECT.md                      ← project guide (SuperSaiyan writes)
        phase-1/
          PHASE.md                      ← phase spec
          01-task.md
        phase-2/
          PHASE.md
          01-task.md
    templates/task-file.md              ← task file template
  .claude/
    skills/                             ← supersaiyan + pipeline worker skills
    bin/                                ← wave planner scripts
    workflows/super-board-wave.js       ← autonomous loop runtime
    super-board/configs/<slug>.json     ← board config (setup writes)
```

---

*SuperSaiyan — Getting Started*
