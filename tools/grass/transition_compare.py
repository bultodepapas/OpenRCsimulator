#!/usr/bin/env python3
"""Reduce the bounded moving-view imported-grass boundary capture.

The reducer subtracts a same-pose grass-hidden image from each visible image,
then follows that residual through camera motion. Its step ratios are diagnostic
only: camera motion and perspective create expected image changes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any

import numpy as np
from PIL import Image


FORMAT = "openrc-grass-transition-capture v1"
REPORT_FORMAT = "openrc-grass-transition-report v1"
WIDTH = 1280
HEIGHT = 720
RADII_M = (22.0, 24.0, 26.0, 28.0, 29.0, 29.5, 29.75, 30.25, 30.5, 31.0, 32.0, 34.0, 36.0, 38.0)
CAMERA_CASES = {
    "low_rc": {"height_m": 0.55, "lookahead_m": 4.0, "fov_deg": 68.0},
    "pilot": {"height_m": 1.7, "lookahead_m": 10.0, "fov_deg": 58.0},
}
SEQUENCES = {
    "calm_outbound": ("outbound", "calm", False),
    "wind_outbound": ("outbound", "wind", False),
    "calm_return": ("return", "calm", False),
    "camera_cut_outbound": ("outbound", "cut", True),
    "camera_cut_return": ("return", "cut", True),
}
PAIR_FIELDS = (
    "pose_id", "sequence_id", "sequence_kind", "sequence_direction", "camera_facing",
    "height_case", "camera_radius_from_pilot_m", "eye_height_m", "lookahead_m",
    "eye_render_m", "target_render_m", "fov_deg", "sequence_index", "sequence_length",
    "shader_clock_s", "wind_render_mps", "camera_cut", "camera_right_render",
    "camera_up_render", "camera_forward_render", "ground_detail_enabled",
)
RADIAL_BINS = ((22.0, 28.0), (28.0, 29.5), (29.5, 30.5), (30.5, 32.0), (32.0, 38.0))


class TransitionError(ValueError):
    """Invalid or incomplete capture evidence."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_child(root: Path, relative: str) -> Path:
    candidate = (root / relative).resolve()
    if candidate == root.resolve() or root.resolve() not in candidate.parents:
        raise TransitionError(f"capture image path escapes its run directory: {relative}")
    return candidate


def load_rgb(path: Path, expected_size: tuple[int, int] = (WIDTH, HEIGHT)) -> np.ndarray:
    try:
        with Image.open(path) as image:
            rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
    except OSError as error:
        raise TransitionError(f"cannot read capture image {path}: {error}") from error
    if rgb.shape != (expected_size[1], expected_size[0], 3):
        raise TransitionError(
            f"{path.name}: expected {expected_size[0]}×{expected_size[1]} RGB, "
            f"got {rgb.shape[1]}×{rgb.shape[0]}"
        )
    return rgb


def validate_pair_metadata(visible: dict[str, Any], hidden: dict[str, Any]) -> None:
    if visible.get("state") != "visible" or hidden.get("state") != "grass_hidden":
        raise TransitionError("every pose needs one visible and one grass-hidden capture")
    if visible.get("grass_visible") is not True or visible.get("grass_node_visible") is not True:
        raise TransitionError("visible capture did not keep Field/NearGrass visible")
    if hidden.get("grass_visible") is not False or hidden.get("grass_node_visible") is not False:
        raise TransitionError("hidden reference did not hide only Field/NearGrass")
    if visible.get("grass_hidden_reference") is not False or hidden.get("grass_hidden_reference") is not True:
        raise TransitionError("grass-hidden reference state metadata is inconsistent")
    for key in PAIR_FIELDS:
        if visible.get(key) != hidden.get(key):
            raise TransitionError(f"visible/hidden pair mismatch for {key}")
    if visible.get("pose_id") != hidden.get("pose_id"):
        raise TransitionError("visible/hidden pair pose IDs differ")


