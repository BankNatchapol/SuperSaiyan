# QA report — issue #4 (v9)

PR: #23 · Branch: `issue-4-rewire-tasks-to-issues-and-wave-plan` · Tested product commit:
`c2f7412256cd3fc24575a302c9592b75dd4ec146`

Non-visual shell/CLI change. Command output and the acceptance-criteria audit below are the
evidence; screenshots are intentionally omitted.

## Review-fix matrix

| Risk | Observable verification | Result |
|---|---|---|
| CLOSED mapped issues can be re-enqueued | The real-helper prepare fixture covers CLOSED issues both in Backlog and absent from the board and verifies neither is moved to Ready | ✅ Pass |
| Shared Projects can confuse same-number issues | The board fixture includes a Ready issue with the same number from another repository and verifies the target repository's Backlog issue is independently moved to Ready by canonical URL | ✅ Pass |

## Acceptance criteria

| AC | Verification | Result |
|---|---|---|
| AC1 — Adapter-specific Ready enqueue | Explicit board fixtures validate adapter metadata and execute `platform_card_status_set --add`; retry and reconciliation paths are behaviorally covered | ✅ Pass |
| AC2 — Platform board snapshot | GitHub, GitLab-context, dependency-ordering, live-fetch, and mapped-issue reconciliation paths use `platform_board_snapshot` | ✅ Pass |
| AC3 — Normalized issue view | Dispatch, task filing, and prepare consume normalized `{number,title,body,labels:string[],state}` data with `PLATFORM_CONFIG_PATH` context | ✅ Pass |
| AC4 — Prepare regression coverage | A fresh `tests/test-supersaiyan-prepare.sh` run passes all nine scenarios | ✅ Pass |
| AC5 — Explicit board intent | Direct filing remains issue-only by default; only `--board` performs board authentication and enqueue, and prepare supplies the flag | ✅ Pass |
| AC6 — Strict shared config resolution | Task filing, dispatch, and prepare share the Bash 3.2-compatible resolver and its precedence/conflict/fail-fast matrix passes | ✅ Pass |
| AC7 — Auth and lookup safety | Live issue/board auth, target-host scope selection, repository access, lookup-exit handling, map preservation, CLOSED-state preservation, and canonical issue identity pass | ✅ Pass |

## Fresh verification

```text
bash tests/test-tasks-wave-dispatch-platform-rewire.sh
bash tests/test-prepare-platform-rewire.sh
bash tests/test-supersaiyan-prepare.sh
bash tests/test-platform-contract.sh
bash tests/test-backend-contract.sh
bash tests/test-build-safety-contract.sh
bash tests/test-run-platform-rewire.sh
bash -n <all 11 changed shell files in origin/main...c2f7412>
python3 tests/test-reference-sync.py
source scripts/platforms/github.sh && platform_auth_check issue && platform_auth_check board
git diff --check origin/main...HEAD
gh pr checks 23
```

All commands exited 0. The seven-suite run includes the complete issue-specific negative and
configuration matrix. All four current PR checks pass. See `test-output.log` for the concise
transcript.

## Thread inventory

PR #23 has zero unresolved `[QA]` threads and two unresolved `[builder]` threads. QA did not
resolve Builder-owned threads; Reviewer Gate 1 must enforce the lane ownership protocol.

## Verdict

Pass. All seven acceptance criteria and both Review-v8 regressions are verified at product
commit `c2f7412`. Product behavior is ready for the Review lane; the two Builder-owned thread
records remain visible for Reviewer Gate 1.
