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
from tools.testqueue import agent_view
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
CREATE_BREAKAWAY_FROM_JOB = 0x01000000


def spawn_background(argv, output):
    """Start a supervisor that outlives the MCP client (TQ-05-F2.1).

    MCP clients (Claude Code, Codex) start their servers inside a Windows Job
    Object, so a plain child dies when the agent session closes. That left
    batches claiming RUNNING for days. Break away when the job allows it.
    If it does not, start normally; the watchdog resumes the batch later.
    """
    options = {"stdin": subprocess.DEVNULL, "stdout": output, "stderr": output,
               "cwd": str(REPO), "close_fds": True}
    if os.name != "nt":
        return subprocess.Popen(argv, start_new_session=True, **options)
    # A private hidden console, not DETACHED_PROCESS: every descendant
    # (git, ssh, Godot console wrappers, shells) inherits it instead of
    # opening its own visible window on the user's desktop.
    try:
        return subprocess.Popen(argv, creationflags=BACKGROUND_CREATIONFLAGS | CREATE_BREAKAWAY_FROM_JOB, **options)
    except PermissionError:
        return subprocess.Popen(argv, creationflags=BACKGROUND_CREATIONFLAGS, **options)


def _start(directory):
    with (directory / "supervisor.log").open("ab") as output:
        spawn_background([sys.executable, str(Path(__file__).resolve()), "--worker", str(directory)], output)


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


def status(request_id, detail="summary", *, config=None):
    """Read cached receipts, without network or rehashing collected artifacts.

    ``detail="summary"`` (default) returns one compact line per test with its
    typed waiting reason and failing lines; ``"full"`` returns the rows.
    """
    if detail not in {"summary", "full"}:
        raise ValueError("detail must be summary or full")
    full = _full_status(request_id, config=config)
    if detail == "full":
        return full
    if not full.get("jobs"):
        full = {**full, "request_jobs": _read(Path(full["receipt"]) / "request.json").get("jobs", [])}
    return agent_view.compact_status(full)


def fleet(refresh=False, *, config=None):
    """Cached fleet view: hosts, typed busy causes and local Godot processes."""
    return agent_view.fleet(Pool(config or default_config()), refresh=bool(refresh))


def list_requests(limit=20, *, config=None):
    return {"requests": agent_view.list_requests(Pool(config or default_config()), int(limit))}


RUN_POLL_SECONDS = 1.0
RUN_MAX_WAIT_SECONDS = 300


def run(jobs, request_id=None, source=None, wait_s=60, *, config=None):
    """Launch and wait up to ``wait_s`` for a final result in one call (TQ-05-F1.5).

    Without ``request_id`` a fresh one is generated, so a deliberate rerun is a
    new attempt. Repeating a call with the same explicit ID stays idempotent.
    Waiting only observes: a timeout returns the ticket and never cancels.
    """
    if not isinstance(wait_s, (int, float)) or not 0 <= wait_s <= RUN_MAX_WAIT_SECONDS:
        raise ValueError(f"wait_s must be 0-{RUN_MAX_WAIT_SECONDS} seconds")
    request_id = request_id or time.strftime("run-%Y%m%d-%H%M%S-") + os.urandom(3).hex()
    launch(request_id, jobs, source, config=config)
    deadline = time.monotonic() + wait_s
    time.sleep(min(RUN_POLL_SECONDS, wait_s))  # let the detached supervisor take its lock first
    while True:
        view = status(request_id, config=config)
        if view["summary"].get("result") in {"PASSED", "FAILED"} or time.monotonic() >= deadline:
            break
        if not view.get("supervisor_active") and view["summary"].get("next_action", "").startswith(
                ("sim_test_recover", "inspect", "snapshot", "source freeze")):
            break  # the supervisor stopped; waiting longer cannot change the answer
        time.sleep(min(RUN_POLL_SECONDS, max(0.0, deadline - time.monotonic())))
    view["waited_seconds"] = round(wait_s - max(0.0, deadline - time.monotonic()), 1)
    if view["summary"].get("result") not in {"PASSED", "FAILED"} and view.get("supervisor_active"):
        view["note"] = ("still running: call sim_test_status or sim_test_run again with this request_id; "
                        "waiting never cancels the tests")
    return view


