"""Independent checks on the generated Extra load reference and propeller section."""

import contextlib
import io
import json
import math
from pathlib import Path
import runpy
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = Path(__file__).with_name("derive_physics.py")
AIRCRAFT = ROOT / "app/data/aircraft/gp_extra_300s_60.json"
INSTALLATION = ROOT / "app/data/glow/extra_61fx_2t.json"
sys.path.insert(0, str(ROOT / "research/glow-engines"))
from calibration_report import annular_prop_performance  # noqa: E402


class PhysicsInvariants(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        previous = sys.argv
        try:
            sys.argv = [str(SCRIPT), "--check"]
            with contextlib.redirect_stdout(io.StringIO()):
                cls.g = runpy.run_path(str(SCRIPT))
        finally:
            sys.argv = previous
        cls.data = json.loads(AIRCRAFT.read_text(encoding="utf-8"))

    def test_reference_inventory_rate_wrench(self):
        g = self.g
        a = {key: entry["value"] for key, entry in self.data["aero"]["coefficients"].items()}
        b, c = g["b"], g["c_ref"]
        xg, zg = g["cg_model_z"], g["cg_model_y"]
        xa, za = g["x_arp"], g["arp_y"]
        lv, zv = g["xv_ac"] - xg, g["fin_cy"] - zg
        cyb = -g["slope_v"] * g["Sv"] / g["S"]
        dx, dz = xg - xa, zg - za  # body FRD vector from reference CG to ARP

        self.assertAlmostEqual(a["Clb"], g["Clb_wing"] + g["dihedral_low"]
                               + cyb * (g["fin_cy"] - za) / b, delta=5.1e-7)
        self.assertAlmostEqual(a["CYp"], 2 * cyb * zv / b, delta=5.1e-7)
        self.assertAlmostEqual(a["CYr"], -2 * cyb * lv / b, delta=5.1e-7)
        tail_arm = g["xh_ac"] - xg
        wing_lift = (0.5 + 2 * (xg - g["x_ac_w"]) / g["mac"]) * g["CLa_w"] * g["mac"] / c
        self.assertAlmostEqual(a["CLq"], 2 * g["tail_q"] * tail_arm / c + wing_lift, delta=5.1e-7)

        # qbar*S=1; rate hats=1. Apply r_ARP/CG x F in dimensional units.
        roll_other = (-(g["CLa_w"] / 12) * (1 + 3 * g["lam"]) / (1 + g["lam"])
                      - g["eta_h"] * (g["CLa_h"] / 12) * (g["Sh"] / g["S"])
                      * (g["bh"] / b) ** 2 * (1 + 3 * g["lh_"]) / (1 + g["lh_"]))
        self.assertAlmostEqual((a["Clp"] * b - dz * a["CYp"]) / b,
                               roll_other + zv / b * a["CYp"], delta=1e-6)
        self.assertAlmostEqual((a["Clr"] * b - dz * a["CYr"]) / b,
                               g["CL_ref"] / 4 + zv / b * a["CYr"], delta=1e-6)
        self.assertAlmostEqual((a["Cnp"] * b + dx * a["CYp"]) / b,
                               -g["CL_ref"] / 8 - lv / b * a["CYp"], delta=1e-6)
        self.assertAlmostEqual((a["Cnr"] * b + dx * a["CYr"]) / b,
                               -0.25 * 0.035 - 0.02 - lv / b * a["CYr"], delta=1e-6)
        self.assertAlmostEqual((a["Cmq"] * c + dx * a["CLq"]) / c,
                               -2 * g["tail_q"] * (tail_arm / c) ** 2 * 1.1, delta=1e-6)

    def test_local_roll_closes_existing_wing_body_estimate(self):
        d, g = self.data, self.g
        surface = d["aero"]["surfaces"]
        term = surface["wing_body_cl_beta"]["value"]
        fin = surface["vertical"]
        ref = d["reference"]
        fin_clb = (-fin["lift_slope"]["value"] * fin["area"]["value"]
                   / ref["wing_area"]["value"]
                   * (fin["position"]["value"][2] - ref["aero_reference_point"]["value"][2])
                   / ref["wing_span"]["value"])
        self.assertGreater(term, 0.0)  # Low-wing interference exceeds the stabilizing wing term.
        self.assertAlmostEqual(term, g["Clb_wing"] + g["dihedral_low"], delta=1e-6)
        self.assertAlmostEqual(term + fin_clb, d["aero"]["coefficients"]["Clb"]["value"], delta=1e-14)

    def test_section_adapter_optional_camber(self):
        from calibration_report import section_from_installation
        prop = json.loads(INSTALLATION.read_text(encoding="utf-8"))["propeller"]
        get = lambda key: prop[key]["value"]
        section = {"lift_slope_per_rad": get("lift_slope"), "cd0": get("cd0"),
                   "induced_drag": get("induced_drag"), "blades": get("blades"),
                   "zero_lift_angle_rad": get("zero_lift_angle_rad")}
        self.assertEqual(section_from_installation(prop), section)
        missing = {key: value for key, value in prop.items() if key != "zero_lift_angle_rad"}
        no_camber = section_from_installation(missing)
        zero_camber = dict(no_camber, zero_lift_angle_rad=0.0)
        self.assertNotIn("zero_lift_angle_rad", no_camber)
        args = (12000, 30.0, get("diameter_m"), get("pitch_m"), get("chord_m"), 1.225)
        self.assertEqual(annular_prop_performance(*args, no_camber), annular_prop_performance(*args, zero_camber))

    def test_installed_section_and_all_crossflow_rows(self):
        prop = json.loads(INSTALLATION.read_text(encoding="utf-8"))["propeller"]
        get = lambda key: prop[key]["value"]
        section = {"lift_slope_per_rad": get("lift_slope"), "cd0": get("cd0"),
                   "induced_drag": get("induced_drag"), "blades": get("blades"),
                   "zero_lift_angle_rad": get("zero_lift_angle_rad")}
        no_camber = {key: value for key, value in section.items() if key != "zero_lift_angle_rad"}
        zero_camber = dict(no_camber, zero_lift_angle_rad=0.0)
        radius, n, rho = get("diameter_m") / 2, 200.0, 1.225
        sigma = get("blades") * get("chord_m") * 0.8 * radius / (math.pi * radius ** 2)

        def tables(j, blade):
            if not j:
                return 0.0, 0.0, 0.0
            thrust = annular_prop_performance(60 * n, j * n * 2 * radius, 2 * radius,
                                              get("pitch_m"), get("chord_m"), rho, blade)["thrust_n"]
            ct = thrust / (rho * n ** 2 * (2 * radius) ** 4)
            a, cd = get("lift_slope"), get("cd0")
            log = math.log1p((math.pi / j) ** 2)
            cl = 3 * j / (2 * math.pi) * (16 * ct / (sigma * math.pi ** 2 * j) + cd)
            cn = sigma * math.pi * j ** 2 / 16 * (cl + a * j / (2 * math.pi) * log + math.pi / j * cd)
            cm = sigma * math.pi * j ** 2 / 32 * (2 * math.pi / (3 * j) * cl
                  + a / 2 * (1 - (j / math.pi) ** 2 * log) - math.pi / j * cd)
            return cn, cm, ct

        nf = self.data["propulsion"]["propeller"]["normal_force"]["value"]
        pm = self.data["propulsion"]["propeller"]["pfactor_moment"]["value"]
        self.assertEqual(len(nf), 22)
        self.assertEqual(len(pm), 22)
        for (j, actual_n), (jm, actual_m) in zip(nf, pm):
            self.assertEqual(j, jm)
            cn, cm, ct = tables(j, section)
            cn0, cm0, ct0 = tables(j, no_camber)
            self.assertEqual(tables(j, zero_camber), (cn0, cm0, ct0))
            self.assertAlmostEqual(cn - cn0, 3 * j ** 2 / (2 * math.pi ** 2) * (ct - ct0), delta=1e-15)
            self.assertAlmostEqual(cm - cm0, j / (2 * math.pi) * (ct - ct0), delta=1e-15)
            self.assertAlmostEqual(actual_n, max(cn, 0.0), delta=5.1e-7)
            self.assertAlmostEqual(actual_m, max(cm, 0.0), delta=5.1e-7)
        self.assertGreater(nf[10][1], 0.006)
        self.assertGreater(pm[10][1], 0.006)


if __name__ == "__main__":
    unittest.main()
