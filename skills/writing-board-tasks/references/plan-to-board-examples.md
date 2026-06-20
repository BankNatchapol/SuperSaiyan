# Plan task → board task — examples

Companion to **writing-board-tasks** (fork of superpowers:writing-plans). Same decomposition rules; different output shape.

---

## Example 1 — Merge scaffold into deliverable

### writing-plans (excerpt)

```markdown
### Task 1: Project scaffold

- [ ] Step 1: npm init
- [ ] Step 2: Add vitest
...

### Task 2: Supabase client module

**Files:** Create `lib/supabase.ts`
- [ ] Step 1: Write failing test...
- [ ] Step 2: Implement createClient()...
```

### writing-board-tasks → one file

**`01-supabase-client.md`**

- **Maps from:** Task 1–2 (scaffold folded in)
- **Goal:** App has a tested Supabase client module wired to env vars.
- **ACs:** module exports `createClient()`; test file path; `npm test` passes; README lists required env vars
- **Implementation notes:** "See plan Task 2 for TDD steps; Task 1 setup assumed in repo"

**Why:** super-board should not run "npm init" as its own PR.

---

## Example 2 — Split oversized plan task

### writing-plans (excerpt)

```markdown
### Task 4: Chat UI with insert, list, and realtime

**Files:** index.html, lib/chat.ts, lib/realtime.ts
...15 micro-steps...
```

### writing-board-tasks → two files

| File | Maps from | Split reason |
|------|-----------|--------------|
| `03-chat-insert-ui.md` | Task 4 steps 1–8 | Insert-only vertical slice |
| `04-message-list.md` | Task 4 steps 9–15 | Depends on 03; list view separate PR |

**Why:** One issue with insert + list + realtime fails QA scope and produces huge PRs.

---

## Example 3 — AC translation (not step copy)

### Plan micro-step (NOT an AC)

```markdown
- [ ] **Step 3: Write minimal implementation**
```typescript
export function createClient() { ... }
```
```

### Board task AC (observable)

```markdown
- [ ] `lib/supabase.ts` exports `createClient()` returning a Supabase client instance
- [ ] `tests/supabase.test.ts` passes (`npm test -- supabase`)
```

The Builder still reads **Implementation notes** → plan Task 2 for TDD detail. QA judges **checkboxes**, not plan steps.

---

## Example 4 — Chat bubble feature (3 board tasks)

Typical breakdown for a Supabase chat feature:

| # | Title | Plan coverage |
|---|-------|---------------|
| 01 | Add Supabase client and messages migration | Tasks 1–3 |
| 02 | Chat input inserts one message row | Task 4 (insert half) |
| 03 | Render message list from Supabase | Task 4–5 (read path) |

Realtime, auth, polish → **later board tasks** or explicitly **Out of scope** on early tasks.

---

## Anti-pattern — mechanical split script

A script that dumps each `### Task N:` into `NN-*.md` with placeholder ACs produces:

- Too many issues (one per TDD cycle)
- ACs like "Tests pass (document command in PR)" with no real checks
- Board tasks that fail `/super-board lint`

Use **writing-board-tasks** (agent) for decomposition; use **split-plan-to-tasks.sh** only as a stub generator you fully rewrite.