def _full_status(request_id, *, config=None):
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
    attention, pending, waiting, progressing = [], [], {}, 0
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
            reason = agent_view._wait_reason(row, (row.get("input") or {}).get("platform"))
            if reason and reason["code"] != "QUEUED_IN_BATCH":
                waiting[reason["code"]] = waiting.get(reason["code"], 0) + 1
        elif phase in _ACTIVE:
            counts["running"] += 1
            pending.append(script)
            reason = agent_view._wait_reason(row, (row.get("input") or {}).get("platform")) \
                if phase == "SUBMITTING" else None
            if reason and reason["code"] != "QUEUED_IN_BATCH":
                waiting[reason["code"]] = waiting.get(reason["code"], 0) + 1
            else:
                progressing += 1
    overall = result.get("result", "INCOMPLETE")
    active = bool(result.get("supervisor_active"))
    state = supervisor.get("state")
    if overall == "PASSED":
        action = "none: every test passed with recorded verified evidence (status does not rehash artifacts)"
    elif not active and not result.get("source_frozen") and not rows and (
            state == "SNAPSHOTTING"
            or state == "ERROR" and "snapshot preparation was interrupted" in str(supervisor.get("error"))):
        action = "snapshot was interrupted before any dispatch; sim_test_launch with a new request_id"
    elif state == "ERROR" and not active and not result.get("source_frozen") and not rows:
        action = ("source freeze failed before any test was dispatched (" + str(supervisor.get("error"))[:160]
                  + "); fix that cause, then run again with a new request_id")
    elif state == "ERROR" and not active:
        action = "inspect supervisor.error; then sim_test_recover with the same request_id"
    elif state == "NEEDS_OPERATOR" and not active:
        action = f"needs attention: {supervisor.get('detail')}; {supervisor.get('action')}"
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
    elif waiting and set(waiting) <= {"NO_HOST_FOR_PLATFORM"}:
        action = ("no configured host has the requested platform: these tests cannot start; "
                  "launch a new request_id with a configured platform or host")
    elif waiting and not progressing and set(waiting) <= {"NO_ONLINE_HOST_FOR_PLATFORM"}:
        action = ("every host for the requested platform is offline; tests wait for one to return "
                  "(sim_fleet shows hosts; a reviewed portable check may use platform any)")
    elif waiting:
        action = ("poll sim_test_status; waiting: " + ", ".join(f"{code}={count}" for code, count in sorted(waiting.items()))
                  + " (tests[].waiting explains each; sim_fleet shows hosts)")
    else:
        action = "poll sim_test_status"
    summary = {"result": overall, **counts, "attention": attention, "next_action": action}
    if waiting:
        summary["waiting"] = waiting
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


SUPERVISOR_PAUSE_SECONDS = 2.0
BLOCKED_RECOVER_SECONDS = 300.0
STUCK_SECONDS = 15 * 60
IDLE_SECONDS = 6 * 3600
_STUCK_PHASES = {"BLOCKED", "COLLECTION_BLOCKED"}
_FINAL_PHASES = {"DONE", "REJECTED"}


class Progress:
    """Decide when observing further cannot help (TQ-05-F2.2).

    A batch whose remaining rows are all blocked for STUCK_SECONDS, or which
    has not changed at all for IDLE_SECONDS (e.g. waiting for an offline host),
    stops with NEEDS_OPERATOR and a reason. It never cancels accepted work.
    """

    def __init__(self, clock=time.monotonic):
        self.clock, self.signature, self.changed = clock, None, clock()

    def observe(self, rows):
        signature = tuple((row.get("request_id"), row.get("phase"), (row.get("status") or {}).get("state"))
                          for row in rows)
        now = self.clock()
        if signature != self.signature:
            self.signature, self.changed = signature, now
            return None
        open_rows = [row for row in rows if row.get("phase") not in _FINAL_PHASES]
        quiet = now - self.changed
        if open_rows and all(row.get("phase") in _STUCK_PHASES for row in open_rows) and quiet >= STUCK_SECONDS:
            return {"detail": f"{len(open_rows)} test(s) blocked without change for {int(quiet)} s",
                    "action": "inspect tests[].error; testctl pool status/recover/reconcile with each job id, "
                              "then sim_test_recover; never resubmit them under a new id",
                    "blocked_jobs": [row.get("request_id") for row in open_rows][:20]}
        if open_rows and quiet >= IDLE_SECONDS:
            return {"detail": f"no progress for {int(quiet)} s; observation stopped, nothing was cancelled",
                    "action": "check sim_fleet (offline or busy hosts), then sim_test_recover to keep waiting"}
        return None


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
        # TQ-05-F2.2: observe until a final result or a stop rule, not for a
        # fixed hour. A stop never cancels work; recover resumes observation.
        progress = Progress()
        recovered_at = {}
        while True:
            update("RUNNING")
            batch_path = directory / "batch.json"
            if batch_path.exists():
                for row in _read(batch_path)["jobs"]:
                    identifier = row["request_id"]
                    if (row["phase"] == "BLOCKED" and (pool.root / "jobs" / (identifier + ".json")).exists()
                            and time.monotonic() - recovered_at.get(identifier, -1e9) >= BLOCKED_RECOVER_SECONDS):
                        recovered_at[identifier] = time.monotonic()
                        try:
                            pool.recover(identifier)
                        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError):
                            pass  # retry only this exact receipt after the interval
            batch = run_batch(pool, request["config"], manifest, batch_path, timeout=30)
            if batch["result"] in {"PASSED", "FAILED"}:
                update("FINISHED", result=batch["result"])
                return
            stop = progress.observe(batch["jobs"])
            if stop:
                update("NEEDS_OPERATOR", result="INCOMPLETE", **stop)
                return
            update("WAITING", result="INCOMPLETE")
            time.sleep(SUPERVISOR_PAUSE_SECONDS)
    except Exception as error:
        update("ERROR", error=str(error))
    finally:
        guard.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", required=True)
    supervise(parser.parse_args().worker)
