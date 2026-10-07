"""SC-01(d) analysis of probe.gd output. Run with the pinned visual venv (numpy, Pillow):
    .tools/visual-venv/bin/python -I research/scenery/sc01/analyze.py <out-dir> > summary.json
Reads <out-dir>/<case>/result.json and PNGs; prints one JSON summary. Thresholds are analysis choices, stated inline.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def load(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB")).astype(np.int32)


def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def merge(out: Path) -> dict:
    r = json.loads((out / "result.json").read_text())
    base = load(out / "merge-none.png")
    diffs = {}
    for name in ("importer", "surfacetool", "shared"):
        d = np.abs(base - load(out / f"merge-{name}.png")).max(axis=2)
        diffs[name] = {"pixels_gt_24_levels": int((d > 24).sum()), "pixels_gt_3_levels": int((d > 3).sum())}
    return {"variants": r["variants"], "pixel_diff_vs_separate": diffs, "vertex_colour_trap": r["vertex_colour_trap"],
            "cars": r["cars"], "mirrored_cars": r["mirrored_cars"], "triangles": r["triangles"]}


def depth(out: Path) -> dict:
    r = json.loads((out / "result.json").read_text())
    planes = []
    for row in r.get("planes", []):
        share = {}
        for gap, tag in row["shots"].items():
            img = load(out / f"{tag}.png")
            white = img.min(axis=2) > 128
            red = (img[..., 0] > 128) & (img[..., 1] < 100)
            share[gap] = round(float(red.sum()) / max(1, int((white | red).sum())), 4)
        planes.append({"distance_m": row["distance_m"], "near_m": row["near_m"],
                       "predicted_step_m": round(row["depth_step_at_d_m"], 3), "red_share_by_gap_m": share})
    rows = []
    for row in r["rows"]:
        wrong, overlaps, blade_px = [], [], []
        for j, tag in enumerate(row["both"]):
            tower = load(out / f"{row['tower'][j]}.png")
            blades = load(out / f"{row['blades'][j]}.png")
            tower_m = (tower[..., 0] > 128) & (tower[..., 1] < 100)  # red tower
            blade_m = blades.min(axis=2) > 128  # white blades
            overlap = tower_m & blade_m
            img = load(out / f"{tag}.png")
            red = (img[..., 0] > 128) & (img[..., 1] < 100)
            wrong.append(int((red & overlap).sum()))
            overlaps.append(int(overlap.sum()))
            blade_px.append(int(blade_m.sum()))
        rows.append({
            "distance_m": row["distance_m"], "near_m": row["near_m"], "fov_deg": row["fov_deg"], "separation_m": row["separation_m"],
            "depth_step_m": round(row["depth_step_at_d_m"], 3), "blade_pixels": blade_px[0],
            "overlap_pixels_per_frame": overlaps, "wrong_pixels_per_frame": wrong,
            "wrong_share": round(sum(wrong) / sum(overlaps), 3) if sum(overlaps) else None,
        })
    return {"planes": planes, "turbine": rows}


def polygon_mask(shape, corners) -> np.ndarray:
    """Pixels inside a convex quad given in screen pixels (inner window of the shadow quad)."""
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    pts = np.array(corners, dtype=float)
    inside = np.ones((h, w), dtype=bool)
    sign = None
    for i in range(4):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % 4]
        cross = (x1 - x0) * (yy + 0.5 - y0) - (y1 - y0) * (xx + 0.5 - x0)
        s = np.sign(cross.sum()) if sign is None else sign
        sign = s
        inside &= (cross * s) >= 0
    return inside


def ground(out: Path) -> dict:
    r = json.loads((out / "result.json").read_text())
    rows = []
    for row in r["rows"]:
        ref = load(out / f"{row['shots']['ref']}.png")
        lum_ref = ref.mean(axis=2)
        mask = polygon_mask(lum_ref.shape, row["window_px"])
        entry = {"height_m": row["height_m"], "distance_m": row["distance_m"], "window_pixels": int(mask.sum()),
                 "lift_dh_m": round(row["lift_dh_m"], 4), "lift_d2_m": round(row["lift_d2_m"], 4), "darkened_share": {}}
        for lift, tag in row["shots"].items():
            if lift == "ref":
                continue
            lum = load(out / f"{tag}.png").mean(axis=2)
            # Darkened = at least 15 % darker than the same pixel without the quad (alpha 0.5 black gives about 50 %).
            dark = (lum < 0.85 * lum_ref) & mask
            entry["darkened_share"][lift] = round(float(dark.sum()) / mask.sum(), 4) if mask.sum() else None
        rows.append(entry)
    fog = []
    for row in r.get("fog", []):
        mask = polygon_mask(load(out / f"{row['ref']}.png").shape[:2], row["window_px"])
        lin = {v: srgb_to_linear(load(out / f"{row[v]}.png")).mean(axis=2)[mask].mean() for v in ("ref", "nofog", "mix", "mul")}
        t = row["transmittance"]
        expected = lin["ref"] - 0.5 * t * lin["nofog"]  # L_g − 0.5·T·G: only the surface term is halved
        fog.append({"distance_m": row["distance_m"], "transmittance": round(t, 4), "window_pixels": int(mask.sum()),
                    "linear": {k: round(float(v), 4) for k, v in lin.items()}, "expected": round(float(expected), 4),
                    "error_mix": round(float(lin["mix"] - expected), 4), "error_mul": round(float(lin["mul"] - expected), 4)})
    return {"rows": rows, "fog": fog}


def style(out: Path) -> dict:
    r = json.loads((out / "result.json").read_text())
    shots = r["shots"]
    views = sorted({k.rsplit("-", 1)[0] for k in shots})
    table = {}
    for v in views:
        e = shots[f"{v}-empty"]
        table[v] = {mode: {"draw_calls_delta": shots[f"{v}-{mode}"]["draw_calls"] - e["draw_calls"],
                           "primitives_delta": shots[f"{v}-{mode}"]["primitives"] - e["primitives"]}
                    for mode in ("separate", "merged")}
        d = np.abs(load(out / f"style-{v}-separate.png") - load(out / f"style-{v}-merged.png")).max(axis=2)
        table[v]["merged_vs_separate_pixels_gt_24"] = int((d > 24).sum())
    return {"library": r["library"], "counts": r["counts"], "merge_build_ms": r.get("merge_build_ms"),
            "merged_zone_surfaces": r.get("merged_zone_surfaces"), "views": table}


def main() -> None:
    out = Path(sys.argv[1])
    summary = {}
    for case, fn in (("merge", merge), ("depth", depth), ("ground", ground), ("style", style)):
        if (out / case / "result.json").exists():
            summary[case] = fn(out / case)
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
