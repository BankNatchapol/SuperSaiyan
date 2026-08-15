#!/usr/bin/env python3
"""Contract for the spec→task Open Questions gate.

Hard-refuse only when an equivalent heading is present and still lists
unresolved items. A missing heading is warn-and-ask, not a refusal — the
repo's real spec uses ## Open judgment calls, and office-hours output is
not guaranteed to emit ## Open Questions.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WRITING = ROOT / "skills" / "writing-board-tasks" / "SKILL.md"
REFINING = ROOT / "skills" / "refining-spec" / "SKILL.md"
GITLAB_SPEC = ROOT / "docs" / "superpowers" / "specs" / "gitlab-integration-design.md"

EQUIVALENT_HEADINGS = (
    "Open Questions",
    "Open judgment calls",
    "Unresolved",
)
HEADING_RE = re.compile(
    r"^## (" + "|".join(re.escape(h) for h in EQUIVALENT_HEADINGS) + r")\s*$",
    re.MULTILINE | re.IGNORECASE,
)


def classify(spec: str) -> str:
    """Return ok | warn-missing | refuse-unresolved."""
    match = HEADING_RE.search(spec)
    if not match:
        return "warn-missing"
    start = match.end()
    nxt = re.search(r"^## ", spec[start:], re.MULTILINE)
    body = spec[start : start + nxt.start() if nxt else None].strip()
    if not body or body.lower().strip(" .") == "none":
        return "ok"
    return "refuse-unresolved"


def main() -> int:
    fail = 0

    def check(cond: bool, msg: str) -> None:
        nonlocal fail
        if not cond:
            print(f"FAIL: {msg}", file=sys.stderr)
            fail += 1

    check(classify("## Requirements\n\nShip it.\n") == "warn-missing", "missing heading should warn, not refuse")
    check(classify("## Open Questions\n\nNone\n") == "ok", "Open Questions / None should be ok")
    check(classify("## Open Questions\n\n") == "ok", "empty Open Questions should be ok")
    check(
        classify("## Open judgment calls\n\nNone\n") == "ok",
        "Open judgment calls / None should be ok",
    )
    check(
        classify("## Unresolved\n\nNone\n") == "ok",
        "Unresolved / None should be ok",
    )
    check(
        classify("## Open Questions\n\n- How should retries work?\n") == "refuse-unresolved",
        "heading plus unresolved items should refuse",
    )
    check(
        classify("## Open judgment calls\n\n1. Still undecided.\n") == "refuse-unresolved",
        "equivalent heading plus unresolved items should refuse",
    )

    gitlab = GITLAB_SPEC.read_text(encoding="utf-8")
    check(GITLAB_SPEC.is_file(), "gitlab-integration-design.md should exist")
    check(
        classify(gitlab) != "warn-missing",
        "gitlab-integration-design.md must match an equivalent Open Questions heading",
    )
    check(
        HEADING_RE.search(gitlab) is not None
        and HEADING_RE.search(gitlab).group(1).lower() == "open judgment calls",
        "gitlab spec should be recognized via ## Open judgment calls",
    )

    writing = WRITING.read_text(encoding="utf-8")
    refining = REFINING.read_text(encoding="utf-8")
    for heading in EQUIVALENT_HEADINGS:
        check(
            heading.lower() in writing.lower(),
            f"writing-board-tasks SKILL.md should mention equivalent heading {heading!r}",
        )
        check(
            heading.lower() in refining.lower(),
            f"refining-spec SKILL.md should mention equivalent heading {heading!r}",
        )

    check(
        "Refuse if the spec lacks a `## Open Questions` heading" not in writing,
        "writing-board-tasks must not hard-refuse on a missing exact ## Open Questions heading",
    )
    check(
        re.search(
            r"lacks a `## Open Questions` heading, or that section still has unresolved",
            refining,
        )
        is None,
        "refining-spec post-save must not halt on a missing heading it was told to add",
    )

    if fail:
        return 1
    print("PASS: test-open-questions-gate.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
