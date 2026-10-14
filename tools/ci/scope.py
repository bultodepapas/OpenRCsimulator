#!/usr/bin/env python3
"""Fail-closed path scope for deciding whether GitHub app checks may be skipped."""

from __future__ import annotations

import argparse
import subprocess
import sys
from typing import Optional, Sequence


class ScopeError(Exception):
    """The requested comparison could not be completed safely."""


def app_checks_required(event: str, ref: str, base: str, head: str) -> bool:
    """Return whether app checks must run; only a docs-only diff may skip them."""
    if event == "workflow_dispatch" or ref.startswith("refs/tags/"):
        return True
    if event not in {"push", "pull_request"}:
        return True
    if not base or not any(character != "0" for character in base):
        # New branches and missing event metadata do not have a comparable base.
        return True
    if not head:
        # Without a head SHA there is no safe comparison, so keep the checks enabled.
        return True
    if base.startswith("-") or head.startswith("-"):
        raise ScopeError("revision arguments may not begin with '-'")

    try:
        result = subprocess.run(
            ["git", "diff", "--no-renames", "--name-only", "-z", base, head],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise ScopeError(f"could not run git diff: {error}") from error
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ScopeError(detail or f"git diff exited with status {result.returncode}")

    paths = [path for path in result.stdout.split(b"\0") if path]
    return any(not path.endswith(b".md") for path in paths)


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True, help="GitHub event name")
    parser.add_argument("--ref", default="", help="GitHub ref, such as refs/heads/main")
    parser.add_argument("--base", default="", help="base commit SHA from the event")
    parser.add_argument("--head", default="", help="head commit SHA from the event")
    args = parser.parse_args(argv)

    try:
        required = app_checks_required(args.event, args.ref, args.base, args.head)
    except ScopeError as error:
        print(f"CI scope check failed: {error}", file=sys.stderr)
        return 2

    print("app=true" if required else "app=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
