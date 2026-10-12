"""LU-09 native image checks. Pillow is pinned in tools/landscape/requirements.txt."""
import json
import re
import sys
from pathlib import Path

from PIL import Image


def main():
    folder = Path(sys.argv[1])
    report = json.loads((folder / "report.json").read_text(encoding="utf-8"))
    samples = {}
    for name, case in report["cases"].items():
        if not name.startswith("marker_") and name not in ("runway_threshold", "runway_inside", "runway_east_far"):
            continue
        # Godot JSON encodes Vector2 as a parenthesized string.
        point = [float(v) for v in re.findall(r"[-+]?\d+(?:\.\d+)?", case["marker_center_px"])]
        x, y = map(round, point)
        with Image.open(folder / f"{name}.png") as image:
            image = image.convert("RGB")
            pixels = [image.getpixel((u, v)) for v in range(y - 8, y + 9) for u in range(x - 8, x + 9)
                      if 0 <= u < image.width and 0 <= v < image.height]
        samples[name] = {"sum_rgb": sum(sum(p) for p in pixels), "peak_rgb": max(pixels, key=sum),
                         "lamp_factor": case["lamp_factor"], "exposure": case["exposure"]}
    clear = samples["marker_clear"]["sum_rgb"]
    half = samples["marker_half"]["sum_rgb"]
    checks = {
        "visible_core": clear > 10000,
        "intermediate_fade": 0 < half < clear,
        "daylight_off": samples["marker_off"]["sum_rgb"] == 0,
        "opaque_occlusion": samples["marker_occluded"]["sum_rgb"] == 0,
        "fixed_exposure": len({samples[n]["exposure"] for n in samples if n.startswith("marker_")}) == 1,
    }
    for name, channel in [("runway_threshold", 1), ("runway_inside", 0), ("runway_east_far", 1)]:
        if name in samples:
            color = samples[name]["peak_rgb"]
            checks[name + "_directional_color"] = color[channel] > max(color[i] for i in range(3) if i != channel) * 1.1
    result = {"checks": checks, "samples": samples, "passed": all(checks.values()),
              "note": "Encoded RGB comparison, not linear radiance or photometric calibration; raw engine PNGs."}
    (folder / "marker-checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
