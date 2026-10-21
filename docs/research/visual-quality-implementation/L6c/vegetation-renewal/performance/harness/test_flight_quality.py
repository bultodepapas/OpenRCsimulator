"""Fast validation checks for the active-flight quality harness."""

from __future__ import annotations

import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from flight_quality import (
	alternating_orders,
	compare_pair,
	legacy_receipt_failures,
	main,
	pair_identity_failures,
	parser,
	resume_contract_failures,
	series_settings,
)
from flight_quality_common import contains_engine_error, parse_environment, sha256_file, validate_frame_report, write_json
from temporal_quality import ROUTES, parse_resolutions, validate_temporal_report


def valid_frame_report() -> dict:
	frames = 4
	return {
		"format": "openrc-tree-flight-quality-v1",
		"complete": True,
		"route": "live-input-tick-tape",
		"input_tape_sha256": "a" * 64,
		"scenario_sha256": "b" * 64,
		"scenario_identity": {"weather": "calm", "camera": "pilot"},
		"route_spec": {"tick_rate": 240},
		"sample_s": 0.067,
		"warmup_s": 0.0,
		"actual_sample_s": 0.067,
		"actual_warmup_s": 0.0,
		"actual_sample_start_monotonic_usec": 1000000,
		"actual_sample_end_monotonic_usec": 1067000,
		"frame_deltas_s": [0.01675] * frames,
		"frame_wall_usec": [16750] * frames,
		"frame_end_monotonic_usec": [1016750, 1033500, 1050250, 1067000],
		"settings": {
			"input_enabled": True,
			"physics_enabled": True,
			"render_settings": {"msaa_4x": True},
			"window": {"width": 1280, "height": 720},
			"max_fps": 60,
			"vsync": False,
		},
		"simulation": {
			"physics_ticks_per_second": 240,
			"paused": False,
			"crash": False,
			"fault": "",
			"read_raw_calls": 112,
			"ticks": 12,
			"elapsed_time_s": 0.05,
			"measured_wall_s": 0.05025,
			"wall_ratio": 0.05 / 0.05025,
		},
		"raw_metrics": {
			"input_read_calls": [100, 104, 108, 112],
			"sim_tick": [100, 104, 108, 112],
			"sim_time_s": [100 / 240, 104 / 240, 108 / 240, 112 / 240],
			"process_time_s": [0.001] * frames,
			"physics_process_time_s": [0.001] * frames,
			"draw_calls": [10] * frames,
			"primitives": [100] * frames,
			"visible_draw_calls": [8] * frames,
			"shadow_draw_calls": [2] * frames,
			"visible_primitives": [80] * frames,
			"shadow_primitives": [20] * frames,
			"video_memory_bytes": [1000] * frames,
			"texture_memory_bytes": [500] * frames,
			"buffer_memory_bytes": [500] * frames,
			"cpu_static_memory_bytes": [2000] * frames,
			"render_cpu_ms": [0.5] * frames,
			"render_gpu_ms": [0.0] * frames,
		},
		"build": {
			"adapter": "fixture GPU",
			"api": "fixture API",
			"frame_samples_sha256": "frame-source-hash",
			"viewport_render_timing": {
				"cpu": {"available": True},
				"gpu": {"available": False},
			},
			"render_memory": {"available": {"cpu_static": True, "video": True, "textures": True, "buffers": True}},
		},
		"frames": frames,
		"frame_ms": {"p50": 16.6, "p95": 16.7, "p99": 16.8, "max": 17.0},
		"measured_render": {
			"cpu_render_ms": {"p95": 0.5},
			"gpu_render_ms": {"p95": 0.0},
		},
	}


