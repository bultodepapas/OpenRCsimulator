#!/usr/bin/env python3
"""Reproduce MCP control-plane gaps using stubs only; never contact a worker.

These are audit observations of the 2026-11-15 baseline, not desired-behavior
regression tests. Run from any directory with Python 3.12 or later.
"""
from __future__ import annotations

import io
import json
from pathlib import Path
import sys
import threading
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(REPO / "tools" / "debug"))
import mcp_server  # noqa: E402
from tools.testqueue import common  # noqa: E402


def serial_dispatch() -> dict:
    entered, release = threading.Event(), threading.Event()
    consumed, calls, failures = [], [], []
    messages = [
        {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
         "params": {"name": "sim_command", "arguments": {"command": "audit_stub"}}},
        {"jsonrpc": "2.0", "method": "notifications/cancelled",
         "params": {"requestId": 1, "reason": "audit stub cancellation"}},
        {"jsonrpc": "2.0", "id": 2, "method": "ping"},
        {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
         "params": {"name": "sim_stop", "arguments": {}}},
    ]

    def input_lines():
        for message in messages:
            consumed.append(message.get("id", "notification"))
            yield json.dumps(message) + "\n"

    def fake_tool(name, arguments):
        calls.append(name)
        if name == "sim_command":
            entered.set()
            if not release.wait(5):
                raise RuntimeError("audit harness did not release its stub")
        return [{"type": "text", "text": "stub completed; no external work"}]

    output = io.StringIO()

    def serve():
        try:
            mcp_server.serve(input_lines(), output)
        except BaseException as error:
            failures.append(repr(error))

    with patch.object(mcp_server, "call_tool", side_effect=fake_tool):
        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        try:
            if not entered.wait(5):
                raise RuntimeError("stub never started")
            while_blocked = {"consumed": list(consumed), "replies": output.getvalue(),
                             "tool_calls": list(calls)}
        finally:
            release.set()
            thread.join(5)
        if thread.is_alive() or failures:
            raise RuntimeError(f"audit harness failed: {failures}")

    replies = [json.loads(line) for line in output.getvalue().splitlines()]
    assert while_blocked == {"consumed": [1], "replies": "", "tool_calls": ["sim_command"]}
    assert [reply["id"] for reply in replies] == [1, 2, 3]
    assert not replies[0]["result"]["isError"]
    assert calls == ["sim_command", "sim_stop"]
    return {"observation": "ping, cancellation and stop are unread while a tool is executing",
            "consumed_while_tool_blocked": while_blocked["consumed"],
            "reply_ids_after_release": [reply["id"] for reply in replies],
            "original_request_completed_after_queued_cancellation": True,
            "live_workers_contacted": 0}


def zero_wait_rpc_budget() -> dict:
    observed = []

    def fake_rpc(operation, *, root=None, timeout=30, **payload):
        observed.append({"operation": operation, "timeout_seconds": timeout})
        return {"state": "QUEUED", "id": "audit-stub"}

    with patch.object(common, "rpc", side_effect=fake_rpc):
        result = common.wait("audit-stub", timeout=0)
    assert observed == [{"operation": "status", "timeout_seconds": 30}]
    assert result["state"] == "QUEUED"
    return {"observation": "a zero-second observer budget still permits the default 30-second status RPC",
            "rpc_calls": observed, "live_workers_contacted": 0}


if __name__ == "__main__":
    print(json.dumps({"baseline": "c048a4e6834646400070a488b293344dc1e1fd80",
                      "scope": "stubbed control flow; no simulator or network",
                      "serial_dispatch": serial_dispatch(),
                      "zero_wait_rpc_budget": zero_wait_rpc_budget()}, indent=2))
