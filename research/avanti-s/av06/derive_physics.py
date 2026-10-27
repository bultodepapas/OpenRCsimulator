#!/usr/bin/env python3
"""AV-06: physics data of the SebArt Avanti S Jet 2.2m (A200, 2.00 m span) with a JetCat P100-RX, derived and reproducible.

Reads the physical surrogate geometry (assets/aircraft/avanti-s-a200/geometry.json, AV-02 blockout), gear-up collision
witnesses and retractable wheel trajectories from assets/aircraft/avanti-s-a200/blender-geometry.json, the sourced inputs in
research/avanti-s/av06/inputs.json (manual, catalog, research reports) and the Ugly Stik data file (shared conventions and
the provisional local-surface limits). The Blender geometry supplies visual collision probes and wheel-center/contact
trajectories only; it does not calibrate the physical aircraft, aerodynamic surfaces, mass properties, spring behavior,
or turbine installation. Writes
app/data/aircraft/sebart_avanti_s_a200.json (openrc-aircraft v2 with propulsion kind "turbine", AV-05) and
research/avanti-s/av06/derivation.md.

Methods are textbook estimates, not flight identification: Helmbold/DATCOM lift slopes with sweep, DATCOM downwash with
tail height, Munk-Multhopp fuselage moment with Biot-Savart upwash, tail-volume derivatives, strip theory for ailerons and
roll damping, a skin-friction drag build-up, a component inventory, and a momentum-theory turbojet. Every number written
carries its unit, evidence kind and source.

    python3 research/avanti-s/av06/derive_physics.py           # writes the JSON and the report
    python3 research/avanti-s/av06/derive_physics.py --check   # fails if either file is stale
"""
import hashlib
import argparse
import json
import math
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "research/aero"))
from aileron_effectiveness import derive_effectiveness  # noqa: E402
sys.path.insert(0, str(ROOT / "research" / "fuel-systems"))
import fuel_registry  # noqa: E402
KEROSENE_BLEND = "kerosene_5pct_turbine_oil"
CLI_ARGS = None
if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--check", action="store_true", help="check canonical generated outputs without writing")
    cli.add_argument("--flap-aero-disabled", action="store_true",
                     help="write a software sensitivity variant with flap aerodynamics zeroed; actuator remains active")
    cli.add_argument("--output", type=Path, help="JSON output path (primarily for an isolated sensitivity variant)")
    cli.add_argument("--report-output", type=Path, help="derivation report path")
    CLI_ARGS = cli.parse_args()
    if CLI_ARGS.flap_aero_disabled and CLI_ARGS.output is None:
        cli.error("--flap-aero-disabled requires --output so the canonical aircraft is not overwritten")
MIGRATOR_DIR = ROOT / "research/aircraft-standardization"
if str(MIGRATOR_DIR) not in sys.path:
    sys.path.insert(0, str(MIGRATOR_DIR))
from migrate import legacy_input, numeric_parity, upgrade  # noqa: E402
from physical_identity import validate_physical_identity  # noqa: E402
sys.path.insert(0, str(ROOT / "research/avanti-s/av17-r2"))
from build_polar import build_polar  # noqa: E402

GEOMETRY = ROOT / "assets/aircraft/avanti-s-a200/geometry.json"
COLLISION_GEOMETRY = ROOT / "assets/aircraft/avanti-s-a200/blender-geometry.json"
INPUTS = ROOT / "research/avanti-s/av06/inputs.json"
STIK = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
WHEEL_PROFILES = ROOT / "app/data/ground/wheel_profiles.json"
PROJECT_SETTINGS = ROOT / "app/project.godot"
OUT_DIR = Path(os.environ.get("OPENRC_AIRCRAFT_OUTPUT_DIR", ROOT / "app/data/aircraft")).resolve()
REPORT_DIR = Path(os.environ.get("OPENRC_AIRCRAFT_REPORT_DIR", ROOT / "research/avanti-s/av06")).resolve()
OUT = CLI_ARGS.output.resolve() if CLI_ARGS and CLI_ARGS.output else OUT_DIR / "sebart_avanti_s_a200.json"
REPORT = CLI_ARGS.report_output.resolve() if CLI_ARGS and CLI_ARGS.report_output else REPORT_DIR / "derivation.md"
RHO = 1.225
G0 = 9.80665
NU = 1.46e-5
SCRIPT = "research/avanti-s/av06/derive_physics.py"
GEO_SRC = "assets/aircraft/avanti-s-a200/geometry.json (AV-02 visual blockout, estimated)"
COLLISION_GEOMETRY_SRC = "assets/aircraft/avanti-s-a200/blender-geometry.json"

g = json.loads(GEOMETRY.read_text(encoding="utf-8"))
collision_geometry_bytes = COLLISION_GEOMETRY.read_bytes()
collision_geometry_hash = hashlib.sha256(collision_geometry_bytes).hexdigest()
collision_geometry = json.loads(collision_geometry_bytes.decode("utf-8"))
wheel_profile_bytes = WHEEL_PROFILES.read_bytes()
wheel_profile_hash = hashlib.sha256(wheel_profile_bytes).hexdigest()
wheel_profile_registry = json.loads(wheel_profile_bytes.decode("utf-8"))
project_settings = PROJECT_SETTINGS.read_text(encoding="utf-8")
physics_tick_match = re.search(r"(?m)^common/physics_ticks_per_second=(\d+)\s*$", project_settings)
if physics_tick_match is None:
    raise ValueError(f"{PROJECT_SETTINGS.relative_to(ROOT)} must declare common/physics_ticks_per_second")
PHYSICS_TICK_HZ = int(physics_tick_match.group(1))
IN = globals().get("IN_OVERRIDE") or json.loads(INPUTS.read_text(encoding="utf-8"))  # sensitivity.py injects modified inputs
log = []
# Wing station along the fuselage (inputs airframe.wing_forward_shift): every fuselage-attached part (fuselage, canopy,
# tail, fin, installation, fuselage items) moves aft by this much relative to the wing and its leading-edge datum, i.e.
# the wing sits that much further forward on the fuselage than the visual blockout draws it. 0 = the blockout as drawn.
DZ = IN["airframe"]["wing_forward_shift"]["value"]
if not math.isfinite(DZ):
    raise ValueError("airframe.wing_forward_shift must be finite")
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
    area = sum(chord * dy for _, _, chord, _, dy in st)
    mac = sum(chord * chord * dy for _, _, chord, _, dy in st) / area
    # The geometric leading edge of the MAC is area weighted; chord-squared weighting is only for MAC length.
    mac_le = sum(chord * le_z * dy for _, le_z, chord, _, dy in st) / area
    y_mac = sum(chord * y * dy for y, _, chord, _, dy in st) / area  # area centroid of the semi-span
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
c_ref = note("reference", "geometric S/b used in coefficient derivation (m)", S / b, "unrounded current polyline planform area / manual span")
if IN["airframe"].get("coefficient_reference_length"):
    c_ref_output = v("airframe.coefficient_reference_length")
    c_ref_output_kind, c_ref_output_source = src("airframe.coefficient_reference_length")
else:
    c_ref_output = c_ref
    c_ref_output_kind, c_ref_output_source = "derived", "geometric S / b; serialized v1 coefficient reference length (not the MAC)"
