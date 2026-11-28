"""TQ-07-A0: the fleet report's definitions, and that it never writes under the pool root."""
from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
import time
import unittest

from tools.testqueue import fleet_report
from tools.testqueue.common import write_json


def tree(root):
    return {path.relative_to(root).as_posix(): (path.stat().st_size, path.stat().st_mtime_ns)
            for path in Path(root).rglob("*")}


class FleetReportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="openrc-fleet-report-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "pool"
        self.now = time.time()

    def request(self, name, *, supervisor, batch=None, jobs=({"script": "res://tests/test_a.gd", "platform": "any"},),
                age_hours=1.0):
        directory = self.root / "mcp" / name
        write_json(directory / "request.json", {"request_id": name, "jobs": list(jobs)})
        write_json(directory / "supervisor.json", supervisor)
        if batch is not None:
            write_json(directory / "batch.json", batch)
        stamp = self.now - age_hours * 3600
        for path in directory.iterdir():
            os.utime(path, (stamp, stamp))

    def test_definitions(self):
        self.request("passed", supervisor={"state": "FINISHED"}, batch={"result": "PASSED", "jobs": []})
        self.request("operator", supervisor={"state": "NEEDS_OPERATOR", "detail": "no progress"},
                     batch={"result": "INCOMPLETE", "jobs": [
                         {"phase": "WAITING", "status": {"decision": {"candidates": [
                             {"host": "linux", "reasons": ["INSUFFICIENT_DISK: 1 < 2 bytes"]}]}}}]})
        self.request("frozen", supervisor={"state": "ERROR", "error": "source changed during snapshot"})
        self.request("stale", supervisor={"state": "RUNNING"}, batch={"result": "INCOMPLETE", "jobs": []}, age_hours=30)
        self.request("live", supervisor={"state": "RUNNING"}, batch={"result": "INCOMPLETE", "jobs": []},
                     jobs=[{"script": "res://tests/test_b.gd", "platform": "windows", "host": "windows"}])
        self.request("old", supervisor={"state": "FINISHED"}, batch={"result": "FAILED", "jobs": []}, age_hours=24 * 30)
        archive = self.root / "archives" / ("d" * 64 + ".tar")
        archive.parent.mkdir(parents=True)
        archive.write_bytes(b"x" * 2_000_000)
        receipts = {
            "a": {"host": "linux", "state": "SUBMITTED", "source_digest": "d" * 64, "transfer_seconds": 100.0,
                  "last_status": {"state": "FINISHED", "outcome": "PASSED"}},
            "b": {"host": "linux", "state": "SUBMITTED", "transfer_seconds": 3.0,
                  "last_status": {"state": "FINISHED", "outcome": "INFRA_FAILED"}},
            "c": {"host": "mac", "state": "SUBMISSION_UNCONFIRMED", "error": "lost reply"},
            "d": {"host": "mac", "state": "CANCELED_BEFORE_DISPATCH",
                  "last_status": {"state": "FINISHED", "outcome": "NOT_DISPATCHED"}},
        }
        for name, value in receipts.items():
            write_json(self.root / "jobs" / (name + ".json"), {"created": self.now - 3600, **value})
        before = tree(self.root)
        value = fleet_report.report(self.root, days=7, now=self.now)
        self.assertEqual(tree(self.root), before)  # read-only
        requests = value["requests"]
        self.assertEqual(requests["total"], 5)  # "old" is outside the window
        self.assertEqual(requests["needs_person"], 3)  # operator, frozen and stale
        self.assertEqual(requests["in_flight"], 1)
        self.assertEqual(value["executed_attempts"], {"total": 2, "infra_failed": 1, "infra_share": 0.5,
                                                      "by_host_outcome": {"linux:INFRA_FAILED": 1, "linux:PASSED": 1}})
        self.assertEqual(value["transfers"]["linux"]["uploads"]["n"], 1)
        self.assertEqual(value["transfers"]["linux"]["reuse_checks"]["n"], 1)
        self.assertEqual(value["transfers"]["linux"]["upload_mb_per_s"]["p50"], 0.0)  # 2 MB in 100 s, rounded
        self.assertEqual([item["job"] for item in value["reserving_receipts"]], ["c"])
        self.assertEqual(value["waiting_refusals"], {"linux:INSUFFICIENT_DISK": 1})
        self.assertEqual(value["routing"]["pinning"], {"unpinned": 4, "pinned": 1})
        self.assertIn("needs a person 3", fleet_report.text(value))

    def test_cli_refuses_to_write_under_the_pool_root(self):
        (self.root / "mcp").mkdir(parents=True)
        with self.assertRaises(SystemExit):
            fleet_report.main(["--root", str(self.root), "--json", str(self.root / "report.json")])
        self.assertFalse((self.root / "report.json").exists())
        outside = self.root.parent / "report.json"
        self.assertEqual(fleet_report.main(["--root", str(self.root), "--json", str(outside)]), 0)
        self.assertEqual(json.loads(outside.read_text())["requests"]["total"], 0)


if __name__ == "__main__":
    unittest.main()
