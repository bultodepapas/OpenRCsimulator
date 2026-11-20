"""Compact, agent-facing views of the checked-test fleet (TQ-05-F1).

Everything here only reads durable receipts, cached observations and local
process lists. It never submits, recovers, cancels or removes work, so it is
safe to call from any MCP client at any time.
"""
from __future__ import annotations

import json
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

def _host_view(observation: dict, work: dict) -> dict:
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
    return {key: value for key, value in view.items() if value is not None}


def _active_pool_work(pool_root: Path) -> dict:
    counts = {}
    for path in (pool_root / "jobs").glob("*.json"):
        receipt = _read(path) or {}
        last = receipt.get("last_status") or {}
        if last.get("state") != "FINISHED" and receipt.get("state") not in {"REJECTED", "OPERATOR_RECONCILED_ABSENT",
                                                                           "CANCELED_BEFORE_DISPATCH"}:
            host = receipt.get("host")
            if isinstance(host, str):
                counts[host] = counts.get(host, 0) + 1
    return counts


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
        work = _active_pool_work(pool.root)
        data = {"observed_at": time.time(), "probe_seconds": round(time.monotonic() - started, 2),
                "hosts": [_host_view(item, work) for item in observations]}
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
    reasons = {c["host"]: [str(r)[:120] for r in c.get("reasons", [])] for c in matching}
    if not matching:
        code = "NO_HOST_FOR_PLATFORM"
    elif all(any(r == "OFFLINE" for r in c.get("reasons", [])) for c in matching):
        code = "NO_ONLINE_HOST_FOR_PLATFORM"
    else:
        flat = " ".join(r for c in matching for r in c.get("reasons", []))
        code = next((name for token, name in (("CIRCUIT_OPEN", "CIRCUIT_OPEN"), ("QUARANTIN", "QUARANTINED"),
                                              ("INSUFFICIENT_DISK", "DISK"), ("DISK_UNKNOWN", "DISK"),
                                              ("BUSY", "HOST_BUSY")) if token in flat), "NO_ELIGIBLE_HOST")
    reason = {"code": code, "hosts": reasons}
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


def compact_row(row: dict) -> dict:
    status, collection = row.get("status") or {}, row.get("collection") or {}
    item = {"script": (row.get("input") or {}).get("script"), "platform": (row.get("input") or {}).get("platform"),
            "phase": row.get("phase"), "job": row.get("request_id")}
    host = status.get("pool_host") or collection.get("pool_host") or (status.get("decision") or {}).get("selected")
    if host:
        item["host"] = host
    if status.get("outcome") or collection.get("pool_outcome"):
        item["outcome"] = status.get("outcome") or collection.get("pool_outcome")
    seconds = collection.get("elapsed_seconds")
    if isinstance(seconds, (int, float)):
        item["seconds"] = round(seconds, 1)
    if item["phase"] in {"WAITING", "RETRY_WAIT", "SUBMITTING"}:
        reason = _wait_reason(row, item["platform"])
        if reason and reason["code"] != "QUEUED_IN_BATCH":  # not yet tried: nothing to explain
            item["waiting"] = reason
    error = row.get("collection_error") or status.get("error") or row.get("first_error")
    if error:
        item["error"] = str(error)[:300]
    if item.get("outcome") and item["outcome"] != "PASSED" or item["phase"] in {"BLOCKED", "COLLECTION_BLOCKED"}:
        checked = status.get("checked") or {}
        why = collection.get("reason") or checked.get("reason")
        if why:
            item["why"] = why
        if collection.get("missing_required_text"):
            item["missing_markers"] = collection["missing_required_text"][:5]
        log = collection.get("log") or collection.get("diagnostic_log")
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
