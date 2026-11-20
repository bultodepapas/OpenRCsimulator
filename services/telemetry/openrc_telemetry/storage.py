"""SQLite storage: a short-lived raw database and a separate ID-free aggregate database.

The raw file holds batches and session/seq dedup keys for at most 48 hours and must never be
backed up. The aggregate file never contains a session_id or batch_id.
"""
from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import sqlite3
import threading

RAW_TTL = 48 * 3600
AGGREGATE_DAYS = 180


class StorageUnavailable(Exception):
    """Storage cannot durably commit right now (maps to HTTP 503)."""


def utc_day(unix):
    return datetime.fromtimestamp(int(unix), tz=timezone.utc).strftime("%Y-%m-%d")


class _Conflict(Exception):
    """Internal: overlapping session/seq; aborts the transaction."""


class _Db:
    """One lazily opened connection guarded by a lock; reconnects after an error."""

    pragmas = ()
    schema = ""
    incremental_vacuum = False

    def __init__(self, path):
        self.path = Path(path)
        self._conn = None
        self._lock = threading.RLock()

    def _connect(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fresh = not self.path.exists()
        conn = sqlite3.connect(str(self.path), timeout=5.0, isolation_level=None, check_same_thread=False)
        try:
            if self.incremental_vacuum:
                # Must precede the first table so freed pages can be released later.
                conn.execute("PRAGMA auto_vacuum=INCREMENTAL")
            conn.execute("PRAGMA journal_mode=WAL")
            for pragma in self.pragmas:
                conn.execute(pragma)
            conn.executescript(self.schema)
            self._verify(conn)
        except (sqlite3.Error, StorageUnavailable):
            conn.close()
            raise
        if fresh:
            try:
                os.chmod(self.path, 0o600)
            except OSError:
                pass
        return conn

    def _verify(self, conn):
        """Run after the schema script; a store may refuse a file from an older layout."""

    def _get(self):
        if self._conn is None:
            self._conn = self._connect()
        return self._conn

    def close(self):
        with self._lock:
            if self._conn is not None:
                try:
                    self._conn.close()
                finally:
                    self._conn = None

    @contextmanager
    def connection(self):
        """Locked connection; any sqlite error drops it and raises StorageUnavailable."""
        with self._lock:
            try:
                yield self._get()
            except (sqlite3.Error, OSError):
                self.close()
                raise StorageUnavailable("storage") from None

    @contextmanager
    def transaction(self):
        with self._lock:
            try:
                conn = self._get()
                conn.execute("BEGIN IMMEDIATE")
                try:
                    yield conn
                except BaseException:
                    conn.execute("ROLLBACK")
                    raise
                conn.execute("COMMIT")
            except (sqlite3.Error, OSError):
                self.close()
                raise StorageUnavailable("storage") from None


class RawStore(_Db):
    pragmas = ("PRAGMA synchronous=FULL", "PRAGMA secure_delete=ON", "PRAGMA foreign_keys=ON",
               "PRAGMA busy_timeout=5000")
    incremental_vacuum = True
    schema = """
    CREATE TABLE IF NOT EXISTS batches(
        batch_id TEXT PRIMARY KEY NOT NULL,
        body_sha256 TEXT NOT NULL,
        session_id TEXT NOT NULL,
        receipt_unix INTEGER NOT NULL,
        receipt_day TEXT NOT NULL,
        body BLOB NOT NULL);
    CREATE TABLE IF NOT EXISTS events(
        session_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        batch_id TEXT NOT NULL REFERENCES batches(batch_id) ON DELETE CASCADE,
        PRIMARY KEY(session_id, seq)) WITHOUT ROWID;
    CREATE INDEX IF NOT EXISTS events_batch ON events(batch_id);
    CREATE INDEX IF NOT EXISTS batches_receipt ON batches(receipt_unix);
    CREATE INDEX IF NOT EXISTS batches_day ON batches(receipt_day);
    """

    def __init__(self, path, max_bytes=2 * 1024**3):
        super().__init__(path)
        self.max_bytes = max_bytes

    def _size(self, conn):
        pages = conn.execute("PRAGMA page_count").fetchone()[0]
        free = conn.execute("PRAGMA freelist_count").fetchone()[0]
        size = conn.execute("PRAGMA page_size").fetchone()[0]
        return (pages - free) * size

    def ingest(self, batch_id, digest, session_id, seqs, body, now):
        """One transaction. Returns 'accepted', 'duplicate' (identical retry) or 'conflict'.

        Uniqueness is enforced by the PRIMARY KEY constraints, not by a cache.
        """
        try:
            with self.transaction() as conn:
                if self._size(conn) >= self.max_bytes:
                    raise StorageUnavailable("full")
                cursor = conn.execute(
                    "INSERT INTO batches(batch_id, body_sha256, session_id, receipt_unix, receipt_day, body) "
                    "VALUES(?,?,?,?,?,?) ON CONFLICT(batch_id) DO NOTHING",
                    (batch_id, digest, session_id, int(now), utc_day(now), body))
                if cursor.rowcount == 0:
                    stored = conn.execute("SELECT body_sha256 FROM batches WHERE batch_id=?",
                                          (batch_id,)).fetchone()
                    return "duplicate" if stored and stored[0] == digest else "conflict"
                try:
                    conn.executemany("INSERT INTO events(session_id, seq, batch_id) VALUES(?,?,?)",
                                     [(session_id, seq, batch_id) for seq in seqs])
                except sqlite3.IntegrityError:
                    raise _Conflict from None  # whole batch rolls back atomically
                return "accepted"
        except _Conflict:
            return "conflict"

    def records_for_day(self, day):
        """(receipt_day, body) pairs in ingestion order."""
        with self.connection() as conn:
            rows = conn.execute("SELECT receipt_day, body FROM batches WHERE receipt_day=? ORDER BY rowid",
                                (day,)).fetchall()
        return [(row[0], bytes(row[1])) for row in rows]

    def purge(self, now, ttl=RAW_TTL):
        """Delete records at or past their deadline, then overwrite/free pages. Idempotent."""
        cutoff = int(now) - ttl
        with self.transaction() as conn:
            # events rows follow through ON DELETE CASCADE (foreign_keys=ON).
            deleted = conn.execute("DELETE FROM batches WHERE receipt_unix <= ?", (cutoff,)).rowcount
        checkpoint = None
        with self.connection() as conn:
            conn.execute("PRAGMA incremental_vacuum")
            checkpoint = conn.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        return {"deleted_batches": deleted, "checkpoint_busy": bool(checkpoint and checkpoint[0])}

    def count(self):
        with self.connection() as conn:
            return conn.execute("SELECT count(*) FROM batches").fetchone()[0]

    def oldest_receipt(self):
        with self.connection() as conn:
            return conn.execute("SELECT min(receipt_unix) FROM batches").fetchone()[0]

    def newest_receipt(self):
        with self.connection() as conn:
            return conn.execute("SELECT max(receipt_unix) FROM batches").fetchone()[0]


class AggStore(_Db):
    pragmas = ("PRAGMA synchronous=FULL", "PRAGMA foreign_keys=ON", "PRAGMA busy_timeout=5000")
    schema = """
    CREATE TABLE IF NOT EXISTS daily_status(
        day TEXT NOT NULL, release_id TEXT NOT NULL, tbl TEXT NOT NULL, status TEXT NOT NULL,
        computed_unix INTEGER NOT NULL, PRIMARY KEY(day, release_id, tbl)) WITHOUT ROWID;
    CREATE TABLE IF NOT EXISTS daily_gpu(
        day TEXT NOT NULL, release_id TEXT NOT NULL, gpu_family TEXT NOT NULL,
        session_observations INTEGER NOT NULL, interval_sum_us INTEGER NOT NULL,
        rendered_frames INTEGER NOT NULL, excluded_gap_count INTEGER NOT NULL,
        hist0 INTEGER NOT NULL, hist1 INTEGER NOT NULL, hist2 INTEGER NOT NULL, hist3 INTEGER NOT NULL,
        hist4 INTEGER NOT NULL, hist5 INTEGER NOT NULL, hist6 INTEGER NOT NULL, hist7 INTEGER NOT NULL,
        PRIMARY KEY(day, release_id, gpu_family)) WITHOUT ROWID;
    CREATE TABLE IF NOT EXISTS daily_vehicle(
        day TEXT NOT NULL, release_id TEXT NOT NULL, vehicle_id TEXT NOT NULL,
        session_observations INTEGER NOT NULL, activity_summaries INTEGER NOT NULL,
        active_seconds INTEGER NOT NULL, PRIMARY KEY(day, release_id, vehicle_id)) WITHOUT ROWID;
    CREATE TABLE IF NOT EXISTS publications(
        repository TEXT NOT NULL, key TEXT NOT NULL, digest TEXT NOT NULL, title TEXT NOT NULL,
        body TEXT NOT NULL, bot_author TEXT NOT NULL, state TEXT NOT NULL,
        create_attempts INTEGER NOT NULL DEFAULT 0, issue_number INTEGER,
        created_unix INTEGER NOT NULL, updated_unix INTEGER NOT NULL,
        PRIMARY KEY(repository, key)) WITHOUT ROWID;
    CREATE TABLE IF NOT EXISTS ingest_counts(
        day TEXT NOT NULL, category TEXT NOT NULL, count INTEGER NOT NULL,
        PRIMARY KEY(day, category)) WITHOUT ROWID;
    CREATE TABLE IF NOT EXISTS daily_cells(
        day TEXT NOT NULL, release_id TEXT NOT NULL, tbl TEXT NOT NULL, dims TEXT NOT NULL,
        sessions INTEGER NOT NULL, metrics TEXT NOT NULL,
        PRIMARY KEY(day, release_id, tbl, dims)) WITHOUT ROWID;
    """
    # hist0..hist7: per-bucket frame-interval counts (upper bounds contract.HISTOGRAM_UPPER_US, in µs).
    HISTOGRAM_COLUMNS = tuple(f"hist{i}" for i in range(8))
    TABLES = {"gpu": ("daily_gpu", ("gpu_family", "session_observations", "interval_sum_us", "rendered_frames",
                                    "excluded_gap_count", *HISTOGRAM_COLUMNS)),
              "vehicle": ("daily_vehicle", ("vehicle_id", "session_observations", "activity_summaries",
                                            "active_seconds"))}

    def _verify(self, conn):
        have = {row[1] for row in conn.execute("PRAGMA table_info(daily_gpu)")}
        if not set(self.TABLES["gpu"][1]) <= have:
            raise StorageUnavailable("aggregates_schema")  # an older layout: there is no migration

    @classmethod
    def _flatten(cls, row):
        if "interval_histogram" not in row:
            return row
        histogram = row["interval_histogram"]
        if len(histogram) != len(cls.HISTOGRAM_COLUMNS):
            raise ValueError("histogram")
        return {**row, **dict(zip(cls.HISTOGRAM_COLUMNS, histogram))}

    @classmethod
    def _nest(cls, values):
        row = dict(values)
        if cls.HISTOGRAM_COLUMNS[0] in row:
            row["interval_histogram"] = [row.pop(column) for column in cls.HISTOGRAM_COLUMNS]
        return row

    def put_day(self, day, release_id, table, status, rows, now):
        """Idempotent replace keyed by (day, release_id, table)."""
        sql_table, columns = self.TABLES[table]
        with self.transaction() as conn:
            conn.execute(f"DELETE FROM {sql_table} WHERE day=? AND release_id=?", (day, release_id))
            conn.executemany(
                f"INSERT INTO {sql_table}(day, release_id, {', '.join(columns)}) VALUES(?,?,{','.join('?' * len(columns))})",
                [(day, release_id, *(flat[c] for c in columns)) for flat in map(self._flatten, rows)])
            conn.execute(
                "INSERT INTO daily_status(day, release_id, tbl, status, computed_unix) VALUES(?,?,?,?,?) "
                "ON CONFLICT(day, release_id, tbl) DO UPDATE SET status=excluded.status, "
                "computed_unix=excluded.computed_unix", (day, release_id, table, status, int(now)))

    def get_day(self, day, release_id, table):
        """(status, rows) or None when the day was never rolled up (missing)."""
        sql_table, columns = self.TABLES[table]
        with self.connection() as conn:
            row = conn.execute("SELECT status FROM daily_status WHERE day=? AND release_id=? AND tbl=?",
                               (day, release_id, table)).fetchone()
            if row is None:
                return None
            rows = conn.execute(
                f"SELECT {', '.join(columns)} FROM {sql_table} WHERE day=? AND release_id=? ORDER BY {columns[0]}",
                (day, release_id)).fetchall()
        return row[0], [self._nest(zip(columns, values)) for values in rows]

    def purge(self, now, days=AGGREGATE_DAYS):
        """Remove aggregate rows older than the 180-day maximum lifetime."""
        today = datetime.fromtimestamp(int(now), tz=timezone.utc).date()
        cutoff = (today - timedelta(days=days)).isoformat()
        deleted = 0
        with self.transaction() as conn:
            for table in ("daily_gpu", "daily_vehicle", "daily_status", "ingest_counts", "daily_cells"):
                deleted += conn.execute(f"DELETE FROM {table} WHERE day < ?", (cutoff,)).rowcount
        return {"deleted_aggregate_rows": deleted}

    # TELEM-20 ingest counters: ID-free (day, fixed category) totals ------------------------

    def add_ingest_counts(self, items):
        """items: [(day, category, count)]; added to existing totals in one transaction."""
        with self.transaction() as conn:
            conn.executemany(
                "INSERT INTO ingest_counts(day, category, count) VALUES(?,?,?) "
                "ON CONFLICT(day, category) DO UPDATE SET count=count+excluded.count", items)

    def ingest_counts(self, day):
        with self.connection() as conn:
            rows = conn.execute("SELECT category, count FROM ingest_counts WHERE day=? ORDER BY category",
                                (day,)).fetchall()
        return dict(rows)

    # TELEM-16/17 insight cells: unsuppressed, ID-free daily cells (operator-only; disclosure control at report time)

    def put_cells(self, day, release_id, rows, now):
        """Idempotent replace of one (day, release) set. rows: [(tbl, dims_json, sessions, metrics_json)]."""
        with self.transaction() as conn:
            conn.execute("DELETE FROM daily_cells WHERE day=? AND release_id=?", (day, release_id))
            conn.executemany("INSERT INTO daily_cells(day, release_id, tbl, dims, sessions, metrics) "
                             "VALUES(?,?,?,?,?,?)", [(day, release_id, *row) for row in rows])
            conn.execute(
                "INSERT INTO daily_status(day, release_id, tbl, status, computed_unix) VALUES(?,?,?,?,?) "
                "ON CONFLICT(day, release_id, tbl) DO UPDATE SET status=excluded.status, "
                "computed_unix=excluded.computed_unix",
                (day, release_id, "cells", "ready" if rows else "no_data", int(now)))

    def get_cells(self, day, release_id):
        with self.connection() as conn:
            return conn.execute("SELECT tbl, dims, sessions, metrics FROM daily_cells WHERE day=? AND release_id=? "
                                "ORDER BY tbl, dims", (day, release_id)).fetchall()

    def cells_status(self, day, release_id):
        with self.connection() as conn:
            row = conn.execute("SELECT status FROM daily_status WHERE day=? AND release_id=? AND tbl='cells'",
                               (day, release_id)).fetchone()
        return row[0] if row else None

    def day_statuses(self, day):
        """{'<release_id>/<table>': status} for one rolled-up day."""
        with self.connection() as conn:
            rows = conn.execute("SELECT release_id, tbl, status FROM daily_status WHERE day=? "
                                "ORDER BY release_id, tbl", (day,)).fetchall()
        return {f"{release}/{table}": status for release, table, status in rows}

    # Publication intents -------------------------------------------------------------------

    _PUB_COLUMNS = ("repository", "key", "digest", "title", "body", "bot_author", "state",
                    "create_attempts", "issue_number")

    def get_publication(self, repository, key):
        with self.connection() as conn:
            row = conn.execute(f"SELECT {', '.join(self._PUB_COLUMNS)} FROM publications "
                               "WHERE repository=? AND key=?", (repository, key)).fetchone()
        return dict(zip(self._PUB_COLUMNS, row)) if row else None

    def create_publication(self, repository, key, digest, title, body, bot_author, now):
        with self.transaction() as conn:
            conn.execute(
                "INSERT INTO publications(repository, key, digest, title, body, bot_author, state, "
                "create_attempts, created_unix, updated_unix) VALUES(?,?,?,?,?,?, 'creating', 0, ?, ?)",
                (repository, key, digest, title, body, bot_author, int(now), int(now)))

    def update_publication(self, repository, key, now, **fields):
        allowed = {"state", "create_attempts", "issue_number"}
        if not fields or set(fields) - allowed:
            raise ValueError("fields")
        assignments = ", ".join(f"{name}=?" for name in fields)
        with self.transaction() as conn:
            conn.execute(f"UPDATE publications SET {assignments}, updated_unix=? WHERE repository=? AND key=?",
                         (*fields.values(), int(now), repository, key))
