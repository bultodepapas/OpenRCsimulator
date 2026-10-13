"""Numerical invariants for the independent crank-angle glow-cycle oracle."""

from __future__ import annotations

import importlib.util
import json
import math
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("cycle_oracle.py")
SPEC = importlib.util.spec_from_file_location("cycle_oracle", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
oracle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oracle)


class GeometryAndCycleTests(unittest.TestCase):
    def profiles(self) -> dict[str, dict]:
        return {family: json.loads((oracle.PROFILE_DIR / config["profile"]).read_text(encoding="utf-8"))
                for family, config in oracle.ENGINES.items()}

    def test_manufacturer_bore_stroke_reproduce_candidate_displacement(self) -> None:
        profiles = self.profiles()
        for family, config in oracle.ENGINES.items():
            params = profiles[family]["parameters"]
            geom = {key: oracle.qvalue(params, key) for key in ["bore_m", "stroke_m"]}
            swept = math.pi * geom["bore_m"] ** 2 * geom["stroke_m"] / 4.0
            disp = oracle.qvalue(params, "displacement_m3")
            self.assertAlmostEqual(swept, disp, delta=disp * 0.001)

    def test_slider_crank_volume_hits_clearance_and_swept_endpoints(self) -> None:
        for family, config in oracle.ENGINES.items():
            params = self.profiles()[family]["parameters"]
            geom = {key: oracle.qvalue(params, key) for key in ["bore_m", "stroke_m"]}
            disp = math.pi * geom["bore_m"] ** 2 * geom["stroke_m"] / 4.0
            cr = 8.0
            v_tdc = oracle.volume_m3(0.0, disp, geom["bore_m"], geom["stroke_m"], cr, 4.0)
            v_bdc = oracle.volume_m3(180.0, disp, geom["bore_m"], geom["stroke_m"], cr, 4.0)
            self.assertAlmostEqual(v_tdc, disp / (cr - 1.0), delta=1e-15)
            self.assertAlmostEqual(v_bdc - v_tdc, disp, delta=disp * 1e-12)

    def test_true_cycle_period_and_distinct_valve_or_port_events(self) -> None:
        two = oracle.cycle_angles("glow_2t", oracle.ENGINES["glow_2t"]["nominal"])
        four = oracle.cycle_angles("glow_4t", oracle.ENGINES["glow_4t"]["nominal"])
        self.assertEqual(two["end"] - two["start"], 360.0)
        self.assertEqual(four["end"] - four["start"], 720.0)
        self.assertLess(two["epo"], two["tpo"])
        self.assertLess(two["tpo"], two["tpc"])
        self.assertLess(two["tpc"], two["epc_next"])
        self.assertLess(four["start"], four["tdc"])
        self.assertLess(four["tdc"], four["evo"])
        self.assertLess(four["evo"], four["ivo"])
        self.assertLess(four["ivo"], four["evc"])
        self.assertLess(four["evc"], four["ivc_next"])

    def test_wiebe_law_is_bounded_and_releases_unit_mass_fraction(self) -> None:
        start, duration = 345.0, 40.0
        self.assertEqual(oracle.wiebe_fraction(start - 1.0, start, duration), 0.0)
        self.assertEqual(oracle.wiebe_fraction(start + duration, start, duration), 1.0)
        values = [oracle.wiebe_fraction(start + duration * i / 100, start, duration) for i in range(101)]
        self.assertTrue(all(0.0 <= value <= 1.0 for value in values))
        self.assertEqual(values, sorted(values))


