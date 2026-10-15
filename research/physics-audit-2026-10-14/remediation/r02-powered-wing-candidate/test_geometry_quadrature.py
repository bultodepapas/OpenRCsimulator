"""Independent closed-form and convergence checks for the offline candidate."""

from __future__ import annotations

import math
import unittest

from scipy.integrate import quad

from geometry_quadrature import (
    integrate_panel,
    make_field_sampler,
    p51_physics_panels,
    p51_static_wake_radius,
    p51_strip_centroid_hit,
)


def rectangle(x0: float, x1: float, y0: float, y1: float) -> list[list[float]]:
    return [[x0, y0, 0.0], [x1, y0, 0.0], [x1, y1, 0.0], [x0, y1, 0.0]]


def stable_unit_circle_cap_area(delta: float) -> float:
    """Circle-cap area without subtracting nearly equal acos/sqrt terms."""
    coefficient = 1.0
    integral = 0.0
    for order in range(32):
        if order > 0:
            coefficient *= (order - 1.5) / order
        integral += coefficient * (delta / 2.0) ** order / (2.0 * order + 3.0)
    return 4.0 * math.sqrt(2.0) * delta**1.5 * integral


def independent_p51_strip_area(panel: dict, data: dict, radius: float) -> tuple[float, float]:
    """Physical-y adaptive line integral, independent of candidate plane slicing."""
    vertices = panel["vertices_body_m"]
    y0, y1 = panel["span_edges_le_m"]
    y0 -= data["cg_le_m"][1]
    y1 -= data["cg_le_m"][1]
    origin = data["hub_body_m"]
    ax, ay, az = data["wake_path_body"]
    quadratic = 1.0 - ax * ax

    def width(y: float) -> float:
        fraction = (y - y0) / (y1 - y0)
        leading = vertices[0][0] + fraction * (vertices[3][0] - vertices[0][0])
        trailing = vertices[1][0] + fraction * (vertices[2][0] - vertices[1][0])
        x_min, x_max = min(leading, trailing), max(leading, trailing)
        dy, dz = y - origin[1], vertices[0][2] - origin[2]
        transverse = ay * dy + az * dz
        constant = dy * dy + dz * dz - transverse * transverse - radius * radius
        discriminant = (ax * transverse)**2 - quadratic * constant
        if discriminant <= 0.0:
            return 0.0
        root = math.sqrt(discriminant)
        wake_min = origin[0] + (ax * transverse - root) / quadratic
        wake_max = origin[0] + (ax * transverse + root) / quadratic
        return max(0.0, min(x_max, wake_max) - max(x_min, wake_min))

    value, error = quad(width, y0, y1, epsabs=1e-12, epsrel=1e-12, limit=500)
    return value, error


