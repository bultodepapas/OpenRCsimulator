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
        self.serial = 0

    def tearDown(self):
        self.raw.close()
        self.agg.close()
        self._tmp.__exit__()

    def seed_day(self, day, scale=1):
        for gpu, count in MIX.items():
            for _ in range(count * scale):
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

    def test_snapshot_and_render(self):
        for offset in range(7):
            day = MONDAY + timedelta(days=offset)
            self.seed_day(day)
            self.agg.add_ingest_counts([(day.isoformat(), "accepted", 61 * (1 + offset % 3)),
                                        (day.isoformat(), "duplicate", offset),
                                        (day.isoformat(), "rejected:unapproved_release", 4 if offset == 2 else 0),
                                        (day.isoformat(), "rate_limited", 2 if offset == 5 else 0),
                                        (day.isoformat(), "forwarded_for_present", 61)])
        self.agg.add_ingest_counts([("2027-01-20", "accepted", 37), ("2027-01-19", "accepted", 80)])

        data = snapshot.collect(self.config, NOW, days=14, weeks=2, floor=20)
        json.dumps(data)  # serialisable
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

        page = dashboard.render(data)
        self.assertIn("<title>OpenRC Telemetry Dashboard</title>", page)
        self.assertIn("Operator-only", page)
        self.assertIn("nvidia_rtx", page)
        self.assertNotIn(">software<", page)
        self.assertIn("rejected:unapproved_release", page)
        self.assertNotIn("forwarded_for_present", page.split("<h2>Daily rollup")[0].split("Refusals")[1])
        rows = dashboard.ingest_rows(data)
        self.assertEqual(rows[-1]["counts"]["accepted"], 37)

        demo = os.environ.get("OPENRC_DASHBOARD_DEMO")
        if demo:
            Path(demo).mkdir(parents=True, exist_ok=True)
            (Path(demo) / "snapshot.json").write_text(json.dumps(data, indent=1), encoding="utf-8")
            (Path(demo) / "dashboard.html").write_text(page, encoding="utf-8")

    def test_empty_receiver_renders(self):
        data = snapshot.collect(self.config, NOW, days=7, weeks=1, floor=20)
        page = dashboard.render(data)
        self.assertIn("No rolled-up insight days", page)
        self.assertIn("never", page)

    def test_remote_command_quotes_and_targets_container(self):
        command = dashboard.remote_command("404", "/opt/x y", "/etc/e", 30, 4, 20)
        self.assertTrue(command.startswith("pct exec 404 -- bash -c "))
        self.assertIn("runuser -u telemetry", command)
        self.assertTrue(dashboard.remote_command("", "/opt/r", "/etc/e", 1, 1, 20).startswith("bash -c "))

    def test_nice_ticks(self):
        self.assertEqual(dashboard.nice_ticks(0), [0, 1])
        self.assertEqual(dashboard.nice_ticks(183), [0, 50, 100, 150, 200])
        self.assertEqual(dashboard.nice_ticks(7), [0, 2, 4, 6, 8])


if __name__ == "__main__":
    unittest.main()
