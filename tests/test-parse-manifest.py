#!/usr/bin/env python3
"""Regression test: a dispatcher restart must not leave phantom in-flight workers.

Reproduces the real incident: a Review dispatch with no matching `reaped stale
lock` line (Review is the last lane, so nothing else ever proves it finished),
followed by a brand-new dispatcher process starting later in the same day's
manifest file. Before the fix, `parse_manifest()` only recognized the literal
substring "super-board run started" (the native script's wording) and never
reset `inflight` at all — so the stale Review entry from the dead process
would show up as a currently-active worker forever, across the restart.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATUS = ROOT / "scripts" / "super-board-status.py"

spec = importlib.util.spec_from_file_location("super_board_status", STATUS)
assert spec is not None and spec.loader is not None
sbs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sbs)


def _check(condition: bool, message: str) -> None:
    if not condition:
        print(f"FAIL: {message}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    today = "2026-07-30"

    # Cursor fork's exact wording, with a Review dispatch that never gets a
    # matching reap line before the process exits (the real incident shape),
    # followed by a fresh dispatcher process starting later the same day.
    manifest = (
        "[12:35:02] supersaiyan cursor run started — config=demo variant=full "
        "base=main poll=5s idle_recheck=60s max_workers=3\n"
        "[15:07:35] dispatch lane=review issue=#50 pid=33363 claim=bot\n"
        "[15:12:55] ✅ all active-pipeline columns empty and all lanes idle "
        "— exiting cleanly\n"
        "[15:40:03] supersaiyan cursor run started — config=demo variant=full "
        "base=main poll=5s idle_recheck=60s max_workers=3\n"
        "[15:40:18] dispatch lane=build issue=#60 pid=42451 claim=bot\n"
    )

    state = sbs.parse_manifest(manifest, today)
    inflight = state["inflight"]

    _check(
        "review" not in inflight,
        f"phantom Review entry survived the restart: {inflight}",
    )
    _check(
        inflight.get("build", {}).get("issue") == "60",
        f"expected only the new run's #60 build dispatch in-flight, got: {inflight}",
    )

    # All three dispatcher wordings must be recognized, not just Cursor's.
    for wording in (
        "super-board run started",
        "supersaiyan codex run started",
        "supersaiyan cursor run started",
    ):
        text = (
            "[09:00:00] dispatch lane=qa issue=#1 pid=999 claim=bot\n"
            f"[09:05:00] {wording} — config=demo variant=full base=main\n"
        )
        state = sbs.parse_manifest(text, today)
        _check(
            state["inflight"] == {},
            f"{wording!r} did not reset in-flight state: {state['inflight']}",
        )

    print("PASS: test-parse-manifest.py")


if __name__ == "__main__":
    main()