class ThermodynamicIntegrationTests(unittest.TestCase):
    def profiles(self) -> dict[str, dict]:
        return {family: json.loads((oracle.PROFILE_DIR / config["profile"]).read_text(encoding="utf-8"))
                for family, config in oracle.ENGINES.items()}

    def test_closed_first_law_balance_and_fuel_heat_budget(self) -> None:
        profiles = self.profiles()
        for family, config in oracle.ENGINES.items():
            profile = profiles[family]
            rpm = oracle.qvalue(profile["operation"], "rated_rpm")
            trace = oracle.simulate_cycle(profile, family, rpm, 1.0)
            self.assertGreater(trace["cycle_work_j"], 0.0)
            self.assertGreater(trace["heat_released_to_gas_j"], 0.0)
            self.assertAlmostEqual(trace["heat_released_to_gas_j"],
                                   oracle.family_inputs(profile, rpm)["chemical_heat_j_cycle"]
                                   * config["nominal"]["heat_to_gas_fraction"],
                                   delta=1e-10)
            self.assertLess(abs(trace["closed_energy_first_law_residual_j"]), 1e-10)

    def test_refinement_converges_pressure_work_without_claiming_measurement(self) -> None:
        profiles = self.profiles()
        for family in oracle.ENGINES:
            profile = profiles[family]
            rpm = oracle.qvalue(profile["operation"], "rated_rpm")
            coarse = oracle.simulate_cycle(profile, family, rpm, 1.0)
            fine = oracle.simulate_cycle(profile, family, rpm, 0.0625)
            self.assertLess(abs(coarse["cycle_work_j"] / fine["cycle_work_j"] - 1.0), 0.001)
            self.assertLess(abs(coarse["peak_pressure_pa"] / fine["peak_pressure_pa"] - 1.0), 0.002)

    def test_unlocked_phase_probe_reports_phase_sensitive_quadrature(self) -> None:
        profiles = self.profiles()
        for family in oracle.ENGINES:
            profile = profiles[family]
            rpm = oracle.qvalue(profile["operation"], "rated_rpm")
            trace = oracle.simulate_cycle(profile, family, rpm, 0.25)
            rows = oracle.unlocked_phase_sampling_audit(trace, [20.0, 1.0], 16)
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]["phase_offsets_tested"], 16)
            self.assertGreater(rows[0]["max_abs_work_error_fraction"], 0.0)
            self.assertLess(rows[1]["rms_work_error_fraction"], rows[0]["rms_work_error_fraction"])

    def test_profile_and_oracle_work_are_reported_as_separate_closures(self) -> None:
        profiles = self.profiles()
        for family in oracle.ENGINES:
            profile = profiles[family]
            rpm = oracle.qvalue(profile["operation"], "rated_rpm")
            result = oracle.simulate_cycle(profile, family, rpm, 0.5)
            self.assertGreater(result["candidate_kernel_cycle_work_j"], 0.0)
            self.assertNotEqual(result["cycle_work_j"], result["candidate_kernel_cycle_work_j"])
            self.assertNotEqual(result["thermodynamic_indicated_efficiency_estimate"],
                                oracle.family_inputs(profile, rpm)["indicated_efficiency"])


class PropellerAndPeriodMapTests(unittest.TestCase):
    def profiles(self) -> dict[str, dict]:
        return {family: json.loads((oracle.PROFILE_DIR / config["profile"]).read_text(encoding="utf-8"))
                for family, config in oracle.ENGINES.items()}

    def test_estimated_piston_mass_adds_angle_dependent_inertia(self) -> None:
        profiles = self.profiles()
        for family, config in oracle.ENGINES.items():
            profile = profiles[family]
            aircraft = json.loads((oracle.ROOT / "app" / "data" / "aircraft" / config["aircraft"])
                                  .read_text(encoding="utf-8"))
            rotor = oracle.qvalue(aircraft["propulsion"]["propeller"], "rotating_inertia")
            base = oracle.effective_rotor_inertia_kg_m2(0.0, profile, rotor)
            at_quarter_turn = oracle.effective_rotor_inertia_kg_m2(90.0, profile, rotor)
            self.assertAlmostEqual(base, rotor, delta=1e-15)
            self.assertGreater(at_quarter_turn, base)
            doubled_mass = oracle.effective_rotor_inertia_kg_m2(
                90.0, profile, rotor, 2.0 * oracle.qvalue(profile["parameters"], "reciprocating_mass_kg"))
            self.assertGreater(doubled_mass, at_quarter_turn)

    def test_default_installed_propellers_pass_independent_static_power_bound(self) -> None:
        for family, config in oracle.ENGINES.items():
            prop = oracle.installation_prop(oracle.PROFILE_DIR / config["installation"])
            profile = json.loads((oracle.PROFILE_DIR / config["profile"]).read_text(encoding="utf-8"))
            rpm = oracle.qvalue(profile["operation"], "rated_rpm")
            load = oracle.propeller_load(rpm, 0.0, oracle.DEFAULT_RHO_KG_M3, prop)
            self.assertTrue(load["ideal_power_bound_pass"])
            if load["ideal_actuator_disk_power_w"] > 0.0:
                self.assertGreaterEqual(load["shaft_to_ideal_power_ratio"], 1.0)

    def test_periodic_energy_map_closes_for_both_default_families(self) -> None:
        for family, config in oracle.ENGINES.items():
            profile = json.loads((oracle.PROFILE_DIR / config["profile"]).read_text(encoding="utf-8"))
            prop = oracle.installation_prop(oracle.PROFILE_DIR / config["installation"])
            aircraft = json.loads((oracle.ROOT / "app" / "data" / "aircraft" / config["aircraft"])
                                  .read_text(encoding="utf-8"))
            inertia = oracle.qvalue(aircraft["propulsion"]["propeller"], "rotating_inertia")
            roots = oracle.dynamic_orbit_roots(profile, family, prop, config["nominal"],
                                              inertia, 1.0)
            self.assertTrue(roots, family)
            root = roots[-1]
            self.assertTrue(root["ok"])
            self.assertFalse(root["stopped"])
            self.assertLess(abs(root["end_rpm"] / root["start_rpm"] - 1.0), 1e-5)
            self.assertGreater(root["max_rpm"], root["min_rpm"])


if __name__ == "__main__":
    unittest.main()
