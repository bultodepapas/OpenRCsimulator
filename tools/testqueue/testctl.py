#!/usr/bin/env python3
"""Submit and inspect supervised OpenRC jobs. Guide: tools/testqueue/README.md."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import secrets
import sys
import time
import uuid

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue.common import rpc, state_root, wait, write_json, submission_receipt


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    serve = sub.add_parser("serve")
    serve.add_argument("--engine", required=True, type=Path)
    serve.add_argument("--headless-slots", type=int, default=None,
                       help="parallel headless capacity (1..8); remembered in capacity.json, default 1")
    serve.add_argument("--capture-slots", type=int, default=None,
                       help="parallel studio capture capacity (1..4); remembered in capacity.json, default 1; "
                            "qualify GPU/RAM/disk headroom before increasing")
    snapshot = sub.add_parser("snapshot")
    snapshot.add_argument("--source", type=Path, default=REPO)
    snapshot.add_argument("--out", required=True, type=Path)
    snapshot.add_argument("--imports", action="store_true")
    submit = sub.add_parser("submit")
    submit.add_argument("--preset", required=True)
    submit.add_argument("--snapshot", required=True, type=Path)
    submit.add_argument("--source", type=Path, default=REPO)
    submit.add_argument("--owner", required=True)
    submit.add_argument("--platform", default=platform.system().lower())
    submit.add_argument("--request-id", default=None)
    submit.add_argument("--request-secret", default=None)
    for name in ("resubmit", "recover", "cancel-submission"):
        sub.add_parser(name).add_argument("receipt", type=Path)
    submit.add_argument("--options", default="{}", help="JSON preset options")
    for name in ("hosts", "list"):
        sub.add_parser(name).add_argument("--json", action="store_true")
    for name in ("status", "result", "wait"):
        command = sub.add_parser(name)
        command.add_argument("job")
        command.add_argument("--json", action="store_true")
        if name == "wait":
            command.add_argument("--timeout", type=float, default=600)
    for name in ("cancel", "reconcile", "release"):
        sub.add_parser(name).add_argument("handle")
    abandon = sub.add_parser("abandon", help="operator release of an orphan with incomplete cleanup evidence")
    abandon.add_argument("handle")
    abandon.add_argument("--reason", required=True)
    sub.add_parser("reserve").add_argument("--owner", required=True)
    sub.add_parser("drain").add_argument("mode", choices=("on", "off"))
    return result


def serve_capacity(root, headless=None, capture=None):
    """Slot counts for ``serve``: explicit flags win and are remembered (TQ-07-A6).

    A restart without flags (the watchdog's) reuses the remembered counts, so a
    qualified capacity no longer silently falls back to one slot.
    """
    path = Path(root) / "capacity.json"
    saved = {}
    if path.exists():
        try:
            saved = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            raise ValueError(f"capacity.json is unreadable; fix or remove it: {error}") from error
        if not isinstance(saved, dict):
            raise ValueError("capacity.json must hold an object")
    value = {"headless_slots": headless if headless is not None else saved.get("headless_slots", 1),
             "capture_slots": capture if capture is not None else saved.get("capture_slots", 1)}
    if type(value["headless_slots"]) is not int or not 1 <= value["headless_slots"] <= 8:
        raise ValueError("headless slots must be in 1..8 (qualify isolation before increasing)")
    if type(value["capture_slots"]) is not int or not 1 <= value["capture_slots"] <= 4:
        raise ValueError("capture slots must be in 1..4 (qualify graphics headroom before increasing)")
    if headless is not None or capture is not None:
        write_json(path, {**value, "updated_at": time.time()})
    return value["headless_slots"], value["capture_slots"]


def main(argv=None):
    arguments = list(sys.argv[1:] if argv is None else argv)
    if arguments and arguments[0] == 'pool':
        from tools.testqueue.pool import main as pool_main
        return pool_main(arguments[1:])
    args = parser().parse_args(argv)
    if args.command == "serve":
        headless, capture = serve_capacity(state_root(), args.headless_slots, args.capture_slots)
        from tools.testqueue.worker import Worker
        worker = Worker(state_root(), REPO, args.engine, slots=headless, capture_slots=capture)
        write_json(state_root() / "enrollment.json", {"mode": "enforced", "host": worker.host_id})
        worker.serve()
        return 0
    if args.command == "snapshot":
        from tools.testqueue.snapshots import capture
        value = capture(args.source.resolve(), args.out.resolve(), include_imports=args.imports)
    elif args.command == "submit":
        request_id = args.request_id or uuid.uuid4().hex
        request = dict(preset=args.preset, snapshot=str(args.snapshot.resolve()), source=str(args.source.resolve()),
                       owner=args.owner, platform=args.platform, options=json.loads(args.options),
                       request_id=request_id, request_secret=args.request_secret or secrets.token_hex(32))
        prior_path = state_root() / "submissions" / (request_id + ".json") if request_id.isalnum() else None
        if args.request_secret is None and prior_path is not None and prior_path.is_file():
            request["request_secret"] = json.loads(prior_path.read_text(encoding="utf-8"))["request_secret"]
        # Retry credentials exist before the first byte of the submit RPC.
        receipt = submission_receipt(state_root(), request)
        print(f"testqueue submission receipt: {receipt}", file=sys.stderr)
        value = rpc("submit", **request)
    elif args.command in {"resubmit", "recover", "cancel-submission"}:
        request = json.loads(args.receipt.read_text(encoding="utf-8"))
        identity = {key: request[key] for key in ("request_id", "request_secret")}
        if args.command == "cancel-submission":
            value = rpc("cancel_submission", **identity)
        else:
            value = rpc("recover", **identity)
            if value is None:
                value = (rpc("submit", **request) if args.command == "resubmit"
                         else {"state": "SUBMISSION_UNCONFIRMED", "ready": False})
    elif args.command == "wait":
        value = wait(args.job, timeout=args.timeout)
    elif args.command in {"status", "result"}:
        value = rpc(args.command, job=args.job)
    elif args.command in {"cancel", "reconcile", "release"}:
        value = rpc(args.command, handle=args.handle)
    elif args.command == "abandon":
        value = rpc("abandon", handle=args.handle, reason=args.reason)
    elif args.command == "reserve":
        value = rpc("reserve", owner=args.owner)
    elif args.command == "drain":
        value = rpc("drain", enabled=args.mode == "on")
    else:
        value = rpc(args.command)
    print(json.dumps(value, indent=2, allow_nan=False))
    if args.command in {"result", "wait"}:
        return 0 if value.get("outcome") == "PASSED" else 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(f"testctl: {error}", file=sys.stderr)
        raise SystemExit(2)
