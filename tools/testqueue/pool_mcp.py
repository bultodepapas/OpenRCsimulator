"""Durable, nonblocking MCP facade for the checked-test pool."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue.common import Singleton, write_json
from tools.testqueue.pool import Pool, default_config, digest
from tools.testqueue.pool_batch import _finished_success, reobservation_ids, run_batch
from tools.testqueue.pool_history import expected_seconds
from tools.testqueue.presets import validate, scheduling


def _read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def _directory(pool, request_id):
    if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", request_id):
        raise ValueError("request_id must be 1-80 letters, digits, underscores or hyphens")
    return pool.root / "mcp" / request_id


def _jobs(jobs):
    if not isinstance(jobs, list) or not 1 <= len(jobs) <= 64:
        raise ValueError("jobs must contain 1-64 independent checked tests")
    result = []
    for job in jobs:
        if not isinstance(job, dict) or set(job) - {"script", "platform", "require", "timeout", "host"}:
            raise ValueError("invalid job fields")
        target = job.get("platform", platform.system().lower())
        if target not in {"windows", "linux", "darwin", "any"}:
            raise ValueError("invalid platform")
        options = validate("checked", {"script": job.get("script"), "require": job.get("require", []),
                                      "timeout": job.get("timeout", 90), "headless": True})
        if scheduling("checked", options)["workload"] == "performance":
            raise ValueError("performance tests require a dedicated same-host campaign")
        item = {"script": options["script"], "require": options["require"],
                "timeout": options["timeout"], "platform": target}
        if "host" in job:
            if not isinstance(job["host"], str) or not job["host"]:
                raise ValueError("host must be a nonempty ID")
            item["host"] = job["host"]
        result.append(item)
    return result


BACKGROUND_CREATIONFLAGS = ((subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW)
                            if os.name == "nt" else 0)


def _start(directory):
    with (directory / "supervisor.log").open("ab") as output:
        options = {"stdin": subprocess.DEVNULL, "stdout": output, "stderr": output,
                   "cwd": str(REPO), "close_fds": True}
        if os.name == "nt":
            # A private hidden console, not DETACHED_PROCESS: every descendant
            # (git, ssh, Godot console wrappers, shells) inherits it instead of
            # opening its own visible window on the user's desktop.
            options["creationflags"] = BACKGROUND_CREATIONFLAGS
        else:
            options["start_new_session"] = True
        subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--worker", str(directory)], **options)


def _active(directory):
    if not (directory / "worker.lock").exists():
        return False
    try:
        lock = Singleton(directory / "worker.lock")
    except OSError:
        return True
    lock.close()
    return False


def launch(request_id, jobs, source=None, *, config=None):
    pool = Pool(config or default_config())
    directory = _directory(pool, request_id)
    source = Path(source or REPO).resolve()
    if not (source / "app" / "project.godot").is_file():
        raise ValueError("source must be an OpenRC checkout with app/project.godot")
    request = {"request_id": request_id, "jobs": _jobs(jobs), "source": str(source),
               "config": str(pool.config_path), "config_sha256": pool.config_digest}
    guard = Singleton(directory / "request.lock")
    try:
        path = directory / "request.json"
        if path.exists():
            if _read(path) != request:
                raise ValueError("request_id already binds different inputs; use the original request")
        else:
            write_json(path, request)
        if not (directory / "supervisor.json").exists():
            write_json(directory / "supervisor.json", {"state": "ACCEPTED", "updated_at": time.time()})
        # A lost reply or failed Popen may leave only the durable request. Safe
        # duplicate children are excluded by worker.lock before freezing bytes.
        if _read(directory / "supervisor.json").get("state") == "ACCEPTED" and not _active(directory):
            _start(directory)
    finally:
        guard.close()
    return status(request_id, config=config)


def status(request_id, *, config=None):
    """Read cached receipts, without network or rehashing collected artifacts."""
    pool = Pool(config or default_config())
    directory = _directory(pool, request_id)
    request = _request(directory, request_id)
    result = {"request_id": request_id, "receipt": str(directory),
              "evidence_observation": "CACHED_METADATA",
              "supervisor": _read(directory / "supervisor.json") if (directory / "supervisor.json").exists() else {"state": "ACCEPTED"},
              "source": request["source"], "source_frozen": (directory / "manifest.json").exists()}
    result["supervisor_active"] = _active(directory)
    if (directory / "batch.json").exists():
        batch = _read(directory / "batch.json")
        result.update(result=batch.get("result", "INCOMPLETE"), snapshot=batch["snapshot"], jobs=batch["jobs"])
        reobserve = reobservation_ids(pool, batch["jobs"])
        if reobserve:
            result.update(result="INCOMPLETE", recovery_required=True,
                          recovery_reason="Legacy outcomes or unverified collections require original-authority observation")
            result["jobs"] = [({**row, "phase": "BLOCKED", "previous_status": row.get("status"),
                                "status": {"state": "UNKNOWN", "cleanup": "UNCONFIRMED"},
                                "recovery_required": True} if row["request_id"] in reobserve else row)
                              for row in batch["jobs"]]
    # Summary first: clients that truncate long tool output keep the digest.
    return {"request_id": request_id, "summary": summarize(result, pool),
            **{key: value for key, value in result.items() if key != "request_id"}}


def _request(directory, request_id):
    try:
        return _read(directory / "request.json")
    except FileNotFoundError:
        raise ValueError(f"unknown request_id {request_id!r}; if the sim_test_launch reply was lost, "
                         "repeat sim_test_launch with the same request_id and inputs") from None


_ACTIVE = {"SUBMITTING", "TRACKING", "COLLECTING"}
_QUEUED = {"WAITING", "RETRY_WAIT"}


def summarize(result, pool=None):
    """Compact, actionable digest of a status; the full rows remain authoritative.

    Built from cached receipts and local advisory history only. Expected times
    are medians of past successful runs, not deadlines or promises.
    """
    rows = result.get("jobs") or []
    supervisor = result.get("supervisor") or {}
    counts = {"total": len(rows), "passed": 0, "failed": 0, "rejected": 0, "blocked": 0,
              "running": 0, "queued": 0}
    attention, pending = [], []
    for row in rows:
        script = (row.get("input") or {}).get("script")
        status, collection = row.get("status") or {}, row.get("collection") or {}
        phase = row.get("phase")
        if phase == "DONE" and _finished_success(row):
            counts["passed"] += 1
            continue
        if phase == "DONE":
            counts["failed"] += 1
            attention.append({"script": script, "request_id": row.get("request_id"), "phase": phase,
                              "outcome": status.get("outcome"),
                              "evidence": collection.get("report") or collection.get("pool_report"),
                              "log": collection.get("log") or collection.get("diagnostic_log")})
            continue
        if phase == "REJECTED":
            counts["rejected"] += 1
            attention.append({"script": script, "request_id": row.get("request_id"), "phase": phase,
                              "error": status.get("error") or row.get("first_error")})
            continue
        if phase in {"BLOCKED", "COLLECTION_BLOCKED"}:
            counts["blocked"] += 1
            attention.append({"script": script, "request_id": row.get("request_id"), "phase": phase,
                              "state": status.get("state"),
                              "error": row.get("collection_error") or status.get("error")})
        elif phase in _QUEUED:
            counts["queued"] += 1
            pending.append(script)
        elif phase in _ACTIVE:
            counts["running"] += 1
            pending.append(script)
    overall = result.get("result", "INCOMPLETE")
    active = bool(result.get("supervisor_active"))
    state = supervisor.get("state")
    if overall == "PASSED":
        action = "none: every test passed with recorded verified evidence (status does not rehash artifacts)"
    elif not active and not result.get("source_frozen") and not rows and (
            state == "SNAPSHOTTING"
            or state == "ERROR" and "snapshot preparation was interrupted" in str(supervisor.get("error"))):
        action = "snapshot was interrupted before any dispatch; sim_test_launch with a new request_id"
    elif state == "ERROR" and not active:
        action = "inspect supervisor.error; then sim_test_recover with the same request_id"
    elif not active and overall == "INCOMPLETE" and (result.get("recovery_required") or state not in {None, "ACCEPTED"}):
        action = "sim_test_recover with the same request_id (supervisor is not running)"
    elif not active and overall == "INCOMPLETE":
        action = ("poll sim_test_status; if supervisor stays ACCEPTED and inactive for about 30 s, "
                  "sim_test_recover with the same request_id")
    elif overall == "FAILED":
        action = "inspect attention[].evidence and attention[].log; fix and launch a new request_id"
    elif counts["blocked"] and not counts["running"] and not counts["queued"]:
        action = ("blocked rows cannot finish on their own: inspect attention[] and run "
                  "testctl pool status/recover with each row request_id; never resubmit them under a new ID")
    else:
        action = "poll sim_test_status"
    summary = {"result": overall, **counts, "attention": attention, "next_action": action}
    if overall == "INCOMPLETE" and pool is not None:
        try:
            history = pool.history()
            expected = [expected_seconds(history, script) for script in pending]
        except Exception:  # advisory only; status must still answer
            expected = []
        known = [value for value in expected if value is not None]
        if known:
            # Serial sum of fleet-best medians for queued and running tests;
            # parallel hosts finish sooner and running tests may be near done.
            summary["pending_test_seconds_serial"] = round(sum(known), 1)
            summary["unmeasured_pending_tests"] = len(expected) - len(known)
        summary["suggested_poll_seconds"] = int(min(30, max(2, min(known) if known else 10)))
    return summary


def recover(request_id, *, config=None):
    pool = Pool(config or default_config())
    directory = _directory(pool, request_id)
    request = _request(directory, request_id)
    if digest(pool.config_path) != request["config_sha256"]:
        raise ValueError("pool configuration changed; restore the original configuration before recovery")
    if (directory / "batch.json").exists():
        batch = _read(directory / "batch.json")
        if batch.get("result") in {"PASSED", "FAILED"} and not reobservation_ids(pool, batch["jobs"]):
            return status(request_id, config=config)
    if not (directory / "manifest.json").exists() and not (directory / "batch.json").exists():
        supervisor = _read(directory / "supervisor.json") if (directory / "supervisor.json").exists() else {}
        if supervisor.get("state") not in {None, "ACCEPTED"} and not _active(directory):
            raise ValueError("snapshot preparation was interrupted before any dispatch; "
                             "use sim_test_launch with a new request_id for the current source")
    _start(directory)  # worker.lock excludes concurrent supervisors
    return status(request_id, config=config)


def supervise(directory):
    directory = Path(directory).resolve()
    # A status observer briefly holds worker.lock to test liveness; retry so a
    # freshly spawned supervisor is not lost to that probe.
    deadline = time.monotonic() + 3
    while True:
        try:
            guard = Singleton(directory / "worker.lock")
            break
        except OSError:
            if time.monotonic() >= deadline:
                return
            time.sleep(0.1)
    state_path = directory / "supervisor.json"
    def update(state, **extra):
        write_json(state_path, {"state": state, "updated_at": time.time(), **extra})
    try:
        request = _read(directory / "request.json")
        if digest(request["config"]) != request["config_sha256"]:
            raise ValueError("pool configuration changed; restore it before recovery")
        pool = Pool(request["config"])
        manifest = directory / "manifest.json"
        if not manifest.exists():
            previous = _read(state_path) if state_path.exists() else {}
            if previous.get("state") != "ACCEPTED":
                raise ValueError("snapshot preparation was interrupted; no tests dispatched; use a new request_id for current source")
            update("SNAPSHOTTING")
            snapshot = pool.snapshot(Path(request["source"]))
            write_json(manifest, {"snapshot": str(snapshot), "jobs": request["jobs"]})
        deadline = time.monotonic() + 3600
        while time.monotonic() < deadline:
            update("RUNNING")
            batch_path = directory / "batch.json"
            if batch_path.exists():
                for row in _read(batch_path)["jobs"]:
                    if row["phase"] == "BLOCKED" and (pool.root / "jobs" / (row["request_id"] + ".json")).exists():
                        try:
                            pool.recover(row["request_id"])
                        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError):
                            pass  # retry only this exact receipt on the next observation
            batch = run_batch(pool, request["config"], manifest, batch_path,
                              timeout=min(30, max(0.1, deadline - time.monotonic())))
            if batch["result"] in {"PASSED", "FAILED"}:
                update("FINISHED", result=batch["result"])
                return
            update("WAITING", result="INCOMPLETE")
            time.sleep(5)
        update("INCOMPLETE", detail="Supervisor observation deadline reached; recover the same request to continue. Remote jobs are not cancelled.")
    except Exception as error:
        update("ERROR", error=str(error))
    finally:
        guard.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", required=True)
    supervise(parser.parse_args().worker)
