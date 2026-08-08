# Agent handoff — SuperSaiyan

Read this first when working in **this repository** (`SuperSaiyan`). Humans follow [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md); this file is the compressed context for agents.

---

## What this repo is

| Repo | Role |
|------|------|
| **SuperSaiyan** (here) | Toolkit source: vendored **gstack**, **superpowers**, **super-board**; bridge skills; setup scripts; guides |
| **User's app repo** (e.g. `my-first-agent-app`) | Real product code, GitHub issues, Project board, PRs — **where the pipeline runs** |

Do not confuse the two. super-board slash commands and the feature pipeline run in the **app repo**, not in SuperSaiyan (except studying upstream code here).

---

## End-to-end pipeline (app repo)

```text
/office-hours                    → product design (gstack)
docs/gstack/designs/             → repo copy of design
refining-spec                    → docs/superpowers/specs/<slug>-design.md
writing-board-tasks              → docs/superpowers/tasks/<slug>/*.md
/supersaiyan prepare             → onboard if needed + issues + Ready + lint
/super-board run                 → Build → QA → Review
```

**Not used in the tutorial path:** superpowers `writing-plans` (optional for interactive SDD only). **Do not** use gstack `/spec` when the goal is multi-issue super-board — it files a single issue.

---

## SuperSaiyan directory map

```text
SuperSaiyan/
  AGENTS.md                          ← this file
  README.md
  apps/desktop/                      optional Electron control center
  packages/
    control-protocol/                typed UI/main-process contract
    control-core/                    repo, GitHub, config, and watcher services
    ui/                              shared React renderer (no Electron imports)
  design/dashboard-control-center/  extracted Aura Console design reference
  docs/
    GETTING-STARTED.md               ← primary human tutorial (20 steps)
    templates/                       issue.md, task-file.md, github-project-columns.md
    superpowers/tasks/README.md      task-folder convention
    super-board-analysis/            architecture + plan-to-issues bridge
  .claude/skills/
    refining-spec/                   office-hours design → repo spec
    writing-board-tasks/             spec → PR-sized task .md files
    supersaiyan/                      prepare tasks → Ready issues → lint
  scripts/
    bootstrap-app.sh                 check/install dependencies + configure app repo
    install-bridge-skills.sh         copy bridge skills + templates → app repo
    setup-gstack-artifacts-path.sh   docs/gstack/ layout + CLAUDE.md rules → app repo
    tasks-to-issues.sh               task .md → gh issue create (run from app repo)
    split-plan-to-tasks.sh           stub only — prefer writing-board-tasks agent
    verify-super-board-setup.sh      smoke check for toolkit clones
  super-board/                       upstream super-board (install.sh → app)
  superpowers/                       upstream superpowers (plugin, not copied wholesale)
  gstack/                            upstream gstack (global ~/.claude/skills/gstack)
```

---

## App repo layout (after bootstrap)

Created by `super-board/install.sh` + `install-bridge-skills.sh` + `setup-gstack-artifacts-path.sh`:

```text
my-first-agent-app/
  CLAUDE.md                          gstack “save artifacts to repo” rules
  docs/
    gstack/designs/                  /office-hours copies
    gstack/specs/                    /spec copies (optional)
    superpowers/specs/               feature specs (refining-spec output)
    superpowers/tasks/<feature>/     board task files (writing-board-tasks output)
    templates/                       issue.md, task-file.md
  scripts/gstack-env.sh              optional GSTACK_HOME=<repo>/.gstack
  .claude/skills/                    super-board + refining-spec + writing-board-tasks
  .claude/bin/                       super-board dispatcher scripts
  .claude/workflows/                 super-board-wave.js
  .claude/supersaiyan/configs/       onboard writes <slug>.json here
```

---

## Setup scripts (run from SuperSaiyan, target = app repo)

Recommended from the app repo:

```bash
~/Documents/SuperSaiyan/scripts/bootstrap-app.sh
```

Manual equivalent:

```bash
APP=/path/to/your-app
SAIYAN=/path/to/SuperSaiyan

"$SAIYAN/install.sh" "$APP"
(
  cd "$APP"
  "$SAIYAN/scripts/install-bridge-skills.sh"
)
"$SAIYAN/scripts/setup-gstack-artifacts-path.sh" "$APP"
```

| Script | Idempotent? | Notes |
|--------|-------------|-------|
| `bootstrap-app.sh` | Yes | Checks/installs dependencies, then runs all three app installers; defaults target to cwd |
| `install-bridge-skills.sh` | Yes | Copies `docs/templates/issue.md` + `docs/superpowers/tasks/README.md` (skills come from `install.sh`); target defaults to cwd |
| `setup-gstack-artifacts-path.sh` | Yes | Appends CLAUDE.md section once; creates doc dirs |
| `tasks-to-issues.sh` | Mostly | Low-level helper; prefer `/supersaiyan prepare` |
| `split-plan-to-tasks.sh` | With `--force` | Mechanical stub — not recommended alone |

