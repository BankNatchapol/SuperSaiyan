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
claude plugin install github:BankNatchapol/SuperSaiyan
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

The upstream sources (`super-board/`, `superpowers/`, `gstack/`) are vendored
here for reference and future updates.

---

## For contributors / deep dive

| Doc | Purpose |
|-----|---------|
| [docs/super-board-analysis/idea-to-merged-playbook.md](docs/super-board-analysis/idea-to-merged-playbook.md) | Full pipeline architecture |
| [docs/super-board-analysis/plan-to-issues-bridge.md](docs/super-board-analysis/plan-to-issues-bridge.md) | Issue creation strategy |
| [docs/super-board-analysis/card-lifecycle-thesis-notes.md](docs/super-board-analysis/card-lifecycle-thesis-notes.md) | One card through Build → QA → Review |
| [AGENTS.md](AGENTS.md) | Agent handoff reference |

---

## Test without GitHub

```bash
bash super-board/tests/test-wave-plan.sh
./tests/test-supersaiyan-prepare.sh
```
