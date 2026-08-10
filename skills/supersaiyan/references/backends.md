<!-- GENERATED FILE — edit skills/super-board/references/backends.md, then run scripts/generate-supersaiyan-references.sh to regenerate. Do not hand-edit. -->

# Worker backends — contract + per-tool reference

`config.worker_backend` selects which CLI actually runs lane workers. Four values exist,
split into two families:

| Family | Values | Dispatched by |
|---|---|---|
| Claude-Code-native | `workflow` (default) | Claude Code's own `/workflows` primitive — see `references/run-workflow.md`. Session-bound; no equivalent exists in Codex or Cursor, so this family stays Claude-Code-only. |
| Bash dispatcher | `claude-p`, `codex-exec`, `cursor-agent` | `.supersaiyan/bin/super-board-run.sh` (or, for the standalone loops, `super-build-dispatch.sh` / `super-qa-dispatch.sh`), via `scripts/backends/<worker_backend>.sh` |

All three bash-dispatcher backends are explicit opt-in; the dispatcher refuses to run
(exit 78) unless `worker_backend` is set to one of them.

`worker_backend` selects the tool for **headless Build/QA/Review dispatch only**. It has no
effect on the planning phase (`office-hours` → `refining-spec` → `writing-board-tasks`), which
always runs interactively in whatever session you invoke it from — see
[docs/GETTING-STARTED.md](../../../docs/GETTING-STARTED.md) for driving that phase from Codex
or Cursor.

## Per-lane `worker_backend`

`worker_backend` is either a single string (one backend for every lane) or an object mapping
lane → backend name, letting one board run a different CLI per lane in a single dispatcher
process:

```json
"worker_backend": {
  "build":  "codex-exec",
  "qa":     "cursor-agent",
  "review": "claude-p"
}
```

- Any lane key you omit defaults to `claude-p`.
- `"workflow"` is **never** valid as a per-lane value — it is Claude-Code-session-bound, not a
  bash-dispatcher backend. The dispatcher exits 78 and names the offending lane.
- Only lanes the `variant` actually dispatches are validated: a `qa-only` board never runs a
  Builder, so a missing (or unusable) `build` key there is ignored, not fatal.
- This is still ONE dispatcher process. For genuinely independent parallel boards — one tool
  owning a whole pipeline each — use the N-separate-configs path in `references/onboard.md`
  step 2 instead. Never run two dispatchers against the same board.

**Contract implication — the backend functions are not namespaced.** Sourcing a backend file
overwrites every `backend_*` function in the current shell, so only the most recently sourced
file's functions are live. Any caller supporting per-lane backends must therefore re-source the
lane's backend immediately before calling any `backend_*` function, in the same synchronous
flow — never source one "for later." In `scripts/super-board-run.sh` this is the `load_backend`
helper, the single sourcing point in that script; `dispatch_lane` calls it after resolving the
lane's backend and before `backend_worker_addendum`/`backend_launch`. Startup checks that must
cover every backend in use (auth check, orphan guard) iterate the deduplicated set of backends
for the lanes this variant dispatches, re-sourcing once per backend.

## The Backend contract

Every `scripts/backends/<name>.sh` file must define six shell functions. Dispatch scripts
`source` the file for the active `worker_backend` — never invoke the CLI directly.

| Function | Contract |
|---|---|
| `backend_launch "<prompt>"` | Backgrounds the worker process with the right non-interactive flags, echoes its PID to stdout. Used by headless loops (`super-board-run.sh`) that must track a PID across ticks. |
| `backend_run_sync "<prompt>"` | Runs the worker process in the foreground with the same non-interactive flags as `backend_launch`; the caller captures its exit code directly (`$?`). Used by single-shot dispatchers (`super-build-dispatch.sh`, `super-qa-dispatch.sh`) that are already backgrounded by their orchestrator via `Bash run_in_background` — there's no PID to track independently, just the CLI's own exit status. |
| `backend_orphan_pattern` | Echoes a `pgrep -f` regex that matches a genuinely live worker process for this backend. Match on a stable marker string embedded in the prompt (see `backend_worker_addendum`), not on flag adjacency — see the Cursor note below for why that matters. Only meaningful for `backend_launch` consumers; single-shot dispatchers have no orphan-scan use for it. |
| `backend_auth_check` | Returns 0 if the CLI is authenticated and ready to dispatch, 1 otherwise. Prints the exact remediation command on failure. |
| `backend_skills_dir` | Echoes the relative path a worker should read skill files from. |
| `backend_worker_addendum` | Echoes an extra block prepended to every worker prompt. Empty for `claude-p` (a real Claude Code session — Skill/Task tool and plugin skills work natively). Non-empty for `codex-exec`/`cursor-agent`: tells the worker it is not a Claude Code session, has no Skill/Task tool, and must not spawn a nested `claude -p`/`codex exec`/`agent -p` sub-worker where a skill doc describes doing so — read the referenced files directly instead. Also embeds the orphan-guard marker string. |

