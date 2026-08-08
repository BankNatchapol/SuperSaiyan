---
title: Make worker-facing skill docs platform-agnostic
order: 5
depends_on_task: 04-rewire-tasks-to-issues-and-wave-plan
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Architecture > One structural difference from the worker-backend precedent
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

No worker-facing skill doc contains a literal `gh`/`gh api graphql` command any more — every
GitHub-specific operation (review-thread resolve, issue close, label edit, etc.) is described
in terms of `platform_*` operations, so a worker running under `git_platform: gitlab` gets
correct instructions instead of silently broken GitHub-only commands.

## Acceptance Criteria

- [ ] `grep -rn 'gh api\|gh issue\|gh pr\|gh project' skills/super-board/references/run.md
      skills/super-board/references/block-template.md skills/super-build/references/worker-preamble.md
      skills/super-build/SKILL.md skills/super-qa/SKILL.md` returns zero matches in
      worker-instruction prose (citations/comments referencing "the `gh` CLI" by name for
      context are fine; literal invocable commands are not)
- [ ] Each of those five files gains a one-line pointer to `references/platforms.md` for the
      concrete per-platform command (file created in task 14 — pointer text is written now,
      target file lands later; this is expected and not a broken link at review time since
      task 14 depends on this task)
- [ ] The `resolveReviewThread` GraphQL mutation text in `run.md`'s Gate 1 section is replaced
      with a description of `platform_thread_resolve`
- [ ] `skills/supersaiyan/references/run.md` is regenerated via
      `scripts/generate-supersaiyan-references.sh` and `--check` passes

## Implementation notes

**Files:**
- Modify: `skills/super-board/references/run.md`
- Modify: `skills/super-board/references/block-template.md`
- Modify: `skills/super-build/references/worker-preamble.md`
- Modify: `skills/super-build/SKILL.md`
- Modify: `skills/super-qa/SKILL.md`

**Interfaces:**
- Consumes: `platform_*` function names from task 01
- Produces: doc text that task 14's `platforms.md` must stay consistent with — if task 14
  reveals a naming mismatch, that task fixes it (noted there as a dependency), not this one

## Out of scope

Writing `references/platforms.md` itself (task 14). Any change to the actual dispatcher
scripts (already done in tasks 03-04).
