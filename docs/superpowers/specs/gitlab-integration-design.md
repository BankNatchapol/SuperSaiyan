# GitLab integration — design spec

Status: draft, ready for board-task decomposition.

## Why

SuperSaiyan's autonomous Build → QA → Review pipeline currently only drives GitHub. Every
dispatcher, the wave planner, the status renderer, onboarding, and every skill doc's
review-thread/label/CI logic is written directly against `gh`/GitHub's API. The goal is
feature parity on GitLab, added as an orthogonal platform choice — not a fork, not a
GitHub-only-with-GitLab-bolted-on compromise.

This spec was produced from three research passes (GitHub-CLI touchpoint inventory across
`scripts/`, GitHub-concept inventory across `skills/*/references/*.md`, and sourced research
into GitLab's actual current primitives) plus a dedicated architecture-design pass. It is the
`design:` input for `writing-board-tasks`-style task decomposition — see
`docs/superpowers/tasks/gitlab-integration/`.

## Requirements

1. A `git_platform: "github" | "gitlab"` config dimension, orthogonal to the existing
   `worker_backend: "workflow" | "claude-p" | "codex-exec" | "cursor-agent"` — any combination
   is valid (GitLab has no special affinity for one worker CLI over another; the
   Codex/Cursor "no Skill/Task tool" constraint is about Claude-Code-specific tooling, not the
   forge).
2. Every operation the pipeline currently performs against GitHub must have a GitLab
   equivalent behind the same abstraction: board read, board write (card/column move), issue
   claim/release (the assignee-mutex pattern), issue CRUD, MR CRUD (GitLab's PR equivalent),
   review-thread resolve, production/CI detection, and the raw-file-URL scheme used for
   inline screenshot embeds.
3. **Board-state model.** GitHub Projects v2's queryable/writable single-select "Status"
   field has **no GitLab equivalent** — confirmed via sourced research: GitLab Issue Boards
   are label-backed (a board list = one label; moving a card = adding/removing that label).
   GitLab's newer Work Items "Custom Fields" (Premium/Ultimate only, group-scoped not
   board-scoped, write-mutation API unconfirmed to exist cleanly) is not a fit. **Decision:**
   use GitLab **scoped labels** — labels sharing a `key::value` prefix are mutually exclusive
   per scope on an issue, and GitLab's own Issue Boards natively render one list per label
   including scoped labels. This reproduces single-select-field semantics using GitLab's own
   intended mechanism, no custom UI required: `status::ready`, `status::building` (full
   variant only), `status::qa`, `status::review`, `status::done`, `status::blocked`,
   `status::skipped`. No label at all = Backlog (GitLab's board UI shows an automatic
   unlabeled "Open" list for this, for free).
4. **This board-state model introduces a real race condition GitHub's never had.** GitLab has
   a confirmed, currently open bug — *"Adding scoped labels via the API does not always
   remove existing scoped labels"* ([gitlab-org/gitlab#207269](https://gitlab.com/gitlab-org/gitlab/-/issues/207269))
   — where concurrent scoped-label mutations on the same issue can leave stale or duplicate
   `status::*` labels, even within a single combined add/remove request. Any card-move
   implementation MUST verify the result (read-after-write) and retry, not trust the mutation
   response. This is the single highest-risk piece of this spec.

## Architecture

### Precedent to mirror

This repo already has an equivalent abstraction for worker-CLI choice — study it, don't
reinvent the shape:
- `skills/super-board/references/backends.md` — documents a 6-function shell contract.
- `scripts/backends/{claude-p,codex-exec,cursor-agent}.sh` — one file per backend, sourced
  (not executed) by dispatch scripts.
- `config-schema.json`'s `worker_backend` field selects which one to source.
- `scripts/super-board-run.sh` sources `.claude/bin/backends/${WORKER_BACKEND}.sh` (installed)
  or `scripts/backends/` (dev), `BASH_SOURCE`-relative, after a case-statement validating the
  value.
- `scripts/generate-supersaiyan-references.sh` keeps `skills/super-board/references/*` and
  `skills/supersaiyan/references/*` in sync from one canonical source.

The platform abstraction follows the identical shape: `scripts/platforms/{github,gitlab}.sh`,
`config.git_platform` selects which is sourced, a new `references/platforms.md` (backends.md
-shaped) documents the contract, and it's added to the generator's file list.

**One structural difference from the worker-backend precedent:** `worker_backend` is only
consumed by dispatcher scripts. GitHub calls are NOT confined to the dispatcher layer —
workers themselves issue raw `gh`/`gh api graphql` commands directly from skill-doc prose
(e.g. `run.md`'s `resolveReviewThread` mutation, `block-template.md`'s `gh issue close`,
`super-build/SKILL.md`'s inline GraphQL). The platform contract must be sourced by **every
lane worker at lifecycle start** (the same way `run.md` already tells every worker to
`source scripts/super-board-gh-guard.sh`), and every skill doc must be rewritten to reference
`platform_*` operations, never literal `gh`/`glab`. This is the highest-blast-radius task in
the decomposition (board task 05).

`scripts/super-board-status.py` is pure Python and cannot `source` a bash file — it needs a
parallel Python-side adapter (`scripts/platforms/status_adapter.py`, a `PlatformAdapter`
interface with `GithubStatusAdapter`/`GitlabStatusAdapter` implementations).

### Platform interface contract

Every function prefixed `platform_`. Contract-checked by a new `tests/test-platform-contract.sh`
mirroring the existing `tests/test-backend-contract.sh`.

**Group A — Auth & identity**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_auth_check issue|board` | `issue` requires `repo` scope plus access to the target repository; `board` additionally requires `project` | `issue` requires repository API access; `board` additionally requires board-write capability (`api`,`write_repository`) |
| `platform_bot_identity_resolve` | GitHub App install vs. personal login | Project/Group Access Token → auto-created bot user (`project_<id>_bot_<random>`) vs. personal token |

The auth argument is an operation-level requirement, not a platform selection signal.
No argument defaults to `issue` for backward compatibility. Standalone issue creation passes
`issue`; board enqueue/reconciliation passes `board` and fails before mutation when the required
capability is absent. GitHub's `project` OAuth scope includes Project read and write access, so a
separate `read:project` scope is not required alongside it.

**Group B — Rate limit / quota**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_rate_remaining <resource>` | `gh api rate_limit` JSON (`graphql`/`core` buckets) | No dedicated endpoint. Probe a cheap REST call (`glab api user --include`, not GraphQL — GraphQL responses sometimes omit these headers) and parse `RateLimit-Remaining`/`RateLimit-Reset`/`RateLimit-Limit` response headers. Confirmed flaky presence ([gitlab-org/gitlab#365728](https://gitlab.com/gitlab-org/gitlab/-/issues/365728), [#352409](https://gitlab.com/gitlab-org/gitlab/-/issues/352409)) — absent headers mean "unknown," never "zero remaining." |
| `platform_rate_guard <min>` | sleeps until reset if below threshold | same, but MUST fail open (no-op) when headers are absent — required for self-hosted instances that may not expose them at all |

GitHub has two quota buckets (graphql/core); GitLab effectively has one per-endpoint-family
number. `super-board-gh-guard.sh`'s worker-local soft-budget concept (`sb_gh_budget_*`) is
platform-agnostic and needs no change; only the remote-quota-check half collapses to the
simpler model on GitLab.

**Group C — Board read**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_board_snapshot <project-ref>` → normalized `{number,title,url,state,repository,assignees[],labels[],status}[]` | `gh project item-list` / hand-written `ITEMS_QUERY` GraphQL; `.status` = single-select field value | Paginated REST (`/projects/:id/issues?scope=all&per_page=100`) or GraphQL, returning `labels[]`; **`.status` is derived client-side inside this one function** by scanning labels for the `status::` scope prefix (first/only match; zero matches → `"Backlog"`). This derivation must live in exactly one place so the dispatcher, wave-plan, and status renderer never disagree. |
| `platform_column_count`, `platform_top_unclaimed_card` | unchanged shape | unchanged shape once `.status` is normalized — `super-board-wave-plan.sh`'s jq pipeline (`Depends on: #N` resolution, `.content.repository`/`.status=="Done"` cross-reference) needs zero changes if this normalization is correct, since it already treats `.status`/`.content.*` as opaque fields |

**Group D — Board write / move-card (the critical gap — see Requirement 4)**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_card_status_set <issue> <target-status>` | `gh project item-edit --field-id --single-select-option-id` — one mutation, single-select semantics | Combined PUT: `glab api "projects/:id/issues/:iid" --method PUT -f "remove_labels=status::OLD" -f "add_labels=status::NEW"` (GitLab's Issues API accepts both in one request) |
| `platform_card_move_verify <issue> <expected-status>` | not needed | **New, GitLab-only.** Re-GET the issue's labels immediately after the PUT; confirm exactly one `status::*` label matches. |

Sequence required: (1) send the combined PUT, (2) call `platform_card_move_verify`, (3) on
mismatch, retry once with an explicit two-step remove-then-add (remove confirmed via its own
verify before the add fires), (4) on continued failure, return non-zero — `run.md`'s existing
"Known issue — multi-attempt card moves" retry-and-another-worker-picks-it-up safety net
already absorbs this; no new halt-gate is needed.

**The read-side race, made concrete:** between the label-remove and label-add, a concurrent
`platform_board_snapshot` could observe the card with zero `status::` labels — a state
GitHub's atomic single-select mutation has no equivalent for. Practically: the dispatcher
re-fetches every tick, so a card caught mid-mutation is picked up correctly one tick later —
"one tick of undercounting," not corruption — but every caller keying logic off "count of
cards in column X" must be told (in `platforms.md` and `run.md`'s per-tick section) that a
zero-`status::`-label card during an active run is ambiguous, not confidently "Backlog."

**Group E — Claim / release mutex**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_claim_issue <issue> <bot>` | `gh issue edit N --add-assignee <bot>` — additive to existing assignees | `glab api "projects/:id/issues/:iid" --method PUT -f "assignee_ids[]=<bot-user-id>"` — GitLab's assignee update **replaces** the whole set, it does not add. Never use the comma-joined form `assignee_ids=1,2` (confirmed broken: `{"error":"assignee_ids is invalid"}`, [gitlab-org/gitlab-foss#59302](https://gitlab.com/gitlab-org/gitlab-foss/-/issues/59302)) — always a single-element array (or the `glab issue update <iid> --assignee <user>` wrapper). Because it's replace-not-add, claiming MUST first read current assignees and refuse (return 1, "already claimed") if any non-bot assignee is present — otherwise it silently evicts a human who self-assigned. |
| `platform_release_issue <issue> <bot>` | `--remove-assignee` | PUT with empty `assignee_ids[]=` — same replace-semantics caveat: if a human added themselves as a second assignee while the bot held the claim, release evicts them too. Accepted limitation (open judgment call), not engineered around. |

Neither platform's assignee-write API is a true compare-and-swap against "currently empty" —
this repo's actual mutex safety today already comes from defense-in-depth (`run.md`'s
"Anti-zombie addendum": single-threaded dispatcher tick, snapshot-filtered candidates, local
inflight lock files), not GitHub API atomicity. GitLab needs the identical defense-in-depth,
plus the one addition above given documented flakiness of concurrent label/assignee mutations.

**Group F — Issue CRUD**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_issue_create` | `gh issue create --title --body-file` | `glab issue create --title "<t>" --description-file <f>` |
| `platform_issue_view <issue>` → normalized `{number,title,body,labels:string[],state}` with `state` in `OPEN|CLOSED` | `gh issue view N --json number,title,body,labels,state`, projecting label objects to their names | `glab api "projects/:id/issues/:iid"` followed inside the adapter by normalization from `iid`/`description`/lowercase `state` (raw REST is still the source, for the same machine-parsing reason `super-board-status.py` already prefers raw GraphQL over `gh project item-list`'s formatted output) |
| `platform_issue_comment` | `gh issue comment N --body` | `glab issue note <iid> -m "<body>"` (GitLab calls comments "notes") |
| `platform_issue_close` | `gh issue close N --comment "<c>"` | `glab issue close <iid> --note "<c>"` — clean 1:1 |
| `platform_issue_edit_labels` | `gh issue edit N --add-label a,b --remove-label c` | `glab issue update <iid> --label "a,b" --unlabel "c"` |

For callers whose public signature is only `platform_issue_view <issue>`, the
selected adapter receives the project context through the exported
`PLATFORM_CONFIG_PATH` environment variable. It points to the same config file
used to select the adapter; adapters must resolve forge-specific project
coordinates from that file and still return the normalized shape above.

`platform_issue_view` has normalized exits as well as normalized JSON: `0` means found, `44`
means a confirmed 404/not-found response, `69` means authentication or permission failure, and
`70` means network/API failure or malformed output. A caller may treat an issue as deleted only
after `44`; all other failures must preserve local state.

### Issue #4 delivery contract

The task, issue, PR, and QA evidence use these same seven acceptance criteria:

1. **AC1 — Adapter-specific Ready enqueue:** explicit board filing resolves forge-specific Ready
   metadata and uses `platform_card_status_set --add`.
2. **AC2 — Platform board snapshot:** wave planning uses `platform_board_snapshot` without
   changing dependency parsing.
3. **AC3 — Normalized issue view:** dispatch and prepare consume normalized issue JSON with the
   selected config exported as context.
4. **AC4 — Prepare regression coverage:** all existing nine prepare scenarios pass.
5. **AC5 — Explicit board intent:** direct task filing is issue-only by default; only `--board`
   enables board authentication and enqueue, and prepare supplies it.
6. **AC6 — Strict shared config resolution:** task filing, dispatch, and prepare share one
   Bash 3.2-compatible resolver and reject stale, ambiguous, missing, unsupported, or conflicting
   selections before adapter use.
7. **AC7 — Auth and lookup safety:** issue/board capabilities are checked explicitly, lookup
   exits are normalized, and issue-map deletion occurs only after confirmed not-found.

**Group G — MR/PR CRUD**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_mr_create_draft` | `gh pr create --draft --base --head --title --body-file` | `glab mr create --draft --source-branch --target-branch --title --description-file` (use `--draft`, not `--wip` — removed in GitLab 14.8) |
| `platform_mr_mark_ready` | `gh pr ready N` | `glab mr update <iid> --ready` |
| `platform_mr_comment` | `gh pr comment N --body` | `glab mr note <iid> -m "<body>"` |
| `platform_mr_merge_squash` | `gh pr merge N --squash --delete-branch` | `glab mr merge <iid> --squash --remove-source-branch` |
| `platform_mr_view` / `platform_mr_list_by_branch` | `gh pr view` / `gh pr list --search "head:<branch>"` | `glab api "projects/:id/merge_requests/:iid"` / `glab api "projects/:id/merge_requests?source_branch=<branch>"` |

**Group H — Review-thread resolve/create**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_thread_list_unresolved` | `gh api graphql` over `pullRequest.reviewThreads`, filtering `isResolved:false` | `glab api graphql` over `mergeRequest.discussions`, filtering non-resolved AND `notes[0].resolvable:true` — GitLab's "discussion" is broader than GitHub's "review thread" (also covers plain top-level comments), so this filter is required to match GitHub's semantics |
| `platform_thread_resolve` | `resolveReviewThread(input:{threadId})` mutation | `discussionToggleResolve(input:{id, resolve:true})` — confirmed idempotent, the cleanest mapping in the whole surface |
| `platform_thread_create` | (not a literal command anywhere in the current codebase — needs its own verification regardless of platform) | `POST /projects/:id/merge_requests/:iid/discussions` (or GraphQL `createDiffNote`), requiring a 4-field SHA `position` object (`base_sha`/`head_sha`/`start_sha`/`new_path`/`new_line`) — more ceremony than GitHub's commit_id+path+line. **The fiddliest mapping in this spec** — budget an investigation spike against a real sandbox, not a copy-paste implementation. |

**Group I — Production/CI detection**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_detect_production_ci` | `rg` on `.github/workflows/*.yml` for `on: push: branches: main` + a deploy job, plus `vercel.json`/`netlify.toml` (unchanged on both platforms) | `rg` on `.gitlab-ci.yml` for a job block containing `environment:` (often `name: production`) AND `rules: - if: '$CI_COMMIT_BRANCH == "main"'` (or `== $CI_DEFAULT_BRANCH`) — a structurally different pattern, not a string swap. GitLab CI is a single file that may `include:` others (local paths) — a thorough implementation resolves local includes. |
| `platform_detect_branch_protection` | `gh api repos/.../branches/<base>/protection` | `glab api "projects/:id/protected_branches/<base>"` |

**Group J — Raw-URL screenshot embed**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_raw_file_url` | `https://github.com/<OWNER>/<REPO>/raw/<BRANCH>/<path>` | `https://<HOST>/<GROUP>/<PROJECT>/-/raw/<BRANCH>/<path>` — note the `-/raw/` path segment; `<HOST>` must come from `config.project.host` (self-hosted), never hardcoded `gitlab.com` |

**Group K — Repo/label/board bootstrap (onboarding-time)**

| Function | GitHub | GitLab |
|---|---|---|
| `platform_repo_create` | `gh repo create` | `glab repo create` |
| `platform_label_ensure` | `gh label create <name> --color --description 2>/dev/null \|\| true` | `glab label create <name> --color --description` — needs a `glab label list` pre-check rather than suppress-and-ignore (idempotent-on-duplicate behavior needs confirming during implementation) |
| `platform_board_ensure` | validate/create Status field options | see Recommended Approach below — fully scriptable via raw `glab api` |

### Config schema

```jsonc
// Which forge this config drives. "github" (default, back-compat) or "gitlab".
// Orthogonal to worker_backend. See references/platforms.md.
"git_platform": "github",

"project": {
  "owner": "<github-owner>",        // github only
  "number": 0,                      // github only — ProjectV2 number
  "title": "<project title>",       // both
  "host": "gitlab.com",             // gitlab only — self-hosted support
  "full_path": "<group>/<project>", // gitlab only
  "board_id": 0                     // gitlab only — from POST .../boards
}
```

Flat optional fields on `project` (minimal diff to existing config-reading code) rather than
a nested `project.gitlab{}` sub-object — see Open Judgment Call 8 for the alternative.

## Recommended Approach

### Onboarding (`skills/super-board/references/onboard.md`)

- New question alongside the existing "which tool(s)" step: *"Is this board driven by a
  GitHub repo or a GitLab project?"* Default: detect from `git remote get-url origin` host;
  only ask if ambiguous (matches onboard's existing "detect first" rule).
- Auth step becomes platform-conditional: GitLab branch is `glab auth status`, scope check
  `api`+`write_repository`, remediation `glab auth login` (with `--hostname` for self-hosted).
- Project/columns step becomes "PICK OR CREATE BOARD" / "VALIDATE OR CREATE STATUS LABELS."
  **GitLab board auto-provisioning IS fully scriptable** (reversing an earlier assumption) —
  no `glab` subcommand wraps it, so this goes through raw `glab api`:
  1. Ensure repo exists.
  2. Create/ensure the `status::*` scoped labels (need their numeric ids for step 4).
  3. `glab api -X POST "projects/:id/boards" -f name="<title>"` → returns `board_id`.
  4. For each status value, in board order: `glab api -X POST "projects/:id/boards/:board_id/lists" -f label_id=<id>`.
     List order is creation order, correctable post-hoc via `PUT .../lists/:list_id -f position=<n>`.
  5. Store `board_id` in the config.
  Free-tier-scriptable for one board per project (Premium/Ultimate gating only applies to
  *multiple* boards per project — never needed here).
- Base-branch/production-detection step swaps the `.github/workflows` grep for the
  `.gitlab-ci.yml` pattern (Group I); branch-protection call swaps to GitLab's endpoint.
- Bot-identity step asks "use a Project Access Token (recommended — isolates the bot as its
  own service-account user) or your personal GitLab account?" — mirrors the GH App-vs-personal
  choice.
- Worker self-check: GitLab branch verifies `board_id` resolves and its list count matches the
  variant's status count, replacing GitHub's `gh project field-list` check.
- **Graceful degradation required**: since board/list creation relies on undocumented-by-`glab`
  raw API calls (more exposed to breaking silently on a GitLab version bump than documented
  `glab` subcommands), on failure print the exact manual UI steps and continue onboarding with
  `board_id: null` rather than hard-failing the whole flow.

### Per-script rewrite map

- `scripts/super-board-run.sh`: source `scripts/platforms/${GIT_PLATFORM}.sh` (mirrors today's
  `${WORKER_BACKEND}.sh` sourcing); replace inline `gh project item-list`, `gh api rate_limit`,
  `gh issue edit --add/--remove-assignee`, and the `.github/workflows` grep with the
  corresponding `platform_*` calls.
- `scripts/super-board-gh-guard.sh`: becomes platform-conditional (rename candidate
  `scripts/platform-rate-guard.sh`); worker-local soft-budget logic is unchanged, only the
  remote-quota-check half branches per platform.
- `scripts/super-board-status.py`: gains the `PlatformAdapter` split described above; the
  `status::` label-projection rule must not be reimplemented independently from the bash
  version (see Open Judgment Call 4) — recommend the Python adapter shells out to a small
  bash helper for just that one derivation.
- `scripts/tasks-to-issues.sh`: default to issue-only filing; `--board` swaps the former inline
  `gh project view`/`field-list`/`item-add`/`item-edit
  --single-select-option-id` (resolve Project GraphQL ID, find Status field + Ready option,
  add item, set status) for the adapter's logical Ready enqueue plus
  `platform_card_status_set`'s add-only case. GitHub resolves Project Status metadata through
  `platform_board_ensure`; GitLab resolves the `status::ready` label through
  `platform_label_ensure`, and has no separate "add item to project" step since an issue is "on
  the board" the instant it exists.
- `scripts/platform-config.sh`: resolve explicit config, `PLATFORM_CONFIG_PATH`, active pointer,
  sole config, or GitHub default in that order; reject config/`GIT_PLATFORM` conflicts and
  unsupported platforms before any adapter is sourced.
- `scripts/super-board-wave-plan.sh`: same board-snapshot swap as `super-board-run.sh`; the
  `Depends on: #N` jq parsing needs zero changes if `platform_board_snapshot`'s output shape
  genuinely matches today's `.content.*`/`.status` fields.
- `scripts/super-board-wave.js`: no direct `gh` shell-outs today; only needs to thread
  `config.git_platform` into the dispatched sub-agent's prompt.
- `skills/super-build/scripts/super-build-dispatch.sh`: its one `gh issue view` call becomes
  `platform_issue_view`; its `git merge --no-ff`/no-PR integration model is otherwise
  platform-agnostic pure git and needs no other change.
- `scripts/bootstrap-app.sh`: install `glab` via brew alongside `gh` unconditionally (cheap,
  avoids a second onboarding round-trip); platform-conditional auth-scope check.
- `scripts/backends/*.sh`: no changes — confirmed orthogonal to platform choice.

## Out of Scope

- Bitbucket or any forge beyond GitHub/GitLab.
- GitLab Premium/Ultimate-gated features (Work Items custom fields) as a board-state mechanism.
- Automated migration of an existing GitHub-configured project to GitLab.
- Self-hosted GitLab edge cases beyond threading `project.host` through every `platform_*`
  call and failing open on missing rate-limit signals — deep self-hosted-version compatibility
  testing is a follow-up concern, not this spec's acceptance bar.
- `platform_thread_create`'s full implementation detail (the diff-position mapping) — this
  spec scopes it as an investigation spike, not a specified mechanism, given no clean
  reference implementation was found during research.

## Open judgment calls

1. **Skill-doc abstraction level** — should `run.md` etc. call `platform_*` function names
   inline, or stay fully CLI-agnostic in prose ("resolve the thread") with `platforms.md`
   holding all literal command detail? Recommend the latter, mirroring `backends.md`'s
   relationship to `run.md` — keeps future third-platform additions to a smaller diff surface.
2. GitLab's automatic unlabeled "Open" list appears in the board UI alongside the `status::*`
   lists — free Backlog-equivalent; onboarding copy should explain it so users aren't
   surprised. SuperSaiyan's status renderer is unaffected (it only reads labels it cares about).
3. `platform_release_issue`'s co-assignee eviction risk — accept as a known limitation
   matching GitHub's own equivalent risk class rather than engineering around it now; revisit
   only if actually reported.
4. Python/bash duplication of the `status::` label-projection rule — recommend
   `GitlabStatusAdapter` shells out to a bash helper for that one derivation rather than
   reimplementing it twice.
5. GitLab discussions vs. GitHub review threads — **resolved (task 10):** GitLab Block
   signal = a **non-resolvable** top-level MR note whose body has no `[QA]` / `[Review]` /
   lane prefix and whose author is not `notifications.bot_identity`. Resolvable
   discussions stay Gate 1 review threads (`platform_thread_list_unresolved` /
   `platform_thread_resolve`). Do not treat resolvable-but-human notes as Block.
6. Self-hosted GitLab instances — rate-limit headers and possibly scoped-label enforcement may
   differ from gitlab.com; `project.host` must be threaded through every `platform_*` call,
   and `platform_rate_guard` must fail open on missing signals rather than fail closed.
7. Bot identity choice — confirm Project/Group Access Tokens are available on the user's
   specific GitLab tier/instance at onboarding time (a runtime check) rather than assuming
   Free-tier availability universally.
8. Config schema shape — flat optional fields on `project` (chosen above, minimal diff) vs. a
   nested `project.gitlab{}` sub-object (cleaner separation, slightly bigger diff to existing
   config-reading code). Flagged as debatable, not resolved.
