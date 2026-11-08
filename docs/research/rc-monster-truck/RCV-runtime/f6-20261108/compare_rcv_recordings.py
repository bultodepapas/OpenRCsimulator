"""Compare the saved ground-vehicle baseline and candidate on their actual recorded tape."""
import csv
import hashlib
import json
import math
from pathlib import Path

root = Path(__file__).resolve().parent

def read_json(name):
    return json.loads((root / name).read_text(encoding="utf-8"))

def read_csv(name):
    with (root / name).open(encoding="utf-8", newline="") as stream:
        if stream.readline().strip() != "# openrc-ground-vehicle-recording v4":
            raise ValueError("recording format mismatch")
        return list(csv.DictReader(stream))

base = read_json("baseline-replay.json")
candidate = read_json("candidate-replay.json")
base_record = read_json("baseline-recording.json")
candidate_record = read_json("candidate-recording.json")
left = read_csv("baseline.csv")
right = read_csv("candidate.csv")
if not (base["complete"] and base["exact_replay"] and candidate["complete"]
        and candidate["same_tape"] and candidate["solver_changed"] and candidate["candidate_self_replay"]
        and candidate["old_checkpoint_refused"] and base["ticks"] == candidate["ticks"] == 840
        and base["samples"] == candidate["samples"] == 841 and len(left) == len(right) == 841
        and base["tape_sha256"] == candidate["tape_sha256"]
        and base_record["model_identity"] == candidate_record["model_identity"]
        and base_record["course_identity"] == candidate_record["course_identity"]):
    raise ValueError("incomplete or incomparable baseline/candidate")

first = None
max_position = max_velocity = max_spin = max_attitude_deg = 0.0
for index, (before, after) in enumerate(zip(left, right)):
    if any(before[key] != after[key] for key in ("tick", "time_s", "throttle", "steering", "brake", "reverse")):
        raise ValueError(f"recorded time/control mismatch at row {index}")
    a, b = json.loads(before["state_json"]), json.loads(after["state_json"])
    if len(a) != 31 or len(b) != 31 or not all(map(math.isfinite, a + b)):
        raise ValueError(f"invalid state at row {index}")
    if first is None and a != b:
        first = int(before["tick"])
    max_position = max(max_position, math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3))))
    max_velocity = max(max_velocity, math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3, 6))))
    max_spin = max(max_spin, *(abs(a[i] - b[i]) for i in range(21, 25)))
    dot = abs(sum(a[i] * b[i] for i in range(6, 10)))
    max_attitude_deg = max(max_attitude_deg, math.degrees(2 * math.acos(min(1.0, dot))))

report = {
    "complete": True, "solver_changed": True, "same_recorded_controls": True, "samples": len(left),
    "first_state_divergence_tick": first, "max_position_difference_m": max_position,
    "max_body_velocity_difference_mps": max_velocity, "max_wheel_spin_difference_radps": max_spin,
    "max_attitude_difference_deg": max_attitude_deg,
    "baseline_csv_sha256": hashlib.sha256((root / "baseline.csv").read_bytes()).hexdigest(),
    "candidate_csv_sha256": hashlib.sha256((root / "candidate.csv").read_bytes()).hexdigest(),
    "note": "One open-loop control tape on the estimated practice course; not an exact cross-solver replay or physical validation.",
}
out = root / "same-tape-comparison.json"
with out.open("x", encoding="utf-8") as stream:
    json.dump(report, stream, indent=2, sort_keys=True)
    stream.write("\n")
print(json.dumps(report, sort_keys=True))
