#!/usr/bin/env python3
"""Fail when a tracked file exceeds GitHub's 50 MiB warning size without a recorded reason in
large_files.json, or any tracked file exceeds GitHub's 100 MiB push limit. Checks the index, so
staged files count.
Usage: check_large_files.py [--root <repo>]"""
import argparse
import json
import subprocess
from pathlib import Path

POLICY = Path(__file__).with_name("large_files.json")


def check(root: Path, policy: dict) -> list[str]:
    listed = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], check=True, capture_output=True).stdout
    failures = []
    for name in filter(None, listed.decode("utf-8").split("\0")):
        path = root / name
        if not path.is_file():
            continue
        size = path.stat().st_size
        if size > policy["hard_limit_bytes"]:
            failures.append(f"{name}: {size / 2**20:.1f} MiB exceeds GitHub's 100 MiB push limit")
        elif size > policy["max_new_file_bytes"] and name not in policy["allowed"]:
            failures.append(f"{name}: {size / 2**20:.1f} MiB exceeds 50 MiB; store a hash and download or "
                            f"regeneration recipe, or record why it must be tracked in {POLICY.name}")
    for name in policy["allowed"]:
        if not (root / name).is_file():
            failures.append(f"{name}: allowed in {POLICY.name} but no longer present; remove the entry")
    return failures


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    if policy.get("format") != "openrc-large-files v1":
        raise SystemExit("unsupported large-file policy")
    failures = check(args.root, policy)
    if failures:
        raise SystemExit("large tracked files:\n  " + "\n  ".join(failures))
    print(f"large tracked files: {len(policy['allowed'])} recorded above 50 MiB, none above the 100 MiB limit")


if __name__ == "__main__":
    main()
