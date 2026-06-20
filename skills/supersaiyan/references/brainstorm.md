# Brainstorm — Product Design Session

Runs before the spec phase. Saves a design doc that `references/spec.md` reads as input.

Announce at start: "Starting brainstorm for `<feature-slug>`. I'll guide you through a product design session before we write any specs."

---

## Step 0 — Context Load (silent)

Read before asking any questions:

1. `CLAUDE.md` — stack constraints, conventions, existing context
2. `PROJECT.md` if it exists — repo-wide context
3. `package.json` / `go.mod` / `pyproject.toml` — tech stack
4. Run: `git log --oneline -20` — what's been built recently

Check for an existing design doc:
- `docs/gstack/designs/<feature-slug>-design.md` → found: say "I found an existing design. I'll use it as the starting point and only ask about gaps." Read it, skip questions already answered.
- None found → proceed to Step 1.

---

## Step 1 — Mode Selection

Ask the user one question to determine the mode:

> "Before we dig in — what's the context for this? I'll adjust my questions accordingly."
>
> A) **Building a product or startup** — need to validate demand and find the right wedge
> B) **Side project / hackathon / learning** — want to build something cool and ship it
> C) **Quick fix / small edit** — bug, config change, minor tweak (skip planning, write one task, run)

- A → **Startup Mode** (Step 2A)
- B → **Builder Mode** (Step 2B)
- C → **Quick Mode** (Step 2C) — skip brainstorm, spec, and phases entirely

---

## Step 2A — Startup Mode: YC Product Diagnostic

### Operating Principles (non-negotiable)

**Specificity is the only currency.** Vague answers get pushed. "Enterprises in healthcare" is not a customer. You need a name, a role, a company, a reason.

**Interest is not demand.** Waitlists, signups, "that's interesting" — none of it counts. Behavior counts. Money counts. Panic when it breaks counts.

**The status quo is your real competitor.** Not another startup — the cobbled-together spreadsheet-and-Slack workaround your user is already living with.

**Narrow beats wide, early.** The smallest version someone will pay real money for this week is more valuable than the full platform vision.

### Anti-Sycophancy Rules

Never say during this phase:
- "That's an interesting approach" — take a position instead
- "There are many ways to think about this" — pick one
- "That could work" — say whether it WILL work and what evidence is missing

Always: take a position on every answer. State your position AND what evidence would change it.

### The Six Forcing Questions — ask ONE AT A TIME, push until specific

**Smart routing by stage:**
- Pre-product (no users yet) → Q1, Q2, Q3
- Has users (not paying) → Q2, Q4, Q5
- Has paying customers → Q4, Q5, Q6

#### Q1 — Demand Reality
**Ask:** "What's the strongest evidence you have that someone actually wants this — not 'is interested,' not 'signed up for a waitlist,' but would be genuinely upset if it disappeared tomorrow?"

**Push until you hear:** Specific behavior. Someone paying. Someone who built their workflow around it.

**Red flags:** "People say it's interesting." "We got 500 waitlist signups." None of these are demand.

**After first answer:** Check language precision. Are key terms defined? Is there real evidence or hypothetical pain? If imprecise, reframe: "Let me try restating what I think you're building: [reframe]. Does that capture it?"

#### Q2 — Status Quo
**Ask:** "What are your users doing right now to solve this problem — even badly? What does that workaround cost them?"

**Push until you hear:** A specific workflow. Hours spent. Dollars wasted. Tools duct-taped together.

**Red flag:** "Nothing — there's no solution." If no one is doing anything, the problem probably isn't painful enough.

#### Q3 — Desperate Specificity
**Ask:** "Name the actual human who needs this most. What's their title? What gets them promoted? What gets them fired? What keeps them up at night?"

**Push until you hear:** A name. A role. A specific consequence. Not "healthcare enterprises" — an actual person.

#### Q4 — Narrowest Wedge
**Ask:** "What's the smallest possible version of this that someone would pay real money for — this week, not after you build the platform?"

**Push until you hear:** One feature. One workflow. Something shippable in days.

**Red flag:** "We need to build the full platform before anyone can really use it." — That's attachment to architecture, not value.

#### Q5 — Observation & Surprise
**Ask:** "Have you actually sat down and watched someone use this without helping them? What did they do that surprised you?"

**Push until you hear:** A specific surprise. Something the user did that contradicted assumptions.

**Red flag:** "We did some demo calls." Demos are theater — guided walkthroughs teach you nothing.

#### Q6 — Future-Fit
**Ask:** "If the world looks meaningfully different in 3 years — and it will — does your product become more essential or less?"

**Push until you hear:** A specific claim about how their users' world changes and why that makes the product more valuable.

**Red flag:** "The market is growing 20% per year." Growth rate is not a thesis.

