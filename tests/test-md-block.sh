#!/usr/bin/env bash
# test-md-block.sh — unit coverage for scripts/lib/md-block.sh, the marker-fenced block
# upsert used by install.sh and setup-gstack-artifacts-path.sh to write agent-instruction
# blocks into a target repo's AGENTS.md. No file writes outside a temp dir.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/scripts/lib/md-block.sh"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

[ -f "$LIB" ] || { echo "error: $LIB not found" >&2; exit 1; }

echo "checking scripts/lib/md-block.sh"

bash -n "$LIB" || fail "bash -n reported a syntax error"
# bash 3.2 is the floor (macOS default) — guard against bash-4-only constructs creeping in.
if grep -vE '^\s*#' "$LIB" | grep -qE 'declare -A|mapfile|readarray'; then
  fail "uses a bash-4-only construct (declare -A / mapfile / readarray); repo targets bash 3.2"
fi

# shellcheck disable=SC1090
source "$LIB"

TD=$(mktemp -d)
trap 'rm -rf "$TD"' EXIT

printf 'body one\nbody two\n' > "$TD/src.md"
printf 'UPDATED body\n' > "$TD/src2.md"

# ── 1. Absent file → created with the bootstrap header + fenced block ──────────────────────
md_block_upsert "$TD/new.md" pipeline-paths "$TD/src.md"
grep -q '^# Agent notes$' "$TD/new.md" || fail "1: bootstrap header missing"
grep -q '^<!-- supersaiyan:begin id=pipeline-paths -->$' "$TD/new.md" || fail "1: begin marker missing"
grep -q '^<!-- supersaiyan:end id=pipeline-paths -->$' "$TD/new.md" || fail "1: end marker missing"
grep -q '^body one$' "$TD/new.md" || fail "1: block body missing"

# ── 2. Idempotency — a second run changes nothing ──────────────────────────────────────────
cp "$TD/new.md" "$TD/new.before"
md_block_upsert "$TD/new.md" pipeline-paths "$TD/src.md"
diff -q "$TD/new.before" "$TD/new.md" >/dev/null || fail "2: re-run was not idempotent"

# ── 3. Update-in-place — the capability the old substring grep could never deliver ─────────
md_block_upsert "$TD/new.md" pipeline-paths "$TD/src2.md"
grep -q '^UPDATED body$' "$TD/new.md" || fail "3: block was not updated to the new source"
grep -q '^body one$' "$TD/new.md" && fail "3: stale block content survived the update"
[ "$(grep -c '^<!-- supersaiyan:begin id=pipeline-paths -->$' "$TD/new.md")" -eq 1 ] \
  || fail "3: update duplicated the fence instead of replacing in place"

# ── 4. Byte-preservation of user content outside the fence ─────────────────────────────────
cat > "$TD/user.md" <<'EOF'
# My Project

My own paragraph that must survive.

<!-- supersaiyan:begin id=pipeline-paths -->
stale generated content
<!-- supersaiyan:end id=pipeline-paths -->

## My Own Section

Trailing content that must also survive.
EOF
md_block_upsert "$TD/user.md" pipeline-paths "$TD/src2.md"
grep -q '^# My Project$' "$TD/user.md" || fail "4: user H1 lost"
grep -q '^My own paragraph that must survive\.$' "$TD/user.md" || fail "4: user paragraph lost"
grep -q '^## My Own Section$' "$TD/user.md" || fail "4: user section lost"
grep -q '^Trailing content that must also survive\.$' "$TD/user.md" || fail "4: trailing content lost"
grep -q '^UPDATED body$' "$TD/user.md" || fail "4: block not updated"
grep -q '^stale generated content$' "$TD/user.md" && fail "4: stale content survived"

# ── 5. Multiple distinct block ids coexist in one file ─────────────────────────────────────
md_block_upsert "$TD/user.md" gstack-paths "$TD/src.md"
grep -q '^<!-- supersaiyan:begin id=gstack-paths -->$' "$TD/user.md" || fail "5: second block not added"
grep -q '^UPDATED body$' "$TD/user.md" || fail "5: first block clobbered by the second"
md_block_upsert "$TD/user.md" pipeline-paths "$TD/src2.md"
[ "$(grep -c '^<!-- supersaiyan:begin id=gstack-paths -->$' "$TD/user.md")" -eq 1 ] \
  || fail "5: updating one block disturbed the other"

