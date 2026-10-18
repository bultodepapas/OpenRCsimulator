#!/usr/bin/env python3
"""Generate bounded, visual-only woodland-edge placements for the default field.

The coordinates are estimated N/E metres for the default field, not surveyed
geography. This tool adds short ground vegetation only; it never edits field or
scenery layout and never creates a tree/sapling asset.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "app/data/woodland_edges.json"
FIELD_PATH = ROOT / "app/data/fields/default.json"
LAKE_PATH = ROOT / "app/data/fields/lake.json"
SCENERY_PATH = ROOT / "app/data/scenery/default.json"
VEGETATION_CATALOG_PATH = ROOT / "app/assets/landscape/vegetation/catalog.json"
TREE_CATALOG_PATH = ROOT / "app/assets/landscape/trees/catalog.json"
HEDGE_MANIFEST_PATH = ROOT / "app/assets/landscape/vegetation/impostors/bush_common_flowers_4view.json"
GRASS_SHORT_MANIFEST_PATH = ROOT / "app/assets/landscape/vegetation/impostors/grass_common_short_4view.json"
GRASS_SHORT_ATLAS_PATH = ROOT / "app/assets/landscape/vegetation/impostors/grass_common_short_4view.png"
SHRUB_SPECIES_MANIFEST_PATHS = {
    "grass_common_tall": ROOT / "app/assets/landscape/vegetation/impostors/grass_common_tall_4view.json",
    "bush_common_flowers": HEDGE_MANIFEST_PATH,
    "fern_1": ROOT / "app/assets/landscape/vegetation/impostors/fern_1_4view.json",
}
HEDGE_SOURCE_PATH = ROOT / "app/scenery/imported_hedge.gd"
PALETTE_SOURCE_PATH = ROOT / "app/scenery/palette.gd"
VEGETATION_SOURCE_PATH = ROOT / "app/scenery/imported_vegetation.gd"
VEGETATION_PLACEMENT_PATH = ROOT / "app/scenery/vegetation_placement.gd"
PREFABS_SOURCE_PATH = ROOT / "app/scenery/prefabs.gd"
MODELS_SOURCE_PATH = ROOT / "app/scenery/models.gd"
FIELD_LOADER_PATH = ROOT / "app/data/field_loader.gd"
TREELINE_SOURCE_PATH = ROOT / "app/render/treeline.gd"
TREE_WIND_SOURCE_PATH = ROOT / "app/render/tree_wind.gdshaderinc"
GRASS_MASK_SOURCE_PATH = ROOT / "app/render/landscape_upgrade/scenery_grass_mask.gd"
TREE_PLACEMENT_SOURCE_PATH = ROOT / "tools/trees/place.py"

FORMAT = "openrc-woodland-edges v3"
LOCAL_CARD_CENTERS_TANGENT_RADIAL_M = (
    (-1.5, 0.6), (-0.6, -0.9), (0.1, 0.2), (1.5, 1.1), (1.4, -0.5), (-1.2, 1.7),
    (0.4, 1.8), (-0.2, 2.5), (-2.3, -0.6), (-2.0, -1.8), (0.5, -1.6), (1.7, -2.0),
)
LOCAL_CARD_SEGMENT_LENGTHS_M = (1.60, 1.70, 1.85, 1.65, 1.90, 1.55, 1.78, 1.62, 1.86, 1.72, 1.95, 1.58)
PATCHES = (
    {"id": "woodland-edge-east-north", "center_ne_m": [249.5, 534.5], "rotation_rad": 0.0,
     "skew": 0.025, "grass_local_tangent_radial_m": [[-4.8, -4.9], [1.8, -5.6], [5.0, -4.2]],
     "shrub_height_m": 0.8},
    {"id": "woodland-edge-east-south", "center_ne_m": [-249.5, 534.5], "rotation_rad": 0.21,
     "skew": -0.03, "grass_local_tangent_radial_m": [[-4.3, -5.2], [2.5, -5.8], [5.4, -3.5]],
     "shrub_height_m": 1.0},
    {"id": "woodland-edge-southwest", "center_ne_m": [-553.0, 201.5], "rotation_rad": -0.16,
     "skew": 0.035, "grass_local_tangent_radial_m": [[-5.3, -4.5], [1.2, -5.9], [5.1, -3.8]],
     "shrub_height_m": 1.1},
    {"id": "woodland-edge-northwest", "center_ne_m": [201.5, -553.0], "rotation_rad": 0.34,
     "skew": -0.02, "grass_local_tangent_radial_m": [[-4.9, -4.7], [2.1, -5.7], [5.2, -3.9]],
     "shrub_height_m": 0.9},
)
SHRUB_WIDTH_M = 0.90
GRASS_HEIGHT_M = 0.25
FLOOR_HALF_SIZE_M = 2.0
FLOOR_TRIANGLES_PER_PATCH = 8
SHRUB_SPECIES_COUNTS = {"grass_common_tall": 4, "bush_common_flowers": 2, "fern_1": 6}
SHRUB_CENTER_JITTER_AXIS_M = 0.24
SHRUB_CLUSTER_COMPACTNESS = 0.72
GRASS_ASSET_ID = "grass_common_short"
SHRUB_QUALITY = "high"
INCLUDE_HEDGEROW_TREES = False
PLANT_CLEARANCE_M = 1.0
PATH_SAMPLE_STEP_M = 0.25
EDGE_RING_MIN_M = 570.0
EDGE_RING_MAX_M = 600.0
# Certified radial footprints from the accepted v1 layout, including each source
# geometry bound and 1 m clearance. The grass points set the outer edge in all four
# patches; shrub layout changes must stay inside these existing per-patch envelopes.
PATCH_RADIAL_ENVELOPE_LIMITS_M = {
    "woodland-edge-east-north": 8.057428,
    "woodland-edge-east-south": 7.778322,
    "woodland-edge-southwest": 8.172611,
    "woodland-edge-northwest": 7.847895,
}
# The twelve original grass positions remain as low, compact edge accents. New cards
# sit in irregular clusters near the shrub groups; their centers stay within 5.2 m of
# each patch floor center. Varying count and spread avoids a ring or a regular grid.
GROUNDCOVER_CENTER_RADIUS_LIMIT_M = 5.2
GROUNDCOVER_MIN_SPACING_M = 0.18
GROUNDCOVER_SEED_BASE = 720000
GROUNDCOVER_CLUMPS = (
    (-3.2, -1.5, 5, 0.92),
    (-1.4, 2.25, 12, 1.00),
    (1.1, -3.0, 6, 1.15),
    (3.2, 0.6, 11, 0.90),
    (-0.25, 4.0, 6, 0.72),
)
GROUNDCOVER_NEW_CARDS_PER_PATCH = sum(item[2] for item in GROUNDCOVER_CLUMPS)


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _source_hash(path: Path) -> str:
    """Hash source text with normalized newlines; hashes are evidence, not runtime gates."""
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _source_number(source: str, name: str, *, integer: bool = False) -> float | int:
    kind = r"int" if integer else r"float"
    pattern = rf"^const\s+{re.escape(name)}\s*:\s*{kind}\s*=\s*([-+0-9.eE]+)"
    match = re.search(pattern, source, re.MULTILINE)
    if match is None:
        raise ValueError(f"could not read {name} from current source")
    return int(match.group(1)) if integer else float(match.group(1))


def _catalog_sizes(source: str) -> dict[str, tuple[float, float, float]]:
    sizes: dict[str, tuple[float, float, float]] = {}
    pattern = re.compile(
        r'"(?P<id>[^"]+)"\s*:\s*\{[^\n]*?size\s*=\s*Vector3\('
        r"\s*(?P<x>[-+0-9.eE]+)\s*,\s*(?P<y>[-+0-9.eE]+)\s*,\s*(?P<z>[-+0-9.eE]+)\s*\)",
        re.MULTILINE,
    )
    for match in pattern.finditer(source):
        sizes[match.group("id")] = tuple(float(match.group(axis)) for axis in ("x", "y", "z"))
    if not sizes:
        raise ValueError("could not read scenery prefab/model size catalogs")
    return sizes


def _max_tree_envelope_m(tree_catalog: dict[str, Any], treeline_source: str,
                         tree_wind_source: str, field_loader_source: str) -> dict[str, float]:
    height_pattern = re.compile(
        r"(?:var\s+)?height(?:\s*:\s*float)?\s*=\s*([0-9.]+)\s*\+\s*"
        r"([0-9.]+)\s*\*\s*float\(h\s*%\s*(\d+)\)\s*/\s*([0-9.]+)"
    )
    height_match = height_pattern.search(treeline_source)
    if height_match is None:
        raise ValueError("could not read treeline identity height formula")
    height_min = float(height_match.group(1))
    height_span = float(height_match.group(2))
    height_modulus = int(height_match.group(3))
    height_divisor = float(height_match.group(4))
    height_max = height_min + height_span * float(height_modulus - 1) / height_divisor

    card_species = tree_catalog.get("species", [])
    frame_sizes = [float(item["frame_size_m"]) for item in card_species]
    if not frame_sizes:
        raise ValueError("tree-card catalog has no species frames")
    frame_size = max(frame_sizes)
    lean = float(_source_number(treeline_source, "WIND_LEAN_M"))
    shader_lean = re.search(r"TREE_WIND_LEAN_M\s*=\s*([-+0-9.eE]+)", tree_wind_source)
    if shader_lean is None or not math.isclose(lean, float(shader_lean.group(1)), abs_tol=1e-12):
        raise ValueError("treeline CPU and shader wind limits disagree")
    radius_cap = float(_source_number(field_loader_source, "TREE_CARD_MAX_HORIZONTAL_RADIUS_M"))
    half_width = frame_size * height_max * 0.5
    highest_vertex = (0.5 + frame_size * 0.5) * height_max
    vertex_radius = math.hypot(half_width, highest_vertex)
    wind_sweep = 2.0 * vertex_radius * math.sin((lean / height_max) * 0.5)
    swept_radius = half_width + wind_sweep
    if swept_radius > radius_cap:
        raise ValueError("runtime tree clearance no longer covers the derived wind envelope")
    return {
        "tree_max_identity_height_m": height_max,
        "tree_max_frame_size_m": frame_size,
        "tree_max_wind_sweep_m_at_10mps": wind_sweep,
        "tree_max_horizontal_radius_with_wind_m": swept_radius,
        "tree_runtime_clearance_radius_m": radius_cap,
        "tree_clearance_used_m": max(radius_cap, swept_radius),
    }


def _vegetation_asset_radius(asset: dict[str, Any], target_height_m: float) -> float:
    bounds = asset.get("source_bounds_m", {})
    minimum = bounds.get("min", [])
    maximum = bounds.get("max", [])
    source_height = float(bounds.get("height", 0.0))
    if len(minimum) != 3 or len(maximum) != 3 or source_height <= 0.0:
        raise ValueError(f"asset has incomplete source bounds: {asset.get('id')}")
    scale = target_height_m / source_height
    x_radius = max(abs(float(minimum[0])), abs(float(maximum[0]))) * scale
    z_radius = max(abs(float(minimum[2])), abs(float(maximum[2]))) * scale
    return math.hypot(x_radius, z_radius)


def _vegetation_aliases(vegetation_source: str, alias: str) -> list[str]:
    match = re.search(rf'"{re.escape(alias)}"\s*:\s*\[(.*?)\]', vegetation_source, re.DOTALL)
    if match is None:
        return []
    return re.findall(r'"([^"]+)"', match.group(1))


def _max_prop_radii(prefab_source: str, model_source: str,
                    vegetation_catalog: dict[str, Any], vegetation_source: str,
                    placement_source: str) -> tuple[dict[str, float], float]:
    sizes = _catalog_sizes(prefab_source)
    sizes.update(_catalog_sizes(model_source))
    radii = {asset_id: 0.5 * math.hypot(size[0], size[2]) for asset_id, size in sizes.items()}
    assets = {str(item["id"]): item for item in vegetation_catalog.get("assets", [])}
    role_heights: dict[str, float] = {}
    for prefab, pattern in (
        ("shade_tree", r"var\s+height\s*:=\s*([0-9.]+)\s*\+\s*([0-9.]+)\s*\*"),
        ("sapling", r'if\s+prefab\s*==\s*"sapling":\s*\n\s*height\s*(?::=|=)\s*([0-9.]+)\s*\+\s*([0-9.]+)\s*\*'),
        ("bush", r'if\s+prefab\s*==\s*"bush":\s*\n\s*height\s*(?::=|=)\s*([0-9.]+)\s*\+\s*([0-9.]+)\s*\*'),
        ("flower_clump", r'if\s+prefab\s*==\s*"flower_clump":\s*\n\s*height\s*(?::=|=)\s*([0-9.]+)\s*\+\s*([0-9.]+)\s*\*'),
    ):
        match = re.search(pattern, placement_source)
        if match is None:
            raise ValueError(f"could not read variable vegetation height for {prefab}")
        role_heights[prefab] = float(match.group(1)) + float(match.group(2))

    for prefab, max_height in role_heights.items():
        ids = _vegetation_aliases(vegetation_source, prefab)
        if not ids:
            ids = [prefab] if prefab in assets else []
        candidates = [assets[item] for item in ids if item in assets]
        if not candidates:
            raise ValueError(f"no catalog assets resolve scenery vegetation alias {prefab}")
        radii[prefab] = max(_vegetation_asset_radius(asset, max_height) for asset in candidates)
    if not radii:
        raise ValueError("scenery placement radius catalog is empty")
    return radii, max(radii.values())


def _number(value: Any) -> float:
    if isinstance(value, dict):
        return float(value["value"])
    return float(value)


def _segment_distance(point: tuple[float, float], start: tuple[float, float],
                      finish: tuple[float, float]) -> float:
    dn = finish[0] - start[0]
    de = finish[1] - start[1]
    length_sq = dn * dn + de * de
    if length_sq <= 1e-18:
        return math.hypot(point[0] - start[0], point[1] - start[1])
    t = max(0.0, min(1.0, ((point[0] - start[0]) * dn + (point[1] - start[1]) * de) / length_sq))
    return math.hypot(point[0] - start[0] - t * dn, point[1] - start[1] - t * de)


def _point_in_polygon(point: tuple[float, float], polygon: list[tuple[float, float]]) -> bool:
    if len(polygon) < 3:
        return False
    north, east = point
    inside = False
    for index, first in enumerate(polygon):
        second = polygon[(index + 1) % len(polygon)]
        if _segment_distance(point, first, second) <= 1e-9:
            return True
        if (first[0] > north) != (second[0] > north):
            crossing_east = (second[1] - first[1]) * (north - first[0]) / (second[0] - first[0]) + first[1]
            if east < crossing_east:
                inside = not inside
    return inside


def _polygon_distance(point: tuple[float, float], polygon: list[tuple[float, float]]) -> float:
    if _point_in_polygon(point, polygon):
        return 0.0
    return min(
        (_segment_distance(point, polygon[index], polygon[(index + 1) % len(polygon)])
         for index in range(len(polygon))),
        default=math.inf,
    )


def _raw_points(group: dict[str, Any]) -> list[tuple[float, float]]:
    raw = group.get("points", [])
    if isinstance(raw, dict):
        raw = raw.get("value", [])
    result: list[tuple[float, float]] = []
    if isinstance(raw, list):
        for pair in raw:
            if isinstance(pair, (list, tuple)) and len(pair) >= 2:
                result.append((float(pair[0]), float(pair[1])))
    return result


def _tree_points(field: dict[str, Any]) -> list[tuple[float, float]]:
    objects = [obj for obj in field.get("objects", []) if obj.get("type") == "treeline"]
    if len(objects) != 1:
        raise ValueError("default field must contain exactly one treeline object")
    positions = objects[0].get("positions", {}).get("value", [])
    if not isinstance(positions, list):
        raise ValueError("treeline positions are invalid")
    return [(float(point[0]), float(point[1])) for point in positions]


def _scene_obstacles(scenery: dict[str, Any], prefab_radii: dict[str, float],
                     max_prop_radius: float) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    circles: list[dict[str, Any]] = []
    lines: list[dict[str, Any]] = []
    polygons: list[dict[str, Any]] = []
    for group in scenery.get("groups", []):
        group_type = str(group.get("type", ""))
        group_id = str(group.get("id", "scenery"))
        if group_type == "instances":
            placements = group.get("placements", {}).get("value", [])
            if not isinstance(placements, list):
                continue
            candidates = group.get("prefabs", group.get("prefab", ""))
            if isinstance(candidates, str):
                candidates = [candidates]
            if not isinstance(candidates, list):
                candidates = []
            radius = max((prefab_radii.get(str(item), max_prop_radius) for item in candidates),
                         default=max_prop_radius)
            for index, placement in enumerate(placements):
                if isinstance(placement, dict):
                    north = float(placement.get("north", 0.0))
                    east = float(placement.get("east", 0.0))
                    prefab = str(placement.get("prefab", ""))
                    this_radius = prefab_radii.get(prefab, radius)
                elif isinstance(placement, (list, tuple)) and len(placement) >= 2:
                    north, east = float(placement[0]), float(placement[1])
                    this_radius = radius
                else:
                    continue
                circles.append({"id": f"{group_id}:{index}", "north": north, "east": east,
                                "radius_m": this_radius})
        elif group_type in ("track", "hedge", "fence"):
            points = _raw_points(group)
            if len(points) < 2:
                continue
            width = _number(group.get("width", 0.0))
            for index, (start, finish) in enumerate(zip(points, points[1:])):
                lines.append({"id": f"{group_id}:{index}", "start": start, "finish": finish,
                              "half_width_m": max(0.0, width * 0.5)})
        elif group_type == "patch":
            points = _raw_points(group)
            if len(points) >= 3:
                polygons.append({"id": group_id, "points": points})
    return circles, lines, polygons


def _hash01(a: int, b: int, c: int) -> float:
    """Mirror Palette.hash01's signed 64-bit GDScript integer operations."""
    mask = (1 << 64) - 1

    def signed(value: int) -> int:
        value &= mask
        return value - (1 << 64) if value >= (1 << 63) else value

    h = signed((a * 73856093) ^ (b * 19349663) ^ (c * 83492791))
    h = signed((h ^ (h >> 13)) * 1274126177)
    h = signed(h ^ (h >> 16))
    return float(h & 0xFFFF) / 65536.0


