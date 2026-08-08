#!/usr/bin/env bash
# scripts/backends/cursor-agent.sh — Backend contract implementation for worker_backend
# "cursor-agent". Sourced (not executed) by scripts/super-board-run.sh,
# skills/super-build/scripts/super-build-dispatch.sh, and
# skills/super-qa/scripts/super-qa-dispatch.sh. See references/backends.md for the contract.
#
# Flags verified against the installed `agent` (Cursor) CLI's --help output, and live-tested
# by spawning a real (harmless, --mode ask, killed within ~1s) process and inspecting its
# actual argv via ps:
#   -p/--print       non-interactive
#   -f/--force       skip command-approval prompts (alias: --yolo)
#   --trust          skip the per-directory workspace-trust prompt — required because every
#                     dispatch runs in a FRESH git worktree, which cursor-agent treats as an
#                     untrusted directory by default and otherwise hangs waiting for a y/n.
#   --sandbox disabled
#
# Orphan-guard pattern: the real `agent` binary re-execs as
#   agent --use-system-ca <path>/index.js -p --trust --force --sandbox disabled <prompt...>
# so `-p` is NEVER adjacent to `agent` on the command line — confirmed live on this machine.
# A pattern assuming that adjacency (e.g. `agent -p .*...`) silently matches zero real
# processes. Match on the stable marker text in the prompt instead.

backend_launch() {
  # $1 = full prompt text. Backgrounds the worker, echoes its PID.
  nohup agent -p --trust --force --sandbox disabled "$1" >/dev/null 2>&1 &
  echo $!
}

backend_run_sync() {
  # $1 = full prompt text. Runs in the foreground; caller captures the exit code.
  agent -p --trust --force --sandbox disabled "$1"
}

backend_orphan_pattern() {
  echo 'agent.*for SuperSaiyan'
}

backend_auth_check() {
  if ! agent status >/dev/null 2>&1; then
    if [ -n "${CURSOR_API_KEY:-}" ]; then
      echo "note: CURSOR_API_KEY is set — this is a CI escape hatch, not the intended auth path. If dispatch still fails, run: agent login" >&2
    else
      echo "cursor-agent CLI is not logged in — run: agent login" >&2
    fi
    return 1
  fi
  return 0
}

backend_skills_dir() {
  echo '.claude/skills'
}

backend_worker_addendum() {
  cat <<'EOF'
NOTE: you are running as Cursor's `agent -p`, NOT inside a Claude Code session. You do not
have a Skill tool or a Task tool — do not attempt to invoke either. Where any referenced
skill document describes spawning a nested `claude -p` / `codex exec` / `agent -p`
sub-worker, ignore that instruction; those docs assume a Claude Code parent process. Instead,
read the referenced skill files directly (they are plain files under `.claude/skills/`
relative to the repo root) and follow their instructions inline in this session.

for SuperSaiyan cursor-agent dispatch
---
EOF
}
