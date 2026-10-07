#!/usr/bin/env python3
"""Profile baseline and instrumented E0b6p native calls in disposable app copies."""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
NATIVE_DIR = ROOT / "research/propwash/e0b6p/native"
BASELINE_SOURCE = NATIVE_DIR / "src/smooth_wake_extension.cpp"
KERNEL_HEADER = NATIVE_DIR / "src/smooth_wake_kernel.hpp"
GENERATED_SOURCE = ROOT / ".tools/native-wake-attribution/src/smooth_wake_extension.cpp"
BUILD_METADATA = ROOT / ".tools/native-wake-attribution/build-metadata.json"
REGIMES = ("forward", "stall", "static", "spin", "reverse_fade", "reverse_off")
MEASURED_BATCHES = 7
CALLS_PER_BATCH = 3000
WARMUP_CALLS = 500
STAT_KEYS = (
    "calls", "method_total_ns", "input_decode_ns", "model_decode_ns", "transported_decode_ns",
    "kernel_total_ns", "validate_ns", "wake_ns", "profile_ns", "swirl_ns", "kernel_finalize_ns",
    "pack_ns", "clock_pair_overhead_ns",
)
ROUTE_KEYS = ("native", "kernel_calls", "legacy", "refused")
PROFILE_SPEC = importlib.util.spec_from_file_location("native_e0b6p_run", NATIVE_DIR / "run.py")
native_run = importlib.util.module_from_spec(PROFILE_SPEC)
PROFILE_SPEC.loader.exec_module(native_run)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_profile(godot: str, project: Path, script: Path, report: Path, instrumented: bool) -> str:
    command = [godot, "--headless", "--path", str(project), "--script", str(script), "--",
               str(report), "true" if instrumented else "false"]
    result = subprocess.run(command, text=True, capture_output=True, timeout=180, check=False)
    combined = result.stdout + result.stderr
    (report.parent / f"{report.stem}.log").write_text(combined, encoding="utf-8")
    if result.returncode != 0 or native_run.ERROR_RE.search(combined):
        raise RuntimeError(f"Profiling script failed ({result.returncode}): {script}\n{combined}")
    if not report.is_file():
        raise RuntimeError(f"Godot did not write profile report: {report}\n{combined}")
    return combined


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"Could not read JSON report {path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected an object in {path}")
    return value


def _finite_number(value: Any) -> bool:
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(float(value))


def _require_vector(row: dict[str, Any], key: str, label: str) -> None:
    values = row.get(key)
    if not isinstance(values, list) or len(values) != 6 or any(not _finite_number(value) for value in values):
        raise RuntimeError(f"{label} has a missing, malformed, or non-finite six-load vector")


def _require_samples(row: dict[str, Any], key: str, label: str, *, positive: bool) -> None:
    values = row.get(key)
    if (not isinstance(values, list) or len(values) != MEASURED_BATCHES
            or any(not _finite_number(value) for value in values)
            or (positive and any(float(value) <= 0.0 for value in values))):
        raise RuntimeError(f"{label} must contain {MEASURED_BATCHES} finite batch samples")


