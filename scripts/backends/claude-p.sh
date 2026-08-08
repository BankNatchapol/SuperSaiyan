#!/usr/bin/env bash
# scripts/backends/claude-p.sh — Backend contract implementation for worker_backend "claude-p".
# Sourced (not executed) by scripts/super-board-run.sh,
# skills/super-build/scripts/super-build-dispatch.sh, and
# skills/super-qa/scripts/super-qa-dispatch.sh. See references/backends.md for the contract.
#
# claude -p already runs inside a real Claude Code session context, so it natively resolves
# plugin skills and can use the Skill/Task tool — no worker addendum needed.

backend_launch() {
  # $1 = full prompt text. Backgrounds the worker, echoes its PID.
  nohup claude -p --dangerously-skip-permissions --max-turns "${MAX_TURNS:-250}" "$1" >/dev/null 2>&1 &
  echo $!
}

backend_run_sync() {
  # $1 = full prompt text. Runs in the foreground; caller captures the exit code.
  # Used by single-shot dispatchers (super-build-dispatch.sh, super-qa-dispatch.sh) that are
  # themselves already backgrounded by their orchestrator via Bash run_in_background — unlike
  # backend_launch, there's no PID to track here, just the CLI's own exit status.
  claude -p --dangerously-skip-permissions --max-turns "${MAX_TURNS:-250}" "$1"
}

backend_orphan_pattern() {
  echo 'claude -p .*super-board run'
}

backend_auth_check() {
  command -v claude >/dev/null 2>&1 || {
    echo "claude CLI not found on PATH — install Claude Code: https://claude.ai/code" >&2
    return 1
  }
  return 0
}

backend_skills_dir() {
  echo '.claude/skills'
}

backend_worker_addendum() {
  # Empty: claude -p is a real Claude Code session — plugin skills, Skill tool, and
  # Task tool all work natively. Nothing extra needs to be told to the worker.
  echo ''
}
