"""Validate event-bounded artifacts and compare only eligible workload segments."""
from __future__ import annotations

import hashlib
import html
import json
import math
from pathlib import Path
import statistics
from collections import defaultdict
import heapq

from runner import read_json, write_json

REDUCER_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def validate_stream(directory: Path, frames: dict) -> dict:
    stream = frames.get("stream", {})
    filename = stream.get("file", "")
    if not isinstance(filename, str) or Path(filename).name != filename or not filename:
        raise ValueError("frame stream filename must be a local basename")
    path = directory / filename
    if path.is_symlink() or path.stat().st_size > 268435456:
        raise ValueError("invalid or oversized frame stream")
    digest = hashlib.sha256()
    count, chunks, previous_end, header, trailer = 0, 0, None, None, None
    metric_schema = None
    phase_samples = defaultdict(list)
    phase_hitches = defaultdict(lambda: {str(limit): dict(frames=0, consecutive=0, max_consecutive=0,
        excess_ms=0.0, slow_time_ms=0.0, runs=0, consecutive_ms=0.0, max_run_ms=0.0)
        for limit in (16.667, 33.333, 50, 100)})
    phase_final_counters = {}
    previous_phase = None
    slowest = []
    with path.open("rb") as source:
        for line in source:
            if len(line) > 8 * 1024 * 1024:
                raise ValueError("frame chunk exceeds 8 MiB")
            digest.update(line)
            item = json.loads(line, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"invalid stream number {value}")))
            if not isinstance(item, dict) or trailer is not None:
                raise ValueError("invalid records after stream trailer")
            if header is None:
                if item.get("type") != "header" or item.get("format") != "openrc-frame-stream v1":
                    raise ValueError("invalid stream header")
                header = item
                continue
            if item.get("type") == "trailer":
                trailer = item
                continue
            if item.get("type") != "chunk" or item.get("sequence") != chunks or item.get("start_frame") != count:
                raise ValueError("frame stream sequence discontinuity")
            size = item.get("frames")
            if type(size) is not int or not 1 <= size <= 512:
                raise ValueError("invalid chunk frame count")
            walls, ends, engine = item.get("wall_usec"), item.get("end_usec"), item.get("engine_delta_s")
            if not all(isinstance(series, list) and len(series) == size for series in (walls, ends, engine)):
                raise ValueError("inconsistent chunk arrays")
            for wall, end, delta in zip(walls, ends, engine):
                if type(wall) is not int or type(end) is not int or wall <= 0 or end < wall or type(delta) not in (float, int) or not math.isfinite(delta) or delta < 0:
                    raise ValueError("invalid frame clock")
                if previous_end is not None and end - wall != previous_end:
                    raise ValueError("noncontiguous frame intervals")
                previous_end = end
            metrics = item.get("metrics")
            if not isinstance(metrics, dict) or len(metrics) > 64:
                raise ValueError("invalid metric schema")
            if "phase_index" not in metrics:
                raise ValueError("phase_index is required for phase reduction")
            if metric_schema is None:
                metric_schema = sorted(metrics)
            if sorted(metrics) != metric_schema:
                raise ValueError("metric schema changed")
            for key, series in metrics.items():
                if not isinstance(key, str) or not isinstance(series, list) or len(series) != size or any(type(value) not in (float, int) or not math.isfinite(value) for value in series):
                    raise ValueError("invalid metric values")
            for offset, (phase_index, wall) in enumerate(zip(metrics.get("phase_index", []), walls)):
                if phase_index != int(phase_index) or not 0 <= phase_index <= 10000:
                    raise ValueError("invalid phase index")
                if previous_phase is not None and phase_index != previous_phase:
                    for stats in phase_hitches[str(int(previous_phase))].values():
                        stats["consecutive"] = 0
                        stats["consecutive_ms"] = 0.0
                previous_phase = phase_index
                phase_samples[str(int(phase_index))].append(wall)
                phase_final_counters[str(int(phase_index))] = {key: metrics[key][offset] for key in ("memory_static_bytes", "resource_count", "orphan_node_count", "render_texture_memory_bytes") if key in metrics}
                for limit, stats in phase_hitches[str(int(phase_index))].items():
                    if wall / 1000 > float(limit):
                        if not stats["consecutive"]:
                            stats["runs"] += 1
                        stats["frames"] += 1
                        stats["consecutive"] += 1
                        stats["consecutive_ms"] += wall / 1000
                        stats["max_run_ms"] = max(stats["max_run_ms"], stats["consecutive_ms"])
                        stats["max_consecutive"] = max(stats["max_consecutive"], stats["consecutive"])
                        stats["excess_ms"] += wall / 1000 - float(limit)
                        stats["slow_time_ms"] += wall / 1000
                    else:
                        stats["consecutive"] = 0
                        stats["consecutive_ms"] = 0.0
                entry = (wall, count + offset, int(phase_index), ends[offset])
                if len(slowest) < 20: heapq.heappush(slowest, entry)
                elif entry > slowest[0]: heapq.heapreplace(slowest, entry)
            count += size
            chunks += 1
    if header is None or trailer is None:
        raise ValueError("frame stream is an interrupted prefix")
    if stream.get("bytes") != path.stat().st_size or stream.get("sha256") != digest.hexdigest():
        raise ValueError("frame stream byte count/hash mismatch")
    if any(item.get("frames") != count or item.get("chunks") != chunks for item in (stream, trailer)) or frames.get("frames") != count:
        raise ValueError("frame stream receipt mismatch")
    if frames.get("complete") is not True or stream.get("complete") is not True or trailer.get("complete") is not True:
        raise ValueError("frame collection is incomplete")
    if count == 0:
        raise ValueError("empty frame collection")
    phase_stats = {}
    phase_pacing = {}
    for index, values in phase_samples.items():
        elapsed_ms = sum(values) / 1000
        phase_pacing[index] = {"frames": len(values), "sample_wall_ms": elapsed_ms,
                               "fps_mean": len(values) * 1000 / elapsed_ms,
                               "assignment": "phase_index at interval end; denominator is assigned wall time"}
        for stats in phase_hitches[index].values():
            stats["slow_time_percent"] = 100 * stats["slow_time_ms"] / elapsed_ms
            stats["over_budget_percent"] = 100 * stats["frames"] / len(values)
        values.sort()
        for suffix, fraction in (("1pct", .01), ("01pct", .001)):
            tail = max(1, math.floor(len(values) * fraction))
            phase_pacing[index][f"fps_{suffix}_low"] = tail * 1_000_000 / sum(values[-tail:])
            phase_pacing[index][f"low_{suffix}_frames"] = tail
            phase_pacing[index][f"low_{suffix}_status"] = "available" if len(values) >= round(1/fraction) else "short_sample"
        phase_pacing[index]["low_method"] = "reciprocal of mean slowest tail; floor(N*fraction), at least one sample"
        phase_stats[index] = {name: values[max(0, math.ceil(q*len(values))-1)] / 1000 for name, q in (("p50", .5), ("p95", .95), ("p99", .99), ("max", 1))}
    return {"valid": True, "frames": count, "chunks": chunks, "phase_stats": phase_stats,
            "phase_hitches": dict(phase_hitches), "phase_pacing": phase_pacing,
            "phase_final_counters": phase_final_counters,
            "slowest_frames": [dict(wall_ms=w/1000, frame=i, phase_index=p, end_usec=end) for w,i,p,end in sorted(slowest, reverse=True)]}


