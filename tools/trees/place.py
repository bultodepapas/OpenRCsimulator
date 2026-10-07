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


def generate(field: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    near_points = generate_near(field)
    far_points, clusters = generate_far(field)
    points = near_points + far_points
    if len(points) != NEAR_COUNT + FAR_COUNT:
        raise ValueError("Combined placement count does not match the L6b/L7 contract")
    return {
        "id": "treeline",
        "type": "treeline",
        "collides": False,
        "positions": {
            "value": points,
            "unit": "m",
            "kind": "derived",
            "source": (
                "L6b/L7 tools/trees/place.py. Estimated visual layout, not surveyed: "
                "480 near trees from seed 610602 at 270-570 m, plus 1,200 far trees "
                "from seed 610607 in twelve 100-tree clusters at 600-1,500 m; 0.25 m grid; "
                "preserves the 30+/-8 and 210+/-10 degree crown-cleared gaps and the runway/mown "
                "east-west flight corridor. Flat visual vegetation; no collision, terrain or aerodynamics."
            ),
        },
    }, {
        "near_count": len(near_points),
        "far_count": len(far_points),
        "near_positions_sha256": _positions_sha256(near_points),
        "far_positions_sha256": _positions_sha256(far_points),
        "positions_sha256": _positions_sha256(points),
        "clusters": clusters,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--field",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "app/data/fields/default.json",
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    field = json.loads(args.field.read_text())
    obj, manifest = generate(field)
    objects = [obj]
    if args.check:
        if field["objects"] != objects:
            raise SystemExit("Committed placement differs from offline recipe")
    else:
        field["objects"] = objects
        args.field.write_text(json.dumps(field, indent=2) + "\n")
    print(json.dumps({"seed_near": NEAR_SEED, "seed_far": FAR_SEED, **manifest}, indent=2))


if __name__ == "__main__":
    main()
