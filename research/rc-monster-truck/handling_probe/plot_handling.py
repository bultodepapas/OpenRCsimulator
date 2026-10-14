#!/usr/bin/env python3
"""Plot hash-verified baseline/candidate handling traces."""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


SURFACE_COLORS = {"asphalt": "#d95f02", "grass": "#1b9e77", "gravel": "#7570b3"}
RUN_COLORS = {"baseline": "#343a40", "candidate": "#1769aa"}


def load_run(receipt_path: Path) -> tuple[dict, dict[str, list[dict[str, str]]]]:
    report = json.loads(receipt_path.read_text(encoding="utf-8"))
    if report.get("format") != "openrc-rcv-handling-probe" or report.get("version") != 1:
        raise ValueError(f"unsupported run receipt: {receipt_path}")
    if not report.get("complete"):
        raise ValueError(f"incomplete handling run: {receipt_path}")
    changed = report.get("source_manifest", {}).get("changed_during_run", [])
    if changed:
        raise ValueError(f"run has changing inputs ({receipt_path}): {changed}")
    csv_info = report["csv"]
    csv_path = Path(csv_info.get("storage_path", csv_info["path"]))
    if not csv_path.is_file():
        raise FileNotFoundError(csv_path)
    digest = hashlib.sha256(csv_path.read_bytes()).hexdigest()
    expected_digest = csv_info.get("storage_sha256", csv_info["sha256"])
    if digest != expected_digest:
        raise ValueError(f"CSV hash mismatch: {csv_path}")
    if csv_info.get("storage_format") == "gzip":
        decoded = gzip.decompress(csv_path.read_bytes())
        if hashlib.sha256(decoded).hexdigest() != csv_info["sha256"]:
            raise ValueError(f"decompressed CSV hash mismatch: {csv_path}")
        rows = list(csv.DictReader(io.StringIO(decoded.decode("utf-8"), newline="")))
    else:
        with csv_path.open("r", newline="", encoding="utf-8") as stream:
            rows = list(csv.DictReader(stream))
    if len(rows) != report["csv"]["rows"]:
        raise ValueError(f"CSV row count mismatch: {csv_path}")
    by_case: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_case.setdefault(row["case_id"], []).append(row)
    return report, by_case


def f(row: dict[str, str], key: str) -> float | None:
    value = row.get(key, "")
    if not value:
        return None
    return float(value)


def series(rows: list[dict[str, str]], key: str) -> tuple[list[float], list[float]]:
    x: list[float] = []
    y: list[float] = []
    for row in rows:
        value = f(row, key)
        if value is not None:
            x.append(float(row["time_s"]))
            y.append(value)
    return x, y


def unwrap(values: list[float]) -> list[float]:
    if not values:
        return []
    result = [values[0]]
    previous = values[0]
    for value in values[1:]:
        delta = (value - previous + 3.141592653589793) % (2.0 * 3.141592653589793) - 3.141592653589793
        result.append(result[-1] + delta)
        previous = value
    return result


def case_rows(
    runs: dict[str, dict[str, tuple[dict, dict[str, list[dict[str, str]]]]]], run: str, name: str, case: str
):
    report, cases = runs[name][run]
    if case not in cases:
        raise ValueError(f"missing case {case} in {name} {run} receipt")
    return cases[case]


def assert_matched(baseline: dict, candidate: dict, name: str) -> None:
    for field in ("scenario", "fixed_hz", "control_tape"):
        if baseline.get(field) != candidate.get(field):
            raise ValueError(f"{name}: baseline/candidate {field} differs")
    baseline_initial = baseline.get("initial_conditions", {})
    candidate_initial = candidate.get("initial_conditions", {})
    for field in (
        "protocol", "forward_speed_m_per_s", "lateral_speed_m_per_s", "wheel_spin",
        "seeded_components", "surface_geometry",
    ):
        if baseline_initial.get(field) != candidate_initial.get(field):
            raise ValueError(f"{name}: baseline/candidate initial-condition field {field} differs")
    for field in ("north_m", "east_m", "heading_rad", "vehicle_up_m"):
        if baseline_initial.get("pose", {}).get(field) != candidate_initial.get("pose", {}).get(field):
            raise ValueError(f"{name}: baseline/candidate start-pose recipe field {field} differs")


