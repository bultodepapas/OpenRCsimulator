#!/usr/bin/env python3
"""P51-05: physics data of the giant-scale P-51D Mustang (120 cc class), derived and reproducible.

Reads the scaled visual geometry (assets/aircraft/p51d-mustang-120/geometry.json), the kit values in source.json and the
Ugly Stik data file (shared conventions and the provisional local-surface limits). Writes
app/data/aircraft/p51d_mustang_120.json (openrc-aircraft v1) and research/p51/p51-05/derivation.md.

Methods are textbook estimates, not flight identification: Helmbold/DATCOM lift slopes, tail-volume static and damping
derivatives, strip theory for ailerons, roll damping and dihedral, a skin-friction drag build-up, a component inventory,
and a blade-element/momentum propeller model for the 4-blade 28x10 (no measured table exists for that propeller).
Every number written carries its unit, evidence kind and source. Nothing here validates the airplane.

    python3 research/p51/p51-05/derive_physics.py           # writes the JSON and the report
    python3 research/p51/p51-05/derive_physics.py --check   # fails if either file is stale
    python3 research/p51/p51-05/derive_physics.py --dry     # prints the intermediate quantities, writes nothing
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GEOMETRY = ROOT / "assets/aircraft/p51d-mustang-120/geometry.json"
SOURCE = ROOT / "assets/aircraft/p51d-mustang-120/source.json"
STIK = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
OUT = ROOT / "app/data/aircraft/p51d_mustang_120.json"
REPORT = ROOT / "research/p51/p51-05/derivation.md"
SECTION = ROOT / "research/p51/p51-13/section.json"  # real-section camber analysis (P51-13)
IN = 0.0254
LB = 0.45359237
RHO = 1.225
G0 = 9.80665
NU = 1.46e-5
GEO_SRC = "assets/aircraft/p51d-mustang-120/geometry.json (P51-01: full-size P-51D dimensions scaled to the kit span)"
SCRIPT = "research/p51/p51-05/derive_physics.py"

g = json.load(open(GEOMETRY))
src = json.load(open(SOURCE))
KIT = src["kit"]
KIT_NAME = KIT["name"]
W, T, GEAR, PROP = g["wing"], g["tail"], g["gear"], g["propeller"]
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


def shoelace(points):
    a = cu = cv = 0.0
    for (u0, v0), (u1, v1) in zip(points, points[1:] + points[:1]):
        cross = u0 * v1 - u1 * v0
        a += cross
        cu += (u0 + u1) * cross
        cv += (v0 + v1) * cross
    a *= 0.5
    return abs(a), cu / (6 * a), cv / (6 * a)


def helmbold(aspect, kappa, half_chord_sweep=0.0):
    t = math.tan(half_chord_sweep)
    return 2 * math.pi * aspect / (2 + math.sqrt(aspect ** 2 / kappa ** 2 * (1 + t * t) + 4))


def flap_tau(cf):
    th = math.acos(2 * cf - 1)
    return 1 - (th - math.sin(th)) / math.pi


# --- Frames -----------------------------------------------------------------------------------------------------
# Model axes: +X right, +Y up, -Z nose; z = 0 at the root LE, y = 0 on the thrust line. The physics le frame
# [x_aft, y_right, z_up] measures from the same point, so x_aft = model z and z_up = model y.
LE0 = W["le_z_root"]
assert LE0 == 0.0


def le(model_z, model_y=0.0, model_x=0.0):
    return [model_z - LE0, model_x, model_y]


# --- Reference geometry -----------------------------------------------------------------------------------------
cr, ct = W["root_chord"], W["tip_chord"]
b = note("reference", "b (m)", W["span"], f"kit span ({KIT_NAME})")
semi = b / 2
S = note("reference", "S (m2)", b * (cr + ct) / 2, "trapezoid to the centreline (the kit's published area is checked in the report when known)")
c_ref = note("reference", "c_ref = S/b (m)", S / b, "v1 coefficient reference length (not the MAC)")
lam = ct / cr
AR = note("reference", "AR = b2/S", b * b / S, "")
mac = 2 / 3 * cr * (1 + lam + lam * lam) / (1 + lam)
y_mac = semi / 3 * (1 + 2 * lam) / (1 + lam)
le_slope = (W["le_z_tip"] - W["le_z_root"]) / semi
mac_le_z = W["le_z_root"] + le_slope * y_mac
note("reference", "MAC (m)", mac, f"trapezoid; geometry.json says {W['reference']['mac']}")
note("reference", "MAC LE (model z)", mac_le_z, f"at y = {y_mac:.4f} m")
qc = lambda y: W["le_z_root"] + le_slope * y + 0.25 * (cr + (ct - cr) * y / semi)
hc = lambda y: W["le_z_root"] + le_slope * y + 0.5 * (cr + (ct - cr) * y / semi)
sweep_qc = math.atan2(qc(semi) - qc(0), semi)
sweep_hc = math.atan2(hc(semi) - hc(0), semi)
note("reference", "quarter-chord sweep (deg)", math.degrees(sweep_qc), "unswept by construction (source.json)")
note("reference", "half-chord sweep (deg)", math.degrees(sweep_hc), "forward: the TE sweeps forward")
dihedral = math.radians(W["dihedral_deg"])
washout = math.radians(W["washout_deg"])
sec = json.load(open(SECTION))
# Chord-weighted means over the semi-span (linear twist and linear root -> tip section blend): what the whole wing
# sees at zero body alpha. eta = y / semi.
n_eta = 400
etas = [(k + 0.5) / n_eta for k in range(n_eta)]
cw = [cr + (ct - cr) * e for e in etas]
cmean = lambda f: sum(c * f(e) for c, e in zip(cw, etas)) / sum(cw)
i_root = math.radians(W["incidence_deg"])
i_w = note("aero", "mean wing incidence (deg)", math.degrees(cmean(lambda e: i_root - washout * e)), f"root {W['incidence_deg']:+.2f} deg, washout {W['washout_deg']:.2f} deg linear to the tip (NACA P-51B dimension table, source.json), chord-weighted")
i_w = math.radians(i_w)

cg_mac = KIT["cg_fraction_of_mac"]
cg_z_model = mac_le_z + cg_mac * mac
note("balance", "CG (% MAC)", 100 * cg_mac, "kit placeholder balance point (source.json); model z " + f"{cg_z_model:.4f}")

st = g["fuselage_stations"]
fus_w = 2 * max(r[1] for r in st)
fus_d = max(r[2] - r[3] for r in st)
scoop_d = max(-row[2] for row in g["scoop_stations"]) - min(r[3] for r in st)  # extra depth of the belly scoop below the fuselage
fus_len = st[-1][0] - g["spinner"]["tip_z"]
note("fuselage", "max width / depth / length (m)", [fus_w, fus_d, fus_len], f"spinner tip to tail post; scoop adds {scoop_d:.3f} m of depth")

# Horizontal tail: trapezoid, elevator aft of the hinge fraction.
hs = T["stab_half_span"]
crh, cth = T["stab_root_chord"], T["stab_tip_chord"]
Sh = note("tail", "Sh (m2)", 2 * hs * (crh + cth) / 2, "stab + elevators trapezoid through the fuselage")
bh = 2 * hs
lh_ = cth / crh
y_mach = hs / 3 * (1 + 2 * lh_) / (1 + lh_)
mach = 2 / 3 * crh * (1 + lh_ + lh_ * lh_) / (1 + lh_)
xh_ac = T["stab_root_le_z"] + (T["stab_tip_le_z"] - T["stab_root_le_z"]) * y_mach / hs + 0.25 * mach
note("tail", "horizontal ac (model z)", xh_ac, "quarter chord of the stab MAC")
cf_e = note("tail", "elevator chord fraction", 1 - T["elevator_hinge_fraction"], "hinge at a constant chord fraction")

# Vertical tail: fin + rudder side polygon (z, y) above the fuselage top line, dorsal fillet included.
fus_top = lambda z: next(r0[2] + (r1[2] - r0[2]) * (z - r0[0]) / (r1[0] - r0[0]) for r0, r1 in zip(st, st[1:]) if r0[0] <= z <= r1[0])
z_post = T["rudder_hinge_z"]
fin_top_te = T["fin_top_le_z"] + T["fin_top_chord"]
fin = [(T["dorsal_start_z"], fus_top(T["dorsal_start_z"])), (T["fin_root_le_z"], fus_top(T["fin_root_le_z"]) + 0.06),
       (T["fin_top_le_z"], T["fin_top_y"]), (fin_top_te, T["fin_top_y"]), tuple(T["rudder_te_bottom"]), (z_post, T["rudder_te_bottom"][1])]
Sv, fin_cz, fin_cy = shoelace(fin)
note("tail", "Sv (m2)", Sv, "fin (with dorsal fillet) + rudder side polygon")
rud = [(z_post, T["fin_top_y"]), (fin_top_te, T["fin_top_y"]), tuple(T["rudder_te_bottom"]), (z_post, T["rudder_te_bottom"][1])]
Sr, _, _ = shoelace(rud)
cf_r = note("tail", "rudder area fraction", Sr / Sv, "used as its chord fraction")
h_v = T["fin_top_y"] - T["rudder_te_bottom"][1]
fin_le_at = lambda y: T["fin_root_le_z"] + (T["fin_top_le_z"] - T["fin_root_le_z"]) * (y - fin[1][1]) / (T["fin_top_y"] - fin[1][1])
xv_ac = fin_le_at(fin_cy) + 0.25 * (Sv / h_v)
note("tail", "fin ac (model z, y)", [xv_ac, fin_cy], "LE at the area-centroid height + 1/4 of the mean chord")

# --- Lift slopes, downwash, neutral point ----------------------------------------------------------------------
kappa = note("aero", "section lift slope / 2pi", 0.86, "NACA 66(2)-415 at Re 0.7-1.0e6: 0.093-0.095 /deg (Loftin & Smith, NACA TN 1945, ntrs.nasa.gov/citations/19930082618); the NAA 45-100 is a 6-series-type laminar section; the full-size section measured 0.111 /deg at Re 13e6 (NACA MR 1943), the low Re lowers it")
CLa_w = note("aero", "CLa wing (1/rad)", helmbold(AR, kappa, sweep_hc) * math.cos(dihedral) ** 2, "Helmbold/DATCOM x cos2(dihedral)")
AR_h = bh * bh / Sh
CLa_h = note("aero", "CLa horizontal (1/rad)", helmbold(AR_h, 0.9), f"Helmbold, AR {AR_h:.2f}")
eta_h = note("aero", "tail dynamic pressure ratio", 0.9, "estimated; propwash not modelled (ROADMAP E0b)")
deps = note("aero", "d(eps)/d(alpha)", 2 * CLa_w / (math.pi * AR), "elliptic-wing downwash estimate")
slope_h = note("aero", "effective tail slope (1/rad)", CLa_h * eta_h * (1 - deps), "CLa_h eta (1 - deps/dalpha)")
CLa = note("aero", "CLa airplane (1/rad)", CLa_w + slope_h * Sh / S, "wing + tail (wing-body interference ~1 for d/b 0.08)")

x_qc_root = (qc(0) - g["spinner"]["tip_z"]) / fus_len
x_ac_w = mac_le_z + 0.25 * mac
arp_y = W["chord_plane_y"]
NP_GLIDE = 0.342  # stick-fixed, power-off glide neutral point (% MAC / 100)


def neutral_point(k_f):
    """Neutral point (model z) for a fuselage + nacelle term k_f (Raymer's K_fus, per deg)."""
    dx = k_f * fus_w ** 2 * fus_len / (mac * S) * 180 / math.pi / CLa_w * mac
    x_a = x_ac_w - dx
    cma = -slope_h * Sh / S * (xh_ac - x_a) / c_ref
    return x_a - cma / CLa * c_ref, x_a, dx


lo_k, hi_k = 0.0, 0.1
for _ in range(80):
    mid_k = 0.5 * (lo_k + hi_k)
    lo_k, hi_k = (mid_k, hi_k) if neutral_point(mid_k)[0] > mac_le_z + NP_GLIDE * mac else (lo_k, mid_k)
K_f = note("aero", "K_fus (per deg)", 0.5 * (lo_k + hi_k),
           f"CALIBRATED: the fuselage, belly scoop and windmilling-propeller term that puts the power-off neutral point at the full-size airplane's measured stick-fixed glide value, {100 * NP_GLIDE:.1f} % MAC (NACA XP-51 flying-qualities report 1942, Table II, ntrs.nasa.gov/citations/19930092575; cruise 30.8, climb 30.6 % with power). Raymer Fig. 16.14 gives 0.005-0.015 for a wing at {100 * x_qc_root:.0f} % of the body; the geometry is the full-size airplane scaled, so the neutral point carries over (Re lowers both slopes alike)")
_, x_arp, dx_f = neutral_point(K_f)
note("aero", "wing-body ac = ARP (model z)", x_arp, f"wing ac at 25 % MAC {x_ac_w:.4f}, fuselage moves it {dx_f * 1000:.1f} mm forward")
l_h = xh_ac - x_arp
Cma = note("aero", "Cma about ARP (1/rad, c_ref)", -slope_h * Sh / S * l_h / c_ref, "tail only: the ARP is the wing-body ac")
Cma_cg = Cma + CLa * (cg_z_model - x_arp) / c_ref
x_np = x_arp - Cma / CLa * c_ref
sm = note("aero", "static margin at the kit CG (% MAC)", 100 * (x_np - cg_z_model) / mac, f"neutral point at model z {x_np:.4f} ({100 * (x_np - mac_le_z) / mac:.1f} % MAC)")
note("aero", "Cma about the CG (1/rad, c_ref)", Cma_cg, "what the pilot feels")

# Camber: thin-airfoil integrals over the REAL root and tip camber lines (research/p51/p51-13/section.json), blended
# linearly root -> tip and chord-weighted. Thin-airfoil Cm_ac overestimates measured values of aft-loaded 6-series
# sections by ~20 % (66(2)-415: -0.065 measured at Re 0.7-1e6 in NACA TN 1945 vs -0.083 for its a = 1.0, cli 0.4 mean
# line), so x 0.8.
rs_, ts_ = sec["root"], sec["tip"]
alpha0 = note("aero", "wing zero-lift angle (deg)", cmean(lambda e: rs_["alpha0_deg"] + (ts_["alpha0_deg"] - rs_["alpha0_deg"]) * e),
              f"thin-airfoil over the UIUC NAA 45-100 camber lines: root {rs_['alpha0_deg']:.2f}, tip {ts_['alpha0_deg']:.2f} deg (section.json)")
cm_ac = note("aero", "section Cm_ac", 0.8 * cmean(lambda e: rs_["cm_ac"] + (ts_["cm_ac"] - rs_["cm_ac"]) * e),
             f"thin-airfoil root {rs_['cm_ac']:.4f}, tip {ts_['cm_ac']:.4f} (aft-loaded camber) x 0.8 (theory/measured, NACA TN 1945)")
CL0_w = CLa_w * (i_w - math.radians(alpha0))
eps0 = 2 * CL0_w / (math.pi * AR)
i_h = math.radians(T["stab_incidence_deg"])
inc_eff = note("aero", "tail effective incidence (rad)", (i_h - eps0) / (1 - deps), "(i_h - eps0) / (1 - deps/dalpha): the local tail model sees body alpha")
CL0 = note("aero", "CL0", CL0_w + slope_h * Sh / S * inc_eff, "wing at its mean incidence with camber + tail at zero body alpha")
Cm0 = note("aero", "Cm0 about ARP", cm_ac * mac / c_ref - slope_h * Sh / S * l_h / c_ref * inc_eff, "wing Cm_ac + tail at zero body alpha")

# Controls (kit placeholder throws, degrees).
# Throws (P51-09): degrees, high rate, from the Hangar 9 Mustang 1.50 manual (80 in; astramodel.cz/manualy/hangar9/
# hangar9_mustang_150.pdf, read 2026-10-06): aileron 18, elevator 15, rudder 30 deg; full-size P-51D rudder +-30 deg (NACA
# RM L6J25). The millimetre throws of the 60cc and Top Flite manuals convert to the same range on our chords.
THROWS_DEG = {"aileron": 18.0, "elevator": 15.0, "rudder": 30.0}
THROWS_SRC = "Hangar 9 Mustang 1.50 (80 in) manual, high rate (low: aileron 14, elevator 12, rudder 20 deg); full-size P-51D rudder +-30 deg (NACA RM L6J25, ntrs.nasa.gov/citations/20050019329)"
throws = {k: note("controls", f"{k} (deg)", v, THROWS_SRC) for k, v in THROWS_DEG.items()}
k_flap = note("controls", "flap effectiveness correction", 0.8, "estimated: real/thin-airfoil effectiveness with gap and large throws (DATCOM range 0.6-0.9)")
tau_e = flap_tau(cf_e) * k_flap
ce_h = note("controls", "elevator effectiveness (local)", tau_e / (1 - deps), f"tau {tau_e:.3f} / (1 - deps/dalpha)")
CLde = note("aero", "CLde (1/rad)", slope_h * ce_h * Sh / S, "")
Cmde = note("aero", "Cmde (1/rad)", -CLde * l_h / c_ref, "")

chord = lambda y: cr + (ct - cr) * y / semi
cf_a = W["aileron_chord_fraction"]
y1, y2 = W["aileron_inner"], min(W["aileron_outer"], semi)
n_int = 400
ys = [y1 + (y2 - y1) * (k + 0.5) / n_int for k in range(n_int)]
dy = (y2 - y1) / n_int
int_c = sum(chord(y) for y in ys) * dy
int_cy = sum(chord(y) * y for y in ys) * dy
tau_a = note("controls", "aileron tau", flap_tau(cf_a) * k_flap, f"chord fraction {cf_a:.3f}")
CLda_each = CLa_w * tau_a * int_c / S
Clda = -CLa_w * tau_a * int_cy / (S * b)
note("aero", "Clda_right (1/rad)", Clda, "strip theory")

# --- Inventory (le frame) ---------------------------------------------------------------------------------------
fw = g["firewall_z"]  # scaled full-size firewall: cowl/fuselage split only
rc_fw = g["spinner"]["back_z"] + 0.25  # the model's engine box: a 120 cc twin on standoffs is ~0.25 m long from the spinner back
cp_y = W["chord_plane_y"]
spinner_d_in = 2 * g["spinner"]["radius"] / IN
items = [
    ("engine DA-120 with ignition module", 2.45, "manual", "DA-120: 2300 g engine, 2445 g with ignition (toni-clark.com/en/da-120); DLE-120 2.78-2.90 kg complete", le(g["spinner"]["back_z"] + 0.13), [0.16, 0.30, 0.16], "estimated", "crankshaft on the thrust line, crankcase ~0.13 m behind the spinner back"),
    ("mufflers / canisters (2)", 0.60, "estimated", "two in-cowl canister mufflers for a 120 cc twin", le(g["spinner"]["back_z"] + 0.20, -0.07), [0.25, 0.20, 0.08], "estimated", "under the cylinders inside the cowl"),
    (f"propeller 4-blade {KIT['propeller']['diameter_in']:.0f}x{KIT['propeller']['pitch_in']:.0f}", 0.43, "manual", "Biela 26x12 4-blade CFK semi-scale: 428 g (pp-rc.de product page, read 2026-10-06)", le(PROP["z"]), [0.02, PROP["diameter"], PROP["diameter"]], "measured", "propeller plane from geometry.json"),
    (f"spinner {spinner_d_in:.1f} in aluminium with backplate", 0.35, "estimated", "machined aluminium spinner of this diameter", le(g["spinner"]["back_z"] - 0.06), [0.17, 0.15, 0.15], "measured", "spinner from geometry.json"),
    ("engine standoffs / mount and bolts", 0.25, "estimated", "aluminium standoffs on a plywood firewall", le(rc_fw - 0.03), None, "estimated", "on the model's firewall"),
    ("cowl (fiberglass) with dummy exhausts", 0.60, "estimated", "fiberglass cowl of a 2.5 m warbird", le((g["spinner"]["back_z"] + g["cowl_rear_z"]) / 2, 0.0), [g["cowl_rear_z"] - g["spinner"]["back_z"], fus_w, fus_d], "measured", "between the spinner back and the cowl rear (geometry.json)"),
    ("fuel tank 1 l (empty) with lines", 0.20, "estimated", "gasoline tank with clunk and lines", le(rc_fw + 0.10, -0.02), None, "estimated", "behind the model's firewall"),
    ("fuel (half tank)", 0.37, "estimated", "0.5 l at 0.74 g/ml gasoline; flight state: half tank (no consumption model, G4)", le(rc_fw + 0.10, -0.02), None, "estimated", "same as the tank"),
    ("ignition battery 2S LiFe", 0.15, "estimated", "1500-2100 mAh LiFe pack", le(rc_fw + 0.03, -0.08), None, "estimated", "below the tank, as far forward as the cowl allows"),
    ("receiver batteries 2S LiFe (2)", 0.30, "estimated", "two 2100 mAh LiFe packs (redundant)", le(rc_fw + 0.06, -0.09), None, "estimated", "forward fuselage floor, next to the ignition pack (warbird practice: everything heavy forward)"),
    ("receiver, switches, power distribution", 0.12, "estimated", "receiver, two switches, harnesses", le(0.25, -0.05), None, "estimated", "under the cockpit floor"),
    ("aileron servos (2)", 0.16, "estimated", "two 20-25 kg·cm servos ~80 g", le(0.12, cp_y), [0.03, 1.9, 0.04], "estimated", "one per aileron, mid-aileron span"),
    ("flap servos (2)", 0.16, "estimated", "two 20-25 kg·cm servos ~80 g", le(0.30, cp_y), [0.03, 0.8, 0.04], "estimated", "one per flap"),
    ("elevator servos (2)", 0.16, "estimated", "two servos in the tail", le(T["stab_root_le_z"] - 0.05, T["stab_y"]), [0.04, 0.3, 0.04], "estimated", "in the stab roots"),
    ("rudder servo and pull-pull", 0.10, "estimated", "one servo with cables", le(0.55, -0.02), None, "estimated", "aft of the cockpit"),
    ("throttle, choke servos and linkage", 0.08, "estimated", "two small servos", le(rc_fw + 0.05, 0.02), None, "estimated", "behind the model's firewall"),
    ("main retracts, struts and wheels (2 sides)", 2.00, "estimated", "two electric/pneumatic giant-scale retracts (0.5 kg each), oleo struts (0.25 each), 6 in wheels with hubs (0.2 each), gear doors", le(GEAR["main_axle"][0], (GEAR["main_axle"][1] + cp_y) / 2), [0.12, GEAR["track"], cp_y - GEAR["main_axle"][1]], "measured", "axle station from geometry.json; mass centred mid-strut"),
    ("tail wheel assembly (retractable)", 0.20, "estimated", "retractable tail wheel unit", le(GEAR["tail_axle"][0], GEAR["tail_axle"][1] + 0.04), None, "measured", "geometry.json tail axle"),
    ("wing panel, left, sheeted, with flap and aileron", 2.00, "estimated", "built-up sheeted/glassed 1.25 m panel of a 2.5 m warbird ARF (wings 4-5 kg a pair)", le(mac_le_z + 0.42 * mac, cp_y, -y_mac), [mac, semi, 0.07], "derived", "42 % MAC at the MAC span station"),
    ("wing panel, right, sheeted, with flap and aileron", 2.00, "estimated", "same as the left panel", le(mac_le_z + 0.42 * mac, cp_y, y_mac), [mac, semi, 0.07], "derived", "42 % MAC at the MAC span station"),
    ("wing tube and bolts", 0.35, "estimated", "aluminium or carbon wing joiner", le(0.17, cp_y), [0.04, 0.6, 0.04], "estimated", "main spar"),
    ("fuselage front (engine box to cockpit rear), covered", 1.80, "estimated", "lite-ply/balsa box with doublers, glassed", le(0.20, -0.02), [1.0, fus_w, fus_d], "estimated", "from the stations in geometry.json"),
    ("belly scoop (fiberglass)", 0.35, "estimated", "moulded scoop", le(0.70, -0.18), [0.5, 0.15, 0.12], "measured", "scoop stations in geometry.json"),
    ("fuselage rear and turtle deck, covered", 1.00, "estimated", "balsa sides and stringered deck", le(1.05, 0.02), [0.9, 0.18, 0.2], "estimated", "from the stations in geometry.json"),
    ("canopy, frame and pilot", 0.35, "estimated", "blown canopy with frame; 1/4.5 WWII pilot bust", le(0.62, 0.17), None, "measured", "pilot block in geometry.json"),
    ("stabilizer and elevators, covered", 0.65, "estimated", "sheeted built-up stab", le(T["stab_root_le_z"] + 0.45 * crh, T["stab_y"]), [crh, bh, 0.025], "measured", "stab from geometry.json"),
    ("fin and rudder, covered", 0.35, "estimated", "sheeted built-up fin", le(fin_cz, fin_cy), [0.3, 0.02, h_v], "derived", "area centroid of the fin polygon"),
    ("pushrods, horns, cowl fasteners, hardware", 0.35, "estimated", "clevises, horns, ball links, screws, bolts: rough sum", le(0.6), None, "estimated", "spread along the fuselage"),
]
# Built weight (P51-09): plan weights (Veich 18-27 kg, Don Smith 112 in 35-40 lb) understate real 1/4-scale P-51s with
# retracts and a 120 cc twin: "easy 50-55 lb" (giantscalenews.com/threads/don-smith-p-51-mustang.10787), Bates "50 lb+";
# the CARF 2.54 m's 15-17 kg dry scaled by span^3 gives 20.5-23 kg. Target 21.5 kg in flight: the airframe items
# (wings, fuselage, tails, cowl, scoop, canopy, hardware) are scaled by one factor; engine, propeller, radio, fuel and
# gear stay as listed. The balancing mass is then solved again.
FLIGHT_MASS = 21.5
STRUCTURE = ("wing panel", "wing tube", "fuselage", "belly scoop", "canopy", "stabilizer", "fin and rudder", "cowl", "pushrods")
is_structure = lambda it: any(it[0].startswith(s) for s in STRUCTURE)
k_total_struct = 1.0
for _ in range(30):
    base = sum(i[1] for i in items)
    m_cg = sum(i[1] * i[4][0] for i in items) / base
    nose_ = m_cg > cg_z_model - LE0
    xb_ = le(g["spinner"]["back_z"] - 0.02)[0] if nose_ else le(T["stab_root_le_z"])[0]
    total = base + base * (cg_z_model - LE0 - m_cg) / (xb_ - (cg_z_model - LE0))
    k_struct = 1 + (FLIGHT_MASS - total) / sum(i[1] for i in items if is_structure(i))
    items = [(i[0], i[1] * k_struct) + i[2:] if is_structure(i) else i for i in items]
    k_total_struct *= k_struct
    if abs(FLIGHT_MASS - total) < 1e-6:
        break
note("balance", "airframe mass (kg)", sum(i[1] for i in items if is_structure(i)), f"airframe items scaled so the flight mass is {FLIGHT_MASS} kg (built 1/4-scale P-51s: 50-55 lb with retracts and 120 cc)")
mass0 = sum(i[1] for i in items)
mom0 = [sum(i[1] * i[4][k] for i in items) for k in range(3)]
x_target = cg_z_model - LE0
x_cg0 = mom0[0] / mass0
nose = x_cg0 > x_target
xb = le(g["spinner"]["back_z"] - 0.02)[0] if nose else le(T["stab_root_le_z"])[0]
mb = mass0 * (x_target - x_cg0) / (xb - x_target)
ballast_pos = [xb, 0.0, 0.0 if nose else 0.03]
note("balance", "inventory without balancing mass (kg, CG x_aft m)", [mass0, x_cg0], f"target CG x_aft {x_target:.4f}")
note("balance", "balancing mass (kg)", mb, ("nose weight" if nose else "tail weight") + " that puts the CG on the kit's balance point")
items.append(("virtual reference-build balancing mass", mb, "derived",
              f"{SCRIPT}: m = M (x_CG - x0) / (x_ballast - x_CG) for the kit balance point; a virtual reference build, NOT measured hardware or a ballast recommendation",
              ballast_pos, [0.04, 0.04, 0.04], "estimated", "behind the spinner backplate" if nose else "tail post"))
mass = mass0 + mb
cg = [sum(i[1] * i[4][k] for i in items) / mass for k in range(3)]
cg[1] = 0.0  # symmetric build
lo_m, hi_m = KIT["flying_mass_kg"]
note("balance", "flight mass (kg)", mass, f"dry {mass - 0.37:.3f} kg = {(mass - 0.37) / LB:.1f} lb vs kit range {lo_m}-{hi_m} kg")
note("balance", "flight CG (le frame)", cg, "z: below the thrust line by the inventory")


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

# --- Spanwise stall (P51-13) ----------------------------------------------------------------------------------------
# Each of the simulation's equal-area strips stalls when its section reaches its own clmax. Additional loading by
# Schrenk (NACA TM 948): c·cl/CL = ½[c + (4S/πb)·sqrt(1 − η²)] (a 40-term lifting line gives the same 1.05 peak at
# η 0.5, research/p51/p51-13/README.md); section clmax from the Reynolds number (NACA TN 1945, 66(2)-415 smooth:
# 3e5 1.00 (extrapolated), 7e5 1.14, 1e6 1.16, 2e6 1.27), minus 0.05 for a painted model's finish (TN 1945: rough
# is ~0.1 lower). The washout adds its basic loading geometrically (strip incidence). Strip i stalls at the wing CL
# CL*_i = clmax_i / (cl/CL)_i; the strips' angle offsets are the twist plus (mean CL* − CL*_i)/CLa_w, zero-mean.
CLMAX_RE = [(3e5, 1.00), (7e5, 1.14), (1e6, 1.16), (2e6, 1.27)]
FINISH = 0.05
clmax_re = lambda re: CLMAX_RE[0][1] if re <= CLMAX_RE[0][0] else next((a[1] + (b_[1] - a[1]) * (re - a[0]) / (b_[0] - a[0]) for a, b_ in zip(CLMAX_RE, CLMAX_RE[1:]) if a[0] <= re <= b_[0]), CLMAX_RE[-1][1])
schrenk = lambda e: 0.5 * ((cr + (ct - cr) * e) + 4 * S / (math.pi * b) * math.sqrt(max(1 - e * e, 0.0))) / (cr + (ct - cr) * e)
n_strips = 3  # physics/aero.gd WING_STATIONS_PER_SIDE
edges = [0.0]
area_h = (cr + ct) / 2  # semi-span area / semi, in eta units
for k in range(1, n_strips):
    target = area_h * k / n_strips  # cr e + (ct - cr) e^2 / 2 = target
    a2 = (ct - cr) / 2
    edges.append((-cr + math.sqrt(cr * cr + 4 * a2 * target)) / (2 * a2))
edges.append(1.0)
strip_eta = []
for e0, e1 in zip(edges, edges[1:]):
    es = [e0 + (e1 - e0) * (k + 0.5) / 200 for k in range(200)]
    strip_eta.append(sum(e * (cr + (ct - cr) * e) for e in es) / sum(cr + (ct - cr) * e for e in es))
V_stall_guess = 14.0
for _ in range(4):
    cl_star = [(clmax_re(V_stall_guess * (cr + (ct - cr) * e) / NU) - FINISH) / schrenk(e) for e in strip_eta]
    CL_max = sum(cl_star) / n_strips
    V_stall_guess = math.sqrt(2 * mass * G0 / (RHO * S * CL_max))
eta_bar = sum(strip_eta) / n_strips
strip_inc = [-washout * (e - eta_bar) + (CL_max - c_) / CLa_w for e, c_ in zip(strip_eta, cl_star)]
for i, (e, c_) in enumerate(zip(strip_eta, cl_star)):
    note("stall", f"strip {i + 1} (root to tip): eta, Re, cl/CL, CL*", [e, V_stall_guess * (cr + (ct - cr) * e) / NU, schrenk(e), c_], "")
note("stall", "strip incidence offsets root to tip (deg)", [math.degrees(x) for x in strip_inc], f"washout part {[round(-W['washout_deg'] * (e - eta_bar), 2) for e in strip_eta]} deg; the most positive strip stalls first")
CL_max = note("aero", "CL_max", CL_max, "mean of the strips' CL*: the wing stalls progressively around it (blend width below); full-size airplane 1.5 at Re 1.3e7 (NACA XP-51 report), the model's Re 2.5-7e5 lowers it")
Vs = note("aero", "1-g stall (m/s)", math.sqrt(2 * mass * G0 / (RHO * S * CL_max)), "flight mass, CL_max")
V_start = note("aero", "start speed (m/s)", round(1.6 * Vs), "1.6 x the 1-g stall, rounded: the trimmed in-air start")
CL_ref = note("aero", "CL_ref", mass * G0 / (0.5 * RHO * V_start ** 2 * S), "level flight at the start speed; CL-dependent cross terms are frozen there")

# --- Lateral-directional ----------------------------------------------------------------------------------------
cg_model_z, cg_model_y = cg[0] + LE0, cg[2]
l_v = xv_ac - cg_model_z
z_v = fin_cy - cg_model_y
AR_v = note("lateral", "fin effective AR", 1.55 * h_v * h_v / Sv, "geometric h2/Sv x 1.55 end-plate factor (fuselage + stab, DATCOM range 1.4-1.7)")
mid_station = next(r for r in st if r[0] >= 0.3 * cr)
z_w = cp_y - (mid_station[2] + mid_station[3]) / 2
sidewash = note("lateral", "(1 + dsigma/dbeta) eta_v", 0.724 + 3.06 * (Sv / S) / 2 + 0.4 * (-z_w) / fus_d + 0.009 * AR,
                "Nelson/DATCOM: 0.724 + 3.06 (Sv/S)/(1 + cos sweep) + 0.4 z_w/d + 0.009 AR (low wing: z_w down positive)")
slope_v = note("lateral", "effective fin slope (1/rad)", helmbold(AR_v, 0.9) * sidewash, "")
tau_r = flap_tau(cf_r) * k_flap
ce_v = note("lateral", "rudder effectiveness (local)", tau_r / sidewash, f"tau {tau_r:.3f} / sidewash factor")
CYb_v = -slope_v * Sv / S
fus_x0_area = 0.8 * fus_w * fus_d
CYb_B = note("lateral", "CYb body (1/rad)", -2 * 1.3 * fus_x0_area / S, "-2 K_i S0/S, K_i 1.3 low wing (DATCOM), S0 0.8 w d")
arm_v_arp = xv_ac - x_arp
CYdr = slope_v * Sv / S * ce_v
Cnb = slope_v * Sv / S * arm_v_arp / b
Cndr = -CYdr * arm_v_arp / b
Cldr = CYdr * (fin_cy - arp_y) / b
note("lateral", "Cnb body, omitted (1/rad)", -0.001 * 1.4 * 57.3 * (0.6 * fus_len * fus_d / S) * (fus_len / b),
     "DATCOM -K_N K_Rl (S_side/S)(L/b): destabilizing; not in v1 (Cnb must equal the fin term), same as the Stik and Extra")
Clb_dihedral = note("lateral", "Clb dihedral (1/rad)", -CLa_w * dihedral * (1 + 2 * lam) / (6 * (1 + lam)), "strip theory: -CLa_w Gamma (1 + 2 lambda) / (6 (1 + lambda)); 5 deg geometric dihedral")
dihedral_low = note("lateral", "Clb low-wing interference (1/rad)", 1.2 * math.sqrt(AR) * (-z_w / b) * (2 * fus_d / b),
                    "DATCOM: 1.2 sqrt(AR) (z_w/b)(2d/b), destabilizing for a low wing")
Clb_wing = note("lateral", "Clb wing sweep/taper at CL_ref (1/rad)", -0.03 * CL_ref, "DATCOM Clb/CL ~ -0.0005/deg for an unswept AR 5.8 taper 0.48 wing (estimated)")
Clb = Clb_wing + Clb_dihedral + dihedral_low + CYb_v * z_v / b
Clp = -(CLa_w / 12) * (1 + 3 * lam) / (1 + lam) - eta_h * (CLa_h / 12) * (Sh / S) * (bh / b) ** 2 * (1 + 3 * lh_) / (1 + lh_) + 2 * CYb_v * (z_v / b) ** 2
Clr = CL_ref / 4 - 2 * l_v * z_v / b ** 2 * CYb_v
Cnp = -CL_ref / 8 - 2 * l_v * z_v / b ** 2 * CYb_v
Cnr = -0.25 * 0.03 + 2 * (l_v / b) ** 2 * CYb_v - 0.02
CYp = 2 * CYb_v * z_v / b
CYr = -2 * CYb_v * l_v / b
K_adv = 0.15
Cnda = -2 * K_adv * CL_ref * Clda
tail_q = CLa_h * eta_h * Sh / S
CLq = 2 * tail_q * l_h / c_ref + (0.5 + 2 * (cg_model_z - x_ac_w) / mac) * CLa_w * mac / c_ref
Cmq = -2 * tail_q * (xh_ac - cg_model_z) ** 2 / c_ref ** 2 * 1.1
CLadot = 2 * tail_q * l_h / c_ref * deps
th_a = math.acos(2 * cf_a - 1)
cp_frac = 0.25 + 0.5 * math.sin(th_a) * (1 - math.cos(th_a)) / (2 * (math.pi - th_a + math.sin(th_a)))
x_cp_ail = sum((W["le_z_root"] + le_slope * y + cp_frac * chord(y)) * chord(y) for y in ys) / sum(chord(y) for y in ys)
Cmda = -CLda_each * (x_cp_ail - x_arp) / c_ref

# --- Drag build-up ---------------------------------------------------------------------------------------------
V = V_start
cf_mix = lambda L, lam_frac: lam_frac * 1.328 / math.sqrt(V * L / NU) + (1 - lam_frac) * 0.455 / math.log10(V * L / NU) ** 2.58
exposed_wing = S - fus_w * cr
tc = W["root_thickness_ratio"] * 0.6 + W["tip_thickness_ratio"] * 0.4
scoop_side = sum((r1[0] - r0[0]) * (-(r0[2] + r1[2]) / 2 - 0.1) for r0, r1 in zip(g["scoop_stations"], g["scoop_stations"][1:]))
parts = {
    "wing": cf_mix(mac, 0.3) * (1 + 0.6 / 0.4 * tc + 100 * tc ** 4) * 2.04 * exposed_wing,
    "tails": cf_mix(0.22, 0.3) * 1.10 * 2.03 * (Sh + Sv),
    "fuselage": cf_mix(fus_len, 0.1) * (1 + 60 / (fus_len / fus_d) ** 3 + (fus_len / fus_d) / 400) * (0.85 * 2 * (fus_w + fus_d) * fus_len),
    "belly scoop (wetted + inlet spill)": cf_mix(1.0, 0.1) * 1.3 * (2.5 * scoop_side) + 0.004,
    "gear down: wheels, struts, doors": 0.020,
    "cooling flow, exhausts, cowl leaks": 0.006,
}
D_q = sum(parts.values()) * 1.1
CD0 = note("drag", "CD0", D_q / S, f"skin friction (30 % laminar on surfaces) x form factors (Raymer ch. 12) + scoop + gear DOWN + cooling, x1.1 excrescences: " + ", ".join(f"{k} {v:.4f} m2" for k, v in parts.items()))
e_osw = note("drag", "Oswald e", 0.75, "full-size P-51D 0.70-0.75 (Loftin, NASA SP-468: L/D max 14.6 with CD0 0.0163); no measured value")
k_ind = 1 / (math.pi * e_osw * AR)


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


# --- Propeller: blade-element / momentum model (research/p51/p51-06/bem.py), calibrated on Mejzlik tables -------
sys.path.insert(0, str(ROOT / "research/p51/p51-06"))
from bem import bem_tables  # noqa: E402


calib = json.load(open(ROOT / "research/p51/p51-06/calibration.json"))
mejz = json.load(open(ROOT / "research/p51/p51-06/mejzlik_26x12.json"))
ct_table, cp_table = bem_tables(PROP["diameter"], PROP["pitch"], PROP["blades"], PROP["blade"]["chord_fraction_of_radius"],
                                pitch_factor=calib["pitch_factor"], chord_factor=calib["chord_factor"], j_max=1.6)
Ct0, Cp0 = ct_table[0][1], cp_table[0][1]
note("propulsion", "BEM calibration (pitch x, chord x, rms)", [calib["pitch_factor"], calib["chord_factor"], calib["rms_relative_error"]],
     "fitted to Mejzlik's manufacturer-simulated 26x12 2-blade and 3-blade tables together (research/p51/p51-06/fit_mejzlik.py); the 4-blade is the calibrated model's prediction (no 4-blade gas datasheet exists)")
note("propulsion", "BEM Ct0 / Cp0 / J at zero thrust", [Ct0, Cp0, next(r[0] for r in ct_table if r[1] <= 0)], f"4-blade {KIT['propeller']['diameter_in']:.0f}x{KIT['propeller']['pitch_in']:.0f}")

# --- Engine (shaft balance, P51-06) -----------------------------------------------------------------------------------
# Full-throttle torque shape of a carburetted two-stroke twin (x = rpm / 6900): estimated, no DA-120 dyno curve is
# published (desertaircraft.com gives 11.7 hp and 1300-6900 rpm only; UST magazine: the DA family has a flat, high
# torque curve). Level set by the one measured anchor: a 28x10 turns 6550 rpm static on a DA-120 (Falcon spec;
# Mejzlik 28x10 6400-6850, DLE-120 6350-6450), where Mejzlik's 28x10 static Cp 0.0238 absorbs the engine's power.
TORQUE_SHAPE = [(0.0, 0.70), (0.2, 0.75), (0.4, 0.85), (0.6, 0.95), (0.75, 1.0), (0.9, 0.97), (1.0, 0.92), (1.1, 0.80), (1.25, 0.55), (1.4, 0.25)]
N_REF = 6900.0
shape = lambda rpm: next((a[1] + (b_[1] - a[1]) * (rpm / N_REF - a[0]) / (b_[0] - a[0]) for a, b_ in zip(TORQUE_SHAPE, TORQUE_SHAPE[1:]) if a[0] <= rpm / N_REF <= b_[0]), TORQUE_SHAPE[-1][1])
anc = mejz["anchor_28x10_2B"]
n_anchor = anc["static_rpm_on_DA120"] / 60
P_anchor = note("propulsion", "installed power at 6550 rpm (W)", anc["static_Cp"] * RHO * n_anchor ** 3 * anc["diameter_m"] ** 5,
                "Mejzlik 28x10 static Cp 0.0238 at the measured 6550 rpm static on a DA-120 (" + anc["static_rpm_source"] + ")")
Q0 = P_anchor / (shape(anc["static_rpm_on_DA120"]) * 2 * math.pi * n_anchor)
power_curve = [[float(r), Q0 * shape(r) * 2 * math.pi * r / 60] for r in range(1000, 9001, 500)]
P_peak = note("propulsion", "installed peak power (W)", max(p_[1] for p_ in power_curve),
              f"at {max(power_curve, key=lambda p_: p_[1])[0]:.0f} rpm; the catalogue's 11.7 hp ({11.7 * 745.7:.0f} W) is {100 * (11.7 * 745.7 / max(p_[1] for p_ in power_curve) - 1):.0f} % higher (stock mufflers and cowl installation vs the maker's rating)")
FRICTION = [0.5, 0.14]  # N·m, N·m per 1000 rpm: ~12 % of the brake torque at 6900 rpm (YASim uses 8 %, research synthesis 10-15 %)
q_fric = lambda rpm: FRICTION[0] + FRICTION[1] * rpm / 1000
IDLE_RPM = 1400.0  # static idle (DA-120 range starts at 1300; a reliable idle with a large propeller sits a little above)
q_prop_static = lambda rpm: Cp0 * RHO * (rpm / 60) ** 2 * PROP["diameter"] ** 5 / (2 * math.pi)
idle_power = note("propulsion", "idle admitted power (W)", (q_prop_static(IDLE_RPM) + q_fric(IDLE_RPM)) * 2 * math.pi * IDLE_RPM / 60,
                  f"closed throttle: holds the propeller at {IDLE_RPM:.0f} rpm static against its torque plus friction")
peak_ind = max(p_[1] + q_fric(p_[0]) * 2 * math.pi * p_[0] / 60 for p_ in power_curve)
# Static full-throttle rpm: brake torque = propeller torque.
lo, hi = 1000.0, 8000.0
for _ in range(80):
    mid = 0.5 * (lo + hi)
    lo, hi = (mid, hi) if Q0 * shape(mid) > q_prop_static(mid) else (lo, mid)
rpm_static = note("propulsion", "static rpm", 0.5 * (lo + hi), "full-throttle torque meets the 4-blade's static torque")
n_static = rpm_static / 60
thrust_static = Ct0 * RHO * n_static ** 2 * PROP["diameter"] ** 4
note("propulsion", "static thrust (N, kgf) and thrust/weight", [thrust_static, thrust_static / G0, thrust_static / (mass * G0)],
     "research estimate for a 4-blade 26x12 on a DA-120: 5000-5400 rpm, ~25 kgf (P51-09)")
# Rotating inertia: Mejzlik's per-blade estimates (26x12 2B 7.16e-3, 3B 1.42e-2 kg m2) x 4, the spinner shell and the
# crankshaft with the ignition flywheel.
blade_j = (mejz["props"]["26x12 2B GAS"]["inertia_kgm2"] / 2 + mejz["props"]["26x12 3B GAS N"]["inertia_kgm2"] / 3) / 2
rotor_j = note("propulsion", "rotating inertia (kg m2)", 4 * blade_j + 0.35 * (g["spinner"]["radius"] * 0.8) ** 2 / 2 + 0.002,
               "4 x Mejzlik's mean per-blade inertia (26x12 2B/3B datasheets) + aluminium spinner shell + crank and flywheel 0.002 (estimated)")

# --- Slipstream on the tail (E0b first slice, P51-12) -------------------------------------------------------------
# Geometry only here; the wake itself (momentum theory, swirl) is computed in the simulation (physics/slipstream.gd).
hub = le(PROP["z"])  # propeller disc centre on the thrust line
x_fin = xv_ac
fin_root_y = fus_top(x_fin)  # the fuselage blocks the wash below its top line
fin_te_at = lambda y: T["rudder_te_bottom"][0] + (fin_top_te - T["rudder_te_bottom"][0]) * (y - T["rudder_te_bottom"][1]) / (T["fin_top_y"] - T["rudder_te_bottom"][1])
fin_chords = [fin_te_at(fin_root_y) - fin_le_at(fin_root_y), fin_te_at(T["fin_top_y"]) - fin_le_at(T["fin_top_y"])]
note("slipstream", "fin piece: root height, span, chords (m)", [fin_root_y, T["fin_top_y"] - fin_root_y] + fin_chords, "from the fuselage top at the fin ac to the fin tip; LE/TE lines of the fin polygon")
slip_pieces = [
    {"surface": "vertical", "area": Sv, "root": le(x_fin, fin_root_y), "span_dir": [0.0, 0.0, 1.0], "span": T["fin_top_y"] - fin_root_y, "chords": fin_chords},
    {"surface": "horizontal", "area": Sh / 2, "root": le(xh_ac, T["stab_y"]), "span_dir": [0.0, 1.0, 0.0], "span": hs, "chords": [crh, cth]},
    {"surface": "horizontal", "area": Sh / 2, "root": le(xh_ac, T["stab_y"]), "span_dir": [0.0, -1.0, 0.0], "span": hs, "chords": [crh, cth]},
]

# --- Landing gear (E1/E2 contacts, P51-12): taildragger, wheel bottoms from geometry.json ------------------------------
main_r = GEAR["main_wheel_diameter"] / 2
tail_r = GEAR["tail_wheel_diameter"] / 2
main_pos = [le(GEAR["main_axle"][0], GEAR["main_axle"][1] - main_r, s * GEAR["track"] / 2) for s in (-1, 1)]
tail_pos = le(GEAR["tail_axle"][0], GEAR["tail_axle"][1] - tail_r)
three_point = math.degrees(math.atan2(tail_pos[2] - main_pos[0][2], tail_pos[0] - main_pos[0][0]))
note("gear", "three-point attitude (deg)", three_point, "thrust line to the ground with all three wheels down (static, uncompressed)")

# --- Propeller in a crossflow (P51-06): normal force and P-factor -------------------------------------------------
# McCormick's blade-element result as used by Selig (AIAA 2010-7938, eqs. for P_N and N_P; Ribner NACA TR 819 agrees
# within ~20 %), per radian of disc angle of attack, with the free-stream q = ½ρV², V = JnD, A = πD²/4:
#   C̄l = (3J/2π)·[16·Ct/(σπ²J) + C̄d]                         (mean blade lift coefficient from the thrust)
#   C_N = σπJ²/16 · [C̄l + (aJ/2π)·ln(1 + (π/J)²) + (π/J)·C̄d]   (× ρn²D⁴)
#   C_M = σπJ²/32 · [(2π/3J)·C̄l + (a/2)·(1 − (J/π)²·ln(1 + (π/J)²)) − (π/J)·C̄d]   (× ρn²D⁵, nose-left for α > 0)
# σ = blade area / disc area of the calibrated planform, a = 0.9·2π (the BEM section), C̄d 0.02 (research synthesis).
# Not included: the near-static jet ("ram drag") normal force (Selig: for 3D/hover flight).
plan_ = PROP["blade"]["chord_fraction_of_radius"]
sigma = PROP["blades"] * calib["chord_factor"] * sum(0.5 * (a[1] + b_[1]) * (b_[0] - a[0]) for a, b_ in zip(plan_, plan_[1:])) / math.pi
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
note("propulsion", "solidity; C_N, C_M at J 0.3 and 0.5", [sigma, next(r[1] for r in nf_rows if r[0] >= 0.3), next(r[1] for r in pm_rows if r[0] >= 0.3), next(r[1] for r in nf_rows if r[0] >= 0.5), next(r[1] for r in pm_rows if r[0] >= 0.5)], "per rad; x rho n2 D4 and x rho n2 D5")
THRUST_ANGLES = [1.75, 1.0]  # deg down, right
note("propulsion", "thrust angles down, right (deg)", THRUST_ANGLES, "down 1.75 deg: Top Flite Giant P-51D manual (geometry.json visual down thrust); right 1 deg: Ziroli 98 in plans (ziroligiantscaleplans.com, 1 deg right and 1 deg down); the full-size thrust line angles are not published")

# Gear (E1/E2 contacts): stiffness from the E1 rule (heave ω·dt = 0.09 at 240 Hz), split by static load so the
# airplane sits at its three-point attitude; ζ 0.3 (sprung oleo legs, little damping); tyres as the Stik's E2 values
# with a lower rolling resistance for the 6.75 in wheels.
x_m, x_t = main_pos[0][0], tail_pos[0]
tail_share = (cg[0] - x_m) / (x_t - x_m)
k_total = (0.09 * 240) ** 2 * mass
k_main, k_tail = k_total * (1 - tail_share) / 2, k_total * tail_share
damp = lambda k_: 2 * 0.3 * math.sqrt(k_ * mass / 3)
note("gear", "tail-wheel load share, sum k (N/m), static sag (mm)", [tail_share, k_total, 1000 * mass * G0 / k_total], "")
GEAR_SRC = "wheel bottom from geometry.json (axle station and height measured on the AN 01-60-3 three-view, track 142 in full size per NACA, wheel 6.75 in)"
gear_contact = lambda name, pos, k_, travel, steer, how: dict({
    "name": name,
    "position": q([float(v) for v in pos], "m", "measured", GEAR_SRC),
    "stiffness": q(k_, "N/m", "estimated", f"E1 rule: heave ω·dt 0.09 at 240 Hz (Σk = {k_total:.0f} N/m for {mass:.2f} kg), split by the static load ({100 * tail_share:.1f} % on the tail wheel) so all three wheels sag alike ({1000 * mass * G0 / k_total:.0f} mm); softer than a real oleo, which a 240 Hz explicit tick cannot resolve"),
    "damping": q(damp(k_), "N·s/m", "estimated", "damping ratio 0.3 of the loader's m/3 share: sprung oleo legs and tyres, little hydraulic damping in RC retract struts"),
    "max_compression": q(travel, "m", "estimated", how),
}, **({"max_steering": q(steer, "deg", "estimated", "steerable tail wheel linked to the rudder, +-25 deg typical for giant-scale retract tail wheels; negative: the tail wheel turns against the rudder trailing edge")} if steer else {}))
landing_gear = {
    "description": "P51-12: taildragger, two main wheels and a steerable tail wheel (E1 spring-dampers, E2 tyre friction, E3 field surfaces). Retracts are not simulated: the gear stays down.",
    "contacts": [
        gear_contact("main_left", main_pos[0], k_main, 0.12, 0, "breaking travel: a level touchdown at about 2.5 m/s sink reaches it (½mv² against the springs with the static sag); RC practice, not measured"),
        gear_contact("main_right", main_pos[1], k_main, 0.12, 0, "breaking travel: a level touchdown at about 2.5 m/s sink reaches it (½mv² against the springs with the static sag); RC practice, not measured"),
        gear_contact("tail", tail_pos, k_tail, 0.08, -25.0, "tail-wheel leg travel before the fuselage hits: estimated"),
    ],
    "rolling_resistance": q(0.03, "1", "estimated", "between a full-size tyre on concrete (JSBSim c172x 0.022) and the Stik's 76 mm wheel (0.04): the 171 mm wheels deform less; per-surface factors (grass) come from the field"),
    "side_friction": q(0.8, "1", "borrowed", "JSBSim c172x static_friction 0.8 (as the Stik, E2)"),
    "peak_slip_angle": q(6.0, "deg", "borrowed", "JSBSim FGLGear default Pacejka initial slope (as the Stik, E2)"),
}

# --- Assemble -----------------------------------------------------------------------------------------------------
stik = json.load(open(STIK))
D = lambda how: f"{SCRIPT}: {how}"
coeff = lambda v, unit, kind, how: q(float(v), unit, kind, D(how) if kind == "derived" else how)
coefficients = {
    "CL0": coeff(CL0, "1", "derived", "cambered wing at +1 deg incidence + tail at zero body alpha"),
    "CLa": coeff(CLa, "1/rad", "derived", "Helmbold wing x cos2(dihedral) + downwashed tail"),
    "CLadot": coeff(CLadot, "1/rad", "derived", "2 eta CLa_h Sh/S l_h/c deps/dalpha"),
    "CLq": coeff(CLq, "1/rad", "derived", "tail volume + DATCOM wing term"),
    "CLde": coeff(CLde, "1/rad", "derived", "tail slope x elevator effectiveness"),
    "CLda_each": coeff(CLda_each, "1/rad", "derived", "strip theory over the aileron span"),
    "CD0": coeff(CD0, "1", "derived", f"component drag build-up at {V_start} m/s with the gear DOWN (retracts not simulated), see derivation.md"),
    "CL_minD": coeff(CL0_w * 0.5, "1", "estimated", "cambered laminar section: minimum drag near half the zero-alpha wing lift"),
    "k_induced": coeff(k_ind, "1", "derived", "1/(pi e AR), e 0.80 estimated"),
    "CDda_each": q(stik["aero"]["coefficients"]["CDda_each"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file); second-order control drag"),
    "CDdr": q(stik["aero"]["coefficients"]["CDdr"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file); second-order control drag"),
    "CDde": q(stik["aero"]["coefficients"]["CDde"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file); second-order control drag"),
    "CYb": coeff(CYb_v + CYb_B, "1/rad", "derived", "fin + DATCOM body"),
    "CYp": coeff(CYp, "1/rad", "derived", "fin above the CG"),
    "CYr": coeff(CYr, "1/rad", "derived", "fin behind the CG"),
    "CYdr": coeff(CYdr, "1/rad", "derived", "fin slope x Sv/S x rudder effectiveness (must equal the vertical surface)"),
    "Clb": coeff(Clb, "1/rad", "derived", "5 deg dihedral (strip theory) + wing at CL_ref + low-wing interference + fin"),
    "Clp": coeff(Clp, "1/rad", "derived", "strip theory with taper + stab + fin"),
    "Clr": coeff(Clr, "1/rad", "derived", "CL_ref/4 + fin"),
    "Clda_right": coeff(Clda, "1/rad", "derived", "strip theory"),
    "Clda_left": coeff(-Clda, "1/rad", "derived", "strip theory"),
    "Cldr": coeff(Cldr, "1/rad", "derived", "rudder side force x fin height above the ARP"),
    "Cm0": coeff(Cm0, "1", "derived", "wing Cm_ac (parabolic camber) + tail at zero body alpha, about the ARP"),
    "Cma": coeff(Cma, "1/rad", "derived", "tail about the wing-body ac; the CG transfer gives the static margin"),
    "Cmq": coeff(Cmq, "1/rad", "derived", "tail damping about the CG (undownwashed tail slope) x1.1 for wing/fuselage"),
    "Cmde": coeff(Cmde, "1/rad", "derived", "elevator lift x tail arm from the ARP"),
    "Cmda_each": coeff(Cmda, "1/rad", "derived", "aileron lift increment at its thin-airfoil centre, arm from the ARP"),
    "Cnb": coeff(Cnb, "1/rad", "derived", "fin only (v1 contract: equals the vertical surface)"),
    "Cnp": coeff(Cnp, "1/rad", "derived", "-CL_ref/8 + fin"),
    "Cnr": coeff(Cnr, "1/rad", "derived", "fin + wing profile drag + fuselage (-0.02 estimated)"),
    "Cnda_right": coeff(Cnda, "1/rad", "derived", "adverse yaw 2 K CL_ref Clda, K 0.15 (Nelson, AR 5.8, taper 0.48)"),
    "Cnda_left": coeff(-Cnda, "1/rad", "derived", "adverse yaw"),
    "Cndr": coeff(Cndr, "1/rad", "derived", "rudder side force x fin arm from the ARP (must equal the vertical surface)"),
}
surf = stik["aero"]["surfaces"]
same = lambda key: dict(surf[key], source="same provisional value as the Ugly Stik surface model (" + surf[key]["source"].split(";")[-1].strip() + ")", kind=surf[key]["kind"] if surf[key]["kind"] != "derived" else "estimated")
canopy_top = max(g["canopy"]["top"], key=lambda p: p[1])
data = {
    "format": "openrc-aircraft v1",
    "id": "p51d-mustang-120",
    "description": f"{KIT_NAME}: {b:.3f} m span giant-scale P-51D Mustang, 120 cc gasoline. EXPERIMENTAL first physics estimate (P51-05), generated by {SCRIPT} from full-size dimensions scaled to the kit; not flight-identified. Flaps and retracts are not simulated (gear DOWN drag). Visual geometry lives in assets/aircraft/p51d-mustang-120/geometry.json.",
    "frames": {
        "le_frame": "positions in metres from the wing leading edge at the centreline (model z 0): [x_aft, y_right, z_up]; z = 0 on the thrust line (spinner axis)",
        "body": "simulation body axes FRD about the CG: x forward = -x_aft, y right, z down = -z_up",
    },
    "reference": {
        "wing_area": q(S, "m2", "derived", D("trapezoid span x (root + tip) / 2 from " + GEO_SRC)),
        "wing_span": q(b, "m", "estimated", f"kit span, {KIT_NAME} (source.json)"),
        "mean_chord": q(c_ref, "m", "derived", f"S / b: the v1 coefficient reference length. NOT the MAC ({mac:.4f} m at {y_mac:.4f} m span)"),
        "root_chord": q(cr, "m", "derived", "104 in full-size root chord x scale, " + GEO_SRC),
        "tip_chord": q(ct, "m", "derived", "50 in full-size tip chord x scale, " + GEO_SRC),
        "aero_reference_point": q(le(x_arp, arp_y), "m", "derived", D("wing-body aerodynamic centre: 25 % MAC moved forward by the fuselage (Raymer K_fus); on the wing chord plane")),
        "planform": "tapered",
    },
    "start": {"level_speed": q(float(V_start), "m/s", "derived", D("1.6 x the 1-g stall at the flight mass and CL_max, rounded"))},
    "balance": {
        "plan_cg": q(cg, "m", "estimated", f"{100 * cg_mac:.0f} % MAC (kit placeholder, source.json) = model z {cg_z_model:.4f}; z from the inventory (derived)"),
        "firewall": q(le(rc_fw), "m", "estimated", "the model's engine-box firewall: spinner back + 0.25 m (a 120 cc twin on standoffs); the scaled full-size firewall is only the cowl split"),
        "configuration": "virtual-balanced-reference-v1",
        "cg_tolerance": q(0.001, "m", "estimated", D("virtual reference build balanced to the kit's point, NOT a measured airplane")),
    },
    "inventory": [
        dict({"name": it[0], "mass": q(float(it[1]), "kg", it[2], it[3] + (f"; x{k_total_struct:.3f}: airframe scaled to the built weight (P51-09)" if is_structure(it) else "")), "position": q([float(v) for v in it[4]], "m", it[6], it[7])},
             **({"size": q([float(v) for v in it[5]], "m", "estimated", "rough envelope for intrinsic inertia")} if it[5] else {}))
        for it in items
    ],
    "crash_hull": q([
        le(W["le_z_tip"], cp_y + semi * math.tan(dihedral), -semi), le(W["le_z_tip"], cp_y + semi * math.tan(dihedral), semi),
        le(W["le_z_tip"] + ct, cp_y + semi * math.tan(dihedral), -semi), le(W["le_z_tip"] + ct, cp_y + semi * math.tan(dihedral), semi),
        le(g["spinner"]["tip_z"]),
        le(PROP["z"], -PROP["diameter"] / 2), le(PROP["z"], -PROP["diameter"] / 2 * 0.7071, -PROP["diameter"] / 2 * 0.7071), le(PROP["z"], -PROP["diameter"] / 2 * 0.7071, PROP["diameter"] / 2 * 0.7071),
        le(T["rudder_te_bottom"][0], T["rudder_te_bottom"][1]),
        le(T["stab_tip_le_z"] + cth, T["stab_y"], -hs), le(T["stab_tip_le_z"] + cth, T["stab_y"], hs),
        le(fin_top_te, T["fin_top_y"]),
        le(canopy_top[0], canopy_top[1]),
        le(g["scoop_stations"][2][0], g["scoop_stations"][2][2]),
    ], "m", "derived", "Points that hit the ground first (le frame) from " + GEO_SRC + ": wing tip LE/TE (with dihedral), spinner tip, propeller disc bottom and lower quarters (a prop strike), rudder bottom TE, stab tips, fin top, canopy top, scoop bottom. The wheels are landing-gear contacts (P51-12)"),
    "plausibility": {
        "mass_range": q([float(lo_m) - 1.5, float(hi_m) + 2.0], "kg", "estimated", f"kit flying mass range {lo_m}-{hi_m} kg (source.json; CARF 2.54 m: 15-17 kg dry), widened for fuel and the virtual balancing mass of the reference build"),
        "inertia_reference": stik["plausibility"]["inertia_reference"],
    },
    "controls": {
        "max_throw": {k: q(float(v), "deg", "estimated", "asin(kit mm / local chord): " + KIT["throws_note"]) for k, v in throws.items()},
        "servo_full_throw_time": q(0.18, "s", "estimated", "giant-scale high-torque servos: 0.15-0.20 s per 60 deg at 6-7 V"),
    },
    "aero": {
        "source": f"Derived from the scaled geometry by {SCRIPT} (Helmbold/DATCOM, tail volume, strip theory, drag build-up); report research/p51/p51-05/derivation.md. Not flight-identified: EXPERIMENTAL.",
        "envelope": {
            "CL_max": q(CL_max, "1", "estimated", "15 % laminar section clmax ~1.3 at Re 7e5 x 0.9 for the wing, flaps up; no polar identified"),
            "CL_min": q(-0.85, "1", "estimated", "cambered section: inverted stall earlier than upright"),
            "stall_blend_width": q(6.0, "deg", "estimated", "NACA TN 1945: at Re 0.7-1e6 the 15 % 6-series stall is rounded (cl flat over ~4 deg, mild drop); which part of the span stalls first comes from the strip offsets (aero.surfaces.wing_station_incidence)"),
            "CD90": q(1.11 + 0.018 * AR, "1", "derived", "Viterna CDmax = 1.11 + 0.018 AR (NASA CR-1983)"),
            "sideslip_blend": stik["aero"]["envelope"]["sideslip_blend"],
        },
        "conventions": stik["aero"]["conventions"],
        "coefficients": coefficients,
        "surfaces": {
            "wing_aileron_effectiveness": q(wing_ail_eff, "1", "derived", D("|Clda_right| 2n b / (CLa sum(y)) over the loader's equal-area tapered strips")),
            "wing_station_incidence": q([float(x) for x in strip_inc], "rad", "derived", D("per-strip angle offsets root -> tip, zero mean: linear washout + Schrenk loading + Re-dependent section clmax (NACA TN 1945); see derivation.md 'stall'")),
            "attached_limit": same("attached_limit"),
            "tail_local_limit": same("tail_local_limit"),
            "tail_stall_end": same("tail_stall_end"),
            "tail_CD0": same("tail_CD0"),
            "tail_k": same("tail_k"),
            "tail_CD90": same("tail_CD90"),
            "horizontal": {
                "area": q(Sh, "m2", "derived", D("stab + elevator trapezoid from " + GEO_SRC)),
                "position": q(le(xh_ac, T["stab_y"]), "m", "derived", D("quarter chord of the stab MAC")),
                "lift_slope": q(slope_h, "1/rad", "derived", D("Helmbold x eta 0.9 x (1 - deps/dalpha)")),
                "control_effectiveness": q(ce_h, "1", "derived", D("thin-airfoil tau x 0.8 / (1 - deps/dalpha)")),
                "incidence": q(inc_eff, "rad", "derived", D("(stab incidence - eps0) / (1 - deps/dalpha)")),
            },
            "vertical": {
                "area": q(Sv, "m2", "derived", D("fin + rudder side polygon from " + GEO_SRC)),
                "position": q(le(xv_ac, fin_cy), "m", "derived", D("fin ac: quarter chord at the area-centroid height")),
                "lift_slope": q(slope_v, "1/rad", "derived", D("Helmbold (end-plated AR) x DATCOM sidewash/eta")),
                "control_effectiveness": q(ce_v, "1", "derived", D("thin-airfoil tau x 0.8 / sidewash factor")),
                "incidence": q(0.0, "rad", "estimated", "symmetric fin; engine side thrust not modelled"),
            },
        },
    },
    "propulsion": {
        "description": f"120 cc gasoline twin turning a 4-blade {KIT['propeller']['diameter_in']:.0f}x{KIT['propeller']['pitch_in']:.0f}. Shaft balance (rpm from engine torque against propeller torque), blade-element tables calibrated on Mejzlik's 26x12 2- and 3-blade data, down and right thrust, propeller normal force and P-factor, tail slipstream with swirl ({SCRIPT}, P51-06/P51-12).",
        "engine": {
            "name": "Desert Aircraft DA-120 (121 cc twin, 2.45 kg with ignition) or DLE-120",
            "peak_power": q(11.7 * 745.7, "W", "manual", "DA-120 11.7 hp, desertaircraft.com/products/da-120 (2026-10-06): the maker's rating; the installed curve below is lower"),
            "peak_power_rpm": q(6900.0, "rpm", "manual", "DA-120 top of the 1300-6900 rpm range (desertaircraft.com)"),
            "max_rpm_static": q(rpm_static, "rpm", "derived", D("full-throttle shaft balance at rest (shaft model)")),
            "idle_rpm": q(IDLE_RPM, "rpm", "estimated", "static idle: DA-120 range starts at 1300 rpm (desertaircraft.com); set a little above for a large propeller"),
            "lag_time_constant": q(0.6, "s", "estimated", "D5 lag model, unused while the shaft model is present (kept for the format)"),
            "shaft": {
                "power_curve": {"value": [[r, round(w_, 1)] for r, w_ in power_curve], "unit": "rpm, W", "kind": "derived",
                                "source": D("installed full-throttle brake power: generic two-stroke torque shape (estimated; no DA-120 dyno curve published) scaled to the measured anchor, a 28x10 at 6550 rpm static (Mejzlik 28x10 Cp 0.0238 -> %.0f W)" % P_anchor)},
                "friction_torque": q(FRICTION, "N·m, N·m/krpm", "estimated", "friction and pumping ~12 % of the brake torque at 6900 rpm (YASim 8 %; research synthesis 10-15 %)"),
                "idle_power": q(idle_power, "W", "derived", D(f"closed-throttle admitted power: holds {IDLE_RPM:.0f} rpm static")),
                "peak_indicated_power": q(peak_ind, "W", "derived", D("brake + friction power at the curve's peak: the open throttle never limits")),
            },
        },
        "propeller": {
            "name": f"4-blade {KIT['propeller']['diameter_in']:.0f}x{KIT['propeller']['pitch_in']:.0f} (scale look; heavy for a 120 cc: Biela rates its 26x12 4-blade for 150-160 cc, the DA-120 list gives 3-blade 26x12 / 27x12)",
            "diameter": q(PROP["diameter"], "m", "estimated", f"{KIT['propeller']['diameter_in']:.0f} in (source.json)"),
            "rotation": "clockwise seen from behind (standard tractor): the reaction torque rolls the airplane left",
            "ct_table": q(ct_table, "1", "derived", D("blade-element/momentum (research/p51/p51-06/bem.py), pitch x%.3f and chord x%.3f fitted to Mejzlik 26x12 2B/3B tables (rms %.1f %%); tabulated into the windmilling branch" % (calib["pitch_factor"], calib["chord_factor"], 100 * calib["rms_relative_error"]))),
            "cp_table": q(cp_table, "1", "derived", D("same calibrated blade-element model; Cp < 0 = windmilling")),
            "rotating_inertia": q(rotor_j, "kg·m2", "estimated", "4 x Mejzlik's mean per-blade inertia (26x12 2B/3B datasheets) + spinner shell + crank and flywheel 0.002"),
            "thrust_line_offset": q([hub[0] - cg[0], 0.0, hub[2] - cg[2]], "m", "derived", D("propeller disc centre (thrust line) relative to the inventory CG; [x_aft, y_right, z_up]")),
            "thrust_angles": q(THRUST_ANGLES, "deg", "estimated", "down 1.75 deg (Top Flite Giant P-51D manual), right 1 deg (Ziroli 98 in plans); no published full-size or 1/4-scale value"),
            "normal_force": q(nf_rows, "1", "derived", D(f"McCormick blade-element normal force per rad of disc angle of attack (Selig, AIAA 2010-7938), x rho n2 D4; solidity {sigma:.3f}")),
            "pfactor_moment": q(pm_rows, "1", "derived", D("McCormick P-factor yawing moment per rad of disc angle of attack (Selig, AIAA 2010-7938), x rho n2 D5")),
            "slipstream": {
                "hub": q(hub, "m", "derived", D("propeller disc centre on the thrust line (le frame)")),
                "wash_factor": q([0.8, 1.8], "1", "borrowed", "velocity added at the tail per disc induced velocity w: 0.8 static, 1.8 at mass-flow ratio >= 0.75 (Selig, AIAA 2010-7938, Fig. 5; ideal 2)"),
                "swirl_factor": q(0.6, "1", "estimated", "part of the propeller's angular momentum that reaches the tail (wing and fuselage straighten the rest): research synthesis 0.5-0.8; Selig: the swirl offsets ~40 % of the torque roll"),
                "vertical_drift": q(1 - deps, "1", "derived", D("1 - d(eps)/d(alpha): the wake drifts with the downwashed flow")),
                "pieces": [{k: (q(v, "m2" if k == "area" else ("1" if k == "span_dir" else "m"), "derived", D("tail piece from geometry.json")) if k != "surface" else v) for k, v in pc.items()} for pc in slip_pieces],
            },
        },
    },
    "landing_gear": landing_gear,
}


def check_consistency(d):
    fin_ = d["aero"]["surfaces"]["vertical"]
    arp = d["reference"]["aero_reference_point"]["value"]
    S_, b_ = d["reference"]["wing_area"]["value"], d["reference"]["wing_span"]["value"]
    cy = fin_["lift_slope"]["value"] * fin_["area"]["value"] / S_ * fin_["control_effectiveness"]["value"]
    arm = fin_["position"]["value"][0] - arp[0]
    exp = {"CYdr": cy, "Cndr": -cy * arm / b_, "Cldr": cy * (fin_["position"]["value"][2] - arp[2]) / b_,
           "Cnb": fin_["lift_slope"]["value"] * fin_["area"]["value"] / S_ * arm / b_}
    for k, v in exp.items():
        d["aero"]["coefficients"][k]["value"] = v
    # The loader's trapezoid/area rule (1 %) must hold on the rounded values.
    rc, tc_ = d["reference"]["root_chord"]["value"], d["reference"]["tip_chord"]["value"]
    assert abs(b_ * (rc + tc_) / 2 - S_) / S_ < 0.01 and abs(b_ * d["reference"]["mean_chord"]["value"] - S_) / S_ < 0.01


check_consistency(data)

text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
rows = ["| Section | Quantity | Value | How |", "| --- | --- | --- | --- |"]
for sec, name, val, how in log:
    v = ", ".join(f"{x:.4g}" for x in val) if isinstance(val, list) else f"{val:.4g}"
    rows.append(f"| {sec} | {name} | {v} | {how} |")
coef_rows = ["| Coefficient | Value | Kind |", "| --- | --- | --- |"] + [f"| {k} | {v['value']:.5g} | {v['kind']} |" for k, v in data["aero"]["coefficients"].items()]
prop_rows = ["| J | Ct | Cp |", "| --- | --- | --- |"] + [f"| {ct[0]:.2f} | {ct[1]:.4f} | {cp[1]:.4f} |" for ct, cp in zip(ct_table, cp_table)]
report = f"""# P51-05: P-51D Mustang 120 cc physics derivation

Generated by `{SCRIPT}` from `{GEOMETRY.relative_to(ROOT)}` and `source.json`; do not edit (regenerate). Output:
`{OUT.relative_to(ROOT)}`. **Experimental**: textbook estimates from scaled full-size geometry and kit placeholders, not flight
identification. Flaps and retracts are not simulated; the drag build-up assumes the gear DOWN.

Flight mass {mass:.3f} kg, CG {100 * cg_mac:.1f} % MAC, static margin {sm:.1f} % MAC, 1-g stall {Vs:.1f} m/s, start {V_start} m/s.
Throws (Hangar 9 60cc high rates scaled by span): aileron {throws['aileron']:.1f}°, elevator {throws['elevator']:.1f}°, rudder {throws['rudder']:.1f}°.
Propeller: static {rpm_static:.0f} rpm, static thrust {thrust_static:.0f} N ({thrust_static / G0:.1f} kgf), thrust/weight {thrust_static / (mass * G0):.2f}; flown performance (speeds, climb, glide, takeoff) is measured by `app/tests/test_p51_envelope.gd` (P51-08).

## Intermediate quantities

{chr(10).join(rows)}

## Coefficients written (c_ref = S/b; moments about the ARP = wing-body ac)

{chr(10).join(coef_rows)}

## Propeller tables (blade-element/momentum, 4-blade {KIT['propeller']['diameter_in']:.0f}x{KIT['propeller']['pitch_in']:.0f})

{chr(10).join(prop_rows)}

## Known simplifications

- Axial thrust; no engine side/down thrust. Propeller tables are a blade-element estimate with a generic section, not a measurement.
- Flaps fixed up; retracts fixed DOWN for drag (the visual model shows the gear down). No ground contact (crash hull only).
- Fuselage directional destabilization is omitted (v1 contract: Cnb equals the fin term), as for the Stik and the Extra.
- The local (post-stall) wing strips use the whole-airplane CLa, so local lift is ~{100 * slope_h * Sh / S / CLa:.0f} % high (tail counted twice).
- CL-dependent cross terms (Clb wing part, Clr, Cnp, adverse yaw) are frozen at CL_ref = {CL_ref:.2f}.
- The laminar section's camber and thickness are approximations of the NAA 45-100 family; washout 0 by assumption.
"""

if "--dry" in sys.argv:  # print the intermediate table, write nothing
    print("\n".join(rows))
elif "--check" in sys.argv:
    stale = [p for p, t in ((OUT, text), (REPORT, report)) if not p.exists() or p.read_text() != t]
    if stale:
        sys.exit("stale: " + ", ".join(str(p.relative_to(ROOT)) for p in stale) + f" (run {SCRIPT})")
    print("p51d_mustang_120.json and derivation.md are up to date")
else:
    OUT.write_text(text)
    REPORT.write_text(report)
    print(f"wrote {OUT.relative_to(ROOT)} and {REPORT.relative_to(ROOT)}")
    print(f"mass {mass:.3f} kg, CG {100 * cg_mac:.1f} % MAC, SM {sm:.1f} % MAC, stall {Vs:.1f} m/s, start {V_start} m/s, static {rpm_static:.0f} rpm, thrust {thrust_static / G0:.1f} kgf")
