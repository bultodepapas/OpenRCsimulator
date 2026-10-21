"""Paired roof capture comparison: changed area, high-frequency energy and zoomed crops.

Usage: python roof_compare.py <root>, where <root> holds cap-before/ and cap-after/ from
tools/landscape/capture_building_roofs.gd. Writes diff_<view>.png and pair_<view>.png
(before above after) into <root> and prints the metrics as JSON.
"""
import json
import sys

import numpy as np
from PIL import Image

VIEWS = ("club_air", "pavilion_pilot", "pavilion_roof", "shed_roof", "farm_roofs")
PAIRS = ("club_air", "pavilion_pilot", "pavilion_roof")


def laplacian(img):
    out = np.zeros_like(img)
    out[1:-1, 1:-1] = (4 * img[1:-1, 1:-1] - img[:-2, 1:-1] - img[2:, 1:-1]
                       - img[1:-1, :-2] - img[1:-1, 2:])
    return out


def main(root):
    report = {}
    for view in VIEWS:
        a = np.asarray(Image.open(f"{root}/cap-before/{view}.png").convert("L"), dtype=np.float64)
        b = np.asarray(Image.open(f"{root}/cap-after/{view}.png").convert("L"), dtype=np.float64)
        diff = np.abs(a - b)
        mask = diff > 2.0
        # Grow the changed mask so it covers each roof, not only its differing pixels.
        region = mask.copy()
        for _ in range(4):
            region[1:] |= region[:-1]
            region[:-1] |= region[1:]
            region[:, 1:] |= region[:, :-1]
            region[:, :-1] |= region[:, 1:]
        region[[0, -1], :] = False
        region[:, [0, -1]] = False
        ea = float(np.mean(laplacian(a)[region] ** 2)) if region.any() else 0.0
        eb = float(np.mean(laplacian(b)[region] ** 2)) if region.any() else 0.0
        report[view] = {"changed_px": int(mask.sum()), "changed_pct": round(100 * mask.mean(), 3),
                        "max_abs_diff": int(diff.max()), "region_px": int(region.sum()),
                        "laplacian_energy_before": round(ea, 2), "laplacian_energy_after": round(eb, 2),
                        "energy_ratio": round(eb / ea, 3) if ea else None}
        vis = np.clip(diff * 8, 0, 255).astype(np.uint8)
        Image.fromarray(vis).save(f"{root}/diff_{view}.png")
        if view in PAIRS:
            ys, xs = np.nonzero(vis > 16)
            pad = 12
            box = (max(0, int(xs.min()) - pad), max(0, int(ys.min()) - pad),
                   min(a.shape[1], int(xs.max()) + pad), min(a.shape[0], int(ys.max()) + pad))
            before = Image.open(f"{root}/cap-before/{view}.png").crop(box)
            after = Image.open(f"{root}/cap-after/{view}.png").crop(box)
            scale = max(1, min(3, 900 // before.width))
            size = (before.width * scale, before.height * scale)
            before, after = before.resize(size, Image.NEAREST), after.resize(size, Image.NEAREST)
            pair = Image.new("RGB", (size[0], size[1] * 2 + 6), (255, 0, 0))
            pair.paste(before, (0, 0))
            pair.paste(after, (0, size[1] + 6))
            pair.save(f"{root}/pair_{view}.png")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main(sys.argv[1])