def require_profile(report: dict[str, Any], label: str, expected_instrumented: bool) -> None:
    if report.get("format") != "openrc-e0b6p-native-attribution-profile v1":
        raise RuntimeError(f"Unexpected {label} profile format")
    if report.get("instrumented") is not expected_instrumented:
        raise RuntimeError(f"Unexpected instrumented flag in {label} profile")
    if (report.get("warmup_calls_per_regime") != WARMUP_CALLS
            or report.get("calls_per_batch") != CALLS_PER_BATCH
            or report.get("measured_batches") != MEASURED_BATCHES):
        raise RuntimeError(f"{label} profile used an unexpected timing roster")
    rows = report.get("rows")
    if not isinstance(rows, list) or [row.get("regime") for row in rows] != list(REGIMES):
        raise RuntimeError(f"{label} profile omitted or reordered an initial fixture regime")
    for row in rows:
        regime = str(row["regime"])
        if not _finite_number(row.get("fade")):
            raise RuntimeError(f"{label}/{regime} has a non-finite fade")
        _require_vector(row, "direct_loads", f"{label}/{regime}/direct")
        _require_vector(row, "adapter_loads", f"{label}/{regime}/adapter")
        if row["direct_loads"] != row["adapter_loads"]:
            raise RuntimeError(f"{label}/{regime} direct and adapter loads differ")
        _require_samples(row, "direct_external_us_per_call_batches", f"{label}/{regime}/direct times", positive=True)
        _require_samples(row, "direct_empty_loop_us_per_iteration_batches", f"{label}/{regime}/empty loops", positive=False)
        _require_samples(row, "adapter_external_us_per_call_batches", f"{label}/{regime}/adapter times", positive=True)

        route_batches = row.get("adapter_routes_batches")
        if not isinstance(route_batches, list) or len(route_batches) != MEASURED_BATCHES:
            raise RuntimeError(f"{label}/{regime} has incomplete adapter route samples")
        expected_kernel_calls = 0 if regime == "reverse_off" else CALLS_PER_BATCH
        expected_routes = {
            "native": CALLS_PER_BATCH,
            "kernel_calls": expected_kernel_calls,
            "legacy": 0,
            "refused": 0,
        }
        for routes in route_batches:
            if not isinstance(routes, dict) or any(routes.get(key) != value for key, value in expected_routes.items()):
                raise RuntimeError(f"{label}/{regime} adapter route counts are wrong: {routes}")
        if row.get("adapter_routes_last_batch") != route_batches[-1]:
            raise RuntimeError(f"{label}/{regime} last-batch routes do not match the route roster")

        direct_stats = row.get("direct_internal_stats_batches")
        adapter_stats = row.get("adapter_internal_stats_batches")
        expected_stats = MEASURED_BATCHES if expected_instrumented else 0
        if not isinstance(direct_stats, list) or len(direct_stats) != expected_stats:
            raise RuntimeError(f"{label}/{regime} has incomplete direct phase counters")
        if not isinstance(adapter_stats, list) or len(adapter_stats) != expected_stats:
            raise RuntimeError(f"{label}/{regime} has incomplete adapter phase counters")
        if expected_instrumented:
            for stats in direct_stats:
                if (not isinstance(stats, dict) or any(not _finite_number(stats.get(key)) for key in STAT_KEYS)
                        or int(stats["calls"]) != CALLS_PER_BATCH
                        or int(stats["clock_pair_overhead_ns"]) <= 0):
                    raise RuntimeError(f"{label}/{regime} direct native counters are malformed")
            for stats in adapter_stats:
                if (not isinstance(stats, dict) or any(not _finite_number(stats.get(key)) for key in STAT_KEYS)
                        or int(stats["calls"]) != expected_kernel_calls
                        or int(stats["clock_pair_overhead_ns"]) <= 0):
                    raise RuntimeError(f"{label}/{regime} adapter native counters are malformed")


def compare_loads(baseline: dict[str, Any], instrumented: dict[str, Any]) -> None:
    require_profile(baseline, "baseline", False)
    require_profile(instrumented, "instrumented", True)
    for old, new in zip(baseline["rows"], instrumented["rows"], strict=True):
        if old.get("fade") != new.get("fade"):
            raise RuntimeError(f"Fade changed under instrumentation for {old['regime']}")
        for key in ("direct_loads", "adapter_loads"):
            if old[key] != new[key]:
                raise RuntimeError(f"Instrumented {key} differs from baseline for {old['regime']}")
        if old["adapter_routes_batches"] != new["adapter_routes_batches"]:
            raise RuntimeError(f"Instrumented adapter route roster differs for {old['regime']}")


def _synthetic_profile(instrumented: bool) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for regime in REGIMES:
        kernel_calls = 0 if regime == "reverse_off" else CALLS_PER_BATCH
        routes = {"native": CALLS_PER_BATCH, "kernel_calls": kernel_calls, "legacy": 0, "refused": 0}
        base: dict[str, Any] = {
            "regime": regime,
            "fade": 0.0 if regime == "reverse_off" else 1.0,
            "direct_loads": [0.0] * 6,
            "adapter_loads": [0.0] * 6,
            "direct_external_us_per_call_batches": [1.0] * MEASURED_BATCHES,
            "direct_empty_loop_us_per_iteration_batches": [0.01] * MEASURED_BATCHES,
            "adapter_external_us_per_call_batches": [2.0] * MEASURED_BATCHES,
            "adapter_routes_batches": [routes.copy() for _ in range(MEASURED_BATCHES)],
            "adapter_routes_last_batch": routes.copy(),
            "direct_internal_stats_batches": [],
            "adapter_internal_stats_batches": [],
        }
        if instrumented:
            direct_stats = {key: 100 for key in STAT_KEYS}
            direct_stats["calls"] = CALLS_PER_BATCH
            direct_stats["clock_pair_overhead_ns"] = 20
            adapter_stats = direct_stats.copy()
            adapter_stats["calls"] = kernel_calls
            base["direct_internal_stats_batches"] = [direct_stats.copy() for _ in range(MEASURED_BATCHES)]
            base["adapter_internal_stats_batches"] = [adapter_stats.copy() for _ in range(MEASURED_BATCHES)]
        rows.append(base)
    return {
        "format": "openrc-e0b6p-native-attribution-profile v1",
        "instrumented": instrumented,
        "warmup_calls_per_regime": WARMUP_CALLS,
        "calls_per_batch": CALLS_PER_BATCH,
        "measured_batches": MEASURED_BATCHES,
        "rows": rows,
    }