def summarize_delta(before: np.ndarray, after: np.ndarray) -> dict[str, Any]:
    if before.shape != after.shape or before.ndim != 3 or before.shape[2] != 3:
        raise TransitionError("image deltas require matching RGB arrays")
    delta = np.abs(after.astype(np.int16) - before.astype(np.int16))
    max_channel = delta.max(axis=2)
    return {
        "changed_pixels": int(np.count_nonzero(max_channel)),
        "mean_abs_rgb_delta": float(delta.mean()),
        "p99_max_channel_delta": float(np.percentile(max_channel, 99)),
        "max_channel_delta": int(max_channel.max(initial=0)),
    }


def summarize_temporal_step(
    previous_visible: np.ndarray,
    previous_hidden: np.ndarray,
    current_visible: np.ndarray,
    current_hidden: np.ndarray,
    camera_distance_m: float,
) -> dict[str, Any]:
    if camera_distance_m <= 0.0 or not math.isfinite(camera_distance_m):
        raise TransitionError("camera step distance must be finite and positive")
    for image in (previous_hidden, current_visible, current_hidden):
        if image.shape != previous_visible.shape:
            raise TransitionError("temporal step images must have identical dimensions")
    previous_residual = previous_visible.astype(np.int16) - previous_hidden.astype(np.int16)
    current_residual = current_visible.astype(np.int16) - current_hidden.astype(np.int16)
    visible_motion = summarize_delta(previous_visible, current_visible)
    background_motion = summarize_delta(previous_hidden, current_hidden)
    grass_residual_motion = summarize_delta(previous_residual, current_residual)
    return {
        "camera_distance_m": float(camera_distance_m),
        "visible_motion": visible_motion,
        "hidden_reference_motion": background_motion,
        "grass_residual_motion": grass_residual_motion,
        "visible_mean_abs_rgb_per_camera_m": visible_motion["mean_abs_rgb_delta"] / camera_distance_m,
        "hidden_mean_abs_rgb_per_camera_m": background_motion["mean_abs_rgb_delta"] / camera_distance_m,
        "grass_residual_mean_abs_rgb_per_camera_m": grass_residual_motion["mean_abs_rgb_delta"] / camera_distance_m,
        "interpretation": "grass residual motion is descriptive; camera optical motion and perspective remain expected",
    }


def boundary_control_ratio(steps: list[dict[str, Any]]) -> dict[str, Any]:
    boundary_rates: list[float] = []
    control_rates: list[float] = []
    control_pairs = {(29.5, 29.75), (30.25, 30.5)}
    for step in steps:
        start = float(step["start_radius_m"])
        end = float(step["end_radius_m"])
        pair = tuple(sorted((round(start, 2), round(end, 2))))
        rate = float(step["grass_residual_mean_abs_rgb_per_camera_m"])
        if pair == (29.75, 30.25):
            boundary_rates.append(rate)
        elif pair in control_pairs:
            control_rates.append(rate)
    if not boundary_rates or not control_rates:
        return {
            "boundary_rate": None,
            "adjacent_control_median_rate": None,
            "boundary_to_control_ratio": None,
            "controls_present": False,
        }
    boundary_rate = float(np.max(boundary_rates))
    control_rate = float(np.median(control_rates))
    ratio = boundary_rate / control_rate if control_rate > 0.0 else None
    return {
        "boundary_rate": boundary_rate,
        "adjacent_control_median_rate": control_rate,
        "boundary_to_control_ratio": ratio,
        "controls_present": True,
        "control_rate_zero": control_rate == 0.0,
        "control_steps_m": [[29.5, 29.75], [30.25, 30.5]],
        "boundary_step_m": [29.75, 30.25],
        "interpretation": "ratio is an unthresholded step-refinement diagnostic, not a pop verdict",
    }


