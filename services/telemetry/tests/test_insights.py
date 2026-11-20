"""TELEM-16/17: unsuppressed daily cells, weekly per-cell disclosure and context tables; release prefixes."""
from __future__ import annotations

from datetime import date, timedelta
import hashlib
import io
import json
import unittest
from contextlib import redirect_stderr, redirect_stdout

from openrc_telemetry import insights
from openrc_telemetry.cli import main
from openrc_telemetry.config import Config, ReleasePatterns
from openrc_telemetry.contract import ContractError, load_contracts
from openrc_telemetry.rollup import gpu_report, run_rollup
from openrc_telemetry.storage import AggStore, RawStore

from .support import (CONTEXT, RELEASE, SCHEMA_DIR, TempDir, activity_event, batch, encode, perf_event, unix)

contracts = load_contracts(SCHEMA_DIR)
WEEK = "2027-W02"
MONDAY = date(2027, 1, 11)
AFTER_WEEK = unix("2027-01-20T00:00:00Z")  # Sunday + 47 h has passed
# A realistic small-cohort day: 60 sessions over six GPU families.
MIX = {"nvidia_rtx": 30, "amd_radeon": 12, "intel_integrated": 8, "apple_silicon": 6, "nvidia_gtx": 3, "software": 1}


class InsightsCase(unittest.TestCase):
    def setUp(self):
        self._tmp = TempDir()
        self.dir = self._tmp.__enter__()
        self.raw = RawStore(self.dir / "raw.sqlite")
        self.agg = AggStore(self.dir / "aggregates.sqlite")
        self.serial = 0
        self.session = 0

    def tearDown(self):
        self.raw.close()
        self.agg.close()
        self._tmp.__exit__()

    def put(self, payload, day):
        body = encode(payload)
        receipt = unix(f"{day.isoformat()}T12:00:00Z")
        self.assertEqual(self.raw.ingest(payload["batch_id"], hashlib.sha256(body).hexdigest(),
                                         payload["session_id"], [e["seq"] for e in payload["events"]], body,
                                         receipt), "accepted")

    def day_of_sessions(self, day, mix=MIX, events=None, context=None):
        for gpu, count in mix.items():
            for _ in range(count):
                self.serial += 1
                self.session += 1  # a fresh temporary token per session and day
                payload = batch(self.session, batch_id=self.serial, events=events, gpu=gpu)
                if context:
                    payload["context"].update(context)
                self.put(payload, day)

    def roll(self, day, releases=frozenset({RELEASE})):
        now = unix(f"{day.isoformat()}T00:00:00Z") + 26 * 3600
        return run_rollup(contracts, self.raw, self.agg, day.isoformat(), now, releases)

    def week(self, floor=20):
        return insights.collect(self.agg, WEEK, RELEASE, floor, now=AFTER_WEEK)


class DisclosureTests(InsightsCase):
    def test_small_cohort_day_now_publishes_where_the_whole_table_rule_published_nothing(self):
        day = MONDAY
        self.day_of_sessions(day)
        self.roll(day)
        # Before (daily whole-table rule): one small family suppresses everything.
        self.assertEqual(self.agg.get_day(day.isoformat(), RELEASE, "gpu"), ("suppressed", []))
        # After: the 30-session family is published, the five small ones are combined (12+8+6+3+1 = 30).
        table = self.week()["tables"]["flight_gpu"]
        self.assertEqual([row["dims"] for row in table["published"]], [["nvidia_rtx"]])
        self.assertEqual(table["combined"]["sessions"], 30)

    def test_a_week_pools_days_and_never_leaves_a_withheld_remainder(self):
        for offset in range(7):
            day = MONDAY + timedelta(days=offset)
            self.day_of_sessions(day)
            self.roll(day)
        data = self.week()
        table = data["tables"]["flight_gpu"]
        published = {row["dims"][0]: row["sessions"] for row in table["published"]}
        # The lone small cell (software, 7) is never shown alone and never left out: the smallest shown cell
        # (nvidia_gtx, 21) joins it in the combined row, so the table still adds up to its full population.
        self.assertEqual(published, {"nvidia_rtx": 210, "amd_radeon": 84, "intel_integrated": 56,
                                     "apple_silicon": 42})
        self.assertEqual(table["combined"]["sessions"], 28)
        self.assertEqual(sum(1 for d in data["days"] if d["status"] == "ready"), 7)
        body = insights.render(data)
        self.assertIn("| nvidia_rtx | 210 |", body)
        self.assertNotIn("software", body)
        self.assertNotIn("nvidia_gtx", body)
        self.assertIn("Operator-only report: do not publish", body)

    def test_every_table_adds_up_to_its_population_or_is_not_shown(self):
        mixes = [{"nvidia_rtx": 25, "software": 1}, {"amd_radeon": 19}, {"nvidia_gtx": 7, "intel_arc": 9},
                 {"apple_silicon": 30, "intel_integrated": 18, "other": 2}]
        for offset, mix in enumerate(mixes):
            self.day_of_sessions(MONDAY + timedelta(days=offset), mix)
            self.roll(MONDAY + timedelta(days=offset))
        pooled = insights._pool(sum((self.agg.get_cells((MONDAY + timedelta(days=d)).isoformat(), RELEASE)
                                     for d in range(len(mixes))), []))
        data = self.week()
        for table, cells in pooled.items():
            total = sum(entry["sessions"] for entry in cells.values())
            shown = data["tables"].get(table)
            if shown is None:
                self.assertLess(total, 20, table)
                continue
            rows = shown["published"] + ([shown["combined"]] if shown["combined"] else [])
            self.assertEqual(sum(row["sessions"] for row in rows), total, table)
            self.assertTrue(all(row["sessions"] >= 20 for row in rows), table)
            if shown["combined"]:
                self.assertGreaterEqual(len([1 for dims, e in cells.items()
                                             if [*dims] not in [r["dims"] for r in shown["published"]]]), 2, table)

    def test_one_forged_odd_batch_no_longer_hides_the_day(self):
        self.day_of_sessions(MONDAY, {"nvidia_rtx": 25})
        self.day_of_sessions(MONDAY, {"software": 1})  # e.g. a single forged batch
        self.roll(MONDAY)
        table = self.week()["tables"]["flight_gpu"]
        # The day is not hidden; the odd cell cannot be isolated: everything is shown as one combined row.
        self.assertEqual(table["published"], [])
        self.assertEqual(table["combined"]["sessions"], 26)

    def test_floor_bounds_and_private_label(self):
        self.day_of_sessions(MONDAY)
        self.roll(MONDAY)
        with self.assertRaises(ContractError):
            insights.collect(self.agg, WEEK, RELEASE, 9, now=AFTER_WEEK)
        data = self.week(floor=10)
        published = {row["dims"][0] for row in data["tables"]["flight_gpu"]["published"]}
        self.assertEqual(published, {"nvidia_rtx", "amd_radeon"})
        self.assertIn("Private floor 10", insights.render(data))
        self.assertNotIn("Private floor", insights.render(self.week()))


