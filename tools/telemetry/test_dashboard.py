"""Snapshot + dashboard on a receiver database seeded through the real ingest and rollup paths.

    python -m unittest tools/telemetry/test_dashboard.py      (from the repository root, service deps installed)

Set OPENRC_DASHBOARD_DEMO=<dir> to keep the rendered demo page and snapshot for a visual check.
"""
from __future__ import annotations

from datetime import date, timedelta
import hashlib
import json
import os
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parent
SERVICE = HERE.parents[1] / "services" / "telemetry"
sys.path[:0] = [str(SERVICE), str(HERE)]

from openrc_telemetry.contract import load_contracts  # noqa: E402
from openrc_telemetry.rollup import run_rollup  # noqa: E402
from openrc_telemetry.storage import AggStore, RawStore  # noqa: E402
from tests.support import (RELEASE, SCHEMA_DIR, TempDir, activity_event, batch, encode, make_config,  # noqa: E402
                           perf_event, unix)

import dashboard  # noqa: E402
import snapshot  # noqa: E402

MONDAY = date(2027, 1, 11)
NOW = unix("2027-01-20T09:30:00Z")  # Sunday + 47 h has passed; W02 is closed
MIX = {"nvidia_rtx": 30, "amd_radeon": 12, "intel_integrated": 8, "apple_silicon": 6, "nvidia_gtx": 3, "software": 1}
SLOW = [0, 900, 700, 150, 40, 8, 2, 0]  # a heavier frame-interval histogram (sums to 1800)


