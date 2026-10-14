#!/usr/bin/env python3
"""Analyze a ground-vehicle experiment recording with independent checks.

Uses only the Python standard library. It never imports or mirrors the GDScript
kernel; source identities bind the recording to the exact vehicle/course inputs.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VEHICLE = ROOT / "app/data/vehicles/ground/mt8_bisonte.json"
DEFAULT_COURSE = ROOT / "app/data/ground_vehicle/practice.json"
ANALYSIS_FORMAT = "openrc-ground-vehicle-analysis"
ANALYSIS_VERSION = 1
STATE_LAYOUT = (
    "north_m", "east_m", "down_m", "u_m_per_s", "v_m_per_s", "w_m_per_s",
    "qw", "qx", "qy", "qz", "p_rad_per_s", "q_rad_per_s", "r_rad_per_s",
    "travel_fl_m", "travel_fr_m", "travel_rl_m", "travel_rr_m",
    "travel_rate_fl_m_per_s", "travel_rate_fr_m_per_s", "travel_rate_rl_m_per_s", "travel_rate_rr_m_per_s",
    "wheel_spin_fl_rad_per_s", "wheel_spin_fr_rad_per_s", "wheel_spin_rl_rad_per_s", "wheel_spin_rr_rad_per_s",
    "wheel_angle_fl_rad", "wheel_angle_fr_rad", "wheel_angle_rl_rad", "wheel_angle_rr_rad",
    "steering_right_rad", "steering_rate_right_rad_per_s",
)
ROW_REQUIRED = {
    "run_id", "scenario", "surface_id", "sample_index", "time_s",
    *STATE_LAYOUT,
    "roll_euler_rad", "body_p_rad_per_s",
    "speed_m_per_s", "forward_speed_m_per_s", "airborne",
    "road_height_m", "road_mu", "road_surface_id", "total_energy_j",
    "wheel_load_fl_n", "wheel_load_fr_n", "wheel_load_rl_n", "wheel_load_rr_n",
    "wheel_longitudinal_force_fl_n", "wheel_longitudinal_force_fr_n", "wheel_longitudinal_force_rl_n", "wheel_longitudinal_force_rr_n",
    "wheel_slip_ratio_fl", "wheel_slip_ratio_fr", "wheel_slip_ratio_rl", "wheel_slip_ratio_rr",
    "telemetry_travel_fl_m", "telemetry_travel_fr_m", "telemetry_travel_rl_m", "telemetry_travel_rr_m",
    "wheel_contact_fl", "wheel_contact_fr", "wheel_contact_rl", "wheel_contact_rr",
    "hull_contact_count",
}
WHEEL_SUFFIXES = ("fl", "fr", "rl", "rr")
BOOLEAN_COLUMNS = {
    "airborne",
    *(f"wheel_contact_{corner}" for corner in WHEEL_SUFFIXES),
}


class AnalysisError(ValueError):
    """The recording cannot support a trustworthy analysis."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path, description: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AnalysisError(f"cannot read {description} {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise AnalysisError(f"{description} must contain a JSON object")
    return value


def q_value(mapping: dict[str, Any], key: str) -> float:
    quantity = mapping.get(key)
    if not isinstance(quantity, dict) or quantity.get("unit") is None:
        raise AnalysisError(f"missing physical quantity {key}")
    value = quantity.get("value")
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise AnalysisError(f"quantity {key} is not finite numeric data")
    return float(value)


def load_and_check_identity(path: Path, identity: Any, label: str) -> dict[str, Any]:
    data = read_json(path, label)
    if not isinstance(identity, dict):
        raise AnalysisError(f"metadata has no {label} identity")
    expected_hash = identity.get("sha256")
    actual_hash = sha256_bytes(path.read_bytes())
    if not isinstance(expected_hash, str) or expected_hash != actual_hash:
        raise AnalysisError(f"{label} SHA-256 does not match the recording metadata")
    if str(data.get("id", "")) != str(identity.get("id", "")):
        raise AnalysisError(f"{label} ID does not match the recording metadata")
    if int(data.get("version", -1)) != int(identity.get("version", -2)):
        raise AnalysisError(f"{label} version does not match the recording metadata")
    return data


def _finite_number(row: dict[str, str], key: str, line_number: int) -> float:
    try:
        value = float(row[key])
    except (KeyError, TypeError, ValueError) as exc:
        raise AnalysisError(f"CSV line {line_number}: {key} is not numeric") from exc
    if not math.isfinite(value):
        raise AnalysisError(f"CSV line {line_number}: {key} is non-finite")
    return value


def read_recording(csv_path: Path, metadata_path: Path) -> tuple[dict[str, Any], list[dict[str, str]]]:
    metadata = read_json(metadata_path, "run metadata")
    if metadata.get("format") != "openrc-ground-vehicle-experiment" or metadata.get("version") != 1:
        raise AnalysisError("unsupported run metadata format/version")
    if metadata.get("complete") is not True or metadata.get("status") != "complete":
        raise AnalysisError("run metadata does not mark both exports complete")
    solver_version = metadata.get("solver_version")
    if not isinstance(solver_version, str) or not solver_version.strip():
        raise AnalysisError("recording metadata has no solver version")
    if metadata.get("scenario") not in ("braking", "bump", "drop", "rollover"):
        raise AnalysisError("run metadata has an unsupported scenario")
    substeps = metadata.get("substeps_per_tick")
    if metadata.get("public_hz") != 240 or isinstance(substeps, bool) or not isinstance(substeps, int) or substeps < 1:
        raise AnalysisError("recording rate/substep contract does not match the runner")
    csv_bytes = csv_path.read_bytes()
    expected_hash = metadata.get("csv_sha256")
    if not isinstance(expected_hash, str) or sha256_bytes(csv_bytes) != expected_hash:
        raise AnalysisError("CSV SHA-256 does not match the completed metadata")
    if metadata.get("sample_count") != metadata.get("finite_sample_count"):
        raise AnalysisError("metadata finite sample count is incomplete")
    model_parameters = metadata.get("model_parameters")
    if not isinstance(model_parameters, dict):
        raise AnalysisError("recording metadata has no model parameter summary")
    probe_count = model_parameters.get("hull_probe_count")
    if isinstance(probe_count, bool) or not isinstance(probe_count, int) or not 1 <= probe_count <= 32:
        raise AnalysisError("recording metadata has an invalid hull probe count")
    required_columns = ROW_REQUIRED | {f"hull_contact_{index:02d}" for index in range(probe_count)}
    try:
        with csv_path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames is None or not required_columns.issubset(reader.fieldnames):
                missing = sorted(required_columns - set(reader.fieldnames or []))
                raise AnalysisError(f"CSV header is missing required columns: {missing}")
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        raise AnalysisError(f"cannot read CSV {csv_path}: {exc}") from exc
    if len(rows) != metadata.get("sample_count") or not rows:
        raise AnalysisError("CSV row count does not match complete metadata")
    hz = int(metadata["public_hz"])
    scenario = str(metadata["scenario"])
    by_run: dict[str, list[dict[str, str]]] = {}
    for line_number, row in enumerate(rows, start=2):
        if None in row or any(value is None for value in row.values()):
            raise AnalysisError(f"CSV line {line_number} has a malformed column count")
        if row["scenario"] != scenario:
            raise AnalysisError(f"CSV line {line_number} scenario differs from metadata")
        for key in BOOLEAN_COLUMNS | {f"hull_contact_{index:02d}" for index in range(probe_count)}:
            if row[key] not in ("true", "false"):
                raise AnalysisError(f"CSV line {line_number} has invalid {key} flag")
        for key in required_columns - {"run_id", "scenario", "surface_id", "sample_index", "road_surface_id"} - BOOLEAN_COLUMNS - {f"hull_contact_{index:02d}" for index in range(probe_count)}:
            _finite_number(row, key, line_number)
        recorded_hull_count = _finite_number(row, "hull_contact_count", line_number)
        hull_count = int(recorded_hull_count)
        observed_hull_count = sum(
            row[f"hull_contact_{index:02d}"] == "true" for index in range(probe_count)
        )
        if recorded_hull_count != hull_count or hull_count != observed_hull_count:
            raise AnalysisError(f"CSV line {line_number} hull contact count disagrees with probe flags")
        if not row["run_id"] or not row["surface_id"]:
            raise AnalysisError(f"CSV line {line_number} has empty run or surface ID")
        by_run.setdefault(row["run_id"], []).append(row)
    runs = metadata.get("runs")
    if not isinstance(runs, list) or not runs:
        raise AnalysisError("run metadata has no run descriptors")
    expected_ids = [str(run.get("run_id", "")) for run in runs if isinstance(run, dict)]
    if len(expected_ids) != len(runs) or len(set(expected_ids)) != len(expected_ids) or set(by_run) != set(expected_ids):
        raise AnalysisError("CSV run IDs do not match run metadata")
    expected_count = int(metadata.get("expected_samples_per_run", 0))
    if expected_count <= 0 or int(metadata.get("ticks_per_run", -1)) + 1 != expected_count:
        raise AnalysisError("metadata has an invalid expected sample count")
    for run_meta in runs:
        run_id = str(run_meta["run_id"])
        run_rows = by_run[run_id]
        if len(run_rows) != expected_count or int(run_meta.get("sample_count", -1)) != expected_count:
            raise AnalysisError(f"run {run_id} has an incomplete sample count")
        if int(run_meta.get("finite_sample_count", -1)) != expected_count:
            raise AnalysisError(f"run {run_id} finite sample count is incomplete")
        for index, row in enumerate(run_rows):
            if int(row["sample_index"]) != index:
                raise AnalysisError(f"run {run_id} sample indices are not contiguous")
            time_s = float(row["time_s"])
            if abs(time_s - index / hz) > 1.0e-9:
                raise AnalysisError(f"run {run_id} time does not match fixed tick {index}")
            if row["surface_id"] != str(run_meta.get("surface_id", "")):
                raise AnalysisError(f"run {run_id} surface differs from metadata")
    return metadata, rows


def q_rotate(q: tuple[float, float, float, float], v: tuple[float, float, float]) -> tuple[float, float, float]:
    """Rotate a body vector into NED using scalar quaternion arithmetic."""
    w, x, y, z = q
    vx, vy, vz = v
    # v + 2*w*(q_vec x v) + 2*(q_vec x (q_vec x v))
    tx = 2.0 * (y * vz - z * vy)
    ty = 2.0 * (z * vx - x * vz)
    tz = 2.0 * (x * vy - y * vx)
    return (
        vx + w * tx + (y * tz - z * ty),
        vy + w * ty + (z * tx - x * tz),
        vz + w * tz + (x * ty - y * tx),
    )


def world_velocity(row: dict[str, str]) -> tuple[float, float, float]:
    q = tuple(_finite_number(row, name, -1) for name in ("qw", "qx", "qy", "qz"))
    norm = math.sqrt(sum(component * component for component in q))
    if norm <= 0.0:
        raise AnalysisError("recording contains a zero attitude quaternion")
    qn = tuple(component / norm for component in q)
    body = tuple(_finite_number(row, name, -1) for name in ("u_m_per_s", "v_m_per_s", "w_m_per_s"))
    return q_rotate(qn, body)


def _vehicle_system_com_ned(
    row: dict[str, str], vehicle: dict[str, Any]
) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    """Return total sprung+hub COM position and velocity in NED.

    During free flight, suspension springs can accelerate the sprung chassis
    relative to the wheel hubs. The total vehicle COM still follows a ballistic
    path because internal forces cancel. This independent scalar reconstruction
    uses the published finite-length arm geometry and state travel values.
    """
    parameters = vehicle.get("parameters")
    if not isinstance(parameters, dict):
        raise AnalysisError("vehicle profile has no parameter object")

    def scalar(key: str, unit: str) -> float:
        return q_value_by_unit(parameters, key, unit)

    def vector(key: str, unit: str, length: int) -> tuple[float, ...]:
        quantity = parameters.get(key)
        if not isinstance(quantity, dict) or quantity.get("unit") != unit:
            raise AnalysisError(f"{key} has unexpected unit")
        value = quantity.get("value")
        if not isinstance(value, list) or len(value) != length:
            raise AnalysisError(f"{key} must contain {length} numeric values")
        result: list[float] = []
        for item in value:
            if isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(float(item)):
                raise AnalysisError(f"{key} contains a non-finite or non-numeric value")
            result.append(float(item))
        return tuple(result)

    sprung_mass = scalar("sprung_mass_kg", "kg")
    unsprung_mass = scalar("unsprung_mass_kg", "kg")
    total_mass = sprung_mass + 4.0 * unsprung_mass
    if total_mass <= 0.0:
        raise AnalysisError("vehicle total mass must be positive")
    corner_x = vector("corner_x_datum_frd_m", "m", 4)
    corner_y = vector("corner_y_datum_frd_m", "m", 4)
    arm_length = scalar("arm_length_m", "m")
    cg_forward = scalar("cg_forward_from_datum_m", "m")
    cg_right = scalar("cg_right_from_datum_m", "m")
    cg_height = scalar("cg_height_above_chassis_datum_m", "m")
    wheel_rest_below = scalar("wheel_center_rest_below_chassis_datum_m", "m")
    if arm_length <= 0.0:
        raise AnalysisError("vehicle arm length must be positive")

    q = tuple(_finite_number(row, name, -1) for name in ("qw", "qx", "qy", "qz"))
    q_norm = math.sqrt(sum(component * component for component in q))
    if q_norm <= 0.0:
        raise AnalysisError("recording contains a zero attitude quaternion")
    q = tuple(component / q_norm for component in q)
    position = tuple(_finite_number(row, name, -1) for name in ("north_m", "east_m", "down_m"))
    body_velocity = tuple(_finite_number(row, name, -1) for name in ("u_m_per_s", "v_m_per_s", "w_m_per_s"))
    body_rate = tuple(_finite_number(row, name, -1) for name in ("p_rad_per_s", "q_rad_per_s", "r_rad_per_s"))
    total_position = [sprung_mass * component for component in position]
    total_velocity = [sprung_mass * component for component in q_rotate(q, body_velocity)]

    for index, corner in enumerate(WHEEL_SUFFIXES):
        travel = _finite_number(row, f"travel_{corner}_m", -1)
        travel_rate = _finite_number(row, f"travel_rate_{corner}_m_per_s", -1)
        arm_radial_sq = arm_length * arm_length - travel * travel
        if arm_radial_sq <= 0.0:
            raise AnalysisError("recorded suspension travel reaches the arm singularity")
        arm_radial = math.sqrt(arm_radial_sq)
        side = -1.0 if index in (0, 2) else 1.0
        hub_from_cg = (
            corner_x[index] - cg_forward,
            corner_y[index] - cg_right + side * (arm_radial - arm_length),
            cg_height + wheel_rest_below - travel,
        )
        hub_offset_rate = (0.0, -side * travel / arm_radial, -1.0)
        omega_cross_hub = (
            body_rate[1] * hub_from_cg[2] - body_rate[2] * hub_from_cg[1],
            body_rate[2] * hub_from_cg[0] - body_rate[0] * hub_from_cg[2],
            body_rate[0] * hub_from_cg[1] - body_rate[1] * hub_from_cg[0],
        )
        hub_velocity_body = tuple(
            body_velocity[axis] + omega_cross_hub[axis] + hub_offset_rate[axis] * travel_rate
            for axis in range(3)
        )
        hub_offset_world = q_rotate(q, hub_from_cg)
        hub_velocity_world = q_rotate(q, hub_velocity_body)
        for axis in range(3):
            total_position[axis] += unsprung_mass * (position[axis] + hub_offset_world[axis])
            total_velocity[axis] += unsprung_mass * hub_velocity_world[axis]
    return (
        tuple(component / total_mass for component in total_position),
        tuple(component / total_mass for component in total_velocity),
    )


def q_value_by_unit(mapping: dict[str, Any], key: str, unit: str) -> float:
    value = q_value(mapping, key)
    if mapping[key].get("unit") != unit:
        raise AnalysisError(f"{key} has unexpected unit")
    return value


def _smooth01(value: float) -> float:
    clipped = min(1.0, max(0.0, value))
    return clipped * clipped * (3.0 - 2.0 * clipped)


def _lateral_factor(feature: dict[str, Any], east_m: float) -> float:
    delta = east_m - q_value_by_unit(feature, "center_east_m", "m")
    distance = abs(delta)
    half_width = 0.5 * q_value_by_unit(feature, "width_m", "m")
    shoulder = q_value_by_unit(feature, "shoulder_width_m", "m")
    if distance <= half_width:
        return 1.0
    if shoulder <= 0.0 or distance >= half_width + shoulder:
        return 0.0
    return _smooth01((half_width + shoulder - distance) / shoulder)


def analytical_course_height(course: dict[str, Any], north_m: float, east_m: float) -> float:
    """Independent scalar reconstruction of the course's published height law."""
    total = 0.0
    for feature in course.get("features", []):
        if not isinstance(feature, dict):
            continue
        lateral = _lateral_factor(feature, east_m)
        if lateral <= 0.0:
            continue
        center = q_value_by_unit(feature, "center_north_m", "m")
        height = q_value_by_unit(feature, "height_m", "m")
        feature_type = feature.get("type")
        contribution = 0.0
        if feature_type in ("tabletop", "slope"):
            rise = q_value_by_unit(feature, "approach_length_m", "m")
            top = q_value_by_unit(feature, "top_length_m", "m")
            fall = q_value_by_unit(feature, "departure_length_m", "m")
            start = center - 0.5 * (rise + top + fall)
            if start <= north_m < start + rise:
                contribution = height * _smooth01((north_m - start) / rise)
            elif start + rise <= north_m <= start + rise + top:
                contribution = height
            elif start + rise + top < north_m <= start + rise + top + fall:
                t = (north_m - start - rise - top) / fall
                contribution = height * (1.0 - _smooth01(t))
        elif feature_type == "wedge":
            length = q_value_by_unit(feature, "length_m", "m")
            start = center - 0.5 * length
            t = (north_m - start) / length
            if 0.0 < t < 1.0:
                contribution = height * math.sin(math.pi * t) ** 2
        elif feature_type == "bump_lane":
            length = q_value_by_unit(feature, "bump_length_m", "m")
            spacing = q_value_by_unit(feature, "bump_spacing_m", "m")
            count = int(feature["bump_count"])
            for bump_index in range(count):
                bump_center = center + (bump_index - 0.5 * (count - 1)) * spacing
                t = (north_m - (bump_center - 0.5 * length)) / length
                if 0.0 < t < 1.0:
                    contribution += height * math.sin(math.pi * t) ** 2
        total += contribution * lateral
    return total


def _distance(samples: list[dict[str, str]]) -> float:
    distance = 0.0
    for first, second in zip(samples, samples[1:]):
        dn = float(second["north_m"]) - float(first["north_m"])
        de = float(second["east_m"]) - float(first["east_m"])
        distance += math.hypot(dn, de)
    return distance


def _braking_analysis(
    metadata: dict[str, Any],
    by_run: dict[str, list[dict[str, str]]],
    vehicle: dict[str, Any],
    course: dict[str, Any],
) -> dict[str, Any]:
    gravity = q_value_by_unit(vehicle["parameters"], "gravity_m_per_s2", "m/s^2")
    tire_scale = q_value_by_unit(vehicle["parameters"], "tire_friction_scale", "1")
    surfaces = {item["id"]: q_value_by_unit(item, "mu", "1") for item in course.get("surfaces", [])}
    results: list[dict[str, Any]] = []
    reference_controls = None
    initial_speeds: list[float] = []
    for run_meta in metadata["runs"]:
        run_id = str(run_meta["run_id"])
        samples = by_run[run_id]
        controls = run_meta.get("controls")
        if not isinstance(controls, dict):
            raise AnalysisError(f"braking run {run_id} has no controls")
        if reference_controls is None:
            reference_controls = controls
        elif controls != reference_controls:
            raise AnalysisError("braking surface trials do not use identical controls")
        surface_id = str(run_meta["surface_id"])
        if surface_id not in surfaces:
            raise AnalysisError(f"unknown braking surface {surface_id}")
        speed = [math.hypot(*world_velocity(row)[:2]) for row in samples]
        distance = _distance(samples)
        v0 = speed[0]
        v_final = speed[-1]
        initial_speeds.append(v0)
        mu_effective = surfaces[surface_id] * tire_scale
        ideal_distance = v0 * v0 / (2.0 * mu_effective * gravity) if mu_effective > 0.0 and gravity > 0.0 else None
        stop_index = None
        stable_ticks = max(1, int(0.25 * int(metadata["public_hz"])))
        for index in range(0, max(0, len(speed) - stable_ticks)):
            if all(value < 0.10 for value in speed[index : index + stable_ticks]):
                stop_index = index
                break
        mean_deceleration = (v0 * v0 - v_final * v_final) / (2.0 * distance) if distance > 1.0e-12 else None
        peak_deceleration = max(
            (-(speed[index + 1] - speed[index]) * int(metadata["public_hz"]) for index in range(len(speed) - 1)),
            default=0.0,
        )
        if max(speed) > v0 + 0.25:
            raise AnalysisError(f"braking run {run_id} gained unexplained forward speed")
        results.append({
            "run_id": run_id,
            "surface_id": surface_id,
            "estimated_surface_mu": surfaces[surface_id],
            "effective_mu_after_tire_scale": mu_effective,
            "initial_horizontal_speed_m_per_s": v0,
            "final_horizontal_speed_m_per_s": v_final,
            "path_length_m": distance,
            "stop_time_s": (stop_index / int(metadata["public_hz"])) if stop_index is not None else None,
            "mean_energy_equivalent_deceleration_m_per_s2": mean_deceleration,
            "peak_sampled_deceleration_m_per_s2": peak_deceleration,
            "ideal_coulomb_stop_distance_m": ideal_distance,
            "distance_to_ideal_ratio": distance / ideal_distance if ideal_distance else None,
            "interpretation": "Ideal constant-mu reference from v^2/(2*mu*g); no guarantee of equality with finite-torque, compliant estimated tires.",
        })
    if not initial_speeds or max(initial_speeds) - min(initial_speeds) > 1.0e-8:
        raise AnalysisError("braking surface trials did not start at the same horizontal speed")
    if reference_controls != {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": False}:
        raise AnalysisError("braking trials are not the documented full-brake/no-steer input")
    ordered = sorted(results, key=lambda item: (float(item["effective_mu_after_tire_scale"]), str(item["surface_id"])))
    return {
        "trials": results,
        "ordered_by_estimated_effective_mu_low_to_high": [item["surface_id"] for item in ordered],
        "same_initial_speed_verified": True,
        "same_controls_verified": True,
        "comparison_limit": "Surface friction values are synthetic estimates. Differences are a software experiment, not measured braking performance.",
    }


def _bump_analysis(
    metadata: dict[str, Any],
    by_run: dict[str, list[dict[str, str]]],
    course: dict[str, Any],
    vehicle: dict[str, Any],
) -> dict[str, Any]:
    run_id = str(metadata["runs"][0]["run_id"])
    samples = by_run[run_id]
    height_errors: list[float] = []
    expected_heights: list[float] = []
    travel_abs: list[float] = []
    vertical_speed: list[float] = []
    for row in samples:
        north = float(row["north_m"])
        east = float(row["east_m"])
        expected = analytical_course_height(course, north, east)
        actual = float(row["road_height_m"])
        height_errors.append(abs(actual - expected))
        expected_heights.append(expected)
        velocity_ned = world_velocity(row)
        vertical_speed.append(-velocity_ned[2])
        travel_abs.extend(abs(float(row[f"travel_{corner}_m"])) for corner in WHEEL_SUFFIXES)
    maximum_error = max(height_errors, default=math.inf)
    peak_height = max(expected_heights, default=0.0)
    if maximum_error > 1.0e-10:
        raise AnalysisError(f"recorded bump road heights diverge from independent course reconstruction ({maximum_error:.3g} m)")
    if peak_height < 0.01:
        raise AnalysisError("bump run did not reach the declared analytic bump lane")
    max_travel = max(travel_abs, default=math.inf)
    travel_limit = max(
        q_value_by_unit(vehicle["parameters"], "travel_bump_m", "m"),
        q_value_by_unit(vehicle["parameters"], "travel_droop_m", "m"),
    )
    return {
        "run_id": run_id,
        "samples": len(samples),
        "peak_road_height_m": peak_height,
        "maximum_road_height_reconstruction_error_m": maximum_error,
        "peak_absolute_body_vertical_speed_m_per_s": max((abs(value) for value in vertical_speed), default=0.0),
        "peak_absolute_arm_travel_m": max_travel,
        "nominal_travel_envelope_m": travel_limit,
        "travel_within_nominal_envelope": max_travel <= travel_limit + 0.05,
        "analysis_limit": "Analytic vertical terrain agreement verifies the shared descriptor; point-probed tires and estimated suspension do not validate obstacle enveloping or a real bump response.",
    }


def _drop_analysis(
    metadata: dict[str, Any],
    by_run: dict[str, list[dict[str, str]]],
    vehicle: dict[str, Any],
) -> dict[str, Any]:
    run_id = str(metadata["runs"][0]["run_id"])
    samples = by_run[run_id]
    gravity = q_value_by_unit(vehicle["parameters"], "gravity_m_per_s2", "m/s^2")
    if samples[0]["airborne"] != "true":
        raise AnalysisError("drop test does not start airborne")
    initial_com_ned, initial_com_velocity_ned = _vehicle_system_com_ned(samples[0], vehicle)
    initial_up_m = -initial_com_ned[2]
    initial_velocity_up = -initial_com_velocity_ned[2]
    residual_height: list[float] = []
    residual_velocity: list[float] = []
    last_airborne_time = 0.0
    first_contact_time = None
    for row in samples:
        time_s = float(row["time_s"])
        elapsed_s = time_s - float(samples[0]["time_s"])
        if row["airborne"] != "true":
            first_contact_time = time_s
            break
        last_airborne_time = time_s
        com_ned, com_velocity_ned = _vehicle_system_com_ned(row, vehicle)
        expected_up = initial_up_m + initial_velocity_up * elapsed_s - 0.5 * gravity * elapsed_s * elapsed_s
        actual_up = -com_ned[2]
        actual_velocity_up = -com_velocity_ned[2]
        residual_height.append(abs(actual_up - expected_up))
        residual_velocity.append(abs(actual_velocity_up - (initial_velocity_up - gravity * elapsed_s)))
    if first_contact_time is None:
        raise AnalysisError("drop test did not reach tire or hull contact within the recording")
    max_height_error = max(residual_height, default=math.inf)
    max_velocity_error = max(residual_velocity, default=math.inf)
    if max_height_error > 1.0e-4 or max_velocity_error > 1.0e-3:
        raise AnalysisError("free-flight samples disagree with independent constant-gravity ballistic motion")
    last_elapsed_s = last_airborne_time - float(samples[0]["time_s"])
    expected_delta_up = initial_velocity_up * last_elapsed_s - 0.5 * gravity * last_elapsed_s * last_elapsed_s
    last_row = next(row for row in samples if abs(float(row["time_s"]) - last_airborne_time) < 1.0e-12)
    last_com_ned, _ = _vehicle_system_com_ned(last_row, vehicle)
    actual_delta_up = -last_com_ned[2] - initial_up_m
    return {
        "run_id": run_id,
        "free_flight_sample_count": len(residual_height),
        "last_airborne_time_s": last_airborne_time,
        "first_contact_time_s": first_contact_time,
        "system_com_free_fall_height_change_m": -expected_delta_up,
        "expected_com_height_delta_m_at_last_airborne_sample": expected_delta_up,
        "actual_com_height_delta_m_at_last_airborne_sample": actual_delta_up,
        "maximum_ballistic_height_error_m": max_height_error,
        "maximum_ballistic_vertical_velocity_error_m_per_s": max_velocity_error,
        "check": "pass",
        "analysis_limit": "The ballistic check uses the sprung-plus-hub system center of mass, because internal suspension forces can accelerate the sprung chassis during free flight. It covers only pre-contact motion; contact bounce and damping remain estimated and are not physical validation.",
    }


def _roll_euler_from_quaternion(row: dict[str, str]) -> float:
    qw, qx, qy, qz = (
        _finite_number(row, name, -1) for name in ("qw", "qx", "qy", "qz")
    )
    norm = math.sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
    if norm <= 0.0:
        raise AnalysisError("recording contains a zero attitude quaternion")
    qw, qx, qy, qz = (component / norm for component in (qw, qx, qy, qz))
    return math.atan2(2.0 * (qw * qx + qy * qz), 1.0 - 2.0 * (qx * qx + qy * qy))


def _body_down_world_ned_z(row: dict[str, str]) -> float:
    """Return body +Z-down projected onto world NED down; negative means inverted."""
    qw, qx, qy, qz = (
        _finite_number(row, name, -1) for name in ("qw", "qx", "qy", "qz")
    )
    norm = math.sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
    if norm <= 0.0:
        raise AnalysisError("recording contains a zero attitude quaternion")
    qx, qy = qx / norm, qy / norm
    return 1.0 - 2.0 * (qx * qx + qy * qy)


def _rigid_tipping_reference(
    vehicle: dict[str, Any], course: dict[str, Any]
) -> dict[str, float]:
    parameters = vehicle.get("parameters")
    if not isinstance(parameters, dict):
        raise AnalysisError("vehicle profile has no parameter object")
    spawns = course.get("spawns")
    if not isinstance(spawns, list):
        raise AnalysisError("course profile has no spawn list")
    start = next((spawn for spawn in spawns if isinstance(spawn, dict) and spawn.get("id") == "start"), None)
    if start is None:
        raise AnalysisError("course profile has no start spawn")
    corner_y_quantity = parameters.get("corner_y_datum_frd_m")
    if (
        not isinstance(corner_y_quantity, dict)
        or corner_y_quantity.get("unit") != "m"
        or not isinstance(corner_y_quantity.get("value"), list)
        or len(corner_y_quantity["value"]) != 4
    ):
        raise AnalysisError("vehicle profile has invalid corner_y_datum_frd_m")
    corner_y = corner_y_quantity["value"]
    if any(isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)) for value in corner_y):
        raise AnalysisError("vehicle profile has nonfinite corner lateral geometry")
    arm = q_value_by_unit(parameters, "arm_length_m", "m")
    gravity = q_value_by_unit(parameters, "gravity_m_per_s2", "m/s^2")
    sprung_mass = q_value_by_unit(parameters, "sprung_mass_kg", "kg")
    spring_k = q_value_by_unit(parameters, "suspension_stiffness_n_per_m", "N/m")
    cg_right = q_value_by_unit(parameters, "cg_right_from_datum_m", "m")
    if arm <= 0.0 or gravity < 0.0 or sprung_mass <= 0.0 or spring_k <= 0.0:
        raise AnalysisError("vehicle profile cannot form the rigid tipping reference")
    static_travel = sprung_mass * gravity / (4.0 * spring_k)
    if static_travel >= arm:
        raise AnalysisError("static suspension travel reaches arm singularity")
    radial = math.sqrt(arm * arm - static_travel * static_travel)
    right_hub_y = float(corner_y[1]) - cg_right + radial - arm
    half_track = abs(right_hub_y)
    spawn_north = q_value_by_unit(start, "north_m", "m")
    spawn_east = q_value_by_unit(start, "east_m", "m")
    cg_up = q_value_by_unit(start, "vehicle_up_m", "m")
    ground_up = analytical_course_height(course, spawn_north, spawn_east)
    cg_height = cg_up - ground_up
    if half_track <= 0.0 or cg_height <= 0.0:
        raise AnalysisError("rigid tipping reference has invalid support geometry")
    threshold = math.atan2(half_track, cg_height)
    return {
        "half_track_m": half_track,
        "upright_sprung_cg_height_above_ground_m": cg_height,
        "critical_tilt_angle_rad": threshold,
        "critical_tilt_angle_deg": math.degrees(threshold),
    }


