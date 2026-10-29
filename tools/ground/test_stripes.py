#!/usr/bin/env python3
"""GPU-independent regression checks for L9c measurements and import recovery."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from check_stripes import errors, mask_for, SIZE, verify_projection
from check_surfaces import checked_run, import_mutation_project, parse_args


class StripeMeasurementTests(unittest.TestCase):
    def test_expected_camera_motion_is_not_an_error(self):
        reference = [np.full((2, 2, 3), 0.1), np.full((2, 2, 3), 0.7)]
        scores = errors(reference, reference, np.ones((2, 2), dtype=bool))
        self.assertEqual(scores["spatial_rms_linear_rgb"], 0)
        self.assertEqual(scores["temporal_rms_linear_rgb"], 0)

    def test_static_bias_and_temporal_error_are_distinct(self):
        reference = [np.zeros((2, 2, 3)), np.ones((2, 2, 3))]
        mask = np.ones((2, 2), dtype=bool)
        scores = errors([item + 0.2 for item in reference], reference, mask)
        self.assertAlmostEqual(scores["spatial_rms_linear_rgb"], 0.2)
        self.assertAlmostEqual(scores["temporal_rms_linear_rgb"], 0)
        scores = errors([reference[0], reference[1] + 0.2], reference, mask)
        self.assertAlmostEqual(scores["temporal_rms_linear_rgb"], 0.2)

    def test_subpixel_world_inset_mask_uses_pixel_centres(self):
        pixels = np.zeros((SIZE[1], SIZE[0], 3))
        records = {("test", shift): (pixels, {"projected_runway_core":
                   [[10, 10.1], [40, 10.1], [40, 10.9], [10, 10.9]]}) for shift in (0, 0.5)}
        mask = mask_for(records, "test")
        self.assertEqual(int(mask.sum()), 30)
        self.assertTrue(mask[10, 10:40].all())
        records["test", 0.5][1]["projected_runway_core"] = [[11, 10.1], [41, 10.1], [41, 10.9], [11, 10.9]]
        self.assertEqual(int(mask_for(records, "test").sum()), 29)

    def test_wrong_reference_camera_is_rejected(self):
        record = {"eye_render": [0, 1, 0], "target_render": [1, 0, 0], "metres_per_pixel": 0.1,
                  "shift_axis": "vertical", "crop_origin": [320,328], "projected_runway": [[0, 0], [2, 0], [2, 2], [0, 2]],
                  "projected_runway_core": [[0.2, 0.2], [1.8, 0.2], [1.8, 1.8], [0.2, 1.8]]}
        native = {("test", 0): (None, record)}
        enlarged = dict(record)
        for name in ("projected_runway", "projected_runway_core"):
            enlarged[name] = (np.asarray(record[name]) * 4).tolist()
        other = {("test", 0): (None, enlarged)}
        verify_projection(native, other, 4)
        enlarged["eye_render"] = [0, 1.001, 0]
        with self.assertRaisesRegex(RuntimeError, "camera mismatch"):
            verify_projection(native, other, 4)


class MutationImportRetryTests(unittest.TestCase):
    COMPLETED_IMPORT = "[ DONE ] reimport\n[ DONE ] loading_editor_layout\n"
    CORE_DUMP = "timeout: the monitored command dumped core\n"

    def test_import_and_render_timeouts_are_independent_and_positive(self):
        _, args = parse_args([])
        self.assertEqual((args.timeout, args.import_timeout), (240, 600))
        _, args = parse_args(["--timeout", "37", "--import-timeout", "901"])
        self.assertEqual((args.timeout, args.import_timeout), (37, 901))
        for option in ("--timeout", "--import-timeout"):
            with self.subTest(option=option), patch("sys.stderr"):
                with self.assertRaises(SystemExit):
                    parse_args([option, "0"])

    @staticmethod
    def fake_run(responses, calls):
        def run(command, **kwargs):
            calls.append(command)
            returncode, output = responses.pop(0)
            kwargs["stdout"].write(output)
            return subprocess.CompletedProcess(command, returncode)
        return run

    def test_completed_sigabrt_retries_once_to_a_separate_log(self):
        calls = []
        first_output = self.COMPLETED_IMPORT + self.CORE_DUMP
        retry_output = self.COMPLETED_IMPORT
        with tempfile.TemporaryDirectory() as temporary:
            first_log = Path(temporary) / "unfiltered-stripe-import.log"
            retry_log = Path(temporary) / "unfiltered-stripe-import-retry.log"
            with patch("check_surfaces.subprocess.run", side_effect=self.fake_run(
                    [(-6, first_output), (0, retry_output)], calls)):
                command = import_mutation_project(Path("godot"), Path("mutation"), first_log, {}, 60)

            self.assertEqual(len(calls), 2)
            self.assertEqual(calls[0], calls[1])
            self.assertEqual(command, calls[0][3:])
            self.assertEqual(first_log.read_text(), first_output)
            self.assertEqual(retry_log.read_text(), retry_output)

    def test_only_exact_completed_sigabrt_signature_is_retryable(self):
        complete = self.COMPLETED_IMPORT
        rejected = (
            ("missing core marker", -6, complete),
            ("incomplete layout", -6, "[ DONE ] reimport\n" + self.CORE_DUMP),
            ("out-of-order completion", -6,
             "[ DONE ] loading_editor_layout\n[ DONE ] reimport\n" + self.CORE_DUMP),
            ("parse error", -6, complete + "SCRIPT ERROR: Parse Error: bad script\n" + self.CORE_DUMP),
            ("shader error", -6, complete + "SHADER ERROR: bad shader\n" + self.CORE_DUMP),
            ("engine error", -6, complete + "ERROR: import failed\n" + self.CORE_DUMP),
            ("shell-style 134 status", 134, complete + self.CORE_DUMP),
            ("cold import timeout", 124, "[ 83% ] reimport | example.glb\n"),
        )
        for label, returncode, output in rejected:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                calls = []
                first_log = Path(temporary) / "import.log"
                retry_log = Path(temporary) / "import-retry.log"
                with patch("check_surfaces.subprocess.run", side_effect=self.fake_run(
                        [(returncode, output)], calls)):
                    with self.assertRaisesRegex(RuntimeError, "Godot import failed"):
                        import_mutation_project(Path("godot"), Path("mutation"), first_log, {}, 60)
                self.assertEqual(len(calls), 1)
                self.assertTrue(first_log.is_file())
                self.assertFalse(retry_log.exists())

    def test_failed_retry_is_fatal_after_one_retry_and_keeps_both_logs(self):
        first_output = self.COMPLETED_IMPORT + self.CORE_DUMP
        second_output = self.COMPLETED_IMPORT + self.CORE_DUMP
        with tempfile.TemporaryDirectory() as temporary:
            calls = []
            first_log = Path(temporary) / "import.log"
            retry_log = Path(temporary) / "import-retry.log"
            with patch("check_surfaces.subprocess.run", side_effect=self.fake_run(
                    [(-6, first_output), (-6, second_output)], calls)):
                with self.assertRaisesRegex(RuntimeError, "Godot import retry failed"):
                    import_mutation_project(Path("godot"), Path("mutation"), first_log, {}, 60)
            self.assertEqual(len(calls), 2)
            self.assertEqual(first_log.read_text(), first_output)
            self.assertEqual(retry_log.read_text(), second_output)

    def test_capture_command_never_uses_import_retry(self):
        capture_output = self.COMPLETED_IMPORT + self.CORE_DUMP
        with tempfile.TemporaryDirectory() as temporary:
            calls = []
            capture_log = Path(temporary) / "capture.log"
            retry_log = Path(temporary) / "capture-retry.log"
            with patch("check_surfaces.subprocess.run", side_effect=self.fake_run(
                    [(-6, capture_output)], calls)):
                with self.assertRaisesRegex(RuntimeError, "Godot command failed"):
                    checked_run(["godot", "--script", "capture.gd"], capture_log, {}, 60)
            self.assertEqual(len(calls), 1)
            self.assertTrue(capture_log.is_file())
            self.assertFalse(retry_log.exists())

    def test_successful_import_does_not_create_a_retry_log(self):
        with tempfile.TemporaryDirectory() as temporary:
            calls = []
            first_log = Path(temporary) / "import.log"
            with patch("check_surfaces.subprocess.run", side_effect=self.fake_run(
                    [(0, self.COMPLETED_IMPORT)], calls)):
                import_mutation_project(Path("godot"), Path("mutation"), first_log, {}, 60)
            self.assertEqual(len(calls), 1)
            self.assertFalse((Path(temporary) / "import-retry.log").exists())

    def test_existing_retry_log_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            calls = []
            first_log = Path(temporary) / "import.log"
            retry_log = Path(temporary) / "import-retry.log"
            retry_log.write_text("prior evidence\n")
            with patch("check_surfaces.subprocess.run", side_effect=self.fake_run(
                    [(-6, self.COMPLETED_IMPORT + self.CORE_DUMP)], calls)):
                with self.assertRaisesRegex(RuntimeError, "refusing to overwrite"):
                    import_mutation_project(Path("godot"), Path("mutation"), first_log, {}, 60)
            self.assertEqual(len(calls), 1)
            self.assertEqual(retry_log.read_text(), "prior evidence\n")


if __name__ == "__main__":
    unittest.main()
