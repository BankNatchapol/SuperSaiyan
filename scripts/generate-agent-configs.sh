#!/usr/bin/env bash
# generate-agent-configs.sh — regenerate the per-tool agent-config artifacts that are derived
# from a single hand-edited source, so no prose is ever authored twice.
#
# Sibling of scripts/generate-supersaiyan-references.sh, not an extension of it: that script's
# whole contract is whole-file concat (one source dir -> one dest dir) with the mapping baked
# into its --check messages. This one does fenced-region replacement with token substitution
# into pre-existing hand-edited files, plus one whole-file emission. Same conventions, though —
# --check semantics, exit codes, DRIFT reporting, and the "do not hand-edit" banner style.
#
#   ./scripts/generate-agent-configs.sh          # write
#   ./scripts/generate-agent-configs.sh --check  # verify, exit 1 on drift (CI)
#
# bash 3.2 (macOS default) — no declare -A, no mapfile.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCKS="$ROOT/docs/templates/agent-blocks"
ADDENDUM_SRC="$BLOCKS/worker-addendum.md"
MANIFEST_SRC="$BLOCKS/plugin-manifest.json"
MDC="$ROOT/.cursor/rules/supersaiyan-generated-files.mdc"

CHECK=false
if [ $# -gt 0 ]; then
  case "$1" in
    --check) CHECK=true ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
fi

[ -f "$ADDENDUM_SRC" ] || { echo "source not found: $ADDENDUM_SRC" >&2; exit 66; }
[ -f "$MANIFEST_SRC" ] || { echo "source not found: $MANIFEST_SRC" >&2; exit 66; }

DRIFTED=false

# ── Registry ──────────────────────────────────────────────────────────────────────────────
# The single list of what is generated. Drives generation, the drift check, AND the body of
# the Cursor guardrail rule — so the rule can never fall out of step with reality.
# Parallel arrays (bash 3.2 has no associative arrays).
REG_BACKEND_FILE=("scripts/backends/codex-exec.sh" "scripts/backends/cursor-agent.sh")
REG_BACKEND_CLAUSE=('running as `codex exec`' "running as Cursor's \`agent -p\`")
REG_BACKEND_MARKER=("for SuperSaiyan codex-exec dispatch" "for SuperSaiyan cursor-agent dispatch")

REGION_BEGIN="  # supersaiyan:generated:begin worker-addendum"
REGION_END="  # supersaiyan:generated:end worker-addendum"

render_addendum_region() {
  # $1 = CLI clause, $2 = marker. Emits the full fenced region, indented as shell-function body.
  local clause="$1" marker="$2"
  printf '%s\n' "$REGION_BEGIN"
  printf '%s\n' "  # GENERATED REGION — edit docs/templates/agent-blocks/worker-addendum.md, then run"
  printf '%s\n' "  # scripts/generate-agent-configs.sh to regenerate. Do not hand-edit."
  printf '%s\n' "  cat <<'EOF'"
  # Token substitution. awk with a literal string (not sub()) so backticks and slashes in the
  # clause are never treated as regex or replacement metacharacters.
  awk -v clause="$clause" -v marker="$marker" '
    {
      line = $0
      i = index(line, "{{CLI_CLAUSE}}")
      if (i > 0) line = substr(line, 1, i - 1) clause substr(line, i + length("{{CLI_CLAUSE}}"))
      j = index(line, "{{MARKER}}")
      if (j > 0) line = substr(line, 1, j - 1) marker substr(line, j + length("{{MARKER}}"))
      print line
    }
  ' "$ADDENDUM_SRC"
  printf '%s\n' "EOF"
  printf '%s\n' "$REGION_END"
}

