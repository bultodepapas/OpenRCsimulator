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

# L7-R1 habitat-v1 is the reviewed default composition. Its uneven patch counts
# sum to the existing 1,200-tree far budget; all source coordinates remain estimates.
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

# L7-R3 groves-v1 regroups the 480 near trees into woods, hedgerow lines and solitary field
# trees; the far ring keeps habitat-v1. Species and height stay the renderer's position hash,
# so candidates are accepted by their hashed identity (grove species, taller interiors).
GROVE_SEED = 620101
GROVE_SHAPE = (26, 30, 34, 38, 42, 46, 50, 56, 62)  # relative wood sizes, scaled to the free count
GROVE_AREA_PER_TREE_M2 = 160.0  # closed broadleaf canopy for 12-25 m card crowns
GROVE_DOMINANT_KEEP = 0.09  # acceptance of a non-dominant candidate: about 85% one species
GROVE_SPACING_FACTOR = 0.6  # crown-centre spacing as a fraction of both crown radii
HEDGEROW_LINES = 4
HEDGEROW_TREES = 14
HEDGEROW_SPACING_M = 12.0
SOLITARY_TREES = 24
GROVE_ATTEMPTS = 600000
# Skyline anchors: tools/scenery/place.py puts the turbines/pylons (70-110 deg window) and the
# village (262-300 deg) where the treeline skyline is lowest. The frozen L6b near trees stay in
# these sectors and no other crown enters them, so landmark azimuths and scenery stay unchanged.
SKYLINE_ANCHORS_DEG = ((64.0, 92.0), (254.0, 268.0))
SCENERY_KEEPOUT_M = 22.0  # around every committed scenery placement beyond 200 m
# L7-R4 groves-v2 keeps the groves-v1 near ring and compacts the twelve habitat-v1 far patches,
# at their centres and orientations, into woods at near-closed canopy density.
FAR_GROVE_SEED = 620102
FAR_GROVE_AREA_PER_TREE_M2 = 220.0
FAR_GROVE_GROWTH_STEPS = 30  # widen a wood by 8% per step only when constraints leave too little room
# Fixed inputs that do not depend on tree positions: bake_countryside.py's farm boxes (it asserts
# 10 m tree clearance) and road centrelines, the woodland-edge floor templates, and the
# botanical farm crops/shrubs, which nothing else keeps clear of trees.
COUNTRYSIDE_FARM_BOXES_NE_M = ((630.0, 280.0, 780.0, 430.0), (470.0, 380.0, 550.0, 540.0))
FARM_BOX_MARGIN_M = 14.0
ROAD_TREE_MARGIN_M = 9.0  # beyond the road half-width; test_countryside.py requires more than 3 m
WOODLAND_EDGE_KEEPOUT_M = 30.0
FARM_HABITAT_KEEPOUT_NE_M = ((561.0, 335.0, 25.0), (554.0, 315.0, 12.0), (573.0, 354.0, 12.0))
# render/treeline.gd crown half-widths at alpha 0.5 times the card frame (Quercus, maple, pine).
CARD_CROWN_FRACTIONS = (0.3701171875 * 1.125001, 0.3017578125 * 1.125001, 0.1669921875 * 1.125001)


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
        start_index = len(far_points)
        far_points.extend(cluster_points)
        cluster_metadata.append({
            "sector": sector,
            "north_m": center[0],
            "east_m": center[1],
            "count": len(cluster_points),
            "start_index": start_index,
            "end_index": start_index + len(cluster_points),
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
            "orientation_rad": orientation,
            # Keep the unrounded outline inputs in the manifest so CPU diagnostics
            # can measure the actual generated habitat boundary deterministically.
            "outline_phase_rad": phase,
            "notch_angle_rad": notch_angle,
            "notch_width_rad": notch_width,
            "outer_radius_m": round(outer_radius, 3),
            "notch_angle_deg": round(math.degrees(notch_angle), 3),
            "notch_width_deg": round(math.degrees(notch_width), 3),
            "notch_depth": round(notch_depth, 4),
            "outline_notch_depth": notch_depth,
            "bounds_m": _point_bounds(patch_points),
        })

    if len(far_points) != HABITAT_FAR_COUNT or len(far_points) != FAR_COUNT:
        raise ValueError("L7-R1 habitat patch counts do not match the 1,200-tree far budget")
    return far_points, patches


