---
title: Rewire super-board-run.sh to the Platform interface
order: 3
depends_on_task: 02-python-github-status-adapter
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Recommended Approach > Per-script rewrite map (super-board-run.sh)
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

`scripts/super-board-run.sh` sources the platform contract by `git_platform` the same way it
already sources the worker backend by `worker_backend`, and every inline `gh` call is routed
through `platform_*` functions instead.

## Acceptance Criteria

- [ ] `super-board-run.sh` reads `GIT_PLATFORM` from config (`jq -r '.git_platform // "github"'`)
      and sources `scripts/platforms/${GIT_PLATFORM}.sh` (dev) / `.claude/bin/platforms/${GIT_PLATFORM}.sh`
      (installed), `BASH_SOURCE`-relative, mirroring the existing `WORKER_BACKEND` sourcing
- [ ] The inline `gh project item-list`, `gh api rate_limit`, and `gh issue edit
      --add-assignee`/`--remove-assignee` calls are replaced with `platform_board_snapshot`,
      `platform_rate_remaining`, `platform_claim_issue`, `platform_release_issue`
- [ ] The production-merge guard's `.github/workflows` grep is replaced with a call to
      `platform_detect_production_ci`
- [ ] Re-running this session's earlier smoke test (temp repo + config with
      `"git_platform": "github"`, `"worker_backend": "claude-p"`) exits cleanly with identical
      log output shape to before this change

## Implementation notes

**Files:**
- Modify: `scripts/super-board-run.sh`

**Interfaces:**
- Consumes: `platform_*` functions from `scripts/platforms/github.sh` (task 01)
- Produces: the sourcing pattern task 08 relies on being already wired, so
  `scripts/platforms/gitlab.sh` slots in with no further dispatcher changes

## Out of scope

`scripts/super-board-gh-guard.sh`'s own quota-check internals — only the caller-side
`platform_rate_remaining` swap happens here; the guard script's rename/restructure (if any) is
handled where it's actually invoked from, not duplicated in this task.
