"""Recovery of an accepted request while its owned fake process is live."""

import json
import unittest
from unittest import mock

from tools.testqueue import snapshots, test_worker
from tools.testqueue.pool import Pool


class PoolRecoveryProcessTests(unittest.TestCase):
    def test_lost_acceptance_recovers_live_attempt_after_manifest_disappears(self):
        fixture = test_worker.WorkerFixture(methodName="runTest")
        self.addCleanup(fixture.doCleanups)
        fixture.setUp()

        # Only the private fixture adapter is changed; no simulator is launched.
        original = 'elif owner.startswith("long"):'
        self.assertIn(original, test_worker._ADAPTER)
        fixture._write("tools/testqueue/adapter.py", test_worker._ADAPTER.replace(
            original, 'elif owner.startswith(("long", "automatic-pool")):'))
        snapshot = fixture.base / "long-snapshot"
        snapshots.capture(fixture.repo, snapshot, scope=("app", "tools"))
        config = fixture.base / "private-pool.json"
        config.write_text(json.dumps({"state_root": str(fixture.base / "pool"),
                                      "hosts": [{"id": "windows", "local": True}]}), encoding="utf-8")
        pool = Pool(config)
        calls = []
        accepted = []

        def local_rpc(operation, *, root=None, **payload):
            self.assertEqual(root, fixture.worker.root)
            calls.append((operation, payload))
            try:
                result = fixture._call(operation, **payload)
            except Exception as error:
                # The RPC client surfaces a worker refusal as ValueError.
                raise ValueError(str(error)) from error
            if operation == "submit" and not accepted:
                accepted.append(result)
                fixture.handles.append(result)

                def started():
                    status = fixture._status(result["job"])
                    if status["state"] != "RUNNING" or not status["attempts"]:
                        return False
                    directory = fixture.worker.root / "attempts" / status["attempts"][-1]["id"]
                    return (directory / "started.json").is_file()

                test_worker.wait_until(started, timeout=10)
                raise RuntimeError("injected lost acceptance acknowledgement")
            return result

        with mock.patch("tools.testqueue.pool.rpc", side_effect=local_rpc), \
             mock.patch("tools.testqueue.pool.state_root", return_value=fixture.worker.root), \
             mock.patch.object(pool, "probe", return_value=[]), \
             mock.patch("tools.testqueue.pool.plan", return_value={"selected": "windows"}), \
             mock.patch("tools.testqueue.worker.platform.system", return_value="Windows"):
            submitted = pool.submit(snapshot, "res://tests/test_fixture.gd",
                                    timeout=40, request_id="localrecoveryfixture")
            receipt_path = pool.root / "jobs" / "localrecoveryfixture.json"
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            self.assertEqual(submitted["state"], "SUBMISSION_UNCONFIRMED")
            self.assertEqual(receipt["state"], "SUBMISSION_UNCONFIRMED")
            self.assertEqual(len(accepted), 1)
            actual = fixture._call("recover", request_id=receipt["request"]["request_id"],
                                   request_secret=receipt["request"]["request_secret"])
            self.assertEqual(actual, {key: accepted[0][key] for key in ("job", "handle")})
            live = fixture._status(actual["job"])
            self.assertEqual(live["state"], "RUNNING")
            self.assertEqual(len(live["attempts"]), 1)
            attempt = live["attempts"][0]["id"]
            with fixture.worker.lock, fixture.worker._process_lock:
                owned_process = fixture.worker.active[attempt]
                self.assertTrue(owned_process.alive())
                before_claims = [tuple(row) for row in fixture.worker.store.db.execute(
                    "SELECT resource, amount FROM claims WHERE attempt=? ORDER BY resource", (attempt,))]
            self.assertTrue(before_claims)

            (snapshot / "manifest.json").rename(snapshot / "manifest.unavailable")
            calls.clear()
            recovered = pool.recover("localrecoveryfixture")
            self.assertEqual(recovered["state"], "RUNNING")
            self.assertEqual(recovered["job"], "localrecoveryfixture")
            self.assertEqual(calls[0][0], "recover")
            self.assertNotIn("submit", [operation for operation, _ in calls])
            for operation, payload in calls:
                if operation == "recover":
                    self.assertEqual(payload, {"request_id": "localrecoveryfixture",
                                               "request_secret": receipt["request"]["request_secret"]})
                elif operation == "status":
                    self.assertEqual(payload, {"job": actual["job"]})
                else:
                    self.fail(f"unexpected RPC: {operation}")
            self.assertEqual(json.loads(receipt_path.read_text(encoding="utf-8"))["state"], "SUBMITTED")
            self.assertEqual(pool.status("localrecoveryfixture")["state"], "RUNNING")
            self.assertNotIn("submit", [operation for operation, _ in calls])

            still_live = fixture._status(actual["job"])
            self.assertEqual(still_live["state"], "RUNNING")
            self.assertEqual([item["id"] for item in still_live["attempts"]], [attempt])
            with fixture.worker.lock, fixture.worker._process_lock:
                self.assertIs(fixture.worker.active[attempt], owned_process)
                self.assertTrue(owned_process.alive())
                after_claims = [tuple(row) for row in fixture.worker.store.db.execute(
                    "SELECT resource, amount FROM claims WHERE attempt=? ORDER BY resource", (attempt,))]
            self.assertEqual(after_claims, before_claims)

            fixture._call("cancel", handle=actual["handle"])
            finished = fixture._finish(actual["job"], timeout=12)
            self.assertEqual(finished["state"], "FINISHED")
            self.assertEqual(finished.get("cleanup"), "CONFIRMED")


if __name__ == "__main__":
    unittest.main()
