# QA report — issue #4 (v1)

PR: #23 · Branch: `issue-4-rewire-tasks-to-issues-and-wave-plan` · Builder commit: `2523ace`

Non-visual change (shell scripts / CLI dispatch) — no UI, no screenshots. Evidence is test
output only, captured at `test-output.log` in this directory.

## Per-AC verification

| AC | Requirement | Verified by | Result |
|----|-------------|-------------|--------|
| AC1 | `tasks-to-issues.sh`'s `gh project view`/`field-list`/`item-add`/`item-edit --single-select-option-id` sequence replaced with a platform call + `platform_card_status_set`'s add-only case | Diff review (`scripts/tasks-to-issues.sh` L54-66, L196-212, L279-282) + `test-tasks-wave-dispatch-platform-rewire.sh` §3 (asserts no inline `gh project view/field-list/item-add/item-edit` remain) | ✅ Pass — see note below |
| AC2 | `super-board-wave-plan.sh`'s `gh project item-list` replaced with `platform_board_snapshot`; `Depends on: #N` jq parsing unchanged | Diff review (`scripts/super-board-wave-plan.sh` L34-47) + `test-tasks-wave-dispatch-platform-rewire.sh` §4 (no inline `gh project item-list`, `Depends on` string still present) + §6 smoke test (plans 1 card from `--items` fixture through the real function) | ✅ Pass |
| AC3 | `super-build-dispatch.sh`'s `gh issue view` replaced with `platform_issue_view` | Diff review (`skills/super-build/scripts/super-build-dispatch.sh` L53-79, L130-134) + `test-tasks-wave-dispatch-platform-rewire.sh` §5 | ✅ Pass |
| AC4 | `./tests/test-supersaiyan-prepare.sh` (all 9 scenarios) still passes | Ran directly | ✅ Pass — `PASS: test-supersaiyan-prepare.sh (9 scenarios)` |

### Note on AC1 naming
The task text names `platform_label_ensure` (the GitLab `status::ready`-label path from
`docs/superpowers/specs/gitlab-integration-design.md`). The task helper now stays platform-neutral:
it calls the logical `platform_card_status_set --add` operation, and the selected adapter owns
board metadata validation (`platform_board_ensure` for GitHub). This keeps the adapter-specific
Project IDs out of `tasks-to-issues.sh` while retaining the same Ready-enqueue gate.

## Regression / signature-compatibility check
- `platform_card_status_set`'s new logical `--add` branch is additive (`if [ "${1:-}" = "--add" ]`);
  both the existing four-ID form and the older six-argument add-only form remain source-compatible.
  The new logical form owns board metadata resolution inside the adapter.
- `prepare.sh` now uses the same logical adapter path for stale-mapping repair, board snapshots,
  and Ready reconciliation, so GitHub Project IDs do not leak into the caller.
- `platform_board_snapshot` preserves the old fail-loud behavior for API/auth failures; an
  unavailable board can no longer look like an empty wave.

## Test suite run (full output in `test-output.log`)

| Suite | Result |
|---|---|
| `tests/test-tasks-wave-dispatch-platform-rewire.sh` (issue-#4-specific contract test) | ✅ PASS |
| `tests/test-prepare-platform-rewire.sh` (platform caller contract) | ✅ PASS |
| `tests/test-supersaiyan-prepare.sh` (AC4, 9 scenarios) | ✅ PASS |
| `tests/test-platform-contract.sh` (31 contract functions defined) | ✅ PASS |
| `tests/test-backend-contract.sh` | ✅ PASS |
| `tests/test-build-safety-contract.sh` | ✅ PASS |
| `tests/test-run-platform-rewire.sh` (issue #3 regression guard) | ✅ PASS |

`shellcheck` is not installed in this environment; `bash -n` syntax checks (run inside the new
contract test) passed for all three modified scripts.

## Verdict
**Pass.** All 4 acceptance criteria met, related contract tests pass, and callers use logical
platform operations without swallowing board-fetch failures.
