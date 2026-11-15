"""Exercise the MCP stream with private, blocked tools and real local pipes."""
from __future__ import annotations

import contextlib
import io
import json
import os
import queue
import subprocess
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import debugctl  # noqa: E402
import mcp_server  # noqa: E402
from tools.testqueue import pool_mcp  # noqa: E402


def request(request_id, name, arguments=None):
    return {"jsonrpc": "2.0", "id": request_id, "method": "tools/call",
            "params": {"name": name, "arguments": arguments or {}}}


class PipeServer:
    def __init__(self):
        server_in, client_out = os.pipe()
        client_in, server_out = os.pipe()
        self.server_in = os.fdopen(server_in, "r", encoding="utf-8")
        self.client_out = os.fdopen(client_out, "w", buffering=1, encoding="utf-8")
        self.client_in = os.fdopen(client_in, "r", encoding="utf-8")
        self.server_out = os.fdopen(server_out, "w", buffering=1, encoding="utf-8")
        self.replies = queue.Queue()
        self.failures = []

        def serve():
            try:
                mcp_server.serve(self.server_in, self.server_out)
            except BaseException as error:
                self.failures.append(error)
            finally:
                self.server_in.close()
                with contextlib.suppress(OSError, ValueError):
                    self.server_out.close()

        def read():
            try:
                for line in self.client_in:
                    self.replies.put(json.loads(line))
            except BaseException as error:
                self.failures.append(error)

        self.thread = threading.Thread(target=serve, daemon=True)
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()
        self.thread.start()

    def send(self, *messages):
        self.client_out.write("".join(json.dumps(message) + "\n" for message in messages))
        self.client_out.flush()

    def get(self):
        return self.replies.get(timeout=3)

    def close_input(self):
        if not self.client_out.closed:
            self.client_out.close()

    def finish(self):
        self.close_input()
        self.thread.join(5)
        if self.thread.is_alive():
            raise AssertionError("server failed to drain accepted work")
        self.reader.join(3)
        self.client_in.close()
        if self.failures:
            raise AssertionError(f"stream failed: {self.failures!r}")


