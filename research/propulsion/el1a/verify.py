#!/usr/bin/env python3
"""EL1a: isolated source verification and mutations; no aircraft calibration."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
FILES = [f"physics/{name}.gd" for name in (
    "electric_motor", "propulsion", "turbine", "math3d", "rigid_body", "rotor_coupling"
)] + ["tests/test_electric_motor.gd"]
MUTATIONS = {
    "battery_current_ignores_duty": (
        "var battery_current: float = effective_duty * current",
        "var battery_current: float = current", "battery current includes duty"),
    "wrong_kv_units": (
        "var kt: float = 60.0 / TAU / kv",
        "var kt: float = 1.0 / kv", "shaft torque uses SI conversion"),
    "coast_loses_mechanical_drag": (
        "var torque: float = electromagnetic_torque - loss_torque",
        "var torque: float = maxf(0.0, electromagnetic_torque - loss_torque)",
        "coasting keeps mechanical loss"),
    "ignore_disable": (
        "var effective_duty: float = duty if enabled else 0.0",
        "var effective_duty: float = duty", "disabled equals duty zero"),
}


def run(godot: Path, project: Path) -> dict:
    result = subprocess.run(
        [str(godot), "--headless", "--path", str(project), "--audio-driver", "Dummy",
         "--script", "res://tests/test_electric_motor.gd"],
        capture_output=True, text=True, timeout=30,
    )
    log = result.stdout + result.stderr
    summary = re.search(r"EL1a electric source: (\d+) checks, (\d+) failed", log)
    engine_errors = bool(re.search(r"^(?:SCRIPT |SHADER )?ERROR:", log, re.M))
    if summary is None or int(summary[1]) <= 0 or engine_errors:
        raise RuntimeError(f"Missing completed suite or engine error:\n{log}")
    return {"exit_code": result.returncode, "checks": int(summary[1]),
            "failures": int(summary[2]), "engine_errors": engine_errors,
            "observations": [line for line in log.splitlines() if line.startswith("EL1a ")],
            "failed_assertions": [line for line in log.splitlines() if line.startswith("FAIL:")]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    godot = args.godot or Path(subprocess.check_output(
        [str(ROOT / "app/get-godot.sh")], text=True).strip())
    godot = godot.resolve()
    sources = {name: (ROOT / "app" / name).read_bytes() for name in FILES}
    report = {"format": "openrc-electric-source-proof v1", "scope": "synthetic verification only",
              "godot": subprocess.check_output([str(godot), "--version"], text=True).strip(),
              "sha256": {name: hashlib.sha256(data).hexdigest() for name, data in sources.items()}}
    # New disposable project, no shared .godot cache and no mutation of the working app.
    with tempfile.TemporaryDirectory(prefix="openrc-el1a-") as directory:
        project = Path(directory)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="EL1a probe"\n')
        for name, data in sources.items():
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        report["control"] = run(godot, project)
        if report["control"]["exit_code"] or report["control"]["failures"]:
            raise RuntimeError(f"Control failed: {report['control']}")
        original = sources["physics/electric_motor.gd"].decode()
        outcomes = {}
        for name, (old, new, assertion) in MUTATIONS.items():
            if original.count(old) != 1:
                raise RuntimeError(f"Mutation target must be unique: {name}")
            (project / "physics/electric_motor.gd").write_text(original.replace(old, new))
            outcome = run(godot, project)
            if outcome["exit_code"] != 1 or not outcome["failures"] or not any(
                assertion in line for line in outcome["failed_assertions"]
            ):
                raise RuntimeError(f"Mutation did not fail the intended assertion: {name}: {outcome}")
            outcomes[name] = {"rejected": True, "checks": outcome["checks"],
                              "failures": outcome["failures"], "assertion": assertion}
        report["mutations"] = outcomes
    if any((ROOT / "app" / name).read_bytes() != data for name, data in sources.items()):
        raise RuntimeError("Source changed during proof; rerun against a stable snapshot")
    report["ok"] = True
    encoded = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded)
    else:
        print(encoded, end="")


if __name__ == "__main__":
    main()
