"""TELEM-08 qualification: the real Godot client against this receiver over loopback HTTP.

Skipped unless OPENRC_GODOT names a Godot 4.8 executable. Starts `python -m openrc_telemetry serve` on a free
loopback port with a temporary data directory, runs app/tests/telemetry_receiver_e2e.gd, then checks that every
batch the client reported as sent is stored once, passes this receiver's own validation and carries no
identifying field.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request

SERVICE_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = SERVICE_DIR.parents[1]
GODOT = os.environ.get("OPENRC_GODOT", "")


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


@unittest.skipUnless(GODOT and Path(GODOT).is_file(), "OPENRC_GODOT is not set")
class GodotClientEndToEnd(unittest.TestCase):
    def test_godot_client_batches_are_accepted_and_stored(self):
        # Windows may hold the receiver's database briefly after it exits.
        with tempfile.TemporaryDirectory(prefix="telemetry-e2e-", ignore_cleanup_errors=True) as data:
            port = free_port()
            env = dict(os.environ, OPENRC_TELEMETRY_DATA_DIR=data, OPENRC_TELEMETRY_RELEASES="v0.0.0",
                       PYTHONDONTWRITEBYTECODE="1")
            server = subprocess.Popen([sys.executable, "-m", "openrc_telemetry", "serve", "--host", "127.0.0.1",
                                       "--port", str(port)], cwd=SERVICE_DIR, env=env,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                deadline = time.monotonic() + 20
                while True:
                    try:
                        with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=1) as answer:
                            if answer.status == 200:
                                break
                    except OSError:
                        if time.monotonic() > deadline or server.poll() is not None:
                            self.fail("receiver did not start")
                        time.sleep(0.2)
                client = subprocess.run(
                    [GODOT, "--headless", "--path", str(REPO_ROOT / "app"), "--audio-driver", "Dummy", "--script",
                     "res://tests/telemetry_receiver_e2e.gd", "--", f"--url=http://127.0.0.1:{port}/v1/batches"],
                    capture_output=True, text=True, timeout=600)
                output = client.stdout + client.stderr
                self.assertNotIn("SCRIPT ERROR", output)
                self.assertEqual(client.returncode, 0, output[-4000:])
                summary = [line for line in output.splitlines() if line.startswith("E2E sent=")]
                self.assertTrue(summary, output[-2000:])
                sent = int(summary[-1].split()[1].split("=")[1])
            finally:
                server.terminate()
                server.wait(timeout=20)
            db = sqlite3.connect(str(Path(data) / "raw.sqlite"))
            try:
                bodies = [bytes(row[0]) for row in db.execute("SELECT body FROM batches ORDER BY rowid")]
            finally:
                db.close()
        self.assertEqual(len(bodies), sent)
        names = set()
        for body in bodies:
            payload = json.loads(body)
            self.assertEqual(payload["build"], {"release_id": "v0.0.0", "channel": "preview", "engine_minor": "4.8"})
            names.update(event["name"] for event in payload["events"])
            text = body.decode("utf-8").lower()
            for forbidden in ("user", "path", "\\\\", "c:/", "home/", "godot", "geforce", "radeon", "intel(r)"):
                self.assertNotIn(forbidden, text)
        self.assertTrue({"session_started", "performance_window", "activity_summary"} <= names, names)


if __name__ == "__main__":
    unittest.main()
