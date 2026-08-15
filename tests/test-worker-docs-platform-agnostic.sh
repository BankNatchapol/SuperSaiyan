#!/usr/bin/env bash
# test-worker-docs-platform-agnostic.sh — issue #5 / gitlab-integration task 05.
# Worker-facing skill docs must describe forge operations as platform_* calls,
# not literal invocable `gh <subcommand>` / $(gh …) commands.
# Mentions of "the gh CLI" / "gh calls" / "gh-quota" by name for context are fine.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FILES=(
  "$ROOT/skills/super-board/references/run.md"
  "$ROOT/skills/super-board/references/block-template.md"
  "$ROOT/skills/super-build/references/worker-preamble.md"
  "$ROOT/skills/super-build/SKILL.md"
  "$ROOT/skills/super-qa/SKILL.md"
)

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

echo "checking worker-facing skill docs are platform-agnostic"

for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "error: $f not found" >&2; exit 1; }
  rel="${f#"$ROOT"/}"

  # Invocable: backtick-wrapped `gh <subcommand>` or command substitution $(gh …)
  if grep -nE '`gh [a-z]|\$\(gh ' "$f"; then
    fail "$rel still contains an invocable gh command (use platform_*)"
  fi

  grep -q 'references/platforms.md' "$f" \
    || fail "$rel missing one-line pointer to references/platforms.md"
done

RUN_MD="$ROOT/skills/super-board/references/run.md"
BUILD_SKILL="$ROOT/skills/super-build/SKILL.md"
QA_SKILL="$ROOT/skills/super-qa/SKILL.md"
WORKFLOW="$ROOT/.github/workflows/skills-lint.yml"

if grep -q 'resolveReviewThread' "$RUN_MD"; then
  fail "skills/super-board/references/run.md still names resolveReviewThread (use platform_thread_resolve)"
fi
grep -q 'platform_thread_resolve' "$RUN_MD" \
  || fail "skills/super-board/references/run.md Gate 1 does not describe platform_thread_resolve"

# Rate-limit guard must name the GraphQL bucket (#381 drain).
if ! grep -E 'platform_rate_remaining' "$RUN_MD" | grep -qi 'graphql'; then
  fail "run.md rate-limit guard does not name the graphql bucket for platform_rate_remaining"
fi

# Snapshot reads cards of a known project — never list-boards, never no-args.
if grep -nF 'platform_board_snapshot' "$BUILD_SKILL" "$QA_SKILL" | grep -q 'to list boards'; then
  fail "platform_board_snapshot is described as a project-list API (it returns cards)"
fi
if grep -nE '^[[:space:]]*platform_board_snapshot([[:space:]]*(#.*)?)?$' "$BUILD_SKILL" "$QA_SKILL"; then
  fail "platform_board_snapshot invoked with no args (need <number> <owner> or a config path)"
fi

# platform_issue_view is one issue, not a list.
if grep -nE 'platform_issue_view[[:space:]]*/[[:space:]]*board snapshot' "$QA_SKILL"; then
  fail "super-qa uses platform_issue_view as an issue list (filter platform_board_snapshot instead)"
fi

grep -q 'test-worker-docs-platform-agnostic.sh' "$WORKFLOW" \
  || fail ".github/workflows/skills-lint.yml does not run test-worker-docs-platform-agnostic.sh"

if [ "$FAIL" -ne 0 ]; then
  echo "error: worker-facing skill docs are not platform-agnostic" >&2
  exit 1
fi

echo "  ✓ five worker docs have no invocable gh commands and point at platforms.md"
echo "PASS: test-worker-docs-platform-agnostic.sh"
