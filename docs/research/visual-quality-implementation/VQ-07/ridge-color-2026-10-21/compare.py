"""Retain selected unmodified PNGs and audit the full ridge comparison campaign.

Usage: python compare.py D:/OpenRCsimulator-scratch/ridge-20261021
Uses Pillow/NumPy, as the repository's other image reducers do.
"""
import hashlib
import json
from pathlib import Path
import shutil
import sys

import numpy as np
from PIL import Image

source = Path(sys.argv[1]).resolve()
output = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pixels(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)


def difference(before, after):
    a, b = pixels(before), pixels(after)
    if a.shape != b.shape:
        raise ValueError(f"dimensions differ: {before}, {after}")
    delta = np.abs(a - b)
    rows, cols = np.nonzero(np.any(delta != 0, axis=2))
    return dict(before_sha256=digest(before), after_sha256=digest(after),
                changed_pixels=len(rows), total_pixels=a.shape[0] * a.shape[1],
                max_channel_delta=float(delta.max()), mean_absolute_channel_delta=float(delta.mean()),
                bbox_xyxy=None if not len(rows) else [int(cols.min()), int(rows.min()), int(cols.max()) + 1, int(rows.max()) + 1])


report = {"scope": "fixed native captures; pixel and regional contrast diagnostics, not quality/FPS scores",
          "numpy": np.__version__, "pillow": Image.__version__, "static": {}, "world": {}, "cost": {}}
for profile in ("standard", "high"):
    report["static"][profile] = {}
    for path in sorted((source / f"{profile}-baseline").glob("*.png")):
        report["static"][profile][path.stem] = difference(path, source / f"{profile}-candidate" / path.name)

# A fixed patch entirely within the middle ridge; no sky, tree silhouettes or buildings.
roi = [700, 245, 900, 295]
report["mountain_patch"] = {"image": "lake.png", "xyxy": roi, "samples": {}}
for variant in ("standard-baseline", "standard-candidate", "high-baseline", "high-candidate"):
    a = pixels(source / variant / "lake.png")[roi[1]:roi[3], roi[0]:roi[2]]
    y = a @ np.array([0.2126, 0.7152, 0.0722])
    report["mountain_patch"]["samples"][variant] = dict(mean_rgb=a.mean((0, 1)).tolist(),
        std_luminance=float(y.std()), mean_absolute_horizontal_luminance_gradient=float(np.abs(np.diff(y, axis=1)).mean()))

for path in sorted((source / "world-cases").glob("*-before-*.png")):
    report["world"][path.name] = difference(path, path.with_name(path.name.replace("-before-", "-after-")))
report["shadow_receiver_ablation"] = difference(source / "high-candidate/lake.png", source / "high-no-receiver/lake.png")
for variant in ("before", "after"):
    data = json.loads((source / f"cost-{variant}" / "report.json").read_text())
    case = data["cases"][0]
    values = case["profile"]["samples_wall_cpu_gpu_ms"]
    report["cost"][variant] = {"samples": len(values), "counters": case["counters"],
        "percentiles_ms": {key: np.percentile([v[key] for v in values], [50, 95, 99]).tolist()
                           for key in ("wall_ms", "cpu_ms", "gpu_ms")}}

for variant in ("standard-baseline", "standard-candidate", "high-baseline", "high-candidate",
                "world-cases", "cost-before", "cost-after", "high-no-receiver"):
    dest = output / variant
    dest.mkdir(exist_ok=True)
    shutil.copy2(source / variant / "report.json", dest / "report.json")
    for path in (source / variant).glob("*.png"):
        if variant == "world-cases" or path.stem in ("lake", "pilot"):
            shutil.copy2(path, dest / path.name)
shutil.copytree(source / "checks", output / "checks", dirs_exist_ok=True)
shutil.copy2(source / "ridge-before.gdshader", output / "ridge-before.gdshader")
shader = source / "isolated/app/render/landscape_upgrade/ridge_haze.gdshader"
report["identity"] = {"base_commit": (source / "base-head.txt").read_text().strip(),
                      "baseline_shader_sha256": digest(source / "ridge-before.gdshader"),
                      "candidate_shader_sha256": digest(shader),
                      "capture_sha256": digest(source / "isolated/tools/graphics/capture.gd"),
                      "cache": "fresh import in isolated archive; no shared asset/import-cache repair"}
(output / "comparison.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"cost": report["cost"], "patch": report["mountain_patch"]}, indent=2))
