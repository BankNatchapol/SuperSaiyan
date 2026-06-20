#!/usr/bin/env bash
# Verify super-board sandbox setup in SuperSaiyan
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

check() {
  if [ -e "$1" ]; then
    echo "  OK  $1"
  else
    echo "  MISSING  $1" >&2
    FAIL=1
  fi
}

echo "Super Board sandbox verification"
echo "Root: $ROOT"
echo

echo "Upstream clone:"
check "$ROOT/super-board/README.md"
check "$ROOT/super-board/workflows/super-board-wave.js"

echo
echo "Installed .claude tree:"
for s in super-board super-build super-qa super-review; do
  check "$ROOT/.claude/skills/$s/SKILL.md"
done
check "$ROOT/.claude/skills/supersaiyan/SKILL.md"
check "$ROOT/.claude/skills/supersaiyan/references/prepare.md"
check "$ROOT/.claude/skills/supersaiyan/scripts/prepare.sh"
check "$ROOT/scripts/tasks-to-issues.sh"
check "$ROOT/.claude/workflows/super-board-wave.js"
check "$ROOT/.claude/bin/super-board-wave-plan.sh"

echo
echo "External dependency clones:"
check "$ROOT/superpowers/README.md"
check "$ROOT/gstack/README.md"
if [ -L "$ROOT/.claude/skills/gstack" ]; then
  echo "  OK  .claude/skills/gstack -> $(readlink "$ROOT/.claude/skills/gstack")"
else
  echo "  MISSING  .claude/skills/gstack symlink" >&2
  FAIL=1
fi

echo
echo "Analysis docs:"
check "$ROOT/docs/super-board-analysis/card-lifecycle-thesis-notes.md"
check "$ROOT/docs/super-board-analysis/integration-decision.md"

echo
if command -v bun >/dev/null 2>&1; then
  echo "Bun: installed (run: cd gstack && ./setup)"
else
  echo "Bun: not installed — gstack ./setup skipped (see docs/super-board-analysis/install-deps.md)"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: core sandbox ready"
  exit 0
else
  echo "FAIL: missing components" >&2
  exit 1
fi
