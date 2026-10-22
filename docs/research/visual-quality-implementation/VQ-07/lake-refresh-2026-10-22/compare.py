"""Reduce retained native lake PNGs; requires the existing Pillow/NumPy tools."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent


def difference(first, second):
    a = np.asarray(Image.open(ROOT / first).convert("RGB")).astype(np.int16)
    b = np.asarray(Image.open(ROOT / second).convert("RGB")).astype(np.int16)
    delta = np.abs(a - b)
    return {
        "changed_pixels": int(np.any(delta, axis=2).sum()),
        "maximum_channel_delta": int(delta.max()),
        "mean_absolute_channel_delta": float(delta.mean()),
        "pixels_above_two_levels": int(np.any(delta > 2, axis=2).sum()),
    }


results = {}
for profile in ("high", "standard"):
    for stage in ("before", "after"):
        name = f"{profile}-{stage}"
        results[name] = difference(f"{name}/edited.png", f"{name}/forced.png")
print(json.dumps(results, indent=2))
