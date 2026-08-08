#!/usr/bin/env bash
# scripts/platforms/github.sh — Platform interface for git_platform "github".
# Sourced (not executed) by dispatcher/helpers once tasks 03–04 rewire call sites.
# Thin wrappers around today's literal `gh` commands — zero behavior change.
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
  local scopes
  scopes=$(gh auth status --active --json hosts --jq \
    '.hosts | add | map(select(.active == true))[0].scopes // ""' 2>/dev/null || true)
  case ",${scopes// /}," in
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
  # $1 = project number, $2 = owner. Emits gh project item-list JSON
  # (status already present as single-select field value).
  local number="$1" owner="$2"
  gh project item-list "$number" --owner "$owner" --format json --limit 500 2>/dev/null || echo '{"items":[]}'
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
  # GitHub ProjectV2 single-select write. Args match today's gh project item-edit:
  # $1 = item_id, $2 = project_id, $3 = field_id, $4 = single-select-option-id.
  # (Logical <issue> <target-status> is resolved to these IDs by the caller /
  # tasks-to-issues load_project_ready_metadata — same as today.)
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
  # Fails (exit 65) if Status field or any required option is missing — same
  # gate as tasks-to-issues.sh load_project_ready_metadata.
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
  # Echo project_id + status field id for callers that need them next.
  printf '%s\n%s\n' "$project_id" "$status_id"
}
