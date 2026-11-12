#!/usr/bin/env python3
"""The shell entry points inherit one validated outer attempt."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.testqueue.common import enabled, inherited
from tools.testqueue.integration import run
from tools.testqueue.common import state_root, write_json
import os


if __name__ == "__main__":
    try:
        preset, *arguments = sys.argv[1:]
        if preset == "receipt":
            if not inherited("rendered"):
                raise ValueError("receipt requires an owned attempt")
            attempt = os.environ["OPENRC_TESTQUEUE_CONTEXT"].partition(":")[0]
            write_json(state_root() / "attempts" / attempt / "shell-receipt.json",
                       {"preset": arguments[0], "exit_code": int(arguments[1]), "complete": True})
            raise SystemExit(0)
        if arguments[:1] == ["--"]:
            arguments = arguments[1:]
        if not enabled():
            raise SystemExit(100)  # private/hosted runner, no host enrollment
        if preset == "capture" and arguments == ["--help"]:
            raise SystemExit(100)
        if inherited("headless" if preset == "checked" else "rendered"):
            raise SystemExit(100)  # already protected by the outer process tree
        raise SystemExit(run(preset, arguments, ROOT))
    except (OSError, ValueError, RuntimeError) as error:
        print(f"testqueue: {error}", file=sys.stderr)
        raise SystemExit(2)