def runway_receipt_valid(value: dict) -> bool:
    """Do not turn a pilot's bare done flag or heading rotation into runway coverage."""
    if not isinstance(value, dict) or value.get("format") != "openrc-godtest-runway-circuit-v1" or value.get("complete") is not True or value.get("failed") is not False:
        return False
    fields = ("center_north_m", "center_east_m", "target_radius_m", "runway_enclosing_radius_m",
              "inner_radius_m", "outer_radius_m", "clockwise_sweep_rad", "lap_sim_seconds",
              "minimum_radius_m", "maximum_radius_m", "minimum_agl_m", "maximum_agl_m")
    if any(type(value.get(key)) not in (float, int) or not math.isfinite(value[key]) for key in fields):
        return False
    return (value.get("quadrants_mask") == 15 and value["clockwise_sweep_rad"] >= math.tau - 1e-9
            and value["lap_sim_seconds"] >= 10 and value["runway_enclosing_radius_m"] > 0
            and value["inner_radius_m"] > value["runway_enclosing_radius_m"]
            and value["inner_radius_m"] <= value["target_radius_m"] <= value["outer_radius_m"]
            and value["inner_radius_m"] <= value["minimum_radius_m"] <= value["maximum_radius_m"] <= value["outer_radius_m"]
            and value.get("agl_limits_m") == [20, 140]
            and 20 <= value["minimum_agl_m"] <= value["maximum_agl_m"] <= 140)