class DashboardCase(unittest.TestCase):
    def setUp(self):
        self._tmp = TempDir()
        self.dir = self._tmp.__enter__()
        self.config = make_config(self.dir)
        self.raw = RawStore(self.config.raw_path)
        self.agg = AggStore(self.config.aggregates_path)
        self.raw.count(), self.agg.ingest_counts("2000-01-01")  # create both databases, as a running receiver has
        self.serial = 0

    def tearDown(self):
        self.raw.close()
        self.agg.close()
        self._tmp.__exit__()

    def seed_day(self, day):
        for gpu, count in MIX.items():
            for _ in range(count):
                self.serial += 1
                heavy = gpu in ("intel_integrated", "software")
                events = [perf_event(1, histogram=SLOW if heavy else None, frames=1500 if heavy else 1800),
                          activity_event(2, vehicle="f4u-corsair-250" if self.serial % 3 else "stik-electric-6s",
                                         seconds=300 + 60 * (self.serial % 7))]
                payload = batch(self.serial, batch_id=self.serial, events=events, gpu=gpu)
                body = encode(payload)
                receipt = unix(f"{day.isoformat()}T12:00:00Z")
                self.raw.ingest(payload["batch_id"], hashlib.sha256(body).hexdigest(), payload["session_id"],
                                [ev["seq"] for ev in payload["events"]], body, receipt)
        run_rollup(load_contracts(SCHEMA_DIR), self.raw, self.agg, day.isoformat(),
                   unix(f"{day.isoformat()}T00:00:00Z") + 26 * 3600, frozenset({RELEASE}))

    def seed_week(self):
        for offset in range(7):
            day = MONDAY + timedelta(days=offset)
            self.seed_day(day)
            self.agg.add_ingest_counts([(day.isoformat(), "accepted", 61 * (1 + offset % 3)),
                                        (day.isoformat(), "duplicate", offset),
                                        (day.isoformat(), "rejected:unapproved_release", 4 if offset == 2 else 0),
                                        (day.isoformat(), "rate_limited", 2 if offset == 5 else 0),
                                        (day.isoformat(), "forwarded_for_present", 61)])
        # 01-18 had traffic and was never rolled up (missed); 01-19 is still inside its window (overdue).
        self.agg.add_ingest_counts([("2027-01-20", "accepted", 37), ("2027-01-19", "accepted", 80),
                                    ("2027-01-18", "accepted", 12), ("2027-01-19", "rate_limited", 3)])

    def test_snapshot_and_render(self):
        self.seed_week()
        data = snapshot.collect(self.config, NOW, days=14, weeks=2, floor=20)
        json.dumps(data)  # serialisable
        self.assertEqual(data["snapshot_version"], 2)
        self.assertEqual([r["week"] for r in data["insights"]], ["2027-W02"])
        week = data["insights"][0]
        self.assertTrue(week["week_closed"])
        gpu = week["tables"]["flight_gpu"]
        self.assertNotIn(["software"], [row["dims"] for row in gpu["published"]])
        self.assertIsNotNone(gpu["combined"])
        self.assertEqual(data["releases_with_cells"], [RELEASE])
        self.assertEqual(len(data["ingest"]), 14)
        text = json.dumps(data)
        for forbidden in ("session_id", "batch_id"):
            self.assertNotIn(forbidden, text)

        rows = dashboard.ingest_rows(data)
        self.assertEqual(rows[-1]["counts"]["accepted"], 37)
        _, cells, day_state = dashboard.coverage_model(data, rows)
        self.assertEqual(day_state["2027-01-18"], "missed")
        self.assertEqual(day_state["2027-01-19"], "overdue")
        self.assertEqual(day_state["2027-01-20"], "pending")
        self.assertEqual(day_state["2027-01-10"], "none")
        self.assertEqual(cells[(RELEASE, "2027-01-13")][0], "ready")
        titles = [title for _, title, _ in dashboard.alerts(data, rows, day_state)]
        self.assertEqual(titles[0], "Raw row past 48 h")  # the seeded raw rows were never purged
        self.assertIn("1 day(s) never rolled up", titles)
        self.assertIn("Rollup overdue for 2027-01-19", titles)
        self.assertIn("Rate limiting", titles)
        # Raw rows end on 01-17, but the counters show batches today: no silence alert, "today" from counters.
        self.assertNotIn("No batch in 24 h", titles)
        self.assertEqual(dashboard.last_seen(data, rows)[1:], ("today", "daily counters (UTC day)"))

        page = dashboard.render(data)
        self.assertIn("<title>OpenRC Telemetry Dashboard</title>", page)
        self.assertIn("Operator-only", page)
        self.assertIn("nvidia_rtx", page)
        self.assertNotIn(">software<", page)
        self.assertIn("rejected:unapproved_release", page)
        self.assertIn("Old snapshot.", page)  # a 2027 fixture rendered now is stale
        self.assertNotIn("forwarded_for_present", page.split("<h2>Daily rollup")[0].split("Refusals")[1])

        demo = os.environ.get("OPENRC_DASHBOARD_DEMO")
        if demo:
            Path(demo).mkdir(parents=True, exist_ok=True)
            (Path(demo) / "dashboard.snapshot.json").write_text(json.dumps(data, indent=1), encoding="utf-8")
            (Path(demo) / "dashboard.html").write_text(page, encoding="utf-8")

    def test_empty_receiver_renders(self):
        data = snapshot.collect(self.config, NOW, days=7, weeks=1, floor=20)
        rows = dashboard.ingest_rows(data)
        _, _, day_state = dashboard.coverage_model(data, rows)
        self.assertEqual([t for _, t, _ in dashboard.alerts(data, rows, day_state)], ["Waiting for first batch"])
        page = dashboard.render(data)
        self.assertIn("No rolled-up insight days", page)
        self.assertIn("never", page)

    def test_silence_after_raw_purge_is_not_first_batch(self):
        self.agg.add_ingest_counts([("2027-01-16", "accepted", 5)])
        data = snapshot.collect(self.config, NOW, days=7, weeks=1, floor=20)
        rows = dashboard.ingest_rows(data)
        _, _, day_state = dashboard.coverage_model(data, rows)
        alerts = dashboard.alerts(data, rows, day_state)
        self.assertIn(("warning", "No batch in 24 h", "last accepted batch on 2027-01-16"), alerts)
        self.assertEqual(dashboard.last_seen(data, rows)[1], "on 2027-01-16")
        self.assertIn("1 day(s) never rolled up", [t for _, t, _ in alerts])
        self.assertIn("2027-01-16", dashboard.render(data))

    def test_missing_database_is_refused(self):
        config = make_config(self.dir / "elsewhere")
        with self.assertRaises(FileNotFoundError):
            snapshot.collect(config, NOW, days=7, weeks=1)
        self.assertFalse((self.dir / "elsewhere" / "raw.sqlite").exists())

    def test_release_order_is_semantic(self):
        ordered = sorted(["v0.3.9", "v0.3.10", "v0.3.10-rc.1", "v0.2.7", "v0.3.10-beta2"],
                         key=snapshot.release_key, reverse=True)
        self.assertEqual(ordered, ["v0.3.10", "v0.3.10-rc.1", "v0.3.10-beta2", "v0.3.9", "v0.2.7"])

    def test_render_refuses_unknown_snapshot_version(self):
        with self.assertRaises(ValueError):
            dashboard.render({"snapshot_version": 99})

    def test_out_inside_repository_is_refused(self):
        with self.assertRaises(SystemExit):
            dashboard.main(["render", "--snapshot", "x.json", "--out", str(HERE / "page.html"), "--no-open"])

    def test_remote_command_quotes_and_filters_environment(self):
        command = dashboard.remote_command("404", "/opt/x y", "/etc/e", 30, 4, 20)
        self.assertTrue(command.startswith("pct exec 404 -- bash -c "))
        self.assertIn("runuser -u telemetry", command)
        self.assertIn("OPENRC_TELEMETRY_", command)
        self.assertTrue(dashboard.remote_command("", "/opt/r", "/etc/e", 1, 1, 20).startswith("bash -c "))

    def test_nice_ticks(self):
        self.assertEqual(dashboard.nice_ticks(0), [0, 1])
        self.assertEqual(dashboard.nice_ticks(183), [0, 50, 100, 150, 200])
        self.assertEqual(dashboard.nice_ticks(7), [0, 2, 4, 6, 8])


if __name__ == "__main__":
    unittest.main()
