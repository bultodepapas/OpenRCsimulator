#!/usr/bin/env python3
"""Compare complete recorded stage-parity results, not engine wall-clock times."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("baseline", type=Path)
parser.add_argument("candidate", type=Path)
args = parser.parse_args()
def read(path):
    lines = path.read_text().splitlines()
    prefix = "STAGE_PARITY_RESULT "
    rows = [json.loads(s[len(prefix):]) for s in lines if s.startswith(prefix)]
    if len(rows) != 1 or "STAGE_PARITY_PROBE PASS" not in lines:
        raise SystemExit(f"{path}: expected one successful parity result")
    return rows[0]
baseline, candidate = read(args.baseline), read(args.candidate)
if baseline != candidate:
    keys = sorted(set(baseline) | set(candidate))
    raise SystemExit("Differences: " + ", ".join(k for k in keys if baseline.get(k) != candidate.get(k)))
if (baseline["stage_cases"], baseline["ok_stages"], baseline["refused_stages"],
    baseline["air_ticks"], baseline["ground_ticks"], baseline["event_ticks"],
    baseline["event_count"]) != (90, 72, 18, 48, 16, 4, 2):
    raise SystemExit("Result shape differs from the recorded bounded experiment")
print(json.dumps({"ok": True, "all_recorded_fields_equal": True,
    "stages": baseline["stage_cases"], "accepted": baseline["ok_stages"],
    "refused": baseline["refused_stages"], "ticks": [48, 16, 4], "events": 2}))

