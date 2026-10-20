#!/usr/bin/env python3
"""EX-05: physics data of the Great Planes Extra 300S .60 (GPMA0236), derived and reproducible.

Reads the measured visual geometry (assets/aircraft/extra-300s-60/geometry.json, EX-01 metrology), the kit
manual values below, and the Ugly Stik data file (same O.S. .61FX engine and propeller data). Writes
app/data/aircraft/gp_extra_300s_60.json (openrc-aircraft v2) and research/extra-300/ex05/derivation.md.

Methods are textbook estimates, not flight identification: Helmbold/DATCOM lift slopes, tail-volume static and
damping derivatives, strip theory for ailerons and roll damping, a skin-friction drag build-up, and a component
inventory. Every number written carries its unit, evidence kind and source. Nothing here validates the airplane:
it is the first traceable estimate (EX-09 owns the independent contrast).

    python3 research/extra-300/ex05/derive_physics.py           # writes the JSON and the report
    python3 research/extra-300/ex05/derive_physics.py --check   # fails if either file is stale
"""
import json
import math
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATOR_DIR = ROOT / "research/aircraft-standardization"
if str(MIGRATOR_DIR) not in sys.path:
    sys.path.insert(0, str(MIGRATOR_DIR))
from migrate import legacy_input, numeric_parity, upgrade  # noqa: E402
from physical_identity import validate_physical_identity  # noqa: E402
FUEL_DIR = ROOT / "research" / "fuel-systems"
if str(FUEL_DIR) not in sys.path:
    sys.path.insert(0, str(FUEL_DIR))
import fuel_registry  # noqa: E402

# FUEL-08: the manual's 12 oz tank and registry glow blend; finite-glow sessions default to the full tank (D4).
TANK_L = 0.355
TANK_SOURCE = "manual p3 GPMQ4105 12 oz tank (12 US fl oz = 0.355 l)"
GLOW_BLEND = "glow_10n_18castor"
START_FILL = 1.0

GEOMETRY = ROOT / "assets/aircraft/extra-300s-60/geometry.json"
STIK = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
OUT_DIR = Path(os.environ.get("OPENRC_AIRCRAFT_OUTPUT_DIR", ROOT / "app/data/aircraft")).resolve()
REPORT_DIR = Path(os.environ.get("OPENRC_AIRCRAFT_REPORT_DIR", ROOT / "research/extra-300/ex05")).resolve()
OUT = OUT_DIR / "gp_extra_300s_60.json"
REPORT = REPORT_DIR / "derivation.md"
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


def inventory_mass(item):
    """Keep the full tank mass exactly equal to capacity × registry density."""
    mass = q(float(item[1]), "kg", item[2], item[3])
    if item[8] == "fuel_flight":
        # q() rounds ordinary authored leaves to 6 decimals. Here that would
        # round 0.3042066 kg above the actual 0.355 l capacity by 0.4 mg.
        mass["value"] = float(item[1])
    return mass


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

# Manual p43 setup datum: 4-1/8 in aft of the rib-2D LE, at model z 0 (EX-01 reads 4.116 in).
# This is the EMPTY-TANK balance target; finite fuel is added after the dry build-mass closure (EX-14a).
cg_target_model_z = 0.0
cg_target_mac = (cg_target_model_z - mac_le_z) / mac
note("balance", "manual empty-tank target (% MAC)", 100 * cg_target_mac, "manual p43 first-flight balance point; range +-3/8 in")

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
eta_h = note("aero", "tail dynamic pressure ratio", 0.9, "estimated free-stream ratio for the coefficients; the runtime adds the propeller tail-slipstream increment separately (EX-14c)")
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
x_np = x_arp - Cma / CLa * c_ref

# Incidence: wing 0 deg to the nominal datum axis, stab -0.5 deg (geometry.json, side-view note).
i_h = math.radians(T["stab_incidence_deg"])
inc_eff = note("aero", "tail effective incidence (rad)", i_h / (1 - deps), "i_h / (1 - deps/dalpha): symmetric wing, eps0 = 0")
CL0 = note("aero", "CL0", slope_h * Sh / S * inc_eff, "symmetric wing at 0 deg + tail incidence")
Cm0 = note("aero", "Cm0 about ARP", -slope_h * Sh / S * l_h / c_ref * inc_eff, "tail incidence; symmetric section Cm_ac = 0")

