#!/usr/bin/env python3
"""Overlay the model's transparent perspective render on the user's photo and measure the outlines.

The photo has a true alpha channel: its silhouette is alpha >= 200 (the motion-blurred propeller is semi-transparent
and drops out; the remaining blade cores are excluded by boxes in picks.json 'exclude_px'). Metric as ../review.py.

    python3 research/p51/p51-02/silhouette/photo/review_photo.py --candidate <renders dir> --output <dir> [--baseline <renders dir>]
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion, distance_transform_edt, binary_opening

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
edge = lambda m: m & ~binary_erosion(m)


def metrics(real, model):
    d_real = distance_transform_edt(~edge(model))
    d_model = distance_transform_edt(~edge(real))
    a, b = d_real[edge(real)], d_model[edge(model)]
    cols = np.where(edge(real))[1]
    lo, hi = cols.min(), cols.max()
    bins = []
    for k in range(8):
        sel = (cols >= lo + (hi - lo) * k / 8) & (cols < lo + (hi - lo) * (k + 1) / 8 + (1 if k == 7 else 0))
        bins.append(float(a[sel].mean()) if sel.any() else None)
    return dict(real_to_model_mean_px=float(a.mean()), real_to_model_p90_px=float(np.percentile(a, 90)), model_to_real_mean_px=float(b.mean()),
                model_to_real_p90_px=float(np.percentile(b, 90)), iou=float((real & model).sum() / (real | model).sum()), real_to_model_bins_px_left_to_right=bins)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--label", default="")
    args = parser.parse_args()
    picks = json.loads((HERE / "picks.json").read_text())
    fit = json.loads((HERE / "camera-fit.json").read_text())
    photo = ROOT / picks["photo"]
    assert sha(photo) == picks["photo_sha256"], "photo changed"
    rgba = np.asarray(Image.open(photo).convert("RGBA"))
    real = rgba[:, :, 3] >= 200
    real = binary_opening(real, structure=np.ones((3, 3)))
    for box in picks.get("exclude_px", []):
        real[box[1]:box[3], box[0]:box[2]] = False
    args.output.mkdir(parents=True, exist_ok=True)
    view = fit["views"][0]
    result = {}
    for label, folder in (("after", args.candidate), ("before", args.baseline)):
        if folder is None:
            continue
        man = json.loads((folder / "render-manifest.json").read_text())
        rec = next(c for c in man["captures"] if c["id"] == view["id"])
        path = folder / rec["file"]
        assert sha(path) == rec["sha256"]
        model = np.asarray(Image.open(path).convert("RGBA"))[:, :, 3] >= 128
        for box in picks.get("exclude_px", []):
            model[box[1]:box[3], box[0]:box[2]] = False
        result[label] = dict(metrics(real, model), geometry_sha256=man["geometry_sha256"], model_sha256=man["model_sha256"])
        if label == "after":
            # Composite: photo over a dark board, model silhouette in translucent cyan, photo outline in red.
            board = np.full(rgba.shape, (40, 40, 40, 255), np.uint8)
            img = Image.alpha_composite(Image.fromarray(board), Image.fromarray(rgba))
            arr = np.asarray(img).astype(float)[:, :, :3]
            arr[model] = arr[model] * 0.5 + np.array([24, 220, 234]) * 0.5
            arr[edge(real)] = [230, 40, 40]
            for key, lmk in view["anchors"].items():
                x, y = lmk["picked_px"]
                arr[max(0, y - 4):y + 5, max(0, x - 4):x + 5] = [255, 220, 0]
            Image.fromarray(arr.astype(np.uint8)).save(args.output / "overlay_photo.png")
            Image.fromarray(np.asarray(img)[:, :, :3]).save(args.output / "photo_board.png")
    summary = dict(schema="openrc-photo-silhouette-review-v1", label=args.label, fit_sha256=sha(HERE / "camera-fit.json"), photo_sha256=picks["photo_sha256"],
                   camera=dict(fov_deg=view["assumed_vertical_fov_deg"], fit_rms_px=view["fit_rms_px"], check_rms_px=view["check_rms_px"], distance_m=view["distance_to_origin_m"]),
                   metric="Photo silhouette = alpha >= 200 (blurred propeller drops out) minus exclusion boxes; distance from each photo-outline pixel to the nearest render-alpha edge and the reverse; IoU; 8 bins left->right. Pixels; the photographed airplane is a real P-51D with pilot, antenna and gear doors not in the model.",
                   result=result)
    (args.output / "metrics.json").write_text(json.dumps(summary, indent=2) + "\n")
    for label, r in result.items():
        print(f"{label:6} real->model {r['real_to_model_mean_px']:5.1f} px (p90 {r['real_to_model_p90_px']:5.1f}) model->real {r['model_to_real_mean_px']:5.1f} px IoU {r['iou']:.3f}")
        print("       bins L->R:", " ".join("  -- " if x is None else f"{x:5.1f}" for x in r["real_to_model_bins_px_left_to_right"]))
    print(args.output)


if __name__ == "__main__":
    main()
