# Shared base config + linked per-tool overlays for multi-tool boards

**Status:** Proposed — not implemented. Future work, tracked here until it's worth a task file.

**Context:** raised while reviewing the per-lane `worker_backend` feature — onboarding a board
across Claude, Codex, and Cursor together today means N fully independent config files.

## Problem

Two patterns exist today for a board that uses more than one coding-agent CLI
(`skills/super-board/references/onboard.md` step 2, `skills/super-board/references/backends.md`):

1. **Per-lane `worker_backend` object** — one config, one dispatcher process, a different
   backend per lane (`{"build": "codex-exec", "qa": "cursor-agent", "review": "claude-p"}`).
   Already shipped. No duplication problem — it's one file.
2. **N independent configs** — one config file per tool (`<slug>-claude.json`,
   `<slug>-codex.json`, `<slug>-cursor.json`), each its own dispatcher process, for genuinely
   parallel/redundant boards rather than lane specialization.

Path 2 is where the actual pain is. Onboarding today writes each tool's config as a fully
independent, fully self-contained JSON file. `description` and `worker_backend` (plus, since
the per-tool model change, `codex.model`/`codex.reasoning_effort`/`cursor.model`) are the only
fields that differ between them — `project`, `variant`, `base_branch`, `columns`, `paths`,
`human_approves_merge`, `truth_gate`, `truth_threshold`, `rebuild_cap`, `block_rate_alert_pct`,
and `notifications` are byte-for-byte duplicated across all N files. Changing a shared setting
(e.g. `rebuild_cap`) means hand-editing every tool's file identically, with no mechanism
catching drift if you miss one.

## Proposed design

Introduce an optional `"extends": "<slug>"` field. A config with `extends` set supplies only
the fields that differ for that tool (`description`, `worker_backend`, and its own model
block); everything else is inherited from the base config at `.claude/supersaiyan/configs/<slug>.json`.

```
.claude/supersaiyan/configs/
  myboard.json          ← base: project, variant, base_branch, columns, paths,
                           human_approves_merge, truth_gate, rebuild_cap, notifications, ...
  myboard-claude.json   ← { "extends": "myboard", "worker_backend": "workflow" }
  myboard-codex.json    ← { "extends": "myboard", "worker_backend": "codex-exec",
                             "codex": { "model": "gpt-5.6-sol", "reasoning_effort": "high" } }
  myboard-cursor.json   ← { "extends": "myboard", "worker_backend": "cursor-agent",
                             "cursor": { "model": "cursor-grok-4.5-high" } }
```

Resolution: merge base + overlay (`jq -s '.[0] * .[1]' myboard.json myboard-codex.json`) into
an effective config **once, upstream of every existing field read**, in whichever script loads
`CONFIG_PATH`. Every consumer's individual `jq -r '.field // default'` line stays unchanged —
they already read from one resolved JSON blob today, and would keep doing so; only the step
that produces that blob gains an `extends` check first. Consumers needing this: `scripts/super-board-run.sh`,
`skills/super-build/scripts/super-build-dispatch.sh`, `skills/super-qa/scripts/super-qa-dispatch.sh`,
`scripts/super-board-status.py`, `packages/control-core/src/index.ts` (`discoverConfigs`).

Onboarding changes (`onboard.md` step 2, path A / "independent boards"): ask the shared
settings once, write the base file once, then for each tool selected write only the thin
overlay. Editing a shared setting later touches one file and applies to every tool's next
dispatcher run — each process re-reads its config fresh at startup already, so no caching
invariant to preserve.

## Explicitly out of scope for this proposal

- The per-lane object path (already shipped) doesn't need this — it's already one file.
- Whether per-lane configs should ever `extends` a shared base too (e.g. a "prod" and
  "staging" per-lane config sharing `rebuild_cap`/`truth_gate`) is plausible but not required
  for a first version.
- `super-board lint`/re-onboard need to learn about linked configs (broken `extends` pointer,
  listing an overlay without its base, reconfiguring a base and needing to re-validate every
  overlay that points at it) — not designed here, flagged as a dependency.
- Back-compat: `extends` is optional. Every config that doesn't set it — including the
  standalone single-string and per-lane-object shapes — keeps working exactly as it does today.
