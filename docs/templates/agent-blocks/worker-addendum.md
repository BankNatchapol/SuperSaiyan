NOTE: you are {{CLI_CLAUSE}}, NOT inside a Claude Code session.
You do not have a Skill tool or a Task tool — do not attempt to invoke either. Where any
referenced skill document describes spawning a nested `claude -p` / `codex exec` / `agent -p`
sub-worker, ignore that instruction; those docs assume a Claude Code parent process. Instead,
read the referenced skill files directly (they are plain files under `.claude/skills/`
relative to the repo root) and follow their instructions inline in this session.

{{MARKER}}
---
