#!/usr/bin/env python3
"""D6b-R2: verify fresh throttle evidence using only disposable reader copies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
READER = Path("app/input/rc_input.gd")
CALIBRATION = Path("app/input/rc_calibration.gd")
REGRESSION = Path("app/tests/test_rc_rearm.gd")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="new evidence directory")
    parser.add_argument("--baseline", type=Path, help="optional pre-repair reader")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    godot = subprocess.check_output([str(ROOT / "app/get-godot.sh")], text=True).strip()
    frozen = {path: (ROOT / path).read_bytes() for path in (READER, CALIBRATION, REGRESSION)}
    source = frozen[READER].decode()
    evidence = "\t\t_throttle_low_seen = is_finite(value) and normalize_throttle(value, profile.throttle) <= ARM_THROTTLE"
    profile_reset = "\tprofile_source = source\n\tarmed = false\n\t_throttle_low_seen = false"
    connect_reset = "\tarmed = false\n\t_throttle_low_seen = false\n\t_rate_throttle = 0.0\n\t_seen.clear()"
    mutations = {
        "cached_history": ("elif not armed and _throttle_low_seen and throttle_position() <= ARM_THROTTLE:",
                           "elif not armed and _seen.has(int(profile.throttle.axis)) and throttle_position() <= ARM_THROTTLE:",
                           "stale pre-profile event cannot arm"),
        "missing_profile_reset": (profile_reset, profile_reset.replace("\n\t_throttle_low_seen = false", ""),
                                  "stale pre-profile event cannot arm"),
        "missing_connection_reset": (connect_reset, connect_reset.replace("\n\t_throttle_low_seen = false", ""),
                                     "direct device replacement cannot reuse low evidence"),
        "nonfinite_evidence": (evidence, evidence.replace("is_finite(value) and ", ""),
                               "nonfinite event is not low-throttle evidence"),
        "latched_evidence": (evidence, evidence.replace("= is_finite", "= _throttle_low_seen or (is_finite") + ")",
                             "later high event replaces low evidence"),
        "missing_current_low": ("elif not armed and _throttle_low_seen and throttle_position() <= ARM_THROTTLE:",
                                "elif not armed and _throttle_low_seen:",
                                "low event with high current poll remains safe"),
        "cleared_history": (profile_reset, profile_reset + "\n\t_seen.clear()",
                            "calibration retains raw values and connection history"),
    }
    results = {}
    with tempfile.TemporaryDirectory(prefix="openrc-d6b-r2-private-") as temporary:
        project = Path(temporary)
        (project / "input").mkdir()
        (project / "tests").mkdir()
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="D6b-R2 verification"\n')
        (project / "input/rc_calibration.gd").write_bytes(frozen[CALIBRATION])
        (project / "tests/test_rc_rearm.gd").write_bytes(frozen[REGRESSION])

        def run(name, reader, expected_failure=None):
            (project / "input/rc_input.gd").write_text(reader)
            result = subprocess.run([godot, "--headless", "--path", str(project), "--script",
                                     "res://tests/test_rc_rearm.gd"], capture_output=True, text=True, timeout=60,
                                    env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
            log = result.stdout + result.stderr
            (args.out / (name + ".log")).write_text(log)
            if re.search(r"^(?:SCRIPT |SHADER )?ERROR:", log, re.M):
                raise RuntimeError("engine error cannot count as a detected fault: " + name)
            summary = re.findall(r"D6b-R2: (\d+) checks, (\d+) failed", log)
            if len(summary) != 1:
                raise RuntimeError("missing completed regression: " + name)
            count, failed = map(int, summary[0])
            if count != 365:
                raise RuntimeError("unexpected regression coverage: " + name)
            if expected_failure is None:
                valid = result.returncode == 0 and failed == 0
            else:
                failures = [line for line in log.splitlines() if line.startswith("FAIL ")]
                valid = result.returncode == 1 and failed > 0 and any(expected_failure in line for line in failures)
            if not valid:
                raise RuntimeError("unexpected regression result: " + name)
            results[name] = {"checks": count, "failures": failed, "exit_code": result.returncode,
                             "expected_failure": expected_failure}

        run("control", source)
        if args.baseline:
            run("baseline", args.baseline.read_text(), "stale pre-profile event cannot arm")
        for name, (old, new, failure) in mutations.items():
            if source.count(old) != 1:
                raise RuntimeError("mutation target changed: " + name)
            run(name, source.replace(old, new), failure)
    for path, original in frozen.items():
        if (ROOT / path).read_bytes() != original:
            raise RuntimeError("verification inputs changed: " + str(path))
    report = {"format": "openrc-rc-rearm-verification v1", "results": results,
              "source_sha256": {str(path): hashlib.sha256(value).hexdigest() for path, value in frozen.items()}}
    if args.baseline:
        report["baseline_sha256"] = hashlib.sha256(args.baseline.read_bytes()).hexdigest()
    (args.out / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
