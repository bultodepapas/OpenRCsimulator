#!/usr/bin/env python3
"""Measure the TOD-07 cloud-occlusion probe's centered Sun ROI."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_image(path: Path) -> Image.Image:
    with Image.open(path) as source:
        return source.convert("RGB")


def luma(pixel: tuple[int, int, int]) -> float:
    return 0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]


def compare_pair(folder: Path, on_name: str, off_name: str, half: int) -> dict:
    on_image = read_image(folder / on_name)
    off_image = read_image(folder / off_name)
    if on_image.size != off_image.size:
        raise ValueError(f"image dimensions differ for {on_name} and {off_name}")
    width, height = on_image.size
    cx, cy = width // 2, height // 2
    box = (cx - half, cy - half, cx + half + 1, cy + half + 1)
    on_pixels = list(on_image.crop(box).getdata())
    off_pixels = list(off_image.crop(box).getdata())
    on_luma = [luma(pixel) for pixel in on_pixels]
    off_luma = [luma(pixel) for pixel in off_pixels]
    delta = [a - b for a, b in zip(on_luma, off_luma)]
    channel_deltas = [
        max(abs(a[channel] - b[channel]) for channel in range(3))
        for a, b in zip(on_pixels, off_pixels)
    ]
    return {
        "sun_on": on_name,
        "sun_off": off_name,
        "image_size": [width, height],
        "roi_box_xyxy": list(box),
        "roi_pixel_count": len(on_pixels),
        "sun_on_mean_rec709_code_luma_0_255": sum(on_luma) / len(on_luma),
        "sun_off_mean_rec709_code_luma_0_255": sum(off_luma) / len(off_luma),
        "sun_lin_delta_mean_rec709_code_luma_0_255": sum(delta) / len(delta),
        "sun_lin_delta_max_rec709_code_luma_0_255": max(delta),
        "sun_lin_delta_changed_pixels": sum(value > 0 for value in delta),
        "max_rgb_channel_delta": max(channel_deltas),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence_dir", type=Path)
    parser.add_argument("--roi-half-size", type=int, default=20,
                        help="half-width/height in pixels for the centered square Sun ROI")
    args = parser.parse_args()
    folder = args.evidence_dir.resolve()
    if args.roi_half_size < 1:
        raise ValueError("ROI half-size must be positive")
    probe = json.loads((folder / "probe.json").read_text(encoding="utf-8"))
    clear = compare_pair(folder, "high-cloud-0-sun-on.png", "high-cloud-0-sun-off.png", args.roi_half_size)
    overcast = compare_pair(folder, "high-cloud-1-sun-on.png", "high-cloud-1-sun-off.png", args.roi_half_size)
    below = compare_pair(folder, "below-sun-sun-on.png", "below-sun-sun-off.png", args.roi_half_size)
    clear_delta = clear["sun_lin_delta_mean_rec709_code_luma_0_255"]
    overcast_delta = overcast["sun_lin_delta_mean_rec709_code_luma_0_255"]
    ratio = overcast_delta / clear_delta if clear_delta > 0.0 else None
    results = {
        "format": "openrc-tod-07-cloud-occlusion-analysis v1",
        "method": "Centered 41x41 sRGB capture patch; compare rendered sun_lin on/off with other test uniforms fixed. Rec.709 code luma is an image-code metric, not physical radiance.",
        "renderer": probe["renderer"],
        "adapter": probe["adapter"],
        "roi_half_size_px": args.roi_half_size,
        "clear_cloud_coverage_0": clear,
        "overcast_cloud_coverage_1": overcast,
        "below_horizon_control": below,
        "overcast_to_clear_sun_delta_ratio": ratio,
        "checks": {
            "clear_sun_roi_has_positive_solar_delta": clear_delta > 10.0,
            "overcast_reduces_solar_delta_by_at_least_99_percent": ratio is not None and ratio <= 0.01,
            "below_horizon_control_has_exactly_zero_rgb_change": below["max_rgb_channel_delta"] == 0,
        },
        "probe_sha256": sha256(folder / "probe.json"),
    }
    results["checks"]["all_pass"] = all(results["checks"].values())
    output = folder / "analysis.json"
    output.write_text(json.dumps(results, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(results, indent=2, sort_keys=True))
    return 0 if results["checks"]["all_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
