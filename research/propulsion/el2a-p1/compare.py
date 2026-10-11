#!/usr/bin/env python3
"""Compare isolated EL2a-P1 benchmark snapshots and powered exhaustion controls."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BENCH = HERE / "bench.gd"
POWERED_PROBE = HERE.parent / "el2" / "powered" / "powered_parity_probe.gd"
IGNORED_DIRS = {".godot", "captures"}
EXPECTED_CASE_FAMILIES = {
    "synthetic_stik_electric_4s": "electric",
    "synthetic_stik_electric_6s": "electric",
    "synthetic_stik_electric_4s_battery": "electric",
    "synthetic_stik_electric_6s_battery": "electric",
    "jensen_ugly_stik_60": "legacy_control",
    "p51d_mustang_120": "legacy_control",
}
EXPECTED_CASES = {(case, mode) for case in EXPECTED_CASE_FAMILIES for mode in ("powered", "coast")}
EVENT_KEYS = {(pack, hz) for pack in ("4s", "6s") for hz in (120, 240, 480, 960)}
ENGINE_ERROR = re.compile(r"(?mi)^\s*(?:SCRIPT ERROR|SHADER ERROR|ERROR|Parse Error|Compile Error):")
PINNED_GODOT_VERSION = re.compile(r"4\.7\.2\.stable\.official\.[0-9a-f]{9}")
COMMAND_TIMEOUT_S = 900


class CompareError(RuntimeError):
    """A failed precondition, subprocess, or report contract."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _reject_json_constant(value: str) -> None:
    raise CompareError(f"non-finite JSON number {value!r}")


def _finite_tree(value: Any, label: str = "JSON") -> None:
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return
    if isinstance(value, (int, float)):
        if isinstance(value, float) and not math.isfinite(value):
            raise CompareError(f"{label} contains a non-finite number")
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            _finite_tree(item, f"{label}[{index}]")
        return
    if isinstance(value, dict):
        for key, item in value.items():
            _finite_tree(item, f"{label}.{key}")


def read_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"), parse_constant=_reject_json_constant)
    except (OSError, json.JSONDecodeError) as exc:
        raise CompareError(f"cannot read valid JSON from {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise CompareError(f"expected a JSON object in {path}")
    _finite_tree(data, str(path))
    return data


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(data, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CompareError(message)


def _hex_bytes(value: Any, label: str) -> bytes:
    _require(isinstance(value, str) and len(value) % 2 == 0, f"{label}: expected even-length native hex")
    try:
        data = bytes.fromhex(value)
    except ValueError as exc:
        raise CompareError(f"{label}: invalid native hex") from exc
    _require(data.hex() == value, f"{label}: native hex must be lowercase and whitespace-free")
    return data


def _sha_matches(value: Any, data: bytes, label: str) -> None:
    _require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None,
             f"{label}: expected lowercase SHA-256")
    _require(value == sha256_bytes(data), f"{label}: SHA-256 does not match native bytes")


def _percentile95(values: list[float]) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(0.95 * len(ordered)) - 1)]


def _same_number(actual: Any, expected: float, label: str) -> None:
    _require(isinstance(actual, (int, float)) and not isinstance(actual, bool), f"{label}: missing numeric value")
    _require(math.isclose(float(actual), expected, rel_tol=1e-12, abs_tol=1e-9),
             f"{label}: reported {actual}, expected {expected}")


def _positive_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value)) and value > 0


