# Sketchbook — Portfolio Design System

A hand-drawn / sketchbook design system for **Natchapol Patamawisut**, a Quantum
Computing Researcher. It dresses a personal portfolio site in the look of an
ink-and-pencil notebook: aged-paper surfaces, navy ink text, wobbly drawn
borders, typewriter body copy, handwritten display type, and small watercolour
accents. Everything is built to feel *made by hand* rather than generated.

> **Sources.** This system was created from a written brief only — no codebase,
> Figma, or screenshots were attached. All content (name, papers, affiliations)
> is plausible placeholder copy for a quantum-computing researcher and should be
> swapped for the real thing. If you have the original site or assets, share them
> and the system can be tuned to match exactly.

**Tech target:** React + TypeScript + Vite, single-page app, no backend.

---

## Content fundamentals

How the portfolio *talks*:

- **Voice — first person, warm, a little self-deprecating.** The narrator is the
  researcher. *"I build the error-correction software that keeps fragile qubits
  honest."* *"I reply, eventually."* Confident about the work, light about
  everything else.
- **Plain over grand.** Real nouns, no buzzwords. "the unglamorous plumbing
  between a dilution fridge and a laptop" beats "end-to-end quantum solutions."
  Never markety; this is a person, not a product.
- **Sentence case everywhere** in running text and headings. The only UPPERCASE
  is the stamped typewriter labels/eyebrows (`SELECTED PUBLICATIONS`,
  `01 — RESEARCH`), which are tracked out like a rubber stamp.
- **Handwritten asides.** Short margin notes in Kalam add personality next to
  headings: *"follow the qubits ↓"*, *"that's me ↖"*, *"pinned to the board"*.
  Use sparingly — one per section at most.
- **Punctuation as texture.** A single `✦`, `↘`, `→`, or `★` glyph is welcome as
  a drawn flourish. No emoji — the hand-drawn marks do that job.
- **Numbers stay honest.** Years, venues, and counts only. No invented metrics or
  vanity stats; a researcher's credibility is the papers, not a dashboard.
- **Length.** Hero bio ≈ 2–3 sentences. Research blurbs ≈ 1–2 sentences. CV
  details one line each. Brevity reads as confidence.

---

## Visual foundations

- **Colour.** Paper backgrounds (`--paper-0…3`, warm off-white → cream) with
  near-black navy **ink** for text (`--ink-900` `#1B2230`) and graphite **pencil**
  greys for meta. Accents are a small coloured-pencil set: **quantum blue is
  primary** (`--blue-500` `#3B6EA5`), with terracotta, sage, and amber as
  category colours. Highlighter washes (`--mark-amber/blue/sage`) sit behind
  inline emphasis. Keep colour scarce — mostly ink on paper, accent for one thing
  at a time.
- **Type.** Two voices. **Caveat** (handwritten) for display — the name, section
  headings, big years. **Courier Prime** (typewriter) for everything you read —
  body, UI, data. **Special Elite** stamps the UPPERCASE eyebrows/labels/badges.
  **Kalam** writes the margin notes. Display runs large (Caveat has a small
  x-height); body is 15–19px at 1.75 leading with plenty of air.
- **Borders & shape.** The signature move is the **wobbly border-radius** preset
  (`--sketch-radius-1/2/3`) on a 2px ink border — a box that looks drawn, not
  generated. Rotate which preset you use so repeated boxes don't look cloned.
  `IconButton`/`Avatar` use an organic **blob** radius. Uniform `border-radius`
  is kept tiny (2–8px); the character comes from the wobble.
- **Shadows.** Hard, slightly-transparent **doodle shadows** offset down-right
  (`--shadow-sketch*`) — paper lifted off the page, not a soft blur. `--shadow-lift`
  adds a faint ambient blur under the hard edge for hover.
- **Texture.** A faint SVG turbulence **paper grain** (`--paper-grain`) tiles over
  every paper surface at ~4% opacity. Never flat fills for large areas.
- **Backgrounds.** No photography, no gradients. Solid paper + grain, separated by
  drawn rules (`Divider` wave/dashed/dots) and a 2px paper-edge hairline between
  sections. Alternating `--paper-1` / `--paper-0` distinguishes bands.
