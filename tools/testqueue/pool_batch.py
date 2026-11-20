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
from tools.testqueue.collection import FORMAT as COLLECTION_FORMAT
from tools.testqueue.pool import Pool, SubmissionDeferred, SubmissionRejected
from tools.testqueue.presets import scheduling, validate

BATCH_VERSION = 2
RETRY_INITIAL_SECONDS = 0.25
RETRY_MAX_SECONDS = 30.0


def _error_text(error):
    """Typed refusals read as written; anything else names its type (TQ-05-F0.6).

    A bare ``str(KeyError('log'))`` reached agents as the reason "'log'".
    """
    text = str(error)
    if isinstance(error, (ValueError, OSError, RuntimeError)) and text:
        return text
    return f"{type(error).__name__}: {text}" if text else type(error).__name__


def _backoff(attempts):
    return min(RETRY_MAX_SECONDS, RETRY_INITIAL_SECONDS * 2 ** min(max(attempts, 1) - 1, 16))


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
        if not isinstance(item, dict) or set(item) - {"script", "platform", "require", "timeout", "host", "rendering_driver"}:
            raise ValueError("job has unknown fields")
        driver = item.get("rendering_driver")
        if driver is not None and driver not in {"vulkan", "opengl3"}:
            raise ValueError("rendering_driver must be vulkan or opengl3")
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
                     "timeout": options["timeout"], "host": host,
                     **({"rendering_driver": driver} if driver else {})})
    return snapshot, jobs


def _finished_success(row):
    status = row.get("status") or {}
    collection = row.get("collection") or {}
    return (row["phase"] == "DONE" and status.get("state") == "FINISHED"
            and status.get("outcome") == "PASSED" and status.get("evidence") == "COMPLETE"
            and status.get("cleanup") == "CONFIRMED" and collection.get("pool_job") == row["request_id"]
            and collection.get("pool_outcome") == "PASSED" and collection.get("diagnostic_only") is False
            and collection.get("collection_format") == COLLECTION_FORMAT)


def _result(state):
    phases = [row["phase"] for row in state["jobs"]]
    if all(phase in {"DONE", "REJECTED"} for phase in phases):
        return "PASSED" if all(_finished_success(row) for row in state["jobs"]) else "FAILED"
    return "INCOMPLETE"


def _script_specific_refusal(submission):
    """A per-script history refusal does not prove other scripts are ineligible."""
    candidates = (submission.get("decision") or {}).get("candidates") or []
    return any(isinstance(reason, str) and reason.startswith("INVALID_INVENTORY: historical duration")
               for candidate in candidates if isinstance(candidate, dict)
               for reason in candidate.get("reasons") or [])


def submission_order(pool, rows):
    """Longest expected test first, so short tests fill gaps near the end.

    Measured medians come from advisory pool history; an unmeasured test uses
    its timeout. Ties keep manifest order. Ordering never changes which host is
    eligible, and every row is still submitted exactly as before.
    """
    estimate = getattr(pool, "expected_seconds", None)
    known = {}
    for script in dict.fromkeys(row["input"]["script"] for row in rows):
        try:
            known[script] = estimate(script) if callable(estimate) else None
        except Exception:  # advisory: unreadable history keeps manifest order
            known[script] = None
    def expected(item):
        index, row = item
        value = known[row["input"]["script"]]
        return (-(value if type(value) in (int, float) and math.isfinite(value) else row["input"]["timeout"]), index)
    return [row for _, row in sorted(enumerate(rows), key=expected)]


