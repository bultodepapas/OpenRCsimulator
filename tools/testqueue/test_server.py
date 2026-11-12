"""Real loopback clients and worker restart, using an isolated fake runner."""
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import time
import unittest

from tools.testqueue.common import rpc, wait
from tools.testqueue.snapshots import capture


class ProtocolTests(unittest.TestCase):
    def test_clients_idempotency_auth_and_completed_job_survive_restart(self):
        with tempfile.TemporaryDirectory(prefix="openrc-server space-") as temporary:
            base = Path(temporary)
            source, root, snapshot = base / "source", base / "state", base / "snapshot"
            source.mkdir()
            (source / "app").mkdir()
            (source / "app/project.godot").write_text("[application]\n")
            adapter = source / "tools/testqueue/adapter.py"
            adapter.parent.mkdir(parents=True)
            adapter.write_text("import json,sys\nfrom pathlib import Path\n(Path(sys.argv[1])/'verdict.json').write_text(json.dumps({'ok':True,'complete':True}))\n")
            for args in (["init", "-q"], ["add", "."], ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"]):
                subprocess.run(["git", *args], cwd=source, check=True, capture_output=True)
            capture(source, snapshot, scope=("app", "tools"))
            repo = Path(__file__).resolve().parents[2]
            environment = {**os.environ, "OPENRC_TESTQUEUE_ROOT": str(root)}
            environment.pop("OPENRC_TESTQUEUE_CONTEXT", None)
            code = "from pathlib import Path; import sys; from tools.testqueue.worker import Worker; Worker(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.executable), fixture=True).serve()"

            def start():
                process = subprocess.Popen([sys.executable, "-c", code, str(root), str(repo)], cwd=repo, env=environment,
                                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    try:
                        rpc("hosts", root=root, timeout=1)
                        return process
                    except (ValueError, RuntimeError):
                        if process.poll() is not None:
                            self.fail(process.communicate()[1].decode(errors="replace"))
                        time.sleep(0.05)
                process.terminate()
                process.communicate(timeout=5)
                self.fail("fixture worker startup timed out")

            request = dict(preset="debug-session", options={"argv": ["--headless"], "timeout": 10},
                           owner="first-client", source=str(source), snapshot=str(snapshot),
                           request_id="durable-client-request", request_secret=secrets.token_hex(32))
            worker = start()
            try:
                accepted = rpc("submit", root=root, **request)
                self.assertEqual(rpc("submit", root=root, **request), accepted)
                wrong = {**request, "request_secret": "x" * 64}
                with self.assertRaises(ValueError):
                    rpc("submit", root=root, **wrong)
                outcome = wait(accepted["job"], root=root, timeout=15)
                self.assertEqual(outcome.get("outcome"), "PASSED", outcome)
                self.assertEqual(rpc("hosts", root=root)["claims"], [])
                endpoint = json.loads((root / "endpoint.json").read_text())
                with socket.create_connection(("127.0.0.1", endpoint["port"]), timeout=2) as connection:
                    connection.sendall(b'{"operation":"hosts","auth":"forged"}\n')
                    with connection.makefile("rb") as stream:
                        self.assertFalse(json.loads(stream.readline())["ok"])
            finally:
                worker.terminate()
                worker.communicate(timeout=10)
            worker = start()
            try:
                self.assertEqual(rpc("submit", root=root, **request), accepted)
                self.assertEqual(rpc("result", root=root, job=accepted["job"])["outcome"], "PASSED")
            finally:
                worker.terminate()
                worker.communicate(timeout=10)


if __name__ == "__main__":
    unittest.main()