class ContextTablesTest(InsightsCase):
    def test_context_dimensions_usage_and_errors(self):
        events = [perf_event(1), activity_event(2, seconds=300),
                  {"name": "error_count", "seq": 3, "category": "asset_load_failed", "count": 2}]
        self.day_of_sessions(MONDAY, {"nvidia_rtx": 20}, events=events,
                             context={"vsync": "off", "fps_cap_bucket": "unlimited", "resolution_class": "1440p"})
        self.day_of_sessions(MONDAY, {"nvidia_rtx": 20}, events=[perf_event(1, mode="home", vehicle="none")])
        self.roll(MONDAY)
        tables = self.week()["tables"]
        rows = lambda t: {tuple(r["dims"]): r for r in tables[t]["published"]}  # noqa: E731
        self.assertEqual(rows("flight_pacing")[("unlimited",)]["sessions"], 20)
        self.assertEqual(insights.cap_class({"vsync": "on", "fps_cap_bucket": "unlimited"}), "vsync_or_fps_cap")
        self.assertEqual(insights.cap_class({"vsync": "off", "fps_cap_bucket": "121_plus"}), "vsync_or_fps_cap")
        self.assertEqual(insights.cap_class({"vsync": "unknown", "fps_cap_bucket": "unlimited"}), "unknown")
        self.assertEqual(rows("flight_resolution")[("1440p",)]["metrics"]["windows"], 20)
        self.assertIn(("windows", "opengl3"), rows("flight_platform"))
        self.assertEqual(rows("menus")[("home",)]["sessions"], 20)
        usage = rows("usage_vehicle")[("f4u-corsair-250",)]["metrics"]
        self.assertEqual((usage["summaries"], usage["active_seconds"], usage["takeoffs"]), (20, 6000, 20))
        self.assertEqual(rows("errors")[("asset_load_failed",)]["metrics"]["count"], 40)
        # v1 activity summaries carry no physics backend: they count as "unknown" in the v2 backend table.
        self.assertEqual(rows("usage_backend")[("f4u-corsair-250", "unknown")]["metrics"]["summaries"], 20)
        # Session mix counts every session once per cell, whatever events it sent.
        self.assertEqual(rows("mix_gpu")[("nvidia_rtx",)]["sessions"], 40)
        self.assertEqual(rows("mix_input")[(CONTEXT["input_class"],)]["sessions"], 40)
        body = insights.render(self.week())
        for heading in ("Flight frame cadence", "Vehicle usage", "Software errors", "Hardware and settings mix"):
            self.assertIn(heading, body)

    def test_v2_physics_backend_table(self):
        """Schema v2: one usage_backend cell per (vehicle, backend), capped per session like usage_vehicle."""
        def payload(session, backend):
            body = batch(session, events=[{**activity_event(1), "physics_backend": backend}])
            body.update(schema_version=2, notice_version="2026-11-20")
            return body
        payloads = [payload(i, "native") for i in range(1, 4)] + [payload(9, "reference_stale")]
        cells = {(t, d): (sessions, m) for t, d, sessions, m in insights.daily_cells(payloads)}
        self.assertEqual(cells[("usage_backend", ("f4u-corsair-250", "native"))][0], 3)
        self.assertEqual(cells[("usage_backend", ("f4u-corsair-250", "reference_stale"))][1]["summaries"], 1)
        self.assertEqual(cells[("usage_vehicle", ("f4u-corsair-250",))][1]["summaries"], 4)
        for (table, dims), (sessions, metrics) in cells.items():
            insights.validate_cell(table, dims, sessions, metrics)

    def test_cells_hold_no_identifiers_and_rollup_is_idempotent(self):
        self.day_of_sessions(MONDAY, {"nvidia_rtx": 20})
        self.roll(MONDAY)
        first = self.agg.get_cells(MONDAY.isoformat(), RELEASE)
        self.roll(MONDAY)
        self.assertEqual(self.agg.get_cells(MONDAY.isoformat(), RELEASE), first)
        with self.agg.connection() as conn:
            dump = "\n".join(conn.iterdump())
        self.assertNotIn(batch(1)["session_id"], dump)
        self.assertNotIn(batch(1, batch_id=1)["batch_id"], dump)

    def test_corrupt_stored_cells_are_refused(self):
        self.day_of_sessions(MONDAY, {"nvidia_rtx": 20})
        self.roll(MONDAY)
        with self.agg.transaction() as conn:
            conn.execute("UPDATE daily_cells SET dims='[\"Robert; DROP\"]' WHERE tbl='mix_gpu'")
        with self.assertRaises(ContractError):
            self.week()

    def test_gpu_report_public_daily_form_is_unchanged(self):
        # The daily whole-table form stays the conservative public form and keeps reference equivalence.
        self.day_of_sessions(MONDAY, {"nvidia_rtx": 20})
        self.roll(MONDAY)
        self.assertEqual(self.agg.get_day(MONDAY.isoformat(), RELEASE, "gpu")[0], "ready")
        self.assertTrue(callable(gpu_report))

    def test_cli_json_and_markdown(self):
        self.day_of_sessions(MONDAY, {"nvidia_rtx": 20})
        self.roll(MONDAY)
        env = {"OPENRC_TELEMETRY_DATA_DIR": str(self.dir), "OPENRC_TELEMETRY_SCHEMA_DIR": str(SCHEMA_DIR)}
        import os
        saved = {k: os.environ.get(k) for k in env}
        os.environ.update(env)
        try:
            out, err = io.StringIO(), io.StringIO()
            with redirect_stdout(out), redirect_stderr(err):
                code = main(["insights", "--week", WEEK, "--release", RELEASE, "--format", "json"])
            self.assertEqual(code, 0)
            payload = json.loads(out.getvalue())
            self.assertEqual(payload["data"]["tables"]["flight_gpu"]["published"][0]["sessions"], 20)
            self.assertEqual(len(payload["digest"]), 64)
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value


