"""Independent reference-inventory force/moment checks on generated F4U data."""

import contextlib
import io
import json
from pathlib import Path
import runpy
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = Path(__file__).with_name("derive_physics.py")
AIRCRAFT = ROOT / "app/data/aircraft/f4u_corsair_250.json"


class PhysicsInvariants(unittest.TestCase):
    def test_reference_inventory_rate_wrench(self):
        previous = sys.argv
        try:
            sys.argv = [str(SCRIPT), "--check"]
            with contextlib.redirect_stdout(io.StringIO()):
                g = runpy.run_path(str(SCRIPT))
        finally:
            sys.argv = previous
        data = json.loads(AIRCRAFT.read_text(encoding="utf-8"))
        a = {key: entry["value"] for key, entry in data["aero"]["coefficients"].items()}
        b, c = g["b"], g["c_ref"]
        xg, zg = g["cg"][0], g["cg"][2]
        xa, za = g["x_arp"], g["arp_z"]
        lv, zv = g["xv_ac"] - xg, g["fin_cz"] - zg
        cyb = -g["slope_v"] * g["Sv"] / g["S"]
        dx, dz = xg - xa, zg - za  # body FRD vector from reference CG to ARP

        self.assertAlmostEqual(a["CYp"], 2 * cyb * zv / b, delta=5.1e-7)
        self.assertAlmostEqual(a["CYr"], -2 * cyb * lv / b, delta=5.1e-7)
        tail_arm = g["xh_ac"] - xg
        wing_lift = (0.5 + 2 * (xg - g["x_ac_w"]) / g["mac"]) * g["CLa_w"] * g["mac"] / c
        self.assertAlmostEqual(a["CLq"], 2 * g["tail_q"] * tail_arm / c + wing_lift, delta=5.1e-7)

        # qbar*S=1; rate hats=1. Apply r_ARP/CG x F in dimensional units.
        integral = g["integral"]
        roll_other = (-4 * g["CLa_w"] / (g["S"] * b * b)
                      * integral(lambda y: g["chord"](y) * y * y)
                      - g["eta_h"] * (g["CLa_h"] / 12) * (g["Sh"] / g["S"]) * (g["bh"] / b) ** 2)
        self.assertAlmostEqual((a["Clp"] * b - dz * a["CYp"]) / b,
                               roll_other + zv / b * a["CYp"], delta=1e-6)
        self.assertAlmostEqual((a["Clr"] * b - dz * a["CYr"]) / b,
                               g["CL_ref"] / 4 + zv / b * a["CYr"], delta=1e-6)
        self.assertAlmostEqual((a["Cnp"] * b + dx * a["CYp"]) / b,
                               -g["CL_ref"] / 8 - lv / b * a["CYp"], delta=1e-6)
        self.assertAlmostEqual((a["Cnr"] * b + dx * a["CYr"]) / b,
                               -0.25 * 0.03 - 0.02 - lv / b * a["CYr"], delta=1e-6)
        self.assertAlmostEqual((a["Cmq"] * c + dx * a["CLq"]) / c,
                               -2 * g["tail_q"] * (tail_arm / c) ** 2 * 1.1, delta=1e-6)


if __name__ == "__main__":
    unittest.main()
