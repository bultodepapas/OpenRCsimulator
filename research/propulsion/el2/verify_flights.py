#!/usr/bin/env python3
"""EL2a software-only verification for synthetic OCV/resistance battery flights.

Reads openrc-trace v8, independently recomputes pack and motor arithmetic, checks
charge/energy ledgers, and compares coupled-state refinement runs. These authored
fixtures are not measured batteries or physical flight validation.
"""
import argparse
import copy
import csv
import hashlib
import io
import json
import math
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
BATTERY_LAW = "electric-ocv-resistance-coupled-events-v1"
TIMING = "accepted endpoint; current tick input and source-enabled mode"
BATTERY_LAYOUT = (
    "axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm, "
    "remaining charge C, terminal energy J, pack heat J; RK4 coupled"
)
LEVEL_ALTITUDE_BAND_M = 10.0
POWER_TOL_W = 2e-5
CURRENT_TOL_A = 2e-6
VOLTAGE_TOL_V = 2e-6
TORQUE_TOL_NM = 2e-6
ENERGY_LEDGER_TOL_J = 2e-3
CHARGE_LEDGER_TOL_C = 2e-6

BODY_LIMITS = {
    "position_m": (0, 3, 2e-6),
    "velocity_mps": (3, 6, 2e-6),
    "quaternion": (6, 10, 2e-7),
    "body_rate_radps": (10, 13, 2e-6),
}
CONTINUOUS_LIMITS = {
    "shaft_rpm": (0, 1e-4),
    "remaining_charge_c": (1, 2e-7),
    "terminal_energy_j": (2, 2e-5),
    "pack_heat_j": (3, 2e-6),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def close(actual, expected, tolerance, label):
    difference = abs(actual - expected)
    require(difference <= tolerance, f"{label}: {actual:.12g} != {expected:.12g} (|Δ|={difference:.3g}, tol={tolerance:g})")
    return difference


def read_fixture(data_path):
    raw = json.loads(data_path.read_text())
    propulsion = raw["propulsion"]
    battery = propulsion["battery"]
    require(propulsion["kind"] == "electric_prop", "fixture is not electric_prop")
    require(battery["kind"] == "ocv_resistance", "fixture is not an OCV/resistance battery")
    quantities = [battery[key] for key in ("capacity_ah", "resistance_ohm", "auxiliary_current_a", "initial_soc")]
    quantities.extend(point[key] for point in battery["ocv_points"] for key in ("soc", "voltage"))
    for quantity in quantities:
        require(quantity["kind"] == "estimated" and "EL2a synthetic authored fixture" in quantity["source"]
                and "not Timber data" in quantity["source"]
                and "measured LiPo fit" in quantity["source"]
                and "real battery specification" in quantity["source"],
                "fixture provenance must identify synthetic authored values, not measurements")
    return raw


def normalized_configuration(metadata, raw, data_path):
    require(metadata.get("format") == "openrc-trace v8", "expected openrc-trace v8")
    require(metadata.get("propulsion_model") == BATTERY_LAW, "wrong dynamic battery law")
    require(metadata.get("electric_sample_timing") == TIMING, "ambiguous electrical sample time")
    require(metadata.get("shaft_integrator") == "coupled-rk4", "wrong electric shaft integrator")
    require(metadata.get("continuous_layout") == BATTERY_LAYOUT, "wrong battery continuous-state layout")
    require(metadata.get("battery_model") == "balanced-pack-ocv-resistance-no-regeneration-v1", "wrong battery model metadata")
    require(metadata.get("battery_exhaustion") == "remaining charge zero; all pack loads disconnected; bearing loss retained; not ESC LVC",
            "wrong battery exhaustion convention")
    require(metadata.get("battery_charge") == "remaining coulombs integrated; SOC and consumed charge derived; terminal energy and pack heat integrated",
            "wrong battery charge metadata")
    require(metadata.get("battery_auxiliary") == "prescribed pack-side current; no receiver/servo brownout or assistance model",
            "wrong auxiliary-load metadata")
    require(metadata.get("aircraft_input_sha256") == hashlib.sha256(data_path.read_bytes()).hexdigest(),
            "aircraft input SHA does not identify exact source bytes")
    require(metadata.get("aircraft_input_hash_convention") == "sha256 of exact aircraft input file bytes",
            "wrong aircraft byte-hash convention")

    source = raw["propulsion"]
    expected_motor = {key: source["motor"][key]["value"] for key in
                      ("kv_rpm_per_volt", "resistance_ohm", "no_load_current_a")}
    expected_battery = {
        "kind": "ocv_resistance",
        "capacity_ah": source["battery"]["capacity_ah"]["value"],
        "resistance_ohm": source["battery"]["resistance_ohm"]["value"],
        "auxiliary_current_a": source["battery"]["auxiliary_current_a"]["value"],
        "initial_soc": source["battery"]["initial_soc"]["value"],
        "ocv_points": [
            value
            for point in source["battery"]["ocv_points"]
            for value in (point["soc"]["value"], point["voltage"]["value"])
        ],
    }
    expected_esc = {"kind": "ideal_motoring", "command_mapping": "identity"}
    config = json.loads(metadata["electric_configuration"])
    require(config == {"motor": expected_motor, "battery": expected_battery, "esc": expected_esc},
            "full normalized motor/battery/ESC metadata does not match source data")
    return config


def parse_trace(path, data_path):
    text = path.read_text()
    metadata = {}
    body = []
    for line in text.splitlines():
        if line.startswith("# "):
            key, value = line[2:].split(": ", 1)
            require(key not in metadata, f"duplicate metadata: {key}")
            metadata[key] = value
        else:
            body.append(line)
    raw = read_fixture(data_path)
    config = normalized_configuration(metadata, raw, data_path)
    reader = csv.DictReader(io.StringIO("\n".join(body)))
    require(reader.fieldnames is not None and len(reader.fieldnames) == len(set(reader.fieldnames)),
            "missing or duplicate CSV columns")
    required = {
        "tick", "t_s", "alt_m", "speed_mps", "yaw_deg", "roll_deg", "engine_rpm", "cmd_throttle",
        "drive_enabled", "drive_duty", "bus_voltage_v", "motor_current_a", "drive_bus_current_a",
        "source_torque_nm", "shaft_power_w", "copper_loss_w", "rotational_loss_w", "battery_soc",
        "remaining_charge_c", "consumed_charge_c", "pack_current_a", "auxiliary_current_a", "ocv_v",
        "pack_terminal_power_w", "pack_loss_w", "terminal_energy_j", "pack_heat_j", "pack_exhausted",
    }
    require(required.issubset(set(reader.fieldnames)), "trace is missing required v8 electric/battery columns")
    rows = []
    for source_row in reader:
        try:
            rows.append({key: float(value) for key, value in source_row.items()})
        except (TypeError, ValueError) as error:
            raise ValueError(f"malformed CSV row {len(rows)}: {error}") from error
    require(len(rows) == 7201, "incomplete 30-second flight (expected 7201 samples)")
    pack = config["battery"]
    capacity_c = 3600.0 * pack["capacity_ah"]
    initial_charge_c = capacity_c * pack["initial_soc"]
    start_continuous = json.loads(metadata.get("recording_start_continuous", "null"))
    start_aux = json.loads(metadata.get("recording_start_aux", "null"))
    require(isinstance(start_continuous, list) and len(start_continuous) == 4
            and isinstance(start_aux, list) and len(start_aux) == 4,
            "trace start metadata must contain the four-state battery layout and four sampled auxiliaries")
    require(all(isinstance(value, (int, float)) and math.isfinite(float(value))
                for value in start_continuous + start_aux), "nonfinite trace start metadata")
    close(float(start_continuous[1]), initial_charge_c, CHARGE_LEDGER_TOL_C, "start continuous charge")
    close(float(start_continuous[2]), 0.0, 0.0, "start terminal energy")
    close(float(start_continuous[3]), 0.0, 0.0, "start pack heat")
    close(float(start_continuous[0]), float(start_aux[0]), 1e-12, "start RPM mirror")
    previous = None
    for tick, row in enumerate(rows):
        require(all(math.isfinite(value) for value in row.values()), f"nonfinite trace value at row {tick}")
        require(row["tick"] == tick and abs(row["t_s"] - tick / 240.0) < 1e-9,
                f"wrong tick/time at row {tick}")
        require(row["alt_m"] > 10.0, f"flight reached ground at row {tick}")
        if previous is None:
            close(float(start_continuous[0]), row["engine_rpm"], 2e-8, "recording start RPM")
            close(float(start_continuous[1]), row["remaining_charge_c"], CHARGE_LEDGER_TOL_C, "recording start charge")
        else:
            require(row["remaining_charge_c"] <= previous["remaining_charge_c"] + CHARGE_LEDGER_TOL_C,
                    f"charge increased during motoring-only flight at row {tick}")
            require(row["terminal_energy_j"] + 1e-9 >= previous["terminal_energy_j"],
                    f"terminal energy decreased at row {tick}")
            require(row["pack_heat_j"] + 1e-9 >= previous["pack_heat_j"],
                    f"pack heat decreased at row {tick}")
        electrical_row(row, config, capacity_c, initial_charge_c, tick)
        previous = row
    return metadata, rows, config


def ocv_at(points, soc):
    if soc <= points[0]:
        return points[1]
    if soc >= points[-2]:
        return points[-1]
    for index in range(0, len(points) - 2, 2):
        left_soc, left_v, right_soc, right_v = points[index:index + 4]
        if soc <= right_soc:
            fraction = (soc - left_soc) / (right_soc - left_soc)
            return left_v + fraction * (right_v - left_v)
    raise ValueError("SOC is outside OCV table")


def integrate_ocv_soc(points, low_soc, high_soc):
    """Exact integral of piecewise-linear OCV(SOC) over [low_soc, high_soc]."""
    require(0.0 <= low_soc <= high_soc <= 1.0, "invalid OCV integral interval")
    area = 0.0
    for index in range(0, len(points) - 2, 2):
        left_soc, left_v, right_soc, right_v = points[index:index + 4]
        start = max(low_soc, left_soc)
        end = min(high_soc, right_soc)
        if end <= start:
            continue
        slope = (right_v - left_v) / (right_soc - left_soc)
        v_start = left_v + (start - left_soc) * slope
        v_end = left_v + (end - left_soc) * slope
        area += (end - start) * (v_start + v_end) * 0.5
    return area


def electrical_row(row, config, capacity_c, initial_charge_c, tick):
    motor = config["motor"]
    pack = config["battery"]
    kv = motor["kv_rpm_per_volt"]
    motor_r = motor["resistance_ohm"]
    no_load_a = motor["no_load_current_a"]
    pack_r = pack["resistance_ohm"]
    auxiliary_a = pack["auxiliary_current_a"]
    remaining = row["remaining_charge_c"]
    soc = row["battery_soc"]
    rpm = row["engine_rpm"]
    duty = row["drive_duty"]
    enabled = row["drive_enabled"]
    exhausted = row["pack_exhausted"]
    require(rpm >= 0.0 and 0.0 <= duty <= 1.0 and enabled in (0.0, 1.0), "invalid operating domain")
    require(exhausted in (0.0, 1.0), "pack_exhausted must be boolean-valued")
    close(duty, row["cmd_throttle"] if enabled else 0.0, 2e-9, "duty plane")

    require(0.0 <= remaining <= initial_charge_c + CHARGE_LEDGER_TOL_C, "remaining charge outside pack budget")
    require(0.0 <= soc <= 1.0, "SOC outside [0,1]")
    require(row["consumed_charge_c"] >= 0.0, "negative consumed charge")
    require(abs(remaining + row["consumed_charge_c"] - initial_charge_c) <= CHARGE_LEDGER_TOL_C,
            "charge ledger does not conserve configured initial charge")
    close(soc, remaining / capacity_c, 1e-9, "SOC from remaining charge")
    close(exhausted, 1.0 if remaining == 0.0 else 0.0, 0.0, "exhaustion boundary")

    expected_ocv = ocv_at(pack["ocv_points"], soc)
    close(row["ocv_v"], expected_ocv, VOLTAGE_TOL_V, "OCV interpolation")
    if exhausted:
        require(row["pack_current_a"] == 0.0 and row["auxiliary_current_a"] == 0.0
                and row["drive_bus_current_a"] == 0.0 and row["bus_voltage_v"] == 0.0,
                "exhausted pack did not disconnect every load")
        expected_motor_current = 0.0
        expected_bus = 0.0
        expected_pack_current = 0.0
    else:
        close(row["auxiliary_current_a"], auxiliary_a, CURRENT_TOL_A, "prescribed auxiliary draw")
        emf = rpm / kv
        bus_without_motor = expected_ocv - pack_r * auxiliary_a
        denominator = motor_r + duty * duty * pack_r
        numerator = duty * bus_without_motor - emf
        expected_motor_current = max(numerator / denominator, 0.0) if duty > 0.0 and numerator > 0.0 else 0.0
        expected_drive_current = duty * expected_motor_current
        expected_pack_current = expected_drive_current + auxiliary_a
        expected_bus = expected_ocv - pack_r * expected_pack_current
        require(expected_bus > 0.0, "independently reconstructed battery bus is not positive")
        close(row["drive_bus_current_a"], expected_drive_current, CURRENT_TOL_A, "duty-squared drive current")
        close(row["pack_current_a"], expected_pack_current, CURRENT_TOL_A, "pack current including auxiliary draw")
        close(row["bus_voltage_v"], expected_bus, VOLTAGE_TOL_V, "resistive bus sag")

    close(row["motor_current_a"], expected_motor_current, CURRENT_TOL_A, "motor current")
    kt = 60.0 / (2.0 * math.pi * kv)
    omega = rpm * (2.0 * math.pi / 60.0)
    torque = kt * (expected_motor_current - no_load_a)
    if rpm == 0.0:
        torque = max(torque, 0.0)
    close(row["source_torque_nm"], torque, TORQUE_TOL_NM, "motor torque")
    close(row["shaft_power_w"], torque * omega, POWER_TOL_W, "shaft power")
    close(row["copper_loss_w"], expected_motor_current ** 2 * motor_r, POWER_TOL_W, "motor copper loss")
    close(row["rotational_loss_w"], kt * no_load_a * omega, POWER_TOL_W, "rotational loss")
    drive_power = row["bus_voltage_v"] * row["drive_bus_current_a"]
    motor_power = row["shaft_power_w"] + row["copper_loss_w"] + row["rotational_loss_w"]
    close(drive_power, motor_power, POWER_TOL_W, "drive port power balance")

    close(row["pack_terminal_power_w"], row["bus_voltage_v"] * expected_pack_current,
          POWER_TOL_W, "pack terminal power")
    expected_loss = pack_r * expected_pack_current ** 2
    close(row["pack_loss_w"], expected_loss, POWER_TOL_W, "pack I²R loss")
    close(expected_ocv * expected_pack_current,
          row["pack_terminal_power_w"] + row["pack_loss_w"], POWER_TOL_W, "pack power balance")

    ocv_energy_j = capacity_c * integrate_ocv_soc(pack["ocv_points"], soc, pack["initial_soc"])
    stored_energy_j = row["terminal_energy_j"] + row["pack_heat_j"]
    require(row["terminal_energy_j"] >= 0.0 and row["pack_heat_j"] >= 0.0,
            "negative terminal energy or pack heat")
    close(stored_energy_j, ocv_energy_j, ENERGY_LEDGER_TOL_J, "OCV charge/energy ledger")
    if tick > 0:
        require(row["remaining_charge_c"] <= initial_charge_c + CHARGE_LEDGER_TOL_C,
                "charge increased above initial budget")
    return {
        "power_balance_residual_w": abs(drive_power - motor_power),
        "pack_power_residual_w": abs(expected_ocv * expected_pack_current - row["pack_terminal_power_w"] - row["pack_loss_w"]),
        "energy_ledger_residual_j": abs(stored_energy_j - ocv_energy_j),
    }


def flight_checks(scenario, rows):
    delta_alt = rows[-1]["alt_m"] - rows[0]["alt_m"]
    altitude_deviation = max(abs(row["alt_m"] - rows[0]["alt_m"]) for row in rows)
    heading_change = sum((b["yaw_deg"] - a["yaw_deg"] + 180.0) % 360.0 - 180.0
                         for a, b in zip(rows, rows[1:]))
    if scenario == "level":
        require(altitude_deviation <= LEVEL_ALTITUDE_BAND_M,
                f"level battery flight exceeded predeclared ±{LEVEL_ALTITUDE_BAND_M:g} m band ({altitude_deviation:.3f} m)")
    elif scenario == "climb":
        require(delta_alt > 30.0, "climb did not gain more than 30 m")
    elif scenario == "turn":
        require(heading_change > 180.0 and 15.0 < rows[-1]["roll_deg"] < 30.0,
                "turn did not exceed 180 degrees with a stable commanded bank")
    else:
        chopped = rows[1201:3601]
        require(chopped and all(row["drive_bus_current_a"] == 0.0 and row["motor_current_a"] == 0.0
                                for row in chopped), "motor drew current during the 5–15 s throttle chop")
        require(all(row["auxiliary_current_a"] > 0.0 and row["pack_current_a"] == row["auxiliary_current_a"]
                    for row in chopped), "auxiliary pack draw was not retained during throttle chop")
        require(rows[4800]["drive_bus_current_a"] > 0.0, "duty restoration failed after throttle chop")
    return {
        "altitude_change_m": delta_alt,
        "max_abs_altitude_deviation_m": altitude_deviation,
        "heading_change_deg": heading_change,
        "min_altitude_m": min(row["alt_m"] for row in rows),
        "final_speed_mps": rows[-1]["speed_mps"],
    }


def check_negative_controls(rows, config):
    source = rows[0]
    pack = config["battery"]
    capacity_c = 3600.0 * pack["capacity_ah"]
    initial_c = capacity_c * pack["initial_soc"]
    mutations = {
        "finite_ocv": ("ocv_v", source["ocv_v"] + 0.5),
        "finite_sag": ("bus_voltage_v", source["bus_voltage_v"] + 0.25),
        "finite_current": ("pack_current_a", source["pack_current_a"] + 0.1),
        "finite_heat": ("pack_heat_j", source["pack_heat_j"] + 0.5),
        "finite_soc": ("battery_soc", source["battery_soc"] - 0.02),
        "finite_charge_ledger": ("consumed_charge_c", source["consumed_charge_c"] + 1.0),
    }
    rejected = {}
    for name, (key, value) in mutations.items():
        bad = copy.deepcopy(source)
        bad[key] = value
        require(math.isfinite(bad[key]), f"negative-control mutation {name} is not finite")
        try:
            electrical_row(bad, config, capacity_c, initial_c, 0)
        except ValueError:
            rejected[name] = True
        else:
            raise ValueError(f"independent verifier accepted corrupted {name}")
    return rejected


def convergence_diagnostic(values):
    ordered = [values[str(rate)] for rate in (120, 240, 480, 960)]
    if all(a > b for a, b in zip(ordered, ordered[1:])):
        return "decreasing"
    if max(ordered) <= 1e-12:
        return "machine-precision plateau"
    if max(ordered[-2:]) <= 1e-12:
        return "machine-precision plateau at fine rates"
    return "nonmonotone or plateau observed; tolerances remain the acceptance gate"


def verify_refinement(directory):
    path = directory / "refinement.json"
    payload = json.loads(path.read_text())
    cases = payload.get("cases")
    require(isinstance(cases, dict) and len(cases) == 10, "refinement output must contain exactly 10 cases")
    report = {}
    for config in ("4s_battery", "6s_battery"):
        reference = cases.get(f"{config}-1920")
        require(isinstance(reference, dict) and reference.get("ok") is True,
                f"missing successful 1920 Hz reference for {config}")
        body_ref = reference.get("body")
        continuous_ref = reference.get("continuous")
        require(isinstance(body_ref, list) and len(body_ref) == 13, f"{config} body state must have 13 entries")
        require(isinstance(continuous_ref, list) and len(continuous_ref) == 4,
                f"{config} battery continuous state must be [rpm, charge, energy, heat]")
        require(all(isinstance(v, (int, float)) and math.isfinite(float(v)) for v in body_ref + continuous_ref),
                f"{config} reference contains nonfinite state")
        errors = {}
        for rate in (120, 240, 480, 960, 1920):
            current = cases.get(f"{config}-{rate}")
            require(isinstance(current, dict) and current.get("ok") is True,
                    f"missing successful {rate} Hz refinement for {config}")
            body = current.get("body")
            continuous = current.get("continuous")
            require(isinstance(body, list) and len(body) == 13, f"{config}-{rate} body state must have 13 entries")
            require(isinstance(continuous, list) and len(continuous) == 4,
                    f"{config}-{rate} battery continuous state must have four entries")
            require(all(isinstance(v, (int, float)) and math.isfinite(float(v)) for v in body + continuous),
                    f"{config}-{rate} contains nonfinite state")
            body_groups = {}
            for name, (start, end, limit) in BODY_LIMITS.items():
                error = max(abs(float(body[i]) - float(body_ref[i])) for i in range(start, end))
                require(error < limit, f"{config}-{rate} body refinement exceeded {name} tolerance")
                body_groups[name] = error
            continuous_errors = {}
            for name, (index, limit) in CONTINUOUS_LIMITS.items():
                error = abs(float(continuous[index]) - float(continuous_ref[index]))
                require(error < limit, f"{config}-{rate} refinement exceeded {name} tolerance ({error:.4g} > {limit:g})")
                continuous_errors[name] = error
            errors[str(rate)] = {
                "body_max_absolute": max(body_groups.values()),
                "body_components": body_groups,
                "continuous_components": continuous_errors,
            }
        require(errors["240"]["body_max_absolute"] < errors["120"]["body_max_absolute"] and
                errors["480"]["body_max_absolute"] < errors["240"]["body_max_absolute"],
                f"{config} body refinement did not converge at coarse rates")
        report[config] = {
            "limits": {
                "position_m": 2e-6, "velocity_mps": 2e-6, "quaternion": 2e-7,
                "body_rate_radps": 2e-6, "shaft_rpm": 1e-4, "remaining_charge_c": 2e-7,
                "terminal_energy_j": 2e-5, "pack_heat_j": 2e-6,
            },
            "errors": errors,
            "body_convergence": convergence_diagnostic({k: v["body_max_absolute"] for k, v in errors.items()}),
            "charge_convergence": convergence_diagnostic({k: v["continuous_components"]["remaining_charge_c"] for k, v in errors.items()}),
            "energy_convergence": convergence_diagnostic({k: v["continuous_components"]["terminal_energy_j"] for k, v in errors.items()}),
            "heat_convergence": convergence_diagnostic({k: v["continuous_components"]["pack_heat_j"] for k, v in errors.items()}),
        }
    return report


def find_probe(app_path):
    candidates = [
        app_path.resolve().parent / "research/propulsion/el1/flight_probe.gd",
        Path.cwd() / "research/propulsion/el1/flight_probe.gd",
        ROOT / "research/propulsion/el1/flight_probe.gd",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise ValueError("cannot find the extended absolute research/propulsion/el1/flight_probe.gd")


def run_probe(godot, app_path, output, mode, expected_cases):
    probe = find_probe(app_path)
    command = [str(godot.resolve()), "--headless", "--path", str(app_path.resolve()), "--script", str(probe),
               "--", mode, str(output.resolve()), "battery"]
    run = subprocess.run(command, text=True, capture_output=True, timeout=900)
    log = run.stdout + run.stderr
    (output / f"{mode}.log").write_text(log)
    marker = f"EL1 session probe: {expected_cases} cases, 0 failed"
    require(run.returncode == 0 and not re.search(r"^(?:SCRIPT )?ERROR:|^FAIL", log, re.M) and marker in log,
            f"Godot {mode} probe did not complete with exact marker {marker!r}; see {mode}.log")


def verify(app_path, directory):
    report = {
        "format": "openrc-electric-battery-flight-verification v1",
        "evidence_scope": "software-only verification using synthetic authored fixtures; not measured battery or physical-flight validation",
        "level_altitude_band_m": LEVEL_ALTITUDE_BAND_M,
        "flights": {},
        "refinement": {},
        "negative_controls": 0,
        "negative_control_types": {},
    }
    for config_name in ("4s_battery", "6s_battery"):
        data_path = app_path / "data/aircraft" / f"synthetic_stik_electric_{config_name}.json"
        require(data_path.is_file(), f"missing synthetic battery fixture: {data_path}")
        for scenario in ("level", "turn", "climb", "chop"):
            path = directory / f"{config_name}-{scenario}.csv"
            metadata, rows, config = parse_trace(path, data_path)
            results = flight_checks(scenario, rows)
            residuals = [electrical_row(row, config, 3600.0 * config["battery"]["capacity_ah"],
                                        3600.0 * config["battery"]["capacity_ah"] * config["battery"]["initial_soc"], tick)
                         for tick, row in enumerate(rows)]
            report["flights"][f"{config_name}-{scenario}"] = {
                "trace_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "aircraft_input_sha256": metadata["aircraft_input_sha256"],
                "rows": len(rows),
                **results,
                "initial_soc": rows[0]["battery_soc"],
                "final_soc": rows[-1]["battery_soc"],
                "soc_drop": rows[0]["battery_soc"] - rows[-1]["battery_soc"],
                "max_rpm": max(row["engine_rpm"] for row in rows),
                "min_ocv_v": min(row["ocv_v"] for row in rows),
                "max_pack_current_a": max(row["pack_current_a"] for row in rows),
                "max_pack_power_residual_w": max(item["pack_power_residual_w"] for item in residuals),
                "max_drive_power_residual_w": max(item["power_balance_residual_w"] for item in residuals),
                "max_energy_ledger_residual_j": max(item["energy_ledger_residual_j"] for item in residuals),
            }
            rejected_controls = check_negative_controls(rows, config)
            report["negative_controls"] += len(rejected_controls)
            for name in rejected_controls:
                report["negative_control_types"][name] = report["negative_control_types"].get(name, 0) + 1
    report["refinement"] = verify_refinement(directory)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "app", help="Godot app directory (default: repository app)")
    parser.add_argument("--godot", type=Path, help="pinned Godot binary; required unless --reuse")
    parser.add_argument("--directory", type=Path, required=True, help="trace/probe output directory")
    parser.add_argument("--reuse", action="store_true", help="verify existing staged traces and refinement output")
    args = parser.parse_args()
    app_path = args.app.resolve()
    output = args.directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if not args.reuse:
        require(args.godot is not None, "--godot is required unless --reuse is set")
        godot = args.godot.resolve()
        require(godot.is_file(), f"Godot executable does not exist: {godot}")
        run_probe(godot, app_path, output, "flight", 8)
        run_probe(godot, app_path, output, "refinement", 10)
    result = verify(app_path, output)
    (output / "verified.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"EL2 battery flights: {len(result['flights'])} flights, 2 refinement sweeps, "
          f"{result['negative_controls']} finite corruption controls passed")


if __name__ == "__main__":
    main()
