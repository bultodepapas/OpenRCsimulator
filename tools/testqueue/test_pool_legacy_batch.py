"""Legacy false-terminal batch receipts must be reobserved without relaunch."""

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.testqueue import pool_mcp
from tools.testqueue.common import write_json
from tools.testqueue.collection import FORMAT as COLLECTION_FORMAT
from tools.testqueue.pool import Pool
from tools.testqueue.pool_batch import run_batch
from tools.testqueue.test_collection import checked_fixture


def file_digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class LegacyBatchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-legacy-batch-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.config = self.root / "config.json"
        write_json(self.config, {"state_root": str(self.root / "pool"),
                                 "hosts": [{"id": "local", "local": True}]})
        self.pool = Pool(self.config)
        self.snapshot = self.root / "snapshot"
        write_json(self.snapshot / "manifest.json", {"source_digest": "a" * 64})
        self.manifest = self.root / "manifest.json"
        self.state_path = self.root / "batch.json"
        self.identifier = "legacyid"
        self.source_digest = "a" * 64
        self.false_status = {"state": "FINISHED", "outcome": "INFRA_FAILED", "cleanup": "CONFIRMED",
                             "error": "legacy false nonexecution"}
        self.old_collection = {"pool_job": self.identifier, "pool_outcome": "INFRA_FAILED",
                               "pool_status": str(self.root / "prior-status.json"),
                               "pool_report": str(self.root / "prior-report.json")}
        (self.root / "prior-status.json").write_text("original status evidence", encoding="utf-8")
        (self.root / "prior-report.json").write_text("original report evidence", encoding="utf-8")
        self.finished = checked_fixture(self.root / "attempt", outcome="TEST_FAILED")
        self.log = Path(self.finished["runner_verdict"]["checked"]["log"])
        self.observed_state = "RUNNING"
        self.calls = []

    def input_row(self, script):
        return {"script": script, "platform": "any", "require": [], "timeout": 90, "host": None}

    def write_batch(self, rows, *, result="FAILED"):
        write_json(self.manifest, {"snapshot": str(self.snapshot),
                                   "jobs": [{"script": row["input"]["script"]} for row in rows]})
        state = {"version": 1, "config_sha256": file_digest(self.config),
                 "manifest_sha256": file_digest(self.manifest), "snapshot": str(self.snapshot),
                 "snapshot_manifest_sha256": file_digest(self.snapshot / "manifest.json"),
                 "jobs": rows, "result": result}
        write_json(self.state_path, state)
        return state

    def row(self, identifier, phase, status, collection=None, script="res://tests/test_sample.gd"):
        value = {"request_id": identifier, "input": self.input_row(script), "phase": phase, "status": status}
        if collection is not None:
            value["collection"] = collection
        return value

    def write_receipt(self, identifier, *, legacy):
        receipt = {"request_id": identifier, "host": "local", "state": "NOT_DISPATCHED" if legacy else "SUBMITTED",
                   "request": {"request_id": identifier, "request_secret": "s" * 64},
                   "options": {"script": "res://tests/test_sample.gd"}, "source_digest": self.source_digest}
        if legacy:
            receipt["last_status"] = self.false_status
        else:
            receipt["config_sha256"] = self.pool.config_digest
            receipt["local_authority_root"] = str(self.root / "authority")
        write_json(self.pool.root / "jobs" / (identifier + ".json"), receipt)

    def rpc(self, operation, **payload):
        self.calls.append((operation, payload))
        if operation == "recover":
            self.assertIn(payload["request_id"], {self.identifier, "liveid"})
            return {"job": "authority-" + payload["request_id"]}
        if operation == "status":
            self.assertIn(payload["job"], {"authority-" + self.identifier, "authority-liveid"})
            result = {"state": self.observed_state, "payload": {"manifest": {"source_digest": self.source_digest}}}
            if self.observed_state == "FINISHED":
                result.update(self.finished)
            return result
        self.fail(f"unexpected RPC: {operation}")

    def run_batch(self):
        return run_batch(self.pool, self.config, self.manifest, self.state_path, timeout=0.2, poll_interval=0.01)

    def test_legacy_terminal_and_collection_phases_reobserve_and_preserve_failure(self):
        for phase in ("DONE", "COLLECTING", "COLLECTION_BLOCKED"):
            with self.subTest(phase=phase):
                self.calls.clear()
                self.observed_state = "RUNNING"
                self.write_receipt(self.identifier, legacy=True)
                row = self.row(self.identifier, phase, self.false_status, self.old_collection)
                self.write_batch([row])
                previous_destination = self.pool.root / "results" / self.identifier
                previous_destination.mkdir(parents=True, exist_ok=True)
                old_status_file = previous_destination / "pool-status.json"
                old_status_file.write_text("original false-terminal artifact", encoding="utf-8")

                with patch("tools.testqueue.pool.rpc", side_effect=self.rpc), \
                     patch.object(self.pool, "submit") as submit, \
                     patch.object(self.pool, "collect", wraps=self.pool.collect) as collect:
                    first = self.run_batch()
                    current = first["jobs"][0]
                    self.assertEqual(first["result"], "INCOMPLETE")
                    self.assertEqual(current["request_id"], self.identifier)
                    self.assertEqual(current["phase"], "TRACKING")
                    self.assertEqual(current["status"]["state"], "RUNNING")
                    self.assertEqual(current["status"]["pool_recovery_version"], 1)
                    self.assertEqual(current["previous_results"][0]["status"], self.false_status)
                    self.assertEqual(current["previous_results"][0]["collection"], self.old_collection)
                    collect.assert_not_called()
                    submit.assert_not_called()
                    self.assertTrue(any(operation == "recover" and args["request_id"] == self.identifier
                                        for operation, args in self.calls))

                    self.observed_state = "FINISHED"
                    second = self.run_batch()
                    current = second["jobs"][0]
                    self.assertEqual(second["result"], "FAILED")
                    self.assertEqual(current["phase"], "DONE")
                    self.assertEqual(current["status"]["outcome"], "TEST_FAILED")
                    self.assertEqual(current["status"]["pool_recovery_version"], 1)
                    self.assertEqual(current["collection"]["pool_job"], self.identifier)
                    self.assertEqual(current["collection"]["pool_outcome"], "TEST_FAILED")
                    self.assertEqual(len(current["previous_results"]), 1)
                    generation = Path(current["collection"]["report"]).parent
                    self.assertEqual(generation.parent, previous_destination / "recovery-1")
                    self.assertTrue((generation / "pool-status.json").is_file())
                    self.assertEqual(Path(current["collection"]["log"]).read_text(encoding="utf-8"),
                                     self.log.read_text(encoding="utf-8"))
                    collect.assert_called_once_with(self.identifier)

                    third = self.run_batch()
                    self.assertEqual(third["result"], "FAILED")
                    self.assertEqual(len(third["jobs"][0]["previous_results"]), 1)
                    self.assertEqual(collect.call_count, 1)
                    submit.assert_not_called()

                self.assertEqual(old_status_file.read_text(encoding="utf-8"), "original false-terminal artifact")
                self.assertEqual((self.root / "prior-status.json").read_text(encoding="utf-8"), "original status evidence")
                self.assertEqual((self.root / "prior-report.json").read_text(encoding="utf-8"), "original report evidence")

    def test_missing_terminal_receipt_keeps_evidence_and_observes_independent_live_row(self):
        missing = self.row(self.identifier, "DONE", self.false_status, self.old_collection)
        live = self.row("liveid", "TRACKING", {"state": "RUNNING"}, script="res://tests/test_other.gd")
        self.write_receipt("liveid", legacy=False)
        original = self.write_batch([missing, live], result="INCOMPLETE")
        with patch("tools.testqueue.pool.rpc", side_effect=self.rpc), patch.object(self.pool, "submit") as submit:
            result = self.run_batch()
        submit.assert_not_called()
        self.assertEqual(result["result"], "INCOMPLETE")
        self.assertEqual(result["jobs"][0]["phase"], "BLOCKED")
        self.assertEqual(result["jobs"][0]["status"]["state"], "UNKNOWN")
        self.assertEqual(result["jobs"][0]["previous_results"][0]["status"], original["jobs"][0]["status"])
        self.assertEqual(result["jobs"][0]["previous_results"][0]["collection"], self.old_collection)
        self.assertEqual(result["jobs"][1]["request_id"], "liveid")
        self.assertEqual(result["jobs"][1]["status"]["state"], "RUNNING")
        self.assertTrue(any(operation == "recover" and args["request_id"] == "liveid"
                            for operation, args in self.calls))

    def write_mcp_cache(self, rows, *, result="FAILED"):
        batch = self.write_batch(rows, result=result)
        directory = self.pool.root / "mcp" / "cached"
        write_json(directory / "request.json", {"request_id": "cached", "source": str(self.root),
                                                 "config_sha256": self.pool.config_digest})
        write_json(directory / "supervisor.json", {"state": "FINISHED", "result": result})
        write_json(directory / "batch.json", batch)
        return directory

    def test_mcp_legacy_failed_cache_requires_recovery_without_network(self):
        self.write_receipt(self.identifier, legacy=True)
        row = self.row(self.identifier, "DONE", self.false_status, self.old_collection)
        directory = self.write_mcp_cache([row])
        original = (directory / "batch.json").read_bytes()
        with patch("tools.testqueue.pool.rpc") as rpc, patch.object(Pool, "remote") as remote, \
             patch.object(pool_mcp, "_start") as start:
            result = pool_mcp.status("cached", "full", config=self.config)
            self.assertEqual(result["result"], "INCOMPLETE")
            self.assertTrue(result["recovery_required"])
            self.assertEqual(result["jobs"][0]["phase"], "BLOCKED")
            self.assertEqual(result["jobs"][0]["status"]["state"], "UNKNOWN")
            self.assertEqual(result["jobs"][0]["previous_status"], self.false_status)
            recovered = pool_mcp.recover("cached", config=self.config)
            self.assertEqual(recovered["result"], "INCOMPLETE")
            start.assert_called_once_with(directory)
            rpc.assert_not_called()
            remote.assert_not_called()
        self.assertEqual((directory / "batch.json").read_bytes(), original)

    def test_mcp_missing_receipt_preserves_cached_independent_row(self):
        missing = self.row(self.identifier, "DONE", self.false_status, self.old_collection)
        live = self.row("liveid", "TRACKING", {"state": "RUNNING"}, script="res://tests/test_other.gd")
        self.write_receipt("liveid", legacy=False)
        directory = self.write_mcp_cache([missing, live], result="INCOMPLETE")
        original = (directory / "batch.json").read_bytes()
        with patch("tools.testqueue.pool.rpc") as rpc, patch.object(Pool, "remote") as remote:
            result = pool_mcp.status("cached", "full", config=self.config)
        rpc.assert_not_called()
        remote.assert_not_called()
        self.assertEqual(result["result"], "INCOMPLETE")
        self.assertTrue(result["recovery_required"])
        self.assertEqual(result["jobs"][0]["status"]["state"], "UNKNOWN")
        self.assertEqual(result["jobs"][1]["status"]["state"], "RUNNING")
        self.assertEqual((directory / "batch.json").read_bytes(), original)

    def test_old_passing_collection_requires_observation_and_verified_recollection(self):
        self.write_receipt(self.identifier, legacy=False)
        old_status = {"state": "FINISHED", "outcome": "PASSED", "cleanup": "CONFIRMED", "evidence": "COMPLETE"}
        old_collection = {"pool_job": self.identifier, "pool_outcome": "PASSED",
                          "report": str(self.root / "prior-report.json")}
        row = self.row(self.identifier, "DONE", old_status, old_collection)
        directory = self.write_mcp_cache([row], result="PASSED")
        original = (directory / "batch.json").read_bytes()
        with patch("tools.testqueue.pool.rpc") as rpc, patch.object(Pool, "remote") as remote, \
                patch.object(pool_mcp, "_start") as start:
            cached = pool_mcp.status("cached", "full", config=self.config)
            self.assertEqual(cached["result"], "INCOMPLETE")
            self.assertTrue(cached["recovery_required"])
            self.assertEqual(cached["jobs"][0]["status"]["state"], "UNKNOWN")
            self.assertEqual(cached["jobs"][0]["previous_status"], old_status)
            self.assertEqual(pool_mcp.recover("cached", config=self.config)["result"], "INCOMPLETE")
            start.assert_called_once_with(directory)
            rpc.assert_not_called()
            remote.assert_not_called()
        self.assertEqual((directory / "batch.json").read_bytes(), original)

        self.finished = checked_fixture(self.root / "passing-attempt")
        self.observed_state = "FINISHED"
        with patch("tools.testqueue.pool.rpc", side_effect=self.rpc), \
                patch.object(self.pool, "submit") as submit, \
                patch.object(self.pool, "collect", wraps=self.pool.collect) as collect:
            result = self.run_batch()
        self.assertEqual(result["result"], "PASSED")
        current = result["jobs"][0]
        self.assertEqual(current["request_id"], self.identifier)
        self.assertEqual(current["collection"]["collection_format"], COLLECTION_FORMAT)
        self.assertIs(current["collection"]["diagnostic_only"], False)
        self.assertEqual(current["previous_results"][0]["status"], old_status)
        self.assertEqual(current["previous_results"][0]["collection"], old_collection)
        submit.assert_not_called()
        collect.assert_called_once_with(self.identifier)
        self.assertEqual((self.root / "prior-report.json").read_text(), "original report evidence")

    def test_legitimate_failed_test_remains_terminal_and_unchanged(self):
        self.write_receipt(self.identifier, legacy=False)
        status = {"state": "FINISHED", "outcome": "TEST_FAILED", "cleanup": "CONFIRMED", "evidence": "COMPLETE"}
        collection = {"pool_job": self.identifier, "pool_outcome": "TEST_FAILED", "log": str(self.log),
                      "collection_format": COLLECTION_FORMAT, "diagnostic_only": False}
        row = self.row(self.identifier, "DONE", status, collection)
        directory = self.write_mcp_cache([row])
        original = (directory / "batch.json").read_bytes()
        with patch("tools.testqueue.pool.rpc") as rpc, patch.object(Pool, "remote") as remote, \
             patch.object(pool_mcp, "_start") as start, \
             patch.object(self.pool, "verify_collection", return_value=collection), \
             patch.object(self.pool, "submit") as submit, patch.object(self.pool, "collect") as collect:
            self.assertEqual(self.run_batch()["result"], "FAILED")
            result = pool_mcp.status("cached", "full", config=self.config)
            self.assertEqual(result["result"], "FAILED")
            self.assertEqual(result["jobs"][0], row)
            self.assertFalse(result.get("recovery_required", False))
            self.assertEqual(pool_mcp.recover("cached", config=self.config)["result"], "FAILED")
            start.assert_not_called()
            rpc.assert_not_called()
            remote.assert_not_called()
            submit.assert_not_called()
            collect.assert_not_called()
        self.assertEqual((directory / "batch.json").read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