# Controls (manual p43 high rates, measured at the widest part of each surface: delta = asin(d / chord)).
ail_c = W["aileron_chord"]
elev_c = T["elevator_root_corner"][1] - T["elevator_hinge_z"]
rud_c = T["rudder_te_low"][0] - T["rudder_hinge_z"]
LOW_RATE_TRAVEL = {"aileron": 0.4, "elevator": 0.6, "rudder": 0.6}  # manual p43 LOW rate / HIGH rate travel (D6e)
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
# CR-22b: which inventory items carry energy (crash fire/smoke presentation only).
ENERGY_SOURCES = {"fuel (full tank)": "glow_fuel"}
items = [
    ("engine O.S. MAX-61FX", 0.55, "manual", "O.S. catalog 17750 (same engine as the Stik); manual p3 prototype engine", le(fw - 0.045), [0.1, 0.05, 0.1], "estimated", "crankcase ~1.8 in ahead of the firewall", "engine_main"),
    ("in-cowl muffler Slimline Pitts #3217", 0.13, "estimated", "manual p3 names it; ~4.5 oz typical for a .61 Pitts-style muffler (no catalog mass found)", le(fw - 0.03, -0.06), None, "estimated", "below the engine inside the cowl", "muffler_main"),
    ("propeller APC 12x6 Sport", 0.046, "manual", "APC LP12060 1.62 oz (same propeller data as the Stik)", le(g["propeller"]["z"]), [0.01, 0.305, 0.025], "measured", "propeller plane from geometry.json", "propeller_main"),
    ("2-1/2 in spinner and prop nut", 0.03, "estimated", "manual p3 GPMQ4520", le(g["spinner"]["back_z"] - 0.02), None, "measured", "spinner from geometry.json", "spinner_main"),
    ("engine mount and bolts", 0.06, "estimated", "glass-filled beam mount", le(fw - 0.02, -0.005), None, "estimated", "on the firewall", "engine_mount"),
    ("cowl", 0.09, "estimated", "ABS/fiberglass cowl of a .60 kit", le((g["spinner"]["back_z"] + g["cowl_rear_z"]) / 2, -0.01), [0.24, 0.15, 0.17], "measured", "between the spinner back and the cowl rear (geometry.json)", "cowl_main"),
    ("fuel tank 12 oz (empty)", 0.06, "estimated", "manual p3 GPMQ4105", le(fw + 0.07), None, "estimated", "behind the firewall, on the thrust line", "fuel_tank"),
    ("receiver battery 4.8 V", 0.11, "estimated", "1100 mAh NiMH pack", le(fw + 0.05, -0.07), None, "estimated", "under the tank (manual: location shown on the plans)", "receiver_battery"),
    ("receiver and switch", 0.04, "estimated", "typical 7-ch receiver + switch harness", le(0.0, -0.05), None, "estimated", "under the wing saddle", "receiver_radio"),
    ("fuselage servos (3: elevator, rudder, throttle)", 0.135, "estimated", "manual p3: five standard servos ~45 g", le(0.12, -0.03), None, "estimated", "servo tray behind the wing LE", "fuselage_servos"),
    ("aileron servos (2)", 0.09, "estimated", "standard servos ~45 g", le(0.05, W["chord_plane_y"]), [0.02, 0.6, 0.02], "estimated", "one per wing half, mid-panel", "aileron_servos"),
    ("main gear, 2-3/4 in wheels and pants", 0.2, "estimated", "aluminium strap, two wheels and two pants", le(GEAR["main_axle"][0], -0.16), [0.08, GEAR["track"], 0.15], "measured", "axle station from geometry.json; height midway down the leg", "landing_gear_main"),
    ("tail wheel assembly", 0.03, "estimated", "1 in tail wheel and wire", le(GEAR["tail_axle"][0], GEAR["tail_axle"][1]), None, "measured", "geometry.json tail axle", "landing_gear_tail"),
    ("wing incl. ailerons, covered", 0.66, "estimated", "built-up sheeted 64 in tapered wing, MonoKote", le(mac_le_z + 0.4 * mac, W["chord_plane_y"]), [mac, b, 0.045], "derived", "40 % MAC, on the chord plane", "wing_main"),
    ("fuselage front (firewall to cockpit), covered", 0.33, "estimated", "lite-ply formers/doublers, balsa sides", le(-0.05, -0.02), [0.4, fus_w, fus_d], "estimated", "from the stations in geometry.json", "fuselage_front"),
    ("fuselage rear and turtle deck, covered", 0.2, "estimated", "balsa sides and sheeted turtle deck", le(0.45, 0.01), [0.7, 0.09, 0.13], "estimated", "from the stations in geometry.json", "fuselage_rear"),
    ("canopy and pilot", 0.08, "estimated", "butyrate canopy; DGA 1/4 scale sportsman pilot (manual p3)", le(0.27, 0.09), None, "measured", "pilot block in geometry.json", "canopy_pilot"),
    ("stabilizer and elevators, covered", 0.12, "estimated", "sheeted built-up stab", le(0.75, T["stab_y"]), [0.17, bh, 0.01], "measured", "stab from geometry.json", "horizontal_tail"),
    ("fin and rudder, covered", 0.07, "estimated", "sheeted built-up fin", le(fin_cz, fin_cy), [0.22, 0.01, 0.3], "derived", "area centroid of the fin polygon", "vertical_tail"),
    ("pushrods, horns, hardware", 0.1, "estimated", "clevises, horns, pushrods, screws: rough sum", le(0.3), None, "estimated", "spread along the fuselage", "control_hardware"),
]
fuel_item = ("fuel (full tank)", TANK_L * 1e-3 * fuel_registry.blend_density(GLOW_BLEND) * START_FILL, "derived",
             f"FUEL-08: full finite-glow start (D4): {TANK_SOURCE} x {fuel_registry.blend_source(GLOW_BLEND)}; finite 61FX consumption uses the existing NITRO candidate profile",
             le(fw + 0.07), [0.12, 0.065, 0.046], "estimated", "same as the tank; uniform liquid box holding the 0.355 l capacity", "fuel_flight")
mass0 = sum(i[1] for i in items)
mom0 = [sum(i[1] * i[4][k] for i in items) for k in range(3)]
x_target = cg_target_model_z - LE0
x_cg0 = mom0[0] / mass0
# EX-14a: the only weighed .61FX build is RCM's prototype (Jack J. Joseph, RCM April 2000 p.2 specification box: O.S.
# .61FX, 12 oz tank, "Weight, Ready to Fly 124 oz (7 lbs, 12 oz)", 24 oz/sq ft); owner builds on the RC Universe
# build thread weigh 7.6-8.4 lb (docs/research/extra-300-realism/EX-14). The estimated inventory falls short of it,
# so one unaccounted build mass (glue, covering, paint, fuel line, wiring, hardware) closes both the measured mass and
# the manual p43 empty-tank balance point; its station follows from the inventory's own moment.
MEASURED_DRY_KG = 124 * OZ
mb = MEASURED_DRY_KG - mass0
if mb <= 0:
    raise ValueError("EX-14a: the estimated dry inventory already exceeds the measured build mass")
xb = (MEASURED_DRY_KG * x_target - mom0[0]) / mb
if not le(g["spinner"]["back_z"])[0] <= xb <= le(T["rudder_hinge_z"])[0]:
    raise ValueError(f"EX-14a: the build-mass closure station {xb:.3f} m lies outside the fuselage")
ballast_pos = [xb, mom0[1] / mass0, mom0[2] / mass0]  # at the inventory's own height and lateral station
note("balance", "dry inventory before the build-mass closure (kg, CG x_aft m)", [mass0, x_cg0], f"manual empty-tank target x_aft {x_target:.4f}")
note("balance", "measured dry build mass (kg)", MEASURED_DRY_KG, "RCM April 2000 review prototype, O.S. .61FX: 124 oz ready to fly (owner builds 7.6-8.4 lb)")
note("balance", "unaccounted build-mass closure (kg, x_aft m)", [mb, xb], "m = M_measured - M_inventory at x = (M_measured x_target - sum m x) / m: closes the measured mass and the manual p43 empty-tank balance point")
# The name keeps the "virtual reference-build balancing mass" marker: crash economics excludes it as no purchasable part.
items.append(("virtual reference-build balancing mass (EX-14a: unaccounted build mass closing the RCM-weighed 124 oz)", mb, "derived",
              f"{SCRIPT}: EX-14a closure: RCM April 2000 prototype 124 oz ready to fly minus the estimated inventory, placed where the dry build balances at the manual p43 point; glue, covering, paint, wiring and hardware the inventory does not list. NOT measured component data or a ballast recommendation",
              ballast_pos, [0.3, fus_w, fus_d], "estimated", "solved station; spread over the fuselage around it", "ballast_reference"))
