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
i_w = math.radians(W["incidence_deg"])

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
kappa = note("aero", "section lift slope / 2pi", 0.95, "estimated: 15 % laminar section at Re ~7e5 (no polar identified)")
CLa_w = note("aero", "CLa wing (1/rad)", helmbold(AR, kappa, sweep_hc) * math.cos(dihedral) ** 2, "Helmbold/DATCOM x cos2(dihedral)")
AR_h = bh * bh / Sh
CLa_h = note("aero", "CLa horizontal (1/rad)", helmbold(AR_h, 0.9), f"Helmbold, AR {AR_h:.2f}")
eta_h = note("aero", "tail dynamic pressure ratio", 0.9, "estimated; propwash not modelled (ROADMAP E0b)")
deps = note("aero", "d(eps)/d(alpha)", 2 * CLa_w / (math.pi * AR), "elliptic-wing downwash estimate")
slope_h = note("aero", "effective tail slope (1/rad)", CLa_h * eta_h * (1 - deps), "CLa_h eta (1 - deps/dalpha)")
CLa = note("aero", "CLa airplane (1/rad)", CLa_w + slope_h * Sh / S, "wing + tail (wing-body interference ~1 for d/b 0.08)")

x_qc_root = (qc(0) - g["spinner"]["tip_z"]) / fus_len
K_f = note("aero", "K_fus (per deg)", 0.012, f"estimated, Raymer Fig. 16.14 at root quarter chord {100 * x_qc_root:.0f} % of body length (long nose: upper range)")
cma_f_mac = K_f * fus_w ** 2 * fus_len / (mac * S) * 180 / math.pi
dx_f = cma_f_mac / CLa_w * mac
x_ac_w = mac_le_z + 0.25 * mac
x_arp = note("aero", "wing-body ac = ARP (model z)", x_ac_w - dx_f, f"wing ac at 25 % MAC {x_ac_w:.4f}, fuselage moves it {dx_f * 1000:.1f} mm forward")
arp_y = W["chord_plane_y"]
l_h = xh_ac - x_arp
Cma = note("aero", "Cma about ARP (1/rad, c_ref)", -slope_h * Sh / S * l_h / c_ref, "tail only: the ARP is the wing-body ac")
Cma_cg = Cma + CLa * (cg_z_model - x_arp) / c_ref
x_np = x_arp - Cma / CLa * c_ref
sm = note("aero", "static margin at the kit CG (% MAC)", 100 * (x_np - cg_z_model) / mac, f"neutral point at model z {x_np:.4f} ({100 * (x_np - mac_le_z) / mac:.1f} % MAC)")
note("aero", "Cma about the CG (1/rad, c_ref)", Cma_cg, "what the pilot feels")

# Camber: parabolic camber line m -> alpha_0 = -2 m (thin airfoil), Cm_ac = -pi m / 2.
m_c = W["camber_ratio"]
alpha0 = note("aero", "wing zero-lift angle (deg)", math.degrees(-2 * m_c), "thin-airfoil parabolic camber: -2 m")
cm_ac = note("aero", "section Cm_ac", -math.pi * m_c / 2, "thin-airfoil parabolic camber")
CL0_w = CLa_w * (i_w - math.radians(alpha0))
eps0 = 2 * CL0_w / (math.pi * AR)
i_h = math.radians(T["stab_incidence_deg"])
inc_eff = note("aero", "tail effective incidence (rad)", (i_h - eps0) / (1 - deps), "(i_h - eps0) / (1 - deps/dalpha): the local tail model sees body alpha")
CL0 = note("aero", "CL0", CL0_w + slope_h * Sh / S * inc_eff, "wing at +1 deg incidence with camber + tail at zero body alpha")
Cm0 = note("aero", "Cm0 about ARP", cm_ac * mac / c_ref - slope_h * Sh / S * l_h / c_ref * inc_eff, "wing Cm_ac + tail at zero body alpha")