def _coherent_species_assignments(
    local_centers: list[tuple[float, float]], path_seeds: list[int]
) -> list[str]:
    """Assign compact tall-grass and flowering groups; ferns fill the understory."""
    if len(local_centers) != 12 or len(path_seeds) != 12:
        raise ValueError("woodland patches require twelve local shrub centers and seeds")

    def anchor(seed: int, lane: int, indices: list[int]) -> int:
        selected = int(_hash01(seed, lane, 233) * len(indices))
        return indices[selected]

    def closest(anchor_index: int, indices: list[int], count: int) -> list[int]:
        origin = local_centers[anchor_index]
        return sorted(
            indices,
            key=lambda index: (
                math.dist(local_centers[index], origin),
                _hash01(path_seeds[index], 499, anchor_index),
                index,
            ),
        )[:count]

    assignments = ["fern_1"] * len(local_centers)
    remaining = list(range(len(local_centers)))
    grass_anchor = anchor(path_seeds[0], 701, remaining)
    grass_group = closest(grass_anchor, remaining, SHRUB_SPECIES_COUNTS["grass_common_tall"])
    for index in grass_group:
        assignments[index] = "grass_common_tall"
    remaining = [index for index in remaining if index not in grass_group]

    flower_anchor = anchor(path_seeds[-1], 907, remaining)
    flower_group = closest(flower_anchor, remaining, SHRUB_SPECIES_COUNTS["bush_common_flowers"])
    for index in flower_group:
        assignments[index] = "bush_common_flowers"
    return assignments