def tree_identity(north: float, east: float) -> tuple[int, float]:
    """render/treeline.gd identity(): (species, height_m) from the quarter-metre position hash."""
    qn, qe = round(north * 4.0), round(east * 4.0)
    offset = 8192 if (qn < -2400 or qe < -2400) else 2400
    h = ((qn + offset) * 7381 + (qe + offset) * 19391 + 6113) % 65521
    h = (h * 25173 + 13849) % 65521
    return h % 3, 12.0 + 13.0 * (h % 1024) / 1023.0


def _card_crown_radius(north: float, east: float) -> float:
    species, height = tree_identity(north, east)
    return CARD_CROWN_FRACTIONS[species] * height


def _snap(value: float) -> float:
    return round(value / POSITION_GRID_M) * POSITION_GRID_M


def _in_skyline_anchor(north: float, east: float, crown_radius: float = 0.0) -> bool:
    radius = math.hypot(north, east)
    angle = math.degrees(math.atan2(east, north)) % 360.0
    margin = math.degrees(math.asin(min(1.0, crown_radius / radius))) if crown_radius else 0.0
    return any(low - margin <= angle <= high + margin for low, high in SKYLINE_ANCHORS_DEG)


class _Canopy:
    """Placed crowns on a coarse grid; spacing scales with both crowns' radii."""

    CELL_M = 12.0

    def __init__(self) -> None:
        self._grid: dict[tuple[int, int], list[tuple[float, float, float]]] = {}

    def clear(self, north: float, east: float, radius: float, factor: float) -> bool:
        cell_north, cell_east = math.floor(north / self.CELL_M), math.floor(east / self.CELL_M)
        reach = 1 + math.ceil(factor * 22.0 / self.CELL_M)
        for offset_north in range(-reach, reach + 1):
            for offset_east in range(-reach, reach + 1):
                for other_north, other_east, other_radius in self._grid.get(
                    (cell_north + offset_north, cell_east + offset_east), ()
                ):
                    if (north - other_north) ** 2 + (east - other_east) ** 2 < (factor * (radius + other_radius)) ** 2:
                        return False
        return True

    def add(self, north: float, east: float, radius: float) -> None:
        key = (math.floor(north / self.CELL_M), math.floor(east / self.CELL_M))
        self._grid.setdefault(key, []).append((north, east, radius))


class _GroveSite:
    def __init__(self, field: dict[str, Any], keepout: list[tuple[float, float]]) -> None:
        self.pilot_north = float(field["pilot"]["north"]["value"])
        self.strips = [s for s in field["surfaces"] if s["type"] in ("runway", "mown")]
        self.keepout = keepout

    def allowed(self, north: float, east: float) -> bool:
        if not NEAR_RADIUS_MIN_M <= math.hypot(north, east) <= NEAR_RADIUS_MAX_M:
            return False
        if _inside_protected_gap(north, east) or _in_skyline_anchor(north, east, CROWN_RADIUS_M):
            return False
        if _inside_flight_corridor(north, self.pilot_north, self.strips, 0.0):
            return False
        return all(
            (north - keep_north) ** 2 + (east - keep_east) ** 2 >= SCENERY_KEEPOUT_M**2
            for keep_north, keep_east in self.keepout
        )


def _scenery_keepout(scenery_path: Path) -> list[tuple[float, float]]:
    """Committed scenery placements beyond 200 m; scenery/place.py must stay unchanged after a run."""
    scenery = json.loads(scenery_path.read_text(encoding="utf-8"))
    keepout = []
    for group in scenery["groups"]:
        placements = group.get("placements", [])
        values = placements["value"] if isinstance(placements, dict) else placements
        for point in values:
            if isinstance(point, list) and len(point) >= 2 and math.hypot(point[0], point[1]) > 200.0:
                keepout.append((float(point[0]), float(point[1])))
    return keepout


