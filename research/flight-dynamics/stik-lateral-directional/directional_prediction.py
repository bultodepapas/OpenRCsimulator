"""Independent semi-empirical prediction of the Ugly Stik's static directional stability (2026-10-18).

The flight data's Cnβ = a_v·S_v/S·l_v/b (0.1274) is the isolated fin with efficiency 1. This script predicts the
two terms it omits from the airframe geometry alone, before any comparison with flight-identified aircraft:

* fin efficiency η_v(1 + dσ/dβ) = 0.724 + 3.06·(S_v/S)/(1 + cos Λ) + 0.4·z_w/h + 0.009·AR
  (USAF DATCOM via Nelson, Flight Stability and Automatic Control, 2nd ed.; z_w is the wing-root quarter-chord
  distance below the fuselage centreline, positive down, h the maximum fuselage height. A high wing gives z_w < 0
  and unfavourable sidewash, consistent with Nicolosi et al. 2017 and NACA wing-position tests);
* fuselage Cnβ,B = −1.3·Vol/(S·b)·√(h/w) (Raymer, Aircraft Design: A Conceptual Approach, 6th ed., eq. 16.50, as
  implemented by FAST-GA), and the inviscid Munk slender-body value −2·Vol·(k2 − k1)/(S·b) as a second estimate.

Inputs: assets/aircraft/ugly-stik-60/geometry.json (plan metrology; stations are [z (nose −Z), half width, top y,
bottom y] in metres) and the reference area/span of app/data/aircraft/jensen_ugly_stik_60.json.
Run from the repository root: python3 -I research/flight-dynamics/stik-lateral-directional/directional_prediction.py
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
geometry = json.loads((ROOT / "assets/aircraft/ugly-stik-60/geometry.json").read_text())
data = json.loads((ROOT / "app/data/aircraft/jensen_ugly_stik_60.json").read_text())

S = data["reference"]["wing_area"]["value"]
b = data["reference"]["wing_span"]["value"]
AR = b * b / S
# The isolated fin term a_v·S_v/S·l_v/b about the aero reference point (efficiency 1), from the vertical-surface data.
# Computed rather than read from Cnb: since D10-R2 the data Cnb already carries the predicted efficiency and body term.
vertical = data["aero"]["surfaces"]["vertical"]
arp_x = data["reference"]["aero_reference_point"]["value"][0]
fin_only = (vertical["lift_slope"]["value"] * vertical["area"]["value"] / S
            * (vertical["position"]["value"][0] - arp_x) / b)

stations = geometry["fuselage_stations"]
z = [s[0] for s in stations]
width = [2.0 * s[1] for s in stations]
height = [s[2] - s[3] for s in stations]
area = [w * h for w, h in zip(width, height)]
volume = sum((z[i + 1] - z[i]) * (area[i] + area[i + 1]) / 2.0 for i in range(len(z) - 1))
length = z[-1] - z[0]
i_max = max(range(len(area)), key=lambda i: area[i])
h_max = max(height)
w_at_max = width[i_max]


def centreline_at(position: float) -> float:
    """Fuselage mid-height (y up) at an axial position, linear between stations."""
    for i in range(len(z) - 1):
        if z[i] <= position <= z[i + 1]:
            f = (position - z[i]) / (z[i + 1] - z[i])
            top = stations[i][2] + f * (stations[i + 1][2] - stations[i][2])
            bottom = stations[i][3] + f * (stations[i + 1][3] - stations[i][3])
            return 0.5 * (top + bottom)
    raise ValueError("position outside the fuselage stations")


def polygon_area(points: list) -> float:
    return abs(sum(points[i][0] * points[(i + 1) % len(points)][1] - points[(i + 1) % len(points)][0] * points[i][1]
                   for i in range(len(points)))) / 2.0


wing = geometry["wing"]
quarter_chord_z = wing["leading_z"] + 0.25 * wing["chord"]  # nose is −Z, so aft is +Z
quarter_chord_y = wing["root_y"]  # root_y is the chord line: the lower surface sits in the fuselage saddle
z_w = -(quarter_chord_y - centreline_at(quarter_chord_z))  # positive down
tail = geometry["tail"]
S_v = polygon_area(tail["fin_outline"]) + polygon_area(tail["rudder_outline"])
sweep = 0.0  # rectangular wing
efficiency = 0.724 + 3.06 * (S_v / S) / (1.0 + math.cos(sweep)) + 0.4 * z_w / h_max + 0.009 * AR

raymer = -1.3 * volume / (S * b) * math.sqrt(h_max / w_at_max)
d_eq = math.sqrt(4.0 * area[i_max] / math.pi)
fineness = length / d_eq
e = math.sqrt(1.0 - 1.0 / fineness ** 2)
log_term = math.log((1.0 + e) / (1.0 - e))
alpha0 = 2.0 * (1.0 - e * e) / e ** 3 * (0.5 * log_term - e)
beta0 = 1.0 / e ** 2 - (1.0 - e * e) / (2.0 * e ** 3) * log_term
k_lamb = beta0 / (2.0 - beta0) - alpha0 / (2.0 - alpha0)
munk = -2.0 * volume * k_lamb / (S * b)

print(f"wing S {S:.6f} m2, b {b:.3f} m, AR {AR:.3f}; isolated fin Cnβ (efficiency 1, about the ARP) {fin_only:.5f} /rad")
print(f"fuselage stations {z[0]:+.3f}..{z[-1]:+.3f} m (firewall to tail; engine and spinner excluded): "
      f"length {length:.3f} m, volume {volume * 1e3:.2f} L, max section {area[i_max] * 1e4:.1f} cm2 "
      f"(h {height[i_max]:.4f}, w {w_at_max:.4f}), max height {h_max:.4f} m")
print(f"wing root quarter chord at z {quarter_chord_z:+.4f} m, y {quarter_chord_y:+.4f} m; fuselage centreline "
      f"y {centreline_at(quarter_chord_z):+.4f} m -> z_w {z_w:+.4f} m (positive down), z_w/h {z_w / h_max:+.3f}")
print(f"fin + rudder area S_v {S_v:.4f} m2, S_v/S {S_v / S:.4f}")
print(f"DATCOM fin efficiency η_v(1 + dσ/dβ) = 0.724 + {3.06 * (S_v / S) / 2.0:.4f} {0.4 * z_w / h_max:+.4f} "
      f"+ {0.009 * AR:.4f} = {efficiency:.3f}")
print(f"fuselage Cnβ: Raymer {raymer:+.5f} /rad; Munk (fineness {fineness:.2f}, k2 − k1 {k_lamb:.3f}) {munk:+.5f} /rad")
for name, body in (("Raymer", raymer), ("Munk", munk)):
    print(f"predicted Cnβ ({name} body) = {efficiency:.3f} × {fin_only:.5f} {body:+.5f} = {efficiency * fin_only + body:.4f} /rad")
print("for comparison (not an input): Ultra Stick 25e OpenFlightSim Cnβ 0.0723 /rad")
