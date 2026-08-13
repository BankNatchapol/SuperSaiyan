#!/usr/bin/env bash
# test-worker-docs-platform-agnostic.sh — issue #5 / gitlab-integration task 05.
# Worker-facing skill docs must describe forge operations as platform_* calls,
# not literal `gh api` / `gh issue` / `gh pr` / `gh project` commands.
# Mentions of "the gh CLI" by name for context are fine; invocable commands are not.

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

  if grep -nE 'gh api|gh issue|gh pr|gh project' "$f"; then
    fail "$rel still contains invocable gh api/issue/pr/project commands (use platform_*)"
  fi

  grep -q 'references/platforms.md' "$f" \
    || fail "$rel missing one-line pointer to references/platforms.md"
done

RUN_MD="$ROOT/skills/super-board/references/run.md"
if grep -q 'resolveReviewThread' "$RUN_MD"; then
  fail "skills/super-board/references/run.md still names resolveReviewThread (use platform_thread_resolve)"
fi
grep -q 'platform_thread_resolve' "$RUN_MD" \
  || fail "skills/super-board/references/run.md Gate 1 does not describe platform_thread_resolve"

if [ "$FAIL" -ne 0 ]; then
  echo "error: worker-facing skill docs are not platform-agnostic" >&2
  exit 1
fi

echo "  ✓ five worker docs have no invocable gh commands and point at platforms.md"
echo "PASS: test-worker-docs-platform-agnostic.sh"