def ground_radius_grid(case: dict[str, Any], pilot_render: np.ndarray, width: int = WIDTH,
                       height: int = HEIGHT) -> tuple[np.ndarray, np.ndarray]:
    eye = np.asarray(case["eye_render_m"], dtype=np.float64)
    forward = np.asarray(case["camera_forward_render"], dtype=np.float64)
    right = np.asarray(case["camera_right_render"], dtype=np.float64)
    up = np.asarray(case["camera_up_render"], dtype=np.float64)
    for name, vector in (("eye", eye), ("forward", forward), ("right", right), ("up", up)):
        if vector.shape != (3,) or not np.isfinite(vector).all():
            raise TransitionError(f"invalid {name} vector in pose {case.get('pose_id')}")
    fov = float(case["fov_deg"])
    if not 1.0 < fov < 179.0:
        raise TransitionError(f"invalid camera FOV in pose {case.get('pose_id')}")
    scale = math.tan(math.radians(fov) / 2.0) / (height / 2.0)
    rows = np.arange(height, dtype=np.float64) + 0.5
    columns = np.arange(width, dtype=np.float64) + 0.5
    ray_x = (columns - width / 2.0) * scale
    ray_y = (height / 2.0 - rows) * scale
    rays = (
        forward[None, None, :]
        + ray_x[None, :, None] * right[None, None, :]
        + ray_y[:, None, None] * up[None, None, :]
    )
    down = rays[:, :, 1] < -1e-9
    distance = np.divide(-eye[1], rays[:, :, 1], out=np.zeros((height, width), dtype=np.float64), where=down)
    valid = down & (distance > 0.0) & np.isfinite(distance)
    hit_x = eye[0] + distance * rays[:, :, 0]
    hit_z = eye[2] + distance * rays[:, :, 2]
    radius = np.hypot(hit_x - float(pilot_render[0]), hit_z - float(pilot_render[2]))
    return np.where(valid, radius, np.inf), valid


def validate_pose_geometry(record: dict[str, Any], pilot_render: np.ndarray) -> None:
    view = CAMERA_CASES.get(str(record.get("height_case", "")))
    if view is None:
        raise TransitionError(f"{record.get('pose_id')}: unknown camera height case")
    radius = float(record.get("camera_radius_from_pilot_m", math.nan))
    height = float(record.get("eye_height_m", math.nan))
    lookahead = float(record.get("lookahead_m", math.nan))
    fov = float(record.get("fov_deg", math.nan))
    if not all(math.isfinite(value) for value in (radius, height, lookahead, fov)):
        raise TransitionError(f"{record.get('pose_id')}: non-finite camera geometry")
    if not math.isclose(height, view["height_m"], abs_tol=1e-6):
        raise TransitionError(f"{record['pose_id']}: camera height differs from its declared view")
    if not math.isclose(lookahead, view["lookahead_m"], abs_tol=1e-6):
        raise TransitionError(f"{record['pose_id']}: camera lookahead differs from its declared view")
    if not math.isclose(fov, view["fov_deg"], abs_tol=1e-6):
        raise TransitionError(f"{record['pose_id']}: camera FOV differs from its declared view")
    eye = np.asarray(record.get("eye_render_m"), dtype=np.float64)
    target = np.asarray(record.get("target_render_m"), dtype=np.float64)
    if eye.shape != (3,) or target.shape != (3,) or not np.isfinite(eye).all() or not np.isfinite(target).all():
        raise TransitionError(f"{record['pose_id']}: invalid camera eye or target")
    expected_eye = pilot_render + np.array([0.0, height, -radius], dtype=np.float64)
    facing = str(record.get("camera_facing", ""))
    if facing not in {"outbound", "return"}:
        raise TransitionError(f"{record['pose_id']}: invalid camera facing direction")
    target_sign = -1.0 if facing == "outbound" else 1.0
    expected_target = np.array(
        [pilot_render[0], pilot_render[1], expected_eye[2] + target_sign * lookahead],
        dtype=np.float64,
    )
    if not np.allclose(eye, expected_eye, rtol=0.0, atol=1e-6):
        raise TransitionError(f"{record['pose_id']}: camera eye does not match the fixed pilot-relative path")
    if not np.allclose(target, expected_target, rtol=0.0, atol=1e-6):
        raise TransitionError(f"{record['pose_id']}: camera target does not match the fixed facing direction")
    forward = np.asarray(record.get("camera_forward_render"), dtype=np.float64)
    right = np.asarray(record.get("camera_right_render"), dtype=np.float64)
    up = np.asarray(record.get("camera_up_render"), dtype=np.float64)
    if any(vector.shape != (3,) or not np.isfinite(vector).all() for vector in (forward, right, up)):
        raise TransitionError(f"{record['pose_id']}: invalid camera basis")
    if any(not math.isclose(float(np.linalg.norm(vector)), 1.0, abs_tol=1e-4) for vector in (forward, right, up)):
        raise TransitionError(f"{record['pose_id']}: camera basis vectors are not normalized")
    direction = expected_target - expected_eye
    direction /= np.linalg.norm(direction)
    if not math.isclose(float(np.dot(forward, direction)), 1.0, abs_tol=1e-4):
        raise TransitionError(f"{record['pose_id']}: recorded camera forward vector misses the target")
    if any(abs(float(np.dot(a, b))) > 1e-4 for a, b in ((forward, right), (forward, up), (right, up))):
        raise TransitionError(f"{record['pose_id']}: camera basis is not orthogonal")


