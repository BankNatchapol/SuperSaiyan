#!/usr/bin/env bash
# scripts/platforms/github.sh — Platform interface for git_platform "github".
# Sourced (not executed) by dispatcher/helpers once tasks 03–04 rewire call sites.
# Thin wrappers around today's literal `gh` commands. Board reads preserve the
# normalized output shape while propagating command failures to callers.
# Contract: docs/superpowers/specs/gitlab-integration-design.md § Platform interface.

# ───────────────────────────── Group A — Auth & identity ─────────────────────────────

platform_auth_check() {
  # gh auth status + scope check (project, read:project, repo).
  command -v gh >/dev/null 2>&1 || {
    echo "gh CLI not found on PATH — install: https://cli.github.com" >&2
    return 1
  }
  gh auth status >/dev/null 2>&1 || {
    echo "gh not authenticated — run: gh auth login" >&2
    return 1
  }
  local auth_json scopes
  auth_json=$(gh auth status --active --json hosts 2>/dev/null || true)
  scopes=$(printf '%s' "$auth_json" | jq -r \
    '.hosts | add | map(select(.active == true))[0].scopes // ""' 2>/dev/null)
  case ",${scopes// /,}," in
    *,project,*) ;;
    *)
      echo "GitHub Project write scope missing; run: gh auth refresh -s project,read:project,repo" >&2
      return 1
      ;;
  esac
  return 0
}

platform_bot_identity_resolve() {
  # GitHub App install vs. personal login. Echoes the assignee identity string.
  # Optional $1 = preferred app slug (default super-board-bot). Falls back to
  # the authenticated user's login when no matching App installation is found —
  # same choice onboard.md step 12 records into notifications.bot_identity.
  local app_slug="${1:-super-board-bot}"
  local owner repo app_login login
  owner=$(gh repo view --json owner -q .owner.login 2>/dev/null || true)
  repo=$(gh repo view --json name -q .name 2>/dev/null || true)
  if [ -n "$owner" ] && [ -n "$repo" ]; then
    app_login=$(gh api "repos/${owner}/${repo}/installation" -q .app_slug 2>/dev/null || true)
    if [ "$app_login" = "$app_slug" ]; then
      echo "${app_slug}[bot]"
      return 0
    fi
  fi
  login=$(gh api user -q .login 2>/dev/null || true)
  if [ -z "$login" ]; then
    echo "could not resolve bot identity — gh auth / repo context unavailable" >&2
    return 1
  fi
  echo "$login"
}

# ───────────────────────────── Group B — Rate limit / quota ─────────────────────────────

platform_rate_remaining() {
  # $1 = resource bucket: "graphql" (default) or "core".
  local resource="${1:-graphql}"
  local payload
  payload=$(gh api rate_limit 2>/dev/null || echo '{"resources":{"graphql":{"remaining":5000,"reset":0},"core":{"remaining":5000,"reset":0}}}')
  echo "$payload" | jq -r --arg r "$resource" '.resources[$r].remaining // 5000'
}

platform_rate_guard() {
  # Sleep until GraphQL quota recovers. Also checks REST (core).
  # $1 = optional minimum-remaining threshold (default 200).
  # Extracted from scripts/super-board-gh-guard.sh / super-board-run.sh gh_rate_guard.
  local min="${1:-200}"
  local payload graphql_remaining graphql_reset rest_remaining now wait
  payload=$(gh api rate_limit 2>/dev/null || echo '{"resources":{"graphql":{"remaining":5000,"reset":0},"core":{"remaining":5000,"reset":0}}}')
  graphql_remaining=$(echo "$payload" | jq -r '.resources.graphql.remaining // 5000')
  rest_remaining=$(echo "$payload" | jq -r '.resources.core.remaining // 5000')

  if [ "$graphql_remaining" -lt "$min" ]; then
    graphql_reset=$(echo "$payload" | jq -r '.resources.graphql.reset // 0')
    now=$(date +%s)
    wait=$((graphql_reset - now + 10))
    [ "$wait" -lt 60 ] && wait=60
    [ "$wait" -gt 3600 ] && wait=3600
    echo "[platform-rate-guard] GraphQL low: ${graphql_remaining} left (<${min}); sleeping ${wait}s" >&2
    sleep "$wait"
    return 0
  fi

  if [ "$rest_remaining" -lt 500 ]; then
    echo "[platform-rate-guard] REST low: ${rest_remaining} left — pausing 60s to let the token breathe" >&2
    sleep 60
  fi
}

