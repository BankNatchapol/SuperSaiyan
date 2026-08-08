#!/usr/bin/env bash
# generate-supersaiyan-references.sh — regenerate skills/supersaiyan/references/* from the
# canonical skills/super-board/references/* copies.
#
# skills/super-board/references/ and skills/supersaiyan/references/ used to be two
# independently hand-maintained copies of the same 9 files. They had already drifted apart
# (a "superseded" skip type existed only in the supersaiyan copy). This script makes
# skills/super-board/references/ the single hand-edited source of truth; the supersaiyan
# copies are generated output — never hand-edit them.
#
# Usage:
#   scripts/generate-supersaiyan-references.sh           # write the generated files
#   scripts/generate-supersaiyan-references.sh --check   # verify only; exit non-zero + diff on drift

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT/skills/super-board/references"
DST_DIR="$ROOT/skills/supersaiyan/references"

# Files hand-maintained once in super-board/references/ and mirrored into
# supersaiyan/references/. Files with no super-board counterpart (brainstorm.md, new.md,
# prepare.md, project.md, setup.md, spec.md) are supersaiyan-only and NOT listed here — they
# stay hand-maintained directly in skills/supersaiyan/references/.
FILES=(
  run.md
  config-schema.json
  lint.md
  onboard.md
  status.md
  stop.md
  block-template.md
  rate-limit-etiquette.md
  run-workflow.md
  backends.md
)

CHECK_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    *) echo "unknown arg: $arg (expected --check or no args)" >&2; exit 64 ;;
  esac
done

banner_for() {
  local name="$1"
  case "$name" in
    *.json)
      printf '// GENERATED FILE — edit skills/super-board/references/%s, then run scripts/generate-supersaiyan-references.sh to regenerate. Do not hand-edit.\n' "$name"
      ;;
    *)
      printf '<!-- GENERATED FILE — edit skills/super-board/references/%s, then run scripts/generate-supersaiyan-references.sh to regenerate. Do not hand-edit. -->\n\n' "$name"
      ;;
  esac
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DRIFTED=false
for name in "${FILES[@]}"; do
  src="$SRC_DIR/$name"
  dst="$DST_DIR/$name"
  [ -f "$src" ] || { echo "error: missing source $src" >&2; exit 66; }

  generated="$TMP_DIR/$name"
  { banner_for "$name"; cat "$src"; } > "$generated"

  if [ "$CHECK_ONLY" = true ]; then
    if [ ! -f "$dst" ] || ! diff -q "$generated" "$dst" >/dev/null 2>&1; then
      echo "DRIFT: $dst does not match generated output from $src" >&2
      diff -u "$dst" "$generated" >&2 || true
      DRIFTED=true
    fi
  else
    cp "$generated" "$dst"
    echo "  ✓ generated $dst"
  fi
done

if [ "$CHECK_ONLY" = true ]; then
  if [ "$DRIFTED" = true ]; then
    echo "error: skills/supersaiyan/references/* is out of sync with skills/super-board/references/*." >&2
    echo "       Run scripts/generate-supersaiyan-references.sh (no flags) to fix." >&2
    exit 1
  fi
  echo "OK: skills/supersaiyan/references/* matches generated output from skills/super-board/references/*."
fi