def validate_benchmark_report(report: dict[str, Any], batches: int) -> dict[tuple[str, str], dict[str, Any]]:
    """Validate one bench.gd report and return decoded native bytes and raw timings."""
    _require(report.get("format") == "openrc-el2a-p1-performance-bench-v1", "wrong EL2a-P1 benchmark format")
    _require(report.get("type") == "whole_session_physics_tick_cost", "wrong benchmark type")
    machine = report.get("machine")
    _require(isinstance(machine, dict) and isinstance(machine.get("godot"), dict), "missing engine/machine metadata")
    _require(isinstance(machine.get("os"), str) and isinstance(machine.get("architecture"), str),
             "machine metadata is malformed")
    _require(isinstance(machine.get("processor"), str)
             and isinstance(machine.get("logical_cpu_count"), int)
             and not isinstance(machine.get("logical_cpu_count"), bool)
             and machine["logical_cpu_count"] > 0,
             "machine metadata is malformed")
    _require(report.get("tick_hz") == 240 and report.get("warmup_ticks") == 240
             and report.get("ticks_per_batch") == 120 and report.get("batch_count") == batches,
             "benchmark timing contract differs from the requested run")
    rows = report.get("cases")
    _require(isinstance(rows, list) and report.get("case_count") == 12 and len(rows) == 12,
             "expected exactly 12 benchmark cases")
    _require(report.get("success_count") == 12 and report.get("failure_count") == 0
             and report.get("successful_batch_count") == 12 * batches,
             "benchmark summary reports failed or incomplete cases")

    decoded: dict[tuple[str, str], dict[str, Any]] = {}
    for row in rows:
        _require(isinstance(row, dict) and row.get("ok") is True, "benchmark case is not successful")
        case_id, mode = row.get("id"), row.get("mode")
        key = (case_id, mode)
        _require(key in EXPECTED_CASES and key not in decoded, f"unexpected or duplicate benchmark case {key}")
        family = EXPECTED_CASE_FAMILIES[case_id]
        _require(row.get("type") == family and row.get("family") == family, f"{key}: case type mismatch")
        _require(row.get("engine_running") is (mode == "powered"), f"{key}: wrong engine-running mode")
        _require(row.get("warmup_ticks") == 240 and row.get("ticks_per_batch") == 120
                 and row.get("batch_count") == batches and row.get("completed_batch_count") == batches,
                 f"{key}: case has incomplete timing counts")
        seed = _hex_bytes(row.get("seed_checkpoint_native_hex"), f"{key} seed")
        _require(row.get("seed_checkpoint_bytes") == len(seed), f"{key}: seed byte count mismatch")
        _sha_matches(row.get("seed_checkpoint_sha256"), seed, f"{key} seed")
        samples: list[float] = []
        endpoints: list[bytes] = []
        batch_rows = row.get("batches")
        _require(isinstance(batch_rows, list) and len(batch_rows) == batches, f"{key}: missing raw batch samples")
        for index, batch in enumerate(batch_rows):
            _require(isinstance(batch, dict) and batch.get("index") == index
                     and batch.get("completed_ticks") == 120, f"{key}: batch {index} is incomplete")
            elapsed = batch.get("elapsed_us")
            sample = batch.get("us_per_tick")
            _require(_positive_number(elapsed) and _positive_number(sample), f"{key}: invalid batch timing")
            _same_number(sample, float(elapsed) / 120.0, f"{key} batch {index} us/tick")
            endpoint = _hex_bytes(batch.get("checkpoint_native_hex"), f"{key} batch {index} checkpoint")
            _require(batch.get("checkpoint_bytes") == len(endpoint), f"{key} batch {index}: byte count mismatch")
            _sha_matches(batch.get("checkpoint_sha256"), endpoint, f"{key} batch {index} checkpoint")
            endpoints.append(endpoint)
            samples.append(float(sample))
        _require(row.get("batch_checkpoint_bytes_identical") is True and all(x == endpoints[0] for x in endpoints),
                 f"{key}: endpoint checkpoints differ across restored batches")
        _same_number(row.get("median_us_per_tick"), statistics.median(samples), f"{key} median")
        _same_number(row.get("p95_us_per_tick"), _percentile95(samples), f"{key} p95")
        fingerprint = row.get("trajectory_fingerprint")
        _require(isinstance(fingerprint, dict) and fingerprint.get("ok") is True
                 and fingerprint.get("includes_initial_checkpoint") is True
                 and fingerprint.get("ticks") == 120, f"{key}: trajectory replay incomplete")
        fingerprint_sha = fingerprint.get("sha256")
        _require(isinstance(fingerprint_sha, str) and re.fullmatch(r"[0-9a-f]{64}", fingerprint_sha) is not None,
                 f"{key}: malformed trajectory fingerprint")
        _require(fingerprint.get("endpoint_checkpoint_sha256") == sha256_bytes(endpoints[-1]),
                 f"{key}: replay endpoint SHA does not match the timed checkpoint")
        decoded[key] = {"seed": seed, "endpoints": endpoints, "fingerprint": fingerprint_sha,
                        "samples": samples, "median": statistics.median(samples),
                        "p95": _percentile95(samples)}
    _require(decoded.keys() == EXPECTED_CASES, "benchmark case set is missing one or more expected cases")
    return decoded