def _make_grove(
    rng: random.Random,
    site: _GroveSite,
    canopy: _Canopy,
    center: tuple[float, float],
    count: int,
    semi_major: float,
    semi_minor: float,
    orientation: float,
    dominant: int,
) -> list[list[float | int]] | None:
    """An irregular closed-canopy wood; committed to the canopy only when it fills."""
    phase, notch_angle = rng.random() * math.tau, rng.random() * math.tau
    notch_width, notch_depth = math.radians(rng.uniform(18.0, 36.0)), rng.uniform(0.13, 0.28)
    cos_orientation, sin_orientation = math.cos(orientation), math.sin(orientation)
    local = _Canopy()
    placed: list[tuple[float, float, float]] = []
    for _ in range(GROVE_ATTEMPTS):
        angle = rng.random() * math.tau
        relative = math.sqrt(rng.random())
        scale = _habitat_outline_scale(angle, phase, notch_angle, notch_width, notch_depth)
        local_north = semi_major * relative * scale * math.cos(angle)
        local_east = semi_minor * relative * scale * math.sin(angle)
        north = _snap(center[0] + local_north * cos_orientation - local_east * sin_orientation)
        east = _snap(center[1] + local_north * sin_orientation + local_east * cos_orientation)
        if not site.allowed(north, east):
            continue
        species, height = tree_identity(north, east)
        if species != dominant and rng.random() > GROVE_DOMINANT_KEEP:
            continue
        # Woodland profile: lower trees at the margin, the tallest inside.
        target = 13.5 + 10.0 * (1.0 - relative * relative)
        if rng.random() > math.exp(-(((height - target) / 4.0) ** 2)):
            continue
        radius = _card_crown_radius(north, east)
        if not canopy.clear(north, east, radius, GROVE_SPACING_FACTOR) or not local.clear(
            north, east, radius, GROVE_SPACING_FACTOR
        ):
            continue
        local.add(north, east, radius)
        placed.append((north, east, radius))
        if len(placed) == count:
            for item in placed:
                canopy.add(*item)
            return [[north, east, 0] for north, east, _ in placed]
    return None


def _make_hedgerow(rng: random.Random, site: _GroveSite, canopy: _Canopy) -> list[list[float | int]]:
    """A broadleaf tree line roughly along the ring, as along a field boundary."""
    for _ in range(4000):
        azimuth = math.radians(rng.uniform(0.0, 360.0))
        radius = rng.uniform(330.0, 480.0)
        north, east = radius * math.cos(azimuth), radius * math.sin(azimuth)
        heading = azimuth + math.pi / 2.0 + rng.uniform(-0.35, 0.35)
        bend = rng.uniform(-0.0025, 0.0025)
        local = _Canopy()
        placed: list[tuple[float, float, float]] = []
        misses = 0
        while len(placed) < HEDGEROW_TREES and misses < 12:
            heading += bend * HEDGEROW_SPACING_M
            north += HEDGEROW_SPACING_M * math.cos(heading)
            east += HEDGEROW_SPACING_M * math.sin(heading)
            tree_north = _snap(north + rng.uniform(-1.25, 1.25))
            tree_east = _snap(east + rng.uniform(-1.25, 1.25))
            species, _ = tree_identity(tree_north, tree_east)
            if not site.allowed(tree_north, tree_east) or species == 2:
                misses += 1
                continue
            tree_radius = _card_crown_radius(tree_north, tree_east)
            if not canopy.clear(tree_north, tree_east, tree_radius, 0.55) or not local.clear(
                tree_north, tree_east, tree_radius, 0.55
            ):
                misses += 1
                continue
            local.add(tree_north, tree_east, tree_radius)
            placed.append((tree_north, tree_east, tree_radius))
            misses = 0
        if len(placed) == HEDGEROW_TREES:
            for item in placed:
                canopy.add(*item)
            return [[north, east, 0] for north, east, _ in placed]
    raise ValueError("L7-R3 hedgerow line exhausted its bounded candidate budget")


