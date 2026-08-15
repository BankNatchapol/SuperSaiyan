# GitLab e2e evidence — issues #15 and #16

Sandbox project: [BankNatchapol/supersaiyan-gitlab-sandbox](https://gitlab.com/BankNatchapol/supersaiyan-gitlab-sandbox)

Onboard-only empty project (issue #13): [BankNatchapol/supersaiyan-gitlab-onboard](https://gitlab.com/BankNatchapol/supersaiyan-gitlab-onboard) (`board_id` 11532821)

## #15 — `tasks-to-issues.sh --board`

Config: `sandbox.json` in this directory (`git_platform: gitlab`, `full_path: BankNatchapol/supersaiyan-gitlab-sandbox`, `board_id: 11532822`).

```bash
platform_board_ensure docs/super-board/runs/issue-7-16-gitlab-e2e/sandbox.json
./scripts/tasks-to-issues.sh \
  docs/superpowers/tasks/gitlab-e2e-smoke/01-add-health-file.md \
  --config docs/super-board/runs/issue-7-16-gitlab-e2e/sandbox.json \
  --board
```

| Field | Value |
|---|---|
| Issue iid | **10** |
| URL | https://gitlab.com/BankNatchapol/supersaiyan-gitlab-sandbox/-/work_items/10 |
| Labels | `status::ready` |
| Board | SuperSaiyan `11532822` Ready list `25541684` |
| Map | `docs/superpowers/tasks/gitlab-e2e-smoke/.issue-map.json` |

GraphQL confirmation that iid 10 sits on the Ready list (not just the PUT):

```text
project.board(id: gid://gitlab/Board/11532822)
  lists(id: gid://gitlab/List/25541684)
    title: status::ready
    issues: #1, #8, #10  ("Add HEALTH.md with ok")
```

`glab issue create` returned a `/-/work_items/10` URL. `tasks-to-issues.sh` now takes the last path segment (`${url##*/}`) so both `issues/N` and `work_items/N` parse.

## #16 — live `super-board-run.sh`

Local clone (not in this repo): `/Users/banknatchapol/Desktop/Codes/supersaiyan-gitlab-sandbox`  
Config: `git_platform: gitlab`, `worker_backend: cursor-agent`, `human_approves_merge: false`, `notifications.bot_identity: BankNatchapol`.

| Stage | Evidence |
|---|---|
| Builder draft MR | [MR !3](https://gitlab.com/BankNatchapol/supersaiyan-gitlab-sandbox/-/merge_requests/3) `Draft: Add HEALTH.md with ok (#10)` |
| Tester | Card moved to `status::qa`; `[QA]` lane owned the card |
| Reviewer squash-merge | MR !3 `state: merged`, `squash: true`, draft cleared |
| Independent re-GET | `issue-10.json`: `state: closed`, labels `["status::done"]` |
| `HEALTH.md` on `main` | contents `ok\n` (base64 `b2sK`) |
| Concurrent write | `concurrent-write.txt` — `#2` → Blocked, exactly one `status::*` |
| Manifest | `run-16-manifest.md` — Build 14:26:32 → QA 14:28:56 → Review 14:32:21 → exit 14:36:42 |

Dispatcher fixes needed for this run (in this PR): `platform_board_snapshot "$CONFIG_PATH"`, rate-guard fail-open on `unknown`, `export PLATFORM_CONFIG_PATH`, claim via `glab issue update --assignee` (work_items reject `assignee_ids[]=`), active-lane counts ignore CLOSED leftovers.