# Controls (kit placeholder throws, degrees).
# Throws: kit millimetres at the widest part of each surface -> hinge angle asin(d / chord) (as the Extra does).
ail_c_in = cf_a_w = W["aileron_chord_fraction"] * (cr + (ct - cr) * W["aileron_inner"] / semi)
elev_c = (1 - T["elevator_hinge_fraction"]) * crh
rud_c = T["rudder_te_bottom"][0] - T["rudder_hinge_z"]
mm = KIT["throws_mm"]
throws = {
    "aileron": note("controls", "aileron (deg)", math.degrees(math.asin(mm["aileron"] / 1000 / ail_c_in)), f"{mm['aileron']:.0f} mm on the {ail_c_in * 1000:.0f} mm inboard aileron chord ({KIT['throws_note']})"),
    "elevator": note("controls", "elevator (deg)", math.degrees(math.asin(mm["elevator"] / 1000 / elev_c)), f"{mm['elevator']:.0f} mm on the {elev_c * 1000:.0f} mm root elevator chord"),
    "rudder": note("controls", "rudder (deg)", math.degrees(math.asin(mm["rudder"] / 1000 / rud_c)), f"{mm['rudder']:.0f} mm on the {rud_c * 1000:.0f} mm bottom rudder chord"),
}
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
    (f"propeller 4-blade {KIT['propeller']['diameter_in']:.0f}x{KIT['propeller']['pitch_in']:.0f}", 0.55, "estimated", "wood/composite 4-blade giant-scale propeller (0.45-0.65 kg typical)", le(PROP["z"]), [0.02, PROP["diameter"], PROP["diameter"]], "measured", "propeller plane from geometry.json"),
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

CL_max = note("aero", "CL_max", 1.15, "estimated: 15 % laminar section clmax ~1.3 at Re 7e5 x 0.9 for the tapered wing, flaps up (no polar identified)")
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
e_osw = note("drag", "Oswald e", 0.80, "estimated: taper 0.48 near the optimum; fuselage and scoop interference")
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


