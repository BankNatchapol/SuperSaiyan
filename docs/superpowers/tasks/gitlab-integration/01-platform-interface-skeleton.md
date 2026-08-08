---
title: Add Platform interface skeleton and git_platform config field
order: 1
depends_on_task: null
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Architecture > Platform interface contract; Config schema
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

`scripts/platforms/github.sh` exists implementing the full Platform interface as a pure
refactor of today's literal `gh` calls (zero behavior change), and `git_platform` is a
documented config field, so every later GitLab task has a contract to implement against.

## Acceptance Criteria

- [ ] `skills/super-board/references/config-schema.json` gains a `git_platform` field
      (default `"github"`), documented as a sibling to `worker_backend` per the spec's
      Architecture > Config schema section
- [ ] `scripts/platforms/github.sh` defines every function listed in the spec's Platform
      interface contract (Groups A-K), each a thin wrapper around the exact `gh` command it
      replaces today (extracted from `scripts/super-board-run.sh`, `scripts/tasks-to-issues.sh`,
      `scripts/super-board-gh-guard.sh`) — no behavior change, same commands, now named
- [ ] `tests/test-platform-contract.sh` exists (mirrors `tests/test-backend-contract.sh`'s
      structure: static syntax + function-presence check, no live API calls) and passes
      against `scripts/platforms/github.sh`
- [ ] `bash -n scripts/platforms/github.sh` passes

## Implementation notes

**Files:**
- Create: `scripts/platforms/github.sh`
- Create: `tests/test-platform-contract.sh`
- Modify: `skills/super-board/references/config-schema.json`

**Interfaces:**
- Produces: the `platform_*` function names every later task (03-16) sources or implements
  against for the `gitlab.sh` counterpart

## Out of scope

Rewiring any dispatcher script or skill doc to actually call these functions instead of raw
`gh` — that's tasks 03-05. This task only establishes the contract and the GitHub-side
implementation of it.
