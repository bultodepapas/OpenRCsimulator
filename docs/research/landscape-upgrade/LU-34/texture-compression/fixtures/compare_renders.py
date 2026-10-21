#!/usr/bin/env python3
"""Fidelity of GPU-compressed versus lossless plant renders from measure_*.gd (same views, same lighting).

Usage: compare_renders.py <lossless out dir> <compressed out dir> <out.json>
Plant pixels differ from the flat sky background (0.62, 0.72, 0.82) by more than 12 levels.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

BACKGROUND = np.array([0.62, 0.72, 0.82]) * 255


def main() -> None:
    lossless, compressed, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    result = {}
    for image in sorted(lossless.glob("*.png")):
        a = np.asarray(Image.open(image).convert("RGB"), dtype=np.float64)
        b = np.asarray(Image.open(compressed / image.name).convert("RGB"), dtype=np.float64)
        plant_a = np.abs(a - BACKGROUND).max(axis=2) > 12
        plant_b = np.abs(b - BACKGROUND).max(axis=2) > 12
        mask = plant_a | plant_b
        mse = ((a - b) ** 2)[mask].mean()
        result[image.stem] = {
            "plant_pixels": int(mask.sum()),
            "silhouette_iou": round(float((plant_a & plant_b).sum() / mask.sum()), 4),
            "psnr_db": round(10 * math.log10(255 ** 2 / mse), 2),
            "mean_abs_level_difference": round(float(np.abs(a - b)[mask].mean()), 3),
            "pixels_over_16_levels_percent": round(float((np.abs(a - b).max(axis=2)[mask] > 16).mean() * 100), 3),
        }
    out.write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