def _shrub_heights(path_seeds: list[int], species: list[str], ceiling_m: float) -> list[float]:
    """Keep a few full-height forms and let ferns taper into low understory."""
    mature_indices = [index for index, source_id in enumerate(species) if source_id == "grass_common_tall"]
    mature_index = mature_indices[int(_hash01(path_seeds[0], 919, 337) * len(mature_indices))]
    heights: list[float] = []
    for index, (seed, source_id) in enumerate(zip(path_seeds, species)):
        if index == mature_index:
            factor = 1.0
        elif source_id == "fern_1":
            factor = 0.55 + 0.18 * _hash01(seed, 811, 73)
        elif source_id == "bush_common_flowers":
            factor = 0.76 + 0.24 * _hash01(seed, 812, 73)
        else:
            factor = 0.68 + 0.32 * _hash01(seed, 813, 73)
        heights.append(round(ceiling_m * factor, 6))
    return heights


def _grass_heights(path_seeds: list[int], ceiling_m: float) -> list[float]:
    """Vary the existing grass species from low margin tufts to its old maximum."""
    if not path_seeds:
        raise ValueError("grass height generation requires the existing patch path seeds")
    grass_seeds = [int(path_seeds[0]) + 100 + index for index in range(3)]
    tallest_index = int(_hash01(path_seeds[0], 923, 337) * len(grass_seeds))
    return [
        round(ceiling_m if index == tallest_index else ceiling_m * (
            0.45 + 0.55 * _hash01(seed, 824, 73)
        ), 6)
        for index, seed in enumerate(grass_seeds)
    ]


def _patch_local_to_world(template: dict[str, Any], point: tuple[float, float]) -> tuple[float, float]:
    """Map patch-local tangent/radial coordinates into field north/east metres."""
    center_north, center_east = (float(value) for value in template["center_ne_m"])
    center_radius = math.hypot(center_north, center_east)
    radial_north, radial_east = center_north / center_radius, center_east / center_radius
    tangent_north, tangent_east = -radial_east, radial_north
    tangent, radial = point
    phase = float(template["rotation_rad"])
    cosine, sine = math.cos(phase), math.sin(phase)
    rotated_tangent = tangent * cosine - radial * sine
    rotated_radial = tangent * sine + radial * cosine
    rotated_tangent += float(template["skew"]) * rotated_radial
    return (
        round(center_north + rotated_tangent * tangent_north + rotated_radial * radial_north, 6),
        round(center_east + rotated_tangent * tangent_east + rotated_radial * radial_east, 6),
    )


def _grass_card_radius_per_height(manifest: dict[str, Any]) -> float:
    frame = [float(value) for value in manifest.get("frame_world_size_m", [])]
    source_height = float(manifest.get("source_height_m", 0.0))
    if len(frame) != 2 or min(frame) <= 0.0 or source_height <= 0.0:
        raise ValueError("short-grass impostor manifest has invalid frame dimensions")
    return math.hypot(frame[0] * 0.5, frame[1] * 0.5) / source_height


def _groundcover_cards(
    template: dict[str, Any], patch_index: int, legacy_grass_ne_m: list[list[float]],
    legacy_grass_heights_m: list[float], grass_asset: dict[str, Any],
    grass_manifest: dict[str, Any],
) -> list[dict[str, Any]]:
    """Create three envelope-preserving legacy cards and forty clumped skirt cards."""
    patch_id = str(template["id"])
    if len(legacy_grass_ne_m) != 3 or len(legacy_grass_heights_m) != 3:
        raise ValueError(f"{patch_id}: expected the three retained grass positions")
    card_radius_coefficient = _grass_card_radius_per_height(grass_manifest)
    mesh_radius_coefficient = _vegetation_asset_radius(grass_asset, 1.0)
    cards: list[dict[str, Any]] = []

    # V3 runtime reads grass_cards. These records retain the old positions and IDs;
    # their requested heights fit the same full-quad footprint as the old mesh.
    for index, (point, old_height) in enumerate(zip(legacy_grass_ne_m, legacy_grass_heights_m)):
        seed = int(710000 + patch_index * 100 + 100 + index)
        old_radius = mesh_radius_coefficient * float(old_height)
        max_card_height = old_radius / card_radius_coefficient
        height = math.floor(min(float(old_height), max_card_height) * 1_000_000_000) / 1_000_000_000
        cards.append({
            "id": f"{patch_id}:grass:{index}",
            "north_m": float(point[0]),
            "east_m": float(point[1]),
            "height_m": height,
            "yaw_rad": round(math.tau * _hash01(seed, 4259, 73), 6),
            "seed": seed,
        })

    center = (float(template["floor_center_ne_m"][0]), float(template["floor_center_ne_m"][1]))
    occupied = [(float(card["north_m"]), float(card["east_m"])) for card in cards]
    new_index = 0
    for cluster_index, (anchor_tangent, anchor_radial, count, spread_m) in enumerate(GROUNDCOVER_CLUMPS):
        cluster_seed = 730000 + patch_index * 20 + cluster_index
        anchor = (
            float(anchor_tangent) + (_hash01(cluster_seed, 61, 17) - 0.5) * 0.36,
            float(anchor_radial) + (_hash01(cluster_seed, 67, 17) - 0.5) * 0.36,
        )
        for _ in range(count):
            seed = GROUNDCOVER_SEED_BASE + patch_index * 100 + new_index
            point: tuple[float, float] | None = None
            for attempt in range(128):
                radius = float(spread_m) * math.sqrt(_hash01(seed, attempt, 941))
                angle = math.tau * _hash01(seed, attempt, 947)
                local_point = (anchor[0] + math.cos(angle) * radius,
                               anchor[1] + math.sin(angle) * radius)
                candidate = _patch_local_to_world(template, local_point)
                if math.dist(candidate, center) > GROUNDCOVER_CENTER_RADIUS_LIMIT_M:
                    continue
                if any(math.dist(candidate, other) < GROUNDCOVER_MIN_SPACING_M for other in occupied):
                    continue
                point = candidate
                break
            if point is None:
                raise ValueError(f"{patch_id}: could not fit deterministic groundcover clump {cluster_index}")

            occupied.append(point)
            center_radius = math.dist(point, center)
            taper = max(0.0, min(1.0, (center_radius - 2.4) /
                                  (GROUNDCOVER_CENTER_RADIUS_LIMIT_M - 2.4)))
            height = (0.22 + 0.16 * _hash01(seed, 4253, 73)) * (1.0 - 0.52 * taper)
            cards.append({
                "id": f"{patch_id}:groundcover:{new_index}",
                "north_m": point[0],
                "east_m": point[1],
                "height_m": round(height, 6),
                "yaw_rad": round(math.tau * _hash01(seed, 4259, 73), 6),
                "seed": seed,
            })
            new_index += 1

    if new_index != GROUNDCOVER_NEW_CARDS_PER_PATCH:
        raise ValueError(f"{patch_id}: generated an incomplete groundcover population")
    return cards