def watch_report(directory: Path, execution: dict, runtime: dict, problems: list[str]) -> dict:
    """Keep the bridge's original format and validate its separately owned receipt."""
    receipt = execution.get("frame_watch", {})
    try:
        path = directory / "frame-watch/watch.json"
        if receipt.get("status") != "complete" or receipt.get("error") or receipt.get("thread_alive") is not False or receipt.get("source_changed") is not False:
            raise ValueError("frame watcher did not complete cleanly")
        sources = receipt.get("source_sha256", {})
        expected_sources = {"tools/godtest/frame_monitor.py", "tools/debug/frame_watch.py", "tools/debug/frame_capture.py", "tools/debug/debugctl.py"}
        if not isinstance(sources, dict) or set(sources) != expected_sources or not all(_sha256(value) for value in sources.values()):
            raise ValueError("frame watcher source identity is missing or invalid")
        monitor_source = execution.get("orchestrator_sources", {}).get("frame_monitor.py")
        if monitor_source is not None and sources["tools/godtest/frame_monitor.py"] != monitor_source:
            raise ValueError("frame watcher source differs from the loaded orchestrator")
        if not path.is_file() or path.is_symlink():
            raise ValueError("frame watcher artifact is missing")
        if receipt.get("report_sha256") != hashlib.sha256(path.read_bytes()).hexdigest():
            raise ValueError("frame watcher artifact hash differs from its execution receipt")
        value = read_json(path)
        if value.get("format") != "openrc-debug-frame-watch v1" or value.get("outcome") != "owner_stopped" or value.get("error") or value.get("final_poll") != "complete":
            raise ValueError("incomplete or unsupported frame watch")
        segments = value.get("segments", [])
        if len(segments) != 1 or value.get("gaps"):
            raise ValueError("frame watch has missing frames or changed epochs")
        segment = segments[0]
        identity = {key: segment.get(key) for key in ("capture_id", "launch_instance", "epoch")}
        armed = runtime.get("identity", {}).get("frame_watch", {})
        if identity != value.get("identity") or identity != receipt.get("identity") or identity != armed.get("identity") or armed.get("run_id") != directory.name:
            raise ValueError("frame watch identity differs from the armed runtime")
        if not segment.get("overall", {}).get("frames") or segment.get("rows_lost") != 0 or segment.get("coverage") != "contiguous":
            raise ValueError("frame watch contains no complete continuous sample")
        totals = segment.get("reconciliation", {})
        if set(totals) != {"relative_stutter_total", "stall_total", "hitch_total"} or any(item.get("agrees") is not True for item in totals.values()):
            raise ValueError("frame watch counters do not reconcile")
        # Both recorders use the engine's monotonic clock; the route string alone
        # cannot distinguish a paused Settings overlay from active flight.
        incidents = []
        for incident in value.get("incidents", []):
            item = dict(incident)
            item["triggers"] = [dict(trigger, phase_at_interval_end=next(
                (phase.get("id") for phase in runtime.get("phases", [])
                 if type(trigger.get("end_usec")) is int and phase.get("start_usec", math.inf) <= trigger["end_usec"] < phase.get("end_usec", -math.inf)), None))
                for trigger in incident.get("triggers", [])]
            incidents.append(item)
        return {"status": "complete", "path": "frame-watch/watch.json", "html": "frame-watch/report.html",
                "scope": receipt.get("coverage_scope"), "overall": segment["overall"],
                "incidents": incidents, "hangs": value.get("hangs", []), "policy": value.get("policy", {}),
                "triggers_not_captured": value.get("triggers_not_captured", {}), "drop_blind_s": value.get("drop_blind_s"),
                "phase_assignment": "trigger interval end on engine clock; overlapping transitions remain boundary observations"}
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        problems.append(str(error))
        return {"status": "incomplete", "error": str(error)}


def _sha256(value) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(char in "0123456789abcdef" for char in value)


def _verify_gpu_samples(value: dict, execution: dict) -> None:
    """Recheck utilization evidence instead of accepting an `available` label alone."""
    digest = value.get("source_sha256")
    if not _sha256(digest) or value.get("source_changed") is not False or execution.get("orchestrator_sources", {}).get("hardware.py") != digest:
        raise ValueError("GPU sampler source identity changed or is unverified")
    if value.get("source_end_sha256") != digest:
        raise ValueError("GPU sampler final source identity is unverified")
    if value.get("thread_alive") is not False or value.get("sample_cap_reached") is not False or value.get("worker_exit_reason") != "owner_stopped":
        raise ValueError("GPU sampler did not stop cleanly within its coverage bound")
    samples = value.get("samples")
    if not isinstance(samples, list) or len(samples) < 2 or value.get("sample_count") != len(samples):
        raise ValueError("GPU utilization needs at least two verified samples")
    timing = value.get("timing_coverage", {})
    interval = value.get("interval_seconds")
    if type(interval) not in (int, float) or not math.isfinite(interval) or interval <= 0 or timing.get("status") != "complete":
        raise ValueError("GPU sampling time coverage is incomplete")
    gap_limit = round((3 * interval + 0.25) * 1_000_000)
    start, stop = value.get("start_monotonic_usec"), value.get("stop_requested_monotonic_usec")
    if type(start) is not int or type(stop) is not int or not 0 <= start <= stop:
        raise ValueError("GPU sampling observation bounds are invalid")
    observed, previous_start, previous_end = {}, None, start
    for sample in samples:
        before, after = sample.get("start_monotonic_usec"), sample.get("end_monotonic_usec")
        if type(before) is not int or type(after) is not int or not previous_end <= before <= after:
            raise ValueError("GPU sample clock brackets are invalid or out of order")
        if before - (previous_start if previous_start is not None else start) > gap_limit:
            raise ValueError("GPU sample clock contains an excessive gap")
        if before > stop:
            raise ValueError("GPU sample starts after the owner requested stop")
        previous_start, previous_end = before, after
        backends = sample.get("backends")
        if not isinstance(backends, list) or not backends:
            raise ValueError("GPU sample has no backend observations")
        in_poll = set()
        for backend in backends:
            lower, upper = backend.get("start_monotonic_usec"), backend.get("end_monotonic_usec")
            if type(lower) is not int or type(upper) is not int or not before <= lower <= upper <= after:
                raise ValueError("GPU backend clock brackets are outside their poll")
            devices = backend.get("devices")
            if not isinstance(devices, list):
                raise ValueError("GPU backend device list is invalid")
            for device in devices:
                identity = device.get("identity", {})
                key, utilization = identity.get("key"), device.get("metrics", {}).get("gpu_utilization_pct")
                if not isinstance(key, str) or not key or key in in_poll or type(utilization) not in (int, float) or not math.isfinite(utilization) or not 0 <= utilization <= 100:
                    raise ValueError("GPU utilization or device identity is missing or invalid")
                if device.get("metric_status", {}).get("gpu_utilization_pct") != "available" or backend.get("status") != "available":
                    raise ValueError("GPU utilization observation is incomplete")
                in_poll.add(key)
                entry = observed.setdefault(key, {"identity": identity, "backend": backend.get("backend"), "values": []})
                if entry["identity"] != identity or entry["backend"] != backend.get("backend"):
                    raise ValueError("GPU device identity changed during observation")
                entry["values"].append(utilization)
    if max(0, stop - previous_end) > gap_limit:
        raise ValueError("GPU observation stopped before the owned run ended")
    summary = value.get("summary_by_device", {})
    if not observed or set(summary) != set(observed):
        raise ValueError("GPU summary does not match observed devices")
    for key, item in observed.items():
        values, recorded = item["values"], summary[key]
        stats = recorded.get("metrics", {}).get("gpu_utilization_pct", {})
        expected = {"min": min(values), "max": max(values), "mean": statistics.mean(values)}
        if (len(values) != len(samples) or recorded.get("samples") != len(values) or stats.get("count") != len(values)
                or recorded.get("identity") != item["identity"] or recorded.get("backend") != item["backend"]
                or any(type(stats.get(k)) not in (int, float) or not math.isfinite(stats[k]) or not math.isclose(stats[k], v, rel_tol=1e-9, abs_tol=1e-9) for k, v in expected.items())):
            raise ValueError("GPU summary or per-device coverage differs from raw utilization")


