<!-- GENERATED FILE — edit skills/super-board/references/onboard.md, then run scripts/generate-supersaiyan-references.sh to regenerate. Do not hand-edit. -->

# super-board onboard — verb reference

Source of truth: `docs/superpowers/specs/2026-05-21-super-board-design.md` §5
(with §4 config schema and field notes referenced from `config-schema.json`).

This file documents the interactive setup wizard. It is loaded by `SKILL.md`
when the user invokes `super-board onboard …`.

**Where it runs:** current Claude Code session, in user's CWD. Not headless.
**Design rule:** minimize questions. Detect first, ask only what can't be
inferred. Lead with one big "goal" question — it branches the entire flow.

---

## Intro shown when onboard starts

```
super-board onboard
─────────────────────────────────────────────────────────
super-board = a GitHub Project pipeline that runs autonomously.
              It drains issues from Ready across columns
              (Building → QA → Review → Done) until the board
              is empty or only Blocked/Skipped cards remain.

Progress: 🛠 onboard (you are here)  →  🧹 lint  →  🤖 run
─────────────────────────────────────────────────────────
```

---

## Step-by-step logic

```
0. SILENT DETECT (no questions yet)
   ├─ CWD: git repo? any commits? remote URL?
   ├─ Existing configs in .claude/supersaiyan/configs/?
   └─ Existing PROJECT.md?

1. ONE BIG QUESTION — "What do you want to run in a loop?"
   ├─ A) Test a live URL (staging/prod, no code access)
   │       → variant = qa-only, target = url
   ├─ B) Build features for a local repo
   │       → variant = full, target = repo (+ optional URL)
   ├─ C) QA a local repo (already built)
   │       → variant = qa-only, target = repo (+ optional URL)
   └─ D) Use an existing config
           → list configs with descriptions → pick → skip to step 10

2. WHICH TOOL(S) WILL DRIVE THIS BOARD?
   ├─ Ask: "Will Claude Code drive this loop, or do you also want Codex
   │        and/or Cursor CLI workers dispatching from the same board?"
   ├─ Default: Claude Code only (worker_backend "workflow").
   └─ If more than one tool is selected, ask ONE follow-up — these are two
      genuinely different setups, and picking the wrong one is annoying to
      undo later:
        "Should each tool run its OWN independent board (separate config +
         separate dispatcher process), or should ONE board use a different
         tool per LANE — Codex builds, Cursor QAs, Claude reviews, all in a
         single dispatcher process?"
        │
        ├─ A) INDEPENDENT BOARDS — N configs, N dispatcher processes.
        │     Pick this for parallel/redundant boards, or when each tool
        │     should own a whole pipeline end to end.
        │     ├─ Run steps 3-13 ONCE per tool, producing N config files that
        │     │  all point at the SAME project.owner/project.number but
        │     │  differ in `description` and `worker_backend`:
        │     │    <slug>-claude.json  → worker_backend "workflow" (or "claude-p")
        │     │    <slug>-codex.json   → worker_backend "codex-exec"
        │     │    <slug>-cursor.json  → worker_backend "cursor-agent"
        │     └─ Explain: each config's dispatcher is a plain background
        │        process — run `.claude/bin/super-board-run.sh <slug>-codex`
        │        alongside `<slug>-cursor` and `<slug>-claude` in parallel
        │        shells; they share the board but never fight over one config
        │        file. (This is what fixes the classic "two dispatchers
        │        overwrite each other's worker_backend" collision — no
        │        data-model change needed, multiple named configs already
        │        work.)
        │     Known gap: every shared field (`project`, `variant`,
        │     `rebuild_cap`, `truth_gate`, etc.) is fully duplicated across
        │     the N files today — editing one means editing all of them
        │     identically, with nothing catching drift. A shared-base +
        │     linked-overlay design is proposed, not implemented, in
        │     `docs/super-board-analysis/multi-tool-config-linking.md`.
        │
        └─ B) PER-LANE MAP — one board, one config, one dispatcher process.
              Pick this to specialize by lane (e.g. one tool builds, another
              reviews) rather than run whole parallel pipelines.
              ├─ Ask which tool drives each lane the variant uses ("Which
              │  tool should Build use? QA? Review?" — skip Build entirely
              │  for qa-only). Default any unanswered lane to Claude Code.
              ├─ Run steps 3-13 ONCE, writing a single config whose
              │  `worker_backend` is an object:
              │    "worker_backend": {
              │      "build":  "codex-exec",
              │      "qa":     "cursor-agent",
              │      "review": "claude-p"
              │    }
              ├─ Note explicitly: "workflow" is NEVER a valid per-lane value.
              │  A lane driven by Claude Code here uses "claude-p" (headless
              │  `claude -p`, bash-dispatched), not "workflow" (in-session
              │  workflow lane agents). Close in behavior, not identical —
              │  see `references/backends.md`. The dispatcher rejects a
              │  per-lane "workflow" with exit 78.
              └─ Optional: set per-tool models by hand after onboarding —
                 `codex.model` / `codex.reasoning_effort` / `cursor.model`
                 in the same config (one setting per TOOL, applied wherever
                 that tool is used). Empty/absent = the CLI's own default.

      For EITHER path, for every codex/cursor lane or config selected:
      confirm `codex login status` / `agent status` succeed now (fail fast,
      not at first dispatch), and that `./install.sh --keep-local-skills`
      has been run so `.claude/skills/` is populated locally — Codex/Cursor
      have no plugin skill cache and can only read files that physically
      exist in the repo. See `references/backends.md`.

3. VERIFY GITHUB AUTH (always)
   ├─ `gh auth status`  — must be authenticated
   ├─ Scope check: `project`, `read:project`, `repo`
   ├─ If missing → `gh auth refresh -s project,read:project,repo`
   └─ Tell user WHY: "needed to move cards on your board and create
       projects on your behalf"

4. ENFORCE LOCAL GIT REPO (mandatory)
   ├─ If CWD is not a git repo → "I need to init git before continuing. Proceed? [y/n]"
   ├─ If no remote on local repo and user picked B or C with `push`/`pr`/`merge` authority later
   │     → offer `gh repo create`
   └─ Reason: version control is required to manage worktrees, branches, and merges.

5. RESOLVE TARGET (branches by Q1 answer)
   ├─ A (URL only): ask for the URL → save target.url. Repo = null.
   ├─ B (build local repo):
   │    ├─ Auto-detect remote. Offer `gh repo create` if missing.
   │    ├─ No commits? Offer "scaffold from template? [NestJS / Next.js / Vite / blank]"
   │    └─ Save repo = {path, remote_or_null}. Optionally also save target.url.
   └─ C (QA local repo): auto-detect repo. Ask only for target URL if any.

6. PICK OR CREATE GITHUB PROJECT
   ├─ List existing projects under repo owner (or user's account if no repo)
   ├─ If picked → validate column shape matches variant (fix if not)
   └─ If new → `gh project create --title <name>` → create columns for variant

7. VALIDATE / CREATE COLUMNS (idempotent)
   ├─ Full variant (7 total):    Ready · Building · QA · Review · Done · Blocked · Skipped
   ├─ QA-only variant (6 total): Ready ·            QA · Review · Done · Blocked · Skipped
   └─ Read Status field, add missing options, re-read to confirm.

8. AUTO-GENERATE PROJECT.md (skip if URL-only or user opts out)
   ├─ Spawn sub-agent: read whichever manifest set exists + README + top-level structure:
   │    • Node:    package.json
   │    • Python:  pyproject.toml or requirements.txt
   │    • Rust:    Cargo.toml
   │    • Go:      go.mod
   │    • Ruby:    Gemfile
   │    • Other:   no manifest found → ask user one question:
   │              "What does this project do? (one short paragraph)"
   │              Use the answer verbatim as the seed for PROJECT.md.
   │    → draft PROJECT.md (what the app is, stack, conventions, success criteria)
   ├─ Show draft → user confirms/edits inline
   └─ Save to docs/supersaiyan/PROJECT.md

9. PICK BASE BRANCH (Full variant with local repo, OR QA-only with a local repo)
   (Skip entirely only when target.type == "url" with no repo.)
   ├─ Detect current branch + remote default branch
   ├─ Production-detection (any of these signals → treat as production):
   │    • `.github/workflows/*.yml` contains `deploy` job triggered on push to base
   │    • `vercel.json` / `netlify.toml` present at repo root
   │    • Branch protection rules require PR review on base (gh api repos/.../branches/<base>/protection)
   │    • README contains "production" or live URL on the base branch
   ├─ Ask: "Which branch should super-board cut feature branches from
   │        and squash-merge them back into?"
   ├─ Default: main (unless production-detected, then default to creating `staging`)
   └─ ⚠️ WARN if base looks production-y (any signal above fires):
       "Heads up — using main means every merged ticket lands in
        production. Consider a staging or develop branch instead.
        Want me to create one?"

10. MERGE POLICY (Full variant with local repo, OR QA-only with a local repo)
    (Tester commits test files to the same branch; merge policy applies.
    Skip only when target.type == "url" with no repo.)
    ├─ "Should super-board auto-merge approved PRs into base, or wait
    │   for a human to click merge? [auto / human]"
    ├─ Sets config.human_approves_merge accordingly.
    └─ HARD RULE: if base_branch was production-detected (step 9) AND user
        did NOT switch to staging/develop, force human_approves_merge = true
        and tell the user: "Auto-merge to production is disabled. Approved
        PRs will be marked ready for review; you click merge."

11. RECORD NOTIFICATION CHANNEL
    └─ Auto-detect from the current session; allow override.

12. WRITE CONFIG + ACTIVE POINTER
    ├─ Generate `description` (short, scannable)
    ├─ Record notifications.bot_identity — either `super-board-bot[bot]`
    │  (when a GitHub App is installed on the repo) or the user's own
    │  GitHub login (solo projects). Pick during step 3 based on what
    │  `gh auth status` returned.
    ├─ Write .claude/supersaiyan/configs/<slug>.json (committed)
    └─ Write .claude/supersaiyan/active ← <slug> (gitignored)

13. SUMMARY
    "✅ Onboard complete.
     📋 Go write your tickets here: <project URL>
     🧹 Then run `super-board lint` to make sure each issue has clear
        success criteria."
```

---

## Error recovery during onboard

Every onboard step that touches GitHub or the filesystem has a defined recovery path. The user never gets a raw `gh` stack trace — they get a friendly diagnosis and the exact next command.

| Step | Failure mode | What the user sees |
|---|---|---|
| 2. which tool(s) | `codex login status` / `agent status` fails for a selected tool | `🔑 <tool> isn't logged in. Run: \`codex login\` / \`agent login\` — then re-run super-board onboard.` |
| 3. gh auth | Not logged in | `🔑 You're not signed in to GitHub. Run: \`gh auth login\` — then re-run super-board onboard.` |
| 3. gh auth | Scope refused (user said no on browser) | `🔑 GitHub asked for project,read:project,repo scopes and you said no. Without them I can't read or move project cards. Re-run: \`gh auth refresh -s project,read:project,repo\`.` |
| 4. git init | User declined | Halt with: `🛑 super-board needs a git repo. Re-run when ready.` |
| 5. gh repo create | Quota/perm denied | `📦 GitHub refused to create the repo (org admin required, or you hit your free-repo quota). Options: (a) pick an existing repo, (b) create one in the web UI then re-run, (c) skip repo and run URL-only.` |
| 6. gh project create | Org project denied | `🔑 You don't have permission to create projects under <org>. Either ask an org admin, or pick your personal account: \`gh project create --owner @me\`.` |
| 6. gh project pick | Project deleted between list + pick | `📋 That project was deleted after I listed it. Reloading…` then auto-retry. |
| 7. column create | Column add denied (read-only project) | `🔑 Project is read-only for your account. Either get write access, or pick a different project.` |
| 8. PROJECT.md autogen | Sub-agent timeout / empty draft | `📝 Couldn't auto-draft PROJECT.md. Skip for now, or write one paragraph and I'll seed from that.` |
| 9. base branch | gh API rate limit on protection-rule lookup | Soft-fail production detection, warn the user, fall back to asking. Do not halt. |
| 12. write config | File system not writable | Halt with the exact path: `🛑 Can't write to .claude/supersaiyan/configs/<slug>.json — check permissions.` |

Every onboard halt comment includes (a) what the bot tried, (b) what failed, (c) the exact command or click the user can do, (d) how to resume (always: "re-run `super-board onboard`").

---

## Re-running onboard

- Detects existing active config → "Reconfigure? [y/n]"
- If yes: walks the same steps, defaults to current values.
- Variant switches (Full ↔ QA-only) warn that column shape changes.

---

## Worker self-check (mandatory before exit)

Before exiting `onboard` successfully, the worker MUST verify:

1. **Config file exists and validates** — `.claude/supersaiyan/configs/<slug>.json`
   parses as JSON and contains every required field from `references/config-schema.json`
   (including `notifications.bot_identity`).
2. **Active pointer is updated** — `.claude/supersaiyan/active` is a one-line
   file containing exactly the new slug, no trailing whitespace beyond a single `\n`.
3. **Project columns are present on GitHub** — running
   `gh project field-list <project.number> --owner <project.owner>` returns all
   required column options for the chosen variant:
   - Full: `Ready, Building, QA, Review, Done, Blocked, Skipped`
   - QA-only: `Ready, QA, Review, Done, Blocked, Skipped`
4. **PROJECT.md exists** — when `paths.project_md` is non-null (i.e. any flow with
   a local repo), the file at that path exists and is non-empty.
5. **Local skills mirror exists for non-`claude-p` backends** — when any resolved
   backend is `codex-exec` or `cursor-agent` (either the whole-board `worker_backend`
   string, or ANY value inside a per-lane `worker_backend` object), verify
   `.claude/skills/` exists in the target repo as real files — e.g.
   `.claude/skills/super-board/references/backends.md` resolves to an actual file, not
   just a Claude Code plugin-cache reference. If it is missing, tell the user to run
   `./install.sh --keep-local-skills` and re-check before continuing. Codex and Cursor
   have no plugin skill cache; they can only read files that physically exist in the
   repo they run against, so a worker dispatched without this fails at read time with
   no useful error. See `references/backends.md`.

If any of these five checks fail, do NOT print the step-13 summary. Instead, surface
the specific failed check and tell the user to re-run `super-board onboard`. A
partial config is worse than no config — the lint and run verbs depend on these
invariants.
