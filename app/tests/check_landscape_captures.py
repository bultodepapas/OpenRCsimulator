"""Landscape capture checks (LANDSCAPE-PLAN L1+), run by capture.sh on the PNGs it just made.

L1a sky: in every landscape review view the sky is darker at the top of the frame than just above the horizon (the
gradient says which way is up); no 8-bit banding (the longest run of identical pixels down a sky column ≤ 3 px);
in the sun view the sun disc sits where the light direction projects (≤ 2 px).
Usage: python3 check_landscape_captures.py <captures dir>
"""
import os
import re
import sys

from PIL import Image

d = sys.argv[1]
problems = []
counters = {}
for line in open(os.path.join(d, "landscape-counters.txt")):
    name, rest = line.split(" ", 1)
    counters[name] = dict(kv.split("=") for kv in rest.split())


def lum(p):
    return 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]


def band(px, x0, x1, y0, y1):
    vals = [lum(px[x, y]) for y in range(y0, y1) for x in range(x0, x1)]
    return sum(vals) / len(vals)


views = sorted(f for f in os.listdir(d) if f.startswith("capture-land-") and f.endswith(".png"))
if len(views) < 11:
    problems.append(f"expected 11 landscape views, found {len(views)}")
for f in views:
    im = Image.open(os.path.join(d, f)).convert("RGB")
    px = im.load()
    w, h = im.size
    x0, x1 = w - 280, w - 10  # right edge: away from the panel, the HUD and the sun
    # Horizon = first row (from the top) where this strip turns green (ground: g clearly above b).
    horizon = next((y for y in range(h) if all(px[x, y][1] > px[x, y][2] + 10 for x in range(x0, x1, 30))), h)
    if horizon < 40:
        continue  # no sky in this strip
    top = band(px, x0, x1, 2, 12)
    low = band(px, x0, x1, max(12, horizon - 14), horizon - 4)
    if not top < low:
        problems.append(f"{f}: sky not darker at the top (top {top:.1f}, near horizon {low:.1f})")
    # Banding: longest run of identical pixels down one sky column (debanding keeps it short).
    run = best = 1
    for y in range(3, horizon - 4):
        run = run + 1 if px[x1 - 5, y] == px[x1 - 5, y - 1] else 1
        best = max(best, run)
    if best > 3:
        problems.append(f"{f}: banding, {best} identical pixels in a row down the sky")
    print(f"{f}: sky top {top:.1f} < near horizon {low:.1f} (horizon row {horizon}), longest equal run {best} px")

sun = counters.get("capture-land-sun", {}).get("sun_px")
if sun is None or sun == "behind":
    problems.append("sun view: no projected sun position recorded")
else:
    ex, ey = map(float, sun.split(","))
    im = Image.open(os.path.join(d, "capture-land-sun.png")).convert("RGB")
    px = im.load()
    pts = [(x, y) for y in range(max(0, int(ey) - 40), min(im.size[1], int(ey) + 40))
           for x in range(max(0, int(ex) - 40), min(im.size[0], int(ex) + 40)) if lum(px[x, y]) > 245]
    if not pts:
        problems.append("sun view: no sun disc found near its projected position")
    else:
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        err = ((cx - ex) ** 2 + (cy - ey) ** 2) ** 0.5
        print(f"sun disc centroid {cx:.1f},{cy:.1f} vs projected {ex:.1f},{ey:.1f}: {err:.2f} px")
        if err > 2.0:
            problems.append(f"sun disc {err:.2f} px from the light direction (limit 2)")
if problems:
    print("FAIL " + "; ".join(problems))
    sys.exit(1)
print("landscape captures ok")
