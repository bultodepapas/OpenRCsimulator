import unittest
import numpy as np
from filter_compare import (
    BASE_VIEWPORT, CROP, FAR_M, FOV_DEG, NEAR_M, _validate_actual_route,
    _validate_projection, decide, linear, motion_error,
)


class FilterReferenceTests(unittest.TestCase):
    def test_sampling_improvement_must_exceed_reference_uncertainty(self):
        self.assertTrue(all(decide(.01, .04, .002, .02, .01, .04, .002).values()))
        self.assertFalse(all(decide(.01, .04, .02, .02, .01, .04, .02).values()))

    def test_zero_photo_signal_is_rejected(self):
        self.assertFalse(all(decide(.001, .04, .002, 0.0, .001, .04, .002).values()))

    def test_actual_route_requires_rendered_ground_and_photo_bindings(self):
        manifest = self._valid_route_manifest()
        _validate_actual_route(manifest, 'capture/manifest.json')
        manifest['actual_route']['material_override_is_lighting_binding'] = False
        with self.assertRaisesRegex(ValueError, 'active production grass-only material route'):
            _validate_actual_route(manifest, 'capture/manifest.json')

    def test_null_material_parameter_is_resolved_from_exact_shader_default(self):
        manifest = self._valid_route_manifest()
        self.assertIsNone(manifest['actual_route']['bool_parameters']['rc_surface_enabled']['override'])
        _validate_actual_route(manifest, 'capture/manifest.json')

    def test_effective_route_does_not_accept_null_for_defaulted_false(self):
        manifest = self._valid_route_manifest()
        manifest['actual_route']['rc_surface_enabled'] = None
        manifest['actual_route']['bool_parameters']['rc_surface_enabled']['value'] = None
        with self.assertRaisesRegex(ValueError, 'invalid effective rc_surface_enabled evidence'):
            _validate_actual_route(manifest, 'capture/manifest.json')

    @staticmethod
    def _valid_route_manifest():
        include_path = 'res://render/rc_ground_detail.gdshaderinc'
        include_hash = 'a' * 64
        return {
            'probe_shader_sha256': ['probe-hash'],
            'source_sha256': {include_path: include_hash},
            'actual_route': {
                'ground_node': 'Field/rough',
                'production_ground_shader': 'res://render/ground.gdshader',
                'material_override_is_lighting_binding': True,
                'capture_shader_matches_probe': True,
                'capture_shader_code_sha256': 'probe-hash',
                'grass_photo_enabled': True,
                'rc_surface_enabled': False,
                'bool_parameters': {
                    'grass_photo_enabled': {
                        'value': True, 'override': True, 'source': 'material_override',
                        'shader_default': False, 'declaration': 'uniform bool grass_photo_enabled = false;',
                        'declaration_count': 1, 'source_path': include_path, 'default_source_sha256': include_hash,
                    },
                    'rc_surface_enabled': {
                        'value': False, 'override': None, 'source': 'shader_default',
                        'shader_default': False, 'declaration': 'uniform bool rc_surface_enabled = false;',
                        'declaration_count': 1, 'source_path': include_path, 'default_source_sha256': include_hash,
                    },
                },
                'grass_texture_paths': {
                    'rc_grass_albedo': 'res://assets/landscape/rc-ground/grass-albedo.jpg',
                    'rc_grass_normal': 'res://assets/landscape/rc-ground/grass-normal.jpg',
                    'rc_grass_roughness': 'res://assets/landscape/rc-ground/grass-roughness.jpg',
                },
            },
        }

    @staticmethod
    def projection_record(height=.55, step=1, scale=1):
        position = np.array([4.0 + step * .02, height, 0.0])
        point = np.array([4.0, 0.0, -45.0])
        distance = np.hypot(height, 45.0)
        basis = np.array([[1.0, 0.0, 0.0],
                          [0.0, 45.0 / distance, -height / distance],
                          [0.0, height / distance, 45.0 / distance]])
        local = basis @ (point - position)
        depth = -local[2]
        focal = BASE_VIEWPORT[1] / (2.0 * np.tan(np.deg2rad(FOV_DEG) / 2.0))
        full = np.array([BASE_VIEWPORT[0] / 2.0 + local[0] * focal / depth,
                         BASE_VIEWPORT[1] / 2.0 - local[1] * focal / depth])
        crop_pixel = (full - np.array(CROP[:2])) * scale
        frustum_height = 2.0 * NEAR_M * np.tan(np.deg2rad(FOV_DEG) / 2.0)
        return {
            'position': position.tolist(),
            'projection_probe_world': point.tolist(),
            'camera_basis': basis.tolist(),
            'projection_probe_px': crop_pixel.tolist(),
            'viewport': [CROP[2] * scale, CROP[3] * scale],
            'fov_deg': FOV_DEG,
            'near_m': NEAR_M,
            'far_m': FAR_M,
            'frustum_size': frustum_height * CROP[3] / BASE_VIEWPORT[1],
            'frustum_offset': [0.0, -(CROP[1] + CROP[3] / 2 - BASE_VIEWPORT[1] / 2)
                               * frustum_height / BASE_VIEWPORT[1]],
        }

    def test_projected_world_point_matches_full_camera_crop_at_all_scales(self):
        for scale in (1, 8, 16):
            _validate_projection(self.projection_record(height=1.7, step=2, scale=scale), scale, 1.7, 2)

    def test_projected_world_point_rejects_camera_that_drifted_with_crop(self):
        record = self.projection_record()
        record['projection_probe_px'][1] += 2.0
        with self.assertRaisesRegex(ValueError, 'projected world point disagrees'):
            _validate_projection(record, 1, .55, 1)

    def test_expected_camera_motion_is_removed(self):
        reference = np.array([0., 3., 8.])[:, None, None]
        self.assertEqual(motion_error(reference, reference), 0.)
        self.assertEqual(motion_error(reference + 2., reference), 0.)
        self.assertGreater(motion_error(reference + np.array([0., 1., 0.])[:, None, None], reference), 0.)

    def test_averaging_occurs_in_linear_light(self):
        average = linear(np.array([0, 255])).mean()
        self.assertAlmostEqual(average, .5)
        self.assertLess(float(linear(127.5)), average)


if __name__ == '__main__':
    unittest.main()
