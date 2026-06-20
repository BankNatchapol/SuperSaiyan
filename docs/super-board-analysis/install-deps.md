# External Dependencies Install Status

super-board references [superpowers](https://github.com/obra/superpowers) and [gstack](https://github.com/garrytan/gstack) but does **not** bundle them.

## super-board (core)

**Status:** Installed

```bash
./super-board/install.sh /Users/bank.p/Documents/SuperSaiyan
```

Outputs:

- `.claude/skills/super-board`, `super-build`, `super-qa`, `super-review`
- `.claude/bin/super-board-*.sh`, `super-board-status.py`
- `.claude/workflows/super-board-wave.js`

## superpowers

**Status:** Cloned to `superpowers/`; plugin install required for runtime `superpowers:*` skill names

super-board workers invoke skills like:

- `superpowers:test-driven-development`
- `superpowers:verification-before-completion`
- `superpowers:systematic-debugging`
- `superpowers:using-superpowers`

The `superpowers:` prefix comes from the **Claude Code plugin**, not from copying skill folders alone.

**Recommended install (Claude Code):**

```
/plugin install superpowers@claude-plugins-official
```

Or marketplace:

```
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

**Also supports:** Cursor (`/add-plugin superpowers`), Codex (official plugin marketplace), and others — see `superpowers/README.md`.

**Where referenced in super-board:**

| File | Usage |
|------|-------|
| `skills/super-build/references/worker-preamble.md` | Default skills before coding |
| `skills/super-qa/SKILL.md` | Skill dependencies section |
| `skills/super-board/references/run.md` | Spec path `docs/superpowers/specs/...` |

## gstack

**Status:** Cloned to `gstack/`; symlinked to `.claude/skills/gstack`; full setup pending Bun

**Symlink:**

```bash
ln -snf /Users/bank.p/Documents/SuperSaiyan/gstack /Users/bank.p/Documents/SuperSaiyan/.claude/skills/gstack
```

**Full setup (registers slash commands, builds browse):**

```bash
# Requires Bun 1.0+
cd gstack && ./setup
```

gstack `./setup` failed in this environment because Bun is not installed. Install Bun per https://bun.sh, then re-run `./setup`.

**Where referenced in super-board:**

| File | Usage |
|------|-------|
| `skills/super-build/references/worker-preamble.md` | `/plan-ceo-review`, `/plan-eng-review`, `/cso`, `/plan-design-review` |
| `skills/super-build/references/gstack-voting.md` | Vote protocol + `--- gstack-vote ---` commit trailer |
| `skills/super-build/SKILL.md` | gstack advisors on decision points |

gstack is **Builder-lane only**. QA and Review do not call gstack.

## Optional: spec directory

Eric's projects use:

```
docs/superpowers/specs/2026-05-21-super-board-design.md
```

Create in your target app repo if you follow spec-driven development. super-board's `run.md` points here as design source of truth.

## Verification script

```bash
./scripts/verify-super-board-setup.sh
```
