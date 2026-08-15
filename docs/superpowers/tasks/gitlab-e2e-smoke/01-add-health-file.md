---
title: Add HEALTH.md with ok
order: 1
depends_on_task: null
feature: gitlab-e2e-smoke
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Verification
skills: superpowers:verification-before-completion
---

## Goal

`HEALTH.md` exists on `main` containing the single word `ok`.

## Acceptance Criteria

- [ ] `HEALTH.md` is at the repository root
- [ ] The file contents are exactly `ok` plus a trailing newline
- [ ] The change lands via a squash-merged merge request