def hardware_report(directory: Path, execution: dict, required: bool) -> tuple[dict, dict, dict]:
    """Keep capability and sample coverage separate from frame-data integrity."""
    resources = {"status": "not_requested", "rss_peak_bytes": None, "cpu_percent_mean": None}
    gpu = {"status": "not_requested", "summary_by_device": {}}
    issues = []
    for filename, key in (("resources.json", "resources"), ("gpu.json", "gpu")):
        path = directory / filename
        requested = required or execution.get("resource_sampling" if key == "resources" else "gpu_sampling")
        if not requested and not path.exists():
            continue
        try:
            if path.is_symlink() or not path.is_file():
                raise ValueError(f"{key} artifact is missing")
            expected = execution.get(key + "_sha256")
            if (required or expected) and expected != hashlib.sha256(path.read_bytes()).hexdigest():
                raise ValueError(f"{key} artifact does not match its execution receipt")
            value = read_json(path, 128 * 1024 * 1024 if key == "gpu" else 32 * 1024 * 1024)
            if key == "gpu":
                if value.get("format") != "openrc-godtest-gpu-v1":
                    raise ValueError("unsupported GPU sample format")
                gpu = {k: v for k, v in value.items() if k != "samples"}
                gpu["path"] = filename
                gpu["correlation"] = "whole-device observations; renderer-device binding and frame causation are not established"
                if value.get("status") != "available" or value.get("thread_alive"):
                    issues.append("GPU utilization sampling is " + str(value.get("status", "unavailable")))
                else:
                    _verify_gpu_samples(value, execution)
                continue
            if value.get("format") != "openrc-resource-samples v1":
                raise ValueError("unsupported process sample format")
            if required and (not _sha256(execution.get("resource_sampler_source_sha256")) or execution.get("resource_sampler_source_changed") is not False):
                raise ValueError("process resource sampler source identity changed or is unverified")
            samples = value.get("samples", [])
            if not isinstance(samples, list) or len(samples) < 2 or value.get("sample_count") != len(samples):
                raise ValueError("process resources need at least two verified samples")
            if value.get("identity_status") != "verified" or value.get("pid") != execution.get("launch", {}).get("pid"):
                raise ValueError("process resources do not identify the launched simulator")
            fields = ("elapsed_seconds", "cpu_user_seconds", "cpu_system_seconds", "rss_bytes")
            if any(not isinstance(row, dict) or any(type(row.get(k)) not in (float, int) or not math.isfinite(row[k]) or row[k] < 0 for k in fields) for row in samples):
                raise ValueError("process resource counters are missing or invalid")
            for earlier, later in zip(samples, samples[1:]):
                if later["elapsed_seconds"] <= earlier["elapsed_seconds"] or any(later[k] < earlier[k] for k in ("cpu_user_seconds", "cpu_system_seconds")):
                    raise ValueError("process resource clock/counters decreased")
            elapsed = samples[-1]["elapsed_seconds"] - samples[0]["elapsed_seconds"]
            cpu_seconds = sum(samples[-1][k] - samples[0][k] for k in ("cpu_user_seconds", "cpu_system_seconds"))
            peak = value.get("summary", {}).get("peaks", {})
            resources = {"status": value.get("measurement_status", "unknown"), "path": filename,
                "identity": value.get("identity_status"), "pid": value.get("pid"),
                "coverage": value.get("required_coverage"), "samples": len(samples),
                "sampled_wall_seconds": elapsed, "cpu_seconds": cpu_seconds,
                "cpu_percent_mean": 100 * cpu_seconds / elapsed,
                "cpu_percent_peak": peak.get("cpu_percent"),
                "rss_peak_bytes": max(row["rss_bytes"] for row in samples),
                "rss_delta_bytes": samples[-1]["rss_bytes"] - samples[0]["rss_bytes"],
                "threads_peak": peak.get("num_threads"),
                "io_counter_deltas": value.get("summary", {}).get("counter_deltas", {}),
                "scope": execution.get("resource_scope"), "errors": value.get("errors", []),
                "cpu_scope": "direct process; 100% means one logical CPU fully occupied; may exceed 100%",
                "phase_correlation": "host monotonic samples are separate from engine phase clock; no same-frame causal claim"}
            if value.get("required_coverage") != "complete":
                issues.append("process resource sample coverage is incomplete")
        except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
            issues.append(str(error))
            if key == "gpu":
                gpu = {"status": "unavailable", "error": str(error), "summary_by_device": {}}
            else:
                resources.update(status="unavailable", error=str(error))
    complete = (resources.get("coverage") == "complete" and gpu.get("status") == "available" and not issues)
    return resources, gpu, {"required": required, "complete": complete, "issues": issues,
                            "scope": "after bridge readiness; early startup and physical presentation are not sampled"}


