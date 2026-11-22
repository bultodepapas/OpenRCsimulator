#!/usr/bin/env python3
"""Fit a descriptive pixel-cost model to a pinned, retained paused-view table.

Offline arithmetic only: does not launch Godot, query a GPU, or measure FPS.
The reported ranges are sensitivity inputs, not statistical confidence intervals.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import re
import subprocess
from pathlib import Path

PIN = "85a2475f60029a4b6b09f23f643119bceea84a45"
REPORT = "docs/research/god-test/2026-11-22-linux-uhd630-comparison.md"
LABELS = {
    "mobile": "Minimal, Mobile",
    "compatibility": "Minimal, Compatibility (the product's iGPU renderer)",
    "forward_plus": "Minimal, Forward+",
}


def fps_range(cell: str) -> list[float] | None:
    clean = cell.replace("**", "").strip()
    if clean == "—":
        return None
    match = re.fullmatch(r"(\d+(?:\.\d+)?)(?:–(\d+(?:\.\d+)?))? FPS", clean)
    if not match:
        raise ValueError(f"Unrecognized FPS cell: {cell!r}")
    low, high = float(match[1]), float(match[2] or match[1])
    if low <= 0.0 or high < low:
        raise ValueError("Invalid positive FPS range")
    return [low, high]


def fit(native_fps: float, scaled_fps: float) -> dict[str, float]:
    native_ms, scaled_ms = 1000.0 / native_fps, 1000.0 / scaled_fps
    b = (native_ms - scaled_ms) / (1.0 - 0.75**2)
    a = native_ms - b
    return {
        "fixed_term_ms": a,
        "pixel_term_at_native_ms": b,
        "native_frame_ms": native_ms,
        "scale_075_frame_ms": scaled_ms,
        "pixel_term_fraction_at_native": b / native_ms,
        "predicted_scale_067_frame_ms": a + b * 0.67**2,
        "predicted_scale_067_fps": 1000.0 / (a + b * 0.67**2),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error("--out must be new; retained evidence is never overwritten")
    raw = subprocess.run(
        ["git", "show", f"{PIN}:{REPORT}"], cwd=args.repo, check=True, capture_output=True
    ).stdout
    text = raw.decode("utf-8")
    models = {}
    for key, label in LABELS.items():
        rows = [line for line in text.splitlines() if line.startswith(f"| {label} |")]
        if len(rows) != 1:
            raise ValueError(f"Expected exactly one pinned table row: {label}")
        cells = [cell.strip() for cell in rows[0].strip("|").split("|")]
        values = [fps_range(cell) for cell in cells[1:]]
        native, scaled, held_out = values
        if native is None or scaled is None:
            raise ValueError("Missing fit input")
        middle = fit(sum(native) / 2.0, sum(scaled) / 2.0)
        corners = [fit(n, s) for n, s in itertools.product(native, scaled)]
        sensitivity = {name: [min(c[name] for c in corners), max(c[name] for c in corners)]
                       for name in middle}
        holdout = None
        if held_out:
            observed = sum(held_out) / 2.0
            holdout = {
                "observed_fps_range": held_out,
                "observed_midpoint_frame_ms": 1000.0 / observed,
                "prediction_minus_observed_ms": middle["predicted_scale_067_frame_ms"] - 1000.0 / observed,
                "prediction_minus_observed_fps": middle["predicted_scale_067_fps"] - observed,
                "used_for_fit": False,
            }
        models[key] = {
            "source_row": rows[0],
            "fit_fps_ranges": {"1.0": native, "0.75": scaled},
            "midpoint_fit": middle,
            "endpoint_sensitivity_not_confidence_interval": sensitivity,
            "scale_067_holdout": holdout,
        }
    receipt = {
        "schema": 1,
        "source_commit": PIN,
        "source_report": REPORT,
        "source_report_sha256": hashlib.sha256(raw).hexdigest(),
        "reproducer_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "method": "T(s)=A+B*s^2; fit 1.0 and 0.75 FPS midpoints after conversion to ms; withhold 0.67",
        "scope": "Retained PRIMIS X11 1920x1080 Stik day Club Field minimal paused debug-bridge view, RC track Off; not live tour",
        "limitations": [
            "No application or hardware was run by this reproducer.",
            "The source is a summarized experiment, without paired raw samples in these table rows.",
            "A is an empirical intercept, not measured CPU time or a validated zero-pixel limit.",
            "The 0.67 point is withheld from fitting, not an independent hardware replication.",
            "FPS-range endpoint combinations give sensitivity, not a statistical confidence interval.",
            "Pixel-area ratios are nominal s^2; actual internal drawable dimensions can round.",
            "The RC track is Off in this experiment; it does not attribute any track shader cost.",
            "No prediction qualifies live physics, another scene, renderer, device, driver or 60 FPS.",
        ],
        "models": models,
        "pixel_area_ratios": {str(s): s*s for s in [1.0, 0.85, 0.75, 0.67, 0.5]},
        "frame_budgets_ms": {str(f): 1000.0/f for f in [30, 60, 120]},
        "serial_240hz_observer_arithmetic": [
            {"microseconds_per_tick": cost, "cpu_ms_per_simulated_second": cost*240/1000,
             "cpu_ms_per_60hz_frame_at_realtime": cost*4/1000,
             "cpu_ms_per_30hz_frame_at_realtime": cost*8/1000}
            for cost in [25, 50, 100, 250, 500, 1000]
        ],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("x", encoding="utf-8") as stream:
        json.dump(receipt, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write("\n")
    for key, value in models.items():
        f = value["midpoint_fit"]
        print(f"{key}: A={f['fixed_term_ms']:.4f} ms; B={f['pixel_term_at_native_ms']:.4f} ms; "
              f"predicted 0.67={f['predicted_scale_067_fps']:.4f} FPS")
    print(f"Offline descriptive model written to {args.out}")


if __name__ == "__main__":
    main()
