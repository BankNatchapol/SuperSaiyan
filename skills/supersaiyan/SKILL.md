---
name: supersaiyan
description: End-to-end AI development pipeline — idea to merged PR with one command set. Handles brainstorming, spec writing, task decomposition, issue filing, and autonomous Build → QA → Review execution. Use when the user types "/supersaiyan", "supersaiyan", or any supersaiyan verb (new, setup, prepare, run, status, lint, stop).
---

# SuperSaiyan

One command set. Idea → merged PR.

## The pipeline

```
/supersaiyan new <name>    ← brainstorm → spec → tasks → queue
/supersaiyan run           ← autonomous Build → QA → Review
```

`<name>` is a kebab-case slug for anything you want to build — a single feature (`health-endpoint`), a product idea (`my-saas-app`), or a project (`chat-system`). The brainstorm phase asks what context you're working in and adjusts accordingly. For a new app or large project, `new` automatically switches to project mode and decomposes the work into phases.

```
/supersaiyan new <name>               ← brainstorm → spec → phases → tasks per phase
/supersaiyan run                      ← run Phase 1
/supersaiyan prepare <name> --phase 2 ← unlock Phase 2 when Phase 1 is done
/supersaiyan run                      ← run Phase 2  (repeat per phase)
```

---

## All verbs

| Verb | What | Next step after |
|------|------|-----------------|
| `supersaiyan setup` | One-time: docs layout + GitHub Project + board config | Run `supersaiyan new <name>` |
| `supersaiyan new <name>` | Full pipeline: brainstorm → spec → tasks → commit → prepare | Run `supersaiyan run` |
| `supersaiyan prepare <feature>` | Re-sync issues, add to Ready, run lint (re-run anytime) | Run `supersaiyan run` |
| `supersaiyan prepare <slug> --phase N` | Unlock next project phase after previous phase is done | Run `supersaiyan run` |
| `supersaiyan run [slug]` | Start the autonomous Build → QA → Review loop | Watch the board; stop with `supersaiyan stop` |
| `supersaiyan status [slug]` | Board snapshot (read-only) | Fix issues if blocked; then run again |
| `supersaiyan lint` | Pre-flight check on issue quality | Fix flagged issues, then run |
| `supersaiyan stop` | Graceful shutdown | Resume with `supersaiyan run` |

---

## Routing

| Invocation | Action |
|---|---|
| `supersaiyan setup` | Read `references/setup.md`, follow exactly |
| `supersaiyan new <name>` | Read `references/new.md`, follow exactly |
| `supersaiyan prepare <feature>` | Read `references/prepare.md`, follow exactly |
| `supersaiyan prepare <slug> --phase N` | Read `references/project.md` → "Prepare — Phase Unlock" section |
| `supersaiyan run [slug]` | Read `references/run-workflow.md`; lane lifecycles from `references/run.md` |
| `supersaiyan lint` | Read `references/lint.md`, follow exactly |
| `supersaiyan status [slug]` | Read `references/status.md`, follow exactly |
| `supersaiyan stop` | Read `references/stop.md`, follow exactly |
| No verb / unknown verb | Print the usage table above. List verbs only. Do not guess. |

---

## Config

Config lives at `.claude/super-board/configs/<slug>.json`. Created by `setup`.

If config is missing when any verb (other than `setup`) is invoked, run `setup` inline first, then continue with the original verb.

When `prepare` is invoked and no board config exists, `scripts/prepare.sh` exits `78` — this signals the agent to run inline onboarding before retrying.

---

## What's inside `supersaiyan new`

The `new` command runs a four-phase pipeline using trusted methodologies:

| Phase | Reference | Based on |
|-------|-----------|----------|
| Brainstorm | `references/brainstorm.md` | gstack office-hours (two modes, six forcing questions) |
| Spec | `references/spec.md` | gstack /spec (five-phase technical interrogation) |
| Tasks | `writing-board-tasks` skill | superpowers writing-board-tasks |
| Agents use | `test-driven-development` skill | superpowers TDD |
| Agents use | `verification-before-completion` skill | superpowers verification |

For multi-phase projects, `spec.md` routes to `references/project.md` which handles phase decomposition, PROJECT.md, per-phase PHASE.md specs, and per-phase task writing.

---

## Next step after each verb

**After `setup`:**
```
/supersaiyan new <name>    ← start your first feature, project, or app idea
```

**After `new` (single feature):**
```
/supersaiyan run              ← start the autonomous loop
```

**After `new` (project — multiple phases):**
```
/supersaiyan run              ← run Phase 1 (already queued)
# when Phase 1 board is empty:
/supersaiyan prepare <slug> --phase 2
/supersaiyan run              ← run Phase 2
# repeat for each phase
```

**After `run` completes a phase:**
```
/supersaiyan prepare <slug> --phase N   ← unlock next phase
/supersaiyan run                        ← run it
```

**If something is stuck:**
```
/supersaiyan status           ← see what's blocked and why
/supersaiyan stop             ← stop the loop
# fix the issue (merge conflict, failing test, bad AC)
/supersaiyan lint             ← re-check issue quality
/supersaiyan run              ← resume
```

---

## Internal pipeline skills

These skills power the autonomous loop. Users do not invoke them directly:

- `super-build` — Builder lane agent (implements code, opens PR)
- `super-qa` — QA lane agent (runs tests, captures evidence)
- `super-review` — Reviewer lane agent (reruns tests, merge readiness)
- `refining-spec` — Tightens a design into a pipeline-ready spec
- `writing-board-tasks` — Decomposes spec into PR-sized task files
- `test-driven-development` — TDD discipline used by Builder agent
- `verification-before-completion` — Verification gate used by Builder and QA agents
