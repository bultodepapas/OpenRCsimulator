"""Observer deadlines against an isolated loopback peer and controlled sockets."""
from __future__ import annotations

import contextlib
import io
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import time
import unittest
from unittest import mock

from tools.testqueue import common, integration


class LoopbackPeer:
    def __init__(self, handler, count=1):
        self.temporary = tempfile.TemporaryDirectory(prefix="openrc-observer-")
        self.root = Path(self.temporary.name)
        self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server.bind(("127.0.0.1", 0))
        self.server.listen()
        self.server.settimeout(0.1)
        self.stop = threading.Event()
        self.requests = []
        self.errors = []
        (self.root / "endpoint.json").write_text(json.dumps({
            "version": common.VERSION, "port": self.server.getsockname()[1], "auth": "fixture-only"
        }), encoding="utf-8")

        def serve():
            try:
                for index in range(count):
                    while not self.stop.is_set():
                        try:
                            connection, _address = self.server.accept()
                            break
                        except socket.timeout:
                            continue
                    else:
                        return
                    with connection:
                        connection.settimeout(2)
                        data = bytearray()
                        while not data.endswith(b"\n"):
                            chunk = connection.recv(4096)
                            if not chunk:
                                return
                            data.extend(chunk)
                        self.requests.append(json.loads(data))
                        handler(index, connection, self.stop)
            except OSError as error:
                if not self.stop.is_set():
                    self.errors.append(error)
            except BaseException as error:
                self.errors.append(error)

        self.thread = threading.Thread(target=serve, daemon=True)
        self.thread.start()

    def close(self):
        self.stop.set()
        self.thread.join(3)
        self.server.close()
        self.temporary.cleanup()
        if self.thread.is_alive() or self.errors:
            raise AssertionError(f"loopback fixture failed: {self.errors!r}")


def reply(connection, result):
    connection.sendall((json.dumps({"ok": True, "result": result}) + "\n").encode())


