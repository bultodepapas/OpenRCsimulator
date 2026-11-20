import io
import json
import os
import unittest
from contextlib import redirect_stderr, redirect_stdout
from hashlib import sha256

from openrc_telemetry import report
from openrc_telemetry.cli import main
from openrc_telemetry.contract import ContractError, load_contracts
from openrc_telemetry.storage import AggStore, StorageUnavailable

from .support import RELEASE, SCHEMA_DIR, TempDir, unix

WEEK = "2027-W02"      # 2027-01-11 .. 2027-01-17
contracts = load_contracts(SCHEMA_DIR)
NOW = unix("2027-01-18T02:00:00Z")


def gpu_row(family="nvidia_rtx", sessions=20, seconds=600, fps=60):
    intervals = sessions * seconds * fps
    # 60 FPS: every interval in bucket 1; 30 FPS: a 2:1 mix of buckets 2 and 3 around the 33.3 ms mean.
    histogram = ([0, intervals, 0, 0, 0, 0, 0, 0] if fps == 60
                 else [0, 0, intervals * 2 // 3, intervals // 3, 0, 0, 0, 0])
    return {"gpu_family": family, "session_observations": sessions,
            "interval_sum_us": sessions * seconds * 1_000_000,
            "rendered_frames": sessions * seconds * fps, "interval_histogram": histogram, "excluded_gap_count": 0}


class ReportCase(unittest.TestCase):
    def setUp(self):
        self._tmp = TempDir()
        self.dir = self._tmp.__enter__()
        self.agg = AggStore(self.dir / "aggregates.sqlite")

    def tearDown(self):
        self.agg.close()
        self._tmp.__exit__()

    def fill(self):
        put = lambda day, table, status, rows: self.agg.put_day(day, RELEASE, table, status, rows, NOW)  # noqa: E731
        put("2027-01-11", "gpu", "ready", [gpu_row(sessions=20, fps=60), gpu_row("amd_radeon", 25, fps=30)])
        put("2027-01-12", "gpu", "ready", [gpu_row(sessions=30, fps=60)])
        put("2027-01-13", "gpu", "suppressed", [])
        put("2027-01-14", "gpu", "no_data", [])
        put("2027-01-11", "vehicle", "ready", [{"vehicle_id": "f4u-corsair-250", "session_observations": 20,
                                                "activity_summaries": 40, "active_seconds": 7200}])
        put("2027-01-12", "vehicle", "ready", [{"vehicle_id": "f4u-corsair-250", "session_observations": 22,
                                                "activity_summaries": 22, "active_seconds": 3600}])
        put("2027-01-13", "vehicle", "suppressed", [])
        # 2027-01-15..17 never rolled up: missing.


class ReportTests(ReportCase):
    def test_weekly_pooling_and_wording(self):
        self.fill()
        title, body, digest = report.material(contracts, self.agg, WEEK, RELEASE)
        self.assertEqual(title, "OpenRC telemetry: 2027-W02 / v0.2.7 / weekly GPU and vehicle v2")
        self.assertTrue(body.startswith("<!-- openrc-telemetry:weekly-v2/2027-W02/v0.2.7 -->\n"))
        self.assertIn("contributing session-day observations", body.lower())
        self.assertIn("| nvidia_rtx | 50 | 60.00 | 0.0% | 0.0% | 0.00 |", body)
        self.assertIn("| amd_radeon | 25 | 30.00 | 33.3% | 0.0% | 0.00 |", body)
        self.assertIn("| f4u-corsair-250 | 42 | 62 | 3.00 |", body)
        self.assertIn("| 2027-01-13 | suppressed | suppressed |", body)
        self.assertIn("| 2027-01-14 | no_data | missing |", body)
        self.assertIn("| 2027-01-17 | missing | missing |", body)
        self.assertIn("Days with a published GPU table: 2 of 7", body)
        self.assertIn("not unique sessions, players, devices", body)

    def test_deterministic_and_digest_covers_title_and_body(self):
        self.fill()
        first = report.material(contracts, self.agg, WEEK, RELEASE)
        second = report.material(contracts, self.agg, WEEK, RELEASE)
        self.assertEqual(first, second)
        artifact = json.dumps({"title": first[0], "body": first[1]}, sort_keys=True, separators=(",", ":"),
                              ensure_ascii=False)
        self.assertEqual(first[2], sha256(artifact.encode("utf-8")).hexdigest())
        self.agg.put_day("2027-01-12", RELEASE, "gpu", "suppressed", [], NOW)
        self.assertNotEqual(report.material(contracts, self.agg, WEEK, RELEASE)[2], first[2])

    def test_empty_week_states_no_claims(self):
        _, body, _ = report.material(contracts, self.agg, WEEK, RELEASE)
        self.assertIn("No GPU cells are published. This status is not a claim of zero players or zero FPS.", body)
        self.assertIn("No vehicle cells are published.", body)
        self.assertIn("Days with a published GPU table: 0 of 7", body)

    def test_json_form_embeds_schema_valid_daily_reports(self):
        self.fill()
        data = report.collect(contracts, self.agg, WEEK, RELEASE)
        self.assertEqual(data["aggregation_scope"], "closed_week")
        self.assertEqual([d["gpu"] for d in data["days"]],
                         ["ready", "ready", "suppressed", "no_data", "missing", "missing", "missing"])
        self.assertEqual(data["gpu_rows"][0], {"gpu_family": "amd_radeon", "session_observations": 25,
                                               "interval_sum_us": 25 * 600_000_000,
                                               "rendered_frames": 25 * 600 * 30,
                                               "interval_histogram": [0, 0, 300000, 150000, 0, 0, 0, 0],
                                               "excluded_gap_count": 0})
        json.dumps(data)

    def test_implausible_daily_rows_are_refused(self):
        self.agg.put_day("2027-01-11", RELEASE, "gpu", "ready",
                         [{"gpu_family": "nvidia_rtx", "session_observations": 20, "interval_sum_us": 1,
                           "rendered_frames": 0, "interval_histogram": [1, 0, 0, 0, 0, 0, 0, 0],
                           "excluded_gap_count": 0}], NOW)
        with self.assertRaises(ContractError):
            report.material(contracts, self.agg, WEEK, RELEASE)

    def test_slow_frame_shares_come_from_the_summed_histogram(self):
        def row(sessions, histogram):
            return {"gpu_family": "nvidia_rtx", "session_observations": sessions,
                    "interval_sum_us": sessions * 600_000_000, "rendered_frames": sum(histogram),
                    "interval_histogram": histogram, "excluded_gap_count": 4}
        self.agg.put_day("2027-01-11", RELEASE, "gpu", "ready", [row(20, [0, 700000, 20000, 8000, 2000, 400, 90, 10])],
                         NOW)
        self.agg.put_day("2027-01-12", RELEASE, "gpu", "ready",
                         [row(30, [0, 1000000, 30000, 12000, 3000, 600, 140, 60])], NOW)
        cell = report.collect(contracts, self.agg, WEEK, RELEASE)["gpu_rows"][0]
        self.assertEqual(cell["interval_histogram"], [0, 1700000, 50000, 20000, 5000, 1000, 230, 70])
        self.assertEqual(cell["excluded_gap_count"], 8)
        _, body, _ = report.material(contracts, self.agg, WEEK, RELEASE)
        # 1,776,300 intervals: 26,300 over 33.3 ms (1.48%), 6,300 over 50 ms (0.35%), 1,300 over 100 ms in
        # 500 minutes (2.60 per minute); 1,776,300 frames / 30,000 s = 59.21 FPS.
        self.assertIn("| nvidia_rtx | 50 | 59.21 | 1.5% | 0.4% | 2.60 |", body)

    def test_vehicle_rows_that_bypassed_the_rollup_are_refused_at_publication(self):
        good = {"vehicle_id": "f4u-corsair-250", "session_observations": 20, "activity_summaries": 20,
                "active_seconds": 600}
        for broken in ({**good, "session_observations": 3, "activity_summaries": 3},   # small cell
                       {**good, "vehicle_id": "my-own|plane"},                          # not a stock id
                       {**good, "active_seconds": 20 * 1800 + 1},                       # implausible exposure
                       {**good, "activity_summaries": 20 * 120 + 1}):                   # over the per-token cap
            self.agg.put_day("2027-01-11", RELEASE, "vehicle", "ready", [broken], NOW)
            with self.assertRaises(ContractError):
                report.material(contracts, self.agg, WEEK, RELEASE)
        with self.assertRaises(StorageUnavailable):  # a duplicate cell is refused by the primary key at storage
            self.agg.put_day("2027-01-11", RELEASE, "vehicle", "ready", [good, good], NOW)
        self.agg.put_day("2027-01-11", RELEASE, "vehicle", "ready", [], NOW)
        with self.assertRaises(ContractError):  # "ready" with no rows is not a valid stored day
            report.material(contracts, self.agg, WEEK, RELEASE)

    def test_input_validation(self):
        for week in ("2027-W00", "2027-W54", "2027W02", "27-W02", "2027-W2", "", None):
            with self.assertRaises(ContractError, msg=week):
                report.parse_week(week)
        for release in ("0.2.7", "v1.2", "v0.2.7 ", "v0.2.7\n", "v0.2.7-gamma1"):
            with self.assertRaises(ContractError, msg=release):
                report.check_release(release)
        self.assertEqual(report.parse_week("2026-W53")[0].isoformat(), "2026-12-28")

    def test_week_closed_boundary(self):
        # Sunday 2027-01-17 can be rolled up until 2027-01-18T23:00Z; publication waits for that.
        self.assertFalse(report.week_closed(WEEK, unix("2027-01-18T22:59:59Z")))
        self.assertTrue(report.week_closed(WEEK, unix("2027-01-18T23:00:00Z")))


class ReportCliTests(ReportCase):
    def run_cli(self, *argv):
        os.environ["OPENRC_TELEMETRY_DATA_DIR"] = str(self.dir)
        os.environ["OPENRC_TELEMETRY_SCHEMA_DIR"] = str(SCHEMA_DIR)
        out, err = io.StringIO(), io.StringIO()
        try:
            with redirect_stdout(out), redirect_stderr(err):
                code = main(list(argv))
        finally:
            del os.environ["OPENRC_TELEMETRY_DATA_DIR"], os.environ["OPENRC_TELEMETRY_SCHEMA_DIR"]
        return code, out.getvalue(), err.getvalue()

    def test_report_command_prints_body_and_digest(self):
        self.fill()
        self.agg.close()
        code, out, err = self.run_cli("report", "--week", WEEK, "--release", RELEASE)
        self.assertEqual(code, 0)
        title, body, digest = report.material(contracts, AggStore(self.dir / "aggregates.sqlite"), WEEK, RELEASE)
        self.assertEqual(out, body)
        self.assertIn(f"digest: {digest}", err)
        code, out, _ = self.run_cli("report", "--week", WEEK, "--release", RELEASE, "--format", "json")
        self.assertEqual(json.loads(out), {"title": title, "body": body, "digest": digest})

    def test_report_command_rejects_bad_arguments(self):
        code, _, err = self.run_cli("report", "--week", "bad", "--release", RELEASE)
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
