#!/usr/bin/env python3
"""Run VAL-8a's positive control and bounded defects on disposable copies only."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
MUTATIONS = {
    "inclusive_frame_count": ("n = end[\"frame\"] - start[\"frame\"]", "n = end[\"frame\"] - start[\"frame\"] + 1",
                              "test_known_answer_and_not_inclusive_frame_count"),
    "dropped_capture_clock": ("clock_u = campaign[\"video\"][\"fps_relative_u\"]", "clock_u = 0.0",
                              "test_calibration_does_not_average_away"),
    "dropped_survey_scale": ("scale_u = campaign[\"survey\"][\"scale_relative_u\"]", "scale_u = 0.0",
                             "test_calibration_does_not_average_away"),
    "ignored_event_correlation": ("rho = event[\"frame_x_correlation\"]", "rho = 0.0",
                                  "test_correlated_position_frame_picks"),
    "lost_shared_event_identity": ('f"event:{name}:joint"', 'f"event:{start_id}:{end_id}:{name}:joint"',
                                   "test_shared_event_and_calibration_covariance"),
}


def run(directory, case=None):
    args = [sys.executable, str(directory/"test_reduce.py")]
    if case:
        args.append("ReductionTests."+case)
    return subprocess.run(args, capture_output=True, text=True, timeout=30)


def main():
    with tempfile.TemporaryDirectory(prefix="openrc-val8a-mutations-") as tmp:
        copy = Path(tmp)/"ground-video"
        shutil.copytree(HERE, copy, ignore=shutil.ignore_patterns("__pycache__"))
        control = run(copy)
        if control.returncode:
            sys.stderr.write(control.stdout+control.stderr)
            return 1
        source = (copy/"reduce.py").read_text()
        results = {"positive_control": "passed", "mutations": {}}
        for name, (old, new, case) in MUTATIONS.items():
            if source.count(old) != 1:
                raise ValueError(f"mutation target changed: {name}")
            (copy/"reduce.py").write_text(source.replace(old, new))
            shutil.rmtree(copy/"__pycache__", ignore_errors=True)
            result = run(copy, case)
            detected = result.returncode != 0 and "FAIL: "+case in result.stderr and "ERROR:" not in result.stderr
            results["mutations"][name] = {"test": case, "assertion_detected": detected}
            if not detected:
                sys.stderr.write(result.stdout+result.stderr)
                print(json.dumps(results, indent=2))
                return 1
        print(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
