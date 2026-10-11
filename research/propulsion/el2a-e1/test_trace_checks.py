"""Offline regression tests for the EL2a-E1 v8 trace verifier."""
from __future__ import annotations

import hashlib
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import trace_checks  # noqa: E402


ROOT = Path(__file__).resolve().parents[3]
FIXTURES = {
    "4s": ROOT / "app/data/aircraft/synthetic_stik_electric_4s_battery.json",
    "6s": ROOT / "app/data/aircraft/synthetic_stik_electric_6s_battery.json",
}


def normalized_configuration(raw: dict[str, Any]) -> dict[str, Any]:
    source = raw["propulsion"]
    battery = source["battery"]
    return {
        "motor": {
            key: source["motor"][key]["value"]
            for key in ("kv_rpm_per_volt", "resistance_ohm", "no_load_current_a")
        },
        "battery": {
            "kind": "ocv_resistance",
            "capacity_ah": battery["capacity_ah"]["value"],
            "resistance_ohm": battery["resistance_ohm"]["value"],
            "auxiliary_current_a": battery["auxiliary_current_a"]["value"],
            "initial_soc": battery["initial_soc"]["value"],
            "ocv_points": [
                value
                for point in battery["ocv_points"]
                for value in (point["soc"]["value"], point["voltage"]["value"])
            ],
        },
        "esc": {"kind": "ideal_motoring", "command_mapping": "identity"},
    }


def make_trace(path: Path, pack_name: str = "4s", hz: int = 480, ticks: int = 3,
               mutate: Callable[[dict[str, str], list[dict[str, float]]], None] | None = None) -> Path:
    data_path = FIXTURES[pack_name]
    raw = trace_checks.EL2.read_fixture(data_path)
    config = normalized_configuration(raw)
    battery = config["battery"]
    capacity_c = 3600.0 * battery["capacity_ah"]
    initial_charge_c = capacity_c * battery["initial_soc"]
    auxiliary_a = battery["auxiliary_current_a"]
    pack_r = battery["resistance_ohm"]
    points = battery["ocv_points"]

    metadata = {
        "format": "openrc-trace v8",
        "propulsion_model": trace_checks.EL2.BATTERY_LAW,
        "electric_sample_timing": trace_checks.EL2.TIMING,
        "shaft_integrator": "coupled-rk4",
        "continuous_layout": trace_checks.EL2.BATTERY_LAYOUT,
        "battery_model": "balanced-pack-ocv-resistance-no-regeneration-v1",
        "battery_exhaustion": "remaining charge zero; all pack loads disconnected; bearing loss retained; not ESC LVC",
        "battery_charge": "remaining coulombs integrated; SOC and consumed charge derived; terminal energy and pack heat integrated",
        "battery_auxiliary": "prescribed pack-side current; no receiver/servo brownout or assistance model",
        "aircraft_input_sha256": hashlib.sha256(data_path.read_bytes()).hexdigest(),
        "aircraft_input_hash_convention": "sha256 of exact aircraft input file bytes",
        "electric_configuration": json.dumps(config, separators=(",", ":")),
        "recording_start_continuous": json.dumps([0.0, initial_charge_c, 0.0, 0.0]),
        "recording_start_aux": json.dumps([0.0, 0.0, 0.0, 0.0]),
        "recording_start_tick": "0",
        "launch_engine_running": "true",
        "dt_s": repr(1.0 / hz),
        "el2a_e1_pack": pack_name,
        "el2a_e1_maneuver": "takeoff",
        "el2a_e1_simulation_hz": str(hz),
        "el2a_e1_planned_duration_s": repr(ticks / hz),
        "el2a_e1_pilot": "offline deterministic fixture",
        "launch_choice": "runway",
    }

    rows: list[dict[str, float]] = []
    for tick in range(ticks + 1):
        elapsed_s = tick / hz
        remaining = initial_charge_c - auxiliary_a * elapsed_s
        soc = remaining / capacity_c
        ocv = trace_checks.EL2.ocv_at(points, soc)
        pack_current = auxiliary_a
        bus_voltage = ocv - pack_r * pack_current
        pack_loss = pack_r * pack_current ** 2
        pack_heat = pack_loss * elapsed_s
        ocv_energy = capacity_c * trace_checks.EL2.integrate_ocv_soc(
            points, soc, battery["initial_soc"]
        )
        row = {column: 0.0 for column in trace_checks.REQUIRED_COLUMNS}
        row.update({
            "tick": float(tick),
            "t_s": elapsed_s,
            "alt_m": 0.0,
            "speed_mps": 0.0,
            "engine_rpm": 0.0,
            "cmd_throttle": 0.0,
            "drive_enabled": 1.0,
            "drive_duty": 0.0,
            "bus_voltage_v": bus_voltage,
            "motor_current_a": 0.0,
            "drive_bus_current_a": 0.0,
            "source_torque_nm": 0.0,
            "shaft_power_w": 0.0,
            "copper_loss_w": 0.0,
            "rotational_loss_w": 0.0,
            "battery_soc": soc,
            "remaining_charge_c": remaining,
            "consumed_charge_c": initial_charge_c - remaining,
            "pack_current_a": pack_current,
            "auxiliary_current_a": auxiliary_a,
            "ocv_v": ocv,
            "pack_terminal_power_w": bus_voltage * pack_current,
            "pack_loss_w": pack_loss,
            "terminal_energy_j": ocv_energy - pack_heat,
            "pack_heat_j": pack_heat,
            "pack_exhausted": 0.0,
        })
        rows.append(row)

    if mutate is not None:
        mutate(metadata, rows)

    columns = sorted(trace_checks.REQUIRED_COLUMNS)
    lines = [f"# {key}: {value}" for key, value in metadata.items()]
    lines.append(",".join(columns))
    for row in rows:
        lines.append(",".join(
            str(int(row[column])) if column == "tick" else f"{row[column]:.9f}"
            for column in columns
        ))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def set_nonzero_electrically_valid_start(metadata: dict[str, str],
                                         rows: list[dict[str, float]]) -> None:
    config = normalized_configuration(trace_checks.EL2.read_fixture(FIXTURES["4s"]))
    motor = config["motor"]
    rpm = 100.0
    kt = 60.0 / (2.0 * math.pi * motor["kv_rpm_per_volt"])
    omega = rpm * (2.0 * math.pi / 60.0)
    torque = kt * (0.0 - motor["no_load_current_a"])
    rows[0]["engine_rpm"] = rpm
    rows[0]["source_torque_nm"] = torque
    rows[0]["shaft_power_w"] = torque * omega
    rows[0]["rotational_loss_w"] = kt * motor["no_load_current_a"] * omega
    continuous = json.loads(metadata["recording_start_continuous"])
    auxiliary = json.loads(metadata["recording_start_aux"])
    continuous[0] = rpm
    auxiliary[0] = rpm
    metadata["recording_start_continuous"] = json.dumps(continuous)
    metadata["recording_start_aux"] = json.dumps(auxiliary)


