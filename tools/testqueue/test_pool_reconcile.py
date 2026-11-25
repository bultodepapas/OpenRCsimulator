"""Legacy receipts release a host only with nonexecution proof (or operator confirmation)."""
import json
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from tools.testqueue import pool as pool_module
from tools.testqueue.pool import Pool, RemoteRefusal


class PoolReconcileTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-reconcile-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        config = root / "config.json"
        config.write_text(json.dumps({"state_root": str(root / "pool"), "hosts": [
            {"id": "windows", "local": True},
            {"id": "mac", "ssh": "mac", "python": "python3", "root": "/r", "agent": "/a", "engine": "/e"}]}))
        self.pool = Pool(config)
        (self.pool.root / "jobs").mkdir(parents=True)

    def receipt(self, identifier, host, state="NOT_DISPATCHED", **extra):
        value = {"request_id": identifier, "host": host, "state": state, "created": 1.0, **extra}
        (self.pool.root / "jobs" / (identifier + ".json")).write_text(json.dumps(value))

    def stored(self, identifier):
        return json.loads((self.pool.root / "jobs" / (identifier + ".json")).read_text())

    def busy(self):
        return {item["id"]: item["busy"] for item in self.pool._reserve([{"id": "windows", "busy": False},
                                                                         {"id": "mac", "busy": False}])}

    def test_missing_receipt_is_actionable_and_cannot_dispatch(self):
        with patch.object(pool_module, "rpc") as rpc, patch.object(self.pool, "remote") as remote:
            for operation in (self.pool.status, self.pool.recover):
                status = operation("lost123")
                self.assertEqual((status["job"], status["state"], status["cleanup"], status["reason_code"]),
                                 ("lost123", "UNKNOWN", "UNCONFIRMED", "MISSING_RECEIPT"))
                self.assertIn("jobs/lost123.json", status["error"])
            rpc.assert_not_called()
            remote.assert_not_called()
        self.assertFalse((self.pool.root / "jobs/lost123.json").exists())

    def test_remote_probe_distinguishes_external_simulators_and_legacy_busy_hosts(self):
        host = self.pool.hosts[1]
        admission = {"busy": True, "quarantined": False, "enrolled": False}
        observation = {"host": {"system": "Darwin"}, "engine": {"available": True},
                       "capacity": {"free_bytes": 10**10, "free_memory_bytes": 10**9, "cpu_count": 8},
                       "admission": admission, "capabilities": ["headless"]}
        with patch.object(self.pool, "remote", return_value=observation):
            self.assertEqual(self.pool.probe_host(host)["busy_code"], "RUNNING_POOL_JOB")
            for code in ("EXTERNAL_SIMULATOR", "OCCUPANCY_UNKNOWN"):
                admission.update(busy_code=code, busy_reason="probe evidence")
                host_view = self.pool.probe_host(host)
                self.assertEqual(host_view["busy_code"], code)
                self.assertIn(code, host_view["busy_reason"])
            admission["quarantined"] = True
            self.assertEqual(self.pool.probe_host(host)["busy_code"], "QUARANTINED")

    def test_local_tombstone_releases_the_host_and_status_stays_final(self):
        self.receipt("local1", "windows", request={"request_id": "local1", "request_secret": "s"})
        self.assertTrue(self.busy()["windows"])
        with patch.object(pool_module, "rpc", return_value={"canceled": True}) as rpc:
            result = self.pool.reconcile("local1")
        rpc.assert_called_once_with("cancel_submission", request_id="local1", request_secret="s")
        self.assertEqual((result["state"], result["outcome"]), ("FINISHED", "NOT_DISPATCHED"))
        self.assertEqual(self.stored("local1")["state"], "CANCELED_BEFORE_DISPATCH")
        self.assertFalse(self.busy()["windows"])
        with patch.object(pool_module, "rpc", side_effect=AssertionError("no authority call")):
            self.assertEqual(self.pool.status("local1")["outcome"], "NOT_DISPATCHED")

    def test_local_request_that_was_accepted_is_never_released(self):
        self.receipt("local2", "windows", request={"request_id": "local2", "request_secret": "s"})
        with patch.object(pool_module, "rpc", return_value={"canceled": True, "job": "j1"}), \
                self.assertRaisesRegex(ValueError, "accepted"):
            self.pool.reconcile("local2")
        self.assertEqual(self.stored("local2")["state"], "SUBMISSION_UNCONFIRMED")  # still reserving
        self.receipt("local3", "windows")
        with self.assertRaisesRegex(ValueError, "no request credential"):
            self.pool.reconcile("local3")

    def test_remote_absence_needs_operator_confirmation_and_presence_is_refused(self):
        self.receipt("remote1", "mac")
        absent = RemoteRefusal("request not found", "NOT_FOUND")
        with patch.object(self.pool, "remote", side_effect=absent):
            with self.assertRaisesRegex(ValueError, "operator-confirm"):
                self.pool.reconcile("remote1")
            self.assertTrue(self.busy()["mac"])
            self.assertEqual(self.pool.reconcile("remote1", operator_confirm=True)["outcome"], "NOT_DISPATCHED")
        self.assertFalse(self.busy()["mac"])
        self.assertEqual(self.stored("remote1")["state"], "OPERATOR_RECONCILED_ABSENT")
        self.receipt("remote2", "mac")
        with patch.object(self.pool, "remote", return_value={"state": "RUNNING"}), \
                self.assertRaisesRegex(ValueError, "knows this request"):
            self.pool.reconcile("remote2", operator_confirm=True)
        with patch.object(self.pool, "remote", side_effect=RuntimeError("ssh: connection refused")), \
                self.assertRaisesRegex(ValueError, "absence was not observed"):
            self.pool.reconcile("remote2", operator_confirm=True)
        self.assertEqual(self.stored("remote2")["state"], "SUBMISSION_UNCONFIRMED")  # still reserving
        self.receipt("done1", "mac", state="SUBMITTED")
        with self.assertRaisesRegex(ValueError, "not reconcilable"):
            self.pool.reconcile("done1", operator_confirm=True)


