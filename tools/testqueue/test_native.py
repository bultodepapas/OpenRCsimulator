"""Opt-in Windows desktop campaign; never part of the default fake-runner suite."""
from __future__ import annotations

import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import unittest
import uuid

from tools.testqueue.common import rpc, wait, write_json
from tools.testqueue.integration import submit
from tools.testqueue.worker import desktop_ready, external_simulators


@unittest.skipUnless(os.name == "nt" and os.environ.get("OPENRC_TESTQUEUE_NATIVE_ENGINE"), "opt-in native Windows desktop campaign")
class NativeSessionTests(unittest.TestCase):
    def test_two_sessions_use_one_rendered_lifetime(self):
        repo = Path(__file__).resolve().parents[2]
        engine = Path(os.environ["OPENRC_TESTQUEUE_NATIVE_ENGINE"]).resolve()
        root = Path(os.environ["OPENRC_TESTQUEUE_ROOT"]).resolve()
        self.assertTrue(desktop_ready(), "active unlocked Windows desktop required")
        if external_simulators():
            self.skipTest("unmanaged simulators occupy this host; no native qualification")
        root.mkdir(parents=True, exist_ok=True)
        log = (root / "service.log").open("xb")
        worker = subprocess.Popen([sys.executable, str(repo / "tools/testqueue/testctl.py"), "serve", "--engine", str(engine)],
                                  env=os.environ.copy(), stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        handles = []
        evidence = {"source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()}
        try:
            deadline = time.monotonic() + 30
            while True:
                try:
                    evidence["host"] = rpc("hosts")
                    break
                except RuntimeError:
                    if worker.poll() is not None or time.monotonic() > deadline:
                        self.fail("worker did not start; inspect service.log")
                    time.sleep(0.2)
            first = submit("debug-session", {"argv": ["--mute"], "timeout": 240}, repo)
            handles.append(first["handle"])
            status = wait(first["job"], timeout=180, ready=True)
            self.assertEqual(status["state"], "RUNNING", status)
            self.assertTrue(status.get("session"), status)
            render = rpc("bridge", handle=first["handle"], command="render", args={}, bridge_timeout=30)
            self.assertTrue(render["ok"], render)
            evidence["render"] = render
            with self.assertRaises(ValueError):
                rpc("bridge", handle=first["job"] + ":" + "0" * 64, command="quit", args={})
            payload = status["payload"]
            second = rpc("submit", request_id=uuid.uuid4().hex, request_secret=secrets.token_hex(32),
                         preset="debug-session", options=payload["options"], owner="native-second-client",
                         snapshot=payload["snapshot"], source=str(repo))
            handles.append(second["handle"])
            time.sleep(1)
            waiting = rpc("status", job=second["job"])
            self.assertEqual(waiting["state"], "QUEUED", waiting)
            if waiting["reason"].startswith("EXTERNAL_SIMULATOR"):
                evidence.update(partial=True, blocked_reason=waiting["reason"], first=rpc("status", job=first["job"]))
                self.skipTest("unmanaged simulator appeared during campaign; retained partial evidence")
            self.assertIn("rendered", waiting["reason"])
            rpc("cancel", handle=first["handle"])
            stopped = wait(first["job"], timeout=30)
            self.assertEqual(stopped.get("cleanup"), "CONFIRMED", stopped)
            running = wait(second["job"], timeout=180, ready=True)
            self.assertEqual(running["state"], "RUNNING", running)
            self.assertTrue(running.get("session"), running)
            self.assertGreaterEqual(running["started"], stopped["finished"])
            rpc("cancel", handle=second["handle"])
            finished = wait(second["job"], timeout=30)
            self.assertEqual(finished.get("cleanup"), "CONFIRMED", finished)
            self.assertEqual(rpc("hosts")["claims"], [])
            evidence.update(first=stopped, second=finished, passed=True)
        finally:
            pending = []
            for handle in handles:
                try:
                    status = rpc("cancel", handle=handle)
                    pending.append(status["id"])
                except (ValueError, RuntimeError):
                    pass
            for job in pending:
                try:
                    wait(job, timeout=300)
                except (ValueError, RuntimeError):
                    pass
            evidence["cleanup_results"] = []
            for job in pending:
                try:
                    evidence["cleanup_results"].append(rpc("result", job=job))
                except (ValueError, RuntimeError):
                    evidence["cleanup_results"].append({"job": job, "cleanup": "UNKNOWN"})
            worker.terminate()
            worker.wait(timeout=10)
            log.close()
            write_json(root / "native-evidence.json", evidence)
        refused = subprocess.run([sys.executable, str(repo / "tools/debug/debugctl.py"), "launch", "--headless"],
                                 env=os.environ.copy(), capture_output=True, text=True, timeout=15)
        self.assertNotEqual(refused.returncode, 0, refused.stdout)
        self.assertIn("worker unavailable", refused.stderr)
        self.assertEqual(external_simulators(), [])


if __name__ == "__main__":
    unittest.main()