def set_nonzero_electrically_valid_duty(metadata: dict[str, str],
                                         rows: list[dict[str, float]]) -> None:
    config = normalized_configuration(trace_checks.EL2.read_fixture(FIXTURES["4s"]))
    motor = config["motor"]
    battery = config["battery"]
    duty = 0.1
    pack_current_aux = battery["auxiliary_current_a"]
    pack_r = battery["resistance_ohm"]
    motor_r = motor["resistance_ohm"]
    kv = motor["kv_rpm_per_volt"]
    no_load_a = motor["no_load_current_a"]
    capacity_c = 3600.0 * battery["capacity_ah"]
    remaining = capacity_c * battery["initial_soc"]
    soc = remaining / capacity_c
    ocv = trace_checks.EL2.ocv_at(battery["ocv_points"], soc)
    bus_without_motor = ocv - pack_r * pack_current_aux
    denominator = motor_r + duty * duty * pack_r
    motor_current = max(duty * bus_without_motor / denominator, 0.0)
    drive_current = duty * motor_current
    pack_current = drive_current + pack_current_aux
    bus_voltage = ocv - pack_r * pack_current
    kt = 60.0 / (2.0 * math.pi * kv)
    torque = max(kt * (motor_current - no_load_a), 0.0)
    row = rows[0]
    row.update({
        "cmd_throttle": duty,
        "drive_duty": duty,
        "bus_voltage_v": bus_voltage,
        "motor_current_a": motor_current,
        "drive_bus_current_a": drive_current,
        "source_torque_nm": torque,
        "shaft_power_w": 0.0,
        "copper_loss_w": motor_current * motor_current * motor_r,
        "rotational_loss_w": 0.0,
        "pack_current_a": pack_current,
        "auxiliary_current_a": pack_current_aux,
        "ocv_v": ocv,
        "pack_terminal_power_w": bus_voltage * pack_current,
        "pack_loss_w": pack_r * pack_current * pack_current,
    })


