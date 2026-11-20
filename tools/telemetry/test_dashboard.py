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
import github_archive as downloads  # noqa: E402
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
        self.assertIn("<title>OpenRC Stats Dashboard</title>", page)
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
        self.assertIn("No player data yet", page)
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

    def make_archive(self, directory):
        """A GitHub history archive written through tools/analytics/github_history.py's own storage functions."""
        import sqlite3
        directory.mkdir(parents=True, exist_ok=True)
        gh = downloads.github_history
        connection = sqlite3.connect(directory / gh.DATABASE_NAME, isolation_level=None)
        gh.initialize(connection, gh.DEFAULT_REPO, gh.DEFAULT_ASSET_GLOB)

        def assets(counts, stamp):
            return [{"asset_id": i, "release_id": i // 10, "tag": tag, "name": f"openrc-simulator-{tag}-{os_}.zip",
                     "count": n, "started": stamp, "finished": stamp}
                    for i, (tag, os_, n) in enumerate(counts, start=10)]
        base = [("v0.3.9", "windows-x86_64", 40), ("v0.3.9", "linux-x86_64", 5),
                ("v0.3.10", "windows-x86_64", 3), ("v0.3.10", "macos-universal", 2)]
        gh.save_assets(connection, assets(base, "2027-01-18T00:10:00Z"), "2027-01-18T00:10:00Z", "2027-01-18T00:10:05Z")
        later = [(t, o, n + 4) for t, o, n in base]
        gh.save_assets(connection, assets(later, "2027-01-19T00:10:00Z"), "2027-01-19T00:10:00Z", "2027-01-19T00:10:05Z")
        connection.execute("INSERT INTO attempts(kind, started_utc, finished_utc, success) VALUES "
                           "('release assets', '2027-01-19T00:10:00Z', '2027-01-19T00:10:05Z', 1)")
        days = [{"day": f"2027-01-{d:02d}", "views": 10 * d, "uniques": d, "status": "observed_after_day"}
                for d in range(10, 20)]
        gh.save_traffic(connection, days, "2027-01-19T00:10:00Z", "2027-01-19T00:10:01Z")
        gh.save_clones(connection, [{**d, "views": d["views"] * 3} for d in days], "2027-01-19T00:10:00Z",
                       "2027-01-19T00:10:01Z")
        gh.save_community(connection, {
            "counters": {"stars": 12, "forks": 3, "watchers": 2, "open_issues": 5},
            "referrers": [{"referrer": "reddit.com", "count": 30, "uniques": 20},
                          {"referrer": "<b>evil</b>", "count": 2, "uniques": 1}],
            "paths": [{"path": "/o/r/releases", "title": "Releases · o/r", "count": 9, "uniques": 6}],
            "releases": [{"tag": "v0.3.9", "published": "2027-01-12T15:00:00Z", "prerelease": False},
                         {"tag": "v0.3.10", "published": "2027-01-18T09:00:00Z", "prerelease": False}],
            "star_days": {"2026-12-01": 10, "2027-01-15": 2}},
            "2027-01-19T00:10:02Z", "2027-01-19T00:10:03Z")
        connection.close()

    def test_github_and_overview_tabs(self):
        archive = self.dir / "analytics"
        self.make_archive(archive)
        model = downloads.load(archive)
        self.assertEqual(model["counters"][-1]["stars"], 12)
        self.assertEqual(downloads.stars_cumulative(model, ["2027-01-14", "2027-01-15", "2027-01-16"]), [10, 12, 12])
        self.assertEqual(downloads.window_sum(model["traffic"], ["2027-01-18", "2027-01-19"]), 370)
        data = snapshot.collect(self.config, NOW, days=14, weeks=1, floor=20)
        data["github"] = model
        page = dashboard.render(data)
        for tab in ("overview", "players", "downloads", "github", "website", "receiver"):
            self.assertIn(f'id="panel-{tab}"', page)
        self.assertIn("Repository views, 14 days", page)
        self.assertIn("&lt;b&gt;evil&lt;/b&gt;", page)  # referrer text is escaped
        self.assertNotIn("<b>evil</b>", page)
        self.assertIn("Release v0.3.10", page)  # release marker in a tooltip
        self.assertIn("G-4Z11DSB2BV", page)

    def test_website_tab_from_ga4(self):
        import test_ga4
        data = snapshot.collect(self.config, NOW, days=7, weeks=1, floor=20)
        data["github"] = None
        self.assertIn("Not connected", dashboard.render(data))  # older snapshots have no "website" key
        data["website"] = test_ga4.model()
        page = dashboard.render(data)
        website = page.split('id="panel-website"')[1].split('id="panel-receiver"')[0]
        for text in ("Active users, 7 days", "Download requests by platform", "windows", "Not registered in GA4",
                     "<code>download_source</code>", "Web Vitals ratings", "/OpenRCsimulator/ja.html",
                     "Etc/UTC", "Active users now", "property 123456789"):
            self.assertIn(text, website)
        self.assertIn("&lt;b&gt;evil&lt;/b&gt;", website)  # country text is escaped
        self.assertNotIn("<b>evil</b>", page)
        overview = page.split('id="panel-overview"')[1].split('id="panel-players"')[0]
        self.assertIn("Website users, 7 days", overview)
        self.assertIn("Website visitors per day", overview)
        rows = dashboard.ingest_rows(data)
        self.assertNotIn("Website analytics failed", [t for _, t, _ in dashboard.alerts(data, rows, {})])
        data["website"] = test_ga4.model(fail={(("date",), "download_request")})
        overview, website = (dashboard.render(data).split('id="panel-website"')[i] for i in (0, 1))
        self.assertIn("download requests: report failed", overview)
        self.assertIn('<div class="tv">-</div><div class="ts">report failed</div>', website)
        data["website"] = {"error": "HTTP 403: <denied>", "collected_utc": "2027-01-20T09:00:00Z", "property": None}
        page = dashboard.render(data)
        self.assertIn("HTTP 403: &lt;denied&gt;", page)
        self.assertIn("Website analytics failed", [t for _, t, _ in dashboard.alerts(data, rows, {})])

    def test_version_one_archive_loads_without_extras(self):
        import sqlite3
        archive = self.dir / "v1"
        self.make_archive(archive)
        connection = sqlite3.connect(archive / downloads.github_history.DATABASE_NAME)
        connection.execute("PRAGMA user_version = 1")
        connection.commit()
        connection.close()
        model = downloads.load(archive)
        self.assertEqual((model["clones"], model["counters"], model["star_days"]), ([], [], {}))
        self.assertTrue(model["traffic"])
        self.assertEqual(downloads.stars_cumulative(model, ["2027-01-01", "2027-01-02"]), [None, None])

    def test_path_labels_strip_the_repository_prefix(self):
        repo = "o/r"
        self.assertEqual(dashboard.path_label("/o/r", repo), "(repository home)")
        self.assertEqual(dashboard.path_label("/o/r/issues/12", repo), "issues/12")
        self.assertEqual(dashboard.path_label("/other/x", repo), "other/x")

    def test_downloads_section_and_alerts(self):
        archive = self.dir / "analytics"
        self.make_archive(archive)
        model = downloads.load(archive)
        releases = downloads.per_release(model)
        self.assertEqual([tag for tag, _, _ in releases], ["v0.3.10", "v0.3.9"])  # semantic, newest first
        self.assertEqual(releases[1][1]["Windows"], 44)
        self.assertEqual(releases[0][2], 13)
        self.assertEqual(downloads.per_day(model), {"2027-01-19": (16, False)})
        self.assertEqual(downloads.recent_increase(model, NOW), 16)

        data = snapshot.collect(self.config, NOW, days=7, weeks=1, floor=20)
        data["github"] = model
        page = dashboard.render(data)
        self.assertIn('id="panel-downloads"', page)
        self.assertIn("Latest release v0.3.10", page)
        rows = dashboard.ingest_rows(data)
        titles = [t for _, t, _ in dashboard.alerts(data, rows, dashboard.coverage_model(data, rows)[2])]
        self.assertNotIn("Download counters stale", titles)
        data["generated_unix"] = NOW + 3 * 86400
        titles = [t for _, t, _ in dashboard.alerts(data, rows, dashboard.coverage_model(data, rows)[2])]
        self.assertIn("Download counters stale", titles)
        data["github"]["collect_note"] = "gh: not logged in"
        self.assertIn("Download refresh failed", [t for _, t, _ in dashboard.alerts(data, rows, {})])

    def test_no_archive_renders_hint(self):
        self.assertIsNone(downloads.load(self.dir / "nothing"))
        data = snapshot.collect(self.config, NOW, days=7, weeks=1, floor=20)
        data["github"] = None
        self.assertIn("No GitHub history archive found", dashboard.render(data))

    def test_release_order_matches_between_modules(self):
        tags = ["v0.3.9", "v0.3.10", "v0.3.10-rc.1", "v0.1.0-rc8", "v0.1.0", "odd"]
        self.assertEqual(sorted(tags, key=snapshot.release_key), sorted(tags, key=downloads.release_key))

    def test_nice_ticks(self):
        self.assertEqual(dashboard.nice_ticks(0), [0, 1])
        self.assertEqual(dashboard.nice_ticks(183), [0, 50, 100, 150, 200])
        self.assertEqual(dashboard.nice_ticks(7), [0, 2, 4, 6, 8])


if __name__ == "__main__":
    unittest.main()
