---
title: Implement race-safe GitLab card-move and claim/release
order: 8
depends_on_task: 07-gitlab-auth-ratelimit-boardread
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Architecture > Platform interface contract (Group D, Group E); Requirement 4
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

Moving a card between board columns and claiming/releasing an issue as a worker mutex are
both provably race-safe on GitLab, given the confirmed, currently-open scoped-label bug
(gitlab-org/gitlab#207269) that GitHub's atomic single-select field write never had to guard
against. This is the highest-risk task in the whole feature — review it against that bug
report specifically, not just the code diff.

## Acceptance Criteria

- [ ] `platform_card_status_set` sends a combined `remove_labels`/`add_labels` PUT, then calls
      `platform_card_move_verify` (re-GETs the issue's labels and confirms exactly one
      `status::*` label matches the target); on mismatch it retries once via an explicit
      two-step remove-then-add (remove confirmed via its own verify before the add fires); on
      continued failure it returns non-zero rather than silently leaving inconsistent state
- [ ] A concurrent-write test exists and passes: two near-simultaneous
      `platform_card_status_set` calls targeting different statuses on the same sandbox issue
      — after both complete, the issue has exactly one `status::*` label, and it matches
      whichever call's mutation actually landed last (no duplicate or stale label survives)
- [ ] `platform_claim_issue` reads the issue's current assignees first and returns 1
      ("already claimed") if any assignee other than the claiming bot identity is present,
      before attempting the write — verified by a test that pre-assigns a different (human)
      user and confirms claim is refused
- [ ] `platform_claim_issue`'s actual assignment call uses a single-element `assignee_ids[]`
      array, never the comma-joined `assignee_ids=1,2` form (confirmed broken by GitLab)
- [ ] `platform_release_issue` is implemented, with a code comment documenting the
      co-assignee-eviction limitation from spec Open Judgment Call 3 (accepted, not engineered
      around)

## Implementation notes

**Files:**
- Modify: `scripts/platforms/gitlab.sh`
- Test: a new concurrency test exercising the retry path (exact path/framework to match this
  repo's existing bash-test conventions, e.g. `tests/test-gitlab-cardmove-race.sh`)

**Interfaces:**
- Consumes: `platform_board_snapshot` (task 07) for the verify step
- Produces: the race-safety guarantee tasks 13, 15, and 16 rely on when they exercise real
  concurrent dispatch

## Out of scope

Issue/MR CRUD (task 09), review threads (task 10). If the concurrent-write test reveals the
retry-once policy is insufficient (still races under real GitLab latency), escalate that
finding rather than silently increasing the retry count — it may mean the halt-gate story in
`run.md`'s "Known issue — multi-attempt card moves" needs its own follow-up task.