def self_check_comparator() -> None:
    baseline = _synthetic_profile(False)
    instrumented = _synthetic_profile(True)
    compare_loads(baseline, instrumented)
    mutations: list[tuple[str, dict[str, Any], dict[str, Any]]] = []
    missing = copy.deepcopy(baseline)
    del missing["rows"][0]["direct_loads"]
    missing_new = copy.deepcopy(instrumented)
    del missing_new["rows"][0]["direct_loads"]
    mutations.append(("missing load vector", missing, missing_new))
    nonfinite = copy.deepcopy(baseline)
    nonfinite["rows"][0]["adapter_loads"][2] = float("nan")
    mutations.append(("non-finite load", nonfinite, copy.deepcopy(instrumented)))
    wrong_count = copy.deepcopy(instrumented)
    wrong_count["rows"][0]["direct_internal_stats_batches"][0]["calls"] = CALLS_PER_BATCH - 1
    mutations.append(("wrong native call count", copy.deepcopy(baseline), wrong_count))
    for label, old, new in mutations:
        try:
            compare_loads(old, new)
        except RuntimeError:
            continue
        raise RuntimeError(f"Comparator self-check did not reject {label}")


def median(values: list[float]) -> float:
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[mid]
    return 0.5 * (ordered[mid - 1] + ordered[mid])


def phase_summary(profile: dict[str, Any]) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for row in profile["rows"]:
        batch_stats: list[dict[str, Any]] = row["direct_internal_stats_batches"]
        keys = (
            "method_total_ns", "input_decode_ns", "model_decode_ns", "transported_decode_ns",
            "kernel_total_ns", "validate_ns", "wake_ns", "profile_ns", "swirl_ns",
            "kernel_finalize_ns", "pack_ns",
        )
        means: dict[str, list[float]] = {key: [] for key in keys}
        loop_adjusted_binding_us: list[float] = []
        direct_us: list[float] = row["direct_external_us_per_call_batches"]
        empty_loop_us: list[float] = row["direct_empty_loop_us_per_iteration_batches"]
        for batch_index, stats in enumerate(batch_stats):
            count = int(stats["calls"])
            if count <= 0:
                raise RuntimeError(f"No instrumented direct calls for {row['regime']}")
            overhead = float(stats["clock_pair_overhead_ns"])
            for key in keys:
                raw = float(stats[key]) / count
                means[key].append(raw)
            # This is the external-to-C++-method remainder after subtracting the measured
            # empty-loop cost. It still includes call binding, marshalling and Variant handling.
            loop_adjusted_binding_us.append(
                direct_us[batch_index] - empty_loop_us[batch_index]
                - float(stats["method_total_ns"]) / count / 1000.0
            )
            if overhead <= 0:
                raise RuntimeError("Clock-pair calibration was not reported")
        medians = {key: median(values) for key, values in means.items()}
        timer_pair = median([float(item["clock_pair_overhead_ns"]) for item in batch_stats])
        corrected = {
            key: max(0.0, medians[key] - timer_pair)
            for key in (
                "input_decode_ns", "model_decode_ns", "transported_decode_ns", "validate_ns",
                "wake_ns", "profile_ns", "swirl_ns", "kernel_finalize_ns", "pack_ns",
            )
        }
        calls = int(batch_stats[0]["calls"])
        raw_kernel_phase_sum = sum(medians[key] for key in (
            "validate_ns", "wake_ns", "profile_ns", "swirl_ns", "kernel_finalize_ns"))
        raw_method_phase_sum = sum(medians[key] for key in (
            "input_decode_ns", "model_decode_ns", "transported_decode_ns", "kernel_total_ns", "pack_ns"))
        kernel_calls_adapter = int(row["adapter_routes_last_batch"].get("kernel_calls", -1))
        adapter_stats = row["adapter_internal_stats_batches"]
        if adapter_stats:
            adapter_count = int(adapter_stats[0]["calls"])
        else:
            adapter_count = kernel_calls_adapter
        output.append({
            "regime": row["regime"],
            "fade": row["fade"],
            "calls_per_direct_batch": calls,
            "clock_pair_overhead_ns_median": timer_pair,
            "direct_external_us_per_call_batches": direct_us,
            "direct_empty_loop_us_per_iteration_batches": empty_loop_us,
            "direct_external_us_per_call_median": median(direct_us),
            "baseline_direct_external_us_per_call_batches": row.get("baseline_direct_external_us_per_call_batches", []),
            "instrumented_method_and_phase_ns_per_call_median_raw": medians,
            "phase_ns_per_call_median_clock_corrected": corrected,
            "kernel_phase_sum_ns_per_call_median_raw": raw_kernel_phase_sum,
            "kernel_unattributed_ns_per_call_estimate": medians["kernel_total_ns"] - raw_kernel_phase_sum,
            "wrapper_unattributed_ns_per_call_estimate": medians["method_total_ns"] - raw_method_phase_sum,
            "estimated_binding_and_outer_remainder_us_batches": loop_adjusted_binding_us,
            "estimated_binding_and_outer_remainder_us_median": median(loop_adjusted_binding_us),
            "adapter_external_us_per_call_batches": row["adapter_external_us_per_call_batches"],
            "adapter_external_us_per_call_median": median(row["adapter_external_us_per_call_batches"]),
            "adapter_kernel_calls_per_batch": kernel_calls_adapter,
            "adapter_instrumented_call_count_per_batch": adapter_count,
        })
    return output


