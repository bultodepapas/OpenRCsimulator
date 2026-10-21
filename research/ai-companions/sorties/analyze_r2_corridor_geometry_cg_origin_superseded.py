#!/usr/bin/env python3
"""Read-only reconstruction of AFC-09 R2 taxi end-corridor margins."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


DEFAULT_CASES = (
    "east-north-crosswind-s20261025",
    "east-south-crosswind-s20261027",
    "west-south-crosswind-s20261051",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rotate(q: list[float], v: list[float]) -> list[float]:
    """Match app/physics/math3d.gd:q_rotate for [w,x,y,z] and body FRD vectors."""
    w, x, y, z = q
    tx = 2.0 * (y * v[2] - z * v[1])
    ty = 2.0 * (z * v[0] - x * v[2])
    tz = 2.0 * (x * v[1] - y * v[0])
    return [
        v[0] + w * tx + y * tz - z * ty,
        v[1] + w * ty + z * tx - x * tz,
        v[2] + w * tz + x * ty - y * tx,
    ]


def yaw_rad(row: dict[str, str]) -> float:
    w, x, y, z = (float(row[k]) for k in ("qw", "qx", "qy", "qz"))
    return math.atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))


def body_points(aircraft: dict) -> tuple[list[tuple[str, list[float]]], float, float]:
    inventory = aircraft["inventory"]
    mass = sum(float(item["mass"]["value"]) for item in inventory)
    cg = [
        sum(float(item["mass"]["value"]) * float(item["position"]["value"][axis]) for item in inventory)
        / mass
        for axis in range(3)
    ]

    def to_body(point: list[float]) -> list[float]:
        # Same LE-to-body-FRD transform as AircraftData._hull_body/_landing_gear.
        return [-(point[0] - cg[0]), point[1] - cg[1], -(point[2] - cg[2])]

    named = [
        (name, to_body(point))
        for name, point in zip(aircraft["crash_hull_components"], aircraft["crash_hull"]["value"])
    ]
    gear = [(item["name"], to_body(item["position"]["value"])) for item in aircraft["landing_gear"]["contacts"]]
    named.extend((f"gear:{name}", point) for name, point in gear)
    main_x = next(point[0] for name, point in gear if name == "main_left")
    nose_x = next(point[0] for name, point in gear if name == "nose")
    nose_steer_rad = math.radians(float(next(
        item["max_steering"]["value"]
        for item in aircraft["landing_gear"]["contacts"]
        if item["name"] == "nose"
    )))
    return named, abs(nose_x - main_x), nose_steer_rad


def corridor_margins(row: dict[str, str], points: list[tuple[str, list[float]]], limit: float) -> list[tuple[float, str, float]]:
    q = [float(row[k]) for k in ("qw", "qx", "qy", "qz")]
    east = float(row["east_m"])
    out = []
    for name, point in points:
        world = rotate(q, point)
        point_east = east + world[1]
        out.append((limit - abs(point_east), name, point_east))
    return out


def constant_arc_envelope(
    east0: float,
    psi0: float,
    points: list[tuple[str, list[float]]],
    wheelbase_m: float,
    steering_angle_rad: float,
    end_limit_east: float,
) -> tuple[float, str, float]:
    """Exact E-extrema for a no-slip, constant-steer arc from current yaw to north."""
    turn_sign = 1.0 if psi0 >= 0.0 else -1.0
    radius = wheelbase_m / math.tan(abs(steering_angle_rad))
    psi_lo, psi_hi = min(psi0, 0.0), max(psi0, 0.0)
    extrema: list[tuple[float, str, float]] = []
    for name, (x_body, y_body, _z_body) in points:
        candidates = [psi0, 0.0]
        root = math.atan2(x_body, turn_sign * radius + y_body)
        for k in range(-2, 3):
            psi = root + k * math.pi
            if psi_lo <= psi <= psi_hi:
                candidates.append(psi)
        for psi in candidates:
            center_east = east0 + turn_sign * radius * (math.cos(psi) - math.cos(psi0))
            point_east = center_east + x_body * math.sin(psi) + y_body * math.cos(psi)
            extrema.append((point_east, name, math.degrees(psi)))
    min_e = min(extrema, key=lambda item: item[0])
    max_e = max(extrema, key=lambda item: item[0])
    boundary = max((abs(min_e[0]), min_e), (abs(max_e[0]), max_e))
    return end_limit_east - boundary[0], boundary[1], radius


def world_horizontal_velocity(row: dict[str, str]) -> tuple[float, float]:
    q = [float(row[k]) for k in ("qw", "qx", "qy", "qz")]
    v = [float(row[k]) for k in ("u_mps", "v_mps", "w_mps")]
    n, e, _d = rotate(q, v)
    return n, e


def analyze_case(case_dir: Path, points: list[tuple[str, list[float]]], wheelbase: float,
                 nose_steer_rad: float, end_limit_east: float) -> dict:
    report = json.loads((case_dir / "candidate-report.json").read_text(encoding="utf-8"))
    replay = json.loads((case_dir / "exact" / "replay.json").read_text(encoding="utf-8"))
    with (case_dir / "exact" / "flight.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    start_tick = int(report["vacate_start"]["tick"])
    start = next(row for row in rows if int(row["tick"]) == start_tick)
    taxi = [row for row in rows if start_tick <= int(row["tick"]) <= int(report["tick_count"])]
    all_margins = [corridor_margins(row, points, end_limit_east) for row in taxi]
    first_breach_i = next((i for i, row_margins in enumerate(all_margins) if min(row_margins)[0] < 0.0), None)
    min_i = min(range(len(all_margins)), key=lambda i: min(all_margins[i])[0])
    breach_i = first_breach_i if first_breach_i is not None else min_i
    breach = taxi[breach_i]
    margin, point_name, point_east = min(all_margins[breach_i])
    start_margin, start_point, _ = min(corridor_margins(start, points, end_limit_east))
    min_margin = min(min(row_margins) for row_margins in all_margins)[0]
    report_margin = float(report["vacate_min_lateral_footprint_margin_m"])
    if abs(min_margin - report_margin) > 1e-9:
        raise ValueError(f"{case_dir.name}: recomputed margin {min_margin} differs from R2 {report_margin}")
    if not replay["complete"] or replay["solver_changed"]:
        raise ValueError(f"{case_dir.name}: exact replay is incomplete or changed solver")

    psi0 = yaw_rad(start)
    end_room_start = end_limit_east - abs(float(start["east_m"]))
    taxi_after_start = [row for row in taxi if int(row["tick"]) > start_tick]
    early_rows = [row for row in taxi_after_start if float(row["t_s"]) - float(report["vacate_start"]["time_s"]) <= 2.0]
    peak_servo = max(abs(float(row["srv_yaw"])) for row in early_rows)
    peak_row = max(early_rows, key=lambda row: abs(float(row["srv_yaw"])))
    actual_steer = peak_servo * nose_steer_rad
    observed_arc = constant_arc_envelope(float(start["east_m"]), psi0, points, wheelbase,
                                         actual_steer, end_limit_east)
    full_arc = constant_arc_envelope(float(start["east_m"]), psi0, points, wheelbase,
                                     nose_steer_rad, end_limit_east)
    world_n, world_e = world_horizontal_velocity(breach)
    gs = math.hypot(world_n, world_e)
    course = math.degrees(math.atan2(world_e, world_n))
    yaw_deg = math.degrees(yaw_rad(breach))
    elapsed = float(breach["t_s"]) - float(report["vacate_start"]["time_s"])
    peak_r_row = max(taxi_after_start[: breach_i], key=lambda row: abs(float(row["r_radps"])), default=breach)
    return {
        "case": case_dir.name,
        "report": report,
        "replay": replay,
        "start": start,
        "start_margin": start_margin,
        "start_point": start_point,
        "start_end_room": end_room_start,
        "first_breach": first_breach_i is not None,
        "breach_tick": int(breach["tick"]),
        "breach_elapsed_s": elapsed,
        "breach_margin": margin,
        "breach_point": point_name,
        "breach_point_east": point_east,
        "breach_cg_north": float(breach["north_m"]),
        "breach_cg_east": float(breach["east_m"]),
        "breach_yaw_deg": yaw_deg,
        "breach_yaw_rate": float(breach["r_radps"]),
        "breach_ground_speed": gs,
        "breach_course_deg": course,
        "breach_cmd_yaw": float(breach["cmd_yaw"]),
        "breach_srv_yaw": float(breach["srv_yaw"]),
        "breach_steer_deg": float(breach["srv_yaw"]) * math.degrees(nose_steer_rad),
        "breach_throttle": float(breach["cmd_throttle"]),
        "breach_rpm": float(breach["engine_rpm"]),
        "peak_servo": float(peak_row["srv_yaw"]),
        "peak_servo_tick": int(peak_row["tick"]),
        "peak_r_yaw_rate": float(peak_r_row["r_radps"]),
        "peak_r_tick": int(peak_r_row["tick"]),
        "reported_min_margin": report_margin,
        "min_tick": int(taxi[min_i]["tick"]),
        "observed_steer_arc_margin": observed_arc[0],
        "observed_steer_arc_radius": observed_arc[2],
        "observed_steer_arc_point": observed_arc[1][1],
        "full_steer_arc_margin": full_arc[0],
        "full_steer_arc_radius": full_arc[2],
        "full_steer_arc_point": full_arc[1][1],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-root", type=Path, required=True, help="AFC09-clearance-gate-R2 evidence directory")
    parser.add_argument("--aircraft-json", type=Path, required=True, help="exact aircraft input JSON used by R2")
    parser.add_argument("--driver-source", type=Path, required=True, help="R2 gate-only driver source")
    parser.add_argument("--case", action="append", help="case folder name; may be supplied more than once")
    args = parser.parse_args()

    aircraft = json.loads(args.aircraft_json.read_text(encoding="utf-8"))
    points, wheelbase, nose_steer_rad = body_points(aircraft)
    source_hashes = {
        "aircraft": sha256(args.aircraft_json),
        "driver": sha256(args.driver_source),
    }
    cases = args.case or list(DEFAULT_CASES)
    print(f"aircraft_sha256={source_hashes['aircraft']}")
    print(f"driver_sha256={source_hashes['driver']}")
    print(f"loaded_inventory_mass_kg={sum(i['mass']['value'] for i in aircraft['inventory']):.15g}")
    print(f"wheelbase_m={wheelbase:.12f}; nosewheel_max_steer_deg={math.degrees(nose_steer_rad):.6f}; footprint_points={len(points)}")
    for case in cases:
        item = analyze_case(args.evidence_root / "cases" / case, points, wheelbase, nose_steer_rad, 50.0)
        report = item["report"]
        if report["aircraft_input_sha256"] != source_hashes["aircraft"]:
            raise ValueError(f"{case}: aircraft source hash does not match R2 report")
        if report["driver_source_sha256"] != source_hashes["driver"]:
            raise ValueError(f"{case}: driver source hash does not match R2 report")
        if abs(float(report["vacate_start"]["runway_margin_m"]) - item["start_margin"]) > 1e-9:
            raise ValueError(f"{case}: reconstructed taxi-start footprint margin does not match R2 report")
        print(
            f"{case}: start tick={report['vacate_start']['tick']} E={item['start']['east_m']} "
            f"yaw={math.degrees(yaw_rad(item['start'])):.6f}deg footprint_margin={item['start_margin']:.9f}m "
            f"center_room={item['start_end_room']:.9f}m"
        )
        print(
            f"  first_breach_tick={item['breach_tick']} elapsed={item['breach_elapsed_s']:.6f}s "
            f"margin={item['breach_margin']:.12f}m point={item['breach_point']} E={item['breach_point_east']:.9f} "
            f"CG=(N{item['breach_cg_north']:.6f},E{item['breach_cg_east']:.6f}) yaw={item['breach_yaw_deg']:.3f}deg "
            f"Vg={item['breach_ground_speed']:.6f}m/s course={item['breach_course_deg']:.3f}deg "
            f"yaw_rate={item['breach_yaw_rate']:.6f}rad/s cmd/srv={item['breach_cmd_yaw']:.6f}/{item['breach_srv_yaw']:.6f} "
            f"implied_nose_steer={item['breach_steer_deg']:.3f}deg throttle={item['breach_throttle']:.6f} rpm={item['breach_rpm']:.3f}"
        )
        print(
            f"  early_peak_srv_yaw={item['peak_servo']:.6f} at_tick={item['peak_servo_tick']} "
            f"peak_body_yaw_rate={item['peak_r_yaw_rate']:.6f}rad/s at_tick={item['peak_r_tick']} "
            f"nominal_arc_margin_at_measured_steer={item['observed_steer_arc_margin']:.6f}m "
            f"(R={item['observed_steer_arc_radius']:.6f}m, point={item['observed_steer_arc_point']}); "
            f"full20deg_arc_margin={item['full_steer_arc_margin']:.6f}m "
            f"(R={item['full_steer_arc_radius']:.6f}m, point={item['full_steer_arc_point']})"
        )
        print(
            f"  replay_complete={item['replay']['complete']} solver_changed={item['replay']['solver_changed']} "
            f"R2_min={item['reported_min_margin']:.12f}m reconstructed_tick={item['min_tick']}"
        )


if __name__ == "__main__":
    main()