def generate_grove_near(field: dict[str, Any], scenery_path: Path) -> tuple[list[list[float | int]], list[dict[str, Any]]]:
    """480 near trees: frozen L6b trees in the skyline anchors, then woods, hedgerows and solitary trees."""
    rng = random.Random(GROVE_SEED)
    site = _GroveSite(field, _scenery_keepout(scenery_path))
    canopy = _Canopy()
    near = [list(point) for point in generate_near(field) if _in_skyline_anchor(point[0], point[1])]
    for point in near:
        canopy.add(point[0], point[1], _card_crown_radius(point[0], point[1]))
    groups: list[dict[str, Any]] = [{"kind": "skyline-anchor", "count": len(near)}]
    grove_total = NEAR_COUNT - len(near) - HEDGEROW_LINES * HEDGEROW_TREES - SOLITARY_TREES
    grove_counts = [round(size * grove_total / sum(GROVE_SHAPE)) for size in GROVE_SHAPE]
    grove_counts[-1] += grove_total - sum(grove_counts)
    rng.shuffle(grove_counts)
    # Spread the woods evenly over the free arcs (outside the anchors and the viewing gaps).
    blocked = [(low - 6.0, high + 6.0) for low, high in SKYLINE_ANCHORS_DEG]
    blocked += [(center - half - 8.0, center + half + 8.0) for center, half in GAPS]
    free = [step * 0.5 for step in range(720) if not any(low <= step * 0.5 <= high for low, high in blocked)]
    offset = rng.randrange(len(free))
    slots = [free[(offset + round(index * len(free) / len(grove_counts))) % len(free)] for index in range(len(grove_counts))]
    for slot, count in zip(slots, grove_counts):
        ratio = rng.uniform(1.4, 2.4)
        semi_minor = math.sqrt(count * GROVE_AREA_PER_TREE_M2 / math.pi / ratio)
        semi_major = semi_minor * ratio
        dominant = rng.choice((0, 0, 1, 1, 2))
        for _ in range(4000):
            radius = rng.uniform(300.0 + semi_major, 560.0 - semi_minor)
            angle = math.radians(slot + rng.uniform(-6.0, 6.0))
            center = (_snap(radius * math.cos(angle)), _snap(radius * math.sin(angle)))
            extent = semi_major * 1.25 + CROWN_RADIUS_M
            if not site.allowed(*center) or _inside_protected_gap(*center, extent) or _in_skyline_anchor(*center, extent):
                continue
            if _inside_flight_corridor(center[0], site.pilot_north, site.strips, semi_major * 1.1):
                continue
            orientation = angle + math.pi / 2.0 + rng.uniform(-0.5, 0.5)
            points = _make_grove(rng, site, canopy, center, count, semi_major, semi_minor, orientation, dominant)
            if points is not None:
                near += points
                share = sum(tree_identity(n, e)[0] == dominant for n, e, _ in points) / count
                groups.append({"kind": "wood", "count": count, "north_m": center[0], "east_m": center[1],
                               "semi_major_m": round(semi_major, 2), "semi_minor_m": round(semi_minor, 2),
                               "dominant_species": dominant, "dominant_share": round(share, 3)})
                break
        else:
            raise ValueError(f"L7-R3 wood near {slot:.1f} deg exhausted its bounded candidate budget")
    for _ in range(HEDGEROW_LINES):
        near += _make_hedgerow(rng, site, canopy)
        groups.append({"kind": "hedgerow", "count": HEDGEROW_TREES})
    solitary = 0
    for _ in range(2000000):
        if len(near) == NEAR_COUNT:
            break
        north, east = _snap(rng.uniform(-NEAR_RADIUS_MAX_M, NEAR_RADIUS_MAX_M)), _snap(rng.uniform(-NEAR_RADIUS_MAX_M, NEAR_RADIUS_MAX_M))
        if not site.allowed(north, east) or tree_identity(north, east)[0] == 2:
            continue
        radius = _card_crown_radius(north, east)
        if not canopy.clear(north, east, radius, 2.5):
            continue
        canopy.add(north, east, radius)
        near.append([north, east, 0])
        solitary += 1
    if len(near) != NEAR_COUNT:
        raise ValueError("L7-R3 solitary trees exhausted their bounded candidate budget")
    groups.append({"kind": "solitary", "count": solitary})
    near.sort()
    return near, groups


