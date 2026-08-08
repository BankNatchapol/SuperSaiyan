#!/usr/bin/env bash
# test-build-safety-contract.sh — static check that skills/super-build/SKILL.md's default
# path never merges or closes an issue on its own. Guards against regressing the fix for:
# standalone super-build closing issues with no QA/Review step (2026-08).
#
# No live CLI calls — just greps the prompt file's structure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/skills/super-build/SKILL.md"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

if [ ! -f "$FILE" ]; then
  echo "error: $FILE not found" >&2
  exit 1
fi

echo "checking skills/super-build/SKILL.md"

# 1. The default success path must open a PR.
grep -q -- 'gh pr create' "$FILE" || fail "default reconcile path no longer opens a PR (gh pr create missing)"

# 2. The Autonomy preflight section must exist.
grep -q '^## Autonomy preflight' "$FILE" || fail "'## Autonomy preflight' section missing"

# 3. The explicit, loud opt-in phrase must exist — this is the only door to the old behavior.
grep -q -- '--standalone-automerge-i-understand-the-risk' "$FILE" || fail "standalone auto-merge opt-in flag missing"

# 4. The gated section for the old destructive behavior must exist.
GATE_LINE="$(grep -n '^## Standalone Auto-Merge mode' "$FILE" | head -1 | cut -d: -f1 || true)"
if [ -z "$GATE_LINE" ]; then
  fail "'## Standalone Auto-Merge mode' heading missing"
else
  # 5. The unconditional close command (the exact old default) must not appear before the gate.
  if head -n "$((GATE_LINE - 1))" "$FILE" | grep -qE 'gh issue close N --comment "Closed by /super-build in \$'; then
    fail "unconditional 'gh issue close' instruction found before the gated Standalone Auto-Merge section"
  fi
fi

# 6. The preflight must check for an onboarded pipeline config before allowing autonomy.
grep -q '.claude/supersaiyan/configs' "$FILE" || fail "preflight config-path check missing (.claude/supersaiyan/configs)"

# 7. The pipeline-dispatched gate must match what the real dispatch backends actually send —
#    regression guard for the "super-board run" vs "super-board workflow wave" string mismatch.
grep -q 'super-board workflow wave' "$FILE" || fail "pipeline-dispatched gate missing 'super-board workflow wave' (the default backend's actual dispatch string)"
grep -qF '.claude/skills/super-board/references/run.md' "$FILE" || fail "pipeline-dispatched gate missing a reference to references/run.md"
grep -qi 'lane lifecycle' "$FILE" || fail "pipeline-dispatched gate missing the 'read run.md -> lane lifecycle' structural signal"

# 8. The repo-identity guard must exist so this repo itself can't run the live pipeline.
grep -qi 'SuperSaiyan toolkit repo' "$FILE" || fail "repo-identity guard for the SuperSaiyan toolkit repo missing"

# 9. Never-implement-on-main rule must exist here and in supersaiyan/SKILL.md (belt and suspenders
#    for ad hoc issue work that never invokes super-build at all).
grep -qi 'directly on the default branch in the primary worktree' "$FILE" || fail "never-implement-on-main rule missing from super-build/SKILL.md"
SUPERSAIYAN_FILE="$ROOT/skills/supersaiyan/SKILL.md"
if [ -f "$SUPERSAIYAN_FILE" ]; then
  grep -qi 'directly on the primary branch' "$SUPERSAIYAN_FILE" || fail "never-implement-on-main golden rule missing from skills/supersaiyan/SKILL.md"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "error: skills/super-build/SKILL.md failed the safety contract check" >&2
  exit 1
fi

echo "  ✓ default path is PR-only; destructive behavior is gated behind explicit opt-in"
echo "PASS: test-build-safety-contract.sh"
