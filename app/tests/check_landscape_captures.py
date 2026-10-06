"""Landscape capture checks (LANDSCAPE-PLAN L1+), run by capture.sh on the PNGs it just made.

L1a sky: in every landscape review view the sky is darker at the top of the frame than just above the horizon (the
gradient says which way is up); no 8-bit banding (the longest run of identical pixels down a sky column ≤ 3 px);
in the sun view the sun disc sits where the light direction projects (≤ 2 px).
Usage: python3 check_landscape_captures.py <captures dir>
"""
import hashlib
import json
import math
import os
import re
import sys

from PIL import Image

d = sys.argv[1]
problems = []
counters = {}
for line in open(os.path.join(d, "landscape-counters.txt")):
    name, rest = line.split(" ", 1)
    if name in counters:
        problems.append(f"duplicate counter record: {name}")
    counters[name] = dict(kv.split("=") for kv in rest.split())


def lum(p):
    return 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]


def band(px, x0, x1, y0, y1):
    vals = [lum(px[x, y]) for y in range(y0, y1) for x in range(x0, x1)]
    return sum(vals) / len(vals)


# This is the atmosphere reference inventory, not a glob of whichever old PNGs happen to remain.
land_cases = [f"az{az}-el{el}" for az in (0, 90, 180, 270) for el in (0, 10)]
land_cases += ["az90-el10-t11"] + [f"az{az}-el0-100m" for az in (0, 90, 180, 225, 270)]
land_cases += ["30m", "low3m", "sun", "30m-noplane", "low3m-noplane", "top"]
views = sorted(f"capture-land-{case}.png" for case in land_cases)
expected = {f[:-4] for f in views}
expected.update("capture" + suffix for suffix in ("", "-inspect", "-inspect-deflected", "-physics",
                "-physics-inspect", "-physics-nozoom", "-physics-low-inspect",
                "-physics-low-inspect-noplane", "-physics-inspect-noplane"))
if set(counters) != expected:
    problems.append(f"counter inventory mismatch: missing={sorted(expected - set(counters))}, extra={sorted(set(counters) - expected)}")
for name in sorted(expected):
    try:
        with open(os.path.join(d, name + ".json")) as file:
            manifest = json.load(file)
        with open(os.path.join(d, name + ".png"), "rb") as file:
            digest = hashlib.sha256(file.read()).hexdigest()
        if manifest.get("image") != name + ".png" or manifest.get("sha256") != digest:
            problems.append(f"{name}: manifest image/hash mismatch")
        if manifest.get("capture_scene") != "atmosphere":
            problems.append(f"{name}: L1-L4 require the atmosphere fixture, not the production field")
    except (OSError, ValueError) as error:
        problems.append(f"{name}: missing or invalid evidence: {error}")
if problems:
    sys.exit("\n".join(problems))
for f in views:
    im = Image.open(os.path.join(d, f)).convert("RGB")
    px = im.load()
    w, h = im.size
    x0, x1 = w - 280, w - 10  # right edge: away from the panel, the HUD and the sun
    # Horizon: geometric for the fixed views (el 0 → row 360, el 10 → row 496 at 50° vertical FOV); otherwise the
    # first row where this strip turns green (ground: g clearly above b).
    if "-el0" in f:
        horizon = h // 2
    elif "-el10" in f:
        horizon = h // 2 + round((h / 2) / math.tan(math.radians(25)) * math.tan(math.radians(10)))
    else:
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

# L0d: the shader clock sent during the capture equals its simulation time (t = 1.5 s).
for name, c in counters.items():
    if name.startswith("capture-land-"):
        want = "11.5" if name.endswith("-t11") else "1.5"
        if c.get("sim_clock") != want:
            problems.append(f"{name}: sim_clock {c.get('sim_clock')} instead of {want} (the capture's simulation time)")
print("sim_clock sent in every landscape view: " + ", ".join(sorted({c.get("sim_clock", "?") for n, c in counters.items() if n.startswith("capture-land-")})))

# L2 haze and horizon. Row means over a right-hand strip (no panel, HUD, airplane or sun there).
def row_means(png):
    im = Image.open(os.path.join(d, png)).convert("RGB")
    px = im.load()
    w, h = im.size
    out = []
    for y in range(h):
        acc = [0.0, 0.0, 0.0]
        for x in range(w - 300, w - 10, 2):
            p = px[x, y]
            acc = [acc[0] + p[0], acc[1] + p[1], acc[2] + p[2]]
        out.append([v / len(range(w - 300, w - 10, 2)) for v in acc])
    return out


def max_step(rows, y0, y1):
    return max(max(abs(rows[y + 1][c] - rows[y][c]) for c in range(3)) for y in range(y0, y1))


for az in (0, 90, 180, 225, 270):
    f = f"capture-land-az{az}-el0-100m.png"
    if f in views:
        step = max_step(row_means(f), 340, 400)
        print(f"{f}: largest step across the ground rim {step:.1f} levels")
        if step > 4.0:  # natural haze gradient ~3 levels/row here; a visible ground edge measured 13-21
            problems.append(f"{f}: a {step:.1f}-level step at the ground's rim (limit 4)")
