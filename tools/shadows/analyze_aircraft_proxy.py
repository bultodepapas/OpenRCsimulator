"""Reduce an aircraft_proxy_trial.gd run; keep raw timings and PNGs in its directory."""
from __future__ import annotations

import argparse
import hashlib
import json
import statistics
from pathlib import Path

from PIL import Image, ImageChops


def difference(reference: Path, candidate: Path, mask: bool) -> dict:
    with Image.open(reference) as source, Image.open(candidate) as target:
        if source.size != target.size:
            raise ValueError(f"Image dimensions differ: {candidate}")
        if mask:
            delta = ImageChops.difference(source.convert("RGBA").getchannel("A"), target.convert("RGBA").getchannel("A"))
        else:
            channels = ImageChops.difference(source.convert("RGB"), target.convert("RGB")).split()
            delta = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
        histogram = delta.histogram()
        return {
            "l1": sum(value * count for value, count in enumerate(histogram)),
            "changed_pixels": sum(histogram[1:]),
            "peak_8bit": max(value for value, count in enumerate(histogram) if count),
            "pixels": source.width * source.height,
        }


def distribution(values: list[float]) -> dict:
    ordered = sorted(values)

    def percentile(fraction: float) -> float:
        position = (len(ordered) - 1) * fraction
        lower = int(position)
        upper = min(lower + 1, len(ordered) - 1)
        return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)

    return {"p50": statistics.median(values), "p95": percentile(0.95), "p99": percentile(0.99)}


def summarize(directory: Path) -> dict:
    report_path = directory / "report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("format") != "openrc-aircraft-shadow-proxy-trial v1" or not report.get("complete"):
        raise ValueError("A complete aircraft proxy trial is required")
    cases = []
    for case in report["cases"]:
        full = next(variant for variant in case["variants"] if variant["role"] == "full")
        variants = []
        for variant in case["variants"]:
            for key in ("mask", "receiver"):
                path = directory / variant[key]
                if hashlib.sha256(path.read_bytes()).hexdigest() != variant[key + "_sha256"]:
                    raise ValueError(f"Changed capture: {path}")
            if variant["role"] == "full":
                continue
            variants.append({
                "role": variant["role"], "triangles": variant["triangles"],
                "mask_alpha": difference(directory / full["mask"], directory / variant["mask"], True),
                "receiver_rgb_max": difference(directory / full["receiver"], directory / variant["receiver"], False),
            })
        proxy = next(variant for variant in variants if variant["role"] == "proxy")
        controls = [variant for variant in variants if variant["role"].startswith("cache-axis-")]
        comparisons = {
            key: proxy[key]["l1"] <= max(control[key]["l1"] for control in controls)
            for key in ("mask_alpha", "receiver_rgb_max")
        } if controls else {}
        cases.append({
            "case_id": case["case_id"], "full_triangles": full["triangles"],
            "representation": case["representation"], "lod_surfaces": case["lod_surfaces"],
            "full_collect_ms": case["full_collect_usec"] / 1000,
            "proxy_collect_ms": case["proxy_collect_usec"] / 1000,
            "proxy_l1_below_largest_sampled_cache_control": comparisons, "differences": variants,
        })
    profiles = []
    for batch in report["profiles"]:
        samples = batch["samples"]
        profiles.append({
            key: batch[key] for key in ("pair", "role", "triangles", "redraws", "root_draw_progress", "frames_including_warmup")
        } | {
            "sample_count": len(samples),
            "wall_ms": distribution([sample["wall_usec"] / 1000 for sample in samples]),
            "mask_cpu_ms": distribution([sample["mask_cpu_ms"] for sample in samples]),
            "mask_gpu_ms": distribution([sample["mask_gpu_ms"] for sample in samples]),
            "observed_mask_primitives": sorted({sample["mask_counter_primitives"] for sample in samples}),
        })
    return {
        "format": "openrc-aircraft-shadow-proxy-summary v1",
        "report_sha256": hashlib.sha256(report_path.read_bytes()).hexdigest(),
        "identity": {key: report[key] for key in ("engine", "adapter", "renderer", "driver", "window_size", "reconstruction", "asset_sha256", "livery", "model_manifest_sha256", "source_sha256", "max_lod_distance")},
        "bindings": report["bindings"], "cases": cases, "profiles": profiles,
        "collection_median_ms": {role: statistics.median(case[role + "_collect_ms"] for case in cases) for role in ("full", "proxy")},
        "limits": report["limits"] + " Cache controls are sampled context, not a global simplification-error bound. Percentiles use linear interpolation; GPU samples may repeat or lag.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--out", required=True, type=Path, help="New summary JSON; existing files are preserved")
    args = parser.parse_args()
    result = summarize(args.directory)
    with args.out.open("x", encoding="utf-8", newline="\n") as output:
        json.dump(result, output, indent=2)
        output.write("\n")
    print(f"Analyzed {len(result['cases'])} cases and {len(result['profiles'])} profile batches: {args.out}")


if __name__ == "__main__":
    main()
