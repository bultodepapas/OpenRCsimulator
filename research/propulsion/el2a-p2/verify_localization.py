#!/usr/bin/env python3
"""Qualify event localization and real defects in a fresh disposable Godot app."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ERROR = re.compile(r"^(?:SCRIPT ERROR|SHADER ERROR|ERROR|Parse Error|Compile Error):", re.M)
SCRIPTS = {
    "test_electric_event_localization.gd": ("EL2a-P2 event localization", 2946),
    "test_electric_stop.gd": ("EL1d electric stop", 37),
    "test_electric_battery_step.gd": ("EL2a electric battery step", 63),
}
SOURCES = ("physics/event_bracket.gd", "physics/electric_stop.gd", "physics/electric_battery_step.gd")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def replace_exact(source: str, before: str, after: str, count: int) -> str:
    if source.count(before) != count:
        raise ValueError(f"mutation needs {count} occurrences, found {source.count(before)}: {before}")
    return source.replace(before, after)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    app, godot, out = args.app.resolve(), args.godot.resolve(), args.out.resolve()
    if not (app / "project.godot").is_file() or not godot.is_file():
        parser.error("existing app and pinned Godot executable are required")
    if out == app or app in out.parents:
        parser.error("output must be outside the source app")
    out.mkdir(parents=True, exist_ok=False)
    workspace = out / "app"
    shutil.copytree(app, workspace, ignore=shutil.ignore_patterns(".godot", "captures"))
    logs = out / "logs"
    logs.mkdir()
    env = dict(os.environ, XDG_DATA_HOME=str(out / "runtime"), XDG_CONFIG_HOME=str(out / "config"))
    original = {name: (workspace / name).read_bytes() for name in SOURCES}
    report = {"format": "openrc-el2a-p2-localization-v1", "ok": False,
              "godot_sha256": sha(godot.read_bytes()), "source_sha256": {n: sha(b) for n, b in original.items()},
              "tests_sha256": {n: sha((workspace / "tests" / n).read_bytes()) for n in SCRIPTS},
              "positive": {}, "mutations": []}

    def run(name: str, arguments: list[str]) -> tuple[int, str]:
        process = subprocess.run([str(godot), *arguments], capture_output=True, text=True,
                                 timeout=120, env=env)
        text = process.stdout + process.stderr
        (logs / f"{name}.log").write_text(text, encoding="utf-8")
        if ERROR.search(text):
            raise AssertionError(f"{name}: engine error, not numerical evidence")
        return process.returncode, text

    def script(name: str, test: str) -> tuple[int, str]:
        return run(name, ["--headless", "--path", str(workspace), "--script", f"res://tests/{test}"])

    try:
        rc, text = run("version", ["--version"])
        if rc not in (0, 1) or not re.fullmatch(r"4\.7\.2\.stable\.official\.[0-9a-f]{9}\s*", text):
            raise AssertionError("pinned Godot version was not confirmed")
        report["godot_version"] = text.strip()
        rc, _ = run("import", ["--headless", "--path", str(workspace), "--editor", "--import"])
        if rc != 0:
            raise AssertionError("fresh project import failed")
        for test, (prefix, count) in SCRIPTS.items():
            rc, text = script(test.removesuffix(".gd"), test)
            if rc != 0 or f"{prefix}: {count} checks, 0 failed" not in text:
                raise AssertionError(f"{test}: incomplete or failing positive control")
            report["positive"][test] = {"exit_code": rc, "checks": count}

        base = {name: raw.decode("utf-8").replace("\r\n", "\n") for name, raw in original.items()}
        battery = "physics/electric_battery_step.gd"
        rotor = "physics/electric_stop.gd"
        bracket = "physics/event_bracket.gd"
        defects: list[tuple[str, dict[str, str], str]] = []
        defects.append(("pure_bisection_cost", {bracket: replace_exact(base[bracket], "if bisect:", "if true:", 1)},
                        "linear battery crossings avoid dozens of RK restarts"))
        no_residual = replace_exact(base[battery], " and absf(high_state[charge_index]) <= CHARGE_TOL_C", "", 2)
        no_residual = replace_exact(no_residual, "and absf(high_state[charge_index]) <= CHARGE_TOL_C", "and true", 1)
        no_residual = replace_exact(no_residual, " or absf(residual_c) > CHARGE_TOL_C", "", 1)
        defects.append(("missing_charge_residual_bound", {battery: no_residual},
                        "unresolved residual never becomes an accepted battery event"))
        no_time = replace_exact(base[battery], "hi - lo <= TIME_TOL and ", "", 3)
        defects.append(("missing_time_bound", {battery: no_time}, "upper residual and time both bounded"))
        no_fallback = {name: replace_exact(base[name], "bisect = not bisect and hi - lo > 0.5 * old_width",
                                          "bisect = false", 1) for name in (battery, rotor)}
        defects.append(("missing_bisection_safeguard", no_fallback, "completes"))
        tie_start = base[battery].index("\t\telif not events.is_empty() and events[-1].type")
        tie_end = base[battery].index("\t\tevents.append", tie_start)
        defects.append(("missing_coincident_order", {battery: base[battery][:tie_start] + base[battery][tie_end:]},
                        "chronological event order with rotor-first tie"))
        for name, changes, expected in defects:
            try:
                for relative, source in changes.items():
                    (workspace / relative).write_text(source, encoding="utf-8")
                rc, text = script(name, "test_electric_event_localization.gd")
                failure_lines = [line for line in text.splitlines() if line.startswith("FAIL:")]
                if rc != 1 or not any(expected in line for line in failure_lines):
                    raise AssertionError(f"{name}: intended defective behavior was not detected")
                report["mutations"].append({"name": name, "exit_code": rc, "expected_failure": expected,
                                            "failures": len(failure_lines), "log": f"logs/{name}.log"})
            finally:
                for relative in changes:
                    (workspace / relative).write_bytes(original[relative])
        if any((workspace / n).read_bytes() != raw for n, raw in original.items()):
            raise AssertionError("pristine source restoration failed")
        rc, text = script("restored", "test_electric_event_localization.gd")
        if rc != 0 or "2946 checks, 0 failed" not in text:
            raise AssertionError("restored source did not pass")
        report["restored"] = True
        report["ok"] = True
    finally:
        (out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("3046 localization/stop/battery checks passed; 5 actual defects rejected; pristine source restored")


if __name__ == "__main__":
    main()
