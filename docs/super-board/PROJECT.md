# SuperSaiyan — Project Overview

## What it is

SuperSaiyan is a Claude Code plugin that implements an end-to-end AI development
pipeline. Given a feature idea, it runs brainstorm → spec → task decomposition →
autonomous Build → QA → Review, draining a GitHub Project board until done.

## Stack & conventions

- **Runtime:** Claude Code (skills system, plugin marketplace)
- **Orchestration:** GitHub Projects (kanban board as state machine)
- **Skills:** Markdown files under `skills/supersaiyan/` loaded via `Skill` tool
- **References:** `skills/supersaiyan/references/` — per-verb step-by-step logic
- **Tasks/Specs:** `docs/superpowers/` — pipeline-ready specs and task files
- **Tests:** `tests/` — skill and integration tests

## Success criteria

- `/supersaiyan new <slug>` produces a spec + task files + GitHub issues in Ready
- `/supersaiyan run` autonomously cycles issues through Building → QA → Review → Done
- All task files pass `super-board lint` before run
