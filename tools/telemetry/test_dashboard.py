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
import unittest.mock

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
from deploy.ct import backup_archive  # noqa: E402
from deploy.host import check_dashboard_health  # noqa: E402

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
        overview = page.split('id="panel-overview"')[1].split('id="panel-players"')[0]
        for text in ("Last 7 full days", "2027-01-13 to 2027-01-19", "Package downloads", "Repository views",
                     "New stars", "Recent releases", "<td>v0.3.10</td>", "Downloads by platform",
                     "Repository referrers, 14 days", "GitHub package downloads by collection day", "Interest per day",
                     "Website (GA4)</b> not connected", "Telemetry batches"):
            self.assertIn(text, overview)
        self.assertIn("Old snapshot.", page)  # the fixture is from 2027-01-20
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
                     "Etc/UTC", "Active users now", "property 123456789", "Download conversion", "8%",
                     "Phone hand-offs", "Property setup (WEB-17)", "missing: release_version",
                     "two months", "<td>github</td><td>10</td><td>9</td><td>90%</td>"):
            self.assertIn(text, website)
        self.assertIn("&lt;b&gt;evil&lt;/b&gt;", website)  # country text is escaped
        self.assertNotIn("<b>evil</b>", page)
        overview = page.split('id="panel-overview"')[1].split('id="panel-players"')[0]
        for text in ("Website sessions", "Website download requests", "8% of 7-day users request a download",
                     "Top countries", "Where people come from", "Website, 7 days", "<td>github</td>",
                     'aria-label="Website download requests per day"'):
            self.assertIn(text, overview)
        rows = dashboard.ingest_rows(data)
        self.assertNotIn("Website analytics failed", [t for _, t, _ in dashboard.alerts(data, rows, {})])
        data["website"] = test_ga4.model(fail={(("date",), "download_request")})
        overview, website = (dashboard.render(data).split('id="panel-website"')[i] for i in (0, 1))
        self.assertIn("download requests: report failed", overview)
        self.assertIn("latest 7 days incomplete", website)
        self.assertIn("Report failed:", website)
        data["website"] = {"error": "HTTP 403: <denied>", "collected_utc": "2027-01-20T09:00:00Z", "property": None}
        page = dashboard.render(data)
        self.assertIn("HTTP 403: &lt;denied&gt;", page)
        self.assertIn("Website analytics failed", [t for _, t, _ in dashboard.alerts(data, rows, {})])

    def test_week_over_week_delta(self):
        self.assertIn("▲ 50% (+5) vs prior 7 days", dashboard.delta_html(15, 10))
        self.assertIn("▼ 25% (-5) vs prior 7 days", dashboard.delta_html(15, 20))
        self.assertIn("nothing in either week", dashboard.delta_html(0, 0))
        self.assertIn("new (+3)", dashboard.delta_html(3, 0))
        self.assertIn("no comparison yet", dashboard.delta_html(3, None))

    def test_provisional_and_missing_observations_stay_distinct(self):
        days = ["2027-01-01", "2027-01-02", "2027-01-03", "2027-01-04"]
        html = dashboard.line_chart(days, [("Sessions", [0, None, 3, 4], "s1")], "Sessions",
                                    provisional={"Sessions": {days[-1]}})
        self.assertIn("0 (observed)", html)
        self.assertIn("Unavailable", html)
        self.assertIn("4 (provisional)", html)
        self.assertIn('class="provisional line-s1"', html)
        path = html.split('class="line line-s1" d="')[1].split('"')[0]
        self.assertEqual(path.count("M"), 2)
        self.assertNotIn("L", path)
        self.assertIn("<summary>Data table</summary>", html)
        metric = dashboard.week_metric("Sessions", "website", "GA4", "UTC", days[2:], days[:2],
                                       dict(zip(days, (0, 0, 3, 4))), "2027-01-04T06:00:00Z",
                                       uncertain={days[-1]})
        self.assertIsNone(metric.previous)
        self.assertEqual(metric.condition, "Partial coverage")

    def test_long_timeline_keeps_every_day_inspectable_with_one_tab_stop(self):
        days = [(MONDAY + timedelta(days=offset)).isoformat() for offset in range(90)]
        page = dashboard.line_chart(days, [("Views", list(range(90)), "s1")], "Views")
        self.assertEqual(page.count('class="hit"'), 90)
        self.assertEqual(page.count('tabindex="0"'), 1)
        self.assertIn(f'aria-label="{days[-1]} · Views: 89"', page)
        self.assertIn(f'<th scope="row">{days[0]}</th><td>0 (observed)</td>', page)
        self.assertEqual(page.count('class="tick date-tick'), 7)

    def test_stacked_release_bars_keep_exact_proportions_and_zero(self):
        counts = {"Windows": 199, "macOS": 1, "Linux": 0, "Other": 0}
        empty = dict.fromkeys(counts, 0)
        page = dashboard.release_chart([("v2", counts, 200), ("v1", empty, 0)])
        self.assertIn('class="fill-s1" style="flex-grow:199"', page)
        self.assertIn('class="fill-s2" style="flex-grow:1"', page)
        self.assertIn('aria-label="v2 · Total 200 · Windows: 199 · macOS: 1"', page)
        self.assertIn('aria-label="v1 · Total 0"', page)
        self.assertEqual(page.count('tabindex="0"'), 1)



    def test_download_columns_distinguish_observed_zero_and_missing_intervals(self):
        days = ["2027-01-01", "2027-01-02", "2027-01-03"]
        html = dashboard.download_collection_chart(days, {days[0]: 12, days[2]: 0},
                                                   {days[1]: "Long collection interval"}, "Package downloads")
        self.assertEqual(html.count('class="collection-bar '), 1)
        self.assertEqual(html.count('class="collection-gap"'), 1)
        self.assertEqual(html.count('class="collection-zero '), 1)
        self.assertIn('2027-01-02 · Matched counter increase: Unavailable · Long collection interval', html)
        self.assertIn('2027-01-03 · Matched counter increase: 0 (observed)', html)
        self.assertNotIn('class="line line-', html)
        self.assertEqual(html.count('tabindex="0"'), 1)

    def test_download_counter_gap_preserves_the_original_interval(self):
        intervals = [{"from_end": "2027-01-16T10:00:00Z", "to_end": "2027-01-19T10:00:00Z",
                      "increase": 30, "status": "matched_ids"}]
        with_archive = {"intervals": intervals, "assets": [], "pattern": "*.zip", "collected_utc": intervals[0]["to_end"]}
        values, notes = dashboard.download_daily(with_archive)
        self.assertEqual(values, {})
        self.assertEqual(notes["2027-01-19"], "Long collection interval")
        html = dashboard.downloads_section(with_archive, NOW, 7)
        self.assertIn("<summary>Collection intervals</summary>", html)
        self.assertIn("<td>2027-01-16T10:00:00Z</td><td>2027-01-19T10:00:00Z</td><td>30</td>", html)

    def test_github_public_counters_continue_when_credentials_fail(self):
        with unittest.mock.patch.dict(os.environ, {"GH_TOKEN": "fixture"}), unittest.mock.patch.object(
                dashboard.downloads, "collect", side_effect=[(False, "authentication failed"), (True, "collected")]
        ) as collect:
            self.assertEqual(dashboard.refresh_github(self.dir), "authentication failed; public counters refreshed")
        self.assertEqual(collect.call_args_list, [unittest.mock.call(self.dir, public_only=False),
                                                  unittest.mock.call(self.dir, public_only=True)])

    def test_release_cadence_requires_covered_and_equally_aged_cohorts(self):
        current = {"tag": "v0.3.2", "published": "2027-01-04T18:00:00Z"}
        previous = {"tag": "v0.3.1", "published": "2026-12-28T15:00:00Z"}
        metrics = {f"hist{i}": 0 for i in range(dashboard.HIST_LEN)}
        metrics.update(hist0=500, hist6=10, interval_sum_us=10_000_000, rendered_frames=510,
                       excluded_gap_count=2)

        def report(release, start, week):
            return {"release_id": release["tag"], "week": week, "week_closed": True,
                    "days": [{"day": (date.fromisoformat(start) + timedelta(days=offset)).isoformat(),
                              "status": "ready"} for offset in range(7)],
                    "tables": {"flight_pacing": {"published": [{"dims": ["unlimited"], "metrics": metrics,
                                                                 "sessions": 20}]}}}

        left = report(current, "2027-01-11", "2027-W02")
        right = report(previous, "2027-01-04", "2027-W01")
        data = {"insights": [left, right],
                "rollup_days": {day["day"]: "complete" for r in (left, right) for day in r["days"]}}
        self.assertIn("Release-age days 7–13", dashboard.release_cadence(data, current, previous))
        self.assertIn(">unlimited<", dashboard.release_cadence(data, current, previous))
        last = right["days"][-1]["day"]
        data["rollup_days"][last] = "partial"
        self.assertIn("Comparable data is unavailable", dashboard.release_cadence(data, current, previous))
        data["rollup_days"][last] = "complete"
        right["days"][-1]["status"] = "missing"
        self.assertIn("Comparable data is unavailable", dashboard.release_cadence(data, current, previous))

    def test_review_deduplicates_the_source_and_caps_actions(self):
        sample = {"generated_unix": NOW, "website": {"missing": {"vitals": []}}}
        alerts = [("critical", "Incomplete rollup", "retry before expiry"),
                  ("warning", "No batch in 24 h", "otherwise healthy"),
                  ("warning", "Download counters stale", "check collector")]
        html = dashboard.review_items(sample, alerts, [])
        self.assertEqual(html.count("<li>"), 3)
        self.assertIn('href="#receiver"', html)
        self.assertIn('href="#downloads"', html)
        self.assertNotIn("No batch in 24 h", html)

    def test_build_writes_page_and_health_atomically(self):
        import test_ga4
        data = snapshot.collect(self.config, NOW, days=7, weeks=1, floor=20)
        inbox, www, state = self.dir / "inbox.json", self.dir / "www", self.dir / "state"
        inbox.write_text(json.dumps(data), encoding="utf-8")
        args = ["build", "--receiver-snapshot", str(inbox), "--www", str(www), "--state-dir", str(state),
                "--downloads-dir", str(self.dir / "no-archive"), "--days", "7", "--ga4-property", "123"]
        fresh = NOW + 600
        with unittest.mock.patch.object(dashboard.ga4, "fetch", return_value=test_ga4.model()) as fetch, \
                unittest.mock.patch.object(dashboard.time, "time", return_value=fresh), \
                unittest.mock.patch("sys.stdout"):
            self.assertEqual(dashboard.main(args), 0)
        fetch.assert_called_once_with(7, "123", None)
        report = json.loads((www / "health.json").read_text(encoding="utf-8"))
        self.assertEqual((report["status"], report["receiver_age_s"], report["website_connected"]),
                         ("degraded", 600, True))
        self.assertEqual(report["sources"]["github_downloads"]["status"], "missing")
        self.assertIn("Active users, 7 days", (www / "index.html").read_text(encoding="utf-8"))
        self.assertTrue((state / "dashboard.snapshot.json").is_file())
        self.assertFalse((www / "dashboard.snapshot.json").exists())  # the combined snapshot is never served
        self.assertEqual(sorted(p.name for p in www.iterdir()), ["health.json", "index.html"])  # no temp files

        with unittest.mock.patch.object(dashboard.time, "time", return_value=NOW + 3 * 3600), \
                unittest.mock.patch("sys.stdout"):  # a receiver snapshot older than 2 h
            self.assertEqual(dashboard.main(args + ["--no-ga4"]), 0)
        self.assertEqual(json.loads((www / "health.json").read_text(encoding="utf-8"))["status"], "stale")

        page = (www / "index.html").read_text(encoding="utf-8")
        for invalid in ("{not json", "[]", '{"snapshot_version": 2}', '{"snapshot_version": 2, "generated_unix": NaN}'):
            with self.subTest(invalid=invalid), unittest.mock.patch("sys.stdout"):
                inbox.write_text(invalid, encoding="utf-8")
                self.assertEqual(dashboard.main(args + ["--no-ga4"]), 1)
                report = json.loads((www / "health.json").read_text(encoding="utf-8"))
                self.assertEqual(report["status"], "error")
                self.assertIn("receiver snapshot unreadable", report["problems"][0])
                self.assertEqual((www / "index.html").read_text(encoding="utf-8"), page)

    def test_health_tracks_partial_sources_and_persisted_errors(self):
        data = snapshot.collect(self.config, NOW, days=7, weeks=1, floor=20)
        stamp = dashboard.utc_stamp(NOW)
        kinds = ("release assets", "traffic", "clones", "community", "referrals", "star history")
        data["github"] = {"source_utc": dict.fromkeys(kinds, stamp), "collected_utc": stamp}
        data["website"] = {"collected_utc": stamp}
        self.assertEqual(dashboard.health(data, NOW, 7200, None, [])["status"], "ok")
        data["github"]["source_attempts"] = {"traffic": {"success": False}}
        data["website"]["missing"] = {"vitals": ["metric_name"]}
        data["status"]["retention_ok"] = False
        data["status"]["oldest_raw_age_h"] = 49
        result = dashboard.health(data, NOW, 7200, None, [])
        self.assertEqual(result["status"], "degraded")
        self.assertEqual(result["sources"]["github_views"]["status"], "error")
        self.assertEqual(result["sources"]["website"]["status"], "partial")
        self.assertIn("Raw row past 48 h", result["receiver_issues"])

    def test_partial_rollup_is_visible_in_legacy_snapshot(self):
        data = snapshot.collect(self.config, NOW, days=7, weeks=1, floor=20)
        data.pop("rollup_days", None)
        day = "2027-01-19"
        data["coverage"] = [{"release_id": "v0.3.0", "day": day, "table": "gpu", "status": "ready"}]
        rows = dashboard.ingest_rows(data)
        _, cells, days = dashboard.coverage_model(data, rows)
        self.assertEqual(cells[("v0.3.0", day)][0], "partial")
        self.assertEqual(days[day], "partial")
        self.assertIn(("critical", "Incomplete rollup", f"retry within the 47 h window: {day}"),
                      dashboard.alerts(data, rows, days))

    def test_overview_compares_full_days_in_each_sources_timezone(self):
        from datetime import datetime

        data = snapshot.collect(self.config, NOW, days=14, weeks=1, floor=20)
        data["generated_unix"] = datetime.fromisoformat("2027-01-20T01:00:00+00:00").timestamp()
        axis = dashboard.window_days(data["generated_unix"], 16)
        data["website"] = {"time_zone": "America/Bogota", "collected_utc": dashboard.utc_stamp(data["generated_unix"]),
                           "days": axis[:-1], "daily": [{"day": d, "sessions": 1} for d in axis[:-2]] +
                           [{"day": "2027-01-19", "sessions": 99}]}
        overview = dashboard.overview_section(data, dashboard.ingest_rows(data), [])
        self.assertIn("Website days follow America/Bogota, 2027-01-12 to 2027-01-18", overview)
        self.assertIn('<div class="tl">Website sessions</div><div class="tv">7</div>', overview)
        self.assertIn("7/7 days observed", overview)

    def test_external_monitor_rejects_frozen_ok_and_source_failure(self):
        from datetime import datetime, timezone

        now = datetime.fromtimestamp(NOW, timezone.utc)
        stamp = dashboard.utc_stamp(NOW)
        report = {"built_utc": stamp, "status": "ok", "receiver_age_s": 300,
                  "sources": {key: {"status": "ok", "observed_utc": stamp}
                              for key in check_dashboard_health.SOURCE_MAX_AGE}}
        self.assertIsNone(check_dashboard_health.check(report, now, 7200))
        for difference in (-7201, 301):
            bad = {**report, "built_utc": dashboard.utc_stamp(NOW + difference)}
            self.assertIn("age", check_dashboard_health.check(bad, now, 7200))
        report["sources"]["github_downloads"]["status"] = "stale"
        self.assertIn("github_downloads=stale", check_dashboard_health.check(report, now, 7200))
        report["sources"]["website"]["observed_utc"] = dashboard.utc_stamp(NOW - 7201)
        self.assertIn("website=stale", check_dashboard_health.check(report, now, 7200))
        report["sources"].pop("website")
        with self.assertRaisesRegex(ValueError, "required source"):
            check_dashboard_health.check(report, now, 7200)

    def test_freshness_uses_build_clock_after_receiver_capture(self):
        stamp = dashboard.utc_stamp(NOW + 15 * 60)
        data = {"generated_unix": NOW, "github": {"collected_utc": stamp}}
        with unittest.mock.patch.object(dashboard.time, "time", return_value=NOW + 16 * 60):
            self.assertIn("<b>GitHub downloads</b> collected with this snapshot", dashboard.freshness_strip(data))

    def test_failed_health_publication_rolls_back_page(self):
        www = self.dir / "www"
        www.mkdir()
        index = www / "index.html"
        index.write_text("previous")
        write = dashboard.write_atomic

        def fail_health(path, value):
            if path.name == "health.json":
                raise OSError("cannot replace the report")
            write(path, value)

        with unittest.mock.patch.object(dashboard, "write_atomic", side_effect=fail_health):
            with self.assertRaisesRegex(OSError, "cannot replace"):
                dashboard.publish_page(www, "candidate", {"status": "ok"})
        self.assertEqual(index.read_text(), "previous")
        self.assertEqual(list(www.iterdir()), [index])

    def test_backup_requires_and_restores_archive(self):
        archive, copies = self.dir / "archive", self.dir / "copies"
        with unittest.mock.patch("sys.stdout"), unittest.mock.patch("sys.stderr"):
            self.assertEqual(backup_archive.main(archive, copies), 1)
            self.make_archive(archive)
            self.assertEqual(backup_archive.main(archive, copies), 0)
        (saved,) = copies.glob("*.sqlite3")
        saved.rename(copies / downloads.github_history.DATABASE_NAME)
        self.assertEqual(downloads.load(copies)["collected_utc"], downloads.load(archive)["collected_utc"])

    def test_build_refuses_directories_inside_the_repository(self):
        with self.assertRaises(SystemExit):
            dashboard.main(["build", "--receiver-snapshot", "x.json", "--www", str(HERE / "www"),
                            "--state-dir", str(self.dir)])

    def test_render_ga4_refreshes_the_saved_snapshot(self):
        import test_ga4
        data = snapshot.collect(self.config, NOW, days=7, weeks=1, floor=20)
        data["github"] = None
        path = self.dir / "dashboard.snapshot.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        with unittest.mock.patch.object(dashboard.ga4, "fetch", return_value=test_ga4.model()) as fetch, \
                unittest.mock.patch("sys.stdout"):
            dashboard.main(["render", "--snapshot", str(path), "--ga4", "--no-open", "--out",
                            str(self.dir / "page.html")])
        fetch.assert_called_once_with(7)
        self.assertEqual(json.loads(path.read_text(encoding="utf-8"))["website"]["property"], test_ga4.PROPERTY)
        self.assertIn("Active users, 7 days", (self.dir / "page.html").read_text(encoding="utf-8"))

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
        data["github"]["collected_utc"] = dashboard.utc_stamp(NOW - 60)
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
