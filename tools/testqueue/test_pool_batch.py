"""Crash recovery, independent execution and evidence boundaries of pool batches."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.testqueue.test_pool import verified_fixture
from tools.testqueue.test_collection import checked_fixture

from tools.testqueue.common import Singleton
from tools.testqueue.collection import FORMAT as COLLECTION_FORMAT
from tools.testqueue.pool import Pool
from tools.testqueue.pool_batch import run_batch


PASS = {"state": "FINISHED", "outcome": "PASSED", "evidence": "COMPLETE", "cleanup": "CONFIRMED"}


class FakePool:
    def __init__(self, state_path):
        self.state_path = state_path
        self.submit_calls = []
        self.status_calls = []
        self.collect_calls = []
        self.verify_calls = []
        self.submissions = {}
        self.statuses = {}
        self.wait_once = set()
        self.wait_decisions = {}
        self.crash_once = False

    def submit(self, snapshot, script, *, platform, require, timeout, host_id, request_id,
               expected_manifest_sha256):
        saved = json.loads(self.state_path.read_text())
        assert request_id in [row["request_id"] for row in saved["jobs"]]
        assert all(row.get("request_id") for row in saved["jobs"])
        self.submit_calls.append((script, request_id))
        if script in self.wait_once:
            self.wait_once.remove(script)
            return {"state": "WAITING", "decision": self.wait_decisions.get(script, {"selected": None})}
        # The real pool binds the input and request ID to one durable receipt.
        self.submissions.setdefault(request_id, script)
        if self.crash_once:
            self.crash_once = False
            raise SystemExit("simulated crash after launch")
        return {"state": "SUBMITTED", "job": request_id}

    def status(self, request_id):
        self.status_calls.append(request_id)
        value = self.statuses.get(request_id, PASS)
        if isinstance(value, list):
            return value.pop(0) if len(value) > 1 else value[0]
        return value

    def collect(self, request_id):
        self.collect_calls.append(request_id)
        state = json.loads(self.state_path.read_text())
        row = next(item for item in state["jobs"] if item["request_id"] == request_id)
        return {"pool_job": request_id, "pool_outcome": row["status"]["outcome"],
                "collection_format": COLLECTION_FORMAT, "diagnostic_only": False}

    def needs_reobservation(self, request_id, status):
        return False

    def verify_collection(self, request_id, result):
        self.verify_calls.append(request_id)
        return result


class PoolBatchTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="openrc-batch-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.config = self.root / "config.json"
        self.config.write_text('{"hosts": []}', encoding="utf-8")
        self.snapshot = self.root / "snapshot"
        self.snapshot.mkdir()
        (self.snapshot / "manifest.json").write_text('{"source_digest": "fixture"}', encoding="utf-8")
        self.manifest = self.root / "batch.json"
        self.state = self.root / "state.json"
        self.pool = FakePool(self.state)

    def inputs(self, jobs):
        self.manifest.write_text(json.dumps({"snapshot": "snapshot", "jobs": jobs}), encoding="utf-8")

    def run_case(self):
        # Generous budget: run_batch returns as soon as every row is final or blocked,
        # so this only absorbs slow fsync/antivirus stalls on loaded hosts.
        return run_batch(self.pool, self.config, self.manifest, self.state, timeout=15, poll_interval=0)

    def test_independent_rows_wait_then_run_without_retrying_failure(self):
        first = "res://tests/test_a.gd"
        second = "res://tests/test_b.gd"
        self.inputs([{"script": first}, {"script": second, "platform": "darwin", "host": "mac-1"}])
        self.pool.wait_once.add(first)
        result = self.run_case()
        self.assertEqual(result["result"], "PASSED")
        calls = list(self.pool.submit_calls)
        # WAITING for platform "any" proves no host is eligible for the
        # narrower darwin/mac-1 row, so that row waits for the next pass.
        self.assertEqual([call[0] for call in calls], [first, first, second])
        self.assertEqual(calls[0][1], calls[1][1])
        self.assertNotEqual(calls[0][1], calls[2][1])
        self.assertEqual(len(self.pool.submissions), 2)
        self.run_case()
        self.assertEqual(self.pool.submit_calls, calls)

    def test_waiting_constraint_skips_only_same_or_narrower_rows_in_that_pass(self):
        a, b, c, d = (f"res://tests/test_{name}.gd" for name in "abcd")
        self.inputs([{"script": a, "platform": "linux"}, {"script": b, "platform": "linux", "host": "l1"},
                     {"script": c, "platform": "windows"}, {"script": d}])
        self.pool.wait_once.add(a)
        result = self.run_case()
        self.assertEqual(result["result"], "PASSED")
        # linux waited: the linux/l1 row is skipped, windows proceeds; the
        # broader "any" row is not implied by a linux wait and proceeds too.
        self.assertEqual([call[0] for call in self.pool.submit_calls], [a, c, d, a, b])
        self.assertEqual(len(self.pool.submissions), 4)

    def test_script_specific_history_refusal_does_not_hold_back_other_rows(self):
        a, b = "res://tests/test_a.gd", "res://tests/test_b.gd"
        self.inputs([{"script": a}, {"script": b}])
        self.pool.wait_once.add(a)
        self.pool.wait_decisions[a] = {"selected": None, "candidates": [
            {"host": "linux", "eligible": False,
             "reasons": ["INVALID_INVENTORY: historical duration must be positive"]}]}
        self.assertEqual(self.run_case()["result"], "PASSED")
        self.assertEqual([call[0] for call in self.pool.submit_calls], [a, b, a])

    def test_longest_expected_test_is_submitted_first(self):
        short, long, unmeasured = (f"res://tests/test_{name}.gd" for name in ("short", "long", "new"))
        self.inputs([{"script": short}, {"script": unmeasured, "timeout": 20}, {"script": long}])
        medians = {short: 2.0, long: 50.0}
        self.pool.expected_seconds = medians.get
        self.assertEqual(self.run_case()["result"], "PASSED")
        self.assertEqual([call[0] for call in self.pool.submit_calls], [long, unmeasured, short])
        self.pool.submit_calls.clear()
        self.state.unlink()
        self.pool.expected_seconds = lambda script: (_ for _ in ()).throw(OSError("history unavailable"))
        self.assertEqual(self.run_case()["result"], "PASSED")
        self.assertEqual([call[0] for call in self.pool.submit_calls], [short, long, unmeasured])

    def test_crash_after_launch_recovers_same_id_without_another_attempt(self):
        self.inputs([{"script": "res://tests/test_a.gd"}])
        self.pool.crash_once = True
        with self.assertRaises(SystemExit):
            self.run_case()
        receipt = json.loads(self.state.read_text())
        identifier = receipt["jobs"][0]["request_id"]
        self.assertIn(identifier, self.pool.submissions)
        result = self.run_case()
        self.assertEqual(result["result"], "PASSED")
        self.assertEqual([call[1] for call in self.pool.submit_calls], [identifier])
        self.assertEqual(len(self.pool.submissions), 1)

    def test_unknown_is_only_polled_on_resume_never_resubmitted(self):
        self.inputs([{"script": "res://tests/test_a.gd"}])
        original_status = self.pool.status
        self.pool.status = lambda identifier: {"state": "UNKNOWN", "error": "lost link"}
        result = self.run_case()
        self.assertEqual(result["result"], "INCOMPLETE")
        self.assertEqual(result["jobs"][0]["phase"], "BLOCKED")
        calls = list(self.pool.submit_calls)
        self.pool.status = original_status
        result = self.run_case()
        self.assertEqual(result["result"], "PASSED")
        self.assertEqual(self.pool.submit_calls, calls)

    def test_test_failure_and_missing_evidence_do_not_retry_or_pass(self):
        self.inputs([{"script": "res://tests/test_a.gd"}])
        self.pool.status = lambda identifier: {"state": "FINISHED", "outcome": "TEST_FAILED",
                                              "evidence": "COMPLETE", "cleanup": "CONFIRMED"}
        self.assertEqual(self.run_case()["result"], "FAILED")
        calls = list(self.pool.submit_calls)
        self.assertEqual(self.run_case()["result"], "FAILED")
        self.assertEqual(self.pool.submit_calls, calls)
        self.state.unlink()
        self.pool.status = lambda identifier: {"state": "FINISHED", "outcome": "PASSED"}
        self.assertEqual(self.run_case()["result"], "FAILED")

    def test_collection_failure_blocks_success_without_relaunching(self):
        self.inputs([{"script": "res://tests/test_a.gd"}])
        collect = self.pool.collect
        self.pool.collect = lambda identifier: (_ for _ in ()).throw(ValueError("digest mismatch"))
        result = self.run_case()
        self.assertEqual(result["result"], "INCOMPLETE")
        self.assertEqual(result["jobs"][0]["phase"], "COLLECTION_BLOCKED")
        self.assertIn("digest mismatch", result["jobs"][0]["collection_error"])
        calls = list(self.pool.submit_calls)
        self.pool.collect = collect
        self.assertEqual(self.run_case()["result"], "PASSED")
        self.assertEqual(self.pool.submit_calls, calls)

    def test_legacy_done_receipt_collects_evidence_without_resubmission(self):
        self.inputs([{"script": "res://tests/test_a.gd"}])
        state = self.run_case()
        row = state["jobs"][0]
        self.assertEqual(row["phase"], "DONE")
        identifier = row["request_id"]
        row.pop("collection")
        self.state.write_text(json.dumps(state), encoding="utf-8")
        calls = list(self.pool.submit_calls)
        self.pool.collect_calls.clear()
        recovered = self.run_case()
        self.assertEqual(recovered["result"], "PASSED")
        self.assertEqual(self.pool.submit_calls, calls)
        self.assertEqual(self.pool.collect_calls, [identifier])
        self.assertEqual(recovered["jobs"][0]["collection"]["pool_job"], identifier)

    def test_changed_batch_or_snapshot_cannot_start_another_row(self):
        self.inputs([{"script": "res://tests/test_a.gd"}])
        self.config.write_text(json.dumps({"state_root": str(self.root / "pool"), "hosts": []}))
        (self.snapshot / "manifest.json").write_text(json.dumps({"source_root": str(self.root),
                                                                  "source_digest": "source", "files": {}}))
        self.pool = Pool(self.config)
        with patch("tools.testqueue.pool.verify", side_effect=verified_fixture), \
                patch.object(self.pool, "probe", return_value=[]), patch("tools.testqueue.pool.rpc") as rpc:
            result = run_batch(self.pool, self.config, self.manifest, self.state, timeout=0.01, poll_interval=0.001)
            self.assertEqual(result["result"], "INCOMPLETE")
            (self.snapshot / "manifest.json").write_text("{}")
            result = self.run_case()
        rpc.assert_not_called()
        self.assertEqual(result["jobs"][0]["phase"], "REJECTED")
        self.assertIn("snapshot manifest changed", result["jobs"][0]["status"]["error"])
        self.manifest.write_text(self.manifest.read_text() + " ")
        with self.assertRaisesRegex(ValueError, "inputs changed"):
            self.run_case()

    def test_manifest_validation_precedes_any_execution_and_state_is_locked(self):
        self.inputs([{"script": "res://tests/test_a.gd"}, {"script": "res://tests/benchmark.gd"}])
        with self.assertRaisesRegex(ValueError, "performance"):
            self.run_case()
        self.assertFalse(self.state.exists())
        self.assertEqual(self.pool.submit_calls, [])
        self.inputs([{"script": "res://tests/test_a.gd"}])
        guard = Singleton(Path(str(self.state.resolve()) + ".lock"))
        try:
            with self.assertRaises(OSError):
                self.run_case()
        finally:
            guard.close()

    def test_real_pool_receipts_are_reused_on_batch_resume(self):
        self.config.write_text(json.dumps({"state_root": str(self.root / "pool"),
                                           "hosts": [{"id": "windows", "local": True}]}))
        (self.snapshot / "manifest.json").write_text(json.dumps({"source_root": str(self.root),
                                                                  "source_digest": "source", "files": {}}))
        self.inputs([{"script": "res://tests/test_a.gd"}, {"script": "res://tests/test_b.gd"}])
        pool = Pool(self.config)
        launched = []
        observations = {}

        def rpc(operation, **kwargs):
            if operation == "submit":
                launched.append(kwargs["request_id"])
                observations[kwargs["request_id"]] = checked_fixture(
                    self.root / "attempts" / kwargs["request_id"], script=kwargs["options"]["script"])
                return {"job": kwargs["request_id"]}
            if operation == "recover":
                return {"job": kwargs["request_id"]}
            if operation == "status":
                return {**observations[kwargs["job"]],
                        "payload": {"manifest": {"source_digest": "source"}}}
            raise AssertionError(operation)

        with patch("tools.testqueue.pool.verify", side_effect=verified_fixture), \
                patch("tools.testqueue.pool.plan", return_value={"selected": "windows"}), \
                patch.object(pool, "probe", return_value=[]), \
                patch("tools.testqueue.pool.rpc", side_effect=rpc):
            result = run_batch(pool, self.config, self.manifest, self.state, timeout=1, poll_interval=0)
            self.assertEqual(result["result"], "PASSED")
            self.assertEqual(len(launched), 2)
            self.assertEqual([row["collection"]["pool_job"] for row in result["jobs"]], launched)
            with patch("tools.testqueue.pool.rpc", side_effect=AssertionError("host offline")) as offline, \
                    patch.object(pool, "submit") as submit, patch.object(pool, "collect") as collect:
                resumed = run_batch(pool, self.config, self.manifest, self.state, timeout=1, poll_interval=0)
                self.assertEqual(resumed["result"], "PASSED")
                offline.assert_not_called()
                submit.assert_not_called()
                collect.assert_not_called()

            original_row = result["jobs"][0]
            log = Path(original_row["collection"]["log"])
            original_log = log.read_bytes()
            for damage in ("missing", "corrupt"):
                if damage == "missing":
                    log.unlink()
                else:
                    log.write_bytes(b"corrupt collected evidence")
                with patch("tools.testqueue.pool.rpc", side_effect=AssertionError("host offline")) as offline, \
                        patch.object(pool, "submit") as submit, patch.object(pool, "collect") as collect:
                    damaged = run_batch(pool, self.config, self.manifest, self.state, timeout=1, poll_interval=0)
                    row = damaged["jobs"][0]
                    self.assertEqual(damaged["result"], "INCOMPLETE")
                    self.assertEqual(row["phase"], "COLLECTION_BLOCKED")
                    self.assertEqual(row["collection"], original_row["collection"])
                    self.assertEqual(row["previous_results"][-1]["collection"], original_row["collection"])
                    offline.assert_not_called()
                    submit.assert_not_called()
                    collect.assert_not_called()
                if damage == "missing":
                    # Restoring retained bytes lets a later collection recheck
                    # the original authority and resume without a new submit.
                    log.write_bytes(original_log)
                    with patch.object(pool, "submit") as submit:
                        repaired = run_batch(pool, self.config, self.manifest, self.state, timeout=1, poll_interval=0)
                        self.assertEqual(repaired["result"], "PASSED")
                        submit.assert_not_called()
        self.assertEqual(len(launched), 2)
        history = json.loads((pool.root / "history.json").read_text())
        self.assertEqual(history["windows"]["res://tests/test_a.gd"]["samples"], [1.25])


if __name__ == "__main__":
    unittest.main()