class _FarGroveSite:
    """Far-ring constraints; every input is fixed independently of tree positions."""

    def __init__(self, field: dict[str, Any], scenery_path: Path, countryside_path: Path, woodland_path: Path) -> None:
        self.pilot_north = float(field["pilot"]["north"]["value"])
        self.strips = [s for s in field["surfaces"] if s["type"] in ("runway", "mown")]
        self.keepout = [(n, e, SCENERY_KEEPOUT_M) for n, e in _scenery_keepout(scenery_path)]
        woodland = json.loads(woodland_path.read_text(encoding="utf-8"))
        self.keepout += [(float(p["floor_center_ne_m"][0]), float(p["floor_center_ne_m"][1]), WOODLAND_EDGE_KEEPOUT_M)
                         for p in woodland["patches"]]
        self.keepout += list(FARM_HABITAT_KEEPOUT_NE_M)
        countryside = json.loads(countryside_path.read_text(encoding="utf-8"))
        # Road segments indexed by every 64 m cell their clearance box overlaps.
        self.road_cells: dict[tuple[int, int], list[tuple[float, float, float, float, float]]] = {}
        for road in countryside["roads"]:
            clearance = float(road["width_m"]) / 2.0 + ROAD_TREE_MARGIN_M
            line = road["centerline_ne_m"]
            for start, end in zip(line, line[1:]):
                segment = (float(start[0]), float(start[1]), float(end[0]), float(end[1]), clearance)
                for cell_north in range(math.floor((min(start[0], end[0]) - clearance) / 64.0),
                                        math.floor((max(start[0], end[0]) + clearance) / 64.0) + 1):
                    for cell_east in range(math.floor((min(start[1], end[1]) - clearance) / 64.0),
                                           math.floor((max(start[1], end[1]) + clearance) / 64.0) + 1):
                        self.road_cells.setdefault((cell_north, cell_east), []).append(segment)

    def _near_road(self, north: float, east: float) -> bool:
        for n0, e0, n1, e1, clearance in self.road_cells.get((math.floor(north / 64.0), math.floor(east / 64.0)), ()):
            dn, de = n1 - n0, e1 - e0
            length2 = dn * dn + de * de
            t = 0.0 if length2 == 0.0 else max(0.0, min(1.0, ((north - n0) * dn + (east - e0) * de) / length2))
            if math.hypot(north - n0 - t * dn, east - e0 - t * de) < clearance:
                return True
        return False

    def allowed(self, north: float, east: float) -> bool:
        radius = math.hypot(north, east)
        # Keep clear of the 600 m CPU/shader near-far boundary.
        if not FAR_RADIUS_MIN_M + 1.5 <= radius <= FAR_RADIUS_MAX_M:
            return False
        if _inside_protected_gap(north, east) or _in_skyline_anchor(north, east, CROWN_RADIUS_M):
            return False
        if _inside_flight_corridor(north, self.pilot_north, self.strips, 0.0):
            return False
        for n0, e0, n1, e1 in COUNTRYSIDE_FARM_BOXES_NE_M:
            if n0 - FARM_BOX_MARGIN_M < north < n1 + FARM_BOX_MARGIN_M and e0 - FARM_BOX_MARGIN_M < east < e1 + FARM_BOX_MARGIN_M:
                return False
        if any((north - kn) ** 2 + (east - ke) ** 2 < kr * kr for kn, ke, kr in self.keepout):
            return False
        return not self._near_road(north, east)


