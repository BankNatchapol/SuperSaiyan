# SuperSaiyan

End-to-end AI development pipeline. **Idea → merged PR with one command set.**

```
/supersaiyan new <feature>    ← brainstorm + spec + tasks + queue
/supersaiyan run              ← autonomous Build → QA → Review
```

No context-switching between tools. No 20-step setup guide.

---

## Install

**Plugin (recommended — global, works in any repo):**

```bash
claude plugin marketplace add github:BankNatchapol/SuperSaiyan
claude plugin install supersaiyan
```

**Direct install into a specific repo:**

```bash
git clone https://github.com/BankNatchapol/SuperSaiyan.git
SuperSaiyan/install.sh /path/to/your-app
```

Requires: [Claude Code](https://claude.ai/code), [GitHub CLI](https://cli.github.com), Git.

---

## Use

```bash
claude /path/to/your-app

/supersaiyan setup            # one-time: GitHub Project + board config
/supersaiyan new my-feature   # define + spec + tasks + prepare
/supersaiyan run              # autonomous loop until board is empty
```

Full guide: [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md)

---

## Optional desktop control center

The macOS-first Electron app provides repository diagnostics, a safe GitHub
Project board, feature/run views, and persistent terminals. It invokes the
same `/supersaiyan` commands; the skills remain fully usable without it.

```bash
npm install
npm start
```

Create a local macOS package with `npm run package:mac`. The interface follows
the extracted Aura Console design reference in
[`design/dashboard-control-center/`](design/dashboard-control-center/).

---

## How it works

```
/supersaiyan new <feature>
  ├── Explore codebase
  ├── Ask 3–5 questions
  ├── Write spec → docs/superpowers/specs/<slug>-design.md
  ├── Propose task breakdown (you approve)
  ├── Write task files → docs/superpowers/tasks/<slug>/NN-*.md
  ├── Commit + push
  └── File GitHub issues → Ready queue + lint

/supersaiyan run
  ├── Builder agent → branch + code + draft PR
  ├── QA agent → tests + evidence
  └── Reviewer agent → reruns tests + merge readiness
```

---

## All commands

| Command | What |
|---------|------|
| `/supersaiyan setup` | One-time init: docs layout + GitHub Project + board config |
| `/supersaiyan new <feature>` | Full define-to-prepare pipeline |
| `/supersaiyan prepare <feature>` | Re-sync issues without redefining |
| `/supersaiyan run [slug]` | Start autonomous loop |
| `/supersaiyan status [slug]` | Board snapshot |
| `/supersaiyan lint` | Pre-flight check |
| `/supersaiyan stop` | Graceful shutdown |

---

## What's bundled

SuperSaiyan is self-contained — no separate tool installs required:

| Component | Role |
|-----------|------|
| `skills/supersaiyan/` | Primary command (`/supersaiyan`) |
| `skills/super-board/` | Board orchestrator (pipeline backbone) |
| `skills/super-build/` | Builder lane agent |
| `skills/super-qa/` | QA lane agent |
| `skills/super-review/` | Reviewer lane agent |
| `skills/refining-spec/` | Design → technical spec |
| `skills/writing-board-tasks/` | Spec → PR-sized task files |

---

## Inspired by

- [super-board](https://github.com/EricTechPro/super-board) by Eric Tech — autonomous board executor that moves cards through Build → QA → Review
- [gstack](https://github.com/garrytan/gstack) by Garry Tan — office-hours, spec, review, and ship discipline
- [superpowers](https://github.com/obra/superpowers) by obra — TDD, verification, and composable skill methodology
- [get-shit-done](https://github.com/gsd-build/get-shit-done) — opinionated workflow loop that keeps agents on track

---

## Test without GitHub

```bash
./tests/test-supersaiyan-prepare.sh
```