def reobservation_ids(pool, rows):
    """Find stale or previously unverified terminal rows without RPC."""
    return {row["request_id"] for row in rows if row.get("phase") in {"DONE", "COLLECTING", "COLLECTION_BLOCKED"}
            and (pool.needs_reobservation(row["request_id"], row.get("status") or {})
                 or row.get("phase") == "DONE"
                 and (row.get("collection") or {}).get("collection_format") != COLLECTION_FORMAT)}


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
        failed_verifications = set()
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
                        "reason": "Legacy outcome or unverified collection requires original-authority observation"})
                    row.update(phase="TRACKING", status={"state": "UNKNOWN", "cleanup": "UNCONFIRMED",
                                                        "error": "Reobserving legacy outcome or unverified collection"})
                    changed = True
                collection = row.get("collection") or {}
                if row["phase"] == "DONE" and (collection.get("pool_job") != row["request_id"]
                        or collection.get("pool_outcome") != (row.get("status") or {}).get("outcome")):
                    if (row.get("status") or {}).get("state") != "FINISHED":
                        raise ValueError("completed row lacks a finished status")
                    row["phase"] = "COLLECTING"
                    changed = True
                if row["phase"] == "DONE":
                    try:
                        # A saved passing result is usable only while its
                        # original collection still verifies. This reads local
                        # receipts and artifacts only, even if the host is offline.
                        pool.verify_collection(row["request_id"], collection)
                    except Exception as error:
                        row.setdefault("previous_results", []).append({
                            "status": row.get("status"), "collection": collection,
                            "reason": "Saved collection failed local verification", "error": str(error)})
                        row.update(phase="COLLECTION_BLOCKED", collection_error=_error_text(error))
                        failed_verifications.add(row["request_id"])
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
        # Preserve failed generations for inspection; a later invocation can
        # retry collection from the same authority without launching new work.
        checked_collections = set(failed_verifications)
        retry_ready = {row["request_id"]: time.monotonic() + min(RETRY_MAX_SECONDS,
                       max(0, row["retry_after"] - time.time())) for row in state["jobs"]
                       if row["phase"] == "RETRY_WAIT"}
        order = submission_order(pool, state["jobs"])
        while True:
            # Every WAITING answer in this pass proves that no host was eligible
            # for its (platform, host) constraint. Rows whose constraint is the
            # same or narrower would only repeat the full host probe; they are
            # reconsidered on the next pass instead.
            saturated = set()
            for row in order:
                if row["phase"] not in {"WAITING", "RETRY_WAIT"}:
                    continue
                if row["phase"] == "RETRY_WAIT" and time.monotonic() < retry_ready[row["request_id"]]:
                    continue
                if time.monotonic() >= deadline:
                    break
                constraint = (row["input"]["platform"], row["input"]["host"])
                if any(platform in {"any", constraint[0]} and host in {None, constraint[1]}
                       for platform, host in saturated):
                    continue
                row.update(phase="SUBMITTING", submission_attempts=row.get("submission_attempts", 0) + 1)
                write_json(state_path, state)
                try:
                    job = row["input"]
                    submission = pool.submit(snapshot, job["script"], platform=job["platform"],
                                             require=job["require"], timeout=job["timeout"],
                                             host_id=job["host"], request_id=row["request_id"],
                                             expected_manifest_sha256=state["snapshot_manifest_sha256"],
                                             **({"rendering_driver": job["rendering_driver"]}
                                                if job.get("rendering_driver") else {}))
                    if submission.get("state") == "WAITING":
                        row.update(phase="WAITING", status=submission)
                        if not _script_specific_refusal(submission):
                            saturated.add(constraint)
                    elif submission.get("job") == row["request_id"]:
                        row.update(phase="TRACKING", status=submission)
                    else:
                        raise ValueError("pool returned an invalid submission receipt")
                except SubmissionRejected as error:
                    row.update(phase="REJECTED", status=error.status)
                    row.setdefault("first_error", str(error))
                except SubmissionDeferred as error:
                    delay = _backoff(row["submission_attempts"])
                    row.update(phase="RETRY_WAIT", retry_after=time.time() + delay,
                               status={"state": "WAITING", "reason_code": error.reason_code, "error": str(error),
                                       **({"transfer": error.detail} if error.detail else {})})
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
                    if status.get("reason_code") == "TRANSFER_DEFERRED":
                        # Proved nondispatched (e.g. a crash right after the deferral was recorded):
                        # resubmit the SAME id so the pool re-enters the transfer.
                        delay = _backoff(row.get("submission_attempts", 1))
                        retry_ready[row["request_id"]] = time.monotonic() + delay
                        row.update(phase="RETRY_WAIT", retry_after=time.time() + delay, status=status)
                    else:
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
                    row.update(phase="COLLECTION_BLOCKED", collection_error=_error_text(error))
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
