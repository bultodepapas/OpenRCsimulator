"""Contract tests for the stdlib flight-log command and CSV reducers."""

from __future__ import annotations

import contextlib
import csv
import hashlib
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


def debrief_rows(first_tick: int = 0, row_count: int = 5, dt_s: float = 0.1) -> list[dict[str, object]]:
    return [
        sample_row(
            first_tick + offset,
            t_s=(first_tick + offset) * dt_s,
            loads_t_s=max(0, first_tick + offset - 1) * dt_s,
            down_m=10.0 - offset,
            tas_mps=10.0 + offset,
            alpha_rad=0.1 * offset,
            beta_rad=-0.05 * offset,
            p_radps=float(offset),
            q_radps=float(-offset),
            r_radps=float(offset) / 2.0,
            cmd_roll=0.1 * offset,
            cmd_pitch=-0.1 * offset,
            srv_roll=0.08 * offset,
            Fx_N=2.0 * offset,
        )
        for offset in range(row_count)
    ]


def write_debrief_csv(path: Path, first_tick: int, row_count: int, dt_s: float) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=HEADER, lineterminator="\n")
        writer.writeheader()
        for offset in range(row_count):
            tick = first_tick + offset
            writer.writerow(sample_row(
                tick,
                t_s=tick * dt_s,
                loads_t_s=max(0, tick - 1) * dt_s,
                down_m=10.0 - offset,
                tas_mps=10.0 + offset,
                alpha_rad=0.1 * offset,
                beta_rad=-0.05 * offset,
                p_radps=float(offset),
                q_radps=float(-offset),
                r_radps=float(offset) / 2.0,
                cmd_roll=0.1 * offset,
                cmd_pitch=-0.1 * offset,
                srv_roll=0.08 * offset,
                Fx_N=2.0 * offset,
            ))


