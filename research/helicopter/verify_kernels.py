"""HELI-03a/04-R1/05/05a/06a–c/13: native verification and disposable defects.

Run from any directory. --out must name a fresh directory; generated logs are
not source artifacts. --parse-all additionally checks every application script.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
SCRIPTS = (
    "physics/rotorcraft/inflow.gd", "physics/rotorcraft/swash.gd",
    "tests/test_heli_inflow.gd", "tests/test_heli_swash.gd",
    "physics/rotorcraft/dynamic_inflow.gd", "physics/rotorcraft/main_rotor.gd",
    "physics/rotorcraft/main_rotor_stage.gd", "tests/test_heli_dynamic_inflow.gd",
    "tests/test_heli_main_rotor.gd", "tests/test_heli_main_rotor_stage.gd",
    "physics/rotorcraft/tail_rotor.gd", "tests/test_heli_tail_rotor.gd",
    "physics/rotorcraft/airframe.gd", "tests/test_heli_airframe.gd",
    "physics/rotorcraft/aerodynamic_stage.gd", "tests/test_heli_aerodynamic_stage.gd",
)
ERROR = re.compile(r"^(?:SCRIPT |SHADER )?ERROR:", re.MULTILINE)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--parse-all", action="store_true")
    parser.add_argument("--native-only", action="store_true", help="focused rerun when Python references/freshness were already checked")
    args = parser.parse_args()
    godot = args.godot.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    records: list[dict[str, object]] = []

    def run(name: str, command: list[str], expect_defect: bool = False) -> str:
        result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8",
                                errors="replace", capture_output=True, timeout=180)
        output = result.stdout + result.stderr
        (out / f"{name}.log").write_text(output, encoding="utf-8")
        if expect_defect:
            passed = result.returncode != 0 and "FAIL " in output and not ERROR.search(output)
        else:
            passed = result.returncode == 0 and not ERROR.search(output)
        records.append({"name": name, "ok": bool(passed), "returncode": result.returncode})
        print(f"{'ok' if passed else 'FAIL'} {name}", flush=True)
        return output

    def engine(app: Path, *arguments: str) -> list[str]:
        return [str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy", *arguments]

    if not args.native_only:
        run("reference", [sys.executable, "-m", "unittest", "discover", "-s",
                          "research/helicopter/reference", "-p", "test_*.py"])
        run("oracle-current", [sys.executable, "research/helicopter/reference/make_oracle.py", "--check"])
        run("dynamic-oracle-current", [sys.executable, "research/helicopter/reference/make_dynamic_oracle.py", "--check"])
        run("main-oracle-current", [sys.executable, "research/helicopter/reference/make_main_rotor_oracle.py", "--check"])
        run("tail-oracle-current", [sys.executable, "research/helicopter/reference/make_tail_rotor_oracle.py", "--check"])
        run("airframe-oracle-current", [sys.executable, "research/helicopter/reference/make_airframe_oracle.py", "--check"])
    run("math-boundary", [sys.executable, "app/tests/check_transcendentals.py"])
    for index, script in enumerate(SCRIPTS):
        run(f"parse-kernel-{index}", engine(APP, "--check-only", "--script", f"res://{script}"))
    oracle = ROOT / "research/helicopter/reference/oracle.json"
    run("inflow", engine(APP, "--script", "res://tests/test_heli_inflow.gd", "--", f"--oracle={oracle}"))
    run("swash", engine(APP, "--script", "res://tests/test_heli_swash.gd"))
    run("dynamic-inflow", engine(APP, "--script", "res://tests/test_heli_dynamic_inflow.gd", "--",
        f"--oracle={ROOT / 'research/helicopter/reference/dynamic_oracle.json'}"))
    run("main-rotor", engine(APP, "--script", "res://tests/test_heli_main_rotor.gd", "--",
        f"--oracle={ROOT / 'research/helicopter/reference/main_rotor_oracle.json'}"))
    run("main-stage", engine(APP, "--script", "res://tests/test_heli_main_rotor_stage.gd"))
    run("tail-rotor", engine(APP, "--script", "res://tests/test_heli_tail_rotor.gd", "--",
        f"--oracle={ROOT / 'research/helicopter/reference/tail_rotor_oracle.json'}"))
    run("airframe", engine(APP, "--script", "res://tests/test_heli_airframe.gd", "--",
        f"--oracle={ROOT / 'research/helicopter/reference/airframe_oracle.json'}"))
    run("aerodynamic-stage", engine(APP, "--script", "res://tests/test_heli_aerodynamic_stage.gd"))
    run("airplane-goldens", engine(APP, "--script", "res://tests/test_golden.gd"))
    hashes: list[str] = []
    for fps in (30, 60, 144):
        output = run(f"airplane-frames-{fps}", engine(APP, "--fixed-fps", str(fps),
                     "--script", "res://tests/run_fixed_step.gd"))
        hashes.extend(re.findall(r"state_sha256=([0-9a-f]{64})", output))
    frame_ok = len(hashes) == 3 and len(set(hashes)) == 1
    records.append({"name": "airplane-frame-identity", "ok": frame_ok, "hashes": hashes})
    print(f"{'ok' if frame_ok else 'FAIL'} airplane-frame-identity", flush=True)

    # Real defects in isolated minimal applications; never mutate the working tree.
    source = (APP / SCRIPTS[0]).read_text(encoding="utf-8")
    mutations = {
        "wrong-vrs-anchor": ("(0.85 -", "(0.95 -"),
        "wrong-windmill-root": ("root = 2.0 / (-z + d)", "root = 0.5 * (-z + d)"),
        "lost-thrust-sign": ("var velocity: float = sense * hover", "var velocity: float = hover"),
    }
    for name, (old, new) in mutations.items():
        if source.count(old) != 1:
            raise RuntimeError(f"mutation anchor drifted: {name}")
        disposable = out / name / "app"
        for relative in (SCRIPTS[0], SCRIPTS[2], "physics/math3d.gd"):
            target = disposable / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(APP / relative, target)
        (disposable / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        (disposable / SCRIPTS[0]).write_text(source.replace(old, new), encoding="utf-8")
        run(name, engine(disposable, "--script", "res://tests/test_heli_inflow.gd"), expect_defect=True)

    # A units regression can look plausible at zero body rate. Probe actual
    # nonzero p/q, and a missing lateral-flow sign, in separate applications.
    rotor_source = (APP / "physics/rotorcraft/main_rotor.gd").read_text(encoding="utf-8")
    rotor_defects = {
        "body-rate-divided-by-lag": ("var a_rate: float = -body_rates[1] +", "var a_rate: float = -body_rates[1] / tau +"),
        "wrong-lateral-flap-sign": ("(-b1 + flapback * mu_y", "(-b1 - flapback * mu_y"),
        "hub-arm-counted-twice": ("var my: float = arm_y + spring_y", "var my: float = 2.0 * arm_y + spring_y"),
    }
    for name, (old, new) in rotor_defects.items():
        if rotor_source.count(old) != 1:
            raise RuntimeError(f"main-rotor mutation anchor drifted: {name}")
        disposable = out / name / "app"
        for relative in ("physics/rotorcraft/main_rotor.gd", "physics/math3d.gd", "tests/test_heli_main_rotor.gd"):
            target = disposable / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(APP / relative, target)
        (disposable / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        (disposable / "physics/rotorcraft/main_rotor.gd").write_text(rotor_source.replace(old, new), encoding="utf-8")
        run(name, engine(disposable, "--script", "res://tests/test_heli_main_rotor.gd"), expect_defect=True)

    tail_source = (APP / "physics/rotorcraft/tail_rotor.gd").read_text(encoding="utf-8")
    tail_defects = {
        "tail-yaw-arm-reversed": ("var mz: float = -model.hub_distance_aft_m * fy", "var mz: float = model.hub_distance_aft_m * fy"),
        "tail-blockage-omitted": ("var thrust: float = model.blockage_factor * scale * ct", "var thrust: float = scale * ct"),
        "tail-hub-roll-velocity-reversed": ("+ model.hub_height_above_cg_m * body_rates[0]", "- model.hub_height_above_cg_m * body_rates[0]"),
    }
    for name, (old, new) in tail_defects.items():
        if tail_source.count(old) != 1:
            raise RuntimeError(f"tail-rotor mutation anchor drifted: {name}")
        disposable = out / name / "app"
        for relative in ("physics/rotorcraft/tail_rotor.gd", "physics/math3d.gd", "tests/test_heli_tail_rotor.gd"):
            target = disposable / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(APP / relative, target)
        (disposable / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        (disposable / "physics/rotorcraft/tail_rotor.gd").write_text(tail_source.replace(old, new), encoding="utf-8")
        run(name, engine(disposable, "--script", "res://tests/test_heli_tail_rotor.gd"), expect_defect=True)

    airframe_source = (APP / "physics/rotorcraft/airframe.gd").read_text(encoding="utf-8")
    airframe_defects = {
        "airframe-wake-sign-reversed": ("var uz: float = point_z - wake[2]", "var uz: float = point_z + wake[2]"),
        "airframe-pitch-point-sign-reversed": ("rates[0] * ry - rates[1] * rx", "rates[0] * ry + rates[1] * rx"),
        "airframe-tail-force-injects-energy": ("ideal = -scale * (model.horizontal_tail_lift_curve_slope_per_rad", "ideal = scale * (model.horizontal_tail_lift_curve_slope_per_rad"),
        "airframe-tail-cap-includes-lateral-flow": ("var cap: float = scale * (ux * ux + uz * uz)", "var cap: float = scale * (ux * ux + uy * uy + uz * uz)"),
    }
    for name, (old, new) in airframe_defects.items():
        if airframe_source.count(old) != 1:
            raise RuntimeError(f"airframe mutation anchor drifted: {name}")
        disposable = out / name / "app"
        for relative in ("physics/rotorcraft/airframe.gd", "physics/math3d.gd", "tests/test_heli_airframe.gd"):
            target = disposable / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(APP / relative, target)
        (disposable / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        (disposable / "physics/rotorcraft/airframe.gd").write_text(airframe_source.replace(old, new), encoding="utf-8")
        run(name, engine(disposable, "--script", "res://tests/test_heli_airframe.gd"), expect_defect=True)

    if args.parse_all:
        scripts = sorted(path for path in APP.rglob("*.gd") if ".godot" not in path.parts)

        def parse_one(path: Path) -> dict[str, object]:
            result = subprocess.run(engine(APP, "--check-only", "--script", f"res://{path.relative_to(APP).as_posix()}"),
                                    cwd=ROOT, text=True, encoding="utf-8", errors="replace",
                                    capture_output=True, timeout=60)
            output = result.stdout + result.stderr
            return {"path": path.relative_to(APP).as_posix(),
                    "ok": result.returncode == 0 and not ERROR.search(output), "output": output}

        # Read-only parsing can run concurrently; physics timings must run alone.
        with ThreadPoolExecutor(max_workers=2) as pool:
            parsed = []
            for index, record in enumerate(pool.map(parse_one, scripts), 1):
                parsed.append(record)
                if index % 100 == 0:
                    print(f"parsed {index}/{len(scripts)}", flush=True)
        (out / "parse-all.json").write_text(json.dumps(parsed, indent=2), encoding="utf-8")
        ok = all(record["ok"] for record in parsed)
        records.append({"name": "all-application-scripts-parse", "ok": ok, "count": len(parsed)})
        print(f"{'ok' if ok else 'FAIL'} all-application-scripts-parse ({len(parsed)})", flush=True)

    ok = all(record["ok"] for record in records)
    (out / "summary.json").write_text(json.dumps({"ok": ok, "native_only": args.native_only, "checks": records}, indent=2) + "\n", encoding="utf-8")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
