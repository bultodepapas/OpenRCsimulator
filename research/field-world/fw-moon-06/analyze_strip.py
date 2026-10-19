# FW-MOON-06: step-to-step change of twilight_strip.gd renders, to find pops (a frame that changes far more than its
# neighbours) as opposed to the steady fall of twilight.
# Usage: python3 -I research/field-world/fw-moon-06/analyze_strip.py DIR [DIR ...]  (prints Markdown; writes
# DIR/strip-summary.json per directory and, with --sheet=OUT.png --minutes=50,60,..., a contact sheet of DIR columns.)
# Per view and region (sky: top 55 % of rows; ground: bottom 30 %), on linearised pixels:
#   change(k) = mean |I_k - I_(k-1)| / mean I_(k-1)            (relative mean absolute difference)
#   pop(k)    = change(k) / median(change over steps k-5 ... k+5, k excluded)
# A pop factor near 1 is the twilight's own pace; a large one is a discrete jump.
import json
import os
import statistics
import sys

import numpy as np
from PIL import Image, ImageDraw


def linear(img):
    a = np.asarray(img.convert("RGB"), dtype=np.float64) / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def regions(a):
    h = a.shape[0]
    return {"sky": a[: int(0.55 * h)], "ground": a[int(0.70 * h):]}


def analyse(d):
    m = json.load(open(os.path.join(d, "manifest.json")))
    frames = m["frames"]
    out = {"sky": m["sky"], "arguments": m["arguments"], "views": {}}
    for view in m["views"]:
        prev = None
        series = {"sky": [], "ground": []}
        for fr in frames:
            cur = regions(linear(Image.open(os.path.join(d, fr[view]))))
            for r in series:
                if prev is None:
                    series[r].append(0.0)
                else:
                    series[r].append(float(np.mean(np.abs(cur[r] - prev[r])) / max(np.mean(prev[r]), 1e-6)))
            prev = cur
        res = {}
        for r, ch in series.items():
            pops = []
            for k in range(1, len(ch)):
                window = [ch[j] for j in range(max(1, k - 5), min(len(ch), k + 6)) if j != k]
                med = statistics.median(window) if window else 0.0
                pops.append((ch[k] / med if med > 1e-9 else 0.0, k))
            worst_pop, k_pop = max(pops)
            worst, k_max = max((c, k) for k, c in enumerate(ch))
            res[r] = {"change": ch, "max_change": worst, "max_change_step": k_max, "max_pop": worst_pop,
                      "max_pop_step": k_pop, "median_change": statistics.median(ch[1:])}
        out["views"][view] = res
    out["frames"] = [{k: v for k, v in fr.items() if k not in m["views"]} for fr in frames]
    json.dump(out, open(os.path.join(d, "strip-summary.json"), "w"), indent=1)
    return out


def describe(d, s):
    print("\n### %s (%s sky, %s)\n" % (os.path.basename(os.path.normpath(d)), s["sky"], " ".join(s["arguments"])))
    print("| View | Region | Median change per step | Largest change (step: min, sun, moon) | Largest pop factor (step) |")
    print("| --- | --- | --- | --- | --- |")
    fr = s["frames"]
    for view, res in s["views"].items():
        for r, v in res.items():
            k = v["max_change_step"]
            kp = v["max_pop_step"]
            print("| %s | %s | %.1f %% | %.1f %% (%d: %.1f min, sun %.2f°, moon %.2f°) | %.1f× (%d: sun %.2f°) |" % (
                view, r, 100 * v["median_change"], 100 * v["max_change"], k, fr[k]["minutes"], fr[k]["sun_elevation_deg"],
                fr[k]["moon_elevation_deg"], v["max_pop"], kp, fr[kp]["sun_elevation_deg"]))


def sheet(dirs, minutes, path):
    tiles = []
    for d in dirs:
        m = json.load(open(os.path.join(d, "manifest.json")))
        by_min = {round(fr["minutes"], 1): fr for fr in m["frames"]}
        views = list(m["views"])  # Godot's JSON.stringify sorts keys: east before west
        col = []
        for mi in minutes:
            fr = by_min[round(mi, 1)]
            col.append((fr, [Image.open(os.path.join(d, fr[v])).convert("RGB") for v in views]))
        tiles.append((os.path.basename(os.path.normpath(d)), col))
    w, h = tiles[0][1][0][1][0].size
    nviews = len(tiles[0][1][0][1])
    sw, sh = w // 2, h // 2
    gap = 4
    label_w = 150
    width = label_w + len(tiles) * (nviews * (sw + gap) + 12)
    height = 18 + len(minutes) * (sh + gap)
    img = Image.new("RGB", (width, height), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    for c, (name, col) in enumerate(tiles):
        x0 = label_w + c * (nviews * (sw + gap) + 12)
        draw.text((x0, 3), name + "  (" + " | ".join(views) + ")", fill=(0, 0, 0))
        for r, (fr, ims) in enumerate(col):
            y = 18 + r * (sh + gap)
            if c == 0:
                draw.text((4, y + 4), "%.1f min" % fr["minutes"], fill=(0, 0, 0))
                draw.text((4, y + 18), "sun %.2f°" % fr["sun_elevation_deg"], fill=(0, 0, 0))
                draw.text((4, y + 32), "moon %.2f°" % fr["moon_elevation_deg"], fill=(0, 0, 0))
                draw.text((4, y + 46), "light %s" % fr["light_source"], fill=(0, 0, 0))
            for v, im in enumerate(ims):
                img.paste(im.resize((sw, sh)), (x0 + v * (sw + gap), y))
    img.save(path)


def main(argv):
    opts = {a.split("=", 1)[0]: a.split("=", 1)[1] for a in argv if a.startswith("--")}
    dirs = [a for a in argv if not a.startswith("--")]
    for d in dirs:
        describe(d, analyse(d))
    if "--sheet" in opts:
        sheet(dirs, [float(x) for x in opts.get("--minutes", "50,62,66,66.5,67,67.5,90,120,135.5,136,136.5,150").split(",")],
              opts["--sheet"])


if __name__ == "__main__":
    main(sys.argv[1:])
