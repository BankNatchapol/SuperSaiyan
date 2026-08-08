# QA report — Issue #3 / PR #18

**Rewire super-board-run.sh to the Platform interface**

Non-visual, script-rewire issue — no UI, no screenshots. Evidence is
command output / greps, one file per AC.

| AC | Result | Evidence |
|----|--------|----------|
| `GIT_PLATFORM` from config + BASH_SOURCE-relative `platforms/${GIT_PLATFORM}.sh` source | ✅ PASS | `ac1-platform-source.txt` |
| Inline `gh project item-list` / `gh api rate_limit` / claim-release replaced with `platform_*` | ✅ PASS | `ac2-call-sites.txt` — all platform_* present; raw sites count 0 |
| Production-merge guard uses `platform_detect_production_ci` | ✅ PASS | `ac3-production-guard.txt` |
| Smoke (temp repo, `git_platform=github`, `worker_backend=claude-p`) exits cleanly with identical log shape | ✅ PASS | `ac4-smoke-and-tests.txt` — exit 74 wave-lock refuse; shape identical to `origin/main`; `test-run-platform-rewire.sh` + `test-platform-contract.sh` PASS |

## Local tests

```
bash tests/test-run-platform-rewire.sh
bash tests/test-platform-contract.sh
```

## Verdict

**PASS** — all 4 acceptance criteria hold. Move card QA → Review.
