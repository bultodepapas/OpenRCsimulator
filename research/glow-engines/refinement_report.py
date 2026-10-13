"""Build a reproducible same-time timestep-refinement report for glow flight cases.

This compares numerical trajectories from the paired installed-aircraft bench. It
does not validate the inferred engine, propeller, or aircraft models physically.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs" / "research" / "glow-engines" / "NITRO-02" / "refinement.json"
RUNS = {
    240: ROOT / "research" / "glow-engines" / "flight-240.json",
    480: ROOT / "research" / "glow-engines" / "flight-480.json",
    960: ROOT / "research" / "glow-engines" / "flight-960.json",
}
SOURCE_PATHS = [
    "research/glow-engines/flight_bench.gd",
    "app/sim/flight_session.gd",
    "app/sim/simulation.gd",
    "app/data/field_loader.gd",
    "app/physics/aircraft_data.gd",
    "app/physics/glow/profile.gd",
    "app/physics/glow/installation.gd",
    "app/physics/glow/flight.gd",
    "app/physics/glow/lifecycle.gd",
    "app/physics/glow/source.gd",
    "app/physics/glow/two_stroke.gd",
    "app/physics/glow/four_stroke.gd",
    "app/physics/glow/thermal.gd",
    "app/physics/glow/fuel_mass.gd",
    "app/physics/glow/propeller.gd",
    "app/physics/dynamics.gd",
    "app/physics/propulsion.gd",
    "app/physics/glow/operating_point.gd",
    "app/physics/electric_battery_step.gd",
    "app/physics/math3d.gd",
    "app/physics/rigid_body.gd",
    "app/physics/rotor_coupling.gd",
]
INPUT_PATHS = [
    "app/data/aircraft/stik_glow_55ax_2t.json",
    "app/data/aircraft/stik_glow_fs64v_4t.json",
    "app/data/glow/stik_55ax_2t.json",
    "app/data/glow/stik_fs64v_4t.json",
    "app/data/glow/os_max_55ax_candidate.json",
    "app/data/glow/os_fs_64v_candidate.json",
]
FAMILIES = {"55ax_2t": "glow_2t", "fs64v_4t": "glow_4t"}
ENGINE_INPUTS = {
    "55ax_2t": (
        "app/data/aircraft/stik_glow_55ax_2t.json",
        "app/data/glow/stik_55ax_2t.json",
    ),
    "fs64v_4t": (
        "app/data/aircraft/stik_glow_fs64v_4t.json",
        "app/data/glow/stik_fs64v_4t.json",
    ),
}
EXPECTED_SCENARIOS = {"cruise", "steps", "rich", "lean", "exhaustion", "takeoff"}
METRICS = {
    "rpm": {"unit": "rpm", "budget": 0.001, "normalization": "maximum absolute 960 Hz reference trajectory"},
    "shaft_work_j": {"unit": "J", "budget": 0.005, "normalization": "maximum absolute 960 Hz reference trajectory"},
    "propeller_work_j": {"unit": "J", "budget": 0.005, "normalization": "maximum absolute 960 Hz reference trajectory"},
    "fuel_consumed_kg": {"unit": "kg", "budget": 0.005, "normalization": "final 960 Hz integrated delivered-fuel amount"},
    "temperature_k": {"unit": "K", "budget": 0.5, "normalization": "absolute difference"},
}
CONFIGURATION = {
    "sample_interval_s": 0.1,
    "sample_tolerance_s": 1.0e-8,
    "continuous_fuel_transport_index": 5,
    "continuous_opportunity_count_index": 9,
    "continuous_fire_count_index": 10,
    "budgets": {
        "rpm_max_percent_of_reference_peak": 0.1,
        "shaft_work_max_percent_of_reference_peak": 0.5,
        "propeller_work_max_percent_of_reference_peak": 0.5,
        "fuel_consumed_max_percent_of_reference_total": 0.5,
        "temperature_max_absolute_k": 0.5,
    },
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def finite(value: Any, label: str) -> float:
    if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise ValueError(f"{label} must be a finite number")
    return float(value)


def verify_recorded_inputs(engine: str, run: dict[str, Any]) -> None:
    config = run.get("configuration")
    if not isinstance(config, dict):
        raise ValueError(f"{engine} run is missing structured configuration provenance")
    aircraft_path, installation_path = ENGINE_INPUTS[engine]
    if config.get("aircraft_input_sha256") != sha256(ROOT / aircraft_path):
        raise ValueError(f"{engine} benchmark aircraft hash does not match {aircraft_path}")
    installation = json.loads((ROOT / installation_path).read_text(encoding="utf-8"))
    if installation.get("family") != FAMILIES[engine]:
        raise ValueError(f"{installation_path} has a mismatched engine family")
    identity = json.loads(config.get("glow_identity", "{}"))
    if identity.get("sha256") != sha256(ROOT / installation_path):
        raise ValueError(f"{engine} benchmark installation hash does not match {installation_path}")
    profile_relative = str(installation.get("profile", "")).removeprefix("res://")
    profile_path = ROOT / "app" / profile_relative
    recorded_profile = identity.get("profile", {}).get("sha256")
    if not profile_path.exists() or recorded_profile != sha256(profile_path):
        raise ValueError(f"{engine} benchmark profile hash does not match {profile_path}")
    if config.get("glow_family") != FAMILIES[engine]:
        raise ValueError(f"{engine} trace family does not match its installation")


def read_runs() -> tuple[dict[int, dict[tuple[str, str], dict[str, Any]]], list[dict[str, Any]]]:
    by_rate: dict[int, dict[tuple[str, str], dict[str, Any]]] = {}
    source_records: list[dict[str, Any]] = []
    for hz, path in RUNS.items():
        raw = json.loads(path.read_text(encoding="utf-8"))
        if raw.get("format") != "openrc-glow-flight-experiment v1" or raw.get("ok") is not True:
            raise ValueError(f"{path.relative_to(ROOT)} is not a successful supported flight bench output")
        if raw.get("hz") != hz or not isinstance(raw.get("runs"), list):
            raise ValueError(f"{path.relative_to(ROOT)} has mismatched rate or missing runs")
        cases: dict[tuple[str, str], dict[str, Any]] = {}
        for run in raw["runs"]:
            engine = run.get("engine")
            scenario = run.get("scenario")
            key = (str(engine), str(scenario))
            if key in cases or engine not in FAMILIES or scenario not in EXPECTED_SCENARIOS:
                raise ValueError(f"unexpected or duplicate case in {path.name}: {key}")
            if run.get("hz") != hz:
                raise ValueError(f"case {key} has an inconsistent rate")
            verify_recorded_inputs(str(engine), run)
            samples = run.get("samples")
            if not isinstance(samples, list) or len(samples) < 2:
                raise ValueError(f"case {key} has no useful trajectory")
            for sample_index, sample in enumerate(samples):
                for name in ("time_s", "rpm", "shaft_work_j", "propeller_work_j", "temperature_k", "fuel_kg"):
                    finite(sample.get(name), f"{path.name}:{key}:{sample_index}:{name}")
                continuous = sample.get("continuous")
                if not isinstance(continuous, list) or len(continuous) <= CONFIGURATION["continuous_fire_count_index"]:
                    raise ValueError(f"case {key} has an incomplete continuous-state sample")
                finite(continuous[CONFIGURATION["continuous_fuel_transport_index"]], "fuel transport")
            cases[key] = run
            source_records.append({
                "engine": engine,
                "family": FAMILIES[engine],
                "scenario": scenario,
                "hz": hz,
                "configuration": run.get("configuration", ""),
                "initial": run["initial"],
                "final": run["final"],
                "cost_us": run.get("cost_us", {}),
            })
        expected = {(engine, scenario) for engine in FAMILIES for scenario in EXPECTED_SCENARIOS}
        if set(cases) != expected:
            missing = sorted(expected - set(cases))
            extra = sorted(set(cases) - expected)
            raise ValueError(f"{path.name}: incomplete case set; missing={missing}, extra={extra}")
        by_rate[hz] = cases
    return by_rate, source_records


def times(run: dict[str, Any]) -> list[float]:
    return [float(sample["time_s"]) for sample in run["samples"]]


def delivered_fuel_trajectory(run: dict[str, Any]) -> list[float]:
    """Trapezoid-integrate logged tank-to-engine transport on the 0.1 s grid."""
    samples = run["samples"]
    index = CONFIGURATION["continuous_fuel_transport_index"]
    consumed = [0.0]
    for previous, current in zip(samples, samples[1:]):
        dt = float(current["time_s"]) - float(previous["time_s"])
        if dt <= 0.0:
            raise ValueError("fuel trajectory samples must have strictly increasing times")
        previous_rate = max(0.0, float(previous["continuous"][index]))
        current_rate = max(0.0, float(current["continuous"][index]))
        consumed.append(consumed[-1] + 0.5 * (previous_rate + current_rate) * dt)
    return consumed


def trajectory(run: dict[str, Any]) -> dict[str, list[float]]:
    samples = run["samples"]
    return {
        "rpm": [float(sample["rpm"]) for sample in samples],
        "shaft_work_j": [float(sample["shaft_work_j"]) for sample in samples],
        "propeller_work_j": [float(sample["propeller_work_j"]) for sample in samples],
        "fuel_consumed_kg": delivered_fuel_trajectory(run),
        "temperature_k": [float(sample["temperature_k"]) for sample in samples],
    }


def compare_metric(name: str, candidate: list[float], reference: list[float]) -> dict[str, Any]:
    if len(candidate) != len(reference) or not candidate:
        raise ValueError(f"{name} trajectories do not have matching samples")
    differences = [a - b for a, b in zip(candidate, reference)]
    absolute = [abs(value) for value in differences]
    max_index = max(range(len(absolute)), key=absolute.__getitem__)
    spec = METRICS[name]
    if name == "temperature_k":
        scale = None
        normalized_peak_percent = None
        passes = absolute[max_index] <= spec["budget"]
    else:
        scale = abs(reference[-1]) if name == "fuel_consumed_kg" else max(abs(value) for value in reference)
        if scale <= 1.0e-30:
            normalized_peak_percent = None
            passes = absolute[max_index] <= 1.0e-30
        else:
            normalized_peak_percent = absolute[max_index] / scale * 100.0
            passes = normalized_peak_percent <= spec["budget"] * 100.0
    result: dict[str, Any] = {
        "unit": spec["unit"],
        "max_absolute_difference": absolute[max_index],
        "max_difference_time_s": None,
        "endpoint_difference_candidate_minus_reference": differences[-1],
        "reference_scale": scale,
        "max_percent_of_reference_scale": normalized_peak_percent,
        "budget": spec["budget"] if name == "temperature_k" else spec["budget"] * 100.0,
        "budget_unit": "K" if name == "temperature_k" else "% of reference scale",
        "passes_budget": passes,
    }
    result["max_difference_time_s"] = None
    return result


def compare_runs(candidate: dict[str, Any], reference: dict[str, Any], candidate_hz: int) -> dict[str, Any]:
    candidate_times = times(candidate)
    reference_times = times(reference)
    if len(candidate_times) != len(reference_times) or any(
        abs(a - b) > CONFIGURATION["sample_tolerance_s"] for a, b in zip(candidate_times, reference_times)
    ):
        raise ValueError("refinement trajectories do not share the same time samples")
    c = trajectory(candidate)
    r = trajectory(reference)
    metrics: dict[str, Any] = {}
    for name in METRICS:
        item = compare_metric(name, c[name], r[name])
        error_index = max(range(len(c[name])), key=lambda i: abs(c[name][i] - r[name][i]))
        item["max_difference_time_s"] = candidate_times[error_index]
        metrics[name] = item
    c_final = candidate["final"]
    r_final = reference["final"]
    c_indices = CONFIGURATION["continuous_opportunity_count_index"], CONFIGURATION["continuous_fire_count_index"]
    r_indices = c_indices
    opportunities_c, fires_c = (int(round(c_final["continuous"][i])) for i in c_indices)
    opportunities_r, fires_r = (int(round(r_final["continuous"][i])) for i in r_indices)
    passed = all(bool(item["passes_budget"]) for item in metrics.values())
    return {
        "candidate_hz": candidate_hz,
        "reference_hz": 960,
        "common_sample_count": len(candidate_times),
        "comparison_method": "same-time comparison of every saved 0.1 s snapshot; fuel is trapezoid-integrated from saved fuel-transport flow",
        "metrics": metrics,
        "firing_events": {
            "candidate_opportunities": opportunities_c,
            "reference_opportunities": opportunities_r,
            "candidate_fires": fires_c,
            "reference_fires": fires_r,
            "opportunity_count_difference": opportunities_c - opportunities_r,
            "fire_count_difference": fires_c - fires_r,
            "informational_only": True,
        },
        "passes_all_budgets": passed,
    }


def run_summary(run: dict[str, Any], hz: int) -> dict[str, Any]:
    samples = run["samples"]
    final = run["final"]
    fuel = delivered_fuel_trajectory(run)
    initial_inventory = float(run["initial"]["fuel_kg"])
    final_inventory = float(final["fuel_kg"])
    return {
        "hz": hz,
        "sample_count": len(samples),
        "duration_s": float(samples[-1]["time_s"]),
        "initial": {key: run["initial"][key] for key in ("rpm", "fuel_kg", "temperature_k", "running", "stop_reason")},
        "final": {key: final[key] for key in ("rpm", "fuel_kg", "temperature_k", "running", "stop_reason", "shaft_work_j", "propeller_work_j")},
        "integrated_delivered_fuel_kg": fuel[-1],
        "sampled_fuel_inventory_change_kg": initial_inventory - final_inventory,
        "end_opportunity_count": int(round(final["continuous"][CONFIGURATION["continuous_opportunity_count_index"]])),
        "end_fire_count": int(round(final["continuous"][CONFIGURATION["continuous_fire_count_index"]])),
        "configuration": run.get("configuration", ""),
    }


def build() -> dict[str, Any]:
    by_rate, source_records = read_runs()
    cases: list[dict[str, Any]] = []
    for engine in sorted(FAMILIES):
        for scenario in sorted(EXPECTED_SCENARIOS):
            key = (engine, scenario)
            run240, run480, run960 = (by_rate[hz][key] for hz in (240, 480, 960))
            if any(abs(float(run["initial"]["time_s"])) > CONFIGURATION["sample_tolerance_s"] for run in (run240, run480, run960)):
                raise ValueError(f"{key}: expected trajectories to start at t=0")
            summaries = {str(hz): run_summary(by_rate[hz][key], hz) for hz in (240, 480, 960)}
            comparisons = {
                "240_vs_960": compare_runs(run240, run960, 240),
                "480_vs_960": compare_runs(run480, run960, 480),
            }
            cases.append({
                "engine": engine,
                "family": FAMILIES[engine],
                "scenario": scenario,
                "runs": summaries,
                "comparisons": comparisons,
            })
    aggregate: dict[str, Any] = {}
    for comparison_name in ("240_vs_960", "480_vs_960"):
        per_metric: dict[str, Any] = {}
        for metric_name in METRICS:
            selected = [case["comparisons"][comparison_name]["metrics"][metric_name] for case in cases]
            worst_index = max(range(len(selected)), key=lambda i: selected[i]["max_absolute_difference"] if metric_name == "temperature_k" else (selected[i]["max_percent_of_reference_scale"] or 0.0))
            worst_case = cases[worst_index]
            per_metric[metric_name] = {
                "budget_passes": sum(bool(item["passes_budget"]) for item in selected),
                "budget_cases": len(selected),
                "worst_case": f"{worst_case['family']}:{worst_case['scenario']}",
                "worst_result": selected[worst_index],
            }
        aggregate[comparison_name] = {
            "cases_passing_all_budgets": sum(bool(case["comparisons"][comparison_name]["passes_all_budgets"]) for case in cases),
            "case_count": len(cases),
            "metrics": per_metric,
        }

    source_hashes = []
    for relative in SOURCE_PATHS:
        path = ROOT / relative
        if path.exists():
            source_hashes.append({"path": relative, "sha256": sha256(path)})
    input_hashes = []
    for relative in INPUT_PATHS:
        path = ROOT / relative
        if not path.exists():
            raise ValueError(f"missing benchmark input: {relative}")
        input_hashes.append({"path": relative, "sha256": sha256(path)})
    run_files = []
    for hz, path in RUNS.items():
        payload = json.loads(path.read_text(encoding="utf-8"))
        run_files.append({
            "path": path.relative_to(ROOT).as_posix(),
            "sha256": sha256(path),
            "hz": hz,
            "run_count": len(payload["runs"]),
            "ok": payload["ok"],
        })
    return {
        "format": "openrc-glow-flight-refinement v1",
        "purpose": "numerical timestep-refinement audit of installed experimental candidates",
        "not_physical_validation": True,
        "case_count": len(cases),
        "run_count": len(source_records),
        "rates_hz": [240, 480, 960],
        "comparison_reference_hz": 960,
        "configuration": CONFIGURATION,
        "fuel_accounting": {
            "metric": "integrated delivered engine fuel",
            "method": "trapezoidal integration of the fuel-transport state (continuous index 5) sampled every 0.1 s",
            "starter_prime": "The takeoff case calls glow_start before its initial snapshot; that start routine deducts the metered starter_prime_kg from tank inventory. Therefore the reported integral begins after priming and does not count priming as engine consumption.",
            "exhaustion_intervention": "At 0.5 s the exhaustion case directly overwrites tank inventory with 1e-7 kg. Inventory change includes this test intervention and is reported separately; it is not labeled fuel burned or delivered.",
            "inventory_change_field": "sampled_fuel_inventory_change_kg is initial sampled inventory minus final sampled inventory and may include explicit case interventions; use integrated_delivered_fuel_kg for the convergence comparison.",
            "integration_limit": "Fuel delivery is reconstructed from 0.1 s saved rates, not an independently recorded cumulative fuel meter.",
        },
        "event_timing_limit": {
            "accepted_step_quantization_s": {str(hz): 1.0 / hz for hz in RUNS},
            "saved_event_observation_interval_s": CONFIGURATION["sample_interval_s"],
            "model": "Mean-cycle work has no crank-angle-resolved torque ripple; firing opportunity/fire counters advance on accepted simulation steps.",
            "limitation": "The report compares endpoint event counts only. It cannot establish cycle pulse timing or event phase against a measured cycle oracle; no matched physical cycle trace is available.",
        },
        "source_hashes": source_hashes,
        "source_hash_scope": "SHA-256 of the current checked-out runner and runtime sources at report generation; the bench configuration does not record per-module source hashes.",
        "input_hashes": input_hashes,
        "benchmark_outputs": run_files,
        "run_metadata": source_records,
        "aggregate": aggregate,
        "cases": cases,
        "interpretation": "The reported differences quantify numerical agreement among this model's timestep choices under identical bench scenarios and assumptions. They are not physical accuracy, engine validation, or pilot validation.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--write", action="store_true", help="write the versioned report")
    group.add_argument("--check", action="store_true", help="fail if the saved report is stale")
    args = parser.parse_args()
    report = build()
    rendered = json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"Stale report: {OUTPUT.relative_to(ROOT)}")
        print(f"Current refinement report: {len(report['run_metadata'])} runs, {len(report['cases'])} paired cases")
    elif args.write:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(rendered, encoding="utf-8")
        print(f"Wrote refinement report: {len(report['run_metadata'])} runs, {len(report['cases'])} paired cases")
    else:
        print(rendered)


if __name__ == "__main__":
    main()
