# Git forges — Platform interface contract + per-forge reference

`config.git_platform` selects which forge the dispatcher talks to (`github` or
`gitlab`). It is **orthogonal to `worker_backend`**. Any combination is valid:
a GitLab board can dispatch `cursor-agent` workers; a GitHub board can use
`workflow`. `workflow` staying Claude-Code-only is a **backend** fact (see
`references/backends.md`), not a platform fact.

Dispatch scripts `source` `scripts/platforms/<git_platform>.sh` (installed as
`.supersaiyan/bin/platforms/<git_platform>.sh`). Callers never invoke `gh` or
`glab` directly for forge I/O.

## The Platform contract

Every `scripts/platforms/<name>.sh` file must define these functions. Signatures
below are **as implemented**, not the spec's first guesses.

| Function | Contract |
|---|---|
| `platform_auth_check [issue\|board]` | 0 if the CLI is authenticated for the mode; prints the exact login/refresh command on failure. |
| `platform_bot_identity_resolve` | Echo the login/username the dispatcher should claim as. |
| `platform_rate_remaining <resource>` | Echo remaining quota for `graphql` (or `core`). Missing signals print `unknown`, never `0`. |
| `platform_rate_guard <min>` | Sleep until reset if remaining `< min`. Fail-open (no-op) when remaining is non-numeric. |
| `platform_board_snapshot <config-path>` | Echo `{items:[{status, content:{type,number,title,body,url,repository,assignees[]}}]}`. GitHub also accepts `<number> <owner>`. |
| `platform_column_count <column> [snapshot]` | Count items whose `.status` equals the column. |
| `platform_top_unclaimed_card <column> [snapshot]` | First unassigned Issue number in that column. |
| `platform_card_status_set <issue> <column>` | Move the card. `--add <config> <url> <column>` enqueues a new issue onto Ready. |
| `platform_card_move_verify <issue> <column>` | GitLab: re-GET and require exactly one matching `status::*`. GitHub: no-op success. |
| `platform_claim_issue <issue> <bot>` | Claim for the bot. Refuse (exit 1) if another assignee is already present. |
| `platform_release_issue <issue> <bot>` | Drop the bot claim. |
| `platform_issue_create <title> <body-file>` | Echo the new issue URL. |
| `platform_issue_view <issue>` | Normalized `{number,title,body,labels:string[],state:OPEN\|CLOSED}`. Exits `0/44/69/70`. |
| `platform_issue_comment <issue> <body>` | Add a comment/note. |
| `platform_issue_close <issue> [note]` | Close, optionally with a note. |
| `platform_issue_edit_labels <issue> [--add-label\|--remove-label] <name>` | Add or remove one label. |
| `platform_mr_create_draft --base --head --title --body-file` | Open a draft MR/PR. Echo the URL. |
| `platform_mr_mark_ready <iid>` | Mark the draft ready. |
| `platform_mr_comment <iid> <body>` | Comment on the MR/PR. |
| `platform_mr_merge_squash <iid>` | Squash-merge and delete the source branch. |
| `platform_mr_view <iid>` | Echo MR/PR JSON. |
| `platform_mr_list_by_branch <branch>` | Echo MRs/PRs whose source/head is that branch. |
| `platform_thread_list_unresolved <iid>` | Echo unresolved **review** thread ids (not plain top-level notes). |
| `platform_thread_resolve <id>` | Resolve one thread. Idempotent. |
| `platform_thread_create <iid> <path> <line> <body>` | Start a line-level review discussion. |
| `platform_detect_production_ci <root>` | 0 if CI/hosting looks like production. |
| `platform_detect_branch_protection [base]` | 0 if `base` (default `main`) is protected. |
| `platform_raw_file_url <owner/repo> <branch> <path>` | Echo a raw-file URL for screenshot embeds. |
| `platform_repo_create …` | Forward to `gh repo create` / `glab repo create`. |
| `platform_label_ensure <name> [color] [description]` | Idempotent label create. |
| `platform_board_ensure …` | GitHub: validate Status options. GitLab: create `status::*` labels + board lists; print `board_id` or `null`. |

GitLab-only helper (Open Judgment Call 4 — single status projection):

| Function | Contract |
|---|---|
| `platform_gitlab_status_from_labels` | stdin or `$1` = JSON label array → one column name (`Ready`… / `Backlog`). |
| `platform_gitlab_label_from_status` | Inverse: `Ready` → `status::ready`. `Backlog` → empty. |

## GitHub (`scripts/platforms/github.sh`)

Verified against `gh`. Config keys: `project.owner`, `project.number`, `project.title`.

