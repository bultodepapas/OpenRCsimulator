"""Retention keeps every referenced, recent or unresolved input (TQ-05-F0.1)."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.testqueue import retention
from tools.testqueue.store import Store

OLD = time.time() - 72 * 3600


def _write(path: Path, data) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def _tree(path: Path, size: int = 10) -> Path:
    (path / "app").mkdir(parents=True, exist_ok=True)
    (path / "app" / "file.bin").write_bytes(b"x" * size)
    return path


def _age(path: Path, when: float = OLD) -> None:
    os.utime(path, (when, when))


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.queue, self.pool = base / "queue", base / "pool"
        self.queue.mkdir()
        Store(self.queue).db.close()
        self.db = sqlite3.connect(self.queue / "queue.sqlite3")
        for name in ("snapshots", "jobs", "batches", "mcp", "archives"):
            (self.pool / name).mkdir(parents=True)
        (self.queue / "snapshots").mkdir()

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def job(self, job, preset="checked", state="FINISHED", snapshot=None, request=None):
        payload = {"preset": preset, "snapshot": str(snapshot) if snapshot else None}
        self.db.execute("INSERT INTO jobs(id, request_id, payload, digest, capability, request_secret, state, submitted)"
                        " VALUES (?,?,?,?,?,?,?,?)", (job, request or "r-" + job, json.dumps(payload), "d", "c", "s",
                                                      state, OLD))
        self.db.commit()

    def attempt(self, attempt, job, state="FINISHED", outcome="TEST_FAILED", claimed=False, age=OLD):
        self.db.execute("INSERT INTO attempts(id, job, generation, state, data) VALUES (?,?,?,?,?)",
                        (attempt, job, 1, state, json.dumps({"outcome": outcome})))
        if claimed:
            self.db.execute("INSERT INTO claims(resource, attempt, amount) VALUES ('cpu', ?, 1)", (attempt,))
        self.db.commit()
        source = _tree(self.queue / "attempts" / attempt / "source")
        _write(self.queue / "attempts" / attempt / "verdict.json", {"outcome": outcome})
        _age(source, age)
        return source

    def plan(self, **kwargs):
        return retention.plan(self.queue, self.pool, 24, **kwargs)

    @staticmethod
    def kinds(report, group):
        return {(row["kind"], Path(row["path"]).name if row["kind"] != "attempt-source"
                 else Path(row["path"]).parent.name) for row in report[group]}

    def test_attempt_sources_follow_preset_state_claim_and_age(self):
        self.job("J1"); self.attempt("A-fail", "J1")
        self.job("J2", preset="godtest"); self.attempt("A-god", "J2")
        self.job("J3"); self.attempt("A-claim", "J3", claimed=True)
        self.job("J4", state="RUNNING"); self.attempt("A-unknown", "J4", state="UNKNOWN", outcome=None)
        self.job("J5"); self.attempt("A-young", "J5", age=time.time())
        self.job("J6", preset="debug-session"); self.attempt("A-dbg", "J6", outcome="CANCELED")
        report = self.plan()
        self.assertEqual(self.kinds(report, "candidates"),
                         {("attempt-source", "A-fail"), ("attempt-source", "A-dbg")})
        held = {Path(row["path"]).parent.name: row["reason"] for row in report["holds"]}
        self.assertIn("godtest", held["A-god"])
        self.assertIn("claim", held["A-claim"])
        self.assertIn("UNKNOWN", held["A-unknown"])
        self.assertIn("younger", held["A-young"])

    def test_snapshots_are_held_by_live_references(self):
        live = _tree(self.queue / "snapshots" / "live"); _age(live)
        free = _tree(self.queue / "snapshots" / "free"); _age(free)
        pending = _tree(self.queue / "snapshots" / "pending"); _age(pending)
        self.job("JQ", state="QUEUED", snapshot=live)
        _write(self.queue / "submissions" / "lost.json", {"request_id": "lost-reply", "snapshot": str(pending)})
        report = self.plan()
        self.assertIn(("local-snapshot", "free"), self.kinds(report, "candidates"))
        self.assertIn(("local-snapshot", "live"), self.kinds(report, "holds"))
        self.assertIn(("local-snapshot", "pending"), self.kinds(report, "holds"))

    def test_a_stale_request_no_longer_pins_its_snapshot_but_a_live_receipt_still_does(self):
        # TQ-07-G4: 28 November, 60 snapshots (38.8 GB) on C: were pinned by MCP
        # requests idle for 5-13 days that the watchdog will never resume.
        snaps = {name: _tree(self.pool / "snapshots" / name) for name in ("stale", "fresh", "dispatched")}
        for path in snaps.values():
            _age(path)
        for name in ("stale", "fresh", "dispatched"):
            directory = self.pool / "mcp" / name
            _write(directory / "manifest.json", {"snapshot": str(snaps[name]), "jobs": []})
            _write(directory / "batch.json", {"result": "INCOMPLETE", "jobs": []})
            _write(directory / "supervisor.json", {"state": "NEEDS_OPERATOR"})
            if name != "fresh":
                for item in directory.iterdir():
                    _age(item, time.time() - 5 * 24 * 3600)
        _write(self.pool / "jobs" / "live.json", {"state": "SUBMITTED", "snapshot": str(snaps["dispatched"]),
                                                   "last_status": {"state": "RUNNING"}})
        report = self.plan(stale_request_hours=72)
        self.assertIn(("pool-snapshot", "stale"), self.kinds(report, "candidates"))
        self.assertIn(("pool-snapshot", "fresh"), self.kinds(report, "holds"))
        self.assertIn(("pool-snapshot", "dispatched"), self.kinds(report, "holds"))  # its receipt still pins it
        self.assertEqual(report["stale_requests"], 2)
        # Without the threshold (the library default) every unfinished request still pins.
        self.assertIn(("pool-snapshot", "stale"), self.kinds(self.plan(), "holds"))

    def test_pool_inputs_follow_receipts_batches_and_mcp_requests(self):
        snaps = {name: _tree(self.pool / "snapshots" / name) for name in ("done", "running", "batch", "mcp", "orphan")}
        for path in snaps.values():
            _age(path)
        _write(self.pool / "jobs" / "done.json", {"state": "SUBMITTED", "snapshot": str(snaps["done"]),
                                                  "source_digest": "aaa", "last_status": {"state": "FINISHED"}})
        _write(self.pool / "jobs" / "run.json", {"state": "SUBMITTED", "snapshot": str(snaps["running"]),
                                                 "source_digest": "bbb", "last_status": {"state": "RUNNING"}})
        _write(self.pool / "batches" / "b1.json", {"snapshot": str(snaps["batch"])})
        _write(self.pool / "batches" / "b1-state.json", {"result": "INCOMPLETE"})
        _write(self.pool / "mcp" / "req" / "manifest.json", {"snapshot": str(snaps["mcp"])})
        for digest in ("aaa", "bbb"):
            _age(_write(self.pool / "archives" / f"{digest}.tar", {}))
        _write(self.pool / "archives" / "ccc.tar.x.pending", {})
        report = self.plan()
        self.assertEqual({k for k in self.kinds(report, "candidates") if k[0] != "attempt-source"},
                         {("pool-snapshot", "done"), ("pool-snapshot", "orphan"), ("pool-archive", "aaa.tar")})
        self.assertIn(("pool-archive", "bbb.tar"), self.kinds(report, "holds"))
        self.assertNotIn("pending", json.dumps(report))

    def test_unreadable_pool_receipt_holds_every_pool_input(self):
        _age(_tree(self.pool / "snapshots" / "any"))
        _age(_write(self.pool / "archives" / "ddd.tar", {}))
        (self.pool / "jobs" / "broken.json").write_text("{", encoding="utf-8")
        report = self.plan()
        self.assertFalse([row for row in report["candidates"] if row["kind"].startswith("pool-")])

    def test_execute_rechecks_and_journals(self):
        gone = _tree(self.queue / "snapshots" / "gone"); _age(gone)
        late = _tree(self.queue / "snapshots" / "late"); _age(late)
        report = self.plan()
        self.job("JL", state="QUEUED", snapshot=late)  # referenced after the dry run
        result = retention.execute(report, self.queue, self.pool, 24)
        self.assertFalse(gone.exists())
        self.assertTrue(late.exists())
        self.assertEqual(result["skipped_now_referenced"], [str(late)])
        journal = json.loads(Path(result["journal"]).read_text(encoding="utf-8"))
        self.assertEqual(journal["state"], "DONE")

    def test_min_age_floor_and_dry_run_default(self):
        free = _tree(self.queue / "snapshots" / "free"); _age(free)
        with self.assertRaises(SystemExit):
            retention.main(["--queue-root", str(self.queue), "--no-pool", "--min-age-hours", "0"])
        retention.main(["--queue-root", str(self.queue), "--no-pool"])
        self.assertTrue(free.exists())


if __name__ == "__main__":
    unittest.main()
