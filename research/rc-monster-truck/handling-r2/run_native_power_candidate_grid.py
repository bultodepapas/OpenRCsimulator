#!/usr/bin/env python3
"""Run a final bounded full-throttle candidate scan on the installed native RCV kernel."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).with_name("native_power_candidate_grid.gd")
TEMP_SCRIPT = ROOT / "app" / "tests" / "_handling_r2_native_power_candidate_grid_temp.gd"
TEMP_UID = TEMP_SCRIPT.with_suffix(TEMP_SCRIPT.suffix + ".uid")
GODOT = ROOT / ".tools" / "Godot_v4.7.2-stable_win64.exe"
OUTPUT_DIR = Path(__file__).parent
LOG_PATH = OUTPUT_DIR / "native-power-candidate-grid.log"
JSON_PATH = OUTPUT_DIR / "native-power-candidate-grid.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    if not GODOT.is_file():
        raise SystemExit("Godot 4.7.2 is missing")
    if TEMP_SCRIPT.exists() or TEMP_UID.exists():
        raise SystemExit("Temporary app script path already exists; refusing to overwrite it")
    if LOG_PATH.exists() or JSON_PATH.exists():
        raise SystemExit("Output exists; refusing to overwrite evidence")

    source_sha = sha256(SOURCE)
    TEMP_SCRIPT.write_bytes(SOURCE.read_bytes())
    try:
        process = subprocess.run(
            [
                str(GODOT),
                "--headless",
                "--path",
                str(ROOT / "app"),
                "--script",
                "res://tests/_handling_r2_native_power_candidate_grid_temp.gd",
            ],
            cwd=ROOT / "app",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
            check=False,
        )
    finally:
        if TEMP_SCRIPT.exists() and sha256(TEMP_SCRIPT) == source_sha:
            TEMP_SCRIPT.unlink()
        if TEMP_UID.exists():
            TEMP_UID.unlink()

    LOG_PATH.write_text(process.stdout, encoding="utf-8")
    if process.returncode != 0:
        raise SystemExit(f"Native power scan failed with exit {process.returncode}; see {LOG_PATH}")
    payload = next(
        (line.removeprefix("RESULT_JSON ") for line in process.stdout.splitlines()
         if line.startswith("RESULT_JSON ")),
        None,
    )
    if payload is None:
        raise SystemExit(f"Native power scan did not emit RESULT_JSON; see {LOG_PATH}")
    result = json.loads(payload)
    result["probe_script_sha256"] = source_sha
    result["runtime_source_sha256"] = sha256(ROOT / "app" / "physics" / "ground_vehicle" / "vehicle_dynamics.gd")
    result["native_kernel_sha256"] = sha256(ROOT / "research" / "rc-monster-truck" / "native" / "src" / "ground_vehicle_kernel.hpp")
    JSON_PATH.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {JSON_PATH.relative_to(ROOT)}")
    for case in result["cases"]:
        print(
            f"{case['torque_per_wheel_nm']:.1f} Nm/wheel @ fade {case['torque_fade_rad_s']:.0f}: "
            f"t3={case['time_to_3mps_s']:.4g}s, "
            f"vmax={case['max_speed_mps']:.4g}m/s, "
            f"vfinal={case['final_speed_mps']:.4g}m/s, "
            f"upright_min={case['min_upright_cos']:.4g}, "
            f"peak pitch={case['peak_pitch_deg']:.4g} deg @ {case['peak_pitch_s']:.4g}s, "
            f"hull_ticks={case['hull_contact_ticks']}, "
            f"E={case['start_energy_j']:.4g}->{case['final_energy_j']:.4g}J, "
            f"complete={case['complete']} ({case['termination']})"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
