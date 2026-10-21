"""Read-only, exact-world point-probe clearance analysis for an AFC-08 ORFL/CSV pair."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np


FORMAT = "afc08-recorded-scenery-clearance-v1"
ORACLE_TOLERANCE_M = 1e-10


def _point_box_signed_distance(point: tuple[float, float, float], box: dict[str, Any]) -> float:
    """Exact signed Euclidean distance from an NED point to the collision OBB surface."""
    dn = point[0] - float(box["north"])
    de = point[1] - float(box["east"])
    dd = point[2] - float(box["down"])
    sin_h = float(box["sin_heading"])
    cos_h = float(box["cos_heading"])
    local = (
        -dn * sin_h + de * cos_h,
        dd,
        -dn * cos_h - de * sin_h,
    )
    half = (float(box["half_x"]), float(box["half_down"]), float(box["half_z"]))
    excess = tuple(abs(local[i]) - half[i] for i in range(3))
    outside = math.sqrt(sum(max(value, 0.0) ** 2 for value in excess))
    if outside > 0.0:
        return outside
    return -min(half[i] - abs(local[i]) for i in range(3))


def _point_capsule_signed_distance(point: tuple[float, float, float], capsule: dict[str, Any]) -> float:
    """Exact signed distance to the down-axis capsule used by SceneryCollision."""
    dn = point[0] - float(capsule["north"])
    de = point[1] - float(capsule["east"])
    dd = point[2] - float(capsule["down"])
    axial_excess = max(abs(dd) - float(capsule["half_length"]), 0.0)
    return math.sqrt(dn * dn + de * de + axial_excess * axial_excess) - float(capsule["radius"])


def _fixture_checks() -> None:
    box = {
        "shape": "box", "north": 0.0, "east": 0.0, "down": 0.0,
        "sin_heading": 0.0, "cos_heading": 1.0,
        "half_x": 1.0, "half_down": 2.0, "half_z": 3.0,
    }
    assert math.isclose(_point_box_signed_distance((0.0, 2.0, 0.0), box), 1.0, abs_tol=1e-12)
    assert math.isclose(_point_box_signed_distance((0.0, 0.0, 0.0), box), -1.0, abs_tol=1e-12)
    assert math.isclose(_point_box_signed_distance((0.0, 1.0, 0.0), box), 0.0, abs_tol=1e-12)
    rotated_box = dict(box, sin_heading=1.0, cos_heading=0.0)
    assert math.isclose(_point_box_signed_distance((2.0, 0.0, 0.0), rotated_box), 1.0, abs_tol=1e-12)

    capsule = {"shape": "capsule", "north": 0.0, "east": 0.0, "down": 0.0,
               "radius": 1.0, "half_length": 2.0}
    assert math.isclose(_point_capsule_signed_distance((3.0, 0.0, 0.0), capsule), 2.0, abs_tol=1e-12)
    assert math.isclose(_point_capsule_signed_distance((0.0, 0.0, 0.0), capsule), -1.0, abs_tol=1e-12)
    assert math.isclose(_point_capsule_signed_distance((1.0, 0.0, 0.0), capsule), 0.0, abs_tol=1e-12)
    assert math.isclose(_point_capsule_signed_distance((0.0, 0.0, 4.0), capsule), 1.0, abs_tol=1e-12)

    broad_bounds = [-10.0, 10.0, -10.0, 10.0, -10.0, 10.0]
    fixture_proxies = _proxy_arrays([
        dict(box, id="box", bounds=broad_bounds),
        dict(rotated_box, id="rotated_box", bounds=broad_bounds),
        dict(capsule, id="capsule", bounds=broad_bounds),
    ])
    points = np.asarray([
        (0.0, 2.0, 0.0), (0.0, 0.0, 0.0), (0.0, 1.0, 0.0), (2.0, 0.0, 0.0),
        (3.0, 0.0, 0.0), (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 4.0),
    ], dtype=np.float64)
    matrix = _exact_distance_matrix(points, np.arange(3, dtype=np.int64), fixture_proxies)
    matrix_cases = [
        (0, 0, 1.0), (1, 0, -1.0), (2, 0, 0.0), (3, 1, 1.0),
        (4, 2, 2.0), (5, 2, -1.0), (6, 2, 0.0), (7, 2, 1.0),
    ]
    for point_index, proxy_index, expected in matrix_cases:
        assert math.isclose(float(matrix[point_index, proxy_index]), expected, abs_tol=1e-12)


def _read_csv(path: Path) -> tuple[list[str], list[dict[str, float]]]:
    rows: list[dict[str, float]] = []
    with path.open("r", newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames is None:
            raise ValueError("CSV has no header")
        required = {"tick", "t_s", "north_m", "east_m", "down_m", "qw", "qx", "qy", "qz",
                    "mass_kg", "cg_offset_x_m", "cg_offset_y_m", "cg_offset_z_m"}
        if not required.issubset(reader.fieldnames):
            raise ValueError(f"CSV is missing state columns: {sorted(required - set(reader.fieldnames))}")
        for row in reader:
            parsed = {name: float(row[name]) for name in required}
            if not all(math.isfinite(value) for value in parsed.values()):
                raise ValueError("CSV contains a nonfinite required state value")
            if parsed["tick"] != math.floor(parsed["tick"]):
                raise ValueError("CSV tick is not an integer-valued state index")
            rows.append(parsed)
    if not rows:
        raise ValueError("CSV has no state rows")
    ticks = [int(row["tick"]) for row in rows]
    if ticks != list(range(ticks[0], ticks[-1] + 1)):
        raise ValueError("CSV tick sequence is not contiguous")
    if ticks[0] != 0:
        raise ValueError("expected initial state row at tick 0")
    return list(reader.fieldnames or []), rows


def _rotate_body_to_ned(q: tuple[float, float, float, float], v: tuple[float, float, float]) -> tuple[float, float, float]:
    """Hamilton quaternion rotation, matching the loaded FlightSession state convention."""
    w, x, y, z = q
    vx, vy, vz = v
    tx = 2.0 * (y * vz - z * vy)
    ty = 2.0 * (z * vx - x * vz)
    tz = 2.0 * (x * vy - y * vx)
    return (
        vx + w * tx + (y * tz - z * ty),
        vy + w * ty + (z * tx - x * tz),
        vz + w * tz + (x * ty - y * tx),
    )


def _world_points(row: dict[str, float], body_points: np.ndarray) -> np.ndarray:
    q = (row["qw"], row["qx"], row["qy"], row["qz"])
    norm = math.sqrt(sum(value * value for value in q))
    if abs(norm - 1.0) > 1e-9:
        raise ValueError(f"tick {int(row['tick'])}: attitude quaternion is not normalized")
    origin = np.array([row["north_m"], row["east_m"], row["down_m"]], dtype=np.float64)
    rotated = np.array([_rotate_body_to_ned(q, tuple(float(v) for v in point)) for point in body_points], dtype=np.float64)
    return origin[None, :] + rotated


def _proxy_arrays(proxy_rows: list[dict[str, Any]]) -> dict[str, np.ndarray]:
    if not proxy_rows:
        raise ValueError("collision world has no proxies")
    ids = np.asarray([str(row["id"]) for row in proxy_rows], dtype=object)
    shapes = np.asarray([str(row["shape"]) for row in proxy_rows], dtype=object)
    if not set(shapes).issubset({"box", "capsule"}):
        raise ValueError("collision world contains an unsupported shape")
    bounds = np.asarray([row["bounds"] for row in proxy_rows], dtype=np.float64)
    centers = np.asarray([[row["north"], row["east"], row["down"]] for row in proxy_rows], dtype=np.float64)
    arrays: dict[str, np.ndarray] = {
        "ids": ids,
        "shapes": shapes,
        "bounds_min": bounds[:, [0, 2, 4]],
        "bounds_max": bounds[:, [1, 3, 5]],
        "centers": centers,
        "box_indices": np.flatnonzero(shapes == "box"),
        "capsule_indices": np.flatnonzero(shapes == "capsule"),
    }
    for name in ("sin_heading", "cos_heading", "half_x", "half_down", "half_z", "radius", "half_length"):
        arrays[name] = np.asarray([float(row.get(name, 0.0)) for row in proxy_rows], dtype=np.float64)
    for name in ("bounds_min", "bounds_max", "centers", "sin_heading", "cos_heading", "half_x",
                 "half_down", "half_z", "radius", "half_length"):
        if not np.all(np.isfinite(arrays[name])):
            raise ValueError(f"collision-world proxy field {name} contains a nonfinite value")
    return arrays


def _aabb_lower_bounds(points: np.ndarray, proxies: dict[str, np.ndarray]) -> np.ndarray:
    # A lower bound from every query point to every proxy AABB. All proxies are scanned; no bins are trusted.
    lower = np.maximum(proxies["bounds_min"][None, :, :] - points[:, None, :], 0.0)
    upper = np.maximum(points[:, None, :] - proxies["bounds_max"][None, :, :], 0.0)
    delta = np.maximum(lower, upper)
    return np.sqrt(np.sum(delta * delta, axis=2)).min(axis=0)


def _exact_distance_matrix(points: np.ndarray, indices: np.ndarray,
                           proxies: dict[str, np.ndarray]) -> np.ndarray:
    distances = np.full((len(points), len(indices)), np.inf, dtype=np.float64)
    if len(indices) == 0:
        return distances
    box_slots = np.flatnonzero(proxies["shapes"][indices] == "box")
    if len(box_slots):
        selected = indices[box_slots]
        delta = points[:, None, :] - proxies["centers"][selected][None, :, :]
        dn, de, dd = delta[:, :, 0], delta[:, :, 1], delta[:, :, 2]
        sin_h = proxies["sin_heading"][selected][None, :]
        cos_h = proxies["cos_heading"][selected][None, :]
        local_x = -dn * sin_h + de * cos_h
        local_down = dd
        local_z = -dn * cos_h - de * sin_h
        half = np.stack((proxies["half_x"][selected], proxies["half_down"][selected],
                         proxies["half_z"][selected]), axis=1)[None, :, :]
        local = np.stack((local_x, local_down, local_z), axis=2)
        abs_local = np.abs(local)
        excess = abs_local - half
        outside = np.sqrt(np.sum(np.maximum(excess, 0.0) ** 2, axis=2))
        inside = -np.min(half - abs_local, axis=2)
        distances[:, box_slots] = np.where(np.any(excess > 0.0, axis=2), outside, inside)
    capsule_slots = np.flatnonzero(proxies["shapes"][indices] == "capsule")
    if len(capsule_slots):
        selected = indices[capsule_slots]
        delta = points[:, None, :] - proxies["centers"][selected][None, :, :]
        axial = np.maximum(np.abs(delta[:, :, 2]) - proxies["half_length"][selected][None, :], 0.0)
        radial_sq = delta[:, :, 0] ** 2 + delta[:, :, 1] ** 2 + axial ** 2
        distances[:, capsule_slots] = np.sqrt(radial_sq) - proxies["radius"][selected][None, :]
    return distances


def _scalar_proxy_distance(point: tuple[float, float, float], proxy_index: int,
                           proxies: dict[str, np.ndarray]) -> float:
    center = proxies["centers"][proxy_index]
    shape = str(proxies["shapes"][proxy_index])
    if shape == "box":
        proxy = {
            "north": center[0], "east": center[1], "down": center[2],
            "sin_heading": proxies["sin_heading"][proxy_index],
            "cos_heading": proxies["cos_heading"][proxy_index],
            "half_x": proxies["half_x"][proxy_index],
            "half_down": proxies["half_down"][proxy_index],
            "half_z": proxies["half_z"][proxy_index],
        }
        return _point_box_signed_distance(point, proxy)
    proxy = {
        "north": center[0], "east": center[1], "down": center[2],
        "radius": proxies["radius"][proxy_index],
        "half_length": proxies["half_length"][proxy_index],
    }
    return _point_capsule_signed_distance(point, proxy)


def _oracle_min_scalar(points: np.ndarray, proxies: dict[str, np.ndarray]) -> tuple[float, int, int]:
    best_distance = math.inf
    best_point_index = -1
    best_proxy_index = -1
    for point_index, point_value in enumerate(points):
        point = tuple(float(value) for value in point_value)
        for proxy_index in range(len(proxies["ids"])):
            distance = _scalar_proxy_distance(point, proxy_index, proxies)
            if distance < best_distance:
                best_distance = distance
                best_point_index = point_index
                best_proxy_index = proxy_index
    return best_distance, best_point_index, best_proxy_index


def _point_group_summary(rows: list[dict[str, float]], point_group: str, body_points: np.ndarray,
                         proxies: dict[str, np.ndarray], oracle_ticks: set[int],
                         point_names: list[str]) -> dict[str, Any]:
    if len(point_names) != len(body_points):
        raise ValueError(f"{point_group}: point-name count does not match body geometry")
    best_distance = math.inf
    best_tick = -1
    best_time = math.nan
    best_point_index = -1
    best_proxy_index = -1
    exact_distance_evaluations = 0
    min_skipped_lower_bound = math.inf
    oracle_records: list[dict[str, Any]] = []
    for row_index, row in enumerate(rows):
        previous_best_distance = best_distance
        points = _world_points(row, body_points)
        lower = _aabb_lower_bounds(points, proxies)
        # Signed penetration can be negative. Every point inside a proxy has AABB lower bound zero,
        # so testing all bounds through max(best, 0) retains every possible new penetration.
        threshold = max(best_distance, 0.0)
        candidate_mask = lower <= threshold + 1e-12
        candidates = np.flatnonzero(candidate_mask)
        skipped = ~candidate_mask
        if np.any(skipped):
            min_skipped_lower_bound = min(min_skipped_lower_bound, float(np.min(lower[skipped])))
        matrix = _exact_distance_matrix(points, candidates, proxies)
        exact_distance_evaluations += int(matrix.size)
        if matrix.size:
            flat = int(np.argmin(matrix))
            point_index, candidate_slot = np.unravel_index(flat, matrix.shape)
            distance = float(matrix[point_index, candidate_slot])
            if distance < best_distance:
                best_distance = distance
                best_tick = int(row["tick"])
                best_time = float(row["t_s"])
                best_point_index = int(point_index)
                best_proxy_index = int(candidates[candidate_slot])
        tick = int(row["tick"])
        if tick in oracle_ticks:
            oracle_distance, oracle_point, oracle_proxy = _oracle_min_scalar(points, proxies)
            expected_running_best = min(previous_best_distance, oracle_distance)
            passed = abs(best_distance - expected_running_best) <= ORACLE_TOLERANCE_M
            oracle_records.append({
                "tick": tick,
                "previous_running_filtered_min_m": previous_best_distance if math.isfinite(previous_best_distance) else None,
                "oracle_scalar_full_world_row_min_m": oracle_distance,
                "expected_running_min_m": expected_running_best,
                "actual_running_filtered_min_m": best_distance,
                "oracle_point_index": oracle_point,
                "oracle_proxy_id": str(proxies["ids"][oracle_proxy]),
                "pass": passed,
            })
            if not passed:
                raise AssertionError(f"full-scan oracle found a closer value at tick {tick} for {point_group}")
        if row_index % 4096 == 0:
            print(f"{point_group}: scanned state row {row_index + 1}/{len(rows)}", flush=True)

    if best_proxy_index < 0:
        raise ValueError(f"no finite clearance found for {point_group}")
    return {
        "metric": "signed 3D Euclidean distance from discrete body-frame contact/probe points to proxy surfaces",
        "minimum_signed_clearance_m": best_distance,
        "tick": best_tick,
        "time_s": best_time,
        "point_index": best_point_index,
        "point_name": point_names[best_point_index],
        "proxy_id": str(proxies["ids"][best_proxy_index]),
        "proxy_shape": str(proxies["shapes"][best_proxy_index]),
        "all_world_proxy_aabbs_checked_per_state_row": True,
        "nearest_search_proof": "For every recorded row, all proxy AABBs were scanned. Exact distances were evaluated for every proxy whose AABB lower bound to any query point was <= the running best (or zero while best was negative); omitted proxies therefore cannot contain a closer outside point or any penetration. No spatial bins or local-radius assumption were used.",
        "minimum_skipped_proxy_aabb_lower_bound_m": min_skipped_lower_bound if math.isfinite(min_skipped_lower_bound) else None,
        "exact_proxy_distance_evaluations": exact_distance_evaluations,
        "full_scan_oracle": {
            "deterministic_tick_count": len(oracle_records),
            "oracle_tolerance_m": ORACLE_TOLERANCE_M,
            "all_pass": all(item["pass"] for item in oracle_records),
            "checks": oracle_records,
        },
    }


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def analyze(args: argparse.Namespace) -> dict[str, Any]:
    inputs_path = Path(args.inputs)
    csv_path = Path(args.csv)
    sortie_report_path = Path(args.sortie_report)
    replay_report_path = Path(args.replay_report)
    input_data = json.loads(inputs_path.read_text(encoding="utf-8"))
    sortie_report = json.loads(sortie_report_path.read_text(encoding="utf-8"))
    replay_report = json.loads(replay_report_path.read_text(encoding="utf-8"))
    if input_data.get("format") != "afc08-recorded-clearance-inputs-v1":
        raise ValueError("unsupported recorded geometry input format")
    if _sha256(Path(input_data["orfl_path"])) != input_data["orfl_sha256"]:
        raise ValueError("ORFL hash does not match exported header binding")
    if input_data["orfl_sha256"] != sortie_report.get("log_sha256"):
        raise ValueError("ORFL hash differs from the completed sortie report")
    if replay_report.get("complete") is not True or replay_report.get("error"):
        raise ValueError("exact replay is not complete and error-free")
    if replay_report.get("solver_changed") is not False:
        raise ValueError("exact replay did not preserve the solver identity")
    if replay_report.get("source_sha256") != input_data["orfl_sha256"]:
        raise ValueError("exact replay source hash differs from the exported ORFL")
    if replay_report.get("current_solver_sha256") != input_data["solver_sha256"] \
            or replay_report.get("baseline_solver_sha256") != input_data["solver_sha256"]:
        raise ValueError("exact replay solver hashes differ from the sortie solver identity")
    if int(replay_report.get("final_tick", -1)) != int(sortie_report.get("tick_count", -2)):
        raise ValueError("exact replay final tick differs from the sortie endpoint tick")
    world = input_data["collision_world"]
    if world.get("identity") != sortie_report.get("field_collision_sha256"):
        raise ValueError("collision-world identity differs from the sortie report")
    if int(world.get("proxy_count", -1)) != int(sortie_report.get("collision_proxy_count", -2)):
        raise ValueError("collision proxy count differs from the sortie report")
    initial_checkpoint = input_data.get("initial_checkpoint", {})
    damage_mask = initial_checkpoint.get("scenery_damage", {})
    if not isinstance(damage_mask, dict) or damage_mask:
        raise ValueError("nonempty or malformed initial scenery damage mask requires per-proxy activity reconstruction")
    if input_data.get("solver_sha256") != sortie_report.get("solver_sha256"):
        raise ValueError("solver identity differs from the sortie report")
    if sortie_report.get("contact_event_history") or sortie_report.get("terminal_damage"):
        raise ValueError("nonempty damage/contact history requires reconstructing its per-tick damage mask")
    if sortie_report.get("prop_strike"):
        raise ValueError("prop strike recorded; this report assumes the undamaged flight geometry")

    fields, rows = _read_csv(csv_path)
    if len(rows) != int(replay_report.get("rows", -1)):
        raise ValueError("CSV row count differs from the exact replay report")
    if int(rows[-1]["tick"]) != int(replay_report.get("final_tick", -2)):
        raise ValueError("CSV final tick differs from the exact replay report")

    aircraft = input_data["aircraft"]
    if aircraft.get("input_sha256") != sortie_report.get("aircraft_input_sha256"):
        raise ValueError("loaded aircraft input hash differs from the completed sortie report")
    hull_flat = np.asarray(aircraft["crash_hull_probe_points_body_frd"], dtype=np.float64)
    if hull_flat.size == 0 or hull_flat.size % 3:
        raise ValueError("loaded crash-hull probe geometry is malformed")
    hull_body = hull_flat.reshape((-1, 3))
    hull_names = list(aircraft.get("crash_hull_component_names", []))
    if len(hull_names) != len(hull_body):
        raise ValueError("loaded crash-hull component names do not match probe count")
    gear_rows = aircraft["landing_gear_contact_points"]
    gear_body = np.asarray([item["position_body_frd"] for item in gear_rows], dtype=np.float64)
    gear_names = [str(item["name"]) for item in gear_rows]
    max_abs_cg_offset = max(abs(row[name]) for row in rows for name in (
        "cg_offset_x_m", "cg_offset_y_m", "cg_offset_z_m"))
    if max_abs_cg_offset != 0.0:
        raise ValueError("nonzero recorded CG offset requires moving body probes with the recorded datum")
    mass_values = [row["mass_kg"] for row in rows]
    if min(mass_values) <= 0.0:
        raise ValueError("recorded mass must remain positive")
    proxies = _proxy_arrays(world["proxies"])
    if len(proxies["ids"]) != int(world["proxy_count"]):
        raise ValueError("exported world proxy array length mismatch")
    if len(set(proxies["ids"])) != len(proxies["ids"]):
        raise ValueError("collision world contains duplicate proxy IDs")

    _fixture_checks()
    oracle_ticks = {0, 1, 18028, 21323, 29173, int(rows[-1]["tick"])}
    oracle_ticks.update(range(2048, int(rows[-1]["tick"]), 2048))
    oracle_ticks = {tick for tick in oracle_ticks if 0 <= tick <= int(rows[-1]["tick"])}
    hull_summary = _point_group_summary(rows, "hull_probe", hull_body, proxies, oracle_ticks, hull_names)
    gear_summary = _point_group_summary(rows, "gear_contact_point", gear_body, proxies, oracle_ticks, gear_names)
    return {
        "format": FORMAT,
        "status": "ok",
        "case_id": "east-south-crosswind-s20261027",
        "inputs": {
            "orfl_path": input_data["orfl_path"], "orfl_sha256": input_data["orfl_sha256"],
            "csv_path": str(csv_path), "csv_sha256": _sha256(csv_path),
            "sortie_report_path": str(sortie_report_path), "sortie_report_sha256": _sha256(sortie_report_path),
            "exact_replay_report_path": str(replay_report_path), "exact_replay_report_sha256": _sha256(replay_report_path),
            "geometry_export_path": str(inputs_path), "geometry_export_sha256": _sha256(inputs_path),
            "solver_sha256": input_data["solver_sha256"],
            "aircraft_input_sha256": aircraft["input_sha256"],
            "collision_world_identity": world["identity"], "collision_proxy_count": len(proxies["ids"]),
            "collision_world_sha256_binding": "ORFL header collision_world.identity; proxy data exported directly from that packet",
            "exact_replay_source_sha256": replay_report["source_sha256"],
            "exact_replay_rows": int(replay_report["rows"]),
            "exact_replay_final_tick": int(replay_report["final_tick"]),
        },
        "scope": {
            "recorded_state_rows_including_initial_tick_zero": len(rows),
            "accepted_transitions": len(rows) - 1,
            "first_tick": int(rows[0]["tick"]), "last_tick": int(rows[-1]["tick"]),
            "csv_field_count": len(fields),
            "all_world_proxies_included": True,
            "damage_mask": "initial checkpoint scenery_damage is empty (omitted-as-empty is accepted); no contact history, terminal damage, or prop strike occurred in the completed sortie, so all proxies remain active",
            "body_geometry_frame": "Loaded ORFL crash-hull and landing-gear body-FRD points are rotated by each recorded quaternion without renormalization and translated by the recorded position. Every row has zero recorded CG offset, so the fixed body geometry remains aligned with the logged datum.",
            "recorded_mass_min_kg": min(mass_values),
            "recorded_mass_max_kg": max(mass_values),
            "max_abs_recorded_cg_offset_m": max_abs_cg_offset,
            "sortie_report_flight_log_rows_field": int(sortie_report.get("flight_log_rows", -1)),
            "exact_replay_csv_rows": int(replay_report["rows"]),
            "sortie_report_row_count_note": "The sortie report flight_log_rows value is retained as a pre-close buffered statistic; CSV row count is bound to the complete exact replay report.",
            "prop_disc_clearance_m": None,
            "prop_disc_limitation": "The existing exact prop-disc query is a field/terrain depth test. No exact disk-to-box/capsule scenery-distance method is available; no sampled-disk or circumradius approximation is reported.",
            "airframe_surface_clearance_m": None,
            "airframe_surface_limitation": "Crash hull is a discrete set of loaded probe points and gear geometry is a set of contact points. These results are point-to-proxy distances, not continuous outer-surface clearance.",
        },
        "hull_probe_points": hull_summary,
        "gear_contact_points": gear_summary,
        "fixtures": {
            "analytic_oriented_box_cases": ["outside", "inside", "on_surface", "rotated_outside"],
            "analytic_capsule_cases": ["outside_side", "inside", "on_surface", "outside_cap"],
            "status": "passed",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inputs", required=True)
    parser.add_argument("--csv", required=True)
    parser.add_argument("--sortie-report", required=True)
    parser.add_argument("--replay-report", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        _fixture_checks()
        if args.self_test:
            print("AFC08 clearance analytic fixtures: 8/8 passed")
            return 0
        result = analyze(args)
        Path(args.out).write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print("AFC08 read-only clearance analysis complete: %d proxies, %d state rows" % (
            result["inputs"]["collision_proxy_count"], result["scope"]["recorded_state_rows_including_initial_tick_zero"]))
        print("Hull-probe minimum: %.9f m at tick %d vs %s" % (
            result["hull_probe_points"]["minimum_signed_clearance_m"],
            result["hull_probe_points"]["tick"], result["hull_probe_points"]["proxy_id"]))
        print("Gear-point minimum: %.9f m at tick %d vs %s" % (
            result["gear_contact_points"]["minimum_signed_clearance_m"],
            result["gear_contact_points"]["tick"], result["gear_contact_points"]["proxy_id"]))
        return 0
    except Exception as exc:  # a failed analysis must not leave a plausible partial receipt
        print(f"AFC08 clearance analysis failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
