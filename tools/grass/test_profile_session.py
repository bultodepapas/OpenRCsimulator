from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "research" / "performance"))

import native_summary  # noqa: E402
import test_native_summary  # noqa: E402
import profile_session  # noqa: E402


def reduce_fixture(directory: Path, report: dict, name: str = "run-01") -> dict:
    report_path = test_native_summary.write_run(directory, name, report)
    return native_summary.summarize_run(report_path, native_summary.DEFAULT_POLICY)


class ProfileOrderTests(unittest.TestCase):
    def test_order_alternates_ab_ba_for_pairs(self):
        self.assertEqual(
            [profile_session.pair_order(index) for index in range(1, 7)],
            [
                ("default", "enhanced"),
                ("enhanced", "default"),
                ("default", "enhanced"),
                ("enhanced", "default"),
                ("default", "enhanced"),
                ("enhanced", "default"),
            ],
        )

    def test_requested_pair_count_below_three_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "at least 3"):
            profile_session.validate_pair_count(2)

    def test_command_keeps_live_route_and_pins_render_conditions(self):
        command = profile_session.build_command(
            Path("godot.exe"), Path("app"), Path("out/run-01-default.json")
        )
        self.assertIn("--rendering-method", command)
        self.assertIn("gl_compatibility", command)
        self.assertIn("--rendering-driver", command)
        self.assertIn("opengl3", command)
        self.assertIn("--resolution", command)
        self.assertIn("1280x720", command)
        self.assertIn("--max-fps", command)
        self.assertIn("60", command)
        self.assertIn("--start=airborne", command)
        self.assertIn("--autozoom=0", command)
        self.assertIn("--scenery=on", command)
        self.assertIn("--scenery_quality=high", command)
        self.assertFalse(any("scripted" in argument or "focus" in argument.lower() for argument in command))

    def test_only_child_grass_selector_varies(self):
        parent = {"PATH": "keep-this", "OPENRC_SCENERY": "on", profile_session.GRASS_SELECTOR: "stale"}
        default = profile_session.child_environment("default", parent)
        enhanced = profile_session.child_environment("enhanced", parent)
        self.assertNotIn(profile_session.GRASS_SELECTOR, default)
        self.assertEqual(enhanced[profile_session.GRASS_SELECTOR], "enhanced")
        for key in parent.keys() - {profile_session.GRASS_SELECTOR}:
            self.assertEqual(default[key], parent[key])
            self.assertEqual(enhanced[key], parent[key])
        self.assertEqual(parent[profile_session.GRASS_SELECTOR], "stale")


class RunEligibilityTests(unittest.TestCase):
    def test_nonzero_abort_rejects_even_a_valid_native_report(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            summary = reduce_fixture(Path(temp_dir), test_native_summary.sustained_report())
        run = {"return_code": 3, "timed_out": False, "interrupted": False, "launch_error": ""}
        reasons = profile_session.run_rejection_reasons(run, summary)
        self.assertTrue(summary["collection_valid"])
        self.assertTrue(summary["active_flight_qualifier"])
        self.assertTrue(any("exit code was 3" in reason for reason in reasons))

    def test_paused_native_run_is_rejected_and_will_stop_acquisition(self):
        report = test_native_summary.sustained_report()
        report["simulation"]["paused"] = True
        with tempfile.TemporaryDirectory() as temp_dir:
            summary = reduce_fixture(Path(temp_dir), report)
        run = {"return_code": 0, "timed_out": False, "interrupted": False, "launch_error": ""}
        reasons = profile_session.run_rejection_reasons(run, summary)
        self.assertTrue(summary["collection_valid"])
        self.assertFalse(summary["active_flight_qualifier"])
        self.assertTrue(any("simulation was paused" in reason for reason in reasons))

    def test_eligible_run_with_pacing_miss_is_not_discarded(self):
        report = test_native_summary.valid_report(
            interval_usec=20_000,
            ticks=[240 + 4 * index for index in range(3_001)],
            sample_s=60.0,
            warmup_s=10.0,
            actual_warmup_s=10.1,
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            summary = reduce_fixture(Path(temp_dir), report)
        run = {"return_code": 0, "timed_out": False, "interrupted": False, "launch_error": ""}
        self.assertTrue(summary["collection_valid"])
        self.assertTrue(summary["active_flight_qualifier"])
        self.assertFalse(summary["pacing_gate"]["pass"])
        self.assertEqual(profile_session.run_rejection_reasons(run, summary), [])


class ProvenanceAndOutputTests(unittest.TestCase):
    def test_changed_runtime_source_invalidates_provenance_but_docs_tests_are_excluded(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app = Path(temp_dir) / "app"
            app.mkdir()
            (app / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            runtime = app / "main.gd"
            runtime.write_text("extends Node\n", encoding="utf-8")
            excluded = app / "docs"
            excluded.mkdir()
            (excluded / "note.md").write_text("first", encoding="utf-8")
            before = profile_session.app_runtime_snapshot(app)
            (excluded / "note.md").write_text("changed docs", encoding="utf-8")
            docs_only = profile_session.app_runtime_snapshot(app)
            self.assertEqual(profile_session.provenance_rejection_reasons(before, docs_only, "a", "a"), [])
            runtime.write_text("extends Node\n# changed runtime\n", encoding="utf-8")
            after = profile_session.app_runtime_snapshot(app)
            reasons = profile_session.provenance_rejection_reasons(before, after, "a", "a")
            self.assertIn("app runtime source/config changed during the campaign", reasons)

    def test_engine_binary_change_invalidates_provenance(self):
        snapshot = {"files_sha256": {"main.gd": "a"}}
        reasons = profile_session.provenance_rejection_reasons(snapshot, snapshot, "old", "new")
        self.assertEqual(reasons, ["Godot executable changed during the campaign"])

    def test_existing_output_is_refused_without_overwriting(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app = Path(temp_dir) / "app"
            app.mkdir()
            out = Path(temp_dir) / "existing"
            out.mkdir()
            marker = out / "retain.txt"
            marker.write_text("leave intact", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "new path"):
                profile_session.ensure_new_output(out, app)
            self.assertEqual(marker.read_text(encoding="utf-8"), "leave intact")

    def test_pair_summary_uses_enhanced_minus_default_medians_only(self):
        pairs = []
        for index, default_p95, enhanced_p95, default_p99, enhanced_p99 in (
            (1, 16.0, 15.0, 20.0, 19.0),
            (2, 17.0, 18.0, 21.0, 20.0),
            (3, 18.0, 15.0, 23.0, 22.0),
        ):
            pairs.append({
                "pair": index,
                "runs": {
                    "default": {"metrics": {"frame_ms": {"p95": default_p95, "p99": default_p99}}},
                    "enhanced": {"metrics": {"frame_ms": {"p95": enhanced_p95, "p99": enhanced_p99}}},
                },
            })
        comparison = profile_session.paired_comparison(pairs)
        self.assertEqual(comparison["median_paired_delta_ms"], {"p95": -1.0, "p99": -1.0})
        self.assertTrue(comparison["minimum_pairs_met"])
        self.assertIn("no grass-only global-budget pass", comparison["decision_scope"])


if __name__ == "__main__":
    unittest.main()
