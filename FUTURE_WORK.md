# Future Work

Items identified during development that are not yet implemented.

---

## Rate limit / session limit handling

When Claude Code hits a usage limit mid-run, the pipeline stops without warning. The board preserves state and the user can resume manually after the limit resets, but there is no automatic detection, waiting, or continuation. The user has to notice the session ended, wait for the reset, and re-invoke `/supersaiyan run` themselves.

Desired behavior: the pipeline detects an approaching or hit usage limit, waits automatically, and resumes without user intervention.

---

## Context window limit handling

When a single worker agent (Builder, QA, or Reviewer) hits the context window limit mid-task, it stops and leaves the card in its current column. The next run retries from scratch, which may hit the same limit again. There is no detection that a card is too large for a single agent context, no mid-card progress checkpointing, and no automatic task-splitting for oversized work.

Desired behavior: the pipeline detects context pressure during a run, preserves intermediate progress, and resumes or splits the work so the card eventually completes.