def main() -> None:
    self_check_comparator()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="the stable Godot app directory")
    parser.add_argument("--godot", required=True, help="Godot 4.7 executable")
    parser.add_argument("--baseline-library", type=Path, required=True)
    parser.add_argument("--instrumented-library", type=Path,
                        default=ROOT / ".tools/native-wake-attribution/libopenrc_slipstream.so")
    parser.add_argument("--output", type=Path, required=True, help="directory for raw profiles and evidence")
    parser.add_argument("--keep-work", action="store_true")
    args = parser.parse_args()
    project = args.project.expanduser().resolve()
    baseline = args.baseline_library.expanduser().resolve()
    instrumented = args.instrumented_library.expanduser().resolve()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    if baseline.name != instrumented.name:
        raise RuntimeError("The GDExtension libraries must have the same filename for isolated swaps")
    if not (project / "project.godot").is_file():
        raise RuntimeError(f"Project is not a Godot app: {project}")
    if not baseline.is_file() or not instrumented.is_file():
        raise RuntimeError("Baseline or instrumented GDExtension library does not exist")

    temporary: tempfile.TemporaryDirectory[str] | None = None
    if args.keep_work:
        work_root = Path(tempfile.mkdtemp(prefix="work-", dir=output))
    else:
        temporary = tempfile.TemporaryDirectory(prefix="openrc-native-attribution-")
        work_root = Path(temporary.name)
    work_project = work_root / "app"
    evidence: dict[str, Any] = {
        "format": "openrc-e0b6p-native-attribution v1",
        "status": "running",
        "project": str(project),
        "godot": args.godot,
        "baseline_library_sha256": sha256(baseline),
        "instrumented_library_sha256": sha256(instrumented),
        "baseline_source_sha256": sha256(BASELINE_SOURCE),
        "kernel_header_sha256": sha256(KERNEL_HEADER),
        "instrumented_source_sha256": sha256(GENERATED_SOURCE),
        "builder_sha256": sha256(HERE / "build_attribution.py"),
        "profile_script_sha256": sha256(HERE / "profile_attribution.gd"),
        "runner_sha256": sha256(Path(__file__).resolve()),
        "build_metadata": read_json(BUILD_METADATA),
        "host_platform": platform.platform(),
        "host_arch": platform.machine(),
        "python": platform.python_version(),
        "output": str(output),
        "keep_work": args.keep_work,
        "work_project": str(work_project) if args.keep_work else None,
        "timing_note": (
            "Baseline and instrumented runs are separate Godot processes. Report their observed batch distributions; "
            "do not attribute their difference causally to instrumentation."
        ),
        "clock_correction_note": (
            "Raw phase medians are retained alongside phase medians corrected by subtracting one measured "
            "steady_clock start/end pair per timed phase. This corrects timer endpoint cost only; it does not "
            "remove counter updates or other instrumentation cost from the raw method total. Independent phase "
            "medians need not sum exactly to the method median."
        ),
    }
    evidence_path = output / "attribution.json"
    try:
        native_run._copy_project(project, work_project)
        probe = native_run._install_probe(work_project, baseline)
        shutil.copy2(HERE / "profile_attribution.gd", probe / "profile_attribution.gd")
        evidence["app_source_sha256"] = native_run._source_hashes(work_project)
        baseline_profile_path = output / "baseline-profile.json"
        run_profile(args.godot, work_project, probe / "profile_attribution.gd", baseline_profile_path, False)
        baseline_profile = read_json(baseline_profile_path)
        require_profile(baseline_profile, "baseline", False)
        evidence["baseline_profile"] = str(baseline_profile_path)

        installed_instrumented = probe / instrumented.name
        shutil.copy2(instrumented, installed_instrumented)
        verification_path = output / "instrumented-verification.json"
        native_run._run_godot(args.godot, work_project, probe / "verify.gd", verification_path, timeout=180)
        verification = native_run._read_json(verification_path)
        if (verification.get("format") != "openrc-e0b6p-native-verification v1"
                or verification.get("random_cases") != 256
                or verification.get("compared_loads") != 297
                or int(verification.get("failures", 1)) != 0):
            raise RuntimeError(f"Instrumented library did not pass the full 297-case verifier: {verification}")
        evidence["instrumented_verification"] = str(verification_path)
        evidence["verification_checks"] = verification.get("checks")
        evidence["verification_compared_loads"] = verification.get("compared_loads")
        evidence["verification_coverage"] = verification.get("coverage")

        instrumented_profile_path = output / "instrumented-profile.json"
        run_profile(args.godot, work_project, probe / "profile_attribution.gd",
                    instrumented_profile_path, True)
        instrumented_profile = read_json(instrumented_profile_path)
        compare_loads(baseline_profile, instrumented_profile)
        evidence["instrumented_profile"] = str(instrumented_profile_path)
        evidence["profile_exact_load_match"] = True

        # Keep both process profiles intact, and place the derived per-regime phase means in
        # one report for review. Baseline batch samples remain separate from instrumented phases.
        instrumented_rows = phase_summary(instrumented_profile)
        baseline_rows = baseline_profile["rows"]
        for summary, baseline_row in zip(instrumented_rows, baseline_rows, strict=True):
            summary["baseline_direct_external_us_per_call_batches"] = baseline_row[
                "direct_external_us_per_call_batches"]
            summary["baseline_direct_external_us_per_call_median"] = median(
                baseline_row["direct_external_us_per_call_batches"])
            summary["baseline_adapter_external_us_per_call_batches"] = baseline_row[
                "adapter_external_us_per_call_batches"]
            summary["baseline_adapter_external_us_per_call_median"] = median(
                baseline_row["adapter_external_us_per_call_batches"])
        evidence["phase_summary"] = instrumented_rows
        evidence["status"] = "pass"
        evidence_path.write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        print(f"E0b6p native attribution passed; evidence: {evidence_path}")
        for row in instrumented_rows:
            phase = row["phase_ns_per_call_median_clock_corrected"]
            print(
                f"{row['regime']}: model decode {phase['model_decode_ns']:.0f} ns, "
                f"validate {phase['validate_ns']:.0f} ns, axial wake {phase['wake_ns']:.0f} ns, "
                f"profile {phase['profile_ns']:.0f} ns, swirl {phase['swirl_ns']:.0f} ns, "
                f"method {row['instrumented_method_and_phase_ns_per_call_median_raw']['method_total_ns']:.0f} ns"
            )
        if args.keep_work:
            print(f"Staged app retained at: {work_project}")
    except Exception as error:
        evidence["status"] = "fail"
        evidence["error"] = str(error)
        evidence_path.write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        raise SystemExit(f"E0b6p native attribution failed; evidence: {evidence_path}\n{error}") from error
    finally:
        if temporary is not None:
            temporary.cleanup()


if __name__ == "__main__":
    main()