class GeometryQuadratureTests(unittest.TestCase):
    def test_normal_disk_area_centroid_and_second_moments(self) -> None:
        radius = 0.37
        field = make_field_sampler([0, 0, 1], [0, 0, 0], radius, s_min=None)
        result = integrate_panel(rectangle(-2, 2, -2, 2), field, tolerance=1e-9, keep_samples=False)
        area = math.pi * radius**2
        polar = math.pi * radius**4 / 4.0
        self.assertAlmostEqual(result["outer_geometric_area_m2"], area, delta=2e-12 * area)
        self.assertLess(max(abs(value) for value in result["raw_first_moment_m3"]), 2e-13 * area)
        for index in (0, 3):
            self.assertAlmostEqual(result["raw_second_moment_m4"][index], polar, delta=3e-12 * polar)
        for index in (1, 2, 4, 5):
            self.assertLess(abs(result["raw_second_moment_m4"][index]), 2e-13 * area * radius**2)

    def test_oblique_axis_ellipse_area_and_axis_moments(self) -> None:
        radius, mu = 0.2, 0.5
        axis = [math.sqrt(1.0 - mu * mu), 0.0, mu]
        field = make_field_sampler(axis, [0, 0, 0], radius, s_min=None)
        result = integrate_panel(rectangle(-1, 1, -1, 1), field, tolerance=1e-9, keep_samples=False)
        area = math.pi * radius**2 / mu
        self.assertAlmostEqual(result["outer_geometric_area_m2"], area, delta=3e-11 * area)
        self.assertAlmostEqual(result["raw_second_moment_m4"][0], area * (radius / mu)**2 / 4,
                               delta=4e-10 * area * (radius / mu)**2)
        self.assertAlmostEqual(result["raw_second_moment_m4"][3], area * radius**2 / 4,
                               delta=4e-10 * area * radius**2)

    def test_exact_parallel_axis_is_a_band(self) -> None:
        radius = 0.2
        field = make_field_sampler([1, 0, 0], [0, 0, 0], radius, s_min=None)
        result = integrate_panel(rectangle(-1, 1, -1, 1), field, tolerance=1e-10, keep_samples=False)
        self.assertAlmostEqual(result["outer_geometric_area_m2"], 4.0 * radius, delta=1e-13)
        self.assertAlmostEqual(result["raw_first_moment_m3"][0], 0.0, delta=1e-13)
        self.assertAlmostEqual(result["raw_second_moment_m4"][0], 4.0 * radius / 3.0, delta=2e-13)
        self.assertAlmostEqual(result["raw_second_moment_m4"][3], 4.0 * radius**3 / 3.0, delta=2e-13)

    def test_near_parallel_sequence_converges_to_exact_band(self) -> None:
        radius = 0.2
        panel = rectangle(-1, 1, -1, 1)
        rows = []
        for mu in (1e-1, 1e-2, 1e-3, 1e-5, 1e-8, 0.0):
            axis = [math.sqrt(max(0.0, 1.0 - mu * mu)), 0.0, mu]
            field = make_field_sampler(axis, [0, 0, 0], radius, s_min=None)
            result = integrate_panel(panel, field, tolerance=2e-9, keep_samples=False)
            if mu == 0.0:
                exact = 4.0 * radius
            else:
                edge = math.sqrt(radius**2 - (mu * 1.0)**2)
                exact = 2.0 * edge + 2.0 * radius**2 / mu * math.asin(mu / radius)
            self.assertAlmostEqual(result["outer_geometric_area_m2"], exact, delta=2e-9 * exact)
            rows.append((mu, result["outer_geometric_area_m2"], result["y_quadrature_evaluations"]))
        self.assertLess(abs(rows[-2][1] - rows[-1][1]), 2e-15)
        self.near_parallel_rows = rows

    def test_near_tangent_circle_caps(self) -> None:
        rows = []
        for delta in (1e-1, 1e-3, 1e-5, 1e-7):
            bottom = 1.0 - delta
            field = make_field_sampler([0, 0, 1], [0, 0, 0], 1.0, s_min=None)
            result = integrate_panel(rectangle(-2, 2, bottom, 1.1), field,
                                     tolerance=2e-8, max_depth=22, keep_samples=False)
            exact = stable_unit_circle_cap_area(delta)
            self.assertAlmostEqual(result["outer_geometric_area_m2"], exact, delta=2e-8 * exact)
            rows.append((delta, exact, result["outer_geometric_area_m2"],
                         result["y_quadrature_evaluations"]))
        self.tangent_rows = rows

    def test_shrinking_disk_radii_preserve_scaled_moments(self) -> None:
        rows = []
        for radius in (1.0, 1e-1, 1e-2, 1e-3, 1e-5):
            field = make_field_sampler([0, 0, 1], [0, 0, 0], radius, s_min=None)
            result = integrate_panel(rectangle(-2 * radius, 2 * radius, -2 * radius, 2 * radius),
                                     field, tolerance=1e-9, keep_samples=False)
            area = math.pi * radius**2
            moment = math.pi * radius**4 / 4.0
            self.assertAlmostEqual(result["outer_geometric_area_m2"], area, delta=3e-11 * area)
            self.assertAlmostEqual(result["raw_second_moment_m4"][0], moment, delta=3e-10 * moment)
            rows.append((radius, result["outer_geometric_area_m2"],
                         result["y_quadrature_evaluations"]))
        self.radius_rows = rows

    def test_finite_axial_window_uses_existing_half_plane_clip(self) -> None:
        field = make_field_sampler([1, 0, 0], [0, 0, 0], 0.2, s_min=0.0, s_max=0.4)
        result = integrate_panel(rectangle(-1, 1, -1, 1), field, tolerance=1e-10, keep_samples=False)
        self.assertAlmostEqual(result["outer_geometric_area_m2"], 0.4 * 0.4, delta=2e-13)
        self.assertAlmostEqual(result["centroid_body_m"][0], 0.2, delta=2e-13)
        self.assertAlmostEqual(result["centroid_body_m"][1], 0.0, delta=2e-13)

    def test_rotation_crossflow_and_smooth_occupancy_moments(self) -> None:
        radius = 1.0
        field = make_field_sampler([0, 0, 1], [0, 0, 0], radius,
                                   delta_v=[1, 0, 0], ambient=[0, 1, 0],
                                   omega=[0, 0, 2], s_min=None)
        result = integrate_panel(rectangle(-2, 2, -2, 2), field, tolerance=1e-9, keep_samples=True)
        area = math.pi
        polar = math.pi / 4.0
        self.assertAlmostEqual(result["velocity_first_moment_m3ps"][0], area, delta=3e-10 * area)
        self.assertAlmostEqual(result["velocity_first_moment_m3ps"][1], area, delta=3e-10 * area)
        self.assertAlmostEqual(result["velocity_second_moment_m4ps2"][0], area + 4 * polar,
                               delta=4e-10 * area)
        self.assertAlmostEqual(result["velocity_second_moment_m4ps2"][1], area,
                               delta=4e-10 * area)
        self.assertAlmostEqual(result["velocity_second_moment_m4ps2"][3], area + 4 * polar,
                               delta=4e-10 * area)

        reversed_increment = make_field_sampler([0, 0, 1], [0, 0, 0], radius,
                                                delta_v=[0, 0, -3], s_min=None)
        reverse = integrate_panel(rectangle(-2, 2, -2, 2), reversed_increment,
                                  tolerance=1e-9, keep_samples=False)
        self.assertAlmostEqual(reverse["outer_geometric_area_m2"], area, delta=3e-10 * area)
        self.assertAlmostEqual(reverse["velocity_first_moment_m3ps"][2], -3 * area,
                               delta=3e-10 * area)

        upstream_origin = [0, 0, 1]
        forward_window = make_field_sampler([0, 0, 1], upstream_origin, 1.0, s_min=0.0)
        reverse_window = make_field_sampler([0, 0, -1], upstream_origin, 1.0, s_min=0.0)
        self.assertEqual(integrate_panel(rectangle(-2, 2, -2, 2), forward_window,
                                         keep_samples=False)["outer_geometric_area_m2"], 0.0)
        reverse_window_result = integrate_panel(rectangle(-2, 2, -2, 2), reverse_window,
                                                tolerance=1e-9, keep_samples=False)
        self.assertAlmostEqual(reverse_window_result["outer_geometric_area_m2"], math.pi,
                               delta=3e-10 * math.pi)

        tapered = make_field_sampler([0, 0, 1], [0, 0, 0], 1.0, s_min=None, edge_fraction=0.1)
        smooth = integrate_panel(rectangle(-2, 2, -2, 2), tapered, tolerance=1e-9, keep_samples=False)
        # C1 occupancy is cubic in squared radius; its transition mean is 1/2.
        expected_weighted_area = math.pi * (0.9**2 + 0.5 * (1.1**2 - 0.9**2))
        self.assertAlmostEqual(smooth["occupancy_weighted_area_m2"], expected_weighted_area,
                               delta=4e-10 * expected_weighted_area)
        inner2 = 0.9**2
        radial_width2 = 1.1**2 - inner2
        weighted_axis_moment = (math.pi / 2.0) * (
            inner2**2 / 2.0 + radial_width2 * (inner2 / 2.0 + 0.15 * radial_width2))
        for index in (0, 3):
            self.assertAlmostEqual(smooth["weighted_second_moment_m4"][index],
                                   weighted_axis_moment,
                                   delta=5e-10 * weighted_axis_moment)

    def test_p51_authored_planform_and_static_wake_overlap(self) -> None:
        data = p51_physics_panels()
        self.assertAlmostEqual(sum(panel["expected_area_m2"] for panel in data["panels"]),
                               data["wing_area_m2"], delta=2e-12)
        for panel in data["panels"]:
            self.assertAlmostEqual(panel["expected_area_m2"], data["wing_area_m2"] / 6.0,
                                   delta=2e-12)
        field = make_field_sampler(data["wake_path_body"], data["hub_body_m"],
                                   p51_static_wake_radius(data), s_min=0.0)
        results = [integrate_panel(panel["vertices_body_m"], field,
                                   tolerance=2e-7, max_depth=20, keep_samples=False)
                   for panel in data["panels"]]
        areas = [result["outer_geometric_area_m2"] for result in results]
        self.assertTrue(all(0.0 <= area <= panel["expected_area_m2"]
                            for panel, area in zip(data["panels"], areas)))
        self.assertEqual([index for index, area in enumerate(areas) if area > 1e-12], [2, 3])
        self.assertTrue(all(not p51_strip_centroid_hit(panel, field) for panel in data["panels"]))
        self.assertAlmostEqual(areas[2], 0.09316023294813035, delta=3e-8)
        self.assertAlmostEqual(areas[3], 0.0739822296078235, delta=3e-8)
        for panel, area in zip(data["panels"], areas):
            independent, reported_error = independent_p51_strip_area(
                panel, data, p51_static_wake_radius(data))
            self.assertAlmostEqual(area, independent, delta=max(5e-11, 5.0 * reported_error))
        self.p51_areas = areas


if __name__ == "__main__":
    unittest.main(verbosity=2)
