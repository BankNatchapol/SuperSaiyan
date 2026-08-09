# QA report — issue #4 (v7)

PR: #23 · Branch: `issue-4-rewire-tasks-to-issues-and-wave-plan` · Tested product commit:
`ed1099a73fcbbc5f1956aafc57e9d755de5d1485`

Non-visual shell/CLI change. Command output and the acceptance-criteria audit below are the
evidence; screenshots are intentionally omitted.

## Contract-reset matrix

| Behavior | Observable verification | Result |
|---|---|---|
| Onboarded GitHub filing defaults to issue-only | Real `tasks-to-issues.sh` fixture selects the onboarded config, requests `issue` auth, creates the issue, and records zero Project mutations | ✅ Pass |
| Explicit `--board` preserves pipeline enqueue | Real caller validates Project/Ready metadata and performs item add/edit; prepare fixture asserts `--board --config <resolved-config>` | ✅ Pass |
| Onboarded GitLab issue-only filing stays forge-correct | Sole GitLab config selects the GitLab adapter, creates the issue, and performs no Ready-label mutation | ✅ Pass |
| Config selection and forge conflicts fail safely | Explicit/env/active/sole precedence, stale active pointer, ambiguity, missing explicit config, unsupported platform, and both task/dispatch `GIT_PLATFORM` conflicts are covered before adapter use | ✅ Pass |
| Auth modes enforce capabilities | `issue` accepts `repo` with repository access and rejects missing scope/access; `board` accepts `repo,project` without separate `read:project` and rejects missing Project scope | ✅ Pass |
| Issue lookup errors are normalized | Found=`0`, confirmed 404=`44`, 401/403=`69`, network/malformed=`70` | ✅ Pass |
| Issue-map repair is safe | 404 mappings are repaired; 401, 403, network, and malformed responses abort with the mapping unchanged | ✅ Pass |
| Installed app layout includes the resolver | Installer smoke copies `.claude/bin/platform-config.sh`; bootstrap verification requires it | ✅ Pass |

## Acceptance criteria

| AC | Verification | Result |
|---|---|---|
| AC1 — Adapter-specific Ready enqueue | Explicit board fixture resolves GitHub Project/Ready metadata and executes `platform_card_status_set --add`; adapter contract remains platform-neutral | ✅ Pass |
| AC2 — Platform board snapshot | Wave-plan GitHub and GitLab-context fixtures use `platform_board_snapshot`; `Depends on: #N` parsing remains present and working | ✅ Pass |
| AC3 — Normalized issue view | Dispatch uses normalized `{number,title,body,labels,state}` data with exported `PLATFORM_CONFIG_PATH`; lookup error exits are also normalized | ✅ Pass |
| AC4 — Prepare regression coverage | Fresh `tests/test-supersaiyan-prepare.sh` run passes all nine scenarios | ✅ Pass |
| AC5 — Explicit board intent | Onboarded direct filing is issue-only by default; only `--board` enables board authentication/enqueue; prepare passes the flag | ✅ Pass |
| AC6 — Strict shared config resolution | All three callers source the Bash 3.2-compatible resolver; the complete precedence/error matrix and installer smoke pass | ✅ Pass |
| AC7 — Auth and lookup safety | Live `issue`/`board` auth passes; negative scope/access cases and 404-vs-error map handling pass | ✅ Pass |

## Fresh verification

```text
bash tests/test-tasks-wave-dispatch-platform-rewire.sh
bash tests/test-prepare-platform-rewire.sh
bash tests/test-supersaiyan-prepare.sh
bash tests/test-platform-contract.sh
bash tests/test-backend-contract.sh
bash tests/test-build-safety-contract.sh
bash tests/test-run-platform-rewire.sh
bash -n <all 11 changed shell files in origin/main...ed1099a>
python3 tests/test-reference-sync.py
source scripts/platforms/github.sh && platform_auth_check issue && platform_auth_check board
git diff --check origin/main...ed1099a
gh api graphql <unresolved review-thread query>
gh pr checks 23 --watch
```

All commands exited 0. GitHub reports four passing checks and zero unresolved review threads.
See `test-output.log` for the concise transcript.

## Verdict

Pass. The seven-AC contract is implemented and verified at product commit `ed1099a`. Issue #4,
its task file, the design contract, PR #23, and this QA report are intended to carry the same
AC1–AC7 wording before the card returns to Review.
