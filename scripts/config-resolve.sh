#!/usr/bin/env bash
# scripts/config-resolve.sh — resolves an optional `extends` link before any config field is
# read. Sourced (not executed) by scripts/super-board-run.sh and scripts/super-board-wave-plan.sh.
# See references/config-schema.json (`extends`) for the field contract.

resolve_config_extends() {
  # $1 = path to a config file, possibly with `.extends` set.
  #
  # On success, prints the path to an EFFECTIVE config file to stdout — the caller reassigns
  # its CONFIG_PATH/CONFIG variable to this path. Every existing `jq -r '.field' "$CONFIG_PATH"`
  # call site downstream keeps working completely unchanged, since it's still just reading a
  # file path — that path may now point at a merged temp file instead of the original.
  #
  # Returns 0 with the SAME path unchanged when `.extends` is absent/null/empty (the common
  # case — zero extra jq calls or temp files beyond the one check). Returns non-zero with a
  # message on stderr on any resolution failure. Callers MUST check the exit code themselves:
  # this function never calls `exit` — it is typically invoked inside `$(...)`, where `exit`
  # would only kill the subshell, not the caller.
  local raw="$1" dir ext base_path base_ext merged
  if [ ! -f "$raw" ]; then
    echo "config not found: $raw" >&2
    return 1
  fi

  ext=$(jq -r '.extends // empty' "$raw" 2>/dev/null) || {
    echo "🛑 invalid JSON: $raw" >&2
    return 1
  }
  if [ -z "$ext" ]; then
    printf '%s\n' "$raw"
    return 0
  fi

  dir="$(dirname "$raw")"
  base_path="$dir/${ext}.json"
  if [ ! -f "$base_path" ]; then
    echo "🛑 $raw sets \"extends\": \"${ext}\" but $base_path does not exist." >&2
    return 1
  fi

  base_ext=$(jq -r '.extends // empty' "$base_path" 2>/dev/null) || {
    echo "🛑 invalid JSON: $base_path" >&2
    return 1
  }
  if [ -n "$base_ext" ]; then
    echo "🛑 $base_path (the base for $raw) itself sets \"extends\" — chained extends are not supported." >&2
    return 1
  fi

  merged=$(mktemp) || { echo "🛑 mktemp failed while resolving $raw" >&2; return 1; }
  if ! jq -s '.[0] * .[1] | del(.extends)' "$base_path" "$raw" > "$merged" 2>/dev/null; then
    echo "🛑 failed to merge $base_path + $raw" >&2
    rm -f "$merged"
    return 1
  fi
  printf '%s\n' "$merged"
}
