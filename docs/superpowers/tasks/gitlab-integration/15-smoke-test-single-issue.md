---
title: Smoke test — file one GitLab issue end-to-end
order: 15
depends_on_task: 14-platforms-reference-doc
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Verification
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

`tasks-to-issues.sh` correctly files a real issue onto a real GitLab project's board, proving
the full write path (label resolution, issue creation, board placement) works together, not
just each function in isolation.

## Acceptance Criteria

- [ ] Against a real sandbox GitLab project with `git_platform: gitlab` onboarded (task 13),
      running `tasks-to-issues.sh` with a single trivial task file creates a real GitLab issue
- [ ] The created issue carries the `status::ready` label
- [ ] The issue appears in the "Ready" list on the project's Issue Board (verified via the
      GitLab UI or `glab api`, not just by trusting the mutation's return code)
- [ ] `docs/superpowers/tasks/<test-feature>/.issue-map.json` is written with the correct
      issue number and URL

## Implementation notes

**Files:**
- No production code changes expected — this task exercises tasks 01-14's work end-to-end
  and fixes anything that breaks under real integration (not caught by any single task's
  isolated verification)
- Test: document the exact sandbox project used and the commands run, so task 16 can reuse the
  same project

**Interfaces:**
- Consumes: everything from tasks 01-14

## Out of scope

Running the actual Build → QA → Review cycle on the filed issue — that's task 16.
