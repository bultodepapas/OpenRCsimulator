# FW-MOON-03b: frame-to-frame motion of the moon's disc from track.gd's track.json (stepped vs per-frame sky).
# Usage: python3 -I research/field-world/fw-moon-03b/analyze.py OUT_DIR  (prints Markdown; writes OUT_DIR/summary.json)
import json
import math
import os
import statistics
import sys


def main(out):
    d = json.load(open(os.path.join(out, "track.json")))
    fov, h = d["fov_deg"], d["size"][1]
    px_per_deg = h / (2.0 * math.tan(math.radians(fov) / 2.0)) * math.pi / 180.0
    summary = {"px_per_deg": px_per_deg, "modes": {}}
    print("Fixed %.0f° camera, %d px high (%.1f px/deg at the centre), %s, %s.\n" % (fov, h, px_per_deg, d["engine"], d["adapter"]))
    print("| Mode | Frames | Total path | Median per-frame motion | Max per-frame motion | Frames moving > 1 px | Frames not moving (< 0.01 px) |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    tracks = {}
    for mode, m in d["modes"].items():
        fr = m["frames"]
        tracks[mode] = fr
        steps = [math.hypot(b["x"] - a["x"], b["y"] - a["y"]) for a, b in zip(fr, fr[1:])]
        s = {"frames": len(fr), "path_px": sum(steps), "median_px": statistics.median(steps), "max_px": max(steps),
             "over_1px": sum(1 for v in steps if v > 1.0), "still": sum(1 for v in steps if v < 0.01)}
        summary["modes"][mode] = s
        print("| %s | %d | %.1f px (%.3f°) | %.3f px | %.2f px | %d | %d |" % (
            mode, s["frames"], s["path_px"], s["path_px"] / px_per_deg, s["median_px"], s["max_px"], s["over_1px"], s["still"]))
    if "stepped" in tracks and "per_frame" in tracks:
        at_steps = []
        for a, b in zip(tracks["stepped"], tracks["per_frame"]):
            if a["i"] % 90 == 0:
                at_steps.append(math.hypot(a["x"] - b["x"], a["y"] - b["y"]))
        summary["step_instants_px"] = at_steps
        print("\nAt the step instants (frames 0, 90, 180, 270) the two modes differ by %s px." % ", ".join("%.3f" % v for v in at_steps))
    json.dump(summary, open(os.path.join(out, "summary.json"), "w"), indent=1)
    strip(out)


def strip(out, names=("stepped-088", "stepped-091", "per_frame-088", "per_frame-091")):
    """step-strip.png: the crops two frames before and one after the step at 1.5 s, stepped and per-frame (Pillow)."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return
    ims = [Image.open(os.path.join(out, n + ".png")).convert("RGB") for n in names]
    w, h = ims[0].size
    sheet = Image.new("RGB", (w * len(ims) + 10 * (len(ims) - 1), h + 20), (255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for k, (n, im) in enumerate(zip(names, ims)):
        sheet.paste(im, (k * (w + 10), 20))
        draw.text((k * (w + 10) + 4, 4), n, fill=(0, 0, 0))
    sheet.save(os.path.join(out, "step-strip.png"))


if __name__ == "__main__":
    main(sys.argv[1])
