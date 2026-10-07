#!/usr/bin/env python3
"""Check F3b1 guards in a disposable reader-only project; never mutate app/."""
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
GODOT = subprocess.check_output([str(ROOT / "app/get-godot.sh")], text=True).strip()
original = (ROOT / "app/input/rc_input.gd").read_text()
results = []
with tempfile.TemporaryDirectory(prefix="openrc-f3b1-mutations-") as folder:
    app = Path(folder)
    (app / "input").mkdir()
    (app / "project.godot").write_text('config_version=5\n[application]\nconfig/name="F3b1 fixture"\n')
    shutil.copy2(ROOT / "app/tests/test_rc_axis_history.gd", app / "test.gd")
    signature = "func on_motion(id: int, axis: int, value: float) -> void:\n"
    cases = {
        "baseline": original,
        "drop_events_after_arming": original.replace(signature, signature + "\tif armed:\n\t\treturn\n", 1),
        "drop_axis_nine": original.replace("axis >= AXES:", "axis >= AXES - 1:", 1),
    }
    for name, source in cases.items():
        (app / "input/rc_input.gd").write_text(source)
        proc = subprocess.run([GODOT, "--headless", "--path", str(app), "--script", "res://test.gd"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        failures = [line for line in proc.stdout.splitlines() if line.startswith("FAIL ")]
        expected = proc.returncode == 0 and not failures if name == "baseline" else proc.returncode != 0 and bool(failures)
        results.append(dict(case=name, passed=expected and "ERROR:" not in proc.stdout, exit_code=proc.returncode, failed_checks=len(failures), summary=[line for line in proc.stdout.splitlines() if line.startswith("F3b:")]))
print(json.dumps(results, indent=2))
raise SystemExit(0 if all(result["passed"] for result in results) else 1)
