#!/usr/bin/env python3
"""Wing-loss feasibility study (Pure Physicist, 2026-10-27). Read-only on the repository.

Inputs: the generated aircraft JSON (openrc-aircraft v2) and the part-throttle probe CSV produced by
research/flight-dynamics/power-climb/part_throttle_probe.gd on a disposable app copy (EM-31) (full-throttle thrust and shaft
power of each aircraft's own propulsion law, calm ISA sea level).

Everything else is an explicit, labelled estimate (CONFIG below). SI units; body axes FRD; le frame [x_aft, y_right, z_up].
Convention for damage: the LEFT side is damaged; the mirror case (right side damaged) differs only in the sign of the
propeller torque reaction (clockwise-from-behind tractor props roll the airframe LEFT).

Outputs: tables printed as Markdown (stdout) and results.json beside this script.
"""
import csv
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
G = 9.80665
RHO = 1.225

# ---------------------------------------------------------------------------------------------------------------------
# Per-aircraft estimates that the JSON does not carry. Every value here is an ESTIMATE unless marked "data".
#   wing: inventory ids of wing structure; 'both' = one symmetric box to split; 'left'/'right' = per-panel items
#   root: fuselage half-width at the wing root (m) [inventory fuselage box widths]
#   ail: aileron span as fractions of the semispan [inner, outer], local tau (thin-airfoil x gap factor), max throw deg
#   flap: same for flaps (None if absent or not usable); flaps are simulated only on P-51, Avanti, F4U
#   side_items: per-side inventory ids that leave with that wing panel if outboard of the cut
#   s_side: fuselage projected side area (m2); k_lin: slender-body side-force slope per side area (1/rad)
#   beta_ft05: knife-edge sideslip the current model holds at full rudder (FT-05 summary), deg
#   ft05_ke: FT-05 knife-edge vertical speed (m/s, full rudder + full throttle) of the INTACT model
#   rot: +1 clockwise-from-behind tractor (torque reaction rolls left), 0 turbine (negligible), None unknown
# ---------------------------------------------------------------------------------------------------------------------
CONFIG = {
    "stik": dict(file="jensen_ugly_stik_60", probe="jensen-das-ugly-stik-60", label="Ugly Stik (legacy .61)",
                 wing={"item_wing_airframe": "both"}, root=0.05, ail=(0.07, 1.0, 0.215, None), flap=None,
                 side_items=[], s_side=0.081, k_lin=0.40, beta_ft05=20.7, ft05_ke=-11.8, rot=1, dihedral_deg=0.0),
    "stik61": dict(file="stik_glow_61fx_2t", probe="stik-glow-61fx-2t", label="Stik MAX-61FX (glow)",
                   wing={"item_wing_airframe": "both"}, root=0.05, ail=(0.07, 1.0, 0.215, None), flap=None,
                   side_items=[], s_side=0.081, k_lin=0.40, beta_ft05=20.7, ft05_ke=-1.4, rot=1, dihedral_deg=0.0),
    "extra": dict(file="gp_extra_300s_60", probe="gp-extra-300s-60", label="Extra 300S .60 (61FX)",
                  wing={"wing_main": "both"}, root=0.076, ail=(0.10, 0.98, 0.436, None), flap=None,
                  side_items=[], s_side=0.172, k_lin=0.346, beta_ft05=20.8, ft05_ke=-13.6, rot=1, dihedral_deg=0.0),
    "p51": dict(file="p51d_mustang_120", probe="p51d-mustang-120", label="P-51D 1/4 (120 cc)",
                wing={"wing_left": "left", "wing_right": "right"}, root=0.13, ail=(0.60, 0.97, 0.43, None),
                flap=(0.10, 0.58, 0.56, 14.3),
                side_items=["servo_aileron_left", "servo_flap_left", "gear_main_left"],
                s_side=0.50, k_lin=0.374, beta_ft05=21.9, ft05_ke=-21.0, rot=1, dihedral_deg=5.0),
    "avanti": dict(file="sebart_avanti_s_a200", probe="sebart-avanti-s-a200-p100rx", label="Ventage/Avanti S jet",
                   wing={"wing_left": "left", "wing_right": "right"}, root=0.16, ail=(0.55, 0.95, 0.536, None),
                   flap=(0.17, 0.52, 0.55, 14.0),
                   side_items=["servo_aileron_left", "servo_flap_left", "gear_main_left"],
                   s_side=0.36, k_lin=0.380, beta_ft05=15.3, ft05_ke=-5.9, rot=0, dihedral_deg=1.3),
    "timber": dict(file="turbo_lumber_evolution", probe="turbo-lumber-evolution", label="Timber (4S electric)",
                   wing={"wing_main": "both"}, root=0.06, ail=(0.45, 0.97, 0.45, None), flap=None,
                   side_items=[], s_side=0.10, k_lin=0.35, beta_ft05=16.9, ft05_ke=-24.8, rot=1, dihedral_deg=2.0),
    "x8": dict(file="moonrunner_x99", probe="skywalker-x8", label="Skywalker X8 (flying wing)",
               wing={"wing_left": "left", "wing_right": "right"}, root=0.235, ail=(0.33, 0.90, 0.45, None), flap=None,
               side_items=["servo_elevon_left"], s_side=0.063, k_lin=0.40, beta_ft05=None, ft05_ke=None, rot=None,
               dihedral_deg=0.0),
    "f4u": dict(file="f4u_corsair_250", probe="f4u-corsair-250", label="F4U-1D 1:4.5 (250 cc)",
                wing={"wing_left": "left", "wing_right": "right"}, root=0.167, ail=(0.627, 0.946, 0.44, None),
                flap=(0.12, 0.62, 0.56, 22.9),
                side_items=["servo_aileron_left", "servo_flap_left", "gear_main_left"],
                s_side=0.611, k_lin=0.456, beta_ft05=None, ft05_ke=None, rot=1, dihedral_deg=0.0),
}
ORDER = ["stik", "stik61", "extra", "p51", "f4u", "avanti", "timber", "x8"]
FRACTIONS = [0.3, 0.4, 0.5]  # outer-panel loss, fraction of the semispan from the tip
CL_SECTION_MAX_FACTOR = 1.10  # section cl_max ~ 1.1 x the aircraft CL_max (3-D -> 2-D), estimate
WING_CD0_SHARE = 0.35        # share of CD0 that is wing profile drag (sport models, estimate)


