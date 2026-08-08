---
title: Implement GitLab review-thread list/resolve/create
order: 10
depends_on_task: 09-gitlab-issue-mr-crud
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Architecture > Platform interface contract (Group H); Open Judgment Call 5
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

Reviewer's Gate 1 (unresolved-thread scan, narrow re-verification, self-resolve) works
identically on GitLab MRs as it does on GitHub PRs, including the fiddlier case of creating a
new line-level discussion thread.

## Acceptance Criteria

- [ ] `platform_thread_list_unresolved` filters `mergeRequest.discussions` to non-resolved AND
      `notes[0].resolvable:true`, verified against a real sandbox MR carrying a mix of
      resolvable discussions and plain top-level notes (only the resolvable ones are returned)
- [ ] `platform_thread_resolve` calls `discussionToggleResolve` and is verified idempotent
      (calling it twice on an already-resolved discussion does not error)
- [ ] `platform_thread_create` opens a genuine line-level discussion at a specific file:line on
      a real sandbox MR, visible correctly positioned in GitLab's UI — the investigation
      spike's findings on the SHA `position` object requirements are recorded as comments in
      `gitlab.sh`
- [ ] The GitLab equivalent of GitHub's "unprefixed top-level human comment = Block signal"
      convention (spec Open Judgment Call 5) is decided and documented in a code comment plus
      a note added to the design spec's Open Judgment Calls section confirming resolution

## Implementation notes

**Files:**
- Modify: `scripts/platforms/gitlab.sh`
- Modify: `docs/superpowers/specs/gitlab-integration-design.md` (resolve Open Judgment Call 5)

**Interfaces:**
- Consumes: a real sandbox MR from task 09's verification flow

## Out of scope

CI detection, raw-URL embeds (task 11). Budget real investigation time for
`platform_thread_create` — this was explicitly flagged in the design spec as the fiddliest
mapping in the whole surface; do not treat it as a copy-paste implementation.