# --- Propeller: blade-element / momentum model of the kit's 4-blade 28x10 --------------------------------------
def bem_tables(diameter, pitch, blades, planform, n_rps=100.0):
    """Ct(J), Cp(J) by blade-element/momentum theory in induced-velocity form (stable at zero airspeed), Prandtl tip
    loss, geometric-pitch twist. Generic section: a0 = 0.9 x 2 pi, zero-lift angle -3 deg, Cl capped at +-1.2,
    Cd = 0.012 + 0.025 Cl^2. Returns [[J, Ct], ...], [[J, Cp], ...] from J = 0 into the windmilling branch (Ct < -0.06), so the
    simulation interpolates rather than extrapolates at high J and low rpm."""
    R = diameter / 2
    a0, alpha_zl, cl_max, cl_min_wm, cd0, k_cd = 2 * math.pi * 0.9, math.radians(-3.0), 1.2, 0.8, 0.012, 0.025
    table = lambda rows, x: next((r0[1] + (r1[1] - r0[1]) * (x - r0[0]) / (r1[0] - r0[0]) for r0, r1 in zip(rows, rows[1:]) if r0[0] <= x <= r1[0]), rows[-1][1])
    omega = 2 * math.pi * n_rps
    ct_rows, cp_rows = [], []
    J = 0.0
    while True:
        Vinf = J * n_rps * diameter
        thrust = torque = 0.0
        n_el = 40
        for i in range(n_el):
            x = 0.2 + 0.8 * (i + 0.5) / n_el
            r = x * R
            dr = 0.8 * R / n_el
            c = table(planform, x) * R
            beta = math.atan(pitch / (2 * math.pi * r))
            wa = 0.1 * omega * r  # induced axial velocity, first guess
            wt = 0.0  # induced swirl
            for _ in range(300):
                Va = Vinf + wa
                Vt = omega * r - wt
                phi = math.atan2(Va, Vt)
                alpha = beta - phi
                cl = max(-cl_min_wm, min(cl_max, a0 * (alpha - alpha_zl)))  # windmilling: the section stalls near -8 deg
                cd = cd0 + k_cd * cl * cl + (0.02 * (alpha_zl - alpha) / 0.1 if alpha < alpha_zl - 0.14 else 0.0)  # post-stall drag rise
                W2 = Va * Va + Vt * Vt
                cn = cl * math.cos(phi) - cd * math.sin(phi)
                ctan = cl * math.sin(phi) + cd * math.cos(phi)
                dT = 0.5 * RHO * W2 * c * cn * blades  # per unit radius
                dQr = 0.5 * RHO * W2 * c * ctan * blades  # torque per unit radius / r
                f = blades / 2 * (R - r) / max(r * abs(math.sin(phi)), 1e-6)
                F = max(2 / math.pi * math.acos(min(1.0, math.exp(-f))), 0.05)
                # Momentum: dT = 4 pi r F rho (Vinf + wa) wa; dQ/r = 4 pi r F rho (Vinf + wa) wt * r
                disc = Vinf * Vinf + max(dT, 0.0) / (math.pi * r * F * RHO)
                wa_new = (-Vinf + math.sqrt(disc)) / 2 if dT > 0 else 0.0
                wt_new = dQr / (4 * math.pi * r * F * RHO * max(Vinf + wa_new, 1e-3)) if dQr > 0 else 0.0
                if abs(wa_new - wa) < 1e-5 and abs(wt_new - wt) < 1e-5:
                    wa, wt = wa_new, wt_new
                    break
                wa += 0.3 * (wa_new - wa)
                wt += 0.3 * (wt_new - wt)
            thrust += dT * dr
            torque += dQr * r * dr
        Ct = thrust / (RHO * n_rps ** 2 * diameter ** 4)
        Cp = torque * omega / (RHO * n_rps ** 3 * diameter ** 5)
        ct_rows.append([round(J, 3), round(Ct, 5)])
        cp_rows.append([round(J, 3), round(max(Cp, 0.0), 5)])
        if Ct < -0.09 or J > 1.6:
            break
        J += 0.05
    return ct_rows, cp_rows


ct_table, cp_table = bem_tables(PROP["diameter"], PROP["pitch"], PROP["blades"], PROP["blade"]["chord_fraction_of_radius"])
Ct0, Cp0 = ct_table[0][1], cp_table[0][1]
P_peak = note("propulsion", "engine peak power (W)", 11.7 * 745.7, "DA-120: 11.7 hp (desertaircraft.com/products/da-120); rpm range 1300-6900")
n_peak = 6900.0 / 60
# Static rpm: engine power P(n) = P_peak (n/n_peak) (2 - n/n_peak) (flat-torque two-stroke approximation) meets the propeller Cp0 rho n^3 D^5.
lo, hi = 10.0, n_peak * 1.3
for _ in range(80):
    mid = 0.5 * (lo + hi)
    engine = P_peak * (mid / n_peak) * (2 - mid / n_peak)
    prop_p = Cp0 * RHO * mid ** 3 * PROP["diameter"] ** 5
    if prop_p > engine:
        hi = mid
    else:
        lo = mid
