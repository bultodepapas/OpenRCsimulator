#!/usr/bin/env python3
"""Plot saved AV-16 pitch-sweep trajectories; this script does not run Godot."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.lines import Line2D


ROOT = Path(__file__).resolve().parents[3]
REPORT_DIR = ROOT / "docs" / "research" / "avanti-realism" / "AV-16"
DEFAULT_REPORTS = {
    "Baseline 240 Hz": REPORT_DIR / "pitch-sweep-baseline-240.json",
    "Candidate 240 Hz": REPORT_DIR / "pitch-sweep-240.json",
    "Candidate 480 Hz": REPORT_DIR / "pitch-sweep-480.json",
}
RUN_STYLES = {
    "Baseline 240 Hz": "-",
    "Candidate 240 Hz": "--",
    "Candidate 480 Hz": ":",
}
MAGNITUDES = (0.05, 0.10, 0.15, 0.25)
COLORS = {
    0.05: "#0072B2",
    0.10: "#D55E00",
    0.15: "#009E73",
    0.25: "#CC79A7",
}


def _load_report(path: Path) -> dict[float, dict[str, Any]]:
    report = json.loads(path.read_text(encoding="utf-8"))
    if report.get("schema") != "openrc-avanti-pitch-sweep-v1":
        raise ValueError(f"{path}: unexpected schema {report.get('schema')!r}")

    cases: dict[float, dict[str, Any]] = {}
    for case in report.get("cases", []):
        command = float(case["pitch_command"])
        columns = case["sample_columns"]
        samples = case["trajectory_samples"]
        heading = case["trajectory"]["vertical_plane_heading_ned"]
        if columns != ["time_s", "north_m", "east_m", "altitude_m"]:
            raise ValueError(f"{path}: unsupported trajectory columns {columns!r}")
        if len(heading) != 2 or len(samples) < 2:
            raise ValueError(f"{path}: incomplete trajectory for {command:+.2f}")

        index = {name: columns.index(name) for name in columns}
        start_north = float(samples[0][index["north_m"]])
        start_east = float(samples[0][index["east_m"]])
        start_altitude = float(samples[0][index["altitude_m"]])
        along_north, along_east = map(float, heading)
        along = []
        altitude = []
        for row in samples:
            north = float(row[index["north_m"]])
            east = float(row[index["east_m"]])
            along.append((north - start_north) * along_north + (east - start_east) * along_east)
            altitude.append(float(row[index["altitude_m"]]) - start_altitude)

        cases[command] = {
            "along_m": along,
            "altitude_change_m": altitude,
            "trajectory": case["trajectory"],
            "report": report,
        }

    if len(cases) != 8:
        raise ValueError(f"{path}: expected eight signed pitch inputs, got {len(cases)}")
    return cases


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_REPORTS["Baseline 240 Hz"])
    parser.add_argument("--candidate-240", type=Path, default=DEFAULT_REPORTS["Candidate 240 Hz"])
    parser.add_argument("--candidate-480", type=Path, default=DEFAULT_REPORTS["Candidate 480 Hz"])
    parser.add_argument("--output", type=Path, default=REPORT_DIR / "pitch-sweep.png")
    return parser.parse_args()


def main() -> None:
    args = _arguments()
    paths = {
        "Baseline 240 Hz": args.baseline,
        "Candidate 240 Hz": args.candidate_240,
        "Candidate 480 Hz": args.candidate_480,
    }
    runs = {label: _load_report(path) for label, path in paths.items()}

    all_along = [value for cases in runs.values() for case in cases.values() for value in case["along_m"]]
    all_altitude = [
        value for cases in runs.values() for case in cases.values() for value in case["altitude_change_m"]
    ]
    pad = 0.025 * max(max(all_along) - min(all_along), max(all_altitude) - min(all_altitude), 1.0)
    x_limits = (min(all_along) - pad, max(all_along) + pad)
    y_limits = (min(all_altitude) - pad, max(all_altitude) + pad)

    fig, axes = plt.subplots(1, 2, figsize=(15.5, 9.0), sharex=True, sharey=True)
    for axis, sign, title in zip(axes, (1, -1), ("Positive pitch command", "Negative pitch command")):
        for magnitude in MAGNITUDES:
            command = sign * magnitude
            for label, cases in runs.items():
                case = cases[command]
                axis.plot(
                    case["along_m"],
                    case["altitude_change_m"],
                    color=COLORS[magnitude],
                    linestyle=RUN_STYLES[label],
                    linewidth=1.65 if label == "Baseline 240 Hz" else 1.35,
                    alpha=0.9,
                    zorder=3 if label == "Candidate 480 Hz" else 2,
                )
                axis.plot(
                    case["along_m"][-1],
                    case["altitude_change_m"][-1],
                    marker="o",
                    markersize=3.1,
                    color=COLORS[magnitude],
                    markeredgecolor="white",
                    markeredgewidth=0.45,
                    zorder=4,
                )
        axis.axhline(0.0, color="#777777", linewidth=0.7, zorder=1)
        axis.axvline(0.0, color="#777777", linewidth=0.7, zorder=1)
        axis.scatter([0.0], [0.0], marker="*", s=85, color="#202020", zorder=5)
        axis.grid(True, color="#D9DDE2", linewidth=0.65)
        axis.set_title(title, pad=10, fontweight="bold")
        axis.set_xlabel("Distance along initial heading (m)")
        axis.set_xlim(*x_limits)
        axis.set_ylim(*y_limits)
        axis.set_aspect("equal", adjustable="box")
    axes[0].set_ylabel("Altitude change from initial (m)")

    magnitude_handles = [
        Line2D([0], [0], color=COLORS[m], lw=2, label=f"|pitch| = {m:.2f}") for m in MAGNITUDES
    ]
    run_handles = [
        Line2D([0], [0], color="#404040", lw=1.8, linestyle=RUN_STYLES[label], label=label)
        for label in RUN_STYLES
    ]
    fig.legend(
        handles=magnitude_handles,
        title="Normalized input",
        loc="upper center",
        bbox_to_anchor=(0.32, 0.94),
        ncol=4,
        frameon=False,
        columnspacing=1.0,
    )
    fig.legend(
        handles=run_handles,
        title="Model snapshot / timestep",
        loc="upper center",
        bbox_to_anchor=(0.74, 0.94),
        ncol=3,
        frameon=False,
        columnspacing=1.0,
    )
    fig.suptitle("AV-16 pitch-input sweep: projected trajectories", y=0.995, fontsize=15, fontweight="bold")
    fig.text(
        0.5,
        0.018,
        "Star = start; dots = endpoints. Along-track/altitude projection uses each case's initial vertical plane; "
        "cross-track is omitted here. "
        "Saved model predictions only, not flight validation.",
        ha="center",
        fontsize=9,
        color="#444444",
    )
    fig.tight_layout(rect=(0.025, 0.065, 0.98, 0.865))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=200, facecolor="white")
    plt.close(fig)
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
