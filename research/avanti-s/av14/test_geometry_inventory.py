"""Independent AV-15 geometry and mass-property checks (standard library only)."""
from __future__ import annotations

import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]
GENERATOR = ROOT / "research/avanti-s/av06/derive_physics.py"
GEOMETRY = ROOT / "assets/aircraft/avanti-s-a200/geometry.json"
GENERATED_JSON = ROOT / "app/data/aircraft/sebart_avanti_s_a200.json"


def load_generator():
    spec = importlib.util.spec_from_file_location("avanti_av06_source", GENERATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not import {GENERATOR}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


AV06 = load_generator()


def integrate_piecewise_tail(rows: list[list[float]], chord_scale: float = 1.0) -> tuple[float, float, float, float]:
    """Analytically integrate area and x/y first moments for linear tail stations.

    Each source row is [span y, leading-edge x, trailing-edge x, height]. The
    station-to-station chord and leading edge are linear; the mass line is at
    leading edge + 45% chord, matching the documented AV-06 placement rule.
    """
    area = moment_y = moment_x = moment_c2 = 0.0
    for a, b in zip(rows, rows[1:]):
        y0, le0, te0, _ = a
        y1, le1, te1, _ = b
        dy = y1 - y0
        c0, c1 = chord_scale * (te0 - le0), chord_scale * (te1 - le1)
        dc, dle = c1 - c0, le1 - le0
        segment_area = dy * (c0 + c1) / 2.0
        span_first = dy * (y0 * (c0 + c1) / 2.0 + dy * (c0 + 2.0 * c1) / 6.0)
        le_chord_integral = dy * (le0 * c0 + (le0 * dc + dle * c0) / 2.0 + dle * dc / 3.0)
        chord_squared_integral = dy * (c0 * c0 + c0 * c1 + c1 * c1) / 3.0
        area += segment_area
        moment_y += span_first
        moment_x += le_chord_integral + 0.45 * chord_squared_integral
        moment_c2 += chord_squared_integral
    return area, moment_y / area, moment_x / area, moment_c2 / (chord_scale * area)


def sampled_tail_centroid(rows: list[list[float]], chord_scale: float, resolution: int) -> tuple[float, float, float]:
    strips = AV06.strips(rows, chord_scale=chord_scale, n=resolution)
    root_y = rows[0][0]
    exposed = [strip for strip in strips if strip[0] >= root_y]
    area = sum(chord * dy for _, _, chord, _, dy in exposed)
    ybar = sum(chord * y * dy for y, _, chord, _, dy in exposed) / area
    xbar = sum((le + 0.45 * chord) * chord * dy for _, le, chord, _, dy in exposed) / area
    return area, ybar, xbar


def inventory_cg(parts: list[tuple]) -> list[float]:
    total = sum(part[1] for part in parts)
    return [sum(part[1] * part[4][axis] for part in parts) / total for axis in range(3)]


def find_quantity(node, key: str):
    if isinstance(node, dict):
        value = node.get(key)
        if isinstance(value, dict) and {"value", "unit", "kind", "source"}.issubset(value):
            return value
        for child in node.values():
            found = find_quantity(child, key)
            if found is not None:
                return found
    elif isinstance(node, list):
        for child in node:
            found = find_quantity(child, key)
            if found is not None:
                return found
    return None


def inventory_tensor(parts: list[tuple], point: list[float]) -> list[float]:
    """Box inertia and parallel-axis terms in runtime [xx, yy, zz, xy, xz, yz] order."""
    j = [0.0] * 6
    for part in parts:
        mass, position, size = part[1], part[4], part[5] or [0.0, 0.0, 0.0]
        x = -(position[0] - point[0])
        y = position[1] - point[1]
        z = -(position[2] - point[2])
        j[0] += mass * (y * y + z * z) + mass * (size[1] ** 2 + size[2] ** 2) / 12.0
        j[1] += mass * (x * x + z * z) + mass * (size[0] ** 2 + size[2] ** 2) / 12.0
        j[2] += mass * (x * x + y * y) + mass * (size[0] ** 2 + size[1] ** 2) / 12.0
        j[3] -= mass * x * y
        j[4] -= mass * x * z
        j[5] -= mass * y * z
    return j


def symmetric_eigenvalues(matrix: list[list[float]]) -> list[float]:
    """Jacobi diagonalization for a real symmetric 3x3 matrix."""
    a = [row[:] for row in matrix]
    for _ in range(32):
        p, q = max(((0, 1), (0, 2), (1, 2)), key=lambda pair: abs(a[pair[0]][pair[1]]))
        apq = a[p][q]
        if abs(apq) < 1e-14:
            break
        tau = (a[q][q] - a[p][p]) / (2.0 * apq)
        t = math.copysign(1.0, tau) / (abs(tau) + math.sqrt(1.0 + tau * tau))
        c = 1.0 / math.sqrt(1.0 + t * t)
        s = t * c
        app, aqq = a[p][p], a[q][q]
        a[p][p] = app - t * apq
        a[q][q] = aqq + t * apq
        a[p][q] = a[q][p] = 0.0
        for k in range(3):
            if k == p or k == q:
                continue
            akp, akq = a[k][p], a[k][q]
            a[k][p] = a[p][k] = c * akp - s * akq
            a[k][q] = a[q][k] = s * akp + c * akq
    return sorted((a[0][0], a[1][1], a[2][2]))


class GeometryInventoryTests(unittest.TestCase):
    def test_analytic_trapezoid_planform(self):
        h, x0, sweep, cr, ct = 0.82, 0.12, 0.37, 0.42, 0.19
        rows = [
            [0.0, x0, x0 + cr, 0.06],
            [h, x0 + sweep * h, x0 + sweep * h + ct, 0.07],
        ]
        result = AV06.planform(AV06.strips(rows, n=20_000))
        expected_area = h * (cr + ct)
        expected_mac = 2.0 * (cr * cr + cr * ct + ct * ct) / (3.0 * (cr + ct))
        expected_y = h * (cr + 2.0 * ct) / (3.0 * (cr + ct))
        expected_mac_le = x0 + sweep * expected_y
        self.assertAlmostEqual(result[0], expected_area, delta=1e-9)
        self.assertAlmostEqual(result[1], expected_mac, delta=1e-9)
        self.assertAlmostEqual(result[2], expected_mac_le, delta=1e-9)
        self.assertAlmostEqual(result[3], expected_y, delta=1e-9)

    def test_exposed_tail_matches_independent_first_moments(self):
        geometry = json.loads(GEOMETRY.read_text(encoding="utf-8"))
        tail_rows = geometry["tail"]["stations"]
        chord_scale = AV06.v("airframe.stab_chord_scale")
        base_area, base_y, _, _ = integrate_piecewise_tail(tail_rows)
        expected_area, expected_y, expected_x, _ = integrate_piecewise_tail(tail_rows, chord_scale)

        self.assertAlmostEqual(base_area, 0.07038, places=10)
        self.assertAlmostEqual(expected_y, base_y, places=10)
        self.assertAlmostEqual(AV06.th_area, expected_area, places=9)
        self.assertAlmostEqual(AV06.th_y, expected_y, delta=3e-6)
        self.assertAlmostEqual(AV06.th_z, expected_x, delta=1e-6)

        area_60, y_60, x_60 = sampled_tail_centroid(tail_rows, chord_scale, 60)
        area_240, y_240, x_240 = sampled_tail_centroid(tail_rows, chord_scale, 240)
        error_60 = math.hypot(y_60 - expected_y, x_60 - expected_x)
        error_240 = math.hypot(y_240 - expected_y, x_240 - expected_x)
        self.assertAlmostEqual(area_60, expected_area, places=12)
        self.assertAlmostEqual(area_240, expected_area, places=12)
        self.assertLess(error_240, error_60)
        self.assertGreater(error_60 / error_240, 10.0)

        scaled_area, scaled_y, scaled_x, _ = integrate_piecewise_tail(tail_rows, 1.1)
        _, scale_1_y, scale_1_x, base_c2_over_area = integrate_piecewise_tail(tail_rows, 1.0)
        self.assertAlmostEqual(scaled_area, 1.1 * base_area, places=10)
        self.assertAlmostEqual(scaled_y, scale_1_y, places=10)
        self.assertAlmostEqual(scaled_x - scale_1_x, 0.45 * 0.1 * base_c2_over_area, places=12)
        area_scaled_sample, y_scaled_sample, x_scaled_sample = sampled_tail_centroid(tail_rows, 1.1, 60)
        self.assertAlmostEqual(area_scaled_sample, scaled_area, places=12)
        self.assertAlmostEqual(y_scaled_sample, scaled_y, delta=3e-6)
        self.assertAlmostEqual(x_scaled_sample, scaled_x, delta=1e-6)

        generated = json.loads(GENERATED_JSON.read_text(encoding="utf-8"))
        tail_parts = [part for part in generated["inventory"] if part["name"].startswith("stab half ")]
        self.assertEqual(len(tail_parts), 2)
        for part in tail_parts:
            position = part["position"]["value"]
            self.assertAlmostEqual(position[0], AV06.th_z, delta=1e-6)
            self.assertAlmostEqual(abs(position[1]), AV06.th_y, delta=1e-6)

    def test_servo_pairs_preserve_mass_and_have_local_tensor(self):
        groups = {
            "aileron servo": (0.13, 0.75, 1.50, 0.35, 0.0),
            "flap servo": (0.15, 0.35, 0.70, 0.33, 0.0),
            "elevator servo": (0.13, 0.125, 0.25, 0.95, 0.06),
        }
        total_delta = 0.0
        for name, (pair_mass, half_span, old_box_span, expected_x, expected_z) in groups.items():
            pair = [part for part in AV06.items if part[0].startswith(name + " ")]
            self.assertEqual(len(pair), 2, name)
            self.assertAlmostEqual(sum(part[1] for part in pair), pair_mass, places=12)
            self.assertEqual({part[2] for part in pair}, {"estimated"})
            lateral = sorted(part[4][1] for part in pair)
            self.assertAlmostEqual(lateral[0], -half_span, places=12)
            self.assertAlmostEqual(lateral[1], half_span, places=12)
            for part in pair:
                self.assertAlmostEqual(part[4][0], expected_x, places=12)
                self.assertAlmostEqual(part[4][2], expected_z, places=12)
                self.assertEqual(part[5], [0.03, 0.03, 0.03])

            new_y_second_moment = sum(
                part[1] * (part[4][1] ** 2 + part[5][1] ** 2 / 12.0) for part in pair
            )
            old_y_second_moment = pair_mass * old_box_span ** 2 / 12.0
            total_delta += new_y_second_moment - old_y_second_moment

        self.assertAlmostEqual(total_delta, 0.06238491666666667, places=12)
        for name in ("rudder servo", "nose steering servo"):
            item = next(part for part in AV06.items if part[0] == name)
            self.assertEqual(item[2], "estimated")

    def test_full_inventory_tensor_has_physical_principal_moments(self):
        parts = AV06.items
        cg = inventory_cg(parts)
        self.assertAlmostEqual(cg[0], AV06.cg[0], places=9)
        self.assertAlmostEqual(cg[1], 0.0, delta=1e-10)
        self.assertAlmostEqual(cg[2], AV06.cg[2], places=9)
        tensor = inventory_tensor(parts, cg)
        for calculated, reported in zip(tensor, AV06.J):
            self.assertAlmostEqual(calculated, reported, delta=1e-10)

        xx, yy, zz, xy, xz, yz = tensor
        principal = symmetric_eigenvalues([[xx, xy, xz], [xy, yy, yz], [xz, yz, zz]])
        for calculated, reported in zip(principal, AV06.I_principal):
            self.assertAlmostEqual(calculated, reported, delta=1e-9)
        self.assertTrue(all(moment > 0.0 for moment in principal), principal)
        self.assertGreaterEqual(principal[0] + principal[1] + 1e-12, principal[2], principal)

    def test_generated_artifacts_match_source_pipeline(self):
        env = os.environ.copy()
        env.pop("OPENRC_AIRCRAFT_OUTPUT_DIR", None)
        env.pop("OPENRC_AIRCRAFT_REPORT_DIR", None)
        result = subprocess.run(
            [sys.executable, str(GENERATOR), "--check"],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_generated_provenance_keeps_estimates_and_model_limits_explicit(self):
        generated = json.loads(GENERATED_JSON.read_text(encoding="utf-8"))
        inputs = json.loads((ROOT / "research/avanti-s/av06/inputs.json").read_text(encoding="utf-8"))
        cg_source = inputs["airframe"]["cg_aft_of_root_le"]["source"]
        self.assertIn("no fuel-state qualifier", cg_source)
        self.assertIn("half-tank state is separately declared", cg_source)

        for part in generated["inventory"]:
            if "servo" in part["name"]:
                self.assertEqual(part["mass"]["kind"], "estimated", part["name"])

        cd0 = find_quantity(generated, "CD0")
        governor = find_quantity(generated, "governor_tau")
        fuel_flow = find_quantity(generated, "fuel_flow")
        self.assertIsNotNone(cd0)
        self.assertIn("M=0.34", cd0["source"])
        self.assertIn("derivation.md", cd0["source"])
        self.assertIsNotNone(governor)
        self.assertEqual(governor["value"], 0.4)
        self.assertEqual(governor["kind"], "measured")
        self.assertIn("not a universal ECU step response", governor["source"])
        self.assertIsNotNone(fuel_flow)
        self.assertIn("no current runtime consumer", fuel_flow["source"])


if __name__ == "__main__":
    unittest.main()