def _load_manifest(run_dir: Path) -> tuple[dict[str, Any], dict[str, dict[str, dict[str, Any]]]]:
    manifest_path = run_dir / "transition-manifest.json"
    if not manifest_path.is_file():
        raise TransitionError(f"missing transition manifest: {manifest_path}")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise TransitionError(f"cannot read {manifest_path}: {error}") from error
    if manifest.get("format") != FORMAT or manifest.get("complete") is not True:
        raise TransitionError(f"{manifest_path}: unsupported or incomplete capture manifest")
    if manifest.get("mode") != "moving_boundary_diagnostic":
        raise TransitionError(f"{manifest_path}: capture mode mismatch")
    if manifest.get("field") != "res://data/fields/default.json" or manifest.get("field_id") != "default":
        raise TransitionError(f"{manifest_path}: capture must use the default production field")
    pilot_render = np.asarray(manifest.get("pilot_render_m"), dtype=np.float64)
    if pilot_render.shape != (3,) or not np.isfinite(pilot_render).all():
        raise TransitionError(f"{manifest_path}: invalid pilot render position")
    viewport = manifest.get("viewport", {})
    if (
        viewport.get("width") != WIDTH
        or viewport.get("height") != HEIGHT
        or viewport.get("msaa_label") != "MSAA_4X"
        or not isinstance(viewport.get("msaa_3d"), int)
    ):
        raise TransitionError(f"{manifest_path}: expected 1280×720 MSAA4 viewport")
    if manifest.get("renderer_method") != "gl_compatibility":
        raise TransitionError(f"{manifest_path}: capture must use the Compatibility renderer")
    if manifest.get("quality_tier") not in {"low", "balanced", "high"}:
        raise TransitionError(f"{manifest_path}: invalid quality tier")
    if manifest.get("material_profile") not in {"default", "enhanced"}:
        raise TransitionError(f"{manifest_path}: invalid material profile")
    source_identity = manifest.get("source_identity", {})
    source_hashes = source_identity.get("files_sha256", {})
    if not source_hashes or any(not _is_sha256(value) for value in source_hashes.values()):
        raise TransitionError(f"{manifest_path}: required source hashes are missing or invalid")
    if source_identity.get("field_sha256") != manifest.get("field_sha256") or not _is_sha256(manifest.get("field_sha256")):
        raise TransitionError(f"{manifest_path}: field source identity mismatch")
    scenery_options = manifest.get("scenery_options", {})
    scenery_file_path = source_identity.get("scenery_file_path")
    scenery_file_sha256 = source_identity.get("scenery_file_sha256")
    if (
        not isinstance(scenery_file_path, str)
        or scenery_file_path != "res://data/scenery/default.json"
        or not _is_sha256(scenery_file_sha256)
        or scenery_options.get("file") != scenery_file_path
        or scenery_options.get("file_sha256") != scenery_file_sha256
        or scenery_options.get("quality") != manifest.get("quality_tier")
        or scenery_options.get("theme") != ""
        or scenery_options.get("file_explicit") is not False
        or scenery_options.get("tree_wind") is not False
        or scenery_options.get("tree_cell_size_m") != 0.0
        or scenery_options.get("audio") is not False
        or scenery_options.get("birds") is not False
    ):
        raise TransitionError(f"{manifest_path}: selected scenery source/options identity is incomplete")
    scene_identity = manifest.get("scene_identity", {})
    if (
        scene_identity.get("imported") is not True
        or scene_identity.get("node_path") != "NearGrass"
        or scene_identity.get("ground_control", "").find("ground meshes") < 0
        or int(scene_identity.get("clumps", 0)) <= 0
        or int(scene_identity.get("source_triangles", 0)) <= 0
        or not _is_sha256(scene_identity.get("placement_sha256"))
        or not _is_sha256(scene_identity.get("mesh_arrays_sha256"))
    ):
        raise TransitionError(f"{manifest_path}: imported grass identity/control contract is incomplete")
    if manifest.get("near_detail_control", "").find("only Field/NearGrass.visible") < 0:
        raise TransitionError(f"{manifest_path}: hidden reference does not isolate imported grass")
    if manifest.get("interpretation", "").find("pop threshold") < 0:
        raise TransitionError(f"{manifest_path}: diagnostic limits are not stated")

    raw_records = manifest.get("captures")
    if not isinstance(raw_records, list) or len(raw_records) != 184:
        raise TransitionError(f"{manifest_path}: expected 184 image records, got {len(raw_records) if isinstance(raw_records, list) else 'invalid'}")
    grouped: dict[str, dict[str, dict[str, Any]]] = {}
    for record in raw_records:
        if not isinstance(record, dict):
            raise TransitionError(f"{manifest_path}: capture record is not an object")
        pose_id = str(record.get("pose_id", ""))
        state = str(record.get("state", ""))
        if not pose_id or state not in {"visible", "grass_hidden"}:
            raise TransitionError(f"{manifest_path}: capture record has invalid pose/state")
        images = grouped.setdefault(pose_id, {})
        if state in images:
            raise TransitionError(f"{manifest_path}: duplicate {state} record for {pose_id}")
        image_path = safe_child(run_dir, str(record.get("image", "")))
        if not image_path.is_file():
            raise TransitionError(f"{manifest_path}: missing capture image {image_path.name}")
        digest = sha256_file(image_path)
        if digest != record.get("image_sha256"):
            raise TransitionError(f"{image_path.name}: image hash mismatch")
        if not _is_sha256(digest):
            raise TransitionError(f"{image_path.name}: invalid SHA-256")
        try:
            with Image.open(image_path) as image:
                dimensions = image.size
        except OSError as error:
            raise TransitionError(f"cannot inspect capture image {image_path}: {error}") from error
        if dimensions != (WIDTH, HEIGHT):
            raise TransitionError(f"{image_path.name}: expected {WIDTH}×{HEIGHT}, got {dimensions}")
        if record.get("ground_detail_enabled") is not True:
            raise TransitionError(f"{pose_id}: ground near-detail control was disabled")
        images[state] = record
    if len(grouped) != 92:
        raise TransitionError(f"{manifest_path}: expected 92 matched poses, got {len(grouped)}")

    expected_pose_groups: set[tuple[str, str]] = set()
    sequences_by_group: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for pose_id, records in grouped.items():
        if set(records) != {"visible", "grass_hidden"}:
            raise TransitionError(f"{manifest_path}: incomplete visible/hidden pair for {pose_id}")
        visible, hidden = records["visible"], records["grass_hidden"]
        validate_pair_metadata(visible, hidden)
        height_case = str(visible.get("height_case", ""))
        sequence_id = str(visible.get("sequence_id", ""))
        if height_case not in CAMERA_CASES or sequence_id not in SEQUENCES:
            raise TransitionError(f"{pose_id}: unknown height or sequence")
        expected_pose_groups.add((height_case, sequence_id))
        sequences_by_group.setdefault((height_case, sequence_id), []).append(visible)
    expected_groups = {(height, sequence) for height in CAMERA_CASES for sequence in SEQUENCES}
    if expected_pose_groups != expected_groups:
        raise TransitionError(f"{manifest_path}: missing height/sequence coverage")
    for (height_case, sequence_id), records in sequences_by_group.items():
        direction, mode, is_cut = SEQUENCES[sequence_id]
        expected_radii = [29.75, 30.25] if sequence_id == "camera_cut_outbound" else (
            [30.25, 29.75] if sequence_id == "camera_cut_return" else list(RADII_M)
        )
        if direction == "return" and not is_cut:
            expected_radii.reverse()
        records.sort(key=lambda item: int(item["sequence_index"]))
        if len(records) != len(expected_radii):
            raise TransitionError(f"{height_case}/{sequence_id}: wrong number of poses")
        for index, (record, expected_radius) in enumerate(zip(records, expected_radii, strict=True)):
            if int(record.get("sequence_index", -1)) != index or int(record.get("sequence_length", -1)) != len(expected_radii):
                raise TransitionError(f"{record['pose_id']}: sequence ordering metadata mismatch")
            if not math.isclose(float(record.get("camera_radius_from_pilot_m", math.nan)), expected_radius, abs_tol=1e-6):
                raise TransitionError(f"{record['pose_id']}: camera radius differs from the fixed trajectory")
            validate_pose_geometry(record, pilot_render)
            expected_wind = [0.0, 0.0, 0.0] if mode == "calm" else [5.0, 0.0, 0.0]
            if record.get("wind_render_mps") != expected_wind:
                raise TransitionError(f"{record['pose_id']}: explicit wind protocol mismatch")
            clock = float(record.get("shader_clock_s", math.nan))
            expected_clock = 0.0 if mode == "calm" else (
                1.0 if mode == "cut" else index / (len(expected_radii) - 1) * 3.0
            )
            if not math.isclose(clock, expected_clock, abs_tol=1e-6):
                raise TransitionError(f"{record['pose_id']}: shader-clock protocol mismatch")
            expected_kind = "camera_cut" if is_cut else "moving_sweep"
            if (
                bool(record.get("camera_cut")) != is_cut
                or record.get("camera_facing") != direction
                or record.get("sequence_direction") != direction
                or record.get("sequence_kind") != expected_kind
            ):
                raise TransitionError(f"{record['pose_id']}: camera direction/cut metadata mismatch")
    return manifest, grouped