class FlightQualityTests(unittest.TestCase):
	def test_legacy_resume_receipt_checks_project_and_measurement_harness_identities(self) -> None:
		current = {
			"engine_sha256": "e" * 64,
			"projects": {
				"baseline": {"sha256": "a" * 64, "files": 1},
				"candidate": {"sha256": "b" * 64, "files": 1},
			},
			"harness_sha256": {
				"flight_quality.py": "c" * 64,
				"flight_quality_common.py": "d" * 64,
				"flight_quality_probe.gd": "f" * 64,
			},
		}
		receipt = {
			"baseline": {"sha256": "a" * 64, "files": 1, "file_manifest": {"main.tscn": {}}},
			"candidate": {"sha256": "b" * 64, "files": 1, "file_manifest": {"main.tscn": {}}},
			"harness": {
				"flight_quality.py": "1" * 64,
				"flight_quality_common.py": "d" * 64,
				"flight_quality_probe.gd": "f" * 64,
			},
		}
		self.assertEqual(legacy_receipt_failures(receipt, current), [])
		changed_project = copy.deepcopy(current)
		changed_project["projects"]["candidate"]["sha256"] = "9" * 64
		self.assertTrue(any("candidate fingerprint" in error for error in legacy_receipt_failures(receipt, changed_project)))
		changed_probe = copy.deepcopy(current)
		changed_probe["harness_sha256"]["flight_quality_probe.gd"] = "8" * 64
		self.assertTrue(any("flight_quality_probe.gd" in error for error in legacy_receipt_failures(receipt, changed_probe)))

	def test_resume_contract_rejects_changed_settings_and_environment(self) -> None:
		with tempfile.TemporaryDirectory() as temporary:
			root = Path(temporary)
			args = parser().parse_args([
				"--baseline", str(root / "baseline"), "--candidate", str(root / "candidate"),
				"--engine", str(root / "godot.exe"), "--out", str(root / "series"),
			])
			identities = {
				"engine_sha256": "e" * 64,
				"projects": {
					"baseline": {"sha256": "a" * 64, "files": 1},
					"candidate": {"sha256": "b" * 64, "files": 1},
				},
				"harness_sha256": {"flight_quality.py": "c" * 64, "flight_quality_common.py": "d" * 64, "flight_quality_probe.gd": "f" * 64},
			}
			report = {
				"format": "openrc-tree-flight-quality-series-v1", "status": "incomplete",
				"out": str((root / "series").resolve()), "engine": str((root / "godot.exe").resolve()),
				"engine_sha256": identities["engine_sha256"],
				"projects": {"baseline": str((root / "baseline").resolve()), "candidate": str((root / "candidate").resolve())},
				"environment_overrides": {"baseline": {"OPENRC_TREE_WIND": "off"}, "candidate": {"OPENRC_TREE_WIND": "on"}},
				"settings": series_settings(args), "source_identities": identities,
			}
			wrong_settings = copy.deepcopy(report)
			wrong_settings["settings"]["sample_s"] = 30.0
			failures = resume_contract_failures(
				wrong_settings, args=args, out=root / "series", engine=root / "godot.exe",
				projects={"baseline": root / "baseline", "candidate": root / "candidate"},
				baseline_environment={"OPENRC_TREE_WIND": "off"}, candidate_environment={"OPENRC_TREE_WIND": "on"},
				current_identities=identities, receipt=None,
			)
			self.assertTrue(any("sample_s" in error for error in failures))
			legacy_settings = copy.deepcopy(report)
			legacy_settings["settings"].pop("timeout_s")
			args.timeout = 300.0
			failures = resume_contract_failures(
				legacy_settings, args=args, out=root / "series", engine=root / "godot.exe",
				projects={"baseline": root / "baseline", "candidate": root / "candidate"},
				baseline_environment={"OPENRC_TREE_WIND": "off"}, candidate_environment={"OPENRC_TREE_WIND": "on"},
				current_identities=identities, receipt=None,
			)
			self.assertTrue(any("historical 600-second default" in error for error in failures))
			args.timeout = 600.0
			wrong_environment = copy.deepcopy(report)
			wrong_environment["environment_overrides"]["candidate"]["OPENRC_TREE_WIND"] = "off"
			failures = resume_contract_failures(
				wrong_environment, args=args, out=root / "series", engine=root / "godot.exe",
				projects={"baseline": root / "baseline", "candidate": root / "candidate"},
				baseline_environment={"OPENRC_TREE_WIND": "off"}, candidate_environment={"OPENRC_TREE_WIND": "on"},
				current_identities=identities, receipt=None,
			)
			self.assertTrue(any("environment overrides" in error for error in failures))

	def test_resume_reuses_whole_pairs_and_retains_failed_attempts(self) -> None:
		with tempfile.TemporaryDirectory() as temporary:
			root = Path(temporary)
			out = root / "series"
			out.mkdir()
			engine = root / "godot.exe"
			baseline = root / "baseline"
			candidate = root / "candidate"
			engine.touch()
			baseline.mkdir()
			candidate.mkdir()
			receipt_path = root / "source-receipt.json"
			args = parser().parse_args([
				"--baseline", str(baseline), "--candidate", str(candidate), "--engine", str(engine), "--out", str(out),
				"--resume", "--resume-source-receipt", str(receipt_path), "--pairs", "5", "--warmup", "0", "--sample", "0.067",
			])
			identities = {
				"engine_sha256": "e" * 64,
				"projects": {
					"baseline": {"sha256": "a" * 64, "files": 1},
					"candidate": {"sha256": "b" * 64, "files": 1},
				},
				"harness_sha256": {"flight_quality.py": "c" * 64, "flight_quality_common.py": "d" * 64, "flight_quality_probe.gd": "f" * 64},
			}
			receipt = {
				"baseline": {"sha256": "a" * 64, "files": 1, "file_manifest": {"main.tscn": {"sha256": "1" * 64}}},
				"candidate": {"sha256": "b" * 64, "files": 1, "file_manifest": {"main.tscn": {"sha256": "2" * 64}}},
				"harness": {"flight_quality.py": "9" * 64, "flight_quality_common.py": "d" * 64, "flight_quality_probe.gd": "f" * 64},
			}
			write_json(receipt_path, receipt)
			settings = series_settings(args)
			settings.pop("timeout_s")  # Legacy series did not save the external process timeout.
			root_report = {
				"format": "openrc-tree-flight-quality-series-v1", "status": "incomplete",
				"out": str(out.resolve()), "engine": str(engine.resolve()), "engine_sha256": identities["engine_sha256"],
				"projects": {"baseline": str(baseline.resolve()), "candidate": str(candidate.resolve())},
				"environment_overrides": {"baseline": {"OPENRC_TREE_WIND": "off"}, "candidate": {"OPENRC_TREE_WIND": "on"}},
				"settings": settings, "runs": [], "pairs": [],
			}
			for pair_number, order in enumerate(alternating_orders(5)[:3], start=1):
				entries = []
				for order_index, build_name in enumerate(order, start=1):
					run_id = f"pair-{pair_number:02d}-{order_index}-{build_name}"
					report_path = out / "runs" / run_id / "frametimes.json"
					report_path.parent.mkdir(parents=True, exist_ok=True)
					write_json(report_path, {"retained": run_id})
					entry = {
						"run_id": run_id, "pair": pair_number, "build_name": build_name, "order_in_pair": order_index,
						"complete": True, "failures": [], "report_path": str(report_path), "frame_report_sha256": sha256_file(report_path),
						"frame_samples_sha256": "frame-source-hash", "scenario_sha256": "b" * 64, "input_tape_sha256": "a" * 64,
						"summary": valid_frame_report(),
					}
					root_report["runs"].append(entry)
					entries.append(entry)
				comparison = compare_pair(entries[0], entries[1])
				comparison["attempt"] = 1
				root_report["pairs"].append(comparison)
		# The old failed candidate attempt remains in history and on disk.
			failed_id = "pair-04-1-candidate"
			failed_report = out / "runs" / failed_id / "frametimes.json"
			failed_report.parent.mkdir(parents=True, exist_ok=True)
			failed_report.write_text("partial report", encoding="utf-8")
			root_report["runs"].append({
				"run_id": failed_id, "pair": 4, "build_name": "candidate", "order_in_pair": 1,
				"complete": False, "failures": ["Godot exited with status 1"], "report_path": str(failed_report),
			})
			write_json(out / "series.json", root_report)
			old_runs = copy.deepcopy(root_report["runs"])
			old_pairs = copy.deepcopy(root_report["pairs"])
			calls: list[str] = []

			def fake_run_godot(command, *, log_path, timeout_s, environment):
				run_id = next(arg.split("=", 1)[1] for arg in command if arg.startswith("--case="))
				calls.append(run_id)
				report_argument = next(arg for arg in command if arg.startswith("--report="))
				report = valid_frame_report()
				report["route_id"] = "performance-neutral-trim"
				write_json(Path(report_argument.split("=", 1)[1]), report)
				return {"timed_out": False, "exit_code": 0, "contains_error": False, "output": ""}

			stdout = io.StringIO()
			with patch("flight_quality.validate_engine_and_project"), patch("flight_quality.source_identities", return_value=identities), \
				patch("flight_quality.run_godot", side_effect=fake_run_godot), contextlib.redirect_stdout(stdout):
				self.assertEqual(main([
					"--baseline", str(baseline), "--candidate", str(candidate), "--engine", str(engine), "--out", str(out),
					"--resume", "--resume-source-receipt", str(receipt_path), "--pairs", "5", "--warmup", "0", "--sample", "0.067",
				]), 0)
			resumed = json.loads((out / "series.json").read_text(encoding="utf-8"))
			self.assertEqual(calls, [
				"pair-04-attempt-02-1-candidate", "pair-04-attempt-02-2-baseline",
				"pair-05-1-baseline", "pair-05-2-candidate",
			])
			self.assertEqual(resumed["runs"][:len(old_runs)], old_runs)
			self.assertEqual(resumed["pairs"][:len(old_pairs)], old_pairs)
			self.assertEqual(len(resumed["pairs"]), 5)
			self.assertEqual(resumed["status"], "collected")
			self.assertTrue(failed_report.is_file())
			self.assertEqual(failed_report.read_text(encoding="utf-8"), "partial report")

	def test_runs_alternate_first_build_order(self) -> None:
		self.assertEqual(alternating_orders(5), [
			("baseline", "candidate"),
			("candidate", "baseline"),
			("baseline", "candidate"),
			("candidate", "baseline"),
			("baseline", "candidate"),
		])
		with self.assertRaises(ValueError):
			alternating_orders(0)

	def test_unknown_or_duplicate_environment_selectors_are_rejected(self) -> None:
		self.assertEqual(parse_environment(["OPENRC_TREE_WIND=off", "OPENRC_GRASS_QUALITY=enhanced"]), {
			"OPENRC_TREE_WIND": "off",
			"OPENRC_GRASS_QUALITY": "enhanced",
		})
		with self.assertRaises(ValueError):
			parse_environment(["OPENRC_UNKNOWN=on"])
		with self.assertRaises(ValueError):
			parse_environment(["OPENRC_TREE_WIND=off", "OPENRC_TREE_WIND=on"])

	def test_engine_error_text_fails_independently_of_exit_code(self) -> None:
		self.assertTrue(contains_engine_error("Godot exited normally\nERROR: renderer fixture failed"))
		self.assertFalse(contains_engine_error("All frames captured successfully"))

	def test_live_report_requires_matching_tick_rate_and_timer_samples(self) -> None:
		report = valid_frame_report()
		self.assertEqual(validate_frame_report(report), [])
		report["simulation"]["measured_wall_s"] = 0.04
		report["simulation"]["wall_ratio"] = 1.25
		self.assertTrue(any("monotonic frame-end timestamps" in error for error in validate_frame_report(report)))
		report = valid_frame_report()
		report["simulation"]["physics_ticks_per_second"] = 120
		self.assertTrue(any("tick rate" in error for error in validate_frame_report(report)))
		report = valid_frame_report()
		report["build"]["viewport_render_timing"]["gpu"]["available"] = True
		self.assertTrue(any("GPU viewport timer availability" in error for error in validate_frame_report(report)))

	def test_pair_comparison_uses_raw_frame_and_render_timing_summaries(self) -> None:
		baseline = {
			"build_name": "baseline", "pair": 1,
			"summary": valid_frame_report(),
		"frame_samples_sha256": "frame-source-hash",
		"scenario_sha256": "b" * 64,
		"input_tape_sha256": "a" * 64,
		}
		candidate = {
			"build_name": "candidate", "pair": 1,
			"summary": valid_frame_report(),
			"frame_samples_sha256": "frame-source-hash",
			"scenario_sha256": "b" * 64,
			"input_tape_sha256": "a" * 64,
		}
		candidate["summary"]["frame_ms"]["p95"] = 17.0
		comparison = compare_pair(baseline, candidate)
		self.assertAlmostEqual(comparison["frame_ms"]["p95"]["delta_candidate_minus_baseline"], 0.3)
		self.assertEqual(comparison["cpu_render_ms_p95"]["candidate"], 0.5)
		self.assertEqual(comparison["gpu_render_ms_p95"]["candidate"], 0.0)
		self.assertEqual(pair_identity_failures(baseline, candidate), [])
		candidate["input_tape_sha256"] = "c" * 64
		self.assertTrue(any("input route tapes" in error for error in pair_identity_failures(baseline, candidate)))

	def test_temporal_routes_describe_controls_not_unverified_forest_traversal(self) -> None:
		self.assertEqual(len(ROUTES), 5)
		self.assertNotIn("approach-retreat", ROUTES)
		self.assertNotIn("lateral-flight", ROUTES)
		self.assertEqual(parse_resolutions("720,1080"), [720, 1080])
		with self.assertRaises(ValueError):
			parse_resolutions("480")


if __name__ == "__main__":
	unittest.main()