def plot(args: argparse.Namespace) -> None:
    paths = {
        "10m": {"baseline": args.baseline_10, "candidate": args.candidate_10},
        "11.87m": {"baseline": args.baseline_1187, "candidate": args.candidate_1187},
    }
    runs = {
        run: {name: load_run(path) for name, path in by_name.items()}
        for run, by_name in paths.items()
    }
    assert_matched(runs["10m"]["baseline"][0], runs["10m"]["candidate"][0], "10 m/s")
    assert_matched(runs["11.87m"]["baseline"][0], runs["11.87m"]["candidate"][0], "11.87 m/s")

    fig, axes = plt.subplots(2, 3, figsize=(17, 10), constrained_layout=True)
    fig.suptitle(args.title, fontsize=17, fontweight="bold")

    ax = axes[0, 0]
    labels: list[str] = []
    baseline_values: list[float] = []
    candidate_values: list[float] = []
    for speed_name in ("10m", "11.87m"):
        for surface in ("asphalt", "grass", "gravel"):
            for brake, suffix in ((1.0, "full"), (0.6, "partial")):
                case = f"brake_{surface}_{suffix}"
                base_case = next(c for c in runs[speed_name]["baseline"][0]["cases"] if c["case_id"] == case)
                candidate_case = next(c for c in runs[speed_name]["candidate"][0]["cases"] if c["case_id"] == case)
                if base_case["stop_distance_m"] < 0 or candidate_case["stop_distance_m"] < 0:
                    raise ValueError(f"missing stop distance for {speed_name} {case}")
                labels.append(f"{speed_name}\n{surface[:3]} {'1.0' if brake == 1.0 else '.6'}")
                baseline_values.append(float(base_case["stop_distance_m"]))
                candidate_values.append(float(candidate_case["stop_distance_m"]))
    x = list(range(len(labels)))
    width = 0.37
    ax.bar([v - width / 2 for v in x], baseline_values, width, color=RUN_COLORS["baseline"], label="Baseline")
    ax.bar([v + width / 2 for v in x], candidate_values, width, color=RUN_COLORS["candidate"], label="Candidate")
    ax.set_xticks(x, labels, rotation=45, ha="right", fontsize=8)
    ax.set_ylabel("Stopping distance (m)")
    ax.set_title("Matched stop distances")
    ax.grid(axis="y", alpha=0.25)
    ax.legend(frameon=False)

    ax = axes[0, 1]
    ax_right = ax.twinx()
    for run in ("baseline", "candidate"):
        rows = case_rows(runs, run, "10m", "brake_asphalt_partial")
        tx, lateral = series(rows, "v_m_per_s")
        ty, yaw_rate = series(rows, "yaw_rate_rad_s")
        ax.plot(tx, lateral, color=RUN_COLORS[run], label=f"{run} lateral speed")
        ax_right.plot(ty, yaw_rate, color=RUN_COLORS[run], linestyle="--", label=f"{run} heading rate")
    ax.set_title("10 m/s asphalt, 0.6 brake")
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Body lateral speed (m/s)")
    ax_right.set_ylabel("Valid heading rate (rad/s)")
    ax.grid(alpha=0.25)
    left_lines, left_labels = ax.get_legend_handles_labels()
    right_lines, right_labels = ax_right.get_legend_handles_labels()
    ax.legend(left_lines + right_lines, left_labels + right_labels, fontsize=8, frameon=False, loc="upper right")

    ax = axes[0, 2]
    for run in ("baseline", "candidate"):
        rows = case_rows(runs, run, "11.87m", "brake_asphalt_full")
        tx, tilt = series(rows, "tilt_deg")
        ax.plot(tx, tilt, color=RUN_COLORS[run], label=run)
    ax.set_title("11.87 m/s asphalt, full brake: supported-start tilt")
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Body tilt from upright (degrees)")
    ax.set_ylim(0, 8)
    ax.grid(alpha=0.25)
    ax.legend(frameon=False)

    ax = axes[1, 0]
    for run in ("baseline", "candidate"):
        rows = case_rows(runs, run, "11.87m", "brake_asphalt_partial")
        tx, yaw_rate = series(rows, "yaw_rate_rad_s")
        ax.plot(tx, yaw_rate, color=RUN_COLORS[run], label=f"{run} heading rate")
    ax.set_title("11.87 m/s asphalt, 0.6 brake")
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Valid heading rate (rad/s)")
    ax.grid(alpha=0.25)
    ax.legend(frameon=False)

    ax = axes[1, 1]
    for run in ("baseline", "candidate"):
        for surface, color in SURFACE_COLORS.items():
            rows = case_rows(runs, run, "10m", f"swerve_{surface}_swerve")
            north_start = float(rows[0]["north_m"])
            east_start = float(rows[0]["east_m"])
            north = [float(row["north_m"]) - north_start for row in rows]
            east = [float(row["east_m"]) - east_start for row in rows]
            ax.plot(east, north, color=color, linestyle="-" if run == "baseline" else "--",
                    label=f"{surface} {run}", linewidth=1.4)
    ax.set_title("10 m/s countersteer path")
    ax.set_xlabel("East displacement from start (m)")
    ax.set_ylabel("North displacement from start (m)")
    ax.set_aspect("equal", adjustable="datalim")
    ax.grid(alpha=0.25)
    ax.legend(fontsize=7, frameon=False, ncol=2)

    ax = axes[1, 2]
    for run in ("baseline", "candidate"):
        rows = case_rows(runs, run, "10m", "swerve_asphalt_swerve")
        tx, slip = series(rows, "body_slip_angle_rad")
        ax.plot(tx, [v * 180.0 / 3.141592653589793 for v in unwrap(slip)],
                color=RUN_COLORS[run], label=f"{run} body slip")
    ax.axhline(5.0, color="#666666", linestyle=":", linewidth=1.0)
    ax.axhline(-5.0, color="#666666", linestyle=":", linewidth=1.0)
    ax.axvline(1.25, color="#c0392b", linestyle="--", linewidth=1.0, label="Neutral begins")
    ax.set_title("10 m/s asphalt, swerve recovery")
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Valid body velocity angle (degrees)")
    ax.grid(alpha=0.25)
    ax.legend(frameon=False)

    fig.text(0.5, -0.01, "Heading is omitted above 60° tilt; body slip is omitted below 0.5 m/s. Synthetic surface estimates; not physical validation.",
             ha="center", fontsize=9)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print(f"plot: {args.output}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--baseline-10", type=Path, required=True)
    result.add_argument("--candidate-10", type=Path, required=True)
    result.add_argument("--baseline-1187", type=Path, required=True)
    result.add_argument("--candidate-1187", type=Path, required=True)
    result.add_argument("--output", type=Path, required=True)
    result.add_argument("--title", default="RCV handling comparison — controlled simulation traces")
    return result


if __name__ == "__main__":
    plot(parser().parse_args())
