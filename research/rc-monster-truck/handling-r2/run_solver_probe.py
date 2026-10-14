#!/usr/bin/env python3
"""Run the isolated Godot evaluator clone without retaining an app/ script."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).with_name("solver_probe.gd")
TEMP_SCRIPT = ROOT / "app" / "tests" / "_handling_r2_solver_probe_temp.gd"
TEMP_UID = TEMP_SCRIPT.with_suffix(TEMP_SCRIPT.suffix + ".uid")
GODOT = ROOT / ".tools" / "Godot_v4.7.2-stable_win64.exe"
BASELINE = ROOT / "docs" / "research" / "rc-monster-truck" / "RCV-handling" / "drive-baseline-vehicle.json"
OUTPUT_DIR = ROOT / "docs" / "research" / "rc-monster-truck" / "RCV-handling"
LOG_PATH = OUTPUT_DIR / "solver-probe.log"
JSON_PATH = OUTPUT_DIR / "solver-probe.json"


def main() -> int:
    if not GODOT.is_file() or not BASELINE.is_file():
        raise SystemExit("Godot 4.7.2 or the frozen drive baseline descriptor is missing")
    if TEMP_SCRIPT.exists() or TEMP_UID.exists():
        raise SystemExit("Temporary app script path already exists; refusing to overwrite it")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    script_bytes = SOURCE.read_bytes()
    script_sha256 = hashlib.sha256(script_bytes).hexdigest()
    TEMP_SCRIPT.write_bytes(script_bytes)
    try:
        command = [
            str(GODOT),
            "--headless",
            "--path",
            str(ROOT / "app"),
            "--script",
            "res://tests/_handling_r2_solver_probe_temp.gd",
            "--",
            "--handling-baseline=" + str(BASELINE),
        ]
        process = subprocess.run(
            command,
            cwd=ROOT / "app",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=45,
            check=False,
        )
    finally:
        if hashlib.sha256(TEMP_SCRIPT.read_bytes()).hexdigest() == script_sha256:
            TEMP_SCRIPT.unlink()
        if TEMP_UID.exists():
            TEMP_UID.unlink()

    LOG_PATH.write_text(process.stdout, encoding="utf-8")
    if process.returncode != 0:
        raise SystemExit(f"Godot probe failed with exit {process.returncode}; see {LOG_PATH}")
    payload = next(
        (line.removeprefix("RESULT_JSON ") for line in process.stdout.splitlines()
         if line.startswith("RESULT_JSON ")),
        None,
    )
    if payload is None:
        raise SystemExit(f"Godot probe did not emit RESULT_JSON; see {LOG_PATH}")
    result = json.loads(payload)
    result["probe_script_sha256"] = script_sha256
    JSON_PATH.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {JSON_PATH.relative_to(ROOT)}")
    for case in result["cases"]:
        straight = case["exact_symmetric_start"]["trajectory"]
        launch = case["shared_launch_start"]["trajectory"]
        print(
            f"{case['name']}: exact start peak yaw={straight['max_abs_yaw_deg']:.3f} deg, "
            f"shared-launch peak yaw={launch['max_abs_yaw_deg']:.3f} deg, "
            f"slip power max={straight['max_positive_slip_force_power_w']:.6g} W"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
