"""Platform adapters for super-board-status.py's remote I/O.

`PlatformAdapter` is the Python-side companion to `scripts/platforms/*.sh`.
GitHub-specific GraphQL / `gh` calls live in `GithubStatusAdapter` so a
`GitlabStatusAdapter` (task 12) can slot in without revisiting this path.

Moved verbatim from `scripts/super-board-status.py` — no behavior change.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from abc import ABC, abstractmethod
from pathlib import Path
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


class GitlabStatusAdapter(PlatformAdapter):
    """GitLab GraphQL issues + `glab` notes implementation of PlatformAdapter.

    Does not reuse `paginate_items()` — that helper is hardcoded to
    `repositoryOwner.projectV2.items`. Status projection is Open Judgment
    Call 4: shell out to `platform_gitlab_status_from_labels` in gitlab.sh
    (same jq as platform_board_snapshot). No Python-side status:: map.
    """

    ITEMS_QUERY = """
query($path: ID!, $after: String) {
  project(fullPath: $path) {
    issues(first: 100, after: $after) {
      pageInfo { endCursor hasNextPage }
      nodes {
        iid
        title
        webUrl
        state
        labels { nodes { title } }
        assignees { nodes { username } }
      }
    }
  }
}
"""

    def __init__(self, config: dict[str, Any] | None = None) -> None:
        cfg = config or {}
        project = cfg.get("project") or {}
        self.host = project.get("host") or "gitlab.com"
        self.full_path = project.get("full_path") or ""
        self.gitlab_sh = Path(
            os.environ.get("GITLAB_SH")
            or Path(__file__).resolve().parent / "gitlab.sh"
        )

    def glab(self, *args: str, check: bool = True) -> str:
        """Run glab from a non-git cwd with -R so a GitHub-origin repo is safe."""
        cmd = ["glab"]
        env = os.environ.copy()
        if self.host and self.host != "gitlab.com":
            env["GITLAB_HOST"] = self.host
        if self.full_path:
            cmd += ["-R", self.full_path]
        cmd.extend(args)
        try:
            proc = subprocess.run(
                cmd,
                cwd=tempfile.gettempdir(),
                capture_output=True,
                text=True,
                encoding="utf-8",
                check=False,
                env=env,
            )
        except FileNotFoundError:
            print("glab CLI not found on PATH", file=sys.stderr)
            sys.exit(67)
        if proc.returncode != 0:
            if check:
                print(f"glab call failed ({' '.join(args[:3])}…)", file=sys.stderr)
                if proc.stderr.strip():
                    print(proc.stderr.strip(), file=sys.stderr)
                sys.exit(67)
            return ""
        return proc.stdout

    def status_from_labels(self, labels: list[str]) -> str:
        """OJC 4 — one bash helper. Python must not reimplement the map."""
        rows = self.status_from_labels_batch([labels])
        return rows[0] if rows else "Backlog"

    def status_from_labels_batch(self, rows: list[list[str]]) -> list[str]:
        """One bash+jq call over every label array (OJC 4, no per-row spawn)."""
        proc = subprocess.run(
            [
                "bash", "-c",
                '. "$1" && printf %s "$2" | platform_gitlab_status_from_labels_batch',
                "gitlab-status",
                str(self.gitlab_sh),
                json.dumps(rows),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )
        if proc.returncode != 0:
            print("platform_gitlab_status_from_labels_batch failed", file=sys.stderr)
            if proc.stderr.strip():
                print(proc.stderr.strip(), file=sys.stderr)
            return ["Backlog"] * len(rows)
        try:
            out = json.loads(proc.stdout or "[]")
        except json.JSONDecodeError:
            return ["Backlog"] * len(rows)
        if not isinstance(out, list):
            return ["Backlog"] * len(rows)
        while len(out) < len(rows):
            out.append("Backlog")
        return [str(s) if s else "Backlog" for s in out[: len(rows)]]

    def _node_to_renderer(
        self, node: dict[str, Any], status: str | None = None
    ) -> dict[str, Any]:
        labels = [
            (n.get("title") or "")
            for n in ((node.get("labels") or {}).get("nodes") or [])
            if n.get("title")
        ]
        if status is None:
            status = self.status_from_labels(labels)
        state_raw = (node.get("state") or "opened").upper()
        state = "CLOSED" if state_raw in ("CLOSED", "CLOSE") else "OPEN"
        try:
            number = int(node.get("iid") or 0)
        except (TypeError, ValueError):
            number = 0
        return {
            "id": f"gitlab:{self.full_path}#{number}",
            "content": {
                "number": number,
                "title": node.get("title") or "",
                "url": node.get("webUrl") or "",
                "state": state,
                "repository": {"nameWithOwner": self.full_path},
                "assignees": {
                    "nodes": [
                        {"login": a["username"]}
                        for a in ((node.get("assignees") or {}).get("nodes") or [])
                        if a.get("username")
                    ]
                },
                "labels": {"nodes": [{"name": name} for name in labels]},
            },
            "fieldValues": {
                "nodes": [
                    {"name": status, "field": {"name": "Status"}},
                ]
            },
        }

    def fetch_project_items(
        self, owner: str, number: int
    ) -> tuple[list[dict[str, Any]], bool]:
        # owner/number are GitHub Project V2 coordinates — ignored on GitLab.
        del owner, number
        raw_nodes: list[dict[str, Any]] = []
        after: str | None = None
        truncated = False
        for _ in range(MAX_ITEM_PAGES):
            args = [
                "api", "graphql",
                "-f", f"query={self.ITEMS_QUERY}",
                "-f", f"path={self.full_path}",
            ]
            if after:
                args += ["-f", f"after={after}"]
            out = self.glab(*args)
            try:
                payload: dict[str, Any] = json.loads(out)
            except json.JSONDecodeError:
                print("gitlab graphql returned non-JSON", file=sys.stderr)
                sys.exit(67)
            if payload.get("errors"):
                print("gitlab graphql returned errors:", file=sys.stderr)
                for err in payload["errors"]:
                    print(f"  - {err.get('message')}", file=sys.stderr)
                sys.exit(67)
            issues = (
                ((payload.get("data") or {}).get("project") or {}).get("issues") or {}
            )
            for raw in issues.get("nodes") or []:
                raw_nodes.append(raw)
            page_info = issues.get("pageInfo") or {}
            if not page_info.get("hasNextPage"):
                break
            after = page_info.get("endCursor")
            if not after:
                break
        else:
            truncated = True
        label_rows = [
            [
                (n.get("title") or "")
                for n in ((node.get("labels") or {}).get("nodes") or [])
                if n.get("title")
            ]
            for node in raw_nodes
        ]
        statuses = self.status_from_labels_batch(label_rows) if raw_nodes else []
        return [
            self._node_to_renderer(node, status)
            for node, status in zip(raw_nodes, statuses)
        ], truncated

    def fetch_issue_comments(
        self, issue_number: int
    ) -> list[dict[str, Any]] | None:
        encoded = self.full_path.replace("/", "%2F")
        out = self.glab(
            "api", f"projects/{encoded}/issues/{issue_number}/notes",
            check=False,
        )
        if not out:
            return None
        try:
            notes = json.loads(out)
        except json.JSONDecodeError:
            return None
        if not isinstance(notes, list):
            return None
        return [
            {
                "body": n.get("body") or "",
                "createdAt": n.get("created_at") or n.get("createdAt") or "",
            }
            for n in notes
            if isinstance(n, dict)
        ]


def get_status_adapter(
    git_platform: str = "github",
    config: dict[str, Any] | None = None,
) -> PlatformAdapter:
    """Dispatch to the adapter for `config.git_platform` (default github)."""
    if git_platform == "github":
        return GithubStatusAdapter()
    if git_platform == "gitlab":
        return GitlabStatusAdapter(config)
    raise ValueError(
        f"unsupported git_platform: {git_platform!r} "
        f"(expected github or gitlab)"
    )
