#!/usr/bin/env python3
"""EX-05: physics data of the Great Planes Extra 300S .60 (GPMA0236), derived and reproducible.

Reads the measured visual geometry (assets/aircraft/extra-300s-60/geometry.json, EX-01 metrology), the kit
manual values below, and the Ugly Stik data file (same O.S. .61FX engine and propeller data). Writes
app/data/aircraft/gp_extra_300s_60.json (openrc-aircraft v1) and research/extra-300/ex05/derivation.md.

Methods are textbook estimates, not flight identification: Helmbold/DATCOM lift slopes, tail-volume static and
damping derivatives, strip theory for ailerons and roll damping, a skin-friction drag build-up, and a component
inventory. Every number written carries its unit, evidence kind and source. Nothing here validates the airplane:
it is the first traceable estimate (EX-09 owns the independent contrast).

    python3 research/extra-300/ex05/derive_physics.py           # writes the JSON and the report
    python3 research/extra-300/ex05/derive_physics.py --check   # fails if either file is stale
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GEOMETRY = ROOT / "assets/aircraft/extra-300s-60/geometry.json"
STIK = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
OUT = ROOT / "app/data/aircraft/gp_extra_300s_60.json"
REPORT = ROOT / "research/extra-300/ex05/derivation.md"
IN = 0.0254
LB = 0.45359237
OZ = LB / 16.0
RHO = 1.225
G0 = 9.80665
NU = 1.46e-5  # kinematic viscosity at sea level, m2/s
GEO_SRC = "assets/aircraft/extra-300s-60/geometry.json (EX-01 metrology)"
SCRIPT = "research/extra-300/ex05/derive_physics.py"
MANUAL = "Great Planes Extra 300S .60 manual EXT6P03"

g = json.load(open(GEOMETRY))
W, T, GEAR = g["wing"], g["tail"], g["gear"]
log = []  # (section, name, value, note) rows for the report


def note(section, name, value, how):
    log.append((section, name, value, how))
    return value


def q(value, unit, kind, source):
    if isinstance(value, float):
        value = round(value, 6)
    elif isinstance(value, list):
        value = [[round(x, 6) for x in v] if isinstance(v, list) else round(v, 6) for v in value]
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def shoelace(points):
    """Area and centroid of a closed polygon [(u, v), ...]."""
    a = cu = cv = 0.0
    for (u0, v0), (u1, v1) in zip(points, points[1:] + points[:1]):
        cross = u0 * v1 - u1 * v0
        a += cross
        cu += (u0 + u1) * cross
        cv += (v0 + v1) * cross
    a *= 0.5
    return abs(a), cu / (6 * a), cv / (6 * a)


def helmbold(aspect, kappa, half_chord_sweep=0.0):
    """DATCOM/Helmbold finite-wing lift slope, 1/rad (Raymer eq. 12.6 at M = 0)."""
    t = math.tan(half_chord_sweep)
    return 2 * math.pi * aspect / (2 + math.sqrt(aspect ** 2 / kappa ** 2 * (1 + t * t) + 4))


def flap_tau(cf):
    """Thin-airfoil flap effectiveness d(alpha)/d(delta) for a flap of chord fraction cf."""
    th = math.acos(2 * cf - 1)
    return 1 - (th - math.sin(th)) / math.pi


# --- Frames -------------------------------------------------------------------------------------------------
# Model axes (geometry.json): +X right, +Y up, -Z nose; y = 0 on the spinner axis; z = 0 at the nominal CG station.
# Physics le frame: [x_aft, y_right, z_up] from the wing leading edge at the centreline (the measured trapezoid's
# root LE), z = 0 on the thrust line (the spinner axis).
LE0 = W["le_z_root"]


def le(model_z, model_y=0.0, model_x=0.0):
    return [model_z - LE0, model_x, model_y]


# --- Reference geometry -------------------------------------------------------------------------------------
S = note("reference", "S (m2)", 744 * IN * IN, "manual title/spec: 744 sq in")
b = note("reference", "b (m)", 64 * IN, "manual: 64 in")
c_ref = note("reference", "c_ref = S/b (m)", S / b, "v1 coefficient reference length (not the MAC)")
cr, ct = W["root_chord"], W["tip_chord"]
lam = ct / cr
semi = W["span"] / 2.0
trap = b * (cr + ct) / 2
note("reference", "measured trapezoid b(cr+ct)/2 (m2)", trap, f"{100 * (trap / S - 1):+.2f} % vs manual area (EX-01)")
AR = note("reference", "AR = b2/S", b * b / S, "")
mac = 2 / 3 * cr * (1 + lam + lam * lam) / (1 + lam)
y_mac = semi / 3 * (1 + 2 * lam) / (1 + lam)
le_slope = (W["le_z_tip"] - W["le_z_root"]) / semi
mac_le_z = W["le_z_root"] + le_slope * y_mac
note("reference", "MAC (m)", mac, f"trapezoid; geometry.json says {W['reference']['mac']}")
note("reference", "MAC LE (model z)", mac_le_z, f"at y = {y_mac:.4f} m; geometry.json {W['reference']['mac_le_z']}")
qc = lambda y: W["le_z_root"] + le_slope * y + 0.25 * (cr + (ct - cr) * y / semi)
hc = lambda y: W["le_z_root"] + le_slope * y + 0.5 * (cr + (ct - cr) * y / semi)
sweep_qc = math.atan2(qc(semi) - qc(0), semi)
sweep_hc = math.atan2(hc(semi) - hc(0), semi)
note("reference", "quarter-chord sweep (deg)", math.degrees(sweep_qc), "aft positive; |sweep| < 1 deg: strips sit on one line")
note("reference", "half-chord sweep (deg)", math.degrees(sweep_hc), "")

# Plan CG: 4-1/8 in aft of the rib-2D LE (manual p43) = model z 0 (EX-01, 4.116 in read on the plan).
cg_z_model = 0.0
cg_mac = (cg_z_model - mac_le_z) / mac
note("balance", "CG (% MAC)", 100 * cg_mac, "manual p43 balance point; range +-3/8 in")

# Fuselage (geometry.json stations: [z, half width, top y, bottom y, ...]).
st = g["fuselage_stations"]
fus_w = 2 * max(r[1] for r in st)
fus_d = max(r[2] - r[3] for r in st)
fus_len = st[-1][0] - g["spinner"]["tip_z"]
fus_top = lambda z: next(r0[2] + (r1[2] - r0[2]) * (z - r0[0]) / (r1[0] - r0[0]) for r0, r1 in zip(st, st[1:]) if r0[0] <= z <= r1[0])
note("fuselage", "max width / depth / length (m)", [fus_w, fus_d, fus_len], "spinner tip to tail post")

# Horizontal tail: half planform polygon in (x, z), relief cut between the elevator halves included.
half_h = [(0.0, T["stab_root_le_z"]), (T["stab_half_span"], T["stab_tip_le_z"]),
          (T["stab_half_span"], T["elevator_tip_te_z"]), tuple(T["elevator_root_corner"]),
          tuple(T["elevator_inner_hinge"]), (0.0, T["elevator_inner_hinge"][1])]
a_half, _, _ = shoelace(half_h)
Sh = note("tail", "Sh (m2)", 2 * a_half, "stab + elevators planform polygon, through the fuselage")
bh = 2 * T["stab_half_span"]
crh = T["elevator_root_corner"][1] - T["stab_root_le_z"]
cth = T["elevator_tip_te_z"] - T["stab_tip_le_z"]
lh_ = cth / crh
y_mach = T["stab_half_span"] / 3 * (1 + 2 * lh_) / (1 + lh_)
mach = 2 / 3 * crh * (1 + lh_ + lh_ * lh_) / (1 + lh_)
xh_ac = T["stab_root_le_z"] + (T["stab_tip_le_z"] - T["stab_root_le_z"]) * y_mach / T["stab_half_span"] + 0.25 * mach
note("tail", "horizontal ac (model z)", xh_ac, "quarter chord of the stab MAC")
mid = 0.55 * T["stab_half_span"]
c_mid = (T["elevator_root_corner"][1] + (T["elevator_tip_te_z"] - T["elevator_root_corner"][1]) * (mid - T["elevator_root_corner"][0]) / (T["stab_half_span"] - T["elevator_root_corner"][0])) \
    - (T["stab_root_le_z"] + (T["stab_tip_le_z"] - T["stab_root_le_z"]) * mid / T["stab_half_span"])
stab_le_mid = T["stab_root_le_z"] + (T["stab_tip_le_z"] - T["stab_root_le_z"]) * mid / T["stab_half_span"]
cf_e = note("tail", "elevator chord fraction (mid span)", (stab_le_mid + c_mid - T["elevator_hinge_z"]) / c_mid, "hinge line to TE / local chord at 55 % semi-span")

# Vertical tail: fin + rudder side polygon (z, y) down to the tail post, closed along the fuselage top.
z_post = T["rudder_hinge_z"]
fin = [tuple(T["fin_root_le"]), (T["fin_le_top_z"], T["fin_top_y"]), (T["rudder_top_te_z"], T["fin_top_y"]),
       tuple(T["rudder_te_low"]), tuple(T["rudder_bottom_corner"]), tuple(T["rudder_bottom_hinge"]),
       (z_post, st[-1][2])]
Sv, fin_cz, fin_cy = shoelace(fin)
note("tail", "Sv (m2)", Sv, "fin + rudder side polygon above the fuselage top line, rudder to its bottom")
rud = [(z_post, T["fin_top_y"]), (T["rudder_top_te_z"], T["fin_top_y"]), tuple(T["rudder_te_low"]),
       tuple(T["rudder_bottom_corner"]), tuple(T["rudder_bottom_hinge"])]
Sr, _, _ = shoelace(rud)
cf_r = note("tail", "rudder area fraction", Sr / Sv, "used as its chord fraction")
h_v = T["fin_top_y"] - T["rudder_bottom_hinge"][1]
# Fin ac: quarter of the local chord at the area centroid height.
fin_le_at = lambda y: T["fin_root_le"][0] + (T["fin_le_top_z"] - T["fin_root_le"][0]) * (y - T["fin_root_le"][1]) / (T["fin_top_y"] - T["fin_root_le"][1])
xv_ac = fin_le_at(fin_cy) + 0.25 * (Sv / h_v)
note("tail", "fin ac (model z, y)", [xv_ac, fin_cy], "LE at the area-centroid height + 1/4 of the mean chord")

# --- Lift slopes, downwash, neutral point -------------------------------------------------------------------
kappa = note("aero", "section lift slope / 2pi", 0.9, "estimated: 13 % symmetric section at Re ~3e5 (no polar identified)")
CLa_w = note("aero", "CLa wing (1/rad)", helmbold(AR, kappa, sweep_hc), "Helmbold/DATCOM")
AR_h = bh * bh / Sh
CLa_h = note("aero", "CLa horizontal (1/rad)", helmbold(AR_h, kappa), f"Helmbold, AR {AR_h:.2f}")
eta_h = note("aero", "tail dynamic pressure ratio", 0.9, "estimated; propwash not modelled (ROADMAP E0b)")
deps = note("aero", "d(eps)/d(alpha)", 2 * CLa_w / (math.pi * AR), "elliptic-wing downwash estimate")
slope_h = note("aero", "effective tail slope (1/rad)", CLa_h * eta_h * (1 - deps), "CLa_h eta (1 - deps/dalpha): the tail sees body alpha in the local model")
CLa = note("aero", "CLa airplane (1/rad)", CLa_w + slope_h * Sh / S, "wing + tail (wing-body interference ~1 for d/b 0.1)")

# Fuselage pitch (Munk) destabilization, Raymer eq. 16.25: K_f w^2 L / (c S) per deg.
x_qc_root = (qc(0) - g["spinner"]["tip_z"]) / fus_len
K_f = note("aero", "K_fus (per deg)", 0.008, f"estimated, read from Raymer Fig. 16.14 at root quarter chord {100 * x_qc_root:.0f} % of body length (+-30 %)")
cma_f_mac = K_f * fus_w ** 2 * fus_len / (mac * S) * 180 / math.pi
dx_f = cma_f_mac / CLa_w * mac  # forward shift of the wing-body ac, m
x_ac_w = mac_le_z + 0.25 * mac
x_arp = note("aero", "wing-body ac = ARP (model z)", x_ac_w - dx_f, f"wing ac at 25 % MAC {x_ac_w:.4f}, fuselage moves it {dx_f * 1000:.1f} mm forward")
arp_y = W["chord_plane_y"]
l_h = xh_ac - x_arp
Cma = note("aero", "Cma about ARP (1/rad, c_ref)", -slope_h * Sh / S * l_h / c_ref, "tail only: the ARP is the wing-body ac")
Cma_cg = Cma + CLa * (cg_z_model - x_arp) / c_ref
x_np = x_arp - Cma / CLa * c_ref
sm = note("aero", "static margin at plan CG (% MAC)", 100 * (x_np - cg_z_model) / mac, f"neutral point at model z {x_np:.4f} ({100 * (x_np - mac_le_z) / mac:.1f} % MAC)")
note("aero", "Cma about the CG (1/rad, c_ref)", Cma_cg, "what the pilot feels")

# Incidence: wing 0 deg to the thrust line, stab -0.5 deg (geometry.json, side-view note).
i_h = math.radians(T["stab_incidence_deg"])
inc_eff = note("aero", "tail effective incidence (rad)", i_h / (1 - deps), "i_h / (1 - deps/dalpha): symmetric wing, eps0 = 0")
CL0 = note("aero", "CL0", slope_h * Sh / S * inc_eff, "symmetric wing at 0 deg + tail incidence")
Cm0 = note("aero", "Cm0 about ARP", -slope_h * Sh / S * l_h / c_ref * inc_eff, "tail incidence; symmetric section Cm_ac = 0")

# Controls (manual p43 high rates, measured at the widest part of each surface: delta = asin(d / chord)).
ail_c = W["aileron_chord"]
elev_c = T["elevator_root_corner"][1] - T["elevator_hinge_z"]
rud_c = T["rudder_te_low"][0] - T["rudder_hinge_z"]
throws = {
    "aileron": note("controls", "aileron (deg)", math.degrees(math.asin(0.625 * IN / ail_c)), f"5/8 in on a {ail_c / IN:.2f} in chord"),
    "elevator": note("controls", "elevator (deg)", math.degrees(math.asin(1.25 * IN / elev_c)), f"1-1/4 in on a {elev_c / IN:.2f} in chord"),
    "rudder": note("controls", "rudder (deg)", math.degrees(math.asin(2.5 * IN / rud_c)), f"2-1/2 in on a {rud_c / IN:.2f} in chord"),
}
k_flap = note("controls", "flap effectiveness correction", 0.8, "estimated: real/thin-airfoil effectiveness with gap, low Re and large throws (DATCOM range 0.6-0.9)")
tau_e = flap_tau(cf_e) * k_flap
ce_h = note("controls", "elevator effectiveness (local)", tau_e / (1 - deps), f"tau {tau_e:.3f} / (1 - deps/dalpha): deflection is not downwashed")
CLde = note("aero", "CLde (1/rad)", slope_h * ce_h * Sh / S, "")
Cmde = note("aero", "Cmde (1/rad)", -CLde * l_h / c_ref, "")

# Ailerons: strip theory over the aileron span with the wing's 3-D slope.
chord = lambda y: cr + (ct - cr) * y / semi
y1, y2 = W["aileron_inner"], min(W["aileron_outer"], semi)
n_int = 400
ys = [y1 + (y2 - y1) * (k + 0.5) / n_int for k in range(n_int)]
dy = (y2 - y1) / n_int
int_c = sum(chord(y) for y in ys) * dy
int_cy = sum(chord(y) * y for y in ys) * dy
cf_a = sum(ail_c / chord(y) * chord(y) for y in ys) * dy / int_c
tau_a = note("controls", "aileron tau", flap_tau(cf_a) * k_flap, f"chord fraction {cf_a:.3f} (area-weighted)")
CLda_each = CLa_w * tau_a * int_c / S
Clda = -CLa_w * tau_a * int_cy / (S * b)
note("aero", "Clda_right (1/rad)", Clda, "strip theory")


# --- Inventory (le frame) -----------------------------------------------------------------------------------
fw = g["firewall_z"]
items = [
    ("engine O.S. MAX-61FX", 0.55, "manual", "O.S. catalog 17750 (same engine as the Stik); manual p3 prototype engine", le(fw - 0.045), [0.1, 0.05, 0.1], "estimated", "crankcase ~1.8 in ahead of the firewall"),
    ("in-cowl muffler Slimline Pitts #3217", 0.13, "estimated", "manual p3 names it; ~4.5 oz typical for a .61 Pitts-style muffler (no catalog mass found)", le(fw - 0.03, -0.06), None, "estimated", "below the engine inside the cowl"),
    ("propeller APC 12x6 Sport", 0.046, "manual", "APC LP12060 1.62 oz (same propeller data as the Stik)", le(g["propeller"]["z"]), [0.01, 0.305, 0.025], "measured", "propeller plane from geometry.json"),
    ("2-1/2 in spinner and prop nut", 0.03, "estimated", "manual p3 GPMQ4520", le(g["spinner"]["back_z"] - 0.02), None, "measured", "spinner from geometry.json"),
    ("engine mount and bolts", 0.06, "estimated", "glass-filled beam mount", le(fw - 0.02, -0.005), None, "estimated", "on the firewall"),
    ("cowl", 0.09, "estimated", "ABS/fiberglass cowl of a .60 kit", le((g["spinner"]["back_z"] + g["cowl_rear_z"]) / 2, -0.01), [0.24, 0.15, 0.17], "measured", "between the spinner back and the cowl rear (geometry.json)"),
    ("fuel tank 12 oz (empty)", 0.06, "estimated", "manual p3 GPMQ4105", le(fw + 0.07), None, "estimated", "behind the firewall, on the thrust line"),
    ("fuel (half tank)", 0.146, "estimated", "12 oz tank = 355 ml, half at 0.82 g/ml glow fuel; flight state: half tank (no consumption model, G4)", le(fw + 0.07), None, "estimated", "same as the tank"),
    ("receiver battery 4.8 V", 0.11, "estimated", "1100 mAh NiMH pack", le(fw + 0.05, -0.07), None, "estimated", "under the tank (manual: location shown on the plans)"),
    ("receiver and switch", 0.04, "estimated", "typical 7-ch receiver + switch harness", le(0.0, -0.05), None, "estimated", "under the wing saddle"),
    ("fuselage servos (3: elevator, rudder, throttle)", 0.135, "estimated", "manual p3: five standard servos ~45 g", le(0.12, -0.03), None, "estimated", "servo tray behind the wing LE"),
    ("aileron servos (2)", 0.09, "estimated", "standard servos ~45 g", le(0.05, W["chord_plane_y"]), [0.02, 0.6, 0.02], "estimated", "one per wing half, mid-panel"),
    ("main gear, 2-3/4 in wheels and pants", 0.2, "estimated", "aluminium strap, two wheels and two pants", le(GEAR["main_axle"][0], -0.16), [0.08, GEAR["track"], 0.15], "measured", "axle station from geometry.json; height midway down the leg"),
    ("tail wheel assembly", 0.03, "estimated", "1 in tail wheel and wire", le(GEAR["tail_axle"][0], GEAR["tail_axle"][1]), None, "measured", "geometry.json tail axle"),
    ("wing incl. ailerons, covered", 0.66, "estimated", "built-up sheeted 64 in tapered wing, MonoKote", le(mac_le_z + 0.4 * mac, W["chord_plane_y"]), [mac, b, 0.045], "derived", "40 % MAC, on the chord plane"),
    ("fuselage front (firewall to cockpit), covered", 0.33, "estimated", "lite-ply formers/doublers, balsa sides", le(-0.05, -0.02), [0.4, fus_w, fus_d], "estimated", "from the stations in geometry.json"),
    ("fuselage rear and turtle deck, covered", 0.2, "estimated", "balsa sides and sheeted turtle deck", le(0.45, 0.01), [0.7, 0.09, 0.13], "estimated", "from the stations in geometry.json"),
    ("canopy and pilot", 0.08, "estimated", "butyrate canopy; DGA 1/4 scale sportsman pilot (manual p3)", le(0.27, 0.09), None, "measured", "pilot block in geometry.json"),
    ("stabilizer and elevators, covered", 0.12, "estimated", "sheeted built-up stab", le(0.75, T["stab_y"]), [0.17, bh, 0.01], "measured", "stab from geometry.json"),
    ("fin and rudder, covered", 0.07, "estimated", "sheeted built-up fin", le(fin_cz, fin_cy), [0.22, 0.01, 0.3], "derived", "area centroid of the fin polygon"),
    ("pushrods, horns, hardware", 0.1, "estimated", "clevises, horns, pushrods, screws: rough sum", le(0.3), None, "estimated", "spread along the fuselage"),
]
mass0 = sum(i[1] for i in items)
mom0 = [sum(i[1] * i[4][k] for i in items) for k in range(3)]
x_target = cg_z_model - LE0
x_cg0 = mom0[0] / mass0
nose = x_cg0 > x_target
xb = le(g["spinner"]["back_z"] - 0.01)[0] if nose else le(0.85)[0]
mb = mass0 * (x_target - x_cg0) / (xb - x_target)
ballast_pos = [xb, 0.0, 0.0 if nose else 0.02]
note("balance", "inventory without balancing mass (kg, CG x_aft m)", [mass0, x_cg0], f"target CG x_aft {x_target:.4f}")
note("balance", "balancing mass (kg)", mb, ("spinner/nose weight" if nose else "tail weight") + " that puts the CG on the manual's balance point")
items.append(("virtual reference-build balancing mass", mb, "derived",
              f"{SCRIPT}: m = M (x_CG - x0) / (x_ballast - x_CG) for the manual p43 balance point; a virtual reference build, NOT measured hardware or a ballast recommendation (manual: balance with the receiver battery first)",
              ballast_pos, [0.025, 0.025, 0.025], "estimated", "spinner weight position (manual p43)" if nose else "stick-on tail weight position (manual p43)"))
mass = mass0 + mb
cg = [sum(i[1] * i[4][k] for i in items) / mass for k in range(3)]
note("balance", "flight mass (kg)", mass, f"dry {mass - 0.146:.3f} kg = {(mass - 0.146) / LB:.2f} lb vs manual 7-7.5 lb; RCM build 124 oz = {124 * OZ:.3f} kg RTF")
note("balance", "flight CG (le frame)", cg, "z: below the thrust line by the inventory")

# Inertia (same box + parallel-axis model as the loader) for the report.
def inertia(pt):
    j = [0.0] * 3
    for it in items:
        m, p, s = it[1], it[4], it[5] or [0, 0, 0]
        x, y, z = -(p[0] - pt[0]), p[1] - pt[1], -(p[2] - pt[2])
        j[0] += m * (y * y + z * z) + m * (s[1] ** 2 + s[2] ** 2) / 12
        j[1] += m * (x * x + z * z) + m * (s[0] ** 2 + s[2] ** 2) / 12
        j[2] += m * (x * x + y * y) + m * (s[0] ** 2 + s[1] ** 2) / 12
    return j
note("balance", "Jxx Jyy Jzz (kg m2)", inertia(cg), "component boxes + parallel axis")

CL_max = note("aero", "CL_max", 1.05, "estimated: 13 % symmetric section clmax ~1.15 at Re 3e5, x0.9 wing (no polar identified)")
Vs = note("aero", "1-g stall (m/s)", math.sqrt(2 * mass * G0 / (RHO * S * CL_max)), "flight mass, CL_max")
V_start = note("aero", "start speed (m/s)", round(1.6 * Vs), "1.6 x the 1-g stall, rounded: the trimmed in-air start")
CL_ref = note("aero", "CL_ref", mass * G0 / (0.5 * RHO * V_start ** 2 * S), "level flight at the start speed; CL-dependent cross terms are frozen there")

# --- Lateral-directional --------------------------------------------------------------------------------------
cg_model_z, cg_model_y = cg[0] + LE0, cg[2]
l_v = xv_ac - cg_model_z
z_v = fin_cy - cg_model_y
AR_v = note("lateral", "fin effective AR", 1.55 * h_v * h_v / Sv, "geometric h2/Sv x 1.55 end-plate factor (fuselage + stab, DATCOM range 1.4-1.7)")
z_w = (W["chord_plane_y"] - (st[6][2] + st[6][3]) / 2)
sidewash = note("lateral", "(1 + dsigma/dbeta) eta_v", 0.724 + 3.06 * (Sv / S) / 2 + 0.4 * (-z_w) / fus_d + 0.009 * AR,
                "Nelson/DATCOM: 0.724 + 3.06 (Sv/S)/(1 + cos sweep) + 0.4 z_w/d + 0.009 AR (low wing: z_w down positive)")
slope_v = note("lateral", "effective fin slope (1/rad)", helmbold(AR_v, kappa) * sidewash, "")
tau_r = flap_tau(cf_r) * k_flap
ce_v = note("lateral", "rudder effectiveness (local)", tau_r / sidewash, f"tau {tau_r:.3f} / sidewash factor")
CYb_v = -slope_v * Sv / S
fus_x0_area = 0.8 * fus_w * fus_d  # rounded box cross-section near x0 (~0.45 L)
CYb_B = note("lateral", "CYb body (1/rad)", -2 * 1.3 * fus_x0_area / S, "-2 K_i S0/S, K_i 1.3 low wing (DATCOM), S0 0.8 w d")
arm_v_arp = xv_ac - x_arp
CYdr = slope_v * Sv / S * ce_v
Cnb = slope_v * Sv / S * arm_v_arp / b
Cndr = -CYdr * arm_v_arp / b
fin_z_le = fin_cy  # up from the thrust line
Cldr = CYdr * (fin_z_le - arp_y) / b
Cnb_B = note("lateral", "Cnb body, omitted (1/rad)", -0.001 * 1.4 * 57.3 * (0.6 * fus_len * fus_d / S) * (fus_len / b),
             "DATCOM -K_N K_Rl (S_side/S)(L/b), K_N ~0.001/deg, K_Rl 1.4: destabilizing; not in v1 (Cnb must equal the fin term), same as the Stik")
dihedral_low = note("lateral", "Clb low-wing interference (1/rad)", 1.2 * math.sqrt(AR) * (-z_w / b) * (2 * fus_d / b),
                    "DATCOM: 1.2 sqrt(AR) (z_w/b)(2d/b), destabilizing for a low wing")
Clb_wing = note("lateral", "Clb wing at CL_ref (1/rad)", -0.034 * CL_ref, "DATCOM Clb/CL ~ -0.0006/deg for an unswept AR 5.5 taper 0.5 wing (estimated)")
Clb = Clb_wing + dihedral_low + CYb_v * z_v / b
Clp = -(CLa_w / 12) * (1 + 3 * lam) / (1 + lam) - eta_h * (CLa_h / 12) * (Sh / S) * (bh / b) ** 2 * (1 + 3 * lh_) / (1 + lh_) + 2 * CYb_v * (z_v / b) ** 2
Clr = CL_ref / 4 - 2 * l_v * z_v / b ** 2 * CYb_v
Cnp = -CL_ref / 8 - 2 * l_v * z_v / b ** 2 * CYb_v
Cnr = -0.25 * 0.035 + 2 * (l_v / b) ** 2 * CYb_v - 0.02
CYp = 2 * CYb_v * z_v / b
CYr = -2 * CYb_v * l_v / b
K_adv = 0.15
Cnda = -2 * K_adv * CL_ref * Clda  # right aileron TE down: drag on the right wing, nose right (adverse yaw)
tail_q = CLa_h * eta_h * Sh / S  # pitch rate and alpha-dot change the tail angle directly: no downwash factor
CLq = 2 * tail_q * l_h / c_ref + (0.5 + 2 * (cg_model_z - x_ac_w) / mac) * CLa_w * mac / c_ref
Cmq = -2 * tail_q * (xh_ac - cg_model_z) ** 2 / c_ref ** 2 * 1.1
CLadot = 2 * tail_q * l_h / c_ref * deps
th_a = math.acos(2 * cf_a - 1)
cp_frac = note("aero", "aileron lift-increment centre (chord fraction)", 0.25 + 0.5 * math.sin(th_a) * (1 - math.cos(th_a)) / (2 * (math.pi - th_a + math.sin(th_a))),
               "thin airfoil: 1/4 + dCm_c/4 / dCl for the flap")
x_cp_ail = sum((W["le_z_root"] + le_slope * y + cp_frac * chord(y)) * chord(y) for y in ys) / sum(chord(y) for y in ys)
Cmda = -CLda_each * (x_cp_ail - x_arp) / c_ref

# --- Drag build-up ---------------------------------------------------------------------------------------------
V = V_start
cf_mix = lambda L, lam_frac: lam_frac * 1.328 / math.sqrt(V * L / NU) + (1 - lam_frac) * 0.455 / math.log10(V * L / NU) ** 2.58
exposed_wing = S - fus_w * cr
tc = 0.131
parts = {
    "wing": cf_mix(mac, 0.4) * (1 + 0.6 / 0.3 * tc + 100 * tc ** 4) * 2.04 * exposed_wing,
    "tails": cf_mix(0.16, 0.4) * 1.12 * 2.03 * (Sh - 0.03 * 0.18 + Sv),
    "fuselage": cf_mix(fus_len, 0.1) * (1 + 60 / (fus_len / fus_d) ** 3 + (fus_len / fus_d) / 400) * (0.85 * 2 * (fus_w + fus_d) * fus_len),
    "main gear, pants, tail wheel": 0.0025,
    "exposed cylinder head, cooling flow": 0.0015,
}
D_q = sum(parts.values()) * 1.1  # +10 % excrescences (hinge gaps, horns, canopy edge, pilot)
CD0 = note("drag", "CD0", D_q / S, "skin friction (40 % laminar on surfaces) x form factors (Raymer ch. 12) + gear + engine, x1.1 excrescences: " + ", ".join(f"{k} {v:.4f} m2" for k, v in parts.items()))
e_osw = note("drag", "Oswald e", 0.78, "estimated: Stik/UltraStick identified value (0.78) at similar AR and Re; Raymer's 0.885 is optimistic at Re 3e5")
k_ind = 1 / (math.pi * e_osw * AR)

# Local-model aileron effectiveness: equal-area strips (as the loader builds them) must give Clda_right.
def station_centres(span, root, tip, n=3):
    h = span / 2
    slope = (tip - root) / h
    area = lambda y: root * y + slope * y * y / 2
    mom = lambda y: root * y * y / 2 + slope * y ** 3 / 3
    out, y0 = [], 0.0
    for k in range(n):
        y1 = h if k == n - 1 else (-root + math.sqrt(root * root + 2 * slope * area(h) * (k + 1) / n)) / slope
        out.append((mom(y1) - mom(y0)) / (area(y1) - area(y0)))
        y0 = y1
    return out
sum_y = sum(station_centres(b, cr, ct))
wing_ail_eff = abs(Clda) * 6 * b / (CLa * sum_y)

# --- Assemble ----------------------------------------------------------------------------------------------------
stik = json.load(open(STIK))
D = lambda how: f"{SCRIPT}: {how}"
coeff = lambda v, unit, kind, how: q(float(v), unit, kind, D(how) if kind == "derived" else how)
coefficients = {
    "CL0": coeff(CL0, "1", "derived", "symmetric wing at 0 deg; stab -0.5 deg"),
    "CLa": coeff(CLa, "1/rad", "derived", "Helmbold wing + downwashed tail"),
    "CLadot": coeff(CLadot, "1/rad", "derived", "2 eta CLa_h Sh/S l_h/c deps/dalpha"),
    "CLq": coeff(CLq, "1/rad", "derived", "tail volume + DATCOM wing term"),
    "CLde": coeff(CLde, "1/rad", "derived", "tail slope x elevator effectiveness"),
    "CLda_each": coeff(CLda_each, "1/rad", "derived", "strip theory over the aileron span"),
    "CD0": coeff(CD0, "1", "derived", "component drag build-up at 16 m/s, see derivation.md"),
    "CL_minD": coeff(0.0, "1", "estimated", "symmetric section at 0 deg incidence"),
    "k_induced": coeff(k_ind, "1", "derived", "1/(pi e AR), e 0.78 estimated"),
    "CDda_each": q(stik["aero"]["coefficients"]["CDda_each"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file); second-order control drag"),
    "CDdr": q(stik["aero"]["coefficients"]["CDdr"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file); second-order control drag"),
    "CDde": q(stik["aero"]["coefficients"]["CDde"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file); second-order control drag"),
    "CYb": coeff(CYb_v + CYb_B, "1/rad", "derived", "fin + DATCOM body"),
    "CYp": coeff(CYp, "1/rad", "derived", "fin above the CG"),
    "CYr": coeff(CYr, "1/rad", "derived", "fin behind the CG"),
    "CYdr": coeff(CYdr, "1/rad", "derived", "fin slope x Sv/S x rudder effectiveness (must equal the vertical surface)"),
    "Clb": coeff(Clb, "1/rad", "derived", "wing at CL_ref + low-wing interference + fin"),
    "Clp": coeff(Clp, "1/rad", "derived", "strip theory with taper + stab + fin"),
    "Clr": coeff(Clr, "1/rad", "derived", "CL_ref/4 + fin"),
    "Clda_right": coeff(Clda, "1/rad", "derived", "strip theory"),
    "Clda_left": coeff(-Clda, "1/rad", "derived", "strip theory"),
    "Cldr": coeff(Cldr, "1/rad", "derived", "rudder side force x fin height above the ARP"),
    "Cm0": coeff(Cm0, "1", "derived", "tail incidence about the ARP (wing-body ac)"),
    "Cma": coeff(Cma, "1/rad", "derived", "tail about the wing-body ac; the CG transfer gives the static margin"),
    "Cmq": coeff(Cmq, "1/rad", "derived", "tail damping about the CG (undownwashed tail slope) x1.1 for wing/fuselage"),
    "Cmde": coeff(Cmde, "1/rad", "derived", "elevator lift x tail arm from the ARP"),
    "Cmda_each": coeff(Cmda, "1/rad", "derived", "aileron lift increment at its thin-airfoil centre, arm from the ARP"),
    "Cnb": coeff(Cnb, "1/rad", "derived", "fin only (v1 contract: equals the vertical surface)"),
    "Cnp": coeff(Cnp, "1/rad", "derived", "-CL_ref/8 + fin"),
    "Cnr": coeff(Cnr, "1/rad", "derived", "fin + wing profile drag + fuselage (-0.02 estimated)"),
    "Cnda_right": coeff(Cnda, "1/rad", "derived", "adverse yaw 2 K CL_ref Clda, K 0.15 (Nelson, AR 5.5, taper 0.5)"),
    "Cnda_left": coeff(-Cnda, "1/rad", "derived", "adverse yaw"),
    "Cndr": coeff(Cndr, "1/rad", "derived", "rudder side force x fin arm from the ARP (must equal the vertical surface)"),
}
surf = stik["aero"]["surfaces"]
same = lambda key: dict(surf[key], source="same provisional value as the Ugly Stik surface model (" + surf[key]["source"].split(";")[-1].strip() + ")", kind=surf[key]["kind"] if surf[key]["kind"] != "derived" else "estimated")
data = {
    "format": "openrc-aircraft v1",
    "id": "gp-extra-300s-60",
    "description": "Great Planes Extra 300S .60 (GPMA0236), 64 in span, O.S. .61FX glow. EXPERIMENTAL first physics estimate (EX-05), generated by " + SCRIPT + "; not flight-identified. Visual geometry lives in assets/aircraft/extra-300s-60/geometry.json.",
    "frames": {
        "le_frame": "positions in metres from the wing leading edge at the centreline (the measured trapezoid's root LE, model z " + f"{LE0}" + "): [x_aft, y_right, z_up]; z = 0 on the thrust line (spinner axis)",
        "body": "simulation body axes FRD about the CG: x forward = -x_aft, y right, z down = -z_up",
    },
    "reference": {
        "wing_area": q(S, "m2", "manual", "744 sq in, " + MANUAL + " specification (EX-01 measured trapezoid +0.26 %)"),
        "wing_span": q(b, "m", "manual", "64 in, " + MANUAL + " (EX-01 measured -0.13 %)"),
        "mean_chord": q(c_ref, "m", "derived", "S / b: the v1 coefficient reference length. NOT the MAC (" + f"{mac:.4f}" + " m at " + f"{y_mac:.4f}" + " m span, " + GEO_SRC + ")"),
        "root_chord": q(cr, "m", "measured", "root chord extrapolated to the centreline, " + GEO_SRC),
        "tip_chord": q(ct, "m", "measured", "tip chord, " + GEO_SRC),
        "aero_reference_point": q(le(x_arp, arp_y), "m", "derived", D("wing-body aerodynamic centre: 25 % MAC moved forward by the fuselage (Raymer K_fus); on the wing chord plane")),
        "planform": "tapered",
    },
    "start": {"level_speed": q(float(V_start), "m/s", "derived", D("1.6 x the 1-g stall at the flight mass and CL_max, rounded"))},
    "balance": {
        "plan_cg": q(cg, "m", "manual", "4-1/8 in aft of the LE at rib 2D (" + MANUAL + " p43) = model z 0 (EX-01 read 4.116 in on the plan); z from the inventory (derived)"),
        "firewall": q(le(fw), "m", "measured", "firewall station, " + GEO_SRC),
        "configuration": "virtual-balanced-reference-v1",
        "cg_tolerance": q(0.001, "m", "estimated", D("virtual reference build balanced to the manual's point, NOT a measured airplane")),
    },
    "inventory": [
        dict({"name": it[0], "mass": q(float(it[1]), "kg", it[2], it[3]), "position": q([float(v) for v in it[4]], "m", it[6], it[7])},
             **({"size": q([float(v) for v in it[5]], "m", "estimated", "rough envelope for intrinsic inertia")} if it[5] else {}))
        for it in items
    ],
    "crash_hull": q([
        le(W["le_z_tip"], W["chord_plane_y"], -semi), le(W["le_z_tip"], W["chord_plane_y"], semi),
        le(W["le_z_tip"] + ct, W["chord_plane_y"], -semi), le(W["le_z_tip"] + ct, W["chord_plane_y"], semi),
        le(g["spinner"]["tip_z"]),
        le(GEAR["main_axle"][0], GEAR["main_axle"][1] - GEAR["main_wheel_diameter"] / 2, -GEAR["track"] / 2),
        le(GEAR["main_axle"][0], GEAR["main_axle"][1] - GEAR["main_wheel_diameter"] / 2, GEAR["track"] / 2),
        le(GEAR["tail_axle"][0], GEAR["tail_axle"][1] - GEAR["tail_wheel_diameter"] / 2),
        le(T["rudder_te_low"][0], T["rudder_te_low"][1]),
        le(T["elevator_tip_te_z"], T["stab_y"], -T["stab_half_span"]), le(T["elevator_tip_te_z"], T["stab_y"], T["stab_half_span"]),
        le(T["rudder_top_te_z"], T["fin_top_y"]),
        le(max(g["canopy"]["top"], key=lambda p: p[1])[0], max(p[1] for p in g["canopy"]["top"])),
    ], "m", "measured", "Points that hit the ground first (le frame) from " + GEO_SRC + ": wing tip LE/TE, spinner tip, main wheel bottoms (track estimated there), tail wheel bottom, rudder bottom TE, stab tips, fin top, canopy top. Replaced by gear contact in E1/E2"),
    "plausibility": {
        "mass_range": q([3.0, 3.8], "kg", "manual", MANUAL + ": 7-7.5 lb (3.18-3.40 kg) dry; RCM review build 124 oz (3.52 kg) RTF; widened for fuel"),
        "inertia_reference": stik["plausibility"]["inertia_reference"],
    },
    "controls": {
        "max_throw": {
            k: q(v, "deg", "derived", f"{MANUAL} p43 HIGH rate at the widest part, delta = asin(d / chord): mechanical maximum with transmitter ATV near 100 % (manual); the radio's dual rate reduces it")
            for k, v in throws.items()
        },
        "servo_full_throw_time": stik["controls"]["servo_full_throw_time"],
    },
    "aero": {
        "source": "Derived from the measured geometry by " + SCRIPT + " (Helmbold/DATCOM, tail volume, strip theory, drag build-up); report research/extra-300/ex05/derivation.md. Not flight-identified: EXPERIMENTAL until EX-08/EX-09.",
        "envelope": {
            "CL_max": q(CL_max, "1", "estimated", "13 % symmetric section clmax ~1.15 at Re 3e5 x 0.9 for the wing; no polar identified (EX-09)"),
            "CL_min": q(-0.98, "1", "estimated", "symmetric section: about the positive value, slightly less with the -0.5 deg tail"),
            "stall_blend_width": q(6.0, "deg", "estimated", "same blend as the Ugly Stik data (PicaSim/YASim class)"),
            "CD90": q(1.11 + 0.018 * AR, "1", "derived", "Viterna CDmax = 1.11 + 0.018 AR (NASA CR-1983)"),
            "sideslip_blend": stik["aero"]["envelope"]["sideslip_blend"],
        },
        "conventions": stik["aero"]["conventions"],
        "coefficients": coefficients,
        "surfaces": {
            "wing_aileron_effectiveness": q(wing_ail_eff, "1", "derived", D("|Clda_right| 2n b / (CLa sum(y)) over the loader's equal-area tapered strips")),
            "attached_limit": same("attached_limit"),
            "tail_local_limit": same("tail_local_limit"),
            "tail_stall_end": same("tail_stall_end"),
            "tail_CD0": same("tail_CD0"),
            "tail_k": same("tail_k"),
            "tail_CD90": same("tail_CD90"),
            "horizontal": {
                "area": q(Sh, "m2", "derived", D("stab + elevator planform polygon from " + GEO_SRC)),
                "position": q(le(xh_ac, T["stab_y"]), "m", "derived", D("quarter chord of the stab MAC")),
                "lift_slope": q(slope_h, "1/rad", "derived", D("Helmbold x eta 0.9 x (1 - deps/dalpha)")),
                "control_effectiveness": q(ce_h, "1", "derived", D("thin-airfoil tau x 0.8 / (1 - deps/dalpha)")),
                "incidence": q(inc_eff, "rad", "derived", D("stab -0.5 deg / (1 - deps/dalpha)")),
            },
            "vertical": {
                "area": q(Sv, "m2", "derived", D("fin + rudder side polygon from " + GEO_SRC)),
                "position": q(le(xv_ac, fin_cy), "m", "derived", D("fin ac: quarter chord at the area-centroid height")),
                "lift_slope": q(slope_v, "1/rad", "derived", D("Helmbold (end-plated AR) x DATCOM sidewash/eta")),
                "control_effectiveness": q(ce_v, "1", "derived", D("thin-airfoil tau x 0.8 / sidewash factor")),
                "incidence": q(0.0, "rad", "estimated", "symmetric fin; the plan's 2 deg right thrust is not modelled (EX-06)"),
            },
        },
    },
    "propulsion": json.loads(json.dumps(stik["propulsion"])),
}
p = data["propulsion"]
p["description"] = "Same O.S. MAX-61FX and APC 12x6 data as the Ugly Stik (manual p3 prototype engine). AXIAL thrust: the plan's 2 deg right and 0.5 deg down thrust are not modelled yet (EX-06); the visual model shows a 12x8 stand-in."
p["propeller"]["thrust_line_offset"] = q([0.0, 0.0, -cg[2]], "m", "derived", D("spinner axis relative to the inventory CG; [x_aft, y_right, z_up] from the CG"))
p["propeller"]["rotating_inertia"] = dict(p["propeller"]["rotating_inertia"], source=p["propeller"]["rotating_inertia"]["source"] + " (2-1/2 in spinner here, within the estimate)")

# The loader's exact consistency rules (aircraft_data.gd _surfaces) must hold: recompute them from the rounded file.
def check_consistency(d):
    a = {k: v["value"] for k, v in d["aero"]["coefficients"].items()}
    fin_ = d["aero"]["surfaces"]["vertical"]
    arp = d["reference"]["aero_reference_point"]["value"]
    S_, b_ = d["reference"]["wing_area"]["value"], d["reference"]["wing_span"]["value"]
    cy = fin_["lift_slope"]["value"] * fin_["area"]["value"] / S_ * fin_["control_effectiveness"]["value"]
    arm = fin_["position"]["value"][0] - arp[0]
    exp = {"CYdr": cy, "Cndr": -cy * arm / b_, "Cldr": cy * (fin_["position"]["value"][2] - arp[2]) / b_,
           "Cnb": fin_["lift_slope"]["value"] * fin_["area"]["value"] / S_ * arm / b_}
    for k, v in exp.items():
        d["aero"]["coefficients"][k]["value"] = v  # exact, unrounded: the loader compares to 1e-8
check_consistency(data)

text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
rows = ["| Section | Quantity | Value | How |", "| --- | --- | --- | --- |"]
for sec, name, val, how in log:
    v = ", ".join(f"{x:.4g}" for x in val) if isinstance(val, list) else f"{val:.4g}"
    rows.append(f"| {sec} | {name} | {v} | {how} |")
coef_rows = ["| Coefficient | Value | Kind |", "| --- | --- | --- |"] + [f"| {k} | {v['value']:.5g} | {v['kind']} |" for k, v in data["aero"]["coefficients"].items()]
report = f"""# EX-05: Extra 300S .60 physics derivation

