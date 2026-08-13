#!/usr/bin/env python3
"""Drift check for generated agent-config artifacts.

Mirrors tests/test-reference-sync.py: the generator's own --check mode is the assertion, and
its stderr (DRIFT: lines + unified diffs) is the failure output.
"""

from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "generate-agent-configs.sh"


def main() -> None:
    subprocess.run(
        ["bash", str(GENERATOR), "--check"],
        cwd=ROOT,
        check=True,
    )
    print("PASS: test-agent-config-sync.py")


if __name__ == "__main__":
    main()
