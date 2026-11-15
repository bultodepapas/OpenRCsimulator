"""Run independent checked tests through the pool with restartable row receipts.

The batch is a client of the host authorities; it never retries a failed or
uncertain attempt. A row request ID is persisted before submit, and the pool
must recover the same receipt when that ID is submitted again. WAITING means
no host was selected and may be reconsidered; a timeout does not cancel jobs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import time
import uuid

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue.common import Singleton, write_json
from tools.testqueue.pool import Pool, SubmissionDeferred, SubmissionRejected
from tools.testqueue.presets import scheduling, validate

BATCH_VERSION = 2
RETRY_INITIAL_SECONDS = 0.25
RETRY_MAX_SECONDS = 30.0


def _digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _manifest(path):
    path = Path(path).resolve()
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or set(value) != {"snapshot", "jobs"}:
        raise ValueError("manifest must contain snapshot and jobs")
    if not isinstance(value["snapshot"], str) or not value["snapshot"]:
        raise ValueError("snapshot must be a path")
    snapshot = Path(value["snapshot"])
    if not snapshot.is_absolute():
        snapshot = path.parent / snapshot
    snapshot = snapshot.resolve()
    if not isinstance(value["jobs"], list) or not value["jobs"]:
        raise ValueError("jobs must be a nonempty list")
    jobs = []
    for item in value["jobs"]:
        if not isinstance(item, dict) or set(item) - {"script", "platform", "require", "timeout", "host"}:
            raise ValueError("job has unknown fields")
        platform = item.get("platform", "any")
        if not isinstance(platform, str) or platform not in {"any", "windows", "linux", "darwin"}:
            raise ValueError("invalid job platform")
        host = item.get("host")
        if host is not None and (not isinstance(host, str) or not host):
            raise ValueError("host must be a nonempty ID")
        options = validate("checked", {"script": item.get("script"), "require": item.get("require", []),
                                       "timeout": item.get("timeout", 90), "headless": True,
                                       "workload": "functional"})
        if scheduling("checked", options)["workload"] == "performance":
            raise ValueError("performance checks require a dedicated same-host campaign")
        jobs.append({"script": options["script"], "platform": platform, "require": options["require"],
                     "timeout": options["timeout"], "host": host})
    return snapshot, jobs


def _finished_success(row):
    status = row.get("status") or {}
    collection = row.get("collection") or {}
    return (row["phase"] == "DONE" and status.get("state") == "FINISHED"
            and status.get("outcome") == "PASSED" and status.get("evidence") == "COMPLETE"
            and status.get("cleanup") == "CONFIRMED" and collection.get("pool_job") == row["request_id"]
            and collection.get("pool_outcome") == "PASSED")


def _result(state):
    phases = [row["phase"] for row in state["jobs"]]
    if all(phase in {"DONE", "REJECTED"} for phase in phases):
        return "PASSED" if all(_finished_success(row) for row in state["jobs"]) else "FAILED"
    return "INCOMPLETE"


def reobservation_ids(pool, rows):
    """Find stale terminal rows using coordinator receipts only, without RPC."""
    return {row["request_id"] for row in rows if row.get("phase") in {"DONE", "COLLECTING", "COLLECTION_BLOCKED"}
            and pool.needs_reobservation(row["request_id"], row.get("status") or {})}


def run_batch(pool, config, manifest, state_path, *, timeout=600, poll_interval=2):
    """Run or resume a batch under its persistent state-file lock.

    SUBMITTING is durable before a call. After interruption, observe its original
    ID; an absent receipt cannot authorize a new submit. Repeated
    invocations can observe recovery of an UNKNOWN attempt but cannot relaunch it.
    Config, manifest and snapshot-manifest identities are bound to the batch.
    """
    if type(timeout) not in (int, float) or not math.isfinite(timeout) or timeout <= 0:
        raise ValueError("timeout must be positive and finite")
    if type(poll_interval) not in (int, float) or not math.isfinite(poll_interval) or poll_interval < 0:
        raise ValueError("poll_interval must be nonnegative and finite")
    config, manifest, state_path = Path(config).resolve(), Path(manifest).resolve(), Path(state_path).resolve()
    snapshot, jobs = _manifest(manifest)
    snapshot_manifest = snapshot / "manifest.json"
    if state_path in {config, manifest, snapshot_manifest}:
        raise ValueError("state path must not overwrite an input")
    config_digest, manifest_digest = _digest(config), _digest(manifest)
    guard = Singleton(Path(str(state_path) + ".lock"))
    try:
        if state_path.exists():
            state = json.loads(state_path.read_text(encoding="utf-8"))
            if (state.get("version") not in {1, BATCH_VERSION} or state.get("config_sha256") != config_digest
                    or state.get("manifest_sha256") != manifest_digest or state.get("snapshot") != str(snapshot)
                    or [row.get("input") for row in state.get("jobs", [])] != jobs):
                raise ValueError("batch inputs changed; preserve and recover the original state")
            ids = [row.get("request_id") for row in state["jobs"]]
            if (len(set(ids)) != len(ids) or any(not isinstance(item, str) or not item.isalnum() for item in ids)
                    or any(row.get("phase") not in {"WAITING", "SUBMITTING", "RETRY_WAIT", "REJECTED",
                                                      "TRACKING", "BLOCKED", "COLLECTING",
                                                      "COLLECTION_BLOCKED", "DONE"} for row in state["jobs"])):
                raise ValueError("invalid batch state")
            # Older batch receipts could mark FINISHED rows done without
            # collecting their evidence. Recover those same IDs, never submit.
            changed = False
            reobserve = reobservation_ids(pool, state["jobs"])
            for row in state["jobs"]:
                attempts = row.get("submission_attempts", 0)
                if type(attempts) is not int or attempts < 0:
                    raise ValueError("invalid batch submission count")
                if row["phase"] == "RETRY_WAIT" and (type(row.get("retry_after")) not in (int, float)
                        or not math.isfinite(row["retry_after"])):
                    raise ValueError("invalid batch retry deadline")
                if row["phase"] == "SUBMITTING" or state["version"] == 1 and row["phase"] == "WAITING":
                    # v1 WAITING could be a crash after acceptance. Do not infer
                    # nonexecution from receipt absence or revalidate its inputs.
                    row.update(phase="TRACKING", status={"state": "UNKNOWN", "cleanup": "UNCONFIRMED",
                        "error": "Interrupted submission requires original-identity observation"})
                    changed = True
                if row["request_id"] in reobserve:
                    row.setdefault("previous_results", []).append({
                        "status": row.get("status"), "collection": row.pop("collection", None),
                        "reason": "Legacy nonexecution result requires original-authority observation"})
                    row.update(phase="TRACKING", status={"state": "UNKNOWN", "cleanup": "UNCONFIRMED",
                                                        "error": "Reobserving legacy nonexecution result"})
                    changed = True
                collection = row.get("collection") or {}
                if row["phase"] == "DONE" and (collection.get("pool_job") != row["request_id"]
                        or collection.get("pool_outcome") != (row.get("status") or {}).get("outcome")):
                    if (row.get("status") or {}).get("state") != "FINISHED":
                        raise ValueError("completed row lacks a finished status")
                    row["phase"] = "COLLECTING"
                    changed = True
            if state["version"] != BATCH_VERSION:
                state["migrated_from_version"] = state["version"]
                state["version"] = BATCH_VERSION
                changed = True
            if changed:
                state["result"] = _result(state)
                write_json(state_path, state)
        else:
            state = {"version": BATCH_VERSION, "config_sha256": config_digest, "manifest_sha256": manifest_digest,
                     "snapshot": str(snapshot), "snapshot_manifest_sha256": _digest(snapshot_manifest),
                     "jobs": [{"request_id": uuid.uuid4().hex, "input": job, "phase": "WAITING"}
                              for job in jobs]}
            # Every row is durable before the first host can receive a request.
            write_json(state_path, state)

        deadline = time.monotonic() + timeout
        checked_blocked = set()
        checked_collections = set()
        retry_ready = {row["request_id"]: time.monotonic() + min(RETRY_MAX_SECONDS,
                       max(0, row["retry_after"] - time.time())) for row in state["jobs"]
                       if row["phase"] == "RETRY_WAIT"}
        while True:
            for row in state["jobs"]:
                if row["phase"] not in {"WAITING", "RETRY_WAIT"}:
                    continue
                if row["phase"] == "RETRY_WAIT" and time.monotonic() < retry_ready[row["request_id"]]:
                    continue
                if time.monotonic() >= deadline:
                    break
                row.update(phase="SUBMITTING", submission_attempts=row.get("submission_attempts", 0) + 1)
                write_json(state_path, state)
                try:
                    job = row["input"]
                    submission = pool.submit(snapshot, job["script"], platform=job["platform"],
                                             require=job["require"], timeout=job["timeout"],
                                             host_id=job["host"], request_id=row["request_id"],
                                             expected_manifest_sha256=state["snapshot_manifest_sha256"])
                    if submission.get("state") == "WAITING":
                        row.update(phase="WAITING", status=submission)
                    elif submission.get("job") == row["request_id"]:
                        row.update(phase="TRACKING", status=submission)
                    else:
                        raise ValueError("pool returned an invalid submission receipt")
                except SubmissionRejected as error:
                    row.update(phase="REJECTED", status=error.status)
                    row.setdefault("first_error", str(error))
                except SubmissionDeferred as error:
                    delay = min(RETRY_MAX_SECONDS, RETRY_INITIAL_SECONDS * 2 ** min(row["submission_attempts"] - 1, 16))
                    row.update(phase="RETRY_WAIT", retry_after=time.time() + delay,
                               status={"state": "WAITING", "reason_code": "SUBMISSION_DEFERRED", "error": str(error)})
                    row.setdefault("first_error", str(error))
                    retry_ready[row["request_id"]] = time.monotonic() + delay
                except Exception as error:
                    # The request may have crossed the dispatch boundary: no failover.
                    row.update(phase="BLOCKED", status={"state": "UNKNOWN", "error": str(error)})
                    row.setdefault("first_error", str(error))
                    checked_blocked.add(row["request_id"])
                write_json(state_path, state)

            for row in state["jobs"]:
                if row["phase"] not in {"TRACKING", "BLOCKED"} or row["request_id"] in checked_blocked:
                    continue
                if time.monotonic() >= deadline:
                    break
                try:
                    status = pool.status(row["request_id"])
                    if not isinstance(status, dict) or not isinstance(status.get("state"), str):
                        raise ValueError("pool returned an invalid status")
                    phase = "COLLECTING" if status["state"] == "FINISHED" else (
                        "BLOCKED" if status["state"] in {"UNKNOWN", "SUBMISSION_UNCONFIRMED", "NOT_FOUND"} else "TRACKING")
                    row.update(phase=phase, status=status)
                except Exception as error:
                    row.update(phase="BLOCKED", status={"state": "UNKNOWN", "error": str(error)})
                    row.setdefault("first_error", str(error))
                if row["phase"] == "BLOCKED":
                    checked_blocked.add(row["request_id"])
                write_json(state_path, state)

            for row in state["jobs"]:
                if row["phase"] not in {"COLLECTING", "COLLECTION_BLOCKED"} or row["request_id"] in checked_collections:
                    continue
                if time.monotonic() >= deadline:
                    break
                try:
                    report = pool.collect(row["request_id"])
                    if (not isinstance(report, dict) or report.get("pool_job") != row["request_id"]
                            or report.get("pool_outcome") != row["status"].get("outcome")):
                        raise ValueError("pool returned an invalid collection report")
                    row.update(phase="DONE", collection=report)
                    row.pop("collection_error", None)
                except Exception as error:
                    # Collection may be retried on a later invocation; the test never is.
                    row.update(phase="COLLECTION_BLOCKED", collection_error=str(error))
                checked_collections.add(row["request_id"])
                write_json(state_path, state)

            state["result"] = _result(state)
            write_json(state_path, state)
            if (state["result"] != "INCOMPLETE" or time.monotonic() >= deadline
                    or all(row["phase"] in {"DONE", "REJECTED", "BLOCKED", "COLLECTION_BLOCKED"} for row in state["jobs"])):
                return state
            delay = poll_interval
            if all(row["phase"] in {"DONE", "REJECTED", "BLOCKED", "COLLECTION_BLOCKED", "RETRY_WAIT"}
                   for row in state["jobs"]):
                pending = [retry_ready[row["request_id"]] for row in state["jobs"] if row["phase"] == "RETRY_WAIT"]
                delay = max(delay, min(pending) - time.monotonic())
            time.sleep(min(max(0, delay), max(0, deadline - time.monotonic())))
    finally:
        guard.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=os.environ.get("OPENRC_TESTPOOL_CONFIG"))
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--timeout", type=float, default=600)
    args = parser.parse_args(argv)
    if not args.config:
        parser.error("--config or OPENRC_TESTPOOL_CONFIG is required")
    result = run_batch(Pool(args.config), args.config, args.manifest, args.state, timeout=args.timeout)
    print(json.dumps(result, indent=2))
    return 0 if result["result"] == "PASSED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
