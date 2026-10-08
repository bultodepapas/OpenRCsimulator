#!/usr/bin/env python3
"""DATA-2a exact-grid verification, isolated mutation checks and paired loader timing."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ENGINE_ERROR = re.compile(r"^(?:SCRIPT |SHADER )?ERROR:", re.MULTILINE)


def execute(godot, script, env=None, expected=0):
    command = [godot, "--headless", "--path", str(ROOT/"app"), "--script", str(script)]
    run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240, env=env)
    if run.returncode != expected or ENGINE_ERROR.search(run.stdout):
        raise RuntimeError(f"{script}: exit {run.returncode}, expected {expected}\n{run.stdout}")
    return run.stdout


def hashes():
    paths = [ROOT/"app/physics"/name for name in ("aircraft_data.gd", "aero.gd", "math3d.gd")]
    paths += sorted((ROOT/"app/data/aircraft").glob("*.json"))
    paths += [ROOT/"app/tests/test_stall_solver.gd", HERE/"reference.gd", HERE/"sweep.gd", HERE/"bench.gd", HERE/"run.py"]
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="defaults to app/get-godot.sh")
    parser.add_argument("--output", type=Path, required=True, help="directory for evidence logs and verification.json")
    args = parser.parse_args()
    godot = args.godot or subprocess.check_output([str(ROOT/"app/get-godot.sh")], text=True).strip()
    before = hashes()
    args.output.mkdir(parents=True, exist_ok=True)
    log = execute(godot, ROOT/"app/tests/test_stall_solver.gd")
    if "571 checks, 0 failed" not in log:
        raise RuntimeError("focused check count changed")
    (args.output/"focused.log").write_text(log)
    print("571 focused checks pass", flush=True)
    loader = (ROOT/"app/physics/aircraft_data.gd").read_text()
    first = loader.index("static func _solve_stall_start(")
    last = loader.index("\n\n## Crash hull", first)
    original = (HERE/"reference.gd").read_text()
    original = original[original.index("static func _solve_stall_start("):]
    mutations = []
    with tempfile.TemporaryDirectory(prefix="openrc-data2-check-") as temp:
        directory = Path(temp)
        baseline = directory/"baseline.gd"
        baseline.write_text(loader[:first] + original + loader[last:])
        env = {**os.environ, "OPENRC_DATA2_BASELINE": str(baseline)}
        log = execute(godot, HERE/"bench.gd", env)
        (args.output/"timings.log").write_text(log)
        timings = [json.loads(line) for line in log.splitlines() if line.startswith("{")]
        if len(timings) != 4 or not all(case["exact_load_result"] and len(case["candidate_ms"]) == 12 for case in timings):
            raise RuntimeError("missing or nonidentical fleet loader cases")
        print("48 paired loader results are exactly equal", flush=True)
        tests = (ROOT/"app/tests/test_stall_solver.gd").read_text()
        for name, old, new in (
            ("omit_curvature", "var curvature: float = 2.0 * cd90 + 3.0 * slope_gap / blend_range + 6.0 * value_gap / (blend_range * blend_range)", "var curvature: float = 0.0"),
            ("wrong_negative_bound", "maxf(flo * sign, fhi * sign)", "maxf(flo, fhi)"),
            ("wrong_sample_grid", "float(mid) / 800.0", "float(mid) / 640.0"),
        ):
            section = loader[first:last]
            if section.count(old) != 1:
                raise RuntimeError(f"mutation anchor changed: {name}")
            mutated = directory/f"{name}.gd"
            mutated.write_text(loader[:first] + section.replace(old, new) + loader[last:])
            test = directory/f"test_{name}.gd"
            test.write_text(tests.replace('preload("res://physics/aircraft_data.gd")', f"preload({json.dumps(str(mutated))})"))
            log = execute(godot, test, expected=1)
            if "FAIL " not in log:
                raise RuntimeError(f"mutation failed without an assertion: {name}")
            (args.output/f"mutation-{name}.log").write_text(log)
            mutations.append({"name": name, "rejected_by_assertions": True})
        print("three isolated formula mutations rejected", flush=True)
    log = execute(godot, HERE/"sweep.gd")
    (args.output/"sweep.log").write_text(log)
    sweep = [json.loads(line) for line in log.splitlines() if line.startswith("{")][-1]
    if sweep["cases"] != 1000 or sweep["mismatches"] or sweep["max_error_rad"] != 0:
        raise RuntimeError(f"sweep incomplete or changed: {sweep}")
    if hashes() != before:
        raise RuntimeError("verification inputs changed during execution")
    report = {"step": "DATA-2a", "input_sha256": before, "focused_checks": 571, "timings": timings,
              "mutations": mutations, "sweep": sweep,
              "limits": "Paired wall-clock measurements on a shared host; no flight physics or calibration change. The 15 ms whole-load target is separate."}
    (args.output/"verification.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps({"sweep_cases": sweep["cases"], "angle_mismatches": sweep["mismatches"], "candidate_medians_ms": [case["candidate_median_ms"] for case in timings]}))


if __name__ == "__main__":
    main()