def _parse_hedge_contract(source: str, palette_source: str) -> dict[str, float | int]:
    number_specs = {
        "card_triangles": (r"const\s+CARD_TRIANGLES\s*:=\s*(\d+)", int),
        "card_spacing_m": (r"const\s+CARD_SPACING_M\s*:=\s*([-+0-9.eE]+)", float),
        "card_jitter_m": (r"minf\(\s*([-+0-9.eE]+)\s*,\s*minf\(along", float),
        "lateral_jitter_scale": (r"minf\(width\s*\*\s*([-+0-9.eE]+)\s*,\s*1\.0\)", float),
        "height_scale_min": (r"height\s*\*\s*\(\s*([-+0-9.eE]+)\s*\+", float),
        "height_scale_span": (r"\+\s*([-+0-9.eE]+)\s*\*\s*Palette\.hash01\(seed, candidate_id, 53\)", float),
    }
    output: dict[str, float | int] = {}
    for key, (pattern, convert) in number_specs.items():
        match = re.search(pattern, source)
        if match is None:
            raise ValueError(f"could not read ImportedHedge layout contract {key}")
        output[key] = convert(match.group(1))
    cap_block = re.search(r"CARD_INSTANCE_LIMITS\s*:=\s*\{([^}]+)", source)
    rank_block = re.search(r"QUALITY_RANK_LIMITS\s*:=\s*\{([^}]+)", source)
    if cap_block is None or rank_block is None:
        raise ValueError("could not read ImportedHedge quality dictionaries")
    cap = re.search(r'"high"\s*:\s*(\d+)', cap_block.group(1))
    rank = re.search(r'"high"\s*:\s*([-+0-9.eE]+)', rank_block.group(1))
    if cap is None or rank is None:
        raise ValueError("could not read ImportedHedge high-quality limits")
    output["high_instance_limit"] = int(cap.group(1))
    output["high_rank_limit"] = float(rank.group(1))
    if output["high_rank_limit"] != 1.0:
        raise ValueError("high-quality hedge layout must include all stable candidates")
    hash_source = re.search(r"static func hash01\(.*?\n\treturn float\(h & 0xFFFF\) / 65536\.0", palette_source, re.DOTALL)
    if hash_source is None:
        raise ValueError("Palette.hash01 source contract changed; update deterministic placement mirror")
    return output


def _layout_card_positions(path_ne_m: list[list[float]], seed: int,
                           shrub_width_m: float, hedge: dict[str, float | int]) -> list[tuple[float, float]]:
    """Return actual candidate positions, mirroring ImportedHedge.layout in render X/Z."""
    render_points = [(-float(point[1]), -float(point[0])) for point in path_ne_m]
    spacing = float(hedge["card_spacing_m"])
    jitter_cap = float(hedge["card_jitter_m"])
    lateral_limit = min(shrub_width_m * float(hedge["lateral_jitter_scale"]), 1.0)
    result: list[tuple[float, float]] = []
    for start, finish in zip(render_points, render_points[1:]):
        dx, dz = finish[0] - start[0], finish[1] - start[1]
        length = math.hypot(dx, dz)
        if length <= 0.01:
            continue
        count = math.floor(length / spacing)
        ux, uz = dx / length, dz / length
        nx, nz = -uz, ux
        for candidate_id in range(count):
            along = spacing * (candidate_id + 0.5)
            max_jitter = max(0.0, min(jitter_cap, along - 0.1, length - along - 0.1))
            along += (_hash01(seed, candidate_id, 41) * 2.0 - 1.0) * max_jitter
            lateral = (_hash01(seed, candidate_id, 43) - 0.5) * lateral_limit
            x = start[0] + ux * along + nx * lateral
            z = start[1] + uz * along + nz * lateral
            result.append((-z, -x))  # render X/Z back to default-field N/E
    return result


def _line_samples(path_ne_m: list[list[float]], step_m: float) -> Iterable[tuple[float, float]]:
    for start, finish in zip(path_ne_m, path_ne_m[1:]):
        length = math.hypot(float(finish[0]) - float(start[0]), float(finish[1]) - float(start[1]))
        count = max(1, math.ceil(length / step_m))
        for index in range(count + 1):
            fraction = index / count
            yield (
                float(start[0]) + (float(finish[0]) - float(start[0])) * fraction,
                float(start[1]) + (float(finish[1]) - float(start[1])) * fraction,
            )


def _lake_polygon(lake: dict[str, Any]) -> list[tuple[float, float]]:
    origin = lake["origin"]
    on, oe = float(origin["north_m"]), float(origin["east_m"])
    return [(on + float(point[0]), oe + float(point[1])) for point in lake["bank_offsets_ne_m"]]


def _surface_bounds(surface: dict[str, Any]) -> tuple[float, float, float, float]:
    n = _number(surface["center_north"])
    e = _number(surface["center_east"])
    half_n = _number(surface["width_north_south"]) * 0.5
    half_e = _number(surface["length_east_west"]) * 0.5
    return n - half_n, n + half_n, e - half_e, e + half_e


def _distance_to_rect(north: float, east: float,
                      bounds: tuple[float, float, float, float]) -> float:
    n0, n1, e0, e1 = bounds
    dn = max(n0 - north, 0.0, north - n1)
    de = max(e0 - east, 0.0, east - e1)
    return math.hypot(dn, de)


def _tree_nearest_distance(point: tuple[float, float], trees: list[tuple[float, float]]) -> float:
    return min((math.hypot(point[0] - tree[0], point[1] - tree[1]) for tree in trees), default=math.inf)


def _mask_check(
    point: tuple[float, float], envelope_m: float, *, field: dict[str, Any], scenery: dict[str, Any],
    lake_polygon: list[tuple[float, float]], tree_points: list[tuple[float, float]],
    tree_clearance_m: float, runway_corridor_m: float, tracks: list[dict[str, Any]],
    prop_circles: list[dict[str, Any]], prop_lines: list[dict[str, Any]],
    prop_polygons: list[dict[str, Any]],
) -> tuple[list[str], dict[str, float]]:
    north, east = point
    errors: list[str] = []
    margins: dict[str, float] = {}
    radius = math.hypot(north, east)
    margins["edge_ring_inner_m"] = radius - envelope_m - EDGE_RING_MIN_M
    margins["edge_ring_outer_m"] = EDGE_RING_MAX_M - radius - envelope_m
    if margins["edge_ring_inner_m"] < 0.0 or margins["edge_ring_outer_m"] < 0.0:
        errors.append("outside 570-600m woodland-edge ring with geometry envelope")

    # The same two crown-cleared display gaps used by tools/trees/place.py.
    from place import GAPS, _angular_distance
    angle = math.degrees(math.atan2(east, north)) % 360.0
    gap_margin = math.degrees(math.asin(min(1.0, envelope_m / max(radius, 1e-9))))
    gap_clearance = min(
        _angular_distance(angle, center) - half - gap_margin
        for center, half in GAPS
    )
    margins["protected_gap_clearance_deg"] = gap_clearance
    if gap_clearance <= 0.0:
        errors.append("intersects a protected treeline gap")

    nearest_tree = _tree_nearest_distance(point, tree_points)
    margins["tree_clearance_m"] = nearest_tree - tree_clearance_m - envelope_m
    if margins["tree_clearance_m"] < 0.0:
        errors.append("plant geometry intersects a current tree full wind envelope")

    rough_margins: list[float] = []
    for surface in field.get("surfaces", []):
        bounds = _surface_bounds(surface)
        if surface.get("type") == "rough":
            n0, n1, e0, e1 = bounds
            rough_margins.append(min(north - envelope_m - n0, n1 - north - envelope_m,
                                     east - envelope_m - e0, e1 - east - envelope_m))
    margins["rough_surface_margin_m"] = max(rough_margins, default=-math.inf)
    if margins["rough_surface_margin_m"] < 0.0:
        errors.append("plant geometry is not contained by a rough surface")

    runway_margin = math.inf
    rotor_margin = math.inf
    for surface in field.get("surfaces", []):
        surface_type = surface.get("type")
        bounds = _surface_bounds(surface)
        if surface_type in ("runway", "mown"):
            required = _number(surface["width_north_south"]) * 0.5 + runway_corridor_m + envelope_m
            runway_margin = min(runway_margin, abs(north - _number(surface["center_north"])) - required)
        elif surface_type == "rotorpad":
            rotor_margin = min(rotor_margin, _distance_to_rect(north, east, bounds) - runway_corridor_m - envelope_m)
    margins["runway_corridor_margin_m"] = runway_margin
    margins["rotorpad_corridor_margin_m"] = rotor_margin
    if runway_margin <= 0.0:
        errors.append("plant geometry intersects a runway/mown approach corridor")
    if rotor_margin <= 0.0:
        errors.append("plant geometry intersects the rotorpad clearance envelope")

    lake_distance = _polygon_distance(point, lake_polygon)
    margins["lake_bank_clearance_m"] = lake_distance - envelope_m
    if margins["lake_bank_clearance_m"] <= 0.0:
        errors.append("plant geometry intersects the authoritative lake-bank polygon")

    track_clearance = min(
        (_segment_distance(point, track["start"], track["finish"])
         - float(track["half_width_m"]) - envelope_m for track in tracks),
        default=math.inf,
    )
    margins["track_clearance_m"] = track_clearance
    if track_clearance <= 0.0:
        errors.append("plant geometry intersects an authored scenery track")

    prop_clearance = min(
        (math.hypot(north - float(prop["north"]), east - float(prop["east"]))
         - float(prop["radius_m"]) - envelope_m for prop in prop_circles),
        default=math.inf,
    )
    margins["props_clearance_m"] = prop_clearance
    if prop_clearance <= 0.0:
        errors.append("plant geometry intersects an authored scenery prop envelope")

    line_clearance = min(
        (_segment_distance(point, line["start"], line["finish"])
         - float(line["half_width_m"]) - envelope_m for line in prop_lines),
        default=math.inf,
    )
    margins["hedge_fence_clearance_m"] = line_clearance
    if line_clearance <= 0.0:
        errors.append("plant geometry intersects an authored hedge/fence line")

    patch_clearance = min(
        (_polygon_distance(point, polygon["points"]) - envelope_m for polygon in prop_polygons),
        default=math.inf,
    )
    margins["scenery_patch_clearance_m"] = patch_clearance
    if patch_clearance <= 0.0:
        errors.append("plant geometry intersects an authored scenery patch")
    return errors, margins


