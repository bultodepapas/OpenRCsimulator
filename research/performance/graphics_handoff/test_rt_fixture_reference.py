"""Analytic anchors and negative-domain checks; no native/Godot performance tests."""

from dataclasses import replace
from fractions import Fraction
import json
import math
from pathlib import Path
import unittest

from rt_fixture_reference import (
    AmbiguousFixture, IDENTITY, Instance, Ray, binary32, shade_selected_sun, trace_closest,
)


CASES = json.loads(Path(__file__).with_name('rt_fixture_cases.json').read_text())
TRIANGLE = (((0, 0, 0), (2, 0, 0), (0, 0, 2)),)


def scene(name):
    result = []
    for description in CASES['scenes'][name]:
        fields = {key: value for key, value in description.items() if key != 'mesh'}
        result.append(Instance(triangles=CASES['meshes'][description['mesh']], **fields))
    return result


def base_ray(**changes):
    return replace(Ray((0.5, 0, 0.5), (0, 1, 0), 0.125, 12), **changes)


class GeometryCases(unittest.TestCase):
    def test_published_analytic_cases(self):
        self.assertEqual(CASES['schema_version'], 1)
        self.assertEqual(len(CASES['geometric_cases']), 14)
        for case in CASES['geometric_cases']:
            with self.subTest(case=case['name']):
                actual = trace_closest(scene(case['scene']), Ray(**case['ray']))
                expected = case['expected']
                self.assertEqual(actual is not None, expected['hit'])
                if actual is None:
                    self.assertTrue(all(expected[key] is None for key in (
                        't', 'distance_m', 'instance_custom_index', 'primitive_index', 'barycentric')))
                    continue
                for key in ('t', 'distance_m', 'instance_custom_index', 'primitive_index'):
                    self.assertEqual(getattr(actual, key), expected[key])
                self.assertEqual(actual.barycentric, tuple(expected['barycentric']))

    def test_closest_identity_is_independent_of_instance_order(self):
        instances = scene('affine_near_far')
        ray = Ray((4, -2, 4.5), (0, 1, 0), 0.125, 12)
        for order in (instances, list(reversed(instances))):
            hit = trace_closest(order, ray)
            self.assertEqual((hit.t, hit.instance_custom_index), (6, 66051))

    def test_nonunit_direction_preserves_parameter_and_distance(self):
        hit = trace_closest(scene('affine_near_far'), Ray((4, -2, 4.5), (0, 2, 0), 0.125, 12))
        self.assertEqual((hit.t, hit.distance_m), (3, 6))

    def test_primitive_index_is_not_custom_instance_index(self):
        raised = ((0, 2, 0), (2, 2, 0), (0, 2, 2))
        far = ((0, 4, 0), (2, 4, 0), (0, 4, 2))
        hit = trace_closest([Instance(66051, (far, raised))], base_ray())
        self.assertEqual((hit.primitive_index, hit.instance_custom_index, hit.t), (1, 66051, 2))

    def test_two_sided_winding_is_explicit(self):
        original = scene('identity_raised')[0]
        reversed_mesh = replace(original, triangles=tuple(tuple(reversed(t)) for t in original.triangles))
        self.assertEqual(trace_closest([original], base_ray()).t, 2)
        self.assertEqual(trace_closest([reversed_mesh], base_ray()).t, 2)

    def test_parallel_non_coplanar_ray_misses(self):
        self.assertIsNone(trace_closest(scene('identity_raised'), base_ray(direction=(1, 0, 0))))

    def test_empty_scene_and_hidden_instance_miss(self):
        self.assertIsNone(trace_closest([], base_ray()))
        hidden = replace(scene('identity_raised')[0], mask=0)
        self.assertIsNone(trace_closest([hidden], base_ray()))

    def test_exact_interval_endpoints_are_ambiguous_not_gpu_failures(self):
        for bounds in ((0, 2), (2, 12)):
            with self.subTest(bounds=bounds), self.assertRaises(AmbiguousFixture):
                trace_closest(scene('identity_raised'), base_ray(t_min=bounds[0], t_max=bounds[1]))

    def test_edge_and_coplanar_inputs_are_ambiguous(self):
        for ray in (base_ray(origin=(0, 0, 0.5)), base_ray(origin=(0.5, 2, 0.5), direction=(1, 0, 0))):
            with self.subTest(ray=ray), self.assertRaises(AmbiguousFixture):
                trace_closest(scene('identity_raised'), ray)

    def test_equal_nearest_ties_are_ambiguous(self):
        a = scene('identity_raised')[0]
        with self.assertRaises(AmbiguousFixture):
            trace_closest([a, replace(a, instance_custom_index=8)], base_ray())

    def test_small_blocker_is_lost_by_an_excessive_origin_offset(self):
        hit = trace_closest(scene('receiver_and_small_blocker'),
                            Ray((0.5, 1/4096, 0.5), (0, 1, 0), 1/4096, 1/128))
        self.assertEqual((hit.t, hit.instance_custom_index), (7/4096, 102))
        self.assertIsNone(trace_closest(scene('receiver_and_small_blocker'),
                                       Ray((0.5, 1/256, 0.5), (0, 1, 0), 1/4096, 1/128)))

    def test_non_axis_endpoint_and_edge_counterexamples_are_ambiguous(self):
        # Reviewer-supplied dyadics: float64 equality formerly classified these
        # exact endpoint/edge intersections as strict misses.
        cases = (
            (((0.2941246032714844, 2.786457061767578, 2.4155197143554688),
              (1.9290733337402344, 1.8796272277832031, -1.1225852966308594),
              (-1.0928001403808594, 2.9995460510253906, 3.641357421875)),
             (-2.0160655975341797, 5.319065093994141, 2.7329301834106445),
             (2.3721961975097656, -2.706043243408203, -0.895477294921875),
             1, (Fraction(1, 2), Fraction(1, 4), Fraction(1, 4))),
            (((3.338886260986328, 1.5929718017578125, -1.4979705810546875),
              (2.8997955322265625, 1.2843170166015625, 3.670440673828125),
              (-2.6111106872558594, 0.8123741149902344, 1.43072509765625)),
             (1.428335189819336, 4.016407012939453, 2.3820114135742188),
             (1.6910057067871094, -2.5777626037597656, -1.2957763671875),
             2, (Fraction(1, 2), Fraction(1, 2), Fraction(0))),
        )
        for vertices, origin, direction, t_max, weights in cases:
            ray, instance = Ray(origin, direction, 0, t_max), Instance(7, (vertices,))
            target = tuple(Fraction(ray.origin[i]) + Fraction(ray.direction[i]) for i in range(3))
            bary_point = tuple(sum(weights[j] * Fraction(instance.triangles[0][j][i])
                                   for j in range(3)) for i in range(3))
            self.assertEqual(target, bary_point)  # Independent construction at t=1.
            with self.subTest(t_max=t_max), self.assertRaises(AmbiguousFixture):
                trace_closest([instance], ray)

    def test_distinct_triangles_have_an_exact_nearest_tie(self):
        triangles = (
            ((-0.9821357727050781, 0.04984283447265625, 1.8192672729492188),
             (-0.9618301391601562, -1.6678237915039062, -1.8606414794921875),
             (2.9261016845703125, 1.5681381225585938, -1.77789306640625)),
            ((-1.628173828125, -0.2938575744628906, 1.0643157958984375),
             (-0.9852409362792969, -1.7837104797363281, -1.1589851379394531),
             (4.241588592529297, 2.3714256286621094, -0.9696464538574219)),
        )
        ray = Ray((-1.0362510681152344, -0.5822372436523438, -0.18738937377929688),
                  (1.0362510681152344, 0.5822372436523438, 0.18738937377929688), 0, 2)
        instances = [Instance(i + 1, (triangle,)) for i, triangle in enumerate(triangles)]
        for triangle in triangles:
            point = tuple(sum(w * Fraction(triangle[j][i]) for j, w in enumerate(
                (Fraction(1, 2), Fraction(1, 4), Fraction(1, 4)))) for i in range(3))
            self.assertEqual(point, (0, 0, 0))
        for order in (instances, list(reversed(instances))):
            with self.assertRaises(AmbiguousFixture):
                trace_closest(order, ray)


