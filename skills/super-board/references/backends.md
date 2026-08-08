# Worker backends — contract + per-tool reference

`config.worker_backend` selects which CLI actually runs lane workers. Four values exist,
split into two families:

| Family | Values | Dispatched by |
|---|---|---|
| Claude-Code-native | `workflow` (default) | Claude Code's own `/workflows` primitive — see `references/run-workflow.md`. Session-bound; no equivalent exists in Codex or Cursor, so this family stays Claude-Code-only. |
| Bash dispatcher | `claude-p`, `codex-exec`, `cursor-agent` | `.claude/bin/super-board-run.sh` (or, for the standalone loops, `super-build-dispatch.sh` / `super-qa-dispatch.sh`), via `scripts/backends/<worker_backend>.sh` |

All three bash-dispatcher backends are explicit opt-in; the dispatcher refuses to run
(exit 78) unless `worker_backend` is set to one of them.

## The Backend contract

Every `scripts/backends/<name>.sh` file must define five shell functions. Dispatch scripts
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

### `codex-exec`

- Launch: `codex exec --sandbox danger-full-access "<prompt>"`. Use `danger-full-access`, not
  `workspace-write` — `workspace-write` is documented to sometimes silently ignore
  `network_access=true` on macOS ([openai/codex#10390](https://github.com/openai/codex/issues/10390)),
  which breaks `git push`/`gh`.
- Auth check: `codex login status` (remediation: `codex login`).
- Orphan pattern: `codex exec .*for SuperSaiyan` — `codex exec` puts the prompt in argv, so
  the marker embedded by `backend_worker_addendum` is directly visible to `pgrep -f`.
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

1. Create `scripts/backends/<name>.sh` implementing all five functions above.
2. Add `<name>` to the allowed-values check in `scripts/super-board-run.sh` (and
   `super-build-dispatch.sh` / `super-qa-dispatch.sh` if it should be available there too).
3. Add a row to the table in `config-schema.json`'s `worker_backend` comment and to this file.
4. Verify the orphan-guard pattern against a real (harmless, non-destructive, briefly-lived)
   spawn of the actual CLI before trusting it — flag adjacency assumptions are easy to get
   wrong and silent to ship, per the Cursor case above.
