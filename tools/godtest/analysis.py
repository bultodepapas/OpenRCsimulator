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
    phase_hitches = defaultdict(lambda: {str(limit): dict(frames=0, consecutive=0, max_consecutive=0, excess_ms=0.0) for limit in (16.667, 33.333, 50, 100)})
    phase_final_counters = {}
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
                phase_samples[str(int(phase_index))].append(wall)
                phase_final_counters[str(int(phase_index))] = {key: metrics[key][offset] for key in ("memory_static_bytes", "resource_count", "orphan_node_count", "render_texture_memory_bytes") if key in metrics}
                for limit, stats in phase_hitches[str(int(phase_index))].items():
                    if wall / 1000 > float(limit):
                        stats["frames"] += 1
                        stats["consecutive"] += 1
                        stats["max_consecutive"] = max(stats["max_consecutive"], stats["consecutive"])
                        stats["excess_ms"] += wall / 1000 - float(limit)
                    else:
                        stats["consecutive"] = 0
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
    for index, values in phase_samples.items():
        values.sort()
        phase_stats[index] = {name: values[max(0, math.ceil(q*len(values))-1)] / 1000 for name, q in (("p50", .5), ("p95", .95), ("p99", .99), ("max", 1))}
    return {"valid": True, "frames": count, "chunks": chunks, "phase_stats": phase_stats,
            "phase_hitches": dict(phase_hitches), "phase_final_counters": phase_final_counters,
            "slowest_frames": [dict(wall_ms=w/1000, frame=i, phase_index=p, end_usec=end) for w,i,p,end in sorted(slowest, reverse=True)]}


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
        if phase.get("frame_statistics") == "offline_from_verified_stream":
            phase["frame_ms"] = integrity.get("phase_stats", {}).get(str(phase.get("index")), {"p50": 0, "p95": 0, "p99": 0, "max": 0})
        phase["hitches"] = integrity.get("phase_hitches", {}).get(str(phase.get("index")), {})
        phase["engine_counters_at_last_sample"] = integrity.get("phase_final_counters", {}).get(str(phase.get("index")), {})
        for key in ("wall_seconds", "sim_seconds"):
            if type(phase.get(key)) not in (float, int) or not math.isfinite(phase[key]) or phase[key] < 0:
                problems.append(f"invalid phase {key}")
        for key in ("p50", "p95", "p99", "max"):
            value = phase.get("frame_ms", {}).get(key)
            if type(value) not in (float, int) or not math.isfinite(value) or value < 0:
                problems.append("invalid phase frame distribution")
    rendered = runtime.get("metrics", {}).get("rendered") is True and manifest.get("headless") is False
    display_ok = runtime.get("metrics", {}).get("requested_resolution_match") is True
    if rendered and not display_ok:
        problems.append("actual window dimensions differ from requested workload")
    coverage = runtime.get("coverage", "none")
    missing_phases = [name for name in manifest.get("phases", []) if name != "shutdown" and not any(p.get("name") == name and p.get("requested") for p in phase_records)]
    if missing_phases:
        problems.append("requested phases are absent: " + ", ".join(missing_phases))
        coverage = "partial"
    if any(p.get("requested") and p.get("status") != "complete" for p in phase_records):
        coverage = "partial"
    if runtime.get("metrics", {}).get("focus_losses", 0):
        problems.append("native focus loss observed; session equivalence requires diagnosis")
    active = [p for p in phase_records if p.get("name") in ("takeoff", "climb_right", "farmhouse", "flag", "right_circuit", "roll", "recover", "large_loop", "approach", "landing", "stop") and p.get("status") == "complete"]
    targets = []
    for phase in active:
        duration = phase.get("wall_seconds", 0)
        ratio = phase.get("sim_seconds", 0) / duration if duration else None
        targets.append({"phase_id": phase.get("id"), "pacing_target": "screen_only" if duration < 60 else "observed",
                        "p95_within_18ms": phase["frame_ms"]["p95"] <= 18,
                        "p99_within_25ms": phase["frame_ms"]["p99"] <= 25,
                        "simulation_wall_ratio": ratio, "simulation_pace_target_met": ratio is not None and 0.99 <= ratio <= 1.01})
    loading = []
    for phase in phase_records:
        if phase.get("name") in ("startup", "loading"):
            loading.append(dict(phase_id=phase.get("id"), seconds=phase.get("wall_seconds"),
                                scope="internal startup to Home" if phase["name"] == "startup" else "Fly through ready/draw and benchmark binding",
                                target_seconds=5 if phase["name"] == "startup" else 2,
                                screen_target_met=phase.get("wall_seconds", math.inf) <= (5 if phase["name"] == "startup" else 2),
                                qualification="scope/repeats must match owning loading protocol"))
    resources = {"status": "not_requested", "rss_peak_bytes": None}
    if (directory / "resources.json").exists():
        sampled = read_json(directory / "resources.json")
        resources = dict(status=sampled.get("measurement_status", "unknown"),
                         identity=sampled.get("identity_status"), coverage=sampled.get("required_coverage"),
                         samples=sampled.get("sample_count"), rss_peak_bytes=sampled.get("summary", {}).get("peaks", {}).get("rss_bytes"),
                         scope=execution.get("resource_scope"), errors=sampled.get("errors", []))
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
                  run_dir=str(directory), scenario=manifest["id"],
                  execution=runtime.get("execution", execution.get("state", "unknown")), data="valid" if not problems else "ineligible",
                  coverage=coverage, flight=runtime.get("flight", "not_run"), rendered=rendered,
                  performance="single_run_screen" if rendered and not problems else "not_qualified",
                  hardware_qualified=False, repeat_campaign="not_collected", issues=problems,
                  phases=phase_records, metrics=runtime.get("metrics", {}), integrity=integrity,
                  targets=targets, loading=loading, resources=resources, shutdown=shutdown,
                  flight_observations=flight_observations)
    if write:
        write_json(directory / "report.json", result)
        rows = "".join(f"<tr><td>{html.escape(str(p.get('name')))}</td><td>{html.escape(str(p.get('status')))}</td><td>{p.get('wall_seconds', 0):.3f}</td><td>{p.get('frame_ms', {}).get('p95', 0):.2f}</td><td>{p.get('frame_ms', {}).get('p99', 0):.2f}</td><td>{html.escape(str(p.get('reason', '')))}</td></tr>" for p in phase_records)
        document = f"""<!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content='width=device-width'><title>OpenRC GOD TEST</title><style>body{{font:16px system-ui;margin:3em;max-width:90em;background:#10171d;color:#e6eef5}}table{{border-collapse:collapse;width:100%}}td,th{{padding:.6em;border-bottom:1px solid #43515d;text-align:left}}code{{color:#9ed7cb}}li{{margin:.4em 0}}</style><h1>OpenRC GOD TEST · {html.escape(manifest['id'])}</h1><p>Execution: {html.escape(str(result['execution']))} · Data: {result['data']} · Coverage: {html.escape(str(coverage))} · Flight: {html.escape(str(result['flight']))}</p><p>{'Rendered' if rendered else 'Headless / drawing unqualified'} · Single instrumented run. Hardware qualification and physical validation remain separate.</p><ul>{''.join('<li>'+html.escape(issue)+'</li>' for issue in problems)}</ul><table><thead><tr><th>Phase</th><th>Status</th><th>Wall s</th><th>p95 ms</th><th>p99 ms</th><th>Reason</th></tr></thead><tbody>{rows}</tbody></table><p>Raw evidence is retained beside this report. GPU counters are not display presentation times. Short phase percentiles are exploratory.</p></html>"""
        flight_notes = "".join(f"<li>{html.escape(str(item['phase_id']))}: wheel contact outside the runway rectangle was observed (minimum margin {item['minimum_wheel_runway_margin_m']:.2f} m). Collection and stopping coverage do not establish a successful runway landing.</li>" for item in flight_observations if item["wheel_outside_runway_observed"])
        if flight_notes:
            document = document.replace("<table>", "<ul>" + flight_notes + "</ul><table>", 1)
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
    ignored = {"output_dir"}
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
