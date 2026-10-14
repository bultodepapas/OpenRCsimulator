"""Run the HELI-20 full-session step probe and write reproducible evidence."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = Path(__file__).with_name("profile.gd")
APP = ROOT / "app"
DEFAULT_OUT = ROOT / "docs" / "research" / "helicopter" / "HELI-20"
SAMPLE_FILES = ("samples.json", "samples.csv")
SOURCE_FILES = [
    APP / "project.godot",
    APP / "sim" / "simulation.gd",
    APP / "sim" / "helicopter_flight_session.gd",
    APP / "physics" / "rigid_body.gd",
    APP / "physics" / "math3d.gd",
    APP / "physics" / "ground_surfaces.gd",
    APP / "physics" / "ground_terrain.gd",
    APP / "physics" / "rotorcraft_data.gd",
    APP / "data" / "field_loader.gd",
    APP / "data" / "fields" / "default.json",
    APP / "data" / "ground" / "surface_friction.json",
    APP / "data" / "aircraft" / "xcell_60_research.json",
    SCRIPT,
    Path(__file__).resolve(),
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes() -> dict[str, str]:
    files = list(SOURCE_FILES)
    files.extend(sorted((APP / "physics" / "rotorcraft").glob("*.gd")))
    files.extend(sorted((APP / "sim").glob("*.gd")))
    files.extend(sorted((APP / "input").glob("*.gd")))
    files.extend(sorted((APP / "physics").glob("*.gd")))
    return {
        path.relative_to(ROOT).as_posix(): sha256(path)
        for path in sorted(set(files))
        if path.is_file()
    }


def git_head() -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def nearest_rank(values: list[int], percentile: float) -> int:
    ordered = sorted(values)
    rank = max(1, int((len(ordered) * percentile + 0.999999999999)))
    return ordered[min(len(ordered), rank) - 1]


def command_prefix(godot: Path) -> list[str]:
    return [str(godot), "--headless", "--path", str(APP), "--script", str(SCRIPT)]


def run_probe(args: argparse.Namespace) -> tuple[dict, str]:
    command = command_prefix(args.godot) + ["--", f"--steady-ticks={args.steady_ticks}",
        f"--soft-spool-ticks={args.soft_spool_ticks}", f"--warmup-ticks={args.warmup_ticks}"]
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=args.timeout_s)
    output = completed.stdout + completed.stderr
    marker = "HELI_PROFILE_RESULT_JSON:"
    error_marker = "HELI_PROFILE_ERROR_JSON:"
    result_line = next((line for line in output.splitlines() if line.startswith(marker)), None)
    error_line = next((line for line in output.splitlines() if line.startswith(error_marker)), None)
    if completed.returncode != 0 or result_line is None:
        detail = error_line[len(error_marker):] if error_line else output[-5000:]
        raise RuntimeError(f"Godot probe exited {completed.returncode}: {detail}")
    return json.loads(result_line[len(marker):]), output


def summarize(samples: list[dict]) -> dict:
    timings = [int(sample["elapsed_usec"]) for sample in samples]
    return {
        "raw_ticks": len(timings),
        "accepted_ticks": sum(1 for sample in samples if sample.get("accepted", False)),
        "p50_usec": nearest_rank(timings, 0.50),
        "p95_usec": nearest_rank(timings, 0.95),
        "p99_usec": nearest_rank(timings, 0.99),
        "max_usec": max(timings),
        "min_usec": min(timings),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path, help="Godot 4.7.2 console executable")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--steady-ticks", type=int, default=2400)
    parser.add_argument("--soft-spool-ticks", type=int, default=12 * 240)
    parser.add_argument("--warmup-ticks", type=int, default=120)
    parser.add_argument("--timeout-s", type=int, default=900)
    parser.add_argument("--load-note", default="Development run with concurrent root cycle/UI tests; host load was not isolated.")
    parser.add_argument("--parse-only", action="store_true", help="Parse the GDScript without running scenarios")
    args = parser.parse_args()
    args.godot = args.godot.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if args.parse_only:
        checked = subprocess.run(command_prefix(args.godot) + ["--", "--parse-only"], cwd=ROOT,
                                 capture_output=True, text=True, encoding="utf-8", errors="replace",
                                 timeout=120)
        sys.stdout.write(checked.stdout)
        sys.stderr.write(checked.stderr)
        return checked.returncode
    for value, name in [(args.steady_ticks, "steady ticks"),
                        (args.soft_spool_ticks, "soft-spool ticks")]:
        if value <= 0:
            parser.error(f"{name} must be positive")
    if args.warmup_ticks < 0:
        parser.error("warmup ticks cannot be negative")

    before_hashes = source_hashes()
    head_before = git_head()
    started_utc = datetime.now(timezone.utc).isoformat()
    godot_version = subprocess.check_output([str(args.godot), "--version"], cwd=ROOT,
                                            text=True, stderr=subprocess.STDOUT).strip()
    report, raw_output = run_probe(args)
    ended_utc = datetime.now(timezone.utc).isoformat()
    after_hashes = source_hashes()
    head_after = git_head()
    changed_sources = sorted(path for path in set(before_hashes) | set(after_hashes)
                             if before_hashes.get(path) != after_hashes.get(path))

    flat_samples: list[dict] = []
    scenarios = []
    for scenario in report["scenarios"]:
        name = scenario["name"]
        samples = []
        for sample in scenario.pop("samples"):
            row = {"scenario": name, **sample, "accepted": True}
            samples.append(row)
            flat_samples.append(row)
        scenarios.append({**scenario, **summarize(samples)})

    metadata = {
        "format": "openrc-heli-session-performance-v1",
        "started_utc": started_utc,
        "ended_utc": ended_utc,
        "step_call": report["step_call"],
        "tick_rate_hz": report["tick_rate_hz"],
        "tick_duration_s": report["tick_duration_s"],
        "timing_clock": report["timing_clock"],
        "percentile_method": "nearest rank, ceil(p*n), one-indexed",
        "control_trace_recording": report["control_trace_recording"],
        "accepted_tick_observer": report["accepted_tick_observer"],
        "sample_timing_includes_signal_observers": report["sample_timing_includes_signal_observers"],
        "settings": report["settings"],
        "environment": {
            "run_context": "development",
            "godot_version": godot_version,
            "os": platform.platform(),
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "processor": platform.processor(),
            "logical_cpu_count": os.cpu_count(),
            "python_version": platform.python_version(),
        },
        "git_head_before": head_before,
        "git_head_after": head_after,
        "source_sha256": after_hashes,
        "source_hash_stable_during_run": before_hashes == after_hashes,
        "source_sha256_before": before_hashes,
        "source_changes_during_run": changed_sources,
        "source_consistency_note": "A changed source path is retained in the evidence; compare before/after hashes before interpreting that profile.",
        "host_load_note": args.load_note,
        "qualification": {
            "h15_qualification": False,
            "note": "Host concurrency and thermal state were not controlled; this software timing sample is research evidence, not H15 qualification.",
        },
        "scenarios": scenarios,
        "samples_json": SAMPLE_FILES[0],
        "samples_csv": SAMPLE_FILES[1],
        "raw_stdout_stderr_sha256": hashlib.sha256(raw_output.encode("utf-8")).hexdigest(),
    }
    (out / "performance.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    (out / SAMPLE_FILES[0]).write_text(json.dumps(flat_samples, indent=2) + "\n", encoding="utf-8")
    with (out / SAMPLE_FILES[1]).open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["scenario", "sample_index", "tick", "sim_time_s",
                                                     "elapsed_usec", "omega_rad_s", "rpm", "accepted"])
        writer.writeheader()
        writer.writerows(flat_samples)
    print(json.dumps({"performance": str(out / "performance.json"),
                      "samples_json": str(out / SAMPLE_FILES[0]),
                      "samples_csv": str(out / SAMPLE_FILES[1]),
                      "scenarios": [{key: row[key] for key in ["name", "raw_ticks", "p50_usec",
                                                                  "p95_usec", "p99_usec", "max_usec"]}
                                    for row in scenarios]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
