#!/usr/bin/env python3
"""AV-06: physics data of the SebArt Avanti S Jet 2.2m (A200, 2.00 m span) with a JetCat P100-RX, derived and reproducible.

Reads the visual geometry (assets/aircraft/avanti-s-a200/geometry.json, AV-02 blockout), the sourced inputs in
research/avanti-s/av06/inputs.json (manual, catalog, research reports) and the Ugly Stik data file (shared conventions and
the provisional local-surface limits). Writes app/data/aircraft/sebart_avanti_s_a200.json (openrc-aircraft v1 with
propulsion kind "turbine", AV-05) and research/avanti-s/av06/derivation.md.

Methods are textbook estimates, not flight identification: Helmbold/DATCOM lift slopes with sweep, DATCOM downwash with
tail height, Munk-Multhopp fuselage moment with Biot-Savart upwash, tail-volume derivatives, strip theory for ailerons and
roll damping, a skin-friction drag build-up, a component inventory, and a momentum-theory turbojet. Every number written
carries its unit, evidence kind and source.

    python3 research/avanti-s/av06/derive_physics.py           # writes the JSON and the report
    python3 research/avanti-s/av06/derive_physics.py --check   # fails if either file is stale
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GEOMETRY = ROOT / "assets/aircraft/avanti-s-a200/geometry.json"
INPUTS = ROOT / "research/avanti-s/av06/inputs.json"
STIK = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
OUT = ROOT / "app/data/aircraft/sebart_avanti_s_a200.json"
REPORT = ROOT / "research/avanti-s/av06/derivation.md"
RHO = 1.225
G0 = 9.80665
NU = 1.46e-5
SCRIPT = "research/avanti-s/av06/derive_physics.py"
GEO_SRC = "assets/aircraft/avanti-s-a200/geometry.json (AV-02 visual blockout, estimated)"

g = json.load(open(GEOMETRY))
IN = globals().get("IN_OVERRIDE") or json.load(open(INPUTS))  # sensitivity.py injects modified inputs
log = []
# Wing station along the fuselage (inputs airframe.wing_forward_shift): every fuselage-attached part (fuselage, canopy,
# tail, fin, installation, fuselage items) moves aft by this much relative to the wing and its leading-edge datum, i.e.
# the wing sits that much further forward on the fuselage than the visual blockout draws it. 0 = the blockout as drawn.
DZ = IN["airframe"]["wing_forward_shift"]["value"]
for r in g["fuselage_stations"] + g["canopy_stations"]:
    r[0] += DZ
for r in g["tail"]["stations"]:
    r[1] += DZ
    r[2] += DZ
g["fin"]["outline_yz"] = [[y, z + DZ] for y, z in g["fin"]["outline_yz"]]
for k in ("hinge_bottom_yz", "hinge_top_yz"):
    g["fin"][k][1] += DZ
g["installation"]["engine_center"][2] += DZ
for r in g["installation"]["intake_stations"]:
    r[0] += DZ


def v(key):
    """An input's value (inputs.json: {value, unit, kind, source})."""
    node = IN
    for part in key.split("."):
        node = node[part]
    return node["value"]


def src(key):
    node = IN
    for part in key.split("."):
        node = node[part]
    return node["kind"], node["source"]


def note(section, name, value, how):
    log.append((section, name, value, how))
    return value


def q(value, unit, kind, source):
    if isinstance(value, float):
        value = round(value, 6)
    elif isinstance(value, list):
        value = [[round(x, 6) for x in r] if isinstance(r, list) else round(r, 6) for r in value]
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def qi(key, unit, value=None):
    """A quantity straight from inputs.json, keeping its evidence."""
    kind, source = src(key)
    return q(v(key) if value is None else value, unit, kind, source)


def helmbold(aspect, kappa, half_chord_sweep=0.0):
    t = math.tan(half_chord_sweep)
    return 2 * math.pi * aspect / (2 + math.sqrt(aspect ** 2 / kappa ** 2 * (1 + t * t) + 4))


def flap_tau(cf):
    th = math.acos(2 * cf - 1)
    return 1 - (th - math.sin(th)) / math.pi


def shoelace(points):
    a = cu = cv = 0.0
    for (u0, v0), (u1, v1) in zip(points, points[1:] + points[:1]):
        cross = u0 * v1 - u1 * v0
        a += cross
        cu += (u0 + u1) * cross
        cv += (v0 + v1) * cross
    a *= 0.5
    return abs(a), cu / (6 * a), cv / (6 * a)


# --- Frames -----------------------------------------------------------------------------------------------------
# Model axes (geometry.json): +X right, +Y up, -Z nose; z = 0 at the root leading edge beside the fuselage, y = 0 on the
# root wing mid-plane. The physics le frame [x_aft, y_right, z_up] uses the same origin (render/airplane.gd datum).
def le(model_z, model_y=0.0, model_x=0.0):
    return [model_z, model_x, model_y]


# --- Planforms: polylines of [y, le_z, te_z, height] integrated in strips -------------------------------------------
def strips(rows, chord_scale=1.0, n=60):
    """Strips (y, le_z, chord, height, dy) of one side from the centreline: the first row is extended to y = 0 (the
    reference area runs through the fuselage). Chords scale about the leading edge."""
    rows = ([[0.0] + list(rows[0][1:])] if rows[0][0] > 0 else []) + [list(r) for r in rows]
    out = []
    for a, b in zip(rows, rows[1:]):
        for k in range(n):
            t = (k + 0.5) / n
            y = a[0] + (b[0] - a[0]) * t
            lez = a[1] + (b[1] - a[1]) * t
            c = ((a[2] - a[1]) + ((b[2] - b[1]) - (a[2] - a[1])) * t) * chord_scale
            out.append((y, lez, c, a[3] + (b[3] - a[3]) * t, (b[0] - a[0]) / n))
    return out


def planform(st):
    area = sum(c * dy for _, _, c, _, dy in st)
    mac = sum(c * c * dy for _, _, c, _, dy in st) / area
    mac_le = sum(c * c * z * dy for _, z, c, _, dy in st) / sum(c * c * dy for _, _, c, _, dy in st)
    y_mac = sum(c * y * dy for y, _, c, _, dy in st) / area  # area centroid of the semi-span
    return 2 * area, mac, mac_le, y_mac


