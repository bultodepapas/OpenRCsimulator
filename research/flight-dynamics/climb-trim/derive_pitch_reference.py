"""D6e-R1: where the Ugly Stik's borrowed pitch coefficients must be referenced so its neutral point is its own.

The Stik flies the UltraStick 25e whole-aircraft derivatives. Their ratio -Cma/CLa fixes the neutral point at a
distance behind the coefficient reference point (ARP); it does not fix where the Stik's neutral point is. That comes
from the Stik's wing, tail, downwash and fuselage. This script estimates it with the fleet generators' method
(research/extra-300/ex05/derive_physics.py: Helmbold slopes, tail dynamic-pressure ratio 0.9, Raymer eq. 16.25 fuselage
term) and places the ARP so that ARP + (-Cma/CLa)*c lands on it. It also prints the directional derivatives the loader
requires for that ARP (fin arm from the ARP) and a vortex-lattice cross-check of the wing+tail neutral point.

Usage: python research/flight-dynamics/climb-trim/derive_pitch_reference.py
Writes nothing. Values are estimates from drawings and textbook methods, not a measured static margin.
"""
import json
import math
from pathlib import Path

from vlm_neutral_point import neutral_point as vlm_neutral_point

ROOT = Path(__file__).resolve().parents[3]
DATA = json.loads((ROOT / "app/data/aircraft/jensen_ugly_stik_60.json").read_text(encoding="utf-8"))
GEOMETRY = json.loads((ROOT / "assets/aircraft/ugly-stik-60/geometry.json").read_text(encoding="utf-8"))

KAPPA = 0.9    # section lift slope / 2 pi, as the fleet generators (no Stik polar identified)
ETA_H = 0.9    # tail dynamic-pressure ratio, as the fleet generators; propwash is not modelled for the Stik
K_FUS = 0.008  # Raymer Fig. 16.14 at the root quarter chord near 31 % of body length; estimated +-30 %


def value(node):
    return node["value"]


def helmbold(aspect, kappa):
    return 2 * math.pi * aspect / (2 + math.sqrt((aspect / kappa) ** 2 + 4))


def derive(kappa=KAPPA, eta_h=ETA_H, k_fus=K_FUS, tail_x=None):
    ref, aero = DATA["reference"], DATA["aero"]
    S, b, c = value(ref["wing_area"]), value(ref["wing_span"]), value(ref["mean_chord"])
    horizontal = aero["surfaces"]["horizontal"]
    Sh = value(horizontal["area"])
    xh = value(horizontal["position"])[0] if tail_x is None else tail_x
    deps = value(horizontal["downwash_gradient"])
    bh = GEOMETRY["tail"]["span"]
    cla_w = helmbold(b * b / S, kappa)
    slope_h = helmbold(bh * bh / Sh, kappa) * eta_h * (1 - deps)
    cla = cla_w + slope_h * Sh / S
    hull = dict(zip(DATA["crash_hull_components"], value(DATA["crash_hull"])))
    body_length = hull["tail_end"][0] - hull["spinner"][0]
    body_width = 2 * max(station[1] for station in GEOMETRY["fuselage_stations"])
    cma_fus = k_fus * body_width ** 2 * body_length / (c * S) * 180 / math.pi
    x_ac = 0.25 * c - cma_fus / cla_w * c  # wing-body aerodynamic centre, le frame
    cma_ac = -slope_h * Sh / S * (xh - x_ac) / c
    x_np = x_ac - cma_ac / cla * c
    coefficients = aero["coefficients"]
    donor_margin = -value(coefficients["Cma"]) / value(coefficients["CLa"])
    return {"x_np": x_np, "x_ac": x_ac, "cla": cla, "donor_margin": donor_margin, "arp_x": x_np - donor_margin * c,
            "body_length": body_length, "body_width": body_width, "root_qc_fraction": (0.25 * c - hull["spinner"][0]) / body_length}


def directional(arp_x):
    """The loader's fin-arm contract (app/physics/aircraft_data.gd) for an ARP at arp_x."""
    ref, aero = DATA["reference"], DATA["aero"]
    S, b = value(ref["wing_area"]), value(ref["wing_span"])
    fin = aero["surfaces"]["vertical"]
    fin_lift = value(fin["lift_slope"]) * value(fin["area"]) / S
    arm = value(fin["position"])[0] - arp_x
    return {"Cnb": fin_lift * arm / b, "Cndr": -fin_lift * value(fin["control_effectiveness"]) * arm / b}


if __name__ == "__main__":
    c = value(DATA["reference"]["mean_chord"])
    cg = value(DATA["balance"]["plan_cg"])[0]
    r = derive()
    arp = round(r["arp_x"], 4)
    print(f"body length {r['body_length']:.3f} m, width {r['body_width']:.4f} m, root quarter chord at {100 * r['root_qc_fraction']:.1f} % of body length")
    print(f"wing-body ac {r['x_ac']:.4f} m ({100 * r['x_ac'] / c:.1f} % c); CLa {r['cla']:.3f}/rad")
    print(f"neutral point {r['x_np']:.4f} m ({100 * r['x_np'] / c:.1f} % c); plan CG {cg:.4f} m ({100 * cg / c:.1f} % c); "
          f"margin {100 * (r['x_np'] - cg) / c:.1f} % c before the ARP height term")
    print(f"donor margin -Cma/CLa {100 * r['donor_margin']:.2f} % c -> ARP x {r['arp_x']:.5f} m, written as {arp:.4f} m")
    print("directional derivatives for that ARP (write full precision):", directional(arp))
    for label, kwargs in [("tail ratio 0.85", {"eta_h": 0.85}), ("tail ratio 0.95", {"eta_h": 0.95}),
                          ("K_fus -30 %", {"k_fus": 0.7 * K_FUS}), ("K_fus +30 %", {"k_fus": 1.3 * K_FUS}),
                          ("tail at plan quarter chord 0.8153 m", {"tail_x": 0.8153})]:
        s = derive(**kwargs)
        print(f"  {label:36s} neutral point {100 * s['x_np'] / c:5.1f} % c, ARP {s['arp_x']:.4f} m")
    v = vlm_neutral_point(eta=ETA_H)
    print(f"vortex-lattice cross-check (wing + tail, eta {ETA_H}, no fuselage): neutral point {100 * v['neutral_point']:.1f} % c")