class McpTransportTests(unittest.TestCase):
    def test_abandoned_output_prevents_new_action_after_prepare(self):
        writing, fail_write, output_closed = threading.Event(), threading.Event(), threading.Event()
        prepared, resume_prepare = threading.Event(), threading.Event()
        failures = []
        original_prepare = mcp_server._prepare

        class BrokenSink:
            def write(self, _data):
                writing.set()
                if not fail_write.wait(5):
                    raise RuntimeError("fixture did not fail output")
                raise BrokenPipeError("fixture observer disconnected")

            def close(self):
                output_closed.set()

        def pause_prepare(message):
            result = original_prepare(message)
            if isinstance(message, dict) and message.get("id") == 2:
                prepared.set()
                if not resume_prepare.wait(5):
                    raise RuntimeError("fixture did not resume intake")
            return result

        def messages():
            yield json.dumps({"jsonrpc": "2.0", "id": 1, "method": "ping"}) + "\n"
            if not writing.wait(3):
                raise RuntimeError("writer did not reach fixture sink")
            yield json.dumps(request(2, "sim_command", {"command": "must-not-run"})) + "\n"

        def serve():
            try:
                mcp_server.serve(messages(), BrokenSink())
            except BaseException as error:
                failures.append(error)

        with patch.object(mcp_server, "_prepare", side_effect=pause_prepare), \
                patch.object(mcp_server, "call_tool") as tool:
            thread = threading.Thread(target=serve, daemon=True)
            thread.start()
            try:
                self.assertTrue(prepared.wait(3))
                fail_write.set()
                self.assertTrue(output_closed.wait(3))
                resume_prepare.set()
                thread.join(3)
                self.assertFalse(thread.is_alive())
                tool.assert_not_called()
                self.assertEqual(failures, [])
            finally:
                fail_write.set()
                resume_prepare.set()
                thread.join(3)

    def test_full_real_stdout_pipe_does_not_hold_process_open_after_eof(self):
        # The child has a private stubbed tool. Its stdout pipe is intentionally
        # never read until after exit, so the writer really blocks in the OS.
        code = r'''
import os, sys, threading
from tools.debug import mcp_server
all_read, writing = threading.Event(), threading.Event()
prepare, write = mcp_server._prepare, os.write
def observe(message):
    result = prepare(message)
    if isinstance(message, dict) and message.get("id") == 4:
        all_read.set()
    return result
def track_write(fd, data):
    if fd == sys.stdout.fileno():
        writing.set()
    return write(fd, data)
def tool(_name, args):
    name = args["command"]
    if name == "one" and not all_read.wait(3):
        raise RuntimeError("input was not read")
    if name == "two" and not writing.wait(3):
        raise RuntimeError("writer did not start")
    sys.stderr.write(name + "\n")
    sys.stderr.flush()
    return [{"type": "text", "text": "x" * 2000000}]
mcp_server._prepare = observe
mcp_server.call_tool = tool
mcp_server.os.write = track_write
mcp_server.OUTPUT_QUEUE_LIMIT = 1
mcp_server.OUTPUT_ENQUEUE_SECONDS = 0.05
mcp_server.OUTPUT_DRAIN_SECONDS = 0.1
mcp_server.serve()
'''
        process = subprocess.Popen([sys.executable, "-c", code], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   cwd=Path(__file__).resolve().parents[2])
        try:
            messages = [request(index, "sim_command", {"command": name})
                        for index, name in enumerate(("one", "two", "three", "four"), 1)]
            process.stdin.write("".join(json.dumps(item) + "\n" for item in messages).encode())
            process.stdin.close()
            process.wait(timeout=5)
            errors = process.stderr.read().decode("utf-8", errors="replace")
            self.assertEqual(process.returncode, 0, errors)
            self.assertEqual(errors.splitlines(), ["one", "two", "three", "four"])
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            if not process.stdin.closed:
                process.stdin.close()
            process.stdout.close()
            process.stderr.close()

    def test_stalled_output_does_not_stop_accepted_fifo_actions_or_eof(self):
        writer_entered, release_writer = threading.Event(), threading.Event()
        writer_returned, intake_done = threading.Event(), threading.Event()
        calls, failures = [], []

        class StalledSink:
            def write(self, data):
                writer_entered.set()
                if not release_writer.wait(5):
                    raise RuntimeError("fixture did not release writer")
                writer_returned.set()
                return len(data)

            def flush(self):
                pass

        def messages():
            yield json.dumps(request(1, "sim_command", {"command": "one"})) + "\n"
            if not writer_entered.wait(3):
                raise RuntimeError("writer did not reach fixture sink")
            for number, name in ((2, "two"), (3, "three"), (4, "four")):
                yield json.dumps(request(number, "sim_command", {"command": name})) + "\n"
            intake_done.set()

        def tool(_name, arguments):
            calls.append(arguments["command"])
            if arguments["command"] == "two" and not intake_done.wait(3):
                raise RuntimeError("input stalled behind output")
            return [{"type": "text", "text": "fixture completed"}]

        def serve():
            try:
                mcp_server.serve(messages(), StalledSink())
            except BaseException as error:
                failures.append(error)

        with patch.object(mcp_server, "OUTPUT_QUEUE_LIMIT", 1), \
                patch.object(mcp_server, "OUTPUT_ENQUEUE_SECONDS", 0.05), \
                patch.object(mcp_server, "OUTPUT_DRAIN_SECONDS", 0.1), \
                patch.object(mcp_server, "call_tool", side_effect=tool):
            thread = threading.Thread(target=serve, daemon=True)
            thread.start()
            try:
                thread.join(3)
                self.assertFalse(thread.is_alive(), "EOF waited for the stalled writer")
                self.assertTrue(writer_entered.is_set())
                self.assertTrue(intake_done.is_set())
                self.assertEqual(calls, ["one", "two", "three", "four"])
                self.assertEqual(failures, [])
            finally:
                release_writer.set()
                thread.join(3)
                self.assertTrue(writer_returned.wait(3))

    def test_blocked_launch_leaves_ping_and_cached_status_live_and_drains_on_eof(self):
        entered, release = threading.Event(), threading.Event()
        calls = []

        def launch(_argv):
            calls.append("launch")
            print("launch diagnostic on stdout")
            print("launch diagnostic on stderr", file=sys.stderr)
            entered.set()
            if not release.wait(5):
                raise RuntimeError("fixture timed out")
            os.environ["OPENRC_TESTQUEUE_HANDLE"] = "fixture-handle"
            print(json.dumps({"job": "fixture", "handle": "fixture-handle"}))
            return 0

        def stop(_argv):
            calls.append(("stop", os.environ.get("OPENRC_TESTQUEUE_HANDLE")))
            print("stopped")
            return 0

        with patch.dict(os.environ, {}, clear=False), \
                patch.object(debugctl.admission, "enabled", return_value=False), \
                patch.object(debugctl, "launch", side_effect=launch), \
                patch.object(debugctl, "stop", side_effect=stop), \
                patch.object(pool_mcp, "status", return_value={"request_id": "batch", "phase": "cached"}):
            server = PipeServer()
            try:
                server.send(request("launch", "sim_launch"))
                self.assertTrue(entered.wait(3))
                server.send(
                    {"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": "launch"}},
                    {"jsonrpc": "2.0", "id": "ping", "method": "ping"},
                    request("status", "sim_test_status", {"request_id": "batch"}),
                    request("stop", "sim_stop"),
                )
                early = {reply["id"]: reply for reply in (server.get(), server.get())}
                self.assertEqual(set(early), {"ping", "status"})
                self.assertEqual(early["ping"]["result"], {})
                cached = json.loads(early["status"]["result"]["content"][0]["text"])
                self.assertEqual(cached["phase"], "cached")
                self.assertEqual(calls, ["launch"])
                # EOF must not discard either the executing or the queued action.
                server.close_input()
                server.thread.join(0.1)
                self.assertTrue(server.thread.is_alive())
                release.set()
                later = {reply["id"]: reply for reply in (server.get(), server.get())}
                self.assertEqual(set(later), {"launch", "stop"})
                self.assertFalse(later["launch"]["result"]["isError"])
                self.assertFalse(later["stop"]["result"]["isError"])
                self.assertEqual(calls, ["launch", ("stop", "fixture-handle")])
            finally:
                release.set()
                server.finish()
            self.assertTrue(server.replies.empty())

    def test_overload_rejects_only_unaccepted_work_and_duplicate_id_is_unambiguous(self):
        entered, release = threading.Event(), threading.Event()
        calls = []

        def tool(name, arguments):
            calls.append((name, arguments.get("command")))
            if arguments.get("command") == "first":
                entered.set()
                if not release.wait(5):
                    raise RuntimeError("fixture timed out")
            return [{"type": "text", "text": "done"}]

        with patch.object(mcp_server, "TOOL_QUEUE_LIMIT", 1), \
                patch.object(mcp_server, "call_tool", side_effect=tool):
            server = PipeServer()
            try:
                server.send(request(1, "sim_command", {"command": "first"}))
                self.assertTrue(entered.wait(3))
                server.send(request(2, "sim_command", {"command": "second"}),
                            request(1, "sim_command", {"command": "duplicate"}),
                            request(3, "sim_command", {"command": "rejected"}),
                            {"jsonrpc": "2.0", "id": 4, "method": "ping"},
                            {"jsonrpc": "2.0", "method": "tools/call",
                             "params": {"name": "sim_stop"}})
                early = [server.get() for _ in range(3)]
                duplicate = next(reply for reply in early if reply["id"] is None)
                self.assertEqual(duplicate["error"]["data"]["requestId"], 1)
                busy = next(reply for reply in early if reply["id"] == 3)
                self.assertEqual(busy["error"]["code"], -32000)
                self.assertIn("not accepted", busy["error"]["message"])
                self.assertEqual(next(reply for reply in early if reply["id"] == 4)["result"], {})
                release.set()
                self.assertEqual({server.get()["id"], server.get()["id"]}, {1, 2})
                self.assertEqual(calls, [("sim_command", "first"), ("sim_command", "second")])
                # A subsequent request uses a fresh wire ID.
                server.send(request(5, "sim_command", {"command": "later"}))
                self.assertEqual(server.get()["id"], 5)
                self.assertEqual(calls[-1], ("sim_command", "later"))
            finally:
                release.set()
                server.finish()
            self.assertTrue(server.replies.empty())

    def test_status_lane_is_bounded_and_does_not_block_ping(self):
        entered, release = threading.Event(), threading.Event()
        seen = []

        def status(request_id):
            seen.append(request_id)
            if request_id == "first":
                entered.set()
                if not release.wait(5):
                    raise RuntimeError("fixture timed out")
            return {"request_id": request_id}

        with patch.object(mcp_server, "STATUS_QUEUE_LIMIT", 1), patch.object(pool_mcp, "status", side_effect=status):
            server = PipeServer()
            try:
                server.send(request(1, "sim_test_status", {"request_id": "first"}))
                self.assertTrue(entered.wait(3))
                server.send(request(2, "sim_test_status", {"request_id": "second"}),
                            request(3, "sim_test_status", {"request_id": "third"}),
                            {"jsonrpc": "2.0", "id": 4, "method": "ping"})
                early = {reply["id"]: reply for reply in (server.get(), server.get())}
                self.assertEqual(early[3]["error"]["code"], -32000)
                self.assertEqual(early[4]["result"], {})
                release.set()
                self.assertEqual({server.get()["id"], server.get()["id"]}, {1, 2})
                self.assertEqual(seen, ["first", "second"])
            finally:
                release.set()
                server.finish()

    def test_input_limit_discards_whole_line_then_recovers(self):
        output = io.StringIO()
        ping = json.dumps({"jsonrpc": "2.0", "id": "after", "method": "ping"})
        with patch.object(mcp_server, "MAX_INPUT_CHARS", 100):
            mcp_server.serve(io.StringIO("x" * 550 + "\n" + ping + "\n"), output)
        replies = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(replies[0]["error"]["code"], -32600)
        self.assertEqual(replies[1], {"jsonrpc": "2.0", "id": "after", "result": {}})
        self.assertEqual(len(replies), 2)

    def test_broken_output_does_not_cancel_accepted_actions(self):
        entered, release, ping_seen = threading.Event(), threading.Event(), threading.Event()
        calls, failures = [], []
        server_in, client_out = os.pipe()
        client_in, server_out = os.pipe()
        os.close(client_in)  # The observer is already gone when the first reply is written.
        source = os.fdopen(server_in, "r", encoding="utf-8")
        sink = os.fdopen(server_out, "w", buffering=1, encoding="utf-8")
        client = os.fdopen(client_out, "w", buffering=1, encoding="utf-8")

        def tool(name, arguments):
            calls.append(name)
            if name == "sim_command":
                entered.set()
                if not release.wait(5):
                    raise RuntimeError("fixture timed out")
            return [{"type": "text", "text": "done"}]

        def serve():
            try:
                mcp_server.serve(source, sink)
            except BaseException as error:
                failures.append(error)

        prepare = mcp_server._prepare

        def observe_prepare(message):
            result = prepare(message)
            if isinstance(message, dict) and message.get("id") == 3:
                ping_seen.set()  # The preceding stop has already entered the FIFO.
            return result

        with patch.object(mcp_server, "call_tool", side_effect=tool), \
                patch.object(mcp_server, "_prepare", side_effect=observe_prepare):
            thread = threading.Thread(target=serve, daemon=True)
            thread.start()
            try:
                client.write(json.dumps(request(1, "sim_command", {"command": "first"})) + "\n")
                client.flush()
                self.assertTrue(entered.wait(3))
                client.write(json.dumps(request(2, "sim_stop")) + "\n" +
                             json.dumps({"jsonrpc": "2.0", "id": 3, "method": "ping"}) + "\n")
                client.flush()
                self.assertTrue(ping_seen.wait(3))
                client.close()
                release.set()
                thread.join(5)
                self.assertFalse(thread.is_alive())
                self.assertEqual(calls, ["sim_command", "sim_stop"])
                self.assertEqual(failures, [])
            finally:
                release.set()
                if not client.closed:
                    client.close()
                thread.join(5)
                source.close()
                with contextlib.suppress(OSError, ValueError):
                    sink.close()


if __name__ == "__main__":
    unittest.main()
