#!/usr/bin/env python3
"""Run bounded headless driving trials through Godot's real ground-vehicle session."""

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
SCRIPT = Path(__file__).with_name("run_drive.gd")
DEFAULT_GODOT = ROOT / ".tools" / "Godot_v4.7.2-stable_win64.exe"
WINDOWS_NO_WINDOW = 0x08000000
ENGINE_ERROR = re.compile(r"(?m)^(?:SCRIPT ERROR:|SHADER ERROR:|Parse Error:|ERROR:)")
SOURCE_FILES = (
    Path("research/rc-monster-truck/driving/run_drive.gd"),
    Path("research/rc-monster-truck/driving/run_drive.py"),
    Path("app/sim/ground_vehicle/session.gd"),
    Path("app/physics/ground_vehicle/vehicle_dynamics.gd"),
    Path("app/physics/ground_vehicle/airfield_course.gd"),
    Path("app/physics/ground_vehicle/airfield_track.gd"),
    Path("app/physics/ground_vehicle/vehicle_data.gd"),
    Path("app/physics/ground_terrain.gd"),
    Path("app/physics/ground_contact.gd"),
    Path("app/data/ground_vehicle/airfield_track.json"),
    Path("app/data/ground/surface_friction.json"),
    Path("app/data/vehicles/ground/mt8_bisonte.json"),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_snapshot(vehicle: Path | None) -> dict[str, str | None]:
    paths = list(SOURCE_FILES)
    if vehicle is not None:
        try:
            vehicle_key = vehicle.resolve().relative_to(ROOT).as_posix()
        except ValueError:
            vehicle_key = str(vehicle.resolve())
        if Path(vehicle_key) not in paths:
            paths.append(Path(vehicle_key))
    snapshot: dict[str, str | None] = {}
    for relative in paths:
        path = relative if relative.is_absolute() else ROOT / relative
        snapshot[relative.as_posix()] = sha256(path) if path.is_file() else None
    return snapshot


def run(args: argparse.Namespace) -> int:
    godot = args.godot.resolve()
    output = args.output.resolve()
    json_path = output.with_suffix(".json")
    log_path = output.with_suffix(".log")
    for path in (godot, SCRIPT):
        if not path.is_file():
            raise ValueError(f"required file does not exist: {path}")
    if not output.parent.is_dir():
        raise ValueError(f"output directory must already exist: {output.parent}")
    for path in (output, json_path, log_path):
        if path.exists():
            raise ValueError(f"refusing to replace existing result: {path}")
    if args.max_seconds is not None and not 1.0 <= args.max_seconds <= 180.0:
        raise ValueError("--max-seconds must be in [1, 180]")
    if not 1 <= args.timeout <= 300:
        raise ValueError("--timeout must be in [1, 300] seconds")

    command = [
        str(godot),
        "--headless",
        "--path",
        str(ROOT / "app"),
        "--audio-driver",
        "Dummy",
        "--script",
        str(SCRIPT.resolve()),
        "--",
        f"--scenario={args.scenario}",
        f"--pace={args.pace}",
        f"--output={output.as_posix()}",
    ]
    if args.vehicle is not None:
        vehicle = args.vehicle.resolve()
        if not vehicle.is_file():
            raise ValueError(f"vehicle JSON does not exist: {vehicle}")
        command.append(f"--vehicle={vehicle.as_posix()}")
    if args.max_seconds is not None:
        command.append(f"--max-seconds={args.max_seconds:g}")

    before_sources = source_snapshot(args.vehicle)
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
    after_sources = source_snapshot(args.vehicle)
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
    if report.get("format") != "openrc-rcv-drive-run" or report.get("version") != 1:
        raise ValueError(f"unsupported result format in {json_path}")
    if report.get("csv", {}).get("sha256") != sha256(output):
        raise ValueError(f"CSV hash mismatch in {json_path}")
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
    if len(rows) != report.get("sample_count") or len(rows) != report.get("csv", {}).get("rows"):
        raise ValueError(f"sample count mismatch between {output} and {json_path}")
    if rows and int(rows[-1]["tick"]) != report.get("ticks"):
        raise ValueError(f"last CSV tick does not match {json_path}")
    json_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        f"scenario={report['scenario']} pace={report.get('pace', args.pace)} complete={report['complete']} "
        f"ticks={report['ticks']} max_speed_mps={report['max_speed_mps']:.6f} "
        f"tick_p95_us={report['session_tick_cost_us']['p95']:.3f}"
    )
    print(f"CSV: {output}\nJSON: {json_path}\nLog: {log_path}")
    if not report.get("complete"):
        print(f"route outcome: incomplete ({report.get('failure_reason', 'unknown')})")
        return 1
    if report["source_manifest"]["changed_during_run"]:
        print("source inputs changed during the run; retained output is not a stable comparison", file=sys.stderr)
        return 1
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--godot", type=Path, default=DEFAULT_GODOT)
    result.add_argument("--scenario", choices=("runway", "circuit", "slalom"), required=True)
    result.add_argument("--pace", choices=("steady", "fast"), default="steady")
    result.add_argument("--output", type=Path, required=True, help="fresh .csv path; .json and .log sidecars are also written")
    result.add_argument("--vehicle", type=Path, help="vehicle v1 JSON; omit to load the current generated default")
    result.add_argument("--max-seconds", type=float, help="simulation limit (default: 12 s runway, 90 s routes; range 1..180)")
    result.add_argument("--timeout", type=int, default=300, help="Godot subprocess wall-time limit (1..300 seconds)")
    return result


def main() -> int:
    args = parser().parse_args()
    if args.output.suffix.lower() != ".csv":
        parser().error("--output must use the .csv extension")
    try:
        return run(args)
    except (OSError, ValueError, json.JSONDecodeError, csv.Error, KeyError) as exc:
        print(f"drive run failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
