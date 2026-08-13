#!/usr/bin/env bash
# test-config-root-fallback.sh — verifies the three-tier config/state root fallback chain
# (.supersaiyan -> .claude/supersaiyan -> .claude/super-board), added when board config/state
# moved out from under Claude Code's own .claude/ directory to the vendor-neutral .supersaiyan/
# root. Covers scripts/super-board-run.sh directly and the three-tier backend-script lookup in
# skills/super-build/scripts/super-build-dispatch.sh (skills/super-qa/scripts/super-qa-dispatch.sh
# shares the identical logic). No live board/GitHub traffic.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SH="$ROOT/scripts/super-board-run.sh"
BUILD_DISPATCH="$ROOT/skills/super-build/scripts/super-build-dispatch.sh"

FAIL=0
fail() { echo "  FAIL: $1" >&2; FAIL=1; }

echo "checking config/state root fallback chain"

TD=$(mktemp -d)
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$TD" "$STUB_DIR"' EXIT

mkdir -p "$STUB_DIR/bin"
cat > "$STUB_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB_DIR/bin/claude"

setup_repo() {
  # Fresh scratch dir mirroring the dev-repo layout dispatch scripts need to source siblings.
  # `rm -rf "$TD"/*` alone would NOT clear dotfiles (bash glob doesn't match leading `.` by
  # default) — a prior scenario's .claude/ or .supersaiyan/ would silently leak into the next
  # one and pollute which root wins. Remove and recreate the whole directory instead.
  rm -rf "${TD:?}"
  mkdir -p "$TD/scripts/platforms" "$TD/scripts/backends" \
           "$TD/docs/supersaiyan/runs" "$TD/.worktrees"
  cp "$RUN_SH" "$TD/scripts/super-board-run.sh"
  cp "$ROOT/scripts/config-resolve.sh" "$TD/scripts/config-resolve.sh"
  cp "$ROOT/scripts/platforms/github.sh" "$TD/scripts/platforms/github.sh"
  cp "$ROOT/scripts/backends/claude-p.sh" "$TD/scripts/backends/claude-p.sh"
  chmod +x "$TD/scripts/super-board-run.sh"
}

board_cfg() {
  printf '%s' '{"variant":"full","base_branch":"develop","human_approves_merge":true,"max_workers":1,"tick_seconds":120,"git_platform":"github","worker_backend":"claude-p","project":{"owner":"o","number":1,"status_field_id":"P","status_option_ids":{}},"notifications":{"bot_identity":""}}'
}

run_dispatcher() {
  # $1 = slug (empty for active-pointer mode)
  set +e
  OUT=$(cd "$TD" && PATH="$STUB_DIR/bin:$PATH" bash scripts/super-board-run.sh "$1" 2>&1)
  RC=$?
  set -e
}

# ── 1. Config exists ONLY under the current-legacy root (.claude/supersaiyan) ──────────────
setup_repo
mkdir -p "$TD/.claude/supersaiyan/configs"
board_cfg > "$TD/.claude/supersaiyan/configs/board.json"
run_dispatcher board
echo "$OUT" | grep -q "config=board" || fail "tier-2-only (.claude/supersaiyan) config was not found"
[ -d "$TD/.claude/supersaiyan/inflight" ] || fail "tier-2-only run did not colocate inflight/ under the resolved root"
[ -d "$TD/.supersaiyan" ] && fail "tier-2-only run created a stray .supersaiyan directory" || true

# ── 2. Config exists ONLY under the oldest-legacy root (.claude/super-board) ────────────────
setup_repo
mkdir -p "$TD/.claude/super-board/configs"
board_cfg > "$TD/.claude/super-board/configs/board.json"
run_dispatcher board
echo "$OUT" | grep -q "config=board" || fail "tier-3-only (.claude/super-board) config was not found"
[ -d "$TD/.claude/super-board/inflight" ] || fail "tier-3-only run did not colocate inflight/ under the resolved root"

# ── 3. Same slug under BOTH the new root and a legacy root — new root must win ─────────────
setup_repo
mkdir -p "$TD/.supersaiyan/configs" "$TD/.claude/supersaiyan/configs"
board_cfg > "$TD/.supersaiyan/configs/board.json"
# Legacy copy differs (base_branch) so the startup log line proves which one was actually read.
printf '%s' '{"variant":"full","base_branch":"WRONG-OLD-BRANCH","human_approves_merge":true,"max_workers":1,"tick_seconds":120,"git_platform":"github","worker_backend":"claude-p","project":{"owner":"o","number":2,"status_field_id":"P","status_option_ids":{}},"notifications":{"bot_identity":""}}' \
  > "$TD/.claude/supersaiyan/configs/board.json"
run_dispatcher board
echo "$OUT" | grep -q "base=develop" || fail "collision: expected the NEW root's config content, got: $(echo "$OUT" | head -1)"
echo "$OUT" | grep -q "WRONG-OLD-BRANCH" && fail "collision: dispatcher read the legacy root's config instead of the new one"
[ -d "$TD/.supersaiyan/inflight" ] || fail "collision: inflight/ was not colocated under the winning (new) root"

# ── 4. No slug given — active pointer under a legacy root supplies it ──────────────────────
setup_repo
mkdir -p "$TD/.claude/super-board/configs"
board_cfg > "$TD/.claude/super-board/configs/fromactive.json"
echo "fromactive" > "$TD/.claude/super-board/active"
run_dispatcher ""
echo "$OUT" | grep -q "config=fromactive" || fail "active pointer under the oldest legacy root was not honored"

# ── 5. Backend-script three-tier lookup (super-build-dispatch.sh) — old-installed only ─────
BUILD_TD=$(mktemp -d)
mkdir -p "$BUILD_TD/skills/super-build/scripts" "$BUILD_TD/.claude/bin/backends"
cp "$BUILD_DISPATCH" "$BUILD_TD/skills/super-build/scripts/super-build-dispatch.sh"
echo '# old-installed marker' > "$BUILD_TD/.claude/bin/backends/claude-p.sh"
RESOLVED=$(
  cd "$BUILD_TD" && REPO_DIR="$PWD" SCRIPT_DIR="$PWD/skills/super-build/scripts" WORKER_BACKEND=claude-p bash -c '
    BACKEND_FILE="$REPO_DIR/.supersaiyan/bin/backends/${WORKER_BACKEND}.sh"
    if [[ ! -f "$BACKEND_FILE" ]]; then BACKEND_FILE="$REPO_DIR/.claude/bin/backends/${WORKER_BACKEND}.sh"; fi
    if [[ ! -f "$BACKEND_FILE" ]]; then BACKEND_FILE="$SCRIPT_DIR/../../../scripts/backends/${WORKER_BACKEND}.sh"; fi
    echo "$BACKEND_FILE"
  '
)
case "$RESOLVED" in
  */.claude/bin/backends/claude-p.sh) ;;
  *) fail "backend-script fallback did not resolve the old-installed (.claude/bin) tier, got: $RESOLVED" ;;
esac
rm -rf "$BUILD_TD"

if [ "$FAIL" -ne 0 ]; then
  echo "error: config/state root fallback chain failed one or more checks" >&2
  exit 1
fi

echo "  ✓ tier-2-only, tier-3-only, new-root-wins-on-collision, active-pointer-via-legacy-root, backend-script fallback"
echo "PASS: test-config-root-fallback.sh"