## Skills path — one convention for all three backends

`backend_skills_dir` returns `.claude/skills` for every backend. That only works because
`install.sh` guarantees `.claude/skills/` exists as real files in the target repo whenever a
non-`workflow` backend is configured — even when the Claude Code plugin is also installed
(which would normally make `install.sh` skip/delete the local copy, since Claude Code
resolves plugin skills from its own cache instead). Codex and Cursor have no such cache; they
can only read files that physically exist in the repo they're running against. This is
simpler than symlinking skills into `~/.codex/skills` / `~/.cursor/skills` with
`CODEX_SKILLS_DIR`/`CURSOR_SKILLS_DIR` env vars threaded through every prompt — every backend
just reads the same repo-relative path `claude -p` workers already use.

## Per-backend reference (verified against installed CLIs)

### `claude-p`

- Launch: `claude -p "<prompt>"`.
- Auth check: `command -v claude`.
- Orphan pattern: `claude -p .*super-board run` (the marker is already baked into every
  `dispatch_lane` prompt — no addendum needed).
- Model: none by design — `claude -p` inherits the session model, the same convention the
  workflow backend's Reviewer lane follows. There is no `claude.model` config field.

### `codex-exec`

- Launch: `codex exec --sandbox danger-full-access "<prompt>"`. Use `danger-full-access`, not
  `workspace-write` — `workspace-write` is documented to sometimes silently ignore
  `network_access=true` on macOS ([openai/codex#10390](https://github.com/openai/codex/issues/10390)),
  which breaks `git push`/`gh`.
- Auth check: `codex login status` (remediation: `codex login`).
- Orphan pattern: `codex exec .*for SuperSaiyan` — `codex exec` puts the prompt in argv, so
  the marker embedded by `backend_worker_addendum` is directly visible to `pgrep -f`.
- Model: `codex.model` and `codex.reasoning_effort` in the board config, or the `CODEX_MODEL`
  / `CODEX_REASONING_EFFORT` env vars (env wins, for one-off runs). Appended as
  `--model <name>` and `-c model_reasoning_effort="<value>"`. Both are optional — unset means
  the codex CLI's own configured default, and no empty flag is emitted. `reasoning_effort` is
  passed through as a free-form string: accepted values are model-specific (e.g. `gpt-5.6-sol`
  takes `low|medium|high|xhigh|max|ultra`), so the dispatcher does not validate it.
- Other useful flags (not used by default, documented for reference): `-C/--cd <DIR>` working
  directory, `--json` for JSONL event output, `-o/--output-last-message <FILE>`.

### `cursor-agent`

- Launch: `agent -p --trust --force --sandbox disabled "<prompt>"`.
  - `--trust` is required, not optional: every dispatch runs in a fresh git worktree, and
    `cursor-agent` treats each new directory as untrusted by default, blocking on a y/n
    prompt otherwise — fatal for headless dispatch.
  - `--force` (alias `--yolo`) skips per-command approval prompts.
  - `--sandbox disabled` matches the non-interactive dispatch model.
- Auth check: `agent status` (prints `✓ Logged in as <email>` when authenticated; remediation:
  `agent login`). If `CURSOR_API_KEY` is set, note it's a CI escape hatch, not the primary
  auth path.
- Model: `cursor.model` in the board config, or the `CURSOR_MODEL` env var (env wins).
  Appended as `--model <name>`. The id must match an entry from `agent models` exactly — e.g.
  `cursor-grok-4.5-high`; a shorthand like `grok-4-5` is rejected by the CLI. Unset means the
  Cursor CLI's own default, and no empty flag is emitted.
- **Orphan pattern — do not assume `agent`/`-p` are adjacent.** The real `agent` binary
  re-execs as:
  ```
  agent --use-system-ca <path>/index.js -p --trust --force --sandbox disabled <prompt...>
  ```
  confirmed live by spawning a real (harmless, immediately-killed) process and inspecting its
  argv via `ps`. A pattern like `agent -p .*...` silently matches zero real processes — this
  is the exact bug a downstream project hit in production, where every orphan-guard, `pkill`
  stop command, and dashboard worker-count relying on that assumption quietly never fired.
  Use `agent.*for SuperSaiyan` instead — matched against the stable marker in
  `backend_worker_addendum`, not against flag position.

## Adding a new backend

1. Create `scripts/backends/<name>.sh` implementing all six functions above.
2. Add `<name>` to the allowed-values check in `scripts/super-board-run.sh` (and
   `super-build-dispatch.sh` / `super-qa-dispatch.sh` if it should be available there too).
3. Add a row to the table in `config-schema.json`'s `worker_backend` comment and to this file.
4. Verify the orphan-guard pattern against a real (harmless, non-destructive, briefly-lived)
   spawn of the actual CLI before trusting it — flag adjacency assumptions are easy to get
   wrong and silent to ship, per the Cursor case above.
