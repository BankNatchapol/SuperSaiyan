# QA report — issue #4 (v3)

PR: #23 · Branch: `issue-4-rewire-tasks-to-issues-and-wave-plan` · Tested commit: `80f3edf`

Non-visual change (shell scripts / CLI dispatch) — screenshots are intentionally omitted.
Command output and this acceptance-criteria audit are the evidence.

## Review-blocker regression checks

| Blocker from Review v2 | Observable verification | Result |
|---|---|---|
| Platform-specific Ready resolution was not explicit | The canonical task and design now state that GitHub resolves Project Status/Ready via `platform_board_ensure`, while GitLab resolves `status::ready` via `platform_label_ensure`; both feed the logical `platform_card_status_set --add` operation | ✅ Pass |
| Real enqueue behavior was not covered | `test-tasks-wave-dispatch-platform-rewire.sh` runs the real `tasks-to-issues.sh` caller with a fake platform and observes issue creation, Project validation, Ready-option resolution, item add, and item edit | ✅ Pass |
| Standalone dispatch could silently select GitHub | The same contract suite creates a sole GitLab config without an active pointer and observes `platform_issue_view` from that adapter | ✅ Pass |

The open `[review]` thread is intentionally left for the Reviewer lifecycle's mandatory narrow
re-verification and resolution at current branch HEAD.

## Per-AC verification

| AC | Verification | Result |
|---|---|---|
| AC1 — platform-neutral Ready enqueue through the adapter's platform-specific metadata resolver and `platform_card_status_set --add` | Diff inspection plus the real enqueue smoke described above | ✅ Pass |
| AC2 — wave plan uses `platform_board_snapshot` and preserves dependency parsing | Contract suite checks the call site, runs the `--items` planning path, and verifies live snapshot failures remain failures | ✅ Pass |
| AC3 — dispatch uses `platform_issue_view` | Contract inspection plus sole-GitLab-config dispatch smoke | ✅ Pass |
| AC4 — all 9 prepare scenarios remain green | Fresh `bash tests/test-supersaiyan-prepare.sh` run | ✅ Pass — 9 scenarios |

## Fresh local verification

```text
bash tests/test-tasks-wave-dispatch-platform-rewire.sh
bash tests/test-prepare-platform-rewire.sh
bash tests/test-supersaiyan-prepare.sh
bash tests/test-platform-contract.sh
bash tests/test-backend-contract.sh
bash tests/test-build-safety-contract.sh
bash tests/test-run-platform-rewire.sh
bash -n <all changed shell files>
git diff --check origin/main...HEAD
```

All commands exited 0. See `test-output.log` for the concise result transcript.

## Verdict

Pass. All four acceptance criteria and all three Review-v2 regression checks are covered by fresh,
observable local verification at `80f3edf`.
