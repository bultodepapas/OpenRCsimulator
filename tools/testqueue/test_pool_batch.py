"""Crash recovery, independent execution and evidence boundaries of pool batches."""
import hashlib
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from tools.testqueue.test_pool import verified_fixture
from tools.testqueue.test_collection import checked_fixture

from tools.testqueue.common import Singleton, write_json
from tools.testqueue.collection import FORMAT as COLLECTION_FORMAT
from tools.testqueue.pool import Pool
from tools.testqueue.pool_batch import _host_lanes, run_batch


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
               expected_manifest_sha256, before_dispatch, rendering_driver=None):
        saved = json.loads(self.state_path.read_text())
        assert request_id in [row["request_id"] for row in saved["jobs"]]
        assert all(row.get("request_id") for row in saved["jobs"])
        self.submit_calls.append((script, request_id))
        if script in self.wait_once:
            self.wait_once.remove(script)
            return {"state": "WAITING", "decision": self.wait_decisions.get(script, {"selected": None})}
        # The real pool binds the input and request ID to one durable receipt.
        before_dispatch()
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
        # The narrower row can proceed on the next pass during the first row's backoff.
        self.assertEqual(calls[0][0], first)
        self.assertEqual([call for call in calls if call[0] == first], [calls[0]] * 2)
        self.assertEqual(len([call for call in calls if call[0] == second]), 1)
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
        scripts = [call[0] for call in self.pool.submit_calls]
        self.assertEqual(scripts[:3], [a, c, d])
        self.assertCountEqual(scripts[3:], [b, a])
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

    def test_refusal_backoff_survives_restart_and_preserves_original_id_and_constraint(self):
        first = "res://tests/test_a.gd"
        self.inputs([{"script": first, "platform": "linux", "host": "linux"}])
        delay = 30
        with patch("tools.testqueue.pool_batch.RETRY_INITIAL_SECONDS", delay):
            for count in (1, 2):
                self.pool.wait_once.add(first)
                self.pool.wait_decisions[first] = {"selected": None, "candidates": [
                    {"host": "linux", "eligible": False, "reasons": [f"INSUFFICIENT_DISK: {count} < 3 bytes"]}]}
                with patch("tools.testqueue.pool_batch.time.sleep", side_effect=SystemExit), self.assertRaises(SystemExit):
                    self.run_case()
                state = json.loads(self.state.read_text())
                row = state["jobs"][0]
                self.assertEqual(row["phase"], "WAITING")
                self.assertEqual(row["admission_wait"]["consecutive"], count)
                stamp = row["admission_wait"]["last_observed_at"]
                self.assertAlmostEqual(row["retry_after"] - stamp, delay)
                if count == 1:
                    identifier, first_stamp = row["request_id"], stamp
                self.assertEqual(row["admission_wait"]["first_observed_at"], first_stamp)
                with patch("tools.testqueue.pool_batch.time.sleep", side_effect=SystemExit), self.assertRaises(SystemExit):
                    self.run_case()
                self.assertEqual(len(self.pool.submit_calls), count)
                row["retry_after"] = 0
                self.state.write_text(json.dumps(state))
            result = self.run_case()
        self.assertEqual(result["result"], "PASSED")
        self.assertEqual(self.pool.submit_calls, [(first, identifier)] * 3)
        # TQ-07-D7: the reason for the wait outlives the placement.
        history = json.loads(self.state.read_text())["jobs"][0]["wait_history"]
        self.assertEqual([(entry["causes"], entry["count"]) for entry in history],
                         [({"linux": ["INSUFFICIENT_DISK"]}, 2)])
        self.assertEqual(self.pool.submissions, {identifier: first})

    def test_slow_placement_cannot_starve_another_host_across_observation_windows(self):
        a, b = "res://tests/test_a.gd", "res://tests/test_b.gd"
        self.inputs([{"script": a}, {"script": b, "platform": "windows"}])
        clock = [100.0]
        submit = self.pool.submit

        def slow(*args, **kwargs):
            clock[0] += 5
            return submit(*args, **kwargs)

        with patch("tools.testqueue.pool_batch.time.monotonic", side_effect=lambda: clock[0]), \
                patch("tools.testqueue.pool_batch.time.time", side_effect=lambda: clock[0]), \
                patch.object(self.pool, "submit", side_effect=slow):
            self.pool.wait_once.add(a)
            run_batch(self.pool, self.config, self.manifest, self.state, timeout=2)
            clock[0] += 10  # Even with the first row eligible to probe again, host B gets its turn.
            self.pool.wait_once.add(a)
            run_batch(self.pool, self.config, self.manifest, self.state, timeout=2)
        self.assertEqual([script for script, _ in self.pool.submit_calls], [a, b])

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

    def test_host_collects_while_another_transfer_is_blocked(self):
        self.cross_host_transfer(pinned=True)

    def test_unpinned_distinct_platforms_advance_independently(self):
        self.cross_host_transfer(pinned=False)

    def test_overlapping_affinities_stay_in_one_lane(self):
        rows = [{"input": {"host": "windows-1", "platform": "windows"}},
                {"input": {"host": None, "platform": "windows"}}]
        self.assertEqual(_host_lanes(rows), [rows])
        rows.append({"input": {"host": "linux-1", "platform": "linux"}})
        self.assertEqual(_host_lanes(rows), [rows[:2], rows[2:]])
        rows[0]["input"]["platform"] = "any"
        self.assertEqual(_host_lanes(rows), [rows])

    def cross_host_transfer(self, *, pinned):
        from tools.testqueue.pool import request_digest
        hosts = [{"id": name, "ssh": name, "agent": "/agent", "engine": "/engine", "engine_sha256": "a"*64}
                 for name in ("slow", "fast")]
        self.config.write_text(json.dumps({"state_root": str(self.root / "pool"), "hosts": hosts}))
        platform_hosts = {"darwin": "slow", "linux": "fast"}
        self.inputs([{"host": host if pinned else None, "platform": platform, "script": "res://tests/test_a.gd"}
                     for platform, host in platform_hosts.items()])
        pool = Pool(self.config)
        entered, finished = threading.Event(), threading.Event()
        visible = []
        real_clock, elapsed = time.monotonic, [0.0]
        refused = []

        def plan(job, observations):
            host = platform_hosts[job["platform"]]
            self.assertIn(host, [item["id"] for item in observations])
            if host == "slow" and not refused:
                refused.append(host)
                return {"selected": None, "candidates": [{"host": host, "eligible": False,
                                                         "reasons": ["INSUFFICIENT_DISK: 1 < 3 bytes"]}]}
            return {"selected": host}

        def transfer(host, archive, archive_digest, identifier):
            if host["id"] == "slow":
                entered.set()
                if not finished.wait(10):
                    raise AssertionError("fast host did not finish while slow transfer was held")
                elapsed[0] += 20  # Exhaust the observation budget while the owner still holds the call.
                visible.extend(json.loads(self.state.read_text())["jobs"])
                with self.assertRaises(OSError):
                    run_batch(pool, self.config, self.manifest, self.state, timeout=.1)
            elif not entered.wait(10):
                raise AssertionError("slow host failed to enter its transfer")
            return "/remote/archive.tar"

        def publish(path, value):
            write_json(path, value)
            if value["jobs"][1]["phase"] == "DONE":
                finished.set()

        def accepted(host, action, request):
            return {"state": "STARTING", "request_id": request["request_id"], "payload_sha256": request_digest(request)}

        def collect(identifier):
            return {"pool_job": identifier, "pool_outcome": "PASSED", "collection_format": COLLECTION_FORMAT,
                    "diagnostic_only": False}

        def preflight(snapshot, script, platform, *args):
            return {"source_digest": "src"}, {}, {"platform": platform}
        def probe(host=None):
            return [{"id": item["id"], "busy": False} for item in hosts if host is None or item["id"] == host]

        with (patch.object(pool, "_preflight", side_effect=preflight),
              patch.object(pool, "probe", side_effect=probe),
              patch("tools.testqueue.pool.plan", side_effect=plan),
              patch("tools.testqueue.pool_batch.time.monotonic", side_effect=lambda: real_clock() + elapsed[0]),
              patch.object(pool, "_prepare_archive", return_value=self.manifest),
              patch("tools.testqueue.pool.verify_archive"),
              patch.object(pool, "_transfer_archive", side_effect=transfer),
              patch.object(pool, "remote", side_effect=accepted) as remote,
              patch.object(pool, "status", return_value=PASS),
              patch.object(pool, "collect", side_effect=collect),
              patch.object(pool, "verify_collection", side_effect=lambda identifier, result: result),
              patch("tools.testqueue.pool_batch.write_json", side_effect=publish)):
            result = run_batch(pool, self.config, self.manifest, self.state, timeout=15, poll_interval=.01)
            self.assertEqual(result["result"], "INCOMPLETE")
            with patch.object(pool, "submit", side_effect=AssertionError("duplicate submission")) as submit:
                result = run_batch(pool, self.config, self.manifest, self.state, timeout=15, poll_interval=.01)
            submit.assert_not_called()
        self.assertEqual(result["result"], "PASSED")
        self.assertEqual([r["phase"] for r in visible], ["SUBMITTING", "DONE"])
        self.assertEqual(visible[0]["status"], {"state": "SUBMITTING", "stage": "placement"})
        self.assertIn("placement_started_at", visible[0])
        self.assertNotIn("retry_after", visible[0])
        self.assertNotIn("admission_wait", visible[0])
        self.assertEqual([r["request_id"] for r in visible], [r["request_id"] for r in result["jobs"]])
        self.assertEqual([call.args[1] for call in remote.call_args_list].count("run"), 2)
        # The disk refusal on the slow host triggered one storage sweep there (no candidates).
        self.assertEqual([(call.args[0]["id"], call.args[1]) for call in remote.call_args_list if call.args[1] != "run"],
                         [("slow", "gc-incoming")])
        for row in result["jobs"]:
            self.assertLessEqual(row["first_placement_at"], row["last_placement_at"])
            self.assertEqual(set(row["coordinator_seconds"]), {"placement", "collection"})

    def test_failed_parallel_publication_fences_other_dispatch_callbacks(self):
        self.inputs([{"host": host, "script": "res://tests/test_a.gd"} for host in ("one", "two")])
        failed = threading.Event()

        def publish(path, value):
            if value["jobs"][0]["phase"] == "SUBMITTING":
                failed.set()
                raise OSError("injected journal write failure")
            write_json(path, value)

        original = self.pool.submit
        def submit(*args, **kwargs):
            if kwargs["host_id"] == "two":
                self.assertTrue(failed.wait(10))
            return original(*args, **kwargs)

        with patch("tools.testqueue.pool_batch.write_json", side_effect=publish), patch.object(self.pool, "submit", submit):
            with self.assertRaisesRegex(RuntimeError, "publication stopped: injected journal write failure"):
                self.run_case()
        self.assertEqual(self.pool.submissions, {})
        self.assertEqual([r["phase"] for r in json.loads(self.state.read_text())["jobs"]], ["WAITING", "WAITING"])

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
