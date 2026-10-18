from __future__ import annotations

import argparse
import json
import tempfile
import unittest
from pathlib import Path
import sys
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "research" / "performance"))

import native_summary  # noqa: E402
import test_native_summary  # noqa: E402
import profile_session  # noqa: E402


def reduce_fixture(directory: Path, report: dict, name: str = "run-01") -> dict:
    report_path = test_native_summary.write_run(directory, name, report)
    return native_summary.summarize_run(report_path, native_summary.DEFAULT_POLICY)


def grass_contract_report(variant: str) -> dict:
    enhanced = variant == "enhanced"
    species_counts = (
        {"grass_common_short": 100, "grass_common_tall": 30, "grass_wispy_tall": 20}
        if enhanced else
        {"grass_common_short": 67, "grass_common_tall": 42, "grass_wispy_tall": 41}
    )
    shader_paths = ["res://scenery/imported_grass.gdshader"] if enhanced else []
    return {
        "route": "live-input",
        "godot": "4.7.2.stable.official",
        "backend": "gl_compatibility",
        "window": "1280x720",
        "camera": {"viewport": [1280, 720], "autozoom": False, "mode": "pilot"},
        "render_settings": {"msaa_3d": 2},
        "effective_grass": {
            "format": "openrc-effective-grass-state v1",
            "verified": True,
            "errors": [],
            "scenery": {"enabled": True, "quality": "high"},
            "ground": {
                "shader_path": "res://render/ground.gdshader",
                "shader_sha256": "a" * 64,
                "material_count": 1,
                "grass_photo_enabled": enhanced,
                "turf_detail_enabled": True,
                "turf_detail_strength": 1.0,
                "texture_bindings": {
                    "turf_detail": {
                        "bound": True,
                        "resource_path": "res://assets/landscape/turf/detail.png",
                    },
                    "rc_grass_albedo": {
                        "bound": enhanced,
                        "resource_path": "res://assets/landscape/rc-ground/grass-albedo.jpg" if enhanced else "",
                    },
                    "rc_grass_normal": {
                        "bound": enhanced,
                        "resource_path": "res://assets/landscape/rc-ground/grass-normal.jpg" if enhanced else "",
                    },
                    "rc_grass_roughness": {
                        "bound": enhanced,
                        "resource_path": "res://assets/landscape/rc-ground/grass-roughness.jpg" if enhanced else "",
                    },
                },
                "normal_texture_paths": ["res://assets/landscape/rc-ground/grass-normal.jpg"] if enhanced else [],
                "roughness_texture_paths": ["res://assets/landscape/rc-ground/grass-roughness.jpg"] if enhanced else [],
            },
            "near_grass": {
                "present": True,
                "route": "imported",
                "material_variant": "qualified-wind" if enhanced else "source-static",
                "grass_wind": enhanced,
                "quality": "high",
                "batch_count": 3,
                "clump_count": 150,
                "source_triangles": 37_720 if enhanced else 49_579,
                "species_counts": species_counts,
                "shader_paths": shader_paths,
                "material_bindings": [{
                    "class": "ShaderMaterial" if enhanced else "StandardMaterial3D",
                    "resource_path": "",
                    "shader_path": shader_paths[0] if enhanced else "",
                    "shader_sha256": "b" * 64 if enhanced else "",
                    "texture_paths": ["res://assets/grass/albedo.png"],
                }],
                "texture_paths": ["res://assets/grass/albedo.png"],
            },
        },
    }