def _is_sha256(value: Any) -> bool:
    if not isinstance(value, str) or len(value) != 64:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return True


def _load_pose_images(run_dir: Path, pair: dict[str, dict[str, Any]]) -> tuple[np.ndarray, np.ndarray]:
    visible = pair["visible"]
    hidden = pair["grass_hidden"]
    return load_rgb(safe_child(run_dir, str(visible["image"]))), load_rgb(safe_child(run_dir, str(hidden["image"])))


def _radial_pair_summary(visible: np.ndarray, hidden: np.ndarray, radius: np.ndarray,
                         valid: np.ndarray) -> list[dict[str, Any]]:
    delta = np.abs(visible.astype(np.int16) - hidden.astype(np.int16))
    changed = delta.max(axis=2) != 0
    result: list[dict[str, Any]] = []
    for low, high in RADIAL_BINS:
        mask = valid & (radius >= low) & (radius < high)
        pixels = int(np.count_nonzero(mask))
        values = delta[mask]
        result.append({
            "root_radius_m": [low, high],
            "screen_pixels": pixels,
            "changed_pixels": int(np.count_nonzero(changed & mask)),
            "mean_abs_rgb_delta": float(values.mean()) if values.size else None,
        })
    return result


def _pose_summary(run_dir: Path, pair: dict[str, dict[str, Any]], pilot_render: np.ndarray) -> dict[str, Any]:
    visible_record = pair["visible"]
    visible, hidden = _load_pose_images(run_dir, pair)
    metrics = summarize_delta(hidden, visible)
    radius, valid = ground_radius_grid(visible_record, pilot_render)
    return {
        "pose_id": visible_record["pose_id"],
        "sequence_id": visible_record["sequence_id"],
        "height_case": visible_record["height_case"],
        "camera_radius_from_pilot_m": visible_record["camera_radius_from_pilot_m"],
        "shader_clock_s": visible_record["shader_clock_s"],
        "wind_render_mps": visible_record["wind_render_mps"],
        "grass_contribution": metrics,
        "projected_root_radius_bins": _radial_pair_summary(visible, hidden, radius, valid),
    }


