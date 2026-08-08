---
title: Implement GitLab CI-detection and raw-URL embed functions
order: 11
depends_on_task: 10-gitlab-review-thread-resolve
feature: gitlab-integration
design: docs/superpowers/specs/gitlab-integration-design.md
plan:
plan_task: Architecture > Platform interface contract (Group I, Group J)
skills: superpowers:test-driven-development, superpowers:verification-before-completion
---

## Goal

The production-merge guard and inline screenshot embeds work correctly against a GitLab
project, matching the safety and UX GitHub configs already get.

## Acceptance Criteria

- [ ] `platform_detect_production_ci` matches a `.gitlab-ci.yml` job containing `environment:`
      gated by `rules: - if: '$CI_COMMIT_BRANCH == "main"'` (or `== $CI_DEFAULT_BRANCH`),
      verified against a fixture `.gitlab-ci.yml` with a real deploy-shaped job
- [ ] `platform_detect_production_ci` resolves at least one level of local `include:` when
      scanning for the deploy pattern
- [ ] `platform_detect_branch_protection` is implemented via the `protected_branches`
      endpoint, verified against a real sandbox project with a protected `main` branch
- [ ] `platform_raw_file_url` produces a `-/raw/<branch>/<path>` URL using
      `config.project.host` (not a hardcoded `gitlab.com`), and a screenshot embedded via this
      URL renders correctly when pasted into a real sandbox issue or MR comment

## Implementation notes

**Files:**
- Modify: `scripts/platforms/gitlab.sh`

**Interfaces:**
- Consumes: `config.project.host` (from the config schema addition in task 01)

## Out of scope

Onboarding's use of `platform_detect_production_ci` to force `human_approves_merge` (that
wiring happens in task 13).
