#!/usr/bin/env python3
"""Split GOD TEST frame intervals into main-loop phases (PT1h-R15-S3, F0).

Reads `frametimes.json.frames.jsonl` streams written with `app/render/frame_phases.gd`
metrics and reports, per tour phase, where typical and slow frames spend their wall
time. Offline and read-only; it never launches Godot.

    python tools/godtest/frame_phases.py RUN_OR_SUITE_DIR [--phase runway_circuit] [--slow-ms 16.7] [--json]
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import statistics
import sys

STREAM_NAME = "frametimes.json.frames.jsonl"
DURATIONS = ("tail_process", "tail_engine", "render", "between", "physics", "after_physics", "pre_process", "process")
# Handlers and resumed awaits connected to `physics_frame`/`process_frame`/`frame_post_draw` before the probe land
# in the preceding phase (`after_physics` or `between`); see the probe's METADATA.
LABELS = {
    "tail_process": "late _process (after the observer)",
    "tail_engine": "deferred calls, timers, frees, navigation, render sync",
    "render": "render recording, acquire, submit, present and fence waits",
    "between": "audio, frame limiter, OS events, input, physics sync",
    "physics": "physics ticks",
    "after_physics": "last tick's deferred work and physics step",
    "pre_process": "process_frame handlers, coroutines, deferred calls",
    "process": "_process callbacks before the observer",
}
DEFAULT_SLOW_MS = (16.7, 33.3)


def load_rows(stream: Path) -> list[dict]:
    """Rows of one stream; each has wall_usec, end_usec and every per-frame metric."""
    rows: list[dict] = []
    with stream.open(encoding="utf-8") as handle:
        for line in handle:
            chunk = json.loads(line)
            if chunk.get("type") != "chunk":
                continue
            metrics = chunk.get("metrics", {})
            for offset, wall in enumerate(chunk["wall_usec"]):
                row = {"wall_usec": int(wall), "end_usec": int(chunk["end_usec"][offset])}
                for key, series in metrics.items():
                    row[key] = series[offset]
                rows.append(row)
    return rows


def phase_names(case_dir: Path) -> dict[int, str]:
    runtime = case_dir / "runtime.json"
    if not runtime.is_file():
        return {}
    phases = json.loads(runtime.read_text(encoding="utf-8")).get("phases", [])
    return {int(item["index"]): str(item["name"]) for item in phases if isinstance(item, dict) and "index" in item}


def _ms(values: list[float]) -> dict:
    if not values:
        return {"median": None, "mean": None}
    return {"median": round(statistics.median(values) / 1000.0, 3), "mean": round(statistics.fmean(values) / 1000.0, 3)}


def summarize(rows: list[dict], slow_ms: tuple[float, ...] = DEFAULT_SLOW_MS) -> dict:
    """Typical-frame phase medians and, for each slow threshold, the mean excess per phase."""
    if rows and "phase_valid" not in rows[0]:
        return {"frames": len(rows), "phase_metrics": "absent"}
    valid = [row for row in rows if row.get("phase_valid") == 1]
    for row in valid:
        total = sum(int(row[f"phase_{key}_usec"]) for key in DURATIONS)
        if total != row["wall_usec"]:
            raise ValueError(f"phase durations sum to {total} us, interval is {row['wall_usec']} us")
    result = {"frames": len(rows), "valid": len(valid), "phase_metrics": "present"}
    if not valid:
        return result
    typical = {key: statistics.median(int(row[f"phase_{key}_usec"]) for row in valid) for key in DURATIONS}
    # Excess compares means with means, so it is unbiased for skewed phases and sums to the wall excess.
    typical_mean = {key: statistics.fmean(int(row[f"phase_{key}_usec"]) for row in valid) for key in DURATIONS}
    result["typical"] = {
        "wall_ms": _ms([row["wall_usec"] for row in valid])["median"],
        "ticks": statistics.median(int(row["phase_ticks"]) for row in valid),
        "phases_ms": {key: round(value / 1000.0, 3) for key, value in typical.items()},
        "tick_scripts_ms": _ms([int(row["phase_tick_scripts_usec"]) for row in valid])["median"],
        "drawn_fraction": round(sum(int(row["phase_drawn"]) for row in valid) / len(valid), 4),
    }
    groups = []
    for threshold in slow_ms:
        slow = [row for row in valid if row["wall_usec"] > threshold * 1000.0]
        group = {"threshold_ms": threshold, "frames": len(slow)}
        if slow:
            means = {key: statistics.fmean(int(row[f"phase_{key}_usec"]) for row in slow) for key in DURATIONS}
            excess = {key: round((means[key] - typical_mean[key]) / 1000.0, 3) for key in DURATIONS}
            ticks = [int(row["phase_ticks"]) for row in slow]
            per_tick = [int(row["phase_physics_usec"]) / int(row["phase_ticks"]) for row in slow if int(row["phase_ticks"]) > 0]
            group.update({
                "wall_ms": _ms([row["wall_usec"] for row in slow]),
                "phases_mean_ms": {key: round(value / 1000.0, 3) for key, value in means.items()},
                "excess_mean_ms": excess,
                "largest_excess": max(excess, key=lambda key: excess[key]),
                "ticks": {"median": statistics.median(ticks), "max": max(ticks)},
                "physics_per_tick_ms": _ms(per_tick)["median"],
                "tick_max_ms": _ms([int(row["phase_tick_max_usec"]) for row in slow])["median"],
                "drawn_fraction": round(sum(int(row["phase_drawn"]) for row in slow) / len(slow), 4),
            })
        groups.append(group)
    result["slow"] = groups
    return result


def analyse(directory: Path, phase: str | None = None, slow_ms: tuple[float, ...] = DEFAULT_SLOW_MS) -> list[dict]:
    """One summary per (stream, tour phase); a suite directory is searched for its case streams."""
    streams = sorted(directory.rglob(STREAM_NAME)) if directory.is_dir() else []
    if not streams:
        raise ValueError(f"no {STREAM_NAME} under {directory}")
    results = []
    for stream in streams:
        names = phase_names(stream.parent)
        rows = load_rows(stream)
        by_phase: dict[int, list[dict]] = {}
        for row in rows:
            index = row.get("phase_index")
            if isinstance(index, (int, float)) and math.isfinite(index):
                by_phase.setdefault(int(index), []).append(row)
        for index in sorted(by_phase):
            name = names.get(index, f"phase-{index}")
            if phase is not None and name != phase:
                continue
            results.append({"case": str(stream.parent), "phase_index": index, "phase": name,
                            **summarize(by_phase[index], slow_ms)})
    return results


def render_text(results: list[dict]) -> str:
    lines = []
    for item in results:
        lines.append(f"{item['case']} :: {item['phase']} (#{item['phase_index']}) frames={item['frames']} valid={item.get('valid', 0)}")
        if item.get("phase_metrics") != "present" or "typical" not in item:
            lines.append("  no phase metrics in this stream")
            continue
        typical = item["typical"]
        lines.append(f"  typical: wall {typical['wall_ms']} ms, ticks {typical['ticks']}, drawn {typical['drawn_fraction']}")
        lines.append("    " + ", ".join(f"{key} {value}" for key, value in typical["phases_ms"].items()))
        for group in item["slow"]:
            if not group["frames"]:
                lines.append(f"  > {group['threshold_ms']} ms: none")
                continue
            lines.append(f"  > {group['threshold_ms']} ms: {group['frames']} frames, wall median {group['wall_ms']['median']} ms, "
                         f"ticks median {group['ticks']['median']} (max {group['ticks']['max']}), "
                         f"physics/tick {group['physics_per_tick_ms']} ms; largest excess: {group['largest_excess']} "
                         f"({LABELS[group['largest_excess']]})")
            lines.append("    mean excess over all valid frames (ms): " + ", ".join(
                f"{key} {value:+.2f}" for key, value in group["excess_mean_ms"].items()))
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0], allow_abbrev=False)
    parser.add_argument("directory", type=Path, help="a GOD TEST run, case or suite directory")
    parser.add_argument("--phase", help="only this tour phase, e.g. runway_circuit")
    parser.add_argument("--slow-ms", type=float, action="append", help="slow-frame threshold; repeatable (default 16.7 and 33.3)")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        results = analyse(args.directory, args.phase, tuple(args.slow_ms) if args.slow_ms else DEFAULT_SLOW_MS)
    except (OSError, ValueError, KeyError) as error:
        print(f"frame_phases: {error}", file=sys.stderr)
        return 2
    print(json.dumps(results, indent=2) if args.json else render_text(results))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
