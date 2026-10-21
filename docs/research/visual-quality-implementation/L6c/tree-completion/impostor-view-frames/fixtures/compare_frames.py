#!/usr/bin/env python3
"""Silhouette IoU between source views (source_views.gd) and each frame of a baked 4-view atlas.

Usage: compare_frames.py <views dir> <out json> <asset_id>=<atlas png> ...
Bounding-box-normalized 64 x 64 alpha masks; opposite views are mirror silhouettes, so
only the correctly ordered frame matches its azimuth.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def normalized(mask: np.ndarray) -> np.ndarray:
    rows, columns = np.nonzero(mask)
    crop = mask[rows.min():rows.max() + 1, columns.min():columns.max() + 1]
    return np.asarray(Image.fromarray((crop * 255).astype(np.uint8)).resize((64, 64))) > 127


def main() -> None:
    views, out = Path(sys.argv[1]), Path(sys.argv[2])
    result = {}
    for item in sys.argv[3:]:
        asset_id, atlas_path = item.split("=", 1)
        atlas = np.asarray(Image.open(atlas_path).convert("RGBA"))
        width = atlas.shape[1] // 4
        frames = [normalized(atlas[:, k * width:(k + 1) * width, 3] > 80) for k in range(4)]
        rows = {}
        for azimuth in (0, 90, 180, 270):
            source = normalized(np.asarray(Image.open(views / f"{asset_id}_az{azimuth}.png").convert("RGBA"))[..., 3] > 80)
            ious = [round(float((source & f).sum() / (source | f).sum()), 4) for f in frames]
            rows[str(azimuth)] = {"iou_frames_0_3": ious, "best_frame": int(np.argmax(ious))}
        result[asset_id] = rows
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
