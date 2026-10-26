"""Model-consistency checks; run: python3 -m unittest discover -s research/aero."""

import math
import unittest

from aileron_effectiveness import (
    _angle_map, _calibrate, _geometry, _influence, derive_effectiveness,
)


class AileronEffectivenessTests(unittest.TestCase):
    STIK = dict(area=0.4645148, span=1.524, lift_slope=4.58,
                tail_lift_share=0.0956 / 0.4645148 * 1.75, clda_right=-0.0823)

    def test_independent_d11d_weissinger_known_answers(self):
        # Frozen independent reference: research/aero/d11d/output.txt.
        edges, ys, chords = _geometry(1.524 * 0.3048, 1.524, None)
        angle_map = _angle_map(_influence(edges, ys, chords), math.tau)
        cla = math.tau * sum(sum(row) for row in angle_map) / len(ys)
        clp = -math.tau * sum(y * sum(value * 2 * source_y / 1.524
                                     for value, source_y in zip(row, ys))
                              for y, row in zip(ys, angle_map)) / (len(ys) * 1.524)
        self.assertAlmostEqual(cla, 4.3171, delta=0.00005)
        self.assertAlmostEqual(clp, -0.4814, delta=0.00005)

    def test_stik_section_slope_matches_independent_reference(self):
        # The reference geometry uses S=b*c; its target tail ratio uses 0.4645148.
        edges, ys, chords = _geometry(1.524 * 0.3048, self.STIK['span'], None)
        slope, angle_map = _calibrate(_influence(edges, ys, chords),
                                     self.STIK['lift_slope'] - self.STIK['tail_lift_share'])
        self.assertAlmostEqual(slope, 6.081756, delta=0.000001)
        self.assertAlmostEqual(angle_map[0][0], 0.395204, delta=0.000001)

    def test_equal_area_taper_geometry(self):
        edges, ys, chords = _geometry(3.0, 4.0, (1.0, 0.5))
        primitive = lambda y: y - 0.125 * y * y
        moment = lambda y: y * y / 2 - y ** 3 / 12
        for index in range(3, 6):
            start, end = edges[index:index + 2]
            strip_area = primitive(end) - primitive(start)
            self.assertAlmostEqual(strip_area, 0.5, places=13)
            self.assertAlmostEqual(ys[index], (moment(end) - moment(start)) / strip_area, places=13)
        self.assertEqual(ys, [-y for y in reversed(ys)])
        self.assertEqual(chords, list(reversed(chords)))

    def test_rectangular_chords_and_uniform_scale_preserve_effectiveness(self):
        base = derive_effectiveness(**self.STIK)
        chord = self.STIK['area'] / self.STIK['span']
        self.assertAlmostEqual(base, derive_effectiveness(**self.STIK, chords=(chord, chord)), places=13)
        # Finite 100 km vortex truncation introduces negligible scale dependence.
        scaled = dict(self.STIK, area=self.STIK['area'] * 4, span=self.STIK['span'] * 2)
        self.assertAlmostEqual(base, derive_effectiveness(**scaled), delta=1e-9)

    def test_requested_roll_derivative_by_independent_linear_solve(self):
        for area, span, chords in [(self.STIK['area'], 1.524, None), (3.0, 4.0, (1.0, 0.5))]:
            tau = derive_effectiveness(area, span, 4.58, 0.36, -0.0823, chords)
            edges, ys, local_chords = _geometry(area, span, chords)
            influence = _influence(edges, ys, local_chords)
            slope, _ = _calibrate(influence, 4.58 - 0.36)
            # Directly solve the physical system for each one-sided deflection;
            # do not multiply the inverse used by the authoring helper.
            for side in (-1, 1):
                matrix = [[float(i == j) + slope * value for j, value in enumerate(row)]
                          + [slope * tau * float(y * side > 0)]
                          for i, (y, row) in enumerate(zip(ys, influence))]
                for col in range(6):
                    pivot = max(range(col, 6), key=lambda i: abs(matrix[i][col]))
                    matrix[col], matrix[pivot] = matrix[pivot], matrix[col]
                    for row in range(col + 1, 6):
                        factor = matrix[row][col] / matrix[col][col]
                        for j in range(col, 7):
                            matrix[row][j] -= factor * matrix[col][j]
                lift = [0.0] * 6
                for row in reversed(range(6)):
                    lift[row] = (matrix[row][-1] - sum(matrix[row][j] * lift[j]
                                                       for j in range(row + 1, 6))) / matrix[row][row]
                roll = -sum(y * cl for y, cl in zip(ys, lift)) / (6 * span)
                self.assertAlmostEqual(roll, -side * 0.0823, places=12)

    def test_rejects_invalid_and_unreachable_inputs(self):
        for key in self.STIK:
            for value in (float('nan'), float('inf'), True, '1'):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    derive_effectiveness(**dict(self.STIK, **{key: value}))
        for changes in [dict(area=0), dict(span=-1), dict(lift_slope=0),
                        dict(tail_lift_share=-1), dict(tail_lift_share=5),
                        dict(clda_right=0), dict(clda_right=0.0823),
                        dict(lift_slope=100), dict(lift_slope=0.361, tail_lift_share=0.36),
                        dict(clda_right=-10), dict(clda_right=-1e-9),
                        dict(area=1e308, span=1e-308)]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                derive_effectiveness(**dict(self.STIK, **changes))
        for chords in [0.3, 'ab', (), (0.3,), (0.3, 0.3, 0.3), (0.1, 0.2),
                       (0.3, 0), (float('nan'), 0.1), (1, 1)]:
            with self.subTest(chords=chords), self.assertRaises(ValueError):
                derive_effectiveness(**self.STIK, chords=chords)


if __name__ == '__main__':
    unittest.main()