- Auth: `gh auth status`; `issue` needs `repo`, `board` needs `repo` + `project`.
- Snapshot: `gh project item-list` / GraphQL `repositoryOwner.projectV2.items`. `.status` is the Status single-select.
- Card move: `gh project item-edit --field-id --single-select-option-id`. `--add` uses `gh project item-add` then the same edit.
- Claim: `gh issue edit N --add-assignee`. Release: `--remove-assignee`.
- Issues: `gh issue create --title --body-file`; `gh issue view --json`; `gh issue comment`; `gh issue close --comment`; `gh issue edit --add-label/--remove-label`.
- PRs: `gh pr create --draft --base --head --title --body-file`; `gh pr ready`; `gh pr comment`; `gh pr merge --squash --delete-branch`; `gh pr view`; `gh pr list --search "head:<branch>"`.
- Threads: GraphQL `pullRequest.reviewThreads` (`isResolved:false`); `resolveReviewThread`; create via the pull-request review API.
- CI: `.github/workflows/*.yml` deploy-on-push-to-base, plus `vercel.json` / `netlify.toml`.
- Raw URL: `https://github.com/<OWNER>/<REPO>/raw/<BRANCH>/<path>`.
- Board ensure: validate Status field options; echo project/field/option ids.

## GitLab (`scripts/platforms/gitlab.sh`)

Verified against `glab` on gitlab.com. Config keys: `project.host`, `project.full_path`, `project.board_id`. Every mutating call needs `PLATFORM_CONFIG_PATH` (or a config-path argument) so `glab -R <full_path>` can run from a non-git cwd — a GitHub-origin SuperSaiyan checkout otherwise makes `glab` refuse GitLab targets.

- Auth: `glab auth status`. PAT needs `api` + `write_repository`. OAuth/session needs Developer+ (`access_level >= 30`) on the target project.
- Rate: `glab api user --include`; parse `RateLimit-*` headers. Absent → `unknown`; guards fail-open.
- Snapshot: paginated `GET projects/:id/issues?scope=all`. `.status` from the first `status::*` label via `platform_gitlab_status_from_labels` (zero matches → `Backlog`).
- Card move: combined PUT `remove_labels=status::OLD` + `add_labels=status::NEW`, then `platform_card_move_verify` (exactly one `status::*`). One two-step retry on mismatch. `--add <config> <url> <column>` parses the iid from the last path segment (`issues/N` or `work_items/N`) and does the same move — GitLab issues are on the board the moment they exist.
- Claim: GET assignees first; refuse if any username ≠ bot; write `assignee_ids[]=<id>` only (never `assignee_ids=1,2`). Release: `assignee_ids=0` (empty `assignee_ids[]=` is HTTP 400). Open Judgment Call 3: release evicts co-assignees.
- Issues: `glab issue create --title --description --yes` (no `--description-file`); REST view + normalize; `glab issue note`; note then `issue close`; `--label` / `--unlabel`.
- MRs: `glab mr create --draft` (never `--wip`); map `--base`→`--target-branch`, `--head`→`--source-branch`; `mr update --ready`; `mr note create`; `mr merge --squash --remove-source-branch --yes`.
- Threads: GraphQL `mergeRequest.discussions`, keep `resolved==false` AND `notes[0].resolvable==true`. Resolve: `discussionToggleResolve` (idempotent). Create: form-encoded `POST .../discussions` with `position[base_sha|start_sha|head_sha|old_path|new_path|position_type=text]` and `-F position[new_line]=N` (JSON body 400s on `line_code`). SHAs from `merge_request.diff_refs`.
- Block signal (Open Judgment Call 5): a **non-resolvable** top-level MR note with no `[QA]` / `[Review]` / lane prefix, whose author is not `notifications.bot_identity`. Resolvable discussions stay Gate 1 review threads.
- CI: `.gitlab-ci.yml` job with `environment:` plus `CI_COMMIT_BRANCH == "main"` or `$CI_DEFAULT_BRANCH`; one level of local `include:`; plus `vercel.json` / `netlify.toml`.
- Protection: `GET projects/:id/protected_branches/<base>`.
- Raw URL: `https://<host>/<full_path>/-/raw/<branch>/<path>` — host from config, never hardcoded `gitlab.com`.
- Labels: `GET .../labels` then `POST` if missing (do not suppress-and-ignore).
- Board ensure: create the seven (or six) `status::*` labels; `POST .../boards`; `POST .../boards/:id/lists` in board order; write `project.board_id`. On API failure print GitLab UI steps and continue with `board_id: null`. `GITLAB_BOARD_ENSURE_FAIL=1` forces that path.

## Status renderer

`scripts/platforms/status_adapter.py` is the Python companion: `GithubStatusAdapter` vs
`GitlabStatusAdapter`, chosen by `get_status_adapter(git_platform, config)`.
GitLab paginates `project(fullPath:) { issues { … } }` itself — it does **not**
reuse `paginate_items()` (that helper is hardcoded to GitHub Project V2).
Column names still come from `platform_gitlab_status_from_labels`.