n_static = 0.5 * (lo + hi)
rpm_static = note("propulsion", "static rpm", n_static * 60, f"BEM Cp0 {Cp0:.4f} meets the engine power curve; static thrust {Ct0 * RHO * n_static ** 2 * PROP['diameter'] ** 4:.0f} N ({Ct0 * RHO * n_static ** 2 * PROP['diameter'] ** 4 / G0:.1f} kgf)")
note("propulsion", "BEM Ct0 / Cp0 / J at zero thrust", [Ct0, Cp0, ct_table[-1][0]], f"4-blade {KIT['propeller']['diameter_in']:.0f}x{KIT['propeller']['pitch_in']:.0f}, P/D {PROP['pitch'] / PROP['diameter']:.3f}")
thrust_static = Ct0 * RHO * n_static ** 2 * PROP["diameter"] ** 4
note("propulsion", "static thrust / weight", thrust_static / (mass * G0), "for comparison, 31 kg static was quoted for a 2-blade Falcon 28x10 on a DA-120 at 6550 rpm (FlyingGiants, snippet only)")
# Maximum level speed with the simulation's propulsion model (rpm held at the static maximum: no in-flight
# unloading yet, ROADMAP G1): full-throttle thrust meets the drag polar at CL for level flight.
def thrust_at(V, n):
    J = V / (n * PROP["diameter"])
    ct = next((r0[1] + (r1[1] - r0[1]) * (J - r0[0]) / (r1[0] - r0[0]) for r0, r1 in zip(ct_table, ct_table[1:]) if r0[0] <= J <= r1[0]), -0.1)
    return ct * RHO * n ** 2 * PROP["diameter"] ** 4
def drag_at(V):
    cl = mass * G0 / (0.5 * RHO * V * V * S)
    return 0.5 * RHO * V * V * S * (CD0 + k_ind * cl * cl)
v_lo, v_hi = Vs, 80.0
for _ in range(60):
    v_mid = 0.5 * (v_lo + v_hi)
    if thrust_at(v_mid, n_static) > drag_at(v_mid):
        v_lo = v_mid
    else:
        v_hi = v_mid