Wg = g["wing"]
b = note("reference", "b (m)", v("airframe.span"), "manual span")
semi = b / 2
assert abs(Wg["stations"][-1][0] - semi) < 1e-9
S_blockout, _, _, _ = planform(strips(Wg["stations"]))
target = IN["airframe"].get("wing_area")
chord_scale = target["value"] / S_blockout if target else 1.0
note("reference", "blockout wing area (m2)", S_blockout, GEO_SRC + "; trapezoids through the fuselage to the centreline")
note("reference", "wing forward shift on the fuselage (m)", DZ, src("airframe.wing_forward_shift")[1])
note("reference", "chord scale applied", chord_scale, "inputs wing_area / blockout area" if target else "none: no published area, the blockout is used")
wst = strips(Wg["stations"], chord_scale)
S, mac, mac_le, y_centroid = planform(wst)
S = note("reference", "S (m2)", S, "wing planform through the fuselage")
c_ref = note("reference", "c_ref = S/b (m)", S / b, "v1 coefficient reference length (not the MAC)")
AR = note("reference", "AR = b2/S", b * b / S, "")
note("reference", "MAC (m)", mac, "integral of c2 over the polyline planform")
note("reference", "MAC LE (model z)", mac_le, "chord2-weighted leading edge")
cr_geo = wst[0][2]
ct_geo = wst[-1][2]
qc_root = wst[0][1] + 0.25 * cr_geo
qc_tip = wst[-1][1] + 0.25 * ct_geo
hc_root = wst[0][1] + 0.5 * cr_geo
hc_tip = wst[-1][1] + 0.5 * ct_geo
sweep_qc = note("reference", "quarter-chord sweep (deg)", math.degrees(math.atan2(qc_tip - qc_root, semi)), "root to tip, straight-line")
sweep_hc = math.radians(note("reference", "half-chord sweep (deg)", math.degrees(math.atan2(hc_tip - hc_root, semi)), ""))
sweep_qc = math.radians(sweep_qc)
lam_geo = ct_geo / cr_geo
note("reference", "taper (tip/root at the centreline)", lam_geo, "")
dihedral = math.atan2(Wg["stations"][-1][3] - Wg["stations"][0][3], Wg["stations"][-1][0] - Wg["stations"][0][0])
note("reference", "dihedral (deg)", math.degrees(dihedral), "blockout tip height over the semi-span")
# The loader's tapered planform is a trapezoid; give it the one with the same area and the same spanwise area centroid
# (where the asymmetric-stall strips sit): ybar/semi = (1 + 2 lam) / (3 (1 + lam)) -> lam = (1 - 3 r) / (3 r - 2).
r_c = y_centroid / semi
lam_eq = (1 - 3 * r_c) / (3 * r_c - 2)
cr_eq = 2 * S / (b * (1 + lam_eq))
ct_eq = lam_eq * cr_eq
note("reference", "equivalent trapezoid root/tip (m)", [cr_eq, ct_eq], f"same area and spanwise centroid ({r_c:.4f} semi-span) as the polyline: the loader's strip stations")

# --- Fuselage ----------------------------------------------------------------------------------------------------
FS = g["fuselage_stations"]  # [z, half-width, top y, bottom y]
fus_len = note("fuselage", "length (m)", FS[-1][0] - FS[0][0], "nose to tail cone, geometry stations")
fus_w = 2 * max(r[1] for r in FS)
fus_d = max(r[2] - r[3] for r in FS)
note("fuselage", "max width / depth (m)", [fus_w, fus_d], GEO_SRC)
fus_width_scale = v("airframe.fuselage_width_scale")
note("fuselage", "width scale for aerodynamics", fus_width_scale, src("airframe.fuselage_width_scale")[1])


def fus_at(z):
    for r0, r1 in zip(FS, FS[1:]):
        if r0[0] <= z <= r1[0]:
            t = (z - r0[0]) / (r1[0] - r0[0])
            return [r0[k] + (r1[k] - r0[k]) * t for k in range(4)]
    return FS[-1] if z > FS[-1][0] else FS[0]


# --- Horizontal tail -------------------------------------------------------------------------------------------------
Tg = g["tail"]
tst = strips(Tg["stations"], v("airframe.stab_chord_scale"))
Sh, mach, mach_le, yh_c = planform(tst)
Sh = note("tail", "Sh (m2)", Sh, "stab + elevators through the fuselage, " + GEO_SRC + f"; chords x {v('airframe.stab_chord_scale')}")
bh = 2 * Tg["stations"][-1][0]
AR_h = bh * bh / Sh
xh_ac = note("tail", "horizontal ac (model z)", mach_le + 0.25 * mach, "quarter chord of the stab MAC")
h_stab = Tg["stations"][0][3]
cf_e = note("tail", "elevator chord fraction", 1 - Tg["hinge_fraction"], "hinge at a constant chord fraction")
hc_h = math.atan2((tst[-1][1] + 0.5 * tst[-1][2]) - (tst[0][1] + 0.5 * tst[0][2]), bh / 2)

# --- Vertical tail: the fin outline above the fuselage top line ----------------------------------------------------
fin_raw = [(z, y) for y, z in g["fin"]["outline_yz"]]  # (z aft, y up)
fin_pts = []
for z, y in fin_raw:
    top = fus_at(z)[2]
    fin_pts.append((z, max(y, top)))
Sv, fin_cz, fin_cy = shoelace(fin_pts)
Sv = note("tail", "Sv (m2)", Sv, "fin + rudder outline above the fuselage top line, " + GEO_SRC)
hb, ht = g["fin"]["hinge_bottom_yz"], g["fin"]["hinge_top_yz"]
fin_top_y = max(y for _, y in fin_pts)
fin_root_y = fus_at(fin_cz)[2]
h_v = fin_top_y - fin_root_y
te_z = max(z for z, _ in fin_raw)
cf_r = note("tail", "rudder chord fraction", (te_z - (hb[1] + ht[1]) / 2) / (Sv / h_v), "mean rudder chord (hinge to TE) over the mean fin chord")
xv_ac = note("tail", "fin ac (model z)", fin_cz - 0.25 * (Sv / h_v), "area centroid minus a quarter of the mean chord (centroid ~ mid-chord)")

# --- Lift slopes, downwash, neutral point -------------------------------------------------------------------------
kappa = note("aero", "section lift slope / 2pi", v("aero.kappa"), src("aero.kappa")[1])
CLa_w = note("aero", "CLa wing (1/rad)", helmbold(AR, kappa, sweep_hc) * math.cos(dihedral) ** 2, "Helmbold/DATCOM with half-chord sweep")
CLa_h = note("aero", "CLa horizontal (1/rad)", helmbold(AR_h, 0.9, hc_h), f"Helmbold, AR {AR_h:.2f}, kappa 0.9 (thin symmetric stab)")
eta_h = note("aero", "tail dynamic pressure ratio", v("aero.eta_h"), src("aero.eta_h")[1])
x_ac_w = mac_le + 0.25 * mac
l_h = xh_ac - x_ac_w
KA = 1 / AR - 1 / (1 + AR ** 1.7)
KL = (10 - 3 * lam_geo) / 7
KH = (1 - abs(h_stab / b)) / (2 * l_h / b) ** (1 / 3)
deps = note("aero", "d(eps)/d(alpha)", 4.44 * (KA * KL * KH * math.sqrt(math.cos(sweep_qc))) ** 1.19,
            f"DATCOM: 4.44 [K_A K_lambda K_H sqrt(cos sweep)]^1.19, tail {h_stab:.3f} m above the wing plane, {l_h:.3f} m behind the wing ac")
slope_h = note("aero", "effective tail slope (1/rad)", CLa_h * eta_h * (1 - deps), "CLa_h eta (1 - deps/dalpha)")
CLa = note("aero", "CLa airplane (1/rad)", CLa_w + slope_h * Sh / S, "wing + tail")

