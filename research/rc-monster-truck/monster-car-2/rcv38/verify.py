"""Run the RCV-38 focused checks sequentially; retain source identities and logs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
TESTS = [
    "test_rcv38_lights.gd",
    "test_rcv_ground_effects.gd",
    "test_rcv36_effects.gd",
    "test_rcv_nitro_activity.gd",
    "test_rcv_activity.gd",
]
SOURCES = [
    "app/vehicles/ground/monster_car_2_lights.gd",
    "app/vehicles/ground/ground_effects.gd",
    "app/vehicles/ground/ground_scene.gd",
    "app/vehicles/ground/ground_dashboard.gd",
]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    rows = []
    for test in TESTS:
        command = [str(args.godot.resolve()), "--headless", "--path", str(ROOT / "app"),
                   "--audio-driver", "Dummy", "--script", "res://tests/" + test]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=180)
        log = result.stdout + result.stderr
        log_path = args.out / (Path(test).stem + ".log")
        log_path.write_text(log, encoding="utf-8")
        summary = re.findall(r"^.*\b\d+ checks, 0 failures.*$", log, re.M)
        errors = re.findall(r"^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ]).*$", log, re.M)
        passed = result.returncode == 0 and bool(summary) and not errors
        rows.append({"test": test, "passed": passed, "exit_code": result.returncode,
                     "summary": summary, "errors": errors, "log": log_path.name,
                     "log_sha256": sha256(log_path),
                     "test_sha256": sha256(ROOT / "app/tests" / test)})
        print(f"{'PASS' if passed else 'FAIL'} {test}: {'; '.join(summary or errors)}", flush=True)
    report = {"step": "RCV-38", "complete": all(row["passed"] for row in rows),
              "sources": {source: sha256(ROOT / source) for source in SOURCES}, "tests": rows}
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
