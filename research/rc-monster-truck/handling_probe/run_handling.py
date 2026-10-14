#!/usr/bin/env python3
"""Run bounded RC handling traces with a pinned solver, vehicle, and native backend."""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = Path(__file__).with_name("handling_probe.gd")
DEFAULT_GODOT = ROOT / ".tools" / "Godot_v4.7.2-stable_win64.exe"
WINDOWS_NO_WINDOW = 0x08000000
ENGINE_ERROR = re.compile(r"(?m)^(?:SCRIPT ERROR:|SHADER ERROR:|Parse Error:|ERROR:)")
BASELINE_ROOT = Path("research/rc-monster-truck/handling_probe/baseline_sources")
BASELINE_PROJECT = BASELINE_ROOT / "app"
COMMON_FILES = (
    Path("research/rc-monster-truck/handling_probe/handling_probe.gd"),
    Path("research/rc-monster-truck/handling_probe/run_handling.py"),
)
BASELINE_FILES = (
    BASELINE_PROJECT / "project.godot",
    BASELINE_PROJECT / "physics/math3d.gd",
    BASELINE_PROJECT / "physics/integrator.gd",
    BASELINE_PROJECT / "physics/rigid_body.gd",
    BASELINE_PROJECT / "physics/ground_vehicle/vehicle_dynamics.gd",
    BASELINE_PROJECT / "physics/ground_vehicle/vehicle_data.gd",
    BASELINE_PROJECT / "physics/ground_vehicle/course.gd",
    BASELINE_PROJECT / "data/ground_vehicle/practice.json",
    BASELINE_PROJECT / "data/vehicles/ground/mt8_bisonte.json",
    BASELINE_PROJECT / "native/ground_vehicle/openrc_ground_vehicle.gdextension",
    BASELINE_PROJECT / "native/ground_vehicle/build-receipt.json",
    BASELINE_PROJECT / "native/ground_vehicle/openrc_ground_vehicle.dll",
    BASELINE_ROOT / "research/rc-monster-truck/native/src/ground_vehicle_kernel.hpp",
    BASELINE_ROOT / "research/rc-monster-truck/native/src/ground_vehicle_native.cpp",
    BASELINE_ROOT / "research/rc-monster-truck/native/toolchain-lock.json",
)
CURRENT_FILES = (
    Path("app/physics/math3d.gd"),
    Path("app/physics/integrator.gd"),
    Path("app/physics/ground_vehicle/vehicle_dynamics.gd"),
    Path("app/physics/ground_vehicle/vehicle_data.gd"),
    Path("app/native/ground_vehicle/openrc_ground_vehicle.gdextension"),
    Path("app/native/ground_vehicle/build-receipt.json"),
    Path("app/native/ground_vehicle/openrc_ground_vehicle.dll"),
    BASELINE_ROOT / "app/physics/ground_vehicle/course.gd",
    BASELINE_ROOT / "app/data/ground_vehicle/practice.json",
    Path("research/rc-monster-truck/native/src/ground_vehicle_kernel.hpp"),
    Path("research/rc-monster-truck/native/src/ground_vehicle_native.cpp"),
    Path("research/rc-monster-truck/native/toolchain-lock.json"),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_snapshot(solver: str, vehicle: Path) -> dict[str, str | None]:
    paths = [*COMMON_FILES, *(BASELINE_FILES if solver == "baseline" else CURRENT_FILES), vehicle]
    snapshot: dict[str, str | None] = {}
    for relative in dict.fromkeys(paths):
        path = relative if relative.is_absolute() else ROOT / relative
        try:
            key = path.resolve().relative_to(ROOT).as_posix()
        except ValueError:
            key = str(path.resolve())
        snapshot[key] = sha256(path) if path.is_file() else None
    return snapshot


def run(args: argparse.Namespace) -> int:
    godot = args.godot.resolve()
    output = args.output.resolve()
    json_path = output.with_suffix(".json")
    log_path = output.with_suffix(".log")
    default_vehicle = (
        ROOT / BASELINE_PROJECT / "data/vehicles/ground/mt8_bisonte.json"
        if args.solver == "baseline"
        else ROOT / "app/data/vehicles/ground/mt8_bisonte.json"
    )
    vehicle = (args.vehicle or default_vehicle).resolve()
    for path in (godot, SCRIPT, vehicle):
        if not path.is_file():
            raise ValueError(f"required file does not exist: {path}")
    if not output.parent.is_dir():
        raise ValueError(f"output directory must already exist: {output.parent}")
    for path in (output, json_path, log_path):
        if path.exists():
            raise ValueError(f"refusing to replace existing result: {path}")
    if not 1 <= args.timeout <= 300:
        raise ValueError("--timeout must be in [1, 300] seconds")

    command = [
        str(godot),
        "--headless",
        "--path",
        str(ROOT / (BASELINE_PROJECT if args.solver == "baseline" else Path("app"))),
        "--audio-driver",
        "Dummy",
        "--script",
        str(SCRIPT.resolve()),
        "--",
        f"--scenario={args.scenario}",
        f"--solver={args.solver}",
        f"--speed={args.speed:.9g}",
        f"--vehicle={vehicle.as_posix()}",
        f"--output={output.as_posix()}",
    ]
    before_sources = source_snapshot(args.solver, vehicle)
    started_utc = datetime.now(timezone.utc).isoformat()
    creationflags = WINDOWS_NO_WINDOW if os.name == "nt" else 0
    try:
        result = subprocess.run(
            command,
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=args.timeout,
            check=False,
            creationflags=creationflags,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout.decode("utf-8", "replace") if isinstance(exc.stdout, bytes) else exc.stdout or ""
        stderr = exc.stderr.decode("utf-8", "replace") if isinstance(exc.stderr, bytes) else exc.stderr or ""
        log_path.write_text(
            f"command: {command!r}\ntimeout_seconds: {args.timeout}\n\n{stdout}\n{stderr}",
            encoding="utf-8",
        )
        print(f"Godot timed out after {args.timeout}s; log: {log_path}", file=sys.stderr)
        return 124

    finished_utc = datetime.now(timezone.utc).isoformat()
    after_sources = source_snapshot(args.solver, vehicle)
    combined = result.stdout + ("\n" if result.stdout and result.stderr else "") + result.stderr
    log_path.write_text(f"command: {command!r}\nexit_code: {result.returncode}\n\n{combined}", encoding="utf-8")
    if result.returncode != 0:
        print(f"Godot exited {result.returncode}; log: {log_path}", file=sys.stderr)
        return result.returncode
    if ENGINE_ERROR.search(combined):
        print(f"Godot emitted an engine/script error; log: {log_path}", file=sys.stderr)
        return 1
    if not output.is_file() or not json_path.is_file():
        print(f"Godot did not write both result files; log: {log_path}", file=sys.stderr)
        return 1

    report = json.loads(json_path.read_text(encoding="utf-8"))
    if report.get("format") != "openrc-rcv-handling-probe" or report.get("version") != 1:
        raise ValueError(f"unsupported result format in {json_path}")
    if report.get("csv", {}).get("sha256") != sha256(output):
        raise ValueError(f"CSV hash mismatch in {json_path}")
    if report.get("backend_identity", {}).get("backend") != "native":
        raise ValueError(f"native backend was not active in {json_path}")
    report["source_manifest"] = {
        "captured_before_utc": started_utc,
        "captured_after_utc": finished_utc,
        "before_sha256": before_sources,
        "after_sha256": after_sources,
        "changed_during_run": sorted(
            key for key in set(before_sources) | set(after_sources)
            if before_sources.get(key) != after_sources.get(key)
        ),
    }
    with output.open("r", newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != report.get("csv", {}).get("rows"):
        raise ValueError(f"sample count mismatch between {output} and {json_path}")
    json_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        f"scenario={report['scenario']} solver={report['solver_mode']} complete={report['complete']} "
        f"backend={report['backend_identity']['backend']} cases={len(report['cases'])} rows={len(rows)}"
    )
    print(f"CSV: {output}\nJSON: {json_path}\nLog: {log_path}")
    if report["source_manifest"]["changed_during_run"]:
        print("input sources changed during the run; trace is not a stable comparison", file=sys.stderr)
        return 1
    return 0 if report.get("complete") else 2


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--godot", type=Path, default=DEFAULT_GODOT)
    result.add_argument("--scenario", choices=("all", "brake", "swerve"), default="all")
    result.add_argument("--solver", choices=("baseline", "current"), default="baseline")
    result.add_argument("--speed", type=float, default=10.0, help="forward speed in m/s; 1..20")
    result.add_argument("--vehicle", type=Path, help="vehicle descriptor JSON; omitted selects the solver's default")
    result.add_argument("--output", type=Path, required=True, help="fresh .csv path; .json and .log sidecars are written")
    result.add_argument("--timeout", type=int, default=300, help="Godot subprocess wall-time limit (1..300 seconds)")
    return result


def main() -> int:
    args = parser().parse_args()
    if args.output.suffix.lower() != ".csv":
        parser().error("--output must use the .csv extension")
    if not 1.0 <= args.speed <= 20.0:
        parser().error("--speed must be in [1, 20] m/s")
    try:
        return run(args)
    except (OSError, ValueError, json.JSONDecodeError, csv.Error, KeyError) as exc:
        print(f"handling run failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
