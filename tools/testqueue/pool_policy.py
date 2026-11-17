"""Pure, advisory host selection for a *new* test-queue attempt.

The caller supplies fresh, trusted inventory and still obtains admission from the
selected host's authority. This estimate does not reserve resources, qualify a
remote adapter, transfer inputs, start an attempt, or retry an existing attempt.
In particular, a failed or uncertain attempt must never be replanned here.

``plan(job, hosts)`` returns a selected host ID or None, plus an explanation for
every host. All sizes are bytes and durations seconds. Host load is the number
of runnable/running CPU tasks, not a percentage. Duration history is keyed by
the job's optional ``duration_key``, not its source-cache identity; an optional
``duration_sources`` mapping labels a duration ``history`` or ``peer``. Capabilities
are explicit: ``headless``, ``graphics``, and ``performance`` only advertise
execution paths the caller has independently qualified on that host.
"""
from __future__ import annotations

import math


DISK_RESERVE_BYTES = 512 * 1024 * 1024
MEMORY_RESERVE_BYTES = 512 * 1024 * 1024
_MIB = 1024 * 1024
_PLATFORMS = {"windows", "linux", "darwin"}
_JOB_FIELDS = {"platform", "workload", "source_bytes", "cache_id", "estimated_seconds",
               "duration_key", "memory_bytes", "disk_bytes", "required_gpu",
               "performance_host", "requires_graphics"}


def _number(value, *, minimum=0):
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value) and value >= minimum
    except OverflowError:
        return False


def _size(value):
    return type(value) is int and 0 <= value <= 2**63 - 1


def _validate_job(job):
    if not isinstance(job, dict) or set(job) - _JOB_FIELDS:
        raise ValueError("job must be an object with known fields")
    platform = job.get("platform", "any")
    workload = job.get("workload", "headless")
    if not isinstance(platform, str) or platform not in _PLATFORMS | {"any"}:
        raise ValueError("platform must be any, windows, linux or darwin")
    if not isinstance(workload, str) or workload not in {"headless", "graphics", "performance"}:
        raise ValueError("workload must be headless, graphics or performance")
    for field in ("source_bytes", "memory_bytes", "disk_bytes"):
        if not _size(job.get(field, 0)):
            raise ValueError(field + " must be a nonnegative byte count")
    if not _number(job.get("estimated_seconds", 60), minimum=0.001):
        raise ValueError("estimated_seconds must be positive and finite")
    for field in ("cache_id", "duration_key", "required_gpu", "performance_host"):
        if field in job and (not isinstance(job[field], str) or not job[field]):
            raise ValueError(field + " must be a nonempty string")
    if type(job.get("requires_graphics", False)) is not bool:
        raise ValueError("requires_graphics must be boolean")
    if job.get("requires_graphics", False) and workload == "headless":
        raise ValueError("headless work cannot require graphics")
    if workload == "performance" and not job.get("performance_host"):
        raise ValueError("performance work requires an explicit performance_host")
    if workload != "performance" and "performance_host" in job:
        raise ValueError("performance_host applies only to performance work")


