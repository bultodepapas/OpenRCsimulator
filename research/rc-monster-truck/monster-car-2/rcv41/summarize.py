"""Validate RCV-41 identity/session evidence and current source fingerprints."""
import hashlib
import json
from pathlib import Path
import re
from statistics import median

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUT = ROOT / "docs/research/rc-monster-truck/RCV-41"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(name):
    return json.loads((OUT / name).read_text(encoding="utf-8"))


def check(value, message):
    if not value:
        raise ValueError(message)


def cost(before, after):
    return {"baseline_us": before, "candidate_us": after,
            "reduction_percent": (1 - after / before) * 100}


def main():
    before, after = read("baseline.json"), read("candidate.json")
    pair, identity = read("paired.json"), read("identity.json")
    exploration, checks = read("exploration.json"), read("checks/verification.json")
    for report in [before, after, pair, identity, exploration, checks]:
        check(report["complete"], "incomplete receipt")
    for report in [before, after]:
        for key in ["exact_replay", "checkpoint_restore_exact", "official_replay_exact", "trace_replay_exact"]:
            check(report[key], f"failed {key}")
        check(report["trajectory_sha256"] == report["replay_trajectory_sha256"], "replay trajectory differs")
    for key in ["trajectory_sha256", "final_state_sha256", "accepted_control_tape_sha256",
                "accepted_control_tape_f64_count", "body_backend_identity", "vehicle_identity",
                "control_phases", "maximum_friction_sweeps", "observed_maximum_friction_sweeps"]:
        check(before[key] == after[key], f"unexpected before/after change: {key}")
    check(before["backend_identity"]["source_sha256"] != after["backend_identity"]["source_sha256"], "composite solver identity failed to track edit")
    check(before["course_identity"] != after["course_identity"], "course identity failed to track edit")
    for key in before["backend_identity"]:
        if key != "source_sha256":
            check(before["backend_identity"][key] == after["backend_identity"][key], f"backend changed: {key}")

    sources = {
        "session": ROOT / "app/sim/ground_vehicle/session.gd",
        "dynamics": ROOT / "app/physics/ground_vehicle/vehicle_dynamics.gd",
        "nitro": ROOT / "app/physics/ground_vehicle/nitro_dynamics.gd",
        "baseline_artifacts": HERE / "baseline_artifacts.gd",
        "baseline_session": HERE / "baseline_session.gd",
        "harness": HERE / "bench_pair.gd",
    }
    for key, path in sources.items():
        check(sha(path) == pair["source_sha256"][key], f"paired source changed: {path}")
    for key, path in {"baseline": sources["baseline_artifacts"], "candidate": sources["dynamics"],
                      "session_candidate": sources["session"], "nitro_source": sources["nitro"],
                      "harness": HERE / "bench_identity.gd"}.items():
        check(identity["source_sha256"][key] == sha(path), f"identity source changed: {path}")
    check(exploration["harness_sha256"] == sha(HERE / "probe_identity.gd"), "exploration harness changed")
    for path, key in [("nitro_dynamics.gd", "nitro_dynamics_script_sha256"), ("vehicle_dynamics.gd", "vehicle_dynamics_script_sha256")]:
        check(exploration["content_hashing"]["res://physics/ground_vehicle/" + path]["sha256"] == before["source_identities"][key], "exploration source is not baseline")
    profile_paths = {
        "field_loader_script_sha256": "app/data/field_loader.gd", "field_data_sha256": "app/data/fields/default.json",
        "vehicle_data_sha256": "app/data/vehicles/ground/monster_car_2.json",
        "vehicle_data_script_sha256": "app/physics/ground_vehicle/vehicle_data.gd",
        "session_script_sha256": "app/sim/ground_vehicle/session.gd",
        "nitro_dynamics_script_sha256": "app/physics/ground_vehicle/nitro_dynamics.gd",
        "vehicle_dynamics_script_sha256": "app/physics/ground_vehicle/vehicle_dynamics.gd",
        "vehicle_environment_script_sha256": "app/physics/ground_vehicle/vehicle_environment.gd",
        "damage_observer_script_sha256": "app/physics/ground_vehicle/vehicle_damage.gd",
        "airfield_course_script_sha256": "app/physics/ground_vehicle/airfield_course.gd",
        "airfield_track_script_sha256": "app/physics/ground_vehicle/airfield_track.gd",
        "native_kernel_source_sha256": "research/rc-monster-truck/native/src/ground_vehicle_kernel.hpp",
        "native_wrapper_source_sha256": "research/rc-monster-truck/native/src/ground_vehicle_native.cpp",
        "profile_script_sha256": str((HERE / "bench_session.gd").relative_to(ROOT)),
        "profile_wrapper_sha256": str((HERE / "profiled_session.gd").relative_to(ROOT)),
    }
    for key, path in profile_paths.items():
        check(sha(ROOT / path) == after["source_identities"][key], f"profile source changed: {path}")
        if key not in ["session_script_sha256", "vehicle_dynamics_script_sha256"]:
            check(before["source_identities"][key] == after["source_identities"][key], f"unexpected source change: {path}")
    check(sha(ROOT / "app/native/ground_vehicle/openrc_ground_vehicle.dll") == after["backend_identity"]["binary_sha256"], "native binary changed")
    check(not identity["failures"], "identity mismatch")
    for row in identity["artifact_cases"]:
        if "exact" in row:
            check(row["exact"] and row["baseline"] == row["candidate"], "artifact differs")
        if "cache_bounds" in row:
            check(row["cache_bounds"]["available"] and row["cache_bounds"]["ok"], "cache bounds missing/failed")
    for key in ["sha256_validation_cases", "session_validation_cases"]:
        check(all(row["exact"] for row in identity[key]), f"digest validation failed: {key}")
    for run in pair["rounds"]:
        check(run["trajectory_sha256"] == before["trajectory_sha256"], "paired trajectory differs")
        check(len(run["baseline_tick_us"]) == len(run["candidate_tick_us"]) == 960, "paired timing incomplete")
    count = 0
    for path, digest in checks["sources"].items():
        check(sha(ROOT / path) == digest, f"regression source changed: {path}")
    for row in checks["tests"]:
        check(row["passed"] and row["exit_code"] == 0, f"failed regression: {row['test']}")
        check(sha(OUT / "checks" / row["log"]) == row["log_sha256"], "regression log changed")
        check(sha(ROOT / "app/tests" / row["test"]) == row["test_sha256"], "regression test changed")
        for line in row["summary"]:
            match = re.search(r"(\d+) (?:passed|checks)", line)
            if match:
                count += int(match[1])
    for path in OUT.rglob("*.log"):
        check(not re.search(r"^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ])", path.read_text(encoding="utf-8-sig"), re.M), f"engine error: {path}")
    bench = identity["benchmark"]
    pair_count = bench["calls_per_pair"]
    report = {
        "step": "RCV-41", "complete": True, "solver_changed": True, "course_changed": True,
        "equations_changed": False, "native_binary_changed": False,
        "scope": "Headless CPU timing; medians of three interleaved round means. Identity lookup uses five alternating batches. Not FPS, physical validation, or a full release qualification.",
        "paired_tick_cost": cost(median(r["baseline"]["mean_us"] for r in pair["rounds"]), median(r["candidate"]["mean_us"] for r in pair["rounds"])),
        "paired_p95_cost": cost(median(r["baseline"]["p95_us"] for r in pair["rounds"]), median(r["candidate"]["p95_us"] for r in pair["rounds"])),
        "paired_round_reductions_percent": [cost(r["baseline"]["mean_us"], r["candidate"]["mean_us"])["reduction_percent"] for r in pair["rounds"]],
        "artifact_pair_cost": cost(median(bench["baseline_elapsed_us"]) / pair_count, median(bench["candidate_elapsed_us"]) / pair_count),
        "artifact_cases": identity["artifact_case_count"], "digest_validation_cases": identity["sha256_validation_case_count"] + identity["session_validation_case_count"],
        "exact_state_and_telemetry_ticks": pair["exact_state_and_telemetry_ticks"],
        "trajectory_sha256": before["trajectory_sha256"], "exact_replay_each_version": True,
        "regression_suites_passed": len(checks["tests"]), "reported_numbered_checks_passed": count,
        "source_sha256": {str(p.relative_to(ROOT)).replace("\\", "/"): sha(p) for p in sources.values()},
        "profile_source_sha256": {p.replace("\\", "/"): sha(ROOT / p) for p in profile_paths.values()},
        "evidence_sha256": {str(p.relative_to(OUT)).replace("\\", "/"): sha(p) for p in sorted(OUT.rglob("*"))
                            if p.is_file() and p.suffix in [".json", ".log"] and p.name != "summary.json"},
        "validator_sha256": sha(Path(__file__)),
    }
    (OUT / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ["complete", "paired_tick_cost", "paired_round_reductions_percent", "artifact_pair_cost", "regression_suites_passed", "reported_numbered_checks_passed"]}, indent=2))


if __name__ == "__main__":
    main()
