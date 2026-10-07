#!/usr/bin/env python3
"""Independent polygon area and span-moment checks for the E0b3b handoff."""
import json
import unittest

import derive_profile as D


def polygon_area_centroid(points, axis):
    """Shoelace area and centroid, independent of the station-profile code."""
    area_twice = moment_twice = 0.0
    for first, second in zip(points, points[1:] + points[:1]):
        cross = first[0] * second[1] - second[0] * first[1]
        area_twice += cross
        moment_twice += (first[axis] + second[axis]) * cross
    area = abs(area_twice) * 0.5
    centroid = moment_twice / (3.0 * area_twice)
    return area, centroid


def profile_area_moment(profile):
    area, moment = 0.0, 0.0
    for low, high, c0, c1 in profile:
        width = high - low
        slope = (c1 - c0) / width
        segment_area = c0 * width + 0.5 * slope * width * width
        segment_moment = (low * segment_area + 0.5 * c0 * width * width
                          + slope * width ** 3 / 3.0)
        area += segment_area
        moment += segment_moment
    return area, moment


def clip_half_plane(points, boundary, greater):
    """Independent Sutherland-Hodgman clip in [span, chord] coordinates."""
    if not points:
        return []
    result = []
    previous = points[-1]
    previous_inside = previous[0] >= boundary if greater else previous[0] <= boundary
    for current in points:
        current_inside = current[0] >= boundary if greater else current[0] <= boundary
        if current_inside != previous_inside:
            fraction = (boundary - previous[0]) / (current[0] - previous[0])
            result.append([boundary, previous[1] + fraction * (current[1] - previous[1])])
        if current_inside:
            result.append(list(current))
        previous, previous_inside = current, current_inside
    return result


def clipped_profile_area_moment(profile, low, high):
    area = moment = 0.0
    for start, end, c0, c1 in profile:
        a, b = max(start, low), min(end, high)
        if b <= a:
            continue
        slope = (c1 - c0) / (end - start)
        ca = c0 + slope * (a - start)
        cb = c0 + slope * (b - start)
        width = b - a
        segment_area = ca * width + 0.5 * (cb - ca) * width
        segment_moment = (a * segment_area + 0.5 * ca * width * width
                          + (cb - ca) * width * width / 3.0)
        area += segment_area
        moment += segment_moment
    return area, moment


class ProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = json.loads(D.SOURCE.read_text())
        cls.aircraft = json.loads(D.AIRCRAFT.read_text())
        cls.report = D.derive(cls.source, cls.aircraft)

    def test_area_and_spanwise_first_moment_match_source_polygons(self):
        axes = {'horizontal_left': (1, -1), 'horizontal_right': (1, 1), 'vertical': (2, 1)}
        for piece in self.report['pieces']:
            with self.subTest(piece=piece['name']):
                span_axis, side = axes[piece['name']]
                source = next(item for item in self.source['pieces'] if item['name'] == piece['name'])
                span_root = min(point[span_axis] * side
                                for footprint in source['footprints']
                                for point in footprint['outline_le']['value'])
                polygon_area = polygon_moment = 0.0
                for footprint in source['footprints']:
                    points = footprint['outline_le']['value']
                    # Project to [span offset, chord coordinate], retaining signed contour orientation.
                    projected = [[point[span_axis] * side - span_root, point[0]] for point in points]
                    area, centroid = polygon_area_centroid(projected, 0)
                    polygon_area += area
                    polygon_moment += area * centroid
                profile = piece['profile']['value']
                profile_area, profile_moment = profile_area_moment(profile)
                self.assertAlmostEqual(profile_area, polygon_area, places=12)
                self.assertAlmostEqual(profile_moment, polygon_moment, places=12)
                self.assertAlmostEqual(profile_area, piece['area']['value'], places=12)
                self.assertAlmostEqual(profile_moment / profile_area,
                                       piece['span_centroid_offset']['value'], places=12)

    def test_profile_rows_are_contiguous_sorted_and_positive(self):
        for piece in self.report['pieces']:
            profile = piece['profile']['value']
            self.assertTrue(profile)
            self.assertEqual(profile[0][0], 0.0)
            self.assertAlmostEqual(profile[-1][1], piece['span']['value'], places=12)
            for index, (low, high, c0, c1) in enumerate(profile):
                self.assertLess(low, high)
                self.assertGreaterEqual(c0, 0.0)
                self.assertGreaterEqual(c1, 0.0)
                self.assertGreater(c0 + c1, 0.0)
                if index:
                    self.assertAlmostEqual(profile[index - 1][1], low, places=12)

    def test_arbitrary_span_band_coverage_matches_clipped_source_polygons(self):
        axes = {'horizontal_left': (1, -1), 'horizontal_right': (1, 1), 'vertical': (2, 1)}
        for piece in self.report['pieces']:
            with self.subTest(piece=piece['name']):
                span_axis, side = axes[piece['name']]
                source = next(item for item in self.source['pieces'] if item['name'] == piece['name'])
                span_root = min(point[span_axis] * side
                                for footprint in source['footprints']
                                for point in footprint['outline_le']['value'])
                span = piece['span']['value']
                # These bands include narrow edge slices, the 30 mm elevator step,
                # contour vertices and broad cuts, like a wake circle's span chord.
                for index in range(24):
                    low = span * index / 27.0
                    high = min(span, low + span * (0.07 + 0.19 * (index % 4) / 3.0))
                    expected_area = expected_moment = 0.0
                    for footprint in source['footprints']:
                        points = [[point[span_axis] * side - span_root, point[0]]
                                  for point in footprint['outline_le']['value']]
                        clipped = clip_half_plane(points, low, True)
                        clipped = clip_half_plane(clipped, high, False)
                        if len(clipped) >= 3:
                            area, centroid = polygon_area_centroid(clipped, 0)
                            expected_area += area
                            expected_moment += area * centroid
                    actual_area, actual_moment = clipped_profile_area_moment(
                        piece['profile']['value'], low, high)
                    self.assertAlmostEqual(actual_area, expected_area, places=12)
                    self.assertAlmostEqual(actual_moment, expected_moment, places=12)

    def test_horizontal_profiles_are_mirrored_and_keep_inner_outer_step(self):
        left, right = self.report['pieces'][:2]
        self.assertEqual(left['profile']['value'], right['profile']['value'])
        self.assertEqual(left['span_dir_le']['value'], [0.0, -1.0, 0.0])
        self.assertEqual(right['span_dir_le']['value'], [0.0, 1.0, 0.0])
        self.assertEqual(left['profile_segment_count']['before_collinear_merge'], 7)
        # A 30 mm elevator section transition changes aggregate chord abruptly;
        # retain separate one-sided profile values at the shared station.
        before, after = left['profile']['value'][:2]
        self.assertEqual(before[1], after[0])
        self.assertAlmostEqual(before[3], 0.166558, places=12)
        self.assertAlmostEqual(after[2], 0.179388, places=12)

    def test_source_notch_hinge_area_and_reference_datums_survive(self):
        source_area = {piece['name']: piece['area']['value'] for piece in self.source['pieces']}
        for piece in self.report['pieces']:
            self.assertAlmostEqual(piece['area']['value'], source_area[piece['name']], places=12)
        discrepancy = self.report['horizontal_reference_discrepancy']
        self.assertAlmostEqual(discrepancy['neutral_coverage_z']['value'], -0.04064, places=12)
        self.assertAlmostEqual(discrepancy['existing_aerodynamic_load_reference_z']['value'], -0.04564, places=12)
        self.assertAlmostEqual(discrepancy['load_minus_coverage']['value'], -0.005, places=12)
        self.assertIn('elevator_inner', self.report['pieces'][0]['source_footprints'])
        self.assertIn('elevator_outer', self.report['pieces'][0]['source_footprints'])

    def test_collinear_merge_requires_continuity_and_equal_slope(self):
        profile = [[0.0, 1.0, 1.0, 2.0], [1.0, 2.0, 2.0, 3.0],
                   [2.0, 3.0, 3.1, 4.1], [3.0, 4.0, 4.1, 5.2]]
        merged = D._merge_collinear(profile)
        self.assertEqual(merged, [[0.0, 2.0, 1.0, 3.0], [2.0, 3.0, 3.1, 4.1],
                                  [3.0, 4.0, 4.1, 5.2]])

    def test_test_fixture_is_fresh_raw_geometry_without_wash_coefficients(self):
        fixture = json.loads(D.FIXTURE.read_text())
        self.assertEqual(fixture, D.fixture_data(self.source, self.report))
        self.assertEqual(fixture['hub'], self.source['hub_le']['value'])
        self.assertEqual(len(fixture['pieces']), 3)
        for piece in fixture['pieces']:
            self.assertEqual(set(piece), {'surface', 'root', 'span_dir', 'span', 'area', 'profile'})
        self.assertFalse({'wash_factor', 'swirl_factor', 'vertical_drift'} & fixture.keys())


if __name__ == '__main__':
    unittest.main()
