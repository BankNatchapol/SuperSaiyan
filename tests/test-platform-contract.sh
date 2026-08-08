#!/usr/bin/env bash
# test-platform-contract.sh — static check that every scripts/platforms/*.sh implements the
# full Platform interface (see docs/superpowers/specs/gitlab-integration-design.md § Platform
# interface contract, Groups A–K). No live API calls — safe to run without gh/glab auth.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORMS_DIR="$ROOT/scripts/platforms"

REQUIRED_FUNCTIONS=(
  # Group A — Auth & identity
  platform_auth_check
  platform_bot_identity_resolve
  # Group B — Rate limit / quota
  platform_rate_remaining
  platform_rate_guard
  # Group C — Board read
  platform_board_snapshot
  platform_column_count
  platform_top_unclaimed_card
  # Group D — Board write / move-card
  platform_card_status_set
  platform_card_move_verify
  # Group E — Claim / release mutex
  platform_claim_issue
  platform_release_issue
  # Group F — Issue CRUD
  platform_issue_create
  platform_issue_view
  platform_issue_comment
  platform_issue_close
  platform_issue_edit_labels
  # Group G — MR/PR CRUD
  platform_mr_create_draft
  platform_mr_mark_ready
  platform_mr_comment
  platform_mr_merge_squash
  platform_mr_view
  platform_mr_list_by_branch
  # Group H — Review-thread resolve/create
  platform_thread_list_unresolved
  platform_thread_resolve
  platform_thread_create
  # Group I — Production/CI detection
  platform_detect_production_ci
  platform_detect_branch_protection
  # Group J — Raw-URL screenshot embed
  platform_raw_file_url
  # Group K — Repo/label/board bootstrap
  platform_repo_create
  platform_label_ensure
  platform_board_ensure
)

FAIL=0

shopt -s nullglob
PLATFORM_FILES=("$PLATFORMS_DIR"/*.sh)
shopt -u nullglob

if [ "${#PLATFORM_FILES[@]}" -eq 0 ]; then
  echo "error: no platform files found in $PLATFORMS_DIR" >&2
  exit 1
fi

for f in "${PLATFORM_FILES[@]}"; do
  name="$(basename "$f")"
  echo "checking $name"

  if ! bash -n "$f"; then
    echo "  FAIL: $name has a syntax error" >&2
    FAIL=1
    continue
  fi

  # Source in a subshell so functions from one platform never leak into the next check.
  MISSING=""
  for fn in "${REQUIRED_FUNCTIONS[@]}"; do
    if ! ( source "$f"; declare -f "$fn" >/dev/null 2>&1 ); then
      MISSING="$MISSING $fn"
    fi
  done

  if [ -n "$MISSING" ]; then
    echo "  FAIL: $name is missing:$MISSING" >&2
    FAIL=1
  else
    echo "  ✓ all ${#REQUIRED_FUNCTIONS[@]} contract functions defined"
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "error: one or more platform files failed the contract check" >&2
  exit 1
fi

echo "PASS: test-platform-contract.sh"
