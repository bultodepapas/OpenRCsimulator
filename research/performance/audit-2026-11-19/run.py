#!/usr/bin/env python3
"""Reproduce the 2026-11-19 audit observations in an isolated source fixture.

This is a baseline counterexample runner, not a repaired-solver acceptance test
or a performance benchmark. It uses the existing checked Godot launcher.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]


def digest(path: Path, algorithm: str = "sha256") -> str:
    value = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def read_observation(log: Path, prefix: str) -> dict:
    rows = [line[len(prefix):] for line in log.read_text().splitlines() if line.startswith(prefix)]
    if len(rows) != 1:
        raise RuntimeError(f"Expected exactly one {prefix.strip()} record in {log}")
    return json.loads(rows[0])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path, help="Exact official 4.8-beta2 Linux x86_64 binary")
    parser.add_argument("--out", required=True, type=Path, help="New output directory; existing directories are refused")
    args = parser.parse_args()
    engine = args.godot.resolve()
    out = args.out.resolve()
    manifest = json.loads((HERE / "fixture_sources.json").read_text())
    if not engine.is_file() or digest(engine, "sha512") != manifest["engine_sha512"]:
        raise RuntimeError("Godot binary does not match the audited Linux x86_64 SHA-512; no process launched")
    for name, expected in manifest["files"].items():
        source = REPO / name
        if not source.is_file() or digest(source) != expected:
            raise RuntimeError(f"Audited source identity differs: {name}; this runner requires the baseline")
    # This path creates no app imports, user preferences, native libraries or runtime edits.
    out.mkdir(parents=True, exist_ok=False)
    fixture = out / "fixture"
    fixture.mkdir()
    for name in manifest["files"]:
        relative = Path(name).relative_to("app")
        target = fixture / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / name, target)
    for name in ("event_probe.gd", "calibration_probe.gd"):
        shutil.copyfile(HERE / name, fixture / name)
    (fixture / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="OpenRC Audit Fixture"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
    )
    results = []

    def checked(label: str, command: list[str], required: str = "") -> tuple[dict, Path]:
        launch = [sys.executable, str(REPO / "tools/godot/run_checked.py"),
                  "--label", label, "--out-dir", str(out / "runs"), "--timeout", "60"]
        if required:
            launch += ["--require-text", required]
        launch += ["--", str(engine), *command]
        process = subprocess.run(launch, cwd=REPO, text=True, capture_output=True, check=False)
        reports = list((out / "runs").glob(f"{label}-*/report.json"))
        if len(reports) != 1:
            raise RuntimeError(f"Checked launcher did not produce one receipt for {label}:\n"
                               + process.stdout[-4000:] + process.stderr[-4000:])
        report_path = reports[0]
        receipt = json.loads(report_path.read_text())
        log = report_path.parent / "engine.log"
        if digest(log) != receipt["log_sha256"]:
            raise RuntimeError(f"Checked log hash differs for {label}")
        results.append(dict(label=label, report=str(report_path.relative_to(out)),
                            log=str(log.relative_to(out)), receipt=receipt))
        print(f"{label}: {receipt['reason']} (errors={receipt['counts']['error']}, "
              f"warnings={receipt['counts']['warning']})", flush=True)
        if process.returncode or not receipt.get("ok"):
            raise RuntimeError(f"Checked run failed: {report_path}\n"
                               + process.stdout[-4000:] + process.stderr[-4000:])
        return receipt, log

    common = ["--headless", "--path", str(fixture), "--audio-driver", "Dummy"]
    checked("audit-import", ["--headless", "--editor", "--path", str(fixture), "--import"])
    checked("audit-control", common + ["--script", "res://tests/test_resource_event_step.gd"],
            "resource event step: 54 checks, 0 failed")
    _, event_log = checked("audit-events", common + ["--script", "res://event_probe.gd"],
                           "Audit probe complete")
    _, calibration_log = checked("audit-calibration", common + ["--script", "res://calibration_probe.gd"],
                                 "Calibration probe complete")
    events = read_observation(event_log, "AUDIT_JSON ")
    calibration = read_observation(calibration_log, "CALIBRATION_JSON ")
    flags = {tuple(case.get("event_flags", [])) for case in events["cases"]}
    observed = {
        "F01_missing_interior_in_both_orders": len(events["internal_crossing"]) == 2 and all(
            row["ok"] and row["flags"] == [1, 0] and
            [event["id"] for event in row["events"]] == ["A_endpoint"]
            for row in events["internal_crossing"]),
        "F02_nontransitive_comparator": all(events["comparator_cycle"].values()),
        "F02_three_accepted_flag_sets": len(events["cases"]) == 6 and len(flags) == 3 and
            all(row["ok"] and row["event_flags"] != [1, 1, 1] for row in events["cases"]),
        "F04_scaled_window_size_mismatch": [row["calibration_matches_same_window"] for row in calibration["windows"]]
            == [True, False, False] and all(row["logical"] == [1920, 1080] for row in calibration["windows"]),
        "F05_stale_size_rejection": calibration["rejection_size_matches_1080"] is False and
            calibration["rejection_at_1080"]["profile"] == "standard" and
            calibration["no_rejection_at_1080"]["profile"] == "high",
        "F06_scale_policy_sensitivity_only": calibration["mac_policy_math"]["assumed_recommendation"]["level"] == "medium"
            and calibration["mac_policy_math"]["native_recommendation"]["level"] == "low",
        "F09_incomplete_neutral_suppresses_retry": calibration["incomplete_loaded"]["complete"] is False
            and calibration["incomplete_retry"] is False,
        "F10_intentional_quantile_difference": calibration["percentile"]["hud_nearest_rank_p95"] == 1
            and calibration["percentile"]["calibration_p95"] == 20,
        "rejected_packed_array_copy_lead": all(value == [1, 2, 3] for value in events["packed_alias"].values()),
    }
    summary = dict(format="openrc-audit-reproduction-v1", generated_utc=datetime.now(timezone.utc).isoformat(),
        audited_commit=manifest["base"], source_mode="exact copied dependency closure; no production edits",
        engine_sha512=manifest["engine_sha512"], fixture_source_hashes=manifest["files"],
        reproduction_script_hashes={name: digest(HERE / name) for name in
            ("run.py", "fixture_sources.json", "event_probe.gd", "calibration_probe.gd")},
        local_test_pool_configured=bool(os.environ.get("OPENRC_TESTPOOL_CONFIG")),
        scope="Headless baseline observations, not a benchmark or fixed-solver acceptance test",
        runs=results, observations=dict(events=events, calibration=calibration),
        expected_baseline_observations=observed, baseline_observations_reproduced=all(observed.values()))
    target = out / "audit_results.json"
    target.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")
    print(f"Baseline observations reproduced: {summary['baseline_observations_reproduced']}")
    print(f"Evidence: {target}")
    return 0 if summary["baseline_observations_reproduced"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Audit reproduction stopped: {error}", file=sys.stderr)
        sys.exit(1)
