import hashlib
import json
import os
import sqlite3
import unittest
from unittest.mock import Mock, call, patch

from openrc_telemetry.cli import main
from openrc_telemetry.storage import AggStore, RawStore, StorageUnavailable, utc_day

from .support import TempDir, batch, encode, hex32

DAY = 86400
NOW = 1_800_000_000


def put(store, number, receipt, events=(1,), session=None):
    payload = batch(session if session is not None else number, batch_id=number)
    body = encode(payload)
    return store.ingest(payload["batch_id"], hashlib.sha256(body).hexdigest(),
                        payload["session_id"], list(events), body, receipt)


class RawStoreTests(unittest.TestCase):
    def setUp(self):
        self._tmp = TempDir()
        self.dir = self._tmp.__enter__()
        self.store = RawStore(self.dir / "raw.sqlite")

    def tearDown(self):
        self.store.close()
        self._tmp.__exit__()

    def test_pragmas_and_constraints(self):
        with self.store.connection() as conn:
            self.assertEqual(conn.execute("PRAGMA journal_mode").fetchone()[0], "wal")
            self.assertEqual(conn.execute("PRAGMA synchronous").fetchone()[0], 2)  # FULL
            self.assertEqual(conn.execute("PRAGMA secure_delete").fetchone()[0], 1)
            self.assertEqual(conn.execute("PRAGMA auto_vacuum").fetchone()[0], 2)  # INCREMENTAL
            columns = [r[1] for r in conn.execute("PRAGMA table_info(batches)")]
        self.assertEqual(columns, ["batch_id", "body_sha256", "session_id", "receipt_unix", "receipt_day", "body"])

    def test_dedup_and_conflict_come_from_constraints(self):
        self.assertEqual(put(self.store, 1, NOW), "accepted")
        self.assertEqual(put(self.store, 1, NOW + 5), "duplicate")
        # Same session/seq, different batch id.
        self.assertEqual(put(self.store, 2, NOW, session=1), "conflict")
        with self.store.connection() as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM batches").fetchone()[0], 1)
            self.assertEqual(conn.execute("SELECT count(*) FROM events").fetchone()[0], 1)

    def test_duplicate_does_not_extend_expiry(self):
        put(self.store, 1, NOW)
        put(self.store, 1, NOW + 40 * 3600)
        self.assertEqual(self.store.oldest_receipt(), NOW)

    def test_purge_boundary_is_exactly_48_hours(self):
        put(self.store, 1, NOW)                       # age exactly 48 h at purge time
        put(self.store, 2, NOW + 1)                   # age 47 h 59 m 59 s
        purge_at = NOW + 48 * 3600
        result = self.store.purge(purge_at)
        self.assertEqual(result["deleted_batches"], 1)
        self.assertEqual(self.store.count(), 1)
        with self.store.connection() as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM events").fetchone()[0], 1)
        self.assertEqual(self.store.purge(purge_at)["deleted_batches"], 0)   # idempotent
        self.assertEqual(self.store.purge(purge_at + 1)["deleted_batches"], 1)
        self.assertEqual(self.store.count(), 0)

    def test_purge_frees_dedup_keys_and_overwrites_bytes(self):
        canary_session = "c0ffee" * 5 + "ab"
        payload = batch(1, batch_id=5)
        payload["session_id"] = canary_session
        body = encode(payload)
        self.store.ingest(payload["batch_id"], "e" * 64, canary_session, [1], body, NOW)
        raw_file = self.dir / "raw.sqlite"
        self.assertIn(canary_session.encode(), raw_file.read_bytes() + (self.dir / "raw.sqlite-wal").read_bytes())
        self.store.purge(NOW + 48 * 3600)
        wal = self.dir / "raw.sqlite-wal"
        residue = raw_file.read_bytes() + (wal.read_bytes() if wal.exists() else b"")
        self.assertNotIn(canary_session.encode(), residue)
        self.assertNotIn(b"performance_window", residue)
        self.assertEqual(wal.stat().st_size if wal.exists() else 0, 0)
        # The deadline also ended dedup protection: the same identity is accepted again.
        self.assertEqual(self.store.ingest(payload["batch_id"], "e" * 64, canary_session, [1], body, NOW + 49 * 3600),
                         "accepted")

    def test_records_for_day_in_ingestion_order(self):
        for number in (3, 1, 2):
            put(self.store, number, NOW)
        records = self.store.records_for_day(utc_day(NOW))
        self.assertEqual([r[0] for r in records], [utc_day(NOW)] * 3)
        self.assertEqual([json.loads(r[1])["batch_id"] for r in records], [hex32(3), hex32(1), hex32(2)])
        self.assertEqual(self.store.records_for_day("1999-01-01"), [])

    def test_unavailable_storage_raises(self):
        broken = RawStore(self.dir / "nodir" / "x" / "raw.sqlite")
        (self.dir / "nodir").write_text("file")
        with self.assertRaises(StorageUnavailable):
            broken.count()

    def test_read_only_store_does_not_change_an_unrelated_sqlite_database(self):
        path = self.dir / "unrelated #+.sqlite"
        conn = sqlite3.connect(path)
        conn.execute("CREATE TABLE unrelated(value TEXT)")
        conn.close()
        before = path.read_bytes()
        reader = RawStore(path, read_only=True)
        try:
            with self.assertRaises(StorageUnavailable):
                reader.count()
        finally:
            reader.close()
        self.assertEqual(path.read_bytes(), before)
        self.assertFalse(path.with_name(path.name + "-wal").exists())


