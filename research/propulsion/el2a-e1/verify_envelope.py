#!/usr/bin/env python3
"""Run and independently check the twelve-case synthetic electric envelope."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess

from trace_checks import check_trace

HERE = Path(__file__).resolve().parent
DURATIONS = {"takeoff": 8, "stall": 20, "landing": 46}
ERROR = re.compile(r"^(?:SCRIPT ERROR|SHADER ERROR|ERROR|Parse Error|Compile Error):", re.M)
# Software regression bands, fixed before the final twelve-case matrix. These
# compare two resolutions; they do not establish convergence order or realism.
REFINEMENT = {
    "takeoff": {"liftoff_time_s": 0.05, "liftoff_speed_mps": 0.10, "liftoff_distance_m": 0.5},
    "stall": {"recovery_latency_s": 0.15, "max_alpha_deg": 0.5, "altitude_lost_m": 0.5},
    "landing": {"touchdown_time_s": 0.05, "max_contact_sink_mps": 0.05,
                "stop_time_s": 0.5, "touchdown_from_threshold_m": 0.25,
                "minimum_runway_margin_m": 0.25},
}


def require(ok: bool, message: str) -> None:
    if not ok:
        raise AssertionError(message)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def finite_tree(value: object) -> bool:
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, dict):
        return all(finite_tree(v) for v in value.values())
    if isinstance(value, list):
        return all(finite_tree(v) for v in value)
    return True


def score_metrics(maneuver: str, metrics: dict) -> None:
    """Require actual maneuver outcomes even if a driver drops a criterion."""
    def number(key: str) -> float:
        value = metrics[key]
        require(type(value) in (int, float) and math.isfinite(value), f"invalid metric {key}")
        return value

    require(metrics["battery_exhausted"] is False, "battery exhausted during envelope case")
    if maneuver == "takeoff":
        require(metrics["liftoff_detected"] is True and number("wheel_clear_s") >= 0.5,
                "takeoff did not sustain final wheel clearance")
        require(0 < number("liftoff_time_s") < DURATIONS[maneuver], "missing liftoff time")
        require(number("liftoff_speed_mps") > 0 and number("liftoff_distance_m") > 0, "invalid liftoff")
        require(0 <= number("liftoff_heading_error_deg") < 15, "takeoff heading departure")
        require(0 <= number("max_heading_error_before_liftoff_deg") < 15, "earlier takeoff heading departure")
        require(number("minimum_lateral_margin_before_liftoff_m") >= 0.5, "takeoff wheel path left runway")
    elif maneuver == "stall":
        require(metrics["stall_detected"] is True
                and number("max_alpha_deg") >= number("stall_alpha_a2_deg"), "no actual stall excursion")
        require(metrics["recovery_detected"] is True and 0 <= number("recovery_latency_s") <= 10,
                "stall recovery missing or late")
        require(0 <= number("altitude_lost_m") < 80 and number("minimum_altitude_after_stall_m") > 35,
                "stall recovery outside altitude envelope")
        require(number("stable_final_s") >= 1, "recovery not sustained to terminal boundary")
    elif maneuver == "landing":
        require(metrics["touchdown_detected"] is True and number("touchdown_from_threshold_m") >= 0,
                "no in-runway touchdown")
        require(0 <= number("touchdown_sink_mps") < 1.2, "touchdown sink outside envelope")
        require(0 <= number("max_contact_sink_mps") < 1.2, "later wheel contact sink outside envelope")
        require(0 < number("touchdown_time_s") < DURATIONS[maneuver], "missing touchdown time")
        require(number("minimum_runway_margin_m") >= 0.5 and number("stop_runway_margin_m") >= 0.5,
                "wheel path outside runway margin")
        require(0 < number("stop_time_s") < DURATIONS[maneuver] and number("stop_dwell_s") >= 2,
                "landing did not stop and hold")
        require(metrics["stopped_then_moved"] is False and number("max_stop_drift_m") < 0.002
                and number("final_speed_mps") < 0.02, "landing stop not stable")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    app, godot, out = args.app.resolve(), args.godot.resolve(), args.out.resolve()
    require((app / "project.godot").is_file() and godot.is_file(), "app and pinned executable required")
    driver = HERE / "envelope.gd"
    require(driver.is_file(), "envelope driver must exist before creating output")
    require(out != app and app not in out.parents, "output must be outside the source app")
    out.mkdir(parents=True, exist_ok=False)
    workspace = out / "app"
    shutil.copytree(app, workspace, ignore=shutil.ignore_patterns(".godot", "captures", "__pycache__"))
    logs = out / "logs"
    logs.mkdir()
    cases = out / "cases"
    cases.mkdir()
    env = dict(os.environ, XDG_DATA_HOME=str(out / "runtime"), XDG_CONFIG_HOME=str(out / "config"))
    report = {"format": "openrc-el2a-e1-envelope-v1", "ok": False,
              "godot_sha256": sha(godot), "driver_sha256": sha(driver),
              "verifier_sha256": {p.name: sha(p) for p in (Path(__file__), HERE / "trace_checks.py")},
              "cases": [], "refinement": []}

    def run(name: str, arguments: list[str], timeout: int = 240) -> str:
        process = subprocess.run([str(godot), *arguments], capture_output=True, text=True,
                                 timeout=timeout, env=env)
        output = process.stdout + process.stderr
        (logs / f"{name}.log").write_text(output, encoding="utf-8")
        require(not ERROR.search(output), f"{name}: engine error")
        require(process.returncode == 0, f"{name}: process failed ({process.returncode})")
        return output

    try:
        version = run("version", ["--version"]).strip()
        require(version == "4.7.2.stable.official.ed1daf0bf", "wrong Godot version")
        report["godot_version"] = version
        run("import", ["--headless", "--path", str(workspace), "--editor", "--import"])
        sources = sorted(p for p in workspace.rglob("*") if p.is_file()
                         and ".godot" not in p.relative_to(workspace).parts
                         and (p.suffix in (".gd", ".json") or p.name == "project.godot"))
        report["app_source_sha256"] = {p.relative_to(workspace).as_posix(): sha(p) for p in sources}
        for pack in ("4s", "6s"):
            for maneuver, duration in DURATIONS.items():
                for hz in (240, 480):
                    name = f"{pack}_{maneuver}_{hz}"
                    run(name, ["--headless", "--path", str(workspace), "--script", str(driver), "--",
                               f"--pack={pack}", f"--hz={hz}", f"--maneuver={maneuver}", f"--out={cases}"])
                    result = json.loads((cases / f"{name}.json").read_text(encoding="utf-8"))
                    require(finite_tree(result), f"{name}: nonfinite report")
                    require((result["pack"], result["maneuver"], result["hz"]) == (pack, maneuver, hz),
                            f"{name}: case identity mismatch")
                    require(result["format"] == "openrc-el2a-e1-case v1", f"{name}: wrong report format")
                    require(result["completed"] is True and result["passed"] is True, f"{name}: incomplete/failed")
                    require(result["ticks"] == result["expected_ticks"] == duration * hz, f"{name}: wrong ticks")
                    require(result["duration_s"] == duration and abs(result["actual_duration_s"] - duration) < 1e-9,
                            f"{name}: wrong duration")
                    require(not result["fault"] and not result["crash"] and not result["pause_reason"]
                            and not result["error"], f"{name}: failed session")
                    criteria = result["criteria"]
                    require(isinstance(criteria, dict) and len(criteria) >= 5
                            and all(value is True for value in criteria.values()), f"{name}: invalid criteria")
                    trace = result["trace"]
                    require(trace["save_ok"] is True and trace["format_v8"] is True
                            and trace["continuous"] is True and not trace["gaps"]
                            and trace["row_count"] == trace["expected_rows"] == duration * hz + 1,
                            f"{name}: invalid trace report")
                    score_metrics(maneuver, result["metrics"])
                    electrical = check_trace(cases / f"{name}.csv",
                                             workspace / f"data/aircraft/synthetic_stik_electric_{pack}_battery.json",
                                             duration * hz, hz)
                    require((electrical["pack"], electrical["maneuver"], electrical["hz"])
                            == (pack, maneuver, hz), f"{name}: trace case mismatch")
                    report["cases"].append({"name": name, "flight": result, "electrical": electrical})
                    print(f"PASS {name}: {electrical['rows']} rows", flush=True)
        require(len(report["cases"]) == 12, "incomplete matrix")
        by_name = {case["name"]: case["flight"]["metrics"] for case in report["cases"]}
        for pack in ("4s", "6s"):
            for maneuver, bands in REFINEMENT.items():
                coarse = by_name[f"{pack}_{maneuver}_240"]
                fine = by_name[f"{pack}_{maneuver}_480"]
                for metric, limit in bands.items():
                    require(all(type(value) in (int, float) and math.isfinite(value)
                                for value in (coarse[metric], fine[metric])), f"invalid refinement metric {metric}")
                    difference = abs(coarse[metric] - fine[metric])
                    report["refinement"].append({"pack": pack, "maneuver": maneuver, "metric": metric,
                                                 "difference": difference, "limit": limit})
                    require(difference <= limit, f"{pack} {maneuver}: {metric} refinement exceeds {limit}")
        report["ok"] = True
        report["checked_rows"] = sum(case["electrical"]["rows"] for case in report["cases"])
    finally:
        (out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": report["ok"], "cases": len(report["cases"]), "rows": report["checked_rows"]}))


if __name__ == "__main__":
    main()
