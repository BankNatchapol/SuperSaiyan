#!/usr/bin/env python3
"""Regression test for the Control Center status JSON boundary."""

from __future__ import annotations

import datetime
import importlib.util
import json
import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATUS = ROOT / "scripts" / "super-board-status.py"


def main() -> None:
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        config_dir = repo / ".claude" / "supersaiyan" / "configs"
        config_dir.mkdir(parents=True)
        (repo / ".claude" / "supersaiyan" / "active").write_text("demo\n")
        (config_dir / "demo.json").write_text(json.dumps({
            "variant": "full",
            "base_branch": "main",
            "max_workers": 3,
            # Per-lane backend map: the JSON boundary must expose both the raw shape and a
            # normalized {build, qa, review} view.
            "worker_backend": {
                "build": "codex-exec",
                "qa": "cursor-agent",
                "review": "claude-p",
            },
            "project": {"owner": "octocat", "number": 7, "title": "Demo Board"},
            "paths": {"runs_dir": "docs/supersaiyan/runs"},
        }))

        runs = repo / "docs" / "supersaiyan" / "runs"
        runs.mkdir(parents=True)
        today = datetime.date.today().isoformat()
        (runs / f"{today}-demo.md").write_text(
            "[09:00:00] super-board run started\n"
            "[09:00:01] dispatch lane=build issue=#12 pid=4321 claim=ok\n"
            "[09:00:02] tick — workers=1\n"
        )

        bin_dir = repo / "bin"
        bin_dir.mkdir()
        gh = bin_dir / "gh"
        gh.write_text(
            "#!/bin/sh\n"
            "cat <<'JSON'\n"
            '{"data":{"repositoryOwner":{"projectV2":{"items":{"pageInfo":'
            '{"endCursor":null,"hasNextPage":false},"nodes":['
            '{"id":"PVTI_backlog","content":{"number":11,"title":"Manual idea",'
            '"url":"https://github.com/octocat/demo/issues/11","state":"OPEN",'
            '"repository":{"nameWithOwner":"octocat/demo"},"assignees":{"nodes":[]},'
            '"labels":{"nodes":[]}},"fieldValues":{"nodes":[{"name":"Backlog",'
            '"field":{"name":"Status"}}]}},'
            '{"id":"PVTI_ready","content":{"number":12,"title":"Ship control center",'
            '"url":"https://github.com/octocat/demo/issues/12","state":"OPEN",'
            '"repository":{"nameWithOwner":"octocat/demo"},"assignees":{"nodes":[]},'
            '"labels":{"nodes":[{"name":"ui"}]}},"fieldValues":{"nodes":'
            '[{"name":"Ready","field":{"name":"Status"}}]}}]}}}}}\n'
            "JSON\n"
        )
        gh.chmod(0o755)

        env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}
        result = subprocess.run(
            ["python3", str(STATUS), "--json"],
            cwd=repo,
            env=env,
            capture_output=True,
            text=True,
            check=True,
        )
        payload = json.loads(result.stdout)
        assert payload["version"] == 1
        assert payload["config"]["slug"] == "demo"
        assert payload["project"]["number"] == 7
        assert payload["lanes"]["Backlog"][0]["number"] == 11
        assert payload["lanes"]["Ready"][0]["number"] == 12
        assert payload["workers"][0]["issue"] == 12
        assert payload["health"]["run_active"] is True
        # Raw shape is preserved verbatim for back-compat...
        assert payload["config"]["worker_backend"] == {
            "build": "codex-exec",
            "qa": "cursor-agent",
            "review": "claude-p",
        }
        # ...and the normalized view is always a {build, qa, review} map.
        assert payload["config"]["worker_backend_resolved"] == {
            "build": "codex-exec",
            "qa": "cursor-agent",
            "review": "claude-p",
        }

    check_worker_backend_resolution()
    print("PASS: test-status-json.py")


def check_worker_backend_resolution() -> None:
    """The string shorthand and omitted lane keys must normalize the same way the
    bash dispatcher (scripts/super-board-run.sh) resolves them."""
    spec = importlib.util.spec_from_file_location("super_board_status", STATUS)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    resolve = module.resolve_worker_backend

    # A single string applies to every lane (back-compat shape).
    assert resolve({"worker_backend": "codex-exec"}) == {
        "build": "codex-exec", "qa": "codex-exec", "review": "codex-exec",
    }
    # Omitted lane keys fall back to claude-p, matching load_backend's default.
    assert resolve({"worker_backend": {"qa": "cursor-agent"}}) == {
        "build": "claude-p", "qa": "cursor-agent", "review": "claude-p",
    }
    # No worker_backend at all means the in-session workflow backend.
    assert resolve({}) == {
        "build": "workflow", "qa": "workflow", "review": "workflow",
    }


if __name__ == "__main__":
    main()
