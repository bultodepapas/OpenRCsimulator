"""Fast validation checks for the active-flight quality harness."""

from __future__ import annotations

import unittest

from flight_quality import alternating_orders, compare_pair, pair_identity_failures
from flight_quality_common import contains_engine_error, parse_environment, validate_frame_report
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
