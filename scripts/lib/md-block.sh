#!/usr/bin/env bash
# scripts/lib/md-block.sh — upsert a marker-fenced block into a Markdown file.
# Sourced (not executed) by install.sh and scripts/setup-gstack-artifacts-path.sh.
#
# Why fences instead of the substring-grep this replaces: the old checks
# (`grep -q "## SuperSaiyan pipeline paths"`) could only SKIP, never UPDATE — so a content fix
# in a later SuperSaiyan version never reached an already-installed repo. A fenced block can be
# rewritten in place on every re-run while byte-preserving everything outside it.
#
# NOT copied into target repos: install.sh's copy loop takes a hardcoded script list, and
# scripts/lib/ is not in it. These functions run only from a SuperSaiyan checkout.
#
# bash 3.2 (macOS default) — no mapfile, no declare -A, no readarray. awk does the work.

# Fence format. Markers are matched by EXACT STRING EQUALITY in awk ($0 == marker), never as a
# regex, so nothing in an id or path can be interpreted as a metacharacter.
md_block_begin_marker() { printf '<!-- supersaiyan:begin id=%s -->' "$1"; }
md_block_end_marker()   { printf '<!-- supersaiyan:end id=%s -->' "$1"; }

_md_block_render() {
  # $1 = file, $2 = id, $3 = source file. Prints the would-be file content to stdout.
  # Never writes anything — md_block_upsert and md_block_check both build from this, so the
  # "what we'd write" and "what we compare against" can never diverge.
  local file="$1" id="$2" src="$3" begin end
  begin=$(md_block_begin_marker "$id")
  end=$(md_block_end_marker "$id")

  awk -v begin="$begin" -v end="$end" -v src="$src" '
    BEGIN { inside = 0; seen = 0 }
    {
      if ($0 == begin) {
        print begin
        while ((getline line < src) > 0) print line
        close(src)
        inside = 1; seen = 1
        next
      }
      if ($0 == end) { print end; inside = 0; next }
      if (!inside) print
    }
    END {
      if (!seen) {
        # Block absent: append it. A blank separator line only when the file has content and
        # does not already end in one.
        if (NR > 0 && last != "") print ""
        print begin
        while ((getline line < src) > 0) print line
        close(src)
        print end
      }
    }
    { last = $0 }
  ' "$file"
}

md_block_upsert() {
  # $1 = target file, $2 = block id, $3 = source file, $4 = optional bootstrap header.
  # Creates the file if absent, replaces the fenced span if present, appends it if not.
  # Everything outside the fence is byte-preserved.
  local file="$1" id="$2" src="$3" header="${4:-# Agent notes}"
  local begin end has_begin has_end tmp

  if [ ! -f "$src" ]; then
    echo "🛑 md_block_upsert: source not found: $src" >&2
    return 66
  fi

  if [ ! -f "$file" ]; then
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$header" > "$file"
  fi

  begin=$(md_block_begin_marker "$id")
  end=$(md_block_end_marker "$id")
  has_begin=$(awk -v m="$begin" '$0 == m { found = 1 } END { print found + 0 }' "$file")
  has_end=$(awk -v m="$end" '$0 == m { found = 1 } END { print found + 0 }' "$file")

  # A begin without its end means the fence was truncated by a hand-edit. Refuse rather than
  # guess where the block was meant to stop — guessing could swallow the rest of the file.
  if [ "$has_begin" -eq 1 ] && [ "$has_end" -eq 0 ]; then
    echo "🛑 $file has an unterminated supersaiyan block (id=$id): found the begin marker but no matching end." >&2
    echo "    Restore or remove the '$end' line by hand, then re-run. File left untouched." >&2
    return 65
  fi

  tmp=$(mktemp) || { echo "🛑 md_block_upsert: mktemp failed" >&2; return 1; }
  if ! _md_block_render "$file" "$id" "$src" > "$tmp"; then
    rm -f "$tmp"
    echo "🛑 md_block_upsert: failed to render $file (id=$id)" >&2
    return 1
  fi
  mv "$tmp" "$file"
}

md_block_check() {
  # $1 = file, $2 = id, $3 = source. Exit 0 = in sync, 1 = drifted, 2 = block/file absent.
  local file="$1" id="$2" src="$3" begin has_begin tmp rc
  [ -f "$file" ] || return 2
  begin=$(md_block_begin_marker "$id")
  has_begin=$(awk -v m="$begin" '$0 == m { found = 1 } END { print found + 0 }' "$file")
  [ "$has_begin" -eq 1 ] || return 2

  tmp=$(mktemp) || return 1
  _md_block_render "$file" "$id" "$src" > "$tmp"
  if diff -q "$tmp" "$file" >/dev/null 2>&1; then rc=0; else rc=1; fi
  rm -f "$tmp"
  return "$rc"
}

md_block_excise_legacy() {
  # $1 = file, $2 = literal heading text (without leading '## '), $3 = backup path.
  # Removes '## <heading>' through the line before the next '## ' (or EOF), after saving the
  # removed text to the backup. Used to migrate the pre-fence sections this repo used to append
  # directly to a target's CLAUDE.md — lossless, so a hand-edit inside the old section survives
  # in the backup rather than being silently destroyed.
  # Exit 0 = excised, 1 = heading not present (no-op).
  local file="$1" heading="$2" backup="$3" want tmp
  [ -f "$file" ] || return 1
  want="## $heading"
  awk -v m="$want" '$0 == m { found = 1 } END { exit !(found + 0) }' "$file" || return 1

  mkdir -p "$(dirname "$backup")"
  awk -v m="$want" '
    $0 == m { inside = 1 }
    inside && $0 != m && /^## / { inside = 0 }
    inside { print }
  ' "$file" > "$backup"

  tmp=$(mktemp) || return 1
  awk -v m="$want" '
    $0 == m { inside = 1; next }
    inside && /^## / { inside = 0 }
    !inside { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}
