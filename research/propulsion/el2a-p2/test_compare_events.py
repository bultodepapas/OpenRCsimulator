"""Regression tests for the EL2a-P2 event-comparison report contract."""
from __future__ import annotations

import copy
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compare_events  # noqa: E402


TICK_HZ = 240
POST_EVENT_TICKS = 8
FULL_CONTRACT = {
    "battery-powered-4s": ("battery", ["battery_exhausted"], 3 * TICK_HZ),
    "battery-coast-4s": ("battery", ["battery_exhausted"], 3 * TICK_HZ),
    "battery-powered-6s": ("battery", ["battery_exhausted"], 3 * TICK_HZ),
    "battery-coast-6s": ("battery", ["battery_exhausted"], 3 * TICK_HZ),
    "fixed-voltage-rotor-stop": ("fixed_voltage", ["rotor_stop"], 20 * TICK_HZ),
    "battery-no-event-4s": ("no_event", [], TICK_HZ),
}
SMOKE_CONTRACT = {
    "battery-powered-smoke-4s": ("battery", ["battery_exhausted"], int(0.05 * TICK_HZ)),
}


def make_event(event_type: str, tick: int) -> dict[str, Any]:
    is_battery = event_type == "battery_exhausted"
    return {
        "type": event_type,
        "tick": tick,
        "containing_tick_time_s": tick / TICK_HZ,
        "event_tick_wall_usec": 1000,
        "body_state": [0.0] * 13,
        "continuous_state": [900.0, 0.0, 3.0, 0.5] if is_battery else [0.0],
        "rotor_index": 0,
        "charge_index": 1 if is_battery else -1,
        "rotor_rpm": 900.0 if is_battery else 0.0,
        "remaining_charge_c": 0.0 if is_battery else -1.0,
        "terminal_energy_j": 3.0 if is_battery else 0.0,
        "pack_heat_j": 0.5 if is_battery else 0.0,
    }


def make_row(case_id: str, contract: tuple[str, list[str], int], smoke: bool) -> dict[str, Any]:
    mode, required_events, max_ticks = contract
    event_type = required_events[0] if required_events else ""
    event_tick = 1 if smoke else (300 if event_type == "rotor_stop" else 24)
    ticks = min(max_ticks, event_tick + POST_EVENT_TICKS) if required_events else max_ticks
    events = [make_event(event_type, event_tick)] if required_events else []
    if case_id == "battery-powered-4s":
        initial_charge, engine_running, throttle = 4.0, True, 1.0
    elif case_id == "battery-coast-4s":
        initial_charge, engine_running, throttle = 0.25, False, 0.0
    elif case_id == "battery-powered-6s":
        initial_charge, engine_running, throttle = 2.4, True, 1.0
    elif case_id == "battery-coast-6s":
        initial_charge, engine_running, throttle = 0.25, False, 0.0
    elif case_id == "fixed-voltage-rotor-stop":
        initial_charge, engine_running, throttle = -1.0, True, 1.0
    elif case_id == "battery-powered-smoke-4s":
        initial_charge, engine_running, throttle = 0.2, True, 1.0
    else:
        initial_charge, engine_running, throttle = 10944.0, True, 0.5

    final_charge = -1.0 if mode == "fixed_voltage" else (
        0.0 if required_events and "battery_exhausted" in required_events else max(initial_charge, 1.0)
    )
    return {
        "id": case_id,
        "ok": True,
        "mode": mode,
        "events": events,
        "event_types": [event["type"] for event in events],
        "required_events": required_events.copy(),
        "tick_hz": TICK_HZ,
        "ticks": ticks,
        "end_time_s": ticks / TICK_HZ,
        "initial_charge_c": initial_charge,
        "final_charge_c": final_charge,
        "final_rotor_rpm": 0.0 if mode == "fixed_voltage" else 900.0,
        "engine_running": engine_running,
        "initial_throttle": throttle,
        "cut_after_ticks": 120 if case_id == "fixed-voltage-rotor-stop" else -1,
        "all_finite": True,
        "seed_checkpoint_file": case_id + "-seed.bin",
        "seed_checkpoint_bytes": 32,
        "endpoint_checkpoint_file": case_id + "-endpoint.bin",
        "endpoint_checkpoint_bytes": 36,
    }


def make_probe(smoke: bool = False) -> dict[str, Any]:
    contract = SMOKE_CONTRACT if smoke else FULL_CONTRACT
    return {
        "format": "el2a-p2-whole-session-event-probe-v1",
        "tick_hz": TICK_HZ,
        "smoke": smoke,
        "rows": [make_row(case_id, expected, smoke) for case_id, expected in contract.items()],
        "failures": [],
    }


