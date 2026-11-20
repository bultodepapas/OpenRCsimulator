import hashlib
import unittest

from openrc_telemetry.cli import main
from openrc_telemetry.contract import ContractError, load_contracts
from openrc_telemetry.rollup import (aggregate_daily_gpu, check_eligible, eligibility_window, run_rollup,
                                     utc_iso)
from openrc_telemetry.storage import AggStore, RawStore

from .support import (RELEASE, SCHEMA_DIR, TempDir, activity_event, batch, encode, perf_event, unix)

DAY = "2027-01-14"           # Thursday, ISO week 2027-W02
START = unix("2027-01-14T00:00:00Z")
ROLL_NOW = START + 26 * 3600
contracts = load_contracts(SCHEMA_DIR)


class RollupCase(unittest.TestCase):
    def setUp(self):
        self._tmp = TempDir()
        self.dir = self._tmp.__enter__()
        self.raw = RawStore(self.dir / "raw.sqlite")
        self.agg = AggStore(self.dir / "aggregates.sqlite")
        self.batch_serial = 0

    def tearDown(self):
        self.raw.close()
        self.agg.close()
        self._tmp.__exit__()

    def put(self, payload, receipt=None):
        body = encode(payload)
        outcome = self.raw.ingest(payload["batch_id"], hashlib.sha256(body).hexdigest(), payload["session_id"],
                                  [e["seq"] for e in payload["events"]], body,
                                  receipt if receipt is not None else START + 3600)
        self.assertEqual(outcome, "accepted")

    def sessions(self, count, first, events=None, **kwargs):
        for session in range(first, first + count):
            self.batch_serial += 1
            self.put(batch(session, batch_id=self.batch_serial, events=events, **kwargs))

    def roll(self, now=ROLL_NOW, releases=frozenset({RELEASE})):
        return run_rollup(contracts, self.raw, self.agg, DAY, now, releases)

    def table(self, table, release=RELEASE):
        return self.agg.get_day(DAY, release, table)


