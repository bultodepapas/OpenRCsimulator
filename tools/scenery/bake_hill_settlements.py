#!/usr/bin/env python3
"""Bake deterministic distant-house placements against the rendered ridge grid."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
PROFILE_PATH = ROOT / "app/data/fields/mountains.json"
OUTPUT_PATH = ROOT / "app/data/scenery/hill_settlements.json"
FORMAT = "openrc-hill-settlements v1"
SURFACE_OFFSET_M = 0.02  # Match the offset applied to ridge mesh vertices.
MAX_SLOPE_DEG = 3.2
MAX_FOOTING_RANGE_M = 0.75
HOUSE_MAX_WIDTH_M = 9.0
HOUSE_MAX_DEPTH_M = 11.0
FOUNDATION_TOP_CLEARANCE_M = 0.02
FOUNDATION_CAP_HEIGHT_M = 0.08
FOUNDATION_BASE_MARGIN_M = 0.25
FOUNDATION_CAP_MARGIN_M = 0.15
HOUSE_OFFSETS_NE_M = ((-9.0, -10.0), (-9.0, 10.0), (9.0, -10.0), (9.0, 10.0))
CLUSTERS = (
    {"id": "west", "north_m": 2350.0, "east_m": -560.0, "base_heading_deg": 165.0},
    {"id": "central", "north_m": 3905.0, "east_m": 45.0, "base_heading_deg": 165.0},
    {"id": "east", "north_m": 2455.0, "east_m": 1540.0, "base_heading_deg": 165.0},
)


def _sample_triangle(profile: dict[str, Any], north: float, east: float) -> tuple[float, float, float]:
    columns = int(profile["columns"])
    rows = int(profile["rows"])
    east_min = float(profile["east_min_m"])
    east_max = float(profile["east_max_m"])
    north_min = float(profile["north_min_m"])
    north_max = float(profile["north_max_m"])
    step_e = (east_max - east_min) / columns
    step_n = (north_max - north_min) / rows
    x = max(0.0, min(float(columns), (east - east_min) / step_e))
    y = max(0.0, min(float(rows), (north - north_min) / step_n))
    col = min(int(x), columns - 1)
    row = min(int(y), rows - 1)
    u = x - col
    v = y - row
    heights = profile["heights_m"]
    a = row * (columns + 1) + col
    b = a + columns + 1
    h00 = float(heights[a])
    h01 = float(heights[a + 1])
    h10 = float(heights[b])
    h11 = float(heights[b + 1])
    if u + v <= 1.0:
        return h00 * (1.0 - u - v) + h10 * v + h01 * u, (h10 - h00) / step_n, (h01 - h00) / step_e
    return h10 * (1.0 - u) + h11 * (u + v - 1.0) + h01 * (1.0 - v), (h11 - h01) / step_n, (h11 - h10) / step_e


def _triangle_key(profile: dict[str, Any], north: float, east: float) -> tuple[int, int, int]:
    columns = int(profile["columns"])
    rows = int(profile["rows"])
    east_min = float(profile["east_min_m"])
    east_max = float(profile["east_max_m"])
    north_min = float(profile["north_min_m"])
    north_max = float(profile["north_max_m"])
    x = (east - east_min) / ((east_max - east_min) / columns)
    y = (north - north_min) / ((north_max - north_min) / rows)
    col = min(int(x), columns - 1)
    row = min(int(y), rows - 1)
    return row, col, 0 if (x - col) + (y - row) <= 1.0 else 1


def _world_up_footprint(profile: dict[str, Any], north: float, east: float,
                        heading_deg: float) -> tuple[float, float, float]:
    angle = math.radians(heading_deg)
    right = (math.cos(angle), 0.0, math.sin(angle))
    back = (-math.sin(angle), 0.0, math.cos(angle))
    points: list[tuple[float, float, float]] = []
    for x in (-HOUSE_MAX_WIDTH_M * 0.5, HOUSE_MAX_WIDTH_M * 0.5):
        for z in (-HOUSE_MAX_DEPTH_M * 0.5, HOUSE_MAX_DEPTH_M * 0.5):
            east_delta = right[0] * x + back[0] * z
            north_delta = -(right[2] * x + back[2] * z)
            point_n = north + north_delta
            point_e = east + east_delta
            sample = _sample_triangle(profile, point_n, point_e)
            points.append((point_n, point_e, sample[0]))
    center_key = _triangle_key(profile, north, east)
    if any(_triangle_key(profile, point_n, point_e) != center_key for point_n, point_e, _height in points):
        raise ValueError(f"house footprint crosses ridge triangles at N={north:.1f}, E={east:.1f}")
    heights = [point[2] for point in points]
    return min(heights), max(heights), max(heights) - min(heights)


def _seed(cluster_id: str, index: int) -> int:
    payload = f"{FORMAT}:{cluster_id}:{index}".encode("utf-8")
    return int.from_bytes(hashlib.sha256(payload).digest()[:4], "big") & 0x7FFFFFFF


def build_layout(profile_bytes: bytes) -> dict[str, Any]:
    profile = json.loads(profile_bytes)
    if profile.get("format") != "openrc-visual-mountains v1" or profile.get("physical_terrain") is not False:
        raise ValueError("mountain profile must be the visual-only ridge grid")
    columns = int(profile["columns"])
    rows = int(profile["rows"])
    if len(profile.get("heights_m", [])) != (columns + 1) * (rows + 1):
        raise ValueError("mountain profile height count does not match its grid")
    profile_sha256 = hashlib.sha256(profile_bytes).hexdigest()
    houses: list[dict[str, Any]] = []
    clusters: list[dict[str, Any]] = []
    for cluster in CLUSTERS:
        cluster_id = str(cluster["id"])
        cluster_start = len(houses)
        for index, (offset_n, offset_e) in enumerate(HOUSE_OFFSETS_NE_M):
            north = float(cluster["north_m"]) + offset_n
            east = float(cluster["east_m"]) + offset_e
            heading = (float(cluster["base_heading_deg"]) + index * 10.0) % 360.0
            terrain_height, dn, de = _sample_triangle(profile, north, east)
            slope_deg = math.degrees(math.atan(math.hypot(dn, de)))
            terrain_min, terrain_max, footing_range = _world_up_footprint(profile, north, east, heading)
            if not 2000.0 <= north <= 4500.0 or not -2500.0 <= east <= 2500.0:
                raise ValueError(f"house outside authored hill range: {cluster_id}-{index + 1}")
            if slope_deg > MAX_SLOPE_DEG:
                raise ValueError(f"slope too steep for {cluster_id}-{index + 1}: {slope_deg:.2f} degrees")
            if footing_range > MAX_FOOTING_RANGE_M:
                raise ValueError(f"footing rise is too large for {cluster_id}-{index + 1}: {footing_range:.3f} m")
            house_id = f"hill-{cluster_id}-{index + 1:02d}"
            foundation_body_height = terrain_max - terrain_min + FOUNDATION_TOP_CLEARANCE_M
            foundation_height = foundation_body_height + FOUNDATION_CAP_HEIGHT_M
            houses.append({
                "id": house_id,
                "cluster": cluster_id,
                "north_m": north,
                "east_m": east,
                "height_m": terrain_min + SURFACE_OFFSET_M + foundation_height,
                "terrain_height_m": terrain_height,
                "terrain_min_height_m": terrain_min,
                "terrain_max_height_m": terrain_max,
                "heading_deg": heading,
                "seed": _seed(cluster_id, index),
                "slope_deg": slope_deg,
                "footing_range_m": footing_range,
                "foundation_body_height_m": foundation_body_height,
                "foundation_height_m": foundation_height,
            })
        clusters.append({
            "id": cluster_id,
            "north_m": float(cluster["north_m"]),
            "east_m": float(cluster["east_m"]),
            "house_count": len(houses) - cluster_start,
        })
    return {
        "format": FORMAT,
        "generator": "tools/scenery/bake_hill_settlements.py",
        "profile": "res://data/fields/mountains.json",
        "profile_sha256": profile_sha256,
        "profile_source_crop_sha256": profile["source_crop_sha256"],
        "columns": columns,
        "rows": rows,
        "east_min_m": profile["east_min_m"],
        "east_max_m": profile["east_max_m"],
        "north_min_m": profile["north_min_m"],
        "north_max_m": profile["north_max_m"],
        "surface_offset_m": SURFACE_OFFSET_M,
        "max_slope_deg": MAX_SLOPE_DEG,
        "max_footing_range_m": MAX_FOOTING_RANGE_M,
        "foundation_top_clearance_m": FOUNDATION_TOP_CLEARANCE_M,
        "foundation_cap_height_m": FOUNDATION_CAP_HEIGHT_M,
        "foundation_base_margin_m": FOUNDATION_BASE_MARGIN_M,
        "foundation_cap_margin_m": FOUNDATION_CAP_MARGIN_M,
        "prefab": "village_house",
        "physical": False,
        "clusters": clusters,
        "houses": houses,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if generated data differs from the checked-in file")
    args = parser.parse_args()
    generated = json.dumps(build_layout(PROFILE_PATH.read_bytes()), indent=2, ensure_ascii=False) + "\n"
    if args.check:
        if not OUTPUT_PATH.is_file() or OUTPUT_PATH.read_text(encoding="utf-8") != generated:
            print(f"hill settlement data is stale: regenerate {OUTPUT_PATH.relative_to(ROOT)}")
            return 1
        print("hill settlement layout matches the committed file")
        return 0
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(generated, encoding="utf-8", newline="\n")
    print(f"wrote {OUTPUT_PATH.relative_to(ROOT)}: {len(json.loads(generated)['houses'])} houses")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
