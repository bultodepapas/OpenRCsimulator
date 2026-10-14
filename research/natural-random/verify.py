"""NR focused native checks. Runs production scripts with isolated test preferences; no golden updates."""
from __future__ import annotations

import argparse
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = [
    "scenarios/scenario_config.gd", "scenarios/natural_random.gd",
    "ui/natural_random_screen.gd", "ui/home.gd", "app_root.gd", "main.gd",
]
TESTS = [
    "test_natural_random_config", "test_natural_random_generator", "test_natural_random_screen",
    "test_natural_random_flight", "test_ui_natural_random",
    "test_ui_home", "test_ui_home_layout", "test_ui_language", "test_ui_screen_stack",
    "test_ui_aircraft", "test_ui_pause", "test_ui_weather", "test_ui_time_of_day_pause",
    "test_ui_field_world_time_of_day", "test_start_choice", "test_wind_flight",
    "test_wind_turbulence", "test_atmosphere_flight", "test_time_of_day_checkpoint",
    "test_checkpoint_integrity", "test_replay_integrity", "test_workshop_integration",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--tests", nargs="*", choices=TESTS)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    godot = args.godot.resolve()
    base = [str(godot), "--headless", "--path", str(ROOT / "app"), "--audio-driver", "Dummy"]
    commands = [("import", ["--editor", "--import", "--quit"])]
    commands += [("parse-" + Path(p).stem, ["--check-only", "--script", "res://" + p]) for p in SCRIPTS]
    commands += [(name, ["--script", "res://tests/" + name + ".gd"]) for name in (args.tests if args.tests is not None else TESTS)]
    report = {"scope": "software verification; no physical/pilot/performance acceptance", "results": [], "ok": True}
    for name, command in commands:
        started = time.monotonic()
        timed_out = False
        try:
            with (out / (name + ".log")).open("wb") as stream:
                result = subprocess.run(base + command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=600)
            log = (out / (name + ".log")).read_text(encoding="utf-8", errors="replace")
            code = result.returncode
        except subprocess.TimeoutExpired:
            log = (out / (name + ".log")).read_text(encoding="utf-8", errors="replace")
            code, timed_out = -1, True
        errors = [line for line in log.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:", "SHADER ERROR:", "FAIL "))]
        passed = code == 0 and not errors
        (out / (name + ".log")).write_text(log, encoding="utf-8")
        report["results"].append({"name": name, "ok": passed, "exit_code": code, "timeout": timed_out,
                                  "elapsed_s": round(time.monotonic() - started, 3), "errors": errors})
        report["ok"] &= passed
        (out / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"{'PASS' if passed else 'FAIL'} {name}", flush=True)
        if not passed:
            print("\n".join(errors[:8]), flush=True)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
