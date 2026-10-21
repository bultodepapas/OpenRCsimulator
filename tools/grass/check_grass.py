#!/usr/bin/env python3
"""Capture and verify L11a grass evidence on the production Compatibility renderer."""

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
CAPTURE_SCRIPT = Path(__file__).with_name("capture_grass.gd")
FORMAT = "openrc-l11a-grass-capture v3"
SUMMARY_FORMAT = "openrc-l11a-grass-review v3"
ANIMATION_ISOLATION_PROTOCOL = "global-pinned-local-grass-inputs-v1"
WIDTH = 1280
HEIGHT = 720
FOV_DEG = 50.0
WARMUP_FRAMES = 12
SETTLE_FRAMES = 3
DRAW_BUDGET = 5
PRIMITIVE_BUDGET = 100_000
SEAM_PERCENT_BUDGET = 3.0
PILOT_AZIMUTHS = (0, 90, 180, 270)
PILOT_ELEVATIONS = (-10, -25)
STANDARD_SCENARIOS = tuple(
    f"pilot-az{azimuth:03d}-el{abs(elevation):02d}"
    for elevation in PILOT_ELEVATIONS
    for azimuth in PILOT_AZIMUTHS
) + ("raised-low-pass", "near-runway", "band-25-35m", "fade-camera-35m")
WIND_CASES = ("windless-t1", "wind-on-t0", "wind-on-t1", "wind-on-t1024", "windless-t0-repeat")
SCENERY_SCENARIO = "scenery-runway-edge"
IMPORTED_GRASS_IDS = ("grass_common_short", "grass_common_tall", "grass_wispy_tall")
STATIC_IMPORTED_GRASS_COUNTS = {"grass_common_short": 67, "grass_common_tall": 42, "grass_wispy_tall": 41}
ENHANCED_IMPORTED_GRASS_COUNTS = {"grass_common_short": 100, "grass_common_tall": 30, "grass_wispy_tall": 20}
IMPORTED_GRASS_TOTAL = 150
ENHANCED_IMPORTED_GRASS_TRIANGLES = 37_720
IMPORTED_GRASS_TRIANGLE_BUDGET = 50_000
IMPORTED_GRASS_SHADER_PATH = "res://scenery/imported_grass.gdshader"
IMPORTED_FLOWER_IDS = ("clover_1", "flower_4_group", "polyhaven_flower_empodium_a")
RUNTIME_SUFFIXES = {
    ".cfg", ".gd", ".gdshader", ".gdshaderinc", ".gdextension", ".godot", ".gltf", ".glb",
    ".import", ".json", ".mp3", ".ogg", ".po", ".png", ".res", ".svg", ".tscn", ".tres",
    ".ttf", ".otf", ".wav", ".webp", ".jpg", ".jpeg",
}
EXCLUDED_DIRS = {".git", ".godot", ".tools", "__pycache__", "build", "captures", "dist", "tests"}
SCREEN = "-screen 0 1280x720x24"


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_map_hash(entries: dict[str, str]) -> str:
    return sha256_bytes(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def source_snapshot(project: Path) -> dict[str, Any]:
    app_files: dict[str, str] = {}
    for current, directories, filenames in os.walk(project):
        directories[:] = sorted(name for name in directories if name not in EXCLUDED_DIRS)
        current_path = Path(current)
        for filename in sorted(filenames):
            path = current_path / filename
            if path.suffix.lower() not in RUNTIME_SUFFIXES:
                continue
            relative = path.relative_to(project).as_posix()
            app_files[relative] = sha256_file(path)
    producers = {
        path.resolve().relative_to(ROOT).as_posix(): sha256_file(path.resolve())
        for path in (CAPTURE_SCRIPT, Path(__file__))
    }
    return {
        "project": str(project),
        "app_files": app_files,
        "app_file_map_sha256": canonical_map_hash(app_files),
        "producer_files": producers,
        "producer_file_map_sha256": canonical_map_hash(producers),
    }


def source_guard_report(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    same_app = before["app_files"] == after["app_files"]
    same_producers = before["producer_files"] == after["producer_files"]
    if not same_app or not same_producers:
        changed_app = sorted(
            key for key in set(before["app_files"]) | set(after["app_files"])
            if before["app_files"].get(key) != after["app_files"].get(key)
        )
        changed_producers = sorted(
            key for key in set(before["producer_files"]) | set(after["producer_files"])
            if before["producer_files"].get(key) != after["producer_files"].get(key)
        )
        raise RuntimeError(
            f"sources changed during capture for {before['project']}: "
            f"app={changed_app[:8]}, producers={changed_producers}"
        )
    return {
        "project": before["project"],
        "runtime_file_count": len(before["app_files"]),
        "runtime_files_sha256": before["app_files"],
        "runtime_file_map_sha256": before["app_file_map_sha256"],
        "producer_files_sha256": before["producer_files"],
        "producer_file_map_sha256": before["producer_file_map_sha256"],
        "unchanged_during_capture": True,
    }


def checked_run(command: list[str], log_path: Path, env: dict[str, str], timeout_s: int = 240) -> None:
    with log_path.open("w") as output:
        result = subprocess.run(
            ["timeout", "--kill-after=5", str(timeout_s), *command],
            stdout=output,
            stderr=subprocess.STDOUT,
            env=env,
            check=False,
        )
    text = re.sub(r"\x1b\[[0-9;]*m", "", log_path.read_text(errors="replace"))
    engine_error = re.search(r"^\s*(?:(?:SCRIPT|SHADER)\s+)?ERROR:", text, re.M)
    if result.returncode or engine_error:
        raise RuntimeError(f"engine capture failed ({result.returncode}) or logged an error: {log_path}")


def expected_ids(mode: str, material_mode: str | None = None) -> set[str]:
    if mode == "baseline":
        return {f"{scenario}-grass-off" for scenario in STANDARD_SCENARIOS}
    if mode == "candidate":
        return {f"{scenario}-grass-{state}" for scenario in STANDARD_SCENARIOS for state in ("off", "on")} | set(WIND_CASES)
    if mode == "scenery":
        result = {f"{SCENERY_SCENARIO}-grass-{state}" for state in ("off", "on")}
        if material_mode == "qualified_wind":
            return result | set(WIND_CASES)
        if material_mode in (None, "static_baseline"):
            return result
        raise RuntimeError(f"unsupported imported grass material mode {material_mode!r}")
    raise RuntimeError(f"unknown mode {mode}")


def image_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        pixels = np.asarray(image.convert("RGB"), dtype=np.uint8)
    if pixels.shape != (HEIGHT, WIDTH, 3):
        raise RuntimeError(f"{path.name}: expected {WIDTH}×{HEIGHT} RGB, got {pixels.shape[1]}×{pixels.shape[0]}")
    return pixels


def image_digest(path: Path) -> str:
    return sha256_file(path)


def projected_ground_masks(case: dict[str, Any], pilot_north: float, pilot_east: float) -> tuple[np.ndarray, np.ndarray]:
    """Return screen masks for the 0–36 m grass envelope and the L11a 25–35 m comparison band."""
    azimuth = math.radians(float(case["azimuth_deg"]))
    elevation = math.radians(float(case["elevation_deg"]))
    forward = np.array(
        [math.sin(azimuth) * math.cos(elevation), math.sin(elevation), -math.cos(azimuth) * math.cos(elevation)],
        dtype=np.float64,
    )
    right = np.cross(forward, np.array([0.0, 1.0, 0.0], dtype=np.float64))
    right /= np.linalg.norm(right)
    camera_up = np.cross(right, forward)
    camera_up /= np.linalg.norm(camera_up)

    rows = np.arange(HEIGHT, dtype=np.float64) + 0.5
    cols = np.arange(WIDTH, dtype=np.float64) + 0.5
    tangent = math.tan(math.radians(FOV_DEG) * 0.5)
    x = (cols - WIDTH * 0.5) / (HEIGHT * 0.5) * tangent
    y = (HEIGHT * 0.5 - rows) / (HEIGHT * 0.5) * tangent
    ray_x = forward[0] + x[np.newaxis, :] * right[0] + y[:, np.newaxis] * camera_up[0]
    ray_y = forward[1] + x[np.newaxis, :] * right[1] + y[:, np.newaxis] * camera_up[1]
    ray_z = forward[2] + x[np.newaxis, :] * right[2] + y[:, np.newaxis] * camera_up[2]

    camera_north = float(case["camera_north_m"])
    camera_east = float(case["camera_east_m"])
    camera_height = float(case["camera_height_m"])
    down = ray_y < -1e-9
    distance_along = np.zeros((HEIGHT, WIDTH), dtype=np.float64)
    distance_along[down] = camera_height / -ray_y[down]
    hit_north = camera_north - distance_along * ray_z
    hit_east = camera_east + distance_along * ray_x
    radius = np.hypot(hit_north - pilot_north, hit_east - pilot_east)
    valid = down & (distance_along > 0.0) & np.isfinite(radius)
    footprint = valid & (radius <= 36.0)
    band = valid & (radius >= 25.0) & (radius <= 35.0)
    return footprint, band


def compare_images(folder_a: Path, case_a: dict[str, Any], folder_b: Path, case_b: dict[str, Any]) -> dict[str, Any]:
    a = image_rgb(folder_a / str(case_a["image"]))
    b = image_rgb(folder_b / str(case_b["image"]))
    delta = np.abs(a.astype(np.int16) - b.astype(np.int16))
    max_delta = delta.max(axis=2)
    changed = max_delta != 0
    return {
        "changed_pixels": int(np.count_nonzero(changed)),
        "changed_pixel_fraction": float(np.count_nonzero(changed) / changed.size),
        "mean_abs_rgb_delta": float(delta.mean()),
        "p99_max_channel_delta": float(np.quantile(max_delta, 0.99)),
    }


def paired_case_metrics(folder: Path, off: dict[str, Any], on: dict[str, Any], pilot_north: float,
                        pilot_east: float) -> dict[str, Any]:
    off_pixels = image_rgb(folder / str(off["image"]))
    on_pixels = image_rgb(folder / str(on["image"]))
    delta = np.abs(on_pixels.astype(np.int16) - off_pixels.astype(np.int16))
    changed = delta.max(axis=2) != 0
    footprint, band = projected_ground_masks(on, pilot_north, pilot_east)
    outside = changed & ~footprint
    band_delta = delta[band].astype(np.float64)
    if band_delta.size:
        baseline_mean = off_pixels[band].astype(np.float64).mean(axis=0)
        mean_abs_by_channel = band_delta.mean(axis=0)
        percent_by_channel = mean_abs_by_channel / np.maximum(baseline_mean, 1.0) * 100.0
        max_percent = float(percent_by_channel.max())
    else:
        baseline_mean = np.zeros(3, dtype=np.float64)
        mean_abs_by_channel = np.zeros(3, dtype=np.float64)
        percent_by_channel = np.zeros(3, dtype=np.float64)
        max_percent = 0.0
    return {
        "scenario_id": str(on["scenario_id"]),
        "grass_off_sha256": image_digest(folder / str(off["image"])),
        "grass_on_sha256": image_digest(folder / str(on["image"])),
        "draw_calls": {"off": int(off["draw_calls"]), "on": int(on["draw_calls"]),
                       "delta": int(on["draw_calls"]) - int(off["draw_calls"])},
        "primitives": {"off": int(off["primitives"]), "on": int(on["primitives"]),
                       "delta": int(on["primitives"]) - int(off["primitives"])},
        "objects": {"off": int(off["objects"]), "on": int(on["objects"]),
                    "delta": int(on["objects"]) - int(off["objects"])},
        "changed_pixels": int(np.count_nonzero(changed)),
        "changed_pixels_outside_projected_grass_footprint": int(np.count_nonzero(outside)),
        "projected_grass_footprint_pixels": int(np.count_nonzero(footprint)),
        "projected_seam_band_pixels": int(np.count_nonzero(band)),
        "seam_band_mean_abs_rgb_delta": [round(float(value), 6) for value in mean_abs_by_channel],
        "seam_band_baseline_rgb_mean": [round(float(value), 6) for value in baseline_mean],
        "seam_band_mean_abs_percent_of_baseline": [round(float(value), 6) for value in percent_by_channel],
        "seam_band_max_channel_percent": round(max_percent, 6),
    }


def load_run(folder: Path, mode: str) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    manifest_path = folder / "capture-manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"missing capture manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("format") != FORMAT or manifest.get("mode") != mode or manifest.get("smoke") is not False:
        raise RuntimeError(f"{manifest_path}: format, mode or smoke metadata mismatch")
    if manifest.get("field") != "res://data/fields/default.json":
        raise RuntimeError(f"{manifest_path}: capture did not use the production default field")
    if manifest.get("viewport") != {"width": WIDTH, "height": HEIGHT}:
        raise RuntimeError(f"{manifest_path}: viewport must be {WIDTH}×{HEIGHT}")
    if not isinstance(manifest.get("renderer"), str) or not manifest["renderer"]:
        raise RuntimeError(f"{manifest_path}: missing Compatibility renderer metadata")
    expected_scenery = mode == "scenery"
    if manifest.get("scenery_on") is not expected_scenery:
        raise RuntimeError(f"{manifest_path}: scenery switch metadata mismatch")
    render_setup = manifest.get("render_setup", {})
    expected_warmup_scenario = SCENERY_SCENARIO if mode == "scenery" else STANDARD_SCENARIOS[0]
    if (
        render_setup.get("warmup_frames") != WARMUP_FRAMES
        or render_setup.get("warmup_scenario") != expected_warmup_scenario
        or render_setup.get("warmup_near_grass_visible") is not (mode != "baseline")
        or render_setup.get("warmup_shader_clock") != 0.0
        or render_setup.get("warmup_wind_vec") != [0.0, 0.0, 0.0]
        or render_setup.get("settle_frames_after_camera_pose") != SETTLE_FRAMES
        or render_setup.get("camera_physics_interpolation") != "off"
    ):
        raise RuntimeError(f"{manifest_path}: deterministic renderer warmup/camera setup mismatch")
    animation = manifest.get("animation_isolation", {})
    if (
        animation.get("protocol") != ANIMATION_ISOLATION_PROTOCOL
        or animation.get("global_shader_inputs") != {"sim_clock": 0.0, "wind_vec": [0.0, 0.0, 0.0]}
        or animation.get("node_geometry_visibility_unchanged") is not True
        or animation.get("source_shader_identity_qualified_before_clone") is not True
    ):
        raise RuntimeError(f"{manifest_path}: missing the global-clock/local-grass isolation contract")
    local_shader_sources = animation.get("near_grass_shader_sources")
    if not isinstance(local_shader_sources, list):
        raise RuntimeError(f"{manifest_path}: NearGrass local shader source identities must be a list")
    if mode == "baseline":
        if manifest.get("grass") != {"present": False}:
            raise RuntimeError(f"{manifest_path}: baseline mode must record the absent NearGrass child")
        if manifest.get("near_grass_material_mode") != "not_present":
            raise RuntimeError(f"{manifest_path}: no-grass baseline material scope mismatch")
        material_mode = "not_present"
        grass = {}
    else:
        grass = manifest.get("grass", {})
        if grass.get("present") is not True or grass.get("node_count") != 1:
            raise RuntimeError(f"{manifest_path}: missing or duplicated production NearGrass")
        material_mode = grass.get("material_mode")
        if manifest.get("near_grass_material_mode") != material_mode:
            raise RuntimeError(f"{manifest_path}: top-level and NearGrass material scopes differ")
        bounds = grass.get("observed_radius_m", {})
        if float(bounds.get("max", 1e9)) > 30.001:
            raise RuntimeError(f"{manifest_path}: grass exceeds its 30 m pilot radius")
        if grass.get("runway_clumps") != 0 or grass.get("casts_shadows") is not False:
            raise RuntimeError(f"{manifest_path}: grass runway exclusion or no-shadow contract failed")
        if mode == "candidate":
            if material_mode != "legacy_procedural":
                raise RuntimeError(f"{manifest_path}: candidate capture must identify the legacy procedural material scope")
            if grass.get("implementation") != "legacy_shader_material":
                raise RuntimeError(f"{manifest_path}: candidate mode must capture the legacy shader-grass path")
            if not 1 <= int(grass.get("multimesh_chunks", 0)) <= 4:
                raise RuntimeError(f"{manifest_path}: legacy grass must fit in at most four MultiMesh chunks")
            if not 1 <= int(grass.get("clumps", 0)) <= 6000:
                raise RuntimeError(f"{manifest_path}: legacy grass count must be in 1–6,000")
            if grass.get("triangles_per_clump") != 7 or grass.get("fixed_root_geometry_and_shader_contract") is not True:
                raise RuntimeError(f"{manifest_path}: legacy clump geometry or fixed-root shader contract failed")
            fade = grass.get("fade", {})
            if (
                grass.get("opaque") is not True
                or float(fade.get("start_m", math.nan)) != 22.0
                or float(fade.get("end_m", math.nan)) != 30.0
                or fade.get("uses_camera_and_pilot") is not True
                or fade.get("source") not in {
                    "material overrides",
                    "compiled ShaderMaterial parameter defaults",
                    "material overrides with compiled defaults",
                }
            ):
                raise RuntimeError(f"{manifest_path}: legacy grass opaque mode or 22–30 m fade contract failed")
        elif mode == "scenery":
            if grass.get("implementation") != "imported_source_meshes":
                raise RuntimeError(f"{manifest_path}: scenery mode must capture the imported source-grass path")
            if grass.get("source_ids") != list(IMPORTED_GRASS_IDS):
                raise RuntimeError(f"{manifest_path}: imported grass source IDs mismatch")
            if material_mode == "static_baseline":
                expected_grass_counts = STATIC_IMPORTED_GRASS_COUNTS
            elif material_mode == "qualified_wind":
                expected_grass_counts = ENHANCED_IMPORTED_GRASS_COUNTS
            else:
                raise RuntimeError(f"{manifest_path}: imported grass material mode must be static_baseline or qualified_wind")
            if grass.get("source_batches") != expected_grass_counts:
                raise RuntimeError(f"{manifest_path}: imported grass source batch counts mismatch")
            if grass.get("multimesh_chunks") != len(IMPORTED_GRASS_IDS) or grass.get("clumps") != IMPORTED_GRASS_TOTAL:
                raise RuntimeError(f"{manifest_path}: imported grass must contain exactly 150 clumps in three batches")
            triangle_count = grass.get("source_triangles")
            triangles_match_profile = (
                triangle_count == ENHANCED_IMPORTED_GRASS_TRIANGLES
                if material_mode == "qualified_wind"
                else type(triangle_count) is int and 0 < triangle_count <= IMPORTED_GRASS_TRIANGLE_BUDGET
            )
            if (
                type(triangle_count) is not int
                or not triangles_match_profile
                or triangle_count > IMPORTED_GRASS_TRIANGLE_BUDGET
                or grass.get("source_geometry_preserved") is not True
                or grass.get("source_material_parameters_matched") is not True
                or grass.get("textured_surfaces") != len(IMPORTED_GRASS_IDS)
                or grass.get("per_pixel_lit_surfaces") != len(IMPORTED_GRASS_IDS)
            ):
                raise RuntimeError(f"{manifest_path}: imported grass changed source geometry/material data or failed its selected triangle profile/budget")
            if material_mode == "static_baseline":
                if (
                    grass.get("material_shader_path") != ""
                    or grass.get("material_shader_sha256") != ""
                    or grass.get("material_contract") != "static baseline: exact textured per-pixel-lit StandardMaterial3D source surfaces"
                    or grass.get("wind_animation") != "static baseline source materials; no imported-grass wind adapter"
                    or grass.get("wind_probe_cases") is not False
                ):
                    raise RuntimeError(f"{manifest_path}: static imported-material baseline metadata mismatch")
            elif material_mode == "qualified_wind":
                if (
                    grass.get("material_shader_path") != IMPORTED_GRASS_SHADER_PATH
                    or not isinstance(grass.get("material_shader_sha256"), str)
                    or re.fullmatch(r"[0-9a-f]{64}", grass["material_shader_sha256"]) is None
                    or grass.get("material_contract") != "qualified imported grass shader; source albedo, UV, vertex-color, roughness, metallic and specular parameters matched"
                    or grass.get("wind_animation") != "qualified imported shader; ShaderClock wind probes are captured"
                    or grass.get("wind_probe_cases") is not True
                ):
                    raise RuntimeError(f"{manifest_path}: qualified imported-wind material metadata mismatch")
            else:
                raise RuntimeError(f"{manifest_path}: imported grass material mode must be static_baseline or qualified_wind")
        else:
            raise RuntimeError(f"{manifest_path}: unsupported grass capture mode {mode!r}")

    expected_local_shader_path = ""
    expected_local_shader_hash = ""
    if mode == "candidate":
        expected_local_shader_path = "res://render/near_grass.gdshader"
        expected_local_shader_hash = str(grass.get("shader_sha256", ""))
    elif mode == "scenery" and material_mode == "qualified_wind":
        expected_local_shader_path = IMPORTED_GRASS_SHADER_PATH
        expected_local_shader_hash = str(grass.get("material_shader_sha256", ""))
    source_paths: list[str] = []
    allowed_replacements = {
        "global uniform float sim_clock;",
        "global uniform vec3 wind_vec;",
    }
    for source in local_shader_sources:
        if not isinstance(source, dict):
            raise RuntimeError(f"{manifest_path}: malformed NearGrass source identity")
        source_path = source.get("path")
        identity = source.get("identity")
        if not isinstance(source_path, str) or not isinstance(identity, dict):
            raise RuntimeError(f"{manifest_path}: malformed NearGrass source identity")
        source_hash = identity.get("source_sha256")
        replacements = identity.get("replaced_declarations")
        if (
            re.fullmatch(r"res://[^\\]+", source_path) is None
            or not isinstance(source_hash, str)
            or re.fullmatch(r"[0-9a-f]{64}", source_hash) is None
            or not isinstance(replacements, list)
            or not replacements
            or any(item not in allowed_replacements for item in replacements)
            or len(replacements) != len(set(replacements))
        ):
            raise RuntimeError(f"{manifest_path}: invalid NearGrass source path, hash or localized declaration list")
        source_paths.append(source_path)
    if source_paths != sorted(set(source_paths)):
        raise RuntimeError(f"{manifest_path}: NearGrass shader sources must be sorted and unique")
    local_binding_count = animation.get("near_grass_material_bindings_overridden")
    if type(local_binding_count) is not int or local_binding_count < 0:
        raise RuntimeError(f"{manifest_path}: invalid NearGrass localized material count")
    if expected_local_shader_path:
        matching_sources = [source for source in local_shader_sources if source.get("path") == expected_local_shader_path]
        if (
            len(local_shader_sources) != 1
            or len(matching_sources) != 1
            or matching_sources[0]["identity"].get("source_sha256") != expected_local_shader_hash
            or set(matching_sources[0]["identity"].get("replaced_declarations", [])) != allowed_replacements
            or local_binding_count <= 0
        ):
            raise RuntimeError(f"{manifest_path}: NearGrass localization does not match its qualified source shader")
    elif local_shader_sources or local_binding_count != 0:
        raise RuntimeError(f"{manifest_path}: static or absent NearGrass must not have a localized shader")
    if expected_scenery:
        flowers = manifest.get("flowers", {})
        flower_counts = flowers.get("asset_counts", {})
        flower_names = flowers.get("names", [])
        observed_ids = sorted({name.split("_Part_", 1)[0] for name in flower_names if isinstance(name, str)})
        if (
            flowers.get("source_ids") != list(IMPORTED_FLOWER_IDS)
            or observed_ids != list(IMPORTED_FLOWER_IDS)
            or set(flower_counts) != set(IMPORTED_FLOWER_IDS)
            or not all(type(flower_counts.get(asset_id)) is int and flower_counts[asset_id] > 0 for asset_id in IMPORTED_FLOWER_IDS)
            or type(flowers.get("count")) is not int
            or sum(flower_counts.values()) != flowers["count"]
            or not flower_names
            or len(flower_names) != len(set(flower_names))
            or flowers.get("unique_names") is not True
        ):
            raise RuntimeError(f"{manifest_path}: imported botanical flower source inventory is missing or duplicated")
    elif manifest.get("flowers", {}).get("count", 0) != 0:
        raise RuntimeError(f"{manifest_path}: scenery-off run unexpectedly contains flower nodes")

    cases_node = manifest.get("cases")
    if not isinstance(cases_node, list):
        raise RuntimeError(f"{manifest_path}: cases must be a list")
    ids = [str(case.get("id", "")) for case in cases_node]
    expected = expected_ids(mode, material_mode if mode == "scenery" else None)
    if len(ids) != len(set(ids)) or set(ids) != expected:
        raise RuntimeError(
            f"{manifest_path}: case inventory mismatch; missing={sorted(expected - set(ids))}, "
            f"extra={sorted(set(ids) - expected)}"
        )
    by_id: dict[str, dict[str, Any]] = {}
    for raw in cases_node:
        case = dict(raw)
        case_id = str(case["id"])
        image_name = str(case.get("image", ""))
        if image_name != f"capture-{case_id}.png" or Path(image_name).name != image_name:
            raise RuntimeError(f"{case_id}: invalid capture image path")
        image_path = folder / image_name
        if not image_path.is_file():
            raise RuntimeError(f"{case_id}: missing image {image_path}")
        image_rgb(image_path)
        for key in ("draw_calls", "primitives", "objects"):
            if type(case.get(key)) is not int or int(case[key]) < 0:
                raise RuntimeError(f"{case_id}: missing/invalid {key} telemetry")
        if case.get("camera_fov_deg") != FOV_DEG:
            raise RuntimeError(f"{case_id}: camera FOV mismatch")
        if not math.isfinite(float(case.get("shader_time_s", math.nan))) or not math.isfinite(float(case.get("shader_clock", math.nan))):
            raise RuntimeError(f"{case_id}: missing shader time/clock metadata")
        if case.get("grass") not in ("off", "on"):
            raise RuntimeError(f"{case_id}: invalid grass visibility metadata")
        by_id[case_id] = case

    extra_files = sorted(
        path.name for path in folder.iterdir()
        if path.is_file() and path.suffix.lower() == ".png"
        and path.name not in {str(case["image"]) for case in cases_node}
    )
    if extra_files:
        raise RuntimeError(f"{folder}: unmanifested PNGs found: {extra_files[:5]}")
    return manifest, by_id


def validate_camera_metadata(case: dict[str, Any], scenario_id: str, state: str,
                             expected: tuple[float, float, float, float, float]) -> None:
    north, east, height, azimuth, elevation = expected
    if case.get("scenario_id") != scenario_id or case.get("grass") != state:
        raise RuntimeError(f"{case['id']}: scenario/visibility metadata mismatch")
    for key, value in (("camera_north_m", north), ("camera_east_m", east), ("camera_height_m", height),
                       ("azimuth_deg", azimuth), ("elevation_deg", elevation)):
        if abs(float(case.get(key, -1e9)) - value) > 1e-6:
            raise RuntimeError(f"{case['id']}: {key} mismatch")


def expected_cameras(app: Path) -> tuple[float, float, dict[str, tuple[float, float, float, float, float]]]:
    field_path = app / "data/fields/default.json"
    raw = json.loads(field_path.read_text())
    pilot = raw["pilot"]
    n = float(pilot["north"]["value"])
    e = float(pilot["east"]["value"])
    eye = float(pilot["eye_height"]["value"])
    scenarios: dict[str, tuple[float, float, float, float, float]] = {}
    for elevation in PILOT_ELEVATIONS:
        for azimuth in PILOT_AZIMUTHS:
            scenario_id = f"pilot-az{azimuth:03d}-el{abs(elevation):02d}"
            scenarios[scenario_id] = (n, e, eye, float(azimuth), float(elevation))
    scenarios["raised-low-pass"] = (n, e, 3.0, 0.0, -8.0)
    scenarios["near-runway"] = (n + 6.0, e, 1.7, 45.0, -10.0)
    scenarios["band-25-35m"] = (n, e, 3.0, 0.0, -3.0)
    scenarios["fade-camera-35m"] = (n, e, 35.0, 0.0, -60.0)
    scenarios[SCENERY_SCENARIO] = (n + 6.0, e, 1.7, 45.0, -10.0)
    return n, e, scenarios


def verify_wind_probes(folder: Path, cases: dict[str, dict[str, Any]], reference: dict[str, Any],
                       pilot_north: float, pilot_east: float, material_scope: str) -> dict[str, Any]:
    wind_cases = {case_id: cases[case_id] for case_id in WIND_CASES}
    windless_t1 = wind_cases["windless-t1"]
    wind_t0 = wind_cases["wind-on-t0"]
    wind_t1 = wind_cases["wind-on-t1"]
    wind_t1024 = wind_cases["wind-on-t1024"]
    calm_repeat = wind_cases["windless-t0-repeat"]
    for case_id, case, time_s, expected_clock, expected_wind in (
        ("windless-t1", windless_t1, 1.0, 1.0, [0.0, 0.0, 0.0]),
        ("wind-on-t0", wind_t0, 0.0, 0.0, [5.0, 0.0, 0.0]),
        ("wind-on-t1", wind_t1, 1.0, 1.0, [5.0, 0.0, 0.0]),
        ("wind-on-t1024", wind_t1024, 1024.0, 0.0, [5.0, 0.0, 0.0]),
        ("windless-t0-repeat", calm_repeat, 0.0, 0.0, [0.0, 0.0, 0.0]),
    ):
        if case.get("scenario_id") != reference.get("scenario_id") or case.get("grass") != "on":
            raise RuntimeError(f"{case_id}: {material_scope} wind camera or grass-state mismatch")
        if float(case.get("shader_time_s", -1.0)) != time_s or float(case.get("shader_clock", -1.0)) != expected_clock:
            raise RuntimeError(f"{case_id}: shader clock metadata mismatch")
        if case.get("wind_vec") != expected_wind:
            raise RuntimeError(f"{case_id}: wind vector metadata mismatch")
        for key in ("camera_north_m", "camera_east_m", "camera_height_m", "azimuth_deg", "elevation_deg", "camera_fov_deg"):
            if case.get(key) != reference.get(key):
                raise RuntimeError(f"{case_id}: camera differs from the zero-wind t=0 reference")
    if float(reference.get("shader_time_s", -1.0)) != 0.0 or reference.get("wind_vec") != [0.0, 0.0, 0.0]:
        raise RuntimeError(f"{material_scope}: grass-on reference must be at t=0 with zero wind")

    windless_equal = image_rgb(folder / reference["image"]).tobytes() == image_rgb(folder / windless_t1["image"]).tobytes()
    calm_repeat_equal = image_rgb(folder / reference["image"]).tobytes() == image_rgb(folder / calm_repeat["image"]).tobytes()
    wind_repeat_equal = image_rgb(folder / wind_t0["image"]).tobytes() == image_rgb(folder / wind_t1024["image"]).tobytes()
    if not windless_equal:
        raise RuntimeError("zero-wind grass changed between sim_clock t=0 and t=1 while the environment was frozen")
    if not wind_repeat_equal:
        raise RuntimeError("winded grass did not repeat at the ShaderClock t=0 / t=1024 wrap")
    if not calm_repeat_equal:
        raise RuntimeError("calm t=0 image changed after the wind-probe sequence")
    moving = compare_images(folder, wind_t0, folder, wind_t1)
    if moving["changed_pixels"] <= 0:
        raise RuntimeError(f"nonzero Vector3 wind produced no {material_scope} image motion from t=0 to t=1")
    wind_footprint, _unused_band = projected_ground_masks(wind_t1, pilot_north, pilot_east)
    a = image_rgb(folder / wind_t0["image"])
    b = image_rgb(folder / wind_t1["image"])
    wind_changed = np.abs(a.astype(np.int16) - b.astype(np.int16)).max(axis=2) != 0
    outside_wind = int(np.count_nonzero(wind_changed & ~wind_footprint))
    if outside_wind:
        raise RuntimeError(f"wind changed {outside_wind} pixels outside the projected grass envelope")
    fixed_root_contract = (
        "all 14 y=0 mesh vertices have UV.y=0; shader offsets are weighted by UV.y squared"
        if material_scope == "legacy procedural grass"
        else "source vertices below plant_base_y have zero height weight; displacement uses blade_height squared"
    )
    return {
        "material_scope": material_scope,
        "windless_t0_case": reference["id"],
        "windless_t1_sha256": image_digest(folder / windless_t1["image"]),
        "windless_t0_t1_byte_identical": windless_equal,
        "calm_t0_repeat_after_probes_byte_identical": calm_repeat_equal,
        "calm_t0_repeat_case": calm_repeat["id"],
        "wind_t0_t1": moving,
        "wind_changed_pixels_outside_grass_footprint": outside_wind,
        "wind_t0_t1024_byte_identical": wind_repeat_equal,
        "wind_clock_wrap": 1024.0,
        "wind_vector": [5.0, 0.0, 0.0],
        "fixed_roots_supported_by": fixed_root_contract,
    }


def verify_candidate(folder: Path, manifest: dict[str, Any], cases: dict[str, dict[str, Any]],
                     app: Path) -> dict[str, Any]:
    pilot_north, pilot_east, scenario_cameras = expected_cameras(app)
    pairs: dict[str, Any] = {}
    positive_draw = False
    positive_primitives = False
    for scenario_id in STANDARD_SCENARIOS:
        off_id, on_id = f"{scenario_id}-grass-off", f"{scenario_id}-grass-on"
        off, on = cases[off_id], cases[on_id]
        expected_camera = scenario_cameras[scenario_id]
        validate_camera_metadata(off, scenario_id, "off", expected_camera)
        validate_camera_metadata(on, scenario_id, "on", expected_camera)
        for key in ("shader_time_s", "shader_clock", "wind_vec", "camera_north_m", "camera_east_m", "camera_height_m",
                    "azimuth_deg", "elevation_deg", "camera_fov_deg", "visual_scope"):
            if off.get(key) != on.get(key):
                raise RuntimeError(f"{scenario_id}: off/on capture state mismatch in {key}")
        metrics = paired_case_metrics(folder, off, on, pilot_north, pilot_east)
        if scenario_id == "fade-camera-35m" and (
            metrics["changed_pixels"] != 0 or metrics["grass_off_sha256"] != metrics["grass_on_sha256"]
        ):
            raise RuntimeError("35 m raised camera did not collapse all grass to an identical PNG")
        draw_delta = metrics["draw_calls"]["delta"]
        primitive_delta = metrics["primitives"]["delta"]
        if draw_delta < 0 or draw_delta > DRAW_BUDGET:
            raise RuntimeError(f"{scenario_id}: grass draw increment {draw_delta} outside 0–{DRAW_BUDGET}")
        if primitive_delta < 0 or primitive_delta > PRIMITIVE_BUDGET:
            raise RuntimeError(f"{scenario_id}: grass primitive increment {primitive_delta} outside 0–{PRIMITIVE_BUDGET}")
        if metrics["changed_pixels_outside_projected_grass_footprint"]:
            raise RuntimeError(
                f"{scenario_id}: {metrics['changed_pixels_outside_projected_grass_footprint']} changed pixels "
                "fall outside the projected 36 m grass envelope"
            )
        if scenario_id == "band-25-35m" and metrics["projected_seam_band_pixels"] <= 0:
            raise RuntimeError("raised-camera 25–35 m projected ground band contains no pixels")
        if scenario_id == "band-25-35m" and metrics["seam_band_max_channel_percent"] > SEAM_PERCENT_BUDGET:
            raise RuntimeError(
                f"{scenario_id}: 25–35 m band mean exceeds {SEAM_PERCENT_BUDGET:.1f}% "
                f"({metrics['seam_band_max_channel_percent']:.3f}%)"
            )
        positive_draw = positive_draw or draw_delta > 0
        positive_primitives = positive_primitives or primitive_delta > 0
        pairs[scenario_id] = metrics
    if not positive_draw or not positive_primitives:
        raise RuntimeError("grass-on captures show no positive draw and primitive increment")

    pilot_case = cases["pilot-az000-el10-grass-on"]
    wind_metrics = verify_wind_probes(folder, cases, pilot_case, pilot_north, pilot_east, "legacy procedural grass")
    return {
        "pairs": pairs,
        "wind": wind_metrics,
        "budgets": {
            "draw_delta_max": max(pair["draw_calls"]["delta"] for pair in pairs.values()),
            "draw_delta_limit": DRAW_BUDGET,
            "primitive_delta_max": max(pair["primitives"]["delta"] for pair in pairs.values()),
            "primitive_delta_limit": PRIMITIVE_BUDGET,
        },
    }


def verify_scenery(folder: Path, manifest: dict[str, Any], cases: dict[str, dict[str, Any]], pilot_north: float,
                   pilot_east: float, scenario_cameras: dict[str, tuple[float, float, float, float, float]]) -> dict[str, Any]:
    off = cases[f"{SCENERY_SCENARIO}-grass-off"]
    on = cases[f"{SCENERY_SCENARIO}-grass-on"]
    expected_camera = scenario_cameras[SCENERY_SCENARIO]
    validate_camera_metadata(off, SCENERY_SCENARIO, "off", expected_camera)
    validate_camera_metadata(on, SCENERY_SCENARIO, "on", expected_camera)
    metrics = paired_case_metrics(folder, off, on, pilot_north, pilot_east)
    if metrics["changed_pixels"] <= 0:
        raise RuntimeError("imported source grass produced no visible change in the scenery integration pair")
    if metrics["draw_calls"]["delta"] < 0 or metrics["draw_calls"]["delta"] > DRAW_BUDGET:
        raise RuntimeError("scenery-on grass draw increment exceeds the five-draw budget")
    if metrics["primitives"]["delta"] < 0 or metrics["primitives"]["delta"] > PRIMITIVE_BUDGET:
        raise RuntimeError("scenery-on grass primitive increment exceeds the 100,000 primitive budget")
    if metrics["changed_pixels_outside_projected_grass_footprint"]:
        raise RuntimeError("scenery-on grass pair changes pixels outside the projected grass envelope")
    grass = manifest.get("grass", {})
    material_mode = str(grass.get("material_mode", ""))
    if material_mode == "qualified_wind":
        wind = verify_wind_probes(folder, cases, on, pilot_north, pilot_east, "qualified imported grass")
    elif material_mode == "static_baseline":
        wind = {"captured": False, "scope": "static imported-material baseline; wind adapter is absent"}
    else:
        raise RuntimeError(f"unsupported imported-grass material scope {material_mode!r}")
    return {**metrics, "material_mode": material_mode, "wind": wind}


def compare_repeat_runs(first_folder: Path, first: dict[str, dict[str, Any]],
                        second_folder: Path, second: dict[str, dict[str, Any]]) -> dict[str, Any]:
    mismatches: list[str] = []
    for case_id in sorted(first):
        a, b = first[case_id], second[case_id]
        if image_rgb(first_folder / a["image"]).tobytes() != image_rgb(second_folder / b["image"]).tobytes():
            mismatches.append(case_id)
    if mismatches:
        raise RuntimeError(f"independent process captures differ: {mismatches[:8]}")
    first_manifest = first_folder / "capture-manifest.json"
    second_manifest = second_folder / "capture-manifest.json"
    if first_manifest.read_bytes() != second_manifest.read_bytes():
        # Renderer build timings are not included, so every manifest is expected to be byte-stable too.
        raise RuntimeError("independent process capture manifests differ")
    return {"case_count": len(first), "image_mismatches": [], "manifests_byte_identical": True, "byte_identical": True}


def run_capture(godot: Path, app: Path, output: Path, mode: str, scenery_arg: str,
                log_path: Path, env: dict[str, str], timeout_s: int) -> None:
    command = [
        "xvfb-run", "-a", "-s", SCREEN,
        str(godot), "--path", str(app), "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
        "--script", str(CAPTURE_SCRIPT.resolve()), "--",
        f"--out={output}", f"--mode={mode}", f"--scenery={scenery_arg}",
        "--scenery_audio=off", "--scenery_birds=off",
    ]
    checked_run(command, log_path, env, timeout_s)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "app", help="candidate Godot project directory")
    parser.add_argument("--godot", type=Path, help="pinned Godot 4.7 executable; defaults to app/get-godot.sh")
    parser.add_argument("--out", type=Path, default=Path("/tmp/l11a-grass"), help="new or empty evidence directory")
    parser.add_argument("--baseline-app", type=Path, help="pre-L11a app to compare with candidate grass-off captures")
    parser.add_argument("--timeout", type=int, default=240, help="timeout per rendered process in seconds")
    args = parser.parse_args()

    app = args.app.resolve()
    out = args.out.resolve()
    baseline_app = args.baseline_app.resolve() if args.baseline_app else None
    if not app.is_dir():
        parser.error(f"missing candidate app directory: {app}")
    if not CAPTURE_SCRIPT.is_file():
        parser.error(f"missing capture producer: {CAPTURE_SCRIPT}")
    if baseline_app is not None and (not baseline_app.is_dir() or baseline_app == app):
        parser.error("--baseline-app must name a different existing Godot project directory")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if shutil.which("xvfb-run") is None or shutil.which("timeout") is None:
        parser.error("xvfb-run and timeout are required for guarded Compatibility captures")
    if args.godot:
        godot = args.godot.resolve()
    else:
        godot_text = subprocess.run([str(app / "get-godot.sh")], check=True, capture_output=True, text=True).stdout.strip()
        godot = Path(godot_text).resolve()
    if not godot.is_file():
        parser.error(f"missing Godot executable: {godot}")
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        parser.error(f"output directory must be new or empty; stale output is refused: {out}")
    out.mkdir(parents=True, exist_ok=True)

    run_dirs = [out / f"candidate-repeat-{repeat}" for repeat in (1, 2)]
    run_dirs += [out / f"scenery-repeat-{repeat}" for repeat in (1, 2)]
    if baseline_app is not None:
        run_dirs += [out / f"baseline-repeat-{repeat}" for repeat in (1, 2)]
    for folder in run_dirs:
        folder.mkdir()

    env = dict(os.environ, LP_NUM_THREADS="1", OPENRC_SCENERY="off", OPENRC_SCENERY_AUDIO="off",
               OPENRC_SCENERY_BIRDS="off", OPENRC_SCENERY_QUALITY="high", PYTHONDONTWRITEBYTECODE="1")
    projects = {"candidate": app}
    if baseline_app is not None:
        projects["baseline"] = baseline_app
    for name, project in projects.items():
        checked_run([str(godot), "--headless", "--path", str(project), "--audio-driver", "Dummy", "--import"],
                    out / f"{name}-import.log", env, args.timeout)
    source_before = {name: source_snapshot(project) for name, project in projects.items()}

    loaded: dict[str, dict[str, tuple[dict[str, Any], dict[str, dict[str, Any]]]]] = {"candidate": {}, "scenery": {}}
    for repeat in (1, 2):
        candidate_folder = out / f"candidate-repeat-{repeat}"
        run_capture(godot, app, candidate_folder, "candidate", "off",
                    out / f"candidate-repeat-{repeat}.log", env, args.timeout)
        candidate_manifest, candidate_cases = load_run(candidate_folder, "candidate")
        loaded["candidate"][str(repeat)] = (candidate_manifest, candidate_cases)

        scenery_folder = out / f"scenery-repeat-{repeat}"
        scenery_env = dict(env, OPENRC_SCENERY="on")
        run_capture(godot, app, scenery_folder, "scenery", "on",
                    out / f"scenery-repeat-{repeat}.log", scenery_env, args.timeout)
        scenery_manifest, scenery_cases = load_run(scenery_folder, "scenery")
        loaded["scenery"][str(repeat)] = (scenery_manifest, scenery_cases)

    repeatability = {
        "candidate": compare_repeat_runs(
            out / "candidate-repeat-1", loaded["candidate"]["1"][1],
            out / "candidate-repeat-2", loaded["candidate"]["2"][1],
        ),
        "scenery": compare_repeat_runs(
            out / "scenery-repeat-1", loaded["scenery"]["1"][1],
            out / "scenery-repeat-2", loaded["scenery"]["2"][1],
        ),
    }
    pilot_north, pilot_east, scenario_cameras = expected_cameras(app)
    candidate_review = verify_candidate(out / "candidate-repeat-1", *loaded["candidate"]["1"], app)
    scenery_review = verify_scenery(out / "scenery-repeat-1", loaded["scenery"]["1"][0], loaded["scenery"]["1"][1],
                                    pilot_north, pilot_east, scenario_cameras)

    baseline_parity: dict[str, Any] | None = None
    if baseline_app is not None:
        baseline_runs: dict[str, tuple[dict[str, Any], dict[str, dict[str, Any]]]] = {}
        for repeat in (1, 2):
            folder = out / f"baseline-repeat-{repeat}"
            run_capture(godot, baseline_app, folder, "baseline", "off",
                        out / f"baseline-repeat-{repeat}.log", env, args.timeout)
            baseline_runs[str(repeat)] = load_run(folder, "baseline")
        repeatability["baseline"] = compare_repeat_runs(
            out / "baseline-repeat-1", baseline_runs["1"][1],
            out / "baseline-repeat-2", baseline_runs["2"][1],
        )
        candidate_cases = loaded["candidate"]["1"][1]
        baseline_cases = baseline_runs["1"][1]
        deltas: dict[str, Any] = {}
        exact = True
        _bn, _be, baseline_scenarios = expected_cameras(baseline_app)
        for scenario_id in STANDARD_SCENARIOS:
            case_id = f"{scenario_id}-grass-off"
            baseline_case = baseline_cases[case_id]
            candidate_case = candidate_cases[case_id]
            validate_camera_metadata(baseline_case, scenario_id, "off", baseline_scenarios[scenario_id])
            metrics = compare_images(out / "baseline-repeat-1", baseline_case,
                                     out / "candidate-repeat-1", candidate_case)
            identical = (out / "baseline-repeat-1" / baseline_case["image"]).read_bytes() == (
                out / "candidate-repeat-1" / candidate_case["image"]
            ).read_bytes()
            metrics["byte_identical"] = identical
            deltas[scenario_id] = metrics
            exact = exact and identical
        if not exact:
            changed = [key for key, value in deltas.items() if not value["byte_identical"]]
            raise RuntimeError(f"grass-off differs from the supplied baseline in {changed[:8]}")
        baseline_parity = {
            "baseline_app": str(baseline_app),
            "paired_views": len(STANDARD_SCENARIOS),
            "byte_identical": exact,
            "deltas": deltas,
        }

    source_after = {name: source_snapshot(project) for name, project in projects.items()}
    source_provenance = {
        name: source_guard_report(source_before[name], source_after[name]) for name in projects
    }

    summary = {
        "format": SUMMARY_FORMAT,
        "complete": True,
        "capture_scene": {
            "field": "FieldLoader.load_from(DEFAULT_PATH) then FieldBuilder.build",
            "environment": "Atmosphere.environment + Atmosphere.create_sun",
            "shader_clock_registered_before_field_build": True,
            "scenery_off": "candidate and optional baseline sets",
            "scenery_on": "imported botanical flowers and source-grass integration pair",
        },
        "source_provenance": source_provenance,
        "capture_set": {
            "production_paired_scenarios": list(STANDARD_SCENARIOS),
            "production_images_per_process": len(expected_ids("candidate")),
            "scenery_images_per_process": len(expected_ids(
                "scenery", loaded["scenery"]["1"][0]["grass"]["material_mode"])),
            "independent_candidate_processes": 2,
            "independent_scenery_processes": 2,
            "baseline_app": str(baseline_app) if baseline_app else None,
            "baseline_images_per_process": len(expected_ids("baseline")) if baseline_app else 0,
            "viewport": {"width": WIDTH, "height": HEIGHT},
        },
        "repeatability": repeatability,
        "grass_contract": loaded["candidate"]["1"][0]["grass"],
        "candidate": candidate_review,
        "scenery_integration": {
            "flower_nodes": loaded["scenery"]["1"][0]["flowers"],
            "imported_grass_contract": loaded["scenery"]["1"][0]["grass"],
            "grass_pair": scenery_review,
            "no_duplicate_flower_nodes": loaded["scenery"]["1"][0]["flowers"]["unique_names"],
        },
        "baseline_parity": baseline_parity,
        "limits": [
            "Software OpenGL proves output repeatability and renderer counters, not target-GPU frame time.",
            "The projected 36 m mask is a conservative image-space envelope around the committed 30 m grass placement.",
        ],
    }
    summary_path = out / "capture-summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    scenery_count = len(expected_ids("scenery", loaded["scenery"]["1"][0]["grass"]["material_mode"]))
    print(f"L11a grass: {len(expected_ids('candidate'))} candidate images/process and "
          f"{scenery_count} scenery images/process; two-process byte repeat passed")
    print(f"Report: {summary_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
