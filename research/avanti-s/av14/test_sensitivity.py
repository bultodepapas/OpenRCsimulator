"""Focused AV-06 sensitivity checks for fixed-build fuel changes."""
import copy
import hashlib
import importlib.util
import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SENSITIVITY_PATH = ROOT / "research" / "avanti-s" / "av06" / "sensitivity.py"
SPEC = importlib.util.spec_from_file_location("av06_sensitivity", SENSITIVITY_PATH)
sensitivity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sensitivity)


def independent_interpolate(rows, x):
    if x <= rows[0][0]:
        return rows[0][1]
    for index in range(len(rows) - 1):
        x0, y0 = rows[index]
        x1, y1 = rows[index + 1]
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return rows[-1][1]


def independent_thrust(reference, speed, rpm):
    """Evaluate the fixed P100 momentum map from its tabulated inputs."""
    flow = independent_interpolate(reference["mass_flow_rows"], rpm)
    bench_thrust = independent_interpolate(reference["thrust_rows"], rpm)
    ram_ratio = independent_interpolate(reference["ram_jet_rows"], rpm)
    jet_velocity_zero = reference["installed_factor"] * bench_thrust / flow
    captured_flow = flow * (1 + reference["ram_flow"] * speed**2)
    exhaust_velocity = math.sqrt(jet_velocity_zero**2 + ram_ratio * speed**2)
    return captured_flow * (exhaust_velocity - speed)


def independent_drag(reference, speed, mass):
    """Drag-polar identity D=q*S*CD0 + k*W^2/(q*S)."""
    q = 0.5 * reference["rho"] * speed**2
    weight = mass * reference["g"]
    return q * reference["area"] * reference["cd0"] + reference["k_ind"] * weight**2 / (q * reference["area"])


class FuelSensitivityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = sensitivity.run(sensitivity.BASE)

    def test_fuel_rows_satisfy_fixed_build_invariants(self):
        for fraction in (1.0, 0.0):
            with self.subTest(fraction=fraction):
                inputs = sensitivity.with_("fuel.fraction", fraction)
                fuel_mass = inputs["fuel"]["tank_l"]["value"] * fraction * inputs["fuel"]["density"]["value"]
                result = sensitivity.fuel_case(self.base, inputs)
                delta_fuel = fuel_mass - self.base["fuel"]

                self.assertAlmostEqual(result["fuel"], fuel_mass, places=12)
                self.assertAlmostEqual(result["mass"], self.base["mass"] + delta_fuel, places=12)
                for axis in range(3):
                    baseline_moment = self.base["mass"] * self.base["cg"][axis]
                    expected_moment = baseline_moment + delta_fuel * self.base["fuel_pos"][axis]
                    self.assertAlmostEqual(result["mass"] * result["cg"][axis], expected_moment, places=11)

                self.assertAlmostEqual(
                    result["stall"] / self.base["stall"],
                    math.sqrt(result["mass"] / self.base["mass"]),
                    places=11,
                )
                self.assertAlmostEqual(
                    result["sm"],
                    100 * (self.base["x_np"] - result["cg"][0]) / self.base["mac"],
                    places=10,
                )

                vmax_residual = independent_thrust(self.base, result["vmax"], self.base["max_rpm"])
                vmax_residual -= independent_drag(self.base, result["vmax"], result["mass"])
                self.assertAlmostEqual(vmax_residual, 0.0, delta=1e-7)

                speed = self.base["v_start"]
                excess_power = (
                    independent_thrust(self.base, speed, self.base["max_rpm"])
                    - independent_drag(self.base, speed, result["mass"])
                ) * speed
                reported_power = result["roc"] * result["mass"] * self.base["g"]
                self.assertAlmostEqual(reported_power, excess_power, places=9)

    def test_fuel_at_baseline_fraction_is_identity(self):
        actual = sensitivity.fuel_case(self.base, sensitivity.BASE)
        for name in ("mass", "sm", "stall", "vmax", "roc", "roll40"):
            self.assertAlmostEqual(actual[name], self.base[name], places=10, msg=name)
        for actual_coordinate, baseline_coordinate in zip(actual["cg"], self.base["cg"]):
            self.assertAlmostEqual(actual_coordinate, baseline_coordinate, places=12)

    def test_full_and_empty_fuel_trends_are_monotonic(self):
        full = sensitivity.fuel_case(self.base, sensitivity.with_("fuel.fraction", 1.0))
        empty = sensitivity.fuel_case(self.base, sensitivity.with_("fuel.fraction", 0.0))
        self.assertGreater(full["mass"], empty["mass"])
        self.assertLess(full["cg"][0], empty["cg"][0])
        self.assertGreater(full["stall"], empty["stall"])
        self.assertGreater(empty["vmax"], full["vmax"])
        self.assertLess(full["roc"], empty["roc"])

    def test_rebalanced_fuel_cases_expose_the_old_mixed_build_defect(self):
        for fraction in (1.0, 0.0):
            with self.subTest(fraction=fraction):
                inputs = sensitivity.with_("fuel.fraction", fraction)
                fixed_build = sensitivity.fuel_case(self.base, inputs)
                rebalanced_build = sensitivity.run(inputs)
                # The old table took these performance values from a fresh balancing run. The two scenarios have
                # different hardware/ballast mass, so all three must now follow the fixed baseline build instead.
                for name in ("stall", "vmax", "roc"):
                    self.assertNotAlmostEqual(fixed_build[name], rebalanced_build[name], places=7, msg=name)

    def test_wing_area_sweeps_run_and_render(self):
        expected = {
            "wing area 0.78 m2 (+11 %)": 0.78,
            "wing area 0.85 m2 (sibling scaling, +21 %)": 0.85,
        }
        inputs_by_name = dict(sensitivity.cases)
        for name, area in expected.items():
            with self.subTest(case=name):
                result = sensitivity.run(inputs_by_name[name])
                self.assertAlmostEqual(result["area"], area, places=10)
                self.assertAlmostEqual(result["span"] * result["reference_length"], area, places=10)

        rendered = sensitivity.render_rows()
        for name in expected:
            self.assertIn(name, rendered)
        self.assertIn("fixed-build static-polar estimates", rendered)
        self.assertIn("CG-dependent trim drag is omitted", rendered)

    def test_sensitivity_calculation_does_not_mutate_inputs_or_files(self):
        expected_files = (
            SENSITIVITY_PATH,
            sensitivity.HERE / "inputs.json",
            sensitivity.HERE / "derive_physics.py",
            sensitivity.HERE / "derivation.md",
            ROOT / "assets" / "aircraft" / "avanti-s-a200" / "geometry.json",
            ROOT / "app" / "data" / "aircraft" / "jensen_ugly_stik_60.json",
            ROOT / "app" / "data" / "aircraft" / "sebart_avanti_s_a200.json",
            ROOT / "research" / "aircraft-standardization" / "migrate.py",
        )
        missing = [str(path) for path in expected_files if not path.is_file()]
        self.assertEqual(missing, [], "expected sensitivity source/output files must exist before checking for writes")

        input_before = copy.deepcopy(sensitivity.BASE)
        variant = sensitivity.with_("fuel.fraction", 1.0)
        variant_before = copy.deepcopy(variant)
        snapshots = {
            path: hashlib.sha256(path.read_bytes()).digest()
            for path in expected_files
        }

        sensitivity.run(sensitivity.BASE)
        sensitivity.run(variant)
        sensitivity.fuel_case(self.base, variant)

        self.assertEqual(sensitivity.BASE, input_before)
        self.assertEqual(variant, variant_before)
        for path, digest in snapshots.items():
            self.assertEqual(hashlib.sha256(path.read_bytes()).digest(), digest, str(path))


if __name__ == "__main__":
    unittest.main()
