#!/usr/bin/env python3
"""Regression checks for L9c-R1 measurement, independent of a GPU."""
import unittest
import numpy as np
from check_stripes import errors, mask_for, SIZE, verify_projection


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


if __name__ == "__main__":
    unittest.main()