class ReleasePatternTests(unittest.TestCase):
    def test_prefixes_match_a_series_only(self):
        allowed = ReleasePatterns({"v0.3.*", "v0.2.9"})
        for tag in ("v0.3.0", "v0.3.12", "v0.3.0-beta.1", "v0.2.9"):
            self.assertIn(tag, allowed)
        for tag in ("v0.4.0", "v0.2.10", "v0.30.0", None):
            self.assertNotIn(tag, allowed)
        self.assertIn("v0.3.1", allowed | ReleasePatterns())
        self.assertIn("v0.3.1", frozenset() | allowed)  # reflected union keeps prefixes

    def test_bad_patterns_refuse_to_start(self):
        for value in ("*", "v*", "v0.3*", "0.3.*", "v0.3.1.*"):
            with self.assertRaises(SystemExit):
                Config.from_env({"OPENRC_TELEMETRY_RELEASES": value})
        config = Config.from_env({"OPENRC_TELEMETRY_RELEASES": "v0.3.*, v0.2.9"})
        self.assertIn("v0.3.7", config.releases)

    def test_ingest_and_check_release_honour_prefixes(self):
        from starlette.testclient import TestClient
        from openrc_telemetry.cli import check_release_tag
        from openrc_telemetry.ingress import create_app
        from .support import FIXTURE, make_config
        with TempDir() as directory:
            config = make_config(directory, releases=ReleasePatterns({"v0.2.*"}))
            client = TestClient(create_app(config))
            response = client.post("/v1/batches", content=encode(batch(1, release="v0.2.7")),
                                   headers={"Content-Type": "application/json"})
            self.assertEqual(response.status_code, 202)
            response = client.post("/v1/batches", content=encode(batch(2, release="v0.3.0")),
                                   headers={"Content-Type": "application/json"})
            self.assertEqual(response.status_code, 422)
            self.assertEqual(check_release_tag(config, "v0.2.11", FIXTURE)[0], True)
            self.assertEqual(check_release_tag(config, "v0.3.0", FIXTURE)[0], False)


if __name__ == "__main__":
    unittest.main()
