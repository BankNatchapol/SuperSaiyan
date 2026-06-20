#!/usr/bin/env bash
# split-plan-to-tasks.sh — STUB ONLY: mechanical split of ### Task headers.
#
# Prefer the writing-board-tasks skill (agent) for real task files — it re-decomposes
# the plan into PR-sized board tasks with observable ACs.
#
# Usage (from app repo root):
#   /path/to/SuperSaiyan/scripts/split-plan-to-tasks.sh <plan.md> <feature-slug> [--force]
set -euo pipefail

PLAN="${1:-}"
FEATURE="${2:-}"
FORCE="${3:-}"

if [ -z "$PLAN" ] || [ -z "$FEATURE" ]; then
  echo "Usage: $0 <plan.md> <feature-slug> [--force]" >&2
  exit 64
fi

if [ ! -f "$PLAN" ]; then
  echo "Plan not found: $PLAN" >&2
  exit 66
fi

OUT_DIR="${TASKS_DIR:-docs/superpowers/tasks}/$FEATURE"
DESIGN="${DESIGN_PATH:-docs/superpowers/specs/${FEATURE}-design.md}"

if [ -d "$OUT_DIR" ] && compgen -G "$OUT_DIR"/*.md >/dev/null 2>&1 && [ "$FORCE" != "--force" ]; then
  echo "Task dir not empty: $OUT_DIR (use --force to overwrite stubs)" >&2
  exit 73
fi

mkdir -p "$OUT_DIR"
if [ "$FORCE" = "--force" ]; then
  rm -f "$OUT_DIR"/*.md
fi

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g' | cut -c1-40
}

TMPDIR_TASKS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TASKS"' EXIT
export TMPDIR_TASKS

# Split plan into task-N.txt files (portable awk)
awk '
  /^### Task [0-9]+:/ {
    if (out != "") close(out)
    num = $3
    gsub(/:/, "", num)
    out = ENVIRON["TMPDIR_TASKS"] "/task-" num ".txt"
    print > out
    next
  }
  out != "" { print >> out }
' TMPDIR_TASKS="$TMPDIR_TASKS" "$PLAN"

shopt -s nullglob
if ! compgen -G "$TMPDIR_TASKS/task-*.txt" >/dev/null; then
  echo "No '### Task N:' sections found in $PLAN" >&2
  exit 65
fi

for tf in $(ls "$TMPDIR_TASKS"/task-*.txt | sort -t- -k2 -n); do
  title_line=$(head -1 "$tf")
  task_num=$(echo "$title_line" | sed -nE 's/^### Task ([0-9]+):.*/\1/p')
  task_name=$(echo "$title_line" | sed -nE 's/^### Task [0-9]+: *(.*)/\1/p')
  stem=$(printf '%02d-%s' "$task_num" "$(slugify "$task_name")")
  out="$OUT_DIR/${stem}.md"

  prev_dep="null"
  if [ "$task_num" -gt 1 ]; then
    prev_num=$((task_num - 1))
    prev_match=$(compgen -G "$OUT_DIR/$(printf '%02d' "$prev_num")-*.md" | head -1 || true)
    if [ -n "$prev_match" ]; then
      prev_dep=$(basename "$prev_match" .md)
    fi
  fi

  {
    echo "---"
    echo "title: $task_name"
    echo "order: $task_num"
    echo "depends_on_task: $prev_dep"
    echo "feature: $FEATURE"
    echo "design: $DESIGN"
    echo "plan: $PLAN"
    echo "plan_task: Task $task_num"
    echo "skills: superpowers:test-driven-development, superpowers:verification-before-completion"
    echo "---"
    echo
    echo "## Goal"
    echo
    echo "<Edit: one-sentence outcome for this task>"
    echo
    echo "## Acceptance Criteria"
    echo
    echo "- [ ] <Edit: observable check>"
    echo "- [ ] Tests pass (document command in PR)"
    echo
    echo "## Implementation notes"
    echo
    tail -n +2 "$tf"
  } > "$out"

  echo "Wrote $out"
done

echo
echo "Next: edit Goal + ACs in $OUT_DIR/, then:"
echo "  tasks-to-issues.sh $FEATURE"
