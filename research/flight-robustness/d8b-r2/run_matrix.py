#!/usr/bin/env python3
"""Run and compare the D8b-R2b FlightSession keyboard research matrix."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import gzip
import json
import math
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
RUNNER = ROOT / "research" / "flight-robustness" / "d8b-r2" / "flight_matrix.gd"
DEFAULT_MODEL = ROOT / "app" / "data" / "aircraft" / "jensen_ugly_stik_60.json"
MATRIX_ROOT = ROOT / "docs" / "research" / "flight-robustness" / "D8b-R2" / "implementation" / "matrix"
SOURCE_FILES = [
    "research/flight-robustness/d8b-r2/flight_matrix.gd",
    "research/flight-robustness/d8b-r2/run_matrix.py",
    "app/sim/flight_session.gd",
    "app/sim/simulation.gd",
    "app/sim/scenarios.gd",
    "app/input/commands.gd",
    "app/input/keyboard.gd",
    "app/physics/aircraft_data.gd",
    "app/physics/aero.gd",
    "app/physics/air_data.gd",
    "app/physics/dynamics.gd",
    "app/physics/propulsion.gd",
    "app/physics/rigid_body.gd",
    "app/physics/ground_contact.gd",
    "app/physics/wash_transport.gd",
    "app/physics/wind_field.gd",
    "app/physics/wind_turbulence.gd",
    "app/spec.gd",
]
METRICS = [
    "max_airspeed_mps",
    "max_alpha_rad",
    "max_abs_beta_rad",
    "max_abs_p_radps",
    "max_abs_q_radps",
    "max_abs_r_radps",
    "max_abs_cross_track_m",
    "max_normal_load_factor_aero",
    "max_normal_load_factor_total",
    "min_altitude_m",
]
PHYSICS_APP_ROOTS = ("sim", "input", "physics", "aircraft", "data")
PHYSICS_FIXED_FILES = ("app/spec.gd", "app/project.godot")
MEASUREMENT_TOOL_FILES = (
    "research/flight-robustness/d8b-r2/flight_matrix.gd",
    "research/flight-robustness/d8b-r2/run_matrix.py",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_hash(files: dict[str, str]) -> str:
    canonical = json.dumps(files, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def physics_dependency_files(files: dict[str, str]) -> dict[str, str]:
    roots = tuple(f"app/{name}/" for name in PHYSICS_APP_ROOTS)
    fixed = set(PHYSICS_FIXED_FILES)
    return {
        path: digest for path, digest in files.items()
        if path in fixed or path.startswith(roots)
    }


def git_commit() -> str:
    try:
        completed = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        return completed.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unavailable"


def fingerprints(model_copy: Path) -> dict[str, Any]:
    files: dict[str, str] = {}
    missing: list[str] = []
    source_paths = {ROOT / relative for relative in SOURCE_FILES}
    app_root = ROOT / "app"
    source_paths.update(app_root.rglob("*.gd"))
    source_paths.update((app_root / "data").rglob("*.json"))
    source_paths.add(app_root / "project.godot")
    for path in sorted(source_paths, key=lambda item: item.as_posix()):
        relative = path.relative_to(ROOT).as_posix()
        if path.is_file():
            files[relative] = sha256(path)
        else:
            missing.append(relative)
    files[model_copy.resolve().as_posix()] = sha256(model_copy)
    physics_files = physics_dependency_files(files)
    tool_files = {relative: files[relative] for relative in MEASUREMENT_TOOL_FILES if relative in files}
    return {
        "git_commit": git_commit(),
        "files_sha256": files,
        "missing_source_files": missing,
        "aircraft_source_sha256": files[model_copy.resolve().as_posix()],
        "source_hash_sha256": canonical_hash(files),
        "physics_dependency_files_sha256": physics_files,
        "physics_dependency_hash_sha256": canonical_hash(physics_files),
        "measurement_tool_files_sha256": tool_files,
        "measurement_tool_hash_sha256": canonical_hash(tool_files),
    }


def default_godot() -> Path:
    if platform.system() == "Windows":
        name = "Godot_v4.7.2-stable_win64_console.exe"
    elif platform.system() == "Darwin":
        name = "Godot_v4.7.2-stable_macos.universal"
    else:
        name = "Godot_v4.7.2-stable_linux.x86_64"
    return ROOT / ".tools" / name


def iso_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def read_run(path: Path) -> dict[str, Any]:
    if path.is_dir():
        candidates = [path / "run_manifest.json", path / "matrix_manifest.json"]
        for candidate in candidates:
            if candidate.is_file():
                path = candidate
                break
    data = json.loads(path.read_text(encoding="utf-8"))
    if "run" in data and isinstance(data["run"], dict):
        return data["run"]
    return data


def file_digest(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def compress_traces(run: dict[str, Any], output: Path, selected_ids: set[str]) -> None:
    cases = run.get("cases", [])
    available = {str(case.get("case_id", "")) for case in cases}
    unknown = selected_ids - available
    if unknown:
        raise ValueError("unknown trace case ID(s): " + ", ".join(sorted(unknown)))
    retain_all = not selected_ids
    inventory: list[dict[str, Any]] = []
    for case in cases:
        filename = str(case.get("trace_file", ""))
        case_id = str(case.get("case_id", ""))
        if not filename:
            case["trace_retained"] = False
            case["trace_storage"] = "summary_only"
            continue
        if Path(filename).name != filename or not filename.endswith(".csv"):
            raise ValueError(f"unexpected trace path in run manifest: {filename!r}")
        raw = output / filename
        if not raw.is_file():
            raise FileNotFoundError(f"missing generated trace: {raw}")
        raw_hash, raw_bytes = file_digest(raw)
        keep = retain_all or case_id in selected_ids
        entry: dict[str, Any] = {
            "case_id": case_id,
            "samples": case.get("samples"),
            "expected_samples": case.get("expected_samples"),
            "complete": bool(case.get("complete", False)),
            "finite": bool(case.get("finite", False)),
            "generated_sha256": raw_hash,
            "generated_bytes": raw_bytes,
            "trace_retained": keep,
        }
        case["trace_generated_sha256"] = raw_hash
        case["trace_generated_bytes"] = raw_bytes
        case["trace_retained"] = keep
        if keep:
            compressed = output / f"{filename}.gz"
            with raw.open("rb") as source, compressed.open("wb") as compressed_stream:
                with gzip.GzipFile(fileobj=compressed_stream, mode="wb", compresslevel=9, mtime=0) as target:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        target.write(chunk)
            expanded_hash = hashlib.sha256()
            expanded_bytes = 0
            with gzip.open(compressed, "rb") as expanded:
                for chunk in iter(lambda: expanded.read(1024 * 1024), b""):
                    expanded_hash.update(chunk)
                    expanded_bytes += len(chunk)
            if (expanded_hash.hexdigest(), expanded_bytes) != (raw_hash, raw_bytes):
                compressed.unlink(missing_ok=True)
                raise ValueError(f"lossless gzip verification failed for {filename}")
            compressed_hash, compressed_bytes = file_digest(compressed)
            raw.unlink()
            case["trace_uncompressed_file"] = filename
            case["trace_file"] = compressed.name
            case["trace_compression"] = "gzip"
            case["trace_uncompressed_sha256"] = raw_hash
            case["trace_uncompressed_bytes"] = raw_bytes
            case["trace_compressed_sha256"] = compressed_hash
            case["trace_compressed_bytes"] = compressed_bytes
            case["trace_storage"] = "gzip"
            entry.update({
                "file": compressed.name,
                "compression": "gzip",
                "compressed_sha256": compressed_hash,
                "compressed_bytes": compressed_bytes,
                "lossless_verified": True,
            })
        else:
            raw.unlink()
            case["trace_uncompressed_file"] = ""
            case["trace_file"] = ""
            case["trace_storage"] = "summary_only"
            entry.update({"file": None, "compression": None, "lossless_verified": None})
        inventory.append(entry)
    kept_ids = [entry["case_id"] for entry in inventory if entry["trace_retained"]]
    run["trace_storage"] = {
        "format": "lossless CSV gzip; omitted cases retain per-case summaries and generated trace hashes",
        "lossless_verified": all(entry.get("lossless_verified") is not False for entry in inventory if entry["trace_retained"]),
        "retained_case_ids": kept_ids,
        "retained_case_count": len(kept_ids),
        "generated_case_count": len(inventory),
    }
    (output / "trace_inventory.json").write_text(json.dumps({
        "format": "openrc-d8b-r2b-trace-inventory-v1",
        "label": run.get("label", "unknown"),
        "generated_case_count": len(inventory),
        "retained_case_count": len(kept_ids),
        "retained_case_ids": kept_ids,
        "generated_total_bytes": sum(int(entry["generated_bytes"]) for entry in inventory),
        "retained_compressed_bytes": sum(int(entry.get("compressed_bytes", 0)) for entry in inventory),
        "cases": inventory,
    }, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def numeric_value(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return parsed if math.isfinite(parsed) else None


def flatten_numeric(value: Any, prefix: str = "") -> dict[str, float]:
    found: dict[str, float] = {}
    if isinstance(value, dict):
        for key, child in value.items():
            found.update(flatten_numeric(child, f"{prefix}.{key}" if prefix else str(key)))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.update(flatten_numeric(child, f"{prefix}.{index}" if prefix else str(index)))
    else:
        parsed = numeric_value(value)
        if parsed is not None and prefix:
            found[prefix] = parsed
    return found


def _trace_rows(directory: Path, case: dict[str, Any], common_hz: int) -> dict[int, dict[str, str]]:
    filename = str(case.get("trace_file", ""))
    if not filename or Path(filename).name != filename:
        raise ValueError(f"case {case.get('case_id')} has no retained trace")
    path = directory / filename
    if path.suffix == ".gz":
        stream = gzip.open(path, "rt", newline="", encoding="utf-8")
    else:
        stream = path.open("r", newline="", encoding="utf-8")
    rows: dict[int, dict[str, str]] = {}
    with stream:
        for row in csv.DictReader(stream):
            time_s = numeric_value(row.get("state_time_s"))
            if time_s is None:
                continue
            slot = round(time_s * common_hz)
            if abs(time_s - slot / common_hz) <= 1e-9:
                rows[slot] = row
    return rows


def compare_common_time_case(baseline_dir: Path, current_dir: Path, baseline: dict[str, Any],
                             current: dict[str, Any], case_id: str) -> dict[str, Any]:
    left_case = next((case for case in baseline.get("cases", []) if case.get("case_id") == case_id), None)
    right_case = next((case for case in current.get("cases", []) if case.get("case_id") == case_id), None)
    if left_case is None or right_case is None:
        raise ValueError(f"common-time case is missing from a run: {case_id}")
    hz_left = int(baseline.get("physics_hz", 0))
    hz_right = int(current.get("physics_hz", 0))
    if hz_left <= 0 or hz_right <= 0:
        raise ValueError("both manifests must contain a positive physics_hz")
    common_hz = math.gcd(hz_left, hz_right)
    left_rows = _trace_rows(baseline_dir, left_case, common_hz)
    right_rows = _trace_rows(current_dir, right_case, common_hz)
    common_slots = sorted(set(left_rows) & set(right_rows))
    if not common_slots:
        raise ValueError(f"no common timestamps for {case_id}")
    excluded = {
        "case_id", "source_hash_sha256", "sample_phase", "tick", "state_time_s", "load_time_s",
        "scenario_phase", "engine_running", "wing_strip_available", "wing_strip_json", "finite_sample", "error",
    }
    accum: dict[str, dict[str, float]] = {}
    finite_pairs = 0
    nonfinite_pairs = 0
    max_time_mismatch = 0.0

    def add_delta(name: str, left_value: float | None, right_value: float | None) -> None:
        nonlocal finite_pairs, nonfinite_pairs
        if left_value is None and right_value is None:
            return
        if left_value is None or right_value is None:
            nonfinite_pairs += 1
            return
        delta = right_value - left_value
        if not math.isfinite(delta):
            nonfinite_pairs += 1
            return
        finite_pairs += 1
        state = accum.setdefault(name, {"max_abs_delta": 0.0, "sum_squared_delta": 0.0, "last_abs_delta": 0.0, "samples": 0.0})
        state["max_abs_delta"] = max(state["max_abs_delta"], abs(delta))
        state["sum_squared_delta"] += delta * delta
        state["last_abs_delta"] = abs(delta)
        state["samples"] += 1.0

    for slot in common_slots:
        left = left_rows[slot]
        right = right_rows[slot]
        left_time = numeric_value(left.get("state_time_s"))
        right_time = numeric_value(right.get("state_time_s"))
        if left_time is not None and right_time is not None:
            max_time_mismatch = max(max_time_mismatch, abs(left_time - right_time))
        for field in (set(left) & set(right)) - excluded:
            add_delta(field, numeric_value(left.get(field)), numeric_value(right.get(field)))
        try:
            left_strips = flatten_numeric(json.loads(left.get("wing_strip_json", "[]")), "wing_strip")
            right_strips = flatten_numeric(json.loads(right.get("wing_strip_json", "[]")), "wing_strip")
        except json.JSONDecodeError:
            nonfinite_pairs += 1
            continue
        for field in set(left_strips) & set(right_strips):
            add_delta(field, left_strips[field], right_strips[field])

    metrics: dict[str, dict[str, Any]] = {}
    for field, state in sorted(accum.items()):
        samples = int(state["samples"])
        metrics[field] = {
            "max_abs_delta": state["max_abs_delta"],
            "rms_delta": math.sqrt(state["sum_squared_delta"] / samples) if samples else None,
            "final_common_time_abs_delta": state["last_abs_delta"],
            "sample_count": samples,
        }
    return {
        "format": "openrc-d8b-r2b-common-time-comparison-v1",
        "case_id": case_id,
        "baseline_label": baseline.get("label", "unknown"),
        "current_label": current.get("label", "unknown"),
        "baseline_physics_hz": hz_left,
        "current_physics_hz": hz_right,
        "common_time_grid_hz": common_hz,
        "common_sample_count": len(common_slots),
        "max_timestamp_mismatch_s": max_time_mismatch,
        "finite_numeric_comparisons": finite_pairs,
        "nonfinite_or_missing_numeric_comparisons": nonfinite_pairs,
        "baseline_case_complete": bool(left_case.get("complete", False)),
        "current_case_complete": bool(right_case.get("complete", False)),
        "baseline_case_finite": bool(left_case.get("finite", False)),
        "current_case_finite": bool(right_case.get("finite", False)),
        "analysis_tool_sha256": sha256(Path(__file__).resolve()),
        "interpretation": "Matched boundary samples only; this reports differences and does not estimate RK4 order or physical validity.",
        "metrics": metrics,
    }


def compare_runs(baseline_dir: Path, current_run: dict[str, Any], output: Path) -> dict[str, Any]:
    baseline = read_run(baseline_dir)
    before = {str(case.get("case_id")): case for case in baseline.get("cases", [])}
    after = {str(case.get("case_id")): case for case in current_run.get("cases", [])}
    rows: list[dict[str, Any]] = []
    for case_id in sorted(set(before) | set(after)):
        left = before.get(case_id)
        right = after.get(case_id)
        row: dict[str, Any] = {
            "case_id": case_id,
            "baseline_present": left is not None,
            "current_present": right is not None,
            "baseline_complete": bool(left and left.get("complete")),
            "current_complete": bool(right and right.get("complete")),
            "baseline_finite": bool(left and left.get("finite")),
            "current_finite": bool(right and right.get("finite")),
        }
        left_peak = (left or {}).get("peak", {})
        right_peak = (right or {}).get("peak", {})
        for metric in METRICS:
            base_value = left_peak.get(metric)
            current_value = right_peak.get(metric)
            row[f"baseline_{metric}"] = base_value
            row[f"current_{metric}"] = current_value
            row[f"delta_{metric}"] = (
                float(current_value) - float(base_value)
                if isinstance(current_value, (int, float)) and isinstance(base_value, (int, float))
                else None
            )
        rows.append(row)
    comparison = {
        "format": "openrc-d8b-r2b-comparison-v1",
        "baseline_path": str(baseline_dir.resolve()),
        "baseline_label": baseline.get("label", "unknown"),
        "current_label": current_run.get("label", "unknown"),
        "baseline_complete": bool(baseline.get("complete", False)),
        "current_complete": bool(current_run.get("complete", False)),
        "same_aircraft_source": baseline.get("model_source_sha256") == current_run.get("model_source_sha256"),
        "baseline_source_hash_sha256": baseline.get("source_hash_sha256"),
        "current_source_hash_sha256": current_run.get("source_hash_sha256"),
        "baseline_physics_dependency_hash_sha256": baseline.get("physics_dependency_hash_sha256"),
        "current_physics_dependency_hash_sha256": current_run.get("physics_dependency_hash_sha256"),
        "same_physics_dependency_hash": baseline.get("physics_dependency_hash_sha256") == current_run.get("physics_dependency_hash_sha256"),
        "cases": rows,
    }
    (output / "comparison.json").write_text(json.dumps(comparison, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    if rows:
        columns = list(rows[0])
        with (output / "comparison.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=columns)
            writer.writeheader()
            writer.writerows(rows)
    return comparison


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True, help="Run label, normally baseline or current")
    parser.add_argument("--output", type=Path, help="Fresh output directory; defaults to matrix/<label>-<UTC timestamp>")
    parser.add_argument("--aircraft-json", "--aircraft-file", dest="aircraft_json", type=Path, default=DEFAULT_MODEL,
                        help="Aircraft v1 JSON to copy into this run and load (candidate or original model override)")
    parser.add_argument("--godot", type=Path, default=default_godot(), help="Pinned Godot 4.7.2 console executable")
    parser.add_argument("--hz", type=int, default=240, help="Physics tick rate (default: 240)")
    parser.add_argument("--case", action="append", default=[], help="Run only this case ID; may be repeated or comma-separated")
    parser.add_argument("--duration-s", type=float, help="Override every case duration for a quick diagnostic run")
    parser.add_argument("--compare", type=Path, help="Compare this run against a previous run directory")
    parser.add_argument("--trace-case", action="append", default=[], help="Retain a full compressed trace only for this case ID; repeat or comma-separate. Default retains all traces.")
    parser.add_argument("--common-time-case", help="Also compare this retained trace at timestamps common to both --compare runs")
    parser.add_argument("--timeout-s", type=int, default=600, help="Maximum wall time for the matrix (default: 600)")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.common_time_case and not args.compare:
        print("--common-time-case requires --compare", file=sys.stderr)
        return 2
    source_model = args.aircraft_json.expanduser().resolve()
    if not source_model.is_file():
        print(f"aircraft JSON does not exist: {source_model}", file=sys.stderr)
        return 2
    godot = args.godot.expanduser().resolve()
    if not godot.is_file():
        print(f"Godot executable does not exist: {godot}", file=sys.stderr)
        return 2
    output = args.output.expanduser().resolve() if args.output else MATRIX_ROOT / f"{args.label}-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}"
    if output.exists() and any(output.iterdir()):
        print(f"output directory is not empty; choose a fresh folder: {output}", file=sys.stderr)
        return 2
    output.mkdir(parents=True, exist_ok=True)
    model_copy = output / "aircraft-model-source.json"
    shutil.copyfile(source_model, model_copy)
    started = iso_now()
    input_fingerprint = fingerprints(model_copy)
    if input_fingerprint["missing_source_files"]:
        print("missing runner source files: " + ", ".join(input_fingerprint["missing_source_files"]), file=sys.stderr)
        return 2
    case_ids = [part.strip() for item in args.case for part in item.split(",") if part.strip()]
    trace_case_ids = {part.strip() for item in args.trace_case for part in item.split(",") if part.strip()}
    command = [
        str(godot), "--headless", "--path", str(ROOT / "app"), "--script", str(RUNNER), "--",
        f"--label={args.label}", f"--output-dir={output.as_posix()}", f"--aircraft-json={model_copy.as_posix()}",
        f"--source-hash={input_fingerprint['source_hash_sha256']}",
        f"--model-hash={input_fingerprint['aircraft_source_sha256']}", f"--hz={args.hz}",
    ]
    if case_ids:
        command.append(f"--case-filter={','.join(case_ids)}")
    if args.duration_s is not None:
        command.append(f"--duration-s={args.duration_s:.17g}")
    (output / "input_manifest.json").write_text(json.dumps({
        "format": "openrc-d8b-r2b-input-v1",
        "started_at_utc": started,
        "label": args.label,
        "command": [str(godot), "--headless", "--path", str(ROOT / "app"), "--script", str(RUNNER)],
        "physics_hz": args.hz,
        "source_aircraft_path": str(source_model),
        "aircraft_source_copy": model_copy.name,
        "model_source_sha256": input_fingerprint["aircraft_source_sha256"],
        "source_identity": input_fingerprint,
    }, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    stdout_path = output / "godot.stdout.log"
    stderr_path = output / "godot.stderr.log"
    print(f"Running {args.label} matrix at {args.hz} Hz: {output}")
    print(f"Aircraft snapshot SHA-256: {input_fingerprint['aircraft_source_sha256']}")
    try:
        with stdout_path.open("w", encoding="utf-8", newline="") as stdout, stderr_path.open("w", encoding="utf-8", newline="") as stderr:
            process = subprocess.run(command, cwd=ROOT, stdout=stdout, stderr=stderr, text=True, timeout=args.timeout_s)
    except subprocess.TimeoutExpired:
        print(f"matrix exceeded {args.timeout_s}s; logs are in {output}", file=sys.stderr)
        return 124
    except OSError as exc:
        print(f"could not start Godot: {exc}", file=sys.stderr)
        return 2
    run_manifest_path = output / "run_manifest.json"
    if not run_manifest_path.is_file():
        print(f"Godot exited {process.returncode} without a run manifest; see {stdout_path} and {stderr_path}", file=sys.stderr)
        return process.returncode or 1
    run_manifest = json.loads(run_manifest_path.read_text(encoding="utf-8"))
    final_fingerprint = fingerprints(model_copy)
    source_stable = (
        input_fingerprint["physics_dependency_hash_sha256"] == final_fingerprint["physics_dependency_hash_sha256"]
        and input_fingerprint["measurement_tool_hash_sha256"] == final_fingerprint["measurement_tool_hash_sha256"]
    )
    source_tree_stable = input_fingerprint["source_hash_sha256"] == final_fingerprint["source_hash_sha256"]
    run_manifest["physics_dependency_hash_sha256"] = input_fingerprint["physics_dependency_hash_sha256"]
    run_manifest["physics_dependency_file_paths"] = sorted(input_fingerprint["physics_dependency_files_sha256"])
    run_manifest["measurement_tool_hash_sha256"] = input_fingerprint["measurement_tool_hash_sha256"]
    try:
        compress_traces(run_manifest, output, trace_case_ids)
    except (OSError, ValueError) as exc:
        print(f"trace compression/retention failed: {exc}", file=sys.stderr)
        return 2
    run_manifest_path.write_text(json.dumps(run_manifest, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    wrapper_manifest = {
        "format": "openrc-d8b-r2b-run-v1",
        "started_at_utc": started,
        "finished_at_utc": iso_now(),
        "label": args.label,
        "godot_executable": str(godot),
        "godot_exit_code": process.returncode,
        "source_hash_sha256": input_fingerprint["source_hash_sha256"],
        "physics_dependency_hash_sha256": input_fingerprint["physics_dependency_hash_sha256"],
        "measurement_tool_hash_sha256": input_fingerprint["measurement_tool_hash_sha256"],
        "model_source_sha256": input_fingerprint["aircraft_source_sha256"],
        "source_stable_during_run": source_stable,
        "source_tree_stable_during_run": source_tree_stable,
        "source_identity_before": input_fingerprint,
        "source_identity_after": final_fingerprint,
        "run": run_manifest,
        "complete": bool(run_manifest.get("complete", False)) and process.returncode == 0 and source_stable,
    }
    (output / "matrix_manifest.json").write_text(json.dumps(wrapper_manifest, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    if args.compare:
        try:
            comparison = compare_runs(args.compare.expanduser().resolve(), run_manifest, output)
        except (OSError, json.JSONDecodeError, KeyError) as exc:
            print(f"comparison failed: {exc}", file=sys.stderr)
            return 2
        print(f"Compared {len(comparison['cases'])} cases; same aircraft JSON: {comparison['same_aircraft_source']}")
        if args.common_time_case:
            try:
                baseline_dir = args.compare.expanduser().resolve()
                baseline_run = read_run(baseline_dir)
                timeline = compare_common_time_case(baseline_dir, output, baseline_run, run_manifest, args.common_time_case)
                (output / "common_time_comparison.json").write_text(
                    json.dumps(timeline, indent=2, allow_nan=False) + "\n", encoding="utf-8"
                )
                with (output / "common_time_comparison.csv").open("w", newline="", encoding="utf-8") as stream:
                    columns = ["field", "max_abs_delta", "rms_delta", "final_common_time_abs_delta", "sample_count"]
                    writer = csv.DictWriter(stream, fieldnames=columns)
                    writer.writeheader()
                    for field, values in timeline["metrics"].items():
                        writer.writerow({"field": field, **values})
            except (OSError, ValueError, json.JSONDecodeError, KeyError) as exc:
                print(f"common-time comparison failed: {exc}", file=sys.stderr)
                return 2
            print(f"Common-time comparison: {timeline['common_sample_count']} samples on {timeline['common_time_grid_hz']} Hz grid")
    print(f"Matrix complete={wrapper_manifest['complete']}; source stable={source_stable}; traces={len(run_manifest.get('cases', []))}")
    if not wrapper_manifest["complete"]:
        print(f"Matrix did not meet completeness/finite checks; see {run_manifest_path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
