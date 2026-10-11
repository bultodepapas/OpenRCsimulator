#!/usr/bin/env python3
"""E5a focused Linux verification; all deliberately invalid data stays in a disposable clone."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
REL = Path("research/ground-contact/e5a")
DATA = Path("app/data/aircraft/gp_extra_300s_60.json")


def run(command, cwd, output):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=120,
                            env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
    log = result.stdout + result.stderr
    output.write_text(log)
    if re.search(r"(?:SCRIPT ERROR:|ERROR:|Parse Error:)", log):
        raise RuntimeError("engine error: " + str(output))
    return result.returncode, log


def checked_program(root, godot, script, output, expect_failure=False):
    code, log = run([str(godot), "--headless", "--path", str(root / "app"), "--script",
                     str(root / REL / script)], root, output)
    summary = re.findall(r"(\d+) checks, (\d+) failed", log)
    if not summary:
        raise RuntimeError("missing completed check summary: " + str(output))
    count, failed = map(int, summary[-1])
    good = count > 0 and ((code != 0 and failed > 0 and "FAIL " in log) if expect_failure else code == 0 and failed == 0)
    if not good:
        raise RuntimeError("unexpected test result: " + str(output))
    return {"checks": count, "failures": failed, "exit_code": code}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--mutations", action="store_true")
    args = parser.parse_args()
    godot = args.godot or Path(subprocess.check_output([str(ROOT / "app/get-godot.sh")], text=True).strip())
    godot = godot.resolve()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=False)
    results = {}
    code, _ = run(["python3", "research/extra-300/ex05/derive_physics.py", "--check"], ROOT, args.out / "generator.log")
    if code:
        raise RuntimeError("generated Extra files are stale")
    for script in ("checks.gd", "session.gd"):
        results[script] = checked_program(ROOT, godot, script, args.out / (script + ".log"))
    if args.mutations:
        with tempfile.TemporaryDirectory(prefix="openrc-e5a-mutations-") as directory:
            clone = Path(directory) / "repo"
            subprocess.run(["git", "clone", "--shared", "--quiet", str(ROOT), str(clone)], check=True)
            # Overlay only this step's artifacts so the tool also works before the change is committed.
            for path in [DATA, Path("research/extra-300/ex05/derive_physics.py"),
                         Path("research/extra-300/ex05/derivation.md"),
                         *[p.relative_to(ROOT) for p in (ROOT / REL).glob("*.gd")]]:
                (clone / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / path, clone / path)
            original = (clone / DATA).read_bytes()
            geometry_path = clone / "assets/aircraft/extra-300s-60/geometry.json"
            original_geometry = geometry_path.read_bytes()
            session_path = clone / REL / "session.gd"
            original_session = session_path.read_text()
            code, _ = run(["python3", "research/extra-300/ex05/derive_physics.py", "--check"],
                          clone, args.out / "clone-generator.log")
            if code:
                raise RuntimeError("generated Extra files are stale in fresh clone")
            results["clone_control"] = {}
            for script in ("checks.gd", "session.gd"):
                results["clone_control"][script] = checked_program(clone, godot, script, args.out / ("clone-" + script + ".log"))
            for mutation, script in [("steering_sign", "checks.gd"), ("tail_position", "checks.gd"),
                                     ("missing_wheel_radius", "checks.gd"), ("wheel_crash_hull", "session.gd"),
                                     ("inert_throttle", "session.gd")]:
                data = json.loads(original)
                if mutation == "steering_sign":
                    data["landing_gear"]["contacts"][2]["max_steering"]["value"] *= -1
                elif mutation == "tail_position":
                    data["landing_gear"]["contacts"][2]["position"]["value"][0] += 0.02
                elif mutation == "missing_wheel_radius":
                    geometry = json.loads(original_geometry)
                    del geometry["gear"]["main_wheel_diameter"]
                    geometry_path.write_text(json.dumps(geometry))
                elif mutation == "inert_throttle":
                    before = "flight.commands.throttle = 0.25 if"
                    if original_session.count(before) != 1:
                        raise RuntimeError("throttle mutation target is not unique")
                    session_path.write_text(original_session.replace(before, "flight.commands.throttle = 0.0 if"))
                else:
                    data["crash_hull"]["value"].append(data["landing_gear"]["contacts"][0]["position"]["value"])
                (clone / DATA).write_text(json.dumps(data, indent=2) + "\n")
                results[mutation] = checked_program(clone, godot, script, args.out / (mutation + ".log"), True)
                expected_marker = {"steering_sign": "gp-extra-300s-60: +right command",
                                   "tail_position": "gp-extra-300s-60: generator wheel bottoms",
                                   "missing_wheel_radius": "gp-extra-300s-60: generator wheel bottoms",
                                   "inert_throttle": "pulse produces resolved RPM response",
                                   "wheel_crash_hull": "completes without crash/fault"}[mutation]
                failed_lines = [line for line in (args.out / (mutation + ".log")).read_text().splitlines()
                                if line.startswith("FAIL ")]
                if not any(expected_marker in line for line in failed_lines):
                    raise RuntimeError("mutation missed its intended assertion: " + mutation)
                results[mutation]["intended_assertion_failed"] = True
                (clone / DATA).write_bytes(original)
                geometry_path.write_bytes(original_geometry)
                session_path.write_text(original_session)
    paths = [DATA, Path("research/extra-300/ex05/derive_physics.py"),
             Path("assets/aircraft/extra-300s-60/geometry.json"), Path("assets/aircraft/p51d-mustang-120/geometry.json"),
             Path("app/data/aircraft/p51d_mustang_120.json"), Path("app/physics/ground_contact.gd"),
             Path("app/physics/aircraft_data.gd"), Path("app/sim/flight_session.gd"), Path("app/sim/simulation.gd"),
             Path("app/data/aircraft/jensen_ugly_stik_60.json"), Path("app/data/fields/default.json"),
             Path("app/data/field_loader.gd"), Path("app/data/ground/surface_friction.json"),
             Path("app/physics/ground_surfaces.gd"),
             *[p.relative_to(ROOT) for p in sorted((ROOT / REL).glob("*.gd"))], REL / "verify.py"]
    report = {"ok": True, "physical_acceptance": False, "results": results,
              "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "input_sha256": {str(p): hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths},
              "godot_sha256": hashlib.sha256(godot.read_bytes()).hexdigest()}
    (args.out / "verification.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