def val(x):
    return x["value"] if isinstance(x, dict) and "value" in x else x


def load(cfg):
    d = json.load(open(os.path.join(REPO, "app/data/aircraft", cfg["file"] + ".json")))
    ref = d["reference"]
    S = val(ref["wing_area"]); b = val(ref["wing_span"])
    chords = (val(ref["root_chord"]), val(ref["tip_chord"])) if "root_chord" in ref else (S / b, S / b)
    co = {k: val(v) for k, v in d["aero"]["coefficients"].items()}
    env = {k: val(v) for k, v in d["aero"].get("envelope", {}).items()}
    throws = {k: val(v) for k, v in d["controls"].get("max_throw", {}).items()}
    return d, S, b, chords, co, env, throws


def probe_table(probe_id):
    rows = list(csv.DictReader(open(os.path.join(HERE, "part_throttle.csv"))))
    t = {}
    mass = None
    for r in rows:
        if r["aircraft"] == probe_id and float(r["throttle"]) == 1.0:
            u = float(r["u_mps"]); rpm = float(r["rpm"])
            p = float(r["shaft_power_w"]) if r["shaft_power_w"] not in ("", "nan") else float("nan")
            q = p / (rpm * 2 * math.pi / 60) if rpm > 0 and p == p else 0.0
            t[u] = (float(r["thrust_n"]), q)
            mass = float(r["mass_kg"])
    us = sorted(t)
    return mass, np.array(us), np.array([t[u][0] for u in us]), np.array([t[u][1] for u in us])


