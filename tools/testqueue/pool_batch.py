"""Run independent checked tests through the pool with restartable row receipts.

The batch is a client of the host authorities; it never retries a failed or
uncertain attempt. A row request ID is persisted before submit, and the pool
must recover the same receipt when that ID is submitted again. WAITING means
no host was selected and may be reconsidered; a timeout does not cancel jobs.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from functools import partial
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import threading
import time
import uuid

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from tools.testqueue.common import Singleton, write_json
from tools.testqueue.collection import FORMAT as COLLECTION_FORMAT
from tools.testqueue.pool import Pool, SubmissionDeferred, SubmissionRejected
from tools.testqueue.pool_policy import platform_set
from tools.testqueue.presets import scheduling, validate

BATCH_VERSION = 2
RETRY_INITIAL_SECONDS = 0.25
RETRY_MAX_SECONDS = 30.0
MAX_HOST_LANES = 4


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
        try:
            platform_set(platform)  # 'any', one OS, or a list of OSes (TQ-07-D1)
        except ValueError:
            raise ValueError("invalid job platform") from None
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


def _refusal_causes(status):
    # Free space fluctuates. Back off the same host/cause while preserving
    # the newest byte counts in the full decision.
    return {candidate["host"]: sorted({reason.partition(":")[0] for reason in candidate["reasons"]})
            for candidate in (status.get("decision") or {}).get("candidates", [])}


def _reclaim_for_space(pool, submission, deadline):
    """Ask the pool to reclaim remote hosts that refused for disk space; advisory.

    The sweep's budget never exceeds this observation window.
    """
    reclaim = getattr(pool, "reclaim_for_space", None)
    if not callable(reclaim):
        return
    try:
        budget = min(Pool.AUTO_GC_BUDGET_SECONDS, deadline - time.monotonic())
        if budget >= 1:
            reclaim(submission.get("decision"), budget_seconds=budget)
    except Exception:  # storage work never changes a row's placement state
        pass


WAIT_HISTORY_ENTRIES = 10


def _record_wait(row, submission):
    now = time.time()
    previous = row.get("admission_wait") or {}
    causes = _refusal_causes(submission)
    if previous and _refusal_causes(row.get("status") or {}) == causes:
        count, first = previous["consecutive"] + 1, previous["first_observed_at"]
    else:
        count, first = 1, now
    delay = _backoff(count)
    # TQ-07-D7: why the row waited survives its placement (admission_wait does
    # not). One entry per distinct per-host refusal, bounded.
    history = row.setdefault("wait_history", [])
    if history and history[-1].get("causes") == causes:
        history[-1].update(last_at=now, count=history[-1].get("count", 1) + 1)
    else:
        history.append({"causes": causes, "first_at": now, "last_at": now, "count": 1})
        del history[:-WAIT_HISTORY_ENTRIES]
    row.update(phase="WAITING", status=submission, retry_after=now + delay,
               admission_wait={"first_observed_at": first, "last_observed_at": now, "consecutive": count})
    return delay


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


def _host_lanes(rows):
    """Run disjoint pinned hosts or specific platform requirements in parallel."""
    by_host = all(row["input"]["host"] is not None for row in rows)
    # Overlapping OS constraints ('any' or a list) share one placement loop.
    if not by_host and any(not isinstance(row["input"]["platform"], str) or row["input"]["platform"] == "any"
                           for row in rows):
        return [rows]
    groups = {}
    for row in rows:
        key = row["input"]["host" if by_host else "platform"]
        groups.setdefault(key, []).append(row)
    lanes = [[] for _ in range(min(len(groups), MAX_HOST_LANES))]
    for index, group in enumerate(groups.values()):
        lanes[index % len(lanes)].extend(group)
    return lanes


def _drive_rows(pool, snapshot, manifest_sha256, rows, failed_verifications, deadline, poll_interval, publish, stopped):
    """Drive rows serially. Publication completes before a dispatch can proceed."""
    checked_blocked = set()
    # Preserve failed generations for inspection; a later invocation can
    # retry collection from the same authority without launching new work.
    checked_collections = set(failed_verifications)
    retry_ready = {row["request_id"]: time.monotonic() + min(RETRY_MAX_SECONDS,
                   max(0, row["retry_after"] - time.time())) for row in rows
                   if row["phase"] in {"WAITING", "RETRY_WAIT"} and "retry_after" in row}
    order = submission_order(pool, rows)

    def before_dispatch(row):
        row.update(phase="SUBMITTING", status={"state": "SUBMITTING", "stage": "placement"})
        row.pop("retry_after", None)
        row.pop("admission_wait", None)
        publish(row)

    while not stopped.is_set():
        # Every WAITING answer in this pass proves that no host was eligible
        # for its (platform, host) constraint. Rows whose constraint is the
        # same or narrower would only repeat the full host probe; they are
        # reconsidered on the next pass instead.
        saturated = set()
        # A slow refusal can consume a whole observation window. Give
        # less-probed rows their turn, retaining duration order among ties.
        for row in sorted(order, key=lambda item: item.get("submission_attempts", 0)):
            if row["phase"] not in {"WAITING", "RETRY_WAIT"}:
                continue
            if time.monotonic() < retry_ready.get(row["request_id"], 0):
                continue
            if stopped.is_set() or time.monotonic() >= deadline:
                break
            constraint = (platform_set(row["input"]["platform"]), row["input"]["host"], row["input"].get("rendering_driver"))
            # A WAITING answer for a constraint proves no host was eligible for it,
            # so a row whose OS set is the same or narrower would only re-probe.
            if any(constraint[0] <= platforms and host in {None, constraint[1]}
                   and driver == constraint[2] for platforms, host, driver in saturated):
                continue
            row["submission_attempts"] = row.get("submission_attempts", 0) + 1
            started = time.monotonic()
            row["placement_started_at"] = time.time()
            row.setdefault("first_placement_at", row["placement_started_at"])
            try:
                job = row["input"]
                submission = pool.submit(snapshot, job["script"], platform=job["platform"],
                                         require=job["require"], timeout=job["timeout"],
                                         host_id=job["host"], request_id=row["request_id"],
                                         expected_manifest_sha256=manifest_sha256,
                                         before_dispatch=partial(before_dispatch, row),
                                         **({"rendering_driver": job["rendering_driver"]}
                                            if job.get("rendering_driver") else {}))
                if submission.get("state") == "WAITING":
                    delay = _record_wait(row, submission)
                    retry_ready[row["request_id"]] = time.monotonic() + delay
                    if not _script_specific_refusal(submission):
                        saturated.add(constraint)
                    _reclaim_for_space(pool, submission, deadline)
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
            if row["phase"] != "WAITING":
                row.pop("admission_wait", None)
            if row["phase"] not in {"WAITING", "RETRY_WAIT"}:
                row.pop("retry_after", None)
            row["last_placement_at"] = time.time()
            timings = row.setdefault("coordinator_seconds", {})
            timings["placement"] = timings.get("placement", 0.0) + time.monotonic() - started
            publish(row)

        for row in rows:
            if row["phase"] not in {"TRACKING", "BLOCKED"} or row["request_id"] in checked_blocked:
                continue
            if stopped.is_set() or time.monotonic() >= deadline:
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
                elif status["state"] == "FINISHED" and status.get("outcome") == "NOT_DISPATCHED":
                    # Proved never to have run (local tombstone or operator
                    # reconciliation). There is no evidence to collect.
                    row.update(phase="REJECTED", status=status)
                    row.setdefault("first_error", status.get("error") or "not dispatched")
                else:
                    phase = "COLLECTING" if status["state"] == "FINISHED" else (
                        "BLOCKED" if status["state"] in {"UNKNOWN", "SUBMISSION_UNCONFIRMED", "NOT_FOUND"} else "TRACKING")
                    row.update(phase=phase, status=status)
            except Exception as error:
                row.update(phase="BLOCKED", status={"state": "UNKNOWN", "error": str(error)})
                row.setdefault("first_error", str(error))
            if row["phase"] == "BLOCKED":
                checked_blocked.add(row["request_id"])
            publish(row)

        for row in rows:
            if row["phase"] not in {"COLLECTING", "COLLECTION_BLOCKED"} or row["request_id"] in checked_collections:
                continue
            if stopped.is_set() or time.monotonic() >= deadline:
                break
            started = time.monotonic()
            try:
                report = pool.collect(row["request_id"])
                if (not isinstance(report, dict) or report.get("pool_job") != row["request_id"]
                        or report.get("pool_outcome") != row["status"].get("outcome")):
                    raise ValueError("pool returned an invalid collection report")
                row.update(phase="DONE", collection=report)
                row.pop("collection_error", None)
                # TQ-07-G2: collect, then reclaim at once, so a host does not
                # fill with collected jobs between sweeps. Advisory: a refusal
                # leaves the job to the next sweep and never changes the row.
                reclaim = getattr(pool, "reclaim_collected", None)
                if callable(reclaim):
                    try:
                        row["storage_reclaim"] = reclaim(row["request_id"], report)
                    except Exception as error:
                        row["storage_reclaim"] = {"error": _error_text(error)}
            except Exception as error:
                # Collection may be retried on a later invocation; the test never is.
                row.update(phase="COLLECTION_BLOCKED", collection_error=_error_text(error))
            checked_collections.add(row["request_id"])
            timings = row.setdefault("coordinator_seconds", {})
            timings["collection"] = timings.get("collection", 0.0) + time.monotonic() - started
            publish(row)

        if (time.monotonic() >= deadline
                or all(row["phase"] in {"DONE", "REJECTED", "BLOCKED", "COLLECTION_BLOCKED"} for row in rows)):
            return
        delay = poll_interval
        if all(row["phase"] in {"DONE", "REJECTED", "BLOCKED", "COLLECTION_BLOCKED"}
               or row["phase"] in {"WAITING", "RETRY_WAIT"} and row["request_id"] in retry_ready
               for row in rows):
            pending = [retry_ready[row["request_id"]] for row in rows
                       if row["phase"] in {"WAITING", "RETRY_WAIT"}]
            delay = max(delay, min(pending) - time.monotonic())
        time.sleep(min(max(0, delay), max(0, deadline - time.monotonic())))


def run_batch(pool, config, manifest, state_path, *, timeout=600, poll_interval=2):
    """Run or resume a batch under its persistent state-file lock.

    The pool invokes the callback before publishing a dispatch receipt. A crash
    during planning can re-enter with the original ID. Once SUBMITTING is
    durable, observe the original attempt even when its receipt is missing.
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
            if (state.get("version") not in {1, BATCH_VERSION}
                    or state.get("manifest_sha256") != manifest_digest or state.get("snapshot") != str(snapshot)
                    or [row.get("input") for row in state.get("jobs", [])] != jobs):
                raise ValueError("batch inputs changed; preserve and recover the original state")
            changed = False
            if state.get("config_sha256") != config_digest:
                # TQ-07-A1: each dispatched row's receipt binds its own destination,
                # so a configuration edit (a new host, another host's settings) no
                # longer strands the batch. Keep the history for evidence.
                history = state.setdefault("config_history", [])
                history.append({"config_sha256": state.get("config_sha256"), "replaced_at": time.time()})
                state["config_sha256"] = config_digest
                changed = True
            ids = [row.get("request_id") for row in state["jobs"]]
            if (len(set(ids)) != len(ids) or any(not isinstance(item, str) or not item.isalnum() for item in ids)
                    or any(row.get("phase") not in {"WAITING", "SUBMITTING", "RETRY_WAIT", "REJECTED",
                                                      "TRACKING", "BLOCKED", "COLLECTING",
                                                      "COLLECTION_BLOCKED", "DONE"} for row in state["jobs"])):
                raise ValueError("invalid batch state")
            # Older batch receipts could mark FINISHED rows done without
            # collecting their evidence. Recover those same IDs, never submit.
            reobserve = reobservation_ids(pool, state["jobs"])
            for row in state["jobs"]:
                attempts = row.get("submission_attempts", 0)
                if type(attempts) is not int or attempts < 0:
                    raise ValueError("invalid batch submission count")
                if (row["phase"] == "RETRY_WAIT" or row["phase"] == "WAITING" and "retry_after" in row) and (
                        type(row.get("retry_after")) not in (int, float)
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

        # The process keeps the batch singleton until every started call returns.
        # Each lane mutates private rows. Only publish() can change the shared
        # journal, including the SUBMITTING write required by the pool callback.
        rows = state["jobs"]
        indices = {row["request_id"]: i for i, row in enumerate(rows)}
        lock = threading.Lock()
        stopped = threading.Event()
        journal_error = None

        def publish(row):
            nonlocal journal_error
            with lock:
                if journal_error is not None:
                    raise RuntimeError(f"batch journal publication stopped: {journal_error}") from journal_error
                if stopped.is_set():
                    raise RuntimeError("batch observer stopped")
                index = indices[row["request_id"]]
                if rows[index] == row:
                    return
                try:
                    rows[index] = deepcopy(row)
                    state["result"] = _result(state)
                    write_json(state_path, state)
                except BaseException as error:
                    journal_error = error
                    stopped.set()
                    raise

        deadline = time.monotonic() + timeout

        def drive(group):
            try:
                _drive_rows(pool, snapshot, state["snapshot_manifest_sha256"], group, failed_verifications,
                           deadline, poll_interval, publish, stopped)
            except BaseException:
                stopped.set()
                raise

        groups = _host_lanes(deepcopy(rows))
        if len(groups) == 1:
            drive(groups[0])
        else:
            with ThreadPoolExecutor(max_workers=len(groups)) as executor:
                list(executor.map(drive, groups))
        result = _result(state)
        if state.get("result") != result:
            state["result"] = result
            write_json(state_path, state)
        return state
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