### Escape Hatch
If the user expresses impatience: "I hear you. The hard questions are the value — skipping them is like skipping the exam. Let me ask two more, then we'll move." Ask the 2 most critical remaining questions for their stage, then proceed. If they push back a second time, go to Step 3.

---

## Step 2B — Builder Mode: Design Partner

### Operating Principles

1. **Delight is the currency** — what makes someone say "whoa"?
2. **Ship something you can show people.** The best version of anything is the one that exists.
3. **The best side projects solve your own problem.** Trust that instinct.
4. **Explore before you optimize.** Try the weird idea first.

### Response Posture

Be an enthusiastic, opinionated collaborator. Riff on their ideas. Suggest cool things they might not have thought of. End with concrete build steps, not business validation tasks.

### Five Generative Questions — ask ONE AT A TIME

1. "What's the coolest version of this? What would make it genuinely delightful?"
2. "Who would you show this to? What would make them say 'whoa'?"
3. "What's the fastest path to something you can actually use or share?"
4. "What existing thing is closest to this, and how is yours different?"
5. "What would you add if you had unlimited time? What's the 10x version?"

**Smart-skip:** If the user's initial prompt already answers a question, skip it.

**If the vibe shifts** — user mentions customers, revenue, fundraising → upgrade naturally: "Okay, now we're talking — let me ask you some harder questions." Switch to Step 2A questions.

---

## Step 3 — Landscape Awareness

Ask permission before searching:

> "I'd like to search for what's out there in this space to inform our discussion. I'll use generalized category terms, not your specific idea. OK to proceed?"
> A) Yes, search away
> B) Skip — keep this session private

If B: skip to Step 4.

If A, use WebSearch with **generalized category terms** (never the user's specific product name):

**Startup mode:** Search "[problem space] startup approach", "[problem space] common mistakes", "why [incumbent] fails"

**Builder mode:** Search "[thing being built] existing solutions", "[thing category] open source alternatives"

Read top 2-3 results. Synthesize:
- **[Layer 1]** What does everyone already know about this space?
- **[Layer 2]** What are search results / current discourse saying?
- **[Layer 3]** Given what we learned in Step 2 — is there a reason the conventional approach is wrong here?

If Layer 3 reveals a genuine insight, name it: "EUREKA: Everyone does X because they assume [assumption]. But [evidence] suggests that's wrong here."

If conventional wisdom is solid: "The conventional wisdom seems sound here. Let's build on it."

---

## Step 4 — Premise Challenge

Before writing the design doc, challenge the foundations:

1. **Is this the right problem?** Could a different framing yield a simpler or more impactful solution?
2. **What happens if we do nothing?** Real pain point or hypothetical?
3. **What existing code already partially solves this?** Check for reusable patterns.
4. **If this produces a new artifact** (CLI, library, app): how will users get it? Distribution is part of the design.

Output premises as clear statements:
```
PREMISES:
1. [statement] — agree or pushback?
2. [statement] — agree or pushback?
```

If user disagrees with a premise, revise understanding and loop back. Confirmed premises feed directly into the design doc.

---

## Step 5 — Write Design Doc

Write `docs/gstack/designs/<feature-slug>-design.md`:

```markdown
# <Feature / Product Name>

**Mode:** Startup | Builder
**Date:** <date>
**Slug:** <slug>

## Problem

[One paragraph: what the pain is, who has it, why now]

## Target User

[Specific person, role, and consequence they face — not a category]

## Status Quo

[What they're doing today to solve this, and what it costs them]

## Demand Evidence

[Specific behavior showing real demand — not interest, not signups]

## Proposed Direction

[What we're building, at a high level]

## Wedge / MVP

[Smallest version someone would pay for or use this week]

## Key Premises

1. [Agreed premise from Step 4]
2. ...

## Landscape

[What exists today, conventional wisdom, where it falls short]

## Out of Scope (initial)

[Things we explicitly won't build now]

## Open Questions

[Unresolved items — things to decide in spec phase]
```

Announce: "Design doc saved to `docs/gstack/designs/<slug>-design.md`. Next: `references/spec.md` will turn this into a technical spec."

---

## Step 2C — Quick Mode

Skip landscape search, startup/builder questioning, and premise challenge. Ask one question, read the code, write a minimal design doc.

Ask: "Describe the change in 1–3 sentences. What should be different when it's done?"

Then (silently):
1. Read `CLAUDE.md` and locate the relevant files via Grep/Read — cite `path:line`.
2. Write a minimal design doc to `docs/gstack/designs/<slug>-design.md`:

```markdown
# <Slug>

**Mode:** Quick fix
**Date:** <date>

## Change

[What should be different when this is done — from the user's description]

## Affected Files

[Exact paths found in the codebase]

## Out of Scope

[What this does NOT include]
```

3. Announce: "Quick design doc saved. Moving to spec."
4. Hand off to `references/spec.md` — the spec phase reads this doc and routes to "Single task" in Phase 5.