def compare_benchmark_reports(baseline_reports: list[dict[str, Any]], candidate_reports: list[dict[str, Any]],
                              batches: int) -> dict[str, Any]:
    _require(len(baseline_reports) == len(candidate_reports) and len(baseline_reports) > 0,
             "baseline and candidate need the same nonzero number of rounds")
    baselines = [validate_benchmark_report(item, batches) for item in baseline_reports]
    candidates = [validate_benchmark_report(item, batches) for item in candidate_reports]
    cases: list[dict[str, Any]] = []
    failures: list[str] = []
    for key in sorted(EXPECTED_CASES):
        b_rows = [run[key] for run in baselines]
        c_rows = [run[key] for run in candidates]
        seed_equal = len({row["seed"] for row in b_rows + c_rows}) == 1
        endpoints = [blob for row in b_rows + c_rows for blob in row["endpoints"]]
        endpoint_equal = len(set(endpoints)) == 1
        fingerprint_equal = len({row["fingerprint"] for row in b_rows + c_rows}) == 1
        if not seed_equal:
            failures.append(f"{key}: seed checkpoint bytes differ across runs")
        if not endpoint_equal:
            failures.append(f"{key}: one or more batch endpoint checkpoint bytes differ across runs")
        if not fingerprint_equal:
            failures.append(f"{key}: replay trajectory fingerprints differ across runs")
        b_samples = [sample for row in b_rows for sample in row["samples"]]
        c_samples = [sample for row in c_rows for sample in row["samples"]]
        b_median, c_median = statistics.median(b_samples), statistics.median(c_samples)
        cases.append({
            "id": key[0], "mode": key[1], "type": EXPECTED_CASE_FAMILIES[key[0]],
            "baseline_sample_count": len(b_samples), "candidate_sample_count": len(c_samples),
            "baseline_samples_us_per_tick": b_samples, "candidate_samples_us_per_tick": c_samples,
            "baseline_median_us_per_tick": b_median, "candidate_median_us_per_tick": c_median,
            "baseline_p95_us_per_tick": _percentile95(b_samples),
            "candidate_p95_us_per_tick": _percentile95(c_samples),
            "candidate_over_baseline_median_ratio": c_median / b_median,
            "median_change_percent": (c_median / b_median - 1.0) * 100.0,
            "seed_checkpoint_bytes_identical": seed_equal,
            "all_batch_endpoint_bytes_identical": endpoint_equal,
            "trajectory_fingerprints_identical": fingerprint_equal,
        })
    return {"status": "passed" if not failures else "failed", "round_count": len(baselines),
            "case_count": len(cases), "seed_checkpoints_identical": all(c["seed_checkpoint_bytes_identical"] for c in cases),
            "all_batch_endpoint_bytes_identical": all(c["all_batch_endpoint_bytes_identical"] for c in cases),
            "trajectory_fingerprints_identical": all(c["trajectory_fingerprints_identical"] for c in cases),
            "cases": cases, "failures": failures}


def _safe_report_file(base: Path, name: Any, label: str) -> Path:
    _require(isinstance(name, str) and name != "", f"{label}: missing binary filename")
    relative = Path(name)
    _require(not relative.is_absolute(), f"{label}: expected a relative binary filename")
    path = (base / relative).resolve()
    try:
        path.relative_to(base.resolve())
    except ValueError as exc:
        raise CompareError(f"{label}: binary filename escapes its evidence directory") from exc
    _require(path.is_file(), f"{label}: missing binary evidence {path}")
    return path