# ───────────────────────────── Group C — Board read ─────────────────────────────

platform_board_snapshot() {
  # Usage A: <project-number> <owner> (dispatcher compatibility).
  # Usage B: <config-path> (prepare/tasks-to-issues logical context).
  local number owner
  if [ -f "${1:-}" ]; then
    number=$(jq -r '.project.number // empty' "$1")
    owner=$(jq -r '.project.owner // "@me"' "$1")
  else
    number="$1" owner="$2"
  fi
  gh project item-list "$number" --owner "$owner" --format json --limit 500
}

platform_column_count() {
  # $1 = column name, $2 = snapshot JSON from platform_board_snapshot.
  # Same jq as scripts/super-board-run.sh column_count.
  local col="$1" snapshot="${2:-}"
  if [ -z "$snapshot" ]; then
    snapshot=$(cat)
  fi
  echo "$snapshot" | jq --arg col "$col" '[.items[] | select(.status == $col)] | length'
}

platform_top_unclaimed_card() {
  # $1 = column name, $2 = snapshot JSON. Emits first unassigned Issue number.
  # Lock-file filtering stays in the dispatcher (local concern, not platform).
  local col="$1" snapshot="${2:-}"
  if [ -z "$snapshot" ]; then
    snapshot=$(cat)
  fi
  echo "$snapshot" | jq -r --arg col "$col" '
    .items[]
    | select(.status == $col and .content.type == "Issue")
    | select((.content.assignees // []) | length == 0)
    | .content.number' | head -1
}

# ───────────────────────────── Group D — Board write / move-card ─────────────────────────────

platform_card_status_set() {
  # GitHub ProjectV2 single-select write.
  # Usage A (existing): <item_id> <project_id> <field_id> <option_id>
  # Usage B (add-only — tasks-to-issues Ready enqueue):
  #   --add <config-path> <issue_url> <target-status>
  #   → resolves board metadata inside this adapter, then adds and moves the item.
  if [ "${1:-}" = "--add" ]; then
    shift
    # Keep the pre-adapter add-only signature source-compatible for installed
    # callers that still pass resolved GitHub IDs.
    if [ "$#" -ge 6 ]; then
      local legacy_number="$1" legacy_owner="$2" legacy_url="$3"
      local legacy_project_id="$4" legacy_field_id="$5" legacy_option_id="$6"
      local legacy_item_id
      legacy_item_id=$(gh project item-add "$legacy_number" --owner "$legacy_owner" \
        --url "$legacy_url" --format json --jq '.id')
      gh project item-edit --id "$legacy_item_id" --project-id "$legacy_project_id" \
        --field-id "$legacy_field_id" --single-select-option-id "$legacy_option_id" >/dev/null
      echo "$legacy_item_id"
      return 0
    fi
    local config_path="$1" url="$2" target_status="$3"
    local number owner metadata project_id field_id option_id item_id existing_id snapshot
    if [ -n "$config_path" ] && [ -f "$config_path" ]; then
      number=$(jq -r '.project.number // empty' "$config_path")
      owner=$(jq -r '.project.owner // "@me"' "$config_path")
    else
      number="${GH_PROJECT_NUMBER:-}"
      owner="${GH_PROJECT_OWNER:-@me}"
    fi
    [ -n "$number" ] || { echo "GitHub Project number is required for Ready enqueue" >&2; return 64; }
    metadata=$(platform_board_ensure "$number" "$owner" "$target_status") || return
    project_id=$(printf '%s\n' "$metadata" | sed -n '1p')
    field_id=$(printf '%s\n' "$metadata" | sed -n '2p')
    option_id=$(printf '%s\n' "$metadata" | sed -n '3p')
    snapshot=$(platform_board_snapshot "$number" "$owner")
    existing_id=$(printf '%s' "$snapshot" | jq -r --arg url "$url" \
      '.items[] | select(.content.url == $url) | .id' | head -1)
    if [ -n "$existing_id" ]; then
      item_id="$existing_id"
    else
      item_id=$(gh project item-add "$number" --owner "$owner" \
        --url "$url" --format json --jq '.id')
    fi
    gh project item-edit --id "$item_id" --project-id "$project_id" \
      --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null
    echo "$item_id"
    return 0
  fi
  local item_id="$1" project_id="$2" field_id="$3" option_id="$4"
  gh project item-edit --id "$item_id" --project-id "$project_id" \
    --field-id "$field_id" --single-select-option-id "$option_id"
}

platform_card_move_verify() {
  # Not needed on GitHub — single-select mutation is atomic. No-op success.
  # Signature kept for Platform-interface parity with GitLab.
  # $1 = issue (unused), $2 = expected-status (unused)
  return 0
}

# ───────────────────────────── Group E — Claim / release mutex ─────────────────────────────

platform_claim_issue() {
  # $1 = issue number, $2 = bot login. Additive assignee write.
  local issue="$1" bot="$2"
  gh issue edit "$issue" --add-assignee "$bot"
}

platform_release_issue() {
  # $1 = issue number, $2 = bot login. Idempotent remove.
  local issue="$1" bot="$2"
  gh issue edit "$issue" --remove-assignee "$bot"
}

# ───────────────────────────── Group F — Issue CRUD ─────────────────────────────

platform_issue_create() {
  # $1 = title, $2 = body-file path. Echoes the created issue URL.
  local title="$1" body_file="$2"
  gh issue create --title "$title" --body-file "$body_file"
}

platform_issue_view() {
  # $1 = issue number, remaining args forwarded (e.g. --json fields).
  local issue="$1"
  shift
  gh issue view "$issue" "$@"
}

platform_issue_comment() {
  # $1 = issue number, $2 = body text.
  local issue="$1" body="$2"
  gh issue comment "$issue" --body "$body"
}

platform_issue_close() {
  # $1 = issue number, optional $2 = close comment.
  local issue="$1" comment="${2:-}"
  if [ -n "$comment" ]; then
    gh issue close "$issue" --comment "$comment"
  else
    gh issue close "$issue"
  fi
}

platform_issue_edit_labels() {
  # Forwards remaining args to `gh issue edit` (e.g. --add-label a --remove-label b).
  # $1 = issue number.
  local issue="$1"
  shift
  gh issue edit "$issue" "$@"
}

# ───────────────────────────── Group G — MR/PR CRUD ─────────────────────────────

platform_mr_create_draft() {
  # Forwards args to `gh pr create --draft` (typically --base --head --title --body-file).
  gh pr create --draft "$@"
}

platform_mr_mark_ready() {
  # $1 = PR number.
  gh pr ready "$1"
}

platform_mr_comment() {
  # $1 = PR number, $2 = body text.
  local pr="$1" body="$2"
  gh pr comment "$pr" --body "$body"
}

platform_mr_merge_squash() {
  # $1 = PR number.
  gh pr merge "$1" --squash --delete-branch
}

platform_mr_view() {
  # $1 = PR number or branch; remaining args forwarded (e.g. --json fields).
  local pr="$1"
  shift
  gh pr view "$pr" "$@"
}

platform_mr_list_by_branch() {
  # $1 = head branch name (or head:pattern). Remaining args forwarded.
  local branch="$1"
  shift
  case "$branch" in
    head:*) gh pr list --search "$branch" "$@" ;;
    *)      gh pr list --search "head:${branch}" "$@" ;;
  esac
}

