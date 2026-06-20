# GitHub issue template (Step 11)

Copy the **Issue body** below into a **new GitHub issue** in your app repo. Replace placeholders with your feature.

**Title:** one line, verb + outcome — e.g. `Add GET /api/health endpoint` or `Add chat bubble that saves messages to Supabase`

---

## How to choose *what* goes in the issue

| Source | Use it for |
|--------|------------|
| `/office-hours` or design doc | **Scope** — pick **one thin slice** agents can finish in one PR |
| Design doc | **Reference** — link or path in Notes; don’t paste the whole spec |
| This template | **Goal + checkboxes** — observable, testable “done” |

**First run:** one issue only. Smallest vertical slice that proves the pipeline works.

**Good issue size:** one user-visible behavior + tests (e.g. one endpoint, one form submit, one DB insert).

**Too big:** “Build the whole app”, “full auth system”, “entire Supabase schema” — split into later issues.

---

## Issue body — copy from here

```markdown
## Goal

<One sentence: what this issue delivers and why.>

## Acceptance Criteria

- [ ] <Observable check 1 — HTTP status, JSON shape, UI text, DB row, etc.>
- [ ] <Observable check 2>
- [ ] <Test exists — name test file or command to run, e.g. `npm test` / `pytest` path>

## Notes

- Design: `docs/superpowers/specs/<feature-slug>-design.md`
- Skills: superpowers:test-driven-development, superpowers:verification-before-completion
- Keep this issue minimal — no extra features
```

---

## Example A — tutorial health endpoint

**Title:** `Add GET /api/health endpoint`

```markdown
## Goal

Add a health-check JSON endpoint at `GET /api/health` so we can verify the app is running.

## Acceptance Criteria

- [ ] `GET /api/health` returns HTTP 200
- [ ] Response body is JSON: `{ "status": "ok" }`
- [ ] A unit or integration test covers the handler (test file path noted in the PR)

## Notes

- Design: `docs/superpowers/specs/health-endpoint-design.md`
- Skills: superpowers:test-driven-development, superpowers:verification-before-completion
- Keep the change minimal — no extra features in this issue
```

---

## Example B — Supabase chat bubble (first slice)

**Title:** `Add chat bubble that inserts a message row in Supabase`

```markdown
## Goal

Show a chat input on `index.html`; submitting inserts one row into the `messages` table in Supabase.

## Acceptance Criteria

- [ ] `index.html` renders a message input and send control
- [ ] Submitting non-empty text inserts a row into `messages` (table + columns documented in PR)
- [ ] Success or error is visible in the UI (not silent failure)
- [ ] A test or documented manual check proves insert works (steps in PR)

## Notes

- Design: `docs/superpowers/specs/chat-bubble-design.md`
- Skills: superpowers:test-driven-development, superpowers:verification-before-completion
- Out of scope: auth, realtime, styling polish — follow-up issues only
```