class ProfileOrderTests(unittest.TestCase):
    def test_windows_runtime_change_is_detected_with_unchanged_console_launcher(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            console = folder / "Godot_console.exe"
            runtime = folder / "Godot.exe"
            console.write_bytes(b"unchanged launcher")
            runtime.write_bytes(b"engine version one")
            before = profile_session.engine_binary_snapshot(console)
            runtime.write_bytes(b"engine version two")
            after = profile_session.engine_binary_snapshot(console)
            self.assertEqual(before[str(console.resolve())], after[str(console.resolve())])
            self.assertNotEqual(before, after)
            runtime.unlink()
            with self.assertRaises(FileNotFoundError):
                profile_session.engine_binary_snapshot(console)

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

    def test_combined_study_requires_five_pairs_and_defaults_to_five(self):
        with self.assertRaisesRegex(ValueError, "at least 5"):
            profile_session.validate_pair_count(4)
        profile_session.validate_pair_count(5)
        arguments = profile_session._parser().parse_args(["--out", "out"])
        self.assertEqual(arguments.pairs, 5)

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
    def test_effective_live_input_route_is_checked(self):
        report = grass_contract_report("default")
        self.assertEqual(profile_session.validate_report_contract(report, "default"), [])
        report["route"] = "scripted-fixed"
        self.assertIn(
            "effective frametime route is not live-input",
            profile_session.validate_report_contract(report, "default"),
        )

    def test_effective_grass_contract_requires_each_variant_and_compares_shared_settings(self):
        default = grass_contract_report("default")
        enhanced = grass_contract_report("enhanced")
        self.assertEqual(profile_session.validate_report_contract(default, "default"), [])
        self.assertEqual(profile_session.validate_report_contract(enhanced, "enhanced"), [])
        self.assertNotEqual(
            default["effective_grass"]["ground"]["grass_photo_enabled"],
            enhanced["effective_grass"]["ground"]["grass_photo_enabled"],
        )
        self.assertNotEqual(
            default["effective_grass"]["near_grass"]["species_counts"],
            enhanced["effective_grass"]["near_grass"]["species_counts"],
        )
        self.assertEqual(
            profile_session.report_identity(default),
            profile_session.report_identity(enhanced),
        )

    def test_effective_grass_contract_rejects_wrong_route_or_variant_specific_features(self):
        report = grass_contract_report("default")
        report["effective_grass"]["near_grass"]["route"] = "procedural-fallback"
        report["effective_grass"]["ground"]["grass_photo_enabled"] = True
        report["effective_grass"]["near_grass"]["species_counts"]["grass_common_short"] = 100
        errors = profile_session.validate_report_contract(report, "default")
        self.assertTrue(any("NearGrass route is not imported" in error for error in errors))
        self.assertTrue(any("grass photo detail is not disabled" in error for error in errors))
        self.assertTrue(any("species counts are incorrect" in error for error in errors))

    def test_enhanced_ground_texture_slots_must_match_their_expected_resources(self):
        mutations = (
            (
                "swapped albedo and normal",
                lambda bindings: (
                    bindings.__setitem__(
                        "rc_grass_albedo",
                        {"bound": True, "resource_path": "res://assets/landscape/rc-ground/grass-normal.jpg"},
                    ),
                    bindings.__setitem__(
                        "rc_grass_normal",
                        {"bound": True, "resource_path": "res://assets/landscape/rc-ground/grass-albedo.jpg"},
                    ),
                ),
                "rc_grass_albedo texture binding is not",
            ),
            (
                "missing enhanced albedo",
                lambda bindings: bindings.__setitem__("rc_grass_albedo", {"bound": False, "resource_path": ""}),
                "rc_grass_albedo texture binding is not",
            ),
            (
                "normal rebound to dirt while legacy path list still claims grass",
                lambda bindings: bindings.__setitem__(
                    "rc_grass_normal",
                    {"bound": True, "resource_path": "res://assets/landscape/rc-ground/dirt-normal.jpg"},
                ),
                "rc_grass_normal texture binding is not",
            ),
        )
        for label, mutate, expected_error in mutations:
            with self.subTest(label=label):
                report = grass_contract_report("enhanced")
                bindings = report["effective_grass"]["ground"]["texture_bindings"]
                mutate(bindings)
                errors = profile_session.validate_report_contract(report, "enhanced")
                self.assertTrue(any(expected_error in error for error in errors), errors)

    def test_baseline_and_enhanced_ground_require_the_expected_turf_detail_slot(self):
        for variant in ("default", "enhanced"):
            with self.subTest(variant=variant):
                report = grass_contract_report(variant)
                report["effective_grass"]["ground"]["texture_bindings"]["turf_detail"] = {
                    "bound": True,
                    "resource_path": "res://assets/landscape/rc-ground/grass-albedo.jpg",
                }
                errors = profile_session.validate_report_contract(report, variant)
                self.assertTrue(any("turf_detail texture binding is not" in error for error in errors), errors)

    def test_variant_run_requires_observed_grass_scene(self):
        report = grass_contract_report("enhanced")
        report.pop("effective_grass")
        self.assertIn(
            "effective grass scene metadata is missing",
            profile_session.validate_report_contract(report, "enhanced"),
        )

    def test_windows_inventory_uses_hidden_tasklist_csv_and_finds_godot(self):
        output = (
            '"Godot_v4.7.2-stable_win64_console.exe","12796","Console","1,024 K"\r\n'
            '"editor.exe","8","Console","2,048 K"\r\n'
        )
        with patch.object(profile_session.platform, "system", return_value="Windows"), patch.object(
            profile_session.subprocess,
            "run",
            return_value=SimpleNamespace(returncode=0, stdout=output, stderr=""),
        ) as run:
            inventory = profile_session.godot_process_inventory()

        self.assertEqual(run.call_args.args[0], ["tasklist", "/FO", "CSV", "/NH"])
        self.assertEqual(run.call_args.kwargs["creationflags"], getattr(profile_session.subprocess, "CREATE_NO_WINDOW", 0x08000000))
        self.assertEqual(inventory["godot_processes"], [
            {"image": "Godot_v4.7.2-stable_win64_console.exe", "pid": "12796"}
        ])

    def test_preflight_stops_before_second_launch_and_preserves_first_report(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            app = root / "app"
            app.mkdir()
            (app / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            godot = root / "Godot_v4.7.2-stable_win64_console.exe"
            godot.write_bytes(b"test engine identity")
            (root / "Godot_v4.7.2-stable_win64.exe").write_bytes(b"test runtime identity")
            output = root / "campaign"
            args = argparse.Namespace(app=app, godot=godot, out=output, pairs=5, timeout=180)
            inventories = iter((
                {
                    "status": "available", "platform": "Windows", "scope": "test process inventory",
                    "command": ["tasklist"], "timeout_s": 10, "godot_processes": [],
                },
                {
                    "status": "available", "platform": "Windows", "scope": "test process inventory",
                    "command": ["tasklist"], "timeout_s": 10,
                    "godot_processes": [{"image": "Godot_v4.7.2-stable_win64_console.exe", "pid": "12796"}],
                },
            ))

            def fake_launch(**kwargs):
                kwargs["report_path"].write_text('{"preserved": true}\n', encoding="utf-8")
                kwargs["log_path"].write_text("preserved raw log\n", encoding="utf-8")
                return {
                    "id": f"pair-{kwargs['pair_index']:02d}-{kwargs['variant']}",
                    "variant": kwargs["variant"],
                    "report_identity": {"godot": "4.7.2.stable.official"},
                    "rejection_reasons": [],
                    "interrupted": False,
                    "metrics": {"frame_ms": {"p95": 16.0, "p99": 20.0}},
                }

            with patch.object(
                profile_session, "godot_process_inventory", side_effect=lambda: next(inventories)
            ) as inventory_check, patch.object(
                profile_session, "_launch_and_summarize", side_effect=fake_launch
            ) as launch:
                with self.assertRaisesRegex(profile_session.CampaignStop, "PID 12796"):
                    profile_session.run_campaign(args)

            campaign = json.loads((output / "campaign.json").read_text(encoding="utf-8"))
            first_report = output / "runs" / "default" / "run-01-default.json"
            first_log = output / "runs" / "default" / "run-01-default.log"
            self.assertEqual(inventory_check.call_count, 2)
            self.assertEqual(launch.call_count, 1)
            self.assertEqual(first_report.read_text(encoding="utf-8"), '{"preserved": true}\n')
            self.assertEqual(first_log.read_text(encoding="utf-8"), "preserved raw log\n")
            self.assertEqual(campaign["status"], "stopped")
            self.assertIn("PID 12796", campaign["stop_reason"])
            self.assertEqual(campaign["pairs"][0]["status"], "stopped_preflight")
            self.assertFalse(campaign["pairs"][0]["qualified"])
            self.assertEqual(campaign["comparison"]["complete_pair_count"], 0)
            self.assertFalse(campaign["comparison"]["minimum_pairs_met"])
            self.assertEqual(len(campaign["runs"]), 1)

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


class CampaignFailureTests(unittest.TestCase):
    @staticmethod
    def make_campaign_inputs(root: Path) -> argparse.Namespace:
        app = root / "app"
        app.mkdir()
        (app / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        godot = root / "godot.exe"
        godot.write_bytes(b"test engine identity")
        return argparse.Namespace(
            app=app,
            godot=godot,
            out=root / "campaign",
            pairs=5,
            timeout=180,
        )

    @staticmethod
    def available_inventory() -> dict:
        return {
            "status": "available",
            "platform": "Windows",
            "scope": "test process inventory",
            "command": ["tasklist"],
            "timeout_s": 10,
            "godot_processes": [],
        }

    def test_missing_native_report_is_retained_as_invalid_run_and_stops_campaign(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            args = self.make_campaign_inputs(root)

            def fake_popen(_command, **kwargs):
                kwargs["stdout"].write(b"ERROR: flight ended after the throttle closed\n")
                return SimpleNamespace(returncode=0, wait=lambda timeout: 0, poll=lambda: 0)

            with patch.object(
                profile_session, "godot_process_inventory", return_value=self.available_inventory()
            ), patch.object(profile_session.platform, "platform", return_value="Windows-Test"), patch.object(
                profile_session.platform, "machine", return_value="AMD64"
            ), patch.object(profile_session.subprocess, "Popen", side_effect=fake_popen):
                with self.assertRaisesRegex(profile_session.CampaignStop, "frame-time report is missing"):
                    profile_session.run_campaign(args)

            campaign = json.loads((args.out / "campaign.json").read_text(encoding="utf-8"))
            run = campaign["runs"][0]
            raw_log = args.out / "runs" / "default" / "run-01-default.log"
            self.assertEqual(campaign["status"], "stopped")
            self.assertFalse(campaign["complete"])
            self.assertTrue(campaign["finished_utc"])
            self.assertEqual(campaign["pairs"][0]["status"], "stopped_ineligible")
            self.assertEqual(len(campaign["runs"]), 1)
            self.assertIsNone(run["individual_pacing_pass"])
            self.assertIsNone(run["native_summary"]["pacing_gate"])
            self.assertTrue(any("report is missing" in reason for reason in run["rejection_reasons"]))
            self.assertIn("ERROR: flight ended after the throttle closed", raw_log.read_text(encoding="utf-8"))

    def test_unexpected_collection_exception_finalizes_campaign_and_keeps_attempt_paths(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            args = self.make_campaign_inputs(root)

            def fail_after_writing_evidence(**kwargs):
                kwargs["report_path"].write_text("partial report\n", encoding="utf-8")
                kwargs["log_path"].write_text("raw log\n", encoding="utf-8")
                raise AttributeError("simulated report reducer failure")

            with patch.object(
                profile_session, "godot_process_inventory", return_value=self.available_inventory()
            ), patch.object(profile_session, "_launch_and_summarize", side_effect=fail_after_writing_evidence):
                with self.assertRaisesRegex(profile_session.CampaignStop, "simulated report reducer failure"):
                    profile_session.run_campaign(args)

            campaign = json.loads((args.out / "campaign.json").read_text(encoding="utf-8"))
            failed_attempt = campaign["failed_attempt"]
            self.assertEqual(campaign["status"], "stopped")
            self.assertFalse(campaign["complete"])
            self.assertTrue(campaign["finished_utc"])
            self.assertEqual(campaign["pairs"][0]["status"], "stopped_error")
            self.assertFalse(campaign["pairs"][0]["qualified"])
            self.assertNotIn("current_attempt", campaign)
            self.assertTrue(Path(failed_attempt["report"]).is_file())
            self.assertTrue(Path(failed_attempt["log"]).is_file())
            self.assertIn("AttributeError", campaign["stop_reason"])

    def test_keyboard_interrupt_finalizes_pair_and_preserves_current_attempt(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            args = self.make_campaign_inputs(root)
            with patch.object(
                profile_session, "godot_process_inventory", side_effect=KeyboardInterrupt
            ), patch.object(profile_session.platform, "platform", return_value="Windows-Test"), patch.object(
                profile_session.platform, "machine", return_value="AMD64"
            ):
                with self.assertRaisesRegex(profile_session.CampaignStop, "campaign interrupted by the operator"):
                    profile_session.run_campaign(args)

            campaign = json.loads((args.out / "campaign.json").read_text(encoding="utf-8"))
            self.assertEqual(campaign["status"], "stopped")
            self.assertFalse(campaign["complete"])
            self.assertEqual(campaign["pairs"][0]["status"], "stopped_interrupted")
            self.assertFalse(campaign["pairs"][0]["qualified"])
            self.assertNotIn("current_attempt", campaign)
            self.assertEqual(campaign["failed_attempt"]["variant"], "default")
            self.assertIn("campaign interrupted by the operator", campaign["stop_reason"])

    def test_interrupted_run_marks_its_pair_terminal(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            args = self.make_campaign_inputs(root)

            def interrupted_launch(**kwargs):
                return {
                    "id": f"pair-{kwargs['pair_index']:02d}-{kwargs['variant']}",
                    "variant": kwargs["variant"],
                    "report_identity": {},
                    "rejection_reasons": [],
                    "eligible_for_pair": True,
                    "interrupted": True,
                    "metrics": {},
                }

            with patch.object(
                profile_session, "godot_process_inventory", return_value=self.available_inventory()
            ), patch.object(
                profile_session, "_launch_and_summarize", side_effect=interrupted_launch
            ):
                with self.assertRaisesRegex(profile_session.CampaignStop, "campaign interrupted by the operator"):
                    profile_session.run_campaign(args)

            campaign = json.loads((args.out / "campaign.json").read_text(encoding="utf-8"))
            self.assertEqual(campaign["status"], "stopped")
            self.assertFalse(campaign["complete"])
            self.assertEqual(campaign["pairs"][0]["status"], "stopped_interrupted")
            self.assertFalse(campaign["pairs"][0]["qualified"])
            self.assertEqual(len(campaign["runs"]), 1)

    def test_final_provenance_error_is_appended_to_original_stop_reason(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            args = self.make_campaign_inputs(root)
            snapshot_calls = 0

            def fail_final_snapshot(_app):
                nonlocal snapshot_calls
                snapshot_calls += 1
                if snapshot_calls == 1:
                    return {"app": "initial snapshot"}
                raise OSError("final source tree became unavailable")

            def invalid_launch(**kwargs):
                return {
                    "id": f"pair-{kwargs['pair_index']:02d}-{kwargs['variant']}",
                    "variant": kwargs["variant"],
                    "report_identity": {},
                    "rejection_reasons": ["native frame report is invalid"],
                    "eligible_for_pair": False,
                    "interrupted": False,
                    "metrics": {},
                }

            with patch.object(
                profile_session, "godot_process_inventory", return_value=self.available_inventory()
            ), patch.object(
                profile_session, "_launch_and_summarize", side_effect=invalid_launch
            ), patch.object(profile_session, "app_runtime_snapshot", side_effect=fail_final_snapshot):
                with self.assertRaisesRegex(profile_session.CampaignStop, "native frame report is invalid"):
                    profile_session.run_campaign(args)

            campaign = json.loads((args.out / "campaign.json").read_text(encoding="utf-8"))
            self.assertEqual(campaign["status"], "stopped")
            self.assertFalse(campaign["complete"])
            self.assertIn("pair-01-default rejected: native frame report is invalid", campaign["stop_reason"])
            self.assertIn("final provenance snapshot failed: final source tree became unavailable", campaign["stop_reason"])


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

    def test_external_buffers_and_native_extension_binaries_are_hashed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            app = Path(temp_dir) / "app"
            binary_dir = app / "native" / "ground_vehicle"
            binary_dir.mkdir(parents=True)
            asset_names = (
                "mesh.bin",
                "ground_vehicle.dll",
                "ground_vehicle.so",
                "ground_vehicle.dylib",
            )
            for asset_name in asset_names:
                (binary_dir / asset_name).write_bytes(b"original binary data")

            before = profile_session.app_runtime_snapshot(app)
            for asset_name in asset_names:
                self.assertIn(f"native/ground_vehicle/{asset_name}", before["files_sha256"])

            changed = binary_dir / "ground_vehicle.dll"
            changed.write_bytes(b"changed native extension")
            after = profile_session.app_runtime_snapshot(app)
            self.assertNotEqual(
                before["files_sha256"]["native/ground_vehicle/ground_vehicle.dll"],
                after["files_sha256"]["native/ground_vehicle/ground_vehicle.dll"],
            )
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
            (4, 19.0, 17.0, 25.0, 23.0),
            (5, 21.0, 20.0, 27.0, 26.0),
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
