#!/usr/bin/env bash
# test-gitlab-review-threads.sh — issue #10.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLAB_SH="$ROOT/scripts/platforms/gitlab.sh"
SANDBOX="${GITLAB_SANDBOX:-BankNatchapol/supersaiyan-gitlab-sandbox}"
MR_IID="${GITLAB_DRAFT_MR_IID:-}"
[ -z "$MR_IID" ] && [ -f "$ROOT/docs/super-board/runs/issue-7-16-gitlab-e2e/draft-mr-iid.txt" ] \
  && MR_IID=$(tr -d '[:space:]' < "$ROOT/docs/super-board/runs/issue-7-16-gitlab-e2e/draft-mr-iid.txt")

FAIL=0
tfail() { echo "  FAIL: $1" >&2; FAIL=1; }

echo "checking gitlab.sh Group H (review threads)"
bash -n "$GITLAB_SH" || tfail "syntax"
# shellcheck disable=SC1090
. "$GITLAB_SH"
# shellcheck disable=SC1091
. "$ROOT/tests/lib/gitlab-live-gate.sh"
gitlab_live_gate_assert "$0"
grep -q 'Open Judgment Call 5' "$GITLAB_SH" || tfail "OJC 5 comment missing in gitlab.sh"
grep -q 'resolved (task 10)' "$ROOT/docs/superpowers/specs/gitlab-integration-design.md" \
  || tfail "OJC 5 not marked resolved in the design spec"
grep -q 'position\[base_sha\]' "$GITLAB_SH" || tfail "thread_create missing form-field position spike notes"

if ! gitlab_live_enabled; then
  echo "  skip live sandbox checks (set GITLAB_LIVE=1 with glab auth to run)"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "PASS: test-gitlab-review-threads.sh (docs only)"
  exit 0
fi
[ -n "$MR_IID" ] || { tfail "no draft MR iid for live thread tests"; exit 1; }

CFG=$(mktemp)
cat > "$CFG" <<EOF
{"git_platform":"gitlab","project":{"host":"gitlab.com","full_path":"$SANDBOX"}}
EOF
export PLATFORM_CONFIG_PATH="$CFG"

# Seed a fresh line-level thread + rely on existing top-level note
platform_thread_create "$SANDBOX" "$MR_IID" "" README.md 1 "thread-create from test #10" >/dev/null \
  || tfail "platform_thread_create failed"

ids=$(platform_thread_list_unresolved "$SANDBOX" "$MR_IID") || tfail "list_unresolved failed"
echo "$ids" | grep -q 'gid://gitlab/Discussion/' || tfail "list did not emit GraphQL discussion IDs: $ids"
# Must not include the non-resolvable top-level note discussion
count=$(printf '%s\n' "$ids" | grep -c 'gid://gitlab/Discussion/' || true)
[ "$count" -ge 1 ] || tfail "expected at least one unresolved resolvable thread"

first=$(printf '%s\n' "$ids" | head -1)
platform_thread_resolve "$first" >/dev/null || tfail "resolve failed"
# idempotent
platform_thread_resolve "$first" >/dev/null || tfail "second resolve (idempotent) failed"

rm -f "$CFG"
if [ "$FAIL" -ne 0 ]; then
  echo "error: gitlab review-thread check failed" >&2
  exit 1
fi
echo "  ✓ Group H: list resolvable-only, idempotent resolve, line-level create"
echo "PASS: test-gitlab-review-threads.sh"