c_ref_output = note("reference", "serialized coefficient reference length (m)", c_ref_output, c_ref_output_source)
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
FUSELAGE_SHELL_IDS = {
    (-1.05, -1.0): "fuselage_shell_nose_to_front",
    (-1.0, -0.85): "fuselage_shell_front_to_cabin",
    (-0.85, -0.65): "fuselage_shell_cabin_forward",
    (-0.65, -0.4): "fuselage_shell_cabin_center",
    (-0.4, -0.15): "fuselage_shell_cabin_aft",
    (-0.15, 0.0): "fuselage_shell_wing_front",
    (0.0, 0.3): "fuselage_shell_wing_aft",
    (0.3, 0.6): "fuselage_shell_mid_tail",
    (0.6, 0.86): "fuselage_shell_tail_forward",
    (0.86, 1.05): "fuselage_shell_tail_aft",
    (1.05, 1.17): "fuselage_shell_exhaust_exit",
}
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
sm = note("aero", "static margin at the manual CG, main tank empty (% MAC)", 100 * (x_np - cg_z) / mac,
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
# CR-22b: which inventory items carry energy (crash fire/smoke presentation only).
ENERGY_SOURCES = {"kerosene + 5 % oil (declared fuel state)": "kerosene"}
items = []
# Structure measured by owners (airframe research): placed from the geometry.
ST = IN["structure"]
exposed = [st_ for st_ in wst if st_[0] >= Wg["stations"][0][0]]
ex_area = sum(c * dy for _, _, c, _, dy in exposed)
ex_y = sum(c * y * dy for y, _, c, _, dy in exposed) / ex_area
ex_z = sum((z + 0.42 * c) * c * dy for _, z, c, _, dy in exposed) / ex_area
for side, sign in (("left", -1.0), ("right", 1.0)):
    items.append((f"wing panel {side}, covered, with flap and aileron", float(ST["wing_panel"]["value"]), ST["wing_panel"]["kind"], ST["wing_panel"]["source"],
                  le(ex_z, ex_y * math.tan(dihedral), sign * ex_y), [mac, semi - Wg["stations"][0][0], 0.05], "derived", "42 % chord at the exposed panel's area centroid (geometry.json)",
                  {"left": "wing_left", "right": "wing_right"}[side]))
tail_root_y = Tg["stations"][0][0]
exposed_tail = [(y, le_z, chord, height, dy) for y, le_z, chord, height, dy in tst if y >= tail_root_y]
th_area = sum(chord * dy for _, _, chord, _, dy in exposed_tail)
th_y = sum(chord * y * dy for y, _, chord, _, dy in exposed_tail) / th_area
th_z = sum((le_z + 0.45 * chord) * chord * dy for _, le_z, chord, _, dy in exposed_tail) / th_area
for side, sign in (("left", -1.0), ("right", 1.0)):
    items.append((f"stab half {side} with elevator", float(ST["stab_half"]["value"]), ST["stab_half"]["kind"], ST["stab_half"]["source"],
                  le(th_z, h_stab, sign * th_y), [mach, bh / 2, 0.02], "derived", "45 % chord at the stab half's area centroid (geometry.json)",
                  {"left": "stabilizer_left", "right": "stabilizer_right"}[side]))
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
                  le(zc, yc), [r1[0] - r0[0], 2 * max(r0[1], r1[1]), max(r0[2] - r0[3], r1[2] - r1[3])], "derived", "segment centre, fuselage stations (geometry.json)",
                  FUSELAGE_SHELL_IDS[(r0[0], r1[0])]))
if set(FUSELAGE_SHELL_IDS) != {(r0[0], r1[0]) for r0, r1, _ in segs}:
    raise ValueError("Avanti fuselage-shell identity source does not match the authored station pairs")
items.append(("fin and rudder", float(ST["fin"]["value"]), ST["fin"]["kind"], ST["fin"]["source"], le(fin_cz, fin_cy), [0.3, 0.015, h_v], "derived", "fin outline area centroid (geometry.json)", "vertical_tail"))
for it in IN["inventory"]:
    pos = list(it["position_model"])  # [model z, model y, model x]
    if it.get("attached", "fuselage") != "wing":
        pos[0] += DZ
    items.append((it["name"], float(it["mass"]["value"]), it["mass"]["kind"], it["mass"]["source"],
                  le(pos[0], pos[1], pos[2]), it.get("size"), it["position_kind"], it["position_source"], it["id"]))
fuel_l = v("fuel.tank_l") * v("fuel.fraction")
# FUEL-05e: the density lives in the fuel registry; the input mirrors it for the AV-14 sensitivity tools.
if abs(v("fuel.density") * 1000.0 - fuel_registry.blend_density(KEROSENE_BLEND)) > 1e-9:
    raise ValueError("inputs fuel.density must equal the registry blend " + KEROSENE_BLEND)
fuel_kg = fuel_l * v("fuel.density")
fpos = list(v("fuel.position_model"))
fpos[0] += DZ
items.append(("kerosene + 5 % oil (declared fuel state)", fuel_kg, "derived",
              f"{v('fuel.tank_l')} l x {v('fuel.fraction')} x {v('fuel.density')} kg/l ({src('fuel.tank_l')[1]}; {src('fuel.fraction')[1]})",
              le(fpos[0], fpos[1], fpos[2]), [0.25, 0.14, 0.10], "estimated", src("fuel.position_model")[1], "fuel_flight"))
# Builders balance a jet by placing the batteries and electronics (inputs: "balance_item"): they move together, within
# the bay limits, to put the CG on the manual's point; whatever they cannot reach becomes a virtual balancing mass.
movable = [k for k, it in enumerate(IN["inventory"]) if it.get("balance_item")]
offset = len(items) - len(IN["inventory"]) - 1  # index of the first inventory item in `items`
z_lo, z_hi = IN["balance"]["balance_item_range_z"]
m_mov = sum(items[offset + k][1] for k in movable)
# FUEL-05e: the manual point is met with the main tank empty (full hopper, empty main); the fuel item is last.
mom = sum(i[1] * i[4][0] for i in items[:-1])
m_all = sum(i[1] for i in items[:-1])
mom_fixed = mom - sum(items[offset + k][1] * items[offset + k][4][0] for k in movable)
z_bal = min(max((cg_z * m_all - mom_fixed) / m_mov, z_lo), z_hi)
for k in movable:
    it = items[offset + k]
    items[offset + k] = (it[0], it[1], it[2], it[3], [z_bal, it[4][1], it[4][2]], it[5], "derived",
                         f"placed to balance: the batteries and electronics together at model z {z_bal:.3f} (bay {z_lo}..{z_hi} m)", it[8])
note("balance", "batteries/electronics station (model z)", z_bal, f"{m_mov:.2f} kg moved within {z_lo}..{z_hi} m to approach the manual CG" + (" (at the bay limit)" if z_bal in (z_lo, z_hi) else ""))
dry = sum(i[1] for i in items[:-1])
note("balance", "pre-balance dry components (kg)", dry, f"inventory before virtual balance mass; SebArt manual reference is {v('airframe.dry_mass')} kg complete RTF dry with P100")
fuel_item = items[-1]
mass0 = sum(i[1] for i in items if i is not fuel_item)
x_cg0 = sum(i[1] * i[4][0] for i in items if i is not fuel_item) / mass0
note("balance", "inventory CG without balancing mass (model z)", x_cg0, f"target {cg_z:.3f}")
nose = x_cg0 > cg_z
xb = IN["balance"]["nose_ballast_z"] if nose else IN["balance"]["tail_ballast_z"]
mb = mass0 * (cg_z - x_cg0) / (xb - cg_z)
note("balance", "balancing mass (kg)", mb, ("nose" if nose else "tail") + " weight that puts the CG on the manual's point")
if mb > 1e-6:
    items.append(("virtual reference-build balancing mass", mb, "derived",
                  f"{SCRIPT}: m = M (x_CG - x0) / (x_ballast - x_CG) for the manual balance point; a virtual reference build, NOT measured hardware",
                  [xb, 0.0, 0.0], [0.04, 0.04, 0.04], "estimated", "nose cone" if nose else "tail cone", "ballast_reference"))
dry_mass = sum(i[1] for i in items if i is not fuel_item)
dry_cg = [sum(i[1] * i[4][k] for i in items if i is not fuel_item) / dry_mass for k in range(3)]
dry_cg[1] = 0.0
note("balance", "empty-main-tank CG (le frame)", dry_cg, "manual 240 mm point with a full hopper and an empty main tank (FUEL-05e)")
mass = sum(i[1] for i in items)
cg = [sum(i[1] * i[4][k] for i in items) / mass for k in range(3)]
cg[1] = 0.0
note("balance", "dry flight mass including virtual balance (kg)", mass - fuel_kg,
     f"component inventory plus virtual reference-build mass; manual complete RTF dry reference {v('airframe.dry_mass')} kg")
note("balance", "flight mass (kg)", mass, f"dry {mass - fuel_kg:.3f} kg + fuel {fuel_kg:.3f} kg")
note("balance", "flight CG (le frame)", cg, "z from the inventory")
# FUEL-05e: the flown (declared) fuel sits ahead of the empty-main-tank balance point; report its margin.
sm = note("aero", "static margin at the flight CG, declared fuel (% MAC)", 100 * (x_np - cg[0]) / mac,
          f"flight CG {cg[0] * 1000:.1f} mm aft of the root LE with {fuel_kg:.3f} kg of fuel; same neutral point")


def inertia(pt):
    # Full symmetric tensor order matches aircraft_data.inertia_about():
    # [Jxx, Jyy, Jzz, Jxy, Jxz, Jyz].
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