def rewrite_trace(path: Path,
                  edit: Callable[[list[str], list[str], list[list[str]]], None]) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    header_index = next(index for index, line in enumerate(lines) if not line.startswith("# "))
    metadata = lines[:header_index]
    columns = lines[header_index].split(",")
    rows = [line.split(",") for line in lines[header_index + 1:]]
    edit(metadata, columns, rows)
    path.write_text("\n".join(metadata + [",".join(columns)] +
                             [",".join(row) for row in rows]) + "\n", encoding="utf-8")


class TraceChecksTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_accepts_variable_rate_duration_and_ground_rows_for_both_packs(self) -> None:
        for pack, hz, ticks in (("4s", 480, 3), ("6s", 240, 4)):
            with self.subTest(pack=pack, hz=hz):
                path = make_trace(self.directory / f"{pack}.csv", pack, hz, ticks)
                result = trace_checks.check_trace(path, FIXTURES[pack], ticks, hz)
                self.assertEqual(result["pack"], pack)
                self.assertEqual(result["hz"], hz)
                self.assertEqual(result["ticks"], ticks)
                self.assertEqual(result["rows"], ticks + 1)
                self.assertEqual(result["rows_at_or_below_10m"], ticks + 1)
                self.assertEqual(result["min_altitude_m"], 0.0)
                self.assertLessEqual(result["max_energy_ledger_residual_j"],
                                     trace_checks.EL2.ENERGY_LEDGER_TOL_J)

    def test_rejects_truncated_or_duplicate_samples(self) -> None:
        def truncate(_metadata: dict[str, str], rows: list[dict[str, float]]) -> None:
            rows.pop()

        def duplicate_tick(_metadata: dict[str, str], rows: list[dict[str, float]]) -> None:
            rows[1]["tick"] = 0.0

        for name, mutate in (("truncated", truncate), ("duplicate", duplicate_tick)):
            with self.subTest(name=name):
                path = make_trace(self.directory / f"{name}.csv", mutate=mutate)
                with self.assertRaises(ValueError):
                    trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)

    def test_rejects_a_simulation_time_gap(self) -> None:
        def gap(_metadata: dict[str, str], rows: list[dict[str, float]]) -> None:
            rows[1]["t_s"] += 0.0005

        path = make_trace(self.directory / "time-gap.csv", mutate=gap)
        with self.assertRaisesRegex(ValueError, "simulation-time gap"):
            trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)

    def test_rejects_fixture_hash_and_metadata_mismatches(self) -> None:
        def wrong_hash(metadata: dict[str, str], _rows: list[dict[str, float]]) -> None:
            metadata["aircraft_input_sha256"] = "0" * 64

        def wrong_hz(metadata: dict[str, str], _rows: list[dict[str, float]]) -> None:
            metadata["el2a_e1_simulation_hz"] = "240"

        for name, mutate in (("hash", wrong_hash), ("hz", wrong_hz)):
            with self.subTest(name=name):
                path = make_trace(self.directory / f"metadata-{name}.csv", mutate=mutate)
                with self.assertRaises(ValueError):
                    trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)

    def test_rejects_a_normalized_configuration_mismatch(self) -> None:
        def wrong_configuration(metadata: dict[str, str], _rows: list[dict[str, float]]) -> None:
            configuration = json.loads(metadata["electric_configuration"])
            configuration["battery"]["capacity_ah"] += 0.1
            metadata["electric_configuration"] = json.dumps(configuration)

        path = make_trace(self.directory / "configuration.csv", mutate=wrong_configuration)
        with self.assertRaisesRegex(ValueError, "normalized motor/battery/ESC metadata"):
            trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)

    def test_rejects_duplicate_metadata_and_columns(self) -> None:
        def duplicate_metadata(metadata: list[str], _columns: list[str],
                               _rows: list[list[str]]) -> None:
            metadata.append(metadata[0])

        def duplicate_column(_metadata: list[str], columns: list[str],
                             _rows: list[list[str]]) -> None:
            columns.append(columns[0])

        for name, edit in (("metadata", duplicate_metadata), ("column", duplicate_column)):
            with self.subTest(name=name):
                path = make_trace(self.directory / f"duplicate-{name}.csv")
                rewrite_trace(path, edit)
                with self.assertRaisesRegex(ValueError, "duplicate"):
                    trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)

    def test_rejects_missing_and_extra_csv_cells(self) -> None:
        def remove_cell(_metadata: list[str], _columns: list[str], rows: list[list[str]]) -> None:
            rows[0].pop()

        def add_cell(_metadata: list[str], _columns: list[str], rows: list[list[str]]) -> None:
            rows[0].append("0")

        for name, edit in (("missing", remove_cell), ("extra", add_cell)):
            with self.subTest(name=name):
                path = make_trace(self.directory / f"{name}-cell.csv")
                rewrite_trace(path, edit)
                with self.assertRaisesRegex(ValueError, "expected .* cells, found"):
                    trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)

    def test_rejects_nan_infinity_and_numeric_overflow(self) -> None:
        for name, value in (("nan", "nan"), ("infinity", "inf"), ("overflow", "1e999")):
            with self.subTest(value=name):
                path = make_trace(self.directory / f"{name}.csv")

                def set_nonfinite(_metadata: list[str], columns: list[str],
                                  rows: list[list[str]]) -> None:
                    rows[0][columns.index("speed_mps")] = value

                rewrite_trace(path, set_nonfinite)
                with self.assertRaisesRegex(ValueError, "nonfinite"):
                    trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)

    def test_rejects_invalid_drive_domain_and_energy(self) -> None:
        def bad_drive(_metadata: list[str], columns: list[str], rows: list[list[str]]) -> None:
            rows[0][columns.index("drive_enabled")] = "2"

        def bad_energy(_metadata: list[str], columns: list[str], rows: list[list[str]]) -> None:
            rows[0][columns.index("terminal_energy_j")] = "-1"

        for name, edit in (("drive", bad_drive), ("energy", bad_energy)):
            with self.subTest(name=name):
                path = make_trace(self.directory / f"invalid-{name}.csv")
                rewrite_trace(path, edit)
                with self.assertRaises(ValueError):
                    trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)

    def test_rejects_boolean_and_extra_start_continuous_values(self) -> None:
        def boolean_start(metadata: dict[str, str], _rows: list[dict[str, float]]) -> None:
            values = json.loads(metadata["recording_start_continuous"])
            values[0] = True
            metadata["recording_start_continuous"] = json.dumps(values)

        def boolean_auxiliary(metadata: dict[str, str], _rows: list[dict[str, float]]) -> None:
            values = json.loads(metadata["recording_start_aux"])
            values[1] = False
            metadata["recording_start_aux"] = json.dumps(values)

        def extra_start(metadata: dict[str, str], _rows: list[dict[str, float]]) -> None:
            values = json.loads(metadata["recording_start_continuous"])
            values.append(0.0)
            metadata["recording_start_continuous"] = json.dumps(values)

        for name, mutate in (("continuous-boolean", boolean_start),
                             ("auxiliary-boolean", boolean_auxiliary),
                             ("extra", extra_start)):
            with self.subTest(name=name):
                path = make_trace(self.directory / f"start-{name}.csv", mutate=mutate)
                with self.assertRaises(ValueError):
                    trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)

    def test_rejects_complete_runway_traces_with_nonzero_initial_rpm_or_duty(self) -> None:
        for name, mutate, message in (
            ("rpm", set_nonzero_electrically_valid_start, "propeller shaft stopped"),
            ("duty", set_nonzero_electrically_valid_duty, "zero motor duty and throttle"),
        ):
            with self.subTest(initial_state=name):
                path = make_trace(self.directory / f"4s_takeoff_{name}_480.csv", mutate=mutate)
                metadata, rows = trace_checks._parse_trace(path)
                raw = trace_checks.EL2.read_fixture(FIXTURES["4s"])
                config = trace_checks.EL2.normalized_configuration(metadata, raw, FIXTURES["4s"])
                capacity_c = 3600.0 * config["battery"]["capacity_ah"]
                initial_charge_c = capacity_c * config["battery"]["initial_soc"]
                trace_checks.EL2.electrical_row(rows[0], config, capacity_c, initial_charge_c, 0)
                self.assertEqual(len(rows), 4)
                with self.assertRaisesRegex(ValueError, message):
                    trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)

    def test_rejects_electrical_corruption_and_start_mirror_mismatch(self) -> None:
        def corrupt_bus(_metadata: dict[str, str], rows: list[dict[str, float]]) -> None:
            rows[0]["bus_voltage_v"] += 0.25

        def corrupt_start(metadata: dict[str, str], _rows: list[dict[str, float]]) -> None:
            metadata["recording_start_continuous"] = json.dumps([1.0, 10944.0, 0.0, 0.0])

        for name, mutate in (("bus", corrupt_bus), ("start", corrupt_start)):
            with self.subTest(name=name):
                path = make_trace(self.directory / f"corrupt-{name}.csv", mutate=mutate)
                with self.assertRaises(ValueError):
                    trace_checks.check_trace(path, FIXTURES["4s"], 3, 480)


if __name__ == "__main__":
    unittest.main()
