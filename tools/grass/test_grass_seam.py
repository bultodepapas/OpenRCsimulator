"""Projection and evidence-preservation regressions for the imported seam check."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from check_grass_seam import ground_radius


class GrassSeamTests(unittest.TestCase):
    def setUp(self):
        self.camera = dict(azimuth_deg=0.0, elevation_deg=-10.0, camera_fov_deg=50.0,
                           camera_height_m=3.0, camera_north_m=0.0, camera_east_m=0.0)

    def test_moving_camera_does_not_move_placement_center(self):
        original = ground_radius(self.camera, 0.0, 0.0)
        moved = ground_radius(dict(self.camera, camera_north_m=6.0), 0.0, 0.0)
        # Near the center ray, moving six metres north adds six metres to the
        # distance from the fixed pilot. A camera-centred mask wrongly stays unchanged.
        self.assertAlmostEqual(moved[359, 639] - original[359, 639], 6.0, places=4)
        self.assertGreater(np.count_nonzero((original >= 25) & (original < 35) &
                                           ~((moved >= 25) & (moved < 35))), 1000)

    def test_translating_scene_and_camera_preserves_mask(self):
        original = ground_radius(self.camera, 0.0, 0.0)
        shifted = ground_radius(dict(self.camera, camera_north_m=123.0, camera_east_m=-45.0), 123.0, -45.0)
        np.testing.assert_allclose(original, shifted, rtol=1e-12, atol=1e-12)

    def test_existing_evidence_is_never_deleted(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'existing.json'
            sentinel = b'{"retained":true}\n'
            output.write_bytes(sentinel)
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('check_grass_seam.py')),
                                     '--captures', folder, '--out', str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn('never overwritten', result.stderr)
            self.assertEqual(output.read_bytes(), sentinel)


if __name__ == '__main__':
    unittest.main()