class AggStoreTests(unittest.TestCase):
    def setUp(self):
        self._tmp = TempDir()
        self.dir = self._tmp.__enter__()
        self.store = AggStore(self.dir / "aggregates.sqlite")

    def tearDown(self):
        self.store.close()
        self._tmp.__exit__()

    def test_has_no_identifier_columns(self):
        with self.store.connection() as conn:
            names = {row[1] for table in ("daily_status", "daily_gpu", "daily_vehicle")
                     for row in conn.execute(f"PRAGMA table_info({table})")}
        self.assertFalse({"session_id", "batch_id"} & names)

    def test_an_aggregates_file_from_before_the_histogram_columns_is_refused(self):
        path = self.dir / "old.sqlite"
        legacy = sqlite3.connect(str(path))
        legacy.execute("CREATE TABLE daily_gpu(day TEXT NOT NULL, release_id TEXT NOT NULL, gpu_family TEXT NOT NULL, "
                       "session_observations INTEGER NOT NULL, interval_sum_us INTEGER NOT NULL, "
                       "rendered_frames INTEGER NOT NULL, PRIMARY KEY(day, release_id, gpu_family)) WITHOUT ROWID")
        legacy.commit()
        legacy.close()
        old = AggStore(path)
        try:
            with self.assertRaises(StorageUnavailable):
                old.get_day("2027-01-14", "v0.2.7", "gpu")
        finally:
            old.close()

    def test_put_day_is_an_idempotent_replace(self):
        row = {"gpu_family": "nvidia_rtx", "session_observations": 20, "interval_sum_us": 600_000_000,
               "rendered_frames": 36000, "interval_histogram": [0, 35000, 800, 150, 40, 8, 2, 0],
               "excluded_gap_count": 7}
        self.store.put_day("2027-01-14", "v0.2.7", "gpu", "ready", [row], NOW)
        self.store.put_day("2027-01-14", "v0.2.7", "gpu", "ready", [row], NOW + 1)
        self.assertEqual(self.store.get_day("2027-01-14", "v0.2.7", "gpu"), ("ready", [row]))
        self.store.put_day("2027-01-14", "v0.2.7", "gpu", "suppressed", [], NOW + 2)
        self.assertEqual(self.store.get_day("2027-01-14", "v0.2.7", "gpu"), ("suppressed", []))
        self.assertIsNone(self.store.get_day("2027-01-15", "v0.2.7", "gpu"))

    def test_aggregates_expire_after_180_days(self):
        self.store.put_day("2026-07-18", "v0.2.7", "gpu", "no_data", [], NOW)
        self.store.put_day("2026-07-19", "v0.2.7", "gpu", "no_data", [], NOW)
        today = NOW + 1800  # 2027-01-15; cutoff is 180 days earlier = 2026-07-19
        self.assertEqual(self.store.purge(today)["deleted_aggregate_rows"], 1)
        self.assertIsNone(self.store.get_day("2026-07-18", "v0.2.7", "gpu"))
        self.assertIsNotNone(self.store.get_day("2026-07-19", "v0.2.7", "gpu"))

    def test_read_only_view_reads_live_wal_and_holds_a_committed_snapshot(self):
        day = "2027-01-14"
        self.store.add_ingest_counts([(day, "accepted", 1)])
        reader = AggStore(self.store.path, read_only=True)
        try:
            with reader.read_snapshot():
                self.assertEqual(reader.ingest_counts(day), {"accepted": 1})
                self.store.add_ingest_counts([(day, "accepted", 2)])
                self.store.put_rollup(day, {}, NOW)
                self.assertEqual(reader.rollup_commits(), {})
                self.assertEqual(reader.ingest_counts(day), {"accepted": 1})
            self.assertEqual(reader.rollup_commits(), {day: 0})
            self.assertEqual(reader.ingest_counts(day), {"accepted": 3})
            with self.assertRaises(StorageUnavailable):
                reader.add_ingest_counts([(day, "accepted", 1)])
            self.assertEqual(self.store.ingest_counts(day), {"accepted": 3})
        finally:
            reader.close()

    def test_read_only_legacy_store_does_not_create_the_missing_commit_table(self):
        day = "2027-01-14"
        self.store.put_day(day, "v0.2.7", "gpu", "ready", [], NOW)
        with self.store.connection() as conn:
            conn.execute("DROP TABLE daily_rollup")
        reader = AggStore(self.store.path, read_only=True)
        try:
            self.assertEqual(reader.rollup_commits(), {})
            self.assertEqual(reader.day_statuses(day), {"v0.2.7/gpu": "ready"})
        finally:
            reader.close()
        with self.store.connection() as conn:
            self.assertIsNone(conn.execute("SELECT 1 FROM sqlite_master WHERE name='daily_rollup'").fetchone())