for az in (0, 90, 180, 270):
    f = f"capture-land-az{az}-el0.png"
    if f in views:
        rows = row_means(f)
        sky_step = max_step(rows, 300, 359)
        lum = lambda r: 0.2126 * r[0] + 0.7152 * r[1] + 0.0722 * r[2]
        far, near = lum(rows[361]), lum(rows[650])  # ~1.4 km vs ~4.7 m away (row 650 stays off the runway)
        print(f"{f}: sky above the horizon steps ≤ {sky_step:.1f} levels; far ground {far:.0f} vs near ground {near:.0f}")
        if sky_step > 2.0:
            problems.append(f"{f}: a line in the sky above the horizon ({sky_step:.1f} levels)")
        if not far > near + 10.0:
            problems.append(f"{f}: no aerial perspective (far ground {far:.0f} not hazier than near ground {near:.0f})")

# L3 sun shadow: in the 0.8 m close-up the airplane's shadow lies where the light projects its CG onto the ground.
def rgb(png):
    return Image.open(os.path.join(d, png)).convert("RGB").load(), Image.open(os.path.join(d, png)).size


if "capture-physics-low-inspect.png" in os.listdir(d):
    (a, size), (b, _) = rgb("capture-physics-low-inspect.png"), rgb("capture-physics-low-inspect-noplane.png")
    w, h = size
    pts = []
    for y in range(h // 2, h):
        for x in range(0, w, 2):
            pa, pb = a[x, y], b[x, y]
            ground = pb[1] > pb[0] and pb[1] > pb[2]
            still_grass = pa[1] >= pa[0] and pa[1] >= pa[2]  # not an airplane pixel (red/white/grey)
            if ground and still_grass and lum(pa) < 0.85 * lum(pb):
                pts.append((x, y))
    expected = counters.get("capture-physics-low-inspect", {}).get("shadow_px", "behind")
    if len(pts) < 200 or expected == "behind":
        problems.append(f"sun shadow: not found in the 0.8 m close-up ({len(pts)} px, expected {expected})")
    else:
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        ex, ey = map(float, expected.split(","))
        bx, by = map(float, counters["capture-physics-low-inspect"]["below_px"].split(","))
        to_sun_proj = ((cx - ex) ** 2 + (cy - ey) ** 2) ** 0.5
        to_below = ((cx - bx) ** 2 + (cy - by) ** 2) ** 0.5
        offset = ((ex - bx) ** 2 + (ey - by) ** 2) ** 0.5
        print(f"sun shadow centroid {cx:.0f},{cy:.0f}: {to_sun_proj:.0f} px from the CG's projection along the light, "
              f"{to_below:.0f} px from the point straight below (the two are {offset:.0f} px apart; {len(pts)} shadow px)")
        # Direction, not shape: a whole airplane's shadow centroid is not its CG, but it must follow the light.
        if not (to_sun_proj < 0.5 * offset and to_below > 0.5 * offset):
            problems.append(f"sun shadow not offset along the light ({to_sun_proj:.0f} px vs {to_below:.0f} px; offset {offset:.0f})")

# L3: the sunlit airplane does not clip: 99th percentile of its CIE lightness L* stays below 95 (of 100). (Saturated
# red reaching 255 in one channel is colour, not clipping: its L* is ~55.)
def lightness(p):
    lin = [((c / 255 + 0.055) / 1.055) ** 2.4 if c / 255 > 0.04045 else c / 255 / 12.92 for c in p]
    y = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
    return 116 * y ** (1 / 3) - 16 if y > 0.008856 else 903.3 * y


if "capture-physics-inspect.png" in os.listdir(d):
    (a, size), (b, _) = rgb("capture-physics-inspect.png"), rgb("capture-physics-inspect-noplane.png")
    w, h = size
    ls = sorted(lightness(a[x, y]) for y in range(0, h, 2) for x in range(0, w, 2) if max(abs(a[x, y][c] - b[x, y][c]) for c in range(3)) > 10)
    p99 = ls[int(0.99 * (len(ls) - 1))] if ls else 100
    print(f"airplane in the close-up: {len(ls)} px sampled, 99th percentile lightness L* {p99:.1f} (limit 95)")
    if not ls or p99 >= 95:
        problems.append(f"sunlit airplane clips: L* 99th percentile {p99:.1f} ≥ 95")

# L4 clouds: 10 s apart, the same view visibly changes only in the sky (outside the panel and HUD text). Below the
# horizon the ground may shift by 1 level: the clouds change the sky radiance, i.e. the ambient light (measured).
if "capture-land-az90-el10-t11.png" in os.listdir(d):
    (a, size), (b, _) = rgb("capture-land-az90-el10.png"), rgb("capture-land-az90-el10-t11.png")
    w, h = size
    horizon = h // 2 + round((h / 2) / math.tan(math.radians(25)) * math.tan(math.radians(10)))
    ui = lambda x, y: (x < 500 and y < 270) or (y > 640 and x < 1000)  # input panel, HUD line
    delta = lambda x, y: max(abs(a[x, y][c] - b[x, y][c]) for c in range(3))
    sky_moved = sum(1 for y in range(horizon) for x in range(0, w) if not ui(x, y) and delta(x, y) > 3)
    ground_max = max(delta(x, y) for y in range(horizon, h) for x in range(0, w) if not ui(x, y))
    print(f"clouds 10 s apart: {sky_moved} sky px changed by > 3 levels; the ground changed by at most {ground_max} level(s)")
    if sky_moved < 1000:
        problems.append(f"clouds: the sky barely changed in 10 s ({sky_moved} px)")
    if ground_max > 1:
        problems.append(f"clouds: the ground changed by {ground_max} levels (only the sky may change visibly)")

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
