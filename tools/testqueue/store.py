"""Durable jobs, attempts and resource allocations. Only the worker opens this DB."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import secrets
import sqlite3
import time
import uuid

ACTIVE = ("DISPATCHING", "RUNNING", "CLEANING", "UNKNOWN")


def digest(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


class Store:
    def __init__(self, root: Path):
        self.db = sqlite3.connect(root / "queue.sqlite3", check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version not in (0, 1):
            raise ValueError(f"unsupported testqueue schema {version}")
        self.db.executescript("""
          CREATE TABLE IF NOT EXISTS jobs (
            id TEXT PRIMARY KEY, request_id TEXT UNIQUE NOT NULL, payload TEXT NOT NULL,
            digest TEXT NOT NULL, capability TEXT NOT NULL, request_secret TEXT NOT NULL, state TEXT NOT NULL,
            submitted REAL NOT NULL, canceled INTEGER NOT NULL DEFAULT 0, reason TEXT NOT NULL DEFAULT '');
          CREATE TABLE IF NOT EXISTS attempts (
            id TEXT PRIMARY KEY, job TEXT NOT NULL REFERENCES jobs(id), generation INTEGER NOT NULL,
            state TEXT NOT NULL, data TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS claims (
            resource TEXT NOT NULL, attempt TEXT NOT NULL, amount INTEGER NOT NULL,
            PRIMARY KEY(resource, attempt));
          CREATE TABLE IF NOT EXISTS events (
            seq INTEGER PRIMARY KEY, at REAL NOT NULL, job TEXT, event TEXT NOT NULL, data TEXT NOT NULL);
          PRAGMA user_version=1;
        """)
        # A lost supervisor is uncertainty, even when its recorded PID looks dead.
        with self.db:
            self.db.execute("UPDATE attempts SET state='UNKNOWN' WHERE state IN ('DISPATCHING','RUNNING','CLEANING')")
            self.db.execute("UPDATE jobs SET state='UNKNOWN', reason='SUPERVISOR_RESTART: reconcile required' WHERE state IN ('DISPATCHING','RUNNING','CLEANING')")

    def event(self, job: str | None, event: str, data=None):
        self.db.execute("INSERT INTO events(at,job,event,data) VALUES(?,?,?,?)", (time.time(), job, event, json.dumps(data or {})))

    def submit(self, request_id: str, payload: dict, request_secret: str) -> dict:
        if len(request_secret) < 32:
            raise ValueError("submission secret must have at least 32 characters")
        hashed = digest(payload)
        prior = self.db.execute("SELECT * FROM jobs WHERE request_id=?", (request_id,)).fetchone()
        if prior:
            if not secrets.compare_digest(prior["request_secret"], digest(request_secret)):
                raise ValueError("request_id belongs to another submitting client")
            if prior["digest"] != hashed:
                raise ValueError("request_id already exists with different inputs")
            return {"job": prior["id"], "handle": prior["id"] + ":" + prior["capability"]}
        job, capability = "T-" + uuid.uuid4().hex, secrets.token_hex(32)
        with self.db:
            self.db.execute("INSERT INTO jobs(id,request_id,payload,digest,capability,request_secret,state,submitted) VALUES(?,?,?,?,?,?,'QUEUED',?)",
                            (job, request_id, json.dumps(payload), hashed, capability, digest(request_secret), time.time()))
            self.event(job, "SUBMITTED", {"digest": hashed})
        return {"job": job, "handle": job + ":" + capability}

    def get(self, job: str) -> dict:
        row = self.db.execute("SELECT * FROM jobs WHERE id=?", (job,)).fetchone()
        if not row:
            raise ValueError("unknown job")
        result = dict(row)
        result.pop("capability")
        result.pop("request_secret")
        result["payload"] = json.loads(result["payload"])
        result["attempts"] = [dict(attempt) for attempt in self.db.execute("SELECT * FROM attempts WHERE job=? ORDER BY generation", (job,))]
        for attempt in result["attempts"]:
            attempt["data"] = json.loads(attempt["data"])
        if result["attempts"]:
            result.update(result["attempts"][-1]["data"])
        return result

    def authorize(self, handle: str) -> str:
        job, separator, secret = handle.partition(":")
        row = self.db.execute("SELECT capability FROM jobs WHERE id=?", (job,)).fetchone()
        if not separator or not row or not secrets.compare_digest(secret, row[0]):
            raise ValueError("owning session handle required")
        return job

    def allocate(self, job: str, resources: dict[str, int], capacities: dict[str, int]) -> str | None:
        self.db.execute("BEGIN IMMEDIATE")
        try:
            row = self.db.execute("SELECT state,canceled FROM jobs WHERE id=?", (job,)).fetchone()
            if row[0] != "QUEUED" or row[1]:
                self.db.rollback()
                return None
            for resource, amount in sorted(resources.items()):
                used = self.db.execute("SELECT COALESCE(SUM(amount),0) FROM claims WHERE resource=?", (resource,)).fetchone()[0]
                if used + amount > capacities.get(resource, 1):
                    self.db.execute("UPDATE jobs SET reason=? WHERE id=?", (f"RESOURCE_BUSY: {resource}", job))
                    self.db.commit()
                    return None
            attempt = "A-" + uuid.uuid4().hex
            self.db.execute("INSERT INTO attempts VALUES(?,?,1,'DISPATCHING','{}')", (attempt, job))
            self.db.execute("UPDATE jobs SET state='DISPATCHING',reason='' WHERE id=?", (job,))
            self.db.executemany("INSERT INTO claims VALUES(?,?,?)", [(key, attempt, amount) for key, amount in resources.items()])
            self.event(job, "DISPATCHING", {"attempt": attempt, "resources": resources})
            self.db.commit()
            return attempt
        except BaseException:
            self.db.rollback()
            raise

    def update(self, job: str, attempt: str, state: str, data: dict):
        with self.db:
            self.db.execute("UPDATE attempts SET state=?,data=? WHERE id=? AND job=?", (state, json.dumps(data), attempt, job))
            self.db.execute("UPDATE jobs SET state=? WHERE id=?", (state, job))
            self.event(job, state, {"attempt": attempt, **data})
            if state == "FINISHED":
                if data.get("cleanup") != "CONFIRMED":
                    raise ValueError("cannot release without confirmed process-tree cleanup")
                self.db.execute("DELETE FROM claims WHERE attempt=?", (attempt,))

    def cancel(self, job: str):
        with self.db:
            # Durable cancellation before any future dispatch/start checks.
            self.db.execute("UPDATE jobs SET canceled=1 WHERE id=?", (job,))
            self.db.execute("UPDATE jobs SET state='FINISHED',reason='CANCELED before dispatch' WHERE id=? AND state='QUEUED'", (job,))
            self.event(job, "CANCEL_REQUESTED")
