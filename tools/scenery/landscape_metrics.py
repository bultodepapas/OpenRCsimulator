#!/usr/bin/env python3
"""Landscape improvement metrics (docs/research/landscape-improvement-2026-10-07/implementation).

Usage: landscape_metrics.py BEFORE_DIR AFTER_DIR
Each folder holds capture_views.gd output (1280x720, scenery off) with pilot_north, pilot_south, turbines_zoom,
top_140, top_140_b, top_140_c. Prints, per folder:
- grass hue/saturation (mean in linear light, re-encoded) of the pilot views' near band;
- far-band spread: Rec. 709 luma sd in pilot_south rows 360-392, x 950-1270 (report 01: target 9-14 levels);
- pilot box: mean linear Y of the bottom rows (target: within 5 % of before);
- tile repetition: luma minus a 24 px Gaussian, 2-D autocorrelation peak at lags 20-120 px (report 01: <= 0.30);
- crown seam: largest column-mean step inside a crown in turbines_zoom (report 02: <= 5 levels);
- crowns front-lit (north) vs backlit (south): mean luma of the tree pixels above the horizon.
"""
import colorsys
import sys

import numpy as np
from PIL import Image, ImageFilter

REC709 = np.array([0.2126, 0.7152, 0.0722])


def rgb(folder, name):
    return np.asarray(Image.open(f"{folder}/{name}.png").convert("RGB")).astype(float)


def linear(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def hue_sat(px):
    m = linear(px.reshape(-1, 3)).mean(0)
    s = np.where(m <= 0.0031308, m * 12.92, 1.055 * m ** (1 / 2.4) - 0.055)
    h, sat, _ = colorsys.rgb_to_hsv(*s)
    return h * 360.0, sat


def repetition(folder, name):
    y = rgb(folder, name) @ REC709
    blur = np.asarray(Image.fromarray(np.clip(y, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(24)))
    z = (y - blur)[40:680, 40:1240]
    z -= z.mean()
    f = np.fft.fft2(z, s=(2 * z.shape[0], 2 * z.shape[1]))
    ac = np.real(np.fft.ifft2(f * np.conj(f)))
    ac /= ac[0, 0]
    h, w = ac.shape
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(np.minimum(yy, h - yy), np.minimum(xx, w - xx))
    return float(np.where((r >= 20) & (r <= 120), ac, -1.0).max())


def tree_mask(img):
    return ~((img[..., 2] > img[..., 1]) & (img[..., 2] > img[..., 0]))  # sky is blue-dominant


def horizon(mask):
    return int(np.where(mask.mean(1) > 0.9)[0][0])


def seam(folder):
    img = rgb(folder, "turbines_zoom")
    mask = tree_mask(img)
    hor = horizon(mask)
    luma = img @ REC709
    counts, means = [], []
    for x in range(img.shape[1]):
        ys = np.where(mask[: hor - 2, x])[0]
        counts.append(len(ys))
        upper = luma[ys[: max(1, len(ys) // 2)], x] if len(ys) else np.zeros(1)
        means.append(float(upper.mean()))
    worst, run = 0.0, []
    for x in range(len(counts) + 1):
        if x < len(counts) and counts[x] > 0:
            run.append(x)
            continue
        if run:
            top = max(counts[i] for i in run)
            inner = [i for i in run if counts[i] >= 0.6 * top]
            if len(inner) >= 6:
                worst = max(worst, max(abs(means[i + 1] - means[i]) for i in inner[:-1] if i + 1 in inner))
        run = []
    return worst


def crowns(folder, name):
    img = rgb(folder, name)
    mask = tree_mask(img)
    hor = horizon(mask)
    return float((img[: hor - 3] @ REC709)[mask[: hor - 3]].mean())


def report(folder):
    print(f"== {folder}")
    for name, rows in (("pilot_north", (650, 720)), ("pilot_south", (480, 720))):
        h, s = hue_sat(rgb(folder, name)[rows[0]:rows[1]])
        print(f"grass {name:12} hue {h:4.0f} deg, saturation {s:.2f}")
    south = rgb(folder, "pilot_south")
    print(f"far band luma sd {(south @ REC709)[360:392, 950:1270].std():.1f} levels")
    y_s = (linear(south) @ REC709)[480:].mean()
    y_n = (linear(rgb(folder, "pilot_north")) @ REC709)[640:].mean()
    print(f"pilot box linear Y south {y_s:.4f}, north {y_n:.4f}")
    print("repetition " + " / ".join(f"{repetition(folder, n):.2f}" for n in ("top_140", "top_140_b", "top_140_c")))
    print(f"crown seam {seam(folder):.1f} levels")
    print(f"crowns front-lit {crowns(folder, 'pilot_north'):.1f}, backlit {crowns(folder, 'pilot_south'):.1f}")


if __name__ == "__main__":
    for d in sys.argv[1:]:
        report(d)