# --------------------------------------------------------------------------------------------- mass properties
def parts_from_inventory(d, cfg, h, chords):
    """Point/box parts [m, pos_le, size, tag]. Wing items are sliced spanwise (mass proportional to local chord)."""
    parts = []
    cr, ct = chords
    n = 120
    for it in d["inventory"]:
        iid = it.get("id"); m = val(it["mass"]); p = list(val(it["position"]))
        sz = list(val(it.get("size", {"value": [0, 0, 0]})))
        side = cfg["wing"].get(iid)
        if side is None:
            parts.append([m, p, sz, iid])
            continue
        sides = ["left", "right"] if side == "both" else [side]
        m_side = m / len(sides)
        # spanwise slices on [0, h]; mass ~ chord(y); x keeps the item's chordwise centre (sweep ignored except X8)
        ys = (np.arange(n) + 0.5) / n * h
        cy = cr + (ct - cr) * ys / h
        w = cy / cy.sum()
        sweep = 0.30 if cfg["file"] == "moonrunner_x99" else 0.0  # X8 quarter-chord sweep ~17 deg (estimate)
        ybar = float((w * ys).sum())
        dih = math.tan(math.radians(cfg["dihedral_deg"]))
        for s in sides:
            sg = -1.0 if s == "left" else 1.0
            for yi, wi, ci in zip(ys, w, cy):
                x = p[0] + sweep * (yi - ybar)
                z = p[2] + dih * (yi - ybar)
                chord_size = sz[0] * ci / (cr + ct) * 2 if sz[0] else 0.0
                parts.append([m_side * wi, [x, sg * yi, z], [chord_size, h / n, sz[2]], "%s:%s" % (iid, s)])
    return parts


def mass_props(parts):
    m = sum(p[0] for p in parts)
    cg = np.sum([np.array(p[1]) * p[0] for p in parts], axis=0) / m
    J = np.zeros(6)
    for mi, pos, s, _ in parts:
        x = -(pos[0] - cg[0]); y = pos[1] - cg[1]; z = -(pos[2] - cg[2])
        J[0] += mi * (y * y + z * z) + mi * (s[1] ** 2 + s[2] ** 2) / 12.0
        J[1] += mi * (x * x + z * z) + mi * (s[0] ** 2 + s[2] ** 2) / 12.0
        J[2] += mi * (x * x + y * y) + mi * (s[0] ** 2 + s[1] ** 2) / 12.0
        J[3] -= mi * x * y
        J[4] -= mi * x * z
        J[5] -= mi * y * z
    return m, cg, J


def tensor(J):
    return np.array([[J[0], J[3], J[4]], [J[3], J[1], J[5]], [J[4], J[5], J[2]]])


def split_damage(parts, cut_y, cfg):
    """Remove everything at y < cut_y that belongs to the left wing (slices) or is a listed left-side item."""
    keep, lost = [], []
    for p in parts:
        tag = p[3]
        on_left_wing = tag.endswith(":left")
        listed = tag in cfg["side_items"]
        if (on_left_wing or listed) and p[1][1] < cut_y:
            lost.append(p)
        else:
            keep.append(p)
    return keep, lost


# --------------------------------------------------------------------------------------------- lifting line (Weissinger)
def horseshoe_w(xp, yp, xa, ya, xb, yb):
    """Normal (z-up) induced velocity at (xp, yp, 0) per unit circulation of a planar horseshoe: bound A->B, legs to
    x = +inf (downstream). Bertin & Smith form; positive circulation (lift) gives downwash (negative) on the wing."""
    r1 = math.hypot(xp - xa, yp - ya)
    r2 = math.hypot(xp - xb, yp - yb)
    den = (xp - xa) * (yp - yb) - (xp - xb) * (yp - ya)
    t1 = 0.0
    if abs(den) > 1e-12:
        t1 = (((xb - xa) * (xp - xa) + (yb - ya) * (yp - ya)) / r1 - ((xb - xa) * (xp - xb) + (yb - ya) * (yp - yb)) / r2) / den
    t2 = (1.0 + (xp - xa) / r1) / (ya - yp) if abs(ya - yp) > 1e-12 else 0.0
    t3 = (1.0 + (xp - xb) / r2) / (yb - yp) if abs(yb - yp) > 1e-12 else 0.0
    return (t1 + t2 - t3) / (4.0 * math.pi)