`tasks-to-issues.sh` and `split-plan-to-tasks.sh` are **run with cwd = app repo**; they live in SuperSaiyan but read/write `docs/superpowers/` in the app.

### Keeping the installed plugin in sync

If SuperSaiyan was installed as a Claude Code **plugin** (the common path — see README), edits
in this working tree have zero effect on any Claude Code session until:

1. Commit and push to `origin/main` on GitHub.
2. `claude plugin marketplace update supersaiyan`
3. `claude plugin update supersaiyan`
4. Restart Claude Code.

`bootstrap-app.sh` warns (not a hard failure) when the plugin's pinned commit
(`~/.claude/plugins/installed_plugins.json` → `gitCommitSha`) is behind
`git -C SAIYAN_ROOT rev-parse HEAD`.

---

## Bridge skills (SuperSaiyan-authored)

| Skill | Input | Output | Invoke (app repo, `>` prompt) |
|-------|-------|--------|-------------------------------|
| **refining-spec** | `docs/gstack/designs/…` or `~/.gstack/…` | `docs/superpowers/specs/<slug>-design.md` | `Use refining-spec for <path>` |
| **writing-board-tasks** | `docs/superpowers/specs/<slug>-design.md` | `docs/superpowers/tasks/<slug>/NN-*.md` | `Use writing-board-tasks for docs/superpowers/specs/…` |
| **supersaiyan** | Task folder + onboard config | Ready GitHub issues + linted pre-flight | `/supersaiyan prepare <feature-slug>` |

Both are forks/adaptations of superpowers/gstack patterns — see each `SKILL.md` under `.claude/skills/`.

**writing-board-tasks** rules of thumb:
- One task file = one GitHub issue = one PR through Build → QA → Review
- 3–5 **observable** acceptance criteria per task (not TDD micro-steps)
- Agent may merge/split spec requirements; not a 1:1 header split

---

## gstack artifact paths

When you run gstack `/office-hours` or `/spec` in an app repo, **also save a copy** in the
repo — do not skip this. Agents and git only see files under the repository; gstack's own
default save location is not in git and not visible to a headless worker.

| Skill | gstack default (not in git) | **Repo copy (required)** |
|-------|------------------------------|---------------------------|
| `/office-hours` | `~/.gstack/projects/<slug>/*-design-*.md` | `docs/gstack/designs/<feature-slug>-design.md` |
| `/spec` | `~/.gstack/projects/<slug>/specs/*.md` | `docs/gstack/specs/<feature-slug>-spec.md` |

After `/office-hours`, run **refining-spec** (or copy by hand) so the pipeline's canonical
spec file exists **before** running **writing-board-tasks**:

| Artifact | Path |
|----------|------|
| Feature spec (pipeline canonical) | `docs/superpowers/specs/<feature-slug>-design.md` |
| Board tasks | `docs/superpowers/tasks/<feature-slug>/NN-*.md` |
| Issue map | `docs/superpowers/tasks/<feature-slug>/.issue-map.json` ← generated by tasks-to-issues |

Optional: `source scripts/gstack-env.sh` sets `GSTACK_HOME=<app>/.gstack` to relocate gstack's
own default save location inside the app repo instead of the home directory.

---

## super-board essentials

- **Verbs:** `onboard`, `lint`, `status`, `run`, `stop`
- **Trigger:** GitHub Project card in **Ready** linked to an **Issue**
- **Does not:** auto-read plan files, auto-create issues from specs, run without a Ready card
- **Wave planner:** issues only (`content.type == "Issue"`) — see `super-board/workflows/super-board-wave.js`
- **Install:** `super-board/install.sh` — do not hand-copy skills unless debugging

Config schema: `super-board/skills/super-board/references/config-schema.json`

---

## Naming conventions

| Token | Example | Used in |
|-------|---------|---------|
| `<feature-slug>` | `chat-bubble`, `health-endpoint` | spec path, task folder, issue batch |
| `<slug>` | `myapp` | super-board config `configs/<slug>.json` |
| Task file stem | `01-supabase-client` | `depends_on_task` in frontmatter |

Task file template: [docs/templates/task-file.md](docs/templates/task-file.md)  
Issue template: [docs/templates/issue.md](docs/templates/issue.md)

---

## What to edit where

| Change | Edit here |
|--------|-----------|
| Tutorial steps, human onboarding | `docs/GETTING-STARTED.md` |
| Bridge skill behavior | `.claude/skills/refining-spec/`, `writing-board-tasks/` |
| Issue/task file shape | `docs/templates/` |
| Plan → issues analysis | `docs/super-board-analysis/plan-to-issues-bridge.md` |
| super-board upstream behavior | `super-board/` (fork/vendor) |
| gstack upstream behavior | `gstack/` — prefer SuperSaiyan bridge over patching |
| superpowers upstream | `superpowers/` — use plugin + bridge skills |

