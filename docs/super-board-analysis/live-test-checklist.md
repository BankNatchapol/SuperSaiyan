# Live Smoke Test Checklist

Optional Phase B from the adoption plan. SuperSaiyan is set up as a **sandbox**; for a meaningful end-to-end run, use a real app repository with a GitHub Project.

## What is already prepared in SuperSaiyan

- [x] `super-board/` — upstream clone for study and `install.sh`
- [x] `.claude/skills/` — super-board, super-build, super-qa, super-review installed
- [x] `.claude/bin/` — wave planner, status script, legacy dispatcher
- [x] `.claude/workflows/super-board-wave.js`
- [x] `gstack` symlinked at `.claude/skills/gstack` (full `./setup` requires Bun — see `install-deps.md`)
- [x] `superpowers/` cloned for reference (plugin install recommended for `superpowers:*` namespace)

## Prerequisites (manual)

- [ ] Claude Code with **dynamic workflows** enabled (`/config`)
- [ ] `gh auth login` with `project`, `read:project`, `repo` scopes
- [ ] `jq`, bash 4+, Python 3
- [ ] GitHub Project v2 with columns: `Backlog`, `Ready`, `Building`, `QA`, `Review`, `Done`, `Blocked`, `Skipped`
- [ ] superpowers: `/plugin install superpowers@claude-plugins-official` (Claude Code)
- [ ] gstack: `cd gstack && ./setup` (requires Bun)

## Install into target app repo

```bash
cd /path/to/your-app
/Users/bank.p/Documents/SuperSaiyan/super-board/install.sh .
```

## Onboard (Claude Code)

```
/super-board onboard
```

Creates `.claude/super-board/configs/<slug>.json`.

## Sample config (first run — safe defaults)

Save as `.claude/super-board/configs/staging.json`:

```json
{
  "variant": "full",
  "worker_backend": "workflow",
  "model_tier": "medium",
  "project": {
    "owner": "YOUR_GH_USER_OR_ORG",
    "number": 0
  },
  "base_branch": "main",
  "human_approves_merge": true,
  "rebuild_cap": 2,
  "tick_seconds": 120,
  "max_workers": 3,
  "truth_gate": "non-trivial",
  "truth_threshold": 70,
  "notifications": {
    "bot_identity": "YOUR_GH_LOGIN"
  }
}
```

**First run:** `human_approves_merge: true` so you click merge manually.

## Sample issue (copy into GitHub)

```markdown
## Goal
Add a health-check JSON endpoint at GET /api/health.

## Acceptance Criteria
- [ ] GET /api/health returns 200 with `{ "status": "ok" }`
- [ ] Unit test covers the handler

## Notes
- Skills: superpowers:test-driven-development, superpowers:verification-before-completion
```

Move card to **Ready**.

## Run sequence

```
/super-board lint
/super-board status staging
/super-board run staging
```

## Observe

- [ ] Card moves Ready → Building → QA → Review
- [ ] Draft PR opened with PR description template
- [ ] Issue + PR comments per lane (🔨 Build, 🔍 QA, ✅ Review)
- [ ] QA fail (optional): card bounces to Ready with `loop:rebuild-1`
- [ ] Review with `human_approves_merge`: PR marked ready, you merge manually
- [ ] `/super-board stop` posts mid-flight comments if interrupted

## Why not run live from this agent session

Live test requires:

1. Your authenticated `gh` identity and a real GitHub Project number
2. Claude Code interactive session (not Cursor) for `/super-board` verbs and workflow tool
3. A codebase with tests the QA lane can run

This checklist is the executable handoff when those are available.
