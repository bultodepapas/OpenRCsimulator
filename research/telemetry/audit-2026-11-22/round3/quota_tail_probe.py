#!/usr/bin/env python3
"""Bounded SQL-level model of current RawStore.ingest quota check; no live service.

The exact RawStore table/index definitions, _size formula and ordering of
quota-before-insert are reproduced. The payload is synthetic bytes, not a
contract-validated HTTP batch. This is NOT an execution of the service class.
"""
import json
import sqlite3
import tempfile
from pathlib import Path

SCHEMA = """
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

def live_bytes(conn):
    return (conn.execute("PRAGMA page_count").fetchone()[0] -
            conn.execute("PRAGMA freelist_count").fetchone()[0]) * conn.execute("PRAGMA page_size").fetchone()[0]

def run():
    with tempfile.TemporaryDirectory(prefix="telem-audit-quota-") as directory:
        path = Path(directory) / "raw.sqlite"
        conn = sqlite3.connect(path, isolation_level=None)
        conn.execute("PRAGMA auto_vacuum=INCREMENTAL")
        conn.execute("PRAGMA journal_mode=WAL")
        for pragma in ("PRAGMA synchronous=FULL", "PRAGMA secure_delete=ON", "PRAGMA foreign_keys=ON", "PRAGMA busy_timeout=5000"):
            conn.execute(pragma)
        conn.executescript(SCHEMA)
        baseline = live_bytes(conn)
        page = conn.execute("PRAGMA page_size").fetchone()[0]
        limit = baseline + page
        batch_id = "a"*32
        session = "b"*32
        body = b"x" * 8192  # synthetic bounded bytes only; NOT a validated batch
        conn.execute("BEGIN IMMEDIATE")
        admitted = live_bytes(conn) < limit  # same order as RawStore.ingest
        if admitted:
            conn.execute("INSERT INTO batches(batch_id,body_sha256,session_id,receipt_unix,receipt_day,body) VALUES(?,?,?,?,?,?) ON CONFLICT(batch_id) DO NOTHING", (batch_id,"f"*64,session,1800000000,"2027-01-15",body))
            conn.execute("INSERT INTO events(session_id,seq,batch_id) VALUES(?,?,?)",(session,1,batch_id))
        conn.execute("COMMIT")
        after = live_bytes(conn)
        outcome = {
            "kind": "synthetic_sql_equivalent_not_actual_RawStore_or_HTTP",
            "sqlite_version": sqlite3.sqlite_version,
            "page_size_bytes": page,
            "baseline_live_bytes": baseline,
            "configured_limit_bytes": limit,
            "synthetic_body_bytes": len(body),
            "pre_insert_quota_check_passed": admitted,
            "post_insert_live_bytes": after,
            "post_insert_above_quota": after > limit,
            "overshoot_bytes": after - limit,
            "stored_rows": conn.execute("SELECT COUNT(*) FROM batches").fetchone()[0],
            "durability_mode": "WAL_and_FULL_sync",
            "limitation": "Does not exercise upstream JSON/schema validation; shows the SQL admission boundary only. No production capacity or filesystem usage measured."
        }
        conn.close()
        return outcome

if __name__ == "__main__":
    print(json.dumps(run(), indent=2, sort_keys=True))