class Wing:
    """Spanwise vortex-lattice (one chordwise panel) over arbitrary span segments, unswept quarter-chord line."""

    def __init__(self, segments, chord_fn, a0=2 * math.pi * 0.9, n_per_m=40, wall=None):
        ys = []
        for (y0, y1) in segments:
            n = max(4, int(round((y1 - y0) * n_per_m)))
            # cosine spacing per segment for tip resolution
            e = y0 + (y1 - y0) * (1 - np.cos(np.linspace(0, math.pi, n + 1))) / 2
            ys.append(e)
        self.edges = ys
        self.ya = np.concatenate([e[:-1] for e in ys])
        self.yb = np.concatenate([e[1:] for e in ys])
        self.ym = 0.5 * (self.ya + self.yb)
        self.dy = self.yb - self.ya
        self.c = np.array([chord_fn(abs(y)) for y in self.ym])
        k = a0 / (2 * math.pi)
        self.xcp = 0.5 * self.c * k  # control point behind the bound vortex (section slope a0)
        n = len(self.ym)
        A = np.zeros((n, n))
        for i in range(n):
            for j in range(n):
                A[i, j] = horseshoe_w(self.xcp[i], self.ym[i], 0.0, self.ya[j], 0.0, self.yb[j])
                if wall is not None:  # symmetric image about the plane y = wall (fuselage side as a reflection plane)
                    A[i, j] += horseshoe_w(self.xcp[i], self.ym[i], 0.0, 2 * wall - self.yb[j], 0.0, 2 * wall - self.ya[j])
        self.A = A
        # Trefftz-like downwash at bound midpoints from trailing legs only (for induced drag)
        T = np.zeros((n, n))
        for i in range(n):
            for j in range(n):
                ya, yb, y = self.ya[j], self.yb[j], self.ym[i]
                T[i, j] = ((1.0 / (ya - y)) - (1.0 / (yb - y))) / (4.0 * math.pi)
                if wall is not None:
                    ia, ib = 2 * wall - yb, 2 * wall - ya
                    T[i, j] += ((1.0 / (ia - y)) - (1.0 / (ib - y))) / (4.0 * math.pi)
        self.T = T

    def solve(self, alpha_local):
        """gamma = Gamma/V for local geometric angle alpha_local (rad, per panel). Lift/q = 2 sum gamma dy."""
        g = np.linalg.solve(self.A, -np.asarray(alpha_local))
        return g

    def lift_q(self, g):
        return 2.0 * float((g * self.dy).sum())

    def roll_q(self, g, ycg):
        # positive = rolls toward the LEFT (damaged) side: lift at y > ycg
        return 2.0 * float((g * self.dy * (self.ym - ycg)).sum())

    def cl_local(self, g):
        return 2.0 * g / self.c

    def induced_drag_q(self, g):
        w = self.T @ g  # per V
        return -2.0 * float((g * w * self.dy).sum())


def mask(w, lo_frac, hi_frac, h, sign=None):
    a = np.abs(w.ym) / h
    m = ((a >= lo_frac) & (a <= hi_frac)).astype(float)
    if sign is not None:
        m *= (np.sign(w.ym) == sign)
    return m


def check_vlm():
    # rectangular AR 6, 2 pi section: Weissinger/Helmbold ~4.4-4.5 /rad; induced e ~0.9-1
    w = Wing([(-3.0, 3.0)], lambda y: 1.0, a0=2 * math.pi, n_per_m=6)
    g = w.solve(np.full(len(w.ym), 1.0))
    cla = w.lift_q(g) / 6.0
    cl = 0.5
    g2 = w.solve(np.full(len(w.ym), cl / cla))
    e = cl ** 2 / (math.pi * 6 * (w.induced_drag_q(g2) / 6.0))
    return cla, e


