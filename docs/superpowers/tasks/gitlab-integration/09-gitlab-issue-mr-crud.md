---
title: Implement GitLab issue and MR CRUD functions
order: 9
depends_on_task: 08-gitlab-cardmove-claim-race-safety
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Architecture > Platform interface contract (Group F, Group G)
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

`scripts/platforms/gitlab.sh` can create/view/comment/close/label issues and create/manage
draft merge requests, giving lane workers everything they need for the Builder/Tester/
Reviewer lifecycle short of review-thread resolution (task 10).

## Acceptance Criteria

- [ ] `platform_issue_create`/`platform_issue_view`/`platform_issue_comment`/
      `platform_issue_close`/`platform_issue_edit_labels` are implemented per spec Group F,
      each verified against a real sandbox GitLab project (create one, view it, comment on it,
      edit its labels, close it)
- [ ] `platform_mr_create_draft` uses `--draft` (not the removed `--wip`) and the resulting MR
      shows as Draft in GitLab's UI
- [ ] `platform_mr_mark_ready`/`platform_mr_comment`/`platform_mr_merge_squash`/
      `platform_mr_view`/`platform_mr_list_by_branch` are implemented per spec Group G, each
      verified against the same sandbox MR (mark ready, comment, view, list-by-branch, then
      squash-merge with source-branch removal)
- [ ] `tests/test-platform-contract.sh` still passes with the extended `gitlab.sh`

## Implementation notes

**Files:**
- Modify: `scripts/platforms/gitlab.sh`

**Interfaces:**
- Consumes: `platform_issue_view`/`platform_claim_issue` from tasks 07-08 for the sandbox
  verification flow
- Produces: the MR object task 10's review-thread functions operate against

## Out of scope

Review-thread list/resolve/create (task 10) — a draft MR with no discussions is sufficient to
satisfy this task's acceptance criteria.
