#!/usr/bin/env python3
"""The SuperSaiyan directory map in AGENTS.md must name real paths.

Guards the #44 class of drift: a rewritten map that lists stale top-level
trees, or a skills/ listing that omits directories that actually exist.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AGENTS = ROOT / "AGENTS.md"


def _map_block() -> str:
    text = AGENTS.read_text(encoding="utf-8")
    match = re.search(
        r"## SuperSaiyan directory map\n+```text\n(.*?)```",
        text,
        re.DOTALL,
    )
    if not match:
        raise AssertionError("AGENTS.md is missing the SuperSaiyan directory map fence")
    return match.group(1)


def extract_map_entries() -> list[tuple[str, bool]]:
    """Return (relative_path, gitignored) for each entry under SuperSaiyan/."""
    entries: list[tuple[str, bool]] = []
    stack: list[tuple[int, str]] = []
    for raw in _map_block().splitlines():
        if not raw.strip():
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        token = raw.strip().split()[0]
        gitignored = "gitignored" in raw.lower()
        while stack and stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1] if stack else ""
        if token.rstrip("/") == "SuperSaiyan":
            stack.append((indent, ""))
            continue
        rel = f"{parent}{token}"
        entries.append((rel, gitignored))
        if token.endswith("/"):
            stack.append((indent, rel))
    return entries


def main() -> int:
    fail = 0
    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    entries = extract_map_entries()
    if not entries:
        print("FAIL: directory map parsed to zero paths", file=sys.stderr)
        return 1

    mapped = {rel.rstrip("/") for rel, _ in entries}
    for rel, gitignored in entries:
        path = ROOT / rel
        if gitignored:
            name = rel.rstrip("/")
            if name not in gitignore and f"{name}/" not in gitignore:
                print(f"FAIL: map marks {rel} gitignored, but it is not in .gitignore", file=sys.stderr)
                fail += 1
            continue
        if not path.exists():
            print(f"FAIL: map path does not exist: {rel}", file=sys.stderr)
            fail += 1

    skills_dir = ROOT / "skills"
    for child in sorted(p.name for p in skills_dir.iterdir() if p.is_dir() and not p.name.startswith(".")):
        listed = f"skills/{child}"
        if listed not in mapped:
            print(f"FAIL: skills/{child}/ exists but is missing from the directory map", file=sys.stderr)
            fail += 1

    if fail:
        return 1
    print(f"PASS: test-agents-md-map.py ({len(entries)} map paths)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