dry_mass = mass0 + mb
dry_cg = [sum(i[1] * i[4][k] for i in items) / dry_mass for k in range(3)]
note("balance", "dry balanced reference (kg, CG x_aft m)", [dry_mass, dry_cg[0]], "RCM-weighed mass at the manual p43 empty-tank target")

# The finite-glow flight reference adds the full tank only after the manual's dry balance condition is met.
items.append(fuel_item)
mass = sum(i[1] for i in items)
cg = [sum(i[1] * i[4][k] for i in items) / mass for k in range(3)]
cg_model_z, cg_model_y = cg[0] + LE0, cg[2]
cg_loaded_mac = (cg_model_z - mac_le_z) / mac
dry_cg_model_z = dry_cg[0] + LE0
dry_cg_mac = (dry_cg_model_z - mac_le_z) / mac
note("balance", "loaded full-tank reference (kg, CG x_aft m, CG % MAC)", [mass, cg[0], 100 * cg_loaded_mac], "derived after adding the full finite-glow tank to the dry manual-balanced inventory; consumption changes mass, CG and inertia")
sm = note("aero", "static margin at loaded full-tank CG (% MAC)", 100 * (x_np - cg_model_z) / mac,
     f"neutral point at model z {x_np:.4f} ({100 * (x_np - mac_le_z) / mac:.1f} % MAC); loaded full-tank CG {100 * cg_loaded_mac:.2f} % MAC")
Cma_cg = Cma + CLa * (cg_model_z - x_arp) / c_ref
note("aero", "Cma about the loaded CG (1/rad, c_ref)", Cma_cg, "tail about the wing-body ac; transferred to derived loaded full-tank CG")

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
START_SPEED_SOURCE = (
    "estimated from the installed O.S. 61FX candidate trim envelope: 22 m/s is the lowest whole-m/s setting tested "
    "with a six-axis root and at least 1% throttle for full and 10% tank at reference and hot-high conditions; "
    "the original 17 m/s estimate stalls at the minimum throttle command at reference conditions"
)
V_start = note("aero", "start speed (m/s)", max(round(1.6 * Vs), 22), START_SPEED_SOURCE)
CL_ref = note("aero", "CL_ref", mass * G0 / (0.5 * RHO * V_start ** 2 * S), "level flight at the start speed; CL-dependent cross terms are frozen there")

# --- Lateral-directional --------------------------------------------------------------------------------------
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
# EX-14d (D10-R3): the local model's fuselage side force (Allen-Perkins, at the ARP). Its attached slope is the same
# DATCOM body term, so local and oracle agree at small sideslip; NACA TN 3551 (Letko & Williams) measured
# -1.5/rad on A_max for a fuselage of this section (d/w 1.27, between their square and deep bodies), x K_i 1.3 = -1.95,
# against this -2.09. The crossflow part eta c_d S_side carries knife-edge, which the fin cannot (it stalls near 15 deg).
side_pts = [(g["spinner"]["tip_z"], 0.0)] + [(r_[0], r_[2] - r_[3]) for r_ in st]
S_side = note("lateral", "fuselage side area (m2)", sum(0.5 * (h0 + h1) * (z1 - z0) for (z0, h0), (z1, h1) in zip(side_pts, side_pts[1:])),
              "fuselage stations from the spinner tip to the tail post (canopy, gear and wheel pants left out)")
eta_ap = note("lateral", "crossflow finite-length factor eta", 0.65, "estimated: Allen-Perkins eta at fineness L/h 6.7 (literature value, not in the local files); Selig 2010 eq. 7 aspect-ratio correction at AR = L/h gives 0.62")
cd_cross = note("lateral", "fuselage crossflow drag coefficient", 1.4, "estimated: Polhamus NASA TR R-29 Fig. 7(a), rounded rectangle r/b 0.2, subcritical (crossflow Re 0.6-2.3e5 at 33 m/s); sharp corners give ~1.6")
body_cda = note("lateral", "body crossflow drag area eta c_d S_side (m2)", eta_ap * cd_cross * S_side, "Allen-Perkins: CY_cross = -(eta c_d S_side / S) |sin beta| sin beta at zero alpha")
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

# --- E5a: fixed taildragger contacts from the model's wheel bottoms --------------------------------------------
main_pos = [le(GEAR["main_axle"][0], GEAR["main_axle"][1] - GEAR["main_wheel_diameter"] / 2,
               side * GEAR["track"] / 2) for side in (-1, 1)]
tail_pos = le(GEAR["tail_axle"][0], GEAR["tail_axle"][1] - GEAR["tail_wheel_diameter"] / 2)
rest_pitch = math.atan2(tail_pos[2] - main_pos[0][2], tail_pos[0] - main_pos[0][0])
# Vertical reactions balance moments about the CG using horizontal arms in the REST frame, not body x alone.
# Splitting k by those reactions gives equal vertical sag and preserves this three-point attitude.
ground_arm = lambda pos: math.cos(rest_pitch) * (cg[0] - pos[0]) + math.sin(rest_pitch) * (cg[2] - pos[2])
main_arm, tail_arm = ground_arm(main_pos[0]), ground_arm(tail_pos)
tail_share = main_arm / (main_arm - tail_arm)
if not 0 < tail_share < 1:
    raise ValueError("E5a: CG projection lies outside the wheelbase")
k_total = mass * (0.09 * 240) ** 2
k_main, k_tail = k_total * (1 - tail_share) / 2, k_total * tail_share
note("gear", "three-point pitch (deg), tail load share, static sag (mm)",
     [math.degrees(rest_pitch), tail_share, 1000 * mass * G0 / k_total],
     "E5a: point-contact rest geometry; stiffness shares use ground-projected CG moment arms")


def gear_contact(identity, name, position, stiffness, travel, steering=0.0):
    contact = {
        "id": identity,
        "name": name,
        "position": q(position, "m", "derived", GEO_SRC + "; wheel bottom = axle minus radius, transformed to LE frame. Axle stations/heights from EX-01 metrology; diameters from kit references; main track 0.32 m is estimated, not measured."),
        "stiffness": q(stiffness, "N/m", "estimated", "E5a: numerical E1 heave rule omega*dt=0.09 at 240 Hz, total k=m*(0.09*240)^2; split by ground-projected static load share for equal sag. Not measured wire/strap stiffness."),
        "damping": q(2 * 0.3 * math.sqrt(stiffness * mass / 3), "N·s/m", "estimated", "E5a: damping ratio 0.3 with loader m/3 convention, as the P-51 contact fixture; not a measured Extra leg/tyre response."),
        "max_compression": q(travel, "m", "estimated", "GP-06c reserve-energy travel (main 0.10 m, tail 0.08 m): the peak compression of a level/three-point free drop at the former 14 CFR 23.727 reserve velocity, 1.2 x 7 ft/s = 2.56 m/s with wing lift 2/3 W through the CG (23.473(d)/(e)), x1.05 rounded up to 5 mm (research/ground-physics/gp06/reserve_drop.gd: main 93 mm, tail 73 mm). Replaces the E5a 0.08/0.05 m thresholds, which collapsed below the 7 ft/s limit drop. A full-size certification convention borrowed for RC; not measured gear travel or structural strength."),
    }
    if steering:
        contact["max_steering"] = q(steering, "deg", "estimated", "E5a: provisional +/-25 deg rudder-linked tail wheel, as the P-51 fixture. Negative coefficient: positive right-yaw command steers the aft wheel left, forcing the tail left and nose right. No caster or measured linkage ratio.")
    return contact


