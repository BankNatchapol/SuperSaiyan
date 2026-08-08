# QA report — Issue #3 / PR #20 (v2)

**Rewire super-board-run.sh to the Platform interface**

Non-visual, script-rewire issue — no UI, no screenshots. Evidence is
command output / greps, one file per AC.

## Why v2

PR #18 (v1) passed QA and Review and was merged, but was later reverted
(`0c6d139`) because it bundled the `git_platform` rewire together with an
unrelated `worker_backend` multi-backend dispatcher change, out of scope for
this issue. That backend work has since landed separately (issue #2,
closed). PR #20 (`f3baef9`) redoes *only* the platform-interface rewire on
top of the current tree, which already contains the backend contract. This
report re-verifies all 4 ACs against that correctly-scoped diff.

| AC | Result | Evidence |
|----|--------|----------|
| `GIT_PLATFORM` from config + BASH_SOURCE-relative `platforms/${GIT_PLATFORM}.sh` source, mirroring `WORKER_BACKEND` sourcing | ✅ PASS | `ac1-platform-source.txt` |
| Inline `gh project item-list` / `gh api rate_limit` / claim-release replaced with `platform_*` | ✅ PASS | `ac2-call-sites.txt` — all 4 `platform_*` functions present; raw call-site count 0 |
| Production-merge guard uses `platform_detect_production_ci` instead of `.github/workflows` grep | ✅ PASS | `ac3-production-guard.txt` — `.github/workflows` count 0 |
| Smoke exits cleanly with identical log shape to before this change | ✅ PASS | `ac4-smoke-and-tests.txt` — `test-run-platform-rewire.sh` PASS (asserts exit 74 at wave-lock gate + shape-identical-to-`origin/main` check baked into the test itself); `test-platform-contract.sh` PASS (31/31 contract functions defined) |

## Scope check (this PR only)

`git diff origin/main f3baef9 --stat` — touches only `scripts/super-board-run.sh`
(40 lines) and adds `tests/test-run-platform-rewire.sh` (129 lines, new). No
`worker_backend`/`backends/` files touched by this PR — that axis was already
in the base branch from issue #2. Confirms the v1 scope-bundling problem does
not recur here.

## Local tests

```
bash tests/test-run-platform-rewire.sh
bash tests/test-platform-contract.sh
bash -n scripts/super-board-run.sh
```

## Verdict

**PASS** — all 4 acceptance criteria hold, and the scope regression that
caused the v1 revert is not present in this diff. Move card QA → Review.
