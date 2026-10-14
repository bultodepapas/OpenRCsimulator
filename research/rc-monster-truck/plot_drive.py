"""Plot retained RC driving measurements, verifying CSV hashes before use."""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.patches import Rectangle
import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def read_run(stem: Path):
    report = json.loads(stem.with_suffix(".json").read_text(encoding="utf-8"))
    path = stem.with_suffix(".csv")
    payload = path.read_bytes() if path.exists() else gzip.decompress(stem.with_suffix(".csv.gz").read_bytes())
    if hashlib.sha256(payload).hexdigest() != report["csv"]["sha256"]:
        raise ValueError(f"CSV hash mismatch: {stem}")
    rows = list(csv.DictReader(io.StringIO(payload.decode("utf-8"))))
    if len(rows) != report["sample_count"] or not report["complete"]:
        raise ValueError(f"Incomplete or inconsistent run: {stem}")
    def channel(name):
        return np.array([float(row[name]) for row in rows])
    return report, channel


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--lap", default="candidate-circuit-fast")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("--output must be fresh")
    old, baseline = read_run(args.evidence / "baseline-runway-1")
    new, candidate = read_run(args.evidence / "candidate-runway")
    lap, route = read_run(args.evidence / args.lap)
    track = json.loads((ROOT / "app/data/ground_vehicle/airfield_track.json").read_text())
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
                         "axes.spines.top": False, "axes.spines.right": False})
    fig = plt.figure(figsize=(14, 9), layout="constrained", facecolor="#f9fafb")
    grid = fig.add_gridspec(2, 2, height_ratios=(1.25, 1))
    map_ax = fig.add_subplot(grid[0, :])
    speed_ax = fig.add_subplot(grid[1, 0])
    lap_ax = fig.add_subplot(grid[1, 1])
    fig.suptitle("Bisonte MT8 — measured simulation runs", fontsize=20, fontweight="bold", x=.06, ha="left")
    # Authored lane outlines, not an alternate physics terrain.
    n0, e0 = track["center_north_m"], track["center_east_m"]
    half, radius = track["half_straight_m"], track["radius_m"]
    for offset in (-track["lane_width_m"] / 2, track["lane_width_m"] / 2):
        r = radius + offset
        angle = np.linspace(-math.pi / 2, math.pi / 2, 100)
        east = np.r_[[-half, half], half + r * np.cos(angle), [half, -half], -half - r * np.cos(angle)] + e0
        north = np.r_[[-r, -r], r * np.sin(angle), [r, r], -r * np.sin(angle)] + n0
        map_ax.plot(east, north, color="#cbd5d1", lw=1.5, zorder=0)
    for wall in track["walls"]:
        map_ax.add_patch(Rectangle((wall["east_min_m"], wall["north_min_m"]),
            wall["east_max_m"] - wall["east_min_m"], wall["north_max_m"] - wall["north_min_m"],
            facecolor="#a55b32", edgecolor="none"))
    points = np.column_stack((route("east_m"), route("north_m")))
    segments = np.stack((points[:-1], points[1:]), axis=1)
    colored = LineCollection(segments, cmap="viridis", linewidth=2.5)
    colored.set_array(route("speed_mps")[:-1] * 3.6)
    map_ax.add_collection(colored)
    fig.colorbar(colored, ax=map_ax, label="Speed (km/h)", shrink=.8, pad=.02)
    map_ax.scatter(points[0, 0], points[0, 1], marker="o", s=55, color="#e87924", zorder=4)
    map_ax.annotate("Start / finish", points[0], xytext=(-5, -24), textcoords="offset points")
    map_ax.set(xlim=(-23, 23), ylim=(35, 56), aspect="equal", xlabel="East (m)", ylabel="North (m)")
    map_ax.set_title(f"Complete 85.7 m circuit · {lap['elapsed_sim_s']:.2f} s · peak {lap['max_speed_mps'] * 3.6:.1f} km/h", loc="left", pad=10)
    map_ax.grid(alpha=.12)
    for label, data, color in [("Previous motor", baseline, "#64748b"), ("Revised motor + brakes", candidate, "#d85e1b")]:
        speed_ax.plot(data("time_s"), data("speed_mps") * 3.6, label=label, color=color, lw=2)
    speed_ax.axvline(3, color="#b6bec8", ls="--", lw=1)
    speed_ax.text(3.04, 2, "Brake", color="#64748b")
    speed_ax.set(title="Runway · full throttle for 3 s, then full brake", xlabel="Simulation time (s)", ylabel="Speed (km/h)")
    speed_ax.legend(frameon=False, fontsize=9)
    speed_ax.grid(alpha=.15)
    lap_ax.plot(route("path_progress_m"), route("speed_mps") * 3.6, color="#0f766e", lw=1.5)
    lap_ax.set(title="Circuit · controlled speed through each feature", xlabel="Signed route progress (m)", ylabel="Speed (km/h)")
    lap_ax.grid(alpha=.15)
    fig.text(.5, -.005, "Real coupled solver at 240 Hz · estimated vehicle parameters · software evidence, not physical calibration", ha="center", fontsize=9, color="#64748b")
    fig.savefig(args.output, dpi=160, bbox_inches="tight")
    plt.close(fig)
    args.output.with_suffix(".json").write_text(json.dumps({
        "matplotlib": matplotlib.__version__, "numpy": np.__version__,
        "inputs": [str(args.evidence / value) for value in ["baseline-runway-1", "candidate-runway", args.lap]],
        "csv_sha256": [old["csv"]["sha256"], new["csv"]["sha256"], lap["csv"]["sha256"]],
        "output_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
    }, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
