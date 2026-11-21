"""Rebuild a performance-tour index from retained child evidence, not suite flags."""
from __future__ import annotations

from collections import defaultdict
import hashlib
import html
import json
import math
import os
from pathlib import Path
import statistics
from urllib.parse import quote

import catalog
from analysis import report, REDUCER_SOURCES as CASE_REDUCER_SOURCES
from runner import check_frozen, read_json, write_json

FORMAT = "openrc-godtest-performance-tour-report-v1"
TOUR = "performance-tour-v1"
REDUCER_SOURCES = {**CASE_REDUCER_SOURCES, "tour_report.py": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
REDUCER_SHA256 = hashlib.sha256(json.dumps(REDUCER_SOURCES, sort_keys=True).encode()).hexdigest()
# These are the options accepted by the tour CLI. Everything else is the
# reviewed scenario default, including the phase list and instrumentation.
OVERRIDES = ("time", "weather", "sky", "scene_detail", "camera", "seed", "cycles",
             "sample_s", "timeout_s", "phase_timeout_s", "headless", "resolution",
             "rendering_method", "rendering_driver", "window_mode", "max_fps", "vsync_mode")
HARDWARE = ("cpu_model", "adapter_name", "adapter_vendor", "adapter_api_version",
            "os_name", "os_version", "architecture", "rendering_method", "rendering_driver",
            "vsync_mode", "max_fps", "reconstruction_at_start")
METRICS = ("fps_mean", "fps_1pct_low", "fps_01pct_low", "p95_ms", "p99_ms", "worst_ms",
           "slow_frame_percent", "slow_wall_percent", "over_50ms_frames", "over_100ms_frames")


def _planned(index: dict, problems: list[str]) -> list[dict]:
    value = index.get("planned_cases")
    if not isinstance(value, list) or len(value) < 3 or len(value) > 60 or len(value) % 3:
        problems.append("planned roster must contain 1–20 ordered repeats of all three aircraft")
        return []
    if not all(isinstance(row, dict) for row in value):
        problems.append("planned roster contains a non-object manifest")
        return []
    try:
        first = value[0]
        # Missing fields are checked by full equality below rather than defaulted
        # into the recorded manifest.
        options = {key: first[key] for key in OVERRIDES if key in first}
        canonical = catalog.performance_tour(options)
        expected = canonical * (len(value) // 3)
        if value != expected:
            problems.append("planned roster differs from the ordered tour, its requested options, or mandatory defaults/phases")
        for row in value:
            catalog.validate(row)
        return value
    except (KeyError, TypeError, ValueError) as error:
        problems.append(f"invalid planned roster: {error}")
        return []


def _case_path(suite: Path, index: dict, number: int, planned: list[dict],
               entry: dict, visited: set[Path]) -> Path:
    """Follow a recorded same-slot resume chain; never accept a free-form path."""
    raw = entry.get("run_dir")
    if not isinstance(raw, str) or not Path(raw).is_absolute():
        raise ValueError("run_dir must be an absolute recorded path")
    path = Path(raw).resolve()
    if number >= len(planned) or not isinstance(planned[number], dict):
        raise ValueError("case has no corresponding planned manifest")
    catalog.validate(planned[number])
    ident = planned[number].get("id")
    if not isinstance(ident, str):
        raise ValueError("planned case has no scenario id")
    local = suite / f"{number + 1:03d}-{ident}"
    if path == local.resolve():
        if local.is_symlink() or (hasattr(local, "is_junction") and local.is_junction()):
            raise ValueError("case directory is a link or junction")
        return path
    source = index.get("source_suite")
    if not isinstance(source, str) or not Path(source).is_absolute():
        raise ValueError("external run_dir lacks an explicit source_suite")
    prior = Path(source).resolve()
    if prior in visited or len(visited) >= 32:
        raise ValueError("resume provenance is cyclic or too deep")
    previous = read_json(prior / "suite.json")
    if previous.get("format") != "openrc-godtest-suite-v1" or previous.get("suite") != TOUR or previous.get("planned_cases") != planned:
        raise ValueError("source suite does not preserve this tour's planned roster")
    cases = previous.get("cases")
    if not isinstance(cases, list) or number >= len(cases) or not isinstance(cases[number], dict):
        raise ValueError("source suite does not record this case slot")
    prior_entry = cases[number]
    if prior_entry.get("run_dir") != raw:
        raise ValueError("external run_dir is not the recorded source-suite case")
    return _case_path(prior, previous, number, planned, prior_entry, visited | {prior})


def _frozen(path: Path, cache: dict, filename: str = "snapshot.json") -> dict:
    receipt = read_json(path / filename)
    if receipt.get("format") != "openrc-godtest-source-v1":
        raise ValueError("missing or unsupported frozen-source receipt")
    for key, digest_key in (("files", "source_digest"), ("imports", "imported_digest")):
        values = receipt.get(key)
        if not isinstance(values, dict) or not values:
            raise ValueError(f"frozen-source receipt has no {key}")
        digest = hashlib.sha256(json.dumps(values, sort_keys=True).encode()).hexdigest()
        if receipt.get(digest_key) != digest:
            raise ValueError(f"frozen-source {key} receipt digest differs")
    root = receipt.get("root")
    signature = (root, receipt["source_digest"], receipt["imported_digest"])
    if signature not in cache:
        changed = check_frozen(receipt)
        cache[signature] = changed
    if cache[signature]:
        raise ValueError("frozen source or imports have changed: " + ", ".join(cache[signature][:5]))
    return {"source_digest": receipt["source_digest"], "imported_digest": receipt["imported_digest"]}


def _mac_launch(path: Path, execution: dict, cache: dict) -> dict:
    """Verify that the private Mac launch differs only by its owned project name."""
    canonical = read_json(path / "snapshot.json")
    launch = read_json(path / "launch-snapshot.json")
    isolation = execution.get("profile_isolation")
    if not isinstance(isolation, dict) or launch.get("profile_isolation") != isolation:
        raise ValueError("macOS launch snapshot and execution profile receipts differ")
    if execution.get("changed_launch_files") != []:
        raise ValueError("macOS launch-source post-run verification is missing or reports changed files")
    root = path / "mac-source"
    if (not isinstance(launch.get("root"), str) or Path(launch["root"]).resolve() != root.resolve()
            or root.is_symlink() or (hasattr(root, "is_junction") and root.is_junction())):
        raise ValueError("macOS launch snapshot root is not the run-owned launch copy")
    if (isolation.get("canonical_source_digest") != canonical.get("source_digest")
            or isolation.get("changed_settings") != ["application/config/name"]
            or isolation.get("player_profile_touched") is not False
            or Path(isolation.get("user_dir", "")).name != isolation.get("project_name")):
        raise ValueError("macOS profile receipt does not establish its isolated canonical source")
    files, launch_files = canonical.get("files", {}), launch.get("files", {})
    if not isinstance(files, dict) or not isinstance(launch_files, dict):
        raise ValueError("macOS launch-source file manifests are invalid")
    if ({k: v for k, v in files.items() if k != "app/project.godot"} !=
            {k: v for k, v in launch_files.items() if k != "app/project.godot"}
            or canonical.get("imports") != launch.get("imports")
            or isolation.get("original_project_sha256") != files.get("app/project.godot")
            or isolation.get("launch_project_sha256") != launch_files.get("app/project.godot")):
        raise ValueError("macOS launch copy differs from canonical source outside the project name")
    project_name = isolation.get("project_name")
    if not isinstance(project_name, str):
        raise ValueError("macOS launch project name is missing")
    original = (Path(canonical["root"]) / "app/project.godot").read_bytes()
    marker = b'config/name="OpenRC Simulator"'
    if original.count(marker) != 1:
        raise ValueError("macOS canonical project name is unavailable or ambiguous")
    expected_project = original.replace(marker, f'config/name="{project_name}"'.encode(), 1)
    if (root / "app/project.godot").read_bytes() != expected_project:
        raise ValueError("macOS launch project differs beyond its isolated name")
    return _frozen(path, cache, "launch-snapshot.json")


def _expected_phases(cycles: int) -> list[tuple[int, str]]:
    # The driver visits Home both before loading and after returning from flight.
    per_cycle = ("selection", "home", "loading", "recover", "runway_circuit", "pause",
                 "menu_settings", "menu_controls", "settings", "home")
    return [(0, "startup")] + [(cycle, phase) for cycle in range(cycles) for phase in per_cycle]


def _display_matches(value, manifest: dict) -> bool:
    """Require actual post-Home observations, not the early startup diagnostic."""
    return (isinstance(value, dict) and value.get("status") == "observed"
            and type(value.get("monotonic_usec")) is int and value["monotonic_usec"] >= 0
            and type(value.get("max_fps")) is int and value["max_fps"] == manifest["max_fps"]
            and value.get("window_mode") == manifest["window_mode"]
            and value.get("vsync_mode") == manifest["vsync_mode"]
            # Godot DisplayServer enums: windowed/fullscreen = 0/3 and
            # VSync disabled/enabled = 0/1. A string alone is not the observation.
            and type(value.get("window_mode_code")) is int
            and value["window_mode_code"] == {"windowed": 0, "borderless": 3}[manifest["window_mode"]]
            and type(value.get("vsync_mode_code")) is int
            and value["vsync_mode_code"] == {"disabled": 0, "enabled": 1}[manifest["vsync_mode"]]
            and value.get("window_size") == manifest["resolution"]
            and value.get("viewport_size") == manifest["resolution"])


def _phase_rows(phases: list[dict], targets: list[dict] | None = None) -> list[dict]:
    rows, occurrence = [], defaultdict(int)
    by_index = {target["phase_index"]: target for target in targets or []}
    for phase in phases:
        if not isinstance(phase, dict) or not phase.get("requested"):
            continue
        name, cycle = phase.get("name"), phase.get("cycle")
        occurrence[(cycle, name)] += 1
        pacing, frame, hitches = phase.get("pacing", {}), phase.get("frame_ms", {}), phase.get("hitches", {})
        slow = hitches.get("16.667", {})
        target = by_index.get(phase.get("index"), {})
        rows.append({"phase_id": phase.get("id"), "phase": name, "cycle": cycle,
                     "occurrence": occurrence[(cycle, name)], "status": phase.get("status"),
                     "frames": pacing.get("frames"), "wall_seconds": phase.get("wall_seconds"),
                     "fps_mean": pacing.get("fps_mean"), "fps_1pct_low": pacing.get("fps_1pct_low"),
                     "low_1pct_status": pacing.get("low_1pct_status", "unavailable"),
                     "fps_01pct_low": pacing.get("fps_01pct_low"),
                     "low_01pct_status": pacing.get("low_01pct_status", "unavailable"),
                     "p95_ms": frame.get("p95"), "p99_ms": frame.get("p99"), "worst_ms": frame.get("max"),
                     "slow_frame_percent": slow.get("over_budget_percent"),
                     "slow_wall_percent": slow.get("slow_time_percent"),
                     "over_50ms_frames": hitches.get("50", {}).get("frames"),
                     "over_100ms_frames": hitches.get("100", {}).get("frames"),
                     "stutter_frames": None, "stall_frames": None,
                     "simulation_wall_ratio": target.get("simulation_wall_ratio"),
                     "simulation_pace_target_met": target.get("simulation_pace_target_met"),
                     "local_simulation_pace_target_met": target.get("local_simulation_pace_target_met"),
                     "local_simulation_pace_status": target.get("local_simulation_pace_status", "not_applicable"),
                     "local_simulation_pace_target_reason": target.get("local_simulation_pace_target_reason", "not_applicable"),
                     "worst_local_simulation_wall_ratio": target.get("worst_local_simulation_wall_ratio"),
                     "fastest_local_simulation_wall_ratio": target.get("fastest_local_simulation_wall_ratio"),
                     "maximum_observed_simulation_lag_seconds": target.get("maximum_observed_simulation_lag_seconds"),
                     "screen_target_status": target.get("screen_target_status", "not_applicable")})
    return rows


def _href(suite: Path, target: Path) -> str:
    try:
        # relpath is intentionally allowed to contain '..' only after the
        # source-suite chain has established external-case provenance.
        return quote(os.path.relpath(target, suite).replace(os.sep, "/"), safe="/:")
    except ValueError:  # Windows paths on different drives
        return target.as_uri()


def _number(value) -> str:
    return f"{value:.2f}" if type(value) in (int, float) and math.isfinite(value) else "unavailable"


def _count(value) -> str:
    return str(value) if type(value) is int and value >= 0 else "unavailable"


def _html(result: dict, suite: Path) -> str:
    e = lambda value: html.escape(str(value), quote=True)
    body = ["<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width'>",
            "<title>GOD TEST performance tour</title><style>body{font:15px system-ui;margin:2em;max-width:100em;",
            "background:#10171d;color:#e6eef5}table{border-collapse:collapse;width:100%;font-size:.87em}",
            "td,th{padding:.45em;border-bottom:1px solid #43515d;text-align:left}a{color:#9ed7cb}",
            "code{overflow-wrap:anywhere}pre{white-space:pre-wrap;overflow-wrap:anywhere}summary{cursor:pointer}section{margin:2em 0}.scroll{overflow-x:auto}</style>",
            "<h1>GOD TEST · three-aircraft performance tour</h1>",
            f"<p>Data: {e(result['data'])} · Coverage: {e(result['coverage'])} · Performance: {e(result['performance'])}</p>",
            "<p>Instrumented screen only; hardware qualification, physical validation, statistical confidence and presentation timing are not established. Repeats are median/range, never a regression test. Startup/loading stay separate from flight. Sampled CPU and GPU observations are not proof of a bottleneck.</p>",
            "<h2>Issues and observations</h2><ul>"]
    body.extend("<li>" + e(issue) + "</li>" for issue in result["issues"])
    if not result["issues"]:
        body.append("<li>No evidence or coverage issues detected by this reducer.</li>")
    body.append("</ul>")
    for case in result["cases"]:
        body.append(f"<section><h2>{e(case.get('aircraft', 'unknown'))} · case {e(case['number'])}</h2>")
        body.append(f"<p>Data: {e(case.get('data', 'unavailable'))} · Coverage: {e(case.get('coverage', 'unavailable'))} · Rendered: {e(case.get('rendered', 'unavailable'))}</p>")
        links = case.get("links", {})
        for label, path in (("Case report", links.get("report")), ("Stutter report", links.get("watch")),
                            ("CPU resources", links.get("resources")), ("GPU observations", links.get("gpu"))):
            if path:
                body.append(f"<a href='{e(_href(suite, Path(path)))}'>{e(label)}</a> · ")
        watch = case.get("watch", {})
        body.append(f"<p>Watcher overall, after arming: relative stutter frames {_count(watch.get('relative_stutter_frames'))}; stall frames {_count(watch.get('stall_frames'))}; incidents {_count(watch.get('incidents'))}. These are not per-phase counts.</p>")
        resources, gpu = case.get("resources", {}), case.get("gpu", {})
        mib = lambda value: _number(value / 1048576) if type(value) in (int, float) else "unavailable"
        body.append(f"<p>CPU mean / peak: {_number(resources.get('cpu_percent_mean'))}% / {_number(resources.get('cpu_percent_peak'))}% (100% = one logical CPU). "
                    f"Process RSS peak / change: {mib(resources.get('rss_peak_bytes'))} / {mib(resources.get('rss_delta_bytes'))} MiB. "
                    f"Peak threads: {_count(resources.get('threads_peak'))}. GPU sampling: {e(gpu.get('status', 'unavailable'))}.</p>")
        devices = gpu.get("summary_by_device", {})
        if devices:
            body.append("<div class='scroll'><table><thead><tr><th>Observed GPU</th><th>Utilization mean / max %</th><th>Observed memory peak MiB</th><th>Temperature peak °C</th><th>Power peak W</th><th>Graphics clock mean MHz</th></tr></thead><tbody>")
            for key, device in devices.items():
                metrics = device.get("metrics", {})
                metric = lambda name, statistic: metrics.get(name, {}).get(statistic)
                label = device.get("identity", {}).get("name") or key
                body.append("<tr>" + "".join(f"<td>{e(value)}</td>" for value in (
                    label, _number(metric("gpu_utilization_pct", "mean")) + " / " + _number(metric("gpu_utilization_pct", "max")),
                    mib(metric("memory_used_bytes", "max")), _number(metric("temperature_c", "max")),
                    _number(metric("power_w", "max")), _number(metric("graphics_clock_mhz", "mean")))) + "</tr>")
            body.append("</tbody></table></div><p>GPU readings include other applications; renderer attribution is unverified. Apple memory is shared system memory. Unsupported sensors remain unavailable.</p>")
        body.append(f"<details><summary>Monitoring identities, coverage and capability details</summary><pre>{e(json.dumps({'CPU': resources, 'GPU': gpu}, ensure_ascii=False, indent=2))}</pre></details>")
        body.append("<div class='scroll'><table><thead><tr><th>Phase</th><th>Cycle</th><th>Status</th><th>Frames</th><th>Mean FPS</th><th>1% low FPS</th><th>0.1% low FPS</th><th>p95 ms</th><th>p99 ms</th><th>Worst ms</th><th>Slow frames %</th><th>Slow wall %</th><th>&gt;50 ms</th><th>&gt;100 ms</th></tr></thead><tbody>")
        for row in case.get("phases", []):
            body.append("<tr>" + "".join(f"<td>{e(v)}</td>" for v in (
                row["phase"], row["cycle"], row["status"], row["frames"] if row["frames"] is not None else "unavailable",
                _number(row["fps_mean"]), _number(row["fps_1pct_low"]) + " (" + str(row["low_1pct_status"]) + ")",
                _number(row["fps_01pct_low"]) + " (" + str(row["low_01pct_status"]) + ")",
                _number(row["p95_ms"]), _number(row["p99_ms"]), _number(row["worst_ms"]),
                _number(row["slow_frame_percent"]), _number(row["slow_wall_percent"]),
                _count(row["over_50ms_frames"]), _count(row["over_100ms_frames"]))) + "</tr>")
        body.append("</tbody></table></div>")
        active_rows = [row for row in case.get("phases", []) if row["screen_target_status"] != "not_applicable"]
        if active_rows:
            body.append("<h3>Simulation pace and screen targets</h3><div class='scroll'><table><thead><tr><th>Phase</th>"
                        "<th>Screen targets</th><th>Total sim / wall</th><th>Worst 1 s sim / wall</th>"
                        "<th>Fastest 1 s sim / wall</th><th>Max observed lag s</th><th>Local pace evidence</th></tr></thead><tbody>")
            for row in active_rows:
                body.append("<tr>" + "".join(f"<td>{e(value)}</td>" for value in (
                    row["phase"], row["screen_target_status"], _number(row["simulation_wall_ratio"]),
                    _number(row["worst_local_simulation_wall_ratio"]), _number(row["fastest_local_simulation_wall_ratio"]),
                    _number(row["maximum_observed_simulation_lag_seconds"]), row["local_simulation_pace_status"])) + "</tr>")
            body.append("</tbody></table></div><p>Screen targets: p95 ≤18 ms, p99 ≤25 ms and sim / wall 0.99–1.01. "
                        "One-second windows keep slowdowns visible when the phase average recovers. Unsupported local "
                        "coverage or an unscored partial tail cannot pass; short maneuvers remain exploratory. This table is not hardware qualification.</p>")
        body.append("</section>")
    if result["repeat_summaries"]:
        body.append("<h2>Repeat summaries</h2><p>Each value is the median [minimum, maximum] across independent runs of the same aircraft, cycle and phase. Percentiles are not pooled.</p><div class='scroll'><table><thead><tr><th>Aircraft</th><th>Cycle / phase</th><th>N</th><th>Mean FPS</th><th>1% low FPS</th><th>0.1% low FPS</th><th>p95 ms</th><th>p99 ms</th><th>Worst ms</th></tr></thead><tbody>")
        def aggregate(item):
            return "unavailable" if item is None else f"{_number(item['median'])} [{_number(item['min'])}, {_number(item['max'])}]"
        for row in result["repeat_summaries"]:
            body.append("<tr>" + "".join(f"<td>{e(v)}</td>" for v in (row["aircraft"], f"{row['cycle']} / {row['phase']} #{row['occurrence']}", row["runs"], *(aggregate(row["metrics"].get(k)) for k in ("fps_mean", "fps_1pct_low", "fps_01pct_low", "p95_ms", "p99_ms", "worst_ms")))) + "</tr>")
        body.append("</tbody></table></div>")
    body.append("<p>Slow shares use intervals strictly above 16.667 ms, assigned to the phase at interval end. Short-tail FPS estimates are labeled; the stutter watcher starts after initial Home. See each original report for detector definitions, CPU/GPU availability and scope.</p></html>")
    return "".join(body)


def report_tour(directory: Path, *, write: bool = True) -> dict:
    directory = Path(directory).resolve()
    index = read_json(directory / "suite.json")
    problems, coverage_problems, observations = [], [], []
    if index.get("format") != "openrc-godtest-suite-v1" or index.get("suite") != TOUR:
        raise ValueError("report_tour requires a performance-tour-v1 suite")
    planned = _planned(index, problems)
    entries = index.get("cases")
    if not isinstance(entries, list):
        problems.append("suite cases must be an array")
        entries = []
    if len(entries) != len(planned) or index.get("complete") is not True:
        coverage_problems.append(f"suite incomplete: recorded {len(entries)} of {len(planned)} planned cases; complete={index.get('complete')!r}")
    if len(entries) > len(planned):
        problems.append("suite contains unplanned cases")
    if not planned:
        coverage_problems.append("no valid planned tour roster")
    cases, paths, frozen_cache = [], set(), {}
    global_identities, group_identities = [], defaultdict(list)
    for number, entry in enumerate(entries):
        case = {"number": number + 1, "recorded": entry, "phases": []}
        cases.append(case)
        prefix = f"case {number + 1}"
        try:
            if not isinstance(entry, dict):
                raise ValueError("suite case is not an object")
            path = _case_path(directory, index, number, planned, entry, {directory})
            if path in paths:
                raise ValueError("duplicate run_dir")
            paths.add(path)
            requested = read_json(path / "manifest.requested.json", 65536)
            resolved = read_json(path / "manifest.resolved.json", 65536)
            catalog.validate(requested)
            catalog.validate(resolved, resolved=True)
            expected = planned[number]
            isolation_fields = {"isolated_user_dir", "isolated_project_name"}
            if requested != expected or {k: v for k, v in resolved.items() if k != "output_dir" and k not in isolation_fields} != expected or Path(resolved["output_dir"]).resolve() != path:
                raise ValueError("planned, requested and resolved manifests or run directory differ")
            case.update(run_dir=str(path), aircraft=expected["aircraft"], scenario=expected["id"],
                        links={name: str(target) for name, target in (("report", path / "report.html"), ("watch", path / "frame-watch/report.html"), ("resources", path / "resources.json"), ("gpu", path / "gpu.json")) if target.is_file()})
            reduced = report(path, write=False)
            case["summary_performance_stale"] = False
            for key in ("scenario", "aircraft", "execution", "data", "coverage", "flight", "performance", "issues"):
                if key not in entry or entry[key] != reduced.get(key):
                    target = observations if key == "performance" else problems
                    target.append(f"{prefix}: recorded {key} is missing or stale compared with child evidence")
                    if key == "performance":
                        case["summary_performance_stale"] = True
            case.update({key: reduced.get(key) for key in ("execution", "data", "coverage", "performance", "rendered", "requested_headless", "rendering", "issues", "resources", "gpu", "monitoring")})
            case["reducer_sha256"] = reduced.get("reducer_sha256")
            case["resources"] = case["resources"] or {"status": "unavailable"}
            case["gpu"] = case["gpu"] or {"status": "unavailable"}
            case["monitoring"] = case["monitoring"] or {"required": True, "complete": False, "issues": ["monitoring status unavailable"]}
            case["phases"] = _phase_rows(reduced.get("phases", []), reduced.get("targets", []))
            if reduced.get("data") != "valid":
                problems.append(f"{prefix}: child data is ineligible: " + "; ".join(str(x) for x in reduced.get("issues", [])))
            if reduced.get("coverage") != "complete":
                coverage_problems.append(f"{prefix}: child coverage is {reduced.get('coverage', 'unavailable')}")
            if [(p["cycle"], p["phase"]) for p in case["phases"]] != _expected_phases(expected["cycles"]):
                coverage_problems.append(f"{prefix}: observed requested phase sequence or cycles differ from the tour")
            watch = reduced.get("frame_watch", {})
            overall = watch.get("overall", {})
            case["watch"] = {"status": watch.get("status", "unavailable"),
                             "relative_stutter_frames": overall.get("relative_stutter_frames"),
                             "stall_frames": overall.get("stall_frames"),
                             "incidents": len(watch.get("incidents", [])) if watch.get("status") == "complete" else None,
                             "scope": watch.get("scope")}
            if watch.get("status") != "complete":
                problems.append(f"{prefix}: required frame watch is incomplete")
            runtime = read_json(path / "runtime.json")
            execution = read_json(path / "execution.json")
            if execution.get("source_changed") is not False or execution.get("changed_frozen_files") != []:
                raise ValueError("frozen-source post-run verification is missing or reports changed files")
            if execution.get("engine_command_verified") is not True or execution.get("engine_files_changed") != []:
                raise ValueError("launched engine and post-run executable identity were not verified")
            host = execution.get("host_identity", {})
            if reduced.get("rendered") and (not isinstance(host, dict) or host.get("format") != "openrc-godtest-host-v1"
                    or any(not isinstance(host.get(key), str) or len(host[key]) != 64
                           or any(char not in "0123456789abcdef" for char in host[key]) for key in ("host_sha256", "boot_sha256"))):
                raise ValueError("rendered campaign host and boot identity are missing or invalid")
            identity = runtime.get("identity", {})
            diag = identity.get("diagnostics", {})
            selection = identity.get("selection", {})
            if not isinstance(identity, dict) or not isinstance(diag, dict) or not isinstance(selection, dict):
                raise ValueError("invalid runtime identity")
            if isolation_fields.intersection(resolved):
                isolation = execution.get("profile_isolation", {})
                if (not isolation_fields.issubset(resolved) or not isinstance(isolation, dict)
                        or isolation.get("format") != "openrc-godtest-macos-profile-v1"
                        or resolved["isolated_user_dir"] != isolation.get("user_dir")
                        or resolved["isolated_project_name"] != isolation.get("project_name")
                        or identity.get("user_dir") != isolation.get("user_dir")):
                    raise ValueError("macOS isolated launch identity differs from its resolved manifest")
            if selection.get("aircraft") != expected["aircraft"]:
                problems.append(f"{prefix}: actual aircraft selection differs from the planned aircraft")
            actual_flight = identity.get("flight_aircraft")
            if actual_flight != {key: expected["aircraft"] for key in ("requested", "flight", "model")}:
                problems.append(f"{prefix}: loaded flight/model aircraft identity is missing or differs from the planned aircraft")
            if identity.get("instrumentation") != "frames_diagnostics_pilot_v1":
                problems.append(f"{prefix}: frame diagnostics instrumentation identity is missing or unsupported")
            effective = identity.get("effective_display")
            if not isinstance(effective, dict):
                raise ValueError("effective display configuration is unavailable")
            for key in ("scene_detail", "window_mode", "max_fps", "vsync_mode"):
                if effective.get(key) != expected[key]:
                    problems.append(f"{prefix}: effective {key} differs from the requested configuration")
            if reduced.get("rendered") and identity.get("backend", {}).get("backend") != "native":
                problems.append(f"{prefix}: actual native physics was not established")
            case["display"] = {"home": identity.get("runtime_display"), "final": identity.get("final_display")}
            if reduced.get("rendered"):
                for name, value in case["display"].items():
                    if not _display_matches(value, expected):
                        problems.append(f"{prefix}: actual {name} display state is unavailable or differs from the requested mode, VSync, cap or size")
                for phase in reduced.get("phases", []):
                    if (isinstance(phase, dict) and phase.get("requested") and phase.get("status") == "complete"
                            and not _display_matches(phase.get("runtime_display"), expected)):
                        problems.append(f"{prefix}: actual display state at {phase.get('id')} is unavailable or differs from the requested mode, VSync, cap or size")
            case["hardware"] = {key: diag.get(key) for key in HARDWARE}
            case["identity"] = {"engine": identity.get("engine"), "backend": identity.get("backend"),
                                "actual_resolution": identity.get("actual_resolution"), "viewport_size": identity.get("viewport_size"),
                                "frozen": _frozen(path, frozen_cache), "engine_files": execution.get("engine_files"),
                                "flight_aircraft": actual_flight}
            if isolation_fields.intersection(resolved):
                case["identity"]["launch_frozen"] = _mac_launch(path, execution, frozen_cache)
            engine = execution.get("engine_files")
            if not isinstance(engine, dict) or not engine or any(not isinstance(v, str) or len(v) != 64 for v in engine.values()):
                raise ValueError("engine executable identity is missing or invalid")
            if not identity.get("engine") or not identity.get("backend") or not identity.get("actual_resolution") or not identity.get("viewport_size"):
                raise ValueError("engine, backend or resolution identity is unavailable")
            if reduced.get("rendered") and any(diag.get(key) in (None, "", {}, []) for key in HARDWARE):
                raise ValueError("hardware or renderer identity is incomplete")
            devices = case["gpu"].get("summary_by_device", {})
            if not isinstance(devices, dict):
                devices = {}
            gpu_devices = {key: {"identity": value.get("identity"), "backend": value.get("backend")}
                           for key, value in devices.items() if isinstance(value, dict)}
            # Aircraft and the Mac copy's unique project name legitimately differ
            # between cases; canonical bytes and actual backend must still match.
            comparison_identity = {k: v for k, v in case["identity"].items() if k not in ("flight_aircraft", "launch_frozen")}
            base = {**comparison_identity, "hardware": case["hardware"], "gpu_devices": gpu_devices,
                    "resource_sampling": execution.get("resource_sampling"), "gpu_sampling": execution.get("gpu_sampling"),
                    "rendering_requested": execution.get("rendering_requested"), "effective_display": effective,
                    "watch_sources": execution.get("frame_watch", {}).get("source_sha256"),
                    "resource_source": execution.get("resource_sampler_source_sha256"),
                    "host_identity": execution.get("host_identity"),
                    "gpu_source": case["gpu"].get("source_sha256"),
                    "orchestrator_sources": {key: execution.get("orchestrator_sources", {}).get(key)
                                             for key in ("runner.py", "frame_monitor.py", "hardware.py")}}
            global_identities.append((number + 1, base))
            group_identities[expected["aircraft"]].append((number + 1, {**base, "selection": selection,
                **{k: identity.get(k) for k in ("field", "pilot", "camera", "scenery_sha256", "effective_weather", "effective_lighting", "effective_sky")}}))
            if reduced.get("rendered") and case["monitoring"].get("complete") is not True:
                observations.append(f"{prefix}: CPU/GPU monitoring is incomplete or unavailable; performance is not qualified")
            for target in reduced.get("targets", []):
                if target.get("p95_within_18ms") is False or target.get("p99_within_25ms") is False:
                    observations.append(f"{prefix} {target.get('phase_id')}: pacing screen target missed; inspect the retained CPU/GPU and stutter evidence as hypotheses, not a diagnosed cause")
                if target.get("simulation_pace_target_met") is False or target.get("local_simulation_pace_target_met") is False:
                    observations.append(f"{prefix} {target.get('phase_id')}: simulation pace screen target missed; phase averages can hide slowdown followed by catch-up; inspect local windows and observed lag")
            for loading in reduced.get("loading", []):
                if loading.get("screen_target_met") is False:
                    observations.append(f"{prefix} {loading.get('phase_id')}: loading-time screen target missed; investigate the recorded transition separately")
        except (OSError, ValueError, TypeError, KeyError, AttributeError, IndexError) as error:
            case["data"] = "ineligible"
            case["coverage"] = "partial"
            case["error"] = str(error)
            problems.append(f"{prefix}: {error}")
            coverage_problems.append(f"{prefix}: case could not be fully verified")
    consistent = True
    if global_identities and any(value != global_identities[0][1] for _, value in global_identities[1:]):
        consistent = False
        observations.append("source, engine, backend, resolution, hardware or instrumentation differs across cases; no cross-case performance screen is eligible")
    group_ok = {}
    for aircraft, rows in group_identities.items():
        group_ok[aircraft] = all(value == rows[0][1] for _, value in rows)
        if not group_ok[aircraft]:
            consistent = False
            observations.append(f"{aircraft}: repeat configuration differs; no repeat aggregation is available")
    data = "ineligible" if problems else "valid"
    coverage = "partial" if coverage_problems or problems else "complete"
    performance = "screen_only" if (data == "valid" and coverage == "complete" and consistent and cases and
        all(c.get("rendered") is True and c.get("monitoring", {}).get("complete") is True
            and not c.get("summary_performance_stale") for c in cases)) else "not_qualified"
    summaries = []
    repeats = len(planned) // 3 if planned else 0
    if consistent and repeats > 1:
        for aircraft in catalog.TOUR_AIRCRAFT:
            selected = [case for case in cases if case.get("aircraft") == aircraft]
            if len(selected) != repeats or not group_ok.get(aircraft) or any(c.get("data") != "valid" or c.get("coverage") != "complete" for c in selected):
                continue
            layouts = [[(p["cycle"], p["phase"], p["occurrence"]) for p in c["phases"]] for c in selected]
            if any(layout != layouts[0] for layout in layouts[1:]):
                continue
            for position, (cycle, phase, occurrence) in enumerate(layouts[0]):
                values = {}
                for metric in METRICS:
                    samples = [c["phases"][position].get(metric) for c in selected]
                    if all(type(v) in (int, float) and math.isfinite(v) for v in samples):
                        values[metric] = {"median": statistics.median(samples), "min": min(samples), "max": max(samples)}
                    else:
                        values[metric] = None
                summaries.append({"aircraft": aircraft, "cycle": cycle, "phase": phase, "occurrence": occurrence,
                                  "runs": repeats, "metrics": values,
                                  "low_1pct_statuses": [c["phases"][position]["low_1pct_status"] for c in selected],
                                  "low_01pct_statuses": [c["phases"][position]["low_01pct_status"] for c in selected]})
    result = {"format": FORMAT, "reducer_sha256": REDUCER_SHA256, "reducer_sources": REDUCER_SOURCES, "run_dir": str(directory), "suite": TOUR, "data": data,
              "coverage": coverage, "performance": performance, "hardware_qualified": False,
              "repeats": repeats, "cases": cases, "repeat_summaries": summaries,
              "issues": problems + coverage_problems + observations,
              "method": {"repeat_summary": "median and range of per-run phase metrics; no pooling or regression test",
                         "slow_threshold_ms": 16.667, "phase_counts": "watcher stutter/stall counts are overall, not per phase",
                         "scope": "callback intervals, not presentation timing; startup and loading are separate phases"}}
    if write:
        write_json(directory / "report.json", result)
        (directory / "report.html").write_text(_html(result, directory), encoding="utf-8")
    return result