def validate_event_report(report: dict[str, Any], output_dir: Path) -> dict[tuple[str, int], dict[str, Any]]:
    _require(report.get("format") == "el2-powered-parity-v1" and report.get("mode") == "control"
             and report.get("instrumented") is False, "expected powered-parity control-mode output")
    _require(report.get("rates_hz") == [120, 240, 480, 960] and report.get("end_time_s") == 0.05,
             "powered-parity control horizon or rates changed")
    _require(report.get("failures") == [] and isinstance(report.get("rows"), list)
             and len(report["rows"]) == 8, "powered-parity probe reported failure or wrong row count")
    control_dir = (output_dir / "control").resolve()
    rows: dict[tuple[str, int], dict[str, Any]] = {}
    for row in report["rows"]:
        _require(isinstance(row, dict) and row.get("ok") is True and row.get("all_finite") is True,
                 "powered-parity row failed its accepted-state or finite checks")
        key = (row.get("pack"), row.get("hz"))
        _require(key in EVENT_KEYS and key not in rows, f"unexpected or duplicate powered-parity case {key}")
        _require(row.get("steps") == round(0.05 * key[1]) and row.get("end_time_s") == 0.05
                 and _positive_number(row.get("event_tick"))
                 and _positive_number(row.get("event_tick_wall_usec")),
                 f"{key}: incomplete exhaustion timing/status")
        _require(row.get("events") == [], f"{key}: control-mode probe unexpectedly recorded instrumented events")
        seed_path = _safe_report_file(control_dir, row.get("seed_checkpoint_file"), f"{key} seed")
        end_path = _safe_report_file(control_dir, row.get("checkpoint_file"), f"{key} endpoint")
        seed, endpoint = seed_path.read_bytes(), end_path.read_bytes()
        _require(row.get("seed_checkpoint_byte_count") == len(seed), f"{key}: seed checkpoint size mismatch")
        _require(row.get("checkpoint_byte_count") == len(endpoint), f"{key}: endpoint checkpoint size mismatch")
        rows[key] = {"row": row, "seed": seed, "endpoint": endpoint,
                     "seed_sha256": sha256_bytes(seed), "endpoint_sha256": sha256_bytes(endpoint)}
    _require(rows.keys() == EVENT_KEYS, "powered-parity output is missing one or more pack/rate cases")
    return rows


def compare_event_reports(baseline_report: dict[str, Any], candidate_report: dict[str, Any],
                          baseline_dir: Path, candidate_dir: Path) -> dict[str, Any]:
    baseline = validate_event_report(baseline_report, baseline_dir)
    candidate = validate_event_report(candidate_report, candidate_dir)
    rows: list[dict[str, Any]] = []
    failures: list[str] = []
    baseline_times: list[float] = []
    candidate_times: list[float] = []
    for key in sorted(EVENT_KEYS):
        b, c = baseline[key], candidate[key]
        fields_match = all(b["row"].get(field) == c["row"].get(field) for field in
                           ("event_tick", "steps", "end_time_s", "event_start_charge_c", "configured_initial_charge_c"))
        seed_match, endpoint_match = b["seed"] == c["seed"], b["endpoint"] == c["endpoint"]
        if not fields_match:
            failures.append(f"event case {key}: event tick or state metadata differs")
        if not seed_match:
            failures.append(f"event case {key}: native seed checkpoint files differ")
        if not endpoint_match:
            failures.append(f"event case {key}: native endpoint checkpoint files differ")
        b_time = float(b["row"]["event_tick_wall_usec"])
        c_time = float(c["row"]["event_tick_wall_usec"])
        baseline_times.append(b_time)
        candidate_times.append(c_time)
        rows.append({"pack": key[0], "hz": key[1], "event_tick": b["row"]["event_tick"],
                     "baseline_event_tick_wall_usec": b_time, "candidate_event_tick_wall_usec": c_time,
                     "candidate_over_baseline_ratio": c_time / b_time,
                     "seed_checkpoint_bytes": len(b["seed"]), "seed_checkpoint_sha256": b["seed_sha256"],
                     "endpoint_checkpoint_bytes": len(b["endpoint"]), "endpoint_checkpoint_sha256": b["endpoint_sha256"],
                     "event_metadata_identical": fields_match, "seed_checkpoint_bytes_identical": seed_match,
                     "endpoint_checkpoint_bytes_identical": endpoint_match})
    b_median, c_median = statistics.median(baseline_times), statistics.median(candidate_times)
    return {"status": "passed" if not failures else "failed", "type": "powered_exhaustion_control_diagnostic",
            "case_count": len(rows), "timing_note": "one event-tick wall sample per pack/rate; diagnostic, not a repeated timing distribution",
            "baseline_median_event_tick_wall_usec": b_median,
            "candidate_median_event_tick_wall_usec": c_median,
            "candidate_over_baseline_median_ratio": c_median / b_median,
            "baseline_p95_event_tick_wall_usec": _percentile95(baseline_times),
            "candidate_p95_event_tick_wall_usec": _percentile95(candidate_times),
            "all_seed_checkpoint_bytes_identical": all(row["seed_checkpoint_bytes_identical"] for row in rows),
            "all_endpoint_checkpoint_bytes_identical": all(row["endpoint_checkpoint_bytes_identical"] for row in rows),
            "rows": rows, "failures": failures}