landing_gear = {
    "description": "E5a: fixed main wheels and rudder-linked tail wheel. File-backed GP-02 wheel profiles supply per-contact radius, inertia and rim-speed dynamics; terrain-aware contact and wheel-radius corrections are active. E5a spring, damping, tyre and steering values remain provisional. The 1.25 breakaway factor is the shared E3b1 engineering estimate midpoint borrowed from Stik, not an Extra measurement; no caster or brakes.",
    "contacts": [gear_contact("contact_main_left", "main_left", main_pos[0], k_main, 0.10),
                 gear_contact("contact_main_right", "main_right", main_pos[1], k_main, 0.10),
                 gear_contact("contact_tail", "tail", tail_pos, k_tail, 0.08, -25.0)],
    "rolling_resistance": q(0.04, "1", "estimated", "E5a: reuse Stik E2 reference C_rr for similarly sized model wheels; Extra 69.85 mm mains and 25.4 mm tail are not separately calibrated. Field factors apply per contact."),
    "side_friction": q(0.8, "1", "borrowed", "E5a: same provisional JSBSim c172x coefficient used by Stik and P-51 E2 fixtures; no Extra tyre measurement."),
    "peak_slip_angle": q(6.0, "deg", "borrowed", "E5a: same provisional 6 degree peak-slip regularization as Stik/P-51 E2; no Extra tyre measurement."),
    "breakaway_factor": q(1.25, "1", "estimated", "E5a runway-start candidate: reuse the shared E3b1 engineering estimate midpoint (1.0-1.5) from the Stik ground knowledge base. Extra bearing/axle breakaway has not been measured; this is an explicit provisional transfer, not Extra-specific validation."),
}

# --- EX-06: physical installation from the rendered thrust frame --------------------------------------------
prop_geometry = g["propeller"]
down_deg = float(prop_geometry["down_thrust_deg"])
right_deg = float(prop_geometry["right_thrust_deg"])
down_rad, right_rad = math.radians(down_deg), math.radians(right_deg)
prop_delta = float(prop_geometry["z"]) - float(g["spinner"]["back_z"])
# Godot Node3D.rotation uses default YXZ order on the visual thrust frame. Apply its pivot and
# rotation Vector3(-down, -right, 0) to the propeller child at local z=prop_delta.
prop_hub_model = [
    -prop_delta * math.cos(down_rad) * math.sin(right_rad),
    prop_delta * math.sin(down_rad),
    float(g["spinner"]["back_z"]) + prop_delta * math.cos(down_rad) * math.cos(right_rad),
]
prop_hub_le = le(prop_hub_model[2], prop_hub_model[1], prop_hub_model[0])
prop_hub_offset = [prop_hub_le[k] - cg[k] for k in range(3)]
prop_axis_body_fr = [
    math.cos(down_rad) * math.cos(right_rad),
    math.cos(down_rad) * math.sin(right_rad),
    math.sin(down_rad),
]
if abs(sum(v * v for v in prop_axis_body_fr) - 1.0) > 1e-12:
    raise ValueError("EX-06: transformed propeller shaft axis is not unit length")
note("propulsion", "propeller shaft axis (body FRD)", prop_axis_body_fr,
     f"geometry.json thrust frame: {down_deg:g} deg down, {right_deg:g} deg right; [cos(down)cos(right), cos(down)sin(right), sin(down)]")
note("propulsion", "propeller hub (model right, up, aft m)", prop_hub_model,
     "geometry.json propeller child transformed by the visual thrust_frame pivot/rotation (default YXZ)")
note("propulsion", "propeller hub offset from loaded CG (LE frame)", prop_hub_offset,
     "transformed propeller hub [x_aft,y_right,z_up] minus the derived loaded inventory CG")

# --- EX-14c: propeller in a crossflow and tail slipstream (the P-51's P51-06/P51-12 method) --------------------------
# The Glow shaft flies the installation's 12-annulus no-induction surrogate, so Ct(J), solidity, section slope and
# profile drag come from that same propeller (research/glow-engines/calibration_report.py mirrors the runtime), not
# from the borrowed APC 11x6 tables. McCormick's blade-element result as used by Selig (AIAA 2010-7938), per radian of
# disc angle of attack, q = ½ρV², V = JnD:
#   C̄l = (3J/2π)·[16·Ct/(σπ²J) + C̄d]
#   C_N = σπJ²/16 · [C̄l + (aJ/2π)·ln(1 + (π/J)²) + (π/J)·C̄d]   (× ρn²D⁴)
#   C_M = σπJ²/32 · [(2π/3J)·C̄l + (a/2)·(1 − (J/π)²·ln(1 + (π/J)²)) − (π/J)·C̄d]   (× ρn²D⁵, nose-left for α > 0)
GLOW_DIR = ROOT / "research" / "glow-engines"
if str(GLOW_DIR) not in sys.path:
    sys.path.insert(0, str(GLOW_DIR))
from calibration_report import annular_prop_performance  # noqa: E402
INSTALLATION = "app/data/glow/extra_61fx_2t.json"
gp = {k: v["value"] for k, v in json.load(open(ROOT / INSTALLATION))["propeller"].items()}
section = {"lift_slope_per_rad": gp["lift_slope"], "cd0": gp["cd0"], "induced_drag": gp["induced_drag"], "blades": gp["blades"]}
D_p, N_REF = gp["diameter_m"], 12000.0  # Ct of the no-induction surrogate does not depend on rpm at fixed J
n_ref = N_REF / 60.0
sigma = note("propulsion", "solidity of the Glow propeller surrogate", gp["blades"] * gp["chord_m"] * 0.8 * (D_p / 2) / (math.pi * (D_p / 2) ** 2),
             f"B c (0.8 R) / (pi R^2): {gp['blades']:g} constant-chord blades over its 0.2-1.0 R annuli ({INSTALLATION})")
