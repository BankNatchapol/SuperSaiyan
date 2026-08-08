---
title: Write references/platforms.md and wire it into the reference generator
order: 14
depends_on_task: 13-gitlab-onboarding
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Architecture > Precedent to mirror
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

`skills/super-board/references/platforms.md` exists as the single documented source of truth
for the Platform interface contract and every per-platform command mapping — the same role
`backends.md` plays for worker backends — and it's kept in sync between the `super-board` and
`supersaiyan` skill copies the same way every other shared reference doc already is.

## Acceptance Criteria

- [ ] `skills/super-board/references/platforms.md` documents all 5+ Platform-interface
      function groups (mirroring `backends.md`'s structure: a contract table, then a
      per-platform reference section with exact verified commands), including the
      `git_platform: "workflow"-stays-Claude-Code-only` note is NOT applicable here (platform
      is orthogonal to worker backend — state this explicitly to avoid confusion with
      `backends.md`)
- [ ] `scripts/generate-supersaiyan-references.sh`'s `FILES` array includes `platforms.md`
- [ ] `scripts/generate-supersaiyan-references.sh --check` passes (confirms
      `skills/supersaiyan/references/platforms.md` is generated correctly)
- [ ] `python3 tests/test-reference-sync.py` passes
- [ ] Cross-check `platforms.md`'s function names against every skill doc reference added in
      task 05 — if task 05's pointer text used a different name than what actually got
      implemented in tasks 07-12, fix the mismatch here (this task is the last point where
      that consistency can be verified end-to-end)

## Implementation notes

**Files:**
- Create: `skills/super-board/references/platforms.md`
- Modify: `scripts/generate-supersaiyan-references.sh`

**Interfaces:**
- Consumes: the final, as-implemented function signatures from tasks 07-11 (not the spec's
  proposed signatures — if implementation diverged from the spec during those tasks, this doc
  reflects what was actually built)

## Out of scope

Any further code changes — this is a documentation-consistency task closing out the
implementation tasks (01-13).