def _camera_distance(first: dict[str, Any], second: dict[str, Any]) -> float:
    a = np.asarray(first["eye_render_m"], dtype=np.float64)
    b = np.asarray(second["eye_render_m"], dtype=np.float64)
    return float(np.linalg.norm((b - a)[[0, 2]]))


def _sequence_summary(run_dir: Path, sequence_records: list[dict[str, Any]],
                      pairs: dict[str, dict[str, dict[str, Any]]]) -> dict[str, Any]:
    ordered = sorted(sequence_records, key=lambda item: int(item["sequence_index"]))
    steps: list[dict[str, Any]] = []
    for previous, current in zip(ordered, ordered[1:]):
        previous_pair = _load_pose_images(run_dir, pairs[str(previous["pose_id"])])
        current_pair = _load_pose_images(run_dir, pairs[str(current["pose_id"])])
        distance = _camera_distance(previous, current)
        metrics = summarize_temporal_step(
            previous_pair[0], previous_pair[1], current_pair[0], current_pair[1], distance
        )
        metrics.update({
            "start_radius_m": float(previous["camera_radius_from_pilot_m"]),
            "end_radius_m": float(current["camera_radius_from_pilot_m"]),
            "start_clock_s": float(previous["shader_clock_s"]),
            "end_clock_s": float(current["shader_clock_s"]),
            "camera_facing": str(current["camera_facing"]),
        })
        steps.append(metrics)
    return {
        "height_case": ordered[0]["height_case"],
        "sequence_id": ordered[0]["sequence_id"],
        "sequence_kind": ordered[0]["sequence_kind"],
        "camera_facing": ordered[0]["camera_facing"],
        "pose_count": len(ordered),
        "steps": steps,
        "boundary_refinement": boundary_control_ratio(steps),
        "interpretation": "optical flow, changing perspective and wind are expected; the residual is descriptive only",
    }


