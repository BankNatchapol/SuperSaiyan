# supersaiyan prepare — Issue Filing and Board Reconciliation

Files GitHub issues from task files, adds them to the board's Ready column, and runs lint.

Invoked by `supersaiyan new` (Phase 5) and directly via `/supersaiyan prepare <slug>`.

---

## How prepare works

1. **Config discovery** — reads `.claude/supersaiyan/configs/<slug>.json` to find the board.
   - If no config exists, runs inline onboarding (`references/onboard.md`) first.
   - If multiple configs exist, reads `.claude/supersaiyan/active` for the active slug.

2. **Git validation** — verifies task files are committed and pushed. Uncommitted or unpushed
   task changes are caught here before any GitHub writes.

3. **Stale repair** — checks each entry in `.issue-map.json`. If a mapped issue was deleted
   from GitHub, the entry is removed so the issue is recreated.

4. **Issue creation** — runs `.claude/bin/tasks-to-issues.sh` which creates one GitHub issue
   per task file and adds it to the board's Ready column.

5. **Backlog reconciliation** — any generated issue in the board's Backlog column that is still
   open moves to Ready. Active (Building/QA/Review), closed, and manual cards are untouched.

6. **Lint** — follows `references/lint.md` to run pre-flight issue quality checks.

---

## Programmatic entry point

```bash
scripts/prepare.sh <slug> [--phase N] [--check-only]
```

- **`--check-only`** — validates config, git state, and task dependencies without writing
  anything to GitHub. Exits `78` if no board config exists (signal: onboard first).
- **`--phase N`** — operates on `docs/superpowers/projects/<slug>/phase-N/` instead of
  `docs/superpowers/tasks/<slug>/`.

---

## Agent steps when invoked interactively

1. Run `scripts/prepare.sh <slug> --check-only` to surface any validation errors. If exit 78:
   follow `references/onboard.md`, then re-run.

2. Run `scripts/prepare.sh <slug>` to file issues and reconcile board cards. Parse the
   `created=N repaired=N` output and include in the completion message.

3. Follow `references/lint.md` to run the pre-flight quality check.

4. Announce:
   ```
   ✅ <slug> ready for the autonomous loop.
      Issues:  <N> created → Ready queue
      Lint:    complete

   Next: /supersaiyan run
   ```

---

## Phase unlock variant

When invoked as `supersaiyan prepare <slug> --phase N`, follow
`references/project.md` → "Prepare — Phase Unlock" section instead of this file.

---

## GSD fallback (optional)

If the project uses a gsd-discuss-phase workflow (optional — only when explicitly configured),
run the phase-discuss step before filing issues. This is opt-in; most projects skip it.

---

## Error handling

| Exit code | Meaning | Action |
|-----------|---------|--------|
| 0 | Success | Continue |
| 65 | Validation error | Surface the error message; fix before retrying |
| 75 | Multiple configs, no active pointer | `echo <slug> > .claude/supersaiyan/active` then retry |
| 78 | No board config | Run `references/onboard.md` then retry |
