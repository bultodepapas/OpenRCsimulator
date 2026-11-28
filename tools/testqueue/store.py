"""Durable jobs, attempts and resource allocations. Only the worker opens this DB."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import secrets
import sqlite3
import time
import uuid
import re

ACTIVE = ("DISPATCHING", "RUNNING", "CLEANING", "UNKNOWN")


class StaleTransition(ValueError):
    """A transition arrived after the attempt's terminal record became durable."""


def digest(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def submission_identity(request_id, request_secret):
    if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", request_id) or ".." in request_id:
        raise ValueError("request_id must be a safe opaque token")
    if not isinstance(request_secret, str) or not 32 <= len(request_secret) <= 256:
        raise ValueError("submission secret must have at least 32 characters")
    return digest(request_secret)


class Store:
    def __init__(self, root: Path):
        self.db = sqlite3.connect(root / "queue.sqlite3", check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version not in (0, 1, 2):
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
          CREATE TABLE IF NOT EXISTS canceled_submissions (
            request_id TEXT PRIMARY KEY, request_secret TEXT NOT NULL);
          PRAGMA user_version=2;
        """)
        # A lost supervisor is uncertainty, even when its recorded PID looks dead.
        with self.db:
            self.db.execute("UPDATE attempts SET state='UNKNOWN' WHERE state IN ('DISPATCHING','RUNNING','CLEANING')")
            self.db.execute("UPDATE jobs SET state='UNKNOWN', reason='SUPERVISOR_RESTART: reconcile required' WHERE state IN ('DISPATCHING','RUNNING','CLEANING')")

    def event(self, job: str | None, event: str, data=None):
        self.db.execute("INSERT INTO events(at,job,event,data) VALUES(?,?,?,?)", (time.time(), job, event, json.dumps(data or {})))

    def reached_launch_fence(self, job: str, attempt: str) -> bool:
        """True when the attempt ever durably recorded RUNNING (or later).

        The worker writes RUNNING with ``launch: CREATION_UNCERTAIN`` in one
        transaction before it calls the OS to create a process. Without that
        event no process of this attempt was ever created (TQ-07-A10). An
        unreadable event counts as reached, which keeps the attempt quarantined.
        """
        for row in self.db.execute(
                "SELECT data FROM events WHERE job=? AND event IN ('RUNNING','CLEANING','FINISHED')", (job,)):
            try:
                event = json.loads(row["data"])
            except ValueError:
                return True
            if not isinstance(event, dict) or event.get("attempt") in (attempt, None):
                return True
        return False

    def only_dispatched(self, job: str, attempt: str) -> bool:
        """The durable launch fence writes RUNNING before the launch gate can start."""
        try:
            rows = list(self.db.execute(
                "SELECT event,data FROM events WHERE job=? AND event IN ('DISPATCHING','RUNNING','CLEANING','UNKNOWN','FINISHED')",
                (job,),
            ))
            if len(rows) != 1 or rows[0]["event"] != "DISPATCHING":
                return False
            event = json.loads(rows[0]["data"])
            return isinstance(event, dict) and event.get("attempt") == attempt
        except (sqlite3.Error, TypeError, ValueError):
            return False

    def submit(self, request_id: str, payload: dict, request_secret: str) -> dict:
        secret_digest = submission_identity(request_id, request_secret)
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
            canceled = self.db.execute("SELECT request_secret FROM canceled_submissions WHERE request_id=?", (request_id,)).fetchone()
            if canceled and not secrets.compare_digest(canceled[0], secret_digest):
                raise ValueError("request_id belongs to another submitting client")
            self.db.execute("INSERT INTO jobs(id,request_id,payload,digest,capability,request_secret,state,submitted) VALUES(?,?,?,?,?,?,'QUEUED',?)",
                            (job, request_id, json.dumps(payload), hashed, capability, secret_digest, time.time()))
            if canceled:
                self.db.execute("UPDATE jobs SET canceled=1,state='FINISHED',reason='CANCELED before acceptance' WHERE id=?", (job,))
            self.event(job, "SUBMITTED", {"digest": hashed})
        return {"job": job, "handle": job + ":" + capability}

    def recover(self, request_id: str, request_secret: str) -> dict | None:
        """Recover ownership without preparing inputs or creating a job."""
        secret_digest = submission_identity(request_id, request_secret)
        row = self.db.execute("SELECT id,capability,request_secret FROM jobs WHERE request_id=?", (request_id,)).fetchone()
        if row:
            if not secrets.compare_digest(row["request_secret"], secret_digest):
                raise ValueError("request_id belongs to another submitting client")
            return {"job": row["id"], "handle": row["id"] + ":" + row["capability"]}
        canceled = self.db.execute("SELECT request_secret FROM canceled_submissions WHERE request_id=?", (request_id,)).fetchone()
        if canceled and not secrets.compare_digest(canceled[0], secret_digest):
            raise ValueError("request_id belongs to another submitting client")
        return None

    def cancel_submission(self, request_id: str, request_secret: str) -> dict:
        """A late submit must observe this cancellation before becoming dispatchable."""
        accepted = self.recover(request_id, request_secret)
        with self.db:
            self.db.execute("INSERT OR IGNORE INTO canceled_submissions VALUES(?,?)",
                            (request_id, submission_identity(request_id, request_secret)))
            if accepted:
                self._cancel(accepted["job"])
            self.event(accepted["job"] if accepted else None, "SUBMISSION_CANCELED", {"request_id": request_id})
        return {"canceled": True, **(accepted or {})}

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
        elif result["state"] == "FINISHED" and result["canceled"]:
            result.update(outcome="CANCELED", evidence="INCOMPLETE", cleanup="CONFIRMED")
        return result

    def authorize(self, handle: str) -> str:
        job, separator, secret = handle.partition(":")
        row = self.db.execute("SELECT capability FROM jobs WHERE id=?", (job,)).fetchone()
        if not separator or not row or not secrets.compare_digest(secret, row[0]):
            raise ValueError("owning session handle required")
        return job

    def allocate(self, job: str, resources: dict[str, int], capacities: dict[str, int], identity: dict | None = None) -> str | None:
        self.db.execute("BEGIN IMMEDIATE")
        try:
            row = self.db.execute("SELECT state,canceled FROM jobs WHERE id=?", (job,)).fetchone()
            if row[0] != "QUEUED" or row[1]:
                self.db.rollback()
                return None
            # An exclusive attempt conflicts with *every* retained claim,
            # including quarantined UNKNOWN attempts and legacy resource names.
            # This decision belongs in the same transaction as allocation.
            quarantined = self.db.execute("SELECT 1 FROM attempts WHERE state='UNKNOWN' LIMIT 1").fetchone()
            if quarantined:
                self.db.execute("UPDATE jobs SET reason=? WHERE id=? AND reason IS NOT ?", ("RESOURCE_BUSY: unresolved cleanup quarantines the managed host", job, "RESOURCE_BUSY: unresolved cleanup quarantines the managed host"))
                self.db.commit()
                return None
            exclusive_busy = self.db.execute("SELECT 1 FROM claims WHERE resource='exclusive' LIMIT 1").fetchone()
            any_busy = self.db.execute("SELECT 1 FROM claims LIMIT 1").fetchone()
            if exclusive_busy or (resources.get("exclusive", 0) and any_busy):
                self.db.execute("UPDATE jobs SET reason=? WHERE id=? AND reason IS NOT ?", ("RESOURCE_BUSY: exclusive execution requires an idle managed host", job, "RESOURCE_BUSY: exclusive execution requires an idle managed host"))
                self.db.commit()
                return None
            for resource, amount in sorted(resources.items()):
                used = self.db.execute("SELECT COALESCE(SUM(amount),0) FROM claims WHERE resource=?", (resource,)).fetchone()[0]
                if used + amount > capacities.get(resource, 1):
                    self.db.execute("UPDATE jobs SET reason=? WHERE id=? AND reason IS NOT ?", (f"RESOURCE_BUSY: {resource}", job, f"RESOURCE_BUSY: {resource}"))
                    self.db.commit()
                    return None
            attempt = "A-" + uuid.uuid4().hex
            self.db.execute("INSERT INTO attempts VALUES(?,?,1,'DISPATCHING',?)", (attempt, job, json.dumps(identity or {})))
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
            current = self.db.execute("SELECT state FROM attempts WHERE id=? AND job=?", (attempt, job)).fetchone()
            if current is not None and current[0] == "FINISHED":
                # A durable terminal record is never rewritten by a later or
                # older transition; that would resurrect released claims.
                raise StaleTransition(f"attempt {attempt} is already FINISHED; refusing {state}")
            self.db.execute("UPDATE attempts SET state=?,data=? WHERE id=? AND job=?", (state, json.dumps(data), attempt, job))
            self.db.execute("UPDATE jobs SET state=? WHERE id=?", (state, job))
            self.event(job, state, {"attempt": attempt, **data})
            if state == "FINISHED":
                if data.get("cleanup") != "CONFIRMED":
                    raise ValueError("cannot release without confirmed process-tree cleanup")
                self.db.execute("DELETE FROM claims WHERE attempt=?", (attempt,))

    def abandon(self, job: str, reason: str):
        """Release one quarantined attempt by an explicit operator decision."""
        if not isinstance(reason, str) or not reason.strip() or len(reason) > 2000:
            raise ValueError("operator abandonment requires a reason of 1..2000 characters")
        with self.db:
            status = self.get(job)
            if status["state"] != "UNKNOWN":
                raise ValueError("only UNKNOWN attempts can be abandoned")
            attempt = status["attempts"][-1]
            data = {**attempt["data"], "cleanup": "UNCONFIRMED", "outcome": "INFRA_FAILED",
                    "evidence": "INCOMPLETE", "finished": time.time(),
                    "operator_abandoned": {"reason": reason.strip()}}
            self.db.execute("UPDATE attempts SET state='FINISHED',data=? WHERE id=? AND job=?",
                            (json.dumps(data), attempt["id"], job))
            self.db.execute("UPDATE jobs SET state='FINISHED',canceled=1,reason=? WHERE id=?",
                            ("OPERATOR_ABANDONED: " + reason.strip(), job))
            self.db.execute("DELETE FROM claims WHERE attempt=?", (attempt["id"],))
            self.event(job, "OPERATOR_ABANDONED", {"attempt": attempt["id"], **data})

    def cancel(self, job: str):
        with self.db:
            self._cancel(job)

    def _cancel(self, job: str):
        if self.get(job)["state"] == "FINISHED":
            return
        # Durable cancellation before any future dispatch/start checks.
        self.db.execute("UPDATE jobs SET canceled=1 WHERE id=?", (job,))
        self.db.execute("UPDATE jobs SET state='FINISHED',reason='CANCELED before dispatch' WHERE id=? AND state='QUEUED'", (job,))
        self.event(job, "CANCEL_REQUESTED")