# Munk-Multhopp fuselage moment: dM/dalpha = (pi/2) q sum w^2 (d eps_local/d alpha) dx. Ahead of the wing the local flow
# angle grows by the upwash of the wing's horseshoe vortex (bound at the MAC quarter chord, span pi b/4); over the wing
# root nothing; behind it the flow follows the downwash, recovering linearly to (1 - deps/dalpha) at the tail ac.
bprime = math.pi * b / 4
s_hv = bprime / 2


def upwash_slope(x):
    k = 0.5 * S * CLa_w / bprime / (4 * math.pi)
    rr = math.sqrt(x * x + s_hv * s_hv)
    return k * (2 * s_hv / (x * rr) - 2 / s_hv * (1 - x / rr))


root_te = wst[0][1] + wst[0][2]
munk = 0.0
n_seg = 400
for i in range(n_seg):
    z = FS[0][0] + (FS[-1][0] - FS[0][0]) * (i + 0.5) / n_seg
    dz = (FS[-1][0] - FS[0][0]) / n_seg
    w = 2 * fus_at(z)[1] * fus_width_scale
    if z < 0.0:
        f = 1 + upwash_slope(x_ac_w - z)
    elif z <= root_te:
        f = 0.0
    else:
        f = min(1.0, (z - root_te) / (xh_ac - root_te)) * (1 - deps)
    munk += w * w * f * dz
Cma_fus = note("aero", "Cma fuselage (1/rad, MAC)", math.pi / 2 * munk / (S * mac), "Munk-Multhopp over the fuselage stations, Biot-Savart upwash ahead of the wing")
dx_f = Cma_fus / CLa_w * mac
x_arp_tb = note("aero", "textbook wing-body ac (model z)", x_ac_w - dx_f, f"wing ac at 25 % MAC {x_ac_w:.4f}, the fuselage moves it {dx_f * 1000:.1f} mm forward")
# Neutral point: x_np = x_arp (1 - r) + r x_h with r = slope_h Sh / (S CLa) (tail lift about the wing-body ac).
r_t = slope_h * Sh / (S * CLa)
np_tb = note("aero", "textbook neutral point (model z)", x_arp_tb * (1 - r_t) + r_t * xh_ac, f"{100 * (x_arp_tb * (1 - r_t) + r_t * xh_ac - mac_le) / mac:.1f} % MAC: blockout geometry + textbook methods alone")
# Anchor (inputs stability.np_anchor): the manufacturer's CG range is flown by many owners, so the airplane is statically
# stable there. If the textbook neutral point contradicts it, the wing-body ac moves aft by the smallest amount that puts
# the anchor CG at the stated margin; the shift is the geometry's unresolved longitudinal error (reported, not hidden).
anchor = IN["stability"]["np_anchor"]
np_target = anchor["cg"] + anchor["static_margin"] * mac
x_np_adopted = max(np_tb, np_target)
x_arp = (x_np_adopted - r_t * xh_ac) / (1 - r_t)
note("aero", "neutral point anchor (model z)", np_target, f"{anchor['cg'] * 1000:.0f} mm CG at {100 * anchor['static_margin']:.0f} % MAC margin: {anchor['source']}")
note("aero", "wing-body ac = ARP (model z)", x_arp, f"shifted {1000 * (x_arp - x_arp_tb):+.1f} mm from the textbook value to meet the anchor ({100 * (x_arp - x_arp_tb) / mac:+.1f} % MAC)" if x_arp != x_arp_tb else "textbook value: the anchor is already met")
Cma = note("aero", "Cma about ARP (1/rad, c_ref)", -slope_h * Sh / S * (xh_ac - x_arp) / c_ref, "tail only: the ARP is the wing-body ac")
x_np = x_arp - Cma / CLa * c_ref
cg_z = v("airframe.cg_aft_of_root_le")
sm = note("aero", "static margin at the flight CG (% MAC)", 100 * (x_np - cg_z) / mac,
          f"neutral point at model z {x_np:.4f} ({100 * (x_np - mac_le) / mac:.1f} % MAC); CG {cg_z * 1000:.0f} mm = {100 * (cg_z - mac_le) / mac:.1f} % MAC")
for name, z in (("beginner 240 mm", 0.240), ("normal 250 mm", 0.250), ("3D 260 mm", 0.260)):
    note("aero", f"static margin, manual CG {name} (% MAC)", 100 * (x_np - z) / mac, "same neutral point")
Cma_cg = note("aero", "Cma about the CG (1/rad, c_ref)", Cma + CLa * (cg_z - x_arp) / c_ref, "what the pilot feels")

# Symmetric sections (pattern-type jet): zero-lift at zero; incidences from the inputs.
i_w = math.radians(v("aero.wing_incidence_deg"))
i_h = math.radians(v("aero.stab_incidence_deg"))
CL0_w = CLa_w * i_w
eps0 = 2 * CL0_w / (math.pi * AR)
inc_eff = note("aero", "tail effective incidence (rad)", (i_h - eps0) / (1 - deps), "(i_h - eps0) / (1 - deps/dalpha): the local tail model sees body alpha")
CL0 = note("aero", "CL0", CL0_w + slope_h * Sh / S * inc_eff, "symmetric sections: wing incidence + tail incidence at zero body alpha")
Cm0 = note("aero", "Cm0 about ARP", -slope_h * Sh / S * (xh_ac - x_arp) / c_ref * inc_eff, "tail incidence only (symmetric wing section: Cm_ac = 0)")

# --- Controls ------------------------------------------------------------------------------------------------------
k_flap = note("controls", "flap effectiveness correction", v("aero.flap_k"), src("aero.flap_k")[1])
tau_e = flap_tau(cf_e) * k_flap
ce_h = note("controls", "elevator effectiveness (local)", tau_e / (1 - deps), f"tau {tau_e:.3f} / (1 - deps/dalpha)")
CLde = note("aero", "CLde (1/rad)", slope_h * ce_h * Sh / S, "")
Cmde = note("aero", "Cmde (1/rad)", -CLde * (xh_ac - x_arp) / c_ref, "")
cf_a = 1 - Wg["hinge_fraction"]
a_in, a_out = Wg["aileron_span"]
ail = [s for s in wst if a_in <= s[0] <= a_out]
tau_a = note("controls", "aileron tau", flap_tau(cf_a) * k_flap, f"chord fraction {cf_a:.2f}, span {a_in}-{a_out} m")
# Strip theory on the swept wing: the section lift slope along the strip, scaled to the 3-D wing (CLa_w / (2 pi kappa)).
a_strip = CLa_w
CLda_each = a_strip * tau_a * sum(c * dy for _, _, c, _, dy in ail) / S
Clda = note("aero", "Clda_right (1/rad)", -a_strip * tau_a * sum(c * y * dy for y, _, c, _, dy in ail) / (S * b), "strip theory over the aileron span")