class PurgeCliTests(unittest.TestCase):
    def test_automatic_purge_reports_busy_wal_and_retries_promptly(self):
        from openrc_telemetry.cli import PURGE_RETRY_S, _purge_loop
        from .support import make_config
        with TempDir() as directory:
            config = make_config(directory)
            raw, agg = RawStore(config.raw_path), AggStore(config.aggregates_path)
            reader = RawStore(config.raw_path, read_only=True)
            try:
                self.assertEqual(put(raw, 1, NOW), "accepted")
                with raw.connection() as conn:
                    conn.execute("PRAGMA busy_timeout=0")
                with reader.read_snapshot():
                    self.assertEqual(reader.count(), 1)
                    stop = Mock()
                    # End the reader snapshot when the short retry is scheduled.
                    def wait(delay):
                        if delay == PURGE_RETRY_S:
                            reader.close()
                        return stop.wait.call_count == 3
                    stop.wait.side_effect = wait
                    with patch("openrc_telemetry.cli.time.time", return_value=NOW + 48 * 3600):
                        with self.assertLogs("openrc_telemetry", level="WARNING") as logs:
                            _purge_loop(config, raw, agg, stop, config.purge_interval_s)
                    self.assertEqual(stop.wait.call_args_list, [call(config.purge_interval_s),
                                                               call(PURGE_RETRY_S), call(config.purge_interval_s)])
                    self.assertEqual(logs.output, ["WARNING:openrc_telemetry:purge category=checkpoint_busy"])
                self.assertEqual(raw.count(), 0)
                wal = config.raw_path.with_name("raw.sqlite-wal")
                self.assertEqual(wal.stat().st_size if wal.exists() else 0, 0)
            finally:
                reader.close()
                raw.close()
                agg.close()

    def test_purge_command_runs_against_data_dir(self):
        with TempDir() as directory:
            os.environ["OPENRC_TELEMETRY_DATA_DIR"] = str(directory)
            try:
                self.assertEqual(main(["purge"]), 0)
            finally:
                del os.environ["OPENRC_TELEMETRY_DATA_DIR"]
            self.assertTrue((directory / "raw.sqlite").exists())
            self.assertTrue((directory / "aggregates.sqlite").exists())

    def test_purge_interval_cannot_delete_rows_before_their_day_closes_for_rollup(self):
        from openrc_telemetry.config import Config
        from openrc_telemetry.cli import purge_margin_s
        for bad in ("29", "1801", "3600"):
            with self.assertRaises(SystemExit):
                Config.from_env({"OPENRC_TELEMETRY_PURGE_INTERVAL_S": bad})
        widest = Config.from_env({"OPENRC_TELEMETRY_PURGE_INTERVAL_S": "1800"})
        # The earliest serve purge (48 h minus the margin) still comes after the 47 h rollup deadline.
        self.assertGreater(48 * 3600 - purge_margin_s(widest), 47 * 3600)

    def test_serve_purge_cuts_early_enough_that_no_row_outlives_48_hours(self):
        from openrc_telemetry.cli import purge_margin_s, purge_once
        from .support import make_config
        with TempDir() as directory:
            config = make_config(directory, purge_interval_s=300)
            raw, agg = RawStore(config.raw_path), AggStore(config.aggregates_path)
            try:
                self.assertEqual(put(raw, 1, NOW), "accepted")
                margin = purge_margin_s(config)
                self.assertGreater(margin, config.purge_interval_s)
                # The last purge before the row's 48 h deadline happens at most one interval earlier; it must delete it.
                last_purge = NOW + 48 * 3600 - config.purge_interval_s
                self.assertEqual(purge_once(config, last_purge - 1, raw, agg, margin)["deleted_batches"], 1)
            finally:
                raw.close()
                agg.close()


if __name__ == "__main__":
    unittest.main()