def _spherical_tire_center_reference(
    vehicle: dict[str, Any], course: dict[str, Any]
) -> dict[str, float | str]:
    """Estimate the right tire-center normal-moment sign change from profile quantities."""
    fixed_edge = _rigid_tipping_reference(vehicle, course)
    parameters = vehicle.get("parameters")
    if not isinstance(parameters, dict):
        raise AnalysisError("vehicle profile has no parameter object")
    gravity = q_value_by_unit(parameters, "gravity_m_per_s2", "m/s^2")
    sprung_mass = q_value_by_unit(parameters, "sprung_mass_kg", "kg")
    unsprung_mass = q_value_by_unit(parameters, "unsprung_mass_kg", "kg")
    tire_stiffness = q_value_by_unit(parameters, "tire_stiffness_n_per_m", "N/m")
    tire_radius = q_value_by_unit(parameters, "tire_radius_m", "m")
    if gravity < 0.0 or sprung_mass <= 0.0 or unsprung_mass < 0.0 or tire_stiffness <= 0.0 or tire_radius <= 0.0:
        raise AnalysisError("vehicle profile cannot form the spherical tire-center reference")
    compression = (sprung_mass + 4.0 * unsprung_mass) * gravity / (4.0 * tire_stiffness)
    cg_height_above_hub = fixed_edge["upright_sprung_cg_height_above_ground_m"] - tire_radius + compression
    if cg_height_above_hub <= 0.0:
        raise AnalysisError("spherical tire-center reference has invalid vertical CG geometry")
    threshold = math.atan2(fixed_edge["half_track_m"], cg_height_above_hub)
    return {
        "kind": "spherical tire-center normal-moment sign-change estimate",
        "half_track_m": fixed_edge["half_track_m"],
        "upright_sprung_cg_height_above_ground_m": fixed_edge["upright_sprung_cg_height_above_ground_m"],
        "tire_radius_m": tire_radius,
        "estimated_static_tire_compression_m": compression,
        "cg_height_above_tire_hub_center_m": cg_height_above_hub,
        "estimated_sign_change_angle_rad": threshold,
        "estimated_sign_change_angle_deg": math.degrees(threshold),
        "assumptions": "Approximate right tire-center support normal with fixed CG and symmetric static tire compression; ignores suspension articulation during roll, unsprung-force distribution, friction and hull contact. This is a moment-sign geometry witness, not a rollover or recovery threshold.",
    }


