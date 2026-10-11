#!/usr/bin/env python3
"""EL1d/e: strict v7 reader, independent electrical arithmetic and session refinement.

Only software verification. Nine-decimal CSV quantization is included in tolerances.
Never reconstruct combustion power or claim measured Timber performance from these traces.
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
LAW = "electric-fixed-bus-coupled-stop-v1"
TIMING = "accepted endpoint; current tick input and source-enabled mode"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_trace(path, data):
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
    require(metadata["format"] == "openrc-trace v7", "expected versioned electric trace")
    require(metadata["propulsion_model"] == LAW, "wrong source law")
    require(metadata["electric_sample_timing"] == TIMING, "ambiguous sample time")
    require(metadata["shaft_integrator"] == "coupled-rk4", "wrong integrator")
    require(metadata["aircraft_input_sha256"] == hashlib.sha256(data.read_bytes()).hexdigest(), "wrong input SHA")
    raw = json.loads(data.read_text())["propulsion"]
    require(raw["kind"] == "electric_prop", "not an electric dataset")
    config = json.loads(metadata["electric_configuration"])
    require(config["motor"] == {k: raw["motor"][k]["value"] for k in
            ("kv_rpm_per_volt", "resistance_ohm", "no_load_current_a")}, "motor metadata mismatch")
    require(config["battery"] == {"kind": "fixed_voltage", "voltage_v": raw["battery"]["voltage_v"]["value"]}, "bus metadata mismatch")
    require(config["esc"] == {"kind": "ideal_motoring", "command_mapping": "identity"}, "ESC metadata mismatch")
    reader = csv.DictReader(io.StringIO("\n".join(body)))
    require(len(reader.fieldnames) == len(set(reader.fieldnames)), "duplicate column")
    rows = [{key: float(value) for key, value in row.items()} for row in reader]
    require(len(rows) == 7201, "incomplete 30-second flight")
    for tick, row in enumerate(rows):
        require(all(math.isfinite(v) for v in row.values()), "nonfinite trace")
        require(row["tick"] == tick and abs(row["t_s"] - tick / 240) < 1e-9, "wrong tick/time")
        require(row["alt_m"] > 10.0, "flight reached ground")
        electrical_row(row, config)
    return metadata, rows, config


def electrical_row(row, config):
    m = config["motor"]
    voltage = config["battery"]["voltage_v"]
    rpm, duty, enabled = row["engine_rpm"], row["drive_duty"], row["drive_enabled"]
    require(rpm >= 0 and 0 <= duty <= 1 and enabled in (0, 1), "invalid operating domain")
    require(abs(row["bus_voltage_v"] - voltage) < 1e-9, "wrong bus voltage")
    require(abs(duty - (row["cmd_throttle"] if enabled else 0.0)) < 1e-9, "wrong duty plane")
    current = max((duty * voltage - rpm / m["kv_rpm_per_volt"]) / m["resistance_ohm"], 0) if duty else 0.0
    kt = 60 / (2 * math.pi * m["kv_rpm_per_volt"])
    omega = rpm * 2 * math.pi / 60
    torque = kt * (current - m["no_load_current_a"])
    if rpm == 0:
        torque = max(torque, 0)
    expected = {"motor_current_a": current, "drive_bus_current_a": duty * current,
                "source_torque_nm": torque, "shaft_power_w": torque * omega,
                "copper_loss_w": current ** 2 * m["resistance_ohm"],
                "rotational_loss_w": kt * m["no_load_current_a"] * omega}
    for key, value in expected.items():
        require(abs(row[key] - value) < (2e-6 if key.endswith("_a") else 1e-5), f"electrical mismatch: {key}")
    residual = voltage * row["drive_bus_current_a"] - sum(row[k] for k in
               ("shaft_power_w", "copper_loss_w", "rotational_loss_w"))
    require(abs(residual) < 1e-6, "port power does not balance")
    return residual


def verify(directory):
    report = {"format": "openrc-electric-flight-verification v1", "flights": {}, "refinement": {}, "negative_controls": 0}
    for config in ("4s", "6s"):
        data = ROOT / f"app/data/aircraft/synthetic_stik_electric_{config}.json"
        for scenario in ("level", "turn", "climb", "chop"):
            path = directory / f"{config}-{scenario}.csv"
            metadata, rows, definition = read_trace(path, data)
            delta_alt = rows[-1]["alt_m"] - rows[0]["alt_m"]
            turn = sum((b["yaw_deg"] - a["yaw_deg"] + 180) % 360 - 180 for a, b in zip(rows, rows[1:]))
            if scenario == "level":
                require(abs(delta_alt) < 1e-4 and abs(rows[-1]["speed_mps"] - 15) < 1e-4, "level trim drift")
            elif scenario == "climb":
                require(delta_alt > 30, "climb did not gain height")
            elif scenario == "turn":
                require(turn > 180 and 15 < rows[-1]["roll_deg"] < 30, "turn did not turn")
            else:
                # Inputs at the left endpoint produce the next accepted row's telemetry.
                require(all(r["drive_bus_current_a"] == 0 for r in rows[1201:3601]), "chop draws motor current")
                require(rows[4800]["drive_bus_current_a"] > 0, "duty restoration failed")
            report["flights"][f"{config}-{scenario}"] = {
                "trace_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "aircraft_input_sha256": metadata["aircraft_input_sha256"], "rows": len(rows),
                "altitude_change_m": delta_alt, "heading_change_deg": turn,
                "min_rpm": min(r["engine_rpm"] for r in rows),
                "max_current_a": max(r["motor_current_a"] for r in rows),
                "max_power_residual_w": max(abs(electrical_row(r, definition)) for r in rows)}
            for key, value in (("motor_current_a", rows[0]["motor_current_a"] + 0.1),
                               ("drive_enabled", 0.5), ("engine_rpm", -1.0),
                               ("bus_voltage_v", float("nan"))):
                bad = copy.deepcopy(rows[0])
                bad[key] = value
                try:
                    electrical_row(bad, definition)
                except ValueError:
                    report["negative_controls"] += 1
                else:
                    raise ValueError("reader accepted corrupted " + key)
    refined = json.loads((directory / "refinement.json").read_text())["cases"]
    for config in ("4s", "6s"):
        ref = refined[f"{config}-1920"]
        errors = {}
        for rate in (120, 240, 480, 960):
            at = refined[f"{config}-{rate}"]
            require(at["ok"] and ref["ok"], "refinement did not finish")
            body = max(abs(a - b) for a, b in zip(at["body"], ref["body"]))
            rpm = abs(at["rpm"] - ref["rpm"])
            groups = {}
            for name, start, end, limit in (("position_m", 0, 3, 2e-6), ("velocity_mps", 3, 6, 2e-6),
                                            ("quaternion", 6, 10, 2e-7), ("body_rate_radps", 10, 13, 2e-6)):
                groups[name] = max(abs(at["body"][i] - ref["body"][i]) for i in range(start, end))
                require(groups[name] < limit, "refinement exceeded declared " + name + " tolerance")
            require(rpm < 1e-4, "RPM refinement exceeded declared endpoint tolerance")
            errors[str(rate)] = {"body_max_absolute": body, "components": groups, "rpm_absolute": rpm}
        require(errors["240"]["body_max_absolute"] < errors["120"]["body_max_absolute"] and
                errors["480"]["body_max_absolute"] < errors["240"]["body_max_absolute"], "body refinement did not converge")
        report["refinement"][config] = errors
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--reuse", action="store_true", help="verify already generated traces")
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    if not args.reuse:
        require(args.godot is not None, "--godot required unless --reuse")
        for mode, expected in (("flight", 8), ("refinement", 10)):
            run = subprocess.run([str(args.godot.resolve()), "--headless", "--path", str(ROOT / "app"),
                                  "--script", str(Path(__file__).with_name("flight_probe.gd")), "--", mode,
                                  str(args.directory.resolve())], text=True, capture_output=True, timeout=360)
            log = run.stdout + run.stderr
            (args.directory / f"{mode}.log").write_text(log)
            require(run.returncode == 0 and not re.search(r"^(?:SCRIPT )?ERROR:|^FAIL", log, re.M) and
                    f"EL1 session probe: {expected} cases, 0 failed" in log, "Godot probe incomplete: " + mode)
    result = verify(args.directory)
    (args.directory / "verified.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"EL1 flights: {len(result['flights'])} flights, 2 refinement sweeps, {result['negative_controls']} negative controls passed")


if __name__ == "__main__":
    main()
