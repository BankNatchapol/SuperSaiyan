# QA report — issue #4 (v8)

PR: #23 · Branch: `issue-4-rewire-tasks-to-issues-and-wave-plan` · Tested product commit:
`ec4008dbb497ed594c830b988ec9422eaa1c44be`

Non-visual shell/CLI change. Command output and the acceptance-criteria audit below are the
evidence; screenshots are intentionally omitted.

## Review-fix matrix

| Risk | Observable verification | Result |
|---|---|---|
| Failed Ready enqueue leaves a mapped issue outside Ready | The real `tasks-to-issues.sh` fixture forces the first board mutation to fail, verifies the issue map survives, retries without creating a duplicate, reconciles the mapped issue to Ready, and then proves a third run is idempotent | ✅ Pass |
| Authentication can borrow scopes from the wrong GitHub host | A multi-host fixture makes `github.com` active but insufficient and `ghe.example.com` the repository host; issue auth accepts the target host's `repo` scope and rejects a `repo` scope present only on the unrelated host | ✅ Pass |
| Normalized issue labels can leak GitHub label objects | The GitHub issue-view fixture returns label objects and asserts the adapter emits `labels:["bug"]` | ✅ Pass |

## Acceptance criteria

| AC | Verification | Result |
|---|---|---|
| AC1 — Adapter-specific Ready enqueue | Explicit board fixtures validate adapter metadata and execute `platform_card_status_set --add`; the failed-enqueue retry additionally proves recoverable, duplicate-free Ready reconciliation | ✅ Pass |
| AC2 — Platform board snapshot | GitHub, GitLab-context, dependency-ordering, live-fetch, and mapped-issue reconciliation paths use `platform_board_snapshot` | ✅ Pass |
| AC3 — Normalized issue view | Dispatch and prepare consume normalized `{number,title,body,labels:string[],state}` data with exported `PLATFORM_CONFIG_PATH`; object labels are projected to strings | ✅ Pass |
| AC4 — Prepare regression coverage | A fresh `tests/test-supersaiyan-prepare.sh` run passes all nine scenarios | ✅ Pass |
| AC5 — Explicit board intent | Onboarded direct filing remains issue-only by default; only `--board` performs board authentication and enqueue, and prepare supplies the flag | ✅ Pass |
| AC6 — Strict shared config resolution | Task filing, dispatch, and prepare share the Bash 3.2-compatible resolver and the full precedence/conflict/fail-fast matrix passes | ✅ Pass |
| AC7 — Auth and lookup safety | Live issue/board auth passes; target-host scope selection, repository access, 404/69/70 lookup handling, and map-preservation cases pass | ✅ Pass |

## Fresh verification

```text
bash tests/test-tasks-wave-dispatch-platform-rewire.sh
bash tests/test-prepare-platform-rewire.sh
bash tests/test-supersaiyan-prepare.sh
bash tests/test-platform-contract.sh
bash tests/test-backend-contract.sh
bash tests/test-build-safety-contract.sh
bash tests/test-run-platform-rewire.sh
bash -n <all 11 changed shell files in origin/main...ec4008d>
python3 tests/test-reference-sync.py
source scripts/platforms/github.sh && platform_auth_check issue && platform_auth_check board
git diff --check origin/main...ec4008d
```

All commands exited 0. The seven-suite run includes the complete issue-specific negative and
configuration matrix. See `test-output.log` for the concise transcript.

## Verdict

Pass. All seven acceptance criteria and the three Review-v7 edge cases are verified at product
commit `ec4008d`. The branch is ready for an independent Review lane after this QA handoff.