def _expected_paths() -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for patch_index, template in enumerate(PATCHES):
        center_north, center_east = (float(value) for value in template["center_ne_m"])
        center_radius = math.hypot(center_north, center_east)
        radial_north, radial_east = center_north / center_radius, center_east / center_radius
        tangent_north, tangent_east = -radial_east, radial_north
        phase = float(template["rotation_rad"])
        skew = float(template["skew"])
        cosine, sine = math.cos(phase), math.sin(phase)

        def offset_to_world(point: tuple[float, float] | list[float]) -> tuple[float, float]:
            tangent, radial = float(point[0]), float(point[1])
            rotated_tangent = tangent * cosine - radial * sine
            rotated_radial = tangent * sine + radial * cosine
            rotated_tangent += skew * rotated_radial
            return (
                rotated_tangent * tangent_north + rotated_radial * radial_north,
                rotated_tangent * tangent_east + rotated_radial * radial_east,
            )

        def to_world(point: tuple[float, float] | list[float]) -> list[float]:
            north_offset, east_offset = offset_to_world(point)
            return [round(center_north + north_offset, 6), round(center_east + east_offset, 6)]

        paths: list[list[list[float]]] = []
        path_seeds: list[int] = []
        local_centers: list[tuple[float, float]] = []
        segment_lengths: list[float] = []
        for path_index, (source_center, source_length) in enumerate(zip(
            LOCAL_CARD_CENTERS_TANGENT_RADIAL_M, LOCAL_CARD_SEGMENT_LENGTHS_M,
        )):
            seed = 710000 + patch_index * 100 + path_index
            path_seeds.append(seed)
            tangent = float(source_center[0]) + (
                _hash01(seed, 811, 233) * 2.0 - 1.0
            ) * SHRUB_CENTER_JITTER_AXIS_M
            radial = float(source_center[1]) + (
                _hash01(seed, 812, 233) * 2.0 - 1.0
            ) * SHRUB_CENTER_JITTER_AXIS_M
            local_center = (
                tangent * SHRUB_CLUSTER_COMPACTNESS,
                radial * SHRUB_CLUSTER_COMPACTNESS,
            )
            local_centers.append(local_center)
            segment_lengths.append(min(
                1.95,
                max(1.55, float(source_length) + (_hash01(seed, 813, 233) * 2.0 - 1.0) * 0.12),
            ))
            yaw = (
                math.tau * _hash01(seed, 751, 337)
                + phase
                + (_hash01(seed, 814, 233) * 2.0 - 1.0) * 0.24
            )
            direction_north, direction_east = offset_to_world((math.cos(yaw), math.sin(yaw)))
            direction_length = math.hypot(direction_north, direction_east)
            direction_north /= direction_length
            direction_east /= direction_length
            middle_north, middle_east = to_world(local_center)
            half_length = segment_lengths[-1] * 0.5
            paths.append([
                [round(middle_north - direction_north * half_length, 6),
                 round(middle_east - direction_east * half_length, 6)],
                [round(middle_north + direction_north * half_length, 6),
                 round(middle_east + direction_east * half_length, 6)],
            ])

        species = _coherent_species_assignments(local_centers, path_seeds)
        shrub_heights = _shrub_heights(path_seeds, species, float(template["shrub_height_m"]))
        grass_heights = _grass_heights(path_seeds, GRASS_HEIGHT_M)

        result.append({
            "id": template["id"],
            "center_ne_m": [round(center_north, 6), round(center_east, 6)],
            "rotation_rad": phase,
            "skew": skew,
            "paths_ne_m": paths,
            "grass_ne_m": [to_world(point) for point in template["grass_local_tangent_radial_m"]],
            "floor_center_ne_m": [round(center_north, 6), round(center_east, 6)],
            "floor_half_size_m": FLOOR_HALF_SIZE_M,
            "path_seeds": path_seeds,
            "shrub_species": species,
            "shrub_heights_m": shrub_heights,
            "shrub_height_m": template["shrub_height_m"],
            "shrub_width_m": SHRUB_WIDTH_M,
            "grass_heights_m": grass_heights,
            "grass_height_m": GRASS_HEIGHT_M,
        })
    return result