a_bl, cd_bl = gp["lift_slope"], gp["cd0"]
nf_rows, pm_rows = [], []
for k_j in range(22):
    J_ = 0.05 * k_j
    if J_ == 0.0:
        nf_rows.append([0.0, 0.0])
        pm_rows.append([0.0, 0.0])
        continue
    ct_ = annular_prop_performance(N_REF, J_ * n_ref * D_p, D_p, gp["pitch_m"], gp["chord_m"], RHO, section)["thrust_n"] / (RHO * n_ref ** 2 * D_p ** 4)
    lg = math.log(1 + (math.pi / J_) ** 2)
    clb = 3 * J_ / (2 * math.pi) * (16 * ct_ / (sigma * math.pi ** 2 * J_) + cd_bl)
    cn = sigma * math.pi * J_ ** 2 / 16 * (clb + a_bl * J_ / (2 * math.pi) * lg + math.pi / J_ * cd_bl)
    cm = sigma * math.pi * J_ ** 2 / 32 * (2 * math.pi / (3 * J_) * clb + a_bl / 2 * (1 - (J_ / math.pi) ** 2 * lg) - math.pi / J_ * cd_bl)
    nf_rows.append([round(J_, 2), round(max(cn, 0.0), 6)])
    pm_rows.append([round(J_, 2), round(max(cm, 0.0), 6)])
note("propulsion", "C_N, C_M at J 0.3 and 0.5 (per rad)", [nf_rows[6][1], pm_rows[6][1], nf_rows[10][1], pm_rows[10][1]], "x rho n2 D4 and x rho n2 D5")
# Tail pieces: geometry only; the wake (momentum theory, swirl, sidewash) is computed by physics/slipstream.gd.
fin_te_at = lambda y: T["rudder_te_low"][0] + (T["rudder_top_te_z"] - T["rudder_te_low"][0]) * (y - T["rudder_te_low"][1]) / (T["fin_top_y"] - T["rudder_te_low"][1])
fin_root_y = fus_top(xv_ac)
fin_chords = [fin_te_at(fin_root_y) - fin_le_at(fin_root_y), fin_te_at(T["fin_top_y"]) - T["fin_le_top_z"]]
# Unlike the P-51's, the Extra's rudder runs down past the slender tail post to the fuselage bottom line, straight
# behind the thrust line: that part sits in the wash (the reason the model's tail lifts in a 1/3-throttle taxi and it
# pivots in a hammerhead), so it is its own piece, not dropped.
post_top = st[-1][2]
low_rudder = [(z_post, post_top), (fin_te_at(post_top), post_top), tuple(T["rudder_te_low"]), tuple(T["rudder_bottom_corner"]), tuple(T["rudder_bottom_hinge"])]
S_low, low_cz, _ = shoelace(low_rudder)
low_bottom = 0.5 * (T["rudder_bottom_hinge"][1] + T["rudder_bottom_corner"][1])  # mid-height of the slanted bottom edge
low_chords = [T["rudder_bottom_corner"][0] - z_post, fin_te_at(post_top) - z_post]
note("slipstream", "fin piece above the fuselage top: root height, span, chords (m), area (m2)", [fin_root_y, T["fin_top_y"] - fin_root_y] + fin_chords + [Sv - S_low],
     "fuselage top at the fin ac up to the fin tip; LE/TE lines of the fin polygon")
note("slipstream", "rudder piece below the fuselage top: bottom height, span, chords (m), area (m2)", [low_bottom, post_top - low_bottom] + low_chords + [S_low],
     "rudder behind the tail post, from the mid-height of its slanted bottom edge to the fuselage top line at the post; polygon area")
slip_pieces = [
    {"surface": "vertical", "area": Sv - S_low, "root": le(xv_ac, fin_root_y), "span_dir": [0.0, 0.0, 1.0], "span": T["fin_top_y"] - fin_root_y, "chords": fin_chords},
    {"surface": "vertical", "area": S_low, "root": le(low_cz, low_bottom), "span_dir": [0.0, 0.0, 1.0], "span": post_top - low_bottom, "chords": low_chords},
    {"surface": "horizontal", "area": Sh / 2, "root": le(xh_ac, T["stab_y"]), "span_dir": [0.0, 1.0, 0.0], "span": T["stab_half_span"], "chords": [crh, cth]},
    {"surface": "horizontal", "area": Sh / 2, "root": le(xh_ac, T["stab_y"]), "span_dir": [0.0, -1.0, 0.0], "span": T["stab_half_span"], "chords": [crh, cth]},
]

# --- EX-14e: ground effect constants of this planform (research/extra-300/ex14/ground_effect_vlm.py writes the table) --
GE = json.load(open(ROOT / "research/extra-300/ex14/vlm_ground_effect.json"))
arp_wheels = W["chord_plane_y"] - (GEAR["main_axle"][1] - GEAR["main_wheel_diameter"] / 2)
x_wheels = arp_wheels / b
_ge_at = lambda key: next(r[key] for r in GE["rows"] if abs(r["x"] - 0.12) < 1e-9)
GE_SRC_I = (f"research/extra-300/ex14/ground_effect_vlm.py: least-squares fit of the faded runtime law to the same-CL induced-drag ratio of the "
            f"P-51's image-method Weissinger VLM run on this wing (straight taper, no dihedral or twist), x = ARP height / span 0.06-1.5, rms {GE['fit_induced']['rms']:.3f}; "
            f"ratio {_ge_at('cdi_ratio_same_cl'):.2f} at x 0.12 (the low wing sits at x {x_wheels:.2f} on its wheels) where Raymer's 33x^1.5 gives 0.58. No fuselage; not measured")
GE_SRC_T = (f"research/extra-300/ex14/ground_effect_vlm.py: least-squares fit of the faded runtime law to the VLM's tail downwash ratio per unit wing lift "
            f"over the stabilizer quarter-chord line ({T['stab_y'] - W['chord_plane_y']:.3f} m above the chord plane), rms {GE['fit_tail']['rms']:.3f}; "
            f"ratio {_ge_at('tail_downwash_ratio_per_lift'):.2f} at x 0.12. No fuselage; not measured")
note("ground effect", "induced c, e; tail c, e (VLM fit)", [GE["fit_induced"]["coefficient"], GE["fit_induced"]["exponent"], GE["fit_tail"]["coefficient"], GE["fit_tail"]["exponent"]],
     f"EX-14e image-method VLM of this planform, faded runtime law; ARP {arp_wheels:.3f} m above the main-wheel contact in a level attitude (x {x_wheels:.3f})")

