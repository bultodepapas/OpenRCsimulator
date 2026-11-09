"""Compare inspect_timber.gd texture-motion pairs; use app/tests/requirements-visual.txt.

Run with --root DIR containing stock-before/after, paint-before/after and
distance-before/after. Writes metrics and lossless review crops to a NEW --out.
Temporal differences include real camera-driven shading; they are not a perceptual
shimmer score or a performance measurement. Inspect the paired images as well.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


# Fixed interiors selected from the declared camera views, away from silhouettes.
# Coordinates refer to the required native 1920 x 1080 capture; right/bottom exclusive.
REGIONS = {"gear": (1320, 540, 1370, 640), "foam": (1020, 500, 1080, 510)}
TEXTURE_PATHS = {
    "res://assets/aircraft/turbo-lumber-evolution/visual-upgrade/textures/" + name
    for name in ("polystyrene_nor_gl_1k.jpg", "polystyrene_rough_1k.jpg",
                 "Rubber002_1K-JPG_NormalGL.jpg", "Rubber002_1K-JPG_Roughness.jpg")
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_pair(root: Path, case: str) -> tuple[dict, dict]:
    before = json.loads((root / f"{case}-before/manifest.json").read_text())
    after = json.loads((root / f"{case}-after/manifest.json").read_text())
    if before["image_size"] != [1920, 1080] or after["image_size"] != [1920, 1080]:
        raise ValueError("1080p captures required")
    expected_suite = "distance" if case == "distance" else "texture-motion"
    expected_finish = "paint" if case == "paint" else "production"
    if before["suite"] != expected_suite or before["finish"] != expected_finish:
        raise ValueError(f"wrong suite or finish for {case}")
    expected_names = (
        {f"distance_{distance:03d}m_{pose}.png" for distance in (20, 50, 100)
         for pose in ("level_crossing", "roll_minus60", "roll_plus60", "nose_toward_pilot")}
        if case == "distance" else
        {f"texture_{region}_{frame:03d}.png" for region in REGIONS for frame in range(24)}
    )
    for manifest in (before, after):
        textures = manifest["detail_textures"]
        if len(textures) != 4 or {t["path"] for t in textures} != TEXTURE_PATHS:
            raise ValueError("exactly the four expected detail textures are required")
        captures = manifest["captures"]
        if len(captures) != len(expected_names) or {c["file"] for c in captures} != expected_names:
            raise ValueError("the complete named camera sequence is required")
    # Only the four import descriptors and their loaded image data may differ.
    for key in before.keys() | after.keys():
        if key not in {"detail_textures", "captures"} and before.get(key) != after.get(key):
            raise ValueError(f"mismatched {case} manifest field: {key}")
    for a, b in zip(before["detail_textures"], after["detail_textures"], strict=True):
        if a["mipmaps"] != 0 or b["mipmaps"] != 10 or a["path"] != b["path"] or a["format"] != b["format"]:
            raise ValueError("expected unchanged texture format and 0 -> 10 mip levels")
    for a, b in zip(before["captures"], after["captures"], strict=True):
        if {k: v for k, v in a.items() if k != "png_sha256"} != {k: v for k, v in b.items() if k != "png_sha256"}:
            raise ValueError(f"camera/control mismatch: {a['file']}")
    return before, after


def pixels(path: Path, expected_hash: str) -> np.ndarray:
    if digest(path) != expected_hash:
        raise ValueError(f"changed capture: {path}")
    with Image.open(path) as image:
        if image.size != (1920, 1080):
            raise ValueError(f"wrong image dimensions: {path}")
        return np.asarray(image.convert("RGB"))


def compare(root: Path, out: Path, case: str) -> dict:
    before, after = read_pair(root, case)
    rows = []
    series = {name: [[], []] for name in REGIONS}
    for a, b in zip(before["captures"], after["captures"], strict=True):
        name = a["file"]
        left = pixels(root / f"{case}-before" / name, a["png_sha256"])
        right = pixels(root / f"{case}-after" / name, b["png_sha256"])
        difference = np.abs(left.astype(np.int16) - right.astype(np.int16))
        background = left[-1, -1]
        mask_a = np.any(left != background, axis=2)
        mask_b = np.any(right != background, axis=2)
        rows.append({"file": name, "before_sha256": a["png_sha256"], "after_sha256": b["png_sha256"],
                     "changed_pixels": int(np.count_nonzero(np.any(difference != 0, axis=2))),
                     "max_channel_delta": int(difference.max()),
                     "silhouette_changed_pixels": int(np.count_nonzero(mask_a != mask_b))})
        for region, box in REGIONS.items():
            if not name.startswith(f"texture_{region}_"):
                continue
            x0, y0, x1, y1 = box
            series[region][0].append(left[y0:y1, x0:x1].astype(np.float64))
            series[region][1].append(right[y0:y1, x0:x1].astype(np.float64))
            if name.endswith("012.png"):
                width, height = (x1 - x0) * 6, (y1 - y0) * 6
                crop = Image.new("RGB", (width * 2, height))
                crop.paste(Image.fromarray(left).crop(box).resize((width, height), Image.Resampling.NEAREST), (0, 0))
                crop.paste(Image.fromarray(right).crop(box).resize((width, height), Image.Resampling.NEAREST), (width, 0))
                crop.save(out / f"{case}-{region}-before-left-after-right.png")
    temporal = {}
    for region, values in series.items():
        if not values[0]:
            continue
        if len(values[0]) != 24:
            raise ValueError("expected all 24 camera positions for each texture region")
        rms = [float(np.sqrt(np.mean(np.diff(np.stack(v), n=2, axis=0) ** 2))) for v in values]
        temporal[region] = {"crop_xyxy": REGIONS[region], "camera_positions": 24,
                            "second_difference_rms_before": rms[0], "second_difference_rms_after": rms[1],
                            "after_before_ratio": rms[1] / rms[0] if rms[0] else None}
    expected = 12 if case == "distance" else 48
    if len(rows) != expected or any(r["silhouette_changed_pixels"] for r in rows):
        raise ValueError("incomplete suite or changed silhouette")
    return {"before_manifest_sha256": digest(root / f"{case}-before/manifest.json"),
            "after_manifest_sha256": digest(root / f"{case}-after/manifest.json"),
            "textures_before": before["detail_textures"], "textures_after": after["detail_textures"],
            "temporal": temporal, "captures": rows}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    report = {"method": "RGB8 second-difference RMS within fixed surface interiors across successive camera positions",
              "limits": "Includes legitimate shading changes. Crops and silhouette checks do not qualify flight readability or GPU performance.",
              "cases": {case: compare(args.root, args.out, case) for case in ("stock", "paint", "distance")}}
    (args.out / "comparison.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({case: {"captures": len(value["captures"]), "temporal": value["temporal"]}
                      for case, value in report["cases"].items()}, indent=2))


if __name__ == "__main__":
    main()
