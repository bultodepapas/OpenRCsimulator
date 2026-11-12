"""Admission hooks for existing tools, inactive on unenrolled private/hosted runners."""
from __future__ import annotations

import json
import os
from pathlib import Path
import secrets
import sys
import uuid
import getpass

from .common import enabled, inherited, rpc, state_root, wait, submission_receipt


def submit(preset: str, options: dict, source: Path) -> dict:
    from .snapshots import capture
    from .presets import validate
    options = validate(preset, options)
    # Fail before copying when the enrolled authority is unavailable.
    rpc("hosts")
    identifier, submission_secret = uuid.uuid4().hex, secrets.token_hex(32)
    snapshot = state_root() / "snapshots" / identifier
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    scopes = None
    if preset in {"suite", "ci", "capture"}:
        import subprocess
        names = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=source).decode().split("\0")
        scopes = tuple(sorted({name.split("/")[0] for name in names if name}))
    kwargs = {"scope": scopes} if scopes else {}
    capture(source, snapshot, include_imports=(source / "app/.godot/imported").is_dir(), **kwargs)
    request = {"preset": preset, "options": options, "owner": os.environ.get("OPENRC_TESTQUEUE_OWNER", f"{getpass.getuser()}-{os.getpid()}"),
               "source": str(source), "snapshot": str(snapshot), "request_id": identifier, "request_secret": submission_secret,
               "environment": {name: os.environ[name] for name in ("OPENRC_TEST_PART", "OPENRC_UNIT_SHARDS", "OPENRC_UNIT_SHARD", "OPENRC_PARSE_WITH_UNITS") if name in os.environ}}
    # Durable before network submission: a lost reply can replay this exact ID,
    # secret and immutable snapshot rather than silently creating another job.
    receipt = submission_receipt(state_root(), request)
    print(f"testqueue submission receipt: {receipt}", file=sys.stderr)
    return rpc("submit", **request)


def open_debug(argv: list[str], source: Path) -> int:
    previous = os.environ.get("OPENRC_TESTQUEUE_HANDLE")
    if previous:
        status = rpc("status", job=previous.partition(":")[0])
        if status["state"] != "FINISHED":
            raise ValueError("this client already owns a pending/live session; close or cancel it before launching another")
    accepted = submit("debug-session", {"argv": argv}, source)
    status = wait(accepted["job"], timeout=600, ready=True)
    if not status.get("session"):
        print(json.dumps({**accepted, "state": status["state"], "reason": status.get("reason"), "output": status.get("output")}))
        return 1
    session = status["session"]
    os.environ["OPENRC_TESTQUEUE_HANDLE"] = accepted["handle"]
    os.environ["OPENRC_DEBUG_BRIDGE"] = str(session["port"])
    print(json.dumps({"ok": True, **session, **accepted,
                      "use": "Set OPENRC_TESTQUEUE_HANDLE to the returned handle on each command"}))
    return 0


def close_debug() -> int:
    handle = os.environ.get("OPENRC_TESTQUEUE_HANDLE", "")
    status = rpc("cancel", handle=handle)
    status = wait(status["id"], timeout=20)
    print(json.dumps({"stopped": status["state"] == "FINISHED", "state": status["state"], "cleanup": status.get("cleanup")}))
    return 0 if status["state"] == "FINISHED" and status.get("cleanup") == "CONFIRMED" else 1


def request(command: str, args: dict | None, timeout: float, port: int | None):
    handle = os.environ.get("OPENRC_TESTQUEUE_HANDLE", "")
    if not handle:
        raise ValueError("explicit OPENRC_TESTQUEUE_HANDLE required; launch your own session or supply its handle")
    return rpc("bridge", handle=handle, command=command, args=args or {}, port=port,
               timeout=min(timeout + 5, 605), **{"bridge_timeout": timeout})


def run(preset: str, argv: list[str], source: Path) -> int:
    options = {"argv": argv}
    if preset in {"suite", "ci", "capture"}:
        options["timeout"] = 21600
    accepted = submit(preset, options, source)
    print(json.dumps(accepted), flush=True)
    status = wait(accepted["job"], timeout=options.get("timeout", 3600) + 600)
    print(json.dumps(status, indent=2))
    return 0 if status.get("outcome") == "PASSED" else 1


def checked(command, *, timeout, required, max_log_bytes, warnings_as_errors, label):
    """Preserve the ordinary focused checked-runner API without an arbitrary exec endpoint."""
    host = rpc("hosts")
    if not command or Path(command[0]).resolve() != Path(host["engine"]["path"]).resolve():
        raise ValueError("enrolled checked commands must use the worker's exact editor executable")
    if "--" in command:
        raise ValueError("admitted focused checks do not accept mutable external application inputs")
    source = None
    script = None
    headless = False
    index = 1
    while index < len(command):
        value = command[index]
        if value == "--headless":
            headless = True
            index += 1
            continue
        if value not in {"--path", "--script", "--audio-driver"} or index + 1 >= len(command):
            raise ValueError("unsupported admitted engine option: " + value)
        selected = command[index + 1]
        if value == "--path":
            if Path(selected).resolve().name != "app":
                raise ValueError("admitted checks require the submitted checkout's app directory")
            source = Path(selected).resolve().parent
        elif value == "--script":
            script = selected
        elif selected != "Dummy":
            raise ValueError("admitted focused checks use Dummy audio")
        index += 2
    if source is None or script is None:
        raise ValueError("admitted focused checks require --path <checkout>/app and --script res://tests/...gd")
    accepted = submit("checked", {"script": script, "headless": headless, "require": required, "timeout": timeout,
                                   "settings": {"max_log_bytes": max_log_bytes, "warnings_as_errors": warnings_as_errors, "label": label}}, source)
    status = wait(accepted["job"], timeout=timeout + 600)
    report = status.get("runner_verdict", {}).get("checked")
    if not report:
        raise ValueError(f"admitted check did not produce its report: {status.get('state')} {status.get('outcome')} {status.get('error', '')}; job {accepted['job']}")
    if status.get("outcome") != "PASSED" and not (status.get("outcome") == "TEST_FAILED" and report.get("ok") is False):
        raise ValueError(f"admitted check has an unresolved orchestration outcome: {status.get('outcome')}; job {accepted['job']}")
    return report