# --- Assemble ----------------------------------------------------------------------------------------------------
stik = legacy_input(json.load(open(STIK)))
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
crash_hull_probes = [
    ("probe_wing_left_le", le(W["le_z_tip"], W["chord_plane_y"], -semi)),
    ("probe_wing_right_le", le(W["le_z_tip"], W["chord_plane_y"], semi)),
    ("probe_wing_left_te", le(W["le_z_tip"] + ct, W["chord_plane_y"], -semi)),
    ("probe_wing_right_te", le(W["le_z_tip"] + ct, W["chord_plane_y"], semi)),
    ("probe_spinner_tip", le(g["spinner"]["tip_z"])),
    ("probe_rudder_bottom", le(T["rudder_te_low"][0], T["rudder_te_low"][1])),
    ("probe_stabilizer_left_tip", le(T["elevator_tip_te_z"], T["stab_y"], -T["stab_half_span"])),
    ("probe_stabilizer_right_tip", le(T["elevator_tip_te_z"], T["stab_y"], T["stab_half_span"])),
    ("probe_fin_top", le(T["rudder_top_te_z"], T["fin_top_y"])),
    ("probe_canopy_top", le(max(g["canopy"]["top"], key=lambda p: p[1])[0], max(p[1] for p in g["canopy"]["top"]))),
]
data = {
    "format": "openrc-aircraft v1",
    "physical_identity_version": 1,
    "id": "gp-extra-300s-60",
    "description": "Great Planes Extra 300S .60 (GPMA0236), 64 in span, O.S. .61FX glow. EXPERIMENTAL first physics estimate (EX-05), generated by " + SCRIPT + "; not flight-identified. Visual geometry lives in assets/aircraft/extra-300s-60/geometry.json.",
    "frames": {
        "le_frame": "positions in metres from the wing leading edge at the centreline (the measured trapezoid's root LE, model z " + f"{LE0}" + "): [x_aft, y_right, z_up]; z = 0 on the nominal spinner-axis datum; physical shaft angles are propulsion.propeller.thrust_angles",
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
    "start": {"level_speed": q(float(V_start), "m/s", "estimated", START_SPEED_SOURCE)},
    "balance": {
        "plan_cg": q(dry_cg, "m", "derived", "FUEL-08/EX-14a: dry (empty-tank) CG of the RCM-weighed 124 oz build, balanced at the manual p43 4-1/8 in point (model z 0; EX-01 read 4.116 in) by the build-mass closure; finite-glow flight reference starts with a full tank; mass distribution estimated, not measured"),
        "firewall": q(le(fw), "m", "measured", "firewall station, " + GEO_SRC),
        "configuration": "rcm-weighed-dry-manual-p43-plus-full-finite-glow-tank-v3",
        "fuel_state": "empty_tanks",
        "cg_range": {"forward": q(dry_cg[0] - 0.009525, "m", "manual", MANUAL + " p43: balance point +-3/8 in, empty tank"),
                     "aft": q(dry_cg[0] + 0.009525, "m", "manual", MANUAL + " p43: balance point +-3/8 in, empty tank")},
        "cg_tolerance": q(0.001, "m", "estimated", D("EX-14a: RCM-weighed dry mass with an estimated inventory, closed to the manual p43 empty-tank point, then full finite-glow fuel added; the mass distribution is not measured")),
    },
    "inventory": [
        dict({"id": it[8], "name": it[0], "mass": inventory_mass(it), "position": q([float(v) for v in it[4]], "m", it[6], it[7])},
             **({"size": q([float(v) for v in it[5]], "m", "estimated", "rough envelope for intrinsic inertia")} if it[5] else {}),
             **({"energy_source": ENERGY_SOURCES[it[0]]} if it[0] in ENERGY_SOURCES else {}))
        for it in items
    ],
    "fuel_system": {"tanks": [{
        "id": "main_tank", "fuel": GLOW_BLEND, "liquid_inventory_id": "fuel_flight", "shell_inventory_id": "fuel_tank",
        "capacity": q(TANK_L, "l", "manual", TANK_SOURCE),
        "unusable": q(0.005, "l", "estimated", "FUEL-05b: clunk residue estimate; no published value (docs/research/fuel-systems/FUEL-00 section 6.3)"),
        "pickup": "clunk", "feed": "suction_muffler"}]},
    "crash_hull": q([point for _, point in crash_hull_probes], "m", "measured", "Body crash points (le frame) from " + GEO_SRC + ": wing tip LE/TE, spinner tip, rudder bottom TE, stab tips, fin top, canopy top. Wheel bottoms use E5a landing_gear contacts and are excluded from this crash hull."),
    "crash_hull_ids": [identity for identity, _ in crash_hull_probes],
    # CR-01d: one semantic name per crash_hull point above, in the same order (crash presentation only).
    "crash_hull_components": ["left_wing_tip", "right_wing_tip", "left_wing_tip", "right_wing_tip", "spinner", "tail_end", "left_stab_tip", "right_stab_tip", "fin_top", "canopy"],
    "plausibility": {
        "mass_range": q([3.0, 4.2], "kg", "manual", MANUAL + ": 7-7.5 lb (3.18-3.40 kg) dry; RCM review build 124 oz (3.52 kg) RTF; RC Universe owner builds 7.6-8.4 lb (3.45-3.81 kg); widened for the 0.30 kg full tank"),
        "inertia_reference": stik["plausibility"]["inertia_reference"],
    },
    "controls": {
        "surface_ids": {"aileron_left": "surface_aileron_left", "aileron_right": "surface_aileron_right", "elevator": "surface_elevator", "rudder": "surface_rudder"},
        "max_throw": {
            k: q(v, "deg", "derived", f"{MANUAL} p43 HIGH rate at the widest part, delta = asin(d / chord): mechanical maximum with transmitter ATV near 100 % (manual); the radio's dual rate reduces it")
            for k, v in throws.items()
        },
        "servo_full_throw_time": stik["controls"]["servo_full_throw_time"],
        # D6e: the manual's LOW rates as fractions of the high-rate travel at the widest part (aileron 0.4, elevator
        # and rudder 0.6), converted to command fractions of the angular throw, asin(f sin d) / d; applied by the
        # session to the keyboard sticks as a radio would (controls.rates.normal). The manual lists no expo.
        "rates": {
            "normal": {
                **{k: q(math.asin(LOW_RATE_TRAVEL[k] * math.sin(math.radians(throws[k]))) / math.radians(throws[k]), "1", "derived",
                       f"{MANUAL} p43 LOW rate: {LOW_RATE_TRAVEL[k]:.1f} of the high-rate travel at the widest part, as the command fraction asin(f sin d)/d of the angular throw (EX-08 airborne audit)")
                  for k in ["aileron", "elevator", "rudder"]},
                **{k + "_expo": q(0.0, "1", "estimated", f"{MANUAL} lists no expo; 0 until a transmitter setup is documented") for k in ["aileron", "elevator", "rudder"]},
            },
        },
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
            "body_cy_beta": q(CYb_B, "1/rad", "derived", D("EX-14d (D10-R3): the DATCOM body side-force slope -2 K_i S0/S (K_i 1.3 low wing), as in the oracle's CYb; NACA TN 3551 fuselage-alone -1.5/rad on A_max x K_i gives -0.116")),
            "body_crossflow_area": q(body_cda, "m2", "derived", D("EX-14d (D10-R3): Allen-Perkins eta 0.65 x c_d 1.4 (Polhamus TR R-29, subcritical rounded rectangle) x fuselage side area from geometry.json; estimated factors")),
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
                # E0a2c: the loader derives the free tail law from this (free slope CLa_h eta, physical elevator tau,
                # downwash as the lagged wing lift); without it the local tail would use the downwashed slope for pitch
                # rate and the inflated tau for its stall (docs/research/flight-dynamics/elevator-repair-2026-10-13.md).
                "downwash_gradient": q(deps, "1", "derived", D("d(eps)/d(alpha) at the tail: elliptic-wing estimate 2 CLa_w / (pi AR), the same value folded into lift_slope, control_effectiveness and incidence")),
            },
            "vertical": {
                "area": q(Sv, "m2", "derived", D("fin + rudder side polygon from " + GEO_SRC)),
                "position": q(le(xv_ac, fin_cy), "m", "derived", D("fin ac: quarter chord at the area-centroid height")),
                "lift_slope": q(slope_v, "1/rad", "derived", D("Helmbold (end-plated AR) x DATCOM sidewash/eta")),
                "control_effectiveness": q(ce_v, "1", "derived", D("thin-airfoil tau x 0.8 / sidewash factor")),
                "incidence": q(0.0, "rad", "estimated", "symmetric fin; propulsion installation angles are separate"),
            },
        },
        # EX-14e: the shared M5-GE-1 module with constants fitted to this planform and tail (image-method VLM).
        "ground_effect": {
            "induced_coefficient": q(GE["fit_induced"]["coefficient"], "1", "derived", GE_SRC_I),
            "induced_exponent": q(GE["fit_induced"]["exponent"], "1", "derived", GE_SRC_I),
            "downwash_coefficient": q(GE["fit_tail"]["coefficient"], "1", "derived", GE_SRC_T),
            "downwash_exponent": q(GE["fit_tail"]["exponent"], "1", "derived", GE_SRC_T),
        },
    },
    "propulsion": json.loads(json.dumps(stik["propulsion"])),
    "landing_gear": landing_gear,
}
p = data["propulsion"]
p["id"] = "propulsion_main"
p["description"] = "O.S. MAX-61FX prototype engine (manual p3), using the existing NITRO MAX-61FX candidate profile and a dedicated Extra glow installation; APC 12x6 Sport nominal propeller uses borrowed UIUC APC 11x6 Ct/Cp measurements. The plan-derived shaft angles and visual propeller hub are applied; propeller normal force, P-factor and the quasi-static tail slipstream with swirl use the Glow propeller surrogate (EX-14c); exact prototype propeller remains unidentified. Fuel consumption is finite; Extra-specific carburetor-feed calibration is unavailable and omitted."
p["engine"]["glow_installation"] = "res://data/glow/extra_61fx_2t.json"
p["propeller"]["thrust_angles"] = q([down_deg, right_deg], "deg", "manual",
    "Original plan thrust-frame notes transcribed in " + GEO_SRC + "; ordered [down, right] to match the v2 propulsion contract")