# --- Inventory (le frame) ------------------------------------------------------------------------------------------
items = []
# Structure measured by owners (airframe research): placed from the geometry.
ST = IN["structure"]
exposed = [st_ for st_ in wst if st_[0] >= Wg["stations"][0][0]]
ex_area = sum(c * dy for _, _, c, _, dy in exposed)
ex_y = sum(c * y * dy for y, _, c, _, dy in exposed) / ex_area
ex_z = sum((z + 0.42 * c) * c * dy for _, z, c, _, dy in exposed) / ex_area
for side, sign in (("left", -1.0), ("right", 1.0)):
    items.append((f"wing panel {side}, covered, with flap and aileron", float(ST["wing_panel"]["value"]), ST["wing_panel"]["kind"], ST["wing_panel"]["source"],
                  le(ex_z, ex_y * math.tan(dihedral), sign * ex_y), [mac, semi - Wg["stations"][0][0], 0.05], "derived", "42 % chord at the exposed panel's area centroid (geometry.json)"))
th_area = sum(c * dy for _, _, c, _, dy in tst if _ >= Tg["stations"][0][0])
th_y = sum(c * y * dy for y, _, c, _, dy in tst if y >= Tg["stations"][0][0]) / th_area
th_z = sum((z + 0.45 * c) * c * dy for y, z, c, _, dy in tst if y >= Tg["stations"][0][0]) / th_area
for side, sign in (("left", -1.0), ("right", 1.0)):
    items.append((f"stab half {side} with elevator", float(ST["stab_half"]["value"]), ST["stab_half"]["kind"], ST["stab_half"]["source"],
                  le(th_z, h_stab, sign * th_y), [mach, bh / 2, 0.02], "derived", "45 % chord at the stab half's area centroid (geometry.json)"))
# Composite shell: mass spread over the stations in proportion to the wetted perimeter (Ramanujan ellipse) x length.
shell = float(ST["fuselage_shell"]["value"])
segs = []
for r0, r1 in zip(FS, FS[1:]):
    a_ = (r0[1] + r1[1]) / 2
    b_ = ((r0[2] - r0[3]) + (r1[2] - r1[3])) / 4
    per = math.pi * (3 * (a_ + b_) - math.sqrt((3 * a_ + b_) * (a_ + 3 * b_)))
    segs.append((r0, r1, per * (r1[0] - r0[0])))
tot_wet = sum(x[2] for x in segs)
for r0, r1, w_ in segs:
    zc = (r0[0] + r1[0]) / 2
    yc = ((r0[2] + r0[3]) + (r1[2] + r1[3])) / 4
    items.append((f"fuselage shell {r0[0]:+.2f} to {r1[0]:+.2f} m", shell * w_ / tot_wet, ST["fuselage_shell"]["kind"], ST["fuselage_shell"]["source"] + "; spread by wetted area",
                  le(zc, yc), [r1[0] - r0[0], 2 * max(r0[1], r1[1]), max(r0[2] - r0[3], r1[2] - r1[3])], "derived", "segment centre, fuselage stations (geometry.json)"))
items.append(("fin and rudder", float(ST["fin"]["value"]), ST["fin"]["kind"], ST["fin"]["source"], le(fin_cz, fin_cy), [0.3, 0.015, h_v], "derived", "fin outline area centroid (geometry.json)"))
for it in IN["inventory"]:
    pos = list(it["position_model"])  # [model z, model y, model x]
    if it.get("attached", "fuselage") != "wing":
        pos[0] += DZ
    items.append((it["name"], float(it["mass"]["value"]), it["mass"]["kind"], it["mass"]["source"],
                  le(pos[0], pos[1], pos[2]), it.get("size"), it["position_kind"], it["position_source"]))
fuel_l = v("fuel.tank_l") * v("fuel.fraction")
fuel_kg = fuel_l * v("fuel.density")
fpos = list(v("fuel.position_model"))
fpos[0] += DZ
items.append(("kerosene + 5 % oil (declared fuel state)", fuel_kg, "derived",
              f"{v('fuel.tank_l')} l x {v('fuel.fraction')} x {v('fuel.density')} kg/l ({src('fuel.tank_l')[1]}; {src('fuel.fraction')[1]})",
              le(fpos[0], fpos[1], fpos[2]), [0.25, 0.14, 0.10], "estimated", src("fuel.position_model")[1]))
# Builders balance a jet by placing the batteries and electronics (inputs: "balance_item"): they move together, within
# the bay limits, to put the CG on the manual's point; whatever they cannot reach becomes a virtual balancing mass.
movable = [k for k, it in enumerate(IN["inventory"]) if it.get("balance_item")]
offset = len(items) - len(IN["inventory"]) - 1  # index of the first inventory item in `items`
z_lo, z_hi = IN["balance"]["balance_item_range_z"]
m_mov = sum(items[offset + k][1] for k in movable)
mom = sum(i[1] * i[4][0] for i in items)
m_all = sum(i[1] for i in items)
mom_fixed = mom - sum(items[offset + k][1] * items[offset + k][4][0] for k in movable)
z_bal = min(max((cg_z * m_all - mom_fixed) / m_mov, z_lo), z_hi)
for k in movable:
    it = items[offset + k]
    items[offset + k] = (it[0], it[1], it[2], it[3], [z_bal, it[4][1], it[4][2]], it[5], "derived",
                         f"placed to balance: the batteries and electronics together at model z {z_bal:.3f} (bay {z_lo}..{z_hi} m)")
note("balance", "batteries/electronics station (model z)", z_bal, f"{m_mov:.2f} kg moved within {z_lo}..{z_hi} m to approach the manual CG" + (" (at the bay limit)" if z_bal in (z_lo, z_hi) else ""))
dry = sum(i[1] for i in items[:-1])
note("balance", "dry inventory (kg)", dry, f"manual: {v('airframe.dry_mass')} kg RTF dry with P100")
mass0 = sum(i[1] for i in items)
x_cg0 = sum(i[1] * i[4][0] for i in items) / mass0
note("balance", "inventory CG without balancing mass (model z)", x_cg0, f"target {cg_z:.3f}")
nose = x_cg0 > cg_z
xb = IN["balance"]["nose_ballast_z"] if nose else IN["balance"]["tail_ballast_z"]
mb = mass0 * (cg_z - x_cg0) / (xb - cg_z)
note("balance", "balancing mass (kg)", mb, ("nose" if nose else "tail") + " weight that puts the CG on the manual's point")
if mb > 1e-6:
    items.append(("virtual reference-build balancing mass", mb, "derived",
                  f"{SCRIPT}: m = M (x_CG - x0) / (x_ballast - x_CG) for the manual balance point; a virtual reference build, NOT measured hardware",
                  [xb, 0.0, 0.0], [0.04, 0.04, 0.04], "estimated", "nose cone" if nose else "tail cone"))
mass = sum(i[1] for i in items)
cg = [sum(i[1] * i[4][k] for i in items) / mass for k in range(3)]
cg[1] = 0.0
note("balance", "flight mass (kg)", mass, f"dry {mass - fuel_kg:.3f} kg + fuel {fuel_kg:.3f} kg")
note("balance", "flight CG (le frame)", cg, "z from the inventory")


