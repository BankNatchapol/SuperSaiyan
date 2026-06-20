# Wave Planner Test Results

Ran `super-board/tests/test-wave-plan.sh` locally (no `gh` calls — uses JSON fixtures).

## Command

```bash
cd super-board && bash tests/test-wave-plan.sh
```

## Result

```
PASS: test-wave-plan.sh (8 scenarios)
```

## What each scenario proves

| # | Scenario | Expected behavior |
|---|----------|-------------------|
| 1 | Mixed board | 3 cards: Review #10, QA #13, Ready #12 (downstream-first; skips assigned #11) |
| 2 | `qa-only` variant | Review + Ready + Ready (no Builder lane; Ready goes to Tester) |
| 3 | `max_workers: 1` | Only Review #10 (cap enforced) |
| 4 | `max_workers: 5` | 4 cards: base 3 + backlog fill Ready #14 |
| 5 | Review-heavy board | Default: only **1** Review card (merge-race guard) |
| 6 | `human_approves_merge: true` | Allows **2+** Review cards (human merges, no race) |
| 7 | Invalid variant `fulll` | Exit code **65** (loud failure, not silent qa-only) |
| 8 | Empty board | `cards: []` (done condition for orchestrator loop) |

## Takeaway for thesis

Wave planning is **deterministic shell + jq**, separate from LLM workers. This is the right seam for a multi-host system: keep `super-board-wave-plan.sh` as host-agnostic; swap only the dispatcher that runs lane agents.

## Fixtures location

- `super-board/tests/fixtures/wave-config.json`
- `super-board/tests/fixtures/wave-items.json`
- `super-board/tests/fixtures/wave-items-review-heavy.json`
