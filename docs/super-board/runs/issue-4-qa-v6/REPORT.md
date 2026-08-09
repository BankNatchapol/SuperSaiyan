# QA report — issue #4 (v6)

PR: #23 · Branch: `issue-4-rewire-tasks-to-issues-and-wave-plan` · Tested commit: `c57a94d`

Non-visual change (shell scripts / CLI dispatch) — screenshots are intentionally omitted.
Command output and this acceptance-criteria audit are the evidence.

## Rebuild verification

| Rebuild behavior | Observable verification | Result |
|---|---|---|
| Standalone issue creation requires repository authentication only | `test-tasks-wave-dispatch-platform-rewire.sh` exercises issue-only authentication without Project scope | ✅ Pass |
| Board enqueue/reconciliation requires Project access | The issue-specific suite exercises the real enqueue path, and live `platform_auth_check project` succeeds | ✅ Pass |
| Explicitly missing dispatch config must fail before adapter selection | The issue-specific suite supplies a stale config path and asserts that no fallback adapter is invoked | ✅ Pass |
| Adapter issue view receives platform config context | The sole-GitLab dispatch smoke requires a readable `PLATFORM_CONFIG_PATH` and consumes normalized issue JSON | ✅ Pass |

All PR review threads are resolved at the time of this QA run.

## Per-AC verification

| AC | Verification | Result |
|---|---|---|
| AC1 — platform-neutral Ready enqueue through adapter-specific metadata resolution and `platform_card_status_set --add` | The issue-specific contract suite executes the real `tasks-to-issues.sh` enqueue flow and observes Project validation, Ready resolution, item add, and item edit | ✅ Pass |
| AC2 — wave plan uses `platform_board_snapshot` and preserves dependency parsing | GitHub `--items`, live-fetch failure propagation, and GitLab platform-neutral config-context cases pass | ✅ Pass |
| AC3 — dispatch uses normalized `platform_issue_view` with forge-specific context | The sole-GitLab-config dispatch smoke requires `PLATFORM_CONFIG_PATH`, normalized issue fields, and correct adapter selection | ✅ Pass |
| AC4 — all 9 prepare scenarios remain green | Fresh `bash tests/test-supersaiyan-prepare.sh` run | ✅ Pass — 9 scenarios |
| AC5 — standalone issue creation works with repository auth; Project scope is deferred to board operations | Contract coverage plus fresh live no-argument and `project` authentication checks | ✅ Pass |

## Fresh local verification

```text
bash tests/test-tasks-wave-dispatch-platform-rewire.sh
bash tests/test-prepare-platform-rewire.sh
bash tests/test-supersaiyan-prepare.sh
bash tests/test-platform-contract.sh
bash tests/test-backend-contract.sh
bash tests/test-build-safety-contract.sh
bash tests/test-run-platform-rewire.sh
bash -n <all 8 changed shell files>
source scripts/platforms/github.sh && platform_auth_check && platform_auth_check project
git diff --check origin/main...HEAD
gh api graphql <unresolved review-thread query>
```

All commands exited 0. See `test-output.log` for the result transcript.

## Verdict

Pass. All five acceptance criteria pass fresh verification at `c57a94d`, the rebuild-specific
authentication/config-context behaviors have regression coverage, and no unresolved PR review
threads remain.
