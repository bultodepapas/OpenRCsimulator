"""Contract tests for the stdlib flight-log command and CSV reducers."""

from __future__ import annotations

import contextlib
import csv
import io
import json
import math
import tempfile
import tracemalloc
import unittest
from pathlib import Path
from unittest import mock

import flight_log


HEADER = list(flight_log.REQUIRED_COLUMNS) + [
    "cmd_gear_down",
    "cmd_wheel_brake",
    "cmd_auxiliary",
    "aux_4",
    "aux_5",
    "continuous_0",
    "mode_0",
]


def sample_row(tick: int, **changes: object) -> dict[str, object]:
    row: dict[str, object] = {name: 0.0 for name in HEADER}
    row.update(
        {
            "tick": tick,
            "t_s": tick * 0.1,
            "loads_t_s": tick * 0.002,
            "down_m": float(tick),
            "u_mps": float(tick),
            "qw": 1.0,
            "cmd_throttle": 0.5,
            "engine_rpm": 1200.0,
            "tas_mps": 12.0,
            "mode_0": 1,
        }
    )
    row.update(changes)
    return row


def write_csv(path: Path, rows: list[dict[str, object]], *, metadata: str = "") -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        if metadata:
            stream.write(metadata)
            if not metadata.endswith("\n"):
                stream.write("\n")
        writer = csv.DictWriter(stream, fieldnames=HEADER, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


class FlightLogCsvTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="flight log ")
        self.directory = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_summary_reads_metadata_and_reports_altitude_rates_and_rms(self) -> None:
        source = self.directory / "sample.csv"
        write_csv(
            source,
            [
                sample_row(0, down_m=2.0, p_radps=-2.0),
                sample_row(1, down_m=-2.0, p_radps=1.0),
            ],
            metadata="# format: openrc-flight-csv-v1\n# samples: 2",
        )

        result = flight_log.summarize_csv(source)

        self.assertEqual(result["rows"], 2)
        self.assertEqual(result["time_s"]["duration"], 0.1)
        self.assertEqual(result["altitude_m"]["min"], -2.0)
        self.assertEqual(result["altitude_m"]["max"], 2.0)
        self.assertAlmostEqual(result["altitude_m"]["rms"], 2.0)
        self.assertEqual(result["angular_rates_radps"]["max_abs"], 2.0)
        self.assertAlmostEqual(result["columns"]["p_radps"]["rms"], math.sqrt(2.5))

    def test_missing_column_is_rejected(self) -> None:
        source = self.directory / "missing.csv"
        fields = [name for name in HEADER if name != "Fx_N"]
        with source.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
            writer.writeheader()
            writer.writerow(sample_row(0))
        with self.assertRaisesRegex(flight_log.FlightLogError, "missing required columns: Fx_N"):
            flight_log.summarize_csv(source)

    def test_duplicate_headers_nonfinite_values_and_truncated_rows_fail(self) -> None:
        duplicate = self.directory / "duplicate.csv"
        duplicate.write_text(",".join(HEADER + ["tick"]) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(flight_log.FlightLogError, "duplicate CSV columns"):
            flight_log.summarize_csv(duplicate)

        nonfinite = self.directory / "nonfinite.csv"
        write_csv(nonfinite, [sample_row(0, north_m="nan")])
        with self.assertRaisesRegex(flight_log.FlightLogError, "nonfinite number in north_m"):
            flight_log.summarize_csv(nonfinite)

        truncated = self.directory / "truncated.csv"
        write_csv(truncated, [sample_row(0), sample_row(1)])
        lines = truncated.read_text(encoding="utf-8").splitlines()
        truncated.write_text("\n".join(lines[:-1] + [lines[-1].rsplit(",", 1)[0]]) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(flight_log.FlightLogError, "truncated row"):
            flight_log.summarize_csv(truncated)

    def test_tick_duplicates_gaps_and_truncated_metadata_are_rejected(self) -> None:
        duplicate = self.directory / "duplicate-tick.csv"
        write_csv(duplicate, [sample_row(0), sample_row(0)])
        with self.assertRaisesRegex(flight_log.FlightLogError, "duplicate tick"):
            flight_log.summarize_csv(duplicate)

        gap = self.directory / "gap.csv"
        write_csv(gap, [sample_row(4), sample_row(6)])
        with self.assertRaisesRegex(flight_log.FlightLogError, "tick gap"):
            flight_log.summarize_csv(gap)

        short = self.directory / "short.csv"
        write_csv(short, [sample_row(0)], metadata="# rows: 2")
        with self.assertRaisesRegex(flight_log.FlightLogError, "truncated CSV"):
            flight_log.summarize_csv(short)

    def test_compare_checks_alignment_and_command_inputs(self) -> None:
        base = self.directory / "base.csv"
        candidate = self.directory / "candidate.csv"
        write_csv(base, [sample_row(0), sample_row(1)])
        write_csv(candidate, [sample_row(0), sample_row(1, north_m=0.25)])
        report = flight_log.compare_csv(base, candidate)
        self.assertEqual(report["first_divergence"], {"tick": 1, "t_s": 0.1, "metrics": ["position_m"]})
        self.assertAlmostEqual(report["differences"]["position_m"]["components"]["north_m"]["rmse"], math.sqrt(0.25**2 / 2))
        self.assertEqual(report["differences"]["position_m"]["components"]["north_m"]["max_abs"], 0.25)

        write_csv(candidate, [sample_row(0), sample_row(2)])
        with self.assertRaisesRegex(flight_log.FlightLogError, "tick gap"):
            flight_log.compare_csv(base, candidate)

        write_csv(candidate, [sample_row(0), sample_row(1, cmd_roll=0.2)])
        with self.assertRaisesRegex(flight_log.FlightLogError, "command input cmd_roll differs at tick 1"):
            flight_log.compare_csv(base, candidate)

        write_csv(candidate, [sample_row(0), sample_row(1, t_s=0.1001)])
        with self.assertRaisesRegex(flight_log.FlightLogError, "not aligned"):
            flight_log.compare_csv(base, candidate)

    def test_quaternion_comparison_is_invariant_to_sign(self) -> None:
        base = self.directory / "base.csv"
        candidate = self.directory / "candidate.csv"
        write_csv(base, [sample_row(0), sample_row(1, qw=0.5, qx=0.5, qy=0.5, qz=0.5)])
        write_csv(candidate, [sample_row(0, qw=-1.0), sample_row(1, qw=-0.5, qx=-0.5, qy=-0.5, qz=-0.5)])

        report = flight_log.compare_csv(base, candidate)

        self.assertIsNone(report["first_divergence"])
        self.assertEqual(report["differences"]["quaternion_angle_rad"]["rmse"], 0.0)
        self.assertEqual(report["differences"]["quaternion_angle_rad"]["max_abs"], 0.0)

    def test_quaternion_angle_keeps_small_differences_above_float_precision(self) -> None:
        base = self.directory / "base.csv"
        candidate = self.directory / "candidate.csv"
        write_csv(base, [sample_row(0)])
        write_csv(candidate, [sample_row(0, qz=5e-11)])

        report = flight_log.compare_csv(base, candidate)

        angle = report["differences"]["quaternion_angle_rad"]["max_abs"]
        self.assertAlmostEqual(angle, 1e-10, delta=1e-20)
        self.assertEqual(report["first_divergence"]["metrics"], ["quaternion_angle_rad"])

    def test_summary_streams_large_csv_without_retaining_rows(self) -> None:
        source = self.directory / "large.csv"
        with source.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=HEADER, lineterminator="\n")
            writer.writeheader()
            template = sample_row(0)
            for tick in range(5000):
                row = dict(template)
                row["tick"] = tick
                row["t_s"] = tick * 0.1
                row["loads_t_s"] = tick * 0.002
                row["down_m"] = float(tick)
                row["u_mps"] = float(tick)
                writer.writerow(row)

        tracemalloc.start()
        try:
            result = flight_log.summarize_csv(source)
            _current, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()

        self.assertEqual(result["rows"], 5000)
        self.assertLess(peak, 3_000_000, f"reader retained too much data: {peak} bytes")


class FlightLogCommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="flight log commands ")
        self.directory = Path(self.temporary.name)
        self.godot = self.directory / "Godot with spaces.exe"
        self.godot.write_bytes(b"mock executable")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_record_uses_argument_list_and_supports_paths_with_spaces(self) -> None:
        output = self.directory / "recorded flight.orfl"
        aircraft_id = "SebArt Avanti S A200"

        def fake_run(command: list[str], **kwargs: object) -> object:
            self.assertNotIn("--headless", command)
            self.assertIn(f"--flight-log={output.resolve()}", command)
            self.assertIn(f"--aircraft={aircraft_id}", command)
            self.assertIn(str(flight_log.APP), command)
            self.assertIn("--quick-flight", command)
            self.assertIsNone(kwargs.get("timeout"))
            Path(command[command.index("--") + 2].split("=", 1)[1]).write_bytes(b"orfl")
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                result = flight_log.main(
                    [
                        "record",
                        "--godot",
                        str(self.godot),
                        "--out",
                        str(output),
                        "--aircraft",
                        aircraft_id,
                    ]
                )
        self.assertEqual(result, 0)
        self.assertTrue(output.is_file())
        self.assertIn(str(output), stdout.getvalue())
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertNotEqual(
                flight_log.main(["record", "--godot", str(self.godot), "--out", str(output)]),
                0,
            )

    def test_export_builds_godot_cli_arguments_and_checks_report(self) -> None:
        source = self.directory / "source flight.orfl"
        source.write_bytes(b"orfl")
        output = self.directory / "export result with spaces"

        def fake_run(command: list[str], **_kwargs: object) -> object:
            self.assertIn("--headless", command)
            self.assertIn("--script", command)
            self.assertIn(f"--log={source.resolve()}", command)
            self.assertIn(f"--csv={(output / 'flight.csv').resolve()}", command)
            self.assertIn(f"--report={(output / 'export.json').resolve()}", command)
            write_csv(output / "flight.csv", [sample_row(0), sample_row(1)])
            (output / "export.json").write_text(
                json.dumps({"status": "ok", "error": "", "complete": True, "rows": 2}),
                encoding="utf-8",
            )
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            result = flight_log.main(
                ["export", str(source), "--out", str(output), "--godot", str(self.godot)]
            )
        self.assertEqual(result, 0)
        self.assertTrue((output / "flight.csv").is_file())
        self.assertTrue((output / "export.json").is_file())

    def test_recover_is_export_only_and_accepts_a_verified_prefix(self) -> None:
        source = self.directory / "interrupted.orfl.truncate"
        source.write_bytes(b"orfl")
        output = self.directory / "recovered export"

        def fake_run(command: list[str], **_kwargs: object) -> object:
            self.assertIn("--recover", command)
            self.assertNotIn("--replay", command)
            write_csv(output / "flight.csv", [sample_row(0)])
            (output / "export.json").write_text(
                json.dumps(
                    {
                        "status": "ok",
                        "error": "",
                        "complete": False,
                        "recovery_reason": "Interrupted after the last complete block.",
                        "rows": 1,
                    }
                ),
                encoding="utf-8",
            )
            return type("Result", (), {"returncode": 0})()

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertNotEqual(
                flight_log.main(
                    ["export", str(source), "--out", str(self.directory / "strict export"), "--godot", str(self.godot)]
                ),
                0,
            )
        self.assertIn(".orfl extension", stderr.getvalue())

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            result = flight_log.main(
                ["export", str(source), "--out", str(output), "--godot", str(self.godot), "--recover"]
            )
        self.assertEqual(result, 0)

    def test_candidate_replay_requires_solver_identity_report_fields(self) -> None:
        source = self.directory / "source.orfl"
        candidate = self.directory / "candidate aircraft.json"
        source.write_bytes(b"orfl")
        candidate.write_text("{}", encoding="utf-8")
        output = self.directory / "candidate replay"

        def fake_run(command: list[str], **_kwargs: object) -> object:
            self.assertIn("--replay", command)
            self.assertIn(f"--candidate={candidate.resolve()}", command)
            write_csv(output / "flight.csv", [sample_row(0)])
            (output / "replay.json").write_text(
                json.dumps(
                    {
                        "status": "ok",
                        "error": "",
                        "complete": True,
                        "rows": 1,
                        "baseline_solver_sha256": "a" * 64,
                        "current_solver_sha256": "b" * 64,
                        "solver_changed": True,
                        "comparison_method": "open_loop_candidate",
                    }
                ),
                encoding="utf-8",
            )
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            result = flight_log.main(
                [
                    "replay",
                    str(source),
                    "--out",
                    str(output),
                    "--godot",
                    str(self.godot),
                    "--candidate",
                    str(candidate),
                ]
            )
        self.assertEqual(result, 0)

    def test_zero_exit_with_error_report_is_failure(self) -> None:
        source = self.directory / "source.orfl"
        source.write_bytes(b"orfl")
        output = self.directory / "bad export"

        def fake_run(command: list[str], **_kwargs: object) -> object:
            write_csv(output / "flight.csv", [sample_row(0)])
            (output / "export.json").write_text(
                json.dumps({"status": "error", "error": "bad sample", "complete": True}),
                encoding="utf-8",
            )
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                result = flight_log.main(
                    ["export", str(source), "--out", str(output), "--godot", str(self.godot)]
                )
        self.assertNotEqual(result, 0)
        self.assertIn("bad sample", stderr.getvalue())

    def test_zero_exit_engine_error_is_rejected(self) -> None:
        output = self.directory / "engine-error.log"

        def fake_run(_command: list[str], **kwargs: object) -> object:
            kwargs["stdout"].write("SCRIPT ERROR: corrupted observer\n")
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            with self.assertRaisesRegex(flight_log.FlightLogError, "engine error"):
                flight_log._run_godot([str(self.godot)], 5, output)


if __name__ == "__main__":
    unittest.main()
