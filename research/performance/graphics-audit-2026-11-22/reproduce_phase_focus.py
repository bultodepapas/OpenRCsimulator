#!/usr/bin/env python3
"""Offline counterexamples for the unmodified, source-bound GOD TEST reducer.

Synthetic packets only: this does not launch Godot, a desktop, or a benchmark.
Uses the repository's existing valid artifact builders, not a second reducer.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
import tempfile


SOURCE = "7940a4081e10994f34c858c4acac3d7a1a271464"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    root = args.repo.resolve()
    out = args.out.resolve()
    if out.exists():
        raise SystemExit("Refusing to overwrite existing evidence")
    sys.path[:0] = [str(root / "tools/godtest"), str(root)]
    from analysis import REDUCER_SOURCES, report, validate_stream
    from runner import read_json, write_json
    from test_godtest import artifacts, replace_stream

    paths = ["tools/godtest/" + name for name in REDUCER_SOURCES]
    paths += ["tools/godtest/test_godtest.py", "app/debug/godtest_driver.gd"]
    hashes = {}
    for relative in paths:
        current = (root / relative).read_bytes()
        frozen = subprocess.check_output(["git", "show", f"{SOURCE}:{relative}"], cwd=root)
        if current != frozen:
            raise SystemExit(f"Source differs from audited main: {relative}")
        hashes[relative] = hashlib.sha256(current).hexdigest()

    results = {
        "format": "openrc-graphics-audit-phase-focus-v1",
        "source_commit": SOURCE,
        "source_sha256": hashes,
        "probe_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "python": platform.python_version(),
        "scope": "Synthetic offline artifact counterexamples using unmodified analysis.report and validate_stream; no engine, GPU, OS focus, or physical presentation observed",
        "boundary_policy": "All fixture intervals align exactly with declared boundaries; no crossing interval ambiguity",
        "phase_cases": [],
        "focus_cases": [],
    }
    with tempfile.TemporaryDirectory(prefix="openrc-phase-focus-") as temporary:
        for name, waiting, selected in (
            ("wait_stall_assigned_to_selection", [10_000] * 100 + [400_000], [10_000] * 100),
            ("fast_wait_dilutes_slow_selection", [10_000] * 600, [40_000] * 20),
        ):
            directory = Path(temporary) / name
            frames = artifacts(directory)
            startup = [10_000, 10_000]
            walls = startup + waiting + selected
            indices = [0] * len(startup) + [1] * (len(waiting) + len(selected))
            replace_stream(directory, frames, walls, indices)
            requested = read_json(directory / "manifest.requested.json")
            requested["phases"] = ["startup", "selection", "shutdown"]
            write_json(directory / "manifest.requested.json", requested)
            write_json(directory / "manifest.resolved.json", {**requested, "output_dir": str(directory)})
            runtime = read_json(directory / "runtime.json")
            start = 1_000_000
            startup_end = start + sum(startup)
            selection_start = startup_end + sum(waiting)
            selection_end = selection_start + sum(selected)
            initial = runtime["phases"][0]
            initial.update(start_usec=start, end_usec=startup_end,
                           wall_seconds=sum(startup) / 1_000_000, frames=len(startup))
            selection = copy.deepcopy(initial)
            selection.update(name="selection", id="0-1-selection", index=1,
                             start_usec=selection_start, end_usec=selection_end,
                             wall_seconds=sum(selected) / 1_000_000, frames=len(selected))
            runtime["phases"].append(selection)
            runtime["identity"]["window_focused_before_selection"] = True
            write_json(directory / "runtime.json", runtime)
            actual = report(directory, write=False)
            reduced = next(phase for phase in actual["phases"] if phase["name"] == "selection")
            integrity = validate_stream(directory, frames)
            exact = sorted(selected)
            expected = {
                "frames": len(selected),
                "sample_wall_ms": sum(selected) / 1000,
                "fps_mean": len(selected) * 1_000_000 / sum(selected),
                "p95_ms": exact[(95 * len(exact) + 99) // 100 - 1] / 1000,
                "max_ms": max(selected) / 1000,
                "over_100ms": sum(value > 100_000 for value in selected),
            }
            assert actual["data"] == "valid", actual["issues"]
            assert reduced["pacing"]["frames"] == len(waiting) + len(selected)
            assert reduced["pacing"]["sample_wall_ms"] == sum(waiting + selected) / 1000
            results["phase_cases"].append({
                "case": name,
                "declared_selection_start_usec": selection_start,
                "declared_selection_end_usec": selection_end,
                "waiting_frames": len(waiting),
                "waiting_wall_ms": sum(waiting) / 1000,
                "declared_selection_only": expected,
                "reported_data": actual["data"],
                "reported_issues": actual["issues"],
                "reported_selection_pacing": reduced["pacing"],
                "reported_selection_frame_ms": reduced["frame_ms"],
                "reported_selection_over_100ms": reduced["hitches"]["100"]["frames"],
                "reported_selection_rendering": integrity["phase_rendering"]["1"],
            })

        for name, focused, override, losses, expect_flagged in (
            ("focused_control", True, None, 0, False),
            ("initially_unfocused_without_later_loss", False, None, 0, False),
            ("initially_unfocused_wayland_override", False, "wayland_without_keyboard_focus", 0, False),
            ("later_focus_loss_positive_control", True, None, 1, True),
        ):
            directory = Path(temporary) / name
            frames = artifacts(directory)
            replace_stream(directory, frames, [10_000] * 4, [0, 0, 1, 1])
            requested = read_json(directory / "manifest.requested.json")
            requested["phases"] = ["startup", "selection", "shutdown"]
            write_json(directory / "manifest.requested.json", requested)
            write_json(directory / "manifest.resolved.json", {**requested, "output_dir": str(directory)})
            runtime = read_json(directory / "runtime.json")
            initial = runtime["phases"][0]
            initial.update(start_usec=1_000_000, end_usec=1_020_000,
                           wall_seconds=.02, frames=2)
            selection = copy.deepcopy(initial)
            selection.update(name="selection", id="0-1-selection", index=1,
                             start_usec=1_020_000, end_usec=1_040_000)
            runtime["phases"].append(selection)
            runtime["identity"]["display_server"] = "Wayland"
            runtime["identity"]["window_focused_before_selection"] = focused
            if override is not None:
                runtime["identity"]["window_focus_probe_override"] = override
            runtime["metrics"]["focus_losses"] = losses
            runtime["phases"][0]["focus_losses"] = 0
            write_json(directory / "runtime.json", runtime)
            actual = report(directory, write=False)
            message = "native focus loss observed; session equivalence requires diagnosis"
            assert (message in actual["issues"]) is expect_flagged, actual["issues"]
            assert (actual["data"] == "valid") is not expect_flagged, actual["issues"]
            results["focus_cases"].append({
                "case": name,
                "synthetic_requested_phases": requested["phases"],
                "synthetic_display_server": "Wayland",
                "synthetic_identity_focused": focused,
                "synthetic_identity_override": override,
                "subsequent_focus_losses": losses,
                "reported_data": actual["data"],
                "reported_performance": actual["performance"],
                "reported_issues": actual["issues"],
            })

    first, second = results["phase_cases"]
    assert first["reported_selection_over_100ms"] == 1
    assert first["declared_selection_only"]["over_100ms"] == 0
    assert second["reported_selection_frame_ms"]["p95"] == 10
    assert second["declared_selection_only"]["p95_ms"] == 40
    results["checks"] = {
        "source_files_match_frozen_main": True,
        "phase_counterexamples_reproduced": 2,
        "focus_cases_checked": 4,
        "later_focus_loss_still_rejected": True,
        "physical_host_failure_observed": False,
        "benchmark_or_fps_gain_measured": False,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(results, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(results["checks"], sort_keys=True))


if __name__ == "__main__":
    main()
