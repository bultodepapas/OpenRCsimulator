#!/usr/bin/env python3
"""F4U-07: physics data of the 1/5 F4U-1D Corsair (DLE-111 class), derived and reproducible.

Reads the provisional 1/5 geometry measured on the author's R59 master (assets/aircraft/f4u-corsair-1-5/geometry-r59.json),
the authored inputs in source.json, the gull-wing ground-effect fit (vlm_ground_effect.json beside this script), the
Mejzlik 26x12 propeller data and BEM calibration of the P-51 (research/p51/p51-06) and the Ugly Stik data file for
shared conventions and provisional local-surface limits. Writes an openrc-aircraft v2 file natively (the v1 upgrader
is ID-gated to the eight reviewed aircraft) and derivation.md.

The method follows the P-51 generator (research/p51/p51-05/derive_physics.py): Helmbold/DATCOM lift slopes, tail
volume, strip theory, Schrenk/Reynolds spanwise stall, drag build-up, component inventory, BEM propeller and a shaft
model. Corsair-specific: the measured inverted-gull planform and dihedral (strip integral, carried by
aero.surfaces.wing_body_cl_beta), NACA 230-series sections (XFOIL with stated corrections), the VLM tail downwash and
ground effect of that planform, and retraction paths taken from R59's own gear rig. No trim, neutral-point or sideslip
calibration is applied: the NACA F4U values are reported as checks. Nothing here validates the airplane.

The output is staged beside this script until catalog registration (F4U-09) moves it to app/data/aircraft.

    python research/f4u-corsair/F4U-07/derive_physics.py           # writes the JSON and the report
    python research/f4u-corsair/F4U-07/derive_physics.py --check   # fails if either file is stale
    python research/f4u-corsair/F4U-07/derive_physics.py --dry     # prints the intermediate quantities
"""
import json
import math
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
for extra in ("research/aircraft-standardization", "research/fuel-systems", "research/p51/p51-06"):
    if str(ROOT / extra) not in sys.path:
        sys.path.insert(0, str(ROOT / extra))
from physical_identity import validate_physical_identity  # noqa: E402
import fuel_registry  # noqa: E402
from bem import bem_tables  # noqa: E402

GEOMETRY = ROOT / "assets/aircraft/f4u-corsair-1-5/geometry-r59.json"
SOURCE = ROOT / "assets/aircraft/f4u-corsair-1-5/source.json"
STIK = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
GE_FILE = HERE / "vlm_ground_effect.json"
MEJZ = ROOT / "research/p51/p51-06/mejzlik_26x12.json"
CALIB = ROOT / "research/p51/p51-06/calibration.json"
OUT_DIR = Path(os.environ.get("OPENRC_AIRCRAFT_OUTPUT_DIR", HERE)).resolve()
REPORT_DIR = Path(os.environ.get("OPENRC_AIRCRAFT_REPORT_DIR", HERE)).resolve()
OUT = OUT_DIR / "f4u_corsair_1_5.json"
REPORT = REPORT_DIR / "derivation.md"
SCRIPT = "research/f4u-corsair/F4U-07/derive_physics.py"
GEO_SRC = "assets/aircraft/f4u-corsair-1-5/geometry-r59.json (F4U-06: R59 visual master measured at 1/5; provisional until g1)"
IN, FT2, LB = 0.0254, 0.09290304, 0.45359237
RHO, G0, NU = 1.225, 9.80665, 1.46e-5


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


g = load_json(GEOMETRY)
src = load_json(SOURCE)
KIT, FULL, SEC = src["kit"], src["full_size"], src["sections"]
REFSET = KIT["reference_setup"]
SCALE = KIT["scale"]
AREA_SCALE = SCALE * SCALE
log = []


def note(section, name, value, how):
    log.append((section, name, value, how))
    return value


def q(value, unit, kind, source):
    if isinstance(value, float):
        value = round(value, 6)
    elif isinstance(value, list):
        value = [[round(x, 6) for x in v] if isinstance(v, list) else round(v, 6) for v in value]
    return {"value": value, "unit": unit, "kind": kind, "source": source}


D = lambda how: f"{SCRIPT}: {how}"


def helmbold(aspect, kappa, half_chord_sweep=0.0):
    t = math.tan(half_chord_sweep)
    return 2 * math.pi * aspect / (2 + math.sqrt(aspect ** 2 / kappa ** 2 * (1 + t * t) + 4))


def flap_tau(cf):
    th = math.acos(2 * cf - 1)
    return 1 - (th - math.sin(th)) / math.pi


def lerp_table(tab, x):
    if x <= tab[0][0]:
        return tab[0][1]
    for (x0, y0), (x1, y1) in zip(tab, tab[1:]):
        if x0 <= x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return tab[-1][1]