class DomainChecks(unittest.TestCase):
    def test_binary32_rounding_is_explicit(self):
        self.assertEqual(binary32(16777217), 16777216)
        self.assertEqual(binary32(1/4096), 1/4096)

    def test_invalid_numbers_are_rejected(self):
        for value in (math.nan, math.inf, -math.inf, 1e40, True, '1', 10**1000):
            with self.subTest(value=repr(value)[:30]), self.assertRaises(ValueError):
                binary32(value)

    def test_bad_direction_or_interval_is_rejected_after_rounding(self):
        cases = ({'direction': (0, 0, 0)}, {'direction': (0, 1e-50, 0)},
                 {'t_min': -1}, {'t_min': 2, 't_max': 1}, {'t_min': 2, 't_max': 2},
                 {'origin': (0, math.nan, 0)}, {'direction': (0, 1)},
                 {'t_min': 16777216, 't_max': 16777217})
        for changes in cases:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                base_ray(**changes)

    def test_mask_and_custom_index_ranges_are_independent(self):
        self.assertEqual(Instance(0xFFFFFF, TRIANGLE, mask=0).instance_custom_index, 0xFFFFFF)
        for value in (-1, 256, True, 1.0):
            with self.subTest(mask=value), self.assertRaises(ValueError):
                base_ray(cull_mask=value)
        for value in (-1, 1 << 24, True, 7.0):
            with self.subTest(custom=value), self.assertRaises(ValueError):
                Instance(value, TRIANGLE)

    def test_invalid_and_singular_transforms_are_rejected(self):
        for matrix in ((), ((1, 0, 0),) * 3, ((1, 0, 0, 0), (0, 0, 0, 0), (0, 0, 1, 0)),
                       ((math.nan, 0, 0, 0), IDENTITY[1], IDENTITY[2])):
            with self.subTest(matrix=matrix), self.assertRaises(ValueError):
                Instance(7, TRIANGLE, matrix)

    def test_degenerate_and_missing_triangles_are_rejected(self):
        for triangles in ((), (((0, 0, 0), (1, 0, 0), (2, 0, 0)),), (((0, 0, 0),),)):
            with self.subTest(triangles=triangles), self.assertRaises(ValueError):
                Instance(7, triangles)

    def test_duplicate_fixture_custom_indices_are_rejected(self):
        a = scene('identity_raised')[0]
        with self.assertRaises(ValueError):
            trace_closest([a, a], base_ray())

    def test_constructed_values_do_not_alias_input_lists(self):
        origin, direction = [0.5, 0, 0.5], [0, 1, 0]
        ray = Ray(origin, direction, 0.125, 12)
        origin[0], direction[1] = 99, 0
        self.assertEqual(trace_closest(scene('identity_raised'), ray).t, 2)
        vertices = [[list(vertex) for vertex in triangle] for triangle in TRIANGLE]
        rows = [[1, 0, 0, 0], [0, 1, 0, 2], [0, 0, 1, 0]]
        instance = Instance(7, vertices, rows)
        vertices[0][0][0], rows[1][3] = 99, 99
        self.assertEqual(trace_closest([instance], ray).t, 2)