def _analyze_run(run_dir: Path, manifest: dict[str, Any], pairs: dict[str, dict[str, dict[str, Any]]]) -> dict[str, Any]:
    pilot_render = np.asarray(manifest.get("pilot_render_m"), dtype=np.float64)
    if pilot_render.shape != (3,) or not np.isfinite(pilot_render).all():
        raise TransitionError(f"{run_dir}: invalid pilot render position")
    pair_summaries: list[dict[str, Any]] = []
    total_changed_pixels = 0
    for pair in pairs.values():
        summary = _pose_summary(run_dir, pair, pilot_render)
        pair_summaries.append(summary)
        total_changed_pixels += int(summary["grass_contribution"]["changed_pixels"])
    sequence_records: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for pair in pairs.values():
        record = pair["visible"]
        key = (str(record["height_case"]), str(record["sequence_id"]))
        sequence_records.setdefault(key, []).append(record)
    sequence_summaries = [
        _sequence_summary(run_dir, records, pairs)
        for _, records in sorted(sequence_records.items())
    ]
    if total_changed_pixels == 0:
        raise TransitionError(f"{run_dir}: visible imported grass changed no pixels in any matched view")
    return {
        "capture_directory": str(run_dir.resolve()),
        "capture_manifest_sha256": sha256_file(run_dir / "transition-manifest.json"),
        "quality_tier": manifest["quality_tier"],
        "material_profile": manifest["material_profile"],
        "engine": manifest.get("engine"),
        "renderer": {
            "method": manifest.get("renderer_method"),
            "driver": manifest.get("renderer_driver"),
            "adapter": manifest.get("renderer_adapter"),
        },
        "source_identity": manifest.get("source_identity"),
        "scene_identity": manifest.get("scene_identity"),
        "pose_count": len(pairs),
        "image_count": len(pairs) * 2,
        "grass_contributed_pixels_across_pose_pairs_sum": total_changed_pixels,
        "pose_pairs": pair_summaries,
        "sequences": sequence_summaries,
        "limits": manifest.get("limits", []),
    }


