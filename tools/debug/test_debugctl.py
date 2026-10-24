"""PT1h-R7: debugctl.py against a fake loopback bridge (no Godot): argument parsing, token, exit codes, output."""
from __future__ import annotations

import contextlib
import io
import json
import os
import socket
import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import debugctl  # noqa: E402


class FakeBridge:
    """Answers each connection's single JSON line like the Godot bridge and records the requests."""

    def __init__(self) -> None:
        self.server = socket.create_server(("127.0.0.1", 0))
        self.port = self.server.getsockname()[1]
        self.requests: list[dict] = []
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self) -> None:
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            with conn:
                request = json.loads(conn.makefile().readline())
                self.requests.append(request)
                if request["cmd"] == "ui":
                    result = {"scope": "AppRoot/Home", "focus": "AppRoot/Home/Fly", "controls": [
                        {"path": "AppRoot/Home/Fly", "type": "Button", "text": "Fly", "focused": True, "disabled": False},
                        {"path": "AppRoot/Home/Wind", "type": "HSlider", "text": "Wind", "focused": False,
                         "value": 2.5, "min": 0, "max": 10}]}
                    reply = {"id": request["id"], "ok": True, "result": result}
                elif request["cmd"] == "nope":
                    reply = {"id": request["id"], "ok": False, "error": "unknown command 'nope'; try help"}
                else:
                    reply = {"id": request["id"], "ok": True, "result": {"echo": request}}
                conn.sendall((json.dumps(reply) + "\n").encode())

    def close(self) -> None:
        with contextlib.suppress(OSError):
            self.server.shutdown(socket.SHUT_RDWR)  # wakes the blocked accept()
        self.server.close()


class DebugctlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bridge = FakeBridge()
        self.env = dict(os.environ)
        os.environ["OPENRC_DEBUG_BRIDGE"] = str(self.bridge.port)
        os.environ.pop("OPENRC_DEBUG_TOKEN", None)

    def tearDown(self) -> None:
        self.bridge.close()
        os.environ.clear()
        os.environ.update(self.env)

    def run_cli(self, *argv: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = debugctl.main(list(argv))
        return status, out.getvalue(), err.getvalue()

    def test_key_values_are_json_when_possible(self) -> None:
        status, out, _ = self.run_cli("sticks", "roll=0.4", "release=true", "text=Fly", 'expr=flight.session.sim.tick > 3')
        self.assertEqual(status, 0)
        sent = self.bridge.requests[-1]
        self.assertEqual((sent["cmd"], sent["roll"], sent["release"], sent["text"]), ("sticks", 0.4, True, "Fly"))
        self.assertEqual(sent["expr"], "flight.session.sim.tick > 3")
        self.assertEqual(json.loads(out)["echo"]["cmd"], "sticks")

    def test_token_is_sent_from_the_environment(self) -> None:
        os.environ["OPENRC_DEBUG_TOKEN"] = "s3cret"
        self.run_cli("ping")
        self.assertEqual(self.bridge.requests[-1]["token"], "s3cret")

    def test_bridge_errors_exit_one(self) -> None:
        status, out, err = self.run_cli("nope")
        self.assertEqual((status, out), (1, ""))
        self.assertIn("unknown command", err)

    def test_usage_and_connection_errors_exit_two(self) -> None:
        self.assertEqual(self.run_cli("press", "Fly")[0], 2)
        with socket.create_server(("127.0.0.1", 0)) as unused:
            free_port = unused.getsockname()[1]
        os.environ["OPENRC_DEBUG_BRIDGE"] = str(free_port)  # nothing listens there now
        status, _, err = self.run_cli("ping")
        self.assertEqual(status, 2)
        self.assertIn("debugctl:", err)

    def test_ui_prints_a_table_and_json_on_request(self) -> None:
        status, out, _ = self.run_cli("ui")
        lines = out.splitlines()
        self.assertEqual(status, 0)
        self.assertTrue(lines[0].startswith("# scope AppRoot/Home"))
        self.assertTrue(lines[1].startswith("* Button") and lines[1].endswith("AppRoot/Home/Fly"))
        self.assertIn("value=2.5 [0..10]", lines[2])
        self.assertEqual(json.loads(self.run_cli("ui", "--json")[1])["focus"], "AppRoot/Home/Fly")


if __name__ == "__main__":
    unittest.main()
