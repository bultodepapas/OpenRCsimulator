"""Run RCV-40 terrain, contact and session regressions sequentially with retained logs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
TESTS = [
    "test_ground_terrain.gd", "test_ground_contact.gd", "test_ground_surfaces.gd",
    "test_ground_start_environment.gd", "test_lake_ground_contact.gd",
    "test_heli_ground_start.gd", "test_heli_ground_session.gd",
    "test_rcv_airfield_track.gd", "test_rcv_airfield_course.gd",
    "test_rcv_nitro_session.gd", "test_nitro_dynamics.gd", "test_rcv_session.gd",
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
                                encoding="utf-8", errors="replace", timeout=300)
        log = result.stdout + result.stderr
        log_path = args.out / (Path(test).stem + ".log")
        log_path.write_text(log, encoding="utf-8")
        summaries = re.findall(r"^.*(?:\b0 (?:failed|failures)|all lake ground contact checks passed).*$", log, re.M)
        errors = re.findall(r"^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ]).*$", log, re.M)
        passed = result.returncode == 0 and bool(summaries) and not errors
        rows.append({"test": test, "passed": passed, "exit_code": result.returncode,
                     "summary": summaries, "errors": errors, "log": log_path.name,
                     "log_sha256": sha256(log_path), "test_sha256": sha256(ROOT / "app/tests" / test)})
        print(f"{'PASS' if passed else 'FAIL'} {test}: {'; '.join(summaries or errors)}", flush=True)
    sources = ["app/physics/ground_terrain.gd", "app/physics/ground_vehicle/airfield_course.gd",
               "app/physics/ground_vehicle/airfield_track.gd", "app/sim/ground_vehicle/session.gd"]
    report = {"step": "RCV-40", "complete": all(row["passed"] for row in rows),
              "sources": {source: sha256(ROOT / source) for source in sources}, "tests": rows}
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
