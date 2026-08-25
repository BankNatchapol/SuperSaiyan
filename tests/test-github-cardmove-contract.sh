#!/usr/bin/env bash
# test-github-cardmove-contract.sh — the GitHub adapter must implement the documented
# `platform_card_status_set <issue> <column>` signature.
#
# Regression guard: references/platforms.md has always specified `<issue> <column>`, and the
# GitLab adapter implements it — but GitHub's took `<item_id> <project_id> <field_id>
# <option_id>`, so `platform_card_status_set 42 Building` resolved to
# `gh project item-edit --id 42 --project-id Building --field-id "" ...`. It went unnoticed
# because no production caller used that form (only `--add`) and tests/test-platform-contract.sh
# checks function *names*, never signatures.
#
# GitLab's equivalent coverage lives in tests/test-gitlab-cardmove-race.sh.
# `gh` is stubbed on PATH; no live API traffic.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="$ROOT/scripts/platforms/github.sh"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

[ -f "$ADAPTER" ] || { echo "error: $ADAPTER not found" >&2; exit 1; }

echo "checking GitHub platform_card_status_set signature contract"

bash -n "$ADAPTER" || fail "bash -n reported a syntax error in platforms/github.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cat > "$TMP/config.json" <<'JSON'
{ "variant": "full", "git_platform": "github", "project": { "number": 3, "owner": "acme" } }
JSON

# Stubbed gh: records every invocation, and answers the three reads the contract form makes.
# Issue #42 is item PVTI_card42 on the board; #99 is not on the board at all.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_CALLS"
case "$1 $2" in
  "project view")
    echo "PVT_proj3" ;;
  "project field-list")
    cat <<'JSON'
{"fields":[{"id":"PVTSSF_status","name":"Status","options":[
  {"id":"opt_ready","name":"Ready"},
  {"id":"opt_building","name":"Building"},
  {"id":"opt_qa","name":"QA"}]}]}
JSON
    ;;
  "project item-list")
    cat <<'JSON'
{"items":[
  {"id":"PVTI_card42","status":"Ready","content":{"type":"Issue","number":42,"title":"t","url":"https://x/42"}},
  {"id":"PVTI_card43","status":"QA","content":{"type":"Issue","number":43,"title":"u","url":"https://x/43"}}]}
JSON
    ;;
  "project item-edit")
    : ;;
  *) : ;;
esac
STUB
chmod +x "$TMP/bin/gh"

# $1 = expected exit code, then the platform_card_status_set args.
# Sets CALLS to the recorded gh invocations. Runs in the current shell (not a command
# substitution) so the exit-code assertion can report through $FAIL.
CALLS=""
call_adapter() {
  local want="$1"; shift
  local calls="$TMP/calls"
  : > "$calls"
  local rc=0
  PATH="$TMP/bin:$PATH" GH_CALLS="$calls" PLATFORM_CONFIG_PATH="$TMP/config.json" \
    ADAPTER="$ADAPTER" bash -c '
      set -uo pipefail
      source "$ADAPTER"
      platform_card_status_set "$@" >/dev/null 2>&1
    ' _ "$@" || rc=$?
  [ "$rc" -eq "$want" ] || fail "platform_card_status_set $* exited $rc, wanted $want"
  CALLS=$(cat "$calls")
}

# ── 1. Contract form: <issue> <column> ─────────────────────────────────────────────
call_adapter 0 42 Building
echo "$CALLS" | grep -q 'gh project item-edit .*--id PVTI_card42' \
  || fail "did not resolve issue #42 to its project item id (got: $(echo "$CALLS" | tr '\n' '|'))"
echo "$CALLS" | grep -q -- '--project-id PVT_proj3' \
  || fail "did not resolve the project id"
echo "$CALLS" | grep -q -- '--field-id PVTSSF_status' \
  || fail "did not resolve the Status field id"
echo "$CALLS" | grep -q -- '--single-select-option-id opt_building' \
  || fail "did not resolve the Building option id"
# Exactly one mutation — the resolution reads must not double-issue the edit.
EDITS=$(echo "$CALLS" | grep -c 'project item-edit' || true)
[ "$EDITS" -eq 1 ] || fail "expected exactly 1 item-edit mutation, got $EDITS"

# ── 2. The legacy 4-arg id form still works ───────────────────────────────────────
# Installed app repos may hold callers that resolved the ids themselves.
call_adapter 0 PVTI_x PVT_y PVTSSF_z opt_w
echo "$CALLS" | grep -q 'gh project item-edit --id PVTI_x --project-id PVT_y --field-id PVTSSF_z --single-select-option-id opt_w' \
  || fail "legacy 4-arg form no longer passes ids straight through"
echo "$CALLS" | grep -q 'project view\|project field-list' \
  && fail "legacy 4-arg form must not spend resolution calls — the ids are already resolved"

# ── 3. A column the board does not have fails loudly ──────────────────────────────
# This is what a qa-only board asked for "Building" must do: refuse, not mutate.
call_adapter 65 42 Nonexistent
echo "$CALLS" | grep -q 'project item-edit' \
  && fail "an unknown column still issued a mutation"

# ── 4. An issue that is not on the board fails loudly ─────────────────────────────
call_adapter 65 99 Building
echo "$CALLS" | grep -q 'project item-edit' \
  && fail "an off-board issue still issued a mutation"

# ── 5. Missing args are a usage error, never a silent partial mutation ────────────
call_adapter 64 42
echo "$CALLS" | grep -q 'project item-edit' \
  && fail "a one-arg call still issued a mutation"

# ── 6. The documented contract still says <issue> <column> ────────────────────────
grep -q 'platform_card_status_set <issue> <column>' "$ROOT/skills/super-board/references/platforms.md" \
  || fail "references/platforms.md no longer documents the <issue> <column> contract"

if [ "$FAIL" -ne 0 ]; then
  echo "error: GitHub card-move contract check failed" >&2
  exit 1
fi

echo "PASS: test-github-cardmove-contract.sh"
