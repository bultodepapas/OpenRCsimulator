"""Run RCV-42 identity, dynamics and session regressions sequentially with retained logs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
TESTS = [
    "test_rcv_road_batch.gd",
    "test_rcv_session.gd", "test_rcv_nitro_session.gd", "test_nitro_dynamics.gd",
    "test_rcv_airfield_course.gd", "test_rcv_vehicle_dynamics.gd",
    "test_rcv_nitro_service.gd", "test_rcv_damage_session.gd", "test_rcv_obstacle_contacts.gd",
]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--validate-existing", action="store_true", help="Reparse retained logs after verifying their hashes and source identities")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    existing = {}
    if args.validate_existing:
        receipt = json.loads((args.out / "verification.json").read_text(encoding="utf-8"))
        for path, digest in receipt["sources"].items():
            if sha256(ROOT / path) != digest:
                raise ValueError(f"Changed source: {path}")
        existing = {row["test"]: row for row in receipt["tests"]}
    rows = []
    for test in TESTS:
        command = [str(args.godot.resolve()), "--headless", "--path", str(ROOT / "app"),
                   "--audio-driver", "Dummy", "--script", "res://tests/" + test]
        log_path = args.out / (Path(test).stem + ".log")
        if args.validate_existing:
            row = existing[test]
            if sha256(log_path) != row["log_sha256"] or sha256(ROOT / "app/tests" / test) != row["test_sha256"]:
                raise ValueError(f"Changed log or test: {test}")
            log, exit_code = log_path.read_text(encoding="utf-8"), row["exit_code"]
        else:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace", timeout=300)
            log, exit_code = result.stdout + result.stderr, result.returncode
            log_path.write_text(log, encoding="utf-8")
        summaries = [match.group(0) for match in re.finditer(
            r"^.*(?:\b0 (?:failed|failures)|\b(?P<count>\d+)/(?P=count) checks passed).*$", log, re.M)]
        errors = re.findall(r"^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ]).*$", log, re.M)
        passed = exit_code == 0 and bool(summaries) and not errors
        rows.append({"test": test, "passed": passed, "exit_code": exit_code,
                     "summary": summaries, "errors": errors, "log": log_path.name,
                     "log_sha256": sha256(log_path), "test_sha256": sha256(ROOT / "app/tests" / test)})
        print(f"{'PASS' if passed else 'FAIL'} {test}: {'; '.join(summaries or errors)}", flush=True)
    sources = ["app/physics/ground_vehicle/vehicle_dynamics.gd", "app/physics/ground_vehicle/nitro_dynamics.gd",
               "app/physics/ground_vehicle/airfield_course.gd", "app/sim/ground_vehicle/session.gd"]
    report = {"step": "RCV-42", "complete": all(row["passed"] for row in rows),
              "sources": {source: sha256(ROOT / source) for source in sources}, "tests": rows}
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
