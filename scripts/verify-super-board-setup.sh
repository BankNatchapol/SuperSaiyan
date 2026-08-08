#!/usr/bin/env bash
# Verify SuperSaiyan toolkit setup (top-level skills/scripts layout; nothing
# vendored — gstack/superpowers are installed per-machine by bootstrap-app.sh,
# not carried as clones inside this repo).
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

echo "SuperSaiyan toolkit verification"
echo "Root: $ROOT"
echo

echo "Skills:"
for s in super-board super-build super-qa super-review supersaiyan \
         refining-spec writing-board-tasks \
         test-driven-development verification-before-completion; do
  check "$ROOT/skills/$s/SKILL.md"
done

echo
echo "Pipeline scripts:"
check "$ROOT/install.sh"
check "$ROOT/scripts/tasks-to-issues.sh"
check "$ROOT/scripts/super-board-wave.js"
check "$ROOT/scripts/super-board-run.sh"
check "$ROOT/scripts/super-board-status.py"
check "$ROOT/skills/super-board/references/run.md"

echo
echo "Analysis docs:"
check "$ROOT/docs/super-board-analysis/card-lifecycle-thesis-notes.md"
check "$ROOT/docs/super-board-analysis/integration-decision.md"

echo
echo "Machine-level dependencies (per-machine, not vendored here — informational only):"
if command -v bun >/dev/null 2>&1; then
  echo "  OK  bun (required for gstack ./setup)"
else
  echo "  --  bun not installed — required for gstack; see scripts/bootstrap-app.sh"
fi
if claude plugin list 2>/dev/null | grep -q "superpowers@claude-plugins-official"; then
  echo "  OK  superpowers plugin installed"
else
  echo "  --  superpowers plugin not installed — run: claude plugin install superpowers@claude-plugins-official"
fi
if [ -f "$HOME/.claude/skills/office-hours/SKILL.md" ]; then
  echo "  OK  gstack installed (~/.claude/skills/gstack)"
else
  echo "  --  gstack not installed — see scripts/bootstrap-app.sh install_gstack()"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: core toolkit ready"
  exit 0
else
  echo "FAIL: missing components" >&2
  exit 1
fi