def inertia(pt):
    j = [0.0] * 3
    for it in items:
        m, p, s = it[1], it[4], it[5] or [0, 0, 0]
        x, y, z = -(p[0] - pt[0]), p[1] - pt[1], -(p[2] - pt[2])
        j[0] += m * (y * y + z * z) + m * (s[1] ** 2 + s[2] ** 2) / 12
        j[1] += m * (x * x + z * z) + m * (s[0] ** 2 + s[2] ** 2) / 12
        j[2] += m * (x * x + y * y) + m * (s[0] ** 2 + s[1] ** 2) / 12
    return j


J = note("balance", "Jxx Jyy Jzz (kg m2)", inertia(cg), "component boxes + parallel axis")

CL_max = note("aero", "CL_max (clean)", v("aero.CL_max"), src("aero.CL_max")[1])
Vs = note("aero", "1-g stall (m/s)", math.sqrt(2 * mass * G0 / (RHO * S * CL_max)), "flight mass, CL_max, flaps up")
V_start = note("aero", "start speed (m/s)", float(v("start.level_speed")), src("start.level_speed")[1])
CL_ref = note("aero", "CL_ref", mass * G0 / (0.5 * RHO * V_start ** 2 * S), "level flight at the start speed; CL-dependent cross terms are frozen there")

# --- Lateral-directional ----------------------------------------------------------------------------------------
l_v = xv_ac - cg[0]
z_v = fin_cy - cg[2]
AR_v = note("lateral", "fin effective AR", 1.55 * h_v * h_v / Sv, "geometric h2/Sv x 1.55 end-plate factor (fuselage + stab, DATCOM 1.4-1.7)")
mid = fus_at(0.3 * cr_geo)
z_w = 0.0 - (mid[2] + mid[3]) / 2  # wing plane relative to the fuselage centre at the root
sidewash = note("lateral", "(1 + dsigma/dbeta) eta_v", 0.724 + 3.06 * (Sv / S) / (1 + math.cos(sweep_qc)) + 0.4 * (-z_w) / fus_d + 0.009 * AR,
                "Nelson/DATCOM: 0.724 + 3.06 (Sv/S)/(1 + cos sweep) + 0.4 z_w/d + 0.009 AR")
slope_v = note("lateral", "effective fin slope (1/rad)", helmbold(AR_v, 0.9) * sidewash, "")
tau_r = flap_tau(cf_r) * k_flap
ce_v = note("lateral", "rudder effectiveness (local)", tau_r / sidewash, f"tau {tau_r:.3f} / sidewash factor")
CYb_v = -slope_v * Sv / S
CYb_B = note("lateral", "CYb body (1/rad)", -2 * 1.0 * (0.8 * fus_w * fus_width_scale * fus_d) / S, "-2 K_i S0/S, K_i 1.0 mid wing (DATCOM), S0 0.8 w d")
arm_v_arp = xv_ac - x_arp
CYdr = slope_v * Sv / S * ce_v
Cnb = slope_v * Sv / S * arm_v_arp / b
Cndr = -CYdr * arm_v_arp / b
Cldr = CYdr * (fin_cy - 0.0) / b
note("lateral", "Cnb body, omitted (1/rad)", -0.001 * 1.3 * 57.3 * (0.65 * fus_len * fus_d / S) * (fus_len / b),
     "DATCOM -K_N K_Rl (S_side/S)(L/b): destabilizing; not in v1 (Cnb must equal the fin term), as for every aircraft")
Clb_sweep = note("lateral", "Clb sweep at CL_ref (1/rad)", -2 * CL_ref * math.tan(sweep_qc) * y_centroid / b,
                 "strip theory: each strip's lift goes with cos2 of its normal velocity, d ln cos2(sweep - beta)/d beta = 2 tan(sweep), so Clb = -2 CL tan(sweep_c/4) ybar/b (ybar: semi-span area centroid)")
Clb_dihedral = note("lateral", "Clb dihedral (1/rad)", -CLa_w * dihedral * (1 + 2 * lam_geo) / (6 * (1 + lam_geo)), "strip theory: -CLa_w Gamma (1 + 2 lambda) / (6 (1 + lambda))")
Clb_body = note("lateral", "Clb wing-body (1/rad)", 1.2 * math.sqrt(AR) * (z_w / b) * (2 * fus_d / b),
                "DATCOM: 1.2 sqrt(AR) (z_w/b)(2d/b): mid/low wing, sign with the wing above (+) or below (-) the body centre")
Clb = Clb_sweep + Clb_dihedral + Clb_body + CYb_v * z_v / b
Clp = -(CLa_w / 12) * (1 + 3 * lam_geo) / (1 + lam_geo) - eta_h * (CLa_h / 12) * (Sh / S) * (bh / b) ** 2 + 2 * CYb_v * (z_v / b) ** 2
Clr = CL_ref / 4 * (1 + 0.0 * sweep_qc) - 2 * l_v * z_v / b ** 2 * CYb_v
Cnp = -CL_ref / 8 - 2 * l_v * z_v / b ** 2 * CYb_v
Cnr = -0.25 * 0.02 + 2 * (l_v / b) ** 2 * CYb_v - 0.02
CYp = 2 * CYb_v * z_v / b
CYr = -2 * CYb_v * l_v / b
K_adv = 0.15
Cnda = -2 * K_adv * CL_ref * Clda
tail_q = CLa_h * eta_h * Sh / S
CLq = 2 * tail_q * (xh_ac - cg[0]) / c_ref + (0.5 + 2 * (cg[0] - x_ac_w) / mac) * CLa_w * mac / c_ref
Cmq = -2 * tail_q * (xh_ac - cg[0]) ** 2 / c_ref ** 2 * 1.1
CLadot = 2 * tail_q * (xh_ac - cg[0]) / c_ref * deps
th_a = math.acos(2 * cf_a - 1)
cp_frac = 0.25 + 0.5 * math.sin(th_a) * (1 - math.cos(th_a)) / (2 * (math.pi - th_a + math.sin(th_a)))
x_cp_ail = sum((z + cp_frac * c) * c * dy for _, z, c, _, dy in ail) / sum(c * dy for _, _, c, _, dy in ail)
Cmda = -CLda_each * (x_cp_ail - x_arp) / c_ref

# --- Drag build-up ---------------------------------------------------------------------------------------------
V = V_start
cf_mix = lambda L, lam_frac: lam_frac * 1.328 / math.sqrt(V * L / NU) + (1 - lam_frac) * 0.455 / math.log10(V * L / NU) ** 2.58
tc = v("aero.thickness_ratio")
exposed_wing = S - 2 * fus_at(0.2)[1] * fus_width_scale * cr_geo
ff_wing = (1 + 0.6 / 0.3 * tc + 100 * tc ** 4) * 1.34 * 0.34 ** 0.18 * math.cos(sweep_qc) ** 0.28
parts = {
    "wing": cf_mix(mac, 0.15) * ff_wing * 2.04 * exposed_wing,
    "tails": cf_mix(0.2, 0.15) * 1.12 * 2.03 * (Sh + Sv),
    "fuselage": cf_mix(fus_len, 0.05) * (1 + 60 / (fus_len / (fus_d * fus_width_scale)) ** 3 + (fus_len / fus_d) / 400) * (0.9 * math.pi * (fus_w * fus_width_scale + fus_d) / 2 * fus_len),
}
for k_, item in IN["drag_items"].items():
    parts[k_] = item["value"]
