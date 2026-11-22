"""TELEM-08 qualification: the real Godot client against this receiver over loopback HTTP.

Skipped unless OPENRC_GODOT names a Godot 4.8 executable; CI sets OPENRC_REQUIRE_GODOT_E2E=1 to reject a skip.
Starts `python -m openrc_telemetry serve` on a free
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
from unittest.mock import patch

SERVICE_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = SERVICE_DIR.parents[1]
GODOT = os.environ.get("OPENRC_GODOT", "")
GODOT_AVAILABLE = bool(GODOT and Path(GODOT).is_file() and os.access(GODOT, os.X_OK))
if os.environ.get("OPENRC_REQUIRE_GODOT_E2E") == "1" and not GODOT_AVAILABLE:
    raise RuntimeError("required Godot telemetry E2E needs an executable OPENRC_GODOT; refusing to skip")

sys.path.insert(0, str(REPO_ROOT))


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


@unittest.skipUnless(GODOT_AVAILABLE, "OPENRC_GODOT is not set")
class GodotClientEndToEnd(unittest.TestCase):
    def test_godot_client_batches_are_accepted_and_stored(self):
        from tools.godot.run_checked import run_checked
        from tools.testqueue.common import enabled, inherited
        if os.environ.get("OPENRC_TESTPOOL_CONFIG") and not os.environ.get("OPENRC_TESTQUEUE_CONTEXT"):
            self.fail("loopback E2E requires an admitted same-host context, not remote script scheduling")
        if enabled() and not inherited("headless"):
            self.fail("loopback E2E on an enrolled host requires its existing headless admission context")
        # Windows may hold the receiver's database briefly after it exits.
        with tempfile.TemporaryDirectory(prefix="telemetry-e2e-", ignore_cleanup_errors=True) as data:
            port = free_port()
            # Operator settings must never redirect this fixture's databases or enable publication.
            env = {key: value for key, value in os.environ.items() if not key.startswith("OPENRC_TELEMETRY_")}
            env.update(OPENRC_TELEMETRY_DATA_DIR=data, OPENRC_TELEMETRY_RELEASES="v0.0.0",
                       PYTHONDONTWRITEBYTECODE="1")
            evidence_root = REPO_ROOT / "tmp" / "telemetry-e2e"
            evidence_root.mkdir(parents=True, exist_ok=True)
            evidence = Path(tempfile.mkdtemp(prefix="run-", dir=evidence_root))
            server_log = (evidence / "receiver.log").open("w", encoding="utf-8")
            server = subprocess.Popen([sys.executable, "-m", "openrc_telemetry", "serve", "--host", "127.0.0.1",
                                       "--port", str(port)], cwd=SERVICE_DIR, env=env,
                                      stdout=server_log, stderr=subprocess.STDOUT)
            try:
                # urllib's socket timeout is an inactivity limit; the subprocess
                # deadline also bounds a receiver that slowly trickles a response.
                ready = subprocess.run(
                    [sys.executable, str(REPO_ROOT / "tools/telemetry/wait_for_health.py"),
                     f"http://127.0.0.1:{port}/healthz", "--timeout", "20"],
                    capture_output=True, text=True, timeout=25)
                self.assertEqual(ready.returncode, 0, f"{ready.stderr}; evidence: {evidence}")
                self.assertIsNone(server.poll(), "receiver exited after its readiness check")
                # The receiver and client are coupled by loopback and must run on the same host.
                # The checked runner retains diagnostics, enforces completion, and honors local admission.
                with patch.dict(os.environ, {"XDG_DATA_HOME": str(Path(data) / "user-data"),
                                             "XDG_CONFIG_HOME": str(Path(data) / "config"),
                                             "XDG_CACHE_HOME": str(Path(data) / "cache"),
                                             "APPDATA": str(Path(data) / "appdata")}):
                    client = run_checked(
                        [GODOT, "--headless", "--path", str(REPO_ROOT / "app"), "--audio-driver", "Dummy", "--script",
                         "res://tests/telemetry_receiver_e2e.gd", "--", f"--url=http://127.0.0.1:{port}/v1/batches",
                         f"--consent-file={Path(data) / 'consent.cfg'}"],
                        out_dir=evidence / "checks", timeout=600, required=["E2E sent="], label="telemetry-client")
                output = Path(client["log"]).read_text(encoding="utf-8", errors="replace")
                self.assertTrue(client["ok"], f"{client['reason']}; evidence: {evidence}\n{output[-4000:]}")
                summary = [line for line in output.splitlines() if line.startswith("E2E sent=")]
                self.assertTrue(summary, output[-2000:])
                sent = int(summary[-1].split()[1].split("=")[1])
            finally:
                if server.poll() is None:
                    server.terminate()
                try:
                    server.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=10)
                server_log.close()
                print(f"Telemetry E2E evidence: {evidence}")
            # The receiver was killed (Windows TerminateProcess): its WAL/shm files can be briefly held or need
            # recovery, which intermittently surfaces as "disk I/O error" under load. Retry the read for a bounded time.
            for attempt in range(20):
                db = sqlite3.connect(str(Path(data) / "raw.sqlite"))
                try:
                    bodies = [bytes(row[0]) for row in db.execute("SELECT body FROM batches ORDER BY rowid")]
                    break
                except sqlite3.OperationalError:
                    if attempt == 19:
                        raise
                    time.sleep(0.5)
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