def principal_moments(tensor):
    """Eigenvalues of the symmetric inertia tensor, sorted ascending (kg m2)."""
    xx, yy, zz, xy, xz, yz = tensor
    mean = (xx + yy + zz) / 3.0
    p1 = xy * xy + xz * xz + yz * yz
    if p1 < 1e-30:
        return sorted((xx, yy, zz))
    p2 = (xx - mean) ** 2 + (yy - mean) ** 2 + (zz - mean) ** 2 + 2.0 * p1
    p = math.sqrt(p2 / 6.0)
    b00, b11, b22 = (xx - mean) / p, (yy - mean) / p, (zz - mean) / p
    b01, b02, b12 = xy / p, xz / p, yz / p
    determinant = b00 * b11 * b22 + 2.0 * b01 * b02 * b12 - b00 * b12 * b12 - b11 * b02 * b02 - b22 * b01 * b01
    phi = math.acos(max(-1.0, min(1.0, determinant / 2.0))) / 3.0
    first = mean + 2.0 * p * math.cos(phi)
    third = mean + 2.0 * p * math.cos(phi + 2.0 * math.pi / 3.0)
    second = 3.0 * mean - first - third
    return sorted((first, second, third))


J = note("balance", "Jxx Jyy Jzz Jxy Jxz Jyz (kg m2)", inertia(cg), "component boxes + parallel axis; products use the runtime body-FRD convention")
I_principal = note("balance", "principal moments (kg m2)", principal_moments(J), "eigenvalues of the full symmetric inventory tensor; positive values check arithmetic, not physical validation")

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
Cnp_cg = -CL_ref / 8 - 2 * l_v * z_v / b ** 2 * CYb_v
Cnr_cg = -0.25 * 0.02 + 2 * (l_v / b) ** 2 * CYb_v - 0.02
CYp = 2 * CYb_v * z_v / b
CYr = -2 * CYb_v * l_v / b
# AV-17-R3: runtime transfers ARP moments to CG once. These build-ups used CG arms,
# so remove the side-force rate moment at the forward ARP before serialization.
arp_forward_of_cg = cg[0] - x_arp
Cnp = Cnp_cg - CYp * arp_forward_of_cg / b
Cnr = Cnr_cg - CYr * arp_forward_of_cg / b
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
cd0_how = (
    f"estimated Raymer build-up at V_start={V_start:.0f} m/s (about Mach 0.09), "
    "cf_mix laminar fractions 0.15 wing/tails and 0.05 fuselage, fixed wing Raymer Mach multiplier evaluated at M=0.34, "
    "tail form factor 1.12, listed item drag areas, then "
    f"x excrescence factor {v('aero.excrescence_factor'):.2f}; "
    "not matched to measured local Re/Mach or Avanti flight data. Components: "
    + ", ".join(f"{name} {value:.4f} m2" for name, value in parts.items())
)
CD0 = note("drag", "CD0", D_q / S, cd0_how)
e_osw = note("drag", "Oswald e", v("aero.oswald_e"), src("aero.oswald_e")[1])
k_ind = 1 / (math.pi * e_osw * AR)


# D11-R1: match the authored roll derivative through the current induced-flow map.
wing_ail_eff = derive_effectiveness(S, b, CLa, slope_h * Sh / S, Clda, (cr_eq, ct_eq))

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
stik = legacy_input(json.loads(STIK.read_text(encoding="utf-8")))
D = lambda how: f"{SCRIPT}: {how}"
coeff = lambda value, unit, kind, how: q(float(value), unit, kind, D(how) if kind == "derived" else how)
coefficients = {
    "CL0": coeff(CL0, "1", "derived", "symmetric sections; wing and tail incidences at zero body alpha"),
    "CLa": coeff(CLa, "1/rad", "derived", "Helmbold wing with half-chord sweep + downwashed tail"),
    "CLadot": coeff(CLadot, "1/rad", "derived", "2 eta CLa_h Sh/S l_h/c deps/dalpha"),
    "CLq": coeff(CLq, "1/rad", "derived", "tail volume + DATCOM wing term"),
    "CLde": coeff(CLde, "1/rad", "derived", "tail slope x elevator effectiveness"),
    "CLda_each": coeff(CLda_each, "1/rad", "derived", "strip theory over the aileron span"),
    "CD0": coeff(CD0, "1", "derived", f"estimated component drag build-up at {V_start:.0f} m/s (about Mach 0.09), gear UP/flaps up; fixed M=0.34 wing form-factor multiplier, assumed transition fractions and tail form factor; full basis and item areas in research/avanti-s/av06/derivation.md, CD0 model basis"),
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
    "Cnp": coeff(Cnp, "1/rad", "derived", "-CL_ref/8 + fin about CG, minus CYp*(x_CG-x_ARP)/b for the ARP moment contract; AV-17-R3"),
    "Cnr": coeff(Cnr, "1/rad", "derived", "fin + wing profile drag + fuselage (-0.02 estimated) about CG, minus CYr*(x_CG-x_ARP)/b for the ARP moment contract; AV-17-R3"),
    "Cnda_right": coeff(Cnda, "1/rad", "derived", "adverse yaw 2 K CL_ref Clda, K 0.15 (Nelson)"),
    "Cnda_left": coeff(-Cnda, "1/rad", "derived", "adverse yaw"),
    "Cndr": coeff(Cndr, "1/rad", "derived", "rudder side force x fin arm from the ARP (must equal the vertical surface)"),
}
surf = stik["aero"]["surfaces"]
same = lambda key: dict(surf[key], source="same provisional value as the Ugly Stik surface model (" + surf[key]["source"].split(";")[-1].strip() + ")", kind=surf[key]["kind"] if surf[key]["kind"] != "derived" else "estimated")
eng = IN["turbine"]
tq = lambda key, unit: q(eng[key]["value"], unit, eng[key]["kind"], eng[key]["source"])
intake = g["installation"]["intake_stations"][0]
EXHAUST_Z = 1.1685 + DZ  # Preserved AV-02 physical-surrogate nozzle station; not the AV-31 visual outlet.
engine_c = g["installation"]["engine_center"]
CRASH_HULL_IDS = (
    "probe_wing_left_le", "probe_wing_right_le", "probe_wing_left_te", "probe_wing_right_te",
    "probe_nose_tip", "probe_tail_cone", "probe_belly_station_zero", "probe_belly_station_minus_half",
    "probe_belly_station_plus_six", "probe_stabilizer_left_tip", "probe_stabilizer_right_tip",
    "probe_fin_top", "probe_canopy_top",
)
FUSELAGE_ATTACHED_CRASH_HULL_IDS = {
    "probe_nose_tip", "probe_tail_cone", "probe_belly_station_zero", "probe_belly_station_minus_half",
    "probe_belly_station_plus_six", "probe_stabilizer_left_tip", "probe_stabilizer_right_tip",
    "probe_fin_top", "probe_canopy_top",
}
collision_probe_records = collision_geometry.get("collision_probes")
if not isinstance(collision_probe_records, list):
    raise ValueError(f"{COLLISION_GEOMETRY_SRC} must contain a collision_probes array")
collision_probe_ids = [record.get("id") if isinstance(record, dict) else None for record in collision_probe_records]
if collision_probe_ids != list(CRASH_HULL_IDS):
    raise ValueError(
        f"{COLLISION_GEOMETRY_SRC} collision_probes IDs/order must be exactly {list(CRASH_HULL_IDS)!r}; "
        f"found {collision_probe_ids!r}"
    )
wing_crash_hull_ids = set(CRASH_HULL_IDS[:4])
if (FUSELAGE_ATTACHED_CRASH_HULL_IDS & wing_crash_hull_ids
        or (FUSELAGE_ATTACHED_CRASH_HULL_IDS | wing_crash_hull_ids) != set(CRASH_HULL_IDS)):
    raise AssertionError("Crash-hull witness shift groups must partition the expected IDs")

crash_hull_probes = []
for record in collision_probe_records:
    model_position = record.get("model_position")
    if (not isinstance(model_position, list) or len(model_position) != 3
            or any(isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value)
                   for value in model_position)):
        raise ValueError(
            f"{COLLISION_GEOMETRY_SRC} probe {record['id']} must have three finite numeric model_position values"
        )
    model_x_right, model_y_up, model_z_aft = model_position
    le_position = [model_z_aft, model_x_right, model_y_up]
    # This matches the existing physical wing_forward_shift convention: the wing stays fixed while every
    # fuselage-mounted item (including the tail, fin, canopy and belly witnesses) moves aft by DZ.
    if record["id"] in FUSELAGE_ATTACHED_CRASH_HULL_IDS:
        le_position[0] += DZ
    crash_hull_probes.append((record["id"], le_position))

