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

The remaining task filing, wave planning, and dispatch paths use one strict Platform contract
for adapter selection, authentication, issue lookup, and optional board enqueue.

## Acceptance Criteria

- [ ] AC1 — Adapter-specific Ready enqueue: `tasks-to-issues.sh --board` resolves GitHub Project
      or GitLab status metadata through the selected adapter and calls
      `platform_card_status_set --add`.
- [ ] AC2 — Platform board snapshot: `super-board-wave-plan.sh` uses
      `platform_board_snapshot`, while the existing `Depends on: #N` dependency parsing remains
      unchanged.
- [ ] AC3 — Normalized issue view: Build dispatch and prepare use
      `platform_issue_view <issue>` with `PLATFORM_CONFIG_PATH` context and consume normalized
      `{number,title,body,labels:string[],state}` JSON.
- [ ] AC4 — Prepare regression coverage: all nine scenarios in
      `tests/test-supersaiyan-prepare.sh` pass.
- [ ] AC5 — Explicit board intent: direct `tasks-to-issues.sh` usage is issue-only by default,
      even in an onboarded repository; only `--board` permits Project authentication and Ready
      enqueue, and `supersaiyan prepare` always supplies it.
- [ ] AC6 — Strict shared config resolution: task filing, Build dispatch, and prepare use one
      Bash 3.2-compatible resolver with explicit/env/active/sole/default precedence and fail
      before adapter use on missing, ambiguous, stale, unsupported, or conflicting selections.
- [ ] AC7 — Auth and lookup safety: issue auth requires `repo` scope plus repository access,
      board auth additionally requires `project`, and only a confirmed issue-view exit `44`
      removes a map entry; exits `69`/`70` preserve it and abort.

## Implementation notes

**Files:**
- Modify: `scripts/tasks-to-issues.sh`
- Modify: `scripts/super-board-wave-plan.sh`
- Modify: `skills/super-build/scripts/super-build-dispatch.sh`
- Modify: `skills/supersaiyan/scripts/prepare.sh` (thread config context through the same
  adapter operations)
- Add: `scripts/platform-config.sh`
- Modify: `install.sh`, `scripts/bootstrap-app.sh`, setup/manual-filing documentation, and
  Issue #4 contract tests

**Interfaces:**
- Consumes: `platform_*` functions from `scripts/platforms/github.sh` (task 01)
- `platform_issue_view <issue>` returns normalized `{number,title,body,labels:string[],state}` JSON;
  adapters absorb forge-specific CLI flags and field names. Callers export
  `PLATFORM_CONFIG_PATH` so the adapter can resolve project context without
  leaking forge-specific arguments into the caller.
- `platform_auth_check issue|board` defaults to `issue` for backward compatibility.
- `platform_issue_view` returns `0` for found, `44` for confirmed not-found, `69` for
  authentication/permission failures, and `70` for transport/API/malformed-response failures.

**Failure semantics:** platform authentication, issue creation, board snapshot, and Ready
reconciliation failures during `supersaiyan prepare` are intentionally fail-fast.
The pre-adapter implementation suppressed some of these failures, which could report success
while leaving a partially queued board.

## Out of scope

`scripts/super-board-wave.js` — it has no direct `gh` shell-outs today (delegates to sub-agent
prompts); threading `config.git_platform` into its prompt strings is folded into task 13
(onboarding), not this task.
