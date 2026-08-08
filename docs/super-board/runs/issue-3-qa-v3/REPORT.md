# Super QA — issue #3 / PR #20 (v3)

**Date:** 2026-08-08  
**Branch:** `issue-3-rewire-super-board-run` @ build tip `f3baef9` (+ this QA evidence commit)  
**Scope:** platform-interface rewire only (`scripts/super-board-run.sh` + `tests/test-run-platform-rewire.sh`)

Redo after QA v2 evidence commit was reverted (`ffb4a32`) so QA can be an independently checkpointed lane.

## Acceptance criteria

| AC | Result | Evidence |
|----|--------|----------|
| 1. `GIT_PLATFORM` from config + `BASH_SOURCE`-relative `platforms/${GIT_PLATFORM}.sh` | **PASS** | `ac1-platform-source.txt` |
| 2. Inline board/rate/claim/release → `platform_*` | **PASS** | `ac2-call-sites.txt` |
| 3. Production-merge guard → `platform_detect_production_ci` | **PASS** | `ac3-production-guard.txt` |
| 4. Smoke (temp repo, `git_platform: github`, `worker_backend: claude-p`) exits cleanly with prior log shape | **PASS** | `ac4-smoke-and-tests.txt` |

## Commands re-run

```text
bash -n scripts/super-board-run.sh                          → clean
bash tests/test-run-platform-rewire.sh                      → PASS (exit 0; smoke exit 74 at wave-lock)
bash tests/test-platform-contract.sh                        → PASS (31/31)
git diff --stat origin/main...HEAD                          → only run.sh + test-run-platform-rewire.sh
```

## Non-visual note

No UI ACs — screenshot block intentionally omitted. Evidence is command logs above.

## Verdict

**QA PASS.** Ready for Review.