class LightingCases(unittest.TestCase):
    def inputs(self, **changes):
        return dict(CASES['lighting_inputs'], raw_visibility=1, opacity=1,
                    fade_to_lit=0) | changes

    def test_published_binary_exact_energy_cases(self):
        self.assertEqual(len(CASES['lighting_cases']), 5)
        for case in CASES['lighting_cases']:
            with self.subTest(case=case['name']):
                inputs = self.inputs(**{key: case[key] for key in ('raw_visibility', 'opacity', 'fade_to_lit')})
                result = shade_selected_sun(**inputs)
                expected = case['expected']
                self.assertEqual(result.effective_visibility, expected['effective_visibility'])
                for key in ('sun_diffuse', 'sun_specular', 'total'):
                    self.assertEqual(getattr(result, key), tuple(expected[key]))
                for key in ('ambient', 'emission', 'other_lights'):
                    self.assertEqual(getattr(result, key), tuple(inputs[key]))

    def test_fully_opaque_cloud_changes_only_selected_sun(self):
        result = shade_selected_sun(**self.inputs(cloud_transmission=0))
        self.assertEqual(result.total, (0.40625, 0.25, 0.21875))
        self.assertEqual(result.sun_specular, (0, 0, 0))
        self.assertEqual(result.other_lights, (0.25, 0.125, 0.0625))

    def test_zero_and_hdr_radiance_are_valid(self):
        zero = shade_selected_sun(**self.inputs(**{k: (0, 0, 0) for k in (
            'ambient', 'emission', 'other_lights', 'sun_diffuse', 'sun_specular')}))
        self.assertEqual(zero.total, (0, 0, 0))
        hdr = shade_selected_sun(**self.inputs(sun_diffuse=(8, 4, 2), cloud_transmission=1))
        self.assertEqual(hdr.sun_diffuse, (8, 4, 2))
        self.assertGreater(hdr.total[0], 8)

    def test_invalid_energy_and_factors_are_rejected(self):
        for key in ('raw_visibility', 'opacity', 'fade_to_lit', 'cloud_transmission'):
            for value in (-0.1, 1.1, math.nan, math.inf, True):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    shade_selected_sun(**self.inputs(**{key: value}))
        for value in ((-1, 0, 0), (0, math.inf, 0), (0, 1)):
            with self.subTest(color=value), self.assertRaises(ValueError):
                shade_selected_sun(**self.inputs(ambient=value))

    def test_factors_are_independent_of_input_container_mutation(self):
        other = list(CASES['lighting_inputs']['other_lights'])
        inputs = self.inputs(other_lights=other)
        result = shade_selected_sun(**inputs)
        other[0] = 99
        self.assertIsInstance(result.other_lights, tuple)
        self.assertEqual(result.other_lights, (0.25, 0.125, 0.0625))
        self.assertEqual(result.total, (0.6875, 0.4375, 0.40625))


if __name__ == '__main__':
    unittest.main()
