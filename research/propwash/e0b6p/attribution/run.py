#!/usr/bin/env python3
"""Attribute E0b6p native whole-tick cost in a disposable Godot app copy."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import sys
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
APP_BENCH = ROOT / "research/propwash/e0b6p/bench_swirl.gd"
PROFILE_SCRIPT = HERE / "profile.gd"
PROFILER_SCRIPT = HERE / "profiler.gd"
ADAPTER_SCRIPT = ROOT / "research/propwash/e0b6p/native/adapter.gd"
ERROR_RE = re.compile(r"(?m)^(?:SCRIPT ERROR:|ERROR:|Parse Error:)")
REGIMES = ("forward", "stall", "static", "spin", "reverse_fade", "reverse_off")
COMPONENTS = (
    "air_dynamics",
    "air_pre_step",
    "air_transport_derivative",
    "aero_loads",
    "propulsion_loads",
    "slipstream_loads",
    "ground_loads",
    "pre_step_inclusive",
    "step_total",
)


def _resolve(value: str) -> str:
    candidate = Path(value).expanduser()
    if candidate.exists():
        return str(candidate.resolve())
    found = shutil.which(value)
    if found is None:
        raise RuntimeError(f"Executable does not exist or is not on PATH: {value}")
    return found


def _copy_app(source: Path, destination: Path) -> None:
    if not source.is_dir():
        raise RuntimeError(f"--project must name a Godot app directory: {source}")
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".godot", "captures", ".git", "__pycache__"))


def _install_native_adapter(project: Path, library: Path) -> Path:
    if not library.is_file():
        raise RuntimeError(f"Native library does not exist: {library}")
    if sys.platform.startswith("linux"):
        platform_key = "linux"
    elif sys.platform == "win32":
        platform_key = "windows"
    elif sys.platform == "darwin":
        platform_key = "macos"
    else:
        raise RuntimeError(f"Unsupported host platform: {sys.platform}")
    probe = project / "tests/e0b6p_native"
    probe.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ADAPTER_SCRIPT, probe / "adapter.gd")
    shutil.copy2(library, probe / library.name)
    (probe / "smooth_wake.gdextension").write_text(
        "[configuration]\n"
        'entry_symbol = "openrc_smooth_wake_library_init"\n'
        'compatibility_minimum = "4.7"\n'
        "reloadable = false\n\n"
        "[libraries]\n"
        f'{platform_key} = "res://tests/e0b6p_native/{library.name}"\n',
        encoding="utf-8",
    )
    _replace_once(
        project / "physics/dynamics.gd",
        'const Slipstream := preload("res://physics/slipstream.gd")',
        'const Slipstream := preload("res://tests/e0b6p_native/adapter.gd")',
    )
    return probe


def _replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    if source.count(old) != 1:
        raise RuntimeError(f"Expected one instrumentation anchor in {path}: {old!r}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def _instrument_project(project: Path) -> Path:
    profiler = project / "tests/e0b6p_attribution/profiler.gd"
    profiler.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PROFILER_SCRIPT, profiler)
    profile = project / "tests/e0b6p_attribution/profile.gd"
    shutil.copy2(PROFILE_SCRIPT, profile)

    dynamics = project / "physics/dynamics.gd"
    source = dynamics.read_text(encoding="utf-8")
    source = _replace_in_text(
        source,
        'const Slipstream := preload("res://tests/e0b6p_native/adapter.gd")',
        'const Slipstream := preload("res://tests/e0b6p_native/adapter.gd")\n'
        'const E0b6pProfiler := preload("res://tests/e0b6p_attribution/profiler.gd")',
        dynamics,
    )
    source = _replace_in_text(
        source,
        "\tvar air := Air.compute(state, wind_ned, rho)",
        "\tvar _e0b6_started: int = 0\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\t_e0b6_started = Time.get_ticks_usec()\n"
        "\tvar air := Air.compute(state, wind_ned, rho)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"air_dynamics\", Time.get_ticks_usec() - _e0b6_started)",
        dynamics,
    )
    for old, name in (
        ("\tvar aero_loads := Aero.loads(state, air, d, model, rho, downwash_cl)", "aero_loads"),
        ("\tvar propulsion_loads := Propulsion.loads(air.v_air, rpm, model.propulsion, rho)", "propulsion_loads"),
    ):
        replacement = (
            "\tif E0b6pProfiler.enabled:\n\t\t_e0b6_started = Time.get_ticks_usec()\n"
            + old
            + f"\n\tif E0b6pProfiler.enabled:\n\t\tE0b6pProfiler.add(\"{name}\", Time.get_ticks_usec() - _e0b6_started)"
        )
        source = _replace_in_text(source, old, replacement, dynamics)
    source = _replace_in_text(
        source,
        "\t\tvar wash := Slipstream.loads(state, air, d, model, rpm, rho, downwash_cl, transported_dv)",
        "\t\tif E0b6pProfiler.enabled:\n\t\t\t_e0b6_started = Time.get_ticks_usec()\n"
        "\t\tvar wash := Slipstream.loads(state, air, d, model, rpm, rho, downwash_cl, transported_dv)\n"
        "\t\tif E0b6pProfiler.enabled:\n"
        "\t\t\tE0b6pProfiler.add(\"slipstream_loads\", Time.get_ticks_usec() - _e0b6_started)",
        dynamics,
    )
    dynamics.write_text(source, encoding="utf-8")

    flight = project / "sim/flight_session.gd"
    source = flight.read_text(encoding="utf-8")
    source = _replace_in_text(
        source,
        'const GroundSurfaces := preload("res://physics/ground_surfaces.gd")',
        'const GroundSurfaces := preload("res://physics/ground_surfaces.gd")\n'
        'const E0b6pProfiler := preload("res://tests/e0b6p_attribution/profiler.gd")',
        flight,
    )
    source = _replace_in_text(
        source,
        "\tvar ground := Ground.loads(s, aircraft.model.landing_gear, a[AUX_SERVO + 2], ground_surfaces,\n"
        "\t\ta.slice(AUX_ANCHORS) if a.size() > AUX_ANCHORS else PackedFloat64Array())",
        "\tvar _e0b6_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar ground := Ground.loads(s, aircraft.model.landing_gear, a[AUX_SERVO + 2], ground_surfaces,\n"
        "\t\ta.slice(AUX_ANCHORS) if a.size() > AUX_ANCHORS else PackedFloat64Array())\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"ground_loads\", Time.get_ticks_usec() - _e0b6_started)",
        flight,
    )
    source = _replace_in_text(
        source,
        "\t\tvar speed: float = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL).V",
        "\t\tvar _e0b6_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\t\tvar speed: float = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL).V\n"
        "\t\tif E0b6pProfiler.enabled:\n"
        "\t\t\tE0b6pProfiler.add(\"air_pre_step\", Time.get_ticks_usec() - _e0b6_started)",
        flight,
    )
    source = _replace_in_text(
        source,
        "\tvar air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)\n"
        "\treturn WashTransport.derivative(air.v_air, sim.aux[AUX_RPM], aircraft.model.propulsion, Air.RHO_SEA_LEVEL, lagged)",
        "\tvar _e0b6_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"air_transport_derivative\", Time.get_ticks_usec() - _e0b6_started)\n"
        "\treturn WashTransport.derivative(air.v_air, sim.aux[AUX_RPM], aircraft.model.propulsion, Air.RHO_SEA_LEVEL, lagged)",
        flight,
    )
    source = _replace_in_text(
        source,
        "\tvar air := Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)\n"
        "\treturn Aero.wing_lift_coefficient(s, air, _deflections(aux), aircraft.model)",
        "\tvar _e0b6_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar air := Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"air_pre_step\", Time.get_ticks_usec() - _e0b6_started)\n"
        "\treturn Aero.wing_lift_coefficient(s, air, _deflections(aux), aircraft.model)",
        flight,
    )
    flight.write_text(source, encoding="utf-8")

    simulation = project / "sim/simulation.gd"
    source = simulation.read_text(encoding="utf-8")
    source = _replace_in_text(
        source,
        'const RK := preload("res://physics/integrator.gd")',
        'const RK := preload("res://physics/integrator.gd")\n'
        'const E0b6pProfiler := preload("res://tests/e0b6p_attribution/profiler.gd")',
        simulation,
    )
    source = _replace_in_text(
        source,
        "\tvar old_aux := aux.duplicate()\n\tvar next_aux: Variant = pre_step.call(old_aux, inputs, dt())",
        "\tvar old_aux := aux.duplicate()\n"
        "\tvar _e0b6_pre_step_started: int = Time.get_ticks_usec() if E0b6pProfiler.enabled else 0\n"
        "\tvar next_aux: Variant = pre_step.call(old_aux, inputs, dt())\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"pre_step_inclusive\", Time.get_ticks_usec() - _e0b6_pre_step_started)",
        simulation,
    )
    source = _replace_in_text(
        source,
        "\tstepped.emit(tick, time(), state, last_loads, inputs, aux)\n\n\nfunc _physics_process",
        "\tstepped.emit(tick, time(), state, last_loads, inputs, aux)\n"
        "\tif E0b6pProfiler.enabled:\n"
        "\t\tE0b6pProfiler.add(\"step_total\", Time.get_ticks_usec() - started)\n\n\nfunc _physics_process",
        simulation,
    )
    simulation.write_text(source, encoding="utf-8")
    return profile


def _replace_in_text(source: str, old: str, new: str, path: Path) -> str:
    if source.count(old) != 1:
        raise RuntimeError(f"Expected one instrumentation anchor in {path}: {old!r}")
    return source.replace(old, new, 1)


def _instrument_baseline_bench(project: Path, probe: Path) -> Path:
    source = APP_BENCH.read_text(encoding="utf-8")
    source = _replace_in_text(
        source,
        "const TICKS: int = 24\n",
        'const TICKS: int = 24\nconst NativeAdapter = preload("res://tests/e0b6p_native/adapter.gd")\n',
        APP_BENCH,
    )
    source = _replace_in_text(source, "func _initialize() -> void:\n\tvar rows: Array = []",
                              "func _initialize() -> void:\n\tNativeAdapter.reset_route_counts()\n\tvar rows: Array = []", APP_BENCH)
    end = '\t\tcpu = OS.get_processor_name(), godot = Engine.get_version_info().string, rows = rows}, "\\t", true, true)+"\\n")'
    source = _replace_in_text(
        source,
        end,
        '\t\tcpu = OS.get_processor_name(), godot = Engine.get_version_info().string, rows = rows,\n'
        '\t\tnative_route_counts = NativeAdapter.route_counts}, "\\t", true, true)+"\\n")',
        APP_BENCH,
    )
    destination = probe / "bench_swirl.gd"
    destination.write_text(source, encoding="utf-8")
    return destination


def _run_godot(godot: str, project: Path, script: Path, report: Path, timeout: int) -> str:
    command = [godot, "--headless", "--path", str(project), "--script", str(script), "--", str(report)]
    result = subprocess.run(command, text=True, capture_output=True, timeout=timeout, check=False)
    combined = result.stdout + result.stderr
    report.with_suffix(".log").write_text(combined, encoding="utf-8")
    if result.returncode != 0 or ERROR_RE.search(combined):
        raise RuntimeError(f"Godot failed ({result.returncode}): {' '.join(command)}\n{combined}")
    if not report.is_file():
        raise RuntimeError(f"Godot exited without writing report {report}\n{combined}")
    return combined


def _check_only(godot: str, project: Path, script: Path, log_path: Path) -> None:
    command = [godot, "--headless", "--path", str(project), "--check-only", "--script", str(script)]
    result = subprocess.run(command, text=True, capture_output=True, timeout=120, check=False)
    combined = result.stdout + result.stderr
    log_path.write_text(combined, encoding="utf-8")
    if result.returncode != 0 or ERROR_RE.search(combined):
        raise RuntimeError(f"Godot check-only failed ({result.returncode}): {' '.join(command)}\n{combined}")


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected a JSON object: {path}")
    return value


def _number(value: Any, where: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(float(value)):
        raise RuntimeError(f"Expected a finite number at {where}: {value!r}")
    return float(value)


def _validate_routes(report: dict[str, Any], label: str) -> dict[str, int]:
    routes = report.get("native_route_counts")
    if not isinstance(routes, dict):
        raise RuntimeError(f"{label}: no native route counters")
    normalized = {key: int(routes.get(key, -1)) for key in ("native", "kernel_calls", "legacy", "refused")}
    if normalized["native"] <= 0 or normalized["kernel_calls"] <= 0 or normalized["legacy"] != 0 or normalized["refused"] != 0:
        raise RuntimeError(f"{label}: unexpected native routes: {normalized}")
    return normalized


def _validate_profile(profile: dict[str, Any]) -> None:
    if profile.get("format") != "openrc-e0b6p-tick-attribution v1" or len(profile.get("rows", [])) != 12:
        raise RuntimeError("Malformed 12-regime instrumented attribution report")
    expected = [(regime, swirl) for regime in REGIMES for swirl in (0.0, 0.4)]
    actual = [(str(row.get("regime")), float(row.get("swirl_factor", -1.0))) for row in profile["rows"]]
    if actual != expected:
        raise RuntimeError(f"Unexpected instrumented regime roster: {actual}")
    timing_ticks = int(profile.get("ticks_per_timing_batch", 0))
    trajectory_ticks = int(profile.get("trajectory_ticks", 0))
    if timing_ticks <= 0 or trajectory_ticks != 240:
        raise RuntimeError("Unexpected timing-batch or trajectory length")
    for row in profile["rows"]:
        if len(row.get("disabled_samples_us_per_tick", [])) != 5 or len(row.get("enabled_samples", [])) != 5:
            raise RuntimeError(f"Expected five measured batches in {row.get('regime')}")
        for sample in row["enabled_samples"]:
            calls = sample.get("profile", {}).get("calls", {})
            counts = {name: int(calls.get(name, 0)) for name in COMPONENTS}
            expected_counts = {
                "air_dynamics": 4 * timing_ticks,
                "air_pre_step": 2 * timing_ticks,
                "air_transport_derivative": 0,
                "aero_loads": 4 * timing_ticks,
                "propulsion_loads": 4 * timing_ticks,
                "slipstream_loads": 4 * timing_ticks,
                "ground_loads": 4 * timing_ticks,
                "pre_step_inclusive": timing_ticks,
                "step_total": timing_ticks,
            }
            if counts != expected_counts:
                raise RuntimeError(f"Unexpected call counts in {row.get('regime')}: {counts}")
        trajectory_calls = row.get("trajectory_profile", {}).get("calls", {})
        expected_trajectory_counts = {
            "air_dynamics": 4 * 240,
            "air_pre_step": 2 * 240,
            "air_transport_derivative": 0,
            "aero_loads": 4 * 240,
            "propulsion_loads": 4 * 240,
            "slipstream_loads": 4 * 240,
            "ground_loads": 4 * 240,
            "pre_step_inclusive": 240,
            "step_total": 240,
        }
        trajectory_counts = {name: int(trajectory_calls.get(name, 0)) for name in COMPONENTS}
        if trajectory_counts != expected_trajectory_counts:
            raise RuntimeError(f"Trajectory instrumentation missed calls in {row.get('regime')}: {trajectory_counts}")


def _summarize_rows(baseline: dict[str, Any], instrumented: dict[str, Any]) -> list[dict[str, Any]]:
    baseline_rows = baseline.get("rows", [])
    instrumented_rows = instrumented.get("rows", [])
    if len(baseline_rows) != 12:
        raise RuntimeError("Baseline did not report all 12 regimes")
    summary: list[dict[str, Any]] = []
    ticks = int(instrumented["ticks_per_timing_batch"])
    bucket_names = (
        "Air.compute",
        "Aero.loads",
        "Propulsion.loads",
        "Slipstream.loads",
        "Ground.loads",
        "Flight._pre_step (exclusive)",
        "rest sim.step",
    )
    for base, prof in zip(baseline_rows, instrumented_rows, strict=True):
        if (base.get("regime"), float(base.get("swirl_factor", -1.0))) != (
            prof.get("regime"), float(prof.get("swirl_factor", -1.0))
        ):
            raise RuntimeError("Baseline and instrumented row order differs")
        baseline_median = statistics.median(_number(x, "baseline batch") for x in base.get("batches_us", []))
        disabled_median = statistics.median(_number(x, "instrumentation-off batch") for x in prof["disabled_samples_us_per_tick"])
        enabled_samples = prof["enabled_samples"]
        enabled_median = statistics.median(_number(x["wall_us_per_tick"], "instrumented batch") for x in enabled_samples)
        profile_off_delta = disabled_median - baseline_median
        enabled_by_pair = {int(sample["pair"]): _number(sample["wall_us_per_tick"], "enabled paired batch")
                           for sample in enabled_samples}
        disabled_by_pair = {index: _number(value, "disabled paired batch")
                            for index, value in enumerate(prof["disabled_samples_us_per_tick"])}
        paired_observer_deltas = [enabled_by_pair[index] - disabled_by_pair[index]
                                  for index in sorted(enabled_by_pair)]
        observer_overhead = statistics.median(paired_observer_deltas)
        sample_buckets: list[dict[str, float]] = []
        for sample in enabled_samples:
            elapsed = sample["profile"]["elapsed_usec"]
            per_tick = {name: _number(elapsed.get(name, 0), f"{name} timer") / float(ticks) for name in COMPONENTS}
            air_pre = per_tick["air_pre_step"]
            step = per_tick["step_total"]
            pre_step = per_tick["pre_step_inclusive"]
            exclusive = {
                "Air.compute": per_tick["air_dynamics"] + air_pre + per_tick["air_transport_derivative"],
                "Aero.loads": per_tick["aero_loads"],
                "Propulsion.loads": per_tick["propulsion_loads"],
                "Slipstream.loads": per_tick["slipstream_loads"],
                "Ground.loads": per_tick["ground_loads"],
                "Flight._pre_step (exclusive)": pre_step - air_pre,
            }
            exclusive["rest sim.step"] = step - pre_step - per_tick["air_dynamics"] \
                - per_tick["air_transport_derivative"] - per_tick["aero_loads"] \
                - per_tick["propulsion_loads"] - per_tick["slipstream_loads"] - per_tick["ground_loads"]
            total_buckets = sum(exclusive.values())
            if min(exclusive.values()) < -1.0 or abs(total_buckets - step) > 1.0:
                raise RuntimeError(
                    f"Exclusive accounting failed for {prof['regime']} swirl={prof['swirl_factor']}: "
                    f"buckets={exclusive}, step={step}"
                )
            sample_buckets.append(exclusive)
        means = {name: statistics.mean(sample[name] for sample in sample_buckets) for name in bucket_names}
        mean_step = statistics.mean(
            _number(s["profile"]["elapsed_usec"]["step_total"], "step timer") / float(ticks)
            for s in enabled_samples
        )
        if abs(sum(means.values()) - mean_step) > 1e-9:
            raise RuntimeError(f"Mean exclusive buckets do not sum to step for {prof['regime']}")
        summary.append({
            "regime": prof["regime"],
            "swirl_factor": prof["swirl_factor"],
            "baseline_native_uninstrumented_median_us_per_tick": baseline_median,
            "instrumentation_disabled_median_us_per_tick": disabled_median,
            "instrumented_median_us_per_tick": enabled_median,
            "instrumented_minus_disabled_observer_overhead_us_per_tick": observer_overhead,
            "paired_observer_overhead_samples_us_per_tick": paired_observer_deltas,
            "instrumented_wall_spread_us_per_tick": [min(_number(s["wall_us_per_tick"], "enabled") for s in enabled_samples),
                                                       max(_number(s["wall_us_per_tick"], "enabled") for s in enabled_samples)],
            "disabled_wall_spread_us_per_tick": [min(_number(s, "disabled") for s in prof["disabled_samples_us_per_tick"]),
                                                  max(_number(s, "disabled") for s in prof["disabled_samples_us_per_tick"])],
            "disabled_instrumentation_minus_unmodified_baseline_us_per_tick": profile_off_delta,
            "native_route_counts": prof["native_route_counts"],
            "component_calls_per_tick": {
                name: int(enabled_samples[0]["profile"]["calls"].get(name, 0)) // ticks for name in COMPONENTS
            },
            "exclusive_component_mean_us_per_tick": means,
            "exclusive_sum_mean_us_per_tick": sum(means.values()),
            "instrumented_step_timer_mean_us_per_tick": mean_step,
            "inclusive_diagnostics_mean_us_per_tick": {
                "Flight._pre_step": statistics.mean(
                    _number(s["profile"]["elapsed_usec"]["pre_step_inclusive"], "pre-step timer") / float(ticks)
                    for s in enabled_samples
                ),
                "Air.compute in pre-step": statistics.mean(
                    _number(s["profile"]["elapsed_usec"]["air_pre_step"], "pre-step air timer") / float(ticks)
                    for s in enabled_samples
                ),
            },
            "timing_samples": {
                "baseline_native_uninstrumented_us_per_tick": base["batches_us"],
                "instrumentation_disabled_us_per_tick": prof["disabled_samples_us_per_tick"],
                "instrumented_us_per_tick": [float(s["wall_us_per_tick"]) for s in enabled_samples],
                "exclusive_components_per_batch_us_per_tick": sample_buckets,
            },
        })
    return summary


def _compare_boundaries(baseline: dict[str, Any], instrumented: dict[str, Any]) -> dict[str, Any]:
    if baseline.get("format") != "openrc-e0b6p-swirl-cost v1" or instrumented.get("format") != "openrc-e0b6p-tick-attribution v1":
        raise RuntimeError("Unexpected baseline or instrumented report format")
    max_difference = 0.0
    checked = 0
    rows: list[dict[str, Any]] = []
    for base, prof in zip(baseline["rows"], instrumented["rows"], strict=True):
        if (base.get("regime"), float(base.get("swirl_factor", -1.0))) != (
            prof.get("regime"), float(prof.get("swirl_factor", -1.0))
        ):
            raise RuntimeError("Boundary comparison regime order mismatch")
        old_boundaries = base.get("boundaries", [])
        new_boundaries = prof.get("boundaries", [])
        if len(old_boundaries) != 240 or len(new_boundaries) != 240:
            raise RuntimeError("Expected 240 committed body/auxiliary boundaries per case")
        case_max = 0.0
        for tick, (old, new) in enumerate(zip(old_boundaries, new_boundaries, strict=True)):
            for key, expected_size in (("state", 13), ("aux", 14), ("continuous", 0)):
                x_array = old.get(key)
                y_array = new.get(key)
                if not isinstance(x_array, list) or not isinstance(y_array, list) or len(x_array) != expected_size or len(y_array) != expected_size:
                    raise RuntimeError(f"Malformed boundary {key} at {base['regime']} tick {tick}")
                if x_array != y_array:
                    for component, (x, y) in enumerate(zip(x_array, y_array, strict=True)):
                        xv = _number(x, "baseline boundary")
                        yv = _number(y, "instrumented boundary")
                        difference = abs(xv - yv)
                        case_max = max(case_max, difference)
                        max_difference = max(max_difference, difference)
                        if difference != 0.0:
                            raise RuntimeError(
                                f"Instrumentation changed {key} at {base['regime']} swirl={base['swirl_factor']} "
                                f"tick={tick} component={component}: {xv} != {yv}"
                            )
                checked += len(x_array)
        rows.append({"regime": base["regime"], "swirl_factor": base["swirl_factor"],
                     "ticks": 240, "exact": case_max == 0.0, "max_absolute_difference": case_max})
    return {"format": "openrc-e0b6p-attribution-boundary-comparison v1", "cases": len(rows),
            "components_compared": ["state", "aux", "continuous"], "scalar_values_checked": checked,
            "exact_all_boundaries": max_difference == 0.0, "max_absolute_difference": max_difference,
            "rows": rows}


def _expect_rejected(label: str, check: Any) -> str:
    try:
        check()
    except (RuntimeError, KeyError, TypeError, IndexError):
        return label
    raise RuntimeError(f"Comparator self-test was not rejected: {label}")


def _comparator_self_tests(baseline: dict[str, Any], instrumented: dict[str, Any]) -> list[str]:
    passed: list[str] = []
    bad_routes = copy.deepcopy(baseline)
    bad_routes["native_route_counts"]["kernel_calls"] = 0
    passed.append(_expect_rejected("zero native-kernel calls", lambda: _validate_routes(bad_routes, "mutated baseline")))

    bad_profile = copy.deepcopy(instrumented)
    bad_profile["rows"][0]["enabled_samples"][0]["profile"]["calls"]["air_dynamics"] = 0
    passed.append(_expect_rejected("zero component calls", lambda: _validate_profile(bad_profile)))

    bad_roster = copy.deepcopy(instrumented)
    bad_roster["rows"][0]["regime"] = "missing"
    passed.append(_expect_rejected("wrong regime roster", lambda: _compare_boundaries(baseline, bad_roster)))

    truncated = copy.deepcopy(instrumented)
    truncated["rows"][0]["boundaries"].pop()
    passed.append(_expect_rejected("truncated boundary series", lambda: _compare_boundaries(baseline, truncated)))

    non_finite = copy.deepcopy(instrumented)
    non_finite["rows"][0]["boundaries"][0]["state"][0] = float("nan")
    passed.append(_expect_rejected("non-finite boundary", lambda: _compare_boundaries(baseline, non_finite)))
    return passed


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="Godot app directory to copy")
    parser.add_argument("--godot", required=True, help="Godot 4.7 executable")
    parser.add_argument("--library", type=Path, required=True, help="E0b6p smooth-wake GDExtension")
    parser.add_argument("--output", type=Path, required=True, help="raw output and staged app directory")
    args = parser.parse_args()
    source_project = args.project.expanduser().resolve()
    library = args.library.expanduser().resolve()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    godot = _resolve(args.godot)
    work_project = output / "work/app"
    if work_project.exists():
        shutil.rmtree(work_project)
    _copy_app(source_project, work_project)
    source_hashes = {
        str(path.relative_to(source_project)): _sha256(path)
        for folder in ("physics", "sim")
        for path in sorted((source_project / folder).rglob("*.gd"))
    }
    evidence: dict[str, Any] = {
        "format": "openrc-e0b6p-attribution-evidence v1",
        "status": "running",
        "source_project": str(source_project),
        "staged_project": str(work_project),
        "source_revision": subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True,
                                             capture_output=True, check=False).stdout.strip(),
        "source_physics_and_sim_sha256": source_hashes,
        "research_inputs_sha256": {
            str(path.relative_to(ROOT)): _sha256(path)
            for path in (APP_BENCH, ADAPTER_SCRIPT, PROFILE_SCRIPT, PROFILER_SCRIPT, HERE / "run.py",
                         ROOT / "research/propwash/e0b6p/native/src/smooth_wake_kernel.hpp",
                         ROOT / "research/propwash/e0b6p/native/src/smooth_wake_extension.cpp",
                         ROOT / "app/tests/test_wash_profile.gd", ROOT / "app/tests/test_wash_transport.gd",
                         ROOT / "app/tests/fixtures/stik_wash_profile.json")
        },
        "godot": godot,
        "host": platform.platform(),
        "cpu": platform.processor(),
        "native_library": str(library),
        "native_library_sha256": _sha256(library),
        "instrumentation_scope": ["Air.compute call sites", "Aero.loads", "Propulsion.loads", "Slipstream.loads",
                                  "Ground.loads", "pre_step callback", "Simulation.step total"],
        "component_accounting": "Exclusive buckets; Air.compute inside pre-step and the wash derivative is timed separately; rest sim.step is the residual.",
    }
    evidence_path = output / "attribution.json"
    try:
        probe = _install_native_adapter(work_project, library)
        baseline_script = _instrument_baseline_bench(work_project, probe)
        baseline_path = output / "baseline-native.json"
        _run_godot(godot, work_project, baseline_script, baseline_path, timeout=600)
        baseline = _read_json(baseline_path)
        if len(baseline.get("rows", [])) != 12:
            raise RuntimeError("Uninstrumented baseline omitted cases")
        evidence["baseline_native_route_counts"] = _validate_routes(baseline, "baseline")
        profile_script = _instrument_project(work_project)
        _check_only(godot, work_project, profile_script, output / "instrumented-check-only.log")
        instrumented_path = output / "instrumented-native.json"
        _run_godot(godot, work_project, profile_script, instrumented_path, timeout=600)
        instrumented = _read_json(instrumented_path)
        _validate_profile(instrumented)
        evidence["comparator_mutation_self_tests"] = _comparator_self_tests(baseline, instrumented)
        boundary_comparison = _compare_boundaries(baseline, instrumented)
        summary_rows = _summarize_rows(baseline, instrumented)
        evidence["status"] = "pass"
        evidence["baseline_report"] = str(baseline_path)
        evidence["instrumented_report"] = str(instrumented_path)
        evidence["instrumented_godot"] = instrumented.get("godot")
        evidence["instrumented_cpu"] = instrumented.get("cpu")
        evidence["boundary_comparison"] = boundary_comparison
        evidence["rows"] = summary_rows
        evidence["observer_overhead_note"] = (
            "Timer observer overhead is the median of alternating paired enabled-minus-disabled batches in the same staged build. "
            "The disabled-build minus unmodified-baseline difference is only an observed delta with shared-host noise; it does not isolate scaffolding cost."
        )
        evidence["limitations"] = [
            "Native binding model-dictionary decode and pure C++ kernel time are not separated in this pass.",
            "Timers use Godot microsecond clock calls; very small component values have quantization and observer overhead.",
            "The fixture is a research-only smooth-wake model, not a calibrated production Stik configuration.",
        ]
        evidence_path.write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        print(f"E0b6p tick attribution passed: {evidence_path}")
        print(f"Staged app: {work_project}")
    except Exception as error:
        evidence["status"] = "fail"
        evidence["error"] = str(error)
        evidence_path.write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        print(f"E0b6p tick attribution failed: {evidence_path}\n{error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