class GpuTests(RollupCase):
    def test_suppressed_at_19_tokens_and_published_at_20(self):
        self.sessions(19, 1)
        self.roll()
        self.assertEqual(self.table("gpu"), ("suppressed", []))
        self.sessions(1, 100)
        self.roll()
        status, rows = self.table("gpu")
        self.assertEqual(status, "ready")
        self.assertEqual(rows, [{"gpu_family": "nvidia_rtx", "session_observations": 20,
                                 "interval_sum_us": 20 * 30_000_000, "rendered_frames": 20 * 1800,
                                 "interval_histogram": [0, 20 * 1800, 0, 0, 0, 0, 0, 0], "excluded_gap_count": 0}])

    def test_histogram_and_gap_counts_are_summed_per_cell(self):
        mixed = [0, 1700, 60, 30, 8, 2, 0, 0]
        self.sessions(20, 1, events=[perf_event(1, histogram=mixed, gaps=3), perf_event(2, gaps=1)])
        self.roll()
        status, rows = self.table("gpu")
        self.assertEqual(status, "ready")
        self.assertEqual(rows[0]["interval_histogram"], [0, 70000, 1200, 600, 160, 40, 0, 0])
        self.assertEqual(rows[0]["excluded_gap_count"], 80)
        self.assertEqual(sum(rows[0]["interval_histogram"]), 20 * 2 * 1800)

    def test_one_small_cell_suppresses_the_whole_table(self):
        self.sessions(25, 1, gpu="nvidia_rtx")
        self.sessions(19, 100, gpu="amd_radeon")
        self.roll()
        self.assertEqual(self.table("gpu"), ("suppressed", []))

    def test_cells_are_pooled_across_channels_within_a_release(self):
        self.sessions(10, 1)
        for number in range(10):
            payload = batch(100 + number, batch_id=500 + number)
            payload["build"]["channel"] = "preview"
            self.put(payload)
        self.roll()
        self.assertEqual(self.table("gpu")[1][0]["session_observations"], 20)

    def test_120_window_cap_per_session_token(self):
        self.sessions(19, 1)
        # One token sending 130 eligible windows over nine batches.
        seq = 0
        for chunk in range(9):
            events = []
            for _ in range(16 if chunk < 8 else 2):
                seq += 1
                events.append(perf_event(seq))
            self.batch_serial += 1
            self.put(batch(777, batch_id=self.batch_serial, events=events))
        self.assertEqual(seq, 130)
        self.roll()
        status, rows = self.table("gpu")
        self.assertEqual(status, "ready")
        self.assertEqual(rows[0]["session_observations"], 20)
        self.assertEqual(rows[0]["interval_sum_us"], (19 + 120) * 30_000_000)
        self.assertEqual(rows[0]["rendered_frames"], (19 + 120) * 1800)
        self.assertEqual(rows[0]["interval_histogram"], [0, (19 + 120) * 1800, 0, 0, 0, 0, 0, 0])

    def test_only_complete_observed_steady_flight_windows_count(self):
        ignored = [
            perf_event(1, complete=False, sum_us=20_000_000),
            perf_event(2, mode="home"),
            perf_event(3, phase="warmup"),
            perf_event(4, draws="unavailable"),
            activity_event(5),
        ]
        self.sessions(30, 1, events=ignored)
        self.roll()
        self.assertEqual(self.table("gpu"), ("no_data", []))
        self.sessions(1, 200)
        self.roll()
        self.assertEqual(self.table("gpu")[0], "suppressed")  # one token < 20

    def test_exactly_30_second_window_counts_and_floor_is_enforced_on_complete_claims(self):
        short = batch(1, events=[perf_event(1, sum_us=29_999_999)])
        with self.assertRaises(ContractError):
            contracts.validate_body(encode(short))
        self.sessions(20, 1, events=[perf_event(1, sum_us=30_000_000)])
        self.roll()
        self.assertEqual(self.table("gpu")[0], "ready")

    def test_identical_rerun_is_idempotent(self):
        self.sessions(20, 1)
        first = self.roll()
        stored = self.table("gpu")
        self.assertEqual(self.roll(ROLL_NOW + 600), first)
        self.assertEqual(self.table("gpu"), stored)
        with self.agg.connection() as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM daily_gpu").fetchone()[0], 1)

    def test_releases_are_separate_and_allowlisted_empty_release_is_no_data(self):
        self.sessions(20, 1)
        self.sessions(5, 100, release="v0.2.8")
        results = self.roll(releases=frozenset({RELEASE, "v0.3.0"}))
        self.assertEqual({r[0] for r in results}, {"v0.2.7", "v0.2.8", "v0.3.0"})
        self.assertEqual(self.table("gpu")[0], "ready")
        self.assertEqual(self.table("gpu", "v0.2.8")[0], "suppressed")
        self.assertEqual(self.table("gpu", "v0.3.0"), ("no_data", []))

    def test_days_use_trusted_receipt_day(self):
        self.sessions(20, 1)
        for number in range(30):
            self.put(batch(900 + number, batch_id=900 + number), receipt=START - 60)  # previous day
        self.roll()
        self.assertEqual(self.table("gpu")[1][0]["session_observations"], 20)


class VehicleTests(RollupCase):
    def test_counts_and_active_seconds_per_vehicle(self):
        self.sessions(20, 1, events=[perf_event(1), activity_event(2, seconds=600), activity_event(3, seconds=300)])
        self.sessions(20, 100, events=[activity_event(1, vehicle="p51d-mustang-120", seconds=60)])
        self.roll()
        status, rows = self.table("vehicle")
        self.assertEqual(status, "ready")
        self.assertEqual(rows, [
            {"vehicle_id": "f4u-corsair-250", "session_observations": 20, "activity_summaries": 40,
             "active_seconds": 20 * 900},
            {"vehicle_id": "p51d-mustang-120", "session_observations": 20, "activity_summaries": 20,
             "active_seconds": 1200},
        ])

    def test_vehicle_table_suppressed_at_19_tokens(self):
        self.sessions(20, 1, events=[activity_event(1)])
        self.sessions(19, 100, events=[activity_event(1, vehicle="p51d-mustang-120")])
        self.roll()
        self.assertEqual(self.table("vehicle"), ("suppressed", []))
        self.assertEqual(self.table("gpu"), ("no_data", []))
        self.sessions(1, 200, events=[activity_event(1, vehicle="p51d-mustang-120")])
        self.roll()
        self.assertEqual(self.table("vehicle")[0], "ready")

    def test_vehicle_floor_cannot_be_lowered_and_custom_rows_count_like_stock(self):
        from openrc_telemetry.rollup import vehicle_report
        with self.assertRaises(ContractError):
            vehicle_report([], "2027-01-11", RELEASE, "2027-W02", minimum=1)
        custom = {**activity_event(1, vehicle="custom"), "classification": "unsupported",
                  "takeoffs": None, "landings": None, "aircraft_crashes": None}
        self.sessions(20, 1, events=[custom])
        self.roll()
        status, rows = self.table("vehicle")
        self.assertEqual((status, [r["vehicle_id"] for r in rows]), ("ready", ["custom"]))

    def test_vehicle_table_has_no_identifiers(self):
        self.sessions(20, 1, events=[activity_event(1)])
        self.roll()
        with self.agg.connection() as conn:
            dump = "\n".join(str(row) for table in ("daily_status", "daily_gpu", "daily_vehicle")
                             for row in conn.execute(f"SELECT * FROM {table}"))
        self.assertNotIn("0000000000000000000000000000", dump)


