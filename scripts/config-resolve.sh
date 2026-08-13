#!/usr/bin/env bash
# scripts/config-resolve.sh — resolves an optional `extends` link before any config field is
# read. Sourced (not executed) by scripts/super-board-run.sh and scripts/super-board-wave-plan.sh.
# Also usable as a standalone CLI (see `--effective-path` at the bottom) — this is how the
# workflow-backend orchestrator (references/run-workflow.md) resolves `extends` before Launch,
# since Workflow scripts (scripts/super-board-wave.js) have no filesystem access and cannot
# call resolve_config_extends() themselves.
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

persist_resolved_config() {
  # $1 = path to a config file (relative or absolute), possibly with `.extends` set. Expected
  # to sit at <root>/configs/<slug>.json — every real caller's CONFIG_PATH does.
  #
  # Prints an ABSOLUTE, STABLE path to stdout: the effective config a caller should hand to
  # anything that might read it from a different cwd or outlive this process — e.g. a worker
  # prompt embedded by dispatch_lane, where the worker runs from a git worktree, not this repo
  # root (see references/run.md). resolve_config_extends() alone is not safe for that use: it
  # returns an mktemp path that (a) is meaningless once this process's EXIT trap removes it and
  # (b) is only guaranteed readable from the cwd it was created in.
  #
  # No `.extends` (the common case): returns the ABSOLUTE form of the input unchanged — no
  # write, no new file, nothing to clean up.
  #
  # `.extends` set: persists the merged view to <root>/resolved/<slug>.json — sibling of
  # configs/, deliberately NOT inside it. Every config consumer (platform-config.sh's config
  # count, super-board-status.py's configs/*.json glob, control-core's discoverConfigs) treats
  # each file directly under configs/ as a board; a resolved copy there would register as a
  # phantom extra board and break sole-config detection. Overwritten on each call — the
  # previous call's copy lingering is a feature when debugging what a worker was actually
  # handed, not a bug.
  #
  # Write is atomic: cp to a same-directory .tmp.$$ file, then mv (same-directory rename is
  # atomic; a cross-device mv — e.g. the mktemp dir living on tmpfs while the repo does not,
  # common on Linux CI — is not). This also preserves resolve_config_extends()'s existing
  # contract that its returned mktemp file gets consumed, never left behind.
  local raw="$1" abs_raw resolved_tmp configs_dir root slug persisted_dir persisted tmp_persisted
  if [ ! -f "$raw" ]; then
    echo "config not found: $raw" >&2
    return 1
  fi
  abs_raw="$(cd "$(dirname "$raw")" && pwd)/$(basename "$raw")"

  resolved_tmp=$(resolve_config_extends "$raw") || return 1

  if [ "$resolved_tmp" = "$raw" ]; then
    printf '%s\n' "$abs_raw"
    return 0
  fi

  configs_dir="$(dirname "$abs_raw")"
  root="$(dirname "$configs_dir")"
  slug="$(basename "$abs_raw" .json)"
  persisted_dir="$root/resolved"
  mkdir -p "$persisted_dir" || {
    echo "🛑 could not create $persisted_dir" >&2
    rm -f "$resolved_tmp"
    return 1
  }
  persisted="$persisted_dir/${slug}.json"
  tmp_persisted="$persisted.tmp.$$"

  if ! cp "$resolved_tmp" "$tmp_persisted"; then
    echo "🛑 failed to stage resolved config at $tmp_persisted" >&2
    rm -f "$resolved_tmp" "$tmp_persisted"
    return 1
  fi
  if ! mv "$tmp_persisted" "$persisted"; then
    echo "🛑 failed to publish resolved config to $persisted" >&2
    rm -f "$resolved_tmp" "$tmp_persisted"
    return 1
  fi
  rm -f "$resolved_tmp"
  printf '%s\n' "$persisted"
}

# ─────────────────────────────────── CLI mode ───────────────────────────────────
# Only when executed directly (not sourced) — sourcing behavior above is completely
# unaffected. This is how a consumer with no way to `source` a bash function calls in: the
# workflow-backend orchestrator (a Claude Code session, not a bash script) shells out to
# `bash .supersaiyan/bin/config-resolve.sh --effective-path <config-path>` before Launch,
# since scripts/super-board-wave.js (a Workflow script) has no filesystem access and cannot
# resolve `extends` itself. See references/run-workflow.md.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    --effective-path)
      [ -n "${2:-}" ] || {
        echo "usage: config-resolve.sh --effective-path <config-path>" >&2
        exit 64
      }
      persist_resolved_config "$2"
      exit $?
      ;;
    *)
      echo "usage: config-resolve.sh --effective-path <config-path>" >&2
      exit 64
      ;;
  esac
fi
