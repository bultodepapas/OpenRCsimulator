#!/usr/bin/env python3
"""F6a ordering mutations run only on disposable copies, never the shared app."""
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
GODOT = subprocess.check_output([str(ROOT / "app/get-godot.sh")], text=True).strip()
results = []
with tempfile.TemporaryDirectory(prefix="openrc-f6a-mutations-") as folder:
    app = Path(folder) / "app"
    app.mkdir()
    for item in (ROOT / "app").iterdir():
        if item.name not in {".godot", "input", "tests"}:
            (app / item.name).symlink_to(item, target_is_directory=item.is_dir())
    shutil.copytree(ROOT / "app/input", app / "input")
    (app / "tests").mkdir()
    shutil.copy2(ROOT / "app/tests/test_latency_patch.gd", app / "tests/test_latency_patch.gd")
    marker = app / "input/latency_patch.gd"
    original = marker.read_text()
    cases = {
        "baseline": original,
        "before_flight_poll": original.replace("process_physics_priority = 1", "process_physics_priority = -2"),
        "render_frame_instead_of_tick": original.replace("func _physics_process(_delta: float)", "func _process(_delta: float)") + "\n\nfunc _physics_process(_delta: float) -> void:\n\tpass\n",
    }
    for name, source in cases.items():
        marker.write_text(source)
        proc = subprocess.run([GODOT, "--headless", "--path", str(app), "--script", "res://tests/test_latency_patch.gd"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        failures = [line for line in proc.stdout.splitlines() if line.startswith("FAIL ")]
        tick_failures = [line for line in failures if line.startswith("FAIL first tick")]
        ok = (proc.returncode == 0 and not failures) if name == "baseline" else (proc.returncode != 0 and len(tick_failures) > 0)
        ok = ok and "ERROR:" not in proc.stdout
        results.append(dict(case=name, passed=ok, exit_code=proc.returncode, failed_checks=len(failures), same_tick_failures=len(tick_failures), summary=[line for line in proc.stdout.splitlines() if line.startswith("F6a:")]))
print(json.dumps(results, indent=2))
raise SystemExit(0 if all(result["passed"] for result in results) else 1)