def _copy_ignore(directory: str, names: list[str]) -> set[str]:
    return {name for name in names if name.casefold() in IGNORED_DIRS
            and (Path(directory) / name).is_dir()}


def tree_hashes(root: Path) -> dict[str, str]:
    """Hash copied app inputs while omitting Godot caches and capture artifacts."""
    result: dict[str, str] = {}
    for directory, dirs, files in os.walk(root):
        dirs[:] = sorted(name for name in dirs if name.casefold() not in IGNORED_DIRS)
        for name in sorted(files):
            path = Path(directory) / name
            result[path.relative_to(root).as_posix()] = sha256_file(path)
    return result


def _reject_symlinks(root: Path) -> None:
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [name for name in dirs if name.casefold() not in IGNORED_DIRS]
        for name in dirs + files:
            if (Path(directory) / name).is_symlink():
                raise CompareError(f"refusing app copy with a symlink: {Path(directory) / name}")


def run_command(command: list[str], timeout: int, log_path: Path, cwd: Path = ROOT,
                allowed_returncodes: tuple[int, ...] = (0,), xdg_root: Path | None = None) -> str:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    header = "$ " + subprocess.list2cmdline(command) + f"\n# timeout_s={timeout}\n\n"
    environment = os.environ.copy()
    if xdg_root is not None:
        xdg_paths = {name: xdg_root / name.removeprefix("XDG_").lower()
                     for name in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME")}
        for path in xdg_paths.values():
            path.mkdir(parents=True, exist_ok=True)
        environment.update({name: str(path) for name, path in xdg_paths.items()})
    try:
        result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, errors="replace", check=False, timeout=timeout, env=environment)
        output = result.stdout or ""
        log_path.write_text(header + output, encoding="utf-8")
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        log_path.write_text(header + output + f"\nTIMEOUT after {timeout} seconds\n", encoding="utf-8")
        raise CompareError(f"command timed out after {timeout}s; log preserved at {log_path}: {command!r}") from exc
    if result.returncode not in allowed_returncodes:
        raise CompareError(f"command exited {result.returncode}; log preserved at {log_path}: {output[-4000:]}")
    match = ENGINE_ERROR.search(output)
    if match:
        raise CompareError(f"engine error output detected; log preserved at {log_path}: {output[-4000:]}")
    return output


def validate_godot_version_output(output: str) -> str:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    _require(len(lines) == 1 and PINNED_GODOT_VERSION.fullmatch(lines[0]) is not None,
             "Godot --version must print exactly one pinned 4.7.2 official version line")
    return lines[0]


def _absolute_fresh_out(raw: str) -> Path:
    path = Path(raw).expanduser()
    _require(path.is_absolute(), "--out must be an absolute path")
    _require(not path.exists() and not path.is_symlink(), f"refusing to overwrite existing output: {path}")
    return path.resolve()


def _validate_inputs(args: argparse.Namespace, output: Path) -> tuple[Path, Path, Path]:
    baseline = args.baseline_app.expanduser().resolve(strict=True)
    candidate = args.candidate_app.expanduser().resolve(strict=True)
    godot = args.godot.expanduser().resolve(strict=True)
    for label, app in (("baseline", baseline), ("candidate", candidate)):
        _require(app.is_dir() and (app / "project.godot").is_file(), f"{label} is not an app project: {app}")
        _reject_symlinks(app)
        _require(not output.is_relative_to(app) and not app.is_relative_to(output),
                 f"output and {label} app paths must not contain one another")
    _require(godot.is_file(), f"Godot executable is missing: {godot}")
    _require(1 <= args.batches <= 1000, "--batches must be from 1 to 1000")
    _require(args.rounds >= 1, "--rounds must be positive")
    _require(args.timeout_sec >= 1, "--timeout-sec must be positive")
    _require(BENCH.is_file() and POWERED_PROBE.is_file(), "benchmark or powered-parity GDScript is missing")
    return baseline, candidate, godot


