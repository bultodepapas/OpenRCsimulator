"""Visual checks for captures (LANDSCAPE-PLAN L0c). Run with the pinned environment: $(app/tests/visual-env.sh).

compare <reference dir> <test dir> [--max-bad 50] [--flip 0.1]
    Two tiers per capture (matched by name, each PNG with its L0b manifest .json):
      1. same renderer (adapter + API string): the SHA-256 must match exactly;
      2. other renderer: count pixels whose FLIP error exceeds --flip; more than --max-bad fails.
    Byte equality only holds for one Mesa build; mean metrics miss a 15 px airplane, so tier 2 counts bad pixels.

readability <captures dir> [--out readability.json]
    For each capture X with a sibling X-noplane (same view without the airplane): the airplane's pixels are where the
    two differ; then Weber contrast of the airplane against its surroundings, the share of its pixels with
    |local contrast| < 0.1 (nearly invisible), and the mean CIE76 colour difference ΔE.
"""
import argparse
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def manifest(png):
    p = os.path.splitext(png)[0] + ".json"
    return json.load(open(p)) if os.path.exists(p) else {}


def compare(ref_dir, test_dir, max_bad, flip_threshold):
    import flip_evaluator

    problems = []
    names = sorted(f for f in os.listdir(ref_dir) if f.endswith(".png"))
    if not names:
        sys.exit(f"FAIL no reference captures in {ref_dir}")
    for name in names:
        ref, test = os.path.join(ref_dir, name), os.path.join(test_dir, name)
        if not os.path.exists(test):
            problems.append(f"{name}: missing")
            continue
        mr, mt = manifest(ref), manifest(test)
        same_renderer = mr and mt and (mr.get("adapter"), mr.get("api")) == (mt.get("adapter"), mt.get("api"))
        sha_t = hashlib.sha256(open(test, "rb").read()).hexdigest()
        sha_r = hashlib.sha256(open(ref, "rb").read()).hexdigest()
        if same_renderer:
            ok = sha_t == sha_r
            print(f"{'ok  ' if ok else 'FAIL'} {name}: tier 1 (same renderer), sha256 {'equal' if ok else 'differs'}")
            if not ok:
                problems.append(f"{name}: different bytes on the same renderer")
            continue
        err = flip_evaluator.evaluate(load(ref), load(test), "LDR", applyMagma=False)[0]
        bad = int((np.asarray(err) > flip_threshold).sum())
        ok = bad <= max_bad
        print(f"{'ok  ' if ok else 'FAIL'} {name}: tier 2 (other renderer), {bad} pixels with FLIP > {flip_threshold} (limit {max_bad})")
        if not ok:
            problems.append(f"{name}: {bad} bad pixels")
    return problems


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def luminance(rgb):
    lin = srgb_to_linear(rgb)
    return 0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2]


def lab(rgb):
    lin = srgb_to_linear(rgb)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]], dtype=np.float32)
    xyz = lin @ m.T / np.array([0.95047, 1.0, 1.08883], dtype=np.float32)
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116.0 * f[..., 1] - 16.0, 500.0 * (f[..., 0] - f[..., 1]), 200.0 * (f[..., 1] - f[..., 2])], axis=-1)


def dilate(mask, r):
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
    return out


# Pixels that differ by more than this (0–1 scale) between a view with and without an object are that object.
DIFFERENCE_LEVELS = 2.5 / 255.0
# The airplane's surroundings: a ring this many pixels wide around its mask.
RING_PX = 6


def difference_mask(a, b, threshold=DIFFERENCE_LEVELS):
    return np.abs(a - b).max(axis=-1) > threshold


def background_composition(ring, tree_mask=None, horizon_row=None):
    """What the ring pixels are (L6c): trees from a tree mask (view with trees minus view without), sky above the
    horizon row and ground below it; "other" when a part cannot be told. Fractions of the ring."""
    n = int(ring.sum())
    if n == 0:
        return {"pixels": 0, "trees": 0.0, "sky": 0.0, "ground": 0.0, "other": 1.0}
    rows = np.nonzero(ring)[0]
    trees = tree_mask[ring] if tree_mask is not None else np.zeros(n, dtype=bool)
    if horizon_row is None:
        sky = np.zeros(n, dtype=bool)
        ground = np.zeros(n, dtype=bool)
    else:
        sky = ~trees & (rows < float(horizon_row))
        ground = ~trees & ~sky
    other = ~trees & ~sky & ~ground
    return {"pixels": n, "trees": round(float(trees.mean()), 4), "sky": round(float(sky.mean()), 4),
            "ground": round(float(ground.mean()), 4), "other": round(float(other.mean()), 4)}


