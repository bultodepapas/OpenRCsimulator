"""Fixed-inventory, provenance, evidence, and frametime tests for VQ-01b."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

import visual_quality_cases as vq


def evidence_for(case):
    visible = case.pilot_visible if case.pilot_visible is not None else True
    return {
        "format": "openrc-visual-evidence v1",
        "case_id": case.case_id,
        "aircraft": case.aircraft,
        "route": case.route,
        "visual_pose": case.visual_pose,
        "visual_distance_m": case.visual_distance_m,
        "distance_to_pilot_m": case.visual_distance_m if case.visual_pose else 31.0,
        "pose": {"position": [1.0, 2.0, 3.0], "basis_columns": [[1.0, 0.0, 0.0]] * 3},
        "camera": {"fov_deg": 50.0, "autozoom": case.autozoom if case.autozoom is not None else False,
                   "mode": "pilot", "viewport": [1280, 720]},
        "exposure": 0.6,
        "light": {"direction": [0.5, 0.5, 0.5], "energy": 1.0, "color": "Color(1, 1, 1, 1)"},
        "clock_s": 1.5,
        "state": {"shadow": "off", "aircraft_visible": visible},
        "seed": {"kind": "not-used"},
        "provenance": {"code_revision": "test-revision", "source_sha256": {"res://main.gd": "a" * 64}},
    }


class VisualQualityCasesTests(unittest.TestCase):
    def test_fixed_inventory_has_exact_66_case_contract(self):
        cases = vq.capture_cases()
        self.assertEqual(len(cases), 66)
        self.assertEqual(len({case.case_id for case in cases}), 66)
        self.assertEqual(sum(case.family == "pilot-readability" for case in cases), 8)
        self.assertEqual(sum(case.family == "field-repeat" for case in cases), 18)
        self.assertEqual(sum(case.family == "synthetic-attitude" for case in cases), 36)
        self.assertEqual(sum(case.family == "ui-route" for case in cases), 4)

    def test_every_flight_case_uses_capture_flag_and_fixed_time(self):
        cases = vq.capture_cases()
        for case in cases:
            if case.kind != "flight":
                continue
            command = vq.build_capture_command(Path("/app"), "/godot", "xvfb-run", Path("/tmp/case.png"), case)
            delimiter = command.index("--")
            self.assertIn("--capture", command[delimiter + 1:], case.case_id)
            self.assertIn("--t=1.5", command[delimiter + 1:], case.case_id)

    def test_pilot_matrix_keeps_four_readability_pairs_shadow_off(self):
        cases = {case.case_id: case for case in vq.capture_cases()}
        for distance in ("30m", "3m"):
            for zoom in ("on", "off"):
                visible = cases[f"pilot-{distance}-autozoom-{zoom}"]
                hidden = cases[f"pilot-{distance}-autozoom-{zoom}-noplane"]
                self.assertEqual(visible.autozoom, zoom == "on")
                self.assertIn("--shadow=off", visible.arguments)
                self.assertIn("--hide_airplane", hidden.arguments)
                if distance == "3m":
                    self.assertIn("--alt=3", visible.arguments)
                else:
                    self.assertNotIn("--alt=3", visible.arguments)

    def test_extra_uses_same_scripted_pilot_inspection_fixture(self):
        cases = [case for case in vq.capture_cases() if case.case_id.startswith("synthetic-extra-")]
        self.assertEqual(len(cases), 18)
        for case in cases:
            self.assertEqual(case.aircraft, "gp-extra-300s-60")
            self.assertEqual(case.route, "synthetic-inspection")
            self.assertIn("--scripted", case.arguments)
            self.assertIn("--autozoom=0", case.arguments)
            self.assertIn("--shadow=off", case.arguments)
            self.assertEqual(sum(arg.startswith("--visual_pose=") for arg in case.arguments), 1)

    def test_synthetic_capture_rejects_actual_distance_mismatch(self):
        case = next(case for case in vq.capture_cases() if case.case_id == "synthetic-extra-50m-inverted")
        manifest = {"capture_scene": "field", "visual_evidence": evidence_for(case)}
        vq.validate_capture_evidence(case, manifest)
        manifest["visual_evidence"]["distance_to_pilot_m"] = 49.99
        with self.assertRaisesRegex(RuntimeError, "actual distance"):
            vq.validate_capture_evidence(case, manifest)

    def test_field_repeat_requires_image_and_counter_parity(self):
        entries = []
        for case in (case for case in vq.capture_cases() if case.family == "field-repeat"):
            entries.append({
                "case_id": case.case_id, "family": case.family,
                "repeat_group": case.repeat_group, "repeat_index": case.repeat_index,
                "sha256": "b" * 64,
                "render_counters": {key: {"visible": 4, "shadow": 0} for key in vq.COUNTER_KEYS},
            })
        checks = vq.validate_field_parity(entries)
        self.assertEqual(len(checks), 9)
        entries[0]["sha256"] = "c" * 64
        with self.assertRaisesRegex(RuntimeError, "PNG hashes differ"):
            vq.validate_field_parity(entries)

    def test_png_inventory_rejects_extra_images_without_deleting_them(self):
        with tempfile.TemporaryDirectory() as temporary:
            output_dir = Path(temporary)
            extra = output_dir / "unlisted.png"
            extra.write_bytes(b"prior evidence")
            with self.assertRaisesRegex(RuntimeError, "PNG inventory mismatch"):
                vq.validate_png_inventory(output_dir, vq.capture_cases())
            self.assertEqual(extra.read_bytes(), b"prior evidence")

    def test_synthetic_matrix_asserts_shared_light_fov_and_exposure(self):
        entries = []
        for case in (case for case in vq.capture_cases() if case.family == "synthetic-attitude"):
            entries.append({"case_id": case.case_id, "family": case.family,
                            "visual_evidence": evidence_for(case)})
        result = vq.validate_synthetic_parity(entries)
        self.assertTrue(result["shared_light_fov_exposure"])
        self.assertEqual(result["case_count"], 36)
        entries[-1]["visual_evidence"]["camera"]["fov_deg"] = 49.0
        with self.assertRaisesRegex(RuntimeError, "light/FOV/exposure"):
            vq.validate_synthetic_parity(entries)

    def test_ui_commands_capture_home_and_flight_in_both_languages(self):
        cases = [case for case in vq.capture_cases() if case.kind == "ui"]
        self.assertEqual({(case.expected_scene, case.language) for case in cases},
                         {(screen, language) for screen in ("home", "flight") for language in ("en", "es")})
        for case in cases:
            command = vq.build_capture_command(Path("/app"), "/godot", "xvfb-run", Path("/tmp/ui.png"), case)
            self.assertIn("res://tests/capture_ui.gd", command)
            self.assertIn(f"--screen={case.expected_scene}", command)
            self.assertIn(f"--lang={case.language}", command)

    def test_frametime_validation_requires_raw_wall_duration_and_route(self):
        report = {
            "format": "openrc-frametimes v2", "complete": True,
            "route": "scripted-fixed", "case_id": "scripted-fixed-repeat1",
            "preset": "current-default", "backend": "gl_compatibility",
            "warmup_s": 10.0, "sample_s": 60.0, "frames": 60,
            "frame_deltas_s": [1.0] * 60, "wall_seconds": 60.0,
        }
        result = vq.validate_frametime_report(report, "scripted-fixed", case_id="scripted-fixed-repeat1")
        self.assertEqual(result["raw_sample_seconds"], 60.0)
        with self.assertRaisesRegex(RuntimeError, "route"):
            vq.validate_frametime_report(report, "live-input")
        with self.assertRaisesRegex(RuntimeError, "case_id"):
            vq.validate_frametime_report(report, "scripted-fixed", case_id="scripted-fixed-repeat2")
        old_report = dict(report)
        old_report.pop("frame_deltas_s")
        with self.assertRaisesRegex(RuntimeError, "raw frame deltas"):
            vq.validate_frametime_report(old_report, "scripted-fixed")
        bad_duration = dict(report, wall_seconds=59.0, frame_deltas_s=[1.0] * 59 + [0.0], frames=60)
        with self.assertRaisesRegex(RuntimeError, "non-positive"):
            vq.validate_frametime_report(bad_duration, "scripted-fixed")
        under_sample = dict(report, wall_seconds=59.9, frame_deltas_s=[1.0] * 58 + [0.9, 1.0])
        with self.assertRaisesRegex(RuntimeError, "shorter than"):
            vq.validate_frametime_report(under_sample, "scripted-fixed")
        bad_duration = dict(report, wall_seconds=59.0)
        with self.assertRaisesRegex(RuntimeError, "sum of frame deltas"):
            vq.validate_frametime_report(bad_duration, "scripted-fixed")
        incomplete = dict(report, complete=False)
        with self.assertRaisesRegex(RuntimeError, "not marked complete"):
            vq.validate_frametime_report(incomplete, "scripted-fixed")
        no_preset = dict(report, preset="")
        with self.assertRaisesRegex(RuntimeError, "preset"):
            vq.validate_frametime_report(no_preset, "scripted-fixed")
        no_backend = dict(report, backend="")
        with self.assertRaisesRegex(RuntimeError, "backend"):
            vq.validate_frametime_report(no_backend, "scripted-fixed")

    def test_frametime_accepts_last_frame_hitch_and_checks_reported_raw_arrays(self):
        deltas = [1.0] * 58 + [1.25, 1.5]
        report = {
            "format": "openrc-frametimes v2", "complete": True,
            "route": "scripted-fixed", "case_id": "scripted-fixed-repeat2",
            "preset": "current-default", "backend": "gl_compatibility",
            "warmup_s": 10.0, "sample_s": 60.0, "frames": len(deltas),
            "frame_deltas_s": deltas, "wall_seconds": sum(deltas),
            "sim_time_s": [1.0] * len(deltas),
            "frame_end_monotonic_usec": list(range(1, len(deltas) + 1)),
        }
        result = vq.validate_frametime_report(report, "scripted-fixed", case_id="scripted-fixed-repeat2")
        self.assertEqual(result["raw_sample_seconds"], 60.75)
        self.assertEqual(result["raw_metric_lengths"]["sim_time_s"], len(deltas))

        bad_metric = dict(report, sim_time_s=[1.0])
        with self.assertRaisesRegex(RuntimeError, "sim_time_s length"):
            vq.validate_frametime_report(bad_metric, "scripted-fixed")
        bad_timestamps = dict(report, frame_end_monotonic_usec=[1] * len(deltas))
        with self.assertRaisesRegex(RuntimeError, "not strictly increasing"):
            vq.validate_frametime_report(bad_timestamps, "scripted-fixed")

    def test_frametime_command_is_fixed_scripted_not_a_flight_replay(self):
        command = vq.build_frametime_command(
            Path("/app"), "/godot", "xvfb-run", Path("/tmp/frame.json"),
            "scripted-fixed", 10.0, 60.0,
        )
        self.assertIn("--scripted", command)
        self.assertIn("--warmup=10", command)
        self.assertIn("--t=60", command)
        self.assertIn("--case=scripted-fixed", command)
        with self.assertRaises(ValueError):
            vq.build_frametime_command(Path("/app"), "/godot", "xvfb-run",
                                       Path("/tmp/frame.json"), "physics-fixed", 10.0, 60.0)

    def test_output_lock_rejects_concurrent_performance_or_capture_runs(self):
        with tempfile.TemporaryDirectory() as temporary:
            output_dir = Path(temporary)
            with vq._output_lock(output_dir):
                with self.assertRaisesRegex(RuntimeError, "another VQ-01b run"):
                    with vq._output_lock(output_dir):
                        pass

    def test_complete_manifest_lists_only_fresh_fixed_inventory(self):
        cases = {case.case_id: case for case in vq.capture_cases()}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app_dir = root / "repo" / "app"
            app_dir.mkdir(parents=True)
            (app_dir / "main.gd").write_text("# fixture\n")
            output_dir = root / "repo" / "captures" / "vq01b"
            output_dir.mkdir(parents=True)

            def fake_run_capture(command, output, kind, scene, timeout=60.0):
                output.parent.mkdir(parents=True, exist_ok=True)
                case_id = next((argument.split("=", 1)[1] for argument in command
                                if argument.startswith("--case=")), "")
                if kind == "ui":
                    screen = next(argument.split("=", 1)[1] for argument in command
                                  if argument.startswith("--screen="))
                    language = next(argument.split("=", 1)[1] for argument in command
                                    if argument.startswith("--lang="))
                    case_id = f"ui-{screen}-{language}"
                case = cases[case_id]
                image = Image.new("RGB", (1280, 720), (36, 103, 153))
                if case.family == "pilot-readability" and case.pilot_visible:
                    ImageDraw.Draw(image).rectangle((620, 350, 635, 360), fill=(220, 25, 35))
                if case.family == "field-repeat":
                    tone = sum(map(ord, case.repeat_group)) % 32
                    image = Image.new("RGB", (1280, 720), (36 + tone, 103, 153))
                image.save(output, format="PNG")
                digest = hashlib.sha256(output.read_bytes()).hexdigest()
                if kind == "ui":
                    ui_evidence = {
                        "state": scene, "route": case.route, "language": language,
                        "viewport": {"camera_3d_count": 1, "world_environment_count": 1,
                                     "active_camera": "/root/Flight/Camera3D" if scene == "flight" else ""},
                    }
                    if scene == "flight":
                        ui_evidence["visual"] = {"camera": {"fov_deg": 50.0}, "clock_s": 1.5}
                    manifest = {"format": "openrc-ui-capture v2", "producer": "capture_ui",
                                "image": output.name, "sha256": digest, "size": [1280, 720],
                                "capture_scene": scene, "ui_evidence": ui_evidence}
                else:
                    camera = {"fov_deg": 50.0, "autozoom": case.autozoom if case.autozoom is not None else False}
                    native_evidence = evidence_for(case)
                    native_evidence["camera"] = camera
                    native_evidence["state"]["aircraft_visible"] = case.pilot_visible if case.pilot_visible is not None else True
                    native_evidence["route"] = case.route
                    manifest = {
                        "image": output.name, "sha256": digest, "capture_scene": scene,
                        "visual_evidence": native_evidence,
                        "draw_calls": {"visible": 3, "shadow": 0},
                        "primitives": {"visible": 5, "shadow": 0},
                        "objects": {"visible": 2, "shadow": 0},
                    }
                    if case.family == "field-repeat":
                        manifest["draw_calls"] = {"visible": 4, "shadow": 0}
                output.with_suffix(".json").write_text(json.dumps(manifest))
                return manifest

            with patch.object(vq, "run_capture", side_effect=fake_run_capture) as capture:
                manifest = vq.run_visual_quality_cases(app_dir, sys.executable, output_dir,
                                                       xvfb=sys.executable, timeout=5.0)
            self.assertEqual(capture.call_count, 66)
            self.assertTrue(manifest["complete"])
            self.assertEqual(manifest["inventory"]["capture_count"], 66)
            self.assertEqual(manifest["inventory"]["counts_by_family"]["ui-route"], 4)
            self.assertEqual(len(manifest["captures"]), 66)
            self.assertEqual({path.name for path in output_dir.glob("*.png")},
                             {case.filename for case in vq.capture_cases()})
            path = output_dir / "visual-quality-run-manifest.json"
            self.assertTrue(path.is_file())
            saved = json.loads(path.read_text())
            self.assertEqual(saved["inventory"]["expected_case_ids"], [case.case_id for case in vq.capture_cases()])
            self.assertIn("app/main.gd", saved["input_sha256"])
            self.assertEqual(saved["code_revision"], manifest["code_revision"])


if __name__ == "__main__":
    unittest.main()