class EligibilityTests(RollupCase):
    def test_closed_and_expired_days_are_refused(self):
        self.sessions(20, 1)
        for refused in (START + 25 * 3600 - 1, START + 47 * 3600, START + 48 * 3600, START - 3600):
            with self.assertRaises(ContractError, msg=refused) as caught:
                self.roll(refused)
            self.assertEqual(str(caught.exception), "day_not_eligible")
        self.assertIsNone(self.table("gpu"))
        # gpu, vehicle and the TELEM-16/17 insight cells
        self.assertEqual(len(self.roll(START + 25 * 3600)), 3)
        self.assertEqual(len(self.roll(START + 47 * 3600 - 1)), 3)

    def test_bad_day_strings(self):
        for bad in ("2027-1-14", "2027-02-30", "yesterday", "", "2027-01-14T00:00"):
            with self.assertRaises(ContractError):
                check_eligible(bad, utc_iso(ROLL_NOW))

    def test_window_helper(self):
        start, end = eligibility_window(DAY)
        self.assertEqual((start.hour, start.day, end.hour, end.day), (1, 15, 23, 15))

    def test_cli_refuses_with_message(self):
        import io
        import os
        from contextlib import redirect_stderr
        os.environ["OPENRC_TELEMETRY_DATA_DIR"] = str(self.dir)
        os.environ["OPENRC_TELEMETRY_SCHEMA_DIR"] = str(SCHEMA_DIR)
        err = io.StringIO()
        try:
            with redirect_stderr(err):
                code = main(["rollup", "--day", "2999-01-01"])
        finally:
            del os.environ["OPENRC_TELEMETRY_DATA_DIR"], os.environ["OPENRC_TELEMETRY_SCHEMA_DIR"]
        self.assertEqual(code, 2)
        self.assertIn("can be rolled up from 2999-01-02T01:00:00+00:00 until 2999-01-02T23:00:00+00:00", err.getvalue())


class ReducerApiTests(RollupCase):
    def test_aggregate_daily_gpu_matches_reference_signature_semantics(self):
        records = [(DAY, encode(batch(n, batch_id=n))) for n in range(1, 21)]
        report = aggregate_daily_gpu(contracts, records, DAY, RELEASE, as_of_utc="2027-01-15T02:00:00Z")
        self.assertEqual(report["status"], "ready")
        self.assertEqual(report["period"], "2027-W02")
        with self.assertRaises(ContractError):
            aggregate_daily_gpu(contracts, records, DAY, RELEASE, minimum=19, as_of_utc="2027-01-15T02:00:00Z")
        with self.assertRaises(ContractError):
            aggregate_daily_gpu(contracts, records, DAY, RELEASE, as_of_utc="2027-01-14T23:59:59Z")
        with self.assertRaises(ContractError):
            aggregate_daily_gpu(contracts, [("2027-01-13", records[0][1])], DAY, RELEASE,
                                as_of_utc="2027-01-15T02:00:00Z")


if __name__ == "__main__":
    unittest.main()
