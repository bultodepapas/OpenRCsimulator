#!/usr/bin/env python3
"""Run the explicitly selected audit baselines through OpenRC's checked runner.

Run only after the pinned editor has imported the complete project resources.
These are software/reference baselines, not native-package or physical acceptance.
The caller retains the project's test-pool/admission and single-engine ownership.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_ENGINE = "4.8.beta2.official.cafc17a19"
CASES = (
    "math3d", "rigid_body", "integrator", "sf_law_properties",
    "sf_event_refinement", "simulation", "atmosphere",
    "atmosphere_column_session", "air_data", "aero", "ground_effect",
    "ground_friction", "mass_inventory", "rotor_coupling",
    "heli_main_rotor", "heli_inflow", "heli_drive", "heli_aerodynamic_stage",
    "mr_electric_bus", "mr_sample_rate", "electric_motor", "battery_pack_ecm",
    "turbine_continuous", "glow_flight_physics", "airship_dynamics",
    "rcv_suspension", "rcv_vehicle_dynamics",
)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def source_identity() -> dict:
    paths = git("ls-files", "app/physics", "app/sim", "app/data",
                "research/native-kernel/src", "app/project.godot").splitlines()
    rows = [(p, digest(ROOT / p)) for p in paths if (ROOT / p).is_file()]
    raw = json.dumps(rows, separators=(",", ":")).encode()
    return {"git_commit": git("rev-parse", "HEAD"),
            "physics_tree": git("rev-parse", "HEAD:app/physics"),
            "simulation_tree": git("rev-parse", "HEAD:app/sim"),
            "native_tree": git("rev-parse", "HEAD:research/native-kernel/src"),
            "materialized_source_files": len(rows),
            "materialized_source_sha256": hashlib.sha256(raw).hexdigest()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True,
                        help="A new, nonexistent output directory")
    parser.add_argument("--case", action="append", choices=CASES)
    args = parser.parse_args()
    engine = args.godot.resolve()
    out = args.out.resolve()
    if out.exists():
        parser.error("--out must not exist; preserve previous evidence")
    version = subprocess.check_output([str(engine), "--version"], text=True).strip()
    if version != EXPECTED_ENGINE:
        parser.error(f"expected {EXPECTED_ENGINE}, got {version}")
    selected = args.case or list(CASES)
    if len(set(selected)) != len(selected):
        parser.error("duplicate case names are not allowed")
    out.mkdir(parents=True)
    before = source_identity()
    receipt = {
        "format": "openrc-native-physics-audit-baseline-v1",
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "selected software/reference checks; native skips remain explicit",
        "engine": {"version": version, "sha256": digest(engine)},
        "environment": {"platform": platform.platform(), "python": platform.python_version(),
                        "logical_cpus": os.cpu_count(), "gpu_device_present": Path("/dev/dri").exists()},
        "source_before": before, "requested_cases": selected, "cases": [],
    }
    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(out / "profile")
    for name in selected:
        script = ROOT / "app/tests" / f"test_{name}.gd"
        case_dir = out / name
        marker = "0 failures" if name == "rcv_vehicle_dynamics" else "0 failed"
        command = [sys.executable, str(ROOT / "tools/godot/run_checked.py"),
                   "--label", name, "--timeout", "240", "--out-dir", str(case_dir),
                   "--require-text", marker, "--", str(engine), "--headless",
                   "--path", str(ROOT / "app"), "--audio-driver", "Dummy",
                   "--script", f"res://tests/test_{name}.gd"]
        result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        reports = list(case_dir.glob("*/report.json"))
        logs = list(case_dir.glob("*/engine.log"))
        checked = json.loads(reports[0].read_text()) if len(reports) == 1 else {}
        log = logs[0].read_text(errors="replace") if len(logs) == 1 else ""
        summaries = re.findall(r"(\d+) checks, (\d+) fail(?:ed|ures)(?:, (\d+) exempt)?", log)
        row = {"case": name, "script": script.relative_to(ROOT).as_posix(),
               "script_sha256": digest(script), "returncode": result.returncode,
               "checked_ok": checked.get("ok", False), "completion_marker": marker,
               "completion_seen": marker in log,
               "report": str(reports[0].relative_to(out)) if len(reports) == 1 else None,
               "log_sha256": digest(logs[0]) if len(logs) == 1 else None,
               "summary": summaries[-1] if summaries else None,
               "qualifications": [line for line in log.splitlines()
                                  if any(t in line.lower() for t in ("skip", "exempt", "unavailable", "baseline:", "phase cost:", "note "))],
               "runner_tail": result.stdout.splitlines()[-12:]}
        row["ok"] = result.returncode == 0 and row["checked_ok"] and row["completion_seen"]
        receipt["cases"].append(row)
        (out / "baseline.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps({"case": name, "ok": row["ok"], "summary": row["summary"],
                          "qualifications": row["qualifications"]}), flush=True)
    receipt["source_after"] = source_identity()
    receipt["source_unchanged"] = before == receipt["source_after"]
    receipt["finished_utc"] = datetime.now(timezone.utc).isoformat()
    receipt["complete"] = len(receipt["cases"]) == len(selected)
    receipt["ok"] = receipt["complete"] and receipt["source_unchanged"] and all(r["ok"] for r in receipt["cases"])
    (out / "baseline.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"complete": receipt["complete"], "ok": receipt["ok"],
                      "source_unchanged": receipt["source_unchanged"]}), flush=True)
    return 0 if receipt["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
