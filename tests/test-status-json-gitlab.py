#!/usr/bin/env python3
"""GitLab fixture + OJC 4 proof for super-board-status.py --json."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATUS = ROOT / "scripts" / "super-board-status.py"
GITLAB_SH = ROOT / "scripts" / "platforms" / "gitlab.sh"


GRAPHQL = {
    "data": {
        "project": {
            "issues": {
                "pageInfo": {"endCursor": None, "hasNextPage": False},
                "nodes": [
                    {
                        "iid": "1",
                        "title": "Ready card",
                        "webUrl": "https://gitlab.example.com/g/p/-/issues/1",
                        "state": "opened",
                        "labels": {"nodes": [{"title": "status::ready"}]},
                        "assignees": {"nodes": []},
                    },
                    {
                        "iid": "2",
                        "title": "No status label",
                        "webUrl": "https://gitlab.example.com/g/p/-/issues/2",
                        "state": "opened",
                        "labels": {"nodes": []},
                        "assignees": {"nodes": []},
                    },
                ],
            }
        }
    }
}


def write_stub_glab(bin_dir: Path) -> None:
    gh = bin_dir / "glab"
    payload = json.dumps(GRAPHQL)
    gh.write_text(
        "#!/bin/sh\n"
        "case \" $* \" in\n"
        "  *' graphql '*) cat <<'JSON'\n"
        f"{payload}\n"
        "JSON\n"
        "    ;;\n"
        "  *'/notes'*) echo '[]'\n"
        "    ;;\n"
        "  *) echo '{}' ;;\n"
        "esac\n"
    )
    gh.chmod(0o755)


def run_status(repo: Path, env: dict[str, str]) -> dict:
    result = subprocess.run(
        ["python3", str(STATUS), "--json"],
        cwd=repo,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"status --json failed ({result.returncode}): {result.stderr}"
        )
    return json.loads(result.stdout)


def main() -> None:
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        config_dir = repo / ".supersaiyan" / "configs"
        config_dir.mkdir(parents=True)
        (repo / ".supersaiyan" / "active").write_text("sandbox\n")
        (config_dir / "sandbox.json").write_text(json.dumps({
            "variant": "full",
            "base_branch": "main",
            "git_platform": "gitlab",
            "worker_backend": "cursor-agent",
            "project": {
                "host": "gitlab.example.com",
                "full_path": "g/p",
                "board_id": 9,
                "title": "GitLab Sandbox",
            },
            "paths": {"runs_dir": "docs/supersaiyan/runs"},
        }))
        (repo / "docs" / "supersaiyan" / "runs").mkdir(parents=True)

        bin_dir = repo / "bin"
        bin_dir.mkdir()
        write_stub_glab(bin_dir)
        env = {
            **os.environ,
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "GITLAB_SH": str(GITLAB_SH),
        }
        payload = run_status(repo, env)
        assert payload["version"] == 1
        assert payload["config"]["slug"] == "sandbox"
        assert payload["project"]["full_path"] == "g/p"
        assert payload["project"]["host"] == "gitlab.example.com"
        assert payload["project"]["board_id"] == 9
        assert "owner" not in payload["project"]
        assert payload["lanes"]["Ready"][0]["number"] == 1
        assert payload["lanes"]["Backlog"][0]["number"] == 2
        assert "workers" in payload
        assert "health" in payload

        # OJC 4: change the bash map only — Python output must follow.
        proof_sh = repo / "gitlab-proof.sh"
        text = GITLAB_SH.read_text()
        text = text.replace(
            'if . == "ready" then "Ready"',
            'if . == "ready" then "Blocked"',
        )
        proof_sh.write_text(text)
        env["GITLAB_SH"] = str(proof_sh)
        proof = run_status(repo, env)
        assert proof["lanes"]["Ready"] == []
        assert proof["lanes"]["Blocked"][0]["number"] == 1
        assert proof["lanes"]["Blocked"][0]["status"] == "Blocked"

    live_status_if_authenticated()
    print("PASS: test-status-json-gitlab.py")


def live_status_if_authenticated() -> None:
    if shutil.which("glab") is None:
        print("  skip live --json (glab not on PATH)")
        return
    check = subprocess.run(
        ["glab", "auth", "status"],
        capture_output=True,
        text=True,
        check=False,
    )
    if check.returncode != 0:
        print("  skip live --json (glab not authenticated)")
        return
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        config_dir = repo / ".supersaiyan" / "configs"
        config_dir.mkdir(parents=True)
        (repo / ".supersaiyan" / "active").write_text("live\n")
        (config_dir / "live.json").write_text(json.dumps({
            "variant": "full",
            "base_branch": "main",
            "git_platform": "gitlab",
            "worker_backend": "cursor-agent",
            "project": {
                "host": "gitlab.com",
                "full_path": "BankNatchapol/supersaiyan-gitlab-sandbox",
                "title": "live sandbox",
            },
            "paths": {"runs_dir": "docs/supersaiyan/runs"},
        }))
        (repo / "docs" / "supersaiyan" / "runs").mkdir(parents=True)
        env = {**os.environ, "GITLAB_SH": str(GITLAB_SH)}
        payload = run_status(repo, env)
        assert payload["version"] == 1
        assert payload["config"]["slug"] == "live"
        assert payload["project"]["full_path"] == "BankNatchapol/supersaiyan-gitlab-sandbox"
        assert "Ready" in payload["lanes"]
        print("  ✓ live --json against sandbox")


if __name__ == "__main__":
    main()