D_q = sum(parts.values()) * v("aero.excrescence_factor")
CD0 = note("drag", "CD0", D_q / S, "skin friction x form factors (Raymer ch. 12) + items, x excrescence factor: " + ", ".join(f"{k_} {x:.4f} m2" for k_, x in parts.items()))
e_osw = note("drag", "Oswald e", v("aero.oswald_e"), src("aero.oswald_e")[1])
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


sum_y = sum(station_centres(b, cr_eq, ct_eq))
wing_ail_eff = abs(Clda) * 6 * b / (CLa * sum_y)

# --- Turbine -------------------------------------------------------------------------------------------------------
T = IN["turbine"]
thrust_rows = T["static_thrust"]["value"]
mflow_rows = T["mass_flow"]["value"]
k_inst = v("turbine.installed_factor")


def tab(rows, x):
    if x <= rows[0][0]:
        return rows[0][1]
    for r0, r1 in zip(rows, rows[1:]):
        if x <= r1[0]:
            return r0[1] + (r1[1] - r0[1]) * (x - r0[0]) / (r1[0] - r0[0])
    return rows[-1][1]


n_max = v("turbine.max_rpm")
n_idle = v("turbine.idle_rpm")


def thrust_at(V_, n):
    """Net thrust as physics/turbine.gd computes it (ram recovery included)."""
    m0 = tab(mflow_rows, n)
    vj0 = k_inst * tab(thrust_rows, n) / m0
    mf = m0 * (1 + v("turbine.ram_flow") * V_ * V_)
    return mf * (math.sqrt(vj0 * vj0 + tab(T["ram_jet"]["value"], n) * V_ * V_) - V_)


def drag_at(V_):
    cl = mass * G0 / (0.5 * RHO * V_ * V_ * S)
    return 0.5 * RHO * V_ * V_ * S * (CD0 + k_ind * cl * cl)


lo_v, hi_v = Vs, 150.0
for _ in range(60):
    mid_v = 0.5 * (lo_v + hi_v)
    if thrust_at(mid_v, n_max) > drag_at(mid_v):
        lo_v = mid_v
    else:
        hi_v = mid_v
V_max = note("performance", "maximum level speed (m/s)", lo_v, f"full thrust minus ram drag meets the drag polar ({lo_v * 3.6:.0f} km/h; manual: tested to 250 km/h)")
note("performance", "static thrust / weight (installed)", k_inst * tab(thrust_rows, n_max) / (mass * G0), f"installed factor {k_inst}")
roc = (thrust_at(V_start, n_max) - drag_at(V_start)) * V_start / (mass * G0)
note("performance", f"full-throttle climb rate at {V_start:.0f} m/s (m/s)", roc, "excess power / weight")
note("performance", "idle net thrust at the start speed (N)", thrust_at(V_start, n_idle), "idle gross minus ram drag")
L_D = 1 / (2 * math.sqrt(CD0 * k_ind))
note("performance", "best glide L/D", L_D, f"at {math.sqrt(2 * mass * G0 / (RHO * S) * math.sqrt(k_ind / CD0)):.1f} m/s")

