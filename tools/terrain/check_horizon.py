#!/usr/bin/env python3
"""Render and check the L7 horizon A/B capture set, including byte repeatability and flat-corridor fog seams."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CAPTURE_SCRIPT = Path(__file__).with_name("capture_horizon.gd")
PRESETS = {"default": 23000.0, "hazy": 12000.0, "clear": 40000.0}
AZIMUTHS = (0, 90, 180, 270)
ALTITUDES = ((1.7, "h1p7"), (30.0, "h30m"), (140.0, "h140m"))
RIM_AZIMUTHS = (90, 270)
FORMAT = "openrc-horizon-capture v1"
SUMMARY_FORMAT = "openrc-horizon-review v1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def checked_run(command: list[str], log_path: Path, env: dict[str, str], timeout_s: int = 180) -> None:
    with log_path.open("w") as output:
        result = subprocess.run(
            ["timeout", "--kill-after=5", str(timeout_s), *command],
            stdout=output,
            stderr=subprocess.STDOUT,
            env=env,
            check=False,
        )
    text = re.sub(r"\x1b\[[0-9;]*m", "", log_path.read_text(errors="replace"))
    if result.returncode or re.search(r"^\s*(?:(?:SCRIPT|SHADER)\s+)?ERROR:", text, re.M):
        raise RuntimeError(f"engine capture failed ({result.returncode}): {log_path}")


def expected_case_ids() -> dict[str, set[str]]:
    expected: dict[str, set[str]] = {preset: set() for preset in PRESETS}
    for azimuth in AZIMUTHS:
        for _altitude, tag in ALTITUDES:
            expected["default"].add(f"l7-az{azimuth:03d}-{tag}")
            expected["default"].add(f"terrain-az{azimuth:03d}-{tag}")
            expected["default"].add(f"baseline-az{azimuth:03d}-{tag}")
    for preset in PRESETS:
        expected[preset].update(f"rim-{preset}-az{azimuth:03d}-h140" for azimuth in RIM_AZIMUTHS)
    return expected


def load_manifests(folder: Path, profile: dict[str, Any]) -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []
    expected_ids = expected_case_ids()
    for preset, visibility_m in PRESETS.items():
        manifest_path = folder / f"capture-manifest-{preset}.json"
        if not manifest_path.is_file():
            raise RuntimeError(f"missing manifest: {manifest_path}")
        manifest = json.loads(manifest_path.read_text())
        if manifest.get("format") != FORMAT:
            raise RuntimeError(f"{manifest_path}: unexpected format {manifest.get('format')!r}")
        if manifest.get("visibility_preset") != preset or manifest.get("visibility_m") != visibility_m:
            raise RuntimeError(f"{manifest_path}: visibility metadata does not match {preset} ({visibility_m:g} m)")
        if manifest.get("horizon_profile_sha256") != profile.get("sha256"):
            raise RuntimeError(f"{manifest_path}: captured profile SHA-256 does not match committed horizon data")
        entries = manifest.get("cases")
        if not isinstance(entries, list):
            raise RuntimeError(f"{manifest_path}: cases must be a list")
        actual_ids = [str(entry.get("id", "")) for entry in entries]
        if len(actual_ids) != len(set(actual_ids)) or set(actual_ids) != expected_ids[preset]:
            raise RuntimeError(
                f"{manifest_path}: case inventory differs; missing={sorted(expected_ids[preset] - set(actual_ids))}, "
                f"extra={sorted(set(actual_ids) - expected_ids[preset])}"
            )
        for entry in entries:
            case = dict(entry)
            case["manifest"] = manifest_path.name
            cases.append(case)
    if len(cases) != 42:
        raise RuntimeError(f"expected 42 captures, found {len(cases)}")
    return cases


def expected_case_metadata(case_id: str) -> tuple[str, str, int, float, str]:
    if case_id.startswith("rim-"):
        match = re.fullmatch(r"rim-(default|hazy|clear)-az(\d{3})-h140", case_id)
        if not match:
            raise RuntimeError(f"invalid rim case ID: {case_id}")
        preset, azimuth_text = match.groups()
        return "flat-plane", preset, int(azimuth_text), 140.0, "rough-only"
    match = re.fullmatch(r"(l7|terrain|baseline)-az(\d{3})-(h1p7|h30m|h140m)", case_id)
    if not match:
        raise RuntimeError(f"invalid field case ID: {case_id}")
    mode, azimuth_text, tag = match.groups()
    altitude = {height_tag: height for height, height_tag in ALTITUDES}[tag]
    return ("flat-plane" if mode == "baseline" else "polar-hills"), "default", int(azimuth_text), altitude, "field"


def image_metrics(path: Path) -> dict[str, Any]:
    image = Image.open(path).convert("RGB")
    pixels = np.asarray(image, dtype=np.float32)
    if pixels.shape != (720, 1280, 3):
        raise RuntimeError(f"{path.name}: expected 1280×720 RGB, got {image.size}")
    luma = pixels[:, :, 0] * 0.2126 + pixels[:, :, 1] * 0.7152 + pixels[:, :, 2] * 0.0722
    band = luma[310:410, 128:1152]
    p10, p50, p90 = (float(value) for value in np.quantile(band, (0.1, 0.5, 0.9)))
    return {
        "width": 1280,
        "height": 720,
        "horizon_band": {
            "x_px": [128, 1152],
            "y_px": [310, 410],
            "luma_p10": round(p10, 3),
            "luma_p50": round(p50, 3),
            "luma_p90": round(p90, 3),
            "luma_spread_p90_p10": round(p90 - p10, 3),
        },
    }


def rim_step(path: Path, camera_height_m: float = 140.0) -> dict[str, Any]:
    """Measure the full visible fog transition and separately report the flat-plane edge."""
    image = Image.open(path).convert("RGB")
    pixels = np.asarray(image, dtype=np.float32)
    center_strip = pixels[:, 512:768, :]
    row_means = center_strip.mean(axis=1)
    focal_px = 720.0 / (2.0 * math.tan(math.radians(50.0) * 0.5))
    edge_angle = math.atan2(camera_height_m, 20000.0)
    expected_row = 360.0 + focal_px * edge_angle
    y0 = max(0, math.floor(expected_row) - 10)
    y1 = min(719, math.ceil(expected_row) + 10)
    rgb_steps = np.max(np.abs(row_means[y0 + 1 : y1 + 1] - row_means[y0:y1]), axis=1)
    max_index = int(np.argmax(rgb_steps))
    edge_before = int(math.floor(expected_row))
    edge_after = edge_before + 1
    return {
        "center_strip_x_px": [512, 768],
        "search_rows_px": [y0, y1],
        "predicted_plane_edge_row_px": round(expected_row, 3),
        "largest_rgb_step_levels": round(float(rgb_steps[max_index]), 3),
        "largest_rgb_step_rows_px": [y0 + max_index, y0 + max_index + 1],
        "plane_edge_rgb_step_levels": round(float(np.max(np.abs(row_means[edge_after] - row_means[edge_before]))), 3),
        "plane_edge_row_pair_px": [edge_before, edge_after],
    }


def compare_pair(folder: Path, first: dict[str, Any], second: dict[str, Any]) -> dict[str, Any]:
    a = np.asarray(Image.open(folder / str(first["image"])).convert("RGB"), dtype=np.int16)
    b = np.asarray(Image.open(folder / str(second["image"])).convert("RGB"), dtype=np.int16)
    delta = np.abs(a - b)
    pixel_max = delta.max(axis=2)
    return {
        "feature_case": str(first["id"]),
        "baseline_case": str(second["id"]),
        "changed_pixels": int(np.count_nonzero(pixel_max)),
        "changed_pixel_fraction": round(float(np.count_nonzero(pixel_max)) / float(pixel_max.size), 6),
        "mean_abs_rgb_delta": round(float(delta.mean()), 6),
        "p99_max_channel_delta": round(float(np.quantile(pixel_max, 0.99)), 3),
    }


def verify_repeat(folder: Path, profile: dict[str, Any]) -> dict[str, Any]:
    cases = load_manifests(folder, profile)
    by_id = {str(case["id"]): case for case in cases}
    details: dict[str, Any] = {}
    for case in cases:
        case_id = str(case["id"])
        mode, preset, azimuth, altitude, scope = expected_case_metadata(case_id)
        if case.get("terrain_mode") != mode or case.get("visibility_preset") != preset:
            raise RuntimeError(f"{case_id}: terrain mode or visibility preset metadata mismatch")
        if int(case.get("azimuth_deg", -1)) != azimuth or abs(float(case.get("camera_height_m", -1)) - altitude) > 1e-6:
            raise RuntimeError(f"{case_id}: camera azimuth or height metadata mismatch")
        if abs(float(case.get("elevation_deg", 999.0))) > 1e-9:
            raise RuntimeError(f"{case_id}: captures must be level (elevation 0°)")
        if case.get("visual_scope") != scope or abs(float(case.get("camera_fov_deg", -1)) - 50.0) > 1e-6:
            raise RuntimeError(f"{case_id}: visual scope or camera FOV metadata mismatch")
        if case.get("visibility_m") != PRESETS[preset]:
            raise RuntimeError(f"{case_id}: rendered visibility metadata mismatch")
        if int(case.get("near_tree_instances", -1)) != 480 or int(case.get("far_tree_instances", -1)) != 1200:
            raise RuntimeError(f"{case_id}: expected 480 near + 1,200 far tree instances in the shared field")
        expected_tree_population = "hidden" if case_id.startswith("rim-") else (
            "near+far" if case_id.startswith("l7-") else "near-only"
        )
        expected_visible_trees = 1680 if expected_tree_population == "near+far" else 480 if expected_tree_population == "near-only" else 0
        if case.get("tree_population") != expected_tree_population or int(case.get("visible_tree_instances", -1)) != expected_visible_trees:
            raise RuntimeError(f"{case_id}: tree population metadata mismatch")
        if type(case.get("draw_calls")) is not int or int(case["draw_calls"]) <= 0:
            raise RuntimeError(f"{case_id}: missing render draw-call count")
        if type(case.get("primitives")) is not int or int(case["primitives"]) <= 0:
            raise RuntimeError(f"{case_id}: missing render primitive count")
        if type(case.get("objects")) is not int or int(case["objects"]) <= 0:
            raise RuntimeError(f"{case_id}: missing render object count")

        image_name = str(case.get("image", ""))
        if image_name != f"capture-{case_id}.png":
            raise RuntimeError(f"{case_id}: manifest image name mismatch")
        image_path = folder / image_name
        if not image_path.is_file():
            raise RuntimeError(f"{case_id}: missing PNG {image_path}")
        detail = image_metrics(image_path)
        detail["sha256"] = sha256_file(image_path)
        detail["draw_calls"] = case["draw_calls"]
        detail["primitives"] = case["primitives"]
        detail["objects"] = case["objects"]
        detail["visibility_m"] = case["visibility_m"]
        detail["terrain_mode"] = mode
        details[case_id] = detail

    pairs: list[dict[str, Any]] = []
    for azimuth in AZIMUTHS:
        for _altitude, tag in ALTITUDES:
            baseline_id = f"baseline-az{azimuth:03d}-{tag}"
            baseline_case = by_id[baseline_id]
            for comparison, feature_id in (("combined_l7", f"l7-az{azimuth:03d}-{tag}"),
                                           ("terrain_only", f"terrain-az{azimuth:03d}-{tag}")):
                feature_case = by_id[feature_id]
                for key in ("world_id", "visibility_m", "azimuth_deg", "elevation_deg", "camera_height_m", "camera_fov_deg"):
                    if feature_case.get(key) != baseline_case.get(key):
                        raise RuntimeError(f"{feature_id}/{baseline_id}: A/B field mismatch in {key}")
                pair = compare_pair(folder, feature_case, baseline_case)
                pair["comparison"] = comparison
                pair["feature_tree_population"] = feature_case["tree_population"]
                pair["baseline_tree_population"] = baseline_case["tree_population"]
                pairs.append(pair)

    rim_results: list[dict[str, Any]] = []
    corridor_params = profile.get("generator", {}).get("params", {}).get("corridors", {})
    centers = corridor_params.get("centers_deg", [])
    half_width = corridor_params.get("flat_half_width_deg")
    if set(centers) != set(RIM_AZIMUTHS) or half_width != 20:
        raise RuntimeError("rim measurement azimuths are not inside the committed exact-zero hill corridors")
    for preset in PRESETS:
        for azimuth in RIM_AZIMUTHS:
            case_id = f"rim-{preset}-az{azimuth:03d}-h140"
            case = by_id[case_id]
            if case.get("corridor_center_deg") != azimuth or case.get("corridor_half_width_deg") != 20.0:
                raise RuntimeError(f"{case_id}: missing flat-corridor capture evidence")
            measurement = rim_step(folder / str(case["image"]))
            measurement.update({"case_id": case_id, "visibility_preset": preset, "visibility_m": PRESETS[preset]})
            rim_results.append(measurement)

    return {
        "capture_count": len(cases),
        "cases": details,
        "ab_pairs": pairs,
        "flat_corridor_rim": rim_results,
        "draw_calls": {
            "min": min(int(case["draw_calls"]) for case in cases),
            "max": max(int(case["draw_calls"]) for case in cases),
            "mean": round(sum(int(case["draw_calls"]) for case in cases) / len(cases), 3),
        },
        "primitives": {
            "min": min(int(case["primitives"]) for case in cases),
            "max": max(int(case["primitives"]) for case in cases),
            "mean": round(sum(int(case["primitives"]) for case in cases) / len(cases), 3),
        },
        "objects": {
            "min": min(int(case["objects"]) for case in cases),
            "max": max(int(case["objects"]) for case in cases),
            "mean": round(sum(int(case["objects"]) for case in cases) / len(cases), 3),
        },
        "horizon_band_luma_spread": {
            "min": round(min(float(detail["horizon_band"]["luma_spread_p90_p10"]) for detail in details.values()), 3),
            "max": round(max(float(detail["horizon_band"]["luma_spread_p90_p10"]) for detail in details.values()), 3),
            "mean": round(sum(float(detail["horizon_band"]["luma_spread_p90_p10"]) for detail in details.values()) / len(details), 3),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "app", help="Godot project directory")
    parser.add_argument("--godot", type=Path, help="pinned Godot 4.7 executable; defaults to app/get-godot.sh")
    parser.add_argument("--out", type=Path, default=Path("/tmp/l7-horizon"), help="capture output directory")
    args = parser.parse_args()

    app = args.app.resolve()
    out = args.out.resolve()
    if not app.is_dir():
        parser.error(f"missing app directory: {app}")
    if args.godot:
        godot = args.godot.resolve()
    else:
        godot_text = subprocess.run([str(app / "get-godot.sh")], check=True, capture_output=True, text=True).stdout.strip()
        godot = Path(godot_text).resolve()
    if not godot.is_file():
        parser.error(f"missing Godot executable: {godot}")
    if shutil.which("xvfb-run") is None:
        parser.error("xvfb-run is required for the real-render capture")

    profile = json.loads((app / "data/fields/horizon.json").read_text())
    if profile.get("format") != "openrc-horizon-profile v1":
        parser.error("invalid committed horizon profile")
    out.mkdir(parents=True, exist_ok=True)
    (out / "capture-summary.json").unlink(missing_ok=True)
    for child in (out / "repeat-1", out / "repeat-2"):
        if child.exists():
            shutil.rmtree(child)
        child.mkdir(parents=True)
    env = dict(os.environ, LP_NUM_THREADS="1", OPENRC_SCENERY="off", PYTHONDONTWRITEBYTECODE="1")

    checked_run([str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy", "--import"], out / "capture-import.log", env)
    render_base = [
        "xvfb-run", "-a", "-s", "-screen 0 1280x720x24", str(godot), "--path", str(app),
        "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--script", str(CAPTURE_SCRIPT), "--",
    ]
    repeat_results: list[dict[str, Any]] = []
    for repeat in (1, 2):
        folder = out / f"repeat-{repeat}"
        for preset in PRESETS:
            checked_run(
                [*render_base, f"--out={folder}", f"--visibility={preset}", "--scenery=off"],
                out / f"repeat-{repeat}-{preset}.log",
                env,
            )
        repeat_results.append(verify_repeat(folder, profile))

    expected_count = 42
    repeat1, repeat2 = out / "repeat-1", out / "repeat-2"
    image_names = sorted(path.name for path in repeat1.glob("capture-*.png"))
    if len(image_names) != expected_count or image_names != sorted(path.name for path in repeat2.glob("capture-*.png")):
        raise RuntimeError(f"repeat image inventory mismatch: {len(image_names)} first-run PNGs")
    mismatched_images = [name for name in image_names if (repeat1 / name).read_bytes() != (repeat2 / name).read_bytes()]
    manifest_names = sorted(path.name for path in repeat1.glob("capture-manifest-*.json"))
    mismatched_manifests = [
        name for name in manifest_names if (repeat1 / name).read_bytes() != (repeat2 / name).read_bytes()
    ]
    if mismatched_images or mismatched_manifests:
        raise RuntimeError(
            f"repeat mismatch: images={mismatched_images[:5]}, manifests={mismatched_manifests}"
        )

    rim_steps = [measurement["largest_rgb_step_levels"] for measurement in repeat_results[0]["flat_corridor_rim"]]
    failing_rims = [measurement for measurement in repeat_results[0]["flat_corridor_rim"]
                    if float(measurement["largest_rgb_step_levels"]) > 4.0]
    summary = {
        "format": SUMMARY_FORMAT,
        "complete": not failing_rims,
        "capture_set": {
            "views_per_repeat": expected_count,
            "two_processes_byte_identical": not mismatched_images and not mismatched_manifests,
            "combined_l7_hills_and_trees": 12,
            "terrain_only_hills_with_near_trees": 12,
            "flat_plane_near_tree_baseline": 12,
            "flat_corridor_rim": 6,
            "visibility_m": PRESETS,
        },
        "horizon_profile_sha256": profile["sha256"],
        "ab_contract": {
            "combined_l7": "polar hills plus 480 near and 1,200 far tree instances vs flat plane plus the same 480 near instances",
            "terrain_only": "polar hills plus 480 near tree instances vs flat plane plus the same 480 near instances",
            "same_field_and_camera": True,
        },
        "repeatability": {
            "images_compared": len(image_names),
            "image_mismatches": mismatched_images,
            "manifests_compared": len(manifest_names),
            "manifest_mismatches": mismatched_manifests,
        },
        "repeat_1": repeat_results[0],
        "repeat_2": repeat_results[1],
        "rim_limit_rgb_levels": 4.0,
        "rim_gate": "maximum row-to-row RGB step within 10 pixels of the predicted flat-plane edge, center strip x=512..767; includes the inner fog transition and outer plane edge",
        "rim_failures": failing_rims,
        "rim_iteration_findings": [
            {
                "clear_rim_start_end_m": [16000, 20000],
                "largest_horizon_band_step_levels": {"az090": 12.355, "az270": 12.305},
                "largest_horizon_band_step_rows_px": {"az090": [365, 366], "az270": [365, 366]},
                "finding": "clear outer plane-edge closure exceeded the 4-level gate",
            },
            {
                "clear_rim_start_end_m": [8000, 20000],
                "largest_horizon_band_step_levels": {"az090": 11.938, "az270": 11.844},
                "largest_horizon_band_step_rows_px": {"az090": [365, 366], "az270": [365, 366]},
                "finding": "clear outer plane-edge closure still exceeded the 4-level gate",
            },
            {
                "clear_rim_start_end_m": [4000, 16000],
                "largest_horizon_band_step_levels": {"az090": 12.195, "az270": 12.156},
                "largest_horizon_band_step_rows_px": {"az090": [368, 369], "az270": [368, 369]},
                "plane_edge_rgb_step_levels": {"az090": 0.430, "az270": 0.074},
                "finding": "outer plane edge passed, but the near-horizon inner fog transition remained a visible band and failed the full-band gate",
            },
        ],
    }
    summary_path = out / "capture-summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    if failing_rims:
        print("FAIL: a flat-corridor horizon/rim step exceeds 4 RGB levels")
        for item in failing_rims:
            print(f"  {item['case_id']}: {item['largest_rgb_step_levels']:.3f}")
        print(f"Report: {summary_path}")
        return 1
    print(
        f"L7 horizon: 42 captures in each of 2 processes, byte-identical; "
        f"draw calls {repeat_results[0]['draw_calls']['min']}–{repeat_results[0]['draw_calls']['max']}; "
        f"horizon-band luma spread {repeat_results[0]['horizon_band_luma_spread']['min']:.1f}–"
        f"{repeat_results[0]['horizon_band_luma_spread']['max']:.1f}; "
        f"flat-corridor rim max {max(rim_steps):.3f}/4 RGB levels"
    )
    print(f"Report: {summary_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