def _analyze_inputs(capture_dirs: list[Path]) -> dict[str, Any]:
    runs: list[dict[str, Any]] = []
    profiles: set[tuple[str, str]] = set()
    base_source_identity: dict[str, Any] | None = None
    base_field_hash: str | None = None
    base_engine: Any = None
    base_renderer: tuple[Any, ...] | None = None
    for run_dir_value in capture_dirs:
        run_dir = run_dir_value.resolve()
        manifest, pairs = _load_manifest(run_dir)
        profile_key = (str(manifest["material_profile"]), str(manifest["quality_tier"]))
        if profile_key in profiles:
            raise TransitionError(f"duplicate material/quality capture profile: {profile_key}")
        profiles.add(profile_key)
        source_identity = manifest.get("source_identity", {})
        if base_source_identity is None:
            base_source_identity = source_identity
            base_field_hash = str(manifest["field_sha256"])
            base_engine = manifest.get("engine")
            base_renderer = (manifest.get("renderer_method"), manifest.get("renderer_driver"), manifest.get("renderer_adapter"))
        else:
            if source_identity.get("files_sha256") != base_source_identity.get("files_sha256"):
                raise TransitionError("profiles do not share identical production source identities")
            if any(
                source_identity.get(key) != base_source_identity.get(key)
                for key in ("scenery_file_path", "scenery_file_sha256")
            ):
                raise TransitionError("profiles do not share the same selected scenery source")
            if str(manifest["field_sha256"]) != base_field_hash:
                raise TransitionError("profiles do not share identical field data")
            if manifest.get("engine") != base_engine:
                raise TransitionError("profiles were captured with different engine versions")
            renderer = (manifest.get("renderer_method"), manifest.get("renderer_driver"), manifest.get("renderer_adapter"))
            if renderer != base_renderer:
                raise TransitionError("profiles were captured with different renderer identities")
        runs.append(_analyze_run(run_dir, manifest, pairs))
    seen_profiles = {(run["material_profile"], run["quality_tier"]) for run in runs}
    expected_profiles = {(material, quality) for material in ("default", "enhanced") for quality in ("low", "balanced", "high")}
    return {
        "format": REPORT_FORMAT,
        "complete": True,
        "diagnostic_only": True,
        "status": "diagnostic_complete",
        "profile_grid_complete": seen_profiles == expected_profiles,
        "profile_coverage": [
            {"material_profile": material, "quality_tier": quality, "captured": (material, quality) in seen_profiles}
            for material in ("default", "enhanced") for quality in ("low", "balanced", "high")
        ],
        "interpretation": "Same-pose hidden-reference subtraction attributes the image residual to imported near grass. Temporal residual rates remain descriptive because camera optical motion and perspective are expected.",
        "existing_static_seam_gate": {
            "owner": "tools/grass/check_grass_seam.py",
            "channel_mean_abs_percent_limit": 3.0,
            "flip_p99_limit": 0.1,
            "changed": False,
            "evaluated_by_this_report": False,
        },
        "runs": runs,
    }


def write_new_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("x", encoding="utf-8", newline="\n") as output:
            json.dump(report, output, indent=2, sort_keys=True, allow_nan=False)
            output.write("\n")
    except FileExistsError as error:
        raise TransitionError(f"report path already exists; evidence is never overwritten: {path}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--captures", type=Path, nargs="+", required=True,
                        help="one or more output directories from transition_capture.gd")
    parser.add_argument("--out", type=Path, required=True, help="new JSON report path")
    args = parser.parse_args()
    output = args.out.resolve()
    if output.suffix.lower() != ".json":
        parser.error("--out must have a .json suffix")
    if output.exists():
        parser.error("--out must be new; existing evidence is never overwritten")
    if any(output == (directory.resolve() / "transition-manifest.json") for directory in args.captures):
        parser.error("--out cannot replace a capture manifest")
    try:
        report = _analyze_inputs(args.captures)
        write_new_report(output, report)
    except (OSError, TransitionError, ValueError, KeyError, TypeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(json.dumps({
        "status": report["status"],
        "profile_grid_complete": report["profile_grid_complete"],
        "runs": len(report["runs"]),
        "report": str(output),
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
