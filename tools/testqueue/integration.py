"""Admission hooks for existing tools, inactive on unenrolled private/hosted runners."""
from __future__ import annotations

import json
import os
from pathlib import Path
import secrets
import sys
import uuid
import getpass

from .common import (ObservationTimeout, enabled, inherited, rpc, state_root, wait,
                     submission_receipt, validate_wait_timeout)


def submit(preset: str, options: dict, source: Path, *, retain_session: bool = False) -> dict:
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
        names = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=source, creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0).decode().split("\0")
        scopes = tuple(sorted({name.split("/")[0] for name in names if name}))
    kwargs = {"scope": scopes} if scopes else {}
    manifest = capture(source, snapshot, include_imports=(source / "app/.godot/imported").is_dir(), **kwargs)
    environment_names = ("OPENRC_TEST_PART", "OPENRC_UNIT_SHARDS", "OPENRC_UNIT_SHARD", "OPENRC_PARSE_WITH_UNITS")
    if preset in {"suite", "ci"}:
        environment_names += ("OPENRC_IMPORT_TIMEOUT",)
    owner = os.environ.get("OPENRC_TESTQUEUE_OWNER")
    if owner is None:
        owner = f"{getpass.getuser()}-{os.getpid()}"
    request = {"preset": preset, "options": options, "owner": owner,
               "source": str(source), "snapshot": str(snapshot), "request_id": identifier, "request_secret": submission_secret,
               "expected_source_digest": manifest["source_digest"], "expected_manifest_digest": manifest["manifest_digest"],
               "environment": {name: os.environ[name] for name in environment_names if name in os.environ}}
    # Durable before network submission: a lost reply can replay this exact ID,
    # secret and immutable snapshot rather than silently creating another job.
    receipt = submission_receipt(state_root(), request)
    print(f"testqueue submission receipt: {receipt}", file=sys.stderr)
    if retain_session:
        # MCP captures stderr. Retain the receipt independently before a reply
        # can be lost, so retries cannot silently create another session.
        os.environ["OPENRC_TESTQUEUE_SUBMISSION"] = str(receipt)
    try:
        accepted = rpc("submit", **request)
    except (OSError, ValueError, RuntimeError) as error:
        raise RuntimeError(f"submission is unresolved ({error}); recovery receipt: {receipt}") from error
    if retain_session:
        _retain_debug(accepted)
    return accepted


def _pending_debug():
    path = os.environ.get("OPENRC_TESTQUEUE_SUBMISSION")
    if not path:
        return None
    receipt = Path(path).resolve()
    if receipt.parent != (state_root() / "submissions").resolve():
        raise ValueError(f"pending session belongs to another authority; preserve its recovery receipt: {receipt}")
    request = json.loads(receipt.read_text(encoding="utf-8"))
    if request.get("preset") != "debug-session":
        raise ValueError("pending receipt must describe a debug session")
    return request


def _retain_debug(accepted):
    os.environ["OPENRC_TESTQUEUE_HANDLE"] = accepted["handle"]
    os.environ.pop("OPENRC_TESTQUEUE_SUBMISSION", None)
    os.environ.pop("OPENRC_DEBUG_BRIDGE", None)


def _recover_debug(request):
    accepted = rpc("recover", request_id=request["request_id"], request_secret=request["request_secret"])
    if accepted:
        _retain_debug(accepted)
    return accepted


