#!/usr/bin/env python3
"""Reconstruct unchanged source dependencies and run synthetic graphics-policy witnesses.

No product source, native backend, renderer policy, or user preferences are changed.
The fixture's startup configuration is deliberately minimal; this is not a full-app import.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

BASE = "57abea025f62b20233ca281d58d2acbee4ab8b8e"
ENGINE = "4.8.beta2.official.cafc17a19"
LINUX_ENGINE_SHA512 = (
    "428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca"
    "30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9"
)
RESOURCE = re.compile(r'''["']res://([^"'\n]+)["']''')


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error("--out must be a new or empty directory")
    child_env = os.environ.copy()
    isolated_paths = {}
    for key, directory in (("XDG_DATA_HOME", "user-data"), ("XDG_CONFIG_HOME", "user-config"),
                           ("XDG_CACHE_HOME", "user-cache")):
        private = output / directory
        private.mkdir()
        child_env[key] = str(private)
        isolated_paths[key] = directory
    engine = args.godot.resolve()
    engine_bytes = engine.read_bytes()
    if hashlib.sha512(engine_bytes).hexdigest() != LINUX_ENGINE_SHA512:
        parser.error("this receipt accepts only the pinned official Linux x86_64 binary")
    version = subprocess.check_output([str(engine), "--version"], text=True, env=child_env).strip()
    if version != ENGINE:
        parser.error(f"unexpected engine: {version}")
    fixture = output / "fixture"
    fixture.mkdir()
    pending = ["app/tests/test_auto_calibration.gd", "app/render/auto_graphics_report.gd"]
    dependencies: dict[str, bytes] = {}
    while pending:
        name = pending.pop()
        if name in dependencies:
            continue
        data = subprocess.check_output(["git", "-C", str(root), "show", f"{BASE}:{name}"])
        dependencies[name] = data
        if name.endswith((".gd", ".gdshader", ".gdshaderinc", ".tscn", ".tres")):
            for target in RESOURCE.findall(data.decode("utf-8")):
                if "%" not in target and "*" not in target:
                    pending.append("app/" + target)
    inventory = []
    for name, data in sorted(dependencies.items()):
        target = fixture / name.removeprefix("app/")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        inventory.append({"source": name, "sha256": sha(data), "bytes": len(data)})
        if name.endswith((".gd", ".gdshader")):
            uid = subprocess.run(["git", "-C", str(root), "show", f"{BASE}:{name}.uid"],
                                 capture_output=True, check=False)
            if uid.returncode == 0:
                Path(str(target) + ".uid").write_bytes(uid.stdout)
                inventory.append({"source": name + ".uid", "sha256": sha(uid.stdout), "bytes": len(uid.stdout)})
    fixture_config = ('config_version=5\n[application]\nconfig/name="OpenRC graphics audit fixture"\n'
                      '[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n'
                      '[rendering]\nrenderer/rendering_method="forward_plus"\n')
    (fixture / "project.godot").write_text(fixture_config, encoding="utf-8")
    probe = Path(__file__).with_name("calibration_probe.gd")
    (fixture / "calibration_probe.gd").write_bytes(probe.read_bytes())
    runner = root / "tools/godot/run_checked.py"
    manifest = {"source": BASE, "engine_version": version, "engine_sha256": sha(engine_bytes),
                "dependencies": inventory, "dependency_files": len(dependencies),
                "fixture_config_sha256": sha(fixture_config.encode()),
                "probe_sha256": sha(probe.read_bytes()), "runner_sha256": sha(runner.read_bytes()),
                "isolated_user_paths_relative_to_output": isolated_paths,
                "scope": "unchanged source in a minimal headless fixture; synthetic policy inputs, no GPU/frame claim"}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    commands = [
        ("import", ["--editor", "--import"], None),
        ("policy-witnesses", ["--script", "res://calibration_probe.gd"], "graphics audit policy witnesses:"),
        ("unchanged-auto-calibration", ["--script", "res://tests/test_auto_calibration.gd"], "auto calibration:"),
    ]
    statuses = []
    for label, tail, marker in commands:
        command = [sys.executable, str(runner), "--out-dir", str(output / "checks"), "--label", label,
                   "--timeout", "60", "--warnings-as-errors"]
        if marker:
            command += ["--require-text", marker]
        command += ["--", str(engine), "--headless", "--path", str(fixture), "--audio-driver", "Dummy", *tail]
        result = subprocess.run(command, cwd=root, check=False, env=child_env)
        statuses.append({"label": label, "exit_code": result.returncode})
        if result.returncode:
            break
    stable = all(sha((fixture / name.removeprefix("app/")).read_bytes()) == sha(data)
                 for name, data in dependencies.items())
    engine_stable = sha(engine.read_bytes()) == manifest["engine_sha256"]
    summary = {"commands": statuses, "source_stable": stable, "engine_stable": engine_stable,
               "ok": len(statuses) == 3 and all(s["exit_code"] == 0 for s in statuses) and stable and engine_stable}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