render_backend() {
  # $1 = absolute backend path, $2 = clause, $3 = marker. Prints the would-be file to stdout.
  # Replaces an existing region if present; otherwise replaces the body of
  # backend_worker_addendum() wholesale (first-run adoption).
  #
  # The region is passed via a FILE, not `awk -v`: -v mangles embedded newlines (and processes
  # backslash escapes), and the region is inherently multi-line.
  local file="$1" clause="$2" marker="$3" regionfile
  regionfile="$TMPDIR_GEN/region.$$"
  render_addendum_region "$clause" "$marker" > "$regionfile"

  if grep -qF "$REGION_BEGIN" "$file"; then
    awk -v begin="$REGION_BEGIN" -v end="$REGION_END" -v rf="$regionfile" '
      $0 == begin {
        while ((getline line < rf) > 0) print line
        close(rf)
        inside = 1; next
      }
      $0 == end { inside = 0; next }
      !inside   { print }
    ' "$file"
  else
    # First run: swap the hand-written body between `backend_worker_addendum() {` and its
    # closing `}` for the generated region.
    awk -v rf="$regionfile" '
      /^backend_worker_addendum\(\) \{$/ {
        print
        while ((getline line < rf) > 0) print line
        close(rf)
        inside = 1; next
      }
      inside && /^\}$/ { print; inside = 0; next }
      !inside { print }
    ' "$file"
  fi
  rm -f "$regionfile"
}

render_plugin_manifest() {
  # Both Claude Code and Codex use a near-identical plugin manifest — same name/description/
  # version/author/license/keywords, different directory. Generating both from one source is
  # what keeps "publish for two tools" from becoming two places to bump a version.
  # Content is the source verbatim; only the leading comment differs, and JSON has no comment
  # syntax — so the provenance note goes in a "_generated" key instead of a banner line.
  local from="$1"
  python3 - "$MANIFEST_SRC" "$from" <<'PY'
import json, sys
src, frm = sys.argv[1], sys.argv[2]
with open(src) as f:
    data = json.load(f)
# marketplace_description belongs only to marketplace.json — not a plugin.json field.
data.pop("marketplace_description", None)
out = {"_generated": f"GENERATED FILE — edit {frm}, then run scripts/generate-agent-configs.sh. Do not hand-edit."}
out.update(data)
print(json.dumps(out, indent=2, ensure_ascii=False))
PY
}

render_marketplace() {
  # Claude Code additionally needs a marketplace.json wrapping the same plugin entry.
  python3 - "$MANIFEST_SRC" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
out = {
    "_generated": "GENERATED FILE — edit docs/templates/agent-blocks/plugin-manifest.json, then run scripts/generate-agent-configs.sh. Do not hand-edit.",
    "name": d["name"],
    "description": d["marketplace_description"],
    "owner": d["author"],
    "plugins": [
        {
            "name": d["name"],
            "description": d["description"],
            "version": d["version"],
            "source": "./",
            "author": d["author"],
        }
    ],
}
print(json.dumps(out, indent=2, ensure_ascii=False))
PY
}