def report(directory: Path, *, write: bool = True) -> dict:
    directory = directory.resolve()
    manifest = read_json(directory / "manifest.resolved.json", 65536)
    execution = read_json(directory / "execution.json") if (directory / "execution.json").exists() else {}
    runtime = read_json(directory / "runtime.json") if (directory / "runtime.json").exists() else {}
    frames = read_json(directory / "frametimes.json") if (directory / "frametimes.json").exists() else {}
    problems = []
    integrity = {}
    try:
        if frames.get("format") != "openrc-godtest-frames-v1" or frames.get("completion_kind") != "scenario_event":
            raise ValueError("unsupported event frame format")
        integrity = validate_stream(directory, frames)
    except (OSError, ValueError, TypeError, KeyError) as error:
        problems.append(str(error))
    if runtime.get("format") != "openrc-godtest-runtime-v1":
        problems.append("missing or unsupported runtime report")
    if execution.get("failure"):
        problems.append(execution["failure"])
    if execution.get("log", {}).get("counts", {}).get("error", 0):
        problems.append("engine errors recorded")
    if execution.get("log", {}).get("missing_required_text"):
        problems.append("runtime completion marker missing")
    shutdown = execution.get("shutdown", {})
    if not shutdown.get("stopped") or shutdown.get("forced") or shutdown.get("crash") or shutdown.get("launcher_exit_code") != 0:
        problems.append("clean owned process exit was not verified")
    if execution.get("source_changed"):
        problems.append("source changed during execution")
    if execution.get("engine_command_verified") is False or execution.get("engine_files_changed"):
        problems.append("engine executable identity changed or differs from the launched command")
    if runtime.get("complete") is not True or runtime.get("data") != "complete":
        problems.append("runtime/data incomplete")
    phase_records = runtime.get("phases", [])
    if not isinstance(phase_records, list):
        problems.append("invalid phase records")
        phase_records = []
    for phase in phase_records:
        if not isinstance(phase, dict) or phase.get("status") not in ("complete", "failed", "unsupported"):
            problems.append("invalid phase result")
            break
        observed = integrity.get("phase_stats", {}).get(str(phase.get("index")))
        phase["frame_ms"] = observed or {"p50": None, "p95": None, "p99": None, "max": None}
        phase["frame_statistics_status"] = "available" if observed else "unavailable_no_verified_samples"
        phase["pacing"] = integrity.get("phase_pacing", {}).get(str(phase.get("index")), {})
        if not observed and phase.get("requested") and phase.get("status") == "complete":
            problems.append(f"requested phase has no verified frame samples: {phase.get('id')}")
        phase["hitches"] = integrity.get("phase_hitches", {}).get(str(phase.get("index")), {})
        phase["engine_counters_at_last_sample"] = integrity.get("phase_final_counters", {}).get(str(phase.get("index")), {})
        for key in ("wall_seconds", "sim_seconds"):
            if type(phase.get(key)) not in (float, int) or not math.isfinite(phase[key]) or phase[key] < 0:
                problems.append(f"invalid phase {key}")
        for key in ("p50", "p95", "p99", "max"):
            value = phase.get("frame_ms", {}).get(key)
            if value is None and not observed:
                continue
            if type(value) not in (float, int) or not math.isfinite(value) or value < 0:
                problems.append("invalid phase frame distribution")
    rendered = runtime.get("metrics", {}).get("rendered") is True and manifest.get("headless") is False
    display_ok = runtime.get("metrics", {}).get("requested_resolution_match") is True
    if rendered and not display_ok:
        problems.append("actual window dimensions differ from requested workload")
    diagnostic = runtime.get("identity", {}).get("diagnostics", {})
    if rendered:
        for key, expected in execution.get("rendering_requested", {}).items():
            if diagnostic.get(key) != expected:
                problems.append(f"actual {key} differs from requested workload")
        adapter = str(diagnostic.get("adapter_name", "")).lower()
        if any(name in adapter for name in ("llvmpipe", "lavapipe", "swiftshader", "software rasterizer", "microsoft basic render")):
            problems.append("software renderer cannot qualify target-GPU performance")
    if manifest.get("isolated_user_dir"):
        isolation = execution.get("profile_isolation", {})
        if (runtime.get("identity", {}).get("user_dir") != manifest["isolated_user_dir"] or
                isolation.get("user_dir") != manifest["isolated_user_dir"] or
                isolation.get("project_name") != manifest.get("isolated_project_name")):
            problems.append("macOS runtime profile does not match its isolated launch receipt")
    coverage = runtime.get("coverage", "none")
    missing_phases = [name for name in manifest.get("phases", []) if name != "shutdown" and not any(p.get("name") == name and p.get("requested") for p in phase_records)]
    if missing_phases:
        problems.append("requested phases are absent: " + ", ".join(missing_phases))
        coverage = "partial"
    if any(p.get("requested") and p.get("status") != "complete" for p in phase_records):
        coverage = "partial"
    for phase in phase_records:
        if phase.get("name") == "runway_circuit" and phase.get("status") == "complete" and not runway_receipt_valid(phase.get("pilot", {}).get("runway_circuit")):
            problems.append("completed runway circuit has no valid position-based lap receipt")
            coverage = "partial"
        if phase.get("name") in ("menu_settings", "menu_controls") and phase.get("status") == "complete":
            if phase.get("menu_screen") != phase["name"].removeprefix("menu_") or phase.get("pause_tick_invariant") is not True or phase.get("pause_state_invariant") is not True or type(phase.get("resume_to_tick_ms")) not in (float, int) or not math.isfinite(phase["resume_to_tick_ms"]):
                problems.append("completed menu phase lacks pause/return/resume evidence")
                coverage = "partial"
    watched = watch_report(directory, execution, runtime, problems) if manifest.get("watch_frames") else {"status": "not_requested"}
    if manifest.get("require_native") and rendered and runtime.get("identity", {}).get("backend", {}).get("backend") != "native":
        problems.append("rendered performance workload requires actual native physics; reference fallback was observed")
    if runtime.get("metrics", {}).get("focus_losses", 0):
        problems.append("native focus loss observed; session equivalence requires diagnosis")
    active = [p for p in phase_records if p.get("name") in ("takeoff", "climb_right", "farmhouse", "flag", "right_circuit", "runway_circuit", "roll", "recover", "large_loop", "approach", "landing", "stop") and p.get("status") == "complete"]
    targets = []
    for phase in active:
        duration = phase.get("wall_seconds", 0)
        ratio = phase.get("sim_seconds", 0) / duration if duration else None
        available = phase["frame_statistics_status"] == "available"
        targets.append({"phase_id": phase.get("id"), "pacing_target": ("screen_only" if duration < 60 else "observed") if available else "unavailable",
                        "p95_within_18ms": phase["frame_ms"]["p95"] <= 18 if available else None,
                        "p99_within_25ms": phase["frame_ms"]["p99"] <= 25 if available else None,
                        "simulation_wall_ratio": ratio, "simulation_pace_target_met": ratio is not None and 0.99 <= ratio <= 1.01})
    loading = []
    for phase in phase_records:
        if phase.get("name") in ("startup", "loading"):
            loading.append(dict(phase_id=phase.get("id"), seconds=phase.get("wall_seconds"),
                                scope="internal startup to Home" if phase["name"] == "startup" else "Fly through ready/draw and benchmark binding",
                                target_seconds=5 if phase["name"] == "startup" else 2,
                                screen_target_met=phase.get("wall_seconds", math.inf) <= (5 if phase["name"] == "startup" else 2),
                                qualification="scope/repeats must match owning loading protocol"))
    resources, gpu, monitoring = hardware_report(directory, execution, manifest.get("monitor_hardware", False))
    flight_observations = []
    for phase in phase_records:
        pilot = phase.get("pilot", {})
        if phase.get("name") not in ("landing", "stop") or not pilot.get("touchdown"):
            continue
        margin = pilot.get("minimum_wheel_runway_margin_m")
        flight_observations.append(dict(phase_id=phase.get("id"), touchdown=pilot["touchdown"],
                                       contact_episodes=pilot.get("contact_episodes"),
                                       maximum_contact_sink_mps=pilot.get("maximum_contact_sink_mps"),
                                       minimum_wheel_runway_margin_m=margin,
                                       wheel_outside_runway_observed=type(margin) in (int, float) and margin < 0))
    result = dict(format="openrc-godtest-report-v1", reducer_sha256=REDUCER_SHA256,
                  run_dir=str(directory), scenario=manifest["id"], aircraft=manifest["aircraft"],
                  execution=runtime.get("execution", execution.get("state", "unknown")), data="valid" if not problems else "ineligible",
                  coverage=coverage, flight=runtime.get("flight", "not_run"), rendered=rendered,
                  performance="single_run_screen" if rendered and not problems and coverage == "complete" and (not monitoring["required"] or monitoring["complete"]) else "not_qualified",
                  hardware_qualified=False, repeat_campaign="not_collected", issues=problems,
                  phases=phase_records, metrics=runtime.get("metrics", {}), integrity=integrity,
                  targets=targets, loading=loading, resources=resources, shutdown=shutdown,
                  flight_observations=flight_observations, frame_watch=watched,
                  physics_backend=runtime.get("identity", {}).get("backend", {}), gpu=gpu, monitoring=monitoring)
    if write:
        write_json(directory / "report.json", result)
        def number(value):
            return "unavailable" if value is None else f"{value:.2f}"
        rows = "".join(f"<tr><td>{html.escape(str(p.get('name')))}</td><td>{html.escape(str(p.get('status')))}</td><td>{p.get('wall_seconds', 0):.3f}</td><td>{number(p.get('frame_ms', {}).get('p95'))}</td><td>{number(p.get('frame_ms', {}).get('p99'))}</td><td>{number(p.get('pacing', {}).get('fps_mean'))}</td><td>{number(p.get('hitches', {}).get('16.667', {}).get('slow_time_percent'))}</td><td>{p.get('hitches', {}).get('16.667', {}).get('max_consecutive', 'unavailable')}</td><td>{html.escape(str(p.get('reason', '')))}</td></tr>" for p in phase_records)
        document = f"""<!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content='width=device-width'><title>OpenRC GOD TEST</title><style>body{{font:16px system-ui;margin:3em;max-width:90em;background:#10171d;color:#e6eef5}}table{{border-collapse:collapse;width:100%}}td,th{{padding:.6em;border-bottom:1px solid #43515d;text-align:left}}code{{color:#9ed7cb}}li{{margin:.4em 0}}</style><h1>OpenRC GOD TEST · {html.escape(manifest['id'])}</h1><p>Execution: {html.escape(str(result['execution']))} · Data: {result['data']} · Coverage: {html.escape(str(coverage))} · Flight: {html.escape(str(result['flight']))}</p><p>{'Rendered' if rendered else 'Headless / drawing unqualified'} · Single instrumented run. Hardware qualification and physical validation remain separate.</p><ul>{''.join('<li>'+html.escape(issue)+'</li>' for issue in problems)}</ul><table><thead><tr><th>Phase</th><th>Status</th><th>Wall s</th><th>p95 ms</th><th>p99 ms</th><th>Mean callback FPS</th><th>Slow wall % (&gt;16.667 ms)</th><th>Max slow run (frames)</th><th>Reason</th></tr></thead><tbody>{rows}</tbody></table><p>Raw evidence is retained beside this report. GPU counters are not display presentation times. Short phase percentiles are exploratory. FPS and slow-wall share use the sum of intervals assigned at their end to each phase, which differs from event-bounded phase duration. Threshold runs stop at phase changes; edge runs may be clipped. Detailed 16.667/33.333/50/100 ms observations are in report.json. These fixed thresholds are distinct from the debug bridge target plus tolerance.</p></html>"""
        flight_notes = "".join(f"<li>{html.escape(str(item['phase_id']))}: wheel contact outside the runway rectangle was observed (minimum margin {item['minimum_wheel_runway_margin_m']:.2f} m). Collection and stopping coverage do not establish a successful runway landing.</li>" for item in flight_observations if item["wheel_outside_runway_observed"])
        if flight_notes:
            document = document.replace("<table>", "<ul>" + flight_notes + "</ul><table>", 1)
        if manifest.get("watch_frames"):
            summary = watched.get("overall", {})
            watch_section = f"<h2>Stutters and FPS drops</h2><p>Watcher: {html.escape(watched['status'])}. Relative stutter frames: {summary.get('relative_stutter_frames', 'unavailable')}; stalls: {summary.get('stall_frames', 'unavailable')}; incidents: {len(watched.get('incidents', []))}; freezes: {len(watched.get('hangs', []))}.</p><p>1% low: {number(summary.get('fps_1pct_low'))} FPS; 0.1% low: {number(summary.get('fps_01pct_low'))} FPS. <a href='frame-watch/report.html'>Open the original stutter report and incident evidence</a>.</p><p>Watching begins after the Home arming barrier; earlier startup is covered only by GOD TEST. Bridge route statistics combine flight and its menu overlays. Incident triggers in report.json are associated with the GOD TEST phase at interval end. Short-tail and detector warmup limits remain in the original report.</p>"
            document = document.replace("</html>", watch_section + "</html>")
        if monitoring["required"] or execution.get("resource_sampling"):
            hardware_section = f"<h2>CPU, GPU and memory</h2><p>Monitoring complete: {monitoring['complete']}. Process CPU mean: {number(resources.get('cpu_percent_mean'))}% of one logical CPU. Process RSS peak: {number(resources.get('rss_peak_bytes') / 1048576 if resources.get('rss_peak_bytes') is not None else None)} MiB. GPU utilization: {html.escape(str(gpu.get('status')))}.</p><ul>{''.join('<li>'+html.escape(issue)+'</li>' for issue in monitoring['issues'])}</ul><p><a href='resources.json'>Process samples</a> · <a href='gpu.json'>Per-device GPU samples</a>. Measurements begin after bridge readiness. GPU activity includes other processes; the sampled device is not automatically identified as the renderer. Missing counters remain unavailable.</p>"
            document = document.replace("</html>", hardware_section + "</html>")
        (directory / "report.html").write_text(document, encoding="utf-8")
    return result


