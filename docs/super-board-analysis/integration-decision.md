# Integration Decision: super-board for SuperSaiyan

**Context:** Learn-first; primary host Claude Code; future compatibility with Codex, Cursor, and other agents.

**Date:** 2026-06-19

## Decision

**Fork the orchestration spec, not the runtime wholesale.** Use super-board as the reference implementation and protocol source; extend via `worker_backend` plugins rather than rewriting the board loop.

## Rationale

| Factor | Assessment |
|--------|------------|
| Learning value | Excellent — six agentic patterns are explicit and mapped to code |
| Production readiness (Claude Code + GitHub) | Strong — battle-tested safety controls in v1.2–v1.7 |
| Multi-platform fit | Moderate — core protocol ports; dispatch layer is Claude Code–specific |
| Maintenance burden | Small upstream (MIT, ~11 commits) — you own forks/extensions |
| Your stated goals | Aligns with "learn now, integrate later if it works" |

## Three paths ranked

### 1. Recommended now: Study + protocol reuse (SuperSaiyan)

- Keep cloned `super-board/` as upstream reference
- Installed `.claude/` sandbox in this repo for hands-on Claude Code trials
- Copy portable pieces into your own agentic system:
  - Board-as-state
  - `run.md` lane lifecycles
  - `super-board-wave-plan.sh` selection logic
  - `STAGE_SCHEMA` exit contract (`advanced` / `bounced` / `blocked` / `human-gate`)
  - Safety patterns (mutex, rebuild cap, rate limits)

### 2. Use as-is when you have a real product repo

Choose this when:

- Target repo has GitHub Project v2 with standard columns
- You run **Claude Code** with dynamic workflows enabled
- Issues have clear acceptance criteria
- You want GitHub → merged PRs as the delivery loop

Install: `./super-board/install.sh /path/to/your-app` + superpowers plugin + gstack setup.

### 3. Multi-host extension (Claude + Cursor + Codex)

Add backends alongside existing ones:

```text
worker_backend: "workflow"     → Claude Code dynamic workflow (default)
worker_backend: "claude-p"    → headless claude -p (legacy)
worker_backend: "cursor-sdk"  → Agent.prompt() per lane, same STAGE_SCHEMA
worker_backend: "codex"        → Codex plugin / CLI adapter (future)
```

**Do not rewrite** `run.md` handoff protocol — it is the valuable contract.

## Cursor-specific mapping

Each lane ≈ one Cursor SDK call:

```typescript
const result = await Agent.prompt(lanePrompt, {
  local: { cwd: worktreePath },
  model: { id: "composer-2.5" },
});
// Parse structured output matching STAGE_SCHEMA
```

Orchestrator can be a Node script or Cursor agent that calls `super-board-wave-plan.sh` and dispatches lanes.

## Codex-specific mapping

superpowers and gstack both support Codex via official plugin marketplaces. super-board lane skills would need path rewrites (`.claude/` → Codex skill roots) but the GitHub board protocol stays identical.

## What not to do

- Do not vendor superpowers/gstack inside super-board (upstream doesn't; neither should you)
- Do not let the orchestrator session write product code (violates cardinal rule)
- Do not skip acceptance criteria on issues (system is designed to reject vague cards)

## Next concrete step

When you pick a real app repo:

1. `./super-board/install.sh <repo>`
2. `/super-board onboard` in Claude Code
3. One scoped issue, `human_approves_merge: true` for first smoke test
4. Evaluate bounce/rebuild behavior before enabling auto-merge