# --------------------------------------------------------------------------------------------- wings-level trim
def trim_vmin(key, cfg, data, case, lost_side_torque_sign, use_flap, mp, W, vgrid, Tq, Tthrust=lambda V: 0.0):
    d, S, b, chords, co, env, throws = data
    h = b / 2
    cr, ct = chords
    chord = lambda y: cr + (ct - cr) * min(y, h) / h
    ycg = mp["ycg"]
    wall = None
    if case == "b_wall":
        segs = [(cfg["root"], h)]
        wall = cfg["root"]  # fuselage side as a reflection plane (upper bound on the end-plate effect)
    elif case == "b_free":
        segs = [(cfg["root"], h)]
    else:
        f = case
        segs = [(-(1 - f) * h, h)]
    w = Wing(segs, chord, wall=wall)
    real = np.ones(len(w.ym))
    a_lo, a_hi, tau_a, _ = cfg["ail"]
    ail_max = math.radians(throws.get("aileron", 20.0))
    # unit solutions (local angle patterns); the image half in b_wall mirrors the real panel's symmetric loads
    alpha_u = np.ones(len(w.ym))
    ail_r = -tau_a * mask(w, a_lo, a_hi, h, +1)   # right (intact) aileron TE up for a roll-right command
    ail_l = +tau_a * mask(w, a_lo, a_hi, h, -1)   # left aileron TE down (only where the left wing still exists)
    ail_u = ail_r + ail_l
    flap_u = np.zeros(len(w.ym))
    flap_max = 0.0
    if use_flap and cfg["flap"]:
        f_lo, f_hi, tau_f, lim = cfg["flap"]
        flap_u = tau_f * mask(w, f_lo, f_hi, h)
        flap_max = math.radians(lim) / tau_f  # effective angle limit L -> equivalent deflection
    sols = {}
    for name, pat in (("a", alpha_u), ("d", ail_u), ("f", flap_u)):
        g = w.solve(pat)
        g = g * real
        sols[name] = g
    L = {k: w.lift_q(g) for k, g in sols.items()}
    R = {k: w.roll_q(g, ycg) for k, g in sols.items()}
    clmax = CL_SECTION_MAX_FACTOR * float(env.get("CL_max", 1.1))
    Q = Tq  # function V -> torque
    res = None
    for V in vgrid:
        q = 0.5 * RHO * V * V
        df = flap_max if use_flap and cfg["flap"] else 0.0
        Rext = lost_side_torque_sign * Q(V)
        # q*(La*a + Ld*da + Lf*df) = W ; q*(Ra*a + Rd*da + Rf*df) + Rext = 0
        M = np.array([[L["a"], L["d"]], [R["a"], R["d"]]])
        rhs = np.array([W / q - L["f"] * df, -Rext / q - R["f"] * df])
        try:
            a, da = np.linalg.solve(M, rhs)
        except np.linalg.LinAlgError:
            continue
        g = sols["a"] * a + sols["d"] * da + sols["f"] * df
        clloc = w.cl_local(g)[real > 0]
        ok = abs(da) <= ail_max and clloc.max() <= clmax and clloc.min() >= -clmax
        if ok:
            cdi = w.induced_drag_q(g) / S
            # yaw: section induced + profile drag of the remaining wing about the CG, plus thrust on the centreline
            wi = w.T @ g
            d_ind = -2.0 * g * wi * w.dy * real  # per q
            d_prof = co["CD0"] * WING_CD0_SHARE * w.c * w.dy * real  # per q, wing share of CD0 on local area
            n_drag = q * float(((d_ind + d_prof) * (w.ym - ycg)).sum())  # + = nose toward the intact (right) side
            n_thrust = ycg * Tthrust(V)
            n_rudder = abs(co["Cndr"]) * math.radians(throws.get("rudder", 25.0)) * q * S * b
            res = dict(V=V, alpha_deg=math.degrees(a), da_deg=math.degrees(da), cl_peak=float(clloc.max()), cdi=cdi,
                       roll_arm=R["a"] / L["a"] + ycg, yaw_ratio=(n_drag + n_thrust) / n_rudder if n_rudder > 0 else float("inf"))
            break
    lift_arm = R["a"] / L["a"] + ycg  # lift centroid of the basic loading (y from the centreline)
    return res, lift_arm, (L, R), w


# --------------------------------------------------------------------------------------------- knife-edge budget
def side_coeff(law, beta, cfg):
    sb, cb = math.sin(beta), math.cos(beta)
    k = cfg["k_lin"]
    if law == "low":    # Letko & Williams body alone, square round-cornered, fineness ~8 (0.75 sin^2)
        return 0.75 * sb * sb
    if law == "model":  # D10-R3 Allen-Perkins form with the Extra's per-side-area parameters
        return k * sb * cb + 0.91 * sb * sb
    if law == "high":   # wing-body interference doubles the slope (L&W fig 18) + 30 % more side area (gear, canopy)
        return 1.3 * (2 * k * sb * cb + 0.91 * sb * sb)
    raise ValueError(law)