def exact_replay_report(
    log_path: Path,
    events: list[dict[str, object]] | None = None,
    *,
    first_tick: int = 0,
    row_count: int = 5,
    dt_s: float = 0.1,
) -> dict[str, object]:
    return {
        "format": "openrc-flight-log-report v1",
        "status": "ok",
        "error": "",
        "mode": "exact",
        "complete": True,
        "solver_changed": False,
        "source": str(log_path.resolve()),
        "source_sha256": hashlib.sha256(log_path.read_bytes()).hexdigest(),
        "baseline_solver_sha256": "a" * 64,
        "current_solver_sha256": "a" * 64,
        "first_tick": first_tick,
        "final_tick": first_tick + row_count - 1,
        "rows": row_count,
        "dt_s": dt_s,
        "metadata": {"aircraft_id": "fixture-aircraft"},
        "events": events if events is not None else [],
        "events_omitted": 0,
    }


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

    def test_indexed_header_bounds_preserve_decimal_column_names(self) -> None:
        path = Path("indexed.csv")
        for indexed_names in (
            ("aux_4", "aux_5"),
            ("aux_0004", "aux_0005"),
            ("aux_٤", "aux_٥"),
            ("aux_" + "0" * 5000 + "4",),
            ("continuous_0", "continuous_1", "mode_0", "mode_1"),
        ):
            with self.subTest(indexed_names=indexed_names):
                header = (*flight_log.REQUIRED_COLUMNS, *indexed_names)
                self.assertEqual(flight_log._validate_header(header, path), header)

        with self.assertRaisesRegex(
            flight_log.FlightLogError, "aux_ columns must be contiguous from 4"
        ):
            flight_log._validate_header(
                (*flight_log.REQUIRED_COLUMNS, "aux_4", "aux_6"), path
            )

    def test_oversized_indexed_suffix_is_a_controlled_cli_error(self) -> None:
        source = self.directory / "oversized-indexed-header.csv"
        fields = (*flight_log.REQUIRED_COLUMNS, "aux_" + ("9" * 5000))
        with source.open("w", encoding="utf-8", newline="") as stream:
            csv.writer(stream, lineterminator="\n").writerow(fields)

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            result = flight_log.main(["summarize", str(source)])

        self.assertEqual(result, 2)
        self.assertIn("error:", stderr.getvalue())
        self.assertIn("aux_ columns must be contiguous from 4", stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())

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

    def test_release_export_uses_only_the_fixed_shipped_entry_point(self) -> None:
        source = self.directory / "package flight.orfl"
        source.write_bytes(b"orfl")
        output = self.directory / "package export"

        def fake_run(command: list[str], **_kwargs: object) -> object:
            self.assertEqual(command[0], str(self.godot.resolve()))
            self.assertIn("--flight-log-cli", command)
            self.assertIn("--quick-flight", command)
            self.assertNotIn("--path", command)
            self.assertNotIn("--script", command)
            self.assertIn(f"--log={source.resolve()}", command)
            self.assertIn(f"--csv={(output / 'flight.csv').resolve()}", command)
            write_csv(output / "flight.csv", [sample_row(0), sample_row(1)])
            (output / "export.json").write_text(
                json.dumps({"status": "ok", "error": "", "complete": True, "rows": 2}), encoding="utf-8")
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            result = flight_log.main(["export", str(source), "--out", str(output),
                                      "--release-executable", str(self.godot)])
        self.assertEqual(result, 0)

    def test_release_exact_replay_requires_the_selected_executable_identity(self) -> None:
        source = self.directory / "package replay.orfl"
        source.write_bytes(b"orfl")
        executable_hash = hashlib.sha256(self.godot.read_bytes()).hexdigest()

        def run_case(name: str, mutate: str = "") -> int:
            output = self.directory / name

            def fake_run(command: list[str], **_kwargs: object) -> object:
                self.assertIn("--flight-log-cli", command)
                self.assertIn("--replay", command)
                self.assertNotIn("--script", command)
                self.assertNotIn("--path", command)
                write_debrief_csv(output / "flight.csv", 0, 2, 0.1)
                report = exact_replay_report(source, row_count=2)
                report.update({"baseline_solver_sha256": executable_hash, "current_solver_sha256": executable_hash,
                               "baseline_solver_identity_kind": "packaged-executable-v1",
                               "current_solver_identity_kind": "packaged-executable-v1"})
                if mutate == "identity":
                    report["current_solver_sha256"] = "f" * 64
                elif mutate == "kind":
                    report["current_solver_identity_kind"] = "source-tree-v1"
                elif mutate == "changed":
                    report["solver_changed"] = True
                elif mutate == "executable":
                    self.godot.write_bytes(b"modified executable")
                (output / "replay.json").write_text(json.dumps(report), encoding="utf-8")
                return type("Result", (), {"returncode": 0})()

            with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
                with contextlib.redirect_stderr(io.StringIO()):
                    return flight_log.main(["replay", str(source), "--out", str(output),
                                            "--release-executable", str(self.godot)])

        self.assertEqual(run_case("valid"), 0)
        for mutation in ("identity", "kind", "changed", "executable"):
            with self.subTest(mutation=mutation):
                self.assertNotEqual(run_case("bad-" + mutation, mutation), 0)

    def test_release_executable_and_editor_options_are_mutually_exclusive(self) -> None:
        source = self.directory / "flight.orfl"
        source.write_bytes(b"orfl")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            flight_log.main(["replay", str(source), "--out", str(self.directory / "out"),
                             "--godot", str(self.godot), "--release-executable", str(self.godot)])

    def test_empty_release_executable_does_not_fall_back_to_editor(self) -> None:
        source = self.directory / "flight.orfl"
        source.write_bytes(b"orfl")
        with mock.patch.object(flight_log, "_resolve_godot", side_effect=AssertionError("unexpected editor fallback")):
            with contextlib.redirect_stderr(io.StringIO()):
                result = flight_log.main(["replay", str(source), "--out", str(self.directory / "out"),
                                          "--release-executable", ""])
        self.assertNotEqual(result, 0)

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

    def test_debrief_replays_then_writes_marker_windows_and_artifact_hashes(self) -> None:
        source = self.directory / "practice flight.orfl"
        source.write_bytes(b"source log fixture")
        output = self.directory / "debrief output"
        events: list[dict[str, object]] = [
            {"tick": 2, "kind": "marker", "detail": "figure start"},
            {"tick": 2, "kind": "marker", "detail": "pull begins"},
            {"tick": 3, "kind": "pause", "detail": ""},
            {"tick": 4, "kind": "marker", "detail": "figure end"},
        ]

        def fake_run(command: list[str], **_kwargs: object) -> object:
            self.assertIn("--replay", command)
            self.assertNotIn("--candidate", " ".join(command))
            self.assertIn(f"--log={source.resolve()}", command)
            write_csv(output / "flight.csv", debrief_rows())
            report = exact_replay_report(source, events)
            (output / "replay.json").write_text(json.dumps(report), encoding="utf-8")
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            result = flight_log.main(
                ["debrief", str(source), "--out", str(output), "--godot", str(self.godot)]
            )

        self.assertEqual(result, 0)
        for name in ("flight.csv", "replay.json", "godot.log", "debrief.json"):
            self.assertTrue((output / name).is_file(), name)
        document = json.loads((output / "debrief.json").read_text(encoding="utf-8"))
        self.assertEqual(document["format"], "openrc-flight-debrief v1")
        self.assertEqual(document["replay_report"]["metadata"]["aircraft_id"], "fixture-aircraft")
        self.assertEqual(document["replay_report"]["baseline_solver_sha256"], "a" * 64)
        self.assertEqual(document["replay_report"]["current_solver_sha256"], "a" * 64)
        self.assertFalse(document["replay_report"]["solver_changed"])
        self.assertEqual(document["replay_report"]["events"], events)
        self.assertEqual(document["input_artifacts"]["source_log"]["sha256"], hashlib.sha256(source.read_bytes()).hexdigest())
        self.assertEqual(document["input_artifacts"]["replayed_csv"]["sha256"], hashlib.sha256((output / "flight.csv").read_bytes()).hexdigest())
        self.assertEqual(document["input_artifacts"]["replay_report"]["sha256"], hashlib.sha256((output / "replay.json").read_bytes()).hexdigest())

        flight = document["flight"]
        self.assertEqual(flight["marker_groups"], [
            {"tick": 2, "labels": ["figure start", "pull begins"]},
            {"tick": 4, "labels": ["figure end"]},
        ])
        self.assertEqual([window["kind"] for window in flight["windows"]],
            ["unmarked_prefix", "between_markers", "marker_tail"])
        prefix, between, tail = flight["windows"]
        self.assertEqual((prefix["start_tick"], prefix["end_tick"], prefix["endpoint_samples"], prefix["interval_samples"]),
            (0, 2, 3, 2))
        self.assertEqual(prefix["state_endpoints"]["altitude_m"],
            {"min": -10.0, "max": -8.0, "start": -10.0, "end": -8.0, "delta": 2.0})
        self.assertEqual(prefix["state_endpoints"]["alpha_rad"],
            {"min": 0.0, "max": 0.2, "start": 0.0, "end": 0.2, "delta": 0.2})
        self.assertEqual(prefix["interval_channels"]["commands"]["cmd_roll"], {"min": 0.1, "max": 0.2})
        self.assertEqual(prefix["interval_channels"]["loads"]["Fx_N"], {"min": 2.0, "max": 4.0})
        self.assertEqual(prefix["loads_t_s_range"], [0.0, 0.1])
        self.assertEqual((between["start_tick"], between["end_tick"], between["endpoint_samples"], between["interval_samples"]),
            (2, 4, 3, 2))
        self.assertEqual(tail["endpoint_samples"], 1)
        self.assertEqual(tail["interval_samples"], 0)
        self.assertEqual(tail["interval_channels"]["commands"], {})

    def test_debrief_without_markers_reports_one_unmarked_flight(self) -> None:
        source = self.directory / "unmarked.orfl"
        source.write_bytes(b"source log fixture")
        output = self.directory / "unmarked-output"

        def fake_run(command: list[str], **_kwargs: object) -> object:
            self.assertIn("--replay", command)
            write_csv(output / "flight.csv", debrief_rows())
            (output / "replay.json").write_text(
                json.dumps(exact_replay_report(source)), encoding="utf-8"
            )
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            result = flight_log.main(
                ["debrief", str(source), "--out", str(output), "--godot", str(self.godot)]
            )

        self.assertEqual(result, 0)
        document = json.loads((output / "debrief.json").read_text(encoding="utf-8"))
        self.assertEqual(document["flight"]["marker_groups"], [])
        self.assertEqual(len(document["flight"]["windows"]), 1)
        window = document["flight"]["windows"][0]
        self.assertEqual(window["kind"], "unmarked_flight")
        self.assertEqual((window["start_tick"], window["end_tick"]), (0, 4))
        self.assertEqual(window["interval_samples"], 4)

    def test_debrief_one_marker_splits_prefix_from_marked_tail(self) -> None:
        source = self.directory / "one-marker.orfl"
        source.write_bytes(b"source log fixture")
        output = self.directory / "one-marker-output"

        def fake_run(command: list[str], **_kwargs: object) -> object:
            write_csv(output / "flight.csv", debrief_rows())
            (output / "replay.json").write_text(
                json.dumps(exact_replay_report(source, [
                    {"tick": 2, "kind": "marker", "detail": "pilot starts the maneuver"},
                ])),
                encoding="utf-8",
            )
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            result = flight_log.main(
                ["debrief", str(source), "--out", str(output), "--godot", str(self.godot)]
            )

        self.assertEqual(result, 0)
        document = json.loads((output / "debrief.json").read_text(encoding="utf-8"))
        prefix, tail = document["flight"]["windows"]
        self.assertEqual([window["kind"] for window in document["flight"]["windows"]],
            ["unmarked_prefix", "marker_tail"])
        self.assertEqual((prefix["start_tick"], prefix["end_tick"]), (0, 2))
        self.assertEqual((tail["start_tick"], tail["end_tick"]), (2, 4))
        self.assertEqual((prefix["endpoint_samples"], prefix["interval_samples"]), (3, 2))
        self.assertEqual((tail["endpoint_samples"], tail["interval_samples"]), (3, 2))

    def test_debrief_supports_midflight_recording_tick_origin(self) -> None:
        source = self.directory / "midflight.orfl"
        source.write_bytes(b"source log fixture")
        output = self.directory / "midflight-output"
        first_tick = 1200
        dt_s = 1.0 / 240.0
        events = [{"tick": 1202, "kind": "marker", "detail": "marked maneuver"}]

        def fake_run(command: list[str], **_kwargs: object) -> object:
            self.assertIn("--replay", command)
            write_csv(output / "flight.csv", debrief_rows(first_tick, 5, dt_s))
            report = exact_replay_report(
                source, events, first_tick=first_tick, row_count=5, dt_s=dt_s
            )
            (output / "replay.json").write_text(json.dumps(report), encoding="utf-8")
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            result = flight_log.main(
                ["debrief", str(source), "--out", str(output), "--godot", str(self.godot)]
            )

        self.assertEqual(result, 0)
        document = json.loads((output / "debrief.json").read_text(encoding="utf-8"))
        flight = document["flight"]
        self.assertEqual((flight["first_tick"], flight["final_tick"], flight["rows"]), (1200, 1204, 5))
        self.assertAlmostEqual(flight["duration_s"], 4 * dt_s)
        prefix, tail = flight["windows"]
        self.assertEqual((prefix["start_tick"], prefix["end_tick"]), (1200, 1202))
        self.assertEqual((tail["start_tick"], tail["end_tick"]), (1202, 1204))
        self.assertAlmostEqual(prefix["loads_t_s_range"][0], 1200 * dt_s)
        self.assertAlmostEqual(prefix["loads_t_s_range"][1], 1201 * dt_s)

    def test_debrief_refuses_wrong_source_solver_and_candidate_provenance(self) -> None:
        cases = (
            ("candidate mode", {"mode": "candidate"}, "complete exact replay"),
            ("source path", {"source": "/different/source.orfl"}, "source path"),
            ("source hash", {"source_sha256": "b" * 64}, "flight log changed"),
            ("solver changed", {"solver_changed": True}, "solver_changed=false"),
            ("solver identity", {"current_solver_sha256": "b" * 64}, "identities differ"),
        )
        for label, changes, expected_error in cases:
            with self.subTest(label=label):
                source = self.directory / f"provenance-{label.replace(' ', '-')}.orfl"
                source.write_bytes(b"source log fixture")
                output = self.directory / f"provenance-{label.replace(' ', '-')}-output"

                def fake_run(command: list[str], **_kwargs: object) -> object:
                    self.assertIn("--replay", command)
                    self.assertNotIn("--candidate", " ".join(command))
                    write_csv(output / "flight.csv", debrief_rows())
                    report = exact_replay_report(source)
                    report.update(changes)
                    (output / "replay.json").write_text(json.dumps(report), encoding="utf-8")
                    return type("Result", (), {"returncode": 0})()

                stderr = io.StringIO()
                with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
                    with contextlib.redirect_stderr(stderr):
                        result = flight_log.main(
                            ["debrief", str(source), "--out", str(output), "--godot", str(self.godot)]
                        )
                self.assertEqual(result, 2)
                self.assertIn(expected_error, stderr.getvalue())
                self.assertTrue((output / "flight.csv").is_file())
                self.assertTrue((output / "replay.json").is_file())
                self.assertFalse((output / "debrief.json").exists())

    def test_debrief_reducer_memory_does_not_scale_with_row_count(self) -> None:
        source = self.directory / "memory-source.orfl"
        source.write_bytes(b"source log fixture")
        dt_s = 1.0 / 240.0
        peaks: list[tuple[int, int]] = []
        for row_count in (1000, 20000):
            with self.subTest(row_count=row_count):
                first_tick = 0
                csv_path = self.directory / f"memory-{row_count}.csv"
                report_path = self.directory / f"memory-{row_count}.json"
                write_debrief_csv(csv_path, first_tick, row_count, dt_s)
                events = [{
                    "tick": row_count // 2,
                    "kind": "marker",
                    "detail": "bounded memory marker",
                }]
                report = exact_replay_report(
                    source, events, first_tick=first_tick, row_count=row_count, dt_s=dt_s
                )
                report_path.write_text(json.dumps(report), encoding="utf-8")
                summary = flight_log.summarize_csv(csv_path)

                tracemalloc.start()
                try:
                    document = flight_log._build_debrief(
                        csv_path, source, report_path, report, summary
                    )
                    _current, peak = tracemalloc.get_traced_memory()
                finally:
                    tracemalloc.stop()
                self.assertEqual(document["flight"]["rows"], row_count)
                self.assertLess(peak, 4 * 1024 * 1024)
                peaks.append((row_count, peak))

        small_peak = peaks[0][1]
        large_peak = peaks[1][1]
        self.assertLessEqual(large_peak, small_peak + 1024 * 1024)
        print(
            f"debrief reducer peak bytes: {peaks[0][0]} rows={small_peak}, "
            f"{peaks[1][0]} rows={large_peak}"
        )

    def test_debrief_marker_at_recording_start_keeps_zero_duration_prefix(self) -> None:
        source = self.directory / "start-marker.orfl"
        source.write_bytes(b"source log fixture")
        output = self.directory / "start-marker-output"

        def fake_run(command: list[str], **_kwargs: object) -> object:
            write_csv(output / "flight.csv", debrief_rows())
            (output / "replay.json").write_text(
                json.dumps(exact_replay_report(source, [
                    {"tick": 0, "kind": "marker", "detail": "recording begins in maneuver"},
                ])),
                encoding="utf-8",
            )
            return type("Result", (), {"returncode": 0})()

        with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
            result = flight_log.main(
                ["debrief", str(source), "--out", str(output), "--godot", str(self.godot)]
            )

        self.assertEqual(result, 0)
        document = json.loads((output / "debrief.json").read_text(encoding="utf-8"))
        prefix, tail = document["flight"]["windows"]
        self.assertEqual((prefix["start_tick"], prefix["end_tick"]), (0, 0))
        self.assertEqual((prefix["endpoint_samples"], prefix["interval_samples"]), (1, 0))
        self.assertEqual((tail["start_tick"], tail["end_tick"]), (0, 4))
        self.assertEqual((tail["endpoint_samples"], tail["interval_samples"]), (5, 4))

    def test_debrief_refuses_incomplete_or_truncated_event_reports_but_keeps_replay_artifacts(self) -> None:
        cases = (("incomplete", {"complete": False}), ("truncated events", {"events_omitted": 1}))
        for label, change in cases:
            with self.subTest(label=label):
                source = self.directory / f"{label.replace(' ', '-')}.orfl"
                source.write_bytes(b"source log fixture")
                output = self.directory / f"{label.replace(' ', '-')}-output"

                def fake_run(command: list[str], **_kwargs: object) -> object:
                    self.assertIn("--replay", command)
                    write_csv(output / "flight.csv", debrief_rows())
                    report = exact_replay_report(source)
                    report.update(change)
                    (output / "replay.json").write_text(json.dumps(report), encoding="utf-8")
                    return type("Result", (), {"returncode": 0})()

                stderr = io.StringIO()
                with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
                    with contextlib.redirect_stderr(stderr):
                        result = flight_log.main(
                            ["debrief", str(source), "--out", str(output), "--godot", str(self.godot)]
                        )
                self.assertNotEqual(result, 0)
                self.assertTrue((output / "flight.csv").is_file())
                self.assertTrue((output / "replay.json").is_file())
                self.assertFalse((output / "debrief.json").exists())
                expected_error = "incomplete" if label == "incomplete" else "debrief"
                self.assertIn(expected_error, stderr.getvalue().lower())

    def test_debrief_cli_does_not_accept_arbitrary_csv_report_pairs(self) -> None:
        source = self.directory / "source.orfl"
        source.write_bytes(b"source log fixture")
        csv_path = self.directory / "untrusted.csv"
        report_path = self.directory / "untrusted.json"
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaises(SystemExit) as raised:
                flight_log.main([
                    "debrief", str(source), str(csv_path), str(report_path),
                    "--out", str(self.directory / "output"),
                ])
        self.assertEqual(raised.exception.code, 2)
        self.assertIn("unrecognized arguments", stderr.getvalue())

    def test_debrief_rejects_out_of_order_and_out_of_range_markers(self) -> None:
        cases = (
            ("out of order", [
                {"tick": 3, "kind": "marker", "detail": "late"},
                {"tick": 2, "kind": "marker", "detail": "early"},
            ], "out of order"),
            ("outside marker", [{"tick": 5, "kind": "marker", "detail": "outside"}], "outside"),
            ("outside pause", [{"tick": 5, "kind": "pause", "detail": ""}], "outside"),
        )
        for label, events, expected_error in cases:
            with self.subTest(label=label):
                source = self.directory / f"{label.replace(' ', '-')}.orfl"
                source.write_bytes(b"source log fixture")
                output = self.directory / f"{label.replace(' ', '-')}-output"

                def fake_run(command: list[str], **_kwargs: object) -> object:
                    write_csv(output / "flight.csv", debrief_rows())
                    (output / "replay.json").write_text(
                        json.dumps(exact_replay_report(source, events)), encoding="utf-8"
                    )
                    return type("Result", (), {"returncode": 0})()

                stderr = io.StringIO()
                with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
                    with contextlib.redirect_stderr(stderr):
                        result = flight_log.main(
                            ["debrief", str(source), "--out", str(output), "--godot", str(self.godot)]
                        )
                self.assertEqual(result, 2)
                self.assertIn(expected_error, stderr.getvalue())
                self.assertTrue((output / "flight.csv").is_file())
                self.assertTrue((output / "replay.json").is_file())
                self.assertFalse((output / "debrief.json").exists())

    def test_debrief_rejects_report_tick_count_and_timestep_mismatches(self) -> None:
        cases = (
            ("row count", {"rows": 4}, debrief_rows()),
            ("tick bounds", {"first_tick": 1, "final_tick": 5}, debrief_rows()),
            ("timestep", {"dt_s": 0.2}, debrief_rows()),
            ("CSV interior time", {}, [
                *debrief_rows()[:2],
                sample_row(2, t_s=0.25, loads_t_s=0.1),
                *debrief_rows()[3:],
            ]),
            ("CSV load time", {}, [
                *debrief_rows()[:2],
                sample_row(2, t_s=0.2, loads_t_s=0.125),
                *debrief_rows()[3:],
            ]),
        )
        for label, changes, rows in cases:
            with self.subTest(label=label):
                source = self.directory / f"mismatch-{label.replace(' ', '-')}.orfl"
                source.write_bytes(b"source log fixture")
                output = self.directory / f"mismatch-{label.replace(' ', '-')}-output"

                def fake_run(command: list[str], **_kwargs: object) -> object:
                    write_csv(output / "flight.csv", rows)
                    report = exact_replay_report(source)
                    report.update(changes)
                    (output / "replay.json").write_text(json.dumps(report), encoding="utf-8")
                    return type("Result", (), {"returncode": 0})()

                stderr = io.StringIO()
                with mock.patch.object(flight_log.subprocess, "run", side_effect=fake_run):
                    with contextlib.redirect_stderr(stderr):
                        result = flight_log.main(
                            ["debrief", str(source), "--out", str(output), "--godot", str(self.godot)]
                        )
                self.assertEqual(result, 2)
                self.assertIn("report", stderr.getvalue().lower())
                self.assertTrue((output / "flight.csv").is_file())
                self.assertFalse((output / "debrief.json").exists())


if __name__ == "__main__":
    unittest.main()
