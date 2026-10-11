#!/usr/bin/env python3
"""Strict, independent checks for EL2a-E1 electric flight traces.

The existing EL2 v8 battery verifier remains the authority for the battery
fixture contract and per-row electrical/energy equations. This module adds the
variable-duration, variable-rate trace boundary needed by EL2a-E1.
"""
from __future__ import annotations

import csv
from decimal import Decimal, InvalidOperation
import hashlib
import importlib.util
import io
import json
import math
import sys
from pathlib import Path
from types import ModuleType
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
BASE_VERIFIER_PATH = ROOT / "research/propulsion/el2/verify_flights.py"
BASE_VERIFIER_MODULE = "openrc_el2_battery_flight_verifier"


def _load_base_verifier() -> ModuleType:
    existing = sys.modules.get(BASE_VERIFIER_MODULE)
    if existing is not None:
        return existing
    spec = importlib.util.spec_from_file_location(BASE_VERIFIER_MODULE, BASE_VERIFIER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load the EL2 battery verifier: {BASE_VERIFIER_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[BASE_VERIFIER_MODULE] = module
    spec.loader.exec_module(module)
    return module


EL2 = _load_base_verifier()

REQUIRED_COLUMNS = frozenset({
    "tick", "t_s", "alt_m", "speed_mps", "yaw_deg", "roll_deg", "engine_rpm", "cmd_throttle",
    "drive_enabled", "drive_duty", "bus_voltage_v", "motor_current_a", "drive_bus_current_a",
    "source_torque_nm", "shaft_power_w", "copper_loss_w", "rotational_loss_w", "battery_soc",
    "remaining_charge_c", "consumed_charge_c", "pack_current_a", "auxiliary_current_a", "ocv_v",
    "pack_terminal_power_w", "pack_loss_w", "terminal_energy_j", "pack_heat_j", "pack_exhausted",
})
MANEUVERS = frozenset({"takeoff", "stall", "landing"})
PACKS = frozenset({"4s", "6s"})
CSV_TIME_ROUNDING_TOL_S = 0.501e-9  # Recorder.to_csv writes t_s with nine decimal places.
MIN_INEXACT_DT_DIGITS = 12  # Preserve the serialized precision of Godot's `str(float)` metadata.


def _require(condition: bool, message: str) -> None:
    EL2.require(condition, message)


def _finite_number(value: str, label: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{label} is not numeric: {value!r}") from error
    _require(math.isfinite(result), f"{label} is nonfinite")
    return result


def _parse_trace(path: Path) -> tuple[dict[str, str], list[dict[str, float]]]:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ValueError(f"could not read UTF-8 trace {path}: {error}") from error

    metadata: dict[str, str] = {}
    body_lines: list[str] = []
    found_header = False
    for line_number, line in enumerate(text.splitlines(), start=1):
        if not found_header and line.startswith("# "):
            try:
                key, value = line[2:].split(": ", 1)
            except ValueError as error:
                raise ValueError(f"malformed metadata line {line_number}") from error
            _require(bool(key), f"empty metadata key at line {line_number}")
            _require(key not in metadata, f"duplicate metadata: {key}")
            metadata[key] = value
        else:
            if not found_header:
                _require(bool(line), f"missing CSV header at line {line_number}")
                found_header = True
            body_lines.append(line)

    _require(found_header, "trace is missing its CSV header")
    try:
        parsed = list(csv.reader(io.StringIO("\n".join(body_lines)), strict=True))
    except csv.Error as error:
        raise ValueError(f"malformed CSV: {error}") from error
    _require(bool(parsed), "trace is missing its CSV header")
    columns = parsed[0]
    _require(bool(columns) and all(columns), "missing or empty CSV column name")
    _require(len(columns) == len(set(columns)), "missing or duplicate CSV columns")
    _require(REQUIRED_COLUMNS.issubset(set(columns)), "trace is missing required v8 electric/battery columns")

    rows: list[dict[str, float]] = []
    for row_index, cells in enumerate(parsed[1:]):
        _require(len(cells) == len(columns),
                 f"malformed CSV row {row_index}: expected {len(columns)} cells, found {len(cells)}")
        row: dict[str, float] = {}
        for column, value in zip(columns, cells):
            row[column] = _finite_number(value, f"row {row_index} {column}")
        rows.append(row)
    _require(bool(rows), "trace contains no data rows")
    return metadata, rows


def _metadata_number(metadata: dict[str, str], key: str) -> float:
    _require(key in metadata, f"missing required metadata: {key}")
    return _finite_number(metadata[key], f"metadata {key}")


def _check_el2a_metadata(metadata: dict[str, str], raw: dict[str, Any],
                         expected_ticks: int, hz: int) -> tuple[str, str, float]:
    recorded_hz_value = _metadata_number(metadata, "el2a_e1_simulation_hz")
    _require(recorded_hz_value.is_integer() and int(recorded_hz_value) == hz,
             f"simulation_hz metadata does not match requested {hz} Hz")

    planned_duration = _metadata_number(metadata, "el2a_e1_planned_duration_s")
    expected_duration = expected_ticks / hz
    _require(planned_duration > 0.0 and abs(planned_duration - expected_duration) <= 1e-12,
             "planned_duration_s metadata does not match the declared tick count and Hz")
    dt_text = metadata.get("dt_s")
    _require(dt_text is not None, "missing required metadata: dt_s")
    _metadata_number(metadata, "dt_s")  # Reject NaN, infinity, and non-numeric metadata first.
    try:
        dt_decimal = Decimal(dt_text)
        requested_dt = Decimal(1) / Decimal(hz)
    except InvalidOperation as error:
        raise ValueError("dt_s metadata is not a valid decimal") from error
    last_place = Decimal(1).scaleb(dt_decimal.as_tuple().exponent)
    serialization_rounding = abs(last_place) / 2
    dt_error = abs(dt_decimal - requested_dt)
    _require(dt_error <= serialization_rounding,
             f"dt_s metadata does not match requested {hz} Hz")
    if dt_error != 0:
        _require(len(dt_decimal.as_tuple().digits) >= MIN_INEXACT_DT_DIGITS,
                 "inexact dt_s metadata does not preserve sufficient decimal precision")

    maneuver = metadata.get("el2a_e1_maneuver", "")
    _require(maneuver in MANEUVERS, f"unknown or missing EL2a-E1 maneuver: {maneuver!r}")
    pack = metadata.get("el2a_e1_pack", "").lower()
    _require(pack in PACKS, f"unknown or missing EL2a-E1 pack: {pack!r}")
    aircraft_id = str(raw.get("id", "")).lower()
    _require(f"_{pack}_" in f"_{aircraft_id}_",
             f"EL2a-E1 pack metadata {pack!r} does not match fixture id {aircraft_id!r}")
    _require(bool(metadata.get("el2a_e1_pilot", "").strip()), "missing EL2a-E1 pilot metadata")
    _require("recording_start_tick" in metadata, "missing required metadata: recording_start_tick")
    recording_start_tick = _metadata_number(metadata, "recording_start_tick")
    _require(recording_start_tick == 0.0, "EL2a-E1 trace must begin at simulation tick zero")
    if maneuver == "takeoff":
        _require(metadata.get("launch_choice") == "runway",
                 "takeoff trace must record a runway launch")
    return pack, maneuver, planned_duration


def _check_start_metadata(metadata: dict[str, str], config: dict[str, Any],
                          first_row: dict[str, float]) -> float:
    try:
        start_continuous = json.loads(metadata.get("recording_start_continuous", "null"))
        start_aux = json.loads(metadata.get("recording_start_aux", "null"))
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid recording start metadata: {error}") from error
    _require(isinstance(start_continuous, list) and len(start_continuous) == 4
             and isinstance(start_aux, list) and len(start_aux) == 4,
             "trace start metadata must contain the four-state battery layout and four sampled auxiliaries")
    _require(all(type(value) in (int, float) and math.isfinite(float(value))
                 for value in start_continuous + start_aux),
             "nonfinite trace start metadata")

    pack = config["battery"]
    capacity_c = 3600.0 * pack["capacity_ah"]
    initial_charge_c = capacity_c * pack["initial_soc"]
    shaft_rpm, remaining_charge, terminal_energy, pack_heat = map(float, start_continuous[-4:])
    EL2.close(remaining_charge, initial_charge_c, EL2.CHARGE_LEDGER_TOL_C, "start continuous charge")
    EL2.close(terminal_energy, 0.0, 0.0, "start terminal energy")
    EL2.close(pack_heat, 0.0, 0.0, "start pack heat")
    EL2.close(shaft_rpm, float(start_aux[0]), 1e-12, "start RPM mirror")
    EL2.close(shaft_rpm, first_row["engine_rpm"], 2e-8, "recording start RPM")
    EL2.close(remaining_charge, first_row["remaining_charge_c"],
              EL2.CHARGE_LEDGER_TOL_C, "recording start charge")
    EL2.close(terminal_energy, first_row["terminal_energy_j"],
              EL2.ENERGY_LEDGER_TOL_J, "recording start terminal energy")
    EL2.close(pack_heat, first_row["pack_heat_j"], 2e-6, "recording start pack heat")
    return initial_charge_c


def check_trace(path: Path, data_path: Path, expected_ticks: int, hz: int) -> dict[str, Any]:
    """Verify one EL2a-E1 v8 trace and return concise evidence metrics.

    ``expected_ticks`` counts accepted integration steps after the tick-zero
    boundary sample. A complete recording therefore contains ticks 0 through
    ``expected_ticks`` inclusive, or ``expected_ticks + 1`` rows.
    """
    path = Path(path)
    data_path = Path(data_path)
    _require(type(expected_ticks) is int and expected_ticks >= 0,
             "expected_ticks must be a nonnegative integer step count")
    _require(type(hz) is int and hz > 0, "hz must be a positive integer")

    metadata, rows = _parse_trace(path)
    raw = EL2.read_fixture(data_path)
    config = EL2.normalized_configuration(metadata, raw, data_path)
    pack, maneuver, planned_duration = _check_el2a_metadata(metadata, raw, expected_ticks, hz)
    _require(len(rows) == expected_ticks + 1,
             f"incomplete trace: expected {expected_ticks + 1} samples for {expected_ticks} ticks, found {len(rows)}")

    capacity_c = 3600.0 * config["battery"]["capacity_ah"]
    initial_charge_c = capacity_c * config["battery"]["initial_soc"]
    _check_start_metadata(metadata, config, rows[0])
    if maneuver == "takeoff":
        start = rows[0]
        _require(start["engine_rpm"] == 0.0,
                 "runway takeoff trace must begin with the propeller shaft stopped")
        _require(start["drive_duty"] == 0.0 and start["cmd_throttle"] == 0.0,
                 "runway takeoff trace must begin at zero motor duty and throttle")
        _require(start["drive_enabled"] == 1.0,
                 "runway takeoff trace must begin with the electric source enabled")

    previous: dict[str, float] | None = None
    max_time_error_s = 0.0
    max_drive_power_residual_w = 0.0
    max_pack_power_residual_w = 0.0
    max_energy_ledger_residual_j = 0.0
    for tick, row in enumerate(rows):
        _require(row["tick"] == float(tick),
                 f"duplicate, reordered, or missing sample at row {tick}: tick={row['tick']}")
        expected_time = tick / hz
        time_error = abs(row["t_s"] - expected_time)
        _require(time_error <= CSV_TIME_ROUNDING_TOL_S,
                 f"simulation-time gap at row {tick}: {row['t_s']:.12g} != {expected_time:.12g} s")
        max_time_error_s = max(max_time_error_s, time_error)
        if previous is not None:
            _require(row["t_s"] > previous["t_s"], f"duplicate or nonincreasing sample time at row {tick}")
            _require(row["remaining_charge_c"] <= previous["remaining_charge_c"] + EL2.CHARGE_LEDGER_TOL_C,
                     f"charge increased during motoring-only flight at row {tick}")
            _require(row["consumed_charge_c"] + EL2.CHARGE_LEDGER_TOL_C >= previous["consumed_charge_c"],
                     f"consumed charge decreased at row {tick}")
            _require(row["battery_soc"] <= previous["battery_soc"] + 1e-9,
                     f"SOC increased during motoring-only flight at row {tick}")
            _require(row["terminal_energy_j"] + 1e-9 >= previous["terminal_energy_j"],
                     f"terminal energy decreased at row {tick}")
            _require(row["pack_heat_j"] + 1e-9 >= previous["pack_heat_j"],
                     f"pack heat decreased at row {tick}")

        residuals = EL2.electrical_row(row, config, capacity_c, initial_charge_c, tick)
        max_drive_power_residual_w = max(max_drive_power_residual_w,
                                         residuals["power_balance_residual_w"])
        max_pack_power_residual_w = max(max_pack_power_residual_w,
                                        residuals["pack_power_residual_w"])
        max_energy_ledger_residual_j = max(max_energy_ledger_residual_j,
                                           residuals["energy_ledger_residual_j"])
        previous = row

    return {
        "trace_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "aircraft_input_sha256": metadata["aircraft_input_sha256"],
        "fixture_id": raw["id"],
        "pack": pack,
        "maneuver": maneuver,
        "pilot": metadata["el2a_e1_pilot"],
        "launch_choice": metadata.get("launch_choice", ""),
        "hz": hz,
        "ticks": expected_ticks,
        "rows": len(rows),
        "planned_duration_s": planned_duration,
        "min_altitude_m": min(row["alt_m"] for row in rows),
        "max_altitude_m": max(row["alt_m"] for row in rows),
        "rows_at_or_below_10m": sum(row["alt_m"] <= 10.0 for row in rows),
        "max_engine_rpm": max(row["engine_rpm"] for row in rows),
        "max_pack_current_a": max(row["pack_current_a"] for row in rows),
        "start_soc": rows[0]["battery_soc"],
        "final_soc": rows[-1]["battery_soc"],
        "max_tick_time_error_s": max_time_error_s,
        "max_drive_power_residual_w": max_drive_power_residual_w,
        "max_pack_power_residual_w": max_pack_power_residual_w,
        "max_energy_ledger_residual_j": max_energy_ledger_residual_j,
    }