p["propeller"]["thrust_line_offset"] = q(prop_hub_offset, "m", "derived",
    D("visual thrust_frame pivot/rotation and propeller child transform to actual hub; hub minus loaded inventory CG in [x_aft,y_right,z_up]"))
p["propeller"]["rotating_inertia"] = dict(p["propeller"]["rotating_inertia"], source=p["propeller"]["rotating_inertia"]["source"] + " (2-1/2 in spinner here, within the estimate)")
p["propeller"]["normal_force"] = q(nf_rows, "1", "derived", D(f"EX-14c: McCormick blade-element normal force per rad of disc angle of attack (Selig, AIAA 2010-7938), x rho n2 D4; Ct(J), solidity {sigma:.4f}, section slope and cd0 of the Glow propeller surrogate ({INSTALLATION})"))
p["propeller"]["pfactor_moment"] = q(pm_rows, "1", "derived", D("EX-14c: McCormick P-factor yawing moment per rad of disc angle of attack (Selig, AIAA 2010-7938), x rho n2 D5; same Glow propeller surrogate"))
p["propeller"]["slipstream"] = {
    "hub": q(prop_hub_le, "m", "derived", D("EX-14c: propeller disc centre from the visual thrust frame (le frame), as thrust_line_offset")),
    "wash_factor": q([0.8, 1.8], "1", "borrowed", "velocity added at the tail per disc induced velocity w (Selig, AIAA 2010-7938, eqs. 17-19, m = V/(V + w)): 0.8 at m = 0 and 1.8 at m >= 0.75 (Fig. 5); the P-51's value. No Extra wake measurement"),
    "swirl_factor": q(0.6, "1", "estimated", "part of the propeller's angular momentum that reaches the tail (wing and fuselage straighten the rest): research synthesis 0.5-0.8, the P-51's value; Selig: the swirl offsets ~40 % of the torque roll"),
    "vertical_drift": q(1 - deps, "1", "derived", D("1 - d(eps)/d(alpha): the wake drifts with the downwashed flow")),
    "propeller_sidewash": q(1.0, "1", "borrowed", "Ribner, NACA ARR L4I12a (1944) eq. 8: far-wake crossflow of a propeller at incidence, applied as published (1); also selects the piecewise swirl quadrature (P51-26). The Glow installation supports only this quasi-static wake (EX-14c)"),
    "pieces": [{k: (q(v, "m2" if k == "area" else ("1" if k == "span_dir" else "m"), "derived", D("EX-14c: tail piece from geometry.json")) if k != "surface" else v) for k, v in pc.items()} for pc in slip_pieces],
}

