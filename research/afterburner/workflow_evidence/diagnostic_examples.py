#!/usr/bin/env python3
"""Reproduce a synthetic whole-frame versus local-region image-metric example.

This script creates two in-memory 1920x1080 linear-grayscale arrays. A 10x20
rectangle of unit-valued pixels in the reference is absent from the candidate;
all other pixels are zero in both arrays. Their local region is 30x60 pixels.
No Godot render, screenshot, visual-quality limit, or qualification is implied.
"""
import json
import math
from pathlib import Path

WIDTH = 1920
HEIGHT = 1080
ROI = {"x": 930, "y": 525, "width": 60, "height": 30}
PATCH = {"x": 950, "y": 535, "width": 20, "height": 10}
HERE = Path(__file__).resolve().parent


def measure(reference, candidate):
    """Compare normalized grayscale values with PSNR reference peak 1.0."""
    assert len(reference) == len(candidate) and len(reference) > 0
    squared_error_sum = sum((a - b) ** 2 for a, b in zip(reference, candidate))
    changed = sum(a != b for a, b in zip(reference, candidate))
    mse = squared_error_sum / len(reference)
    rmse = math.sqrt(mse)
    psnr_db = 10.0 * math.log10(1.0 / mse) if mse else math.inf
    return {
        "pixels": len(reference),
        "different_pixels": changed,
        "squared_error_sum": squared_error_sum,
        "mse": mse,
        "rmse": rmse,
        "psnr_db_peak_1": psnr_db,
    }


def extract_roi(image):
    x, y, w, h = (ROI[key] for key in ("x", "y", "width", "height"))
    return b"".join(image[row * WIDTH + x:row * WIDTH + x + w] for row in range(y, y + h))


def make_plot(result):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("Matplotlib unavailable; JSON data saved without the optional plot.")
        return

    full = result["whole_frame"]["psnr_db_peak_1"]
    roi = result["local_region"]["psnr_db_peak_1"]
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11})
    fig, ax = plt.subplots(figsize=(8.8, 5.8))
    fig.subplots_adjust(left=0.13, right=0.97, bottom=0.27, top=0.84)
    fig.patch.set_facecolor("#ffffff")
    ax.set_facecolor("#ffffff")
    bars = ax.bar([0, 1], [full, roi], width=0.54, color=["#526e88", "#d17245"], zorder=3)
    for bar, value in zip(bars, (full, roi)):
        ax.text(bar.get_x() + bar.get_width() / 2, value + 1.1, f"{value:.2f} dB",
                ha="center", va="bottom", fontsize=14, fontweight="bold", color="#202c37")
    ax.set_xticks([0, 1], ["Whole frame\n2,073,600 pixels", "Local region\n1,800 pixels"])
    ax.set_ylabel("PSNR (dB; peak = 1.0)")
    ax.set_ylim(0, 49)
    ax.set_yticks([0, 10, 20, 30, 40])
    ax.grid(axis="y", color="#e1e6ea", linewidth=0.8, zorder=0)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color("#9ba9b3")
    ax.tick_params(axis="both", length=0, pad=8)
    ax.set_title("Synthetic example: a small missing region", loc="left", fontweight="bold", fontsize=15, pad=16)
    fig.text(0.5, 0.055, "200 pixels differ by 1.0 in both comparisons; all others match.\n"
             "Normalized linear grayscale; illustrative arithmetic, not a Godot capture or quality threshold.",
             ha="center", va="bottom", fontsize=9.1, color="#44525f")
    fig.savefig(HERE / "diagnostic_examples.png", dpi=180, facecolor=fig.get_facecolor())
    plt.close(fig)


def main():
    assert PATCH["x"] >= ROI["x"] and PATCH["y"] >= ROI["y"]
    assert PATCH["x"] + PATCH["width"] <= ROI["x"] + ROI["width"]
    assert PATCH["y"] + PATCH["height"] <= ROI["y"] + ROI["height"]
    assert ROI["x"] >= 0 and ROI["y"] >= 0
    assert ROI["x"] + ROI["width"] <= WIDTH and ROI["y"] + ROI["height"] <= HEIGHT

    # Bytes 0 and 1 are used as exact normalized linear values, not 8-bit sRGB colors.
    reference = bytearray(WIDTH * HEIGHT)
    candidate = bytearray(WIDTH * HEIGHT)
    for y in range(PATCH["y"], PATCH["y"] + PATCH["height"]):
        start = y * WIDTH + PATCH["x"]
        reference[start:start + PATCH["width"]] = bytes([1]) * PATCH["width"]

    full = measure(reference, candidate)
    roi = measure(extract_roi(reference), extract_roi(candidate))
    assert full["different_pixels"] == roi["different_pixels"] == 200
    assert full["pixels"] == 2_073_600 and roi["pixels"] == 1_800
    assert full["squared_error_sum"] == roi["squared_error_sum"] == 200
    assert abs(full["mse"] - 200 / 2_073_600) < 1e-15
    assert abs(roi["mse"] - 1 / 9) < 1e-15

    result = {
        "scope": "Synthetic CPU-only arithmetic. Not a Godot screenshot, a flame simulation, a visual quality threshold, or rendering/hardware qualification.",
        "interpretation": "The same localized error is diluted by whole-frame averaging. These values alone do not classify an image as acceptable or unacceptable.",
        "sample_format": "normalized linear grayscale, with exact values 0 and 1; maximum possible value 1.0",
        "frame": {"width": WIDTH, "height": HEIGHT},
        "region_of_interest": ROI,
        "missing_reference_rectangle": PATCH,
        "reference_and_candidate": "Reference is 1 in the 10x20 rectangle and 0 elsewhere; candidate is 0 everywhere.",
        "formulae": {
            "mse": "sum((reference - candidate)^2) / number_of_pixels",
            "rmse": "sqrt(mse)",
            "psnr_db_peak_1": "10 * log10(1 / mse)",
        },
        "whole_frame": full,
        "local_region": roi,
    }
    (HERE / "diagnostic_examples.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    make_plot(result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
