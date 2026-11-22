"""Reproduce five offline counterexamples from the 2026-11-22 main audit.

Run from the repository root with Python 3.12:
    python3 -B research/performance/godtest/audit_main_20261122.py

Exit zero means the documented defects were reproduced, NOT that the benchmark
passed. No engine, GPU sampler, queue job or network operation is started. Only
temporary synthetic frame streams are written. Listed probe-input bytes must match
the audited hashes below; later fixes require a new verification record, not changes
to these historical expectations. The guard reads local files without invoking Git.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import platform
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[3]
AUDITED_COMMIT = "7940a4081e10994f34c858c4acac3d7a1a271464"
COMPARISON_COMMIT = "7a403ea059830913192696138020fd78ec458820"
EXPECTED_SOURCE_SHA256 = {
    "app/debug/godtest_driver.gd": "fd198cf550e53005f53bec006f1b5c86838784dda8472222c8ee6e26b6bb262f",
    "research/performance/godtest/pilot.gd": "bf223b016f7fb74a4f2d26fee95237e5ee01c222f2bde263ce64ede778531569",
    "research/performance/godtest/runway_circuit.gd": "9d8d6b412f1bb33ed8da11b1704940359e1b2d6c21dc1b2e1f14d7cc22a95103",
    "tools/godot/resource_samples.py": "5dc82ef9c0875d34addc6a446b58cf3a83b619b8dfaa8d778ad008cf61069a03",
    "tools/godot/run_checked.py": "69de29252150e7815e3e44b2d887bd69ed2b76d948460572491baa17e5af2888",
    "tools/godtest/admission.py": "b61efa942e2424b1675a87e293a0f68486e6f2d29ff8d3282068452e73c657c7",
    "tools/godtest/analysis.py": "cfa56993edc6adf7951e6447d4a0cd33319b0b9d1b6243c0059762c0e7ebff75",
    "tools/godtest/catalog.py": "9e6a72186329086f94d8188a84ccfe194e8e0016cffa5a5c042af4a048ebe656",
    "tools/godtest/godtest.py": "2cd1fafa6b08ec21381410e9f99dc906197988a1b50dca6280ca4d306f89ee5d",
    "tools/godtest/gpu_coverage.py": "d6ff2baf1760094d892c7fcc92f6e97908aff4866313f2e521afa913067b5879",
    "tools/godtest/hardware.py": "b1470f0c990c6c273c3915f0ae2e3789a25b12b8619cdc89166f4311d7bad4e6",
    "tools/godtest/isolation.py": "2ce2368119bf11b77a511d819b71cfedd49838d9bac56522efc05a5803ca63c8",
    "tools/godtest/pace_windows.py": "cc1eb6269346eb682161f8b8efd56a1cf7cfdf9b77c34e84dba11efc2e60884e",
    "tools/godtest/render_evidence.py": "93235343ef005c089275157e3620faf969f2f7a8d987484b5c2168dfb49de0bb",
    "tools/godtest/resource_coverage.py": "22fd747bc63ed491b2faff56bf5a1d67bff6598e7078a8ce99896fbfaf2ecde3",
    "tools/godtest/runner.py": "e2db797afab31b70125d7bedf2dc6f31ef8b16a5e6e43c35c95c934754493568",
    "tools/godtest/test_render_evidence.py": "a9fd2f9a4e308a368a957d40920ec5fabd218fa55f91778babf0d8f7870a8963",
    "tools/godtest/tour_report.py": "c895c14ce4edf6f4b7d1eae4a98081cf87a5f1d2ddb683924836b2c36ea461fe",
    "tools/testqueue/__init__.py": "5baaa9ea0a675272a578afb9ce3b404d079ebbe12062c3a76821264265738c9c",
    "tools/testqueue/common.py": "d19fb3ecbad3b884689829b76ff0faa0036262c391dfeba6e6781ba76cf2d481",
    "tools/testqueue/presets.py": "030dd9d534428f4eb92fd94961dd5a139379b2c9d6c4ce522df274cee9b3e7e1"
}


def check(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def source_identity() -> dict:
    hashes = {}
    for relative, expected in EXPECTED_SOURCE_SHA256.items():
        actual = (ROOT / relative).read_bytes()
        observed = hashlib.sha256(actual).hexdigest()
        check(observed == expected, f"source differs from audited commit: {relative}")
        hashes[relative] = observed
    return hashes


def render_transition_probe() -> dict:
    from render_evidence import RenderAccumulator, validate_rendering
    from test_render_evidence import request_fixture

    requested, resolved, runtime, phases, _, execution = request_fixture()
    rows = [(0, 1_000_000, 1_000_000, 1, 1, 1, 0),
            (0, 2_000_000, 1_000_000, 2, 1, 1, 0)]
    rows += [(1, index * 1_000_000, 1_000_000, index, 1, 0, 1)
             for index in range(3, 7)]

    def reduce_rows(values):
        accumulator = RenderAccumulator()
        for row in values:
            accumulator.add(*row)
        return accumulator.finish()

    claimed = reduce_rows(rows)
    unclaimed = reduce_rows([(*row[:-1], 0) for row in rows])
    verdict = validate_rendering(requested, resolved, runtime, phases, claimed, execution)
    check(claimed["1"]["status"] == verdict["status"] == "complete",
          "expected the unsupported selection transition to pass")
    check(unclaimed["1"]["status"] == "incomplete",
          "control without transition label must remain incomplete")
    return {
        "finding": "M02", "evidence_kind": "synthetic_reducer_counterexample",
        "host": execution["host"], "phase": "selection", "actual_drawable_intervals": 0,
        "claimed_transition_intervals": 4, "mode_event_supplied": False,
        "claimed_raw_receipt": claimed["1"], "rendering_verdict": verdict,
        "control_without_label_status": unclaimed["1"]["status"],
        "limit": "Not a complete campaign or a claim that the producer emitted this contradictory fixture.",
    }


def reduce_walls(walls: list[int], start_usec: int = 0) -> dict:
    from analysis import validate_stream

    ends, elapsed = [], start_usec
    for wall in walls:
        elapsed += wall
        ends.append(elapsed)
    records = [
        {"type": "header", "format": "openrc-frame-stream v1"},
        {"type": "chunk", "sequence": 0, "start_frame": 0, "frames": len(walls),
         "wall_usec": walls, "end_usec": ends, "engine_delta_s": [x / 1e6 for x in walls],
         "metrics": {"phase_index": [1] * len(walls)}},
        {"type": "trailer", "complete": True, "frames": len(walls), "chunks": 1},
    ]
    data = b"".join((json.dumps(row) + "\n").encode() for row in records)
    with tempfile.TemporaryDirectory(prefix="openrc-main-audit-") as temporary:
        path = Path(temporary)
        (path / "stream.jsonl").write_bytes(data)
        receipt = {"frames": len(walls), "complete": True,
                   "stream": {"file": "stream.jsonl", "bytes": len(data),
                              "sha256": hashlib.sha256(data).hexdigest(),
                              "frames": len(walls), "chunks": 1, "complete": True}}
        reduced = validate_stream(path, receipt)
    return {"stream_valid": reduced["valid"], "pacing": reduced["phase_pacing"]["1"],
            "frame_ms": reduced["phase_stats"]["1"]}


def focus_gap_probe() -> dict:
    contaminated = reduce_walls([1_000_000] * 4 + [10_000] * 100)
    selection_only = reduce_walls([10_000] * 100, start_usec=4_000_000)
    check(contaminated["pacing"]["fps_mean"] == 20.8 and contaminated["frame_ms"]["p99"] == 1000,
          "expected focus-gap samples to contaminate selection statistics")
    check(selection_only["pacing"]["fps_mean"] == 100 and selection_only["frame_ms"]["p99"] == 10,
          "selection-only control has unexpected statistics")
    return {"finding": "M01", "evidence_kind": "synthetic_stream_reduction",
            "fixture_selection_interval_usec": [4_000_000, 5_000_000],
            "with_preselection_wait": contaminated, "selection_only_control": selection_only,
            "limit": "The synthetic phase boundary describes the fixture; validate_stream receives only raw phase indices. Actual producer control flow is reviewed separately."}


def takeoff_probe() -> dict:
    command = [sys.executable, "-B", "tools/godtest/godtest.py", "run", "ugly-standard",
               "--entry", "isolated", "--phase", "takeoff", "--dry-run"]
    plan = json.loads(subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True).stdout)
    case = plan["cases"][0]
    check(case["start"] == "airborne" and case["phases"] == ["takeoff"],
          "expected the isolated takeoff planner to admit an airborne start")
    return {"finding": "M04", "evidence_kind": "actual_cli_dry_run",
            "aircraft": case["aircraft"], "start": case["start"], "phases": case["phases"],
            "entry": case["entry"],
            "limit": "No flight executed. Completion risk additionally follows the pilot's altitude/climb/elapsed predicate."}


def lap_probe() -> dict:
    from analysis import runway_receipt_valid

    receipt = dict(format="openrc-godtest-runway-circuit-v1", complete=True, failed=False,
                   center_north_m=0, center_east_m=0, target_radius_m=120,
                   runway_enclosing_radius_m=50, inner_radius_m=78, outer_radius_m=198,
                   clockwise_sweep_rad=math.tau, lap_sim_seconds=10,
                   minimum_radius_m=120, maximum_radius_m=120,
                   minimum_agl_m=65, maximum_agl_m=65, quadrants_mask=15,
                   agl_limits_m=[20, 140], accepted_samples=0)
    accepted = runway_receipt_valid(receipt)
    control = runway_receipt_valid({**receipt, "clockwise_sweep_rad": 0})
    check(accepted is True and control is False, "expected zero-sample lap acceptance and incomplete-winding refusal")
    return {"finding": "M05", "evidence_kind": "synthetic_aggregate_receipt",
            "input": receipt, "accepted": accepted, "zero_winding_control_accepted": control,
            "limit": "Does not claim the actual observer produced zero samples or that historical flights were invalid."}


def admission_probe() -> dict:
    from admission import execution_budget
    from catalog import performance_tour
    from tools.testqueue.presets import validate

    argv = ["performance-tour", "--repeats", "3"]
    cases = performance_tour() * 3
    budget = execution_budget(cases)
    short = validate("godtest", {"argv": argv, "timeout": 1})["timeout"]
    default = validate("godtest", {"argv": argv})["timeout"]
    check((len(cases), budget, short, default) == (9, 14924, 1, 3600),
          "expected the admitted direct presets to undercut the calculated roster lease")
    return {"finding": "M06", "evidence_kind": "actual_offline_preset_validation",
            "case_count": len(cases), "case_timeout_sum_seconds": sum(c["timeout_s"] for c in cases),
            "managed_cli_budget_seconds": budget, "accepted_direct_timeout_seconds": short,
            "accepted_direct_default_seconds": default, "job_submitted": False}


def main() -> None:
    hashes = source_identity()
    sys.path[:0] = [str(ROOT), str(ROOT / "tools/godtest")]
    result = {"format": "openrc-godtest-main-audit-probes-v1", "audit_date": "2026-11-22",
              "audited_commit": AUDITED_COMMIT, "comparison_commit": COMPARISON_COMMIT,
              "python": platform.python_version(), "platform": platform.system(),
              "architecture": platform.machine(), "source_sha256": hashes,
              "reproducer_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "observed_behavior_matches_audited_defects": True,
              "qualification": "none; offline counterexamples only",
              "probes": [focus_gap_probe(), render_transition_probe(), takeoff_probe(), lap_probe(), admission_probe()]}
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
