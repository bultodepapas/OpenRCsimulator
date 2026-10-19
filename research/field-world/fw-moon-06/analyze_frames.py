# FW-MOON-06d: frame-to-frame brightness change in frame_track.gd's frames.json (stepped vs per-frame sky).
# Usage: python3 -I research/field-world/fw-moon-06/analyze_frames.py OUT_DIR  (prints Markdown; writes OUT_DIR/frames-summary.json)
# Per region the mean linear luminance is encoded back to an sRGB display level (0-255). Reported: the largest
# frame-to-frame change in display levels, and the relative change of the linear mean where that mean shows (>= 2
# display levels; a near-black region's relative change is quantisation noise).
import json
import math
import os
import statistics
import sys

VISIBLE_LEVEL = 2.0


def level(lin):
    c = max(lin, 0.0)
    return 255.0 * (12.92 * c if c < 0.0031308 else 1.055 * c ** (1.0 / 2.4) - 0.055)


def main(out):
    d = json.load(open(os.path.join(out, "frames.json")))
    summary = []
    print("| Window | Mode | Region | Mean display level | Largest per-frame change (levels) | Largest relative change | Frames changing > 2 % |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for run in d["runs"]:
        fr = run["frames"]
        for region in ("sky", "ground"):
            levels = [level(f[region]) for f in fr]
            dl = [abs(b - a) for a, b in zip(levels, levels[1:])]
            visible = statistics.mean(levels) >= VISIBLE_LEVEL
            rel = [abs(math.log(b[region] / a[region])) for a, b in zip(fr, fr[1:]) if a[region] > 0 and b[region] > 0] if visible else []
            row = {"window": run["window"], "mode": run["mode"], "region": region, "mean_level": statistics.mean(levels),
                   "max_level_change": max(dl), "max_relative": max(rel) if rel else None,
                   "over_2pct": sum(1 for c in rel if c > 0.02) if rel else None}
            summary.append(row)
            print("| %s | %s | %s | %.1f | %.2f | %s | %s |" % (row["window"], row["mode"], region, row["mean_level"],
                row["max_level_change"], "%.2f %%" % (100 * row["max_relative"]) if rel else "(below %g levels)" % VISIBLE_LEVEL,
                row["over_2pct"] if rel else "–"))
    json.dump(summary, open(os.path.join(out, "frames-summary.json"), "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
