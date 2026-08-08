#!/usr/bin/env python3
"""Regression test: skills/supersaiyan/references/* must match the generated output of
skills/super-board/references/* (see scripts/generate-supersaiyan-references.sh)."""

from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "generate-supersaiyan-references.sh"


def main() -> None:
    subprocess.run(
        ["bash", str(GENERATOR), "--check"],
        cwd=ROOT,
        check=True,
    )
    print("PASS: test-reference-sync.py")


if __name__ == "__main__":
    main()