class EventProbeValidationTests(unittest.TestCase):
    def test_full_and_smoke_reports_are_accepted(self) -> None:
        decoded = compare_events.validate_probe(make_probe(), smoke=False)
        self.assertEqual(set(decoded), set(FULL_CONTRACT))
        decoded = compare_events.validate_probe(make_probe(smoke=True), smoke=True)
        self.assertEqual(set(decoded), set(SMOKE_CONTRACT))

    def test_case_mode_requirements_and_missing_events_are_rejected(self) -> None:
        for case_id, (_, required, _) in FULL_CONTRACT.items():
            wrong_mode = "battery" if case_id == "battery-no-event-4s" else "no_event"
            for field, wrong_value in (("mode", wrong_mode), ("required_events", [] if required else ["rotor_stop"])):
                with self.subTest(case=case_id, field=field):
                    report = make_probe()
                    row = next(value for value in report["rows"] if value["id"] == case_id)
                    row[field] = wrong_value
                    with self.assertRaises(compare_events.CompareError):
                        compare_events.validate_probe(report, smoke=False)
            if required:
                with self.subTest(case=case_id, field="missing-event"):
                    report = make_probe()
                    row = next(value for value in report["rows"] if value["id"] == case_id)
                    row["events"] = []
                    row["event_types"] = []
                    with self.assertRaises(compare_events.CompareError):
                        compare_events.validate_probe(report, smoke=False)

    def test_event_and_duration_counts_are_enforced(self) -> None:
        report = make_probe()
        row = next(value for value in report["rows"] if value["id"] == "battery-powered-4s")
        event = row["events"][0]
        event["tick"] = row["ticks"] + 1
        event["containing_tick_time_s"] = event["tick"] / TICK_HZ
        with self.assertRaises(compare_events.CompareError):
            compare_events.validate_probe(report, smoke=False)

        for case_id in ("battery-no-event-4s", "battery-powered-4s"):
            with self.subTest(case=case_id):
                report = make_probe()
                row = next(value for value in report["rows"] if value["id"] == case_id)
                row["ticks"] -= 1
                row["end_time_s"] = row["ticks"] / TICK_HZ
                with self.assertRaises(compare_events.CompareError):
                    compare_events.validate_probe(report, smoke=False)

    def test_event_state_layout_and_finite_values_are_enforced(self) -> None:
        for mutate in (
            lambda event: event["continuous_state"].pop(),
            lambda event: event["body_state"].__setitem__(0, float("nan")),
            lambda event: event["continuous_state"].__setitem__(0, float("inf")),
        ):
            with self.subTest(mutation=mutate):
                report = make_probe()
                row = next(value for value in report["rows"] if value["id"] == "battery-powered-4s")
                mutate(row["events"][0])
                with self.assertRaises(compare_events.CompareError):
                    compare_events.validate_probe(report, smoke=False)


def make_comparison_fixture(root: Path) -> tuple[dict[str, list[dict[str, Any]]], dict[str, list[Path]]]:
    decoded = compare_events.validate_probe(make_probe(), smoke=False)
    reports: dict[str, list[dict[str, Any]]] = {"baseline": [], "candidate": []}
    run_dirs: dict[str, list[Path]] = {"baseline": [], "candidate": []}
    for label in ("baseline", "candidate"):
        for round_index in range(3):
            run_dir = root / label / f"round-{round_index + 1}"
            run_dir.mkdir(parents=True)
            rows = copy.deepcopy(decoded)
            for case_id, row in rows.items():
                seed = ("native-seed:" + case_id).encode("ascii")[:32].ljust(32, b"\0")
                endpoint = ("native-endpoint:" + case_id).encode("ascii")[:36].ljust(36, b"\0")
                (run_dir / row["seed_checkpoint_file"]).write_bytes(seed)
                (run_dir / row["endpoint_checkpoint_file"]).write_bytes(endpoint)
            reports[label].append(rows)
            run_dirs[label].append(run_dir)
    return reports, run_dirs


class ComparisonRegressionTests(unittest.TestCase):
    def test_identical_three_round_comparison_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            reports, run_dirs = make_comparison_fixture(Path(temp))
            result = compare_events.compare_runs(reports, run_dirs, smoke=False)
            self.assertEqual(result["status"], "passed")
            self.assertEqual(result["case_count"], len(FULL_CONTRACT))

    def test_same_size_native_checkpoint_corruption_breaks_replay(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            reports, run_dirs = make_comparison_fixture(Path(temp))
            for run_dir in run_dirs["candidate"]:
                path = run_dir / "battery-no-event-4s-endpoint.bin"
                damaged = bytearray(path.read_bytes())
                damaged[-1] ^= 0x01
                path.write_bytes(damaged)
            result = compare_events.compare_runs(reports, run_dirs, smoke=False)
            no_event = next(row for row in result["cases"] if row["id"] == "battery-no-event-4s")
            self.assertEqual(result["status"], "failed")
            self.assertFalse(no_event["native_no_event_endpoint_bytes_identical"])

        with tempfile.TemporaryDirectory() as temp:
            reports, run_dirs = make_comparison_fixture(Path(temp))
            path = run_dirs["baseline"][1] / "battery-powered-4s-endpoint.bin"
            damaged = bytearray(path.read_bytes())
            damaged[-1] ^= 0x01
            path.write_bytes(damaged)
            with self.assertRaises(compare_events.CompareError):
                compare_events.compare_runs(reports, run_dirs, smoke=False)

    def test_changed_event_state_replay_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            reports, run_dirs = make_comparison_fixture(Path(temp))
            row = reports["candidate"][1]["battery-powered-4s"]
            row["events"][0]["body_state"][0] = 1e-9
            with self.assertRaises(compare_events.CompareError):
                compare_events.compare_runs(reports, run_dirs, smoke=False)

    def test_cross_implementation_body_difference_over_tolerance_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            reports, run_dirs = make_comparison_fixture(Path(temp))
            for rows in reports["candidate"]:
                rows["battery-powered-4s"]["events"][0]["body_state"][0] = 2e-8
            with self.assertRaises(compare_events.CompareError):
                compare_events.compare_runs(reports, run_dirs, smoke=False)


if __name__ == "__main__":
    unittest.main()
