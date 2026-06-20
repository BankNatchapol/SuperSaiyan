# supersaiyan new <name>

Full pipeline: brainstorm → spec → tasks → commit → prepare.

`<name>` is a kebab-case slug for anything — a single feature, a new app, a large system. The brainstorm phase detects the context (startup, builder, existing codebase, greenfield) and adjusts automatically. If the work is large enough to warrant phases, the spec phase switches to project mode.

Announce at start: "Starting SuperSaiyan for `<name>`. I'll guide you from design to a queued board in one flow."

---

## Prerequisites (silent check)

```bash
git rev-parse --is-inside-work-tree 2>/dev/null || echo "NOT_GIT"
ls .claude/super-board/configs/*.json 2>/dev/null || echo "NO_CONFIG"
gh auth status --active >/dev/null 2>&1 || echo "NOT_AUTHED"
```

- Not a git repo → offer `git init` inline, then continue.
- No config → run `references/setup.md` inline first, then return here.
- gh not authenticated → `gh auth login` then `gh auth refresh -s project,read:project,repo`.

---

## Phase 1 — Brainstorm

Read and follow `references/brainstorm.md` exactly.

Output: design doc saved to `docs/gstack/designs/<feature-slug>-design.md`.

---

## Phase 2 — Spec

Read and follow `references/spec.md` exactly.

Input: design doc from Phase 1.

Routes internally:
- **Single feature** → writes `docs/superpowers/specs/<slug>-design.md`, continues to Phase 3
- **Multi-phase project** → hands off to `references/project.md` which handles Phases 3–5 internally. **Stop here** — project.md prints its own completion message and next-step guide.

---

## Phase 3 — Tasks (single feature only)

Invoke the `writing-board-tasks` skill.

Input: `docs/superpowers/specs/<feature-slug>-design.md`

Output: task files at `docs/superpowers/tasks/<feature-slug>/NN-task-name.md`

---

## Phase 4 — Commit (single feature only)

```bash
git add docs/superpowers/specs/<feature-slug>-design.md
git add docs/superpowers/tasks/<feature-slug>/
git commit -m "docs: <feature-slug> spec and board tasks"
git push
```

Wait for push to complete before Phase 5. If push fails, surface the error and stop.

---

## Phase 5 — Prepare (single feature only)

Follow `references/prepare.md` exactly.

On success, print:

```
✅ <feature-slug> ready for the autonomous loop.
   Issues:  <N> created → Ready queue
   Lint:    complete

── What's next ──────────────────────────────────────────
Start the autonomous loop:

   /supersaiyan run <config-slug>

The pipeline runs unattended:
  Ready → Building → QA → Review → Done

Watch progress on the GitHub Project board and in issue comments.
Stop at any time: /supersaiyan stop
Resume:          /supersaiyan run

── Other commands ───────────────────────────────────────
Re-run lint after editing issues:
   /supersaiyan lint

Re-sync issues without redefining the feature:
   /supersaiyan prepare <feature-slug>

Check board status:
   /supersaiyan status
```
