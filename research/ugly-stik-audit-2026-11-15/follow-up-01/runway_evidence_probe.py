#!/usr/bin/env python3
"""Read-only synthetic boundary probe for OpenRC's runway comparison report.

The imported report's source stays unchanged. Inputs and outputs are retained in
the required, new --out JSON. No PNG files, image decoding, engine, or renderer
are involved. All temporary run/history directories are outside the repository.
"""

from __future__ import annotations

import argparse
import contextlib
import copy
import datetime as dt
import hashlib
import importlib.util
import io
import json
import platform
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy
import PIL


def make_frame(view: str, time_s: float, north_m: float = 0.0) -> dict:
    # Fictional, equal declared digests force compare()'s existing no-image branch.
    return {
        "view": view,
        "t_s": time_s,
        "image": f"{view}/t{time_s:05.1f}.png",
        "sha256": "a" * 64,
        "north_m": north_m,
        "east_m": 0.0,
        "height_m": 1.0,
        "speed_ms": 2.0,
        "heading_deg": 3.0,
        "pitch_deg": 4.0,
        "roll_deg": 5.0,
        "rpm": 6.0,
        "prop_angle_deg": 7.0,
        "sim_clock": time_s,
    }


def make_manifest(aircraft: str, frames: list[dict]) -> dict:
    return {
        "format": "openrc-runway-scenario v1",
        "aircraft": aircraft,
        "frames": copy.deepcopy(frames),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path, help="new JSON receipt outside the repository")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent / "OpenRCsimulator")
    args = parser.parse_args()
    repo = args.repo.resolve(strict=True)
    out = args.out.resolve()
    if out.is_relative_to(repo):
        parser.error("--out must be outside the repository")
    if out.exists():
        parser.error("--out must be a new file")
    if not out.parent.is_dir():
        parser.error("the --out parent directory must already exist")
    source = repo / "tools/scenery/scenario_report.py"
    source_bytes = source.read_bytes()
    source_sha256 = hashlib.sha256(source_bytes).hexdigest()

    # Prevent creation of __pycache__ beside the imported repo file.
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("audit_runway_scenario_report", source)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load report source")
    report = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(report)

    def refuse_image_load(path: Path) -> None:
        raise AssertionError(f"unexpected image-load branch: {path}")

    report.load = refuse_image_load
    frame1 = make_frame("pilot", 1.0)
    frame2 = make_frame("pilot", 2.0)
    frame9 = make_frame("pilot", 9.0)
    changed = make_frame("pilot", 1.0, north_m=0.001)
    electric = "stik-electric-6s"
    basic = "jensen-das-ugly-stik-60"
    cases_in = [
        ("identical_matched_positive_control", make_manifest(electric, [frame1, frame2]),
         make_manifest(electric, [frame1, frame2])),
        ("same_frames_different_aircraft_id", make_manifest(basic, [frame1, frame2]),
         make_manifest(electric, [frame1, frame2])),
        ("no_overlapping_frame_keys", make_manifest(electric, [frame9]),
         make_manifest(electric, [frame1])),
        ("previous_frame_removed", make_manifest(electric, [frame1]),
         make_manifest(electric, [frame1, frame2])),
        ("changed_sampled_state_positive_control", make_manifest(electric, [changed]),
         make_manifest(electric, [frame1])),
    ]
    observations = []
    validation_errors = []
    expected_verdicts = {
        "identical_matched_positive_control": "identical",
        "same_frames_different_aircraft_id": "identical",
        "no_overlapping_frame_keys": "identical",
        "previous_frame_removed": "identical",
        "changed_sampled_state_positive_control": "physics changed",
    }
    with tempfile.TemporaryDirectory(prefix="openrc-runway-probe-") as temp_root:
        temporary = Path(temp_root)
        for name, current, previous in cases_in:
            curdir = temporary / name / "current"
            olddir = temporary / name / "previous"
            curdir.mkdir(parents=True)
            olddir.mkdir(parents=True)
            # compare() receives parsed manifest dictionaries, exactly as main() does.
            (curdir / "scenario.json").write_text(json.dumps(current), encoding="utf-8")
            (olddir / "scenario.json").write_text(json.dumps(previous), encoding="utf-8")
            actual = report.compare(curdir, olddir, current, previous)
            observed_statuses = [row["status"] for row in actual["frames"]]
            current_keys = [[row["view"], row["t_s"]] for row in current["frames"]]
            previous_keys = [[row["view"], row["t_s"]] for row in previous["frames"]]
            if actual["verdict"] != expected_verdicts[name]:
                validation_errors.append(f"{name}: unexpected verdict {actual['verdict']!r}")
            if name == "no_overlapping_frame_keys" and observed_statuses != ["new frame"]:
                validation_errors.append(f"{name}: unexpected statuses {observed_statuses!r}")
            if name == "previous_frame_removed" and len(actual["frames"]) != 1:
                validation_errors.append(f"{name}: unexpected emitted frame count")
            if name == "changed_sampled_state_positive_control" and not actual["frames"][0]["state_changes"]:
                validation_errors.append(f"{name}: missing sampled state change")
            observations.append({"case": name, "inputs": {"current": current, "previous": previous},
                                 "input_keys": {"current": current_keys, "previous": previous_keys},
                                 "output": actual})

        # history_index reads each run's receipt if present; these are synthetic
        # controls, with the missing case containing no sync.json whatsoever.
        history = temporary / "history"
        history.mkdir()
        history_inputs = {
            "missing_sync": None,
            "empty_sync": [],
            "present_pass": [{"check": "synthetic control", "ok": True}],
            "present_fail": [{"check": "synthetic control", "ok": False}],
        }
        for name, receipt in history_inputs.items():
            directory = history / name
            directory.mkdir()
            (directory / "scenario.json").write_text(json.dumps(make_manifest(electric, [frame1])), encoding="utf-8")
            if receipt is not None:
                (directory / "sync.json").write_text(json.dumps(receipt), encoding="utf-8")
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            report.history_index(history)
        html = (history / "index.html").read_text(encoding="utf-8")
        headings = re.findall(r"<h2>(.*?)</h2>", html)
        labels = {}
        for name in history_inputs:
            matches = [heading for heading in headings if heading.startswith(name + " · ")]
            if len(matches) != 1:
                validation_errors.append(f"{name}: expected exactly one history row")
                continue
            heading = matches[0]
            labels[name] = {"heading": heading,
                            "sync_label": "pass" if ">sync pass<" in heading else "FAIL" if ">sync FAIL<" in heading else "unrecognized"}
        expected_labels = {"missing_sync": "pass", "empty_sync": "pass", "present_pass": "pass", "present_fail": "FAIL"}
        for name, expected in expected_labels.items():
            if labels.get(name, {}).get("sync_label") != expected:
                validation_errors.append(f"{name}: unexpected history label {labels.get(name)!r}")
        history_result = {"inputs": {"scenario_manifest": make_manifest(electric, [frame1]),
                                     "sync_receipts": history_inputs},
                          "output": {"stdout": captured.getvalue(), "html": html, "labels": labels}}

    after_sha256 = hashlib.sha256(source.read_bytes()).hexdigest()
    if after_sha256 != source_sha256:
        validation_errors.append("the imported source changed while this probe ran")
    git_head = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True,
                              capture_output=True, text=True).stdout.strip()
    receipt = {
        "format": "openrc-runway-report-synthetic-probe-v1",
        "generated_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "scope": "synthetic metadata-only report comparison; no images or engine",
        "source": {"path": str(source), "sha256_before": source_sha256,
                   "sha256_after": after_sha256, "repository_head": git_head},
        "environment": {"python": platform.python_version(), "numpy": numpy.__version__,
                        "pillow": PIL.__version__},
        "notes": ["Image hashes and state samples are invented test inputs, not captures.",
                  "Temporary paths in compare outputs were removed after the call.",
                  "The image-load function was replaced with a failing sentinel to ensure it is never used."],
        "comparison_cases": observations,
        "history_cases": history_result,
        "validation_errors": validation_errors,
    }
    with out.open("x", encoding="utf-8") as handle:
        json.dump(receipt, handle, indent=2)
        handle.write("\n")
    print(f"RUNWAY_PROBE_DONE comparison_cases={len(observations)} history_cases={len(history_inputs)} "
          f"validation_errors={len(validation_errors)} receipt={out}")
    for issue in validation_errors:
        print("FAIL", issue, file=sys.stderr)
    return 1 if validation_errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