# ───────────────────────────── Group H — Review-thread resolve/create ─────────────────────────────

platform_thread_list_unresolved() {
  # $1 = owner/repo, $2 = PR number. Emits unresolved review-thread node IDs (one per line).
  local repo="$1" pr="$2"
  gh api graphql -f query='
    query($owner:String!, $name:String!, $number:Int!) {
      repository(owner:$owner, name:$name) {
        pullRequest(number:$number) {
          reviewThreads(first:100) {
            nodes { id isResolved }
          }
        }
      }
    }' \
    -F "owner=${repo%%/*}" -F "name=${repo#*/}" -F "number=${pr}" \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .id'
}

platform_thread_resolve() {
  # $1 = review-thread node ID.
  local thread_id="$1"
  gh api graphql \
    -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}' \
    -f "threadId=${thread_id}"
}

platform_thread_create() {
  # Create a line-level PR review comment.
  # $1 = owner/repo, $2 = PR number, $3 = commit SHA, $4 = path, $5 = line, $6 = body.
  local repo="$1" pr="$2" commit="$3" path="$4" line="$5" body="$6"
  gh api "repos/${repo}/pulls/${pr}/comments" \
    -f body="$body" -f commit_id="$commit" -f path="$path" -F line="$line" -f side=RIGHT
}

