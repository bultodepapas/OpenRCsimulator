#!/usr/bin/env python3
"""Guarded L15b Compatibility captures for production tree-wind rendering."""

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
import tempfile
from typing import Any

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
CAPTURE_SCRIPT = Path(__file__).with_name("capture_wind.gd")
FORMAT = "openrc-l15b-wind-capture v1"
PROBE_FORMAT = "openrc-l15b-tree-wind-gpu-probe v1"
SUMMARY_FORMAT = "openrc-l15b-wind-review v1"
WIDTH = 1280
HEIGHT = 720
PROBE_CELL_PX = 4
WIDE_FOV_DEG = 50.0
ZOOM_FOV_DEG = 10.0
WIND_CASES = (
    "calm-t0", "calm-t1",
    "east-t0", "east-t1", "east-t1024",
    "west-t0", "west-t1", "west-t1024",
    "east-same-input-t1", "east-replay-t0", "east-disabled-t1",
)
TIME_STRIP_TIMES = tuple(index * 0.25 for index in range(8))
AZIMUTHS = (0, 90, 180, 270)
VIEWS = tuple(
    view_id
    for azimuth in AZIMUTHS
    for view_id in (f"wide-az{azimuth:03d}", f"zoom-az{azimuth:03d}")
)
RUNTIME_SUFFIXES = {
    ".cfg", ".gd", ".gdshader", ".gdshaderinc", ".gdextension", ".godot", ".gltf", ".glb",
    ".import", ".json", ".mp3", ".ogg", ".po", ".png", ".res", ".svg", ".tscn", ".tres",
    ".ttf", ".otf", ".wav", ".webp", ".jpg", ".jpeg",
}
EXCLUDED_DIRS = {".git", ".godot", ".tools", "__pycache__", "build", "captures", "dist", "tests"}
SCREEN = f"-screen 0 {WIDTH}x{HEIGHT}x24"
COUNTER_KEYS = ("draw_calls", "primitives", "objects", "shadow_draw_calls")
MIN_VISIBLE_MOTION_PIXELS = 8


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
    runtime: dict[str, str] = {}
    for current, directories, filenames in os.walk(project):
        directories[:] = sorted(name for name in directories if name not in EXCLUDED_DIRS)
        current_path = Path(current)
        for filename in sorted(filenames):
            path = current_path / filename
            if path.suffix.lower() not in RUNTIME_SUFFIXES:
                continue
            runtime[path.relative_to(project).as_posix()] = sha256_file(path)
    producers = {
        path.resolve().relative_to(ROOT).as_posix(): sha256_file(path.resolve())
        for path in (CAPTURE_SCRIPT, Path(__file__))
    }
    return {
        "project": str(project),
        "runtime_files": runtime,
        "runtime_file_map_sha256": canonical_map_hash(runtime),
        "producer_files": producers,
        "producer_file_map_sha256": canonical_map_hash(producers),
    }