def measure_pair(a, b, tree_mask=None, horizon_row=None):
    """Readability of the airplane in `a` against the same view `b` without it (L0c). With a tree mask of `b`
    and/or the horizon row, also reports what surrounds the airplane (L6c)."""
    mask = difference_mask(a, b)
    if mask.sum() == 0:
        return {"pixels": 0}
    ring = dilate(mask, RING_PX) & ~mask
    la, lb = luminance(a), luminance(b)
    l_plane, l_bg = float(la[mask].mean()), float(lb[ring].mean())
    local = (la[mask] - lb[mask]) / np.maximum(lb[mask], 1e-6)
    de = np.linalg.norm(lab(a)[mask] - lab(b)[mask], axis=-1)
    rows, cols = np.nonzero(mask)
    result = {
        "pixels": int(mask.sum()),
        "weber_contrast": round((l_plane - l_bg) / max(l_bg, 1e-6), 4),
        "share_low_contrast": round(float((np.abs(local) < 0.1).mean()), 4),
        "delta_e": round(float(de.mean()), 2),
        # Investigation 09's "sky sat": mean (max − min) of RGB (0–255) behind the airplane; low = greyed sky.
        "background_saturation": round(float(((b[ring].max(axis=-1) - b[ring].min(axis=-1)) * 255.0).mean()), 1),
    }
    if tree_mask is not None or horizon_row is not None:
        result["delta_e_p10"] = round(float(np.percentile(de, 10)), 2)
        result["bbox_px"] = {"width": int(cols.max() - cols.min() + 1), "height": int(rows.max() - rows.min() + 1),
                             "centre": [round(float(cols.mean()), 1), round(float(rows.mean()), 1)]}
        result["background"] = background_composition(ring, tree_mask, horizon_row)
    return result


def readability(cap_dir, out_path):
    results = {}
    for name in sorted(os.listdir(cap_dir)):
        if not name.endswith("-noplane.png"):
            continue
        with_name = name.replace("-noplane.png", ".png")
        a, b = load(os.path.join(cap_dir, with_name)), load(os.path.join(cap_dir, name))
        results[with_name] = measure_pair(a, b)
        if results[with_name]["pixels"] == 0:
            continue
        r = results[with_name]
        print(f"{with_name}: {r['pixels']} airplane pixels, Weber contrast {r['weber_contrast']:+.3f}, "
              f"{100 * r['share_low_contrast']:.1f} % with |contrast| < 0.1, mean ΔE {r['delta_e']:.1f}, "
              f"background saturation {r['background_saturation']:.1f}")
    json.dump(results, open(out_path, "w"), indent=2, sort_keys=True)
    return results


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("compare")
    c.add_argument("reference")
    c.add_argument("test")
    c.add_argument("--max-bad", type=int, default=50)
    c.add_argument("--flip", type=float, default=0.1)
    r = sub.add_parser("readability")
    r.add_argument("captures")
    r.add_argument("--out", default=None)
    r.add_argument("--require", action="append", default=[],
                   help="VIEW:max_weber:max_low_share:min_delta_e:min_saturation, e.g. "
                        "capture-land-low3m.png:-0.40:0.15:30:25 (L1b)")
    args = ap.parse_args()
    if args.cmd == "compare":
        problems = compare(args.reference, args.test, args.max_bad, args.flip)
        if problems:
            print("FAIL " + "; ".join(problems))
            sys.exit(1)
        print("captures match")
    else:
        res = readability(args.captures, args.out or os.path.join(args.captures, "readability.json"))
        if not res:
            sys.exit("FAIL no capture pairs (X.png + X-noplane.png) found")
        problems = []
        for req in args.require:
            view, w_max, low_max, de_min, sat_min = req.split(":")
            r = res.get(view)
            if not r or r.get("pixels", 0) == 0:
                problems.append(f"{view}: no airplane found")
                continue
            if r["weber_contrast"] > float(w_max):
                problems.append(f"{view}: contrast {r['weber_contrast']:+.3f} > {w_max}")
            if r["share_low_contrast"] > float(low_max):
                problems.append(f"{view}: {100 * r['share_low_contrast']:.1f} % nearly invisible > {100 * float(low_max):.0f} %")
            if r["delta_e"] < float(de_min):
                problems.append(f"{view}: ΔE {r['delta_e']:.1f} < {de_min}")
            if r["background_saturation"] < float(sat_min):
                problems.append(f"{view}: background saturation {r['background_saturation']:.1f} < {sat_min}")
        if problems:
            print("FAIL readability: " + "; ".join(problems))
            sys.exit(1)
        if args.require:
            print("readability thresholds met: " + ", ".join(args.require))


if __name__ == "__main__":
    main()
