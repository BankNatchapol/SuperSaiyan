"""Platform adapters for super-board-status.py's remote I/O.

`PlatformAdapter` is the Python-side companion to `scripts/platforms/*.sh`.
GitHub-specific GraphQL / `gh` calls live in `GithubStatusAdapter` so a
`GitlabStatusAdapter` (task 12) can slot in without revisiting this path.

Moved verbatim from `scripts/super-board-status.py` — no behavior change.
"""

from __future__ import annotations

import json
import subprocess
import sys
from abc import ABC, abstractmethod
from typing import Any, Callable


# Hard ceiling on pagination depth. 20 pages × 100 items = 2000 cards, which
# is well past any realistic super-board project (the dispatcher's 5000-pt/hr
# GraphQL budget makes a 20-page snapshot a meaningful chunk of quota). If a
# project ever exceeds this, we print a truncation warning rather than loop
# forever on a buggy server response.
MAX_ITEM_PAGES = 20


def paginate_items(
    fetch: Callable[[str | None], dict[str, Any]],
    max_pages: int = MAX_ITEM_PAGES,
) -> tuple[list[dict[str, Any]], bool]:
    """Walk `fetch(after) → graphql_payload` until pagination is exhausted.

    Pure: no I/O of its own — the `fetch` callable does all I/O. Returns
    (all_nodes, hit_cap), where `hit_cap` is True iff we stopped because
    of `max_pages` (i.e., the project is bigger than we surfaced).
    """
    all_nodes: list[dict[str, Any]] = []
    after: str | None = None
    for _ in range(max_pages):
        payload = fetch(after)
        items_section = (
            ((payload.get("data") or {})
                .get("repositoryOwner") or {})
                .get("projectV2") or {}
        ).get("items") or {}
        all_nodes.extend(items_section.get("nodes") or [])
        page_info = items_section.get("pageInfo") or {}
        if not page_info.get("hasNextPage"):
            return all_nodes, False
        after = page_info.get("endCursor")
        if not after:
            return all_nodes, False
    return all_nodes, True


class PlatformAdapter(ABC):
    """Remote I/O surface used by super-board-status.py.

    Implementations must return the same shapes the renderer already
    consumes so GitHub and GitLab boards render identically.
    """

    @abstractmethod
    def fetch_project_items(
        self, owner: str, number: int
    ) -> tuple[list[dict[str, Any]], bool]:
        """Return (raw board-item nodes, hit_pagination_cap)."""

    @abstractmethod
    def fetch_issue_comments(
        self, issue_number: int
    ) -> list[dict[str, Any]] | None:
        """Return issue comments; None on soft failure (empty/unparseable)."""


class GithubStatusAdapter(PlatformAdapter):
    """GitHub Project V2 + `gh` implementation of PlatformAdapter.

    Wraps today's `gh(...)` / `ITEMS_QUERY` / comment-fetch logic verbatim.
    """

    # Targeted query — number, title, labels, Status only. ~3 KB vs. 100+ KB for
    # `gh project item-list --format json` (which slurps every issue body).
    # `repositoryOwner(login:)` is the abstract owner; `... on ProjectV2Owner`
    # picks the `projectV2` field which both User and Organization implement.
    # `$after` is nullable — first page omits the `-F after=…` arg entirely
    # (default null) so we don't have to pass a sentinel value.
    ITEMS_QUERY = """
query($owner:String!, $number:Int!, $after:String) {
  repositoryOwner(login:$owner) {
    ... on ProjectV2Owner {
      projectV2(number:$number) {
        items(first:100, after:$after) {
          pageInfo { endCursor hasNextPage }
          nodes {
            id
            content { ... on Issue {
              number title url state
              repository { nameWithOwner }
              assignees(first:10) { nodes { login } }
              labels(first:20){nodes{name}}
            } }
            fieldValues(first:8) {
              nodes { ... on ProjectV2ItemFieldSingleSelectValue {
                name field { ... on ProjectV2SingleSelectField { name } } } }
            }
          }
        }
      }
    }
  }
}
"""

    def gh(self, *args: str, check: bool = True) -> str:
        """Run gh and return stdout. Exits 67 on failure when check=True."""
        try:
            proc = subprocess.run(
                ["gh", *args], capture_output=True, text=True, encoding="utf-8", check=False
            )
        except FileNotFoundError:
            print("gh CLI not found on PATH", file=sys.stderr)
            sys.exit(67)
        if proc.returncode != 0:
            if check:
                print(f"gh call failed ({' '.join(args[:3])}…)", file=sys.stderr)
                if proc.stderr.strip():
                    print(proc.stderr.strip(), file=sys.stderr)
                sys.exit(67)
            return ""
        return proc.stdout

    def fetch_project_items(
        self, owner: str, number: int
    ) -> tuple[list[dict[str, Any]], bool]:
        def fetch_page(after: str | None) -> dict[str, Any]:
            args = [
                "api", "graphql",
                "-f", f"query={self.ITEMS_QUERY}",
                "-F", f"owner={owner}",
                "-F", f"number={number}",
            ]
            if after:
                # First page leaves `$after` unset → GraphQL defaults to null.
                args += ["-F", f"after={after}"]
            out = self.gh(*args)
            payload: dict[str, Any] = json.loads(out)
            if payload.get("errors"):
                print("graphql returned errors:", file=sys.stderr)
                for err in payload["errors"]:
                    print(f"  - {err.get('message')}", file=sys.stderr)
                sys.exit(67)
            return payload

        return paginate_items(fetch_page)

    def fetch_issue_comments(
        self, issue_number: int
    ) -> list[dict[str, Any]] | None:
        out = self.gh(
            "issue", "view", str(issue_number), "--json", "comments", check=False
        )
        if not out:
            return None
        try:
            return json.loads(out).get("comments") or []
        except json.JSONDecodeError:
            return None


def get_status_adapter(git_platform: str = "github") -> PlatformAdapter:
    """Dispatch to the adapter for `config.git_platform` (default github)."""
    if git_platform == "github":
        return GithubStatusAdapter()
    raise ValueError(
        f"unsupported git_platform: {git_platform!r} "
        f"(GithubStatusAdapter only; GitlabStatusAdapter is task 12)"
    )
