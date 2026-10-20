#!/usr/bin/env python3
"""Measure sampled companion trajectory bounds and pilot-station box clearance."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Any


def quantity(owner: dict[str, Any], name: str) -> float:
    return float(owner[name]["value"])


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def measure(csv_path: Path, field_path: Path) -> dict[str, Any]:
    field = json.loads(field_path.read_text(encoding="utf-8"))
    pilot = field["pilot"]
    station = next(
        cue for cue in field.get("flight_cues", [])
        if cue.get("id") == "pilot_station"
    )
    center_north = quantity(pilot, "north")
    center_east = quantity(pilot, "east")
    center_altitude = -quantity(pilot, "down")
    half_depth = quantity(station, "depth") * 0.5
    half_width = quantity(station, "width") * 0.5
    station_top = center_altitude + quantity(station, "height")

    groups: dict[tuple[str, str], dict[str, Any]] = {}
    with csv_path.open(newline="", encoding="utf-8") as source:
        for row in csv.DictReader(source):
            key = (row["case"], row["role"])
            n = float(row["north_m"])
            e = float(row["east_m"])
            altitude = float(row["altitude_m"])
            agl = float(row["agl_m"])
            dn = max(abs(n - center_north) - half_depth, 0.0)
            de = max(abs(e - center_east) - half_width, 0.0)
            dz = max(center_altitude - altitude, altitude - station_top, 0.0)
            clearance = math.sqrt(dn * dn + de * de + dz * dz)
            horizontal = math.hypot(n - center_north, e - center_east)
            group = groups.setdefault(key, {
                "sample_count": 0,
                "time_min_s": math.inf,
                "time_max_s": -math.inf,
                "north_min_m": math.inf,
                "north_max_m": -math.inf,
                "east_min_m": math.inf,
                "east_max_m": -math.inf,
                "altitude_min_m": math.inf,
                "altitude_max_m": -math.inf,
                "agl_min_m": math.inf,
                "agl_max_m": -math.inf,
                "pilot_station_box_clearance_min_m": math.inf,
                "pilot_center_horizontal_distance_min_m": math.inf,
            })
            group["sample_count"] += 1
            group["time_min_s"] = min(group["time_min_s"], float(row["time_s"]))
            group["time_max_s"] = max(group["time_max_s"], float(row["time_s"]))
            group["north_min_m"] = min(group["north_min_m"], n)
            group["north_max_m"] = max(group["north_max_m"], n)
            group["east_min_m"] = min(group["east_min_m"], e)
            group["east_max_m"] = max(group["east_max_m"], e)
            group["altitude_min_m"] = min(group["altitude_min_m"], altitude)
            group["altitude_max_m"] = max(group["altitude_max_m"], altitude)
            group["agl_min_m"] = min(group["agl_min_m"], agl)
            group["agl_max_m"] = max(group["agl_max_m"], agl)
            group["pilot_station_box_clearance_min_m"] = min(
                group["pilot_station_box_clearance_min_m"], clearance
            )
            group["pilot_center_horizontal_distance_min_m"] = min(
                group["pilot_center_horizontal_distance_min_m"], horizontal
            )

    if not groups:
        raise ValueError("trajectory CSV contains no samples")
    return {
        "format": "afc-trajectory-measurement-v1",
        "trajectory_csv": str(csv_path.resolve()),
        "trajectory_csv_sha256": sha256(csv_path),
        "field_json": str(field_path.resolve()),
        "field_json_sha256": sha256(field_path),
        "sampling": "probe trajectory points at 10 Hz; minima are sampled, not swept",
        "pilot_station_geometry": {
            "center_north_m": center_north,
            "center_east_m": center_east,
            "base_altitude_m": center_altitude,
            "north_south_depth_m": half_depth * 2.0,
            "east_west_width_m": half_width * 2.0,
            "height_m": station_top - center_altitude,
            "authored_collides": bool(station.get("collides", False)),
            "clearance_definition": "3D distance from sample point to the authored pilot-station axis-aligned box",
        },
        "cases": [
            {"case": case, "role": role, **values}
            for (case, role), values in sorted(groups.items())
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("trajectory_csv", type=Path)
    parser.add_argument("--field", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if not args.trajectory_csv.is_file() or not args.field.is_file():
        parser.error("trajectory CSV and field JSON must exist")
    if args.out.exists():
        parser.error("output path must be new")
    result = measure(args.trajectory_csv, args.field)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"out": str(args.out.resolve()), "case_roles": len(result["cases"]),
                      "trajectory_sha256": result["trajectory_csv_sha256"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
