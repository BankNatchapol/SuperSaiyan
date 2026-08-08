---
title: Implement GitlabStatusAdapter and adapter dispatch
order: 12
depends_on_task: 11-gitlab-ci-detection-raw-url
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Recommended Approach > Per-script rewrite map (super-board-status.py); Open Judgment Call 4
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

`super-board status` renders a correct live snapshot for a GitLab-backed board, matching the
GitHub renderer's output shape exactly.

## Acceptance Criteria

- [ ] `scripts/platforms/status_adapter.py` gains a `GitlabStatusAdapter` implementing the
      `PlatformAdapter` interface from task 02: GraphQL issues query (`project(fullPath:)
      {issues{nodes{iid title webUrl state labels{nodes{title}} assignees{nodes{username}}}}}`,
      paginated via `pageInfo`) plus a notes fetch for comment-based reason-tag/root-cause-hash
      extraction
- [ ] The `status::` label-projection rule is implemented exactly once (per spec Open Judgment
      Call 4: the Python adapter shells out to the bash `platform_board_snapshot` derivation
      rather than reimplementing it independently) — verified by confirming a change to the
      bash-side projection logic is observable in the Python adapter's output without any
      Python-side edit
- [ ] `super-board-status.py --json` against a real sandbox GitLab project with a
      `git_platform: gitlab` config produces the same JSON shape (`version`, `config.slug`,
      `project.number`→`project` identifier, `lanes.*`, `workers`, `health`) as the existing
      GitHub test fixture in `tests/test-status-json.py`
- [ ] `scripts/super-board-status.py` dispatches to `GithubStatusAdapter` or
      `GitlabStatusAdapter` based on the config's `git_platform` field

## Implementation notes

**Files:**
- Modify: `scripts/platforms/status_adapter.py`
- Modify: `scripts/super-board-status.py`
- Test: add a GitLab-fixture variant of `tests/test-status-json.py`'s scenario (new file,
  e.g. `tests/test-status-json-gitlab.py`, or parametrize the existing one — implementer's
  call, document the choice)

**Interfaces:**
- Consumes: `PlatformAdapter` shape (task 02), `platform_board_snapshot`'s `status::`
  projection logic (task 07)

## Out of scope

Onboarding wiring (task 13) — this task only makes the status renderer correct once a GitLab
config already exists.