- **Motion.** Organic, never linear. `--ease-hand` (slight overshoot) for hovers,
  `--ease-ink` for things that "draw in." Content **sketches in on scroll**
  (fade + 18px rise + a 0.4° rotate) via IntersectionObserver. Reduced-motion
  shows everything immediately. No infinite decorative loops.
- **Hover.** Buttons and cards **lift and tilt** (`translate(-1px,-1px) rotate(-0.6°)`);
  icon buttons rotate ~4° and scale up. **Press** pushes down and shrinks
  (`translate(1px,2px)`, smaller shadow) like pressing a stamp.
- **Focus.** A dashed terracotta outline offset 3px — visibly drawn, not a glow.
- **Corner radii / cards.** Cards = paper sheet: 2px ink border + wobble radius +
  doodle shadow + grain, optional `tilt` for a corkboard lean. That's the whole
  card system; don't invent flat rounded cards.
- **Transparency / blur.** Used once: the sticky nav uses `color-mix` paper at 88%
  + a 4px backdrop blur so content scrolls under it. Otherwise surfaces are
  opaque.
- **Imagery vibe.** When real photos arrive, treat them warm and slightly faded to
  sit on cream paper; frame portraits in the Avatar blob border.

---

## Iconography

- **Set: [Lucide](https://lucide.dev) line icons**, loaded from CDN
  (`unpkg.com/lucide@0.456.0`). Consistent 2px stroke pairs well with the
  typewriter body. **⚠️ Substitution:** no icon set was specified in the brief, so
  Lucide was chosen as a clean, open line-icon system — swap it if the real site
  uses something else.
- **Hand-drawn treatment.** Icons are wrapped in `.rough` and pushed through an
  SVG `feTurbulence` + `feDisplacementMap` filter (`#sk-roughen`, scale ≈ 1.6) so
  the clean Lucide strokes pick up a subtle drawn wobble. Use the `Icon` helper in
  the portfolio kit (`<Icon name="github" />`).
- **Drawn marks, not emoji.** Unicode flourishes (`✦ ★ → ↘ ↖`) are used as
  decorative pen-marks in headings and notes. **No emoji** anywhere — it breaks the
  ink-on-paper illusion.
- **Custom SVG primitives** in the system: the `Divider` squiggle, the `Checkbox`
  drawn tick, and the paper-grain — all generated, all part of the brand. Don't
  hand-roll *new* icon glyphs; reach for Lucide + the roughen filter instead.

---

## Index / manifest

**Root**
- `styles.css` — global entry point (consumers link this). `@import`s only.
- `readme.md` — this file.
- `SKILL.md` — Agent-Skill front-matter wrapper.

**`tokens/`** — CSS custom properties (all reachable from `styles.css`)
- `fonts.css` — Google Fonts `@import` (Caveat, Kalam, Special Elite, Courier Prime).
- `colors.css` — paper / ink / pencil / accents + semantic aliases.
- `typography.css` — families, scale, leading, tracking, semantic roles.
- `spacing.css` — space scale, containers, radii, z-index.
- `effects.css` — wobble radii, doodle shadows, paper grain, easings, sketch utility classes + keyframes.

**`guidelines/`** — foundation specimen cards (Design System tab)
- Colors: paper · ink & pencil · accents · highlighter marks
- Type: display · body · label & note · scale
- Spacing: scale · section rhythm
- Effects: borders · shadows · texture & underline

**`components/`** — reusable React primitives (namespace `window.SketchbookPortfolioDesignSystem_11295f`)
- `buttons/` — **Button**, **IconButton**
- `display/` — **Card**, **Badge**, **Tag**, **Divider**, **Avatar**
- `forms/` — **Input**, **Textarea**, **Checkbox**
- `navigation/` — **Tabs**

**`ui_kits/portfolio/`** — full single-page portfolio recreation
- `index.html` (interactive) + `kit.jsx`, `Nav`, `Hero`, `Research`, `Projects` (Quantum + AI), `Publications`, `Experience`, `Contact` (Footer).

*Generated by the compiler — do not edit:* `_ds_bundle.js`, `_ds_manifest.json`, `_adherence.oxlintrc.json`.