def _copy_and_import(label: str, source: Path, expected_hashes: dict[str, str], out: Path,
                     godot: Path, timeout: int) -> Path:
    parent = out / label
    app = parent / "app"
    parent.mkdir(parents=True, exist_ok=False)
    shutil.copytree(source, app, ignore=_copy_ignore)
    copied_hashes = tree_hashes(app)
    _require(copied_hashes == expected_hashes, f"{label}: isolated copy differs from source manifest")
    run_command([str(godot), "--headless", "--editor", "--path", str(app), "--import", "--quit"],
                timeout, parent / "import.log", xdg_root=out / "runtime" / label / "import")
    return app


def _percentile_record(samples: list[float]) -> dict[str, float]:
    return {"median": statistics.median(samples), "p95": _percentile95(samples)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-app", type=Path, required=True)
    parser.add_argument("--candidate-app", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", required=True, help="fresh absolute evidence directory; it will never be removed")
    parser.add_argument("--batches", type=int, default=12)
    parser.add_argument("--rounds", type=int, default=2)
    parser.add_argument("--timeout-sec", type=int, default=COMMAND_TIMEOUT_S)
    args = parser.parse_args()

    try:
        output = _absolute_fresh_out(args.out)
        baseline_source, candidate_source, godot = _validate_inputs(args, output)
    except Exception as exc:
        print(f"FAIL: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir(exist_ok=False)
    run_doc: dict[str, Any] = {
        "format": "openrc-el2a-p1-compare-v1",
        "status": "running",
        "type": "performance_comparison",
        "scope_note": "Software timing and exact replay comparison only; this report does not close Gate P or validate synthetic packs as hardware.",
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "arguments": {"baseline_app": str(baseline_source), "candidate_app": str(candidate_source),
                      "godot": str(godot), "batches": args.batches, "rounds": args.rounds,
                      "timeout_sec": args.timeout_sec},
        "commands": [],
    }
    write_json(output / "comparison.json", run_doc)
    try:
        version_output = run_command([str(godot), "--version"], 30, output / "godot-version.log",
                                     allowed_returncodes=(0, 1),
                                     xdg_root=output / "runtime" / "godot-version")
        version = validate_godot_version_output(version_output)
        engine = {"path": str(godot), "version": version, "sha256": sha256_file(godot), "bytes": godot.stat().st_size}
        manifests = {"baseline": tree_hashes(baseline_source), "candidate": tree_hashes(candidate_source)}
        changed_paths = []
        for relative in sorted(manifests["baseline"].keys() | manifests["candidate"].keys()):
            b_hash, c_hash = manifests["baseline"].get(relative), manifests["candidate"].get(relative)
            if b_hash != c_hash:
                changed_paths.append({"path": relative, "baseline_sha256": b_hash,
                                      "candidate_sha256": c_hash,
                                      "change": "added" if b_hash is None else "removed" if c_hash is None else "modified"})
        source_manifest = {
            "excluded_directories": sorted(IGNORED_DIRS),
            "baseline": {"source_app": str(baseline_source), "file_count": len(manifests["baseline"]),
                         "files_sha256": manifests["baseline"]},
            "candidate": {"source_app": str(candidate_source), "file_count": len(manifests["candidate"]),
                          "files_sha256": manifests["candidate"]},
            "changed_paths": changed_paths,
            "tools": {"bench_gd_sha256": sha256_file(BENCH), "powered_probe_gd_sha256": sha256_file(POWERED_PROBE),
                      "compare_py_sha256": sha256_file(Path(__file__).resolve())},
        }
        write_json(output / "source-manifest.json", source_manifest)
        run_doc.update({"engine": engine, "source_manifest": "source-manifest.json",
                        "changed_app_path_count": len(changed_paths), "changed_app_paths": changed_paths,
                        "excluded_directories": sorted(IGNORED_DIRS), "round_count": args.rounds,
                        "batch_count_per_case_per_run": args.batches})
        write_json(output / "comparison.json", run_doc)
        app_copies: dict[str, Path] = {}
        for label, source in (("baseline", baseline_source), ("candidate", candidate_source)):
            app_copies[label] = _copy_and_import(label, source, manifests[label], output, godot, args.timeout_sec)

        raw_runs: dict[str, list[dict[str, Any]]] = {"baseline": [], "candidate": []}
        order: list[dict[str, Any]] = []
        for round_index in range(args.rounds):
            sequence = ("baseline", "candidate") if round_index % 2 == 0 else ("candidate", "baseline")
            for label in sequence:
                run_dir = output / "timings" / f"round-{round_index + 1:02d}" / label
                run_dir.mkdir(parents=True, exist_ok=False)
                result_path = run_dir / "benchmark.json"
                log_path = run_dir / "benchmark.log"
                command = [str(godot), "--headless", "--path", str(app_copies[label]), "--script", str(BENCH),
                           "--", f"--out={result_path}", f"--batches={args.batches}"]
                order_entry = {"round": round_index + 1, "snapshot": label, "order_index": len(order) + 1,
                               "results": result_path.relative_to(output).as_posix(),
                               "log": log_path.relative_to(output).as_posix()}
                order.append(order_entry)
                run_doc["commands"] = order.copy()
                write_json(output / "comparison.json", run_doc)
                run_command(command, args.timeout_sec, log_path,
                            xdg_root=output / "runtime" / "timings" / f"round-{round_index + 1:02d}" / label)
                report = read_json(result_path)
                validate_benchmark_report(report, args.batches)
                raw_runs[label].append({"report": report, **order_entry})

        bench_comparison = compare_benchmark_reports(
            [record["report"] for record in raw_runs["baseline"]],
            [record["report"] for record in raw_runs["candidate"]], args.batches)
        run_doc["benchmark_runs"] = [{key: value for key, value in record.items() if key != "report"}
                                     for label in ("baseline", "candidate") for record in raw_runs[label]]
        run_doc["run_order"] = order
        run_doc["benchmark_comparison"] = bench_comparison

        event_outputs: dict[str, dict[str, Any]] = {}
        for label in ("baseline", "candidate"):
            event_dir = output / f"{label}-events"
            event_dir.mkdir(exist_ok=False)
            log_path = event_dir / "probe.log"
            command = [str(godot), "--headless", "--path", str(app_copies[label]), "--script", str(POWERED_PROBE),
                       "--", str(event_dir)]
            run_command(command, args.timeout_sec, log_path,
                        xdg_root=output / "runtime" / f"{label}-events")
            event_result_path = event_dir / "control" / "results.json"
            event_report = read_json(event_result_path)
            validate_event_report(event_report, event_dir)
            event_outputs[label] = {"results": event_result_path.relative_to(output).as_posix(),
                                    "log": log_path.relative_to(output).as_posix(),
                                    "mode": event_report["mode"], "row_count": len(event_report["rows"])}
        event_comparison = compare_event_reports(
            read_json(output / event_outputs["baseline"]["results"]),
            read_json(output / event_outputs["candidate"]["results"]),
            output / "baseline-events", output / "candidate-events")
        run_doc["event_runs"] = event_outputs
        run_doc["event_comparison"] = event_comparison
        failures = bench_comparison["failures"] + event_comparison["failures"]
        run_doc["status"] = "passed" if not failures else "failed"
        run_doc["failures"] = failures
        run_doc["completed_utc"] = datetime.now(timezone.utc).isoformat()
        write_json(output / "comparison.json", run_doc)
        print(f"{run_doc['status'].upper()}: {len(bench_comparison['cases'])} performance cases; "
              f"{event_comparison['case_count']} powered-event controls; evidence: {output}")
        return 0 if not failures else 1
    except Exception as exc:
        run_doc["status"] = "failed"
        run_doc["failure"] = f"{type(exc).__name__}: {exc}"
        run_doc["completed_utc"] = datetime.now(timezone.utc).isoformat()
        try:
            write_json(output / "comparison.json", run_doc)
            write_json(output / "failure.json", {"status": "failed", "failure": run_doc["failure"],
                                                  "evidence_directory_preserved": str(output)})
        except Exception as record_error:
            print(f"Could not update failure record: {record_error}", file=sys.stderr)
        print(f"FAIL: {run_doc['failure']}; evidence preserved at {output}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