class RpcDeadlineTests(unittest.TestCase):
    def test_no_reply_times_out_without_fabricating_status_or_canceling(self):
        peer = LoopbackPeer(lambda _i, _c, stop: stop.wait(5))
        try:
            started = time.monotonic()
            with self.assertRaisesRegex(common.ObservationTimeout, "owned.*retry status") as raised:
                common.wait("owned", root=peer.root, timeout=0.2)
            self.assertEqual(raised.exception.reason, "DEADLINE_EXPIRED")
            self.assertLess(time.monotonic() - started, 2)
            self.assertEqual([(r["operation"], r["job"]) for r in peer.requests], [("status", "owned")])
        finally:
            peer.close()

    def test_trickled_bytes_cannot_extend_observation_deadline(self):
        def trickle(_index, connection, stop):
            for byte in b'{"ok":true,"result":{"state":"FINISHED"}}\n':
                if stop.wait(0.025):
                    return
                with contextlib.suppress(OSError):
                    connection.sendall(bytes([byte]))

        peer = LoopbackPeer(trickle)
        try:
            started = time.monotonic()
            with self.assertRaises(common.ObservationTimeout):
                common.wait("owned", root=peer.root, timeout=0.2)
            self.assertLess(time.monotonic() - started, 2)
            self.assertEqual([r["operation"] for r in peer.requests], ["status"])
        finally:
            peer.close()

    def test_timed_out_launch_returns_same_accepted_handle_without_canceling(self):
        peer = LoopbackPeer(lambda _i, _c, stop: stop.wait(5))
        accepted = {"job": "owned", "handle": "owned:fixture-secret"}
        try:
            with mock.patch.dict(os.environ, {}, clear=True), \
                    mock.patch.object(integration, "submit", return_value=accepted), \
                    mock.patch.object(common, "state_root", return_value=peer.root), \
                    contextlib.redirect_stdout(io.StringIO()) as output, contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(integration.open_debug([], peer.root, wait_timeout=0.2), 0)
                result = json.loads(output.getvalue())
                self.assertEqual(result["state"], "ACCEPTED")
                self.assertEqual(result["observation"], "TIMEOUT")
                self.assertEqual(result["observation_reason"], "DEADLINE_EXPIRED")
                self.assertEqual(result["handle"], accepted["handle"])
                self.assertEqual(os.environ["OPENRC_TESTQUEUE_HANDLE"], accepted["handle"])
            self.assertEqual([r["operation"] for r in peer.requests], ["status"])
        finally:
            peer.close()

    def test_timeout_after_status_returns_last_observation(self):
        queued = {"state": "QUEUED", "reason": "RESOURCE_BUSY"}

        def handler(index, connection, stop):
            if index == 0:
                reply(connection, queued)
            else:
                stop.wait(5)

        peer = LoopbackPeer(handler, count=2)
        try:
            self.assertEqual(common.wait("owned", root=peer.root, timeout=0.5), {
                **queued, "wait_observation": {"state": "STALE", "reason": "DEADLINE_EXPIRED"}})
            self.assertEqual([r["operation"] for r in peer.requests], ["status", "status"])
            self.assertEqual([r["job"] for r in peer.requests], ["owned", "owned"])
        finally:
            peer.close()

    def test_default_rpc_path_still_reads_a_normal_reply(self):
        peer = LoopbackPeer(lambda _i, connection, _s: reply(connection, {"state": "QUEUED"}))
        try:
            self.assertEqual(common.rpc("status", root=peer.root, job="owned"), {"state": "QUEUED"})
        finally:
            peer.close()

    def test_deadline_reader_retains_protocol_size_limit(self):
        peer = LoopbackPeer(lambda _i, connection, _s: connection.sendall(b"x" * 21))
        try:
            with mock.patch.object(common, "LIMIT", 20), self.assertRaisesRegex(ValueError, "protocol limit"):
                common.rpc("status", root=peer.root, deadline=time.monotonic() + 2, job="owned")
        finally:
            peer.close()

    def test_remaining_budget_is_recomputed_for_connect_send_and_receive(self):
        with tempfile.TemporaryDirectory(prefix="openrc-observer-socket-") as directory:
            root = Path(directory)
            (root / "endpoint.json").write_text(json.dumps({"version": common.VERSION, "port": 9999, "auth": "fixture"}))
            now, timeouts = [100.0], []

            class Connection:
                closed = False

                def __enter__(self):
                    return self

                def __exit__(self, *_args):
                    self.closed = True

                def settimeout(self, value):
                    timeouts.append(value)

                def connect(self, address):
                    self.address = address
                    now[0] += 0.3

                def sendall(self, payload):
                    self.request = json.loads(payload)
                    now[0] += 0.3

                def recv(self, _size):
                    now[0] += 0.2
                    return b'{"ok":true,"result":{"state":"QUEUED"}}\n'

            connection = Connection()
            with mock.patch.object(common.socket, "socket", return_value=connection), \
                    mock.patch.object(common.time, "monotonic", side_effect=lambda: now[0]):
                result = common.rpc("status", root=root, deadline=101.0, job="owned")
            self.assertEqual(result, {"state": "QUEUED"})
            self.assertEqual(connection.address, ("127.0.0.1", 9999))
            self.assertEqual(connection.request["operation"], "status")
            self.assertTrue(connection.closed)
            for actual, expected in zip(timeouts, (1.0, 0.7, 0.4), strict=True):
                self.assertAlmostEqual(actual, expected)

    def test_late_connect_closes_socket_before_propagating_timeout(self):
        with tempfile.TemporaryDirectory(prefix="openrc-observer-socket-") as directory:
            root = Path(directory)
            (root / "endpoint.json").write_text(json.dumps({"version": common.VERSION, "port": 9999, "auth": "fixture"}))
            now = [100.0]

            class Connection:
                closed = False

                def __enter__(self):
                    return self

                def __exit__(self, *_args):
                    self.closed = True

                def settimeout(self, _value):
                    pass

                def connect(self, _address):
                    now[0] += 1.1

            connection = Connection()
            with mock.patch.object(common.socket, "socket", return_value=connection), \
                    mock.patch.object(common.time, "monotonic", side_effect=lambda: now[0]):
                with self.assertRaises(common.RpcDeadlineExceeded):
                    common.rpc("status", root=root, deadline=101.0, job="owned")
            self.assertTrue(connection.closed)

    def test_socket_step_timeout_is_reported_as_observation_timeout(self):
        with tempfile.TemporaryDirectory(prefix="openrc-observer-socket-") as directory:
            root = Path(directory)
            (root / "endpoint.json").write_text(json.dumps({"version": common.VERSION, "port": 9999, "auth": "fixture"}))

            class Connection:
                closed = False

                def __enter__(self):
                    return self

                def __exit__(self, *_args):
                    self.closed = True

                def settimeout(self, _value):
                    pass

                def connect(self, _address):
                    pass

                def sendall(self, _payload):
                    # The per-socket 30 s cap can expire before a longer total budget.
                    raise socket.timeout("fixture timeout")

            connection = Connection()
            with mock.patch.object(common.socket, "socket", return_value=connection), \
                    mock.patch.object(common.time, "monotonic", return_value=100.0):
                with self.assertRaisesRegex(common.ObservationTimeout, "owned.*retry status") as raised:
                    common.wait("owned", root=root, timeout=600)
            self.assertEqual(raised.exception.reason, "RPC_STEP_TIMEOUT")
            self.assertIsInstance(raised.exception.__cause__, common.RpcStepTimeout)
            self.assertTrue(connection.closed)


if __name__ == "__main__":
    unittest.main()