def source_guard_report(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    changed_runtime = sorted(
        key for key in set(before["runtime_files"]) | set(after["runtime_files"])
        if before["runtime_files"].get(key) != after["runtime_files"].get(key)
    )
    changed_producers = sorted(
        key for key in set(before["producer_files"]) | set(after["producer_files"])
        if before["producer_files"].get(key) != after["producer_files"].get(key)
    )
    if changed_runtime or changed_producers:
        raise RuntimeError(
            f"sources changed during capture for {before['project']}: "
            f"runtime={changed_runtime[:8]}, producers={changed_producers[:8]}"
        )
    return {
        "project": before["project"],
        "runtime_file_count": len(before["runtime_files"]),
        "runtime_files_sha256": before["runtime_files"],
        "runtime_file_map_sha256": before["runtime_file_map_sha256"],
        "producer_files_sha256": before["producer_files"],
        "producer_file_map_sha256": before["producer_file_map_sha256"],
        "unchanged_during_capture": True,
    }


def checked_run(command: list[str], log_path: Path, env: dict[str, str], timeout_s: int) -> None:
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
        raise RuntimeError(f"Godot command failed ({result.returncode}) or logged an engine error: {log_path}")


def run_import(godot: Path, app: Path, output: Path, env: dict[str, str], timeout_s: int) -> None:
    checked_run(
        [str(godot), "--headless", "--path", str(app), "--audio-driver", "Dummy", "--import"],
        output,
        env,
        timeout_s,
    )


def run_capture(
    godot: Path,
    app: Path,
    output: Path,
    mode: str,
    log_path: Path,
    env: dict[str, str],
    timeout_s: int,
    smoke: bool = False,
) -> None:
    command = [
        "xvfb-run", "-a", "-s", SCREEN,
        str(godot), "--path", str(app), "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
        "--resolution", f"{WIDTH}x{HEIGHT}",
        "--script", str(CAPTURE_SCRIPT.resolve()), "--",
        f"--out={output}", f"--mode={mode}",
    ]
    if smoke:
        command.append("--smoke")
    checked_run(command, log_path, env, timeout_s)


def expected_ids(mode: str, smoke: bool) -> set[str]:
    if mode == "baseline":
        selected_views = {"zoom-az000"} if smoke else set(VIEWS)
        return {f"calm-t0--{view}" for view in selected_views}
    selected_views = {"zoom-az000"} if smoke else set(VIEWS)
    ids = {f"background-{view}" for view in selected_views}
    conditions = ("calm-t0", "east-t0", "east-t1", "east-t1024", "east-disabled-t1") if smoke else WIND_CASES
    ids |= {f"{condition}--{view}" for condition in conditions for view in selected_views}
    if not smoke:
        ids |= {f"time-strip-east-{index:02d}" for index in range(8)}
    return ids


def image_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        pixels = np.asarray(image.convert("RGB"), dtype=np.uint8)
    if pixels.shape != (HEIGHT, WIDTH, 3):
        raise RuntimeError(f"{path.name}: expected {WIDTH}×{HEIGHT} RGB, got {pixels.shape[1]}×{pixels.shape[0]}")
    return pixels


def load_run(folder: Path, mode: str, smoke: bool) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    manifest_path = folder / "capture-manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"missing capture manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("format") != FORMAT or manifest.get("mode") != mode or manifest.get("smoke") is not smoke:
        raise RuntimeError(f"{manifest_path}: format, mode or smoke metadata mismatch")
    if manifest.get("field") != "res://data/fields/default.json":
        raise RuntimeError(f"{manifest_path}: capture did not use the production default field")
    if manifest.get("viewport") != {"width": WIDTH, "height": HEIGHT}:
        raise RuntimeError(f"{manifest_path}: viewport must be {WIDTH}×{HEIGHT}")
    if not isinstance(manifest.get("renderer"), str) or not manifest["renderer"]:
        raise RuntimeError(f"{manifest_path}: missing renderer metadata")
    if manifest.get("scenery_on") is not False or manifest.get("near_grass_visible") is not False:
        raise RuntimeError(f"{manifest_path}: scenery must be off and NearGrass hidden")
    if manifest.get("cloud_clock_s") != 0.0:
        raise RuntimeError(f"{manifest_path}: cloud clock must stay at zero")
    tree = manifest.get("tree", {})
    if tree.get("visible") is not True or tree.get("chunk_count") != 8 or tree.get("tree_instances") != 1680:
        raise RuntimeError(f"{manifest_path}: capture did not use the production 1,680-tree/eight-sector treeline")
    if tree.get("casts_shadows") is not False or tree.get("near_grass_hidden") is not True:
        raise RuntimeError(f"{manifest_path}: trees must cast no shadows and NearGrass must stay hidden")
    expected_views = ["zoom-az000"] if smoke else list(VIEWS)
    views = manifest.get("views")
    if not isinstance(views, list) or [view.get("id") for view in views] != expected_views:
        raise RuntimeError(f"{manifest_path}: view inventory mismatch")
    for view in views:
        validate_view(view)
    if mode == "candidate":
        probe = manifest.get("geometry_probe", {})
        if probe.get("complete") is not True or probe.get("format") != PROBE_FORMAT:
            raise RuntimeError(f"{manifest_path}: missing exact-include GPU geometry probe")
        if probe.get("shader_include") != "res://render/tree_wind.gdshaderinc":
            raise RuntimeError(f"{manifest_path}: geometry probe used the wrong include")
        if not re.fullmatch(r"[0-9a-f]{64}", str(probe.get("shader_include_sha256", ""))):
            raise RuntimeError(f"{manifest_path}: invalid geometry probe include hash")
        if manifest.get("tree_wind_include_sha256") != probe.get("shader_include_sha256"):
            raise RuntimeError(f"{manifest_path}: probe/runtime include hashes differ")

    cases_node = manifest.get("cases")
    if not isinstance(cases_node, list):
        raise RuntimeError(f"{manifest_path}: cases must be a list")
    ids = [str(case.get("id", "")) for case in cases_node]
    expected = expected_ids(mode, smoke)
    if len(ids) != len(set(ids)) or set(ids) != expected:
        raise RuntimeError(
            f"{manifest_path}: image inventory mismatch; missing={sorted(expected - set(ids))}, "
            f"extra={sorted(set(ids) - expected)}"
        )
    by_id: dict[str, dict[str, Any]] = {}
    for raw in cases_node:
        case = dict(raw)
        case_id = str(case["id"])
        image_name = str(case.get("image", ""))
        if image_name != f"{case_id}.png" or Path(image_name).name != image_name:
            raise RuntimeError(f"{case_id}: invalid image path")
        image_path = folder / image_name
        if not check_image_sha256(image_path, str(case.get("sha256", ""))):
            raise RuntimeError(f"{case_id}: missing image or SHA-256 mismatch")
        image_rgb(image_path)
        for key in COUNTER_KEYS:
            if type(case.get(key)) is not int or int(case[key]) < 0:
                raise RuntimeError(f"{case_id}: invalid render counter {key}")
        if type(case.get("tree_visible")) is not bool or type(case.get("wind_enabled")) is not bool:
            raise RuntimeError(f"{case_id}: invalid wind or tree visibility metadata")
        if not math.isfinite(float(case.get("sim_time_s", math.nan))) or not math.isfinite(float(case.get("sim_clock", math.nan))):
            raise RuntimeError(f"{case_id}: invalid simulation clock metadata")
        view = next((entry for entry in views if entry.get("id") == case.get("view_id")), None)
        if view is None:
            raise RuntimeError(f"{case_id}: references unknown view {case.get('view_id')}")
        validate_case_camera(case, view)
        by_id[case_id] = case

    png_files = {path.name for path in folder.glob("*.png")}
    expected_pngs = {str(case["image"]) for case in cases_node}
    if mode == "candidate":
        expected_pngs.add("geometry-probe.png")
        if not (folder / "geometry-probe.png").is_file() or not (folder / "geometry-probe.json").is_file():
            raise RuntimeError(f"{folder}: missing geometry probe output")
        if sha256_file(folder / "geometry-probe.png") != manifest["geometry_probe"].get("png_sha256"):
            raise RuntimeError(f"{folder}: geometry probe PNG hash mismatch")
        verify_geometry_probe(folder / "geometry-probe.json", manifest["geometry_probe"])
        if not smoke and not (folder / "time-strip.html").is_file():
            raise RuntimeError(f"{folder}: missing time-strip HTML")
    if png_files != expected_pngs:
        raise RuntimeError(f"{folder}: PNG inventory mismatch; extra={sorted(png_files - expected_pngs)[:5]}")
    return manifest, by_id


def validate_view(view: dict[str, Any]) -> None:
    view_id = str(view.get("id", ""))
    try:
        azimuth = int(view_id.rsplit("az", 1)[1])
    except (IndexError, ValueError):
        raise RuntimeError(f"invalid view ID: {view_id}") from None
    if azimuth not in AZIMUTHS:
        raise RuntimeError(f"{view_id}: expected a cardinal pilot azimuth")
    is_wide = view_id.startswith("wide-")
    if not is_wide and not view_id.startswith("zoom-"):
        raise RuntimeError(f"{view_id}: unknown capture view family")
    expected_fov = WIDE_FOV_DEG if is_wide else ZOOM_FOV_DEG
    if float(view.get("fov_deg", math.nan)) != expected_fov:
        raise RuntimeError(f"{view_id}: expected vertical FOV {expected_fov}°")
    for key in ("camera_north_m", "camera_east_m", "camera_height_m", "target_north_m", "target_east_m", "target_height_m"):
        if not math.isfinite(float(view.get(key, math.nan))):
            raise RuntimeError(f"{view_id}: invalid {key}")
    if abs(float(view["camera_north_m"])) > 1e-6 or abs(float(view["camera_east_m"])) > 1e-6:
        raise RuntimeError(f"{view_id}: camera must stay at the production pilot station")
    if abs(float(view["camera_height_m"]) - 1.7) > 1e-6:
        raise RuntimeError(f"{view_id}: camera must use the production 1.7 m eye height")
    if is_wide:
        if view.get("kind") != "pilot-wide" or float(view.get("azimuth_deg", -1)) != float(azimuth) \
				or float(view.get("elevation_deg", math.nan)) != 0.0:
            raise RuntimeError(f"{view_id}: wide view must be level and cardinal")
        if abs(float(view["target_north_m"]) - 1000.0 * math.cos(math.radians(azimuth))) > 1e-6 \
				or abs(float(view["target_east_m"]) - 1000.0 * math.sin(math.radians(azimuth))) > 1e-6:
            raise RuntimeError(f"{view_id}: wide view target is not its cardinal pilot ray")
    else:
        radius = math.hypot(float(view["target_north_m"]), float(view["target_east_m"]))
        if view.get("kind") != "production-tree-zoom" or not 350.0 <= radius <= 450.0:
            raise RuntimeError(f"{view_id}: zoom must target a production tree within 350–450 m")
        if not 1.0 <= float(view.get("tree_height_m", 0.0)) <= 30.0:
            raise RuntimeError(f"{view_id}: invalid zoom target tree height")


def validate_case_camera(case: dict[str, Any], view: dict[str, Any]) -> None:
    expected = {
        "camera_fov_deg": "fov_deg",
        "camera_north_m": "camera_north_m",
        "camera_east_m": "camera_east_m",
        "camera_height_m": "camera_height_m",
        "target_north_m": "target_north_m",
        "target_east_m": "target_east_m",
        "target_height_m": "target_height_m",
        "azimuth_deg": "azimuth_deg",
        "elevation_deg": "elevation_deg",
    }
    if case.get("view_id") != view.get("id"):
        raise RuntimeError(f"{case['id']}: view metadata mismatch")
    for case_key, view_key in expected.items():
        if abs(float(case.get(case_key, math.nan)) - float(view.get(view_key, math.nan))) > 1e-6:
            raise RuntimeError(f"{case['id']}: {case_key} does not match the frozen camera view")


def verify_geometry_probe(path: Path, summary: dict[str, Any]) -> dict[str, Any]:
    report = json.loads(path.read_text())
    if report.get("format") != PROBE_FORMAT or report.get("complete") is not True:
        raise RuntimeError(f"{path}: malformed GPU geometry probe report")
    if report.get("shader_include_sha256") != summary.get("shader_include_sha256"):
        raise RuntimeError(f"{path}: include hash differs from capture manifest")
    samples = report.get("samples")
    if not isinstance(samples, list) or len(samples) < 150:
        raise RuntimeError(f"{path}: expected GPU readback at representative production-card points")
    png_name = str(report.get("png", ""))
    if Path(png_name).name != png_name:
        raise RuntimeError(f"{path}: invalid GPU geometry probe image path")
    png_path = path.parent / png_name
    if not check_image_sha256(png_path, str(report.get("png_sha256", ""))):
        raise RuntimeError(f"{path}: missing geometry probe PNG or SHA-256 mismatch")
    with Image.open(png_path) as probe_image:
        probe_pixels = np.asarray(probe_image.convert("RGB"), dtype=np.uint8)
    expected_shape = (PROBE_CELL_PX, len(samples) * PROBE_CELL_PX, 3)
    if probe_pixels.shape != expected_shape:
        raise RuntimeError(f"{path}: GPU probe PNG has shape {probe_pixels.shape}, expected {expected_shape}")
    for index, sample in enumerate(samples):
        actual_rgb = probe_pixels[PROBE_CELL_PX // 2, index * PROBE_CELL_PX + PROBE_CELL_PX // 2].tolist()
        if actual_rgb != sample.get("rgb8"):
            raise RuntimeError(f"{sample.get('id')}: JSON GPU color does not match its PNG cell: {sample.get('rgb8')} != {actual_rgb}")
    by_id = {str(sample.get("id", "")): sample for sample in samples}
    if len(by_id) != len(samples):
        raise RuntimeError(f"{path}: duplicate geometry probe sample IDs")
    root = by_id.get("root-zero-wind")
    if root is None:
        raise RuntimeError(f"{path}: missing exact-origin root sample")
    transfer = _detect_color_transfer(root)
    decoded: dict[str, tuple[np.ndarray, np.ndarray]] = {}
    for sample in samples:
        raw = sample.get("rgb8")
        point = np.asarray(sample.get("point"), dtype=np.float64)
        if not isinstance(raw, list) or len(raw) != 3 or point.shape != (3,):
            raise RuntimeError(f"{sample.get('id')}: malformed GPU output/source values")
        if any(type(value) is not int or not 0 <= value <= 255 for value in raw):
            raise RuntimeError(f"{sample.get('id')}: GPU color bytes are out of range")
        encoded = np.asarray(raw, dtype=np.float64) / 255.0
        linear = _srgb_to_linear(encoded) if transfer == "srgb" else encoded
        encoding_range = float(sample.get("encoding_range_m", 0.8))
        if not math.isfinite(encoding_range) or encoding_range <= 0.0:
            raise RuntimeError(f"{sample.get('id')}: invalid GPU encoding range")
        displacement = (linear - 0.5) * encoding_range
        if any(value in (0, 255) for value in raw):
            raise RuntimeError(f"{sample.get('id')}: encoded GPU displacement clipped its range")
        if abs(encoding_range - 0.8) < 1e-9 and np.any(np.abs(displacement) > 0.34):
            raise RuntimeError(f"{sample.get('id')}: encoded GPU displacement clipped the ±0.4 m range")
        decoded[str(sample["id"])] = point, displacement

    root_displacement = decoded["root-zero-wind"][1]
    if float(np.linalg.norm(root_displacement)) > 0.01:
        raise RuntimeError(f"GPU root moved by {np.linalg.norm(root_displacement):.5f} m")
    root_samples = [sample for sample in samples if sample.get("purpose") == "root"]
    if len(root_samples) < 16 or any(np.linalg.norm(decoded[str(sample["id"])][1]) > 0.01 for sample in root_samples):
        raise RuntimeError("exact-origin GPU root moved under a cardinal wind or later clock")
    max_displacement = 0.0
    max_length_error = 0.0
    cardinal_samples = [sample for sample in samples if sample.get("purpose") == "cardinal"]
    if len(cardinal_samples) < 140:
        raise RuntimeError("GPU probe did not exercise production card vertices in all four cardinal winds")
    for sample in cardinal_samples:
        point, displacement = decoded[str(sample["id"])]
        bent = point + displacement
        chord = float(np.linalg.norm(displacement))
        length_error = abs(float(np.linalg.norm(bent)) - float(np.linalg.norm(point)))
        max_displacement = max(max_displacement, chord)
        max_length_error = max(max_length_error, length_error)
    if max_displacement > 0.3:
        raise RuntimeError(f"maximum production-card GPU displacement {max_displacement:.5f} m exceeds 0.3 m")
    if max_length_error > 0.01:
        raise RuntimeError(f"GPU rotation changed card-vertex radius by {max_length_error:.5f} m")

    wrap_pairs: dict[str, dict[str, str]] = {}
    for sample in samples:
        if sample.get("purpose") != "clock-wrap":
            continue
        key = f"{sample.get('band')}:{sample.get('mesh_vertex')}"
        requested_time = float(sample.get("requested_time_s", -1.0))
        wrap_pairs.setdefault(key, {})["t1024" if requested_time == 1024.0 else "t0"] = str(sample["id"])
    if not wrap_pairs or any(set(pair) != {"t0", "t1024"} for pair in wrap_pairs.values()):
        raise RuntimeError("GPU wrap probe is missing matched t=0/t=1024 sample pairs")
    for pair in wrap_pairs.values():
        if by_id[pair["t0"]]["rgb8"] != by_id[pair["t1024"]]["rgb8"]:
            raise RuntimeError(f"GPU shader clock does not wrap at 1024 s: {pair}")

    prewrap_samples = [sample for sample in samples if sample.get("purpose") == "clock-prewrap"]
    prewrap_deltas: list[float] = []
    if len(prewrap_samples) < 6:
        raise RuntimeError("GPU probe is missing near-wrap samples from production tree-card vertices")
    for sample in prewrap_samples:
        if abs(float(sample.get("requested_time_s", -1.0)) - (1024.0 - 1.0 / 1024.0)) > 1e-9 \
                or float(sample.get("reference_clock", -1.0)) != 0.0:
            raise RuntimeError(f"{sample['id']}: malformed near-wrap comparison clocks")
        delta = float(np.linalg.norm(decoded[str(sample["id"])][1]))
        prewrap_deltas.append(delta)
        if delta > 0.001:
            raise RuntimeError(f"{sample['id']}: final shader-clock step is too large ({delta:.7f} m)")

    calm = [sample for sample in samples if sample.get("purpose") == "calm"]
    if len(calm) != 2 or any(np.linalg.norm(decoded[str(sample["id"])][1]) > 0.01 for sample in calm):
        raise RuntimeError("zero wind moved GPU probe geometry")
    if calm[0]["rgb8"] != calm[1]["rgb8"]:
        raise RuntimeError("zero-wind GPU probe changed with the shader clock")

    directions = [sample for sample in samples if sample.get("purpose") == "direction"]
    if {sample.get("id") for sample in directions} != {
        "direction-east", "direction-west", "direction-north", "direction-south"
    }:
        raise RuntimeError("GPU probe is missing cardinal wind-direction samples")
    for sample in directions:
        _, displacement = decoded[str(sample["id"])]
        wind = np.asarray(sample["wind"], dtype=np.float64)
        direction = wind / np.linalg.norm(wind)
        horizontal = displacement[[0, 2]]
        along = float(np.dot(horizontal, direction))
        cross = abs(float(direction[0] * horizontal[1] - direction[1] * horizontal[0]))
        if along <= 0.0 or cross > 0.02:
            raise RuntimeError(f"GPU bend points away from or sideways to its wind: {sample['id']}")

    phases = [sample for sample in samples if sample.get("purpose") == "hash-phase"]
    phase_vectors = [tuple(by_id[str(sample["id"])]["rgb8"]) for sample in phases]
    # The production sway is sinusoidal, so evenly spaced phases have only
    # seven distinct ideal values by symmetry; 8-bit readback can merge more.
    if len(phases) != 12 or len(set(phase_vectors)) < 6:
        raise RuntimeError("different production hash phases did not produce distinct GPU leans")
    time_samples = {sample["id"]: sample for sample in samples if sample.get("purpose") == "clock-change"}
    if set(time_samples) != {"time-east-t0", "time-east-t1"}:
        raise RuntimeError("missing GPU clock-change samples")
    delta_time = float(np.linalg.norm(decoded["time-east-t1"][1] - decoded["time-east-t0"][1]))
    if delta_time <= 0.02:
        raise RuntimeError(f"GPU tree phase did not advance between t=0 and t=1 ({delta_time:.5f} m chord delta)")

    speed_samples = {str(sample["id"]): sample for sample in samples if sample.get("purpose") == "speed-scale"}
    if set(speed_samples) != {"speed-05", "speed-10", "speed-20"}:
        raise RuntimeError("GPU probe is missing sub-saturated and saturated speed samples")
    speed_lengths = {
        speed: float(np.linalg.norm(decoded[sample_id][1]))
        for speed, sample_id in ((5, "speed-05"), (10, "speed-10"), (20, "speed-20"))
    }
    ratio = speed_lengths[5] / max(speed_lengths[10], 1e-9)
    if abs(ratio - 0.25) > 0.025 or speed_samples["speed-10"]["rgb8"] != speed_samples["speed-20"]["rgb8"]:
        raise RuntimeError(f"GPU speed response missed the quadratic/saturated contract: {speed_lengths}")

    return {
        "sample_count": len(samples),
        "color_transfer": transfer,
        "root_displacement_m": float(np.linalg.norm(root_displacement)),
        "root_samples": len(root_samples),
        "max_card_vertex_displacement_m": max_displacement,
        "max_length_error_m": max_length_error,
        "wrapped_pairs": len(wrap_pairs),
        "prewrap_pairs": len(prewrap_samples),
        "max_prewrap_delta_m": max(prewrap_deltas),
        "cardinal_directions": ["east", "west", "north", "south"],
        "distinct_hash_phase_outputs": len(set(phase_vectors)),
        "t0_to_t1_probe_delta_m": delta_time,
        "speed_sample_displacements_m": speed_lengths,
        "sub_saturation_speed_ratio_5_to_10": ratio,
    }


def _detect_color_transfer(root: dict[str, Any]) -> str:
    raw = np.asarray(root["rgb8"], dtype=np.float64)
    if np.max(raw) - np.min(raw) > 2.0:
        raise RuntimeError("GPU zero-displacement calibration channels disagree")
    center = float(raw.mean())
    if abs(center - 128.0) <= 3.0:
        return "linear"
    if abs(center - 188.0) <= 4.0:
        return "srgb"
    raise RuntimeError(f"unrecognized GPU readback color transfer: zero sample encoded as {center:.1f}")


def _srgb_to_linear(encoded: np.ndarray) -> np.ndarray:
    return np.where(encoded <= 0.04045, encoded / 12.92, ((encoded + 0.055) / 1.055) ** 2.4)


def check_image_sha256(path: Path, expected: str) -> bool:
    return path.is_file() and re.fullmatch(r"[0-9a-f]{64}", expected) is not None and sha256_file(path) == expected


def dilated_tree_mask(calm: np.ndarray, background: np.ndarray, padding: int) -> np.ndarray:
    if calm.shape != background.shape or calm.ndim != 3:
        raise RuntimeError("calm/background images do not have matching RGB shapes")
    mask = np.any(calm != background, axis=2)
    if not np.any(mask):
        raise RuntimeError("isolated production tree mask is empty")
    padded = Image.fromarray((mask.astype(np.uint8) * 255), mode="L").filter(
        ImageFilter.MaxFilter(padding * 2 + 1)
    )
    return np.asarray(padded) > 0


def masked_pixel_difference(first: np.ndarray, second: np.ndarray, allowed: np.ndarray, context: str) -> int:
    if first.shape != second.shape or first.shape[:2] != allowed.shape:
        raise RuntimeError(f"{context}: mismatched image or tree-mask shapes")
    diff = np.any(first != second, axis=2)
    leaked = int(np.logical_and(diff, np.logical_not(allowed)).sum())
    if leaked:
        raise RuntimeError(f"{context}: {leaked} changed pixels escaped the dilated tree-only mask")
    return int(diff.sum())


def require_visible_motion(changed_pixels: dict[str, int], context: str) -> None:
    failures = {name: count for name, count in changed_pixels.items() if count < MIN_VISIBLE_MOTION_PIXELS}
    if failures:
        raise RuntimeError(f"{context} produced fewer than {MIN_VISIBLE_MOTION_PIXELS} changed tree pixels: {failures}")


def checker_self_test() -> dict[str, Any]:
    background = np.zeros((8, 8, 3), dtype=np.uint8)
    calm = background.copy()
    calm[2:6, 2:6] = (70, 90, 110)
    allowed = dilated_tree_mask(calm, background, 1)
    east_t0 = calm.copy()
    east_t0[3, 3] = (180, 180, 180)
    substituted_east_t1 = east_t0.copy()
    static_delta = masked_pixel_difference(east_t0, substituted_east_t1, allowed, "self-test east t=0→t=1")
    try:
        require_visible_motion({"east t=1 vs t=0": static_delta}, "self-test east t=0→t=1")
    except RuntimeError:
        rejected_static = True
    else:
        rejected_static = False
    if not rejected_static:
        raise RuntimeError("checker self-test did not reject t=1 substituted with a static t=0 image")
    moving_east_t1 = east_t0.copy()
    moving_east_t1[3:6, 3:6] = (210, 210, 210)
    moving_delta = masked_pixel_difference(east_t0, moving_east_t1, allowed, "self-test moving east")
    require_visible_motion({"east t=1 vs t=0": moving_delta}, "self-test moving east")

    with tempfile.TemporaryDirectory(prefix="l15b-wind-check-") as temp_name:
        folder = Path(temp_name)
        image_path = folder / "copied-case.png"
        Image.new("RGB", (8, 8), (20, 40, 60)).save(image_path)
        copied_case = {"image": image_path.name, "sha256": sha256_file(image_path)}
        if not check_image_sha256(folder / copied_case["image"], copied_case["sha256"]):
            raise RuntimeError("checker self-test rejected an intact copied PNG")
        payload = image_path.read_bytes()
        image_path.write_bytes(bytes([payload[0] ^ 0x01]) + payload[1:])
        rejected_corrupt = not check_image_sha256(folder / copied_case["image"], copied_case["sha256"])
        if not rejected_corrupt:
            raise RuntimeError("checker self-test did not reject a corrupted copied PNG/hash")
    return {"static_same_input_pair_rejected": True, "moving_pair_accepted": True,
            "corrupted_png_hash_rejected": True}


def compare_repeat_runs(first_folder: Path, first: dict[str, dict[str, Any]],
                        second_folder: Path, second: dict[str, dict[str, Any]]) -> dict[str, Any]:
    mismatches = [
        case_id for case_id in sorted(first)
        if sha256_file(first_folder / first[case_id]["image"]) != sha256_file(second_folder / second[case_id]["image"])
    ]
    if mismatches:
        raise RuntimeError(f"independent-process PNGs differ: {mismatches[:8]}")
    if (first_folder / "capture-manifest.json").read_bytes() != (second_folder / "capture-manifest.json").read_bytes():
        raise RuntimeError("independent-process manifests differ")
    if (first_folder / "geometry-probe.json").exists() and (
        (first_folder / "geometry-probe.json").read_bytes() != (second_folder / "geometry-probe.json").read_bytes()
    ):
        raise RuntimeError("independent-process GPU geometry probe reports differ")
    return {"case_count": len(first), "image_mismatches": [], "manifest_byte_identical": True, "byte_identical": True}


def verify_candidate(folder: Path, manifest: dict[str, Any], cases: dict[str, dict[str, Any]], smoke: bool) -> dict[str, Any]:
    geometry = verify_geometry_probe(folder / "geometry-probe.json", manifest["geometry_probe"])
    if smoke:
        view = "zoom-az000"
        calm = image_rgb(folder / cases[f"calm-t0--{view}"]["image"])
        background = image_rgb(folder / cases[f"background-{view}"]["image"])
        allowed = dilated_tree_mask(calm, background, _mask_padding(view))
        east_t0 = image_rgb(folder / cases[f"east-t0--{view}"]["image"])
        east_t1 = image_rgb(folder / cases[f"east-t1--{view}"]["image"])
        motion = {
            "east-t0-vs-calm": masked_pixel_difference(calm, east_t0, allowed, "smoke east t=0 vs calm"),
            "east-t1-vs-calm": masked_pixel_difference(calm, east_t1, allowed, "smoke east t=1 vs calm"),
            "east-t1-vs-t0": masked_pixel_difference(east_t0, east_t1, allowed, "smoke east t=1 vs t=0"),
        }
        require_visible_motion(motion, "smoke production wind capture")
        return {"smoke": True, "geometry_probe": geometry, "cases": len(cases),
                "visible_motion_pixels": motion}

    arrays: dict[str, np.ndarray] = {}
    allowed_masks: dict[str, np.ndarray] = {}
    for view in VIEWS:
        calm_id = f"calm-t0--{view}"
        background_id = f"background-{view}"
        calm = cases[calm_id]
        background = cases[background_id]
        if not calm["tree_visible"] or background["tree_visible"]:
            raise RuntimeError(f"{view}: calm/background tree visibility metadata mismatch")
        calm_image = image_rgb(folder / calm["image"])
        background_image = image_rgb(folder / background["image"])
        arrays[calm_id] = calm_image
        arrays[background_id] = background_image
        tree_mask = np.any(calm_image != background_image, axis=2)
        mask_pixels = int(tree_mask.sum())
        minimum_mask_pixels = 100 if view.startswith("zoom-") else 20
        if mask_pixels < minimum_mask_pixels:
            raise RuntimeError(f"{view}: isolated production tree mask has only {mask_pixels} pixels")
        allowed_masks[view] = dilated_tree_mask(calm_image, background_image, _mask_padding(view))
        base_draw_delta = calm["draw_calls"] - background["draw_calls"]
        base_primitive_delta = calm["primitives"] - background["primitives"]
        base_shadow_delta = calm["shadow_draw_calls"] - background["shadow_draw_calls"]
        if not 0 <= base_draw_delta <= 8 or base_primitive_delta < 0 or base_shadow_delta != 0:
            raise RuntimeError(
                f"{view}: tree contribution violates draw/primitive/shadow budget "
                f"({base_draw_delta} draws, {base_primitive_delta} primitives, {base_shadow_delta} shadows)"
            )

    states = tuple(case_id for case_id in WIND_CASES if case_id not in ("calm-t0",))
    state_metrics: dict[str, Any] = {}
    for condition in states:
        changed_total = 0
        outside_total = 0
        for view in VIEWS:
            case_id = f"{condition}--{view}"
            case = cases[case_id]
            calm = cases[f"calm-t0--{view}"]
            if not case["tree_visible"]:
                raise RuntimeError(f"{case_id}: tree cards were hidden")
            if tuple(case[key] for key in COUNTER_KEYS) != tuple(calm[key] for key in COUNTER_KEYS):
                raise RuntimeError(f"{case_id}: wind changed draw, primitive, object or shadow counts")
            image = image_rgb(folder / case["image"])
            changed = masked_pixel_difference(
                arrays[f"calm-t0--{view}"], image, allowed_masks[view], f"{case_id} vs calm"
            )
            changed_total += changed
            outside_total += 0
        state_metrics[condition] = {"changed_pixels": changed_total, "changed_pixels_outside_tree_mask": outside_total}

    movement = {
        vector: state_metrics[f"{vector}-t0"]["changed_pixels"]
        for vector in ("east", "west")
    }
    require_visible_motion(movement, "10 m/s wind relative to calm")
    temporal_motion: dict[str, int] = {}
    for vector in ("east", "west"):
        for view in VIEWS:
            first = image_rgb(folder / cases[f"{vector}-t0--{view}"]["image"])
            second = image_rgb(folder / cases[f"{vector}-t1--{view}"]["image"])
            temporal_motion[f"{vector}--{view}"] = masked_pixel_difference(
                first, second, allowed_masks[view], f"{vector} t=1 vs t=0 at {view}"
            )
    require_visible_motion(temporal_motion, "10 m/s east/west time evolution")

    exact_pairs: dict[str, int] = {}
    for view in VIEWS:
        pairs = (
            (f"calm-t0--{view}", f"calm-t1--{view}", "calm clock independence"),
            (f"east-t0--{view}", f"east-t1024--{view}", "east clock wrap"),
            (f"west-t0--{view}", f"west-t1024--{view}", "west clock wrap"),
            (f"east-t1--{view}", f"east-same-input-t1--{view}", "same-input snapshot"),
            (f"east-t0--{view}", f"east-replay-t0--{view}", "replayed t=0 snapshot"),
            (f"calm-t0--{view}", f"east-disabled-t1--{view}", "wind-enabled ablation"),
        )
        for first_id, second_id, label in pairs:
            first_image = folder / cases[first_id]["image"]
            second_image = folder / cases[second_id]["image"]
            if first_image.read_bytes() != second_image.read_bytes():
                raise RuntimeError(f"{view}: byte mismatch for {label}")
            exact_pairs[label] = exact_pairs.get(label, 0) + 1

    strip = verify_time_strip(folder, cases, allowed_masks["zoom-az000"])
    counter_summary: dict[str, Any] = {}
    for view in VIEWS:
        calm = cases[f"calm-t0--{view}"]
        background = cases[f"background-{view}"]
        counter_summary[view] = {
            "tree_draws_added": calm["draw_calls"] - background["draw_calls"],
            "tree_primitives_added": calm["primitives"] - background["primitives"],
            "tree_shadow_draws_added": calm["shadow_draw_calls"] - background["shadow_draw_calls"],
            "wind_counters_unchanged": True,
        }
    return {
        "geometry_probe": geometry,
        "visible_motion_pixels": movement,
        "east_west_t0_to_t1_motion_pixels": temporal_motion,
        "state_pixel_differences": state_metrics,
        "exact_repeat_pairs_per_view": exact_pairs,
        "renderer_counter_deltas": counter_summary,
        "time_strip": strip,
    }


def _mask_padding(view_id: str) -> int:
    fov = ZOOM_FOV_DEG if view_id.startswith("zoom-") else WIDE_FOV_DEG
    focal_px = HEIGHT / (2.0 * math.tan(math.radians(fov) * 0.5))
    # The closest committed tree is >270 m away; 3 px margin covers raster and alpha-edge quantization.
    return math.ceil(focal_px * 0.3 / 270.0) + 3


def verify_time_strip(folder: Path, cases: dict[str, dict[str, Any]], allowed_mask: np.ndarray) -> dict[str, Any]:
    frames: list[np.ndarray] = []
    changed_pairs: list[int] = []
    for index, expected_time in enumerate(TIME_STRIP_TIMES):
        case_id = f"time-strip-east-{index:02d}"
        case = cases[case_id]
        if case.get("condition") != "time-strip-east" or abs(float(case.get("sim_time_s", -1)) - expected_time) > 1e-8:
            raise RuntimeError(f"{case_id}: time strip does not use its fixed-clock sample")
        if case.get("view_id") != "zoom-az000" or float(case.get("camera_fov_deg", -1)) != ZOOM_FOV_DEG:
            raise RuntimeError(f"{case_id}: time strip changed its fixed 10° tree camera")
        frames.append(image_rgb(folder / case["image"]))
    for index in range(len(frames) - 1):
        changed_pairs.append(masked_pixel_difference(
            frames[index], frames[index + 1], allowed_mask, f"time-strip frame {index}→{index + 1}"
        ))
    require_visible_motion(
        {f"frame-{index:02d}-to-{index + 1:02d}": count for index, count in enumerate(changed_pairs)},
        "fixed-camera time strip",
    )
    if (folder / cases["time-strip-east-00"]["image"]).read_bytes() != (
        folder / cases["east-t0--zoom-az000"]["image"]
    ).read_bytes():
        raise RuntimeError("time strip t=0 does not match the production zoom view at t=0")
    if (folder / cases["time-strip-east-04"]["image"]).read_bytes() != (
        folder / cases["east-t1--zoom-az000"]["image"]
    ).read_bytes():
        raise RuntimeError("time strip t=1 does not match the production zoom view at t=1")
    return {
        "view_id": "zoom-az000",
        "fov_deg": ZOOM_FOV_DEG,
        "sim_times_s": list(TIME_STRIP_TIMES),
        "adjacent_changed_pixels": changed_pairs,
        "moving_intervals": sum(value > 0 for value in changed_pairs),
        "html": "time-strip.html",
    }


def verify_baseline_parity(candidate_folder: Path, candidate_cases: dict[str, dict[str, Any]],
                           baseline_folder: Path, baseline_cases: dict[str, dict[str, Any]]) -> dict[str, Any]:
    mismatches: list[str] = []
    deltas: dict[str, Any] = {}
    for view in VIEWS:
        candidate_id = f"calm-t0--{view}"
        baseline_id = candidate_id
        candidate_path = candidate_folder / candidate_cases[candidate_id]["image"]
        baseline_path = baseline_folder / baseline_cases[baseline_id]["image"]
        identical = candidate_path.read_bytes() == baseline_path.read_bytes()
        if not identical:
            mismatches.append(view)
        deltas[view] = {
            "byte_identical": identical,
            "candidate_sha256": sha256_file(candidate_path),
            "baseline_sha256": sha256_file(baseline_path),
        }
    if mismatches:
        raise RuntimeError(f"candidate calm images differ from frozen baseline: {mismatches}")
    return {"paired_views": len(VIEWS), "byte_identical": True, "deltas": deltas}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "app", help="candidate Godot project directory")
    parser.add_argument("--godot", type=Path, help="pinned Godot executable; defaults to app/get-godot.sh")
    parser.add_argument("--out", type=Path, default=Path("/tmp/l15b-wind"), help="new or empty evidence directory")
    parser.add_argument("--baseline-app", type=Path, help="frozen pre-L15b app used for byte-exact calm parity")
    parser.add_argument("--timeout", type=int, default=240, help="timeout per Godot process in seconds")
    parser.add_argument("--smoke", action="store_true", help="run one short production capture and exact-include probe")
    args = parser.parse_args()
    self_test = checker_self_test()

    app = args.app.resolve()
    out = args.out.resolve()
    baseline_app = args.baseline_app.resolve() if args.baseline_app else None
    if not app.is_dir():
        parser.error(f"missing candidate app directory: {app}")
    if not CAPTURE_SCRIPT.is_file():
        parser.error(f"missing capture producer: {CAPTURE_SCRIPT}")
    if baseline_app is not None and (not baseline_app.is_dir() or baseline_app == app):
        parser.error("--baseline-app must name a different existing app")
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

    mode_names = ["candidate"] if args.smoke else ["candidate", "baseline"] if baseline_app else ["candidate"]
    run_folders: dict[tuple[str, int], Path] = {}
    for mode in mode_names:
        repeats = (1,) if args.smoke else (1, 2)
        for repeat in repeats:
            folder = out / f"{mode}-repeat-{repeat}"
            folder.mkdir()
            run_folders[(mode, repeat)] = folder

    env = dict(
        os.environ,
        LP_NUM_THREADS="1",
        OPENRC_SCENERY="off",
        OPENRC_SCENERY_AUDIO="off",
        OPENRC_SCENERY_BIRDS="off",
        PYTHONDONTWRITEBYTECODE="1",
    )
    projects = {"candidate": app}
    if baseline_app is not None and not args.smoke:
        projects["baseline"] = baseline_app
    for name, project in projects.items():
        run_import(godot, project, out / f"{name}-import.log", env, args.timeout)
    source_before = {name: source_snapshot(project) for name, project in projects.items()}

    loaded: dict[tuple[str, int], tuple[dict[str, Any], dict[str, dict[str, Any]]]] = {}
    for repeat in ((1,) if args.smoke else (1, 2)):
        folder = run_folders[("candidate", repeat)]
        run_capture(godot, app, folder, "candidate", out / f"candidate-repeat-{repeat}.log", env,
                    args.timeout, args.smoke)
        loaded[("candidate", repeat)] = load_run(folder, "candidate", args.smoke)
    candidate_repeatability: dict[str, Any] = {"independent_processes": 1 if args.smoke else 2}
    if not args.smoke:
        candidate_repeatability = compare_repeat_runs(
            run_folders[("candidate", 1)], loaded[("candidate", 1)][1],
            run_folders[("candidate", 2)], loaded[("candidate", 2)][1],
        )

    baseline_parity: dict[str, Any] | None = None
    baseline_repeatability: dict[str, Any] | None = None
    if baseline_app is not None and not args.smoke:
        for repeat in (1, 2):
            folder = run_folders[("baseline", repeat)]
            run_capture(godot, baseline_app, folder, "baseline", out / f"baseline-repeat-{repeat}.log", env,
                        args.timeout, False)
            loaded[("baseline", repeat)] = load_run(folder, "baseline", False)
        baseline_repeatability = compare_repeat_runs(
            run_folders[("baseline", 1)], loaded[("baseline", 1)][1],
            run_folders[("baseline", 2)], loaded[("baseline", 2)][1],
        )
        baseline_parity = verify_baseline_parity(
            run_folders[("candidate", 1)], loaded[("candidate", 1)][1],
            run_folders[("baseline", 1)], loaded[("baseline", 1)][1],
        )

    candidate_review = verify_candidate(
        run_folders[("candidate", 1)], loaded[("candidate", 1)][0], loaded[("candidate", 1)][1], args.smoke
    )
    source_after = {name: source_snapshot(project) for name, project in projects.items()}
    source_provenance = {
        name: source_guard_report(source_before[name], source_after[name]) for name in projects
    }
    summary = {
        "format": SUMMARY_FORMAT,
        "complete": True,
        "step": "L15b",
        "smoke": args.smoke,
        "capture_scene": {
            "field": "FieldLoader.load_from(DEFAULT_PATH) then FieldBuilder.build",
            "environment": "Atmosphere.environment() + production sun",
            "near_grass": "hidden",
            "scenery": "off",
            "cloud_clock": "fixed at t=0; ShaderClock alone drives tree wind",
            "camera": "production pilot station; 50° vertical FOV cardinal views and 10° tree zooms",
        },
        "source_provenance": source_provenance,
        "capture_set": {
            "candidate_images_per_process": len(expected_ids("candidate", args.smoke)),
            "baseline_images_per_process": len(expected_ids("baseline", False)) if baseline_app and not args.smoke else 0,
            "candidate_processes": 1 if args.smoke else 2,
            "baseline_processes": 0 if args.smoke or not baseline_app else 2,
            "baseline_app": str(baseline_app) if baseline_app and not args.smoke else None,
            "views": ["zoom-az000"] if args.smoke else list(VIEWS),
            "time_strip_frames": 0 if args.smoke else len(TIME_STRIP_TIMES),
            "viewport": {"width": WIDTH, "height": HEIGHT},
        },
        "repeatability": {"candidate": candidate_repeatability, "baseline": baseline_repeatability},
        "checker_self_test": self_test,
        "baseline_parity": baseline_parity,
        "candidate": candidate_review,
        "limits": [
            "Software OpenGL proves geometry, mask, deterministic pixels and renderer counters, not target-GPU frame time.",
            "The time strip is an owner-review aid; it does not replace a display/GPU visual acceptance pass.",
        ],
    }
    (out / "capture-summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    if args.smoke:
        print(f"L15b smoke passed: {candidate_review['geometry_probe']['sample_count']} GPU geometry samples; report: {out / 'capture-summary.json'}")
    else:
        print(
            f"L15b tree wind passed: {summary['capture_set']['candidate_images_per_process']} candidate images/process, "
            f"repeatable across two processes; baseline parity: {baseline_parity is not None}"
        )
        print(f"Report: {out / 'capture-summary.json'}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
