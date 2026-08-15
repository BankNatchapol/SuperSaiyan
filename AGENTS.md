# Agent handoff — SuperSaiyan

Read this first when working in **this repository** (`SuperSaiyan`). Humans follow [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md); this file is the compressed context for agents.

---

## What this repo is

| Repo | Role |
|------|------|
| **SuperSaiyan** (here) | Toolkit source: flattened **skills** (super-board fork + bridge skills); setup scripts; guides; optional Control Center |
| **User's app repo** (e.g. `my-first-agent-app`) | Real product code, GitHub issues, Project board, PRs — **where the pipeline runs** |

Do not confuse the two. super-board slash commands and the feature pipeline run in the **app repo**, not in SuperSaiyan (except studying skill sources here).

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
  CLAUDE.md                          `@AGENTS.md` pointer
  FUTURE_WORK.md                     backlog notes
  TESTING.md                         test conventions
  install.sh                         app-repo installer (skills + pipeline scripts)
  apps/desktop/                      optional Electron control center
  packages/
    control-protocol/                typed UI/main-process contract
    control-core/                    repo, GitHub, config, and watcher services
    ui/                              shared React renderer (no Electron imports)
  design/dashboard-control-center/   extracted Aura Console design reference
  docs/
    GETTING-STARTED.md               ← primary human tutorial (20 steps)
    templates/                       issue.md, task-file.md, github-project-columns.md
    superpowers/tasks/README.md      task-folder convention
    super-board-analysis/            architecture + plan-to-issues bridge
  skills/
    refining-spec/                   office-hours design → repo spec
    writing-board-tasks/             spec → PR-sized task .md files
    supersaiyan/                     prepare tasks → Ready issues → lint
    super-board/                     board orchestration (fork)
    super-build/                     Build lane
    super-qa/                        QA lane
    super-review/                    Review lane
    test-driven-development/         TDD discipline used by Builder
    verification-before-completion/  verification gate used by Builder and QA
  scripts/
    bootstrap-app.sh                 check/install dependencies + configure app repo
    install-bridge-skills.sh         copy bridge skills + templates → app repo
    setup-gstack-artifacts-path.sh   docs/gstack/ layout + AGENTS.md rules → app repo
    tasks-to-issues.sh               task .md → gh issue create (run from app repo)
    split-plan-to-tasks.sh           stub only — prefer writing-board-tasks agent
    verify-super-board-setup.sh      smoke check for toolkit clones
    super-board-wave.js              wave planner (issues only)
  tests/                             shell/python integration tests for scripts/skills
  .claude-plugin/                    Claude Code plugin manifest
  .codex-plugin/                     Codex plugin manifest
  .supersaiyan/configs/              onboard config for this repo (GitHub Project #3)
  .gstack/                           optional local gstack artifact cache (gitignored)
```

---

## App repo layout (after bootstrap)

Created by `install.sh` + `install-bridge-skills.sh` + `setup-gstack-artifacts-path.sh`:

```text
my-first-agent-app/
  AGENTS.md                          canonical agent instructions (fenced supersaiyan blocks) — Codex + Cursor read this natively
  CLAUDE.md                          `@AGENTS.md` pointer — Claude Code does not read AGENTS.md natively
  docs/
    templates/agent-blocks/          (in SuperSaiyan, not here) the single source for the AGENTS.md blocks above
    supersaiyan/migrations/          backups of legacy CLAUDE.md sections moved into AGENTS.md
    gstack/designs/                  /office-hours copies
    gstack/specs/                    /spec copies (optional)
    superpowers/specs/               feature specs (refining-spec output)
    superpowers/tasks/<feature>/     board task files (writing-board-tasks output)
    templates/                       issue.md, task-file.md
  scripts/gstack-env.sh              optional GSTACK_HOME=<repo>/.gstack
  .claude/skills/                    super-board + refining-spec + writing-board-tasks (Claude Code's own skill-discovery path — stays under .claude/)
  .supersaiyan/bin/                  super-board dispatcher scripts
  .supersaiyan/workflows/            super-board-wave.js
  .supersaiyan/configs/              onboard writes <slug>.json here (legacy: .claude/supersaiyan/configs/, .claude/super-board/configs/ — still read via fallback)
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
| `setup-gstack-artifacts-path.sh` | Yes | Upserts a fenced `gstack-paths` block into the app's AGENTS.md (updates in place on re-run); migrates the legacy CLAUDE.md section with a backup; creates doc dirs |
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

Both are forks/adaptations of superpowers/gstack patterns — see each `SKILL.md` under `skills/`.

**writing-board-tasks** rules of thumb:
- One task file = one GitHub issue = one PR through Build → QA → Review
- 3–5 **observable** acceptance criteria per task (not TDD micro-steps)
- Agent may merge/split spec requirements; not a 1:1 header split

---

## gstack artifact paths

When you run gstack `/office-hours` or `/spec` in an app repo, **also save a copy** in the
repo — do not skip this. Agents and git only see files under the repository; gstack's own
default save location is not in git and not visible to a headless worker.

The exact paths (gstack default → required repo copy, plus the pipeline-canonical spec/tasks
locations) are the same tables `install.sh` / `setup-gstack-artifacts-path.sh` write into an
app repo's `AGENTS.md`. Read them at `docs/templates/agent-blocks/pipeline-paths.md` and
`docs/templates/agent-blocks/gstack-paths.md` — those are the single source; don't re-copy the
tables here, edit them there so app repos stay in sync automatically.

After `/office-hours`, run **refining-spec** (or copy by hand) so the pipeline's canonical spec
file exists **before** running **writing-board-tasks**.

Optional: `source scripts/gstack-env.sh` sets `GSTACK_HOME=<app>/.gstack` to relocate gstack's
own default save location inside the app repo instead of the home directory.

---

## Tool parity — Claude Code / Codex / Cursor

The goal is that anything you can do here in Claude Code, you can do in Codex and Cursor.
Where that isn't true yet, it's stated plainly rather than implied.

| Capability | Claude Code | Codex | Cursor |
|---|---|---|---|
| Skill format (`SKILL.md`) | ✅ | ✅ | ✅ — Agent Skills open standard, byte-identical files, no per-tool variants |
| Skill auto-discovery in an app repo | ✅ plugin cache, or `.claude/skills/` | ✅ `.agents/skills/` | ✅ `.agents/skills/` |
| Project instructions | ✅ `CLAUDE.md` → `@AGENTS.md` | ✅ `AGENTS.md` (native) | ✅ `AGENTS.md` (native) |
| Headless Build/QA/Review lanes | ✅ `claude-p` | ✅ `codex-exec` | ✅ `cursor-agent` |
| Plugin manifest | ✅ `.claude-plugin/` | ✅ `.codex-plugin/` | ➖ no plugin concept; uses skills + rules |
| Published marketplace install | ✅ `claude plugin install` | ⚠️ manifest ships, but OpenAI self-serve publishing was still "coming soon" as of 2026-05 — install by cloning + `install.sh` | ➖ n/a |
| In-session wave orchestration | ✅ workflow backend | ➖ no equivalent primitive | ➖ no equivalent primitive |

Two asymmetries are real and not worth pretending away:

- **The workflow backend is Claude-Code-only** — it uses Claude Code's own `/workflows`
  primitive. Codex and Cursor get the same Build → QA → Review lanes through the bash
  dispatcher (`worker_backend: codex-exec` / `cursor-agent`), which is a complete substitute
  for draining a board; it just isn't the same in-session mechanism.
- **Headless workers still read `.claude/skills/`**, not `.agents/skills/` — that path is
  baked into `dispatch_lane`'s prompt and doubles as super-build's pipeline-dispatched mode
  signal (see `references/backends.md`). So a codex/cursor **worker** still needs
  `./install.sh --keep-local-skills`. `.agents/skills/` fixes **interactive** discovery, which
  is where the gap actually was.

`.claude/skills/` itself can't move: Claude Code's own loader requires that exact path.

---

## super-board essentials

- **Verbs:** `onboard`, `lint`, `status`, `run`, `stop`
- **Trigger:** GitHub Project card in **Ready** linked to an **Issue**
- **Does not:** auto-read plan files, auto-create issues from specs, run without a Ready card
- **Wave planner:** issues only (`content.type == "Issue"`) — see `scripts/super-board-wave.js`
- **Install:** `install.sh` — do not hand-copy skills unless debugging

Config schema: `skills/super-board/references/config-schema.json`

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
| Bridge skill behavior | `skills/refining-spec/`, `skills/writing-board-tasks/` |
| Issue/task file shape | `docs/templates/` |
| Agent instructions installed into an app repo (AGENTS.md blocks) | `docs/templates/agent-blocks/` — never the installed copy |
| Anything under a generated path | The source named in `.cursor/rules/supersaiyan-generated-files.mdc`, then re-run that generator |
| Plan → issues analysis | `docs/super-board-analysis/plan-to-issues-bridge.md` |
| super-board fork behavior | `skills/super-board/` |
| gstack / superpowers upstream | installed plugins + bridge skills — do not vendor or patch here |

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
~/Documents/SuperSaiyan/scripts/tasks-to-issues.sh docs/superpowers/tasks/<feature-slug> --board
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
5. **super-board fork** — lives in `skills/super-board/`; avoid drive-by edits. Prefer SuperSaiyan bridge skills over patching upstream gstack or superpowers plugins.
6. **Control Center stays optional** — UI code lives in `apps/` and `packages/`; never make it a prerequisite for skills or CLI use.
7. **This repo has an onboarded `.supersaiyan/configs/supersaiyan.json`** (added 2026-08-08, moved from `.claude/supersaiyan/configs/` 2026-08-10), linked to GitHub Project #3 ("SuperSaiyan") which is used for real issue tracking here. `/supersaiyan run` drives the full autonomous Build → QA → Review loop in this repo now, same as any onboarded app repo — hand-driving branch → PR → Super QA → Super Review is no longer the only path, just still fine for ad hoc asks. That config sets `human_approves_merge: true`, though: even a clean Review pass only marks the PR ready, it does not squash-merge — a human still clicks merge. Don't flip that to auto-merge without asking; this repo ships as a pinned-commit Claude Code plugin, so a bad auto-merge to `main` doesn't go live until someone updates the plugin, but it then moves everyone on that pin at once. **Each arrow is a separate turn** still applies to manual/ad-hoc lane work done outside the autonomous loop: do one lane (Build, QA, or Review), post its result, then stop and report back — never chain two lanes (e.g. QA straight into Review) in the same response. The automated pipeline enforces this via separate worker dispatches per lane; collapsing lanes into one pass turns Review from an independent re-check of QA into the same reasoning re-approving itself, and removes the checkpoint where the user would otherwise see one lane's result before the next begins.
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
