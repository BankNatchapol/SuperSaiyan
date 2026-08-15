#!/usr/bin/env bash
# Shared SuperSaiyan platform-config resolution.
#
# This file is sourced by pipeline scripts from either scripts/ (toolkit
# checkout) or .claude/bin/ (installed app layout). It intentionally uses only
# Bash 3.2-compatible features.

platform_config_resolve() {
  # Usage: platform_config_resolve <repo-root> [explicit-config]
  # Precedence: explicit config, PLATFORM_CONFIG_PATH, valid active pointer,
  # sole config, then no config (empty output).
  local repo_root="${1:-$PWD}"
  local explicit_config="${2:-}"
  local selected=""
  local configs_dir active_file active_slug candidate root
  local config_count=0 sole_config=""

  repo_root=$(cd "$repo_root" 2>/dev/null && pwd) || {
    echo "repository root not found: $repo_root" >&2
    return 66
  }

  # Config/state root search order, highest priority first: the vendor-neutral root (where new
  # onboards write), then the two Claude-Code-branded roots this project used before multi-tool
  # worker_backend support. Matches scripts/super-board-run.sh's CONFIG_ROOTS and
  # scripts/super-board-status.py's config_roots() — three independent implementations of one
  # contract, kept deliberately in step. First root that has an `active` pointer or any config
  # wins; a pre-migration install keeps resolving with no migration step.
  local config_roots=".supersaiyan .claude/supersaiyan .claude/super-board"
  configs_dir=""
  active_file=""
  for root in $config_roots; do
    if [ -f "$repo_root/$root/active" ] || [ -d "$repo_root/$root/configs" ]; then
      configs_dir="$repo_root/$root/configs"
      active_file="$repo_root/$root/active"
      break
    fi
  done
  # No root present at all — keep the new root's paths so error messages name where to onboard.
  if [ -z "$configs_dir" ]; then
    configs_dir="$repo_root/.supersaiyan/configs"
    active_file="$repo_root/.supersaiyan/active"
  fi

  if [ -n "$explicit_config" ]; then
    selected="$explicit_config"
  elif [ -n "${PLATFORM_CONFIG_PATH:-}" ]; then
    selected="$PLATFORM_CONFIG_PATH"
  elif [ -f "$active_file" ]; then
    active_slug=$(tr -d '[:space:]' < "$active_file")
    if [ -z "$active_slug" ]; then
      echo "active config pointer is empty: $active_file" >&2
      return 65
    fi
    selected="$configs_dir/${active_slug}.json"
    if [ ! -f "$selected" ]; then
      echo "active config not found: $selected" >&2
      return 66
    fi
  elif [ -d "$configs_dir" ]; then
    for candidate in "$configs_dir"/*.json; do
      [ -f "$candidate" ] || continue
      config_count=$((config_count + 1))
      sole_config="$candidate"
    done
    if [ "$config_count" -eq 1 ]; then
      selected="$sole_config"
    elif [ "$config_count" -gt 1 ]; then
      echo "multiple supersaiyan configs found; pass an explicit config or set ${configs_dir%/configs}/active" >&2
      return 75
    fi
  fi

  if [ -z "$selected" ]; then
    printf '\n'
    return 0
  fi

  case "$selected" in
    /*) ;;
    *) selected="$repo_root/$selected" ;;
  esac
  if [ ! -f "$selected" ]; then
    echo "config not found: $selected" >&2
    return 66
  fi

  selected=$(cd "$(dirname "$selected")" 2>/dev/null && pwd)/$(basename "$selected")
  printf '%s\n' "$selected"
}

platform_config_effective() {
  # Usage: platform_config_effective <raw-config-path-or-empty>
  # Field-read view of a path returned by platform_config_resolve. Empty in → empty out
  # (no config selected). Otherwise persist_resolved_config: no `extends` returns the
  # absolute raw path; `extends` set persists the merge under <root>/resolved/.
  # Identity (slug, --config, board discovery) stays on the raw path —
  # never substitute this function's output for platform_config_resolve.
  # Adapters export this function's output as PLATFORM_CONFIG_PATH (field-complete;
  # no `extends`). A child must not feed that env value back into this function:
  # re-entry on resolved/ is already a hard error.
  #
  # persist_resolved_config() lives in the sibling config-resolve.sh — same directory
  # whether this file is scripts/platform-config.sh (dev checkout) or
  # .supersaiyan/bin/platform-config.sh (installed). Sourced lazily so identity-only
  # callers of platform_config_resolve don't require the sibling.
  local raw="${1:-}" dir
  if [ -z "$raw" ]; then
    printf '\n'
    return 0
  fi
  if ! type persist_resolved_config >/dev/null 2>&1; then
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ ! -f "$dir/config-resolve.sh" ]; then
      echo "config resolver not found: $dir/config-resolve.sh" >&2
      return 66
    fi
    # shellcheck disable=SC1091
    . "$dir/config-resolve.sh"
  fi
  persist_resolved_config "$raw"
}

platform_config_resolve_platform() {
  # Usage: platform_config_resolve_platform <config-path-or-empty> [env-platform]
  # A selected config is authoritative. A contradictory inherited
  # GIT_PLATFORM is rejected instead of changing forge adapters.
  local config_path="${1:-}"
  local env_platform="${2:-}"
  local selected_platform=""

  if [ -n "$config_path" ]; then
    selected_platform=$(jq -er \
      '(.git_platform // "github") | select(type == "string" and length > 0)' \
      "$config_path" 2>/dev/null) || {
      echo "invalid git_platform in config: $config_path" >&2
      return 65
    }
    if [ -n "$env_platform" ] && [ "$env_platform" != "$selected_platform" ]; then
      echo "GIT_PLATFORM '$env_platform' conflicts with config git_platform '$selected_platform'" >&2
      return 65
    fi
  else
    selected_platform="${env_platform:-github}"
  fi

  case "$selected_platform" in
    github|gitlab) ;;
    *)
      echo "invalid git_platform: $selected_platform" >&2
      return 77
      ;;
  esac
  printf '%s\n' "$selected_platform"
}