Generated by `{SCRIPT}` from `{GEOMETRY.relative_to(ROOT)}` and the manual; do not edit (regenerate). Output:
`{OUT.relative_to(ROOT)}`. **Experimental**: textbook estimates from measured geometry, not flight identification.
EX-08 flies the envelope, EX-09 looks for an independent contrast.

Flight mass {mass:.3f} kg, CG {100 * cg_mac:.1f} % MAC, static margin {sm:.1f} % MAC, 1-g stall {Vs:.1f} m/s, start {V_start} m/s.
Throws (manual p43 high rate): aileron {throws['aileron']:.1f}°, elevator {throws['elevator']:.1f}°, rudder {throws['rudder']:.1f}°.

## Intermediate quantities

{chr(10).join(rows)}

## Coefficients written (c_ref = S/b; moments about the ARP = wing-body ac)

{chr(10).join(coef_rows)}

## Known simplifications

- Axial thrust: 2° right and 0.5° down thrust of the plan are not modelled (EX-06). Same propeller data as the Stik (APC 12x6, UIUC 11x6 measurement).
- Fuselage directional destabilization is omitted (v1 contract: Cnb equals the fin term), as for the Stik.
- The local (post-stall) wing strips use the whole-airplane CLa, so local lift is ~{100 * slope_h * Sh / S / CLa:.0f} % high (tail counted twice); pitch stiffness agrees with the global model because the ARP is the wing-body ac.
- CL-dependent cross terms (Clb wing part, Clr, Cnp, adverse yaw) are frozen at CL_ref = {CL_ref:.2f}.
- No propwash, no fuel burn, no ground contact (crash hull only).
"""

if "--check" in sys.argv:
    stale = [p for p, t in ((OUT, text), (REPORT, report)) if not p.exists() or p.read_text() != t]
    if stale:
        sys.exit("stale: " + ", ".join(str(p.relative_to(ROOT)) for p in stale) + f" (run {SCRIPT})")
    print("gp_extra_300s_60.json and derivation.md are up to date")
else:
    OUT.write_text(text)
    REPORT.write_text(report)
    print(f"wrote {OUT.relative_to(ROOT)} and {REPORT.relative_to(ROOT)}")
    print(f"mass {mass:.3f} kg, CG {100 * cg_mac:.1f} % MAC, SM {sm:.1f} % MAC, stall {Vs:.1f} m/s, start {V_start} m/s")