def build_document() -> dict[str, Any]:
    field = _read_json(FIELD_PATH)
    scenery = _read_json(SCENERY_PATH)
    lake = _read_json(LAKE_PATH)
    vegetation_catalog = _read_json(VEGETATION_CATALOG_PATH)
    tree_catalog = _read_json(TREE_CATALOG_PATH)
    hedge_manifest = _read_json(HEDGE_MANIFEST_PATH)
    grass_manifest = _read_json(GRASS_SHORT_MANIFEST_PATH)
    shrub_species_manifests = {
        source_id: _read_json(path)
        for source_id, path in SHRUB_SPECIES_MANIFEST_PATHS.items()
    }
    hedge_source = HEDGE_SOURCE_PATH.read_text(encoding="utf-8")
    palette_source = PALETTE_SOURCE_PATH.read_text(encoding="utf-8")
    vegetation_source = VEGETATION_SOURCE_PATH.read_text(encoding="utf-8")
    placement_source = VEGETATION_PLACEMENT_PATH.read_text(encoding="utf-8")
    prefab_source = PREFABS_SOURCE_PATH.read_text(encoding="utf-8")
    model_source = MODELS_SOURCE_PATH.read_text(encoding="utf-8")
    loader_source = FIELD_LOADER_PATH.read_text(encoding="utf-8")
    treeline_source = TREELINE_SOURCE_PATH.read_text(encoding="utf-8")
    tree_wind_source = TREE_WIND_SOURCE_PATH.read_text(encoding="utf-8")

    if field.get("id") != "default" or scenery.get("id") not in (None, "default"):
        raise ValueError("woodland-edge placements are scoped to the default field/scenery")
    pilot_north = _number(field["pilot"]["north"])
    pilot_east = _number(field["pilot"]["east"])
    if abs(pilot_north) > 1e-9 or abs(pilot_east) > 1e-9:
        raise ValueError("woodland-edge coordinates require the default pilot origin at N=E=0")
    tree_points = _tree_points(field)
    if len(tree_points) != int(_source_number(loader_source, "MAX_TREELINE_POSITIONS", integer=True)):
        raise ValueError("current default tree population differs from the field-loader contract")

    hedge = _parse_hedge_contract(hedge_source, palette_source)
    if not INCLUDE_HEDGEROW_TREES:
        pass
    if hedge_manifest.get("source_name") != "Bush_Common_Flowers":
        raise ValueError("unexpected source behind the retained hedge-card atlas")
    frame_world_size = max(float(value) for value in hedge_manifest["frame_world_size_m"])
    patch_templates = _expected_paths()
    shrub_height_scale_max = float(hedge["height_scale_min"]) + float(hedge["height_scale_span"])
    shrub_max_height = max(float(patch["shrub_height_m"]) for patch in patch_templates) * shrub_height_scale_max
    shrub_max_scale = shrub_max_height / float(hedge_manifest["source_height_m"])
    shrub_full_quad_radius = math.hypot(frame_world_size * 0.5, frame_world_size * 0.5) * shrub_max_scale
    quad_radius_per_setting_m = shrub_full_quad_radius / max(float(patch["shrub_height_m"]) for patch in patch_templates)
    lateral_max = 0.5 * min(SHRUB_WIDTH_M * float(hedge["lateral_jitter_scale"]), 1.0)
    path_displacement_bound = math.hypot(float(hedge["card_jitter_m"]), lateral_max)

    grass_assets = {str(item["id"]): item for item in vegetation_catalog.get("assets", [])}
    if GRASS_ASSET_ID not in grass_assets:
        raise ValueError(f"missing ground-vegetation source {GRASS_ASSET_ID}")
    grass_asset = grass_assets[GRASS_ASSET_ID]
    grass_triangles = int(grass_asset.get("source_triangles", 0))
    if grass_triangles <= 0:
        raise ValueError("grass source has no validated triangle count")
    grass_frame_size = [float(value) for value in grass_manifest.get("frame_world_size_m", [])]
    grass_source_height = float(grass_manifest.get("source_height_m", 0.0))
    if (grass_manifest.get("format") != "openrc-vegetation-impostor v1"
            or grass_manifest.get("derived_from_asset_id") != GRASS_ASSET_ID
            or grass_manifest.get("source_geometry_sha256") != grass_asset.get("source_sha256")
            or int(grass_manifest.get("source_triangles", -1)) != grass_triangles
            or len(grass_frame_size) != 2 or min(grass_frame_size) <= 0.0
            or grass_source_height <= 0.0
            or not re.fullmatch(r"[0-9a-f]{64}", str(grass_manifest.get("atlas_sha256", "")))):
        raise ValueError("short-grass impostor manifest does not match the current source asset")
    catalog_height = float(grass_asset.get("source_bounds_m", {}).get("height", 0.0))
    if not math.isclose(grass_source_height, catalog_height, rel_tol=0.0, abs_tol=1e-6):
        raise ValueError("short-grass impostor source height differs from the vegetation catalog")
    if (not GRASS_SHORT_ATLAS_PATH.is_file()
            or hashlib.sha256(GRASS_SHORT_ATLAS_PATH.read_bytes()).hexdigest()
            != grass_manifest["atlas_sha256"]):
        raise ValueError("short-grass impostor atlas does not match its manifest hash")
    missing_species = sorted(set(SHRUB_SPECIES_COUNTS) - set(grass_assets))
    if missing_species:
        raise ValueError(f"missing woodland shrub source assets: {', '.join(missing_species)}")
    shrub_species_source_metadata: dict[str, dict[str, Any]] = {}
    for source_id in SHRUB_SPECIES_COUNTS:
        manifest = shrub_species_manifests[source_id]
        asset = grass_assets[source_id]
        species_frame_world_size = [float(value) for value in manifest.get("frame_world_size_m", [])]
        source_height = float(manifest.get("source_height_m", 0.0))
        source_triangles = int(manifest.get("source_triangles", 0))
        if (manifest.get("format") != "openrc-vegetation-impostor v1"
                or manifest.get("derived_from_asset_id") != source_id
                or asset.get("source_sha256") != manifest.get("source_geometry_sha256")
                or source_triangles != int(asset.get("source_triangles", -1))
                or len(species_frame_world_size) != 2 or min(species_frame_world_size) <= 0.0
                or source_height <= 0.0):
            raise ValueError(f"woodland shrub impostor manifest does not match source asset {source_id}")
        shrub_species_source_metadata[source_id] = {
            "impostor_asset_id": str(manifest["asset_id"]),
            "source_geometry_sha256": str(manifest["source_geometry_sha256"]),
            "source_triangles": source_triangles,
            "source_height_m": round(source_height, 9),
            "frame_world_size_m": [round(value, 9) for value in species_frame_world_size],
            "source_height_to_frame_ratio": round(source_height / max(species_frame_world_size), 9),
            "atlas_sha256": str(manifest["atlas_sha256"]),
        }

    hedge_source_id = str(hedge_manifest.get("derived_from_asset_id", ""))
    hedge_asset = next((item for item in vegetation_catalog.get("assets", [])
                        if item.get("id") == hedge_source_id), None)
    if hedge_asset is None:
        raise ValueError("hedge impostor source asset is missing from vegetation catalog")
    if int(hedge_manifest.get("source_triangles", -1)) != int(hedge_asset.get("source_triangles", -2)):
        raise ValueError("hedge impostor manifest/catalog source triangle counts disagree")
    card_triangles = int(hedge_source.split("const CARD_TRIANGLES :=", 1)[1].splitlines()[0].strip())
    if card_triangles <= 0:
        raise ValueError("hedge card triangle count is invalid")
    hedge_asset_id_match = re.search(r'const\s+BUSH_ATLAS_ASSET_ID\s*:=\s*"([^"]+)"', hedge_source)
    if hedge_asset_id_match is None:
        raise ValueError("could not read shrub-card runtime asset id")

    tree_contract = _max_tree_envelope_m(tree_catalog, treeline_source, tree_wind_source, loader_source)
    runway_corridor = float(_source_number(loader_source, "TREE_FLIGHT_CORRIDOR_HALF_WIDTH_M"))
    lake_polygon = _lake_polygon(lake)
    prop_radii, max_prop_radius = _max_prop_radii(
        prefab_source, model_source, vegetation_catalog, vegetation_source, placement_source)
    prop_circles, scene_lines, scene_polygons = _scene_obstacles(scenery, prop_radii, max_prop_radius)
    tracks: list[dict[str, Any]] = []
    for group in scenery.get("groups", []):
        if group.get("type") != "track":
            continue
        points = _raw_points(group)
        width = _number(group.get("width", 0.0))
        for start, finish in zip(points, points[1:]):
            tracks.append({"id": str(group.get("id", "track")), "start": start, "finish": finish,
                           "half_width_m": width * 0.5})

    patches: list[dict[str, Any]] = []
    actual_cards: list[tuple[float, float]] = []
    card_clearance_radii: list[float] = []
    grass_points: list[tuple[float, float]] = []
    grass_radii: list[float] = []
    floor_centers: list[tuple[float, float]] = []
    path_segment_lengths: list[float] = []
    segment_yaw_bins: set[int] = set()
    all_path_seeds: list[int] = []
    species_counts = {source_id: 0 for source_id in SHRUB_SPECIES_COUNTS}
    for patch_template in patch_templates:
        patch = {
            "id": patch_template["id"],
            "paths_ne_m": patch_template["paths_ne_m"],
            # Kept as v2 source-fit provenance; the v3 runtime contract is grass_cards.
            "grass_ne_m": patch_template["grass_ne_m"],
            "grass_heights_m": patch_template["grass_heights_m"],
            "grass_cards": _groundcover_cards(
                patch_template, len(patches), patch_template["grass_ne_m"],
                patch_template["grass_heights_m"], grass_asset, grass_manifest,
            ),
            "floor_center_ne_m": patch_template["floor_center_ne_m"],
            "floor_half_size_m": float(patch_template["floor_half_size_m"]),
            "path_seeds": patch_template["path_seeds"],
            "shrub_species": patch_template["shrub_species"],
            "shrub_heights_m": patch_template["shrub_heights_m"],
            "shrub_height_m": float(patch_template["shrub_height_m"]),
            "shrub_width_m": SHRUB_WIDTH_M,
            "grass_height_m": GRASS_HEIGHT_M,
        }
        if (len(patch["paths_ne_m"]) != 12 or len(patch["path_seeds"]) != 12
                or len(patch["shrub_species"]) != 12 or len(patch["shrub_heights_m"]) != 12
                or len(patch["grass_ne_m"]) != 3 or len(patch["grass_heights_m"]) != 3
                or len(patch["grass_cards"]) != 3 + GROUNDCOVER_NEW_CARDS_PER_PATCH):
            raise ValueError(f"{patch['id']}: unexpected fixed patch shape")
        if float(patch["floor_half_size_m"]) != FLOOR_HALF_SIZE_M:
            raise ValueError(f"{patch['id']}: woodland floor size differs from its reviewed envelope")
        all_path_seeds.extend(int(seed) for seed in patch["path_seeds"])
        for path_index, path in enumerate(patch["paths_ne_m"]):
            source_id = str(patch["shrub_species"][path_index])
            if source_id not in species_counts:
                raise ValueError(f"{patch['id']}: unknown shrub source {source_id}")
            species_counts[source_id] += 1
            shrub_height = float(patch["shrub_heights_m"][path_index])
            if shrub_height <= 0.0 or shrub_height > patch["shrub_height_m"] + 1e-9:
                raise ValueError(f"{patch['id']}: shrub height exceeds its old patch ceiling")
            # Runtime caps each species card to the previous flower-card envelope
            # at this patch's old scalar height, including the hedge layout jitter.
            patch_card_radius = quad_radius_per_setting_m * patch["shrub_height_m"]
            if len(path) != 2:
                raise ValueError(f"{patch['id']}: every shrub is an independent two-endpoint segment")
            segment_length = math.dist(path[0], path[1])
            if segment_length < 1.5 or segment_length > 2.0:
                raise ValueError(f"{patch['id']}: every shrub segment must be 1.5–2.0 m")
            path_segment_lengths.append(segment_length)
            segment_card_count = math.floor(segment_length / float(hedge["card_spacing_m"]))
            if segment_card_count != 1:
                raise ValueError(f"{patch['id']}: each short segment must produce exactly one source card")
            segment_yaw_bins.add(int((math.atan2(path[1][1] - path[0][1],
                                                 path[1][0] - path[0][0]) % math.tau) / (math.pi / 6.0)))
            positions = _layout_card_positions(path, int(patch["path_seeds"][path_index]), SHRUB_WIDTH_M, hedge)
            if len(positions) != 1:
                raise ValueError(f"{patch['id']}: ImportedHedge layout must produce exactly one card per segment")
            actual_cards.extend(positions)
            card_clearance_radii.extend([patch_card_radius] * len(positions))
        card_ids: set[str] = set()
        card_seeds: set[int] = set()
        for card in patch["grass_cards"]:
            card_id = str(card["id"])
            seed = int(card["seed"])
            grass_height = float(card["height_m"])
            if (card_id in card_ids or seed in card_seeds or grass_height <= 0.0
                    or not 0.0 <= float(card["yaw_rad"]) < math.tau):
                raise ValueError(f"{patch['id']}: invalid or duplicate groundcover record")
            card_ids.add(card_id)
            card_seeds.add(seed)
            point = (float(card["north_m"]), float(card["east_m"]))
            grass_points.append(point)
            grass_radii.append(_grass_card_radius_per_height(grass_manifest) * grass_height)
        floor_centers.append((float(patch["floor_center_ne_m"][0]),
                              float(patch["floor_center_ne_m"][1])))
        patches.append(patch)

    layout_card_count = len(actual_cards)
    grass_count = len(grass_points)
    expected_species_counts = {
        source_id: count * len(patch_templates)
        for source_id, count in SHRUB_SPECIES_COUNTS.items()
    }
    expected_grass_count = (3 + GROUNDCOVER_NEW_CARDS_PER_PATCH) * len(patch_templates)
    if (layout_card_count != 48 or grass_count != expected_grass_count or len(floor_centers) != 4
            or len(set(all_path_seeds)) != 48 or species_counts != expected_species_counts):
        raise ValueError("woodland-edge population differs from the reviewed 48-shrub/172-grass contract")
    high_cap = int(hedge["high_instance_limit"])
    if layout_card_count > high_cap:
        raise ValueError("woodland-edge card count exceeds current ImportedHedge high-quality cap")
    floor_triangles = len(floor_centers) * FLOOR_TRIANGLES_PER_PATCH
    source_triangle_budget = (layout_card_count * card_triangles + grass_count * card_triangles
                             + floor_triangles)

    all_margins: dict[str, list[float]] = {}
    errors: list[str] = []
    checked_geometry_points = 0
    swept_samples = 0

    def check(point: tuple[float, float], envelope: float, context: str) -> None:
        nonlocal checked_geometry_points
        checked_geometry_points += 1
        failures, margins = _mask_check(
            point, envelope, field=field, scenery=scenery, lake_polygon=lake_polygon,
            tree_points=tree_points, tree_clearance_m=float(tree_contract["tree_clearance_used_m"]),
            runway_corridor_m=runway_corridor, tracks=tracks,
            prop_circles=prop_circles, prop_lines=scene_lines, prop_polygons=scene_polygons,
        )
        for key, value in margins.items():
            all_margins.setdefault(key, []).append(float(value))
        if failures:
            errors.extend(f"{context}: {failure}" for failure in failures)

    # Check each actual deterministic card placement with its per-path full-quad bound.
    for index, (point, card_radius) in enumerate(zip(actual_cards, card_clearance_radii)):
        shrub_envelope = card_radius + PLANT_CLEARANCE_M
        check(point, shrub_envelope, f"shrub card {index}")
    # Check every short-grass card using the complete square quad radius at its
    # requested source height, including 1 m plant clearance.
    for index, (point, radius) in enumerate(zip(grass_points, grass_radii)):
        check(point, radius + PLANT_CLEARANCE_M, f"grass card {index}")

    # Check path sweeps and the four complete floor rectangles against the existing
    # masks. A circle of half-diagonal plus 1 m at each floor center contains the full
    # 4 m square and its reviewed clearance.
    swept_envelopes: list[float] = []
    patch_radial_envelope_used: dict[str, float] = {}
    for patch in patches:
        center = (float(patch["floor_center_ne_m"][0]), float(patch["floor_center_ne_m"][1]))
        radial_used = 0.0
        for path_index, path in enumerate(patch["paths_ne_m"]):
            # Keep path sweeps at the old per-patch maximum even where the chosen
            # species/juvenile target height is shorter than that runtime cap.
            patch_radius = quad_radius_per_setting_m * float(patch["shrub_height_m"])
            swept_envelope = patch_radius + path_displacement_bound + PLANT_CLEARANCE_M
            swept_envelopes.append(swept_envelope)
            for point in _line_samples(path, PATH_SAMPLE_STEP_M):
                swept_samples += 1
                check(point, swept_envelope, f"{patch['id']} path {path_index} swept envelope")
                radial_used = max(radial_used, math.dist(point, center) + swept_envelope)

        center_radius = 0.0
        for card in patch["grass_cards"]:
            point = (float(card["north_m"]), float(card["east_m"]))
            radius = _grass_card_radius_per_height(grass_manifest) * float(card["height_m"])
            center_radius = math.dist(point, center)
            if (":groundcover:" in str(card["id"])
                    and center_radius > GROUNDCOVER_CENTER_RADIUS_LIMIT_M + 1e-6):
                errors.append(f"{patch['id']}: groundcover center exceeds its 5.2 m layout bound")
            radial_used = max(radial_used, math.dist(point, center) + radius + PLANT_CLEARANCE_M)

        half_diagonal = math.sqrt(2.0) * float(patch["floor_half_size_m"])
        floor_envelope = half_diagonal + PLANT_CLEARANCE_M
        check(center, floor_envelope, f"{patch['id']} floor rectangle")
        radial_used = max(radial_used, floor_envelope)
        limit = PATCH_RADIAL_ENVELOPE_LIMITS_M.get(str(patch["id"]))
        if limit is None:
            errors.append(f"{patch['id']}: no reviewed radial envelope is recorded")
        elif radial_used > limit + 1e-5:
            errors.append(
                f"{patch['id']}: candidate radial envelope {radial_used:.6f} m exceeds "
                f"the accepted {limit:.6f} m footprint"
            )
        patch_radial_envelope_used[str(patch["id"])] = round(radial_used, 6)

    if errors:
        raise ValueError("\n".join(errors[:30]))

    values = {key: round(min(items), 6) for key, items in all_margins.items() if items}
    minimum_tree_center_distance = min(
        _tree_nearest_distance(point, tree_points) for point in actual_cards + grass_points)
    nearest_neighbor_distances = [
        min(math.dist(point, other) for other_index, other in enumerate(actual_cards) if other_index != index)
        for index, point in enumerate(actual_cards)
    ]
    max_nearest_neighbor = max(nearest_neighbor_distances)
    grass_nearest_neighbor_distances = [
        min(math.dist(point, other) for other_index, other in enumerate(grass_points)
            if other_index != index)
        for index, point in enumerate(grass_points)
    ]
    groundcover_shrub_center_min_m = min(
        math.dist((float(card["north_m"]), float(card["east_m"])), shrub)
        for patch in patches for card in patch["grass_cards"]
        if str(card["id"]).split(":")[-2] == "groundcover"
        for shrub in actual_cards
    )
    source_paths = {
        "default_field": FIELD_PATH,
        "default_scenery": SCENERY_PATH,
        "default_lake": LAKE_PATH,
        "vegetation_catalog": VEGETATION_CATALOG_PATH,
        "tree_card_catalog": TREE_CATALOG_PATH,
        "shrub_impostor_manifest": HEDGE_MANIFEST_PATH,
        "grass_common_short_impostor_manifest": GRASS_SHORT_MANIFEST_PATH,
        "grass_common_tall_impostor_manifest": SHRUB_SPECIES_MANIFEST_PATHS["grass_common_tall"],
        "fern_1_impostor_manifest": SHRUB_SPECIES_MANIFEST_PATHS["fern_1"],
        "imported_hedge_builder": HEDGE_SOURCE_PATH,
        "vegetation_aliases": VEGETATION_SOURCE_PATH,
        "vegetation_placement": VEGETATION_PLACEMENT_PATH,
        "scenery_prefab_catalog": PREFABS_SOURCE_PATH,
        "scenery_model_catalog": MODELS_SOURCE_PATH,
        "field_loader_masks": FIELD_LOADER_PATH,
        "treeline_runtime": TREELINE_SOURCE_PATH,
        "tree_wind_shader": TREE_WIND_SOURCE_PATH,
        "existing_scenery_grass_masks": GRASS_MASK_SOURCE_PATH,
        "tree_placement_gaps": TREE_PLACEMENT_SOURCE_PATH,
        "palette_hash": PALETTE_SOURCE_PATH,
    }
    relative_hashes = {path.relative_to(ROOT).as_posix(): _source_hash(path)
                       for _key, path in sorted(source_paths.items())}
    return {
        "format": FORMAT,
        "scope": "default-field visual placements in absolute north/east metres; estimated layout, not surveyed geography",
        "field_id": "default",
        "pilot_origin_ne_m": [pilot_north, pilot_east],
        "patches": patches,
        "shrub_quality": SHRUB_QUALITY,
        "shrub_include_sparse_trees": INCLUDE_HEDGEROW_TREES,
        "source_triangle_budget": source_triangle_budget,
        "source_geometry": {
            "shrub_source_asset_id": hedge_source_id,
            "shrub_source_asset_role": "maximum_card_envelope_reference_only",
            "shrub_source_geometry_sha256": str(hedge_manifest["source_geometry_sha256"]),
            "shrub_card_asset_id": hedge_asset_id_match.group(1),
            "shrub_source_triangles": int(hedge_asset["source_triangles"]),
            "shrub_species_source_metadata": shrub_species_source_metadata,
            "shrub_card_triangles_per_instance": card_triangles,
            "shrub_card_instance_count": layout_card_count,
            "shrub_species_source_ids": list(SHRUB_SPECIES_COUNTS),
            "shrub_species_instances_per_patch": dict(SHRUB_SPECIES_COUNTS),
            "shrub_species_instance_counts": species_counts,
            "grass_source_asset_id": GRASS_ASSET_ID,
            "grass_source_geometry_sha256": str(grass_manifest["source_geometry_sha256"]),
            "grass_source_triangles": grass_triangles,
            "grass_card_asset_id": str(grass_manifest["asset_id"]),
            "grass_card_atlas_sha256": str(grass_manifest["atlas_sha256"]),
            "grass_card_triangles_per_instance": card_triangles,
            "grass_card_instance_count": grass_count,
            "grass_card_source_height_m": round(grass_source_height, 9),
            "grass_card_frame_world_size_m": [round(value, 9) for value in grass_frame_size],
            "grass_card_max_height_m": round(max(
                float(card["height_m"]) for patch in patches for card in patch["grass_cards"]
            ), 9),
            "grass_full_quad_horizontal_radius_m_at_max_height": round(
                _grass_card_radius_per_height(grass_manifest) * max(
                    float(card["height_m"]) for patch in patches for card in patch["grass_cards"]
                ), 9),
            "floor_patch_count": len(floor_centers),
            "floor_half_size_m": FLOOR_HALF_SIZE_M,
            "floor_grid_cells_per_side": 2,
            "floor_triangles_per_patch": FLOOR_TRIANGLES_PER_PATCH,
            "floor_triangle_count": floor_triangles,
            "computed_source_triangle_budget": source_triangle_budget,
            "shrub_max_height_m": round(shrub_max_height, 9),
            "shrub_full_quad_side_m_at_max_height": round(frame_world_size * shrub_max_scale, 9),
            "shrub_full_quad_horizontal_radius_m_at_max_height": round(shrub_full_quad_radius, 9),
            "shrub_full_quad_sphere_radius_m_at_max_height": round(shrub_full_quad_radius, 9),
            "tree_envelope": {key: round(value, 9) for key, value in tree_contract.items()},
            "layout_jitter_bound_m": round(path_displacement_bound, 9),
            "path_sweep_envelope_m_including_clearance": round(max(swept_envelopes), 9),
            "patch_radial_envelope_limits_m": dict(PATCH_RADIAL_ENVELOPE_LIMITS_M),
        },
        "validation": {
            "layout_cards_reproduced_from_imported_hedge_contract": layout_card_count,
            "independent_shrub_segment_count": len(path_segment_lengths),
            "segment_seed_count": len(set(all_path_seeds)),
            "shrub_species_instance_counts": species_counts,
            "grass_height_range_m": [round(min(
                float(card["height_m"]) for patch in patches for card in patch["grass_cards"]
            ), 6), round(max(
                float(card["height_m"]) for patch in patches for card in patch["grass_cards"]
            ), 6)],
            "grass_card_count": grass_count,
            "groundcover_card_count": sum(
                1 for patch in patches for card in patch["grass_cards"]
                if ":groundcover:" in str(card["id"])
            ),
            "groundcover_center_radius_max_m": round(max(
                math.dist((float(card["north_m"]), float(card["east_m"])),
                          (float(patch["floor_center_ne_m"][0]), float(patch["floor_center_ne_m"][1])))
                for patch in patches for card in patch["grass_cards"]
                if ":groundcover:" in str(card["id"])
            ), 6),
            "grass_card_nearest_neighbor_distance_min_m": round(min(grass_nearest_neighbor_distances), 6),
            "grass_card_nearest_neighbor_distance_max_m": round(max(grass_nearest_neighbor_distances), 6),
            "groundcover_to_shrub_nearest_center_m": round(groundcover_shrub_center_min_m, 6),
            "cards_per_short_segment_min": min(math.floor(length / float(hedge["card_spacing_m"]))
                                                 for length in path_segment_lengths),
            "cards_per_short_segment_max": max(math.floor(length / float(hedge["card_spacing_m"]))
                                                 for length in path_segment_lengths),
            "segment_length_min_m": round(min(path_segment_lengths), 6),
            "segment_length_max_m": round(max(path_segment_lengths), 6),
            "segment_yaw_30_degree_bin_count": len(segment_yaw_bins),
            "card_nearest_neighbor_distance_min_m": round(min(nearest_neighbor_distances), 6),
            "card_nearest_neighbor_distance_max_m": round(max_nearest_neighbor, 6),
            "plant_geometry_centers_checked": checked_geometry_points,
            "path_sweep_samples_at_0_25m": swept_samples,
            "floor_rectangles_checked": len(floor_centers),
            "patch_radial_envelope_used_m": patch_radial_envelope_used,
            "all_current_treeline_positions_checked": len(tree_points),
            "all_scenery_placement_envelopes_checked": len(prop_circles),
            "scenery_track_segments_checked": len(tracks),
            "scenery_hedge_fence_segments_checked": len(scene_lines) - len(tracks),
            "scenery_patch_polygons_checked": len(scene_polygons),
            "minimum_tree_center_distance_to_plant_centers_m": round(minimum_tree_center_distance, 6),
            "minimum_margins_m_or_degrees": values,
            "passed": True,
        },
        "source_sha256_normalized_text": relative_hashes,
    }


def _encode(document: dict[str, Any]) -> str:
    return json.dumps(document, indent=2, sort_keys=True) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT, help="generated woodland-edge JSON")
    parser.add_argument("--check", action="store_true", help="fail if the generated JSON differs from --out")
    args = parser.parse_args()
    document = build_document()
    encoded = _encode(document)
    if args.check:
        if not args.out.exists() or args.out.read_text(encoding="utf-8") != encoded:
            raise SystemExit(f"{args.out} differs from the deterministic woodland-edge recipe")
        print(f"Woodland-edge placements verified: {len(document['patches'])} patches, "
              f"{document['source_triangle_budget']} source triangles")
        return
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(encoded, encoding="utf-8", newline="\n")
    print(f"Woodland-edge placements written to {args.out}")


if __name__ == "__main__":
    main()
