"""Run selected existing native checks with retained stdout, stderr and exit status."""
from __future__ import annotations

import json
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/research/physics-audit-2026-10-14/checks"
GODOT = ROOT / ".tools/Godot_v4.7.2-stable_win64_console.exe"
CHECKS = (
    "test_pilot_trim", "test_regime_consistency", "test_avanti_handling",
    "test_avanti_gamepad", "test_avanti_gamepad_flight", "test_aircraft_data",
    "test_rates", "test_turbine_continuous", "test_control_actuators",
    "test_checkpoint",
)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    for name in CHECKS:
        if not (ROOT / f"app/tests/{name}.gd").exists():
            records.append({"name": name, "status": "not present; not run"})
            continue
        command = [str(GODOT), "--headless", "--path", str(ROOT / "app"), "--audio-driver", "Dummy", "--script", f"res://tests/{name}.gd"]
        start = time.monotonic()
        try:
            completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
            log = completed.stdout + "\n--- STDERR ---\n" + completed.stderr
            errors = re.findall(r"^.*(?:SCRIPT ERROR|Parse Error|^ERROR:|^FAIL\b).*$", log, re.M)
            record = {"name": name, "command": command, "exit_code": completed.returncode, "engine_errors": errors, "passed": completed.returncode == 0 and not errors}
        except subprocess.TimeoutExpired as exc:
            log = str(exc.stdout or "") + "\n" + str(exc.stderr or "")
            record = {"name": name, "command": command, "passed": False, "timeout_seconds": 300}
        (OUT / f"{name}.log").write_text(log, encoding="utf-8")
        record["elapsed_seconds"] = round(time.monotonic() - start, 3)
        records.append(record)
        (OUT / "verification.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
        print(name, record.get("passed"), record["elapsed_seconds"], flush=True)


if __name__ == "__main__":
    main()
