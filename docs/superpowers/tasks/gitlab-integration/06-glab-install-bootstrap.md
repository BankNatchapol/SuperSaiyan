---
title: Install glab and check GitLab auth in bootstrap/install scripts
order: 6
depends_on_task: 05-rewrite-skill-docs-platform-agnostic
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Recommended Approach > Per-script rewrite map (bootstrap-app.sh)
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

A machine running `bootstrap-app.sh` for the first time gets `glab` installed unconditionally
(alongside `gh`), and a target repo's `.claude/bin/platforms/` is populated on install, so
GitLab configs work without a second setup round-trip.

## Acceptance Criteria

- [ ] `scripts/bootstrap-app.sh` installs `glab` via `install_brew_package glab glab`
      unconditionally, alongside the existing `gh` install
- [ ] `check_authentication()` branches on the target config's (or a to-be-onboarded config's)
      `git_platform`, checking `glab auth status` when applicable, with the same friendly
      remediation-message style as the existing `gh auth status` check
- [ ] `install.sh` copies `scripts/platforms/` into `.claude/bin/platforms/` in the target
      repo, mirroring the existing `scripts/backends/` → `.claude/bin/backends/` copy step
      (including making the copied files executable)
- [ ] `./install.sh --check` still passes with no changes to its output for a target with no
      GitLab config

## Implementation notes

**Files:**
- Modify: `scripts/bootstrap-app.sh`
- Modify: `install.sh`

**Interfaces:**
- Consumes: `scripts/platforms/github.sh` (task 01) as the thing being copied; no GitLab file
  needs to exist yet for this task's acceptance criteria (the copy step copies whatever's in
  the directory at install time, GitLab or not)

## Out of scope

Anything under `scripts/platforms/gitlab.sh` itself — that starts at task 07.
