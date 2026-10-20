#!/usr/bin/env python3
"""Measure sampled-flight bounds against the run's static collision AABBs.

Each proxy AABB encloses its authored collision primitive. The distance from a
10 Hz path segment's axis-aligned envelope to a proxy AABB is therefore a
conservative lower bound for the piecewise-linear path reconstruction. This is
not an exact aircraft-envelope or 240 Hz swept-collision test.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any

import numpy as np


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def quantity(owner: dict[str, Any], key: str) -> float:
    return float(owner[key]["value"])


def read_tracks(path: Path) -> dict[str, dict[str, list[dict[str, float]]]]:
    tracks: dict[str, dict[str, list[dict[str, float]]]] = defaultdict(lambda: defaultdict(list))
    with path.open(newline="", encoding="utf-8") as source:
        for row in csv.DictReader(source):
            tracks[row["case"]][row["role"]].append({
                "time_s": float(row["time_s"]),
                "north_m": float(row["north_m"]),
                "east_m": float(row["east_m"]),
                "altitude_m": float(row["altitude_m"]),
                "agl_m": float(row["agl_m"]),
            })
    for roles in tracks.values():
        for rows in roles.values():
            rows.sort(key=lambda item: item["time_s"])
    return tracks


def segment_aabb_clearance(
    rows: list[dict[str, float]], proxies: list[dict[str, Any]], chunk_segments: int = 32,
) -> dict[str, Any]:
    if len(rows) < 2:
        raise ValueError("track requires at least two samples")
    points = np.asarray([
        [row["north_m"], row["east_m"], -row["altitude_m"]]
        for row in rows
    ], dtype=np.float64)
    proxy_min = np.asarray([
        [item["bounds_north_min"], item["bounds_east_min"], item["bounds_down_min"]]
        for item in proxies
    ], dtype=np.float64)
    proxy_max = np.asarray([
        [item["bounds_north_max"], item["bounds_east_max"], item["bounds_down_max"]]
        for item in proxies
    ], dtype=np.float64)
    segment_min = np.minimum(points[:-1], points[1:])
    segment_max = np.maximum(points[:-1], points[1:])
    best_squared = math.inf
    best_segment = -1
    best_proxy = -1
    for start in range(0, segment_min.shape[0], chunk_segments):
        stop = min(start + chunk_segments, segment_min.shape[0])
        low = np.maximum(
            np.maximum(proxy_min[None, :, :] - segment_max[start:stop, None, :],
                       segment_min[start:stop, None, :] - proxy_max[None, :, :]),
            0.0,
        )
        squared = np.einsum("ijk,ijk->ij", low, low, optimize=True)
        flat = int(np.argmin(squared))
        local_segment, proxy_index = np.unravel_index(flat, squared.shape)
        candidate = float(squared[local_segment, proxy_index])
        if candidate < best_squared:
            best_squared = candidate
            best_segment = start + int(local_segment)
            best_proxy = int(proxy_index)
    proxy = proxies[best_proxy]
    return {
        "segment_aabb_to_proxy_aabb_lower_bound_m": math.sqrt(best_squared),
        "closest_interval_start_s": rows[best_segment]["time_s"],
        "closest_interval_end_s": rows[best_segment + 1]["time_s"],
        "closest_proxy": {
            "id": proxy["id"],
            "kind": proxy["kind"],
            "part": proxy["part"],
            "response_class": proxy["response_class"],
            "shape": proxy["shape"],
        },
    }


def horizontal_distance_to_rect(n: float, e: float, n_min: float, n_max: float,
                                e_min: float, e_max: float) -> float:
    dn = max(n_min - n, 0.0, n - n_max)
    de = max(e_min - e, 0.0, e - e_max)
    return math.hypot(dn, de)


def min_track_distance_to_rect(rows: list[dict[str, float]], n_min: float, n_max: float,
                               e_min: float, e_max: float) -> float:
    result = math.inf
    for first, second in zip(rows, rows[1:]):
        track_n_min = min(first["north_m"], second["north_m"])
        track_n_max = max(first["north_m"], second["north_m"])
        track_e_min = min(first["east_m"], second["east_m"])
        track_e_max = max(first["east_m"], second["east_m"])
        dn = max(n_min - track_n_max, 0.0, track_n_min - n_max)
        de = max(e_min - track_e_max, 0.0, track_e_min - e_max)
        result = min(result, math.hypot(dn, de))
    return result


def measure(csv_path: Path, inventory_path: Path, field_path: Path) -> dict[str, Any]:
    inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    field = json.loads(field_path.read_text(encoding="utf-8"))
    proxies = inventory["proxies"]
    if not proxies:
        raise ValueError("collision inventory contains no proxies")
    tracks = read_tracks(csv_path)
    max_proxy_top = max(-float(proxy["bounds_down_min"]) for proxy in proxies)
    runway = next(surface for surface in field["surfaces"] if surface["id"] == field["runway"])
    runway_center_n = quantity(runway, "center_north")
    runway_center_e = quantity(runway, "center_east")
    runway_n_min = runway_center_n - quantity(runway, "width_north_south") * 0.5
    runway_n_max = runway_center_n + quantity(runway, "width_north_south") * 0.5
    runway_e_min = runway_center_e - quantity(runway, "length_east_west") * 0.5
    runway_e_max = runway_center_e + quantity(runway, "length_east_west") * 0.5
    pad = field.get("rotorcraft_pad", {})
    keepouts: list[dict[str, Any]] = []
    if isinstance(pad, dict):
        for item in pad.get("keepouts", []):
            center_n = quantity(item, "north")
            center_e = quantity(item, "east")
            half_n = quantity(item, "width_north_south") * 0.5
            half_e = quantity(item, "length_east_west") * 0.5
            keepouts.append({
                "id": item["id"],
                "north_bounds_m": [center_n - half_n, center_n + half_n],
                "east_bounds_m": [center_e - half_e, center_e + half_e],
            })
    person_proxies = [proxy for proxy in proxies if proxy["kind"] == "person"]
    shelter_proxies = [proxy for proxy in proxies if proxy["part"].startswith("shelter_")]
    if shelter_proxies:
        shelter_bounds = {
            "north_min": min(float(proxy["bounds_north_min"]) for proxy in shelter_proxies),
            "north_max": max(float(proxy["bounds_north_max"]) for proxy in shelter_proxies),
            "east_min": min(float(proxy["bounds_east_min"]) for proxy in shelter_proxies),
            "east_max": max(float(proxy["bounds_east_max"]) for proxy in shelter_proxies),
        }
    else:
        shelter_bounds = None
    surface_results: list[dict[str, Any]] = []
    for case, roles in sorted(tracks.items()):
        if "ai" not in roles:
            continue
        rows = roles["ai"]
        clearance = segment_aabb_clearance(rows, proxies)
        runway_horizontal = min(horizontal_distance_to_rect(
            row["north_m"], row["east_m"], runway_n_min, runway_n_max, runway_e_min, runway_e_max
        ) for row in rows)
        person_distances = []
        for proxy in person_proxies:
            person_distances.append((min_track_distance_to_rect(rows,
                float(proxy["bounds_north_min"]), float(proxy["bounds_north_max"]),
                float(proxy["bounds_east_min"]), float(proxy["bounds_east_max"])), proxy["id"]))
        closest_person = min(person_distances, default=(math.inf, ""))
        keepout_distances = []
        for keepout in keepouts:
            distance = min_track_distance_to_rect(rows,
                keepout["north_bounds_m"][0], keepout["north_bounds_m"][1],
                keepout["east_bounds_m"][0], keepout["east_bounds_m"][1])
            keepout_distances.append({"id": keepout["id"], "horizontal_clearance_m": distance})
        closest_keepout = min(keepout_distances,
                              key=lambda item: item["horizontal_clearance_m"], default=None)
        if shelter_bounds is not None:
            shelter_horizontal = min_track_distance_to_rect(rows,
                shelter_bounds["north_min"], shelter_bounds["north_max"],
                shelter_bounds["east_min"], shelter_bounds["east_max"])
        else:
            shelter_horizontal = math.inf
        pilot_n = quantity(field["pilot"], "north")
        pilot_e = quantity(field["pilot"], "east")
        pilot_horizontal = min_track_distance_to_rect(rows, pilot_n, pilot_n, pilot_e, pilot_e)
        n_values = [row["north_m"] for row in rows]
        e_values = [row["east_m"] for row in rows]
        a_values = [row["altitude_m"] for row in rows]
        agl_values = [row["agl_m"] for row in rows]
        surface_results.append({
            "case": case,
            "role": "ai",
            "sample_count": len(rows),
            "sample_interval_s": rows[1]["time_s"] - rows[0]["time_s"],
            "north_bounds_m": [min(n_values), max(n_values)],
            "east_bounds_m": [min(e_values), max(e_values)],
            "altitude_bounds_m": [min(a_values), max(a_values)],
            "agl_bounds_m": [min(agl_values), max(agl_values)],
            "minimum_segment_aabb_horizontal_clearance_to_runway_bounds_m": runway_horizontal,
            "minimum_segment_aabb_horizontal_clearance_to_any_person_proxy_m": closest_person[0],
            "nearest_person_proxy_id": closest_person[1],
            "minimum_segment_aabb_horizontal_clearance_to_shelter_footprint_m": shelter_horizontal,
            "minimum_segment_aabb_horizontal_clearance_to_pilot_reference_m": pilot_horizontal,
            "minimum_horizontal_clearance_to_rotorcraft_keepout_m": closest_keepout,
            "all_altitude_30m_exclusions": {
                "people_clearance_after_30m_buffer_m": closest_person[0] - 30.0,
                "shelter_clearance_after_30m_buffer_m": shelter_horizontal - 30.0,
                "pilot_reference_clearance_after_30m_buffer_m": pilot_horizontal - 30.0,
            },
            "static_collision_aabb_clearance": clearance,
            "vertical_clearance_to_tallest_proxy_m": min(a_values) - max_proxy_top,
        })
    surface_center = field["pilot"]
    pilot_station = next((cue for cue in field.get("flight_cues", [])
                          if cue.get("id") == "pilot_station"), None)
    return {
        "format": "afc-static-corridor-clearance-v1",
        "sampling_and_method": "10 Hz path segments; distance is the exact Euclidean gap between each segment's AABB and each proxy AABB, minimized over all segments/proxies. The proxy AABBs contain the collision primitives, so this is a lower bound for the piecewise-linear sampled path only.",
        "limitations": [
            "Does not reconstruct the 240 Hz curve between 10 Hz probe samples.",
            "Measures companion center to obstacle AABB; does not include the aircraft's physical envelope.",
            "AABB clearance can be smaller than true shape clearance for rotated or capsule proxies.",
            "Field geometry values are authored estimates; corridor distances are not real-world safety claims.",
        ],
        "source_files": {
            "trajectory_csv": {"path": str(csv_path.resolve()), "sha256": sha256(csv_path)},
            "collision_inventory": {"path": str(inventory_path.resolve()), "sha256": sha256(inventory_path)},
            "field_json": {"path": str(field_path.resolve()), "sha256": sha256(field_path)},
        },
        "collision_world_identity": inventory["identity"],
        "collision_proxy_count": len(proxies),
        "max_proxy_top_m": max_proxy_top,
        "runway_bounds_north_east_m": {
            "north": [runway_n_min, runway_n_max],
            "east": [runway_e_min, runway_e_max],
        },
        "pilot_station_geometry": {
            "collides": bool(pilot_station.get("collides", False)) if pilot_station else None,
            "pilot_position_north_east_m": [quantity(surface_center, "north"), quantity(surface_center, "east")],
        },
        "rotorcraft_keepouts": {
            "configured": "rotorcraft_pad" in field,
            "count": len(field.get("rotorcraft_pad", {}).get("keepouts", []))
            if isinstance(field.get("rotorcraft_pad"), dict) else 0,
            "definitions": keepouts,
        },
        "cases": surface_results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trajectory", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--field", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = measure(args.trajectory, args.inventory, args.field)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(args.out.resolve()),
        "collision_world_identity": result["collision_world_identity"],
        "cases": len(result["cases"]),
        "minimum_static_aabb_clearance_m": min(
            case["static_collision_aabb_clearance"]["segment_aabb_to_proxy_aabb_lower_bound_m"]
            for case in result["cases"]
        ),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
