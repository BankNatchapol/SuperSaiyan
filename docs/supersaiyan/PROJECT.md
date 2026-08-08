# SuperSaiyan — PROJECT.md

## What this is

SuperSaiyan is a Claude Code plugin/toolkit: an end-to-end AI development pipeline
("idea → merged PR with one command set") that other repos install and run against.
This repo is the toolkit's own source — not a typical deployed product.

Distribution: installed either as a Claude Code plugin (`claude plugin install
supersaiyan`, pinned commit synced from `origin/main`) or by direct clone +
`install.sh` into a target app repo. There is no hosted deploy of this repo itself —
"production" here means "the commit other people's Claude Code sessions are
currently running," not a live URL.

## Stack

- Node.js (`>=22`) npm workspaces monorepo: `apps/*`, `packages/*`.
- `apps/desktop` — optional Electron control center (React renderer in `packages/ui`,
  typed IPC contract in `packages/control-protocol`, repo/GitHub/config/watcher
  services in `packages/control-core`).
- Everything outside `apps/`/`packages/` is bash + Markdown: setup scripts
  (`scripts/`), vendored upstream tool clones (`gstack/`, `superpowers/`,
  `super-board/`), bridge skills (`.claude/skills/`), and docs (`docs/`).
- Scripts must run on macOS default bash 3.2 — no `mapfile`, no `declare -A`.

## Conventions (see AGENTS.md for the full, authoritative list)

- Most of this repo is docs + glue; real product/app code for end users lives in
  *their* app repo, not here. Minimize scope on any change.
- `gstack/`, `superpowers/`, `super-board/` are upstream clones/forks — avoid
  drive-by edits; prefer the SuperSaiyan bridge skills layer.
- Never implement issue work directly on `main` — always an issue-scoped branch
  (`issue-N-<slug>`) first, even for small asks.
- After changing bridge skills, re-run `install-bridge-skills.sh` on app repos to
  propagate (not automatic — this repo and its consumers are separate checkouts).
- The Control Center (`apps/`, `packages/`) stays optional — never make it a
  prerequisite for skills or CLI use.

## Success criteria

- A change is "done" when: the relevant script/skill/doc works standalone (tested
  manually or via `scripts/verify-super-board-setup.sh` where applicable), CI
  (`control-center.yml`, `skills-lint.yml`) is green, and — if it touches anything
  under `.claude/skills/` — the change has actually been propagated/considered for
  app-repo consumers, not just edited in place here.
- Because this repo is consumed as a pinned-commit plugin by other sessions, a
  broken `main` has a real (if delayed) blast radius: it doesn't go live until
  someone runs `claude plugin marketplace update supersaiyan` + `claude plugin
  update supersaiyan`, but when they do, everyone on that pin moves at once.