def knife_edge(cfg, S, co, W, T_of_V, beta_deg, law, cd0_scale, dr_rad):
    """Steady straight knife-edge in the vertical plane: thrust along the body axis, nose beta above the path; the body
    side force Y (normal to the body axis) splits into Y cos(beta) across and Y sin(beta) along the path.
    across: T sin(beta) + Y cos(beta) = W cos(gamma);  along: T cos(beta) - D0 - Y sin(beta) + W sin(gamma) = 0,
    gamma > 0 descending. Returns (level_or_climb_possible, (V, sink) of the least-sink steady descent or None)."""
    beta = math.radians(beta_deg)
    level = False
    Vs = np.arange(6.0, 90.0, 0.05)
    resid, sinks, valid = [], [], []
    for V in Vs:
        q = 0.5 * RHO * V * V
        T = T_of_V(V)
        Y = q * cfg["s_side"] * side_coeff(law, beta, cfg)
        perp = T * math.sin(beta) + Y * math.cos(beta)
        D0 = q * S * (co["CD0"] * cd0_scale + abs(co.get("CDdr", 0.03) * dr_rad))
        along = T * math.cos(beta) - D0 - Y * math.sin(beta)
        c = perp / W
        if c >= 1.0:
            if along >= 0:
                level = True
            resid.append(float("nan")); sinks.append(float("nan")); valid.append(False)
            continue
        sg = math.sqrt(1 - c * c)
        resid.append(along + W * sg); sinks.append(V * sg); valid.append(True)
    best = None
    for i in range(1, len(Vs)):
        if valid[i] and valid[i - 1] and resid[i - 1] * resid[i] <= 0 and resid[i - 1] > 0:
            # stable root: accelerating below, decelerating above
            t = resid[i - 1] / (resid[i - 1] - resid[i])
            V = Vs[i - 1] + t * (Vs[i] - Vs[i - 1]); sink = sinks[i - 1] + t * (sinks[i] - sinks[i - 1])
            if best is None or sink < best[1]:
                best = (float(V), float(sink))
    return level, best


