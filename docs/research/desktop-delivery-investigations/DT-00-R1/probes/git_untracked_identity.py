#!/usr/bin/env python3
"""Reproduce how `git describe --dirty` treats an untracked file.

Run from any directory with Git and Python 3 installed:
    python3 docs/research/desktop-delivery-investigations/DT-00-R1/probes/git_untracked_identity.py

The script creates a disposable repository in the system temp directory and writes
the captured result beside this file. It never reads or changes the simulator repo.
"""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile


def run_git(repo: Path, *args: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        text=True,
        capture_output=True,
    )
    return completed.stdout.strip()


def main() -> int:
    git_version = subprocess.run(
        ["git", "--version"], check=True, text=True, capture_output=True
    ).stdout.strip()
    with tempfile.TemporaryDirectory(prefix="openrc-git-dirty-probe-") as temp:
        repo = Path(temp)
        run_git(repo, "init", "--quiet")
        run_git(repo, "config", "user.email", "probe@example.invalid")
        run_git(repo, "config", "user.name", "OpenRC probe")
        (repo / "tracked.txt").write_text("tracked input\n", encoding="utf-8")
        run_git(repo, "add", "tracked.txt")
        run_git(repo, "commit", "--quiet", "-m", "baseline")
        run_git(repo, "tag", "v0.1.0")

        describe_before = run_git(repo, "describe", "--tags", "--always", "--dirty")
        status_before = run_git(
            repo, "status", "--porcelain=v1", "--untracked-files=all"
        )
        (repo / "new-resource.json").write_text("untracked input\n", encoding="utf-8")
        describe_after = run_git(repo, "describe", "--tags", "--always", "--dirty")
        status_after = run_git(
            repo, "status", "--porcelain=v1", "--untracked-files=all"
        )

    expected_status = "?? new-resource.json"
    passed = (
        describe_before == "v0.1.0"
        and not status_before
        and describe_after == describe_before
        and status_after == expected_status
    )
    result = {
        "format": "openrc-git-untracked-identity-probe v1",
        "git_version": git_version,
        "repository": "temporary disposable repository; removed automatically",
        "commands": {
            "identity": "git describe --tags --always --dirty",
            "status": "git status --porcelain=v1 --untracked-files=all",
        },
        "describe_before_untracked_file": describe_before,
        "status_before_untracked_file": status_before,
        "describe_after_untracked_file": describe_after,
        "status_after_untracked_file": status_after,
        "passed": passed,
        "scope": "Shows Git identity/status behavior only; does not show that the untracked file affects a Godot export.",
    }
    output = Path(__file__).with_name("git_untracked_identity.result.json")
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