# ── 6. Broken fence (begin without end) → exit 65, file byte-unchanged ─────────────────────
cat > "$TD/broken.md" <<'EOF'
# Notes

<!-- supersaiyan:begin id=pipeline-paths -->
orphaned content, no end marker
EOF
cp "$TD/broken.md" "$TD/broken.before"
set +e
md_block_upsert "$TD/broken.md" pipeline-paths "$TD/src.md" 2>"$TD/err.txt"
RC=$?
set -e
[ "$RC" -eq 65 ] || fail "6: expected exit 65 for an unterminated fence, got $RC"
diff -q "$TD/broken.before" "$TD/broken.md" >/dev/null || fail "6: file was modified despite the error"
grep -q 'unterminated' "$TD/err.txt" || fail "6: error message does not explain the problem"

# ── 7. Missing source file → exit 66 ───────────────────────────────────────────────────────
set +e
md_block_upsert "$TD/new.md" pipeline-paths "$TD/does-not-exist.md" 2>/dev/null
RC=$?
set -e
[ "$RC" -eq 66 ] || fail "7: expected exit 66 for a missing source, got $RC"

# ── 8. md_block_check: in-sync / drifted / absent ──────────────────────────────────────────
md_block_upsert "$TD/chk.md" pipeline-paths "$TD/src.md"
set +e
md_block_check "$TD/chk.md" pipeline-paths "$TD/src.md"; [ $? -eq 0 ] || fail "8: in-sync block not reported as 0"
md_block_check "$TD/chk.md" pipeline-paths "$TD/src2.md"; [ $? -eq 1 ] || fail "8: drifted block not reported as 1"
md_block_check "$TD/chk.md" no-such-id "$TD/src.md"; [ $? -eq 2 ] || fail "8: absent block not reported as 2"
md_block_check "$TD/nope.md" pipeline-paths "$TD/src.md"; [ $? -eq 2 ] || fail "8: absent file not reported as 2"
set -e

# ── 9. md_block_excise_legacy: removes the section, backs it up, preserves the rest ────────
cat > "$TD/legacy.md" <<'EOF'
# Agent notes

User intro paragraph.

## SuperSaiyan pipeline paths

| Artifact | Path |
|----------|------|
| Feature specs | `docs/superpowers/specs/x.md` |

A user's own hand-edit inside the legacy section.

## User Section

User content after.
EOF
md_block_excise_legacy "$TD/legacy.md" "SuperSaiyan pipeline paths" "$TD/backup/legacy-block.md" \
  || fail "9: excise reported no-op on a file that has the heading"
grep -q '^## SuperSaiyan pipeline paths$' "$TD/legacy.md" && fail "9: legacy heading survived"
grep -q '^| Feature specs' "$TD/legacy.md" && fail "9: legacy body survived"
grep -q '^# Agent notes$' "$TD/legacy.md" || fail "9: file header lost"
grep -q '^User intro paragraph\.$' "$TD/legacy.md" || fail "9: content before the section lost"
grep -q '^## User Section$' "$TD/legacy.md" || fail "9: following section lost"
grep -q '^User content after\.$' "$TD/legacy.md" || fail "9: content after the section lost"
[ -f "$TD/backup/legacy-block.md" ] || fail "9: backup not written"
grep -q "A user's own hand-edit inside the legacy section\." "$TD/backup/legacy-block.md" \
  || fail "9: backup does not contain the user's hand-edit (data loss)"

# ── 10. excise_legacy on a file without the heading → exit 1, no change ────────────────────
cp "$TD/legacy.md" "$TD/legacy.before"
set +e
md_block_excise_legacy "$TD/legacy.md" "SuperSaiyan pipeline paths" "$TD/backup/again.md"
RC=$?
set -e
[ "$RC" -eq 1 ] || fail "10: expected exit 1 when the heading is absent, got $RC"
diff -q "$TD/legacy.before" "$TD/legacy.md" >/dev/null || fail "10: file changed on a no-op excise"

if [ "$FAIL" -ne 0 ]; then
  echo "error: md-block.sh failed one or more checks" >&2
  exit 1
fi

echo "  ✓ create, idempotency, update-in-place, byte-preservation, multi-block, broken fence, check modes, legacy excise"
echo "PASS: test-md-block.sh"