GEAR_CONTACTS = (
    ("main_left", "left", "contact_main_left"),
    ("main_right", "right", "contact_main_right"),
    ("nose", "nose", "contact_nose"),
)
GEAR_PROFILE_ID = "sebart-avanti-s-a200-p100rx"


def model_vector3(value, label):
    if (not isinstance(value, list) or len(value) != 3
            or any(isinstance(part, bool) or not isinstance(part, (int, float)) or not math.isfinite(part)
                   for part in value)):
        raise ValueError(f"{COLLISION_GEOMETRY_SRC} {label} must be three finite model-space numbers")
    return [float(part) for part in value]


def derive_landing_gear():
    """Add source-mesh wheel paths as LE contact points, keeping contact mechanics estimated."""
    gear_source = collision_geometry.get("gear")
    if not isinstance(gear_source, dict):
        raise ValueError(f"{COLLISION_GEOMETRY_SRC} must contain a gear object; no fixed-gear fallback is allowed")
    if type(gear_source.get("version")) is not int or gear_source["version"] != 1:
        raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.version must be 1")
    retract_source = gear_source.get("retraction")
    if not isinstance(retract_source, dict):
        raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear must contain retraction samples")
    sample_records = retract_source.get("samples")
    if not isinstance(sample_records, list) or len(sample_records) < 2 or len(sample_records) > 513:
        raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.retraction.samples must contain 2..513 samples")
    expected_node_names = {
        "MainGear_L_Act_Cyl", "MainGear_L_Act_Piston", "MainGear_L_Pivot",
        "MainGear_R_Act_Cyl", "MainGear_R_Act_Piston", "MainGear_R_Pivot",
        "NoseGear_Act_Cyl", "NoseGear_Act_Piston", "NoseGear_Door_Act_ArmPivot",
        "NoseGear_Door_Act_Rod", "NoseGear_Door_Pivot", "NoseGear_Pivot",
    }
    extensions = []
    for index, sample in enumerate(sample_records):
        if not isinstance(sample, dict):
            raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.retraction.samples[{index}] must be an object")
        extension = sample.get("extension")
        if (isinstance(extension, bool) or not isinstance(extension, (int, float))
                or not math.isfinite(extension)):
            raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.retraction.samples[{index}].extension must be finite")
        expected = index / (len(sample_records) - 1)
        if abs(float(extension) - expected) > 1.0e-6:
            raise ValueError(f"{COLLISION_GEOMETRY_SRC} retraction extension samples must be uniform 0-up to 1-down")
        sample_nodes = sample.get("nodes")
        if not isinstance(sample_nodes, dict) or set(sample_nodes) != expected_node_names:
            raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.retraction.samples[{index}].nodes must contain the 12 exported GearRetract targets")
        for node_name, transform in sample_nodes.items():
            if not isinstance(transform, dict):
                raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.retraction.samples[{index}].nodes.{node_name} must be an object")
            model_vector3(transform.get("translation"), f"gear.retraction.samples[{index}].nodes.{node_name}.translation")
            rotation = transform.get("rotation_wxyz")
            if (not isinstance(rotation, list) or len(rotation) != 4
                    or any(isinstance(part, bool) or not isinstance(part, (int, float)) or not math.isfinite(part)
                           for part in rotation)):
                raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.retraction.samples[{index}].nodes.{node_name}.rotation_wxyz must be four finite numbers")
            rotation_norm = math.sqrt(sum(float(part) ** 2 for part in rotation))
            if abs(rotation_norm - 1.0) > 1.0e-4:
                raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.retraction.samples[{index}].nodes.{node_name}.rotation_wxyz must be normalized")
        extensions.append(float(extension))
    if abs(extensions[0]) > 1.0e-6 or abs(extensions[-1] - 1.0) > 1.0e-6:
        raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear retraction trajectory must run from extension 0 to 1")

    wheel_sources = gear_source.get("wheels")
    if not isinstance(wheel_sources, dict) or set(wheel_sources) != {"left", "right", "nose"}:
        raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.wheels must have exactly left, right and nose records")
    expected_ids = [item[2] for item in GEAR_CONTACTS]
    found_ids = [wheel_sources[item[1]].get("contact_id") for item in GEAR_CONTACTS
                 if isinstance(wheel_sources[item[1]], dict)]
    if found_ids != expected_ids:
        raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear wheel contact IDs/order must be {expected_ids!r}; found {found_ids!r}")

    contact_paths = {}
    radii = {}
    radius_source = f"{COLLISION_GEOMETRY_SRC} (SHA-256 {collision_geometry_hash}); source gear.wheels radius_m, a visual mesh bound, not a certified tyre dimension"
    path_source = (
        f"{COLLISION_GEOMETRY_SRC} (SHA-256 {collision_geometry_hash}); source gear.wheels contact_model trajectory "
        "[x_right,y_up,z_aft] mapped to the AV-02 LE frame [x_aft,y_right,z_up], including wing_forward_shift; "
        "visual mesh contact envelope, not a calibrated strut path"
    )
    for name, side, expected_id in GEAR_CONTACTS:
        wheel = wheel_sources[side]
        if not isinstance(wheel, dict):
            raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.wheels.{side} must be an object")
        required_wheel_refs = ("node", "spin_node", "compression_node") + (("steer_node",) if side == "nose" else ())
        for ref_name in required_wheel_refs:
            if not isinstance(wheel.get(ref_name), str) or not wheel[ref_name].strip():
                raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.wheels.{side}.{ref_name} must be a nonempty scene node reference")
        if not isinstance(wheel.get("contact_id"), str) or wheel["contact_id"] != expected_id:
            raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.wheels.{side}.contact_id must be {expected_id!r}")
        radius = wheel.get("radius_m")
        if (isinstance(radius, bool) or not isinstance(radius, (int, float)) or not math.isfinite(radius)
                or not 0.01 <= float(radius) <= 0.2):
            raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.wheels.{side}.radius_m must be a finite wheel radius in metres")
        centers = wheel.get("center_model")
        bottoms = wheel.get("contact_model")
        if not isinstance(centers, list) or not isinstance(bottoms, list):
            raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.wheels.{side} requires center_model and contact_model arrays")
        if len(centers) != len(sample_records) or len(bottoms) != len(sample_records):
            raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.wheels.{side} paths must align with retraction samples")
        path = []
        for index, (center_raw, bottom_raw) in enumerate(zip(centers, bottoms)):
            center = model_vector3(center_raw, f"gear.wheels.{side}.center_model[{index}]")
            bottom = model_vector3(bottom_raw, f"gear.wheels.{side}.contact_model[{index}]")
            expected_bottom = [center[0], center[1] - float(radius), center[2]]
            if max(abs(bottom[axis] - expected_bottom[axis]) for axis in range(3)) > 2.0e-5:
                raise ValueError(f"{COLLISION_GEOMETRY_SRC} gear.wheels.{side}.contact_model[{index}] is not center_model minus the wheel radius on model up")
            model_x_right, model_y_up, model_z_aft = bottom
            path.append([model_z_aft + DZ, model_x_right, model_y_up])
        contact_paths[name] = path
        radii[name] = float(radius)

    nose = contact_paths["nose"][-1]
    left = contact_paths["main_left"][-1]
    right = contact_paths["main_right"][-1]
    main_aft = (left[0] + right[0]) * 0.5
    wheelbase = main_aft - nose[0]
    if wheelbase <= 0.2 or not (nose[0] < cg[0] < main_aft):
        raise ValueError("source Blender gear-down endpoints do not bracket the AV-06 inventory CG in the LE frame")
    if not (left[1] < 0.0 < right[1]) or abs(left[1] + right[1]) > 0.01 or abs(nose[1]) > 0.02:
        raise ValueError("source Blender gear-down endpoints must form a centred left/right tricycle footprint")
    if max(abs(left[2] - right[2]), abs((left[2] + right[2]) * 0.5 - nose[2])) > 0.03:
        raise ValueError("source Blender gear-down wheel bottoms are not level within 30 mm")

    omega_dt = v("landing_gear.heave_omega_dt")
    zeta = v("landing_gear.damping_ratio")
    omega = omega_dt * PHYSICS_TICK_HZ
    total_k = mass * omega * omega
    nose_share = (main_aft - cg[0]) / wheelbase
    main_share = (cg[0] - nose[0]) / (2.0 * wheelbase)
    shares = {"nose": nose_share, "main_left": main_share, "main_right": main_share}
    if min(shares.values()) <= 0.0 or abs(sum(shares.values()) - 1.0) > 1.0e-9:
        raise ValueError(f"derived wheel reactions are not a positive tricycle load split: {shares}")

    gear_source_note = (
        f"AV09: Σk = inventory mass {mass:.6f} kg × ({omega_dt:.3f} × {PHYSICS_TICK_HZ} Hz)²; "
        f"split by static reaction shares from source-mesh wheelbase and inventory CG; damping ratio {zeta:.2f} "
        "uses the existing m/3 per-contact loader convention. Estimated numerical contact parameters, not measured struts."
    )
    contacts = []
    for name, _, contact_id in GEAR_CONTACTS:
        path = contact_paths[name]
        k_i = total_k * shares[name]
        c_i = 2.0 * zeta * math.sqrt(k_i * mass / 3.0)
        max_compression = qi(
            "landing_gear.nose_max_compression" if name == "nose" else "landing_gear.main_max_compression", "m"
        )
        max_steering = qi("landing_gear.nose_max_steering", "deg") if name == "nose" else q(
            0.0, "deg", "estimated", "main wheels are unsteered; nose steering uses the existing rudder-to-nosewheel mix"
        )
        contacts.append({
            "id": contact_id,
            "name": name,
            "position": q(path[-1], "m", "derived", path_source + "; down endpoint"),
            "stiffness": q(k_i, "N/m", "derived", gear_source_note),
            "damping": q(c_i, "N·s/m", "derived", gear_source_note),
            "max_compression": max_compression,
            "max_steering": max_steering,
            "retraction_path": q([coordinate for point in path for coordinate in point], "m", "derived", path_source),
        })

    # The compact drag line is the equal geometric centroid of the three exposed wheel-bottom locations.
    drag_center = [sum(contact_paths[name][-1][axis] for name, _, _ in GEAR_CONTACTS) / 3.0 for axis in range(3)]
    contact_area = q(v("landing_gear.drag_area"), "m²", *src("landing_gear.drag_area"))
    contact_center = q(
        drag_center, "m", "derived",
        path_source + "; centroid of the three full-down wheel-bottom points, an estimated drag moment arm rather than a measured drag centre",
    )
    result = {
        "description": (
            "Retractable tricycle contact geometry follows the user-supplied Blender GearRetract visual animation. "
            "Wheel-bottom trajectories and radii are mesh-derived presentation witnesses; contact stiffness, damping, "
            "travel limits, rolling/friction parameters, actuator times and incremental drag are estimates, not measured "
            "physical strut or aircraft performance data. Optional main-wheel brakes are assumed installed. Nose steering "
            "uses the existing rudder-to-nosewheel mix; the SebArt manual specifies a separate steering servo."
        ),
        "contacts": contacts,
        "rolling_resistance": qi("landing_gear.rolling_resistance", "1"),
        "side_friction": qi("landing_gear.side_friction", "1"),
        "peak_slip_angle": qi("landing_gear.peak_slip_angle", "deg"),
        "breakaway_factor": qi("landing_gear.breakaway_factor", "1"),
        "retraction": {
            "extension_time": qi("landing_gear.extension_time", "s"),
            "retraction_time": qi("landing_gear.retraction_time", "s"),
            "drag_area": contact_area,
            "drag_center": contact_center,
        },
    }

    # This is a source registry, not generated data. Fail closed if the profile no longer follows the source mesh and inputs.
    profiles = wheel_profile_registry.get("profiles", {})
    profile = profiles.get(GEAR_PROFILE_ID) if isinstance(profiles, dict) else None
    if not isinstance(profile, dict) or set(profile.get("contacts", {})) != {name for name, _, _ in GEAR_CONTACTS}:
        raise ValueError(f"{WHEEL_PROFILES.relative_to(ROOT)} must contain the three-contact profile {GEAR_PROFILE_ID!r}")
    for name, side, _ in GEAR_CONTACTS:
        wheel = profile["contacts"][name]
        expected_inertia = round(0.5 * v(
            "landing_gear.nose_wheel_mass" if name == "nose" else "landing_gear.main_wheel_mass"
        ) * radii[name] ** 2, 9)
        radius_node = wheel.get("wheel_radius", {})
        inertia_node = wheel.get("wheel_inertia", {})
        spin_node = wheel.get("spin_relaxation", {})
        brake_node = wheel.get("brake_torque", {})
        expected_brake = 0.0 if name == "nose" else v("landing_gear.main_brake_torque")
        expected_availability = "none" if name == "nose" else "available"
        if (abs(float(radius_node.get("value", -1.0)) - round(radii[name], 6)) > 1.0e-9
                or abs(float(inertia_node.get("value", -1.0)) - expected_inertia) > 5.0e-10
                or abs(float(spin_node.get("value", -1.0)) - v("landing_gear.wheel_spin_relaxation")) > 1.0e-9
                or abs(float(brake_node.get("value", -1.0)) - expected_brake) > 1.0e-9
                or wheel.get("brake_availability") != expected_availability):
            raise ValueError(f"{WHEEL_PROFILES.relative_to(ROOT)} profile {GEAR_PROFILE_ID}.{name} is stale against source geometry/inputs")

    geometry = {"wheelbase_m": wheelbase, "load_shares": shares, "total_stiffness_N_m": total_k,
                "heave_omega_rad_s": omega, "static_sag_m": mass * G0 / total_k,
                "drag_center_le_m": drag_center, "sample_count": len(sample_records), "radii_m": radii}
    return result, geometry


