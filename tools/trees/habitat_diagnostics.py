#!/usr/bin/env python3
"""Deterministic CPU audit of the field forest layout and its current resources.

All coverage values are geometric proxies for composition. They do not replace
camera captures, terrain surveys, performance measurements, or owner review.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any, Iterable

from place import (
    CROWN_RADIUS_M,
    FAR_RADIUS_MAX_M,
    FAR_RADIUS_MIN_M,
    GAPS,
    NEAR_COUNT,
    NEAR_RADIUS_MAX_M,
    NEAR_RADIUS_MIN_M,
    POSITION_GRID_M,
    _inside_protected_gap,
    generate,
)


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_FIELD = ROOT / "app/data/fields/default.json"
DEFAULT_LAKE = ROOT / "app/data/fields/lake.json"
DEFAULT_SCENERY = ROOT / "app/data/scenery/default.json"
DEFAULT_VEGETATION_CATALOG = ROOT / "app/assets/landscape/vegetation/catalog.json"
DEFAULT_CARD_CATALOG = ROOT / "app/assets/landscape/trees/catalog.json"
DEFAULT_FIELD_LOADER = ROOT / "app/data/field_loader.gd"
DEFAULT_TREELINE = ROOT / "app/render/treeline.gd"
DEFAULT_TREE_WIND = ROOT / "app/render/tree_wind.gdshaderinc"
DEFAULT_PREFABS = ROOT / "app/scenery/prefabs.gd"

FORMAT = "openrc-forest-habitat-diagnostics v2"
DEFAULT_GRID_M = 1.0
SKYLINE_BINS = 1440  # 0.25 degree azimuth samples.
EXPECTED_CARD_IDS = ("CommonTree_1", "CommonTree_3", "Pine_1")
WIND_MAX_SPEED_MPS = 10.0


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object at {path}")
    return value


def _quantity(surface: dict[str, Any], key: str) -> float:
    value = surface[key]
    return float(value["value"] if isinstance(value, dict) else value)


def _surface_bounds(surface: dict[str, Any]) -> tuple[float, float, float, float]:
    north = _quantity(surface, "center_north")
    east = _quantity(surface, "center_east")
    half_north = _quantity(surface, "width_north_south") * 0.5
    half_east = _quantity(surface, "length_east_west") * 0.5
    return north - half_north, north + half_north, east - half_east, east + half_east


def _distance_to_rect(
    north: float,
    east: float,
    bounds: tuple[float, float, float, float],
) -> float:
    north_min, north_max, east_min, east_max = bounds
    delta_north = max(north_min - north, 0.0, north - north_max)
    delta_east = max(east_min - east, 0.0, east - east_max)
    return math.hypot(delta_north, delta_east)


def _distance_to_segment(
    north: float,
    east: float,
    start: tuple[float, float],
    end: tuple[float, float],
) -> float:
    dn = end[0] - start[0]
    de = end[1] - start[1]
    length_squared = dn * dn + de * de
    if length_squared == 0.0:
        return math.hypot(north - start[0], east - start[1])
    t = ((north - start[0]) * dn + (east - start[1]) * de) / length_squared
    t = max(0.0, min(1.0, t))
    return math.hypot(north - (start[0] + t * dn), east - (start[1] + t * de))


def _track_data(scenery: dict[str, Any]) -> list[dict[str, Any]]:
    tracks: list[dict[str, Any]] = []
    for group in scenery.get("groups", []):
        if group.get("type") != "track":
            continue
        raw = group.get("points", {}).get("value", [])
        points = [(float(point[0]), float(point[1])) for point in raw]
        if len(points) < 2:
            continue
        width = float(group.get("width", {}).get("value", 0.0))
        tracks.append({"id": str(group.get("id", "")), "width_m": width, "points": points})
    return tracks


def _track_distance(north: float, east: float, track: dict[str, Any]) -> float:
    points = track["points"]
    return min(
        _distance_to_segment(north, east, points[index], points[index + 1])
        for index in range(len(points) - 1)
    )


def _lake_bank_polygon(lake: dict[str, Any]) -> dict[str, Any]:
    origin = lake["origin"]
    origin_north = float(origin["north_m"])
    origin_east = float(origin["east_m"])
    points = [
        (origin_north + float(point[0]), origin_east + float(point[1]))
        for point in lake["bank_offsets_ne_m"]
    ]
    return {
        "points": points,
        "bounds": (
            min(point[0] for point in points),
            max(point[0] for point in points),
            min(point[1] for point in points),
            max(point[1] for point in points),
        ),
    }


def _point_in_polygon(north: float, east: float, polygon: list[tuple[float, float]]) -> bool:
    inside = False
    for index, (first_north, first_east) in enumerate(polygon):
        second_north, second_east = polygon[(index + 1) % len(polygon)]
        if _distance_to_segment(north, east, (first_north, first_east), (second_north, second_east)) <= 1e-9:
            return True
        if (first_north > north) != (second_north > north):
            crossing_east = (second_east - first_east) * (north - first_north) / (second_north - first_north) + first_east
            if east < crossing_east:
                inside = not inside
    return inside


def _distance_to_polygon(north: float, east: float, polygon: list[tuple[float, float]]) -> float:
    return min(
        _distance_to_segment(north, east, polygon[index], polygon[(index + 1) % len(polygon)])
        for index in range(len(polygon))
    )


def _lake_bank_hit(north: float, east: float, lake_bank: dict[str, Any], clearance_m: float) -> bool:
    north_min, north_max, east_min, east_max = lake_bank["bounds"]
    if north < north_min - clearance_m or north > north_max + clearance_m \
            or east < east_min - clearance_m or east > east_max + clearance_m:
        return False
    polygon = lake_bank["points"]
    return _point_in_polygon(north, east, polygon) or _distance_to_polygon(north, east, polygon) <= clearance_m


def _tree_offset_positions(object_data: dict[str, Any]) -> list[tuple[float, float, float]]:
    return [tuple(float(axis) for axis in point) for point in object_data["positions"]["value"]]


def _current_tree_positions(field: dict[str, Any]) -> list[tuple[float, float, float]]:
    for obj in field.get("objects", []):
        if obj.get("type") == "treeline":
            return _tree_offset_positions(obj)
    return []


def _read_gdscript_number(path: Path, name: str) -> float:
    source = path.read_text(encoding="utf-8")
    match = re.search(rf"^const\s+{re.escape(name)}\s*:[^=]+?=\s*([-+0-9.eE]+)", source, re.MULTILINE)
    if match is None:
        raise ValueError(f"could not read {name} from {path}")
    return float(match.group(1))


def _runtime_contracts(
    field_loader_path: Path,
    treeline_path: Path,
    tree_wind_path: Path,
) -> dict[str, float | int]:
    loader_source = field_loader_path.read_text(encoding="utf-8")
    count_match = re.search(r"^const\s+MAX_TREELINE_POSITIONS\s*:\s*int\s*=\s*(\d+)", loader_source, re.MULTILINE)
    if count_match is None:
        raise ValueError(f"could not read MAX_TREELINE_POSITIONS from {field_loader_path}")
    treeline_source = treeline_path.read_text(encoding="utf-8")
    height_match = re.search(
        r"(?:var\s+)?height(?:\s*:\s*float)?\s*=\s*([0-9.]+)\s*\+\s*([0-9.]+)\s*\*\s*float\(h\s*%\s*(\d+)\)\s*/\s*(\d+(?:\.\d+)?)",
        treeline_source,
    )
    if height_match is None:
        raise ValueError(f"could not read the tree height identity formula from {treeline_path}")
    wind_lean = _read_gdscript_number(treeline_path, "WIND_LEAN_M")
    shader_wind_source = tree_wind_path.read_text(encoding="utf-8")
    shader_match = re.search(r"TREE_WIND_LEAN_M\s*=\s*([-+0-9.eE]+)", shader_wind_source)
    if shader_match is None:
        raise ValueError(f"could not read TREE_WIND_LEAN_M from {tree_wind_path}")
    shader_wind_lean = float(shader_match.group(1))
    if not math.isclose(wind_lean, shader_wind_lean, rel_tol=0.0, abs_tol=1e-12):
        raise ValueError("CPU tree bounds and shader wind lean disagree")
    return {
        "max_treeline_positions": int(count_match.group(1)),
        "card_radius_m": _read_gdscript_number(field_loader_path, "TREE_CARD_MAX_HORIZONTAL_RADIUS_M"),
        "flight_corridor_half_width_m": _read_gdscript_number(field_loader_path, "TREE_FLIGHT_CORRIDOR_HALF_WIDTH_M"),
        "wind_lean_m": wind_lean,
        "wind_speed_cap_mps": WIND_MAX_SPEED_MPS,
        "tree_height_min_m": float(height_match.group(1)),
        "tree_height_span_m": float(height_match.group(2)),
        "tree_height_hash_modulus": int(height_match.group(3)),
        "tree_height_hash_divisor": float(height_match.group(4)),
    }


def _frame_sizes(card_catalog: dict[str, Any]) -> tuple[list[str], list[float]]:
    species = card_catalog.get("species", [])
    ids = [str(entry["id"]) for entry in species]
    sizes = [float(entry["frame_size_m"]) for entry in species]
    if not ids or len(ids) != len(sizes):
        raise ValueError("tree-card catalog has no usable species")
    if ids != list(EXPECTED_CARD_IDS):
        raise ValueError(f"unexpected tree-card order: {ids}")
    return ids, sizes


def _identity(
    north: float,
    east: float,
    runtime: dict[str, float | int],
    card_sizes: list[float],
) -> dict[str, float | int]:
    qn = round(north / POSITION_GRID_M)
    qe = round(east / POSITION_GRID_M)
    legacy_offset = 2400
    offset = 8192 if qn < -legacy_offset or qe < -legacy_offset else legacy_offset
    h = ((qn + offset) * 7381 + (qe + offset) * 19391 + 6113) % 65521
    h = (h * 25173 + 13849) % 65521
    second_hash = (h * 25173 + 13849) % 65521
    height_min = float(runtime["tree_height_min_m"])
    height_span = float(runtime["tree_height_span_m"])
    height_modulus = int(runtime["tree_height_hash_modulus"])
    height_divisor = float(runtime["tree_height_hash_divisor"])
    height = height_min + height_span * float(h % height_modulus) / height_divisor
    species = h % len(card_sizes)
    frame_size = card_sizes[species]
    half_width = frame_size * height * 0.5
    highest_vertex_y = (0.5 + frame_size * 0.5) * height
    max_vertex_radius = math.hypot(half_width, highest_vertex_y)
    angle = float(runtime["wind_lean_m"]) / height
    wind_sweep = 2.0 * max_vertex_radius * math.sin(angle * 0.5)
    return {
        "height_m": height,
        "species_index": species,
        "yaw_rad": math.tau * float(second_hash) / 65521.0,
        "frame_size_m": frame_size,
        "wind_sweep_m": wind_sweep,
        "horizontal_radius_m": half_width + wind_sweep,
        "quad_top_m": highest_vertex_y,
    }


def _inside_global_clearances(
    north_offset: float,
    east_offset: float,
    field: dict[str, Any],
    scenery_tracks: list[dict[str, Any]],
    lake_bank: dict[str, Any],
    runtime: dict[str, float | int],
    crown_radius_m: float,
    ring: tuple[float, float],
) -> bool:
    if not ring[0] <= math.hypot(north_offset, east_offset) <= ring[1]:
        return False
    if _inside_protected_gap(north_offset, east_offset, crown_radius_m):
        return False

    pilot_north = float(field["pilot"]["north"]["value"])
    pilot_east = float(field["pilot"]["east"]["value"])
    north = pilot_north + north_offset
    east = pilot_east + east_offset
    if _lake_bank_hit(north, east, lake_bank, crown_radius_m):
        return False
    surfaces = field.get("surfaces", [])

    rough_contains = False
    for surface in surfaces:
        surface_type = surface.get("type")
        bounds = _surface_bounds(surface)
        if surface_type == "rough":
            north_min, north_max, east_min, east_max = bounds
            if (
                north - crown_radius_m >= north_min
                and north + crown_radius_m <= north_max
                and east - crown_radius_m >= east_min
                and east + crown_radius_m <= east_max
            ):
                rough_contains = True
        elif surface_type == "rotorpad":
            if _distance_to_rect(north, east, bounds) <= (
                float(runtime["flight_corridor_half_width_m"]) + crown_radius_m
            ):
                return False
        elif surface_type in ("runway", "mown"):
            strip_north = _quantity(surface, "center_north")
            strip_width = _quantity(surface, "width_north_south")
            required = strip_width * 0.5 + float(runtime["flight_corridor_half_width_m"]) + crown_radius_m
            if abs(north - strip_north) <= required:
                return False
    if not rough_contains:
        return False

    for track in scenery_tracks:
        if _track_distance(north, east, track) <= track["width_m"] * 0.5 + crown_radius_m:
            return False
    return True


def _point_in_patch(north: float, east: float, patch: dict[str, Any], recipe: str) -> bool:
    center_north = float(patch.get("north_m", 0.0))
    center_east = float(patch.get("east_m", 0.0))
    dn = north - center_north
    de = east - center_east
    if recipe == "existing":
        return math.hypot(dn, de) <= float(patch["radius_m"])

    orientation = float(patch["orientation_rad"])
    c = math.cos(orientation)
    s = math.sin(orientation)
    local_north = (dn * c) + (de * s)
    local_east = (-dn * s) + (de * c)
    semi_major = float(patch["semi_major_m"])
    semi_minor = float(patch["semi_minor_m"])
    x = local_north / semi_major
    y = local_east / semi_minor
    radial = math.hypot(x, y)
    if radial == 0.0:
        return True
    angle = math.atan2(y, x)
    phase = float(patch["outline_phase_rad"])
    notch_angle = float(patch["notch_angle_rad"])
    notch_width = float(patch["notch_width_rad"])
    notch_depth = float(patch["outline_notch_depth"])
    lobes = (
        0.105 * math.sin(3.0 * angle + phase)
        + 0.065 * math.sin(5.0 * angle - phase * 0.7)
        + 0.035 * math.cos(7.0 * angle + phase * 0.4)
    )
    notch_distance = abs((angle - notch_angle + math.pi) % math.tau - math.pi)
    notch = max(0.0, 1.0 - notch_distance / notch_width)
    scale = max(0.72, min(1.2, 1.0 + lobes - notch_depth * notch * notch))
    return radial <= scale


def _grid_patch_measurement(
    patch: dict[str, Any],
    points: list[tuple[float, float, float]],
    recipe: str,
    field: dict[str, Any],
    tracks: list[dict[str, Any]],
    lake_bank: dict[str, Any],
    runtime: dict[str, float | int],
    card_sizes: list[float],
    cell_size_m: float,
) -> dict[str, float | int]:
    center_north = float(patch.get("north_m", 0.0))
    center_east = float(patch.get("east_m", 0.0))
    if recipe == "existing":
        half_north = half_east = float(patch["radius_m"])
    else:
        half_north = half_east = float(patch["semi_major_m"]) * 1.2
    i_min = math.floor((center_north - half_north) / cell_size_m)
    i_max = math.ceil((center_north + half_north) / cell_size_m)
    j_min = math.floor((center_east - half_east) / cell_size_m)
    j_max = math.ceil((center_east + half_east) / cell_size_m)
    eligible_cells: set[tuple[int, int]] = set()
    for i in range(i_min, i_max):
        north = (i + 0.5) * cell_size_m
        for j in range(j_min, j_max):
            east = (j + 0.5) * cell_size_m
            if not _point_in_patch(north, east, patch, recipe):
                continue
            if _inside_global_clearances(
                north,
                east,
                field,
                tracks,
                lake_bank,
                runtime,
                float(runtime["card_radius_m"]),
                (FAR_RADIUS_MIN_M, FAR_RADIUS_MAX_M),
            ):
                eligible_cells.add((i, j))

    occupied_cells: set[tuple[int, int]] = set()
    for north, east, _down in points:
        shape = _identity(north, east, runtime, card_sizes)
        radius = float(shape["horizontal_radius_m"])
        center_i = math.floor(north / cell_size_m)
        center_j = math.floor(east / cell_size_m)
        reach = math.ceil(radius / cell_size_m) + 1
        for i in range(center_i - reach, center_i + reach + 1):
            cell_north = (i + 0.5) * cell_size_m
            for j in range(center_j - reach, center_j + reach + 1):
                cell = (i, j)
                if cell in eligible_cells and math.hypot(cell_north - north, (j + 0.5) * cell_size_m - east) <= radius:
                    occupied_cells.add(cell)

    eligible_area_m2 = len(eligible_cells) * cell_size_m * cell_size_m
    occupied_area_m2 = len(occupied_cells) * cell_size_m * cell_size_m
    return {
        "eligible_area_ha": eligible_area_m2 / 10000.0,
        "stems_per_ha": len(points) / (eligible_area_m2 / 10000.0) if eligible_area_m2 else 0.0,
        "wind_swept_card_disk_occupancy_fraction": occupied_area_m2 / eligible_area_m2 if eligible_area_m2 else 0.0,
        "cell_size_m": cell_size_m,
        "eligible_cells": len(eligible_cells),
        "occupied_cells": len(occupied_cells),
    }


def _quantile(sorted_values: list[float], fraction: float) -> float:
    if not sorted_values:
        return 0.0
    location = (len(sorted_values) - 1) * fraction
    low = math.floor(location)
    high = math.ceil(location)
    if low == high:
        return sorted_values[low]
    weight = location - low
    return sorted_values[low] * (1.0 - weight) + sorted_values[high] * weight


def _summary(values: Iterable[float]) -> dict[str, float | int]:
    ordered = sorted(float(value) for value in values)
    if not ordered:
        return {"count": 0, "min_m": 0.0, "p05_m": 0.0, "p25_m": 0.0, "median_m": 0.0, "p75_m": 0.0, "p95_m": 0.0, "max_m": 0.0}
    return {
        "count": len(ordered),
        "min_m": ordered[0],
        "p05_m": _quantile(ordered, 0.05),
        "p25_m": _quantile(ordered, 0.25),
        "median_m": _quantile(ordered, 0.5),
        "p75_m": _quantile(ordered, 0.75),
        "p95_m": _quantile(ordered, 0.95),
        "max_m": ordered[-1],
    }


def _nearest_neighbors(points: list[tuple[float, float, float]]) -> dict[str, float | int]:
    distances = _nearest_neighbor_values(points)
    return _summary(distances)


def _nearest_neighbor_values(points: list[tuple[float, float, float]]) -> list[float]:
    distances: list[float] = []
    for index, point in enumerate(points):
        nearest_squared = math.inf
        for other_index, other in enumerate(points):
            if index == other_index:
                continue
            dn = point[0] - other[0]
            de = point[1] - other[1]
            nearest_squared = min(nearest_squared, dn * dn + de * de)
        distances.append(math.sqrt(nearest_squared) if math.isfinite(nearest_squared) else 0.0)
    return distances


def _cyclic_gaps(covered: list[bool]) -> list[dict[str, float]]:
    if not covered or all(covered):
        return []
    count = len(covered)
    start = next(index for index, value in enumerate(covered) if value and not covered[(index - 1) % count])
    gaps: list[dict[str, float]] = []
    index = (start + 1) % count
    visited = 1
    while visited <= count:
        if covered[index]:
            index = (index + 1) % count
            visited += 1
            continue
        begin = index
        length = 0
        while visited <= count and not covered[index]:
            length += 1
            index = (index + 1) % count
            visited += 1
        begin_angle = begin * 360.0 / count
        gaps.append({
            "start_deg": begin_angle,
            "width_deg": length * 360.0 / count,
            "center_deg": (begin_angle + length * 180.0 / count) % 360.0,
        })
    return sorted(gaps, key=lambda gap: (-gap["width_deg"], gap["center_deg"]))


def _skyline_proxy(
    points: list[tuple[float, float, float]],
    runtime: dict[str, float | int],
    card_sizes: list[float],
) -> dict[str, Any]:
    covered = [False] * SKYLINE_BINS
    for north, east, _down in points:
        distance = math.hypot(north, east)
        if distance == 0.0:
            covered[:] = [True] * SKYLINE_BINS
            break
        shape = _identity(north, east, runtime, card_sizes)
        half_angle = math.asin(min(1.0, float(shape["horizontal_radius_m"]) / distance))
        center_angle = math.atan2(east, north) % math.tau
        center_bin = int(center_angle / math.tau * SKYLINE_BINS)
        radius_bins = math.ceil(half_angle / math.tau * SKYLINE_BINS)
        for offset in range(-radius_bins, radius_bins + 1):
            covered[(center_bin + offset) % SKYLINE_BINS] = True
    gaps = _cyclic_gaps(covered)
    return {
        "angular_coverage_percent": (sum(covered) / SKYLINE_BINS) * 100.0,
        "open_azimuth_intervals": gaps,
        "largest_open_interval_deg": max((gap["width_deg"] for gap in gaps), default=0.0),
        "sample_step_deg": 360.0 / SKYLINE_BINS,
        "interpretation": "Horizontal wind-swept card-envelope proxy from the pilot; no elevation, alpha texture, terrain, camera FOV, or lighting is evaluated.",
    }


def _patch_points(
    all_points: list[tuple[float, float, float]],
    patch: dict[str, Any],
    near_count: int,
) -> list[tuple[float, float, float]]:
    start = int(patch.get("start_index", 0))
    end = int(patch.get("end_index", 0))
    return all_points[near_count + start:near_count + end]


def _patch_metrics(
    patches: list[dict[str, Any]],
    all_points: list[tuple[float, float, float]],
    recipe: str,
    field: dict[str, Any],
    tracks: list[dict[str, Any]],
    lake_bank: dict[str, Any],
    runtime: dict[str, float | int],
    card_sizes: list[float],
    cell_size_m: float,
) -> dict[str, Any]:
    results: list[dict[str, Any]] = []
    for patch in patches:
        points = _patch_points(all_points, patch, NEAR_COUNT)
        measurement = _grid_patch_measurement(
            patch,
            points,
            recipe,
            field,
            tracks,
            lake_bank,
            runtime,
            card_sizes,
            cell_size_m,
        )
        results.append({
            "patch_index": len(results),
            "sector": int(patch.get("sector", -1)),
            "tree_count": len(points),
            "center_north_m": float(patch.get("north_m", 0.0)),
            "center_east_m": float(patch.get("east_m", 0.0)),
            "shape": "circle" if recipe == "existing" else "irregular_anisotropic_ellipse",
            **measurement,
            "nearest_neighbor_m": _nearest_neighbors(points),
        })
    total_area = sum(float(patch["eligible_area_ha"]) for patch in results)
    total_occupied_area = sum(
        float(patch["eligible_area_ha"]) * float(patch["wind_swept_card_disk_occupancy_fraction"])
        for patch in results
    )
    all_far = all_points[NEAR_COUNT:]
    return {
        "patches": results,
        "eligible_patch_area_ha": total_area,
        "far_stems_per_ha_of_eligible_patch_area": len(all_far) / total_area if total_area else 0.0,
        "eligible_area_weighted_card_disk_occupancy_fraction": total_occupied_area / total_area if total_area else 0.0,
        "patch_stems_per_ha_summary": _summary([float(patch["stems_per_ha"]) for patch in results]),
        "patch_occupancy_summary": _summary([float(patch["wind_swept_card_disk_occupancy_fraction"]) for patch in results]),
        "cell_size_m": cell_size_m,
        "patch_tree_count_range": [min((int(patch["tree_count"]) for patch in results), default=0), max((int(patch["tree_count"]) for patch in results), default=0)],
        "interpretation": "Patch area is a deterministic center-sampled mask clipped by the far ring, protected gaps, full card/wind envelope, field surfaces, the authoritative lake-bank polygon, and current scenery tracks. Card occupancy treats each crossed-card tree as a conservative disk using its deterministic height and wind sweep; it is an upper-envelope proxy, not visible leaf cover.",
    }


def _clearance_report(
    points: list[tuple[float, float, float]],
    field: dict[str, Any],
    tracks: list[dict[str, Any]],
    lake_bank: dict[str, Any],
    runtime: dict[str, float | int],
    card_sizes: list[float],
) -> dict[str, Any]:
    radius = float(runtime["card_radius_m"])
    pilot_north = float(field["pilot"]["north"]["value"])
    pilot_east = float(field["pilot"]["east"]["value"])
    surfaces = field.get("surfaces", [])
    rough_surfaces = [surface for surface in surfaces if surface.get("type") == "rough"]
    strips = [surface for surface in surfaces if surface.get("type") in ("runway", "mown")]
    rotorpads = [surface for surface in surfaces if surface.get("type") == "rotorpad"]
    gap_hits = 0
    strip_hits = 0
    pad_hits = 0
    rough_failures = 0
    path_hits: dict[str, int] = {track["id"]: 0 for track in tracks}
    lake_hits = 0
    ring_failures = 0
    grid_failures = 0
    max_swept_radius = 0.0
    for index, (north_offset, east_offset, down) in enumerate(points):
        if _inside_protected_gap(north_offset, east_offset, radius):
            gap_hits += 1
        ring = (NEAR_RADIUS_MIN_M, NEAR_RADIUS_MAX_M) if index < NEAR_COUNT else (FAR_RADIUS_MIN_M, FAR_RADIUS_MAX_M)
        if not ring[0] <= math.hypot(north_offset, east_offset) <= ring[1]:
            ring_failures += 1
        if (
            abs(north_offset / POSITION_GRID_M - round(north_offset / POSITION_GRID_M)) > 1e-9
            or abs(east_offset / POSITION_GRID_M - round(east_offset / POSITION_GRID_M)) > 1e-9
            or down != 0.0
        ):
            grid_failures += 1
        shape = _identity(north_offset, east_offset, runtime, card_sizes)
        max_swept_radius = max(max_swept_radius, float(shape["horizontal_radius_m"]))
        north = pilot_north + north_offset
        east = pilot_east + east_offset
        if _lake_bank_hit(north, east, lake_bank, radius):
            lake_hits += 1
        if not any(
            north - radius >= _surface_bounds(surface)[0]
            and north + radius <= _surface_bounds(surface)[1]
            and east - radius >= _surface_bounds(surface)[2]
            and east + radius <= _surface_bounds(surface)[3]
            for surface in rough_surfaces
        ):
            rough_failures += 1
        for strip in strips:
            required = _quantity(strip, "width_north_south") * 0.5 + float(runtime["flight_corridor_half_width_m"]) + radius
            if abs(north - _quantity(strip, "center_north")) <= required:
                strip_hits += 1
                break
        for pad in rotorpads:
            if _distance_to_rect(north, east, _surface_bounds(pad)) <= float(runtime["flight_corridor_half_width_m"]) + radius:
                pad_hits += 1
                break
        for track in tracks:
            if _track_distance(north, east, track) <= track["width_m"] * 0.5 + radius:
                path_hits[track["id"]] += 1

    near_distances = _nearest_neighbor_values(points[:NEAR_COUNT])
    far_distances = _nearest_neighbor_values(points[NEAR_COUNT:])
    near_neighbors = _summary(near_distances)
    far_neighbors = _summary(far_distances)
    below_near_spacing = sum(
        distance < 9.0 - 1e-9 for distance in near_distances
    )
    below_far_spacing = sum(
        distance < 4.5 - 1e-9 for distance in far_distances
    )

    wind_contract = _wind_envelope(card_sizes, runtime)
    return {
        "counts": {"near": min(len(points), NEAR_COUNT), "far": max(0, len(points) - NEAR_COUNT), "total": len(points)},
        "inside_expected_ring_failures": ring_failures,
        "grid_or_flatness_failures": grid_failures,
        "protected_gap_crown_hits": gap_hits,
        "rough_surface_full_envelope_failures": rough_failures,
        "runway_mown_full_envelope_hits": strip_hits,
        "rotorpad_full_envelope_hits": pad_hits,
        "lake_bank_full_envelope_hits": lake_hits,
        "scenery_track_full_envelope_hits": path_hits,
        "nearest_neighbor_distances_m": {"near": near_neighbors, "far": far_neighbors},
        "near_spacing_violations_below_9m": below_near_spacing,
        "far_spacing_violations_below_4_5m": below_far_spacing,
        "wind_envelope": wind_contract,
        "maximum_tree_swept_horizontal_radius_m": max_swept_radius,
    }


def _wind_envelope(card_sizes: list[float], runtime: dict[str, float | int]) -> dict[str, float | bool]:
    max_frame = max(card_sizes)
    max_height = float(runtime["tree_height_min_m"]) + float(runtime["tree_height_span_m"])
    half_width = max_frame * max_height * 0.5
    highest_vertex = (0.5 + max_frame * 0.5) * max_height
    max_vertex_radius = math.hypot(half_width, highest_vertex)
    angle = float(runtime["wind_lean_m"]) / max_height
    sweep = 2.0 * max_vertex_radius * math.sin(angle * 0.5)
    swept_horizontal = half_width + sweep
    safe_radius = float(runtime["card_radius_m"])
    return {
        "max_frame_size_m": max_frame,
        "max_identity_height_m": max_height,
        "max_static_half_width_m": half_width,
        "max_vertex_radius_from_root_m": max_vertex_radius,
        "max_rigid_wind_sweep_m_at_10mps": sweep,
        "max_horizontal_radius_with_wind_m": swept_horizontal,
        "runtime_clearance_radius_m": safe_radius,
        "clearance_margin_m": safe_radius - swept_horizontal,
        "runtime_clearance_covers_wind_envelope": swept_horizontal <= safe_radius,
    }


def _resource_audit(
    vegetation_catalog: dict[str, Any],
    card_catalog: dict[str, Any],
    scenery: dict[str, Any],
    prefab_path: Path,
    runtime: dict[str, float | int],
) -> dict[str, Any]:
    assets = vegetation_catalog.get("assets", [])
    tree_assets = [asset for asset in assets if asset.get("role") == "tree"]
    card_ids, card_sizes = _frame_sizes(card_catalog)
    normalized_cards = {
        re.sub(r"[^a-z0-9]+", "_", re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", value).lower()).strip("_")
        for value in card_ids
    }
    imported_ids = {str(asset["id"]) for asset in tree_assets}
    represented = sorted(imported_ids & normalized_cards)
    unrepresented = sorted(imported_ids - normalized_cards)
    tree_heights = [float(asset["source_bounds_m"]["height"]) for asset in tree_assets]
    source_lod = {
        asset["id"]: {
            "source_supplied": bool(asset.get("lod", {}).get("source_supplied", False)),
            "importer_generated": bool(asset.get("lod", {}).get("godot_import_generate", False)),
            "source_lod": asset.get("lod", {}).get("source_lod"),
            "imported_supplied_levels": list(asset.get("lod", {}).get("imported_supplied_levels", [])),
            "alternate_source_lods": list(asset.get("lod", {}).get("alternate_source_lods_included", [])),
            "source_triangles": int(asset.get("source_triangles", 0)),
            "source_height_m": float(asset.get("source_bounds_m", {}).get("height", 0.0)),
        }
        for asset in tree_assets
    }
    groups = scenery.get("groups", [])
    vegetation_groups: dict[str, list[dict[str, Any]]] = {}
    for group in groups:
        prefab = str(group.get("prefab", ""))
        if prefab in ("shade_tree", "sapling", "bush", "flower_clump"):
            placements = group.get("placements", {}).get("value", [])
            vegetation_groups.setdefault(prefab, []).append({
                "group_id": str(group.get("id", "")),
                "zone": str(group.get("zone", "")),
                "count": len(placements),
                "max_radius_from_origin_m": max((math.hypot(float(p[0]), float(p[1])) for p in placements), default=0.0),
                "source": str(group.get("placements", {}).get("source", "")),
            })
    roles: dict[str, dict[str, Any]] = {}
    for asset in assets:
        role = str(asset.get("role", "unknown"))
        data = roles.setdefault(role, {"count": 0, "asset_ids": [], "min_height_m": math.inf, "max_height_m": 0.0})
        data["count"] += 1
        data["asset_ids"].append(str(asset.get("id", "")))
        height = float(asset.get("source_bounds_m", {}).get("height", 0.0))
        if height > 0.0:
            data["min_height_m"] = min(float(data["min_height_m"]), height)
            data["max_height_m"] = max(float(data["max_height_m"]), height)
    for data in roles.values():
        if data["min_height_m"] == math.inf:
            data["min_height_m"] = 0.0
        data["asset_ids"].sort()

    # This source note belongs to the current prefab inventory and is reported
    # as text so the diagnostic does not invent or alter a young-tree asset.
    prefab_source = prefab_path.read_text(encoding="utf-8")
    sapling_match = re.search(r'"sapling"\s*:\s*\{([^\n]+)', prefab_source)
    sapling_prefab_contract = sapling_match.group(1).strip() if sapling_match else "unavailable"
    woody_group_zones: dict[str, int] = {}
    for entries in vegetation_groups.values():
        for entry in entries:
            zone = str(entry["zone"])
            woody_group_zones[zone] = woody_group_zones.get(zone, 0) + int(entry["count"])
    tree_height_min = float(runtime["tree_height_min_m"])
    tree_height_max = tree_height_min + float(runtime["tree_height_span_m"])
    card_quad_min = min(card_sizes) * tree_height_min
    card_quad_max = max(card_sizes) * tree_height_max
    card_top_min = (0.5 + min(card_sizes) * 0.5) * tree_height_min
    card_top_max = (0.5 + max(card_sizes) * 0.5) * tree_height_max
    no_runtime_supplier_alternate = sorted(
        asset_id for asset_id, lod in source_lod.items() if not lod["alternate_source_lods"]
    )
    scenery_feature_groups = [
        {"id": str(group.get("id", "")), "type": str(group.get("type", "")), "zone": str(group.get("zone", ""))}
        for group in groups
        if any(token in (str(group.get("id", "")) + " " + str(group.get("type", ""))).lower() for token in ("water", "lake", "course"))
    ]
    return {
        "imported_mature_tree_form_count": len(tree_assets),
        "imported_tree_form_ids": sorted(imported_ids),
        "card_form_count": len(card_ids),
        "card_form_ids": card_ids,
        "imported_forms_with_a_same_named_card": represented,
        "imported_forms_without_a_same_named_card": unrepresented,
        "imported_form_match_count": len(represented),
        "imported_tree_source_height_range_m": [min(tree_heights), max(tree_heights)] if tree_heights else [0.0, 0.0],
        "far_card_identity_height_range_m": [tree_height_min, tree_height_max],
        "far_card_quad_height_range_m": [card_quad_min, card_quad_max],
        "far_card_quad_top_from_root_range_m": [card_top_min, card_top_max],
        "tree_source_lod_inventory": source_lod,
        "tree_forms_without_runtime_supplier_alternate_lod": no_runtime_supplier_alternate,
        "oak_supplier_lods_excluded_from_runtime": {
            "source_archive": "assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026/quercus_A_packed_v1_0.zip",
            "source_evidence": "docs/research/visual-quality-implementation/L6a-R1/mature-oak/source-intake/oga-listing-audit.md",
            "levels": [
                {"level": "LOD1", "triangles": 842},
                {"level": "LOD2", "triangles": 14},
            ],
            "current_runtime_supplied_levels": source_lod.get("oak_tree", {}).get("imported_supplied_levels", []),
            "godot_importer_generated_lods_enabled": source_lod.get("oak_tree", {}).get("importer_generated", False),
            "disposition": "Supplier LOD1/LOD2 remain excluded: their alternate envelopes and prerendered branches/foliage representation have not been qualified. Runtime imports supplier LOD0 and enables Godot-generated mesh LODs.",
        },
        "understory_source_inventory_by_role": roles,
        "existing_nearfield_vegetation_groups": vegetation_groups,
        "configured_woody_and_understory_group_counts_by_zone": woody_group_zones,
        "sapling_prefab_source_contract": sapling_prefab_contract,
        "sapling_group_zone_counts": [group for group in vegetation_groups.get("sapling", [])],
        "age_class_assessment": {
            "tree_role_forms_below_5m_source_height": sorted(
                asset["id"] for asset in tree_assets
                if float(asset.get("source_bounds_m", {}).get("height", 0.0)) < 5.0
            ),
            "named_sapling_instances": sum(group["count"] for group in vegetation_groups.get("sapling", [])),
            "named_sapling_zones": sorted({group["zone"] for group in vegetation_groups.get("sapling", [])}),
            "named_sapling_farthest_instance_from_origin_m": max(
                (float(group["max_radius_from_origin_m"]) for group in vegetation_groups.get("sapling", [])),
                default=0.0,
            ),
            "assessment": "The imported tree-role catalog contains mature-height sources only. Existing sapling aliases are a separate near-club scenery group; no forest-margin age layer is configured in the default layout.",
        },
        "understory_margin_assessment": {
            "catalog_roles_available": sorted(role for role in roles if role in ("shrub", "herb", "grass", "flower", "reed")),
            "configured_instances_in_countryside_or_forest_zones": sum(
                count for zone, count in woody_group_zones.items() if zone in ("countryside", "woodland", "forest")
            ),
            "assessment": "Catalog sources exist, but current configured vegetation groups are near-club placements or procedural ground layers. A woodland margin still needs an owning grass/terrain mask and habitat review.",
        },
        "scenery_water_or_course_groups_found": scenery_feature_groups,
        "scenery_lake_or_water_group_count": sum(
            1 for group in groups if any(token in (str(group.get("id", "")) + " " + str(group.get("type", ""))).lower() for token in ("water", "lake"))
        ),
        "scenery_course_group_count": sum(
            1 for group in groups if "course" in (str(group.get("id", "")) + " " + str(group.get("type", ""))).lower()
        ),
        "current_source_card_assessment": (
            "The far atlas reuses 3 cards; 5 of 8 imported mature forms have no same-named card. "
            "The card identity height is 12-25 m and its frame is about 1.125 m tall before scale, "
            "while imported source mesh heights are listed separately. This is a measurable representation "
            "difference, not proof of a visible defect or a reason to add geometry."
        ),
        "understory_assessment": (
            "Shrub, herb, grass, flower, and reed sources exist in the vegetation catalog. The named sapling "
            "placements are in the club zone rather than the far forest patches; the diagnostic does not infer "
            "that those resources are ecologically appropriate or that shade/water masks are approved."
        ),
    }


def _density_dispositions(runtime: dict[str, float | int], baseline_count: int) -> dict[str, Any]:
    cap = int(runtime["max_treeline_positions"])
    result: dict[str, Any] = {}
    for label, factor in (("plus_25_percent", 0.25), ("plus_50_percent", 0.50)):
        extra = round(baseline_count * factor)
        total = baseline_count + extra
        result[label] = {
            "extra_tree_count": extra,
            "hypothetical_total_tree_count": total,
            "loader_limit": cap,
            "positions_over_current_loader_limit": max(0, total - cap),
            "additional_card_triangles_at_6_per_tree": extra * 6,
            "current_draw_call_contract_changes": False,
            "disposition": "defer; candidate exceeds the field loader limit and has no same-target performance or flight readability evidence",
            "candidate_positions_generated": False,
        }
    return result


def _representation_dispositions(resource_audit: dict[str, Any]) -> dict[str, Any]:
    return {
        "L8a": {
            "status": "conditional; not qualified",
            "current_cards": resource_audit["card_form_ids"],
            "imported_mature_forms_without_matching_cards": resource_audit["imported_forms_without_a_same_named_card"],
            "runtime_supplier_alternate_lod_form_count": sum(bool(lod["alternate_source_lods"]) for lod in resource_audit["tree_source_lod_inventory"].values()),
            "oak_current_runtime_source_lod": resource_audit["tree_source_lod_inventory"].get("oak_tree", {}).get("source_lod"),
            "oak_supplier_alternates_available_but_excluded": resource_audit["oak_supplier_lods_excluded_from_runtime"],
            "qualifying_defect_capture_present": False,
            "next_evidence": "Capture a named same-source mesh/card defect at fixed projected sizes and camera FOVs before trialing the retained oak supplier LODs or another downloaded mesh. Include close, chase, overhead, and ground views; qualify the alternate envelope, pre-rendered texture, transitions, and scene budget before adoption.",
        },
        "L8b": {
            "status": "defer; dependent need not demonstrated",
            "qualifying_residual_representation_problem_present": False,
            "required_before_trial": [
                "A named residual defect after L8a/card comparisons or L7-R2 batching evidence",
                "Existing baker with pinned revision and resolved license/provenance",
                "Compatibility angle/light/underside/top/transition and export-memory evidence",
            ],
            "custom_baker_or_impostor_framework_added": False,
        },
    }


def _recipe_report(
    recipe: str,
    field: dict[str, Any],
    scenery_tracks: list[dict[str, Any]],
    lake_bank: dict[str, Any],
    runtime: dict[str, float | int],
    card_sizes: list[float],
    cell_size_m: float,
) -> tuple[dict[str, Any], dict[str, Any]]:
    object_data, manifest = generate(field, recipe)
    points = _tree_offset_positions(object_data)
    if recipe == "existing":
        patches = manifest["clusters"]
        near = points[:NEAR_COUNT]
    else:
        patches = manifest["patches"]
        near = points[:NEAR_COUNT]
    far = points[NEAR_COUNT:]
    clearances = _clearance_report(points, field, scenery_tracks, lake_bank, runtime, card_sizes)
    composition = _patch_metrics(patches, points, recipe, field, scenery_tracks, lake_bank, runtime, card_sizes, cell_size_m)
    report = {
        "recipe": recipe,
        "seed_near": 610602,
        "seed_far": manifest.get("clusters", [{}])[0].get("seed", 610607) if recipe == "existing" else 610617,
        "counts": {"near": len(near), "far": len(far), "total": len(points)},
        "positions_sha256": manifest["positions_sha256"],
        "near_positions_sha256": manifest["near_positions_sha256"],
        "far_positions_sha256": manifest["far_positions_sha256"],
        "nearest_neighbor_distances_m": {
            "near": clearances["nearest_neighbor_distances_m"]["near"],
            "far": clearances["nearest_neighbor_distances_m"]["far"],
            "combined": _nearest_neighbors(points),
        },
        "skyline_proxy": {
            "combined": _skyline_proxy(points, runtime, card_sizes),
            "near": _skyline_proxy(near, runtime, card_sizes),
            "far": _skyline_proxy(far, runtime, card_sizes),
        },
        "clearances": clearances,
        "composition": composition,
    }
    return report, object_data


def build_report(
    field: dict[str, Any],
    scenery: dict[str, Any],
    vegetation_catalog: dict[str, Any],
    card_catalog: dict[str, Any],
    *,
    lake_data: dict[str, Any] | None = None,
    cell_size_m: float = DEFAULT_GRID_M,
    field_loader_path: Path = DEFAULT_FIELD_LOADER,
    treeline_path: Path = DEFAULT_TREELINE,
    tree_wind_path: Path = DEFAULT_TREE_WIND,
    prefab_path: Path = DEFAULT_PREFABS,
    source_paths: dict[str, Path] | None = None,
) -> dict[str, Any]:
    if cell_size_m <= 0.0:
        raise ValueError("cell size must be positive")
    if lake_data is None:
        lake_data = _json(DEFAULT_LAKE)
    runtime = _runtime_contracts(field_loader_path, treeline_path, tree_wind_path)
    card_ids, card_sizes = _frame_sizes(card_catalog)
    tracks = _track_data(scenery)
    lake_bank = _lake_bank_polygon(lake_data)
    recipes: dict[str, Any] = {}
    generated_objects: dict[str, dict[str, Any]] = {}
    for recipe in ("existing", "habitat-v1"):
        recipes[recipe], generated_objects[recipe] = _recipe_report(
            recipe,
            field,
            tracks,
            lake_bank,
            runtime,
            card_sizes,
            cell_size_m,
        )
    current_positions = _current_tree_positions(field)
    committed_habitat_matches = bool(current_positions) and (
        field.get("objects", []) == [generated_objects["habitat-v1"]]
    )
    resource_audit = _resource_audit(vegetation_catalog, card_catalog, scenery, prefab_path, runtime)
    paths = source_paths or {
        "field": DEFAULT_FIELD,
        "lake": DEFAULT_LAKE,
        "scenery": DEFAULT_SCENERY,
        "vegetation_catalog": DEFAULT_VEGETATION_CATALOG,
        "card_catalog": DEFAULT_CARD_CATALOG,
        "field_loader": field_loader_path,
        "treeline": treeline_path,
        "tree_wind": tree_wind_path,
        "prefabs": prefab_path,
    }
    actual_cap = int(runtime["max_treeline_positions"])
    report = {
        "format": FORMAT,
        "classification": "estimated visual composition, not surveyed geography or ecological simulation",
        "sampling": {
            "eligible_area_cell_size_m": cell_size_m,
            "skyline_azimuth_bins": SKYLINE_BINS,
            "wind_speed_cap_mps": WIND_MAX_SPEED_MPS,
            "full_tree_clearance_radius_m": float(runtime["card_radius_m"]),
            "near_and_far_count_is_same_between_recipes": recipes["existing"]["counts"] == recipes["habitat-v1"]["counts"],
        },
        "source_sha256": {key: _sha256(path) for key, path in sorted(paths.items())},
        "runtime_contracts": runtime,
        "committed_habitat_matches_generator": committed_habitat_matches,
        "committed_tree_count": len(current_positions),
        "recipe_comparison": recipes,
        "resources": resource_audit,
        "density_increments": _density_dispositions(runtime, len(current_positions)),
        "representation_dispositions": _representation_dispositions(resource_audit),
        "authoritative_exclusions": {
            "lake_source_id": str(lake_data.get("id", "")),
            "lake_source_format": str(lake_data.get("format", "")),
            "lake_bank_polygon_used": "bank_offsets_ne_m",
            "lake_bank_vertices": len(lake_bank["points"]),
            "lake_geometry_separate_from_scenery_groups": resource_audit["scenery_lake_or_water_group_count"] == 0,
            "separate_rc_course_geometry_found_in_default_scenery": resource_audit["scenery_course_group_count"] > 0,
            "scenery_track_ids_checked": [track["id"] for track in tracks],
            "note": "The default openrc-lake v1 source is app/data/fields/lake.json; its bank polygon is used for full card-envelope exclusions. The scenery file also provides three checked track polylines. No separate RC course geometry is configured in the checked default scenery; do not treat those tracks as a complete course layout.",
        },
        "scope_note": "Track clearances are checked against current scenery polylines. Source/card and understory inventories describe current files; they do not claim that the assets are visually or ecologically qualified.",
    }
    return report


def validate_report(report: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if report.get("format") != FORMAT:
        errors.append("unexpected diagnostic format")
    if not report.get("committed_habitat_matches_generator"):
        errors.append("committed field positions do not match habitat-v1")
    cap = int(report["runtime_contracts"]["max_treeline_positions"])
    if report.get("committed_tree_count") != cap:
        errors.append("committed tree count differs from current loader limit")
    for recipe, result in report["recipe_comparison"].items():
        if result["counts"]["total"] != cap:
            errors.append(f"{recipe}: same-count recipe does not match loader limit")
        clearance = result["clearances"]
        for key in (
            "inside_expected_ring_failures",
            "grid_or_flatness_failures",
            "protected_gap_crown_hits",
            "rough_surface_full_envelope_failures",
            "runway_mown_full_envelope_hits",
            "rotorpad_full_envelope_hits",
            "lake_bank_full_envelope_hits",
            "near_spacing_violations_below_9m",
            "far_spacing_violations_below_4_5m",
        ):
            if clearance[key] != 0:
                errors.append(f"{recipe}: {key} is {clearance[key]}")
        if any(clearance["scenery_track_full_envelope_hits"].values()):
            errors.append(f"{recipe}: tree envelope intersects a scenery track")
        if not clearance["wind_envelope"]["runtime_clearance_covers_wind_envelope"]:
            errors.append(f"{recipe}: runtime card clearance is smaller than the derived wind envelope")
        if not result["composition"]["eligible_patch_area_ha"] > 0.0:
            errors.append(f"{recipe}: eligible patch area is empty")
        if not 0.0 <= result["composition"]["eligible_area_weighted_card_disk_occupancy_fraction"] <= 1.0:
            errors.append(f"{recipe}: card disk occupancy falls outside 0..1")
    if report["density_increments"]["plus_25_percent"]["positions_over_current_loader_limit"] <= 0:
        errors.append("+25% density candidate unexpectedly fits current loader limit")
    if report["density_increments"]["plus_50_percent"]["positions_over_current_loader_limit"] <= 0:
        errors.append("+50% density candidate unexpectedly fits current loader limit")
    return errors


def _write_report(report: dict[str, Any], output_path: Path | None) -> None:
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if output_path is None:
        print(encoded, end="")
        return
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(encoded, encoding="utf-8")
    print(f"Habitat diagnostics written to {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--field", type=Path, default=DEFAULT_FIELD)
    parser.add_argument("--lake", type=Path, default=DEFAULT_LAKE)
    parser.add_argument("--scenery", type=Path, default=DEFAULT_SCENERY)
    parser.add_argument("--vegetation-catalog", type=Path, default=DEFAULT_VEGETATION_CATALOG)
    parser.add_argument("--card-catalog", type=Path, default=DEFAULT_CARD_CATALOG)
    parser.add_argument("--cell-size", type=float, default=DEFAULT_GRID_M, help="deterministic eligible-area raster cell size in metres")
    parser.add_argument("--out", type=Path, help="optional JSON evidence output path")
    parser.add_argument("--check", action="store_true", help="fail unless both recipes satisfy current placement contracts")
    args = parser.parse_args()
    source_paths = {
        "field": args.field,
        "lake": args.lake,
        "scenery": args.scenery,
        "vegetation_catalog": args.vegetation_catalog,
        "card_catalog": args.card_catalog,
        "field_loader": DEFAULT_FIELD_LOADER,
        "treeline": DEFAULT_TREELINE,
        "tree_wind": DEFAULT_TREE_WIND,
        "prefabs": DEFAULT_PREFABS,
        "placement_generator": ROOT / "tools/trees/place.py",
        "diagnostics_tool": Path(__file__).resolve(),
    }
    report = build_report(
        _json(args.field),
        _json(args.scenery),
        _json(args.vegetation_catalog),
        _json(args.card_catalog),
        lake_data=_json(args.lake),
        cell_size_m=args.cell_size,
        source_paths=source_paths,
    )
    if args.check:
        errors = validate_report(report)
        if errors:
            raise SystemExit("\n".join(errors))
    _write_report(report, args.out)


if __name__ == "__main__":
    main()
