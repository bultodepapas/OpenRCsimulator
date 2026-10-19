#!/usr/bin/env python3
"""FW-MOON-05 overlay check: the game's rendered moon against NASA SVS 5587 "Moon Phase and Libration, 2026".

Both images have celestial north up: tools/world/moon_capture.gd --cases=svs points the camera at the moon with the
celestial pole up; SVS frames (frames/730x730_1x1_30p/moon.NNNN.jpg, NNNN = hour of 2026 + 1) are geocentric with
north up. The game's disc is resampled onto the SVS frame (its radius is known from the manifest: radius_deg over the
vertical field of view; the SVS disc is measured), then:
  * lit_iou: overlap of the sunlit areas (terminator position and phase), threshold 15 % of each disc's 99th percentile;
  * detail_r: Pearson correlation of the albedo detail (luminance minus a Gaussian blur of R/12) inside both lit areas
    shrunk away from the terminator (a Gaussian of R/24 above 0.95): maria and craters in the right places;
  * best_rotation_deg: the in-plane rotation of the game's image that maximises detail_r (orientation error).
The game is topocentric, SVS geocentric: diurnal libration (< 1°) and parallax shift features by < 2 % of the radius.
Writes <out>/<case>.png (game | SVS | difference) and <out>/summary.json.
  "$(app/tests/visual-env.sh)" research/field-world/fw-moon-05/overlay_svs.py <capture dir> <svs frames dir> <out dir>
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

LIT_FRACTION = 0.15
ROTATIONS = np.arange(-10.0, 10.01, 0.5)


def linear_luminance(path):
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float64) / 255.0
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    return lin @ np.array([0.2126, 0.7152, 0.0722])


def blur(img, sigma):
    radius = int(3 * sigma) + 1
    x = np.arange(-radius, radius + 1)
    k = np.exp(-0.5 * (x / sigma) ** 2)
    k /= k.sum()
    pad = np.pad(img, radius, mode="edge")
    tmp = np.apply_along_axis(lambda r: np.convolve(r, k, mode="valid"), 1, pad)
    return np.apply_along_axis(lambda c: np.convolve(c, k, mode="valid"), 0, tmp)


def bilinear(img, x, y):
    h, w = img.shape
    x = np.clip(x, 0, w - 1.001)
    y = np.clip(y, 0, h - 1.001)
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = x - x0
    fy = y - y0
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def svs_disc(gray8):
    """Centre and radius of the SVS disc (earthlit side included) from its bounding box."""
    ys, xs = np.nonzero(gray8 > 4)
    cx = (xs.min() + xs.max()) / 2.0
    cy = (ys.min() + ys.max()) / 2.0
    return cx, cy, ((xs.max() - xs.min()) + (ys.max() - ys.min())) / 4.0


def resample(game, centre, r_game, shape, cx, cy, r_svs, theta_deg):
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    u = (xx - cx) / r_svs
    v = (yy - cy) / r_svs
    t = math.radians(theta_deg)
    ur = u * math.cos(t) - v * math.sin(t)
    vr = u * math.sin(t) + v * math.cos(t)
    return bilinear(game, centre[0] + ur * r_game, centre[1] + vr * r_game), u * u + v * v


def main(capture_dir, frames_dir, out_dir):
    capture_dir, frames_dir, out_dir = Path(capture_dir), Path(frames_dir), Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((capture_dir / "manifest.json").read_text())
    rows = []
    for case in manifest["cases"]:
        if not case.get("north_up") or case["view"] != "close":
            continue
        game = linear_luminance(capture_dir / case["file"])
        h, w = game.shape
        r_game = float(case["moon"]["radius_deg"]) / float(case["fov_deg"]) * h
        frame = frames_dir / ("moon.%04d.jpg" % int(case["svs_frame"]))
        gray8 = np.asarray(Image.open(frame).convert("L"))
        svs = linear_luminance(frame)
        cx, cy, r_svs = svs_disc(gray8)
        sigma = r_svs / 12.0
        svs_hp = svs - blur(svs, sigma)
        results = []
        for theta in ROTATIONS:
            g, rho2 = resample(game, (w / 2.0, h / 2.0), r_game, svs.shape, cx, cy, r_svs, theta)
            disc = rho2 < 0.92 ** 2
            g_lit = g > LIT_FRACTION * np.percentile(g[disc], 99)
            s_lit = svs > LIT_FRACTION * np.percentile(svs[disc], 99)
            iou = float((g_lit & s_lit & disc).sum() / max((g_lit | s_lit)[disc].sum(), 1))
            core = disc & (blur((g_lit & s_lit).astype(float), sigma / 2.0) > 0.95)  # away from the terminator
            g_hp = g - blur(g, sigma)
            r = float(np.corrcoef(g_hp[core], svs_hp[core])[0, 1]) if core.sum() > 200 else float("nan")
            results.append((theta, iou, r, g))
        at_zero = [x for x in results if x[0] == 0.0][0]
        best = max(results, key=lambda x: -1 if math.isnan(x[2]) else x[2])
        row = {"case": case["case_id"], "svs_frame": case["svs_frame"], "illuminated": case["moon"]["illuminated"],
               "libration_lon_deg": case["moon"]["libration_lon_deg"], "libration_lat_deg": case["moon"]["libration_lat_deg"],
               "game_radius_px": r_game, "svs_radius_px": r_svs, "lit_iou": at_zero[1], "detail_r": at_zero[2],
               "best_rotation_deg": float(best[0]), "best_detail_r": best[2]}
        rows.append(row)
        print("%-20s frame %4d  lit IoU %.3f  detail r %.3f  best rotation %+.1f° (r %.3f)" % (
            row["case"], row["svs_frame"], row["lit_iou"], row["detail_r"], row["best_rotation_deg"], row["best_detail_r"]))
        g0 = at_zero[3]
        disc = (((np.mgrid[0:svs.shape[0], 0:svs.shape[1]][1] - cx) / r_svs) ** 2
                + ((np.mgrid[0:svs.shape[0], 0:svs.shape[1]][0] - cy) / r_svs) ** 2) < 1.0
        def to8(img):
            img = img / max(np.percentile(img[disc], 99.5), 1e-9)
            img = np.clip(img, 0, 1) ** (1 / 2.2)
            return (img * 255).astype(np.uint8)
        diff = np.clip(0.5 + (g0 / max(np.percentile(g0[disc], 99.5), 1e-9)
                              - svs / max(np.percentile(svs[disc], 99.5), 1e-9)) * 0.5, 0, 1)
        sheet = np.concatenate([to8(g0), to8(svs), (diff * 255).astype(np.uint8)], axis=1)
        Image.fromarray(sheet).resize((sheet.shape[1] // 2, sheet.shape[0] // 2), Image.LANCZOS).save(out_dir / (case["case_id"] + ".png"))
    (out_dir / "summary.json").write_text(json.dumps({"format": "openrc-moon-overlay v1", "lit_fraction": LIT_FRACTION,
                                                      "cases": rows}, indent=1) + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