def open_debug(argv: list[str], source: Path, *, wait_timeout: float = 600) -> int:
    wait_timeout = validate_wait_timeout(wait_timeout)
    pending = _pending_debug()
    if pending:
        from .presets import validate
        if Path(pending["source"]).resolve() != source.resolve() or pending["options"] != validate("debug-session", {"argv": argv}):
            raise ValueError("an unresolved launch has different inputs; use session status or stop before launching another")
        accepted = _recover_debug(pending)
        if not accepted:
            # Only a launch retries submission. Status/stop must never create a
            # simulator merely to discover whether an earlier submit committed.
            accepted = rpc("submit", **pending)
    else:
        previous = os.environ.get("OPENRC_TESTQUEUE_HANDLE")
        if previous:
            status = rpc("status", job=previous.partition(":")[0])
            if status["state"] != "FINISHED":
                raise ValueError("this client already owns a pending/live session; close or cancel it before launching another")
        accepted = submit("debug-session", {"argv": argv}, source, retain_session=True)
    # Ownership starts at acceptance, not readiness. The job can remain queued
    # after this caller stops waiting, or the worker may become unreachable.
    _retain_debug(accepted)
    print(json.dumps({"ok": True, **accepted, "state": "ACCEPTED", "ready": False,
                      "use": "Keep the handle for status or cancellation"}), file=sys.stderr, flush=True)
    if wait_timeout == 0:
        print(json.dumps({"ok": True, **accepted, "state": "ACCEPTED", "ready": False,
                          "observation": "NOT_REQUESTED",
                          "use": "Use the handle for status or cancellation; waiting does not cancel the job"}))
        return 0
    try:
        status = wait(accepted["job"], timeout=wait_timeout, ready=True)
    except ObservationTimeout as error:
        print(json.dumps({"ok": True, **accepted, "state": "ACCEPTED", "ready": False,
                          "observation": "TIMEOUT", "observation_reason": error.reason,
                          "use": "Use the handle for status or cancellation; waiting does not cancel the job"}))
        return 0
    ready = status["state"] == "RUNNING" and bool(status.get("session")) and not status.get("canceled")
    if not ready:
        pending = status["state"] in {"QUEUED", "DISPATCHING", "RUNNING", "CLEANING"}
        result = {"ok": pending, **accepted, "state": status["state"], "ready": False,
                  "reason": status.get("reason"), "outcome": status.get("outcome"),
                  "cleanup": status.get("cleanup"), "error": status.get("error"), "output": status.get("output"),
                  "use": "Use the handle for status or cancellation; waiting does not cancel the job"}
        if "wait_observation" in status:
            result["wait_observation"] = status["wait_observation"]
        print(json.dumps(result))
        return 0 if pending else 1
    session = status["session"]
    os.environ["OPENRC_DEBUG_BRIDGE"] = str(session["port"])
    print(json.dumps({"ok": True, **session, **accepted, "state": status["state"], "ready": True,
                      "use": "Set OPENRC_TESTQUEUE_HANDLE to the returned handle on each command"}))
    return 0


def debug_status() -> dict:
    """Inspect this client's admitted session, including one not yet ready."""
    pending = _pending_debug()
    if pending and not _recover_debug(pending):
        return {"state": "SUBMISSION_UNCONFIRMED", "ready": False,
                "submission_receipt": os.environ["OPENRC_TESTQUEUE_SUBMISSION"],
                "use": "Retry the same launch or stop to cancel this request; no replacement was submitted"}
    handle = os.environ.get("OPENRC_TESTQUEUE_HANDLE", "")
    job, separator, secret = handle.partition(":")
    if not separator or not job or not secret:
        raise ValueError("explicit OPENRC_TESTQUEUE_HANDLE required; launch your own session or supply its handle")
    status = rpc("status", job=job)
    fields = ("state", "reason", "outcome", "cleanup", "session", "canceled", "error", "output", "session_failure", "scheduling")
    ready = status["state"] == "RUNNING" and bool(status.get("session")) and not status.get("canceled")
    return {"job": job, "handle": handle, "ready": ready, **{key: status[key] for key in fields if key in status}}


def close_debug() -> int:
    pending = _pending_debug()
    if pending:
        canceled = rpc("cancel_submission", request_id=pending["request_id"], request_secret=pending["request_secret"])
        if not canceled.get("handle"):
            os.environ.pop("OPENRC_TESTQUEUE_SUBMISSION", None)
            os.environ.pop("OPENRC_DEBUG_BRIDGE", None)
            print(json.dumps({"stopped": True, "cancellation_recorded": True, "state": "CANCELED_BEFORE_ACCEPTANCE"}))
            return 0
        _retain_debug(canceled)
    handle = os.environ.get("OPENRC_TESTQUEUE_HANDLE", "")
    status = rpc("cancel", handle=handle)
    status = wait(status["id"], timeout=20)
    result = {"stopped": status["state"] == "FINISHED", "state": status["state"], "cleanup": status.get("cleanup")}
    if "wait_observation" in status:
        result["wait_observation"] = status["wait_observation"]
    print(json.dumps(result))
    return 0 if status["state"] == "FINISHED" and status.get("cleanup") == "CONFIRMED" else 1


def request(command: str, args: dict | None, timeout: float, port: int | None):
    handle = os.environ.get("OPENRC_TESTQUEUE_HANDLE", "")
    if not handle:
        raise ValueError("explicit OPENRC_TESTQUEUE_HANDLE required; launch your own session or supply its handle")
    return rpc("bridge", handle=handle, command=command, args=args or {}, port=port,
               timeout=min(timeout + 5, 605), **{"bridge_timeout": timeout})


def run(preset: str, argv: list[str], source: Path, *, timeout: float | None = None) -> int:
    options = {"argv": argv}
    if timeout is not None:
        options["timeout"] = timeout
        # Refuse invalid explicit leases before submit can copy or contact the
        # authority. submit validates again at its own boundary.
        from .presets import validate
        try:
            validate(preset, options)
        except OverflowError as error:
            raise ValueError("execution timeout must be between 1 and 21600 seconds") from error
    elif preset in {"suite", "ci", "capture"}:
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
