"""CPU regressions for the moving-boundary image reducer."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from transition_compare import (
    PAIR_FIELDS,
    TransitionError,
    boundary_control_ratio,
    ground_radius_grid,
    safe_child,
    summarize_temporal_step,
    validate_pair_metadata,
    validate_pose_geometry,
    write_new_report,
)


class GrassTransitionTests(unittest.TestCase):
    def _pair(self) -> tuple[dict, dict]:
        common = {field: field for field in PAIR_FIELDS}
        common.update({
            "pose_id": "pilot_wind_outbound_29p75_sweep_06",
            "sequence_id": "wind_outbound",
            "sequence_kind": "moving_sweep",
            "sequence_direction": "outbound",
            "camera_facing": "outbound",
            "height_case": "pilot",
            "camera_radius_from_pilot_m": 29.75,
            "eye_height_m": 1.7,
            "lookahead_m": 10.0,
            "eye_render_m": [0.0, 1.7, -29.75],
            "target_render_m": [0.0, 0.0, -39.75],
            "fov_deg": 58.0,
            "sequence_index": 6,
            "sequence_length": 14,
            "shader_clock_s": 1.4,
            "wind_render_mps": [5.0, 0.0, 0.0],
            "camera_cut": False,
            "camera_right_render": [1.0, 0.0, 0.0],
            "camera_up_render": [0.0, 0.985893206467704, -0.167375595760197],
            "camera_forward_render": [0.0, -0.167375595760197, -0.985893206467704],
            "ground_detail_enabled": True,
        })
        visible = dict(common, state="visible", grass_visible=True,
                       grass_node_visible=True, grass_hidden_reference=False)
        hidden = dict(common, state="grass_hidden", grass_visible=False,
                      grass_node_visible=False, grass_hidden_reference=True)
        return visible, hidden

    def test_hidden_reference_motion_is_subtracted_from_temporal_residual(self) -> None:
        background_before = np.full((8, 8, 3), 40, dtype=np.uint8)
        background_after = np.full((8, 8, 3), 80, dtype=np.uint8)
        static_grass = np.zeros((8, 8, 3), dtype=np.uint8)
        static_grass[2:5, 3:6, 1] = 30
        visible_before = background_before + static_grass
        visible_after = background_after + static_grass

        result = summarize_temporal_step(
            visible_before, background_before, visible_after, background_after, 0.5
        )

        self.assertGreater(result["hidden_reference_motion"]["mean_abs_rgb_delta"], 0.0)
        self.assertGreater(result["visible_motion"]["mean_abs_rgb_delta"], 0.0)
        self.assertEqual(result["grass_residual_motion"]["mean_abs_rgb_delta"], 0.0)
        self.assertIn("expected", result["interpretation"])

    def test_boundary_step_ratio_uses_adjacent_quarter_metre_controls(self) -> None:
        steps = [
            {"start_radius_m": 29.5, "end_radius_m": 29.75,
             "grass_residual_mean_abs_rgb_per_camera_m": 10.0},
            {"start_radius_m": 29.75, "end_radius_m": 30.25,
             "grass_residual_mean_abs_rgb_per_camera_m": 40.0},
            {"start_radius_m": 30.25, "end_radius_m": 30.5,
             "grass_residual_mean_abs_rgb_per_camera_m": 20.0},
        ]

        result = boundary_control_ratio(steps)

        self.assertAlmostEqual(result["boundary_to_control_ratio"], 40.0 / 15.0)
        self.assertEqual(result["adjacent_control_median_rate"], 15.0)
        self.assertIn("not a pop verdict", result["interpretation"])
        self.assertNotIn("passed", result)

    def test_camera_clock_and_wind_must_match_in_reference_pair(self) -> None:
        visible, hidden = self._pair()
        validate_pair_metadata(visible, hidden)

        hidden["shader_clock_s"] += 0.01
        with self.assertRaisesRegex(TransitionError, "shader_clock_s"):
            validate_pair_metadata(visible, hidden)

    def test_camera_basis_projects_ground_in_pilot_radius_coordinates(self) -> None:
        case = {
            "pose_id": "test",
            "eye_render_m": [0.0, 1.0, 0.0],
            "camera_forward_render": [0.0, -1.0, 0.0],
            "camera_right_render": [1.0, 0.0, 0.0],
            "camera_up_render": [0.0, 0.0, -1.0],
            "fov_deg": 90.0,
        }
        radius, valid = ground_radius_grid(case, np.zeros(3), width=8, height=8)

        self.assertTrue(valid.all())
        self.assertEqual(radius.shape, (8, 8))
        self.assertGreater(float(radius.max()), float(radius.min()))

    def test_pose_geometry_binds_recorded_camera_to_pilot_relative_view(self) -> None:
        visible, _hidden = self._pair()
        validate_pose_geometry(visible, np.zeros(3, dtype=np.float64))

        visible["target_render_m"] = [0.0, 0.0, -34.0]
        with self.assertRaisesRegex(TransitionError, "camera target"):
            validate_pose_geometry(visible, np.zeros(3, dtype=np.float64))

    def test_safe_child_rejects_paths_outside_capture_directory(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaisesRegex(TransitionError, "escapes"):
                safe_child(root, "../outside.png")

    def test_report_refuses_to_replace_existing_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            report = Path(folder) / "result.json"
            original = b'{"retained":true}\n'
            report.write_bytes(original)

            with self.assertRaisesRegex(TransitionError, "never overwritten"):
                write_new_report(report, {"complete": True})

            self.assertEqual(report.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