# ───────────────────────────── Group I — Production/CI detection ─────────────────────────────

platform_detect_production_ci() {
  # Exit 0 if repo looks production-deployed on push-to-main; else 1.
  # Signals from onboard.md step 9: .github/workflows push→main deploy, vercel.json, netlify.toml.
  local root="${1:-.}"
  if [ -f "$root/vercel.json" ] || [ -f "$root/netlify.toml" ]; then
    return 0
  fi
  if [ -d "$root/.github/workflows" ]; then
    # Look for on.push.branches including main/master plus a job that smells like deploy.
    if command -v rg >/dev/null 2>&1; then
      if rg -l --glob '*.yml' --glob '*.yaml' \
          -e 'branches:\s*(\[|[^\n]*\n\s*-\s*)["'\'']?(main|master)' \
          "$root/.github/workflows" >/dev/null 2>&1 \
        && rg -l --glob '*.yml' --glob '*.yaml' \
          -e '(deploy|vercel|netlify|production)' \
          "$root/.github/workflows" >/dev/null 2>&1; then
        return 0
      fi
    else
      if grep -R -E -l 'branches:.*(main|master)|- (main|master)' \
          "$root/.github/workflows" --include='*.yml' --include='*.yaml' >/dev/null 2>&1 \
        && grep -R -E -l '(deploy|vercel|netlify|production)' \
          "$root/.github/workflows" --include='*.yml' --include='*.yaml' >/dev/null 2>&1; then
        return 0
      fi
    fi
  fi
  return 1
}

platform_detect_branch_protection() {
  # $1 = base branch (default main). Uses current repo from gh context.
  # Exit 0 if protection rules exist (esp. required PR reviews); else 1.
  local base="${1:-main}"
  local owner repo
  owner=$(gh repo view --json owner -q .owner.login) || return 1
  repo=$(gh repo view --json name -q .name) || return 1
  gh api "repos/${owner}/${repo}/branches/${base}/protection" >/dev/null 2>&1
}

# ───────────────────────────── Group J — Raw-URL screenshot embed ─────────────────────────────

platform_raw_file_url() {
  # $1 = owner/repo, $2 = branch, $3 = path.
  local repo="$1" branch="$2" path="$3"
  echo "https://github.com/${repo}/raw/${branch}/${path}"
}

# ───────────────────────────── Group K — Repo/label/board bootstrap ─────────────────────────────

platform_repo_create() {
  # Forwards args to `gh repo create`.
  gh repo create "$@"
}

platform_label_ensure() {
  # $1 = name, $2 = color (hex without #), $3 = description.
  # Idempotent: suppress-and-ignore on duplicate (today's pattern).
  local name="$1" color="${2:-CCCCCC}" description="${3:-}"
  gh label create "$name" --color "$color" --description "$description" 2>/dev/null || true
}

platform_board_ensure() {
  # Validate Status field options for a GitHub Project.
  # $1 = project number, $2 = owner, remaining args = required option names.
  # Fails (exit 65) if Status field or any required option is missing — the
  # adapter-level gate used by logical Ready enqueue operations.
  local number="$1" owner="$2"
  shift 2
  local fields status_id missing="" opt
  local project_id
  project_id=$(gh project view "$number" --owner "$owner" --format json --jq '.id') || return 1
  fields=$(gh project field-list "$number" --owner "$owner" --format json) || return 1
  status_id=$(echo "$fields" | jq -r '.fields[] | select(.name == "Status") | .id' | head -1)
  if [ -z "$status_id" ] || [ -z "$project_id" ]; then
    echo "Project ${owner}#${number} must have a Status field." >&2
    return 65
  fi
  for opt in "$@"; do
    if ! echo "$fields" | jq -e --arg n "$opt" \
      '.fields[] | select(.name == "Status") | .options[] | select(.name == $n)' >/dev/null; then
      missing="$missing $opt"
    fi
  done
  if [ -n "$missing" ]; then
    echo "Project ${owner}#${number} Status field missing options:$missing" >&2
    return 65
  fi
  # Echo project_id, status field id, then one option id per required option name
  # (so tasks-to-issues can resolve Ready without a second field-list round-trip).
  printf '%s\n%s\n' "$project_id" "$status_id"
  for opt in "$@"; do
    echo "$fields" | jq -r --arg n "$opt" \
      '.fields[] | select(.name == "Status") | .options[] | select(.name == $n) | .id' | head -1
  done
}