class LocalRefusalFenceTests(PoolReconcileTests):
    """2026-11-25 audit: a refused local submit held the Windows host 23-61 h per incident."""

    REQUEST = {"request_id": "late1", "request_secret": "s"}

    def unconfirmed(self, identifier="late1", age=3600, **extra):
        self.receipt(identifier, "windows", state="SUBMISSION_UNCONFIRMED", created=time.time() - age,
                     request={**self.REQUEST, "request_id": identifier}, local_authority_root="C:/authority",
                     error="source must be an OpenRC checkout with the admitted adapter", **extra)

    def authority(self, recover=None, fenced=None):
        operations = []

        def call(operation, **payload):
            operations.append(operation)
            if operation == "recover":
                return recover
            if operation == "cancel_submission":
                return fenced if fenced is not None else {"canceled": True}
            raise AssertionError("unexpected authority call " + operation)
        return call, operations

    def test_recent_unconfirmed_local_submission_is_only_observed(self):
        self.unconfirmed(age=60)
        call, operations = self.authority()
        with patch.object(pool_module, "rpc", side_effect=call):
            status = self.pool.status("late1")
        self.assertEqual((status["state"], operations), ("SUBMISSION_UNCONFIRMED", ["recover"]))
        self.assertTrue(self.busy()["windows"])

    def test_overdue_unconfirmed_local_submission_is_fenced_and_releases_the_host(self):
        self.unconfirmed()
        call, operations = self.authority()
        with patch.object(pool_module, "rpc", side_effect=call):
            status = self.pool.status("late1")
        self.assertEqual(operations, ["recover", "recover", "cancel_submission"])
        self.assertEqual((status["state"], status["outcome"], status["reason_code"]),
                         ("FINISHED", "NOT_DISPATCHED", "LOCAL_SUBMIT_REFUSED"))
        self.assertIn("admitted adapter", status["error"])
        stored = self.stored("late1")
        self.assertEqual(stored["state"], "CANCELED_BEFORE_DISPATCH")
        self.assertTrue(stored["reconciliation"]["automatic"])
        self.assertFalse(self.busy()["windows"])
        with patch.object(pool_module, "rpc", side_effect=AssertionError("final status needs no authority call")):
            self.assertEqual(self.pool.status("late1")["outcome"], "NOT_DISPATCHED")

    def test_accepted_or_unobservable_requests_are_never_fenced(self):
        self.unconfirmed("acc1")
        call, operations = self.authority(fenced={"canceled": True, "job": "j1"})
        with patch.object(pool_module, "rpc", side_effect=call):
            self.pool._fence_local_refusal(self.stored("acc1"), self.pool.root / "jobs/acc1.json", {})
        self.assertEqual(operations, ["recover", "cancel_submission"])
        self.assertEqual(self.stored("acc1")["state"], "SUBMISSION_UNCONFIRMED")  # observed through status
        call, operations = self.authority(recover={"job": "j2", "handle": "j2:x"})
        with patch.object(pool_module, "rpc", side_effect=call):
            self.assertIsNone(self.pool._fence_local_refusal(self.stored("acc1"), self.pool.root / "jobs/acc1.json", {}))
        self.assertEqual(operations, ["recover"])
        with patch.object(pool_module, "rpc", side_effect=RuntimeError("testqueue worker unavailable")):
            self.assertIsNone(self.pool._fence_local_refusal(self.stored("acc1"), self.pool.root / "jobs/acc1.json", {}))
        self.assertEqual(self.stored("acc1")["state"], "SUBMISSION_UNCONFIRMED")
        self.assertTrue(self.busy()["windows"])

    def test_placement_sweep_fences_a_receipt_its_batch_stopped_observing(self):
        self.unconfirmed("late1")
        self.unconfirmed("late2", age=30)
        self.receipt("remote9", "mac", state="SUBMISSION_UNCONFIRMED", created=1.0)
        call, operations = self.authority()
        with patch.object(pool_module, "rpc", side_effect=call), patch.object(self.pool, "remote") as remote:
            self.pool._fence_stale_local_receipts()
            self.pool._fence_stale_local_receipts()  # rate limited: no second pass
        remote.assert_not_called()
        self.assertEqual(operations, ["recover", "recover", "cancel_submission"])
        self.assertEqual(self.stored("late1")["state"], "CANCELED_BEFORE_DISPATCH")
        self.assertEqual(self.stored("late2")["state"], "SUBMISSION_UNCONFIRMED")
        self.assertEqual(self.stored("remote9")["state"], "SUBMISSION_UNCONFIRMED")

    def test_recover_replay_refused_by_the_authority_is_fenced(self):
        self.unconfirmed("replay1", config_sha256=self.pool.config_digest)
        operations = []

        def call(operation, **payload):
            operations.append(operation)
            if operation == "submit":
                raise ValueError("source must be an OpenRC checkout with the admitted adapter")
            return {"canceled": True} if operation == "cancel_submission" else None
        with patch.object(pool_module, "rpc", side_effect=call):
            status = self.pool.recover("replay1")
        self.assertEqual(operations, ["recover", "submit", "recover", "cancel_submission"])
        self.assertEqual((status["outcome"], status["reason_code"]), ("NOT_DISPATCHED", "LOCAL_SUBMIT_REFUSED"))
        operations.clear()
        self.unconfirmed("replay2", config_sha256=self.pool.config_digest)

        def unavailable(operation, **payload):
            operations.append(operation)
            if operation == "submit":
                raise RuntimeError("testqueue worker unavailable")  # transport failure, not a refusal
            return None
        with patch.object(pool_module, "rpc", side_effect=unavailable):
            self.assertEqual(self.pool.recover("replay2")["state"], "UNKNOWN")
        self.assertEqual(operations, ["recover", "submit"])  # a transport failure proves nothing
        self.assertEqual(self.stored("replay2")["state"], "SUBMISSION_UNCONFIRMED")


