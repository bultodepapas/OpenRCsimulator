#!/usr/bin/env python3
"""Run AS-04's same-process v2 vs explicit legacy-input paired tick benchmark."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DRIVER = Path(__file__).with_name("paired_metadata_bench.gd")
DEFAULT_ENGINE = ROOT / ".tools" / "Godot_v4.7.2-stable_win64_console.exe"
DEFAULT_APP = ROOT / ".tools" / "as-integration" / "app"
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
ENGINE_ERROR = re.compile(r"(?:SCRIPT ERROR:|Parse Error:|ERROR:)")
IGNORED_PARTS = {".godot", ".git"}
IGNORED_SUFFIXES = {".uid", ".import", ".tmp", ".log"}


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
        if IGNORED_PARTS.intersection(relative.parts):
            continue
        if any(part.lower() == "captures" for part in relative.parts):
            continue
        if path.suffix.lower() in IGNORED_SUFFIXES:
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


def host_process_snapshot() -> dict[str, Any]:
    """Capture visible Windows and WSL Godot processes; this is not a utilization measurement."""
    if os.name != "nt":
        return {"available": False, "reason": "Windows process inventory unavailable on this host"}
    command = (
        "Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue | "
        "Select-Object ProcessName,Id,CPU,StartTime | ConvertTo-Json -Compress"
    )
    try:
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=5,
            check=False,
        )
        if result.returncode != 0:
            windows: dict[str, Any] = {"available": False, "return_code": result.returncode, "error": result.stderr.strip()}
        else:
            data = json.loads(result.stdout) if result.stdout.strip() else []
            if isinstance(data, dict):
                data = [data]
            windows = {"available": True, "godot_processes": data}
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        windows = {"available": False, "error": str(error)}
    wsl_command = ["wsl.exe", "-d", "Ubuntu", "--", "ps", "-eo", "pid,args"]
    try:
        result = subprocess.run(
            wsl_command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=8,
            check=False,
        )
        if result.returncode != 0:
            wsl: dict[str, Any] = {"available": False, "return_code": result.returncode, "error": result.stderr.strip()}
        else:
            processes = []
            for line in result.stdout.splitlines()[1:]:
                columns = line.strip().split(maxsplit=1)
                if len(columns) == 2 and "godot" in columns[1].lower():
                    processes.append({"pid": columns[0], "command": Path(columns[1].split()[0]).name})
            wsl = {"available": True, "godot_processes": processes}
    except (OSError, subprocess.TimeoutExpired) as error:
        wsl = {"available": False, "error": str(error)}
    return {"windows": windows, "wsl_ubuntu": wsl}


def json_write(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")


def run_engine(
    label: str,
    mode: str,
    app: Path,
    engine: Path,
    out_dir: Path,
    timeout: int,
    selected_case: str | None,
    pair_count: int,
) -> dict[str, Any]:
    report_path = out_dir / f"{label}.json"
    log_path = out_dir / f"{label}.log"
    before = source_manifest(app)
    host_before = host_process_snapshot()
    command = [
        str(engine),
        "--headless",
        "--path",
        str(app),
        "--script",
        str(DRIVER),
        "--",
        f"--mode={mode}",
        f"--out={report_path.resolve().as_posix()}",
        f"--pairs={pair_count}",
    ]
    if selected_case:
        command.append(f"--only={selected_case}")
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
        return_code: int | None = process.returncode
    except subprocess.TimeoutExpired as error:
        timed_out = True
        partial = error.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        log = str(partial) + f"\nAS-04 paired TIMEOUT after {timeout}s\n"
        return_code = None
    elapsed = time.perf_counter() - started
    log_path.write_text(log, encoding="utf-8")
    after = source_manifest(app)
    host_after = host_process_snapshot()
    result: dict[str, Any] = {
        "label": label,
        "mode": mode,
        "only": selected_case,
        "pair_count": pair_count,
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
        "host_processes_before": host_before,
        "host_processes_after": host_after,
        "report_path": str(report_path),
        "log_path": str(log_path),
    }
    if report_path.exists():
        try:
            result["report"] = json.loads(report_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            result["report_error"] = f"invalid JSON: {error}"
    return result


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1))
    return ordered[index]


def distribution(values: list[float]) -> dict[str, Any]:
    if not values:
        return {"count": 0, "median": None, "p10": None, "p90": None, "min": None, "max": None, "mad": None}
    median = statistics.median(values)
    return {
        "count": len(values),
        "median": median,
        "p10": percentile(values, 0.10),
        "p90": percentile(values, 0.90),
        "min": min(values),
        "max": max(values),
        "mad": statistics.median([abs(value - median) for value in values]),
    }


def report_failures(label: str, run: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if run.get("timed_out"):
        failures.append(f"{label}: engine timed out")
    if run.get("return_code") != 0:
        failures.append(f"{label}: engine returned {run.get('return_code')}")
    if run.get("engine_errors"):
        failures.append(f"{label}: engine emitted errors {run['engine_errors']}")
    if not run.get("source_unchanged_during_run"):
        failures.append(f"{label}: application sources changed during engine run")
    if run.get("report_error"):
        failures.append(f"{label}: {run['report_error']}")
    report = run.get("report")
    if not isinstance(report, dict):
        failures.append(f"{label}: no structured report")
        return failures
    if report.get("mode") != run.get("mode"):
        failures.append(f"{label}: report mode does not match requested mode")
    if report.get("pair_count") != run.get("pair_count"):
        failures.append(f"{label}: report pair count does not match requested count")
    expected_filter = run.get("only") or "all"
    if report.get("case_filter") != expected_filter:
        failures.append(f"{label}: report case filter does not match requested filter")
    cases = report.get("cases")
    expected_keys = {run["only"]} if run.get("only") else EXPECTED_KEYS
    if not isinstance(cases, list) or {case.get("key") for case in cases} != expected_keys:
        failures.append(f"{label}: expected cases {sorted(expected_keys)}")
        return failures
    if report.get("failures"):
        failures.extend(f"{label}: {failure}" for failure in report["failures"])
    for case in cases:
        if not case.get("ok"):
            failures.append(f"{label}/{case.get('key')}: case checks failed")
        for flag in (
            "loaded_model_equal",
            "legacy_clone_bytes_match_loader_identity",
            "v2_identity_guard",
            "legacy_explicit_format",
            "session_model_equal",
            "initial_state_equal",
        ):
            if not case.get(flag):
                failures.append(f"{label}/{case.get('key')}: {flag} failed")
        if run.get("mode") == "bench":
            pairs = case.get("pairs")
            expected_pair_count = int(run.get("pair_count", 6))
            if not isinstance(pairs, list) or len(pairs) != expected_pair_count:
                failures.append(f"{label}/{case.get('key')}: expected {expected_pair_count} paired batches")
                continue
            if not case.get("warmup_state_equal") or not case.get("reset_after_measurement_v2") or not case.get("reset_after_measurement_legacy"):
                failures.append(f"{label}/{case.get('key')}: warmup or final reset simulation bytes differ")
            for pair_index, pair in enumerate(pairs):
                expected_order = ["v2", "legacy_v1"] if pair_index % 2 == 0 else ["legacy_v1", "v2"]
                if pair.get("order") != expected_order:
                    failures.append(f"{label}/{case.get('key')}/pair{pair.get('pair')}: order is not ABBA-balanced")
                if not pair.get("start_state_equal") or not pair.get("state_equal_after_batch"):
                    failures.append(f"{label}/{case.get('key')}/pair{pair.get('pair')}: simulation bytes differ")
                for variant in ("v2", "legacy_v1"):
                    batch = pair.get(variant, {})
                    samples = batch.get("tick_us_samples", [])
                    if batch.get("ticks_advanced") != 120 or len(samples) != 120:
                        failures.append(
                            f"{label}/{case.get('key')}/pair{pair.get('pair')}/{variant}: expected 120 measured ticks"
                        )
                    if batch.get("failure"):
                        failures.append(
                            f"{label}/{case.get('key')}/pair{pair.get('pair')}/{variant}: {batch['failure']}"
                        )
    return failures


def summarize_pairs(report: dict[str, Any]) -> list[dict[str, Any]]:
    summaries: list[dict[str, Any]] = []
    for case in report.get("cases", []):
        pairs: list[dict[str, Any]] = []
        p50_ratios: list[float] = []
        p95_ratios: list[float] = []
        for pair in case.get("pairs", []):
            v2 = pair.get("v2", {}).get("tick_us", {})
            legacy = pair.get("legacy_v1", {}).get("tick_us", {})
            v2_p50 = v2.get("p50_us")
            legacy_p50 = legacy.get("p50_us")
            v2_p95 = v2.get("p95_us")
            legacy_p95 = legacy.get("p95_us")
            p50_ratio = v2_p50 / legacy_p50 if isinstance(v2_p50, (int, float)) and legacy_p50 else None
            p95_ratio = v2_p95 / legacy_p95 if isinstance(v2_p95, (int, float)) and legacy_p95 else None
            if p50_ratio is not None:
                p50_ratios.append(float(p50_ratio))
            if p95_ratio is not None:
                p95_ratios.append(float(p95_ratio))
            pairs.append({
                "pair": pair.get("pair"),
                "order": pair.get("order"),
                "state_equal_after_batch": pair.get("state_equal_after_batch"),
                "v2_tick_us": v2,
                "legacy_v1_tick_us": legacy,
                "p50_ratio_v2_over_legacy": p50_ratio,
                "p95_ratio_v2_over_legacy": p95_ratio,
            })
        summaries.append({
            "key": case.get("key"),
            "kind": case.get("kind"),
            "loaded_model_equal": case.get("loaded_model_equal"),
            "initial_state_equal": case.get("initial_state_equal"),
            "warmup_state_equal": case.get("warmup_state_equal"),
            "paired_p50_ratio_v2_over_legacy": distribution(p50_ratios),
            "paired_p95_ratio_v2_over_legacy": distribution(p95_ratios),
            "pairs": pairs,
        })
    return summaries


def format_ratio_summary(value: dict[str, Any]) -> str:
    median = value.get("median")
    low = value.get("min")
    high = value.get("max")
    if not all(isinstance(item, (int, float)) for item in (median, low, high)):
        return "n/a"
    return f"{median:.3f} ({low:.3f}–{high:.3f})"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=DEFAULT_APP, help="frozen integrated app snapshot to measure")
    parser.add_argument("--engine", type=Path, default=DEFAULT_ENGINE, help="pinned Godot console executable")
    parser.add_argument("--timeout", type=int, default=180, help="per-process engine timeout in seconds (1-180)")
    parser.add_argument("--only", choices=sorted(EXPECTED_KEYS), help="measure one aircraft case instead of all eight")
    parser.add_argument("--pairs", type=int, default=6, help="even ABBA pair count (2-24); default 6")
    parser.add_argument("--run-id", default=datetime.now(timezone.utc).strftime("AS04-paired-%Y%m%dT%H%M%SZ"), help="unique evidence directory name")
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE, help="directory holding durable run evidence")
    parser.add_argument("--check-only", action="store_true", help="parse and verify all v2/v1 model and initial-session pairs without timing")
    return parser.parse_args()


def resolve(path: Path) -> Path:
    return path if path.is_absolute() else (ROOT / path).resolve()


def main() -> int:
    args = parse_args()
    if not 1 <= args.timeout <= 180:
        print("--timeout must be between 1 and 180 seconds", file=sys.stderr)
        return 2
    if args.pairs < 2 or args.pairs > 24 or args.pairs % 2:
        print("--pairs must be an even integer from 2 through 24", file=sys.stderr)
        return 2
    app = resolve(args.app)
    engine = resolve(args.engine)
    evidence_root = resolve(args.evidence_root)
    if not app.is_dir() or not (app / "project.godot").is_file():
        print(f"missing Godot app directory: {app}", file=sys.stderr)
        return 2
    for label, path in (("engine", engine), ("driver", DRIVER)):
        if not path.is_file():
            print(f"missing {label}: {path}", file=sys.stderr)
            return 2
    out_dir = evidence_root / args.run_id
    try:
        out_dir.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        print(f"evidence directory already exists: {out_dir}", file=sys.stderr)
        return 2

    run_info = {
        "run_id": args.run_id,
        "app": str(app),
        "engine": str(engine),
        "engine_sha256": sha256_file(engine),
        "driver": str(DRIVER),
        "driver_sha256": sha256_file(DRIVER),
        "wrapper_sha256": sha256_file(Path(__file__)),
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "method": f"explicit AircraftData.legacy_v1_input clone; {args.pairs} ABBA-paired 120-tick batches per selected aircraft after a 120-tick warmup; reset and input preparation outside individual Simulation.step timers",
        "selected_case": args.only or "all",
        "pair_count": args.pairs,
        "timing_policy": "descriptive only; no threshold; prior cross-process measurements do not establish regression",
        "host_context_policy": "record visible Godot processes immediately before and after each engine phase; this is residual-variability context, not a CPU/load measurement",
    }
    json_write(out_dir / "run.json", run_info)
    check_run = run_engine("self_check", "check", app, engine, out_dir, args.timeout, args.only, args.pairs)
    runs: dict[str, Any] = {"self_check": check_run}
    failures = report_failures("self_check", check_run)
    if not args.check_only and not failures:
        runs["benchmark"] = run_engine("benchmark", "bench", app, engine, out_dir, args.timeout, args.only, args.pairs)
        failures.extend(report_failures("benchmark", runs["benchmark"]))

    comparison: dict[str, Any] = {
        "format": "openrc-as04-paired-comparison-v1",
        "run_id": args.run_id,
        "ok": not failures,
        "failures": failures,
        "run_info": run_info,
        "self_check": {key: value for key, value in check_run.items() if key not in {"report", "source_before", "source_after"}},
        "source_manifest_sha256": check_run.get("source_before", {}).get("manifest_sha256"),
        "cases": [],
        "measurement_policy": "same-process paired ratios and spread are descriptive; model and every end-of-batch simulation byte boundary are exact acceptance checks",
    }
    if not args.check_only and "benchmark" in runs and isinstance(runs["benchmark"].get("report"), dict):
        comparison["cases"] = summarize_pairs(runs["benchmark"]["report"])
        comparison["benchmark_run"] = {key: value for key, value in runs["benchmark"].items() if key not in {"report", "source_before", "source_after"}}
        if runs["benchmark"].get("source_before", {}).get("manifest_sha256") != check_run.get("source_before", {}).get("manifest_sha256"):
            failures.append("application source manifest changed between self-check and benchmark")
            comparison["ok"] = False
            comparison["failures"] = failures
    json_write(out_dir / "summary.json", comparison)
    json_write(out_dir / "runs.json", runs)
    lines = [
        f"# Same-process aircraft metadata benchmark {args.run_id}",
        "",
        f"Status: {'PASS' if not failures else 'FAIL'}.",
        "",
        f"- App: `{app}`; engine `{engine}` SHA-256 `{run_info['engine_sha256']}`.",
        f"- Driver SHA-256: `{run_info['driver_sha256']}`; wrapper SHA-256 `{run_info['wrapper_sha256']}`.",
        f"- Method: one Godot process per phase; v2 session with expected-ID guard vs an on-disk `AircraftData.legacy_v1_input` clone; 120 warmup ticks and {args.pairs} paired 120-tick batches in ABBA repeated order; reset/input setup outside the per-step timer.",
        f"- Selection: `{args.only or 'all'}`.",
        "- Timing ratios are descriptive and have no pass/fail threshold. Exact non-metadata model values, initial state, warmup state, and each paired final simulation byte boundary are checked.",
        "- Windows and WSL Godot process inventories immediately before and after each phase are retained in `runs.json`; they document residual host activity but do not measure total CPU load.",
        f"- Evidence: `{out_dir}` (raw self-check/benchmark JSON, logs, source manifests, and summary).",
    ]
    if comparison["cases"]:
        lines.extend([
            "",
            f"Paired v2 / legacy per-tick timing ratios are descriptive. Values show the median across {args.pairs} paired batches and the full observed min–max range; 1.000 is equal measured time. No timing threshold is applied.",
            "",
            "| Aircraft | p50 ratio (range) | p95 ratio (range) |",
            "| --- | ---: | ---: |",
        ])
        for case in comparison["cases"]:
            lines.append(
                f"| `{case['key']}` | {format_ratio_summary(case['paired_p50_ratio_v2_over_legacy'])} | "
                f"{format_ratio_summary(case['paired_p95_ratio_v2_over_legacy'])} |"
            )
    if failures:
        lines.extend(["", "Failures:", *[f"- {failure}" for failure in failures]])
    (out_dir / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"AS-04 paired {'PASS' if not failures else 'FAIL'}: evidence {out_dir}")
    for failure in failures:
        print(f"  - {failure}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