def _candidate(job, host):
    candidate = {"host": host["id"], "eligible": False, "reasons": [], "score": None}
    reasons = candidate["reasons"]
    if type(host.get("online")) is not bool:
        reasons.append("INVALID_INVENTORY: online must be boolean")
        return candidate
    if not host["online"]:
        reasons.append("OFFLINE")
        return candidate
    if type(host.get("busy")) is not bool:
        reasons.append("INVALID_INVENTORY: busy must be boolean")
    elif host["busy"]:
        reasons.append("BUSY")
    platform = host.get("platform")
    if not isinstance(platform, str) or platform not in _PLATFORMS:
        reasons.append("INVALID_INVENTORY: unknown platform")
    elif job.get("platform", "any") not in ("any", platform):
        reasons.append("PLATFORM_MISMATCH: requires " + job["platform"])

    capabilities = host.get("capabilities")
    if not isinstance(capabilities, (list, tuple, set)) or any(not isinstance(value, str) for value in capabilities):
        reasons.append("INVALID_INVENTORY: capabilities must be a string list")
        capabilities = []
    workload = job.get("workload", "headless")
    required_capabilities = ["graphics" if workload == "graphics" or job.get("requires_graphics", False) else "headless"]
    if workload == "performance":
        required_capabilities.append("performance")
        if job["performance_host"] != host["id"]:
            reasons.append("PERFORMANCE_AFFINITY: requires " + job["performance_host"])
    for capability in required_capabilities:
        if capability not in capabilities:
            reasons.append("CAPABILITY_MISSING: " + capability)
    if "required_gpu" in job and host.get("gpu") != job["required_gpu"]:
        reasons.append("GPU_MISMATCH: requires " + job["required_gpu"])

    local = host.get("local", False)
    if type(local) is not bool:
        reasons.append("INVALID_INVENTORY: local must be boolean")
        local = False
    cached_inputs = host.get("cached_inputs", [])
    if not isinstance(cached_inputs, (list, tuple, set)) or any(not isinstance(value, str) for value in cached_inputs):
        reasons.append("INVALID_INVENTORY: cached_inputs must be a string list")
        cached_inputs = []
    cached = bool(job.get("cache_id")) and job["cache_id"] in cached_inputs
    source_bytes = job.get("source_bytes", 0)
    # Remote attempts retain an incoming archive and an attempt archive, then
    # extract the source. Local attempts need a cache and a workspace copy.
    copies = (1 if local else 2) + (0 if cached else 1)
    disk_required = DISK_RESERVE_BYTES + job.get("disk_bytes", 0) + source_bytes * copies
    free_disk = host.get("free_disk_bytes")
    if not _size(free_disk):
        reasons.append("DISK_UNKNOWN: free_disk_bytes must be known")
    elif free_disk < disk_required:
        reasons.append(f"INSUFFICIENT_DISK: {free_disk} < {disk_required} bytes")
    memory_required = MEMORY_RESERVE_BYTES + job.get("memory_bytes", 0)
    free_memory = host.get("free_memory_bytes")
    if not _size(free_memory):
        reasons.append("MEMORY_UNKNOWN: free_memory_bytes must be known")
    elif free_memory < memory_required:
        reasons.append(f"INSUFFICIENT_MEMORY: {free_memory} < {memory_required} bytes")

    rate = host.get("transfer_bytes_per_second", (200 if local else 25) * _MIB)
    setup = host.get("setup_seconds", 0 if local else 5)
    load = host.get("load")
    cores = host.get("cores")
    if not _number(rate, minimum=0.001):
        reasons.append("INVALID_INVENTORY: transfer rate must be positive")
    if not _number(setup):
        reasons.append("INVALID_INVENTORY: setup_seconds must be nonnegative")
    if not _number(load):
        reasons.append("INVALID_INVENTORY: load must be nonnegative")
    if type(cores) is not int or cores < 1:
        reasons.append("INVALID_INVENTORY: cores must be a positive integer")
    history = host.get("durations", {})
    if not isinstance(history, dict):
        reasons.append("INVALID_INVENTORY: durations must be a mapping")
        history = {}
    key = job.get("duration_key")
    duration = job.get("estimated_seconds", 60)
    duration_source = "estimate"
    if key and key in history:
        if not _number(history[key], minimum=0.001):
            reasons.append("INVALID_INVENTORY: historical duration must be positive")
        else:
            sources = host.get("duration_sources")
            source = sources.get(key, "history") if isinstance(sources, dict) else "history"
            duration, duration_source = history[key], (source if source in {"history", "peer"} else "history")
    if reasons:
        return candidate

    transfer = 0.0 if cached else source_bytes / rate
    load_factor = 1 + load / cores
    execution = duration * load_factor
    completion = setup + transfer + execution
    if not all(math.isfinite(value) for value in (transfer, load_factor, execution, completion)):
        reasons.append("INVALID_INVENTORY: completion estimate overflow")
        return candidate
    candidate["eligible"] = True
    candidate["score"] = {"estimated_completion_seconds": completion, "setup_seconds": setup,
                          "transfer_seconds": transfer, "duration_seconds": duration,
                          "duration_source": duration_source, "load_factor": load_factor,
                          "execution_seconds": execution, "cached": cached,
                          "required_disk_bytes": disk_required, "required_memory_bytes": memory_required}
    return candidate


def plan(job: dict, hosts: list[dict]) -> dict:
    """Choose the lowest estimated completion time; ties use the host ID.

    ``memory_bytes`` and ``disk_bytes`` are additional working requirements;
    disk admission also accounts for local or remote source copies and the
    512 MiB reserve.
    A performance job requires ``performance_host`` and will never select a
    different host. Missing capacity or capability information rejects a host.
    Inventory is a point-in-time estimate, not an admission or a reservation.
    """
    _validate_job(job)
    if not isinstance(hosts, list):
        raise ValueError("hosts must be a list")
    ids = []
    for host in hosts:
        if not isinstance(host, dict) or not isinstance(host.get("id"), str) or not host["id"]:
            raise ValueError("each host needs a nonempty id")
        ids.append(host["id"])
    if len(ids) != len(set(ids)):
        raise ValueError("host ids must be unique")
    candidates = [_candidate(job, host) for host in sorted(hosts, key=lambda host: host["id"])]
    eligible = [candidate for candidate in candidates if candidate["eligible"]]
    selected = min(eligible, key=lambda candidate: (candidate["score"]["estimated_completion_seconds"], candidate["host"]))["host"] if eligible else None
    return {"selected": selected, "candidates": candidates}
