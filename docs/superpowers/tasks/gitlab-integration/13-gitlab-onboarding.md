---
title: Add GitLab onboarding — labels, board auto-provisioning, onboard.md rewrite
order: 13
depends_on_task: 12-python-gitlab-status-adapter
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Recommended Approach > Onboarding
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

`super-board onboard` can take a user from "empty GitLab project" to a fully configured board
— scoped labels created, an Issue Board with one list per status created, config written —
the same end state GitHub onboarding already produces, with a documented manual fallback if
the board-provisioning API breaks.

## Acceptance Criteria

- [ ] `skills/super-board/references/onboard.md` gains the platform question (detected from
      `git remote get-url origin` host; only asked if ambiguous) inserted per spec Recommended
      Approach > Onboarding, with every downstream step (auth, project/columns, base-branch
      production-detection, bot identity, worker self-check) made platform-conditional
- [ ] Running onboard against a real empty sandbox GitLab project creates the seven
      `status::*` scoped labels (or six for QA-only), creates an Issue Board via
      `POST .../boards`, creates one list per status via `POST .../boards/:id/lists` in the
      correct order, and writes `board_id` into the generated config
- [ ] If the raw `glab api` board/list creation fails, onboard prints the exact manual UI
      steps and continues with `board_id: null` rather than hard-failing — verified by forcing
      a failure (e.g. an already-existing board) and confirming graceful continuation
- [ ] `scripts/super-board-wave.js` threads `config.git_platform` into its dispatched
      sub-agent prompt string
- [ ] Worker self-check verifies `board_id` resolves and its list count matches the variant's
      status count

## Implementation notes

**Files:**
- Modify: `skills/super-board/references/onboard.md`
- Modify: `scripts/super-board-wave.js`

**Interfaces:**
- Consumes: `platform_label_ensure`, `platform_board_ensure`-shaped logic from tasks 07-11,
  `platform_detect_production_ci`/`platform_detect_branch_protection` from task 11

## Out of scope

Regenerating `skills/supersaiyan/references/onboard.md` by hand — task 14 wires this file into
the generator and regenerates it there.
