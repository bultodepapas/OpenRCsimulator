"""Summarize TT-21 paired native observations and compare unedited RGB captures."""
import argparse
import json
import statistics
from pathlib import Path

import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    report = json.loads((args.directory / "report.json").read_text())
    grouped = {}
    for item in report["samples"]:
        grouped.setdefault(item["view"], {}).setdefault(item["variant"], []).append(item)
    views = []
    for view, variants in grouped.items():
        result = {"view": view, "variants": {}, "pixel_pairs": []}
        for variant, records in variants.items():
            frames = [frame for record in records for frame in record["frames"]]
            result["variants"][variant] = {
                key + "_median": statistics.median(frame[key] for frame in frames)
                for key in ["visible_draw_calls", "visible_primitives", "visible_objects",
                            "render_cpu_ms", "render_gpu_ms", "frame_setup_cpu_ms"]
            }
        for base in variants["baseline"]:
            cand = next(r for r in variants["candidate"] if r["pair"] == base["pair"])
            a = np.asarray(Image.open(args.directory / base["image"]).convert("RGB"), dtype=np.int16)
            b = np.asarray(Image.open(args.directory / cand["image"]).convert("RGB"), dtype=np.int16)
            difference = np.abs(a - b)
            result["pixel_pairs"].append({
                "pair": base["pair"], "pixels": int(a.shape[0] * a.shape[1]),
                "changed_pixels": int(np.any(difference != 0, axis=2).sum()),
                "pixels_over_1": int(np.any(difference > 1, axis=2).sum()),
                "pixels_over_8": int(np.any(difference > 8, axis=2).sum()),
                "max_channel_difference": int(difference.max()),
                "mean_absolute_channel_difference": float(difference.mean()),
                "baseline_image": base["image"], "candidate_image": cand["image"],
            })
        views.append(result)
    result = {"format": "openrc-timber-native-render-summary v1", "mode": report["mode"],
              "baseline_sha256": report["baseline_sha256"], "candidate_sha256": report["candidate_sha256"],
              "merge": report["merge"], "views": views,
              "limits": "Render timings are descriptive shared-desktop observations. Pixel comparisons use raw RGB captures, not compressed or rescaled images. Draw calls describe this isolated viewport, not the full simulator."}
    (args.directory / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
    for view in views:
        base, cand = view["variants"]["baseline"], view["variants"]["candidate"]
        print(view["view"], "draws", base["visible_draw_calls_median"], "->", cand["visible_draw_calls_median"],
              "changed pixels", [p["changed_pixels"] for p in view["pixel_pairs"]],
              "max channel", max(p["max_channel_difference"] for p in view["pixel_pairs"]))
    print("merge", result["merge"])


if __name__ == "__main__":
    main()
