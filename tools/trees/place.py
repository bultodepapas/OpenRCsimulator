#!/usr/bin/env python3
"""L6b/L7 offline tree placement; estimated composition, not surveyed field geometry."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
from typing import Any


# L6b placement is frozen: do not change this seed, count, spacing or rejection order.
NEAR_SEED = 610602
NEAR_COUNT = 480
NEAR_RADIUS_MIN_M = 270.0
NEAR_RADIUS_MAX_M = 570.0
NEAR_MIN_SPACING_M = 9.0
CROWN_RADIUS_M = 15.0
GAPS = ((30.0, 8.0), (210.0, 10.0))  # center azimuth, half width in degrees
NEAR_POSITIONS_SHA256 = "9b42b61ff36e5df25ef0245702e4d75965ea805f81de56a1c353fd1f0c722875"

# L7 adds twelve aperiodic patches of 100 trees. The extra seed leaves every L6b
# position and identity untouched. The 55m radius is an artistic patch scale.
FAR_SEED = 610607
FAR_CLUSTER_COUNT = 12
FAR_TREES_PER_CLUSTER = 100
FAR_COUNT = FAR_CLUSTER_COUNT * FAR_TREES_PER_CLUSTER
FAR_RADIUS_MIN_M = 600.0
FAR_RADIUS_MAX_M = 1500.0
FAR_CLUSTER_RADIUS_M = 55.0
FAR_MIN_SPACING_M = 4.5
FAR_CLUSTER_CENTER_MIN_M = FAR_RADIUS_MIN_M + FAR_CLUSTER_RADIUS_M + 10.0
FAR_CLUSTER_CENTER_MAX_M = FAR_RADIUS_MAX_M - FAR_CLUSTER_RADIUS_M - 10.0
FAR_CLUSTER_SEPARATION_M = FAR_CLUSTER_RADIUS_M * 2.0 + 35.0
POSITION_GRID_M = 0.25
FAR_CENTER_ATTEMPTS = 50000
FAR_POINT_ATTEMPTS = 20000

# L7-R1 is an opt-in visual composition. Its uneven patch counts sum to the
# existing 1,200-tree far budget; all source coordinates remain estimates.
HABITAT_FAR_SEED = 610617
HABITAT_PATCH_SPECS = (
    (55, 68.0, 43.0),
    (64, 72.0, 50.0),
    (72, 78.0, 48.0),
    (82, 82.0, 56.0),
    (88, 88.0, 60.0),
    (92, 92.0, 58.0),
    (96, 96.0, 65.0),
    (102, 103.0, 62.0),
    (110, 108.0, 72.0),
    (124, 120.0, 74.0),
    (142, 135.0, 81.0),
    (173, 155.0, 92.0),
)
HABITAT_PATCH_COUNT = len(HABITAT_PATCH_SPECS)
HABITAT_FAR_COUNT = sum(spec[0] for spec in HABITAT_PATCH_SPECS)
HABITAT_OUTLINE_MAX_SCALE = 1.2
HABITAT_PATCH_GAP_M = 24.0
HABITAT_CENTER_ATTEMPTS = 100000
HABITAT_POINT_ATTEMPTS = 100000


def _positions_sha256(points: list[list[float | int]]) -> str:
    encoded = json.dumps(points, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def generate_near(field: dict[str, Any]) -> list[list[float | int]]:
    """Return the original L6b positions byte-for-byte in their old order."""
    rng = random.Random(NEAR_SEED)
    pilot = field["pilot"]
    pn, pe = (pilot[k]["value"] for k in ("north", "east"))
    strips = [s for s in field["surfaces"] if s["type"] in ("runway", "mown")]
    points: list[list[float | int]] = []
    for _ in range(200000):
        n, e = rng.randrange(-2280, 2281) / 4, rng.randrange(-2280, 2281) / 4
        radius = math.hypot(n, e)
        if not NEAR_RADIUS_MIN_M <= radius <= NEAR_RADIUS_MAX_M:
            continue
        angle = math.degrees(math.atan2(e, n)) % 360
        # Keep each complete crown outside the intentional gaps.
        margin = math.degrees(math.asin(CROWN_RADIUS_M / radius))
        if any(_angular_distance(angle, center) <= half + margin for center, half in GAPS):
            continue
        if _inside_flight_corridor(n, pn, strips, 0.0):
            continue
        # Broad irregular clusters rather than a wall or evenly spaced plantation.
        density = 0.25 + 0.75 * (
            0.5 + 0.5 * math.sin(math.radians(3 * angle) + math.sin(math.radians(5 * angle)))
        )
        if rng.random() > density or any((n - p[0]) ** 2 + (e - p[1]) ** 2 < NEAR_MIN_SPACING_M**2 for p in points):
            continue
        points.append([n, e, 0])
        if len(points) == NEAR_COUNT:
            break
    if len(points) != NEAR_COUNT:
        raise ValueError("L6b placement exhausted its bounded candidate budget")
    points.sort()
    digest = _positions_sha256(points)
    if digest != NEAR_POSITIONS_SHA256:
        raise ValueError(f"L6b placement changed: expected {NEAR_POSITIONS_SHA256}, got {digest}")
    return points


def _angular_distance(angle: float, center: float) -> float:
    return abs((angle - center + 180.0) % 360.0 - 180.0)


def _inside_flight_corridor(
    north: float,
    pilot_north: float,
    strips: list[dict[str, Any]],
    cluster_radius: float,
) -> bool:
    for strip in strips:
        clearance = (
            strip["width_north_south"]["value"] / 2.0
            + 35.0
            + CROWN_RADIUS_M
            + cluster_radius
        )
        if abs(north + pilot_north - strip["center_north"]["value"]) <= clearance:
            return True
    return False


def _center_is_clear(
    north: float,
    east: float,
    pilot_north: float,
    strips: list[dict[str, Any]],
) -> bool:
    radius = math.hypot(north, east)
    if not FAR_CLUSTER_CENTER_MIN_M <= radius <= FAR_CLUSTER_CENTER_MAX_M:
        return False
    angle = math.degrees(math.atan2(east, north)) % 360.0
    gap_margin = math.degrees(math.asin(min(1.0, (FAR_CLUSTER_RADIUS_M + CROWN_RADIUS_M) / radius)))
    if any(_angular_distance(angle, center) <= half + gap_margin for center, half in GAPS):
        return False
    return not _inside_flight_corridor(north, pilot_north, strips, FAR_CLUSTER_RADIUS_M)


def _make_cluster_center(
    rng: random.Random,
    sector: int,
    pilot_north: float,
    strips: list[dict[str, Any]],
    previous_centers: list[tuple[float, float]],
) -> tuple[float, float]:
    for _ in range(FAR_CENTER_ATTEMPTS):
        angle_deg = (sector + rng.random()) * 45.0
        angle = math.radians(angle_deg)
        radius = rng.uniform(FAR_CLUSTER_CENTER_MIN_M, FAR_CLUSTER_CENTER_MAX_M)
        north = round(math.cos(angle) * radius / POSITION_GRID_M) * POSITION_GRID_M
        east = round(math.sin(angle) * radius / POSITION_GRID_M) * POSITION_GRID_M
        if not _center_is_clear(north, east, pilot_north, strips):
            continue
        if any(
            math.hypot(north - other_north, east - other_east) < FAR_CLUSTER_SEPARATION_M
            for other_north, other_east in previous_centers
        ):
            continue
        return north, east
    raise ValueError(f"Could not place a clear far-forest cluster center in sector {sector}")


def _make_far_cluster(
    rng: random.Random,
    center: tuple[float, float],
    pilot_north: float,
    strips: list[dict[str, Any]],
) -> list[list[float | int]]:
    points: list[list[float | int]] = []
    center_north, center_east = center
    for _ in range(FAR_POINT_ATTEMPTS):
        distance = FAR_CLUSTER_RADIUS_M * math.sqrt(rng.random())
        angle = rng.random() * math.tau
        north = round((center_north + math.cos(angle) * distance) / POSITION_GRID_M) * POSITION_GRID_M
        east = round((center_east + math.sin(angle) * distance) / POSITION_GRID_M) * POSITION_GRID_M
        radius = math.hypot(north, east)
        if not FAR_RADIUS_MIN_M <= radius <= FAR_RADIUS_MAX_M:
            continue
        direction = math.degrees(math.atan2(east, north)) % 360.0
        margin = math.degrees(math.asin(CROWN_RADIUS_M / radius))
        if any(_angular_distance(direction, gap_center) <= half + margin for gap_center, half in GAPS):
            continue
        if _inside_flight_corridor(north, pilot_north, strips, 0.0):
            continue
        if any((north - point[0]) ** 2 + (east - point[1]) ** 2 < FAR_MIN_SPACING_M**2 for point in points):
            continue
        points.append([north, east, 0])
        if len(points) == FAR_TREES_PER_CLUSTER:
            return points
    raise ValueError("L7 cluster exhausted its bounded candidate budget")


def generate_far(field: dict[str, Any]) -> tuple[list[list[float | int]], list[dict[str, float | int]]]:
    """Create 12 repeatable 100-tree patches in the 600–1,500m ring."""
    rng = random.Random(FAR_SEED)
    pilot_north = float(field["pilot"]["north"]["value"])
    strips = [s for s in field["surfaces"] if s["type"] in ("runway", "mown")]
    previous_centers: list[tuple[float, float]] = []
    cluster_metadata: list[dict[str, float | int]] = []
    far_points: list[list[float | int]] = []

    # Seed one patch per 45-degree sector so every existing MultiMesh receives a
    # far cluster; four additional patches are placed in independently chosen sectors.
    sectors = list(range(8)) + [rng.randrange(8) for _ in range(FAR_CLUSTER_COUNT - 8)]
    for sector in sectors:
        center = _make_cluster_center(rng, sector, pilot_north, strips, previous_centers)
        cluster_points = _make_far_cluster(rng, center, pilot_north, strips)
        previous_centers.append(center)
        far_points.extend(cluster_points)
        cluster_metadata.append({
            "sector": sector,
            "north_m": center[0],
            "east_m": center[1],
            "count": len(cluster_points),
            "radius_m": FAR_CLUSTER_RADIUS_M,
        })
    return far_points, cluster_metadata


def _point_bounds(points: list[list[float | int]]) -> dict[str, float]:
    return {
        "north_min_m": min(float(point[0]) for point in points),
        "north_max_m": max(float(point[0]) for point in points),
        "east_min_m": min(float(point[1]) for point in points),
        "east_max_m": max(float(point[1]) for point in points),
    }


def _inside_protected_gap(north: float, east: float, crown_radius: float = CROWN_RADIUS_M) -> bool:
    radius = math.hypot(north, east)
    angle = math.degrees(math.atan2(east, north)) % 360.0
    margin = math.degrees(math.asin(min(1.0, crown_radius / radius)))
    return any(
        _angular_distance(angle, center) <= half + margin
        for center, half in GAPS
    )


def _habitat_center_is_clear(
    north: float,
    east: float,
    pilot_north: float,
    strips: list[dict[str, Any]],
    outer_radius: float,
) -> bool:
    radius = math.hypot(north, east)
    if not FAR_RADIUS_MIN_M + outer_radius + 10.0 <= radius <= FAR_RADIUS_MAX_M - outer_radius - 10.0:
        return False
    angle = math.degrees(math.atan2(east, north)) % 360.0
    gap_margin = math.degrees(math.asin(min(1.0, (outer_radius + CROWN_RADIUS_M) / radius)))
    if any(_angular_distance(angle, center) <= half + gap_margin for center, half in GAPS):
        return False
    return not _inside_flight_corridor(north, pilot_north, strips, outer_radius)


def _make_habitat_center(
    rng: random.Random,
    sector: int,
    pilot_north: float,
    strips: list[dict[str, Any]],
    outer_radius: float,
    previous_centers: list[tuple[float, float, float]],
) -> tuple[float, float]:
    for _ in range(HABITAT_CENTER_ATTEMPTS):
        angle_deg = (sector + rng.random()) * 45.0
        angle = math.radians(angle_deg)
        radius = rng.uniform(
            FAR_RADIUS_MIN_M + outer_radius + 10.0,
            FAR_RADIUS_MAX_M - outer_radius - 10.0,
        )
        north = round(math.cos(angle) * radius / POSITION_GRID_M) * POSITION_GRID_M
        east = round(math.sin(angle) * radius / POSITION_GRID_M) * POSITION_GRID_M
        if not _habitat_center_is_clear(north, east, pilot_north, strips, outer_radius):
            continue
        if any(
            math.hypot(north - other_north, east - other_east)
            < outer_radius + other_radius + HABITAT_PATCH_GAP_M
            for other_north, other_east, other_radius in previous_centers
        ):
            continue
        return north, east
    raise ValueError(f"Could not place a clear habitat patch center in sector {sector}")


def _angular_distance_radians(angle: float, center: float) -> float:
    return abs((angle - center + math.pi) % math.tau - math.pi)


def _habitat_outline_scale(
    angle: float,
    phase: float,
    notch_angle: float,
    notch_width: float,
    notch_depth: float,
) -> float:
    lobes = (
        0.105 * math.sin(3.0 * angle + phase)
        + 0.065 * math.sin(5.0 * angle - phase * 0.7)
        + 0.035 * math.cos(7.0 * angle + phase * 0.4)
    )
    notch = max(0.0, 1.0 - _angular_distance_radians(angle, notch_angle) / notch_width)
    scale = 1.0 + lobes - notch_depth * notch * notch
    return max(0.72, min(HABITAT_OUTLINE_MAX_SCALE, scale))


def _cell_for(north: float, east: float, cell_size: float) -> tuple[int, int]:
    return math.floor(north / cell_size), math.floor(east / cell_size)


def _too_close_to_grid(
    north: float,
    east: float,
    grid: dict[tuple[int, int], list[tuple[float, float]]],
    spacing: float,
) -> bool:
    cell_north, cell_east = _cell_for(north, east, spacing)
    for offset_north in (-1, 0, 1):
        for offset_east in (-1, 0, 1):
            for other_north, other_east in grid.get(
                (cell_north + offset_north, cell_east + offset_east),
                (),
            ):
                if (north - other_north) ** 2 + (east - other_east) ** 2 < spacing**2:
                    return True
    return False


def _add_to_grid(
    north: float,
    east: float,
    grid: dict[tuple[int, int], list[tuple[float, float]]],
    cell_size: float,
) -> None:
    grid.setdefault(_cell_for(north, east, cell_size), []).append((north, east))


def _make_habitat_patch(
    rng: random.Random,
    center: tuple[float, float],
    count: int,
    semi_major: float,
    semi_minor: float,
    orientation: float,
    phase: float,
    notch_angle: float,
    notch_width: float,
    notch_depth: float,
    pilot_north: float,
    strips: list[dict[str, Any]],
    spacing_grid: dict[tuple[int, int], list[tuple[float, float]]],
) -> list[list[float | int]]:
    points: list[list[float | int]] = []
    center_north, center_east = center
    cos_orientation = math.cos(orientation)
    sin_orientation = math.sin(orientation)
    outer_radius = semi_major * HABITAT_OUTLINE_MAX_SCALE
    for _ in range(HABITAT_POINT_ATTEMPTS):
        angle = rng.random() * math.tau
        radial = math.sqrt(rng.random()) * _habitat_outline_scale(
            angle,
            phase,
            notch_angle,
            notch_width,
            notch_depth,
        )
        local_north = semi_major * radial * math.cos(angle)
        local_east = semi_minor * radial * math.sin(angle)
        north = round((center_north + local_north * cos_orientation - local_east * sin_orientation) / POSITION_GRID_M) * POSITION_GRID_M
        east = round((center_east + local_north * sin_orientation + local_east * cos_orientation) / POSITION_GRID_M) * POSITION_GRID_M
        radius = math.hypot(north, east)
        if not FAR_RADIUS_MIN_M <= radius <= FAR_RADIUS_MAX_M:
            continue
        if _inside_protected_gap(north, east):
            continue
        if _inside_flight_corridor(north, pilot_north, strips, 0.0):
            continue
        if _too_close_to_grid(north, east, spacing_grid, FAR_MIN_SPACING_M):
            continue
        points.append([north, east, 0])
        _add_to_grid(north, east, spacing_grid, FAR_MIN_SPACING_M)
        if len(points) == count:
            points.sort()
            return points
    raise ValueError("L7-R1 habitat patch exhausted its bounded candidate budget")


def generate_habitat_far(
    field: dict[str, Any],
) -> tuple[list[list[float | int]], list[dict[str, Any]]]:
    """Create anisotropic, irregular visual patches with a fixed 1,200-tree budget."""
    rng = random.Random(HABITAT_FAR_SEED)
    pilot_north = float(field["pilot"]["north"]["value"])
    strips = [s for s in field["surfaces"] if s["type"] in ("runway", "mown")]
    sectors = list(range(8)) + [rng.randrange(8) for _ in range(HABITAT_PATCH_COUNT - 8)]
    previous_centers: list[tuple[float, float, float]] = []
    spacing_grid: dict[tuple[int, int], list[tuple[float, float]]] = {}
    far_points: list[list[float | int]] = []
    patches: list[dict[str, Any]] = []

    for (count, semi_major, semi_minor), sector in zip(HABITAT_PATCH_SPECS, sectors):
        outer_radius = semi_major * HABITAT_OUTLINE_MAX_SCALE
        center = _make_habitat_center(
            rng,
            sector,
            pilot_north,
            strips,
            outer_radius,
            previous_centers,
        )
        orientation = math.radians(rng.uniform(0.0, 180.0))
        phase = rng.random() * math.tau
        notch_angle = rng.random() * math.tau
        notch_width = math.radians(rng.uniform(18.0, 36.0))
        notch_depth = rng.uniform(0.13, 0.28)
        patch_points = _make_habitat_patch(
            rng,
            center,
            count,
            semi_major,
            semi_minor,
            orientation,
            phase,
            notch_angle,
            notch_width,
            notch_depth,
            pilot_north,
            strips,
            spacing_grid,
        )
        start_index = len(far_points)
        far_points.extend(patch_points)
        previous_centers.append((center[0], center[1], outer_radius))
        patches.append({
            "sector": sector,
            "north_m": center[0],
            "east_m": center[1],
            "count": len(patch_points),
            "start_index": start_index,
            "end_index": start_index + len(patch_points),
            "semi_major_m": semi_major,
            "semi_minor_m": semi_minor,
            "orientation_deg": round(math.degrees(orientation), 3),
            "outer_radius_m": round(outer_radius, 3),
            "notch_angle_deg": round(math.degrees(notch_angle), 3),
            "notch_width_deg": round(math.degrees(notch_width), 3),
            "notch_depth": round(notch_depth, 4),
            "bounds_m": _point_bounds(patch_points),
        })

    if len(far_points) != HABITAT_FAR_COUNT or len(far_points) != FAR_COUNT:
        raise ValueError("L7-R1 habitat patch counts do not match the 1,200-tree far budget")
    return far_points, patches


def generate(field: dict[str, Any], recipe: str = "existing") -> tuple[dict[str, Any], dict[str, Any]]:
    near_points = generate_near(field)
    if recipe == "existing":
        far_points, patches = generate_far(field)
    elif recipe == "habitat-v1":
        far_points, patches = generate_habitat_far(field)
    else:
        raise ValueError(f"Unknown placement recipe: {recipe}")
    points = near_points + far_points
    if len(points) != NEAR_COUNT + FAR_COUNT:
        raise ValueError("Combined placement count does not match the L6b/L7 contract")
    if recipe == "existing":
        source = (
            "L6b/L7 tools/trees/place.py. Estimated visual layout, not surveyed: "
            "480 near trees from seed 610602 at 270-570 m, plus 1,200 far trees "
            "from seed 610607 in twelve 100-tree clusters at 600-1,500 m; 0.25 m grid; "
            "preserves the 30+/-8 and 210+/-10 degree crown-cleared gaps and the runway/mown "
            "east-west flight corridor. Flat visual vegetation; no collision, terrain or aerodynamics."
        )
        return_manifest: dict[str, Any] = {
            "recipe": "existing",
            "near_count": len(near_points),
            "far_count": len(far_points),
            "near_positions_sha256": _positions_sha256(near_points),
            "far_positions_sha256": _positions_sha256(far_points),
            "positions_sha256": _positions_sha256(points),
            "clusters": patches,
        }
    else:
        far_bounds = _point_bounds(far_points)
        patch_counts = [int(patch["count"]) for patch in patches]
        source = (
            "L7-R1 habitat-v1 tools/trees/place.py. Estimated visual composition, not surveyed "
            f"or an ecological simulation: 480 frozen near trees from seed {NEAR_SEED}, plus "
            f"{len(far_points)} far trees from seed {HABITAT_FAR_SEED} in {len(patches)} "
            f"irregular anisotropic patches with counts {','.join(map(str, patch_counts))}; "
            f"far bounds N={far_bounds['north_min_m']:.2f}..{far_bounds['north_max_m']:.2f} m, "
            f"E={far_bounds['east_min_m']:.2f}..{far_bounds['east_max_m']:.2f} m; 0.25 m grid. "
            "Maintains the existing crown-cleared viewing gaps, runway/mown flight corridor and "
            "4.5 m minimum tree spacing. Flat visual vegetation; no collision, terrain or aerodynamics."
        )
        return_manifest = {
            "recipe": "habitat-v1",
            "near_count": len(near_points),
            "far_count": len(far_points),
            "near_positions_sha256": _positions_sha256(near_points),
            "far_positions_sha256": _positions_sha256(far_points),
            "positions_sha256": _positions_sha256(points),
            "bounds_m": _point_bounds(points),
            "far_bounds_m": far_bounds,
            "patch_counts": patch_counts,
            "patches": patches,
        }
    return {
        "id": "treeline",
        "type": "treeline",
        "collides": False,
        "positions": {
            "value": points,
            "unit": "m",
            "kind": "derived",
            "source": source,
        },
    }, return_manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--field", type=Path, help="field JSON to verify or update")
    parser.add_argument(
        "--recipe",
        choices=("existing", "habitat-v1"),
        default="existing",
        help="existing frozen layout (default) or opt-in L7-R1 visual habitat layout",
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    production_field = Path(__file__).resolve().parents[2] / "app/data/fields/default.json"
    if args.recipe == "habitat-v1":
        if args.field is None:
            parser.error("--recipe habitat-v1 requires an explicit staged --field path")
        if args.field.resolve() == production_field.resolve():
            parser.error("habitat-v1 is not approved for the production default field")
    field_path = args.field or production_field
    field = json.loads(field_path.read_text(encoding="utf-8"))
    obj, manifest = generate(field, args.recipe)
    objects = [obj]
    if args.check:
        if field["objects"] != objects:
            raise SystemExit("Committed placement differs from offline recipe")
    else:
        field["objects"] = objects
        field_path.write_text(json.dumps(field, indent=2) + "\n", encoding="utf-8")
    seed_far = HABITAT_FAR_SEED if args.recipe == "habitat-v1" else FAR_SEED
    print(json.dumps({"seed_near": NEAR_SEED, "seed_far": seed_far, **manifest}, indent=2))


if __name__ == "__main__":
    main()
