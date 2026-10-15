"""Validate retained RCV-42 evidence and reduce paired CPU measurements."""
import hashlib
import json
from pathlib import Path
import re
from statistics import median

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / "docs/research/rc-monster-truck/RCV-42"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(name):
    return json.loads((OUT / name).read_text(encoding="utf-8"))


def main():
    receipt = read("measurement-receipt.json")
    checks = read("checks/verification.json")
    assert receipt["complete"] and checks["complete"]
    for source, digest in {**receipt["sources"], **checks["sources"]}.items():
        assert sha(ROOT / source) == digest, source
    for row in receipt["measurements"]:
        assert row["exit_code"] == 0 and not row["errors"]
        assert sha(OUT / (row["name"] + ".json")) == row["report_sha256"]
        assert sha(OUT / (row["name"] + ".log")) == row["log_sha256"]
        assert sha(ROOT / row["script"]) == row["script_sha256"]
    numbered_checks = 0
    for row in checks["tests"]:
        assert row["passed"] and row["exit_code"] == 0 and not row["errors"]
        assert sha(OUT / "checks" / row["log"]) == row["log_sha256"]
        assert sha(ROOT / "app/tests" / row["test"]) == row["test_sha256"]
        for line in row["summary"]:
            match = re.search(r"\b(\d+)(?:/\d+)? checks", line)
            if match:
                numbered_checks += int(match[1])
    baseline, candidate, paired, batch = map(read, ["baseline.json", "candidate.json", "paired.json", "batch.json"])
    assert all(report["complete"] for report in [baseline, candidate, paired, batch])
    assert sha(ROOT / "research/rc-monster-truck/monster-car-2/rcv42/baseline_vehicle_dynamics.gd") == baseline["source_identities"]["vehicle_dynamics_script_sha256"]
    for report in [baseline, candidate]:
        assert all(report[key] for key in ["checkpoint_restore_exact", "exact_replay", "official_replay_exact", "trace_replay_exact"])
        assert report["physics_ticks_per_second"] == 240
        assert report["backend_identity"]["backend"] == "native"
        assert report["profile"]["road_sampling"]["calls"] == 67200
    for key in ["trajectory_sha256", "final_state_sha256", "accepted_control_tape_sha256"]:
        assert baseline[key] == candidate[key], key
    assert baseline["backend_identity"]["binary_sha256"] == candidate["backend_identity"]["binary_sha256"]
    assert sha(ROOT / "app/native/ground_vehicle/openrc_ground_vehicle.dll") == candidate["backend_identity"]["binary_sha256"]
    assert len(paired["rounds"]) == 3 and paired["exact_state_and_telemetry_ticks"] == 3060
    for row in paired["rounds"]:
        assert row["trajectory_sha256"] == baseline["trajectory_sha256"]
        assert len(row["baseline_tick_us"]) == len(row["candidate_tick_us"]) == 960
    before = median(row["baseline"]["mean_us"] for row in paired["rounds"])
    after = median(row["candidate"]["mean_us"] for row in paired["rounds"])
    p95_before = median(row["baseline"]["p95_us"] for row in paired["rounds"])
    p95_after = median(row["candidate"]["p95_us"] for row in paired["rounds"])
    component_before = median(row["baseline"] for row in batch["rounds_us_per_14_sample_batch"])
    component_after = median(row["fused"] for row in batch["rounds_us_per_14_sample_batch"])
    report = {"step": "RCV-42", "complete": True,
        "whole_session": {"baseline_us": before, "candidate_us": after,
            "reduction_percent": 100 * (1 - after / before),
            "baseline_p95_us": p95_before, "candidate_p95_us": p95_after,
            "round_reductions_percent": [100 * (1 - row["candidate"]["mean_us"] / row["baseline"]["mean_us"]) for row in paired["rounds"]]},
        "component": {"baseline_us_per_14_samples": component_before, "candidate_us_per_14_samples": component_after,
            "reduction_percent": 100 * (1 - component_after / component_before), "exact_comparisons": batch["checks"]},
        "verification": {"suites": len(checks["tests"]), "numbered_checks": numbered_checks,
            "exact_paired_ticks": paired["exact_state_and_telemetry_ticks"], "trajectory_sha256": candidate["trajectory_sha256"]},
        "solver_changed": baseline["backend_identity"] != candidate["backend_identity"],
        "course_changed": baseline["course_identity"] != candidate["course_identity"],
        "native_binary_changed": False, "equations_changed": False,
        "road_queries_per_tick": candidate["profile"]["road_sampling"]["calls"] / candidate["measured_ticks"],
        "real_time_gate_closed": False,
        "scope": "Windows headless source-runtime CPU comparison on a shared host. No FPS/GPU, packaged-runtime or physical qualification claim.",
        "evidence_sha256": {p.relative_to(OUT).as_posix(): sha(p) for p in sorted(OUT.rglob("*.json")) if p.name != "summary.json"}}
    assert report["solver_changed"] and report["course_changed"]
    (OUT / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ["whole_session", "component", "verification"]}, indent=2))


if __name__ == "__main__":
    main()