render_mdc() {
  # Whole-file emission. Frontmatter MUST be line 1 — Cursor does not parse the rule otherwise —
  # so unlike generate-supersaiyan-references.sh's banner_for(), the GENERATED banner is the
  # first BODY line rather than the first line of the file. Deliberate, documented exception.
  cat <<'EOF'
---
description: SuperSaiyan generated-file registry — these paths are machine-written; edit the named source and re-run the generator instead
globs: skills/supersaiyan/references/**,scripts/backends/codex-exec.sh,scripts/backends/cursor-agent.sh,.cursor/rules/**,.claude-plugin/**,.codex-plugin/**
alwaysApply: false
---

<!-- GENERATED FILE — edit scripts/generate-agent-configs.sh's registry, then run
     scripts/generate-agent-configs.sh to regenerate. Do not hand-edit. -->

# Generated files in this repo

The paths below are written by a generator. Editing them directly is silently undone the next
time the generator runs — change the source instead, then regenerate.

| Generated path | Hand-edited source | Regenerate with |
|---|---|---|
EOF
  local i=0
  while [ "$i" -lt "${#REG_BACKEND_FILE[@]}" ]; do
    printf '| `%s` (worker-addendum region) | `docs/templates/agent-blocks/worker-addendum.md` | `scripts/generate-agent-configs.sh` |\n' \
      "${REG_BACKEND_FILE[$i]}"
    i=$((i + 1))
  done
  cat <<'EOF'
| `.claude-plugin/plugin.json` | `docs/templates/agent-blocks/plugin-manifest.json` | `scripts/generate-agent-configs.sh` |
| `.claude-plugin/marketplace.json` | `docs/templates/agent-blocks/plugin-manifest.json` | `scripts/generate-agent-configs.sh` |
| `.codex-plugin/plugin.json` | `docs/templates/agent-blocks/plugin-manifest.json` | `scripts/generate-agent-configs.sh` |
| `.cursor/rules/supersaiyan-generated-files.mdc` | `scripts/generate-agent-configs.sh` (registry) | `scripts/generate-agent-configs.sh` |
| `skills/supersaiyan/references/*` | `skills/super-board/references/*` | `scripts/generate-supersaiyan-references.sh` |

Agent-instruction blocks installed into a target repo's `AGENTS.md` come from
`docs/templates/agent-blocks/` and are written by `install.sh` /
`scripts/setup-gstack-artifacts-path.sh`; edit the block source, not the installed copy.
EOF
}

emit() {
  # $1 = destination path (absolute), $2 = temp file holding the generated content,
  # $3 = source label for messages.
  local dst="$1" generated="$2" src="$3"
  if [ "$CHECK" = true ]; then
    if [ ! -f "$dst" ] || ! diff -q "$generated" "$dst" >/dev/null 2>&1; then
      echo "DRIFT: ${dst#"$ROOT"/} does not match generated output from $src" >&2
      diff -u "$dst" "$generated" >&2 || true
      DRIFTED=true
    fi
  else
    mkdir -p "$(dirname "$dst")"
    cp "$generated" "$dst"
    echo "  ✓ generated ${dst#"$ROOT"/}"
  fi
}

TMPDIR_GEN=$(mktemp -d)
trap 'rm -rf "$TMPDIR_GEN"' EXIT

i=0
while [ "$i" -lt "${#REG_BACKEND_FILE[@]}" ]; do
  rel="${REG_BACKEND_FILE[$i]}"
  abs="$ROOT/$rel"
  [ -f "$abs" ] || { echo "backend not found: $abs" >&2; exit 66; }
  out="$TMPDIR_GEN/$(basename "$rel")"
  render_backend "$abs" "${REG_BACKEND_CLAUSE[$i]}" "${REG_BACKEND_MARKER[$i]}" > "$out"
  emit "$abs" "$out" "docs/templates/agent-blocks/worker-addendum.md"
  i=$((i + 1))
done

render_plugin_manifest "docs/templates/agent-blocks/plugin-manifest.json" > "$TMPDIR_GEN/claude-plugin.json"
emit "$ROOT/.claude-plugin/plugin.json" "$TMPDIR_GEN/claude-plugin.json" "docs/templates/agent-blocks/plugin-manifest.json"

render_plugin_manifest "docs/templates/agent-blocks/plugin-manifest.json" > "$TMPDIR_GEN/codex-plugin.json"
emit "$ROOT/.codex-plugin/plugin.json" "$TMPDIR_GEN/codex-plugin.json" "docs/templates/agent-blocks/plugin-manifest.json"

render_marketplace > "$TMPDIR_GEN/marketplace.json"
emit "$ROOT/.claude-plugin/marketplace.json" "$TMPDIR_GEN/marketplace.json" "docs/templates/agent-blocks/plugin-manifest.json"

render_mdc > "$TMPDIR_GEN/rule.mdc"
emit "$MDC" "$TMPDIR_GEN/rule.mdc" "scripts/generate-agent-configs.sh (registry)"

if [ "$CHECK" = true ]; then
  if [ "$DRIFTED" = true ]; then
    echo "error: generated agent-config artifacts are out of sync with their sources." >&2
    echo "       Run scripts/generate-agent-configs.sh (no flags) to fix." >&2
    exit 1
  fi
  echo "OK: generated agent-config artifacts match their sources."
fi
