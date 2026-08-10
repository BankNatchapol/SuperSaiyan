#!/usr/bin/env bash
# test-agents-md-install.sh — end-to-end coverage for how install.sh and
# setup-gstack-artifacts-path.sh write agent instructions into a target repo.
#
# The bug this guards: those scripts used to append only to a target's CLAUDE.md, so a
# Codex-only or Cursor-only user got SuperSaiyan's pipeline guidance in a file their tool never
# reads. Canonical content now goes to AGENTS.md (read natively by Codex and Cursor) with a
# CLAUDE.md pointer for Claude Code, which does not read AGENTS.md.
#
# Runs the real install.sh against scratch git repos. No network, no GitHub.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT/install.sh"
GSTACK="$ROOT/scripts/setup-gstack-artifacts-path.sh"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

echo "checking AGENTS.md install wiring"

TD=$(mktemp -d)
trap 'rm -rf "$TD"' EXIT

new_repo() {
  # $1 = name. Echoes the repo path.
  local dir="$TD/$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q
  echo "$dir"
}

BEGIN_PIPE='<!-- supersaiyan:begin id=pipeline-paths -->'
BEGIN_GSTACK='<!-- supersaiyan:begin id=gstack-paths -->'

# ── 1. Greenfield: no CLAUDE.md, no AGENTS.md ──────────────────────────────────────────────
REPO=$(new_repo greenfield)
bash "$INSTALL" "$REPO" >/dev/null 2>&1 || fail "1: install.sh failed on a greenfield repo"
grep -qF "$BEGIN_PIPE" "$REPO/AGENTS.md" || fail "1: AGENTS.md missing the fenced pipeline-paths block"
grep -q '^## SuperSaiyan pipeline paths$' "$REPO/AGENTS.md" || fail "1: AGENTS.md missing the block content"
[ "$(cat "$REPO/CLAUDE.md")" = "@AGENTS.md" ] || fail "1: CLAUDE.md should be exactly '@AGENTS.md', got: $(cat "$REPO/CLAUDE.md")"

# ── 2. Idempotency: a second run changes nothing ───────────────────────────────────────────
cp "$REPO/AGENTS.md" "$TD/agents.before"
cp "$REPO/CLAUDE.md" "$TD/claude.before"
bash "$INSTALL" "$REPO" >/dev/null 2>&1 || fail "2: second install.sh run failed"
diff -q "$TD/agents.before" "$REPO/AGENTS.md" >/dev/null || fail "2: AGENTS.md changed on re-run"
diff -q "$TD/claude.before" "$REPO/CLAUDE.md" >/dev/null || fail "2: CLAUDE.md changed on re-run"

# ── 3. Update-in-place — what the old substring-grep could never do ────────────────────────
# Point the installer at a temporary source whose content differs, and assert the target's
# existing block is REPLACED rather than skipped.
SRC="$ROOT/docs/templates/agent-blocks/pipeline-paths.md"
cp "$SRC" "$TD/pipeline-paths.orig"
printf '## SuperSaiyan pipeline paths\n\nSENTINEL-UPDATED-CONTENT\n' > "$SRC"
bash "$INSTALL" "$REPO" >/dev/null 2>&1 || fail "3: install.sh failed after a source edit"
cp "$TD/pipeline-paths.orig" "$SRC"   # restore immediately, before any assertion can abort
grep -q '^SENTINEL-UPDATED-CONTENT$' "$REPO/AGENTS.md" || fail "3: block was not updated in place"
[ "$(grep -cF "$BEGIN_PIPE" "$REPO/AGENTS.md")" -eq 1 ] || fail "3: update duplicated the fence"
bash "$INSTALL" "$REPO" >/dev/null 2>&1
grep -q '^SENTINEL-UPDATED-CONTENT$' "$REPO/AGENTS.md" && fail "3: restored source did not propagate back"

# ── 4. Legacy migration: pre-fence sections in CLAUDE.md, with user content around them ────
REPO=$(new_repo legacy)
cat > "$REPO/CLAUDE.md" <<'EOF'
# My App

My own instructions that must survive verbatim.

## SuperSaiyan pipeline paths

| Artifact | Path |
|----------|------|
| Feature specs | `docs/superpowers/specs/<slug>-design.md` |

MY-HAND-EDIT-INSIDE-LEGACY-SECTION

## gstack artifact paths (SuperSaiyan)

Old gstack content.

## My Own Section

Trailing content that must also survive.
EOF
bash "$INSTALL" "$REPO" >/dev/null 2>&1 || fail "4: install.sh failed on a legacy repo"
bash "$GSTACK" "$REPO" >/dev/null 2>&1 || fail "4: setup-gstack-artifacts-path.sh failed"

