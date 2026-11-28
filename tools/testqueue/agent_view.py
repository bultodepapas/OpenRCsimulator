"""Compact, agent-facing views of the checked-test fleet (TQ-05-F1).

Everything here only reads durable receipts, cached observations and local
process lists. It never submits, recovers, cancels or removes work, so it is
safe to call from any MCP client at any time.
"""
from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import time

from tools.testqueue.common import write_json

FLEET_TTL_SECONDS = 15.0
LOG_TAIL_BYTES = 64 * 1024
FAIL_LINE = re.compile(r"(FAIL|ERROR|SCRIPT ERROR|Assertion|assert|Traceback|missing)", re.IGNORECASE)
_PLATFORM_REASON = "PLATFORM_MISMATCH"


def _read(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _gb(value):
    return round(value / 1e9, 1) if isinstance(value, (int, float)) else None


# ---------------------------------------------------------------- fleet view

def _host_view(observation: dict, work: dict, unsettled: dict | None = None) -> dict:
    view = {"id": observation.get("id"), "platform": observation.get("platform"),
            "online": bool(observation.get("online"))}
    if not view["online"]:
        view["offline_reason"] = str(observation.get("reason") or "engine unavailable")[:200]
        return view
    view.update(busy=bool(observation.get("busy")), busy_code=observation.get("busy_code"),
                busy_reason=observation.get("busy_reason"),
                free_disk_gb=_gb(observation.get("free_disk_bytes")),
                free_memory_gb=_gb(observation.get("free_memory_bytes")),
                cores=observation.get("cores"),
                load=round(observation["load"], 2) if isinstance(observation.get("load"), (int, float)) else None,
                setup_seconds=round(observation.get("setup_seconds") or 0, 1),
                pool_jobs_active=work.get(observation.get("id"), 0))
    if view["busy"] and not view["busy_code"]:
        view["busy_code"] = "BUSY"
    if unsettled and observation.get("id") in unsettled:
        view["unsettled_receipts"] = unsettled[observation["id"]]
    capabilities = observation.get("capabilities")
    if isinstance(capabilities, list) and "graphics" in capabilities:
        # TQ-06: tell agents which hosts take rendering_driver jobs, and on which GPU.
        view["gpu"] = next((c[4:] for c in capabilities if isinstance(c, str) and c.startswith("gpu:")), "unknown")
    return {key: value for key, value in view.items() if value is not None}


LIVE_STATES = {"RUNNING", "STARTING", "ACCEPTED", "QUEUED", "DISPATCHING", "CLEANING"}
SETTLED_RECEIPTS = {"REJECTED", "OPERATOR_RECONCILED_ABSENT", "CANCELED_BEFORE_DISPATCH", "TRANSFER_DEFERRED"}
# A receipt last written longer ago than this is not evidence of work running now.
WORK_FRESH_SECONDS = 2 * 3600


def _pool_work(pool_root: Path, now: float | None = None) -> tuple[dict, dict]:
    """(active, unsettled) per host (TQ-07-A5).

    Active: the receipt's newest observation is a live state (or a submission
    still in its first moments) and was written recently. Unsettled: open
    records that are not evidence of current work, such as a job whose host
    forgot it or a receipt nobody has observed for hours; they are reported with
    their age instead of being counted as running jobs.
    """
    now = time.time() if now is None else now
    active, unsettled = {}, {}
    for path in (pool_root / "jobs").glob("*.json"):
        receipt = _read(path) or {}
        host = receipt.get("host")
        last = receipt.get("last_status") or {}
        if (not isinstance(host, str) or last.get("state") == "FINISHED" or receipt.get("state") in SETTLED_RECEIPTS
                or (receipt.get("terminal_observation") or {}).get("cleanup") == "CONFIRMED"):
            continue
        try:
            age = now - path.stat().st_mtime
        except OSError:
            continue
        starting = receipt.get("state") in {"PREPARING", "SUBMISSION_UNCONFIRMED"} and "last_status" not in receipt
        if (last.get("state") in LIVE_STATES or starting) and age < WORK_FRESH_SECONDS:
            active[host] = active.get(host, 0) + 1
        else:
            entry = unsettled.setdefault(host, {"count": 0, "oldest_hours": 0.0})
            entry["count"] += 1
            entry["oldest_hours"] = max(entry["oldest_hours"], round(age / 3600, 1))
    return active, unsettled


def _active_pool_work(pool_root: Path) -> dict:
    return _pool_work(pool_root)[0]


def godot_processes(managed_roots=()) -> list[dict]:
    """Godot processes on this machine; queue-owned ones run inside a managed root."""
    try:
        import psutil
    except ImportError:
        return [{"error": "psutil unavailable; cannot list processes"}]
    roots = [os.path.normcase(str(root)) for root in managed_roots if root]
    now, found = time.time(), []
    # Filter by name first: asking every process for its command line costs
    # seconds on Windows, while the name pass takes milliseconds.
    godot = [process for process in psutil.process_iter(["name"])
             if "godot" in (process.info.get("name") or "").lower()]
    for process in godot:
        try:
            # The console wrapper and its child share a command line; report the wrapper with both CPU totals.
            ppid = process.ppid()
            parent = psutil.Process(ppid) if ppid else None
            if parent is not None and "godot" in (parent.name() or "").lower():
                continue
            cmdline = process.cmdline() or []
            joined = os.path.normcase(" ".join(cmdline))
            script = next((cmdline[i + 1] for i, arg in enumerate(cmdline[:-1]) if arg == "--script"), None)
            times = process.cpu_times()
            cpu_seconds = times.user + times.system
            for child in process.children(recursive=True):
                try:
                    times = child.cpu_times()
                    cpu_seconds += times.user + times.system
                except psutil.Error:
                    pass
            age = now - process.create_time()
            entry = {"pid": process.pid, "age_minutes": round(age / 60, 1),
                     "cpu_seconds": round(cpu_seconds, 1),
                     "headless": "--headless" in cmdline, "script": script,
                     "managed": any(root in joined for root in roots)}
            if not entry["managed"] and age > 1800:
                entry["note"] = "unmanaged for more than 30 min; ask its owner to stop it"
            found.append(entry)
        except (psutil.Error, OSError):
            continue
    return sorted(found, key=lambda item: -item["age_minutes"])


def fleet(pool, *, refresh: bool = False, queue_root: Path | None = None) -> dict:
    cache = pool.root / "fleet-cache.json"
    data = None if refresh else _read(cache)
    now = time.time()
    if not isinstance(data, dict) or now - float(data.get("observed_at", 0)) > FLEET_TTL_SECONDS:
        started = time.monotonic()
        observations = pool.probe()
        work, unsettled = _pool_work(pool.root)
        data = {"observed_at": time.time(), "probe_seconds": round(time.monotonic() - started, 2),
                "hosts": [_host_view(item, work, unsettled) for item in observations]}
        try:
            write_json(cache, data)
        except OSError:
            pass  # a cache write failure must not hide the fresh observation
    hosts = data.get("hosts") or []
    result = {"age_seconds": round(max(0.0, time.time() - float(data["observed_at"])), 1),
              "probe_seconds": data.get("probe_seconds"),
              "hosts": hosts}
    from tools.testqueue.common import state_root
    result["godot_processes"] = godot_processes((queue_root or state_root(), pool.root, "OpenRC-testpool"))
    free = [host["id"] for host in hosts if host.get("online") and not host.get("busy")]
    hints = []
    if not free:
        hints.append("no idle host: work queues until one frees; sim_test_status explains each wait")
    unmanaged = [item for item in result["godot_processes"] if not item.get("managed") and "pid" in item]
    if unmanaged:
        hints.append(f"{len(unmanaged)} unmanaged Godot process(es) make the local host busy for queued work")
    by_platform = {}
    for host in hosts:
        if host.get("online") and not host.get("busy"):
            by_platform.setdefault(host.get("platform"), []).append(host["id"])
    if by_platform:
        hints.append("idle now: " + ", ".join(f"{p}={'/'.join(ids)}" for p, ids in sorted(by_platform.items())))
    result["hints"] = hints
    return result


# ---------------------------------------------------------- compact status

def _wait_reason(row: dict, platform: str | None) -> dict | None:
    status = row.get("status") or {}
    decision = status.get("decision") or {}
    candidates = decision.get("candidates") or []
    if row.get("phase") == "RETRY_WAIT":
        reason = {"code": status.get("reason_code") or "RETRY_WAIT",
                  "detail": str(status.get("error") or row.get("first_error") or "")[:200]}
        if status.get("reason_code") == "TRANSFER_DEFERRED":
            reason["note"] = "the archive never reached the host; the same job retries there automatically"
        return reason
    if not candidates:
        return {"code": "QUEUED_IN_BATCH"} if row.get("phase") == "WAITING" else None
    matching = [c for c in candidates if not any(str(r).startswith(_PLATFORM_REASON) for r in c.get("reasons", []))]
    others_free = [c["host"] for c in candidates if c not in matching
                   and all(str(r).startswith(_PLATFORM_REASON) for r in c.get("reasons", []))]
    reasons = {c["host"]: [str(r)[:120] for r in c.get("reasons", [])] for c in matching or candidates}
    if not matching:
        code = "NO_HOST_FOR_PLATFORM"
    elif all(any(r == "OFFLINE" for r in c.get("reasons", [])) for c in matching):
        code = "NO_ONLINE_HOST_FOR_PLATFORM"
    else:
        flat = " ".join(r for c in matching for r in c.get("reasons", []))
        code = next((name for token, name in (("CIRCUIT_OPEN", "CIRCUIT_OPEN"), ("QUARANTIN", "QUARANTINED"),
                                              ("EXTERNAL_SIMULATOR", "EXTERNAL_SIMULATOR"),
                                              ("INSUFFICIENT_DISK", "DISK"), ("DISK_UNKNOWN", "DISK"),
                                              ("BUSY", "HOST_BUSY")) if token in flat), "NO_ELIGIBLE_HOST")
    reason = {"code": code, "hosts": reasons}
    observation = row.get("admission_wait") or {}
    for key in ("first_observed_at", "last_observed_at"):
        if key in observation:
            reason[key] = observation[key]
    if "retry_after" in row:
        reason["next_probe_at"] = row["retry_after"]
    reason["next_action"] = {
        "DISK": "check available space against the required bytes on the listed hosts",
        "NO_ONLINE_HOST_FOR_PLATFORM": "check connectivity to the requested hosts",
        "HOST_BUSY": "check sim_fleet for the current capacity owner",
        "EXTERNAL_SIMULATOR": "wait for the external simulator owner to finish",
    }.get(code, "inspect the listed host refusals in sim_fleet")
    if others_free and platform != "any":
        reason["alternative"] = ("only platform blocks " + ", ".join(others_free)
                                 + "; a reviewed portable check may use platform any")
    return reason


def _tail_lines(path, limit: int = 8) -> list[str]:
    try:
        with open(path, "rb") as stream:
            stream.seek(0, os.SEEK_END)
            size = stream.tell()
            stream.seek(max(0, size - LOG_TAIL_BYTES))
            text = stream.read().decode("utf-8", "replace")
    except (OSError, TypeError):
        return []
    lines = [line.rstrip() for line in text.splitlines() if line.strip()]
    flagged = [line for line in lines if FAIL_LINE.search(line)]
    return [line[:300] for line in (flagged[-limit:] if flagged else lines[-min(limit, 5):])]


def _diagnostic_log(collection: dict):
    """The engine log inside a diagnostic-only collection, which has no ``log`` key."""
    report = collection.get("pool_report") or collection.get("report")
    if not report:
        return None
    artifacts = Path(report).parent / "artifacts"
    for pattern in ("check/*/engine.log", "import/*/engine.log"):
        found = sorted(artifacts.glob(pattern))
        if found:
            return str(found[0])
    return None


def compact_row(row: dict) -> dict:
    status, collection = row.get("status") or {}, row.get("collection") or {}
    item = {"script": (row.get("input") or {}).get("script"), "platform": (row.get("input") or {}).get("platform"),
            "phase": row.get("phase"), "job": row.get("request_id")}
    host = status.get("pool_host") or collection.get("pool_host") or (status.get("decision") or {}).get("selected")
    if host:
        item["host"] = host
    if status.get("outcome") or collection.get("pool_outcome"):
        item["outcome"] = status.get("outcome") or collection.get("pool_outcome")
        if item["outcome"] == "PASSED" and row.get("phase") == "DONE":
            from tools.testqueue.pool_batch import _finished_success
            if not _finished_success(row):
                item["outcome"] = "PASSED_UNVERIFIED"
                item["why"] = "evidence incomplete, cleanup unconfirmed or collection unverified; does not qualify"
    seconds = collection.get("elapsed_seconds")
    if isinstance(seconds, (int, float)):
        item["seconds"] = round(seconds, 1)
    if item["phase"] in {"WAITING", "RETRY_WAIT", "SUBMITTING"}:
        reason = _wait_reason(row, item["platform"])
        if reason and reason["code"] != "QUEUED_IN_BATCH":  # not yet tried: nothing to explain
            item["waiting"] = reason
    elif item["phase"] == "TRACKING" and (status.get("reason_code") == "EXTERNAL_SIMULATOR"
            or str(status.get("reason") or "").startswith("EXTERNAL_SIMULATOR:")):
        item.update(stage="admission", cause="EXTERNAL_SIMULATOR")
        item["waiting"] = {"code": "EXTERNAL_SIMULATOR", "detail": status.get("reason"),
                           "next_action": "observe the original job while its host waits for the external simulator"}
        if status.get("admission_wait_started_at") is not None:
            item["waiting"]["first_observed_at"] = status["admission_wait_started_at"]
    if item["phase"] == "SUBMITTING" and status.get("state") == "SUBMITTING":
        item["stage"] = "placement"
        started = row.get("placement_started_at")
        if type(started) in (int, float) and math.isfinite(started):
            item["placement_elapsed_seconds"] = round(max(0.0, time.time() - started), 1)
        if (row.get("input") or {}).get("host"):
            item["host"] = row["input"]["host"]
    error = row.get("collection_error") or status.get("error")
    if not error and (item["phase"] in {"BLOCKED", "REJECTED", "COLLECTION_BLOCKED", "RETRY_WAIT"}
                      or item["phase"] == "DONE" and item.get("outcome") != "PASSED"):
        error = row.get("first_error")
    if error:
        item["error"] = str(error)[:300]
    runner = status.get("runner_verdict") if isinstance(status.get("runner_verdict"), dict) else {}
    checked = status.get("checked") or runner.get("checked") or {}
    imported = status.get("import") or runner.get("import_verdict") or {}
    stage_seconds = {}
    measured = row.get("coordinator_seconds") or {}
    for stage in ("placement", "collection"):
        seconds = measured.get(stage) if isinstance(measured, dict) else None
        if type(seconds) in (float, int) and math.isfinite(seconds) and seconds >= 0:
            stage_seconds[stage] = round(seconds, 3)  # accumulated float sums printed as 105.32800000000861
    transfer = status.get("transfer_seconds")
    if type(transfer) in (int, float) and math.isfinite(transfer) and transfer >= 0:
        stage_seconds["transfer"] = round(transfer, 3)
    start, finish = status.get("admission_wait_started_at"), status.get("admission_wait_finished_at")
    if all(type(t) in (int, float) and math.isfinite(t) for t in (start, finish)) and finish >= start:
        stage_seconds["admission"] = round(finish - start, 3)
    for stage, report in (("import", imported), ("check", checked)):
        seconds = report.get("elapsed_seconds") if isinstance(report, dict) else None
        if type(seconds) in (float, int) and math.isfinite(seconds) and seconds >= 0:
            stage_seconds[stage] = round(seconds, 3)
    if stage_seconds:
        item["stage_seconds"] = stage_seconds
    if item.get("outcome") and item["outcome"] != "PASSED" or item["phase"] in {"BLOCKED", "COLLECTION_BLOCKED", "REJECTED"}:
        stage = collection.get("diagnostic_stage") or status.get("stage")
        cause = status.get("reason_code")
        if not cause and item["phase"] == "BLOCKED" and item["job"]:
            # Persisted batches predating the typed reply can be inspected
            # while the authority is offline. Match only this row's job receipt.
            missing = str(status.get("error") or row.get("first_error") or "")
            if missing.startswith("[Errno 2] No such file or directory: ") and re.search(
                    r"/jobs/+" + re.escape(item["job"]) + r"""\.json['"]$""", missing.replace("\\", "/")):
                cause = "MISSING_RECEIPT"
        # Older authorities recorded these two pre-launch refusals as generic execution failures.
        if cause == "EXTERNAL_SIMULATOR" or status.get("error") in {
                "Refused: external Godot process detected; it was not touched",
                "EXTERNAL_SIMULATOR appeared during preparation; no process started"}:
            stage, cause = "admission", "EXTERNAL_SIMULATOR"
        elif cause == "MISSING_RECEIPT":
            stage = "dispatch"
            item["hint"] = "restore the original receipt from verified evidence and reconcile this job ID"
        elif cause == "LOCAL_SUBMIT_REFUSED":
            stage = "dispatch"
            item["hint"] = ("the local authority refused this request and its durable tombstone proves it never ran; "
                            "fix the reported cause and launch a new request")
        elif item["phase"] == "REJECTED":
            stage = "dispatch" if status.get("outcome") == "NOT_DISPATCHED" else "preflight"
        elif item["phase"] == "COLLECTION_BLOCKED":
            stage = "collection"
        elif isinstance(checked, dict) and checked:
            stage = "check"
        elif isinstance(imported, dict) and imported and imported.get("ok") is False:
            stage = "import"
        checked = checked if isinstance(checked, dict) else {}
        imported = imported if isinstance(imported, dict) else {}
        if stage:
            item["stage"] = stage
        if cause or stage in {"check", "import"}:
            item["cause"] = cause or (checked if stage == "check" else imported).get("reason") or item.get("outcome")
        why = collection.get("reason") or checked.get("reason")
        if not why and imported.get("reason") and imported.get("ok") is not True:
            why = f"import {imported['reason']}"  # the test itself never started
        if why:
            item["why"] = why
            if why == "import timeout":
                item["hint"] = ("the host spent the whole timeout importing project assets; "
                                "raise timeout or prefer a host with a warm import")
        if collection.get("missing_required_text"):
            item["missing_markers"] = collection["missing_required_text"][:5]
        log = collection.get("log") or collection.get("diagnostic_log") or _diagnostic_log(collection)
        if log:
            item["log"] = log
            item["log_tail"] = _tail_lines(log)
        if collection.get("report") or collection.get("pool_report"):
            item["report"] = collection.get("report") or collection.get("pool_report")
    return item


def compact_status(full: dict) -> dict:
    """The default sim_test_status reply: summary, one compact line per test."""
    summary = dict(full.get("summary") or {})
    summary.pop("attention", None)  # the per-test rows below carry the same detail
    if isinstance(summary.get("next_action"), str):
        summary["next_action"] = summary["next_action"].replace("attention[].evidence", "tests[].report") \
            .replace("attention[].log", "tests[].log_tail").replace("attention[]", "tests[]")
    rows = [compact_row(row) for row in full.get("jobs") or []]
    if not rows and isinstance(full.get("request_jobs"), list):
        rows = [{"script": job.get("script"), "platform": job.get("platform"), "phase": "NOT_FROZEN"}
                for job in full["request_jobs"]]
    supervisor = full.get("supervisor") or {}
    view = {"request_id": full.get("request_id"), "summary": summary,
            "result": full.get("result", summary.get("result", "INCOMPLETE")), "tests": rows,
            "supervisor": {key: supervisor.get(key) for key in ("state", "error", "detail") if supervisor.get(key)},
            "supervisor_active": full.get("supervisor_active"), "source_frozen": full.get("source_frozen"),
            "receipt": full.get("receipt")}
    if full.get("recovery_required"):
        view["recovery_required"] = True
    view["detail_hint"] = "detail=full returns the authoritative rows, decisions and artifacts"
    return view


# ------------------------------------------------------------- list requests

def list_requests(pool, limit: int = 20) -> list[dict]:
    directory = pool.root / "mcp"
    if not directory.is_dir():
        return []
    entries = sorted((entry for entry in directory.iterdir() if entry.is_dir()),
                     key=lambda entry: entry.stat().st_mtime, reverse=True)[:max(1, min(limit, 100))]
    result = []
    for entry in entries:
        request = _read(entry / "request.json") or {}
        supervisor = _read(entry / "supervisor.json") or {}
        batch = _read(entry / "batch.json") or {}
        rows = batch.get("jobs") or []
        result.append({"request_id": entry.name,
                       "updated": time.strftime("%Y-%m-%d %H:%M", time.localtime(entry.stat().st_mtime)),
                       "tests": len(request.get("jobs") or []),
                       "scripts": [job.get("script") for job in (request.get("jobs") or [])[:3]],
                       "result": batch.get("result") or supervisor.get("result") or "INCOMPLETE",
                       "supervisor": supervisor.get("state"),
                       "passed": sum(1 for row in rows if (row.get("status") or {}).get("outcome") == "PASSED"
                                     and row.get("phase") == "DONE")})
    return result
