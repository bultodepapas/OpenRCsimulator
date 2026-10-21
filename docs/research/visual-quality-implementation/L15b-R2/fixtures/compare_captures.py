#!/usr/bin/env python3
"""L15b-R2 capture comparisons for tools/trees/quality_capture.gd outputs.

calm:   per-view pixel differences between two complete captures (for example wind off/on).
motion: changed-pixel statistics of a fixed-camera --motion route, plus review images.

Run with the pinned visual environment, for example:
  "$(app/tests/visual-env.sh)" -I compare_captures.py calm --a OFF --b ON --out calm.json
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def load(folder: Path, capture_id: str) -> np.ndarray:
    return np.asarray(Image.open(folder / f"{capture_id}.png").convert("RGB"), dtype=np.int16)


def report(folder: Path) -> dict:
    data = json.loads((folder / "report.json").read_text(encoding="utf-8"))
    if not data.get("complete"):
        raise SystemExit(f"{folder}: incomplete capture")
    return data


def calm(args: argparse.Namespace) -> dict:
    first, second = report(args.a), report(args.b)
    for key in ("godot", "renderer", "adapter", "viewport", "msaa"):
        if first.get(key) != second.get(key):
            raise SystemExit(f"mismatched fixture identity: {key}")
    views = {}
    for capture in first["captures"]:
        capture_id = capture["id"]
        if capture_id.startswith("wind_"):
            continue
        difference = np.abs(load(args.a, capture_id) - load(args.b, capture_id)).max(axis=2)
        views[capture_id] = {
            "pixel_exact": bool(difference.max() == 0),
            "changed_px": int((difference > 0).sum()),
            "changed_px_over_2_levels": int((difference > 2).sum()),
            "max_level_difference": int(difference.max()),
        }
    return {"a": str(args.a.name), "b": str(args.b.name), "renderer": first["renderer"],
            "adapter": first["adapter"], "views": views}


def motion(args: argparse.Namespace) -> dict:
    data = report(args.clip)
    frames = [load(args.clip, capture["id"]) for capture in data["captures"]]
    consecutive = [int((np.abs(frames[i] - frames[i - 1]).max(axis=2) > 2).sum()) for i in range(1, len(frames))]
    union = np.zeros(frames[0].shape[:2], dtype=bool)
    for frame in frames[1:]:
        union |= np.abs(frame - frames[0]).max(axis=2) > 2
    result = {"route": data["motion"], "frames": len(frames),
              "consecutive_changed_px_over_2": {"min": min(consecutive), "median": int(np.median(consecutive)),
                                                "max": max(consecutive)},
              "union_changed_px_over_2": int(union.sum()),
              "union_changed_px_below_row": {str(args.ground_row): int(union[args.ground_row:].sum())}}
    if args.calm is not None:
        calm_image = load(args.calm, args.calm_id)
        result["first_frame_vs_calm_over_2"] = int((np.abs(frames[0] - calm_image).max(axis=2) > 2).sum())
    if args.images is not None:
        args.images.mkdir(parents=True, exist_ok=True)
        overlay = frames[0].astype(np.uint8).copy()
        overlay[union] = (overlay[union] * 0.4 + np.array([255, 0, 255]) * 0.6).astype(np.uint8)
        Image.fromarray(overlay).resize((960, 540)).save(args.images / "motion_union.jpg", quality=85)
        # Four crops 0.25 s apart: a compact stand-in for the clip (raw frames are not retained).
        box = tuple(args.crop)
        crops = [Image.fromarray(frames[index].astype(np.uint8)).crop(box) for index in (0, 6, 12, 18)]
        strip = Image.new("RGB", (sum(crop.width for crop in crops) + 3 * 8, crops[0].height), (255, 255, 255))
        for slot, crop in enumerate(crops):
            strip.paste(crop, (slot * (crop.width + 8), 0))
        strip.save(args.images / "motion_strip.jpg", quality=88)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    calm_parser = commands.add_parser("calm")
    calm_parser.add_argument("--a", type=Path, required=True)
    calm_parser.add_argument("--b", type=Path, required=True)
    motion_parser = commands.add_parser("motion")
    motion_parser.add_argument("--clip", type=Path, required=True)
    motion_parser.add_argument("--calm", type=Path)
    motion_parser.add_argument("--calm-id", default="car_park")
    motion_parser.add_argument("--ground-row", type=int, default=420)
    motion_parser.add_argument("--images", type=Path)
    motion_parser.add_argument("--crop", type=int, nargs=4, default=(860, 0, 1280, 300))
    for sub in (calm_parser, motion_parser):
        sub.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = calm(args) if args.command == "calm" else motion(args)
    args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
