#!/usr/bin/env python3
"""Compare the model's transparent renders with the drawing's filled silhouettes: overlays and contour distances.

Metric (as research/avanti-s/refinement/review.py, but sampled on the whole outline instead of hand picks): for every
pixel of the drawing's outline (boundary of the filled silhouette, measure.py) the Euclidean distance to the nearest
render-alpha edge, and the reverse (render edge -> drawing outline), per view and per longitudinal bin; plus the
intersection-over-union of the two filled masks. Pixels only; nearest edge may belong to another part.

    python3 research/p51/p51-02/silhouette/review.py --candidate <renders dir> --output <dir> [--baseline <renders dir>]
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion, distance_transform_edt

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE))
from measure import silhouette, picks  # noqa: E402

sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
COMPARE_PX = 2  # ignore pixels this close to the crop border


def edge(mask):
    return mask & ~binary_erosion(mask)


def metrics(real, model, view, scale):
    """Mean/percentile distances (px) both ways and IoU, overall and in 8 longitudinal bins (model axis)."""
    d_real = distance_transform_edt(~edge(model))  # distance from any pixel to the model edge
    d_model = distance_transform_edt(~edge(real))
    re, me = edge(real), edge(model)
    a, b = d_real[re], d_model[me]
    out = dict(real_to_model_mean_px=float(a.mean()), real_to_model_p90_px=float(np.percentile(a, 90)),
               model_to_real_mean_px=float(b.mean()), model_to_real_p90_px=float(np.percentile(b, 90)),
               iou=float((real & model).sum() / (real | model).sum()), mean_mm_model=float(a.mean() / scale * 1000))
    axis = 1 if view in ("side",) else 0  # side: along image x; top/front: rows (top) / columns (front)
    if view == "front":
        axis = 1
    coords = np.where(re)[axis]
    lo, hi = coords.min(), coords.max()
    bins = []
    for k in range(8):
        sel = (coords >= lo + (hi - lo) * k / 8) & (coords < lo + (hi - lo) * (k + 1) / 8 + (1 if k == 7 else 0))
        bins.append(float(a[sel].mean()) if sel.any() else None)
    out["real_to_model_bins_px"] = bins
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--label", default="")
    args = parser.parse_args()
    fit = json.loads((HERE / "camera-fit.json").read_text())
    drawing = ROOT / picks["drawing"]
    assert sha(drawing) == fit["drawing_sha256"], "drawing changed"
    im = np.asarray(Image.open(drawing)).astype(np.uint8)
    dark = im < 140
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((args.candidate / "render-manifest.json").read_text())
    base_manifest = json.loads((args.baseline / "render-manifest.json").read_text()) if args.baseline else None
    rows = {}
    for view in fit["views"]:
        key = view["id"]
        v = picks["views"][key]
        real = silhouette(dark, v["box"], v["exclude"])
        if key == "front":  # left half only (the right wing's outline leaks in the drawing)
            real[:, int(view["anchors"]["centre"]["picked_px"][0]):] = False
        crop = im[v["box"][1]:v["box"][3], v["box"][0]:v["box"][2]]
        result = {}
        for label, folder, man in (("after", args.candidate, manifest), ("before", args.baseline, base_manifest)):
            if folder is None:
                continue
            path = folder / f"{key}.png"
            rec = next(c for c in man["captures"] if c["id"] == key)
            assert sha(path) == rec["sha256"], "render changed since its manifest"
            rgba = np.asarray(Image.open(path).convert("RGBA"))
            assert rgba.shape[:2] == real.shape, (rgba.shape, real.shape)
            model = rgba[:, :, 3] >= 128
            if key == "front":
                model[:, int(view["anchors"]["centre"]["picked_px"][0]):] = False
            result[label] = metrics(real, model, key, view["display_scale_px_per_model_m"])
            if label == "after":
                # Composite for review: drawing in grey, model silhouette in translucent cyan, drawing outline in red.
                rgb = np.stack([crop] * 3, -1).astype(float)
                rgb[model] = rgb[model] * 0.45 + np.array([24, 220, 234]) * 0.55
                rgb[edge(real)] = [230, 40, 40]
                Image.fromarray(rgb.astype(np.uint8)).save(args.output / f"overlay_{key}.png")
                Image.fromarray(crop).save(args.output / f"drawing_{key}.png")
        rows[key] = result
    summary = dict(schema="openrc-silhouette-review-v1", label=args.label, fit_sha256=sha(HERE / "camera-fit.json"),
                   candidate=dict(geometry_sha256=manifest["geometry_sha256"], model_sha256=manifest["model_sha256"], visual_revision=manifest.get("visual_revision")),
                   baseline=dict(geometry_sha256=base_manifest["geometry_sha256"], model_sha256=base_manifest["model_sha256"]) if base_manifest else None,
                   metric="Euclidean distance (px) from each drawing-outline pixel to the nearest render-alpha>=128 edge and the reverse; IoU of the filled masks; 8 longitudinal bins nose->tail (side, top) or tip->centre (front). Propeller, wheels, drop tanks and dimension lines excluded by the drawing silhouette; not metric accuracy per component.",
                   views=rows)
    (args.output / "metrics.json").write_text(json.dumps(summary, indent=2) + "\n")
    for key, r in rows.items():
        a = r["after"]
        line = f"{key:6} real->model {a['real_to_model_mean_px']:5.1f} px (p90 {a['real_to_model_p90_px']:5.1f}) model->real {a['model_to_real_mean_px']:5.1f} px  IoU {a['iou']:.3f}  ≈{a['mean_mm_model']:.0f} mm on the model"
        if "before" in r:
            b = r["before"]
            line += f"   | before {b['real_to_model_mean_px']:5.1f} px, IoU {b['iou']:.3f}"
        print(line)
        print("        bins:", " ".join("  -- " if x is None else f"{x:5.1f}" for x in a["real_to_model_bins_px"]))
    print(args.output)


if __name__ == "__main__":
    main()
