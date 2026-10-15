"""Validate RCV-40 receipts against retained/current sources and summarize CPU cost."""
import hashlib
import json
from pathlib import Path
import re
from statistics import median

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OUT = ROOT / "docs/research/rc-monster-truck/RCV-40"


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
    pair, terrain, track = read("paired.json"), read("terrain.json"), read("track.json")
    checks = read("checks/verification.json")
    for name, report in [("baseline", before), ("candidate", after), ("pair", pair),
                         ("terrain", terrain), ("track", track), ("checks", checks)]:
        check(report["complete"], f"incomplete {name}")
    for report in [before, after]:
        for key in ["exact_replay", "checkpoint_restore_exact", "official_replay_exact", "trace_replay_exact"]:
            check(report[key], f"replay check failed: {key}")
        check(report["trajectory_sha256"] == report["replay_trajectory_sha256"], "replay trajectory differs")
    for key in ["trajectory_sha256", "final_state_sha256", "accepted_control_tape_sha256",
                "accepted_control_tape_f64_count", "backend_identity", "body_backend_identity",
                "vehicle_identity", "control_phases", "maximum_friction_sweeps"]:
        check(before[key] == after[key], f"before/after differs: {key}")
    check(before["course_identity"] != after["course_identity"], "course identity did not track source edits")
    check(terrain["differences"] == [] and track["difference_count"] == 0, "sampler mismatch")

    source_paths = {
        "session": ROOT / "app/sim/ground_vehicle/session.gd",
        "baseline_terrain": HERE / "baseline_terrain.gd",
        "candidate_terrain": ROOT / "app/physics/ground_terrain.gd",
        "baseline_track": HERE / "baseline_track.gd",
        "candidate_track": ROOT / "app/physics/ground_vehicle/airfield_track.gd",
        "baseline_course": HERE / "baseline_course.gd",
        "candidate_course": ROOT / "app/physics/ground_vehicle/airfield_course.gd",
        "harness": HERE / "bench_pair.gd",
    }
    for key, path in source_paths.items():
        check(sha(path) == pair["source_sha256"][key], f"paired source changed: {path}")
    bridge = source_paths["baseline_course"].read_text(encoding="utf-8")
    bridge = bridge.replace("res://../research/rc-monster-truck/monster-car-2/rcv40/baseline_terrain.gd", "res://physics/ground_terrain.gd")
    bridge = bridge.replace("res://../research/rc-monster-truck/monster-car-2/rcv40/baseline_track.gd", "res://physics/ground_vehicle/airfield_track.gd")
    check(bridge == source_paths["candidate_course"].read_text(encoding="utf-8"), "reference course bridge has other changes")
    for name, report in [("terrain", terrain), ("track", track)]:
        for key in ["baseline", "candidate"]:
            check(report["source_sha256"][key] == sha(source_paths[f"{key}_{name}"]), f"{name} source changed")
        check(report["source_sha256"]["harness"] == sha(HERE / f"bench_{name}.gd"), f"{name} harness changed")
    for key in before["source_identities"]:
        if key != "airfield_track_script_sha256":
            check(before["source_identities"][key] == after["source_identities"][key], f"unexpected source change: {key}")
    check(before["source_identities"]["airfield_track_script_sha256"] == sha(HERE / "baseline_track.gd"), "track reference is not the baseline")
    for report in [before, after]:
        check(report["source_identities"]["profile_script_sha256"] == sha(HERE / "bench_session.gd"), "session harness changed")
        check(report["source_identities"]["profile_wrapper_sha256"] == sha(HERE / "profiled_session.gd"), "profile wrapper changed")
    for path, digest in checks["sources"].items():
        check(sha(ROOT / path) == digest, f"regression source changed: {path}")
    test_assertions = 0
    for row in checks["tests"]:
        check(row["passed"] and row["exit_code"] == 0, f"failed {row['test']}")
        check(sha(OUT / "checks" / row["log"]) == row["log_sha256"], "test log changed")
        check(sha(ROOT / "app/tests" / row["test"]) == row["test_sha256"], "test source changed")
        for summary in row["summary"]:
            match = re.search(r"(\d+) passed", summary)
            if match:
                test_assertions += int(match[1])
    for path in OUT.rglob("*.log"):
        log = path.read_text(encoding="utf-8-sig")
        check(not re.search(r"^(?:(?:SCRIPT |SHADER )?ERROR:|FAIL[: ])", log, re.M), f"engine error: {path}")
    for run in pair["rounds"]:
        check(run["trajectory_sha256"] == before["trajectory_sha256"], "paired trajectory differs")
        check(len(run["baseline_tick_us"]) == len(run["candidate_tick_us"]) == 960, "incomplete paired timings")
    paired_cost = cost(median(r["baseline"]["mean_us"] for r in pair["rounds"]),
                       median(r["candidate"]["mean_us"] for r in pair["rounds"]))
    components = {}
    for name, bench in [("terrain", terrain["benchmark"]), *track["benchmark"].items()]:
        calls = bench["calls_per_timed_pass"]
        components[name] = cost(bench["baseline_median_us"] / calls, bench["candidate_median_us"] / calls)
    report = {
        "step": "RCV-40", "complete": True, "solver_changed": False, "course_changed": True,
        "scope": "Headless CPU timing; median of three interleaved round means. Component medians use five alternating batches. Not a frame/GPU or physical-validation claim.",
        "paired_tick_cost": paired_cost, "component_costs": components,
        "paired_round_reductions_percent": [cost(r["baseline"]["mean_us"], r["candidate"]["mean_us"])["reduction_percent"] for r in pair["rounds"]],
        "terrain_comparisons_including_invalid_classification": terrain["bit_comparisons"],
        "track_exact_comparisons": track["exact_comparisons"],
        "paired_exact_state_and_telemetry_ticks": pair["exact_state_and_telemetry_ticks"],
        "trajectory_sha256": before["trajectory_sha256"], "exact_replay_each_version": True,
        "regression_suites_passed": len(checks["tests"]), "reported_numbered_assertions_passed": test_assertions,
        "baseline_course_identity": before["course_identity"], "candidate_course_identity": after["course_identity"],
        "current_source_sha256": {str(path.relative_to(ROOT)).replace("\\", "/"): sha(path) for path in source_paths.values()},
        "evidence_sha256": {str(path.relative_to(OUT)).replace("\\", "/"): sha(path)
                            for path in sorted(OUT.rglob("*")) if path.is_file() and path.suffix in [".json", ".log"] and path.name != "summary.json"},
        "validator_sha256": sha(Path(__file__)),
    }
    (OUT / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in ["complete", "paired_tick_cost", "component_costs",
          "regression_suites_passed", "reported_numbered_assertions_passed"]}, indent=2))


if __name__ == "__main__":
    main()
