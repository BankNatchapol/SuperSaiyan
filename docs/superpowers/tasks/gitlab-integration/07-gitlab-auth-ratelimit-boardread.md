---
title: Implement GitLab auth, rate-limit, and board-read functions
order: 7
depends_on_task: 06-glab-install-bootstrap
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Architecture > Platform interface contract (Groups A, B, C)
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

`scripts/platforms/gitlab.sh` exists with working auth-check, rate-limit, and board-read
functions, so the read-only half of the GitLab integration is provably correct before the
riskier write-side work (task 08) begins.

## Acceptance Criteria

- [ ] `platform_auth_check` and `platform_bot_identity_resolve` are implemented via
      `glab auth status` and the Project/Group Access Token vs. personal-token distinction
      (spec Group A), verified against a real logged-in `glab` session
- [ ] `platform_rate_remaining`/`platform_rate_guard` are implemented via the
      `RateLimit-Remaining`/`RateLimit-Reset` response-header probe on a cheap REST call, and
      fail open (treat as unknown, never as zero) when headers are absent
- [ ] `platform_board_snapshot` returns the normalized `{number,title,url,state,repository,
      assignees[],labels[],status}[]` shape from spec Group C, with `status` derived by
      scanning `labels[]` for the `status::` prefix (first match wins; zero matches →
      `"Backlog"`), verified against a real sandbox GitLab project with a mix of labeled and
      unlabeled issues
- [ ] `tests/test-platform-contract.sh` passes with `gitlab.sh` included in the checked set

## Implementation notes

**Files:**
- Modify: `scripts/platforms/gitlab.sh` (created by this task; extended by tasks 08-11)

**Interfaces:**
- Consumes: a real GitLab sandbox project (with at least one issue carrying a `status::*`
  label and one without) for verification
- Produces: `platform_board_snapshot`'s exact output shape, which tasks 08 and 12 depend on
  matching precisely

## Out of scope

Any board write operation (card-move, claim/release — task 08), issue/MR CRUD (task 09),
review threads (task 10), CI detection (task 11).