landing_gear, landing_gear_report = derive_landing_gear()
data = {
    "format": "openrc-aircraft v1",
    "physical_identity_version": 1,
    "id": "sebart-avanti-s-a200-p100rx",
    "description": (
        f"Vantage Jet, based on the SebArt Avanti S Jet 2.2m ARF (A200, {b:.2f} m span) with a JetCat P100-RX turbine. "
        f"EXPERIMENTAL first physics estimate (AV-06), generated by {SCRIPT}; not flight-identified. Physical mass, "
        "aerodynamic, inertia and thrust-line estimates retain the AV-02 geometry.json physical surrogate. The visual "
        "aircraft and gear-up collision witnesses use the imported Blender geometry; wheel positions and radii are "
        "source-mesh-derived, while gear contact mechanics and actuator/drag values are provisional estimates. Optional "
        "main-wheel brakes are assumed installed; this is not a calibrated physical gear or turbine installation. "
        "AV-09 models hinged trailing-edge flaps; gear is retractable_tricycle."
    ),
    "frames": {
        "le_frame": "positions in metres from the root wing leading edge beside the fuselage (model z 0) on the root wing mid-plane (model y 0): [x_aft, y_right, z_up]",
        "body": "simulation body axes FRD about the CG: x forward = -x_aft, y right, z down = -z_up",
    },
    "reference": {
        "wing_area": q(S, "m2", "derived", D("polyline planform through the fuselage" + (f", chords scaled x{chord_scale:.4f} to the published area" if target else " from " + GEO_SRC))),
        "wing_span": qi("airframe.span", "m"),
        "mean_chord": q(c_ref_output, "m", c_ref_output_kind, f"{c_ref_output_source} Geometric MAC is {mac:.4f} m; coefficient reference length only."),
        "root_chord": q(cr_eq, "m", "derived", D(f"equivalent trapezoid (same area and spanwise centroid as the polyline planform); geometric root {cr_geo:.3f} m")),
        "tip_chord": q(ct_eq, "m", "derived", D(f"equivalent trapezoid; geometric tip {ct_geo:.3f} m")),
        "aero_reference_point": q(le(x_arp, 0.0), "m", "derived", D("wing-body aerodynamic centre: 25 % MAC moved forward by the Munk-Multhopp fuselage moment; on the root wing plane")),
        "planform": "tapered",
    },
    "start": {"level_speed": qi("start.level_speed", "m/s")},
    "balance": {
        "plan_cg": q(dry_cg, "m", src("airframe.cg_aft_of_root_le")[0], f"{cg_z * 1000:.0f} mm aft of the root LE ({src('airframe.cg_aft_of_root_le')[1]}); z from the empty-main-tank inventory (derived)"),
        "firewall": q(le(engine_c[2] - 0.12, engine_c[1]), "m", "estimated", "turbine mount ring: front of the P100-RX (241 mm long) centred at the geometry's engine_center"),
        "configuration": "virtual-balanced-reference-v2-empty-main-tank",
        "cg_tolerance": q(0.001, "m", "estimated", D("virtual reference build balanced to the manual's point with the main tank empty, NOT a measured airplane")),
        "fuel_state": "empty_tanks",
    },
    "fuel_system": {"tanks": [{
        "id": "main_tank", "fuel": KEROSENE_BLEND, "liquid_inventory_id": "fuel_flight", "shell_inventory_id": "fuel_tank",
        "capacity": qi("fuel.tank_l", "l"),
        "unusable": q(0.02, "l", "estimated", "FUEL-05e: felt-clunk main-tank residue estimate; the hopper/UAT stays inside the turbine accessories item; no published value"),
        "pickup": "felt_clunk", "feed": "ecu_pump"}]},
    "inventory": [
        dict({"id": it[8], "name": it[0], "mass": q(float(it[1]), "kg", it[2], it[3]), "position": q([float(x) for x in it[4]], "m", it[6], it[7])},
             **({"size": q([float(x) for x in it[5]], "m", "estimated", "rough envelope for intrinsic inertia")} if it[5] else {}),
             **({"energy_source": ENERGY_SOURCES[it[0]]} if it[0] in ENERGY_SOURCES else {}))
        for it in items
    ],
    "crash_hull": q(
        [point for _, point in crash_hull_probes], "m", "derived",
        f"13 gear-up collision witnesses from the imported Blender visual model in {COLLISION_GEOMETRY_SRC} "
        f"(SHA-256 {collision_geometry_hash}); source model_position [x_right, y_up, z_aft] mapped to the "
        "physical LE frame [x_aft, y_right, z_up]. Wing witnesses remain fixed and fuselage-attached witnesses "
        "include wing_forward_shift. This visual witness source does not replace the AV-02 physical geometry "
        "surrogate or calibrate installation. These probes represent the source Blender gear-up/stowed terminal hull; "
        "separate retractable landing-gear contacts follow the visual wheel-bottom paths while deployed."
    ),
    "crash_hull_ids": [identity for identity, _ in crash_hull_probes],
    # CR-01d: one semantic name per crash_hull point above, in the same order (crash presentation only).
    "crash_hull_components": ["left_wing_tip", "right_wing_tip", "left_wing_tip", "right_wing_tip", "nose", "tail_end", "belly", "belly", "belly", "left_stab_tip", "right_stab_tip", "fin_top", "canopy"],
    "plausibility": {
        "mass_range": qi("airframe.mass_range", "kg"),
        "inertia_reference": stik["plausibility"]["inertia_reference"],
    },
    "controls": {
        "surface_ids": {"aileron_left": "surface_aileron_left", "aileron_right": "surface_aileron_right", "elevator": "surface_elevator", "rudder": "surface_rudder"},
        "max_throw": {
            "aileron": qi("controls.aileron_up", "deg"),
            "aileron_down": qi("controls.aileron_down", "deg"),
            "elevator": qi("controls.elevator", "deg"),
            "rudder": qi("controls.rudder", "deg"),
        },
        "servo_full_throw_time": qi("controls.servo_full_throw_time", "s"),
        # D6e: the manual's normal-flight dual rates and expo, applied by the session to the keyboard sticks as a
        # radio would (controls.rates.normal); the throws above stay the mechanical maxima.
        "rates": {
            "normal": {
                "aileron": qi("controls.rates_normal_aileron", "1"),
                "elevator": qi("controls.rates_normal_elevator", "1"),
                "rudder": qi("controls.rates_normal_rudder", "1"),
                "aileron_expo": qi("controls.rates_normal_aileron_expo", "1"),
                "elevator_expo": qi("controls.rates_normal_elevator_expo", "1"),
                "rudder_expo": qi("controls.rates_normal_rudder_expo", "1"),
            },
        },
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
            "wing_aileron_effectiveness": q(wing_ail_eff, "1", "derived", D("D11-R1: research/aero/aileron_effectiveness.py; Clda_right matched through the calibrated section slope and induced-flow map (six equal-area strips); model consistency, not flight calibration")),
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
                # E0a2c: the loader derives the free tail law from this (free slope CLa_h eta, physical elevator tau,
                # downwash as the lagged wing lift); without it the local tail would use the downwashed slope for pitch
                # rate and the inflated tau for its stall (docs/research/flight-dynamics/elevator-repair-2026-10-13.md).
                "downwash_gradient": q(deps, "1", "derived", D("d(eps)/d(alpha) at the tail: DATCOM 4.44 [K_A K_lambda K_H sqrt(cos sweep)]^1.19, the same value folded into lift_slope, control_effectiveness and incidence")),
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
        "id": "propulsion_main",
        "kind": "turbine",
        "description": "JetCat P100-RX (2017 catalog, non-BL) in a fixed thrust tube: ECU throttle map, acceleration/deceleration-limited spool with a governor lag, bench thrust at STP x installed factor, momentum ram drag and inlet normal force at the intakes (physics/turbine.gd, docs/research/avanti-s-av05-turbine-dynamics.md).",
        "engine": {
            "name": "JetCat P100-RX (catalog 2017, 44 000-154 000 rpm, 2-100 N)",
            "spool_integrator": IN["turbine"]["spool_integrator"],
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

legacy_data = data
data = upgrade(legacy_data)
# FUEL-08: finite turbine consumption uses the existing JetCat fuel-flow table and the
# declared 3.2 l main tank only. The hopper/UAT remains represented by dry accessory
# hardware; its separate liquid volume and main-to-hopper transfer are not quantified.
data["capabilities"]["energy"] = "finite_liquid_fuel"
data["propulsion"]["fuel_consumption"] = {
    "law": "turbine_map_v1",
    "tank_id": "main_tank",
}
data["controls"]["keyboard"] = {
    "pitch_press_time": qi("controls.keyboard_pitch_press_time", "s"),
    "pitch_release_time": qi("controls.keyboard_pitch_release_time", "s"),
}
data["controls"]["gamepad"] = {
    "pitch_scale": qi("controls.gamepad_pitch_scale", "1"),
    "yaw_scale": qi("controls.gamepad_yaw_scale", "1"),
    "yaw_response_time": qi("controls.gamepad_yaw_response_time", "s"),
}
parity = numeric_parity(legacy_data, data)
# AV-17-R2: explicit finite-wing proxy, preserving the attached calibration and historical migration.
data["aero"]["wing_polar"] = build_polar(data)
# AS-02's ID-gated policy intentionally records the historical AV-06 gear-up state. AV-09 adds the new gear module after
# that compatibility migration so the legacy record remains evidence of its original locked-up configuration.
data["capabilities"]["gear"] = "retractable_tricycle"
data["landing_gear"] = landing_gear
data["capabilities"]["flaps"] = "simulated"
if (abs(float(v("flaps.inner_span_m")) - float(g["wing"]["flap_span"][0])) > 1e-9
		or abs(float(v("flaps.outer_span_m")) - float(g["wing"]["flap_span"][1])) > 1e-9
		or abs(float(v("flaps.hinge_fraction")) - float(g["wing"]["hinge_fraction"])) > 1e-9):
	raise ValueError("flap span and hinge inputs must match the AV-02 source geometry")
flap_gain_quantity = qi("flaps.aerodynamic_gain", "1")
if CLI_ARGS and CLI_ARGS.flap_aero_disabled:
	flap_gain_quantity = q(0.0, "1", "derived",
		"AV-09 software sensitivity variant: suppresses flap aerodynamic lift/drag/pitch/wake while preserving the same actuator and recorded commands; not an aircraft calibration")
data["flaps"] = {
	"max_angle_deg": qi("flaps.max_angle_deg", "deg"),
	"takeoff_angle_deg": qi("flaps.takeoff_angle_deg", "deg"),
	"inner_span_m": qi("flaps.inner_span_m", "m"),
	"outer_span_m": qi("flaps.outer_span_m", "m"),
	"hinge_fraction": qi("flaps.hinge_fraction", "1"),
	"extension_time": qi("flaps.extension_time", "s"),
	"retraction_time": qi("flaps.retraction_time", "s"),
	"max_speed_mps": qi("flaps.max_speed_mps", "m/s"),
	"elevator_mix_per_flap_fraction": qi("flaps.elevator_mix_per_flap_fraction", "1"),
	"effective_angle_limit_deg": qi("flaps.effective_angle_limit_deg", "deg"),
	"profile_drag_coefficient": qi("flaps.profile_drag_coefficient", "1"),
	"aerodynamic_gain": flap_gain_quantity,
}
data["description"] = str(data.get("description", "")).rstrip() + " Hinged trailing-edge flaps use an AV-09 estimated strip-incidence/drag law with manual 20/50-degree settings."
validate_physical_identity(data)
text = (json.dumps(data, indent=2, ensure_ascii=False) + "\n").replace("\n", "\r\n")
rows = ["| Section | Quantity | Value | How |", "| --- | --- | --- | --- |"]
for sec, name, val, how in log:
    vv = ", ".join(f"{x:.4g}" for x in val) if isinstance(val, list) else f"{val:.4g}"
    rows.append(f"| {sec} | {name} | {vv} | {how} |")
coef_rows = ["| Coefficient | Value | Kind |", "| --- | --- | --- |"] + [f"| {k} | {x['value']:.5g} | {x['kind']} |" for k, x in data["aero"]["coefficients"].items()]
eng_rows = ["| rpm | bench thrust (N) | installed static (N) | net at start speed (N) | air flow (kg/s) |", "| --- | --- | --- | --- | --- |"] + [
    f"| {r[0]:.0f} | {r[1]:.1f} | {k_inst * r[1]:.1f} | {thrust_at(V_start, r[0]):.1f} | {tab(mflow_rows, r[0]):.3f} |" for r in thrust_rows if r[0] >= n_idle]
gear_contact_rows = [
    f"| {contact['name']} | {', '.join(f'{x:.6f}' for x in contact['position']['value'])} | "
    f"{contact['stiffness']['value']:.2f} | {contact['damping']['value']:.2f} | "
    f"{contact['max_compression']['value']:.3f} | {landing_gear_report['radii_m'][contact['name']]:.6f} |"
    for contact in landing_gear["contacts"]
]
gear_radii_text = ", ".join(f"{name} {radius:.6f} m" for name, radius in landing_gear_report["radii_m"].items())
gear_shares_text = ", ".join(f"{name} {share:.1%}" for name, share in landing_gear_report["load_shares"].items())
report = f"""# AV-06: Vantage Jet with JetCat P100-RX, physics derivation

Source aircraft: SebArt Avanti S (A200).

Generated by `{SCRIPT}` from physical surrogate `{GEOMETRY.relative_to(ROOT).as_posix()}`, source-model visual and landing-gear
geometry `{COLLISION_GEOMETRY_SRC}` (SHA-256 `{collision_geometry_hash}`), wheel profile registry
`{WHEEL_PROFILES.relative_to(ROOT).as_posix()}` (SHA-256 `{wheel_profile_hash}`), `inputs.json`, and shared conventions; do not
edit (regenerate). Output: `{OUT.relative_to(ROOT).as_posix()}`. **Experimental**: textbook mass/aero/inertia/thrust estimates
continue to use the AV-02 physical surrogate and sourced kit/engine data, not flight identification. The imported Blender
model supplies visual geometry, 13 gear-up collision witnesses and gear-contact trajectories; its turbine installation is
not calibrated, and the visual mesh does not calibrate physical spring/damper behavior. `--check` recomputes the sidecar and
wheel-profile hashes and rejects stale generated output/report, stale registry values or a missing/invalid geometry source.

The v1 baseline is upgraded to `openrc-aircraft v2` by the ID-gated standardizer, then the AV-09 gear module is added while
preserving the historical AS-02 migration policy. Migration numeric parity: {parity['preserved_numeric_leaves']} original leaves
preserved, {parity['relocated_cladot_numeric_leaves']} relocated CLadot leaves, {parity['added_numeric_leaves']} explicit
compatibility-default leaves added, {parity['numeric_differences']} differences.

Fuel uses the finite `turbine_map_v1` flow table bound to the documented 3.2 l main tank. This is a single-main-tank adapter;
the hopper/UAT remains dry accessory hardware because its independent liquid capacity and transfer path are not quantified.
No hopper volume or transfer behavior is invented, and this simplified installation does not establish hopper starvation fidelity.

Flight mass {mass:.3f} kg (fuel {fuel_kg:.2f} kg), CG {cg[0] * 1000:.0f} mm aft of the root LE = {100 * (cg[0] - mac_le) / mac:.1f} % MAC, static margin {sm:.1f} % MAC; the manual's {cg_z * 1000:.0f} mm point is taken with a full hopper and an empty main tank (FUEL-05e).
Inventory inertia `[Jxx, Jyy, Jzz, Jxy, Jxz, Jyz]` = {", ".join(f"{x:.6g}" for x in J)} kg·m²; principal moments = {", ".join(f"{x:.6g}" for x in I_principal)} kg·m².
1-g stall {Vs:.1f} m/s clean, start {V_start:.0f} m/s, maximum level speed {V_max:.1f} m/s ({V_max * 3.6:.0f} km/h).
Throws (manual high rate): aileron {v('controls.aileron_up')}° up / {v('controls.aileron_down')}° down, elevator ±{v('controls.elevator')}°, rudder ±{v('controls.rudder')}°.

## Intermediate quantities

{chr(10).join(rows)}

## CD0 model basis

The clean-airframe coefficient is an estimate, not an Avanti flight measurement matched to local Reynolds number or Mach number. The build-up evaluates skin friction at the 29 m/s start-speed condition (about Mach 0.09), assumes laminar fractions of 0.15 on wing/tails and 0.05 on the fuselage, retains the fixed wing-form-factor Mach multiplier evaluated at M=0.34, uses a tail form factor of 1.12, adds the listed intake/canopy item drag areas, and multiplies the sum by the 1.15 excrescence estimate. These assumptions yield the reported CD0; they are kept visible so the value is not read as a matched-condition measurement.

## Coefficients written (c_ref = S/b; moments about the ARP = wing-body ac)

{chr(10).join(coef_rows)}

## Keyboard pitch response

AV-17-R1 adds an optional input-layer response: keyboard normal-profile pitch takes
{v('controls.keyboard_pitch_press_time'):.2f} s from neutral to full virtual stick; release takes
{v('controls.keyboard_pitch_release_time'):.2f} s from full stick to neutral. Opposite input recenters first.
The manual's normal rates/expo, physical surface travel and servo rate still apply afterward. These are estimated
device settings, not manufacturer actuator measurements. Radios, gamepads, scripted accepted commands and the explicit
full-rate profile bypass this keyboard filter. No aerodynamic, mass, CG, inertia or turbine quantity changes.

## Gamepad pitch and post-stall proxy

AV-17-R2 adds a fixed normal-gamepad pitch scale of {v('controls.gamepad_pitch_scale'):.2f}, applied after normal
rates and before trim: ±{v('controls.elevator') * 0.5 * v('controls.gamepad_pitch_scale'):.1f}° before trim for a short
gamepad stick. Full profile, physical radios and the keyboard retain their travel. This is simulator device tuning,
not a SebArt setting or an airspeed/AoA limiter.

`research/avanti-s/av17-r2/build_polar.py` derives the optional finite-wing strip polar from the tracked Sandia NACA 0015
Table 3 proxy (hybrid computed/experimental, Re 1e6). It preserves the attached finite-wing line and CD0, scales lift
and angle using the existing slope and nominal CLmax allocation, and joins the existing CD90 plate law at high angles.
Its separation fraction is an estimated Kirchhoff-style inverse, not measured Avanti separation. The exact A200 section,
polar and stall speed remain unidentified. The nominal 1-g speed above is a CLmax-based estimate; loaded, trimmed whole-aircraft
stall behavior also depends on the tail, twist and moments. See `docs/research/avanti-realism/AV-17-R2/README.md` for
source applicability, reproduction, measured simulated departures and numerical verification.

AV-17-R3 keeps the accepted pitch policy and adds fixed gamepad yaw travel {v('controls.gamepad_yaw_scale'):.2f}
(±{v('controls.rudder') * v('controls.rates_normal_rudder') * v('controls.gamepad_yaw_scale'):.1f}° before trim) and a
{v('controls.gamepad_yaw_response_time'):.2f} s first-order input time constant. This response is stored in the existing
command state and bypassed by full/radio/keyboard modes; it is not a physical servo time or feedback damper.
The same normal yaw command feeds nosewheel steering. See `docs/research/avanti-realism/AV-17-R3/README.md`.

The lateral build-up obtains Cnp/Cnr about CG ({Cnp_cg:.6f}, {Cnr_cg:.6f}). AV-17-R3 writes their ARP values
({Cnp:.6f}, {Cnr:.6f}) by subtracting CYp/CYr times the ARP's forward CG arm / span, so the runtime's
ARP-to-CG force-moment transfer applies exactly once. Static yaw stability, the fin, and its local flow law are unchanged.
Evidence: `docs/research/avanti-realism/AV-17-R1/README.md`.

## Turbine at sea level

{chr(10).join(eng_rows)}

## Landing gear and ground model

The imported Blender `GearRetract` source supplies {landing_gear_report['sample_count']} uniformly spaced wheel-bottom
samples from 0 (stowed/up) to 1 (deployed/down), plus mesh-derived tyre radii ({gear_radii_text}). These are visual geometry
measurements, not a physical strut survey. Contact paths are converted from model `[right, up, aft]` to the physics LE frame
`[aft, right, up]`; the existing `wing_forward_shift` is applied to the fuselage-mounted gear. Full-down wheelbase is
{landing_gear_report['wheelbase_m']:.3f} m and the static wheel reactions derived from the AV-06 inventory CG are
{gear_shares_text}. The displayed contact endpoints use wheel-bottom positions; the wheel-center trajectories remain a
separate source sidecar measurement.

| Contact | Full-down LE position [aft, right, up] (m) | Stiffness (N/m) | Damping (N·s/m) | Terminal compression (m) | Mesh radius (m) |
| --- | --- | ---: | ---: | ---: | ---: |
{chr(10).join(gear_contact_rows)}

Total stiffness {landing_gear_report['total_stiffness_N_m']:.1f} N/m gives heave frequency {landing_gear_report['heave_omega_rad_s']:.2f}
rad/s ({landing_gear_report['heave_omega_rad_s'] / (2 * math.pi):.2f} Hz) and {landing_gear_report['static_sag_m'] * 1000:.1f} mm static sag.
The generator distributes that stiffness by the derived static load shares; damping uses ζ={v('landing_gear.damping_ratio'):.2f}
and the existing equal m/3 contact-mass convention. The {v('landing_gear.main_max_compression') * 1000:.0f} mm main and {v('landing_gear.nose_max_compression') * 1000:.0f} mm nose terminal limits are equivalent-compliance
thresholds from the GP-06c reserve-energy drop (former 14 CFR 23.727), not measured strut travel. Smooth-runway rolling resistance, side friction and
slip-angle regularization remain provisional. Extension and retraction are each {v('landing_gear.extension_time'):.1f} s estimates;
the gear-down incremental drag area is {v('landing_gear.drag_area'):.3f} m² and its estimated moment center is
`[{', '.join(f'{x:.4f}' for x in landing_gear_report['drag_center_le_m'])}]` m in the LE frame.

SebArt's Avanti S assembly manual lists pneumatic gear and a steering-wheel servo; optional pneumatic wheel brakes are listed
as separate equipment. The simulation assumes optional brakes on both main wheels at the provisional 1.0 N·m per-wheel value;
the manual gives no brake torque or actuator cycle time. It routes the existing rudder-to-nosewheel mix to steering rather
than modeling a separate steering-servo channel.

## Flaps (AV-09)

The SebArt manual (intro PDF, p.4) specifies 0° for normal flight, 20° for start and 50° for landing. AV-02's estimated
visual hinge and span stations define six-strip coverage. The plain-flap thin-airfoil effectiveness is
`tau = 1 - (theta_h - sin(theta_h))/pi`, `theta_h = acos(1 - 2*x_h/c)`; the resulting ideal incidence is smoothly
saturated at the authored {v('flaps.effective_angle_limit_deg'):.0f}° estimate before the area coverage is applied. The local
finite-wing polar blends attached lift into its measured-proxy stall law; a bounded flap lift increment follows the
separated fraction, and its induced-drag cost is evaluated from the resulting CL. The estimated profile/hinge drag is
`CD_profile = {v('flaps.profile_drag_coefficient'):.2f} * flap_coverage * aerodynamic_gain * sin(delta)^2 * max(cos(alpha), 0)`;
coverage here is the covered fraction of each wing strip's planform reference area, not the flap panel's wetted area.
Lift increment produces the Glauert thin-airfoil quarter-chord couple
`dCm/dCL = 0.25*(sin(2*theta_h) - 2*sin(theta_h))/(2*pi*tau)`; it is applied to actual bounded strip ΔCL instead of
moving the whole wing lift to the aft flap panel. Only the estimated profile drag uses the flap-panel-centre lever.
Strip ΔCL also changes the horizontal-tail downwash, so the net aircraft pitch response emerges from the coupled wing
and tail loads and is not fixed to the section-couple sign. This is an estimated plain-flap model, not a measured Avanti
section polar or flight-identified pitch curve. Full
extension and retraction each take {v('flaps.extension_time'):.1f} s as an estimated effective slowed installed actuator
system; the manual publishes no transit time. The {v('flaps.max_speed_mps'):.0f} m/s value is an estimated equivalent-airspeed
advisory at reference density, not a certified limit and not a simulation clamp. The manual's 8%/20% down-elevator mixes
are represented by the separate normalized pilot mix, linear in accepted flap fraction; it uses {v('flaps.elevator_mix_per_flap_fraction'):.0%}
of full elevator travel at maximum flap and derives {v('flaps.takeoff_angle_deg') / v('flaps.max_angle_deg') * v('flaps.elevator_mix_per_flap_fraction'):.0%}
at the start setting. This manual mix is not a hidden aerodynamic trim correction.

The section basis is the Glauert extension of thin-airfoil theory summarized in [NACA RM L8D09](https://ntrs.nasa.gov/api/citations/20050080791/downloads/20050080791.pdf), pp. 4–7. The moment/lift ratio is also consistent with the thin-airfoil quarter-chord plain-flap result in [NACA Report 938](https://ntrs.nasa.gov/api/citations/19930092003/downloads/19930092003.pdf), p. 8; [NACA RM A51D02](https://ntrs.nasa.gov/api/citations/19930086603/downloads/19930086603.pdf), appendix B, reports a 0.40c incremental lift centre for a 0.30c flap. These are theory/other-airfoil references, not measurements of the Avanti's section. The `aerodynamic_gain=0` generated control retains configuration and actuator but disables flap aerodynamic effects for same-input software sensitivity comparisons; it is not a candidate aircraft calibration.

## Known simplifications

- Physical mass, aerodynamic, inertia and thrust-line estimates continue to use the AV-02 geometry.json physical surrogate
  (estimated sections); see the inputs' scale factors and sources. The imported Blender model provides the new visual shape,
  gear-up collision probes and source-mesh wheel geometry, but does not calibrate aircraft mass, aero, turbine installation,
  strut compliance, wheel inertia or braking torque.
- The AV-09 flap law uses the visual-blockout hinge/span, bounded plain-flap section approximation and manual-derived
  elevator mix; section lift/drag, hinge moments and transit timing are not measured for this aircraft. Gear paths and wheel radii follow
  imported visual geometry; spring/damper behavior, rolling friction, steering limit, brake torque, actuator time and
  incremental gear drag remain estimates pending aircraft-specific physical data.
- The finite turbine-flow adapter consumes the declared main-tank store only. Hopper/UAT liquid quantity and transfer remain
  unresolved; the session does not model ECU ignition/autostart, a measured hot-cut spool-down transient, restart behavior
  or flameout dynamics.
- Fuselage directional destabilization omitted (v1 contract: Cnb equals the fin term), as for every aircraft.
- The induced-flow strip map calibrates section slope and offsets so integrated wing-plus-horizontal-tail lift slope and
  zero-alpha lift reproduce aircraft-level CLa and CL0. This is a consistency calibration, not independent section data;
  Clp and detailed spanwise attached/post-stall loading remain model predictions at the current strip resolution.
- CL-dependent cross terms (Clb sweep part, Clr, Cnp, adverse yaw) are frozen at CL_ref = {CL_ref:.2f}.
"""

if __name__ != "__main__":
    pass  # imported by sensitivity.py: compute only
elif "--check" in sys.argv:
    stale = []
    if not OUT.exists() or OUT.read_bytes() != text.encode("utf-8"):
        stale.append(OUT)
    if not REPORT.exists() or REPORT.read_text() != report:
        stale.append(REPORT)
    if stale:
        sys.exit("stale: " + ", ".join(str(p.relative_to(ROOT)) for p in stale) + f" (run {SCRIPT})")
    print("sebart_avanti_s_a200.json and derivation.md are up to date")
else:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(text.encode("utf-8"))
    REPORT.write_text(report)
    print(f"wrote {OUT.relative_to(ROOT)} and {REPORT.relative_to(ROOT)}")
    print(f"mass {mass:.3f} kg, SM {sm:.1f} % MAC, stall {Vs:.1f} m/s, start {V_start:.0f} m/s, Vmax {V_max:.1f} m/s, J {[round(x, 3) for x in J]}")