def compare(baseline: Path, candidate: Path, phase_name: str | None = None) -> dict:
    paths = [baseline.resolve(), candidate.resolve()]
    reports = [report(path, write=False) for path in paths]
    manifests = [read_json(path / "manifest.resolved.json") for path in paths]
    runtimes = [read_json(path / "runtime.json") for path in paths]
    executions = [read_json(path / "execution.json") for path in paths]
    reasons = []
    for role, result in zip(("baseline", "candidate"), reports):
        if result["data"] != "valid": reasons.append(f"{role}: ineligible artifacts")
        if not result["rendered"]: reasons.append(f"{role}: rendered performance not established")
        if not phase_name and result["coverage"] != "complete": reasons.append(f"{role}: incomplete coverage")
    ignored = {"output_dir", "isolated_user_dir", "isolated_project_name"}
    if {k: v for k, v in manifests[0].items() if k not in ignored} != {k: v for k, v in manifests[1].items() if k not in ignored}:
        reasons.append("requested workload differs")
    for key in ("actual_resolution", "viewport_size", "selection", "backend", "scenery_sha256", "field", "pilot", "camera", "effective_weather", "effective_lighting", "effective_sky"):
        if runtimes[0].get("identity", {}).get(key) != runtimes[1].get("identity", {}).get(key):
            reasons.append(f"effective {key} differs")
    hardware_keys = ("cpu_model", "adapter_name", "adapter_vendor", "adapter_api_version", "os_name", "os_version", "rendering_method", "rendering_driver", "vsync_mode", "max_fps", "reconstruction_at_start")
    for key in hardware_keys:
        values = [runtime.get("identity", {}).get("diagnostics", {}).get(key) for runtime in runtimes]
        if values[0] != values[1] or values[0] is None:
            reasons.append(f"hardware/render identity unavailable or different: {key}")
    if executions[0].get("engine_files") != executions[1].get("engine_files"):
        reasons.append("engine executable identity differs")
    if executions[0].get("resource_sampling") != executions[1].get("resource_sampling"):
        reasons.append("external observer configuration differs")
    selected = [[p for p in result["phases"] if p.get("requested") and (phase_name is None or p["name"] == phase_name)] for result in reports]
    if any(not rows for rows in selected): reasons.append("requested comparison phase is absent")
    if any(p["status"] != "complete" for rows in selected for p in rows): reasons.append("selected phase coverage is incomplete")
    if [[(p["name"], p["cycle"]) for p in rows] for rows in selected][0] != [[(p["name"], p["cycle"]) for p in rows] for rows in selected][1]:
        reasons.append("selected phase layout differs")
    # Route equivalence needs an explicit geometric receipt. Startup/loading/pause are
    # independently bounded transitions; adaptive flight is conservatively unqualified.
    if phase_name not in ("startup", "loading", "selection", "pause", "home"):
        reasons.append("adaptive whole-flight geometric equivalence has not been qualified; select a transition phase")
    changes = []
    if not reasons:
        for left, right in zip(*selected):
            delta = {}
            for key in ("p50", "p95", "p99", "max"):
                a, b = left["frame_ms"][key], right["frame_ms"][key]
                delta[key] = {"baseline_ms": a, "candidate_ms": b, "delta_ms": b-a, "change_pct": (b/a-1)*100 if a else None}
            changes.append(dict(phase=left["name"], cycle=left["cycle"], frames=delta, baseline_wall_s=left["wall_seconds"], candidate_wall_s=right["wall_seconds"]))
    return dict(format="openrc-godtest-comparison-v1", eligible=not reasons, reasons=reasons, changes=changes,
                confidence="single_pair_screen_only", regression_verdict="inconclusive_without_repeated_pairs")