# User content byte-preserved
grep -q '^# My App$' "$REPO/CLAUDE.md" || fail "4: user H1 lost"
grep -q '^My own instructions that must survive verbatim\.$' "$REPO/CLAUDE.md" || fail "4: user paragraph lost"
grep -q '^## My Own Section$' "$REPO/CLAUDE.md" || fail "4: user section lost"
grep -q '^Trailing content that must also survive\.$' "$REPO/CLAUDE.md" || fail "4: trailing content lost"

# Legacy sections gone from CLAUDE.md, present in AGENTS.md — content lives in exactly one file
[ "$(grep -c '^## SuperSaiyan pipeline paths$' "$REPO/CLAUDE.md")" -eq 0 ] || fail "4: legacy pipeline section survived in CLAUDE.md"
[ "$(grep -c '^## gstack artifact paths (SuperSaiyan)$' "$REPO/CLAUDE.md")" -eq 0 ] || fail "4: legacy gstack section survived in CLAUDE.md"
[ "$(grep -c '^## SuperSaiyan pipeline paths$' "$REPO/AGENTS.md")" -eq 1 ] || fail "4: pipeline block not in AGENTS.md exactly once"
[ "$(grep -c '^## gstack artifact paths (SuperSaiyan)$' "$REPO/AGENTS.md")" -eq 1 ] || fail "4: gstack block not in AGENTS.md exactly once"

# The hand-edit inside the legacy section must be recoverable, not destroyed
grep -rq 'MY-HAND-EDIT-INSIDE-LEGACY-SECTION' "$REPO/docs/supersaiyan/migrations/" 2>/dev/null \
  || fail "4: user hand-edit inside the legacy section was not preserved in a backup (data loss)"

# Claude pointer appended without disturbing the user's structure
grep -q '^@AGENTS\.md$' "$REPO/CLAUDE.md" || fail "4: no @AGENTS.md pointer added"
grep -qF '<!-- supersaiyan:begin id=claude-pointer -->' "$REPO/CLAUDE.md" || fail "4: pointer not fenced"

# ── 5. Legacy repo is idempotent too (both scripts, run twice) ─────────────────────────────
cp "$REPO/CLAUDE.md" "$TD/legacy-claude.before"
cp "$REPO/AGENTS.md" "$TD/legacy-agents.before"
bash "$INSTALL" "$REPO" >/dev/null 2>&1
bash "$GSTACK" "$REPO" >/dev/null 2>&1
diff -q "$TD/legacy-claude.before" "$REPO/CLAUDE.md" >/dev/null || fail "5: CLAUDE.md changed on re-run after migration"
diff -q "$TD/legacy-agents.before" "$REPO/AGENTS.md" >/dev/null || fail "5: AGENTS.md changed on re-run after migration"

# ── 6. Existing user AGENTS.md is extended, not clobbered ──────────────────────────────────
REPO=$(new_repo user-agents)
cat > "$REPO/AGENTS.md" <<'EOF'
# Existing Agent Notes

USER-AUTHORED-AGENTS-CONTENT
EOF
bash "$INSTALL" "$REPO" >/dev/null 2>&1 || fail "6: install.sh failed with a pre-existing AGENTS.md"
grep -q '^USER-AUTHORED-AGENTS-CONTENT$' "$REPO/AGENTS.md" || fail "6: pre-existing AGENTS.md content was clobbered"
grep -qF "$BEGIN_PIPE" "$REPO/AGENTS.md" || fail "6: block not appended to an existing AGENTS.md"

# ── 7. Broken fence → hard error, target file untouched ────────────────────────────────────
REPO=$(new_repo broken-fence)
bash "$INSTALL" "$REPO" >/dev/null 2>&1
# Remove the end marker to simulate a truncating hand-edit.
grep -vF '<!-- supersaiyan:end id=pipeline-paths -->' "$REPO/AGENTS.md" > "$TD/tmp.md"
mv "$TD/tmp.md" "$REPO/AGENTS.md"
cp "$REPO/AGENTS.md" "$TD/broken.before"
set +e
bash "$INSTALL" "$REPO" >"$TD/broken.out" 2>&1
set -e
diff -q "$TD/broken.before" "$REPO/AGENTS.md" >/dev/null \
  || fail "7: AGENTS.md was modified despite an unterminated fence"
grep -qi 'unterminated' "$TD/broken.out" || fail "7: no unterminated-fence diagnostic surfaced"

if [ "$FAIL" -ne 0 ]; then
  echo "error: AGENTS.md install wiring failed one or more checks" >&2
  exit 1
fi

echo "  ✓ greenfield, idempotency, update-in-place, legacy migration + backup, existing AGENTS.md, broken fence"
echo "PASS: test-agents-md-install.sh"
