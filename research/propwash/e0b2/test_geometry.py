#!/usr/bin/env python3
"""Independent polygon examples and neutral-tail accounting for E0b2."""
import copy
import json
import unittest
import derive_geometry as D


class GeometryTests(unittest.TestCase):
    def test_clip_rectangle_and_triangle(self):
        rectangle = [[-2, -1], [2, -1], [2, 1], [-2, 1]]
        self.assertEqual(D.area(rectangle), 8)
        for positive in [False, True]:
            self.assertEqual(D.area(D.clip(rectangle, 0, 0, positive)), 4)
        triangle = [[0, 0], [2, 0], [0, 2]]
        self.assertEqual(D.area(D.clip(triangle, 0, 1, True)), 0.5)
        self.assertEqual(D.area(D.clip(triangle, 0, 1, False)), 1.5)
        self.assertEqual(D.clip(rectangle, 0, 3, True), [])
        self.assertEqual(D.area(D.clip(list(reversed(rectangle)), 1, 0, True)), 4)

    def test_datum_uses_both_offsets(self):
        geometry = {'wing': {'leading_z': 2.0}, 'equipment': {'shaft_y': 3.0}}
        self.assertEqual(D.visual_to_le([5.0, 7.0, 11.0], geometry), [9.0, 5.0, 4.0])

    def test_neutral_tail_matches_independent_area_accounting(self):
        geometry = json.loads(D.GEOMETRY.read_text())
        aircraft = json.loads(D.AIRCRAFT.read_text())
        offset, report = D.derive(geometry, aircraft)
        t = geometry['tail']
        # Direct area lost at the two horizontal hinge edges and the rectangular notch.
        # Both polygons meet their hinge over +/-0.27305 m; outer elevator lobes taper to +/-0.2794.
        raw = D.area(t['stab_outline']) + D.area(t['elevator_outline'])
        hinge_span = max(p[0] for p in t['stab_outline']) - min(p[0] for p in t['stab_outline'])
        notch_depth = max(p[1] for p in t['elevator_outline']) - t['elevator_cutout_start']
        expected = raw - hinge_span * t['hinge_gap'] - 2 * t['elevator_cutout_half_width'] * notch_depth
        left, right, vertical = report['pieces']
        self.assertAlmostEqual(left['area']['value'] + right['area']['value'], expected, places=10)
        self.assertAlmostEqual(left['area']['value'], right['area']['value'], places=12)
        self.assertEqual(left['span_bounds_le']['value'], [-t['span']/2, 0.0])
        self.assertEqual(right['span_bounds_le']['value'], [0.0, t['span']/2])
        # Moving each hinge vertex by half the gap removes two adjacent triangular
        # wedges: delta area = gap/4 * separation of its neighbouring span stations.
        vertical_raw = sum(D.area(t[key]) for key in ['fin_outline', 'rudder_outline'])
        removed = 0.0
        for key in ['fin_outline', 'rudder_outline']:
            polygon = t[key]
            for i, point in enumerate(polygon):
                if point[1] == 0:
                    removed += t['hinge_gap'] / 4 * abs(polygon[i-1][0] - polygon[(i+1) % len(polygon)][0])
        self.assertAlmostEqual(vertical['area']['value'], vertical_raw - removed, places=12)
        for piece in report['pieces']:
            for footprint in piece['footprints']:
                self.assertGreater(footprint['area']['value'], 0)
                for p in footprint['outline_le']['value']:
                    if piece['surface'] == 'horizontal':
                        self.assertAlmostEqual(p[2], t['y']-geometry['equipment']['shaft_y'], places=12)
                    else:
                        self.assertEqual(p[1], 0)
        self.assertEqual(report['hub_le']['value'], [-0.293276, 0.0, 0.0])
        self.assertEqual(offset['value'], [-0.414176, 0.0, 0.0])
        self.assertEqual(report['existing_aero_surfaces']['horizontal']['area'], aircraft['aero']['surfaces']['horizontal']['area'])

    def test_changed_geometry_and_cg_flow_into_handoff(self):
        geometry = json.loads(D.GEOMETRY.read_text())
        aircraft = json.loads(D.AIRCRAFT.read_text())
        original_offset, original = D.derive(geometry, aircraft)
        changed = copy.deepcopy(geometry)
        changed['equipment']['prop_z'] += 0.01
        changed['equipment']['shaft_y'] += 0.02
        aircraft['balance']['plan_cg']['value'][0] += 0.03
        offset, report = D.derive(changed, aircraft)
        self.assertAlmostEqual(offset['value'][0] - original_offset['value'][0], -0.02)
        self.assertEqual(report['hub_le']['value'][2], 0.0)
        a = report['pieces'][0]['footprints'][0]['outline_le']['value'][0]
        b = original['pieces'][0]['footprints'][0]['outline_le']['value'][0]
        self.assertAlmostEqual(a[2] - b[2], -0.02)
        changed['tail']['elevator_cutout_start'] -= 0.005
        _, notched = D.derive(changed, aircraft)
        lost = report['pieces'][0]['area']['value'] - notched['pieces'][0]['area']['value']
        self.assertAlmostEqual(lost, 0.005 * changed['tail']['elevator_cutout_half_width'], places=12)


if __name__ == '__main__':
    unittest.main()
