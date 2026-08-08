---
title: Extract GithubStatusAdapter from super-board-status.py
order: 2
depends_on_task: 01-platform-interface-skeleton
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Architecture > Precedent to mirror (Python companion)
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

`super-board-status.py`'s existing GitHub-specific logic (the `ITEMS_QUERY` GraphQL call,
`gh(...)` wrapper, comment-based reason-tag/root-cause-hash extraction) is extracted behind a
named `GithubStatusAdapter`, as a pure refactor, so a `GitlabStatusAdapter` can be added later
(task 12) without touching this code path again.

## Acceptance Criteria

- [ ] `scripts/platforms/status_adapter.py` exists, defining a `PlatformAdapter` interface and
      a `GithubStatusAdapter` implementation wrapping today's `gh(...)`/`ITEMS_QUERY`/comment
      logic verbatim (moved, not rewritten)
- [ ] `scripts/super-board-status.py` imports and dispatches to `GithubStatusAdapter` for its
      existing GitHub code path
- [ ] `python3 tests/test-status-json.py` passes unmodified (no test changes needed — this
      confirms zero behavior change)
- [ ] `--json` output of `super-board-status.py` against the existing test fixture is
      byte-identical before and after this refactor

## Implementation notes

**Files:**
- Create: `scripts/platforms/status_adapter.py`
- Modify: `scripts/super-board-status.py`
- Test: `tests/test-status-json.py` (must pass unmodified)

**Interfaces:**
- Produces: the `PlatformAdapter` shape task 12's `GitlabStatusAdapter` implements against

## Out of scope

Implementing `GitlabStatusAdapter` itself — that's task 12, gated on GitLab's board-read
functions (task 07) existing first.