# --------------------------------------------------------------------------------------------- main
def main():
    cla, e = check_vlm()
    out = {"vlm_check": {"CLa_rect_AR6_2pi": cla, "e": e}}
    print("VLM check: rectangular AR 6 (2 pi section) CLa %.3f /rad (Weissinger ~4.4-4.5), span efficiency %.3f" % (cla, e))
    rows_mass, rows_trim, rows_ke, rows_hover, rows_transient = [], [], [], [], []
    for key in ORDER:
        cfg = CONFIG[key]
        data = load(cfg)
        d, S, b, chords, co, env, throws = data
        h = b / 2
        mass_probe, us, Ts, Qs = probe_table(cfg["probe"])
        T_of_V = lambda V, us=us, Ts=Ts: float(np.interp(V, us, Ts))
        Q_of_V = (lambda V, us=us, Qs=Qs: float(np.interp(V, us, Qs))) if cfg["rot"] else (lambda V: 0.0)
        parts = parts_from_inventory(d, cfg, h, chords)
        m0, cg0, J0 = mass_props(parts)
        # the probe's trim mass may include fuel the inventory lists separately; scale weight only
        W0 = mass_probe * G
        cases = [(f, -(1 - f) * h) for f in FRACTIONS] + [("b", -cfg["root"] + 1e-9)]
        mrec = {"intact": dict(m=m0, cg=cg0.tolist(), J=J0.tolist())}
        for cname, cut in cases:
            keep, lost = split_damage(parts, cut, cfg)
            m1, cg1, J1 = mass_props(keep)
            ml = sum(p[0] for p in lost)
            dcg_body = np.array([-(cg1[0] - cg0[0]), cg1[1] - cg0[1], -(cg1[2] - cg0[2])])
            mrec[str(cname)] = dict(m=m1, lost=ml, cg=cg1.tolist(), dcg_body=dcg_body.tolist(), J=J1.tolist())
            rows_mass.append((cfg["label"], cname, ml, ml / m0, dcg_body, J0, J1))
        out.setdefault(key, {})["mass"] = mrec
        # --- wings-level trim on the remaining wing
        vgrid = np.arange(5.0, 120.0, 0.25)
        cd0 = co["CD0"]
        for cname, cut in cases:
            mr = mrec[str(cname)]
            Wd = W0 - mr["lost"] * G
            ycg = mr["dcg_body"][1]
            mp = {"ycg": ycg}
            variants = [cname] if cname != "b" else ["b_wall", "b_free"]
            for var in variants:
                for torque_sign, side_lbl in ((+1, "left lost"), (-1, "right lost")):
                    for use_flap in ([False, True] if cfg["flap"] else [False]):
                        res, arm, LR, w = trim_vmin(key, cfg, data, var, torque_sign, use_flap, mp, Wd, vgrid, Q_of_V, T_of_V)
                        # level-flight thrust check at Vmin: parasite (lost wing share removed) + induced + aileron drag
                        if res:
                            V = res["V"]; q = 0.5 * RHO * V * V
                            lost_share = (cname if cname != "b" else 1.0) * 0.5 * WING_CD0_SHARE
                            D = q * S * (cd0 * (1 - lost_share) + res["cdi"] + 2 * co.get("CDda_each", 0.015) * abs(math.radians(res["da_deg"])))
                            T = T_of_V(V)
                            sin_g = (D - T) / Wd
                            res.update(D=D, T=T, sink=V * sin_g if sin_g > 0 else 0.0, level=T >= D)
                        rows_trim.append((cfg["label"], var, side_lbl, use_flap, arm, ycg, res))
        # --- knife-edge (wing feathered): intact and full-panel loss
        dr = math.radians(throws.get("rudder", 25.0))
        for cname, Wd, cd0s in (("intact", W0, 1.0), ("b", W0 - mrec["b"]["lost"] * G, 1 - 0.5 * WING_CD0_SHARE)):
            for beta in ([cfg["beta_ft05"]] if cfg["beta_ft05"] else []) + [25.0, 30.0]:
                for law in ("low", "model", "high"):
                    if key == "x8":
                        continue
                    level, best = knife_edge(cfg, S, co, Wd, T_of_V, beta, law, cd0s, dr)
                    rows_ke.append((cfg["label"], cname, beta, law, level, best, Wd))
        # --- prop hang / hover
        T0 = T_of_V(0.0)
        Q0 = Q_of_V(0.0)
        D = None
        prop = d["propulsion"].get("propeller", {})
        if prop:
            D = val(prop["diameter"])
        rows_hover.append((cfg["label"], T0, W0, W0 - mrec["b"]["lost"] * G, Q0, D))
        # --- separation transient: lift on the remaining panel at n g, before any pilot input
        mb = mrec["b"]
        Jb = tensor(mb["J"])
        Jinv = np.linalg.inv(Jb)
        for n_g in (1.0, 3.0):
            Wd = W0 - mb["lost"] * G
            res_b, arm_b, LR_b, w_b = trim_vmin(key, cfg, data, "b_wall", +1, False, {"ycg": mb["dcg_body"][1]}, Wd,
                                                 [999.0], Q_of_V)
            Mx = -n_g * Wd * (arm_b - mb["dcg_body"][1])  # lift on the right panel rolls left (Mx < 0)
            pdot = (Jinv @ np.array([Mx, 0.0, 0.0]))
            # roll damping of the remaining panel at V: antisymmetric alpha = p*y/V on the real panel
            V = 25.0 if key not in ("p51", "f4u", "avanti") else 40.0
            g_p = w_b.solve(w_b.ym / V) * (w_b.ym > 0)
            Lp = 0.5 * RHO * V * V * 2.0 * float((g_p * w_b.dy * w_b.ym).sum())  # N m per rad/s (restoring)
            p_ss = abs(Mx) / Lp if Lp > 0 else float("inf")
            # time to 90 deg bank: p' = (|Mx| - Lp p)/Ixx_eff
            Ixx_eff = 1.0 / Jinv[0, 0]
            t, p, phi, dt = 0.0, 0.0, 0.0, 1e-4
            while phi < math.pi / 2 and t < 5:
                pd = (abs(Mx) - Lp * p) / Ixx_eff
                p += pd * dt; phi += p * dt; t += dt
            rows_transient.append((cfg["label"], n_g, V, Mx, pdot.tolist(), Lp, p_ss, t, J0[0], mb["J"][0]))
    out["rows_trim"] = [(r[0], str(r[1]), r[2], r[3], r[4], r[5], r[6]) for r in rows_trim]
    out["rows_ke"] = [(r[0], r[1], r[2], r[3], r[4], r[5], r[6]) for r in rows_ke]
    out["rows_hover"] = rows_hover
    out["rows_transient"] = rows_transient
    json.dump(out, open(os.path.join(HERE, "results.json"), "w"), indent=1, default=float)

    # ------------------------------------------------------------------ print tables
    print("\n## Mass properties after damage (left side damaged)\n")
    print("| Aircraft | Case | Lost mass kg (% of inventory) | ΔCG body x/y/z mm | Jxx Jyy Jzz kg·m² intact → damaged | Jxy, Jxz damaged kg·m² |")
    print("|---|---|---|---|---|---|")
    for lab, c, ml, frac, dcg, J0, J1 in rows_mass:
        print("| %s | %s | %.3f (%.1f %%) | %+.1f / %+.1f / %+.1f | %.3f %.3f %.3f → %.3f %.3f %.3f | %+.4f, %+.4f |" % (
            lab, ("outer %d %%" % round(c * 100)) if c != "b" else "full panel", ml, 100 * frac,
            1000 * dcg[0], 1000 * dcg[1], 1000 * dcg[2], J0[0], J0[1], J0[2], J1[0], J1[1], J1[2], J1[3], J1[4]))
    print("\n## Wings-level trim on the remaining wing: minimum speed with full aileron (torque included)\n")
    print("| Aircraft | Case | Side | Flaps | Lift centroid y (m) | CG y (mm) | Vmin m/s | α° | δa° | cl peak | T−D at Vmin (N) | Sink at Vmin full power (m/s) | Yaw need / full rudder |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for lab, var, side, fl, arm, ycg, res in rows_trim:
        cname = ("outer %d %%" % round(var * 100)) if not isinstance(var, str) else {"b_wall": "full, root wall", "b_free": "full, free root"}[var]
        if res:
            print("| %s | %s | %s | %s | %.3f | %+.1f | %.1f | %.1f | %.1f | %.2f | %+.1f | %.1f | %.2f |" % (
                lab, cname, side, "yes" if fl else "no", arm, 1000 * ycg, res["V"], res["alpha_deg"], res["da_deg"],
                res["cl_peak"], res["T"] - res["D"], res["sink"], res["yaw_ratio"]))
        else:
            print("| %s | %s | %s | %s | %.3f | %+.1f | none ≤ 120 | – | – | – | – | – | – |" % (lab, cname, side, "yes" if fl else "no", arm, 1000 * ycg))
    print("\n## Knife-edge with the wing feathered (full rudder sideslip β, full throttle)\n")
    print("| Aircraft | Config | β° | Side-force law | Level possible | Best steady point: V m/s, sink m/s | Weight N |")
    print("|---|---|---|---|---|---|---|")
    for lab, c, beta, law, level, best, Wd in rows_ke:
        bs = ("%.1f, %.1f" % best) if best else "no steady solution (V ≤ 90)"
        print("| %s | %s | %.1f | %s | %s | %s | %.1f |" % (lab, c, beta, law, "yes" if level else "no", bs, Wd))
    print("\n## Prop hang / hover\n")
    print("| Aircraft | T0 N | W intact N | T0/W intact | W one panel lost N | T0/W damaged | Hover torque at T=W N·m |")
    print("|---|---|---|---|---|---|---|")
    for lab, T0, W0, Wb, Q0, D in rows_hover:
        print("| %s | %.1f | %.1f | %.2f | %.1f | %.2f | %.2f |" % (lab, T0, W0, T0 / W0, Wb, T0 / Wb, Q0 * (Wb / T0) if T0 > 0 else 0))
    print("\n## Separation transient (full panel, lift held at n g, no pilot input)\n")
    print("| Aircraft | n | V m/s | Roll moment N·m | ṗ0 rad/s² | Lp N·m·s | p steady °/s | t to 90° s | Jxx intact → damaged |")
    print("|---|---|---|---|---|---|---|---|---|")
    for lab, n_g, V, Mx, pdot, Lp, pss, t90, j0, j1 in rows_transient:
        print("| %s | %.0f | %.0f | %.1f | %.0f | %.2f | %.0f | %.2f | %.3f → %.3f |" % (lab, n_g, V, Mx, pdot[0], Lp, math.degrees(pss), t90, j0, j1))


if __name__ == "__main__":
    main()
