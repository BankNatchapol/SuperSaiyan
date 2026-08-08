---
title: End-to-end smoke test — full Build to QA to Review cycle on GitLab
order: 16
depends_on_task: 15-smoke-test-single-issue
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Verification
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

A GitLab-backed board drains a real card through the full autonomous pipeline — Build, QA,
Review, merge — exactly like a GitHub-backed board does today, validating every race-safety
mitigation from task 08 under real concurrent dispatch, not a single-threaded test.

## Acceptance Criteria

- [ ] `super-board run` against the sandbox GitLab project (from task 15) dispatches a Builder
      that opens a draft MR for the Ready card
- [ ] Tester resolves any `[QA]`-prefixed discussions it owns; Reviewer resolves the remainder
      and squash-merges
- [ ] The card lands with the `status::done` label and the correct Issue Board list, verified
      independently (not from the dispatcher's own log claims — re-fetch the issue directly)
- [ ] During the run, deliberately dispatch or simulate a second concurrent card-status write
      on a different card to confirm task 08's race mitigation holds under genuine concurrent
      load, not just the isolated test from task 08
- [ ] Any defect found during this run is filed as a new task (do not silently patch — this
      task's job is to prove or disprove the preceding 15 tasks, not to expand scope invisibly)

## Implementation notes

**Files:**
- No planned production code changes — file follow-up issues for anything this run reveals

**Interfaces:**
- Consumes: the complete Platform interface (tasks 01-14) and the single-issue smoke test
  result (task 15)

## Out of scope

Anything not already covered by tasks 01-15's scope — this is a validation task, not a place
to introduce new functionality.