def median_filter(values, half=3):
    out = []
    for i in range(len(values)):
        window = sorted(values[max(0, i - half):i + half + 1])
        out.append(window[len(window) // 2])
    return out


# --- Wing planform (measured right half, mirrored) ---------------------------------------------------------------
WS = g["wing_sections"]
semi = g["hull"]["wing_tip"][1]
b = note("reference", "b (m)", KIT["span_m"], f"kit span ({KIT['name']}); R59 x 0.2 gives {2 * semi:.4f} m")
assert abs(b - 2 * semi) < 1e-6
ys = [r["station"] for r in WS] + [semi]
cs = [r["chord"] for r in WS] + [0.0]
les = [r["le"][0] for r in WS] + [g["hull"]["wing_tip"][0]]
zs = [r["mid"][2] for r in WS] + [WS[-1]["mid"][2]]
tcs = [r["thickness_ratio"] for r in WS] + [WS[-1]["thickness_ratio"]]
incs = median_filter([math.radians(r["incidence_deg"]) for r in WS]) + [math.radians(WS[-1]["incidence_deg"])]


def at(y, values):
    y = abs(y)
    if y <= ys[0]:
        return values[0]
    for k in range(len(ys) - 1):
        if ys[k] <= y <= ys[k + 1]:
            return values[k] + (values[k + 1] - values[k]) * (y - ys[k]) / (ys[k + 1] - ys[k])
    return values[-1]


chord = lambda y: at(y, cs)
N_INT = 2000
grid = [semi * (k + 0.5) / N_INT for k in range(N_INT)]
dy_int = semi / N_INT
integral = lambda f, lo=0.0, hi=None: sum(f(y) for y in grid if lo <= y <= (semi if hi is None else hi)) * dy_int
S_r59 = 2 * integral(chord)
S = note("reference", "S (m2)", FULL["wing_area_ft2"] * FT2 * AREA_SCALE, f"published 314 sq ft x 1/25 (F4U-01); the measured R59 planform integrates to {S_r59:.4f} m2 ({100 * (S_r59 / (FULL['wing_area_ft2'] * FT2 * AREA_SCALE) - 1):+.1f} %)")
c_ref = note("reference", "c_ref = S/b (m)", S / b, "v1 coefficient reference length (not the MAC)")
AR = note("reference", "AR = b2/S", b * b / S, "")
mac = note("reference", "MAC (m)", 2 / S_r59 * integral(lambda y: chord(y) ** 2), f"measured planform, (2/S) int c2 dy; NACA RM A7C05 94.00 in x 0.2 = {FULL['mac_in'] * IN * SCALE:.4f} m")
y_mac = note("reference", "MAC span station (m)", 2 / S_r59 * integral(lambda y: chord(y) * y), "")
mac_le_x = note("reference", "MAC leading edge (x_aft m)", 2 / S_r59 * integral(lambda y: chord(y) * at(y, les)), "chord-weighted leading edge")
# Equivalent trapezoid of the same area and MAC: the loader's planform fields and equal-area strips use it.
ratio = mac / c_ref
aq, bq = 1 - 0.75 * ratio, 1 - 1.5 * ratio
lam = (-bq - math.sqrt(bq * bq - 4 * aq * aq)) / (2 * aq)
cr = 2 * c_ref / (1 + lam)
ct = lam * cr
note("reference", "equivalent trapezoid root, tip (m), taper", [cr, ct, lam], "same S and MAC as the measured planform; measured root chord " + f"{WS[0]['chord']:.4f} m (NACA 105 in x 0.2 = {FULL['root_chord_in'] * IN * SCALE:.4f})")
qc = lambda y: at(y, les) + 0.25 * chord(y)
hc = lambda y: at(y, les) + 0.5 * chord(y)
sweep_hc = note("reference", "half-chord sweep (deg)", math.degrees(math.atan2(hc(0.8 * semi) - hc(0.2 * semi), 0.6 * semi)), "measured, 20-80 % semi-span")
sweep_hc = math.radians(sweep_hc)
i_w = note("aero", "mean wing incidence (deg)", math.degrees(2 / S_r59 * integral(lambda y: chord(y) * at(y, incs))), "chord-weighted, median-filtered R59 station incidence relative to the thrust line; no primary source (NACA OCR lost it)")
i_w = math.radians(i_w)
tc_mean = 2 / S_r59 * integral(lambda y: chord(y) * at(y, tcs))
note("aero", "chord-weighted thickness ratio", tc_mean, "measured sections (NACA 23018 root to 23009 tip)")

# Gull dihedral: chord-plane slope, smoothed over +-0.04 m; area-weighted cos2 for the projected lift slope.
def dihedral(y):
    h = 0.04
    y0, y1 = max(0.0, y - h), min(semi - 0.02, y + h)
    return math.atan2(at(y1, zs) - at(y0, zs), y1 - y0)


cos2_gamma = note("aero", "area-weighted cos2(dihedral)", 2 / S_r59 * integral(lambda y: chord(y) * math.cos(dihedral(y)) ** 2), "projected lift of the gull panels")
gamma_inner = math.degrees(dihedral(0.2))
gamma_outer = math.degrees(dihedral(0.8))
note("aero", "local dihedral at y 0.20 / 0.80 m (deg)", [gamma_inner, gamma_outer], "inverted gull: anhedral inboard, dihedral outboard (F4U-06)")

# --- Sections: XFOIL 230-series, interpolated in thickness and log Reynolds number --------------------------------
POL = SEC["polars"]
CORR = SEC["xfoil_corrections"]
TC_OF = {"NACA 23012": 0.12, "NACA 23015": 0.15, "NACA 23018": 0.18}


def section(key, tc, re):
    tc = min(max(tc, 0.12), 0.18)
    lre = math.log10(min(max(re, 5e5), 1e6))
    by_tc = {}
    for p in POL:
        by_tc.setdefault(TC_OF[p["airfoil"]], {})[math.log10(p["reynolds"])] = p[key]
    rows = []
    for t in sorted(by_tc):
        lo, hi = by_tc[t][math.log10(5e5)], by_tc[t][math.log10(1e6)]
        rows.append((t, lo + (hi - lo) * (lre - math.log10(5e5)) / (math.log10(1e6) - math.log10(5e5))))
    return lerp_table(rows, tc)


V_cruise_guess = 25.0
re_mac = V_cruise_guess * mac / NU
cla_xfoil = 2 / S_r59 * integral(lambda y: chord(y) * section("cl_alpha_per_rad", at(y, tcs), V_cruise_guess * chord(y) / NU))
kappa = note("aero", "section lift slope / 2pi", CORR["lift_slope_factor"] * cla_xfoil / (2 * math.pi), f"chord-weighted XFOIL {cla_xfoil:.3f}/rad at 25 m/s x {CORR['lift_slope_factor']} ({CORR['source'].split(':')[0]})")
alpha0 = note("aero", "wing zero-lift angle (deg)", 2 / S_r59 * integral(lambda y: chord(y) * section("alpha0_deg", at(y, tcs), V_cruise_guess * chord(y) / NU)), "XFOIL 230-series, chord-weighted; thin-airfoil theory for the 230 mean line gives about -1.2 deg")
cm_ac = note("aero", "section Cm_ac", 2 / S_r59 * integral(lambda y: chord(y) * section("cm", at(y, tcs), V_cruise_guess * chord(y) / NU)), "XFOIL 230-series moment over CL 0-0.6, chord-weighted: the forward-camber family has almost no pitching moment")

# --- Fuselage ------------------------------------------------------------------------------------------------------
FS = g["fuselage_stations"]
nose_x = g["nose"]["spinner_tip"][0]
tail_x = g["hull"]["tail_end"][0]
fus_len = note("fuselage", "length, spinner tip to tail cone (m)", tail_x - nose_x, f"R59 x 0.2; FokkeRC kit length {KIT['length_m']} m; full-size 33.3 ft x 0.2 = {33.3 * 12 * IN * SCALE:.4f} m")
fus_w = 2 * max(s["half_width"] for s in FS)
fus_d = max(s["top"] - s["bottom"] for s in FS)
note("fuselage", "max width, depth (m)", [fus_w, fus_d], "fuselage and cowl stations")
side_area = sum((s1["x"] - s0["x"]) * 0.5 * ((s0["top"] - s0["bottom"]) + (s1["top"] - s1["bottom"])) for s0, s1 in zip(FS, FS[1:]))
note("fuselage", "side area (m2)", side_area, "integrated stations")


def fus_top(x):
    for s0, s1 in zip(FS, FS[1:]):
        if s0["x"] <= x <= s1["x"]:
            return s0["top"] + (s1["top"] - s0["top"]) * (x - s0["x"]) / (s1["x"] - s0["x"])
    return FS[-1]["top"]


# --- Horizontal tail: NACA areas, measured layout ------------------------------------------------------------------
SS = g["stabilizer_sections"]
hs = g["hull"]["stab_tip"][1]
Sh = note("tail", "Sh (m2)", FULL["horizontal_tail_area_ft2"] * FT2 * AREA_SCALE, f"NACA RM A7C05 55.9 sq ft x 1/25; R59 measures {2 * sum(0.5 * (a['chord'] + c['chord']) * (c['station'] - a['station']) for a, c in zip(SS, SS[1:])):.4f} m2")
bh = 2 * hs
AR_h = bh * bh / Sh
mach_h = sum(r["chord"] ** 2 for r in SS) / sum(r["chord"] for r in SS)
xh_ac = sum((r["le"][0] + 0.25 * r["chord"]) * r["chord"] for r in SS) / sum(r["chord"] for r in SS)
zh = sum(r["mid"][2] * r["chord"] for r in SS) / sum(r["chord"] for r in SS)
note("tail", "horizontal ac (x_aft, z_up m)", [xh_ac, zh], "chord-weighted quarter chord of the measured stabilizer")
cf_e = note("tail", "elevator chord fraction (aft of hinge)", FULL["elevator_area_aft_of_hinge_ft2"] / FULL["horizontal_tail_area_ft2"], f"NACA area ratio 21.9/55.9; {FULL['elevator_balance_area_ft2']} sq ft balance ahead of the hinge")
crh = SS[0]["chord"]

# --- Vertical tail: NACA area, measured fin above the fuselage ------------------------------------------------------
FN = g["fin_sections"]
fin_exposed = [r for r in FN if r["station"] >= fus_top(r["le"][0] + 0.5 * r["chord"])]
Sv = note("tail", "Sv (m2)", FULL["vertical_tail_area_ft2"] * FT2 * AREA_SCALE, "NACA RM A7C05 22.0 sq ft x 1/25 (measured fin agrees when cut at the fuselage top, F4U-06)")
fin_root_z = fin_exposed[0]["station"]
fin_top_z = g["hull"]["fin_top"][2]
h_v = note("tail", "fin height above the fuselage (m)", fin_top_z - fin_root_z, "")
fin_cz = sum(r["station"] * r["chord"] for r in fin_exposed) / sum(r["chord"] for r in fin_exposed)
xv_ac = sum((r["le"][0] + 0.25 * r["chord"]) * r["chord"] for r in fin_exposed) / sum(r["chord"] for r in fin_exposed)
note("tail", "fin ac (x_aft, z_up m)", [xv_ac, fin_cz], "chord-weighted quarter chord of the exposed fin")
cf_r = note("tail", "rudder chord fraction (aft of hinge)", FULL["rudder_area_aft_of_hinge_ft2"] / FULL["vertical_tail_area_ft2"], "NACA area ratio 13.0/22.0")

# --- CG from the reference setup -----------------------------------------------------------------------------------
x_cg_target = note("balance", "CG (x_aft m)", REFSET["cg_aft_of_wing_le_at_fuselage_mm"] / 1000 * REFSET["length_ratio_to_1_5"], f"{REFSET['name']}: {REFSET['cg_aft_of_wing_le_at_fuselage_mm']:.0f} mm behind the wing leading edge at the fuselage, x {REFSET['length_ratio_to_1_5']:.5f} to 1/5; the leading edge is straight inboard (x 0 at the root)")
cg_mac = note("balance", "CG (% MAC)", 100 * (x_cg_target - mac_le_x) / mac, "")
cg_mac /= 100

# --- Lift slopes, downwash, neutral point --------------------------------------------------------------------------
GE = load_json(GE_FILE)
CLa_w = note("aero", "CLa wing (1/rad)", helmbold(AR, kappa, sweep_hc) * cos2_gamma, "Helmbold/DATCOM x area-weighted cos2(gull dihedral)")
CLa_h = note("aero", "CLa horizontal (1/rad)", helmbold(AR_h, 0.9), f"Helmbold, AR {AR_h:.2f}")
eta_h = note("aero", "tail dynamic pressure ratio", 0.9, "estimated baseline; the runtime adds the propeller slipstream separately")
deps = note("aero", "d(eps)/d(alpha)", GE["free_air"]["tail_downwash_per_CL"] * CLa_w, f"F4U-07 VLM tail downwash per unit wing CL {GE['free_air']['tail_downwash_per_CL']:.4f} rad x CLa_w; the elliptic estimate 2 CLa_w/(pi AR) gives {2 * CLa_w / (math.pi * AR):.3f}")
slope_h = note("aero", "effective tail slope (1/rad)", CLa_h * eta_h * (1 - deps), "CLa_h eta (1 - deps/dalpha)")
CLa = note("aero", "CLa airplane (1/rad)", CLa_w + slope_h * Sh / S, "wing + tail")
x_ac_w = mac_le_x + 0.25 * mac
x_qc_root = (qc(0.0) - nose_x) / fus_len
# Neutral-point target, stick-fixed and power-off like the simulator's static stability: the NACA F4U-4 stick-free,
# power-on point plus the XP-51's measured power shift (glide 34.2 vs cruise 30.8 % MAC, both stick-fixed) plus the
# middle of a 2-5 % MAC stick-free allowance.
NP_POWER_SHIFT, NP_FREE_SHIFT = 0.034, 0.035
NP_TARGET = FULL["neutral_point_stick_free_power_on_mac"]["flaps_gear_up"] + NP_POWER_SHIFT + NP_FREE_SHIFT


def neutral_point(k_f):
    dx = k_f * fus_w ** 2 * fus_len / (mac * S) * 180 / math.pi / CLa_w * mac
    x_a = x_ac_w - dx
    cma = -slope_h * Sh / S * (xh_ac - x_a) / c_ref
    return x_a - cma / CLa * c_ref, x_a, dx


lo_k, hi_k = 0.0, 0.1
for _ in range(80):
    mid_k = 0.5 * (lo_k + hi_k)
    lo_k, hi_k = (mid_k, hi_k) if neutral_point(mid_k)[0] > mac_le_x + NP_TARGET * mac else (lo_k, mid_k)
K_FUS = note("aero", "K_fus (per deg)", 0.5 * (lo_k + hi_k), f"CALIBRATED hypothesis: puts the stick-fixed power-off neutral point at {100 * NP_TARGET:.1f} % MAC = NACA RM A7C05 30 % (stick-free, power on, F4U-4) + {100 * NP_POWER_SHIFT:.1f} % power shift (XP-51, NACA 19930092575, as the P-51 calibration) + {100 * NP_FREE_SHIFT:.1f} % stick-free allowance (estimated, 2-5 %). Raymer Fig. 16.14 gives about 0.007 for a wing root quarter chord at {100 * x_qc_root:.0f} % of the body; the P-51's calibration also needed several times Raymer (0.033)")
_, x_arp, dx_f = neutral_point(K_FUS)
x_arp = note("aero", "wing-body ac = ARP (x_aft m)", x_arp, f"wing ac at 25 % MAC {x_ac_w:.4f} moved {dx_f * 1000:.1f} mm forward by the calibrated fuselage, cowl and propeller term")
arp_z = WS[0]["mid"][2]
l_h = xh_ac - x_arp
Cma = note("aero", "Cma about ARP (1/rad, c_ref)", -slope_h * Sh / S * l_h / c_ref, "tail only: the ARP is the wing-body ac")
x_np = x_arp - Cma / CLa * c_ref
np_mac = note("aero", "stick-fixed power-off neutral point (% MAC)", 100 * (x_np - mac_le_x) / mac, f"the calibration target; uncalibrated Raymer K_fus 0.007 gives {100 * (neutral_point(0.007)[0] - mac_le_x) / mac:.1f} %")
sm = note("aero", "static margin at the CG (% MAC)", np_mac - 100 * cg_mac, "")
CL0_w = CLa_w * (i_w - math.radians(alpha0))
eps0 = GE["free_air"]["tail_downwash_per_CL"] * CL0_w
i_h = math.radians(1.25)
inc_eff = note("aero", "tail effective incidence (rad)", (i_h - eps0) / (1 - deps), "(i_h - eps0)/(1 - deps/dalpha), stabilizer 1.25 deg (NACA RM A7C05; reference line taken as the thrust line); R59 models 0 deg. Not calibrated to trim data")
CL0 = note("aero", "CL0", CL0_w + slope_h * Sh / S * inc_eff, "wing at its mean incidence with camber + tail at zero body alpha")
Cm0 = note("aero", "Cm0 about ARP", cm_ac * mac / c_ref - slope_h * Sh / S * l_h / c_ref * inc_eff, "section Cm_ac + tail at zero body alpha")

# --- Controls: Phoenix reference throws on this airframe's surface chords -------------------------------------------
SURF = g["surfaces"]
ail = SURF["aileron_right"]
y1a, y2a = ail["span"]
A_ail = FULL["aileron_area_aft_of_hinge_both_ft2"] / 2 * FT2 * AREA_SCALE
cf_a = note("controls", "aileron chord fraction (aft of hinge)", A_ail / integral(chord, y1a, y2a), f"NACA 18.1 sq ft (both) x 1/25 over the wing area of the measured aileron span {y1a:.3f}-{y2a:.3f} m")
flap_spans = [SURF[k]["span"] for k in ("flap_right_1", "flap_right_2", "flap_right_3")]
y1f, y2f = flap_spans[0][0], flap_spans[-1][1]
A_flap = FULL["flap_area_total_ft2"] / 2 * FT2 * AREA_SCALE
cf_f = note("controls", "flap chord fraction", A_flap / integral(chord, y1f, y2f), f"NACA 36.4 sq ft (both) x 1/25 over the measured flap span {y1f:.3f}-{y2f:.3f} m (three panels)")
k_ratio = REFSET["length_ratio_to_1_5"]


def throw_deg(mm, surface_chord):
    return math.degrees(math.asin(min(1.0, mm / 1000 * k_ratio / surface_chord)))


chord_ail = cf_a * chord(y1a)
chord_elev = cf_e * crh
chord_rud = cf_r * max(r["chord"] for r in fin_exposed)
chord_flap = cf_f * chord(y1f)
TH = REFSET["throws_mm"]
throws = {
    "aileron": throw_deg(TH["aileron"]["high"], chord_ail),
    "elevator": throw_deg(TH["elevator"]["high"], chord_elev),
    "rudder": throw_deg(TH["rudder"]["high"], chord_rud),
}
low = {
    "aileron": throw_deg(TH["aileron"]["low"], chord_ail),
    "elevator": throw_deg(TH["elevator"]["low"], chord_elev),
    "rudder": throw_deg(TH["rudder"]["low"], chord_rud),
}
THROW_SRC = f"{REFSET['name']} manual (high/low mm, {REFSET['url']}), x {k_ratio:.4f} to 1/5, converted with this airframe's surface chord at its inboard end (aileron {chord_ail:.3f}, elevator {chord_elev:.3f}, rudder {chord_rud:.3f} m; NACA area fractions): the measuring station is not stated"
for k in throws:
    note("controls", f"{k} high / low (deg)", [throws[k], low[k]], "")
flap_settings = {"take_off": throw_deg(TH["flaps"]["take_off"], chord_flap), "landing": throw_deg(TH["flaps"]["landing"], chord_flap)}
note("controls", "flap take-off / landing (deg)", [flap_settings["take_off"], flap_settings["landing"]], f"Phoenix 15 / 25 mm on a flap chord of {chord_flap:.3f} m")
k_flap = note("controls", "flap effectiveness correction", 0.8, "estimated (DATCOM range 0.6-0.9), as the P-51")
tau_e = flap_tau(cf_e) * k_flap
ce_h = note("controls", "elevator effectiveness (local)", tau_e / (1 - deps), f"tau {tau_e:.3f} / (1 - deps/dalpha)")
CLde = note("aero", "CLde (1/rad)", slope_h * ce_h * Sh / S, "")
Cmde = note("aero", "CMde (1/rad)", -CLde * l_h / c_ref, "")
tau_a = flap_tau(cf_a) * k_flap
CLda_each = CLa_w * tau_a * integral(chord, y1a, y2a) / S
Clda = -CLa_w * tau_a * integral(lambda y: chord(y) * y, y1a, y2a) / (S * b)
note("aero", "Clda_right (1/rad)", Clda, "strip theory over the measured aileron span and chord")

# --- Inventory (le frame) ------------------------------------------------------------------------------------------
NOSE = g["nose"]
GW = g["gear"]["wheels"]
spinner_back = NOSE["spinner_back_x"]
rc_fw = spinner_back + 0.25
cp_z = arp_z
FUEL_BLEND = "gasoline_premix_40_1"
TANK_L = KIT["fuel_tank_l"]
FUEL_KG = TANK_L * 1e-3 * fuel_registry.blend_density(FUEL_BLEND) * 0.5
mejz = load_json(MEJZ)
prop_rec = mejz["props"][KIT["propeller"]["table_key"]]
aileron_mid = 0.5 * (y1a + y2a)
flap_mid = 0.5 * (y1f + y2f)
wing_z_mac = at(y_mac, zs)
ENERGY_SOURCES = {"fuel (half tank)": "gasoline"}
E = KIT["engine"]
items = [
    ("engine DLE-111", E["mass_engine_kg"], "manual", E["sources"], [spinner_back + 0.12, 0.0, 0.0], [0.15, 0.32, 0.15], "estimated", "crankshaft on the thrust line, crankcase ~0.12 m behind the spinner back (boxer twin)", "engine_main"),
    ("ignition module and two canister mufflers", E["mass_with_ignition_and_mufflers_kg"] - E["mass_engine_kg"], "manual", "Lindinger: 2690 g total less the 2370 g engine", [spinner_back + 0.20, 0.0, -0.06], [0.22, 0.22, 0.08], "estimated", "inside the radial cowl below the cylinders", "muffler_pair"),
    ("propeller Mejzlik 26x12 3-blade", prop_rec["mass_kg"], "manual", f"Mejzlik datasheet mass ({prop_rec['url']})", [NOSE["propeller_plane"][0], 0.0, 0.0], [0.02, 26 * IN, 26 * IN], "measured", "propeller plane of the R59 nose (geometry-r59.json)", "propeller_main"),
    ("spinner and hub", 0.15, "estimated", "small aluminium hub cap, as the F4U-1D's", [spinner_back - 0.04, 0.0, 0.0], [0.10, 0.09, 0.09], "measured", "R59 spinner", "spinner_main"),
    ("engine standoffs, mount and bolts", 0.25, "estimated", "aluminium standoffs on a plywood firewall", [rc_fw - 0.03, 0.0, 0.0], None, "estimated", "the model's firewall: spinner back + 0.25 m", "engine_mount"),
    ("cowl (composite, 297 mm)", 0.50, "estimated", "FokkeRC composite cowl, 297 mm diameter", [0.5 * (NOSE["cowl_front_x"] + NOSE["cowl_rear_x"]), 0.0, 0.0], [NOSE["cowl_rear_x"] - NOSE["cowl_front_x"], 2 * NOSE["cowl_half_width"], 2 * NOSE["cowl_half_width"]], "measured", "R59 cowl", "cowl_main"),
    ("fuel tank 1 l (empty) with lines", 0.20, "estimated", "gasoline tank with clunk and lines", [rc_fw + 0.10, 0.0, -0.02], None, "estimated", "behind the firewall", "fuel_tank"),
    ("fuel (half tank)", FUEL_KG, "derived", f"half of the {TANK_L:.1f} l tank x {fuel_registry.blend_source(FUEL_BLEND)} (registry 40:1 premix; DLE asks for 30:1, a negligible density difference)", [rc_fw + 0.10, 0.0, -0.02], [0.16, 0.10, 0.0625], "estimated", "uniform liquid box in the tank", "fuel_flight"),
    ("ignition battery 2S LiFe", 0.15, "estimated", "1500-2100 mAh LiFe pack", [rc_fw + 0.03, 0.0, -0.08], None, "estimated", "below the tank", "ignition_battery"),
    ("receiver batteries 2S LiFe (2)", 0.30, "estimated", "two 2100 mAh LiFe packs (redundant)", [rc_fw + 0.06, 0.0, -0.09], None, "estimated", "forward fuselage floor", "receiver_batteries"),
    ("receiver, switches, power distribution", 0.12, "estimated", "receiver, two switches, harnesses", [0.30, 0.0, -0.05], None, "estimated", "under the cockpit floor", "receiver_radio"),
    ("retract air tank, valve and lines", 0.20, "estimated", "pneumatic Robart retracts need an air tank, valve and lines", [0.25, 0.0, -0.08], None, "estimated", "fuselage floor near the wing", "retract_air"),
    ("aileron servo left", 0.08, "estimated", "20-25 kg cm class servo", [0.5 * chord(aileron_mid), -aileron_mid, at(aileron_mid, zs)], [0.03, 0.04, 0.02], "estimated", "aileron span midpoint", "servo_aileron_left"),
    ("aileron servo right", 0.08, "estimated", "20-25 kg cm class servo", [0.5 * chord(aileron_mid), aileron_mid, at(aileron_mid, zs)], [0.03, 0.04, 0.02], "estimated", "aileron span midpoint", "servo_aileron_right"),
    ("flap servo left", 0.08, "estimated", "one servo per side for the three panels", [0.6 * chord(flap_mid), -flap_mid, at(flap_mid, zs)], [0.03, 0.04, 0.02], "estimated", "flap span midpoint", "servo_flap_left"),
    ("flap servo right", 0.08, "estimated", "one servo per side for the three panels", [0.6 * chord(flap_mid), flap_mid, at(flap_mid, zs)], [0.03, 0.04, 0.02], "estimated", "flap span midpoint", "servo_flap_right"),
    ("elevator servos (2)", 0.16, "estimated", "two tail servos", [xh_ac - 0.10, 0.0, zh], [0.05, 0.25, 0.03], "estimated", "stabilizer root", "servo_elevator"),
    ("rudder servo and pull-pull", 0.10, "estimated", "one servo with cables", [0.60, 0.0, -0.02], None, "estimated", "aft of the cockpit", "servo_rudder"),
    ("throttle, choke servos and linkage", 0.08, "estimated", "two small servos", [rc_fw + 0.05, 0.0, 0.02], None, "estimated", "behind the firewall", "servo_throttle_choke"),
    ("main gear assembly left", 0.75, "estimated", "Robart #150 rotating retract, strut, wheel and door (estimated)", [GW["main_left"]["centre_down"][0], GW["main_left"]["centre_down"][1], 0.5 * (GW["main_left"]["centre_down"][2] + at(abs(GW["main_left"]["centre_down"][1]), zs))], [0.10, 0.08, 0.30], "measured", "R59 main wheel centre and wing chord plane", "gear_main_left"),
    ("main gear assembly right", 0.75, "estimated", "Robart #150 rotating retract, strut, wheel and door (estimated)", [GW["main_right"]["centre_down"][0], GW["main_right"]["centre_down"][1], 0.5 * (GW["main_right"]["centre_down"][2] + at(abs(GW["main_right"]["centre_down"][1]), zs))], [0.10, 0.08, 0.30], "measured", "R59 main wheel centre and wing chord plane", "gear_main_right"),
    ("tail wheel assembly (retractable)", 0.20, "estimated", "Robart #160 1/5 tail retract", [GW["tail"]["centre_down"][0], 0.0, GW["tail"]["centre_down"][2] + 0.04], None, "measured", "R59 tail wheel", "gear_tail"),
    ("wing panel, left, sheeted, with flaps and aileron", 2.20, "estimated", "built-up sheeted wing half of a 2.5 m warbird with retract bays", [mac_le_x + 0.42 * mac, -y_mac, wing_z_mac], [mac, semi, 0.07], "derived", "42 % MAC at the MAC station", "wing_left"),
    ("wing panel, right, sheeted, with flaps and aileron", 2.20, "estimated", "same as the left panel", [mac_le_x + 0.42 * mac, y_mac, wing_z_mac], [mac, semi, 0.07], "derived", "42 % MAC at the MAC station", "wing_right"),
    ("wing tube and bolts", 0.35, "estimated", "aluminium or carbon wing joiner", [0.20, 0.0, arp_z], [0.04, 0.6, 0.04], "estimated", "main spar", "wing_joiner"),
    ("fuselage front (firewall to cockpit rear), covered", 1.70, "estimated", "lite-ply/balsa box with doublers, glassed", [0.25, 0.0, 0.0], [1.0, fus_w, fus_d], "estimated", "from the stations", "fuselage_front"),
    ("fuselage rear, turtle deck and tail cone", 0.95, "estimated", "balsa sides and stringered deck", [1.10, 0.0, 0.02], [0.9, 0.18, 0.2], "estimated", "from the stations", "fuselage_rear"),
    ("canopy, frame and pilot", 0.35, "estimated", "Lexan canopy, composite frame, pilot bust", list(g["canopy_top"][:2]) + [g["canopy_top"][2] - 0.05], None, "measured", "R59 canopy", "canopy_pilot"),
    ("stabilizer and elevator, covered", 0.60, "estimated", "sheeted built-up stab", [xh_ac + 0.15 * mach_h, 0.0, zh], [crh, bh, 0.025], "measured", "R59 stabilizer", "horizontal_tail"),
    ("fin and rudder, covered", 0.30, "estimated", "sheeted built-up fin", [xv_ac + 0.1, 0.0, fin_cz], [0.3, 0.02, h_v], "derived", "exposed fin centroid", "vertical_tail"),
    ("pushrods, horns, cowl fasteners, hardware", 0.35, "estimated", "rough sum", [0.60, 0.0, 0.0], None, "estimated", "spread along the fuselage", "control_hardware"),
]
FLIGHT_MASS = KIT["flying_mass_kg"]["target"]
STRUCTURE = ("wing panel", "wing tube", "fuselage", "canopy", "stabilizer", "fin and rudder", "cowl", "pushrods")
is_structure = lambda it: any(it[0].startswith(s) for s in STRUCTURE)
is_fuel = lambda it: it[0] == "fuel (half tank)"
k_total_struct = 1.0
nose_ballast_x, tail_ballast_x = spinner_back - 0.02, xh_ac - 0.05
for _ in range(40):
    base = sum(i[1] for i in items if not is_fuel(i))
    m_cg = sum(i[1] * i[4][0] for i in items if not is_fuel(i)) / base
    xb_ = nose_ballast_x if m_cg > x_cg_target else tail_ballast_x
    total = base + base * (x_cg_target - m_cg) / (xb_ - x_cg_target) + FUEL_KG
    k_struct = 1 + (FLIGHT_MASS - total) / sum(i[1] for i in items if is_structure(i))
    items = [(i[0], i[1] * k_struct) + i[2:] if is_structure(i) else i for i in items]
    k_total_struct *= k_struct
    if abs(FLIGHT_MASS - total) < 1e-7:
        break
note("balance", "airframe scale factor", k_total_struct, f"airframe items scaled so the flight mass is {FLIGHT_MASS} kg")
mass0 = sum(i[1] for i in items if not is_fuel(i))
x_cg0 = sum(i[1] * i[4][0] for i in items if not is_fuel(i)) / mass0
nose = x_cg0 > x_cg_target
xb = nose_ballast_x if nose else tail_ballast_x
mb = mass0 * (x_cg_target - x_cg0) / (xb - x_cg_target)
note("balance", "balancing mass (kg)", mb, ("nose" if nose else "tail") + " weight of the virtual reference build")
items.append(("virtual reference-build balancing mass", mb, "derived", D("m = M (x_CG - x0) / (x_ballast - x_CG) for the reference balance point; a virtual reference build, NOT measured hardware or a ballast recommendation"),
              [xb, 0.0, 0.0], [0.04, 0.04, 0.04], "estimated", "behind the spinner backplate" if nose else "tail post", "ballast_reference"))
dry_mass = mass0 + mb
dry_cg = [sum(i[1] * i[4][k] for i in items if not is_fuel(i)) / dry_mass for k in range(3)]
dry_cg[1] = 0.0
mass = sum(i[1] for i in items)
cg = [sum(i[1] * i[4][k] for i in items) / mass for k in range(3)]
cg[1] = 0.0
note("balance", "flight mass (kg), CG (le m)", [mass] + cg, f"dry {dry_mass:.3f} kg; range {KIT['flying_mass_kg']['range']}")


def inertia(pt):
    j = [0.0] * 6
    for it in items:
        m, p, s = it[1], it[4], it[5] or [0, 0, 0]
        x, y, z = -(p[0] - pt[0]), p[1] - pt[1], -(p[2] - pt[2])
        j[0] += m * (y * y + z * z) + m * (s[1] ** 2 + s[2] ** 2) / 12
        j[1] += m * (x * x + z * z) + m * (s[0] ** 2 + s[2] ** 2) / 12
        j[2] += m * (x * x + y * y) + m * (s[0] ** 2 + s[1] ** 2) / 12
        j[3] -= m * x * y
        j[4] -= m * x * z
        j[5] -= m * y * z
    return j


note("balance", "Jxx Jyy Jzz Jxy Jxz Jyz (kg m2)", inertia(cg), "component envelopes + parallel axis")

# --- Spanwise stall: equal-area strips of the equivalent trapezoid, measured chord/thickness/Re in each -------------
n_strips = 3  # physics/aero.gd WING_STATIONS_PER_SIDE
edges_eta = [0.0]
for k in range(1, n_strips):
    target = (cr + ct) / 2 * k / n_strips
    a2 = (ct - cr) / 2
    edges_eta.append((-cr + math.sqrt(cr * cr + 4 * a2 * target)) / (2 * a2))
edges_eta.append(1.0)
schrenk = lambda y: 0.5 * (chord(y) + 4 * S_r59 / (math.pi * b) * math.sqrt(max(1 - (y / semi) ** 2, 0.0))) / max(chord(y), 1e-6)
strips = []
V_stall_guess = 14.0
for _ in range(5):
    strips = []
    for e0, e1 in zip(edges_eta, edges_eta[1:]):
        lo_y, hi_y = e0 * semi, e1 * semi
        w = integral(chord, lo_y, hi_y)
        y_c = integral(lambda y: chord(y) * y, lo_y, hi_y) / w
        c_c = w / (hi_y - lo_y)
        tc_c = integral(lambda y: chord(y) * at(y, tcs), lo_y, hi_y) / w
        re_c = V_stall_guess * c_c / NU
        clmax_c = section("clmax", tc_c, re_c) - CORR["clmax_decrement"]
        load = integral(lambda y: chord(y) * schrenk(y), lo_y, hi_y) / w
        twist_c = integral(lambda y: chord(y) * at(y, incs), lo_y, hi_y) / w
        strips.append({"y": y_c, "chord": c_c, "tc": tc_c, "re": re_c, "clmax": clmax_c, "load": load, "twist": twist_c, "cl_star": clmax_c / load})
    CL_max = sum(s_["cl_star"] for s_ in strips) / n_strips
    V_stall_guess = math.sqrt(2 * mass * G0 / (RHO * S * CL_max))
twist_mean = sum(s_["twist"] for s_ in strips) / n_strips
strip_inc = [(s_["twist"] - twist_mean) + (CL_max - s_["cl_star"]) / CLa_w for s_ in strips]
for i, s_ in enumerate(strips):
    note("stall", f"strip {i + 1}: y, chord, t/c, Re, clmax, cl/CL, CL*", [s_["y"], s_["chord"], s_["tc"], s_["re"], s_["clmax"], s_["load"], s_["cl_star"]], "")
note("stall", "strip incidence offsets root to tip (deg)", [math.degrees(x) for x in strip_inc], "measured twist + Schrenk/Re stall order; the most positive strip stalls first")
CL_max = note("aero", "CL_max", CL_max, "mean of three equal-area strip limits: Schrenk loading on the measured chord, XFOIL 230-series clmax(t/c, Re) less the stated decrement")
Vs = note("aero", "1-g stall (m/s)", math.sqrt(2 * mass * G0 / (RHO * S * CL_max)), "flight mass, CL_max")
V_start = note("aero", "start speed (m/s)", round(1.6 * Vs), "1.6 x the 1-g stall, rounded")
CL_ref = note("aero", "CL_ref", mass * G0 / (0.5 * RHO * V_start ** 2 * S), "level flight at the start speed")

# --- Lateral-directional --------------------------------------------------------------------------------------------
l_v = xv_ac - cg[0]
z_v = fin_cz - cg[2]
AR_v = note("lateral", "fin effective AR", 1.55 * h_v * h_v / Sv, "geometric x 1.55 end-plate factor (DATCOM 1.4-1.7)")
fus_mid = next(s_ for s_ in FS if s_["x"] >= 0.3 * cr)
z_w = arp_z - 0.5 * (fus_mid["top"] + fus_mid["bottom"])
sidewash = note("lateral", "(1 + dsigma/dbeta) eta_v", 0.724 + 3.06 * (Sv / S) / 2 + 0.4 * (-z_w) / fus_d + 0.009 * AR, "Nelson/DATCOM; z_w down positive (low wing root)")
slope_v = note("lateral", "effective fin slope (1/rad)", helmbold(AR_v, 0.9) * sidewash, "")
tau_r = flap_tau(cf_r) * k_flap
ce_v = note("lateral", "rudder effectiveness (local)", tau_r / sidewash, f"tau {tau_r:.3f} / sidewash")
CYb_v = -slope_v * Sv / S
CYb_B = note("lateral", "CYb body (1/rad)", -2 * 1.3 * 0.8 * fus_w * fus_d / S, "-2 K_i S0/S, K_i 1.3 low wing (DATCOM), S0 0.8 w d")
crossflow = note("lateral", "body crossflow drag area (m2)", 0.65 * 1.4 * side_area, "Allen-Perkins eta 0.65 x c_d 1.4 x side area, as the Extra (EX-14d)")
arm_v_arp = xv_ac - x_arp
CYdr = slope_v * Sv / S * ce_v
Cnb_fin = slope_v * Sv / S * arm_v_arp / b
Cnb_body = note("lateral", "Cnb body (1/rad)", -0.001 * 1.4 * 57.3 * (side_area / S) * (fus_len / b), "DATCOM -K_N K_Rl (S_side/S)(L/b), K_N 0.001/deg, K_Rl 1.4: estimated and NOT calibrated (the P-51's flight calibration needed more than DATCOM; the radial cowl suggests the same)")
Cndr = -CYdr * arm_v_arp / b
Cldr = CYdr * (fin_cz - arp_z) / b
Clb_dihedral = note("lateral", "Clb gull dihedral (1/rad)", -2 * CLa_w / (S * b) * integral(lambda y: chord(y) * math.sin(dihedral(y)) * y), "strip integral over the measured local dihedral (anhedral inboard, dihedral outboard)")
dihedral_low = note("lateral", "Clb low-wing interference (1/rad)", 1.2 * math.sqrt(AR) * (-z_w / b) * (2 * fus_d / b), "DATCOM, destabilizing for a low wing root")
Clb_wing = note("lateral", "Clb wing at CL_ref (1/rad)", -0.03 * CL_ref, "DATCOM Clb/CL for an unswept AR 5.4 wing (estimated, as the P-51)")
wing_body_cl = note("lateral", "wing-body Clb (1/rad)", Clb_dihedral + dihedral_low + Clb_wing, "carried by aero.surfaces.wing_body_cl_beta (D10-R5)")
Clb_fin = CYb_v * (fin_cz - arp_z) / b
Clp = (-4 * CLa_w / (S * b * b) * integral(lambda y: chord(y) * y * y)
       - eta_h * (CLa_h / 12) * (Sh / S) * (bh / b) ** 2 + 2 * CYb_v * (z_v / b) ** 2)
Clr = CL_ref / 4 - 2 * l_v * z_v / b ** 2 * CYb_v
Cnp = -CL_ref / 8 - 2 * l_v * z_v / b ** 2 * CYb_v
Cnr = -0.25 * 0.03 + 2 * (l_v / b) ** 2 * CYb_v - 0.02
CYp = 2 * CYb_v * z_v / b
CYr = -2 * CYb_v * l_v / b
Cnda = -2 * 0.15 * CL_ref * Clda
tail_q = CLa_h * eta_h * Sh / S
CLq = 2 * tail_q * l_h / c_ref + (0.5 + 2 * (cg[0] - x_ac_w) / mac) * CLa_w * mac / c_ref
Cmq = -2 * tail_q * (xh_ac - cg[0]) ** 2 / c_ref ** 2 * 1.1
CLadot = 2 * tail_q * l_h / c_ref * deps
th_a = math.acos(2 * cf_a - 1)
cp_frac = 0.25 + 0.5 * math.sin(th_a) * (1 - math.cos(th_a)) / (2 * (math.pi - th_a + math.sin(th_a)))
x_cp_ail = integral(lambda y: (at(y, les) + cp_frac * chord(y)) * chord(y), y1a, y2a) / integral(chord, y1a, y2a)
Cmda = -CLda_each * (x_cp_ail - x_arp) / c_ref
def station_centres(span, root, tip, n=3):
    """Area centroids of the loader's equal-area strips on a trapezoid (as the P-51)."""
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


wing_ail_eff = abs(Clda) * 6 * b / (CLa * sum(station_centres(b, cr, ct)))
pb2v = note("lateral", "steady pb/2V at full aileron (rad)", abs(2 * Clda * math.radians(throws["aileron"]) / Clp), f"check: NACA RM A7C05 full-size 0.064 at the full-size throw (not recovered); this is the RC high-rate throw of {throws['aileron']:.1f} deg")

# --- Drag build-up --------------------------------------------------------------------------------------------------
V = V_start
cf_mix = lambda L, lam_frac: lam_frac * 1.328 / math.sqrt(V * L / NU) + (1 - lam_frac) * 0.455 / math.log10(V * L / NU) ** 2.58
exposed_wing = S - fus_w * cr
parts = {
    "wing": cf_mix(mac, 0.3) * (1 + 0.6 / 0.4 * tc_mean + 100 * tc_mean ** 4) * 2.04 * exposed_wing,
    "tails": cf_mix(0.25, 0.3) * 1.10 * 2.03 * (Sh + Sv),
    "fuselage and radial cowl": cf_mix(fus_len, 0.1) * (1 + 60 / (fus_len / fus_d) ** 3 + (fus_len / fus_d) / 400) * (0.85 * 2 * (fus_w + fus_d) * fus_len) * 1.15,
    "gear down: wheels, struts, doors": 0.016,
    "engine cooling through the open cowl, exhausts": 0.008,
}
GEAR_CDA = note("drag", "gear drag area (m2)", 1.1 * parts["gear down: wheels, struts, doors"], "gear-down item x1.1, carried by the retractable-gear module, not CD0")
CD0 = note("drag", "CD0", (sum(parts.values()) - parts["gear down: wheels, struts, doors"]) * 1.1 / S, "gear UP; skin friction (30 % laminar on surfaces) x Raymer form factors, radial-cowl fuselage x1.15, cooling flow, x1.1 excrescences: " + ", ".join(f"{k} {v:.4f} m2" for k, v in parts.items()))
e_osw = note("drag", "Oswald e", 0.75, f"estimated as the P-51; the inviscid VLM of the gull planform gives {GE['free_air']['e_trefftz']:.3f}")
k_ind = 1 / (math.pi * e_osw * AR)

# --- Propeller: calibrated BEM for the Mejzlik 26x12 3-blade ---------------------------------------------------------
calib = load_json(CALIB)
PROP_D = KIT["propeller"]["diameter_in"] * IN
PROP_P = KIT["propeller"]["pitch_in"] * IN
# The BEM calibration was fitted with the P-51 blade planform; reuse it so the fitted factors stay valid.
PLANFORM = load_json(ROOT / "assets/aircraft/p51d-mustang-120/geometry.json")["propeller"]["blade"]["chord_fraction_of_radius"]
ct_table, cp_table = bem_tables(PROP_D, PROP_P, KIT["propeller"]["blades"], PLANFORM,
                                pitch_factor=calib["pitch_factor"], chord_factor=calib["chord_factor"], j_max=1.6)
Ct0, Cp0 = ct_table[0][1], cp_table[0][1]
mej_rows = list(zip(prop_rec["J"], prop_rec["Ct"], prop_rec["Cp"]))
bem_err = [abs(lerp_table(ct_table, J) - ct_) / max(ct_, 1e-3) for J, ct_, _ in mej_rows if ct_ > 0.01]
note("propulsion", "BEM vs Mejzlik 26x12 3B table: Ct0, Cp0, mean |dCt|/Ct", [Ct0, Cp0, sum(bem_err) / len(bem_err)], f"calibrated planform of the P-51 BEM (pitch x{calib['pitch_factor']:.3f}, chord x{calib['chord_factor']:.3f}); Mejzlik static Ct {prop_rec['Ct'][0]:.4f}, Cp {prop_rec['Cp'][0]:.4f}")

# --- Engine: generic two-stroke twin shape at the DLE-111 rating, installed derate borrowed from the P-51 ------------
TORQUE_SHAPE = [(0.0, 0.70), (0.2, 0.75), (0.4, 0.85), (0.6, 0.95), (0.75, 1.0), (0.9, 0.97), (1.0, 0.92), (1.1, 0.80), (1.25, 0.55), (1.4, 0.25)]
N_REF = E["power_rpm"]
shape = lambda rpm: lerp_table(TORQUE_SHAPE, rpm / N_REF)
P_rated = E["power_hp"] * 745.7
p51_data = load_json(ROOT / "app/data/aircraft/p51d_mustang_120.json")
p51_engine = p51_data["propulsion"]["engine"]
derate = max(r[1] for r in p51_engine["shaft"]["power_curve"]["value"]) / p51_engine["peak_power"]["value"]
note("propulsion", "installed/catalogue power ratio", derate, "BORROWED from the P-51 (DA-120 installed curve anchored on a reported 28x10 static rpm, over its 11.7 hp rating); no DLE-111 static-rpm record was found")
peak_shape = max(shape(r) * r for r in range(1000, 9001, 10))
Q0 = derate * P_rated / (2 * math.pi / 60 * peak_shape)
power_curve = [[float(r), Q0 * shape(r) * 2 * math.pi * r / 60] for r in range(1000, 9001, 500)]
P_peak = note("propulsion", "installed peak power (W)", max(p_[1] for p_ in power_curve), f"{E['power_hp']} hp ({P_rated:.0f} W) rating x {derate:.3f}")
FRICTION = [0.5, 0.14]
q_fric = lambda rpm: FRICTION[0] + FRICTION[1] * rpm / 1000
IDLE_RPM = E["idle_rpm"]
q_prop_static = lambda rpm: Cp0 * RHO * (rpm / 60) ** 2 * PROP_D ** 5 / (2 * math.pi)
idle_power = (q_prop_static(IDLE_RPM) + q_fric(IDLE_RPM)) * 2 * math.pi * IDLE_RPM / 60
peak_ind = max(p_[1] + q_fric(p_[0]) * 2 * math.pi * p_[0] / 60 for p_ in power_curve)
lo, hi = 1000.0, 9000.0
for _ in range(80):
    mid = 0.5 * (lo + hi)
    lo, hi = (mid, hi) if Q0 * shape(mid) > q_prop_static(mid) else (lo, mid)
rpm_static = note("propulsion", "static rpm", 0.5 * (lo + hi), "full-throttle torque meets the 3-blade's static torque")
thrust_static = Ct0 * RHO * (rpm_static / 60) ** 2 * PROP_D ** 4
note("propulsion", "static thrust (N, kgf), thrust/weight", [thrust_static, thrust_static / G0, thrust_static / (mass * G0)], f"check: the distributor claims {E['static_thrust_claim_kgf']} kgf static (propeller not named)")
rotor_j = note("propulsion", "rotating inertia (kg m2)", prop_rec["inertia_kgm2"] + 0.15 * 0.045 ** 2 / 2 + 0.002, "Mejzlik 26x12 3B datasheet estimate + hub cap + crank and flywheel 0.002 (estimated)")
plan_ = PLANFORM
sigma = KIT["propeller"]["blades"] * calib["chord_factor"] * sum(0.5 * (a[1] + c_[1]) * (c_[0] - a[0]) for a, c_ in zip(plan_, plan_[1:])) / math.pi
a_bl, cd_bl = 0.9 * 2 * math.pi, 0.02
nf_rows, pm_rows = [], []
for J_, ct_ in ct_table:
    if J_ <= 0.0:
        nf_rows.append([0.0, 0.0])
        pm_rows.append([0.0, 0.0])
        continue
    lg = math.log(1 + (math.pi / J_) ** 2)
    clb = 3 * J_ / (2 * math.pi) * (16 * ct_ / (sigma * math.pi ** 2 * J_) + cd_bl)
    cn = sigma * math.pi * J_ ** 2 / 16 * (clb + a_bl * J_ / (2 * math.pi) * lg + math.pi / J_ * cd_bl)
    cm = sigma * math.pi * J_ ** 2 / 32 * (2 * math.pi / (3 * J_) * clb + a_bl / 2 * (1 - (J_ / math.pi) ** 2 * lg) - math.pi / J_ * cd_bl)
    nf_rows.append([J_, round(max(cn, 0.0), 6)])
    pm_rows.append([J_, round(max(cm, 0.0), 6)])
THRUST_ANGLES = [1.5, 1.5]
hub = NOSE["propeller_plane"]

# --- Slipstream pieces -----------------------------------------------------------------------------------------------
fin_le_root = fin_exposed[0]["le"][0]
slip_pieces = [
    {"surface": "vertical", "area": Sv, "root": [xv_ac, 0.0, fin_root_z], "span_dir": [0.0, 0.0, 1.0], "span": h_v,
     "chords": [fin_exposed[0]["chord"], fin_exposed[-1]["chord"]]},
    {"surface": "horizontal", "area": Sh / 2, "root": [xh_ac, 0.0, zh], "span_dir": [0.0, 1.0, 0.0], "span": hs, "chords": [crh, SS[-1]["chord"]]},
    {"surface": "horizontal", "area": Sh / 2, "root": [xh_ac, 0.0, zh], "span_dir": [0.0, -1.0, 0.0], "span": hs, "chords": [crh, SS[-1]["chord"]]},
]

# --- Landing gear: R59 contacts and retraction paths ----------------------------------------------------------------
main_pos = [GW["main_left"]["contact_down"], GW["main_right"]["contact_down"]]
tail_pos = GW["tail"]["contact_down"]
three_point = note("gear", "three-point attitude (deg)", math.degrees(math.atan2(tail_pos[2] - main_pos[0][2], tail_pos[0] - main_pos[0][0])), "thrust line to the ground, all wheels down, uncompressed")
x_m, x_t = main_pos[0][0], tail_pos[0]
tail_share = (cg[0] - x_m) / (x_t - x_m)
k_total = (0.09 * 240) ** 2 * mass
k_main, k_tail = k_total * (1 - tail_share) / 2, k_total * tail_share
damp = lambda k_: 2 * 0.3 * math.sqrt(k_ * mass / 3)
note("gear", "tail share, sum k (N/m), static sag (mm)", [tail_share, k_total, 1000 * mass * G0 / k_total], "")
GEAR_SRC = "R59 tyre contact point with the gear down (geometry-r59.json)"
PATH_SRC = D(f"{g['gear']['samples']} uniform extension samples of one tyre material point through R59's tren_retraccion rig (F4U-06): 86 deg aft fold with 90 deg wheel twist, sequenced doors")


def contact(identity, name, key, k_, travel, steer, how):
    return dict({
        "id": identity, "name": name,
        "position": q([float(v) for v in GW[key]["contact_down"]], "m", "measured", GEAR_SRC),
        "stiffness": q(k_, "N/m", "estimated", f"E1 rule: heave w dt 0.09 at 240 Hz (sum k {k_total:.0f} N/m for {mass:.2f} kg), split by the static load ({100 * tail_share:.1f} % on the tail wheel)"),
        "damping": q(damp(k_), "N·s/m", "estimated", "damping ratio 0.3 of the loader's m/3 share"),
        "max_compression": q(travel, "m", "estimated", how),
        "max_steering": q(steer, "deg", "estimated", "steerable tail wheel linked to the rudder, as the P-51; negative: against the rudder trailing edge" if steer else "fixed main wheel"),
        "retraction_path": q([v for pt in GW[key]["path"] for v in pt], "m", "derived", PATH_SRC),
    })


TRAVEL_SRC = "BORROWED from the P-51 (same class and mass); recompute with the GP-06 reserve-drop probe in F4U-08"
landing_gear = {
    "description": "F4U-07: retractable taildragger: two main wheels and a steerable tail wheel (E1 spring-dampers, E2 tyre friction, E3 field surfaces) on the shared retractable-point-gear-v1 law. Kinematics from R59's retract rig scaled 1/5; timing, travel and drag are estimates.",
    "contacts": [
        contact("contact_main_left", "main_left", "main_left", k_main, 0.12, 0.0, TRAVEL_SRC),
        contact("contact_main_right", "main_right", "main_right", k_main, 0.12, 0.0, TRAVEL_SRC),
        contact("contact_tail", "tail", "tail", k_tail, 0.105, -25.0, TRAVEL_SRC),
    ],
    "rolling_resistance": q(0.03, "1", "estimated", "as the P-51 (similar wheel size)"),
    "breakaway_factor": q(1.25, "1", "estimated", "shared E3b1 value, as the P-51, Stik and Timber"),
    "side_friction": q(0.8, "1", "borrowed", "JSBSim c172x static_friction 0.8 (as the Stik, E2)"),
    "peak_slip_angle": q(6.0, "deg", "borrowed", "JSBSim FGLGear default Pacejka initial slope (as the Stik, E2)"),
    "retraction": {
        "extension_time": q(KIT["retracts"]["cycle_s"], "s", "estimated", KIT["retracts"]["source"]),
        "retraction_time": q(KIT["retracts"]["cycle_s"], "s", "estimated", "as extension"),
        "drag_area": q(GEAR_CDA, "m²", "derived", D("gear-down item of the drag build-up x1.1, removed from CD0")),
        "drag_center": q([0.45 * main_pos[0][i] + 0.45 * main_pos[1][i] + 0.10 * tail_pos[i] for i in range(3)], "m", "estimated", D("contacts weighted 0.45/0.45/0.10")),
    },
}

# --- Flaps: three slotted panels per side under the shared hinged-trailing-edge law ----------------------------------
FLAP_KPRIME = [(5, 1.000), (10, 0.999), (15, 0.979), (20, 0.868), (25, 0.728), (30, 0.662), (35, 0.620), (40, 0.588), (45, 0.562)]
tau_f = note("flaps", "flap thin-airfoil effectiveness tau", flap_tau(cf_f), f"Glauert, c_f/c {cf_f:.3f}")
_err = lambda L: sum((L * math.tanh(tau_f * d / L) - k * tau_f * d) ** 2 for d, k in FLAP_KPRIME)
flap_limit = note("flaps", "effective angle limit (deg)", min((x / 100 for x in range(600, 3000)), key=_err), "fit of the runtime tanh bound to Roskam's PLAIN-flap K' (as the P-51): conservative for the slotted F4U flap, no slotted-flap table digitized")
flap_cd = note("flaps", "profile drag coefficient", 0.9 * cf_f ** 1.38, "Raymer eq. 12.61 (after Hoerner)")
ROSKAM_BASE = [(11, 0.861), (12, 0.920), (13, 0.988), (14, 1.080), (15, 1.186), (16, 1.313), (17, 1.431), (18, 1.514)]
ROSKAM_K1_CF = [(15, 0.810), (20, 0.926), (25, 1.007)]
ROSKAM_K2 = [(15, 0.457), (20, 0.571), (25, 0.672), (30, 0.759), (35, 0.821), (40, 0.873), (45, 0.912)]
tc_flap = integral(lambda y: chord(y) * at(y, tcs), y1f, y2f) / integral(chord, y1f, y2f)
_ratios = [lerp_table(ROSKAM_BASE, 100 * tc_flap) * lerp_table(ROSKAM_K1_CF, 100 * cf_f) * k2 / (6.0 * tau_f * dict(FLAP_KPRIME)[d] * math.radians(d)) for d, k2 in ROSKAM_K2]
flap_kappa = note("flaps", "stall shift fraction", 1 - sum(_ratios) / len(_ratios), f"1 - dClmax/dCl0, Roskam Part VI Figs. 8.31-8.33 at t/c {tc_flap:.3f}, c_f/c {cf_f:.3f} (as the P-51)")
flaps = {
    "max_angle_deg": q(flap_settings["landing"], "deg", "derived", D(f"landing setting: {TH['flaps']['landing']:.0f} mm on the Phoenix 1.8 m flap, scaled; full-size slotted flap 50 deg (NACA WR L-440)")),
    "takeoff_angle_deg": q(flap_settings["take_off"], "deg", "derived", D(f"take-off setting: {TH['flaps']['take_off']:.0f} mm on the Phoenix flap, scaled")),
    "inner_span_m": q(y1f, "m", "measured", "R59 inner flap panel inboard end"),
    "outer_span_m": q(y2f, "m", "measured", "R59 outer flap panel outboard end"),
    "hinge_fraction": q(1 - cf_f, "1", "derived", D("1 - flap chord fraction from the NACA flap area")),
    "extension_time": q(2.5, "s", "estimated", "slowed RC flap servo, as the P-51"),
    "retraction_time": q(2.5, "s", "estimated", "as extension"),
    "max_speed_mps": q(float(V_start), "m/s", "estimated", D("advisory: the start speed (1.6 Vs clean); no full-size or kit placard found")),
    "elevator_mix_per_flap_fraction": q(0.0, "1", "estimated", "the Phoenix manual lists no flap-elevator mix"),
    "effective_angle_limit_deg": q(flap_limit, "deg", "derived", D("plain-flap K' fit (conservative for a slotted flap)")),
    "profile_drag_coefficient": q(flap_cd, "1", "derived", D("Raymer eq. 12.61")),
    "aerodynamic_gain": q(1.0, "1", "derived", "full shared flap law"),
    "stall_shift_fraction": q(flap_kappa, "1", "derived", D("Roskam Part VI Figs. 8.31-8.33")),
    "lift_reference_offset_m": q(x_ac_w - x_arp, "m", "derived", D("wing 25 % MAC aft of the wing-body ARP")),
}

# --- Assemble -------------------------------------------------------------------------------------------------------
stik = load_json(STIK)
surf = stik["aero"]["surfaces"]
same = lambda key: dict(surf[key], source="same provisional value as the Ugly Stik surface model (" + surf[key]["source"].split(";")[-1].strip() + ")", kind=surf[key]["kind"] if surf[key]["kind"] != "derived" else "estimated")
H = g["hull"]
mirror = lambda p: [p[0], -p[1], p[2]]
R_vis = NOSE["propeller_visual_diameter"] / 2
hull_probes = [
    ("probe_wing_left_le", mirror(H["wing_tip_le"]), "left_wing_tip"), ("probe_wing_right_le", H["wing_tip_le"], "right_wing_tip"),
    ("probe_wing_left_te", mirror(H["wing_tip_te"]), "left_wing_tip"), ("probe_wing_right_te", H["wing_tip_te"], "right_wing_tip"),
    ("probe_spinner_tip", NOSE["spinner_tip"], "spinner"),
    ("probe_propeller_bottom", [hub[0], 0.0, -R_vis], "propeller"),
    ("probe_propeller_lower_left", [hub[0], -0.7071 * R_vis, -0.7071 * R_vis], "propeller"),
    ("probe_propeller_lower_right", [hub[0], 0.7071 * R_vis, -0.7071 * R_vis], "propeller"),
    ("probe_rudder_bottom", H["rudder_bottom_te"], "tail_end"),
    ("probe_stabilizer_left_tip", mirror(H["stab_tip"]), "left_stab_tip"), ("probe_stabilizer_right_tip", H["stab_tip"], "right_stab_tip"),
    ("probe_fin_top", H["fin_top"], "fin_top"), ("probe_canopy_top", g["canopy_top"], "canopy"),
    ("probe_cowl_bottom", H["cowl_bottom"], "belly"),
]
coeff = lambda v, unit, how: q(float(v), unit, "derived", D(how))
coefficients = {
    "CL0": coeff(CL0, "1", "cambered wing at its mean incidence + tail at zero body alpha (no trim calibration)"),
    "CLa": coeff(CLa, "1/rad", "Helmbold x cos2(gull) + downwashed tail (VLM downwash)"),
    "CLq": coeff(CLq, "1/rad", "tail volume + DATCOM wing term"),
    "CLde": coeff(CLde, "1/rad", "tail slope x elevator effectiveness"),
    "CLda_each": coeff(CLda_each, "1/rad", "strip theory over the measured aileron span"),
    "CD0": coeff(CD0, "1", f"component drag build-up at {V_start} m/s, gear up"),
    "CL_minD": q(round(CL0_w * 0.5, 6), "1", "estimated", "minimum drag near half the zero-alpha wing lift"),
    "k_induced": coeff(k_ind, "1", "1/(pi e AR), e 0.75 estimated"),
    "CDda_each": q(stik["aero"]["coefficients"]["CDda_each"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file)"),
    "CDdr": q(stik["aero"]["coefficients"]["CDdr"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file)"),
    "CDde": q(stik["aero"]["coefficients"]["CDde"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file)"),
    "CYb": coeff(CYb_v + CYb_B, "1/rad", "fin + DATCOM body (rule: fin + body_cy_beta)"),
    "CYp": coeff(CYp, "1/rad", "fin above the CG"),
    "CYr": coeff(CYr, "1/rad", "fin behind the CG"),
    "CYdr": coeff(CYdr, "1/rad", "fin slope x Sv/S x rudder effectiveness"),
    "Clb": coeff(Clb_fin + wing_body_cl, "1/rad", "fin + wing-body (gull strip dihedral, low-wing interference, CL term; rule: fin + wing_body_cl_beta)"),
    "Clp": coeff(Clp, "1/rad", "strip theory on the measured chord + stab + fin"),
    "Clr": coeff(Clr, "1/rad", "CL_ref/4 + fin"),
    "Clda_right": coeff(Clda, "1/rad", "strip theory"),
    "Clda_left": coeff(-Clda, "1/rad", "strip theory"),
    "Cldr": coeff(Cldr, "1/rad", "rudder side force x fin height above the ARP"),
    "Cm0": coeff(Cm0, "1", "230-series Cm_ac + tail at zero body alpha"),
    "Cma": coeff(Cma, "1/rad", "tail about the wing-body ac"),
    "Cmq": coeff(Cmq, "1/rad", "tail damping about the CG x1.1"),
    "Cmde": coeff(Cmde, "1/rad", "elevator lift x tail arm from the ARP"),
    "Cmda_each": coeff(Cmda, "1/rad", "aileron lift at its thin-airfoil centre"),
    "Cnb": coeff(Cnb_fin + Cnb_body, "1/rad", "fin + DATCOM body (rule: fin + body_cn_beta)"),
    "Cnp": coeff(Cnp, "1/rad", "-CL_ref/8 + fin"),
    "Cnr": coeff(Cnr, "1/rad", "fin + wing profile drag + fuselage"),
    "Cnda_right": coeff(Cnda, "1/rad", "adverse yaw 2 K CL_ref Clda, K 0.15"),
    "Cnda_left": coeff(-Cnda, "1/rad", "adverse yaw"),
    "Cndr": coeff(Cndr, "1/rad", "rudder side force x fin arm from the ARP"),
}
data = {
    "format": "openrc-aircraft v2",
    "physical_identity_version": 1,
    "id": "f4u-corsair-1-5",
    "description": f"{KIT['name']}: {b:.3f} m span F4U-1D Corsair, DLE-111 gasoline, retractable taildragger, slotted flaps. PROVISIONAL physics derived by {SCRIPT} (F4U-07) from the R59 visual master measured at 1/5 (F4U-06), NACA F4U data and RC-class references; owner decisions D1/D4/D5 open. Not registered in the catalog; not flight-identified.",
    "frames": {
        "le_frame": "positions in metres from the wing leading edge at the centreline: [x_aft, y_right, z_up]; z = 0 on the thrust line (spinner axis)",
        "body": "simulation body axes FRD about the CG: x forward = -x_aft, y right, z down = -z_up",
    },
    "reference": {
        "wing_area": q(S, "m2", "derived", D("published 314 sq ft x 1/25")),
        "wing_span": q(b, "m", "manual", f"kit span, {KIT['name']} ({KIT['url']})"),
        "mean_chord": q(c_ref, "m", "derived", f"S / b (not the MAC, {mac:.4f} m)"),
        "root_chord": q(cr, "m", "derived", D("equivalent trapezoid with the measured planform's area and MAC")),
        "tip_chord": q(ct, "m", "derived", D("equivalent trapezoid with the measured planform's area and MAC")),
        "aero_reference_point": q([x_arp, 0.0, arp_z], "m", "derived", D("wing-body ac (Raymer K_fus estimate) on the root chord plane")),
        "planform": "tapered",
    },
    "start": {"level_speed": q(float(V_start), "m/s", "derived", D("1.6 x the 1-g stall at the flight mass and CL_max, rounded"))},
    "balance": {
        "plan_cg": q(dry_cg, "m", "estimated", f"reference balance point {x_cg_target:.4f} m aft of the root LE ({100 * cg_mac:.1f} % MAC) from the {REFSET['name']} manual, scaled; tank empty"),
        "firewall": q([rc_fw, 0.0, 0.0], "m", "estimated", "spinner back + 0.25 m (a 111 cc twin on standoffs)"),
        "configuration": "virtual-balanced-reference-v2-empty-tank",
        "cg_tolerance": q(0.001, "m", "estimated", D("virtual reference build balanced to the reference point with the tank empty")),
        "fuel_state": "empty_tanks",
    },
    "fuel_system": {"tanks": [{
        "id": "main_tank", "fuel": FUEL_BLEND, "liquid_inventory_id": "fuel_flight", "shell_inventory_id": "fuel_tank",
        "capacity": q(TANK_L, "l", "estimated", "1 l tank for a 111 cc twin (estimated; no kit value)"),
        "unusable": q(0.01, "l", "estimated", "FUEL-05c felt-clunk residue estimate"),
        "pickup": "felt_clunk", "feed": "pumped_diaphragm"}]},
    "inventory": [
        dict({"id": it[8], "name": it[0],
              "mass": q(float(it[1]), "kg", it[2], it[3] + (f"; x{k_total_struct:.3f}: airframe scaled to the target flight mass" if is_structure(it) else "")),
              "position": q([float(v) for v in it[4]], "m", it[6], it[7]),
              "size": q([float(v) for v in (it[5] or [0, 0, 0])], "m", "estimated", "rough envelope for intrinsic inertia" if it[5] else "point mass")},
             **({"energy_source": ENERGY_SOURCES[it[0]]} if it[0] in ENERGY_SOURCES else {}))
        for it in items
    ],
    "crash_hull": q([p_ for _, p_, _ in hull_probes], "m", "derived", "Points that hit the ground first (le frame) from " + GEO_SRC + "; the propeller probes use the visual scale propeller"),
    "crash_hull_ids": [i_ for i_, _, _ in hull_probes],
    "crash_hull_components": [c_ for _, _, c_ in hull_probes],
    "plausibility": {
        "mass_range": q(KIT["flying_mass_kg"]["range"], "kg", "estimated", KIT["flying_mass_kg"]["source"]),
        "inertia_reference": stik["plausibility"]["inertia_reference"],
    },
    "controls": {
        "surface_ids": {"aileron_left": "surface_aileron_left", "aileron_right": "surface_aileron_right", "elevator": "surface_elevator", "rudder": "surface_rudder"},
        "max_throw": {k: q(float(v), "deg", "estimated", THROW_SRC) for k, v in throws.items()},
        "rates": {"normal": {
            **{k: q(low[k] / throws[k], "1", "estimated", THROW_SRC + "; low rate as the fraction of the high-rate throw") for k in throws},
            **{k + "_expo": q(TH[k]["expo"], "1", "estimated", f"{REFSET['name']} manual expo") for k in throws},
        }},
        "servo_full_throw_time": q(0.18, "s", "estimated", "placeholder, as the P-51"),
    },
    "aero": {
        "source": f"Derived from the measured planform by {SCRIPT} (Helmbold/DATCOM, VLM downwash and ground effect, strip theory, Schrenk/Reynolds stall, drag build-up); report research/f4u-corsair/F4U-07/derivation.md. Not calibrated or flight-identified.",
        "envelope": {
            "CL_max": q(CL_max, "1", "estimated", "three equal-area strips: Schrenk on the measured chord, XFOIL 230-series clmax less 0.10; flaps up"),
            "CL_min": q(-0.85, "1", "estimated", "cambered section: inverted stall earlier than upright, as the P-51"),
            "stall_blend_width": q(4.0, "deg", "estimated", "230-series sections stall more abruptly than the P-51's laminar section (full-size F4U stall warning inadequate, NACA RM A7C05)"),
            "CD90": q(1.11 + 0.018 * AR, "1", "derived", "Viterna CDmax = 1.11 + 0.018 AR"),
            "sideslip_blend": stik["aero"]["envelope"]["sideslip_blend"],
        },
        "conventions": stik["aero"]["conventions"],
        "coefficients": coefficients,
        "surfaces": {
            "wing_aileron_effectiveness": q(wing_ail_eff, "1", "derived", D("|Clda| 2n b / (CLa sum(y)) over the loader's equal-area strips")),
            "wing_station_incidence": q([float(x) for x in strip_inc], "rad", "derived", D("per-strip offsets root -> tip, zero mean: measured twist + Schrenk/Re stall order")),
            "wing_section_cm_ac": q(cm_ac, "1", "derived", D("XFOIL 230-series section moment, chord-weighted")),
            "attached_limit": same("attached_limit"), "tail_local_limit": same("tail_local_limit"), "tail_stall_end": same("tail_stall_end"),
            "tail_CD0": same("tail_CD0"), "tail_k": same("tail_k"), "tail_CD90": same("tail_CD90"),
            "horizontal": {
                "area": q(Sh, "m2", "derived", D("NACA area x 1/25")),
                "position": q([xh_ac, 0.0, zh], "m", "derived", D("measured stabilizer quarter chord")),
                "lift_slope": q(slope_h, "1/rad", "derived", D("Helmbold x eta 0.9 x (1 - deps/dalpha)")),
                "control_effectiveness": q(ce_h, "1", "derived", D("thin-airfoil tau x 0.8 / (1 - deps/dalpha)")),
                "incidence": q(inc_eff, "rad", "derived", D("(1.25 deg stabilizer - eps0)/(1 - deps/dalpha)")),
                "downwash_gradient": q(deps, "1", "derived", D("F4U-07 VLM tail downwash")),
            },
            "vertical": {
                "area": q(Sv, "m2", "derived", D("NACA area x 1/25")),
                "position": q([xv_ac, 0.0, fin_cz], "m", "derived", D("exposed fin quarter chord at its centroid height")),
                "lift_slope": q(slope_v, "1/rad", "derived", D("Helmbold (end-plated AR) x sidewash")),
                "control_effectiveness": q(ce_v, "1", "derived", D("thin-airfoil tau x 0.8 / sidewash")),
                "incidence": q(0.0, "rad", "estimated", "the RC fin and the visual model have no offset; the full-size 2 deg left fin offset is replaced by RC right thrust (propulsion.thrust_angles)"),
            },
            "body_cn_beta": q(Cnb_body, "1/rad", "derived", D("DATCOM fuselage estimate, NOT calibrated")),
            "wing_body_cl_beta": q(wing_body_cl, "1/rad", "derived", D("gull strip dihedral + low-wing interference + wing CL term (D10-R5)")),
            "body_cy_beta": q(CYb_B, "1/rad", "derived", D("DATCOM body side force (D10-R3)")),
            "body_crossflow_area": q(crossflow, "m2", "derived", D("Allen-Perkins eta 0.65 x c_d 1.4 x side area (D10-R3)")),
        },
        "ground_effect": {
            "induced_coefficient": q(GE["fit_induced"]["coefficient"], "1", "derived", f"{GE['generator']}: faded runtime law fitted to the gull-planform VLM induced-drag ratio, rms {GE['fit_induced']['rms']:.4f}"),
            "induced_exponent": q(GE["fit_induced"]["exponent"], "1", "derived", f"{GE['generator']}"),
            "downwash_coefficient": q(GE["fit_tail"]["coefficient"], "1", "derived", f"{GE['generator']}: tail downwash ratio per unit lift, rms {GE['fit_tail']['rms']:.4f}"),
            "downwash_exponent": q(GE["fit_tail"]["exponent"], "1", "derived", f"{GE['generator']}"),
        },
        "reference_coefficients": {"CLadot": coeff(CLadot, "1/rad", "2 eta CLa_h Sh/S l_h/c deps/dalpha")},
    },
    "propulsion": {
        "id": "propulsion_main",
        "description": f"DLE-111 gasoline twin turning a Mejzlik 26x12 3-blade. Shaft balance, calibrated blade-element tables, down and right thrust, propeller normal force and P-factor, tail slipstream with swirl ({SCRIPT}).",
        "engine": {
            "name": E["name"],
            "peak_power": q(P_rated, "W", "manual", f"{E['power_hp']} hp at {E['power_rpm']:.0f} rpm: {E['sources']}"),
            "peak_power_rpm": q(E["power_rpm"], "rpm", "manual", "DLE-111 rating"),
            "max_rpm_static": q(rpm_static, "rpm", "derived", D("full-throttle shaft balance at rest")),
            "idle_rpm": q(IDLE_RPM, "rpm", "manual", "DLE-111 idle 1400 rpm"),
            "lag_time_constant": q(0.6, "s", "estimated", "D5 lag model, unused while the shaft model is present"),
            "shaft": {
                "power_curve": {"value": [[r, round(w_, 1)] for r, w_ in power_curve], "unit": "rpm, W", "kind": "derived",
                                "source": D(f"generic two-stroke twin torque shape (P-51) at the DLE-111 rating x the P-51 installed/catalogue ratio {derate:.3f}; no DLE-111 static-rpm record")},
                "friction_torque": q(FRICTION, "N·m, N·m/krpm", "estimated", "as the P-51 (similar twin)"),
                "idle_power": q(idle_power, "W", "derived", D(f"closed throttle holds {IDLE_RPM:.0f} rpm static")),
                "peak_indicated_power": q(peak_ind, "W", "derived", D("brake + friction power at the curve's peak")),
            },
        },
        "propeller": {
            "name": "Mejzlik 26x12 3-blade GAS N (DLE-111 recommended size; three blades as the F4U-1D)",
            "diameter": q(PROP_D, "m", "manual", "26 in"),
            "rotation": "clockwise_from_rear",
            "ct_table": q(ct_table, "1", "derived", D(f"BEM calibrated on the Mejzlik 26x12 2B/3B tables (P-51 calibration, rms {100 * calib['rms_relative_error']:.1f} %)")),
            "cp_table": q(cp_table, "1", "derived", D("same calibrated BEM")),
            "rotating_inertia": q(rotor_j, "kg·m2", "estimated", "Mejzlik 26x12 3B datasheet + hub + crank"),
            "thrust_line_offset": q([hub[0] - cg[0], 0.0, hub[2] - cg[2]], "m", "derived", D("propeller disc centre relative to the inventory CG")),
            "thrust_angles": q(THRUST_ANGLES, "deg", "estimated", "down 1.5 deg, right 1.5 deg: typical giant-warbird engine offsets (no FokkeRC or Phoenix value found); the right thrust stands in for the full-size 2 deg left fin offset"),
            "normal_force": q(nf_rows, "1", "derived", D(f"McCormick normal force per rad (Selig, AIAA 2010-7938), solidity {sigma:.3f}")),
            "pfactor_moment": q(pm_rows, "1", "derived", D("McCormick P-factor per rad (Selig, AIAA 2010-7938)")),
            "slipstream": {
                "hub": q(hub, "m", "derived", D("propeller disc centre")),
                "wash_factor": q([0.8, 1.8], "1", "borrowed", "Selig, AIAA 2010-7938, Fig. 5 (as the P-51)"),
                "swirl_factor": q(0.6, "1", "estimated", "as the P-51"),
                "vertical_drift": q(1 - deps, "1", "derived", D("1 - d(eps)/d(alpha)")),
                "propeller_sidewash": q(1.0, "1", "borrowed", "Ribner, NACA ARR L4I12a eq. 8 (as the P-51)"),
                "pieces": [{k: (q(v, "m2" if k == "area" else ("1" if k == "span_dir" else "m"), "derived", D("tail piece from the measured geometry")) if k != "surface" else v) for k, v in pc.items()} for pc in slip_pieces],
            },
        },
        "kind": "glow_prop",
        "fuel_consumption": {
            "law": "gasoline_bsfc_v1", "tank_id": "main_tank",
            "bsfc": q(0.500, "kg/kWh", "estimated", "FUEL-08 500 g/kWh proxy (as the P-51); not measured on the DLE-111"),
            "idle_flow": q(0.000080, "kg/s", "estimated", "FUEL-08 4.8 g/min idle baseline (as the P-51)"),
        },
    },
    "landing_gear": landing_gear,
    "convention_id": "openrc-le-frd-v1",
    "capabilities": {"controls": "conventional", "gear": "retractable_taildragger", "propulsion_layout": "single_tractor",
                     "energy": "finite_liquid_fuel", "damage": "terminal_hull", "flaps": "simulated"},
    "flaps": flaps,
}


def check_consistency(d):
    fin_ = d["aero"]["surfaces"]["vertical"]
    arp = d["reference"]["aero_reference_point"]["value"]
    S_, b_ = d["reference"]["wing_area"]["value"], d["reference"]["wing_span"]["value"]
    s_ = d["aero"]["surfaces"]
    cy = fin_["lift_slope"]["value"] * fin_["area"]["value"] / S_ * fin_["control_effectiveness"]["value"]
    arm = fin_["position"]["value"][0] - arp[0]
    fin_force = fin_["lift_slope"]["value"] * fin_["area"]["value"] / S_
    exp = {"CYdr": cy, "Cndr": -cy * arm / b_, "Cldr": cy * (fin_["position"]["value"][2] - arp[2]) / b_,
           "Cnb": fin_force * arm / b_ + s_["body_cn_beta"]["value"],
           "Clb": -fin_force * (fin_["position"]["value"][2] - arp[2]) / b_ + s_["wing_body_cl_beta"]["value"],
           "CYb": -fin_force + s_["body_cy_beta"]["value"]}
    for k, v in exp.items():
        d["aero"]["coefficients"][k]["value"] = v
    rc, tc_ = d["reference"]["root_chord"]["value"], d["reference"]["tip_chord"]["value"]
    assert abs(b_ * (rc + tc_) / 2 - S_) / S_ < 0.01 and abs(b_ * d["reference"]["mean_chord"]["value"] - S_) / S_ < 0.01


check_consistency(data)
validate_physical_identity(data)
text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
rows = ["| Section | Quantity | Value | How |", "| --- | --- | --- | --- |"]
for sec, name, val, how in log:
    v = ", ".join(f"{x:.4g}" for x in val) if isinstance(val, list) else f"{val:.4g}"
    rows.append(f"| {sec} | {name} | {v} | {how} |")
coef_rows = ["| Coefficient | Value | Kind |", "| --- | --- | --- |"] + [f"| {k} | {v['value']:.5g} | {v['kind']} |" for k, v in data["aero"]["coefficients"].items()]
prop_rows = ["| J | Ct (BEM) | Cp (BEM) |", "| --- | --- | --- |"] + [f"| {c_[0]:.2f} | {c_[1]:.4f} | {p_[1]:.4f} |" for c_, p_ in zip(ct_table, cp_table)]
report = f"""# F4U-07: F4U Corsair 1/5 physics derivation

Generated by `{SCRIPT}` from `{GEOMETRY.relative_to(ROOT).as_posix()}`, `source.json` and `vlm_ground_effect.json`; do not edit (regenerate). Output: `{OUT.relative_to(ROOT).as_posix() if OUT.is_relative_to(ROOT) else OUT.name}`, staged until catalog registration (F4U-09). PROVISIONAL: geometry from the R59 visual master at 1/5, owner decisions D1/D4/D5 open, no calibration against flight data. Software derivation, not physical validation.

Flight mass {mass:.3f} kg, CG {100 * cg_mac:.1f} % MAC, stick-fixed power-off neutral point {np_mac:.1f} % MAC (static margin {sm:.1f} % MAC), CL_max {CL_max:.3f}, 1-g stall {Vs:.1f} m/s, start {V_start} m/s.
Throws (Phoenix 1.8 m Corsair manual scaled): aileron {throws['aileron']:.1f}°, elevator {throws['elevator']:.1f}°, rudder {throws['rudder']:.1f}° high rate; flaps {flap_settings['take_off']:.1f}° / {flap_settings['landing']:.1f}°.
Propeller: static {rpm_static:.0f} rpm, static thrust {thrust_static:.0f} N ({thrust_static / G0:.1f} kgf, distributor claim {E['static_thrust_claim_kgf']} kgf), thrust/weight {thrust_static / (mass * G0):.2f}.

## Checks against the full-size airplane (not calibrations)

| Quantity | This model | NACA F4U | Note |
| --- | --- | --- | --- |
| Neutral point | {np_mac:.1f} % MAC stick-fixed, power off | 30 % (up) / 27 % (down) stick-free, power on | Stick-free and power-on points lie forward of stick-fixed power-off ones |
| CG | {100 * cg_mac:.1f} % MAC | 26.5-32.5 % MAC tested | RC reference setup, scaled |
| Roll response | pb/2V {pb2v:.3f} at {throws['aileron']:.1f}° | 0.064 at the full-size throw | Full-size aileron throw not recovered |
| Wing area | {S_r59:.4f} m² measured | {S:.4f} m² published | |

## Intermediate quantities

{chr(10).join(rows)}

## Coefficients written (c_ref = S/b; moments about the ARP = wing-body ac)

{chr(10).join(coef_rows)}

## Propeller tables (calibrated BEM, Mejzlik 26x12 3-blade)

{chr(10).join(prop_rows)}

## Known simplifications

- Geometry is the R59 visual master scaled 1/5; g1 metrology replaces it (F4U-05/06). Wing incidence and stabilizer setting lack a primary source.
- Sections: XFOIL predictions with a 0.9 lift-slope factor and a 0.10 clmax decrement, both estimated.
- No trim, neutral-point or sideslip calibration: the fuselage neutral-point term is a Raymer reading and the body yaw term is DATCOM's. The P-51's flight calibrations needed larger body terms; expect revision when F4U data are reduced.
- Engine level borrows the P-51's installed/catalogue ratio; flaps use the plain-flap K' fit (conservative for slotted flaps); gear travel is borrowed from the P-51.
- The fin carries no offset; RC right thrust stands in for the full-size 2° left fin offset.
- CL-dependent cross terms are frozen at CL_ref = {CL_ref:.2f}.
"""

if "--dry" in sys.argv:
    print("\n".join(rows))
elif "--check" in sys.argv:
    stale = [p for p, t in ((OUT, text), (REPORT, report)) if not p.exists() or p.read_text(encoding="utf-8") != t]
    if stale:
        sys.exit("stale: " + ", ".join(p.name for p in stale) + f" (run {SCRIPT})")
    print("f4u_corsair_1_5.json and derivation.md are up to date")
else:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8")
    REPORT.write_text(report, encoding="utf-8")
    print(f"wrote {OUT.name} and {REPORT.name}")
    print(f"mass {mass:.3f} kg, CG {100 * cg_mac:.1f} % MAC, NP {np_mac:.1f} % MAC, SM {sm:.1f}, CLmax {CL_max:.3f}, stall {Vs:.1f} m/s, start {V_start} m/s, static {rpm_static:.0f} rpm, thrust {thrust_static / G0:.1f} kgf")