# --- Assemble ---------------------------------------------------------------------------------------------------------
stik = json.load(open(STIK))
D = lambda how: f"{SCRIPT}: {how}"
coeff = lambda value, unit, kind, how: q(float(value), unit, kind, D(how) if kind == "derived" else how)
coefficients = {
    "CL0": coeff(CL0, "1", "derived", "symmetric sections; wing and tail incidences at zero body alpha"),
    "CLa": coeff(CLa, "1/rad", "derived", "Helmbold wing with half-chord sweep + downwashed tail"),
    "CLadot": coeff(CLadot, "1/rad", "derived", "2 eta CLa_h Sh/S l_h/c deps/dalpha"),
    "CLq": coeff(CLq, "1/rad", "derived", "tail volume + DATCOM wing term"),
    "CLde": coeff(CLde, "1/rad", "derived", "tail slope x elevator effectiveness"),
    "CLda_each": coeff(CLda_each, "1/rad", "derived", "strip theory over the aileron span"),
    "CD0": coeff(CD0, "1", "derived", f"component drag build-up at {V_start:.0f} m/s, gear UP, flaps up, see derivation.md"),
    "CL_minD": q(0.0, "1", "estimated", "symmetric sections: minimum drag at zero lift"),
    "k_induced": coeff(k_ind, "1", "derived", f"1/(pi e AR), e {e_osw} estimated"),
    "CDda_each": q(stik["aero"]["coefficients"]["CDda_each"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file); second-order control drag"),
    "CDdr": q(stik["aero"]["coefficients"]["CDdr"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file); second-order control drag"),
    "CDde": q(stik["aero"]["coefficients"]["CDde"]["value"], "1/rad", "borrowed", "OpenFlightSim UltraStick25e (via the Stik data file); second-order control drag"),
    "CYb": coeff(CYb_v + CYb_B, "1/rad", "derived", "fin + DATCOM body"),
    "CYp": coeff(CYp, "1/rad", "derived", "fin above the CG"),
    "CYr": coeff(CYr, "1/rad", "derived", "fin behind the CG"),
    "CYdr": coeff(CYdr, "1/rad", "derived", "fin slope x Sv/S x rudder effectiveness (must equal the vertical surface)"),
    "Clb": coeff(Clb, "1/rad", "derived", "wing sweep at CL_ref + dihedral + wing-body + fin"),
    "Clp": coeff(Clp, "1/rad", "derived", "strip theory with taper + stab + fin"),
    "Clr": coeff(Clr, "1/rad", "derived", "CL_ref/4 + fin"),
    "Clda_right": coeff(Clda, "1/rad", "derived", "strip theory"),
    "Clda_left": coeff(-Clda, "1/rad", "derived", "strip theory"),
    "Cldr": coeff(Cldr, "1/rad", "derived", "rudder side force x fin height above the ARP"),
    "Cm0": coeff(Cm0, "1", "derived", "tail incidence about the ARP; symmetric wing section"),
    "Cma": coeff(Cma, "1/rad", "derived", "tail about the wing-body ac (Munk-Multhopp fuselage); the CG transfer gives the static margin"),
    "Cmq": coeff(Cmq, "1/rad", "derived", "tail damping about the CG x1.1 for wing/fuselage"),
    "Cmde": coeff(Cmde, "1/rad", "derived", "elevator lift x tail arm from the ARP"),
    "Cmda_each": coeff(Cmda, "1/rad", "derived", "aileron lift increment at its thin-airfoil centre, arm from the ARP"),
    "Cnb": coeff(Cnb, "1/rad", "derived", "fin only (v1 contract: equals the vertical surface)"),
    "Cnp": coeff(Cnp, "1/rad", "derived", "-CL_ref/8 + fin"),
    "Cnr": coeff(Cnr, "1/rad", "derived", "fin + wing profile drag + fuselage (-0.02 estimated)"),
    "Cnda_right": coeff(Cnda, "1/rad", "derived", "adverse yaw 2 K CL_ref Clda, K 0.15 (Nelson)"),
    "Cnda_left": coeff(-Cnda, "1/rad", "derived", "adverse yaw"),
    "Cndr": coeff(Cndr, "1/rad", "derived", "rudder side force x fin arm from the ARP (must equal the vertical surface)"),
}
surf = stik["aero"]["surfaces"]
same = lambda key: dict(surf[key], source="same provisional value as the Ugly Stik surface model (" + surf[key]["source"].split(";")[-1].strip() + ")", kind=surf[key]["kind"] if surf[key]["kind"] != "derived" else "estimated")
eng = IN["turbine"]
tq = lambda key, unit: q(eng[key]["value"], unit, eng[key]["kind"], eng[key]["source"])
intake = g["installation"]["intake_stations"][0]
EXHAUST_Z = 1.1685 + DZ  # app/aircraft/avanti_s_model.gd: the fixed exhaust ring at the tail cone (model z)
engine_c = g["installation"]["engine_center"]
canopy_top = max(g["canopy_stations"], key=lambda r: r[2])
tip = Wg["stations"][-1]
ts = Tg["stations"][-1]
data = {
    "format": "openrc-aircraft v1",
    "id": "sebart-avanti-s-a200-p100rx",
    "description": f"SebArt Avanti S Jet 2.2m ARF (A200, {b:.2f} m span) with a JetCat P100-RX turbine. EXPERIMENTAL first physics estimate (AV-06), generated by {SCRIPT}; not flight-identified. Flaps up, gear up (in-air start; no landing gear contacts). Visual geometry: assets/aircraft/avanti-s-a200/geometry.json.",
    "frames": {
        "le_frame": "positions in metres from the root wing leading edge beside the fuselage (model z 0) on the root wing mid-plane (model y 0): [x_aft, y_right, z_up]",
        "body": "simulation body axes FRD about the CG: x forward = -x_aft, y right, z down = -z_up",
    },
    "reference": {
        "wing_area": q(S, "m2", "derived", D("polyline planform through the fuselage" + (f", chords scaled x{chord_scale:.4f} to the published area" if target else " from " + GEO_SRC))),
        "wing_span": qi("airframe.span", "m"),
        "mean_chord": q(c_ref, "m", "derived", f"S / b: the v1 coefficient reference length. NOT the MAC ({mac:.4f} m)"),
        "root_chord": q(cr_eq, "m", "derived", D(f"equivalent trapezoid (same area and spanwise centroid as the polyline planform); geometric root {cr_geo:.3f} m")),
        "tip_chord": q(ct_eq, "m", "derived", D(f"equivalent trapezoid; geometric tip {ct_geo:.3f} m")),
        "aero_reference_point": q(le(x_arp, 0.0), "m", "derived", D("wing-body aerodynamic centre: 25 % MAC moved forward by the Munk-Multhopp fuselage moment; on the root wing plane")),
        "planform": "tapered",
    },
    "start": {"level_speed": qi("start.level_speed", "m/s")},
    "balance": {
        "plan_cg": q(cg, "m", src("airframe.cg_aft_of_root_le")[0], f"{cg_z * 1000:.0f} mm aft of the root LE ({src('airframe.cg_aft_of_root_le')[1]}); z from the inventory (derived)"),
        "firewall": q(le(engine_c[2] - 0.12, engine_c[1]), "m", "estimated", "turbine mount ring: front of the P100-RX (241 mm long) centred at the geometry's engine_center"),
        "configuration": "virtual-balanced-reference-v1",
        "cg_tolerance": q(0.001, "m", "estimated", D("virtual reference build balanced to the manual's point, NOT a measured airplane")),
    },
    "inventory": [
        dict({"name": it[0], "mass": q(float(it[1]), "kg", it[2], it[3]), "position": q([float(x) for x in it[4]], "m", it[6], it[7])},
             **({"size": q([float(x) for x in it[5]], "m", "estimated", "rough envelope for intrinsic inertia")} if it[5] else {}))
        for it in items
    ],
    "crash_hull": q([
        le(tip[1], tip[3], -semi), le(tip[1], tip[3], semi), le(tip[2], tip[3], -semi), le(tip[2], tip[3], semi),
        le(FS[0][0]), le(FS[-1][0], FS[-1][3]),
        le(0.0, fus_at(0.0)[3]), le(-0.5, fus_at(-0.5)[3]), le(0.6, fus_at(0.6)[3]),
        le(ts[2], ts[3], -ts[0]), le(ts[2], ts[3], ts[0]),
        le(max(z for z, _ in fin_raw), fin_top_y),
        le(canopy_top[0], canopy_top[2]),
    ], "m", "derived", "Points that hit the ground first (le frame) from " + GEO_SRC + ": wing tips LE/TE, nose and tail cone, belly at three stations (gear UP), stab tips, fin top, canopy top. No landing gear contacts: any ground contact is a crash (gear up)"),
    "plausibility": {
        "mass_range": qi("airframe.mass_range", "kg"),
        "inertia_reference": stik["plausibility"]["inertia_reference"],
    },
    "controls": {
        "max_throw": {
            "aileron": qi("controls.aileron_up", "deg"),
            "aileron_down": qi("controls.aileron_down", "deg"),
            "elevator": qi("controls.elevator", "deg"),
            "rudder": qi("controls.rudder", "deg"),
        },
        "servo_full_throw_time": qi("controls.servo_full_throw_time", "s"),
    },
    "aero": {
        "source": f"Derived by {SCRIPT} (Helmbold/DATCOM with sweep, Munk-Multhopp fuselage, tail volume, strip theory, drag build-up); report research/avanti-s/av06/derivation.md. Not flight-identified: EXPERIMENTAL.",
        "envelope": {
            "CL_max": qi("aero.CL_max", "1"),
            "CL_min": q(-v("aero.CL_max"), "1", "derived", "symmetric sections: the inverted stall mirrors the upright one"),
            "stall_blend_width": qi("aero.stall_blend_width", "deg"),
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
            "wing_station_incidence": qi("aero.wing_station_incidence", "rad"),
            "horizontal": {
                "area": q(Sh, "m2", "derived", D("stab + elevator planform from " + GEO_SRC)),
                "position": q(le(xh_ac, h_stab), "m", "derived", D("quarter chord of the stab MAC")),
                "lift_slope": q(slope_h, "1/rad", "derived", D("Helmbold x eta x (1 - deps/dalpha), DATCOM downwash")),
                "control_effectiveness": q(ce_h, "1", "derived", D("thin-airfoil tau x flap correction / (1 - deps/dalpha)")),
                "incidence": q(inc_eff, "rad", "derived", D("(stab incidence - eps0) / (1 - deps/dalpha)")),
            },
            "vertical": {
                "area": q(Sv, "m2", "derived", D("fin + rudder outline above the fuselage from " + GEO_SRC)),
                "position": q(le(xv_ac, fin_cy), "m", "derived", D("fin ac: area centroid less a quarter of the mean chord")),
                "lift_slope": q(slope_v, "1/rad", "derived", D("Helmbold (end-plated AR) x DATCOM sidewash/eta")),
                "control_effectiveness": q(ce_v, "1", "derived", D("thin-airfoil tau x flap correction / sidewash factor")),
                "incidence": q(0.0, "rad", "estimated", "symmetric fin; the turbine has no reaction torque to trim"),
            },
        },
    },
    "propulsion": {
        "kind": "turbine",
        "description": "JetCat P100-RX (2017 catalog, non-BL) in a fixed thrust tube: ECU throttle map, acceleration/deceleration-limited spool with a governor lag, bench thrust at STP x installed factor, momentum ram drag and inlet normal force at the intakes (physics/turbine.gd, docs/research/avanti-s-av05-turbine-dynamics.md).",
        "engine": {
            "name": "JetCat P100-RX (catalog 2017, 44 000-154 000 rpm, 2-100 N)",
            "idle_rpm": tq("idle_rpm", "rpm"),
            "max_rpm": tq("max_rpm", "rpm"),
            "static_thrust": tq("static_thrust", "rpm, N"),
            "mass_flow": tq("mass_flow", "rpm, kg/s"),
            "fuel_flow": tq("fuel_flow", "rpm, kg/s"),
            "throttle_map": tq("throttle_map", "1, rpm"),
            "accel_limit": tq("accel_limit", "rpm, rpm/s"),
            "decel_limit": tq("decel_limit", "rpm, rpm/s"),
            "governor_tau": tq("governor_tau", "s"),
            "installed_factor": tq("installed_factor", "1"),
            "ram_flow": tq("ram_flow", "s2/m2"),
            "ram_jet": tq("ram_jet", "rpm, 1"),
            "rotor_inertia": tq("rotor_inertia", "kg·m2"),
            "rotor_sense": tq("rotor_sense", "1"),
        },
        "thrust_line_offset": q([EXHAUST_Z - cg[0], 0.0, engine_c[1] - cg[2]], "m", "derived", D("nozzle exit on the engine axis (geometry engine_center height, tube exit z 1.1685) relative to the inventory CG; [x_aft, y_right, z_up]")),
        "intake_offset": q([intake[0] - cg[0], 0.0, (intake[2] + intake[3]) / 2 - cg[2]], "m", "derived", D("centroid of the two side intake mouths (geometry intake_stations[0]) relative to the CG")),
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
    for k, x in exp.items():
        d["aero"]["coefficients"][k]["value"] = x
    rc, tc_ = d["reference"]["root_chord"]["value"], d["reference"]["tip_chord"]["value"]
    assert abs(b_ * (rc + tc_) / 2 - S_) / S_ < 0.01 and abs(b_ * d["reference"]["mean_chord"]["value"] - S_) / S_ < 0.01


check_consistency(data)

text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
rows = ["| Section | Quantity | Value | How |", "| --- | --- | --- | --- |"]
for sec, name, val, how in log:
    vv = ", ".join(f"{x:.4g}" for x in val) if isinstance(val, list) else f"{val:.4g}"
    rows.append(f"| {sec} | {name} | {vv} | {how} |")
coef_rows = ["| Coefficient | Value | Kind |", "| --- | --- | --- |"] + [f"| {k} | {x['value']:.5g} | {x['kind']} |" for k, x in data["aero"]["coefficients"].items()]
eng_rows = ["| rpm | bench thrust (N) | installed static (N) | net at start speed (N) | air flow (kg/s) |", "| --- | --- | --- | --- | --- |"] + [
    f"| {r[0]:.0f} | {r[1]:.1f} | {k_inst * r[1]:.1f} | {thrust_at(V_start, r[0]):.1f} | {tab(mflow_rows, r[0]):.3f} |" for r in thrust_rows if r[0] >= n_idle]
report = f"""# AV-06: SebArt Avanti S (A200) with JetCat P100-RX, physics derivation

Generated by `{SCRIPT}` from `{GEOMETRY.relative_to(ROOT)}` and `inputs.json`; do not edit (regenerate). Output:
`{OUT.relative_to(ROOT)}`. **Experimental**: textbook estimates from an estimated visual geometry and sourced kit/engine data,
not flight identification. Flaps up and gear up; in-air start only.

Flight mass {mass:.3f} kg (fuel {fuel_kg:.2f} kg), CG {cg_z * 1000:.0f} mm aft of the root LE = {100 * (cg_z - mac_le) / mac:.1f} % MAC, static margin {sm:.1f} % MAC.
1-g stall {Vs:.1f} m/s clean, start {V_start:.0f} m/s, maximum level speed {V_max:.1f} m/s ({V_max * 3.6:.0f} km/h).
Throws (manual high rate): aileron {v('controls.aileron_up')}° up / {v('controls.aileron_down')}° down, elevator ±{v('controls.elevator')}°, rudder ±{v('controls.rudder')}°.

## Intermediate quantities

{chr(10).join(rows)}

## Coefficients written (c_ref = S/b; moments about the ARP = wing-body ac)

{chr(10).join(coef_rows)}

## Turbine at sea level

{chr(10).join(eng_rows)}

## Known simplifications

- Geometry is the AV-02 visual blockout (estimated sections); see the inputs' scale factors and their sources.
- Flaps fixed up; retracts up. No landing gear contacts (crash hull only): takeoff and landing need AV-09.
- Fuel mass fixed at the declared state (no burn, AV-10). Turbine start, stop and flameout not modelled.
- Fuselage directional destabilization omitted (v1 contract: Cnb equals the fin term), as for every aircraft.
- The local (post-stall) wing strips use the whole-airplane CLa, so local lift is ~{100 * slope_h * Sh / S / CLa:.0f} % high (tail counted twice).
- CL-dependent cross terms (Clb sweep part, Clr, Cnp, adverse yaw) are frozen at CL_ref = {CL_ref:.2f}.
"""

if __name__ != "__main__":
    pass  # imported by sensitivity.py: compute only
elif "--check" in sys.argv:
    stale = [p for p, t in ((OUT, text), (REPORT, report)) if not p.exists() or p.read_text() != t]
    if stale:
        sys.exit("stale: " + ", ".join(str(p.relative_to(ROOT)) for p in stale) + f" (run {SCRIPT})")
    print("sebart_avanti_s_a200.json and derivation.md are up to date")
else:
    OUT.write_text(text)
    REPORT.write_text(report)
    print(f"wrote {OUT.relative_to(ROOT)} and {REPORT.relative_to(ROOT)}")
    print(f"mass {mass:.3f} kg, SM {sm:.1f} % MAC, stall {Vs:.1f} m/s, start {V_start:.0f} m/s, Vmax {V_max:.1f} m/s, J {[round(x, 3) for x in J]}")