After changing bridge skills in SuperSaiyan, re-run `install-bridge-skills.sh` on app repos to propagate.

---

## Agent prompts (copy-paste for app repo)

```text
Use refining-spec for docs/gstack/designs/<feature-slug>-design.md
Feature slug: <feature-slug>
```

```text
Use writing-board-tasks for docs/superpowers/specs/<feature-slug>-design.md
Feature slug: <feature-slug>
```

```bash
~/Documents/SuperSaiyan/scripts/tasks-to-issues.sh docs/superpowers/tasks/<feature-slug>/01-first-task.md --dry-run
export GH_PROJECT_OWNER=@me GH_PROJECT_NUMBER=<n>
~/Documents/SuperSaiyan/scripts/tasks-to-issues.sh docs/superpowers/tasks/<feature-slug>
```

```text
/supersaiyan prepare <feature-slug>
/supersaiyan run
```

---

## Skill routing for agents (read this)

**Default entry point is always `supersaiyan`.** Do not freestyle from `gh issue view`, and do not jump straight to `super-build` / `super-board` / `super-qa` / `super-review` as the top-level skill — those are lanes inside the supersaiyan pipeline.

When the user asks to **fix / implement / solve a GitHub issue**, work a **board task** / **Ready card**, drain the board, or otherwise make pipeline progress: **read and follow `skills/supersaiyan/SKILL.md`** (or the installed `supersaiyan` skill), then use the matching verb (`run`, `prepare`, `status`, `lint`, `stop`, …).

| User ask | Skill / verb |
|----------|----------------|
| Fix / implement / solve issue `#N`, Ready card, board task, “do the next issue” | **supersaiyan** → usually `run` (or `status` first if unclear) |
| Drain the board / autonomous Build→QA→Review | **supersaiyan run** |
| Spec → task files → Ready issues | **supersaiyan prepare** (or refining-spec → writing-board-tasks → prepare) |
| Skills listed in the issue Notes / body (e.g. TDD, verification) | Use **inside** the supersaiyan worker path — not a substitute for it |
| `super-build` / `super-qa` / `super-review` / `super-board` | Internal lane skills — only when supersaiyan (or the user) explicitly routes there |

Trigger phrases for supersaiyan include plain English (“fix the first issue”, “implement #3”, “work the board”), not only `/supersaiyan`.

---

## Constraints for agents working in SuperSaiyan

1. **Minimize scope** — this repo is mostly docs + glue; product code lives in the app repo.
2. **Do not commit** unless the user explicitly asks. After a completed issue/task the user asked to ship, **commit and push** (user preference: always push after done).
3. **Prefer bridge skills** over new one-off scripts for plan/spec/task decomposition.
4. **bash 3.2** — scripts must run on macOS default bash (`mapfile` / `declare -A` break).
5. **Upstream submodules** — `gstack/`, `superpowers/`, `super-board/` may be upstream clones; avoid drive-by edits.
6. **Control Center stays optional** — UI code lives in `apps/` and `packages/`; never make it a prerequisite for skills or CLI use.
7. **This repo has no onboarded `.claude/supersaiyan/configs/<slug>.json`**, even though GitHub Project #3 ("SuperSaiyan") is used for real issue tracking here. Because there's no onboarded config, `super-build`'s Autonomy preflight will refuse a bare/standalone invocation in this repo — issue work here has to be driven manually (branch → PR → Super QA → Super Review) rather than a fully automated `/supersaiyan run` loop, unless/until this repo is properly onboarded. Don't route around that guard to force auto-merge.
8. **Never implement issue work directly on `main` in the primary worktree** — always create an issue-scoped branch first (`issue-N-<slug>`), even for a quick ad hoc "implement issue #N" ask that isn't going through a full `run` dispatch. See `skills/supersaiyan/SKILL.md` → "Golden rule: never implement issue work directly on the primary branch."

---

## Key docs (read order)

1. [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) — full walkthrough
2. [docs/super-board-analysis/plan-to-issues-bridge.md](docs/super-board-analysis/plan-to-issues-bridge.md) — issue strategies
3. [docs/super-board-analysis/idea-to-merged-playbook.md](docs/super-board-analysis/idea-to-merged-playbook.md) — architecture
4. [docs/superpowers/tasks/README.md](docs/superpowers/tasks/README.md) — task folder workflow

---

## Verify toolkit

```bash
./scripts/verify-super-board-setup.sh
```

---

*SuperSaiyan agent handoff — update when pipeline or scripts change.*
