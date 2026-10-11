#!/usr/bin/env python3
"""Run the bounded AS-04 same-engine aircraft lifecycle comparison."""

from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
import math
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DRIVER = Path(__file__).with_name("verify.gd")
DEFAULT_ENGINE = ROOT / ".tools" / "Godot_v4.7.2-stable_win64_console.exe"
DEFAULT_BASELINE = ROOT / ".tools" / "as-baseline" / "app"
DEFAULT_CANDIDATE = ROOT / ".tools" / "as-integration" / "app"
DEFAULT_EVIDENCE = ROOT / "docs" / "research" / "aircraft-standardization" / "AS-04" / "evidence"
EXPECTED_KEYS = {
    "jensen-das-ugly-stik-60",
    "gp-extra-300s-60",
    "p51d-mustang-120",
    "sebart-avanti-s-a200-p100rx",
    "synthetic_stik_electric_4s",
    "synthetic_stik_electric_6s",
    "synthetic_stik_electric_4s_battery",
    "synthetic_stik_electric_6s_battery",
}
ARRAY_KEYS = ("state", "aux", "inputs", "continuous", "modes")
ENGINE_ERROR = re.compile(r"(?:SCRIPT ERROR:|Parse Error:|ERROR:)")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_manifest(app: Path) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    for path in sorted(app.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(app)
        if ".godot" in relative.parts or ".git" in relative.parts:
            continue
        if any(part.lower() == "captures" for part in relative.parts):
            continue
        if path.suffix.lower() in {".uid", ".import", ".tmp", ".log"}:
            continue
        entries.append({
            "path": relative.as_posix(),
            "size": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    encoded = "\n".join(f"{item['path']} {item['sha256']}" for item in entries).encode("utf-8")
    return {
        "app": str(app),
        "file_count": len(entries),
        "manifest_sha256": hashlib.sha256(encoded).hexdigest(),
        "files": entries,
    }


def json_write(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")


def godot_path(path: Path) -> str:
    return path.resolve().as_posix()


def run_probe(label: str, app: Path, engine: Path, out_dir: Path, timeout: int) -> dict[str, Any]:
    report_path = out_dir / f"{label}.json"
    log_path = out_dir / f"{label}.log"
    before = source_manifest(app)
    command = [
        str(engine),
        "--headless",
        "--path",
        str(app),
        "--script",
        str(DRIVER),
        "--",
        f"--out={godot_path(report_path)}",
    ]
    started = time.perf_counter()
    timed_out = False
    try:
        process = subprocess.run(
            command,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
        log = process.stdout
        return_code = process.returncode
    except subprocess.TimeoutExpired as error:
        timed_out = True
        partial = error.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        log = str(partial) + f"\nAS-04 TIMEOUT after {timeout}s\n"
        return_code = None
    elapsed = time.perf_counter() - started
    log_path.write_text(log, encoding="utf-8")
    after = source_manifest(app)
    result: dict[str, Any] = {
        "label": label,
        "app": str(app),
        "command": command,
        "elapsed_seconds": round(elapsed, 3),
        "timeout_seconds": timeout,
        "timed_out": timed_out,
        "return_code": return_code,
        "engine_errors": ENGINE_ERROR.findall(log),
        "source_unchanged_during_run": before["manifest_sha256"] == after["manifest_sha256"],
        "source_before": before,
        "source_after": after,
        "report": str(report_path),
        "log": str(log_path),
    }
    if report_path.is_file():
        try:
            result["probe"] = json.loads(report_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            result["report_error"] = str(error)
    else:
        result["report_error"] = "Godot did not create the probe report"
    json_write(out_dir / f"{label}_provenance.json", result)
    return result


def value_differences(left: Any, right: Any, prefix: str = "$") -> list[dict[str, Any]]:
    if type(left) is not type(right):
        return [{"path": prefix, "baseline": left, "candidate": right}]
    if isinstance(left, dict):
        differences: list[dict[str, Any]] = []
        for key in sorted(set(left) | set(right)):
            if key not in left or key not in right:
                differences.append({
                    "path": f"{prefix}.{key}",
                    "baseline": left.get(key, "<missing>"),
                    "candidate": right.get(key, "<missing>"),
                })
            else:
                differences.extend(value_differences(left[key], right[key], f"{prefix}.{key}"))
        return differences
    if isinstance(left, list):
        if len(left) != len(right):
            return [{"path": prefix, "baseline_length": len(left), "candidate_length": len(right)}]
        differences = []
        for index, (a, b) in enumerate(zip(left, right)):
            differences.extend(value_differences(a, b, f"{prefix}[{index}]"))
        return differences
    if left != right:
        return [{"path": prefix, "baseline": left, "candidate": right}]
    return []


def finite_tree(value: Any, path: str = "$") -> list[str]:
    failures: list[str] = []
    if isinstance(value, float):
        if value != value or value in (float("inf"), float("-inf")):
            failures.append(path)
    elif value in ("NaN", "Infinity", "-Infinity"):
        failures.append(path)
    elif isinstance(value, dict):
        for key, child in value.items():
            failures.extend(finite_tree(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            failures.extend(finite_tree(child, f"{path}[{index}]"))
    return failures


def validate_probe(label: str, result: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if result.get("timed_out"):
        failures.append(f"{label}: engine timed out")
    if result.get("return_code") != 0:
        failures.append(f"{label}: engine exit was {result.get('return_code')}")
    if result.get("engine_errors"):
        failures.append(f"{label}: Godot log contains errors: {result['engine_errors']}")
    if not result.get("source_unchanged_during_run"):
        failures.append(f"{label}: app source changed while the probe was running")
    probe = result.get("probe")
    if not isinstance(probe, dict):
        failures.append(f"{label}: missing valid JSON probe")
        return failures
    if probe.get("format") != "openrc-as04-flight-probe-v2":
        failures.append(f"{label}: unexpected probe format {probe.get('format')!r}")
    if not isinstance(probe.get("timing"), dict):
        failures.append(f"{label}: missing timing-method metadata")
    cases = probe.get("cases")
    if not isinstance(cases, list):
        failures.append(f"{label}: missing cases array")
        return failures
    by_key = {str(case.get("key")): case for case in cases if isinstance(case, dict)}
    if set(by_key) != EXPECTED_KEYS:
        failures.append(f"{label}: case set mismatch (missing={sorted(EXPECTED_KEYS - set(by_key))}, extra={sorted(set(by_key) - EXPECTED_KEYS)})")
    if probe.get("failures"):
        failures.append(f"{label}: GDScript probe failures: {probe['failures']}")
    for key, case in by_key.items():
        if not case.get("ok"):
            failures.append(f"{label}/{key}: probe marked case unsuccessful")
        if case.get("selected_id") != case.get("model_id"):
            failures.append(f"{label}/{key}: selected ID differs from loaded model ID")
        if not case.get("session_model_matches_loader"):
            failures.append(f"{label}/{key}: session model differs from loader output")
        if case.get("session_capabilities_match_loader") is not True or case.get("session_convention_id_matches_loader") is not True:
            failures.append(f"{label}/{key}: session changed capability or convention identity")
        if case.get("kind") == "electric" and case.get("shaft_integrator") != "coupled-rk4":
            failures.append(f"{label}/{key}: electric configuration did not use coupled-rk4")
        for field in ("reset_matches_initial", "checkpoint_restore_pauses", "checkpoint_replay_matches", "malformed_reload_rollback"):
            if case.get(field) is not True:
                failures.append(f"{label}/{key}: {field} did not pass")
        if key != "jensen-das-ugly-stik-60" and case.get("prior_checkpoint_rejected_atomically") is not True:
            failures.append(f"{label}/{key}: prior-model checkpoint was not refused atomically")
        model_numeric = case.get("model_numeric")
        raw_numeric = case.get("raw_numeric")
        if not isinstance(model_numeric, dict) or not model_numeric:
            failures.append(f"{label}/{key}: no normalized numeric model captured")
        if not isinstance(raw_numeric, dict) or not raw_numeric:
            failures.append(f"{label}/{key}: no numeric source data captured")
        if not isinstance(case.get("model_capabilities"), dict):
            failures.append(f"{label}/{key}: model capabilities metadata missing")
        if not isinstance(case.get("load_validation_us_samples"), list) or len(case["load_validation_us_samples"]) != 7:
            failures.append(f"{label}/{key}: expected seven repeated load-validation timings")
        for nonfinite in finite_tree(model_numeric):
            failures.append(f"{label}/{key}: nonfinite normalized value at {nonfinite}")
        if not isinstance(case.get("model_mass_kg"), (int, float)) or case["model_mass_kg"] <= 0:
            failures.append(f"{label}/{key}: invalid normalized mass")
        if len(case.get("model_cg_le", [])) != 3 or len(case.get("model_inertia", [])) < 6:
            failures.append(f"{label}/{key}: normalized CG/inertia summary is incomplete")
        samples = case.get("samples")
        if not isinstance(samples, list) or len(samples) < 2:
            failures.append(f"{label}/{key}: manual flight sequence samples are missing")
            continue
        for sample in samples:
            sim = sample.get("simulation", {})
            if not isinstance(sim, dict) or any(not isinstance(sim.get(name), str) for name in ARRAY_KEYS):
                failures.append(f"{label}/{key}: packed simulation arrays missing at tick {sample.get('tick')}")
                break
        tick_timings = case.get("steady_tick_us_samples")
        if not isinstance(tick_timings, list) or len(tick_timings) != max(0, len(samples) - 21):
            failures.append(f"{label}/{key}: steady tick timing count does not match the recorded run")
    return failures


def compare_probes(baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    old = baseline["probe"]
    new = candidate["probe"]
    comparison: dict[str, Any] = {
        "format": "openrc-as04-comparison-v1",
        "baseline_engine": old.get("godot"),
        "candidate_engine": new.get("godot"),
        "physics_ticks_per_second": old.get("physics_ticks_per_second"),
        "cases": [],
        "failures": [],
        "comparison_policy": "exact numeric normalized models and exact per-tick float64 array bytes on the same engine/platform; source hashes are provenance only",
        "raw_numeric_policy": "source numeric differences are reported for review, not treated as runtime parity failures",
        "timing_policy": "descriptive same-host measurements only; no hard tick deadline or timing-based pass/fail threshold",
    }
    if old.get("godot") != new.get("godot"):
        comparison["failures"].append("engine versions differ")
    if old.get("physics_ticks_per_second") != new.get("physics_ticks_per_second"):
        comparison["failures"].append("physics tick rates differ")
    old_by_key = {case["key"]: case for case in old.get("cases", [])}
    new_by_key = {case["key"]: case for case in new.get("cases", [])}
    if set(old_by_key) != set(new_by_key):
        comparison["failures"].append("baseline and candidate case sets differ")
    for key in sorted(set(old_by_key) & set(new_by_key)):
        a = old_by_key[key]
        b = new_by_key[key]
        raw_differences = value_differences(a.get("raw_numeric"), b.get("raw_numeric"))
        entry: dict[str, Any] = {
            "key": key,
            "kind": a.get("kind"),
            "baseline_model_id": a.get("model_id"),
            "candidate_model_id": b.get("model_id"),
            "baseline_start_speed_mps": a.get("start_speed_mps"),
            "candidate_start_speed_mps": b.get("start_speed_mps"),
            "baseline_sample_count": len(a.get("samples", [])),
            "candidate_sample_count": len(b.get("samples", [])),
            "model_numeric_equal": a.get("model_numeric") == b.get("model_numeric"),
            "model_metadata": {
                "baseline_capabilities": a.get("model_capabilities", {}),
                "candidate_capabilities": b.get("model_capabilities", {}),
                "baseline_convention_id": a.get("model_convention_id", ""),
                "candidate_convention_id": b.get("model_convention_id", ""),
                "baseline_data_sha256": a.get("model_data_sha256", ""),
                "candidate_data_sha256": b.get("model_data_sha256", ""),
            },
            "raw_numeric_equal": a.get("raw_numeric") == b.get("raw_numeric"),
            "raw_numeric_difference_count": len(raw_differences),
            "raw_numeric_changed_paths": sorted({difference["path"] for difference in raw_differences}),
            "raw_numeric_differences": raw_differences[:30],
            "samples_equal": True,
            "sample_mismatches": [],
            "baseline_lifecycle": {},
            "candidate_lifecycle": {},
        }
        if not entry["model_numeric_equal"]:
            entry["model_differences"] = value_differences(a.get("model_numeric"), b.get("model_numeric"))[:30]
        old_samples = a.get("samples", [])
        new_samples = b.get("samples", [])
        if len(old_samples) != len(new_samples):
            entry["samples_equal"] = False
            entry["sample_mismatches"].append({
                "path": "samples.length",
                "baseline": len(old_samples),
                "candidate": len(new_samples),
            })
        for index, (old_sample, new_sample) in enumerate(zip(old_samples, new_samples)):
            for field in ("tick", "pilot_input"):
                if old_sample.get(field) != new_sample.get(field):
                    entry["samples_equal"] = False
                    entry["sample_mismatches"].append({
                        "path": f"samples[{index}].{field}",
                        "baseline": old_sample.get(field),
                        "candidate": new_sample.get(field),
                    })
            old_sim = old_sample.get("simulation", {})
            new_sim = new_sample.get("simulation", {})
            for field in ("tick", "time_s", *ARRAY_KEYS):
                if old_sim.get(field) != new_sim.get(field):
                    entry["samples_equal"] = False
                    mismatch: dict[str, Any] = {"path": f"samples[{index}].simulation.{field}"}
                    if field in ARRAY_KEYS:
                        mismatch["baseline_bytes"] = len(old_sim.get(field, "")) // 2
                        mismatch["candidate_bytes"] = len(new_sim.get(field, "")) // 2
                    else:
                        mismatch["baseline"] = old_sim.get(field)
                        mismatch["candidate"] = new_sim.get(field)
                    entry["sample_mismatches"].append(mismatch)
                    if len(entry["sample_mismatches"]) >= 30:
                        break
            if len(entry["sample_mismatches"]) >= 30:
                break
        lifecycle_fields = (
            "reset_matches_initial",
            "checkpoint_restore_pauses",
            "checkpoint_replay_matches",
            "prior_checkpoint_rejected_atomically",
            "malformed_reload_rollback",
        )
        entry["baseline_lifecycle"] = {field: a.get(field) for field in lifecycle_fields}
        entry["candidate_lifecycle"] = {field: b.get(field) for field in lifecycle_fields}
        if not entry["model_numeric_equal"]:
            comparison["failures"].append(f"{key}: normalized numeric model differs")
        if not entry["samples_equal"]:
            comparison["failures"].append(f"{key}: in-engine flight state/aux/input/continuous/mode differs")
        comparison["cases"].append(entry)
    return comparison


def percentile(values: list[int], fraction: float) -> int | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def summarize_timing(values: list[int]) -> dict[str, Any]:
    return {
        "sample_count": len(values),
        "p50_us": percentile(values, 0.50),
        "p95_us": percentile(values, 0.95),
        "min_us": min(values) if values else None,
        "max_us": max(values) if values else None,
    }


def aggregate_performance(runs_by_label: dict[str, list[dict[str, Any]]], run_order: list[list[str]]) -> dict[str, Any]:
    summaries: list[dict[str, Any]] = []
    for key in sorted(EXPECTED_KEYS):
        row: dict[str, Any] = {"key": key}
        for label in ("baseline", "candidate"):
            load_values: list[int] = []
            tick_values: list[int] = []
            for run in runs_by_label[label]:
                case = next((case for case in run.get("probe", {}).get("cases", []) if case.get("key") == key), {})
                load_values.extend(int(value) for value in case.get("load_validation_us_samples", []))
                tick_values.extend(int(value) for value in case.get("steady_tick_us_samples", []))
            row[label] = {
                "load_validation_us": summarize_timing(load_values),
                "steady_tick_us": summarize_timing(tick_values),
            }
        old_load = row["baseline"]["load_validation_us"]["p50_us"]
        new_load = row["candidate"]["load_validation_us"]["p50_us"]
        old_tick = row["baseline"]["steady_tick_us"]["p50_us"]
        new_tick = row["candidate"]["steady_tick_us"]["p50_us"]
        row["candidate_over_baseline_p50_ratio"] = {
            "load_validation": new_load / old_load if old_load else None,
            "steady_tick": new_tick / old_tick if old_tick else None,
        }
        summaries.append(row)
    return {
        "method": "alternating Godot process order by round; aggregate seven warm AircraftData.load_file() timings and post-warmup Simulation.step() timings per case",
        "run_order": run_order,
        "steady_tick_warmup_discarded": 20,
        "timing_policy": "descriptive only; no host-independent deadline or timing-based pass/fail threshold",
        "aircraft": summaries,
    }


def self_test_comparator() -> None:
    """Prove the acceptance comparator surfaces both a model change and one changed state byte."""
    probe = {
        "godot": "self-test",
        "physics_ticks_per_second": 240,
        "cases": [{
            "key": "jensen-das-ugly-stik-60",
            "kind": "catalog",
            "model_id": "jensen-das-ugly-stik-60",
            "start_speed_mps": 15.0,
            "model_numeric": {"mass_kg": 2.885},
            "raw_numeric": {"aero": {"CLadot": 1.25}},
            "model_capabilities": {},
            "model_convention_id": "",
            "model_data_sha256": "",
            "samples": [{
                "tick": 0,
                "pilot_input": [0.0, 0.0, 0.0, 0.0],
                "simulation": {"tick": 0, "time_s": 0.0, **{field: "00" for field in ARRAY_KEYS}},
            }],
        }],
    }
    baseline = {"probe": deepcopy(probe)}
    candidate_probe = deepcopy(probe)
    candidate_probe["cases"][0]["model_numeric"]["mass_kg"] = 2.886
    candidate_probe["cases"][0]["samples"][0]["simulation"]["state"] = "01"
    comparison = compare_probes(baseline, {"probe": candidate_probe})
    case = comparison["cases"][0]
    if case["model_numeric_equal"] or case["samples_equal"]:
        raise AssertionError("comparator self-check failed to detect the deliberate model/state changes")
    if not case.get("model_differences") or not case.get("sample_mismatches"):
        raise AssertionError("comparator self-check failed to retain mismatch evidence")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE, help="pre-migration app directory")
    parser.add_argument("--candidate", type=Path, default=DEFAULT_CANDIDATE, help="app directory under review")
    parser.add_argument("--engine", type=Path, default=DEFAULT_ENGINE, help="pinned Godot console executable")
    parser.add_argument("--timeout", type=int, default=180, help="per-app engine timeout in seconds (1-180)")
    parser.add_argument("--alternating-runs", type=int, default=2,
                        help="paired rounds; order alternates baseline/candidate then candidate/baseline (1-3)")
    parser.add_argument("--run-id", default=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"), help="unique evidence directory name")
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE, help="directory holding durable run evidence")
    return parser.parse_args()


def resolve(path: Path) -> Path:
    return path if path.is_absolute() else (ROOT / path).resolve()


def main() -> int:
    args = parse_args()
    try:
        self_test_comparator()
    except AssertionError as error:
        print(f"AS-04 comparator self-test failed: {error}", file=sys.stderr)
        return 2
    if not 1 <= args.timeout <= 180:
        print("--timeout must be between 1 and 180 seconds", file=sys.stderr)
        return 2
    if not 1 <= args.alternating_runs <= 3:
        print("--alternating-runs must be between 1 and 3", file=sys.stderr)
        return 2
    baseline = resolve(args.baseline)
    candidate = resolve(args.candidate)
    engine = resolve(args.engine)
    evidence_root = resolve(args.evidence_root)
    out_dir = evidence_root / args.run_id
    for label, path in (("baseline", baseline), ("candidate", candidate), ("engine", engine), ("driver", DRIVER)):
        if not path.exists():
            print(f"missing {label}: {path}", file=sys.stderr)
            return 2
    if not (baseline / "project.godot").is_file() or not (candidate / "project.godot").is_file():
        print("baseline and candidate must both contain project.godot", file=sys.stderr)
        return 2
    try:
        out_dir.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        print(f"evidence directory already exists: {out_dir}", file=sys.stderr)
        return 2

    engine_info = {
        "path": str(engine),
        "sha256": sha256_file(engine),
        "driver": str(DRIVER),
        "driver_sha256": sha256_file(DRIVER),
        "run_id": args.run_id,
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "comparator_self_test": "pass: detected one deliberate numeric model and state-byte change",
        "alternating_runs": args.alternating_runs,
    }
    json_write(out_dir / "run.json", engine_info)
    runs_by_label: dict[str, list[dict[str, Any]]] = {"baseline": [], "candidate": []}
    run_order: list[list[str]] = []
    for round_index in range(args.alternating_runs):
        order = ["baseline", "candidate"] if round_index % 2 == 0 else ["candidate", "baseline"]
        run_order.append(order)
        for label in order:
            app = baseline if label == "baseline" else candidate
            run_name = f"{label}_r{round_index + 1}"
            print(f"AS-04 {run_name}: {app}")
            runs_by_label[label].append(run_probe(run_name, app, engine, out_dir, args.timeout))

    failures: list[str] = []
    for label, runs in runs_by_label.items():
        for index, run in enumerate(runs, start=1):
            failures.extend(validate_probe(f"{label}_r{index}", run))
        manifest_ids = {run.get("source_before", {}).get("manifest_sha256") for run in runs}
        if len(manifest_ids) > 1:
            failures.append(f"{label}: source manifest changed between alternating measurement runs")

    baseline_primary = runs_by_label["baseline"][0]
    candidate_primary = runs_by_label["candidate"][0]
    if "probe" in baseline_primary and "probe" in candidate_primary:
        comparison = compare_probes(baseline_primary, candidate_primary)
        failures.extend(comparison["failures"])
        for label, runs in runs_by_label.items():
            first = runs[0]
            for repeat_index, repeat in enumerate(runs[1:], start=2):
                if "probe" in first and "probe" in repeat:
                    repeat_comparison = compare_probes(first, repeat)
                    if repeat_comparison["failures"]:
                        failures.append(f"{label}_r{repeat_index}: repeat flight/model output is not deterministic")
        comparison["failures"] = failures
        comparison["performance"] = aggregate_performance(runs_by_label, run_order)
        comparison["baseline_source_manifest_sha256"] = baseline_primary["source_before"]["manifest_sha256"]
        comparison["candidate_source_manifest_sha256"] = candidate_primary["source_before"]["manifest_sha256"]
        comparison["engine_sha256"] = engine_info["sha256"]
        comparison["driver_sha256"] = engine_info["driver_sha256"]
        json_write(out_dir / "comparison.json", comparison)
    else:
        comparison = {"format": "openrc-as04-comparison-v1", "failures": failures}
        json_write(out_dir / "comparison.json", comparison)
    summary = {
        "run_id": args.run_id,
        "ok": not failures,
        "failures": failures,
        "evidence": str(out_dir),
        "alternating_runs": args.alternating_runs,
        "baseline_elapsed_seconds": [run["elapsed_seconds"] for run in runs_by_label["baseline"]],
        "candidate_elapsed_seconds": [run["elapsed_seconds"] for run in runs_by_label["candidate"]],
        "cases_compared": len(comparison.get("cases", [])),
        "model_numeric_equal_cases": sum(bool(case.get("model_numeric_equal")) for case in comparison.get("cases", [])),
        "flight_trace_equal_cases": sum(bool(case.get("samples_equal")) for case in comparison.get("cases", [])),
        "comparator_self_test": engine_info["comparator_self_test"],
    }
    json_write(out_dir / "summary.json", summary)
    summary_lines = [
        f"# AS-04 verification run {args.run_id}",
        "",
        f"Status: {'PASS' if summary['ok'] else 'FAIL'}.",
        "",
        f"- Baseline: `{baseline}` (run times {summary['baseline_elapsed_seconds']})",
        f"- Candidate: `{candidate}` (run times {summary['candidate_elapsed_seconds']})",
        f"- Cases: {summary['cases_compared']} compared; {summary['model_numeric_equal_cases']} exact normalized-model matches; {summary['flight_trace_equal_cases']} exact flight-trace matches.",
        f"- Godot: `{engine}` SHA-256 `{engine_info['sha256']}`.",
        f"- Driver SHA-256: `{engine_info['driver_sha256']}`.",
        f"- Timing: {args.alternating_runs} paired rounds with alternating process order; per-aircraft validation-load and steady `Simulation.step()` p50/p95 are in `comparison.json` (descriptive only, no timing gate).",
        "- Comparator self-check: deliberate model-value and state-byte changes were detected before app runs.",
        "- Retained logs: one `.log` and raw `.json` probe per app/round; per-run provenance includes source manifests.",
    ]
    if failures:
        summary_lines.extend(["", "Failures:", *[f"- {failure}" for failure in failures]])
    (out_dir / "README.md").write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
    print(f"AS-04 {'PASS' if summary['ok'] else 'FAIL'}: {summary['cases_compared']} cases; evidence {out_dir}")
    if failures:
        for failure in failures:
            print(f"  - {failure}")
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