V_max = note("propulsion", "maximum level speed (m/s)", v_lo, f"full throttle at {n_static * 60:.0f} rpm (pitch speed {n_static * PROP['pitch']:.1f} m/s); the handling test flies below this")
prop_mass = 0.55
rotor_j = note("propulsion", "rotating inertia (kg m2)", prop_mass * (PROP["diameter"] / 2) ** 2 / 3 * 0.6 + 0.35 * (g["spinner"]["radius"] * 0.8) ** 2 / 2, "4 blades as slender rods (mL2/3 per blade pair x 0.6 planform factor) + spinner shell")

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
        dict({"name": it[0], "mass": q(float(it[1]), "kg", it[2], it[3]), "position": q([float(v) for v in it[4]], "m", it[6], it[7])},
             **({"size": q([float(v) for v in it[5]], "m", "estimated", "rough envelope for intrinsic inertia")} if it[5] else {}))
        for it in items
    ],
    "crash_hull": q([
        le(W["le_z_tip"], cp_y + semi * math.tan(dihedral), -semi), le(W["le_z_tip"], cp_y + semi * math.tan(dihedral), semi),
        le(W["le_z_tip"] + ct, cp_y + semi * math.tan(dihedral), -semi), le(W["le_z_tip"] + ct, cp_y + semi * math.tan(dihedral), semi),
        le(g["spinner"]["tip_z"]),
        le(GEAR["main_axle"][0], GEAR["main_axle"][1] - GEAR["main_wheel_diameter"] / 2, -GEAR["track"] / 2),
        le(GEAR["main_axle"][0], GEAR["main_axle"][1] - GEAR["main_wheel_diameter"] / 2, GEAR["track"] / 2),
        le(GEAR["tail_axle"][0], GEAR["tail_axle"][1] - GEAR["tail_wheel_diameter"] / 2),
        le(T["rudder_te_bottom"][0], T["rudder_te_bottom"][1]),
        le(T["stab_tip_le_z"] + cth, T["stab_y"], -hs), le(T["stab_tip_le_z"] + cth, T["stab_y"], hs),
        le(fin_top_te, T["fin_top_y"]),
        le(canopy_top[0], canopy_top[1]),
        le(g["scoop_stations"][2][0], g["scoop_stations"][2][2]),
    ], "m", "derived", "Points that hit the ground first (le frame) from " + GEO_SRC + ": wing tip LE/TE (with dihedral), spinner tip, main wheel bottoms, tail wheel bottom, rudder bottom TE, stab tips, fin top, canopy top, scoop bottom. Replaced by gear contact in E1/E2"),
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
            "stall_blend_width": q(5.0, "deg", "estimated", "laminar section with a sharper break than the Stik's 6 deg; tip-stall tendency of the real airplane is not modelled beyond the equal-area strips"),
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
        "description": f"120 cc gasoline twin turning a 4-blade {KIT['propeller']['diameter_in']:.0f}x{KIT['propeller']['pitch_in']:.0f}: blade-element/momentum tables computed by {SCRIPT} (no measured table for this propeller); static rpm where the propeller power meets an estimated flat-torque engine curve. AXIAL thrust.",
        "engine": {
            "name": "Desert Aircraft DA-120 (121 cc twin, 2.45 kg with ignition) or DLE-120",
            "peak_power": q(P_peak, "W", "manual", "DA-120 11.7 hp, desertaircraft.com/products/da-120 (2026-10-06); DLE-120 12 hp at 7500 rpm (DLE manual)"),
            "peak_power_rpm": q(n_peak * 60, "rpm", "manual", "DA-120 top of the 1300-6900 rpm range (desertaircraft.com)"),
            "max_rpm_static": q(rpm_static, "rpm", "derived", D("BEM Cp0 meets the engine power curve P(n) = P_peak (n/n_peak)(2 - n/n_peak)")),
            "idle_rpm": q(1300.0, "rpm", "manual", "DA-120 range starts at 1300 rpm (desertaircraft.com); DLE-120 idle 1300 (manual)"),
            "lag_time_constant": q(0.6, "s", "estimated", "heavy 4-blade propeller and a carburetted twin: slower than the .61 glow's 0.25 s"),
        },
        "propeller": {
            "name": f"4-blade {KIT['propeller']['diameter_in']:.0f}x{KIT['propeller']['pitch_in']:.0f} (scale-look choice; DA-120 lists 3-blade 26x12 / 27x12)",
            "diameter": q(PROP["diameter"], "m", "estimated", f"{KIT['propeller']['diameter_in']:.0f} in (source.json)"),
            "rotation": "clockwise seen from behind (standard tractor): the reaction torque rolls the airplane left",
            "ct_table": q(ct_table, "1", "derived", D("blade-element/momentum theory, Prandtl tip loss, geometric pitch twist, generic section (a0 0.9x2pi, alpha_zl -3 deg, Cl caps +1.2/-0.8, Cd 0.012 + 0.025 Cl2 + post-stall rise); tabulated into the windmilling branch")),
            "cp_table": q(cp_table, "1", "derived", D("same blade-element/momentum model")),
            "rotating_inertia": q(rotor_j, "kg·m2", "estimated", "4 blades as slender rods + aluminium spinner"),
            "thrust_line_offset": q([0.0, 0.0, -cg[2]], "m", "derived", D("spinner axis relative to the inventory CG; [x_aft, y_right, z_up] from the CG")),
        },
    },
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
Propeller: static {rpm_static:.0f} rpm, static thrust {thrust_static:.0f} N ({thrust_static / G0:.1f} kgf), thrust/weight {thrust_static / (mass * G0):.2f}, maximum level speed {V_max:.1f} m/s.

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

if "--check" in sys.argv:
    stale = [p for p, t in ((OUT, text), (REPORT, report)) if not p.exists() or p.read_text() != t]
    if stale:
        sys.exit("stale: " + ", ".join(str(p.relative_to(ROOT)) for p in stale) + f" (run {SCRIPT})")
    print("p51d_mustang_120.json and derivation.md are up to date")
else:
    OUT.write_text(text)
    REPORT.write_text(report)
    print(f"wrote {OUT.relative_to(ROOT)} and {REPORT.relative_to(ROOT)}")
    print(f"mass {mass:.3f} kg, CG {100 * cg_mac:.1f} % MAC, SM {sm:.1f} % MAC, stall {Vs:.1f} m/s, start {V_start} m/s, static {rpm_static:.0f} rpm, thrust {thrust_static / G0:.1f} kgf")