# The loader's exact consistency rules (aircraft_data.gd _surfaces) must hold: recompute them from the rounded file.
def check_consistency(d):
    a = {k: v["value"] for k, v in d["aero"]["coefficients"].items()}
    fin_ = d["aero"]["surfaces"]["vertical"]
    arp = d["reference"]["aero_reference_point"]["value"]
    S_, b_ = d["reference"]["wing_area"]["value"], d["reference"]["wing_span"]["value"]
    cy = fin_["lift_slope"]["value"] * fin_["area"]["value"] / S_ * fin_["control_effectiveness"]["value"]
    arm = fin_["position"]["value"][0] - arp[0]
    exp = {"CYdr": cy, "Cndr": -cy * arm / b_, "Cldr": cy * (fin_["position"]["value"][2] - arp[2]) / b_,
           "Cnb": fin_["lift_slope"]["value"] * fin_["area"]["value"] / S_ * arm / b_,
           "CYb": -fin_["lift_slope"]["value"] * fin_["area"]["value"] / S_ + d["aero"]["surfaces"]["body_cy_beta"]["value"]}
    for k, v in exp.items():
        d["aero"]["coefficients"][k]["value"] = v  # exact, unrounded: the loader compares to 1e-8
check_consistency(data)

legacy_data = data
data = upgrade(legacy_data)
validate_physical_identity(data)
parity = numeric_parity(legacy_data, data)
text = (json.dumps(data, indent=2, ensure_ascii=False) + "\n").replace("\n", "\r\n")
rows = ["| Section | Quantity | Value | How |", "| --- | --- | --- | --- |"]
for sec, name, val, how in log:
    v = ", ".join(f"{x:.4g}" for x in val) if isinstance(val, list) else f"{val:.4g}"
    rows.append(f"| {sec} | {name} | {v} | {how} |")
coef_rows = ["| Coefficient | Value | Kind |", "| --- | --- | --- |"] + [f"| {k} | {v['value']:.5g} | {v['kind']} |" for k, v in data["aero"]["coefficients"].items()]
report = f"""# EX-05: Extra 300S .60 physics derivation

Generated by `{SCRIPT}` from `{GEOMETRY.relative_to(ROOT).as_posix()}` and the manual; do not edit (regenerate). Output:
`{OUT.relative_to(ROOT).as_posix()}`. **Experimental**: textbook estimates from measured geometry, not flight identification.
EX-08 flies the envelope, EX-09 looks for an independent contrast.

The final JSON is upgraded to `openrc-aircraft v2` by the ID-gated standardizer. Migration numeric parity: {parity['preserved_numeric_leaves']} original leaves preserved, {parity['relocated_cladot_numeric_leaves']} relocated CLadot leaves, {parity['added_numeric_leaves']} explicit compatibility-default leaves added, {parity['numeric_differences']} differences.

Dry empty-tank reference {dry_mass:.3f} kg at {100 * dry_cg_mac:.2f} % MAC (manual target {100 * cg_target_mac:.2f} % MAC); loaded full-tank reference {mass:.3f} kg at {100 * cg_loaded_mac:.2f} % MAC, static margin at loaded CG {sm:.2f} % MAC, 1-g stall {Vs:.2f} m/s, start {V_start} m/s.
Throws (manual p43 high rate): aileron {throws['aileron']:.1f}°, elevator {throws['elevator']:.1f}°, rudder {throws['rudder']:.1f}°.

## Intermediate quantities

{chr(10).join(rows)}

## Coefficients written (c_ref = S/b; moments about the ARP = wing-body ac)

{chr(10).join(coef_rows)}

## Known simplifications

- The plan-derived 2° right / 0.5° down thrust axis and actual propeller hub are now applied through `thrust_angles` and the CG-relative hub offset. The physics names an APC 12×6 Sport, but the Ct/Cp tables remain a borrowed UIUC APC 11×6 proxy; the exact prototype propeller is unknown.
- EX-14d (D10-R3): the local model carries the fuselage side force at the ARP (attached slope = the oracle's body CYb, plus Allen-Perkins crossflow drag with estimated eta and c_d). Its yaw moment is not: the slender-body part acts on the forebody (destabilizing) and the crossflow part at the side-area centroid about 0.2 m behind the CG (stabilizing); they roughly cancel near knife-edge sideslip, and the oracle's Cnb stays the fin term (v1 contract), as for the Stik. Canopy, gear and wheel-pant side areas are left out.
- The induced-flow strip map calibrates section slope and offsets so integrated wing-plus-horizontal-tail lift slope and
  zero-alpha lift reproduce aircraft-level CLa and CL0. This is a consistency calibration, not independent section data;
  Clp and detailed spanwise attached/post-stall loading remain model predictions at the current strip resolution.
- CL-dependent cross terms (Clb wing part, Clr, Cnp, adverse yaw) are frozen at CL_ref = {CL_ref:.2f}.
- EX-14e: ground effect uses the shared M5-GE-1 law with constants fitted to an image-method VLM of this wing and tail (no fuselage, no rolled-up wake); not measured on a flare.
- EX-14c: the quasi-static tail slipstream (momentum wake, Selig wash factor, swirl, Ribner sidewash), propeller normal force and P-factor follow the P-51 method on the Glow propeller surrogate. The fin is two pieces (above the fuselage top line, and the rudder behind the tail post down to its bottom edge); both use the vertical surface's per-area law, although the lower piece is all rudder. The wing in the wake, a transported (lagged) wake and the jet normal force are not modelled; no Extra wake measurement exists. Finite 61FX glow consumption uses the existing candidate profile (torque and combustion estimates remain unvalidated); no Extra-specific carburetor-feed calibration is available, so feed-pressure/starvation behavior is not represented. E5a spring, damping, tyre, steering and collapse values remain provisional. The file-backed GP-02 wheel profile supplies per-contact radii, inertias, spin relaxation and brake availability; the shared ground path applies wheel/terrain interaction and continuous rim-speed state. The breakaway factor 1.25 is the shared E3b1 engineering estimate midpoint transferred from Stik; Extra bearing/axle breakaway has not been measured. Extra has no caster or brakes, and no Extra takeoff/landing handling acceptance yet.
"""

if "--check" in sys.argv:
    stale = []
    if not OUT.exists() or OUT.read_bytes() != text.encode("utf-8"):
        stale.append(OUT)
    if not REPORT.exists() or REPORT.read_text() != report:
        stale.append(REPORT)
    if stale:
        sys.exit("stale: " + ", ".join(str(p.relative_to(ROOT)) for p in stale) + f" (run {SCRIPT})")
    print("gp_extra_300s_60.json and derivation.md are up to date")
else:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(text.encode("utf-8"))
    REPORT.write_text(report)
    print(f"wrote {OUT.relative_to(ROOT)} and {REPORT.relative_to(ROOT)}")
    print(f"dry {dry_mass:.3f} kg / {100 * dry_cg_mac:.2f} % MAC; loaded {mass:.3f} kg / {100 * cg_loaded_mac:.2f} % MAC; SM {sm:.2f} % MAC, stall {Vs:.2f} m/s, start {V_start} m/s")
