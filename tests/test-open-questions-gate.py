#!/usr/bin/env python3
"""Contract for the spec→task Open Questions gate.

Hard-refuse only when an equivalent heading is present and still lists
genuinely unanswered items. A recorded recommendation or resolution is not
unresolved. A missing heading is warn-and-ask, not a refusal.

classify() pins the documented SKILL.md semantics. It is a Python
reimplementation of prose instructions for an LLM — it cannot verify that a
model will follow those instructions at runtime.
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
DECISION_RE = re.compile(
    r"\b(?:recommend(?:ed|s)?|resolved|accept(?:ed)? as|chosen)\b",
    re.IGNORECASE,
)
UNANSWERED_RE = re.compile(
    r"\b(?:not resolved|unresolved|undecided|still open|TBD|TODO)\b",
    re.IGNORECASE,
)
# Catch "Refuse if the spec lacks a heading" and rewordings like
# "Reject any spec that is missing an Open Questions heading".
MISSING_HEADING_REFUSE_RE = re.compile(
    r"(?:refuse|reject|block|halt)\b.{0,120}(?:lacks|missing|absent|without).{0,80}heading"
    r"|(?:lacks|missing|absent|without).{0,80}heading.{0,80}(?:refuse|reject|block|halt)",
    re.IGNORECASE | re.DOTALL,
)


def _section_body(spec: str, match: re.Match[str]) -> str:
    start = match.end()
    nxt = re.search(r"^## ", spec[start:], re.MULTILINE)
    return spec[start : start + nxt.start() if nxt else None].strip()


def _items(body: str) -> list[str]:
    chunks = re.split(r"(?m)(?=^(?:\d+\.|[-*])\s)", body)
    return [chunk.strip() for chunk in chunks if chunk.strip()]


def _item_is_unanswered(item: str) -> bool:
    if UNANSWERED_RE.search(item):
        return True
    return not DECISION_RE.search(item)


def classify(spec: str) -> str:
    """Return ok | warn-missing | refuse-unresolved.

    Pins writing-board-tasks / refining-spec SKILL.md. Not a runtime LLM check.
    """
    matches = list(HEADING_RE.finditer(spec))
    if not matches:
        return "warn-missing"
    for match in matches:
        body = _section_body(spec, match)
        if not body or body.lower().strip(" .") == "none":
            continue
        if any(_item_is_unanswered(item) for item in _items(body)):
            return "refuse-unresolved"
    return "ok"


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
        "heading plus unanswered items should refuse",
    )
    check(
        classify("## Open judgment calls\n\n1. Still undecided.\n") == "refuse-unresolved",
        "equivalent heading plus unanswered items should refuse",
    )
    check(
        classify(
            "## Open judgment calls\n\n"
            "1. Skill-doc abstraction — Recommend the latter.\n"
        )
        == "ok",
        "a recorded recommendation is not unresolved",
    )
    check(
        classify(
            "## Open judgment calls\n\n"
            "1. Foo — Recommend the latter.\n"
            "2. Bar — Flagged as debatable, not resolved.\n"
        )
        == "refuse-unresolved",
        "a recorded recommendation must not hide a genuinely unanswered sibling",
    )

    sneaky = "Reject any spec that is missing an Open Questions heading."
    check(
        MISSING_HEADING_REFUSE_RE.search(sneaky) is not None,
        "anti-regression regex must catch a reworded missing-heading refuse",
    )

    gitlab = GITLAB_SPEC.read_text(encoding="utf-8")
    check(GITLAB_SPEC.is_file(), "gitlab-integration-design.md should exist")
    check(
        classify(gitlab) == "ok",
        "gitlab-integration-design.md must be usable (classify == ok), not merely not-missing-heading",
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
        MISSING_HEADING_REFUSE_RE.search(writing) is None,
        "writing-board-tasks must not hard-refuse on a missing heading (including rewordings)",
    )
    check(
        re.search(r"warn and ask", writing, re.I) is not None,
        "writing-board-tasks must warn and ask when the heading is missing",
    )
    gate_start = writing.lower().find("**open questions gate:**")
    gate_end = writing.lower().find("**optional input:**")
    gate = writing[gate_start:gate_end] if gate_start >= 0 and gate_end > gate_start else ""
    check(
        bool(gate)
        and re.search(r"recommend", gate, re.I) is not None
        and re.search(r"unanswered", gate, re.I) is not None,
        "writing-board-tasks gate must distinguish recorded recommendations from unanswered items",
    )
    check(
        re.search(r"missing heading is not a halt", refining, re.I) is not None,
        "refining-spec post-save must not halt on a missing heading it was told to add",
    )

    if fail:
        return 1
    print("PASS: test-open-questions-gate.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
