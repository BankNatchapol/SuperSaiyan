#!/usr/bin/env bash
# scripts/backends/codex-exec.sh — Backend contract implementation for worker_backend
# "codex-exec". Sourced (not executed) by scripts/super-board-run.sh,
# skills/super-build/scripts/super-build-dispatch.sh, and
# skills/super-qa/scripts/super-qa-dispatch.sh. See references/backends.md for the contract.
#
# Flags verified against the installed `codex` CLI's --help output (codex exec --help):
#   -s/--sandbox <read-only|workspace-write|danger-full-access>
#   danger-full-access is required, not workspace-write — workspace-write is documented to
#   sometimes silently ignore network_access=true on macOS (openai/codex#10390), which breaks
#   git push / gh. codex exec accepts the prompt as a positional arg.

# Model + reasoning depth. Read here with inline `${VAR:-}` defaulting rather than assuming
# the caller exported them — super-build-dispatch.sh / super-qa-dispatch.sh source this file
# under `set -u` and never set these. Both come from the board config (`codex.model`,
# `codex.reasoning_effort`) via super-board-run.sh, or straight from the env for one-off runs.
# Unset/empty = use the codex CLI's own configured default.
codex_flags() {
  # Emitted one per line so callers can read them into an array.
  printf '%s\n' "exec" "--sandbox" "danger-full-access"
  [ -n "${CODEX_MODEL:-}" ] && printf '%s\n' "--model" "$CODEX_MODEL"
  [ -n "${CODEX_REASONING_EFFORT:-}" ] && printf '%s\n' "-c" "model_reasoning_effort=\"${CODEX_REASONING_EFFORT}\""
  return 0
}

backend_launch() {
  # $1 = full prompt text. Backgrounds the worker, echoes its PID.
  local flags=()
  while IFS= read -r flag; do flags+=("$flag"); done < <(codex_flags)
  nohup codex "${flags[@]}" "$1" >/dev/null 2>&1 &
  echo $!
}

backend_run_sync() {
  # $1 = full prompt text. Runs in the foreground; caller captures the exit code.
  local flags=()
  while IFS= read -r flag; do flags+=("$flag"); done < <(codex_flags)
  codex "${flags[@]}" "$1"
}

backend_orphan_pattern() {
  # Matched against the stable marker embedded by backend_worker_addendum, not against flag
  # adjacency — codex exec always includes the prompt text in its argv.
  echo 'codex exec .*for SuperSaiyan'
}

backend_auth_check() {
  codex login status >/dev/null 2>&1 || {
    echo "codex CLI is not logged in — run: codex login" >&2
    return 1
  }
  return 0
}

backend_skills_dir() {
  echo '.claude/skills'
}

backend_worker_addendum() {
  cat <<'EOF'
NOTE: you are running as `codex exec`, NOT inside a Claude Code session. You do not have a
Skill tool or a Task tool — do not attempt to invoke either. Where any referenced skill
document describes spawning a nested `claude -p` / `codex exec` / `agent -p` sub-worker,
ignore that instruction; those docs assume a Claude Code parent process. Instead, read the
referenced skill files directly (they are plain files under `.claude/skills/` relative to
the repo root) and follow their instructions inline in this session.

for SuperSaiyan codex-exec dispatch
---
EOF
}