def _rollover_analysis(
    metadata: dict[str, Any],
    by_run: dict[str, list[dict[str, str]]],
    vehicle: dict[str, Any],
    course: dict[str, Any],
) -> dict[str, Any]:
    reference = _rigid_tipping_reference(vehicle, course)
    spherical_reference = _spherical_tire_center_reference(vehicle, course)
    recorded_reference = metadata.get("rigid_tipping_reference")
    if not isinstance(recorded_reference, dict):
        raise AnalysisError("rollover metadata has no rigid geometric reference")
    for key, value in reference.items():
        recorded = recorded_reference.get(key)
        if isinstance(recorded, bool) or not isinstance(recorded, (int, float)) or abs(float(recorded) - value) > 1.0e-9:
            raise AnalysisError(f"recorded rigid tipping reference disagrees with source geometry: {key}")
    recorded_spherical_reference = metadata.get("spherical_tire_center_reference")
    if not isinstance(recorded_spherical_reference, dict):
        raise AnalysisError("rollover metadata has no spherical tire-center reference")
    for key, value in spherical_reference.items():
        recorded = recorded_spherical_reference.get(key)
        if isinstance(value, str):
            if recorded != value:
                raise AnalysisError(f"recorded spherical tire-center reference disagrees with source assumptions: {key}")
        elif isinstance(recorded, bool) or not isinstance(recorded, (int, float)) or abs(float(recorded) - float(value)) > 1.0e-9:
            raise AnalysisError(f"recorded spherical tire-center reference disagrees with source geometry: {key}")
    expected_angles = (35.0, 55.0, 75.0)
    if not 35.0 < reference["critical_tilt_angle_deg"] < 55.0:
        raise AnalysisError("the fixed-ground-edge reference does not lie between the 35/55 degree comparison pair")
    if not 55.0 < float(spherical_reference["estimated_sign_change_angle_deg"]) < 75.0:
        raise AnalysisError("the spherical tire-center sign-change estimate does not lie between the 55/75 degree comparison pair")
    if len(metadata["runs"]) != len(expected_angles):
        raise AnalysisError("rollover experiment must contain the 35/55 comparison and 75 degree witness")
    releases: list[dict[str, Any]] = []
    for run_meta in metadata["runs"]:
        run_id = str(run_meta["run_id"])
        samples = by_run[run_id]
        angle = run_meta.get("initial_roll_angle_deg")
        if isinstance(angle, bool) or not isinstance(angle, (int, float)) or float(angle) not in expected_angles:
            raise AnalysisError(f"rollover run {run_id} has an unexpected initial angle")
        controls = run_meta.get("controls")
        if controls != {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": False}:
            raise AnalysisError(f"rollover run {run_id} is not an unpowered neutral release")
        first = samples[0]
        expected_roll_rad = math.radians(float(angle))
        if abs(_roll_euler_from_quaternion(first) - expected_roll_rad) > 1.0e-8:
            raise AnalysisError(f"rollover run {run_id} initial quaternion does not match its declared roll")
        quaternion_roll_error = 0.0
        max_abs_roll = 0.0
        max_hull_count = 0
        first_hull_contact = None
        first_inverted_time = None
        first_four_wheel_contact_time = None
        first_unload: list[float | None] = [None, None, None, None]
        initial_contacts = [samples[0][f"wheel_contact_{corner}"] == "true" for corner in WHEEL_SUFFIXES]
        recorded_initial_contacts = run_meta.get("initial_wheel_contact")
        if recorded_initial_contacts != initial_contacts:
            raise AnalysisError(f"rollover run {run_id} initial contact metadata disagrees with CSV")
        for row in samples:
            time_s = float(row["time_s"])
            calculated_roll = _roll_euler_from_quaternion(row)
            quaternion_roll_error = max(quaternion_roll_error, abs(calculated_roll - float(row["roll_euler_rad"])))
            max_abs_roll = max(max_abs_roll, abs(calculated_roll))
            if _body_down_world_ned_z(row) < 0.0 and first_inverted_time is None:
                first_inverted_time = time_s
            count = int(float(row["hull_contact_count"]))
            max_hull_count = max(max_hull_count, count)
            if count > 0 and first_hull_contact is None:
                first_hull_contact = time_s
            if all(row[f"wheel_contact_{corner}"] == "true" for corner in WHEEL_SUFFIXES):
                if first_four_wheel_contact_time is None:
                    first_four_wheel_contact_time = time_s
            for index, corner in enumerate(WHEEL_SUFFIXES):
                if initial_contacts[index] and row[f"wheel_contact_{corner}"] == "false" and first_unload[index] is None:
                    first_unload[index] = time_s
        if quaternion_roll_error > 1.0e-8:
            raise AnalysisError(f"rollover run {run_id} roll telemetry disagrees with its quaternion")
        metadata_unload = run_meta.get("first_wheel_unload_time_s")
        if not isinstance(metadata_unload, list) or len(metadata_unload) != 4:
            raise AnalysisError(f"rollover run {run_id} has invalid wheel unload metadata")
        for calculated, recorded in zip(first_unload, metadata_unload):
            if calculated is None:
                if recorded is not None:
                    raise AnalysisError(f"rollover run {run_id} unload metadata disagrees with wheel contact samples")
            elif not isinstance(recorded, (int, float)) or abs(float(recorded) - calculated) > 1.0e-9:
                raise AnalysisError(f"rollover run {run_id} unload metadata disagrees with wheel contact samples")
        recorded_hull_time = run_meta.get("first_hull_contact_time_s")
        if first_hull_contact is None:
            if recorded_hull_time is not None:
                raise AnalysisError(f"rollover run {run_id} hull-contact metadata disagrees with samples")
        elif not isinstance(recorded_hull_time, (int, float)) or abs(float(recorded_hull_time) - first_hull_contact) > 1.0e-9:
            raise AnalysisError(f"rollover run {run_id} hull-contact metadata disagrees with samples")
        if int(run_meta.get("max_hull_contact_count", -1)) != max_hull_count:
            raise AnalysisError(f"rollover run {run_id} maximum hull-contact metadata disagrees with samples")
        releases.append({
            "run_id": run_id,
            "initial_tilt_deg": float(angle),
            "relation_to_rigid_reference": "below" if float(angle) < reference["critical_tilt_angle_deg"] else "above",
            "relation_to_spherical_tire_center_reference": "below" if float(angle) < float(spherical_reference["estimated_sign_change_angle_deg"]) else "above",
            "initial_wheel_contacts_fl_fr_rl_rr": initial_contacts,
            "final_wheel_contacts_fl_fr_rl_rr": [samples[-1][f"wheel_contact_{corner}"] == "true" for corner in WHEEL_SUFFIXES],
            "first_four_wheel_contact_time_s": first_four_wheel_contact_time,
            "first_inverted_time_s": first_inverted_time,
            "final_body_down_world_ned_z": _body_down_world_ned_z(samples[-1]),
            "final_is_inverted": _body_down_world_ned_z(samples[-1]) < 0.0,
            "first_wheel_unload_time_s_fl_fr_rl_rr": first_unload,
            "first_hull_contact_time_s": first_hull_contact,
            "maximum_hull_probes_in_contact": max_hull_count,
            "maximum_absolute_roll_deg": math.degrees(max_abs_roll),
            "final_roll_deg": math.degrees(_roll_euler_from_quaternion(samples[-1])),
            "maximum_wheel_slip_ratio": max(
                abs(float(row[f"wheel_slip_ratio_{corner}"]))
                for row in samples
                for corner in WHEEL_SUFFIXES
            ),
            "quaternion_roll_reconstruction_error_rad": quaternion_roll_error,
        })
    return {
        "rigid_tipping_reference": {
            **reference,
            "interpretation": "Fixed ground-edge geometry only. It differs from the spherical tire-center normal-moment estimate and neither predicts nor sets an acceptance threshold for the compliant truck model.",
        },
        "spherical_tire_center_reference": {
            **spherical_reference,
            "interpretation": "Approximate hub-center normal-moment sign comparator for this modeled tire radius and static compression. It is not a rigid ground-edge threshold or a compliant-truck acceptance value.",
        },
        "angle_pair_straddles_rigid_reference": True,
        "over_center_witness_angle_deg": 75.0,
        "over_center_witness_exceeds_spherical_reference": True,
        "neutral_release_trials": releases,
        "observed_behavior_is_qualitative": True,
        "roll_angle_representation": "Euler roll is wrapped to ±180 degrees and is not a cumulative rotation count; final inversion is classified independently from the quaternion's body-down axis.",
        "analysis_limit": "All three releases preserve initialized suspension travel and place the right tire hubs on the flat course, then release with neutral controls. The 35/55 pair brackets the fixed ground-edge atan2 comparator, while 55/75 brackets the estimated spherical tire-center normal-moment sign change. These geometry references make different support assumptions; observed wheel contacts, tire slip, hull contacts and roll remain outputs of this estimated compliant model. No trial establishes a real-truck threshold, self-righting, or handling fidelity.",
    }


def analyze_recording(
    csv_path: Path,
    metadata_path: Path | None = None,
    vehicle_path: Path = DEFAULT_VEHICLE,
    course_path: Path = DEFAULT_COURSE,
) -> dict[str, Any]:
    csv_path = csv_path.resolve()
    if metadata_path is None:
        metadata_path = csv_path.with_suffix(".json")
    metadata_path = metadata_path.resolve()
    if not csv_path.is_file():
        raise AnalysisError(f"CSV recording does not exist: {csv_path}")
    metadata, rows = read_recording(csv_path, metadata_path)
    vehicle = load_and_check_identity(vehicle_path, metadata.get("vehicle_identity"), "vehicle profile")
    course = load_and_check_identity(course_path, metadata.get("course_identity"), "course profile")
    if vehicle.get("format") != "openrc-ground-vehicle" or course.get("format") != "openrc-ground-course":
        raise AnalysisError("source profiles have unsupported formats")
    by_run: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_run.setdefault(row["run_id"], []).append(row)
    scenario = str(metadata["scenario"])
    if scenario == "braking":
        checks = _braking_analysis(metadata, by_run, vehicle, course)
    elif scenario == "bump":
        checks = _bump_analysis(metadata, by_run, course, vehicle)
    elif scenario == "drop":
        checks = _drop_analysis(metadata, by_run, vehicle)
    else:
        checks = _rollover_analysis(metadata, by_run, vehicle, course)
    return {
        "format": ANALYSIS_FORMAT,
        "version": ANALYSIS_VERSION,
        "status": "complete",
        "scenario": scenario,
        "solver_version": metadata["solver_version"],
        "source_recording": str(csv_path),
        "source_recording_sha256": sha256_bytes(csv_path.read_bytes()),
        "source_metadata": str(metadata_path),
        "source_metadata_sha256": sha256_bytes(metadata_path.read_bytes()),
        "vehicle_identity": metadata["vehicle_identity"],
        "course_identity": metadata["course_identity"],
        "sample_count": len(rows),
        "independent_analysis": checks,
        "qualification": "Software and source-consistency checks only. The bundled vehicle and course parameters are estimates; this report does not establish physical validity or handling fidelity.",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recording", type=Path, help="completed experiment CSV")
    parser.add_argument("--metadata", type=Path, help="sidecar JSON (default: recording with .json extension)")
    parser.add_argument("--vehicle-json", type=Path, default=DEFAULT_VEHICLE)
    parser.add_argument("--course-json", type=Path, default=DEFAULT_COURSE)
    parser.add_argument("--output", type=Path, help="write analysis JSON to a fresh path instead of stdout")
    args = parser.parse_args(argv)
    try:
        report = analyze_recording(args.recording, args.metadata, args.vehicle_json, args.course_json)
    except (AnalysisError, OSError, TypeError, ValueError, KeyError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    rendered = json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    if args.output:
        try:
            if args.output.exists():
                print(f"ERROR: refusing to replace existing analysis output: {args.output}", file=sys.stderr)
                return 1
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_bytes(rendered.encode("utf-8"))
        except OSError as exc:
            print(f"ERROR: cannot write analysis JSON {args.output}: {exc}", file=sys.stderr)
            return 1
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
