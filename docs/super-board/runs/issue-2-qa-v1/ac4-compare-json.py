#!/usr/bin/env python3
"""AC4 evidence: run super-board-status.py --json against an identical
synthetic fixture on the pre-refactor (main) and post-refactor (PR branch)
scripts, then diff the payloads with wall-clock fields normalized."""
from __future__ import annotations

import datetime
import json
import os
import subprocess
import tempfile
from pathlib import Path

MAIN_STATUS = Path("/Users/banknatchapol/Desktop/Codes/SuperSaiyan/scripts/super-board-status.py")
PR_STATUS = Path("/Users/banknatchapol/Desktop/Codes/SuperSaiyan/.worktrees/issue-2-qa/scripts/super-board-status.py")


def make_fixture(repo: Path) -> None:
    config_dir = repo / ".claude" / "supersaiyan" / "configs"
    config_dir.mkdir(parents=True)
    (repo / ".claude" / "supersaiyan" / "active").write_text("demo\n")
    (config_dir / "demo.json").write_text(json.dumps({
        "variant": "full",
        "base_branch": "main",
        "max_workers": 3,
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


def run(status_script: Path) -> dict:
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        make_fixture(repo)
        env = {**os.environ, "PATH": f"{repo / 'bin'}{os.pathsep}{os.environ['PATH']}"}
        result = subprocess.run(
            ["python3", str(status_script), "--json"],
            cwd=repo, env=env, capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout)


def normalize(payload: dict) -> dict:
    payload = json.loads(json.dumps(payload))
    payload.pop("generated_at", None)
    for w in payload.get("workers", []):
        w.pop("elapsed_seconds", None)
    return payload


pre = normalize(run(MAIN_STATUS))
post = normalize(run(PR_STATUS))

identical = pre == post
print(f"--json output byte-identical (wall-clock fields normalized): {identical}")
if not identical:
    import difflib
    pre_s = json.dumps(pre, indent=2, sort_keys=True).splitlines()
    post_s = json.dumps(post, indent=2, sort_keys=True).splitlines()
    print("\n".join(difflib.unified_diff(pre_s, post_s, "pre-refactor", "post-refactor", lineterm="")))
else:
    print(json.dumps(pre, indent=2, sort_keys=True))