def generate_grove_far(
    field: dict[str, Any],
    near_points: list[list[float | int]],
    scenery_path: Path,
    countryside_path: Path,
    woodland_path: Path,
) -> tuple[list[list[float | int]], list[dict[str, Any]]]:
    """1,200 far trees: frozen habitat-v1 trees in the skyline anchors, then the twelve compacted woods."""
    rng = random.Random(FAR_GROVE_SEED)
    site = _FarGroveSite(field, scenery_path, countryside_path, woodland_path)
    canopy = _Canopy()
    for north, east, _ in near_points:
        canopy.add(north, east, _card_crown_radius(north, east))
    habitat_far, patches = generate_habitat_far(field)
    far = [list(point) for point in habitat_far if _in_skyline_anchor(point[0], point[1])]
    for point in far:
        canopy.add(point[0], point[1], _card_crown_radius(point[0], point[1]))
    groups: list[dict[str, Any]] = [{"kind": "skyline-anchor", "count": len(far)}]
    budget = [int(patch["count"]) for patch in patches]
    counts = [round(count * (FAR_COUNT - len(far)) / sum(budget)) for count in budget]
    counts[-1] += FAR_COUNT - len(far) - sum(counts)
    for patch, count in zip(patches, counts):
        ratio = float(patch["semi_major_m"]) / float(patch["semi_minor_m"])
        semi_minor = math.sqrt(count * FAR_GROVE_AREA_PER_TREE_M2 / math.pi / ratio)
        dominant = rng.choice((0, 0, 1, 1, 2))
        center = (float(patch["north_m"]), float(patch["east_m"]))
        for step in range(FAR_GROVE_GROWTH_STEPS):
            grow = 1.0 + 0.08 * step
            points = _make_grove(rng, site, canopy, center, count, semi_minor * ratio * grow, semi_minor * grow,
                                 float(patch["orientation_rad"]), dominant)
            if points is not None:
                break
        else:
            raise ValueError(f"L7-R4 far wood at {center} exhausted its bounded growth steps")
        far += points
        share = sum(tree_identity(n, e)[0] == dominant for n, e, _ in points) / count
        groups.append({"kind": "wood", "count": count, "north_m": center[0], "east_m": center[1],
                       "semi_major_m": round(semi_minor * ratio * grow, 2), "semi_minor_m": round(semi_minor * grow, 2),
                       "dominant_species": dominant, "dominant_share": round(share, 3)})
    if len(far) != FAR_COUNT:
        raise ValueError("L7-R4 far woods do not match the 1,200-tree far budget")
    far.sort()
    return far, groups


PRODUCTION_SCENERY = Path(__file__).resolve().parents[2] / "app/data/scenery/default.json"
PRODUCTION_COUNTRYSIDE = Path(__file__).resolve().parents[2] / "app/data/scenery/countryside.json"
PRODUCTION_WOODLAND_EDGES = Path(__file__).resolve().parents[2] / "app/data/woodland_edges.json"


