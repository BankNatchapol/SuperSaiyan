---
title: Rewire tasks-to-issues.sh, wave-plan, and super-build-dispatch to the Platform interface
order: 4
depends_on_task: 03-rewire-super-board-run
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Recommended Approach > Per-script rewrite map
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

The three remaining scripts with direct `gh` calls (`tasks-to-issues.sh`,
`super-board-wave-plan.sh`, and `super-build-dispatch.sh`'s issue-view call) route through the
Platform interface instead.

## Acceptance Criteria

- [ ] `scripts/tasks-to-issues.sh`'s `gh project view`/`field-list`/`item-add`/`item-edit
      --single-select-option-id` sequence is replaced with the platform adapter's logical Ready
      enqueue: GitHub resolves the Project Status/Ready option through `platform_board_ensure`,
      while GitLab resolves the `status::ready` label through `platform_label_ensure`, followed by
      `platform_card_status_set`'s add-only case
- [ ] `scripts/super-board-wave-plan.sh`'s `gh project item-list` call is replaced with
      `platform_board_snapshot`; the `Depends on: #N` jq dependency-parsing logic is unchanged
      (confirms the snapshot's output shape matches today's `.content.*`/`.status` fields)
- [ ] `skills/super-build/scripts/super-build-dispatch.sh`'s `gh issue view` call is replaced
      with `platform_issue_view`
- [ ] `./tests/test-supersaiyan-prepare.sh` (all 9 scenarios) still passes

## Implementation notes

**Files:**
- Modify: `scripts/tasks-to-issues.sh`
- Modify: `scripts/super-board-wave-plan.sh`
- Modify: `skills/super-build/scripts/super-build-dispatch.sh`

**Interfaces:**
- Consumes: `platform_*` functions from `scripts/platforms/github.sh` (task 01)

## Out of scope

`scripts/super-board-wave.js` — it has no direct `gh` shell-outs today (delegates to sub-agent
prompts); threading `config.git_platform` into its prompt strings is folded into task 13
(onboarding), not this task.
