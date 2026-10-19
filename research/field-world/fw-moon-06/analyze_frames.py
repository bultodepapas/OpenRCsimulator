# FW-MOON-06d: frame-to-frame brightness change in frame_track.gd's frames.json (stepped vs per-frame sky).
# Usage: python3 -I research/field-world/fw-moon-06/analyze_frames.py OUT_DIR  (prints Markdown; writes OUT_DIR/frames-summary.json)
import json
import math
import os
import statistics
import sys


def main(out):
    d = json.load(open(os.path.join(out, "frames.json")))
    summary = []
    print("| Window | Mode | Region | Median per-frame change | Largest per-frame change | Frames changing > 2 % |")
    print("| --- | --- | --- | --- | --- | --- |")
    for run in d["runs"]:
        fr = run["frames"]
        for region in ("sky", "ground"):
            ch = [abs(math.log(b[region] / a[region])) for a, b in zip(fr, fr[1:]) if a[region] > 0 and b[region] > 0]
            row = {"window": run["window"], "mode": run["mode"], "region": region, "median": statistics.median(ch),
                   "max": max(ch), "over_2pct": sum(1 for c in ch if c > 0.02)}
            summary.append(row)
            print("| %s | %s | %s | %.3f %% | %.2f %% | %d |" % (row["window"], row["mode"], region, 100 * row["median"],
                                                               100 * row["max"], row["over_2pct"]))
    json.dump(summary, open(os.path.join(out, "frames-summary.json"), "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