def generate(
    field: dict[str, Any],
    recipe: str = "groves-v2",
    scenery_path: Path = PRODUCTION_SCENERY,
    countryside_path: Path = PRODUCTION_COUNTRYSIDE,
    woodland_path: Path = PRODUCTION_WOODLAND_EDGES,
) -> tuple[dict[str, Any], dict[str, Any]]:
    near_groups: list[dict[str, Any]] = []
    far_groups: list[dict[str, Any]] = []
    if recipe in ("groves-v1", "groves-v2"):
        near_points, near_groups = generate_grove_near(field, scenery_path)
    else:
        near_points = generate_near(field)
    if recipe == "existing":
        far_points, patches = generate_far(field)
    elif recipe in ("habitat-v1", "groves-v1"):
        far_points, patches = generate_habitat_far(field)
    elif recipe == "groves-v2":
        far_points, far_groups = generate_grove_far(field, near_points, scenery_path, countryside_path, woodland_path)
        _, patches = generate_habitat_far(field)
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
        near_hash = _positions_sha256(near_points)
        far_hash = _positions_sha256(far_points)
        combined_hash = _positions_sha256(points)
        if recipe in ("groves-v1", "groves-v2"):
            kinds = {kind: sum(g["count"] for g in near_groups if g["kind"] == kind)
                     for kind in ("skyline-anchor", "wood", "hedgerow", "solitary")}
            near_text = (
                f"L7-R3 {recipe} tools/trees/place.py. Estimated visual composition, not surveyed "
                f"or an ecological simulation: 480 near trees from seed {GROVE_SEED} in "
                f"{sum(1 for g in near_groups if g['kind'] == 'wood')} woods ({kinds['wood']} trees), "
                f"{HEDGEROW_LINES} hedgerow lines ({kinds['hedgerow']}), {kinds['solitary']} solitary trees "
                f"and {kinds['skyline-anchor']} frozen L6b trees in the landmark skyline sectors; "
                "species and height are the renderer's position hash; plus "
            )
        else:
            near_text = (
                "L7-R1 habitat-v1 tools/trees/place.py. Estimated visual composition, not surveyed "
                f"or an ecological simulation: 480 frozen near trees from seed {NEAR_SEED}, plus "
            )
        if recipe == "groves-v2":
            far_text = (
                f"L7-R4 {len(far_points)} far trees from seed {FAR_GROVE_SEED}: the {len(patches)} habitat-v1 "
                f"patch centres and orientations compacted to woods at {FAR_GROVE_AREA_PER_TREE_M2:.0f} m2 per tree "
                f"with counts {','.join(str(g['count']) for g in far_groups if g['kind'] == 'wood')}, plus "
                f"{far_groups[0]['count']} frozen habitat-v1 trees in the landmark skyline sectors; clear of the "
                "countryside roads, farm boxes, woodland-edge floors and farm habitats; "
            )
        else:
            far_text = (
                f"{len(far_points)} far trees from seed {HABITAT_FAR_SEED} in {len(patches)} "
                f"irregular anisotropic patches with counts {','.join(map(str, patch_counts))}; "
            )
        source = (
            near_text + far_text +
            f"far bounds N={far_bounds['north_min_m']:.2f}..{far_bounds['north_max_m']:.2f} m, "
            f"E={far_bounds['east_min_m']:.2f}..{far_bounds['east_max_m']:.2f} m; 0.25 m grid. "
            f"Near, far and combined position SHA-256: {near_hash}, {far_hash}, {combined_hash}. "
            "Maintains the existing crown-cleared viewing gaps, runway/mown flight corridor and "
            "4.5 m minimum tree spacing. Estimated scenery placement; collision proxies are "
            "derived by the runtime; no terrain or aerodynamics change."
        )
        return_manifest = {
            "recipe": recipe,
            "near_count": len(near_points),
            "far_count": len(far_points),
            "near_positions_sha256": near_hash,
            "far_positions_sha256": far_hash,
            "positions_sha256": combined_hash,
            "bounds_m": _point_bounds(points),
            "far_bounds_m": far_bounds,
            "patch_counts": patch_counts,
            "patches": patches,
        }
        if recipe in ("groves-v1", "groves-v2"):
            return_manifest["near_groups"] = near_groups
        if recipe == "groves-v2":
            return_manifest["far_groups"] = far_groups
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
        choices=("existing", "habitat-v1", "groves-v1", "groves-v2"),
        default="groves-v2",
        help="L7-R4 groves with far woods (default), L7-R3 near groves, the L7-R1 habitat layout or the historical existing layout",
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    production_field = Path(__file__).resolve().parents[2] / "app/data/fields/default.json"
    field_path = args.field or production_field
    field = json.loads(field_path.read_text(encoding="utf-8"))
    obj, manifest = generate(field, args.recipe)
    objects = [obj]
    if args.check:
        if field["objects"] != objects:
            raise SystemExit("Committed placement differs from offline recipe")
    else:
        field["objects"] = objects
        # .gitattributes keeps this file CRLF; write those bytes on every OS so raw-byte pins agree.
        field_path.write_text(json.dumps(field, indent=2) + "\n", encoding="utf-8", newline="\r\n")
    seed_far = {"existing": FAR_SEED, "groves-v2": FAR_GROVE_SEED}.get(args.recipe, HABITAT_FAR_SEED)
    seed_near = GROVE_SEED if args.recipe in ("groves-v1", "groves-v2") else NEAR_SEED
    print(json.dumps({"seed_near": seed_near, "seed_far": seed_far, **manifest}, indent=2))


if __name__ == "__main__":
    main()
