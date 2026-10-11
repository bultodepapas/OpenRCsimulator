#!/usr/bin/env python3
"""Prove electric runway startup and two real regressions in a disposable app."""
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
SOURCE = "sim/flight_session.gd"
TEST = "tests/test_electric_runway.gd"
CHECKS = 177


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


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
    shutil.copytree(app, workspace, ignore=shutil.ignore_patterns(".godot", "captures", "__pycache__"))
    logs = out / "logs"
    logs.mkdir()
    source = workspace / SOURCE
    original = source.read_bytes()
    env = dict(os.environ, XDG_DATA_HOME=str(out / "runtime"), XDG_CONFIG_HOME=str(out / "config"))
    report = {"format": "openrc-el2a-e1-runway-v1", "ok": False,
              "godot_sha256": sha(godot.read_bytes()),
              "source_sha256": {SOURCE: sha(original), TEST: sha((workspace / TEST).read_bytes())},
              "mutations": []}

    def run(name: str, arguments: list[str]) -> tuple[int, str]:
        process = subprocess.run([str(godot), *arguments], capture_output=True, text=True,
                                 timeout=180, env=env)
        output = process.stdout + process.stderr
        (logs / f"{name}.log").write_text(output, encoding="utf-8")
        if ERROR.search(output):
            raise AssertionError(f"{name}: engine error, not behavioral evidence")
        return process.returncode, output

    def test(name: str) -> tuple[int, str]:
        return run(name, ["--headless", "--path", str(workspace), "--script", "res://" + TEST])

    def positive(name: str) -> None:
        rc, output = test(name)
        if rc != 0 or f"EL2a-E1 electric runway: {CHECKS} checks, 0 failed" not in output:
            raise AssertionError(f"{name}: incomplete or failing positive control")
        report[name] = {"exit_code": rc, "checks": CHECKS}

    try:
        rc, version = run("version", ["--version"])
        if rc not in (0, 1) or version.strip() != "4.7.2.stable.official.ed1daf0bf":
            raise AssertionError("pinned Godot version was not confirmed")
        report["godot_version"] = version.strip()
        rc, _ = run("import", ["--headless", "--path", str(workspace), "--editor", "--import"])
        if rc != 0:
            raise AssertionError("fresh import failed")
        positive("positive")
        base = original.decode("utf-8")
        marker = "0.0 if Propulsion.is_electric(prop) else Propulsion.steady_rpm("
        if base.count(marker) != 1:
            raise AssertionError("runway mutation anchor is not unique")
        defects = [
            ("combustion_idle_search", "Propulsion.steady_rpm(", "runway succeeds"),
            ("invented_electric_idle", "1.0 if Propulsion.is_electric(prop) else Propulsion.steady_rpm(",
             "source enabled with zero duty and exact rest"),
        ]
        for name, replacement, expected in defects:
            try:
                source.write_bytes(base.replace(marker, replacement).encode("utf-8"))
                rc, output = test(name)
                failures = [line for line in output.splitlines() if line.startswith("FAIL:")]
                if rc != 1 or not any(expected in line for line in failures):
                    raise AssertionError(f"{name}: intended defect was not rejected")
                report["mutations"].append({"name": name, "exit_code": rc, "failures": failures})
            finally:
                source.write_bytes(original)
        positive("restored")
        if source.read_bytes() != original:
            raise AssertionError("source restoration failed")
        report["ok"] = True
    finally:
        source.write_bytes(original)
        (out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": report["ok"], "checks": CHECKS, "defects": len(report["mutations"])}))


if __name__ == "__main__":
    main()