class RemoteStorageGcTests(PoolReconcileTests):
    def finished(self, identifier, outcome, *, cleanup="CONFIRMED", evidence="COMPLETE", host="mac", **extra):
        self.receipt(identifier, host, state="SUBMITTED", request={"request_id": identifier, "preset": "checked"},
                     last_status={"state": "FINISHED", "outcome": outcome, "cleanup": cleanup, "evidence": evidence},
                     **extra)

    def test_gc_reclaims_collected_passes_and_finished_failures_only(self):
        self.finished("pass1", "PASSED")
        self.finished("fail1", "TEST_FAILED")
        self.finished("time1", "TIMED_OUT", evidence="INCOMPLETE")
        self.finished("unconf1", "TEST_FAILED", cleanup="UNCONFIRMED")
        self.finished("incomplete1", "PASSED", evidence="INCOMPLETE")
        self.finished("done1", "INFRA_FAILED", storage_gc={"state": "RECLAIMED"})
        self.finished("other1", "TEST_FAILED", host="windows")
        self.receipt("unknown1", "mac", state="SUBMISSION_UNCONFIRMED", request={"request_id": "unknown1"})
        self.assertEqual(sorted(self.pool.gc("mac")["request_ids"]), ["fail1", "pass1", "time1"])

        outcomes = {"pass1": "PASSED", "fail1": "TEST_FAILED", "time1": "INFRA_FAILED"}  # time1 mismatches
        calls = []

        def remote(host, action, payload, timeout=45):
            calls.append((action, payload.get("request_id"), timeout))
            if action == "gc":
                return {"logical_bytes_removed": 100, "retained_residue": {"files": 1}}
            return {"removed_files": 0, "logical_bytes_removed": 0}
        with patch.object(self.pool, "collect", side_effect=lambda identifier: {
                "pool_outcome": outcomes[identifier], "diagnostic_only": False}), \
                patch.object(self.pool, "remote", side_effect=remote):
            report = self.pool.gc("mac", execute=True)
        self.assertEqual((report["reclaimed"], report["logical_bytes_removed"]), (2, 200))
        self.assertEqual([item["request_id"] for item in report["skipped"]], ["time1"])
        self.assertEqual(sorted(call for call in calls if call[0] == "gc"),
                         [("gc", "fail1", 300), ("gc", "pass1", 300)])
        self.assertEqual(self.stored("fail1")["storage_gc"]["state"], "RECLAIMED")
        self.assertEqual(self.pool.gc("mac")["request_ids"], ["time1"])

    def test_sweep_budget_defers_remaining_jobs_and_failures_go_first(self):
        self.finished("apass", "PASSED")
        self.finished("zfail", "TEST_FAILED")
        self.assertEqual(self.pool.gc("mac")["request_ids"], ["zfail", "apass"])
        with patch.object(self.pool, "collect") as collect, \
                patch.object(self.pool, "remote", return_value={"removed_files": 0}) as remote:
            report = self.pool.gc("mac", execute=True, deadline=time.monotonic() - 1)
        collect.assert_not_called()
        self.assertEqual((report["deferred"], report["reclaimed"]), (2, 0))
        self.assertEqual([call.args[1] for call in remote.call_args_list], ["gc-incoming"])
        with patch.object(self.pool, "gc") as gc:
            self.assertEqual(self.pool.reclaim_for_space(
                {"candidates": [{"host": "mac", "reasons": ["INSUFFICIENT_DISK: 1 < 3 bytes"]}]}, budget_seconds=0.5), {})
        gc.assert_not_called()

    def test_disk_refusal_triggers_one_rate_limited_sweep_per_remote_host(self):
        decision = {"selected": None, "candidates": [
            {"host": "mac", "reasons": ["INSUFFICIENT_DISK: 1 < 3 bytes"]},
            {"host": "windows", "reasons": ["INSUFFICIENT_DISK: 1 < 3 bytes"]},
            {"host": "elsewhere", "reasons": ["INSUFFICIENT_DISK: 1 < 3 bytes"]},
            {"host": "mac2", "reasons": ["OFFLINE"]}]}
        with patch.object(self.pool, "gc", return_value={"candidates": 2, "reclaimed": 2,
                                                         "logical_bytes_removed": 9, "skipped": []}) as gc:
            self.assertEqual(list(self.pool.reclaim_for_space(decision)), ["mac"])
            self.assertEqual(self.pool.reclaim_for_space(decision), {})
        gc.assert_called_once()
        self.assertEqual((gc.call_args.args, gc.call_args.kwargs["execute"]), (("mac",), True))
        self.assertLessEqual(gc.call_args.kwargs["deadline"] - time.monotonic(), Pool.AUTO_GC_BUDGET_SECONDS)
        journal = json.loads((self.pool.root / "retention/auto-gc-mac.json").read_text())
        self.assertEqual((journal["state"], journal["reclaimed"], journal["logical_bytes_removed"]), ("DONE", 2, 9))
        journal["at"] -= Pool.AUTO_GC_INTERVAL_SECONDS + 1
        (self.pool.root / "retention/auto-gc-mac.json").write_text(json.dumps(journal))
        with patch.object(self.pool, "gc", side_effect=RuntimeError("ssh: host unreachable")):
            self.assertEqual(self.pool.reclaim_for_space(decision)["mac"]["state"], "FAILED")
        self.assertEqual(json.loads((self.pool.root / "retention/auto-gc-mac.json").read_text())["state"], "FAILED")
        self.assertEqual(self.pool.reclaim_for_space({"selected": "mac"}), {})
        self.assertEqual(self.pool.reclaim_for_space(None), {})


class PoolCircuitTests(PoolReconcileTests):
    def finished(self, identifier, host, outcome, created, source="src", **status):
        self.receipt(identifier, host, state="SUBMITTED", created=time.time() - 100 + created, source_digest=source,
                     last_status={"state": "FINISHED", "outcome": outcome, **status})

    def circuit(self, source="src"):
        return {item["id"]: item.get("busy_reason") for item in self.pool._circuit(
            [{"id": "windows", "busy": False}, {"id": "mac", "busy": False}], source)}

    def test_consecutive_infra_failures_open_only_that_host_and_source(self):
        self.finished("a1", "mac", "PASSED", 1)
        self.finished("a2", "mac", "INFRA_FAILED", 2)
        self.assertIsNone(self.circuit()["mac"])
        self.finished("a3", "mac", "INFRA_FAILED", 3)
        self.finished("w1", "windows", "INFRA_FAILED", 3)
        reasons = self.circuit()
        self.assertIn("CIRCUIT_OPEN", reasons["mac"])
        self.assertIsNone(reasons["windows"])
        self.assertIsNone(self.circuit(source="other")["mac"])
        self.finished("a4", "mac", "TEST_FAILED", 4)  # a real test result closes it
        self.assertIsNone(self.circuit()["mac"])

    def test_host_transient_refusals_do_not_open_the_circuit(self):
        """TQ-05-F0.4: the host's own state says nothing about the source."""
        self.finished("t1", "mac", "INFRA_FAILED", 1, error="Refused: external Godot process detected; it was not touched")
        self.finished("t2", "mac", "INFRA_FAILED", 2, error="Refused: insufficient disk for archive and reserve")
        self.assertIsNone(self.circuit()["mac"])
        self.finished("t3", "mac", "INFRA_FAILED", 3, reason_code="EXTERNAL_SIMULATOR")
        self.finished("t4", "mac", "INFRA_FAILED", 4, reason_code="EXTERNAL_SIMULATOR")
        self.assertIsNone(self.circuit()["mac"])

    def test_deferred_unpinned_trial_rechecks_its_bound_host_before_retry(self):
        snapshot = self.pool.root.resolve()
        inputs = {"snapshot": str(snapshot), "script": "script", "platform": "any", "require": [],
                  "timeout": 90, "host": None, "settings": {}}
        self.receipt("oldtrial", "mac", state="TRANSFER_DEFERRED", source_digest="src", inputs=inputs,
                     config_sha256=self.pool.config_digest, circuit_trial=True)
        self.receipt("newtrial", "mac", state="SUBMITTED", source_digest="src", circuit_trial=True)
        manifest = {"source_digest": "src", "source_root": str(snapshot)}
        def choose(job, hosts):
            self.assertEqual([h["id"] for h in hosts], ["mac"])
            self.assertIn("newtrial", hosts[0]["busy_reason"])
            return {"selected": None}
        with patch.object(self.pool, "_preflight", return_value=(manifest, {}, {})), \
                patch.object(self.pool, "probe", return_value=[{"id": h, "busy": False} for h in ("windows", "mac")]), \
                patch.object(pool_module, "plan", side_effect=choose), patch.object(self.pool, "remote") as remote:
            result = self.pool.submit(snapshot, "script", request_id="oldtrial")
            self.assertEqual(result["state"], "WAITING")
            self.assertEqual(result["placement_job"], {})
            self.assertEqual(result["placement_host"], "mac")
            self.assertEqual(self.stored("oldtrial")["state"], "TRANSFER_DEFERRED")
            remote.assert_not_called()

    def test_open_circuit_half_opens_after_the_retry_interval(self):
        self.finished("o1", "mac", "INFRA_FAILED", 1, finished_at=time.time() - 99)
        self.finished("o2", "mac", "INFRA_FAILED", 2, finished_at=time.time() - 98)
        self.assertIn("CIRCUIT_OPEN", self.circuit()["mac"])
        with patch.object(self.pool, "CIRCUIT_RETRY_SECONDS", 50):
            self.assertIsNone(self.circuit()["mac"])  # newest failure is ~98 s old: one more attempt may run

    def test_long_attempt_opens_circuit_when_its_failure_is_observed(self):
        now = time.time()
        for host, stamp in (("windows", "finished"), ("mac", "finished_at")):
            self.finished(host + "1", host, "INFRA_FAILED", -1000, **{stamp: now - 700})
            self.finished(host + "2", host, "PASSED", -200, **{stamp: now - 800})
            self.finished(host + "3", host, "INFRA_FAILED", -2000, **{stamp: now - 1})
            self.assertIn("CIRCUIT_OPEN", self.circuit()[host])

    def test_legacy_receipt_age_uses_file_observation_and_survives_repeated_status(self):
        observed = time.time() - 200
        for job in ("old1", "old2"):
            self.receipt(job, "windows", state="SUBMITTED", source_digest="src",
                         request={"request_id": job, "request_secret": "s"},
                         last_status={"state": "FINISHED", "outcome": "INFRA_FAILED"})
            os.utime(self.pool.root / "jobs" / (job + ".json"), (observed, observed))
        completed = {"state": "FINISHED", "outcome": "INFRA_FAILED", "payload": {"manifest": {"source_digest": "src"}}}
        receipt_time = (self.pool.root / "jobs/old2.json").stat().st_mtime
        with patch.object(pool_module, "rpc", side_effect=[{"job": "old2"}, completed, OSError("offline"),
                                                          {"job": "old2"}, completed]):
            self.pool.status("old2")
            self.assertEqual(self.pool.status("old2")["state"], "UNKNOWN")
            self.pool.status("old2")
        self.assertEqual(self.stored("old2")["terminal_observation"]["at"], receipt_time)
        self.assertIn("CIRCUIT_OPEN", self.circuit()["windows"])
        with patch.object(self.pool, "CIRCUIT_RETRY_SECONDS", 100):
            self.assertIsNone(self.circuit()["windows"])

    def test_unreachable_terminal_trial_retains_cleanup_and_cause_without_live_success_or_replay(self):
        for outcome, detail, open_again in (("PASSED", {}, False), ("INFRA_FAILED", {}, True),
                                           ("INFRA_FAILED", {"reason_code": "EXTERNAL_SIMULATOR"}, False)):
            with self.subTest(outcome=outcome, detail=detail):
                for job in ("old1", "old2"):
                    self.finished(job, "windows", "INFRA_FAILED", -1000, finished=time.time() - 700)
                self.receipt("trial", "windows", state="SUBMITTED", request={"request_id": "trial", "request_secret": "s"},
                             source_digest="src", circuit_trial=True)
                result = {"state": "FINISHED", "outcome": outcome, "cleanup": "CONFIRMED",
                          "payload": {"manifest": {"source_digest": "src"}}, **detail}
                with patch.object(pool_module, "rpc", side_effect=[{"job": "trial"}, result]) as rpc:
                    self.assertEqual(self.pool.status("trial")["outcome"], outcome)
                with patch.object(pool_module, "rpc", side_effect=OSError("offline")):
                    self.assertEqual(self.pool.status("trial")["state"], "UNKNOWN")
                # A missing receipt at the authority used to cause a replay via recover.
                with patch.object(pool_module, "rpc", return_value=None) as rpc:
                    self.assertEqual(self.pool.recover("trial")["state"], "SUBMISSION_UNCONFIRMED")
                    rpc.assert_called_once_with("recover", request_id="trial", request_secret="s")
                self.assertEqual(self.stored("trial")["last_status"]["state"], "SUBMISSION_UNCONFIRMED")
                self.assertFalse(self.busy()["windows"])
                self.assertEqual(bool(self.circuit()["windows"]), open_again)

    def test_verified_legacy_terminal_observation_survives_earliest_failed_poll(self):
        old = {"state": "FINISHED", "outcome": "PASSED", "cleanup": "CONFIRMED", "request_id": "trial",
               "payload": {"manifest": {"source_digest": "src"}}}
        for source in ("src", "wrong"):
            with self.subTest(source=source):
                self.receipt("trial", "windows", state="SUBMITTED", source_digest=source, circuit_trial=True,
                             request={"request_id": "trial", "request_secret": "s"}, last_status=old)
                with patch.object(pool_module, "rpc", side_effect=OSError("offline")):
                    self.assertEqual(self.pool.status("trial")["state"], "UNKNOWN")
                self.assertEqual(self.busy()["windows"], source != "src")

    def test_concurrent_half_open_submissions_share_one_trial_until_its_terminal_observation(self):
        for job in ("failed1", "failed2"):
            self.finished(job, "windows", "INFRA_FAILED", -1000, finished=time.time() - 900)
        barrier = threading.Barrier(2, timeout=5)
        def idle():
            return [{"id": "windows", "busy": False}]
        def probe():
            barrier.wait()
            return idle()
        def choose(job, hosts):
            return {"selected": next((host["id"] for host in hosts if not host["busy"]), None)}
        def submit(identifier):
            return self.pool.submit(self.pool.root, "script", request_id=identifier)
        manifest = {"source_digest": "src", "source_root": str(self.pool.root)}
        with patch.object(self.pool, "_preflight", return_value=(manifest, {}, {})), \
                patch.object(pool_module, "plan", side_effect=choose), \
                patch.object(pool_module, "rpc", return_value={"job": "accepted"}) as rpc:
            with patch.object(self.pool, "probe", side_effect=probe), ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(submit, ["one", "two"]))
            self.assertCountEqual([r["state"] for r in results], ["SUBMITTED", "WAITING"])
            trial = next(r["job"] for r in results if r["state"] == "SUBMITTED")
            self.assertTrue(self.stored(trial)["circuit_trial"])
            # The probe can look idle again after acceptance, before the coordinator sees a verdict.
            with patch.object(self.pool, "probe", side_effect=idle):
                self.assertEqual(submit("later")["state"], "WAITING")
            rpc.assert_called_once()
            with patch.object(pool_module, "rpc", side_effect=OSError("lost reply")):
                self.assertEqual(self.pool.status(trial)["state"], "UNKNOWN")
            self.assertIn(trial, self.circuit()["windows"])
            passed = {"state": "FINISHED", "outcome": "PASSED", "payload": {"manifest": {"source_digest": "src"}}}
            with patch.object(pool_module, "rpc", side_effect=[{"job": "accepted"}, passed]):
                self.assertEqual(self.pool.status(trial)["outcome"], "PASSED")
            self.assertIsNone(self.circuit()["windows"])


if __name__ == "__main__":
    unittest.main()
