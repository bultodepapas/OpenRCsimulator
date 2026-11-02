"""RC propellers and spinners for the O.S. 61SF, built from published geometry:

  * APC Sport (glow) 11x7, 11x8, 12x6, 12x7, 12.5x6: APC's own PE0 geometry files (station, chord, quoted
    pitch, sweep, thickness ratio, cross-section area, mass offsets CGY/CGZ; Clark-Y sections) mirrored on
    github.com/ericjohnson97/apc_props; hub 1.00 in with the listed thickness (Brodak / AMain / HobbyGulf).
  * Master Airscrew G/F 11x7, Scimitar 11x7 (UIUC Propeller Data Site vol. 1: c/R, beta and our front / side
    silhouettes of the UIUC photos), 3-Blade 11x7 and 12x6 (planform from the maker's product image, UIUC
    11x7 twist); hub thickness and weight from masterairscrew.com.
  * Spinners: Tru-Turn Standard 2-1/2" and Ultimate 2-1/4" (cone outlines from Tru-Turn's 1:1 PDFs,
    aluminium, 10-32 retaining bolt into a spinner nut), Dubro 2-1/2" and 2-3/4" 3-blade (nylon, 63 / 70 mm,
    two / three 3.5 mm cap screws into locknuts in the backplate).

blender -b --factory-startup -P build_props.py -- --save props_library.blend [--json props_build.json]

Frames (mm, same axes as the engine): +Y = rear (engine side), -Y = thrust; props: origin at the centre of
the hub's rear face, blade 0 along +X, rotation counter-clockwise seen from the front (blade 0 moves to +Z);
spinners: origin at the centre of the backplate's rear face, cone along -Y.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, "/home/claude/engine")
import build_engine as be  # noqa: E402
from build_engine import MM, T, Rot, boolean, bm_cyl, bm_revolve, hull2d, make_obj, tmp_obj, _principled  # noqa

sys.path.insert(0, "/home/claude/props")
sys.path.insert(0, "/home/claude/props/ref")
import propgeom as G  # noqa: E402
import spinner_outlines as SO  # noqa: E402

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SAVE = A[A.index("--save") + 1] if "--save" in A else None
JSON_OUT = A[A.index("--json") + 1] if "--json" in A else None
ONLY = A[A.index("--only") + 1].split(",") if "--only" in A else None
IN = 25.4


# ----------------------------------------------------------------------------- helpers
def col(name, parent=None):
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    par = parent or bpy.context.scene.collection
    if c.name not in [x.name for x in par.children]:
        par.children.link(c)
    return c


def earclip(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    ng = [f for f in bm.faces if len(f.verts) > 4]
    if ng:
        bmesh.ops.triangulate(bm, faces=ng, quad_method="BEAUTY", ngon_method="EAR_CLIP")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(ob.data)
    bm.free()


def sharp(ob, deg=34.0):
    ob.data.set_sharp_from_angle(angle=math.radians(deg))


def root_empty(name, collection):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = 0.02
    collection.objects.link(e)
    return e


def parent_to(objs, root):
    for o in objs:
        o.parent = root


def pchip_profile(pts, n=80):
    """Monotone (Fritsch-Carlson) interpolation of an (x, r) outline -> n+1 points."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    h = [xs[i + 1] - xs[i] for i in range(len(xs) - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(len(h))]
    m = [d[0]] + [0.0 if d[i - 1] * d[i] <= 0 else 3 * (h[i - 1] + h[i]) / ((2 * h[i] + h[i - 1]) / d[i - 1] +
                                                                         (h[i] + 2 * h[i - 1]) / d[i])
                  for i in range(1, len(d))] + [d[-1]]
    out = []
    for k in range(n + 1):
        x = xs[0] + (xs[-1] - xs[0]) * k / n
        i = min(len(h) - 1, max(0, next((j for j in range(len(h)) if x <= xs[j + 1]), len(h) - 1)))
        t = (x - xs[i]) / h[i]
        h00, h10, h01, h11 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t, -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
        out.append((x, h00 * ys[i] + h10 * h[i] * m[i] + h01 * ys[i + 1] + h11 * h[i] * m[i + 1]))
    return out


# ----------------------------------------------------------------------------- materials
def mat_nylon(name, base, rough, sss=0.15):
    m = _principled(name, base, 0.0, rough, rough_var=0.05, noise_scale=400.0, bump=0.03, bump_scale=2500.0)
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Subsurface Weight"].default_value = sss
    b.inputs["Subsurface Scale"].default_value = 0.0015
    b.inputs["Subsurface Radius"].default_value = (1.0, 0.6, 0.4)
    return m


def materials():
    M = {}
    # APC Sport: glass-filled nylon, mid grey, satin with a faint mould texture
    M["apc"] = _principled("M_Prop_APC_Gris", (0.092, 0.091, 0.085), 0.0, 0.46, rough_var=0.02, noise_scale=300.0,
                           bump=0.02, bump_scale=6000.0)
    # Master Airscrew: black glass-filled composite, semi-gloss
    M["ma"] = _principled("M_Prop_MA_Negro", (0.014, 0.014, 0.015), 0.0, 0.30, rough_var=0.02, noise_scale=350.0,
                          bump=0.02, bump_scale=6000.0)
    M["alu"] = _principled("M_Spinner_Aluminio_Pulido", (0.91, 0.91, 0.915), 1.0, 0.075, rough_var=0.03,
                           noise_scale=1200.0, aniso=0.55)
    M["alu_turned"] = _principled("M_Spinner_Aluminio_Torneado", (0.88, 0.88, 0.885), 1.0, 0.20, rough_var=0.04,
                                  noise_scale=900.0, aniso=0.7)
    M["nylon_white"] = mat_nylon("M_Spinner_Nylon_Blanco", (0.78, 0.78, 0.76), 0.34, 0.25)
    M["nylon_red"] = mat_nylon("M_Spinner_Nylon_Rojo", (0.50, 0.012, 0.014), 0.30, 0.12)
    M["nylon_black"] = mat_nylon("M_Spinner_Nylon_Negro", (0.02, 0.02, 0.021), 0.36, 0.0)
    M["black_oxide"] = _principled("M_Acero_Pavonado", (0.035, 0.033, 0.032), 1.0, 0.32, rough_var=0.06,
                                   noise_scale=600.0)
    M["zinc"] = _principled("M_Acero_Zincado", (0.78, 0.79, 0.80), 1.0, 0.28, rough_var=0.06, noise_scale=500.0)
    M["nyloc"] = _principled("M_Nylon_Inserto_Azul", (0.15, 0.25, 0.55), 0.0, 0.4, rough_var=0.03)
    return M


# ----------------------------------------------------------------------------- props
def loft(loops, mapf):
    """Closed loft through equal-length loops (list of (r, u, a)): capped inside the hub, closed at the blade
    tip on a single vertex (the tip's last tiny section collapses to its centre: no flat cap at the tip)."""
    bm = bmesh.new()
    rings = [[bm.verts.new(mapf(p)) for p in L] for L in loops[:-1]]
    last = loops[-1]
    tip = bm.verts.new(mapf((last[0][0], sum(p[1] for p in last) / len(last), sum(p[2] for p in last) / len(last))))
    m = len(rings[0])
    for Ar, Br in zip(rings, rings[1:]):
        for k in range(m):
            bm.faces.new((Ar[k], Ar[(k + 1) % m], Br[(k + 1) % m], Br[k]))
    Br = rings[-1]
    for k in range(m):
        bm.faces.new((Br[k], Br[(k + 1) % m], tip))
    caps = [bm.faces.new(rings[0][::-1])]
    bmesh.ops.triangulate(bm, faces=caps, quad_method="BEAUTY", ngon_method="EAR_CLIP")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def blade_map(theta_deg, hub_t):
    """(r, u, a) of a blade along +X -> prop frame, then rotated to its place around the hub."""
    R = Rot("Y", -theta_deg)

    def f(p):
        r, u, a = p
        return R @ Vector((r, -hub_t / 2 - a, u))
    return f


def build_prop(spec, C, M):
    loops, rows, info = G.build_loops(spec)
    hub_r, hub_t = spec["hub_d"] / 2, spec["hub_t"]
    ch = min(0.6, hub_t * 0.05)
    hub = make_obj(f"PROP_{spec['key']}", bm_revolve([(G.BORE_D / 2, 0.0), (hub_r - ch, 0.0), (hub_r, -ch),
                                                      (hub_r, -hub_t + ch), (hub_r - ch, -hub_t),
                                                      (G.BORE_D / 2, -hub_t)], 96, "Y", closed=True),
                   C, [M[spec["mat"]]])
    n = spec["blades"]
    blades = [tmp_obj(loft(loops, blade_map(360.0 * k / n, hub_t))) for k in range(n)]
    boolean(hub, blades, "UNION")
    earclip(hub)
    sharp(hub, 40.0)
    hub["prop_spec"] = json.dumps({k: v for k, v in spec.items()})
    hub["hub_t"] = hub_t
    hub["R_mm"] = spec["D"] * IN / 2
    return hub, loops, rows, info


# ----------------------------------------------------------------------------- spinners
def tt_standard_outline(dia_in):
    d0, L0, pts = min(SO.TT_STANDARD, key=lambda s: abs(s[0] - dia_in))
    k = dia_in / d0 * IN            # outline printed at 0.976 of nominal: scale to the nominal diameter
    return [(x * k, r * k) for x, r in pts]


def ultimate_outline(dia_in):
    Rb = dia_in / 2 * IN
    return [(x * Rb, r * Rb) for x, r in SO.TT_ULTIMATE_NORM if r > 0]


def ogive_outline(R, L, nose_r=2.5, n=40):
    """Tangent ogive, base radius R at x = 0, tip at x = L, blunted with a spherical nose."""
    rho = (R * R + L * L) / (2 * R)
    pts = []
    for k in range(n + 1):
        x = L * k / n
        pts.append((x, math.sqrt(max(0.0, rho * rho - x * x)) + R - rho))
    # blunt nose: replace the tip by a sphere of radius nose_r tangent to the ogive
    xn = L - nose_r * 2.2
    return [p for p in pts if p[0] <= xn] + [(xn + (L - xn) * (1 - math.cos(math.pi / 2 * j / 6)),
                                              interp_r(pts, xn) * math.cos(math.pi / 2 * j / 6) ** 0.8)
                                             for j in range(1, 7)]


def interp_r(pts, x):
    return G.interp([p[0] for p in pts], [p[1] for p in pts], x)


SPINNERS = {
    "TT_Std_2-1/2": dict(label="Tru-Turn Standard 2-1/2\"", maker="truturn", R=2.5 / 2 * IN,
                         outline=lambda: tt_standard_outline(2.5), bp_t=5.5, skirt=2.0, wall=1.6, nose_solid=8.0,
                         mat="alu", bp_mat="alu_turned", blades=2, retainer="bolt"),
    "TT_Ult_2-1/4": dict(label="Tru-Turn Ultimate 2-1/4\"", maker="truturn", R=2.25 / 2 * IN,
                         outline=lambda: ultimate_outline(2.25), bp_t=5.0, skirt=2.0, wall=1.5, nose_solid=9.0,
                         mat="alu", bp_mat="alu_turned", blades=2, retainer="bolt"),
    "DB_2-1/2": dict(label="Dubro 2-1/2\" (63 mm)", maker="dubro", R=31.5, L=68.0,
                     outline=lambda: ogive_outline(31.5, 68.0, 2.4), bp_t=5.0, skirt=2.2, wall=1.8, nose_solid=4.0,
                     mat="nylon_white", bp_mat="nylon_white", blades=2, retainer="screws", screw_r=22.0),
    "DB_3B_2-3/4": dict(label="Dubro 2-3/4\" 3 palas (70 mm)", maker="dubro", R=35.0, L=75.0,
                        outline=lambda: ogive_outline(35.0, 75.0, 2.6), bp_t=5.0, skirt=2.2, wall=1.8,
                        nose_solid=4.0, mat="nylon_red", bp_mat="nylon_red", blades=3, retainer="screws",
                        screw_r=24.5),
}
COMBOS = {   # spinner -> the prop its blade openings are cut for
    "A": ("APC_12x6", "TT_Std_2-1/2"),
    "B": ("MA_3B_11x7", "DB_3B_2-3/4"),
    "C": ("APC_11x7", "DB_2-1/2"),
    "D": ("MA_Scimitar_11x7", "TT_Ult_2-1/4"),
}
WASHER_T, NUT_H = 2.4, 6.5
BP_BORE = 8.1          # backplate bore: slips over the 5/16 thread and the 8 mm drive-hub seat


def spinner_profiles(S):
    """Outer outline (x from the backplate rear face, r) with the backplate's rounded rear corner."""
    out = S["outline"]()
    R = S["R"]
    x0 = out[0][0]
    base = [(0.0, R - 1.2), (0.35, R - 0.45), (0.9, R - 0.1)]
    if x0 > 1.0:
        base.append((x0, out[0][1]))
    prof = base + [p for p in pchip_profile(out, 90) if p[0] > base[-1][0] + 0.2]
    return prof


def build_spinner(skey, prop, C, M):
    """Backplate + cone (with blade openings cut around `prop`, which must sit on the backplate)."""
    S = SPINNERS[skey]
    R, bp_t, sk, wall = S["R"], S["bp_t"], S["skirt"], S["wall"]
    prof = spinner_profiles(S)
    L = prof[-1][0]
    nose_r = prof[-1][1]
    xs = bp_t - sk                     # cone skirt seats on the backplate shoulder at x = xs
    # --- cone outline, wall offset inside, solid nose
    outer = [(xs, interp_r(prof, xs))] + [p for p in prof if p[0] > xs + 0.05]
    x_in_end = L - S["nose_solid"]
    inner = []
    for i, (x, r) in enumerate(outer):
        if x >= x_in_end:
            break
        x1, r1 = outer[min(i + 1, len(outer) - 1)]
        x0_, r0_ = outer[max(i - 1, 0)]
        sl = math.atan2(r0_ - r1, x1 - x0_) if x1 > x0_ else 0.0
        inner.append((x, max(0.6, r - wall / max(0.3, math.cos(sl)))))
    inner.append((x_in_end, max(0.6, interp_r(outer, x_in_end) - wall)))
    r_sh = min(r for x, r in inner if x <= bp_t + 0.5) - 0.05     # backplate shoulder under the skirt
    inner = [(x, r_sh + 0.05) if x <= bp_t + 0.5 else (x, r) for x, r in inner]
    # --- backplate: rounded rear rim, shoulder for the cone skirt, 5/16 bore
    rr = [p for p in prof if p[0] < xs - 0.05]
    bp_prof = [(BP_BORE / 2, 0.0)] + [(r, -x) for x, r in rr] + [(interp_r(prof, xs), -xs), (r_sh, -xs),
                                                                  (r_sh, -bp_t + 0.3), (r_sh - 0.3, -bp_t),
                                                                  (BP_BORE / 2, -bp_t)]
    tag = skey.replace("/", "_")
    PH = math.pi / 128     # half a segment: no revolve vertex on the 0 / 90 / 180 deg planes of the cut features
    bp = make_obj(f"SPIN_{tag}_Placa", bm_revolve(bp_prof, 128, "Y", closed=True, phase=PH), C, [M[S["bp_mat"]]])
    ring = [(r, -x) for x, r in outer]
    if nose_r > 0.8:
        ring.append((0.0, -L))
    else:
        ring[-1] = (0.0, -L)
    ring += [(0.0, -x_in_end)] + [(r, -x) for x, r in inner[::-1]]
    cone = make_obj(f"SPIN_{tag}_Cono", bm_revolve(ring, 128, "Y", closed=True, phase=PH), C, [M[S["mat"]]])
    cuts = []
    if S["retainer"] == "bolt":        # Tru-Turn: 10-32 cap screw recessed in the nose
        cb_r, cb_d = 4.3, 5.4
        x_hb = L - cb_d
        cuts.append(tmp_obj(bm_cyl(cb_r, (0, -x_hb, 0), (0, -L - 2, 0), 40)))
        cuts.append(tmp_obj(bm_cyl(2.55, (0, -x_in_end + 1, 0), (0, -x_hb - 0.1, 0), 32)))
        S["x_bolt_head"] = x_hb
    cuts += blade_cutters(prop, S, prof, inner, xs)
    if S["retainer"] == "screws":      # Dubro: screw bosses moulded in the cone, wells and through holes
        n = S["blades"]
        rs = S["screw_r"]
        solid = bm_revolve([(0.0, -xs)] + [(max(0.1, r - 0.5), -x) for x, r in outer] + [(0.0, -L)], 128, "Y",
                           phase=PH / 2)      # bosses trimmed 0.5 mm inside the skin: they merge into the wall
        bosses = []
        S["screws"] = []
        for k in range(n):
            ang = 360.0 * k / n + 180.0 / n
            p = screw_at(ang, rs)
            x_top = x_where(prof, rs - 4.4) + 1.0
            b = tmp_obj(bm_cyl(4.3, p(bp_t + 0.02), p(x_top), 32))
            boolean(b, [tmp_obj(solid.copy())], "INTERSECT")
            bosses.append(b)
            S["screws"].append(dict(ang=ang, x_head=17.6, x_well=round(x_where(prof, rs + 3.3), 2)))
            cuts.append(tmp_obj(bm_cyl(3.3, p(17.6), p(x_top + 10), 32)))
            cuts.append(tmp_obj(bm_cyl(1.95, p(bp_t - 0.5), p(17.7), 24)))
        solid.free()
        boolean(cone, bosses, "UNION")
    boolean(cone, cuts, "DIFFERENCE")
    if S["retainer"] == "screws":     # hex pockets for the locknuts in the backplate's rear face, through holes
        pk = []
        for sc in S["screws"]:
            p = screw_at(sc["ang"], S["screw_r"])
            pk.append(tmp_obj(bm_cyl(3.0 / math.cos(math.pi / 6) + 0.1, p(-0.6), p(4.1), 6)))
            pk.append(tmp_obj(bm_cyl(1.95, p(-1.0), p(bp_t + 1), 24)))
        boolean(bp, pk, "DIFFERENCE")
    for o in (bp, cone):
        earclip(o)
        sharp(o, 36.0)
    S["L"] = L
    S["inner"] = inner
    S["outer"] = outer
    return [bp, cone], S


def screw_at(ang, rs):
    """Point at axial station x on the screw axis at angle `ang` (same convention as the blades)."""
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return lambda x: (rs * ca, -x, rs * sa)


def x_where(prof, r):
    """Axial station where the outline comes down to radius r."""
    for (x0, r0), (x1, r1) in zip(prof, prof[1:]):
        if r0 >= r >= r1 and r0 != r1:
            return x0 + (r0 - r) / (r0 - r1) * (x1 - x0)
    return prof[-1][0]


def blade_cutters(prop, S, prof, inner, xs, clear=1.6):
    """Openings for each blade: the blade root's silhouette across the cone wall (seen along the blade),
    grown by `clear` and run out to the cone's rear edge; cut straight along the blade axis."""
    me = prop.data
    mw = prop.matrix_world
    vs = [(mw @ v.co) / MM for v in me.vertices]
    n = S["blades"]
    R = S["R"]
    # the cone wall spans these radii over the blade's axial range
    ys = [v.y for v in vs if R - 12 < math.hypot(v.x, v.z) < R + 1.0]
    x_lo, x_hi = -max(ys), -min(ys)
    r_in_min = min(interp_r(inner, x) for x in (x_lo, (x_lo + x_hi) / 2, x_hi) if x <= inner[-1][0])
    r_lo = r_in_min - 2.0
    out = []
    for k in range(n):
        th = 360.0 * k / n
        Rb = Rot("Y", th)                        # prop frame -> blade frame (inverse of Rot(Y, -th))
        pts = []
        for v in vs:
            b = Rb @ v
            if r_lo <= b.x <= R + 1.0 and abs(b.z) < R:
                pts.append((b.z, b.y))
        hull = hull2d(pts)
        grown = []
        for u, y in hull:
            for j in range(12):
                a = 2 * math.pi * j / 12
                grown.append((u + clear * math.cos(a), y + clear * math.sin(a)))
                grown.append((u + clear * math.cos(a), y + clear * math.sin(a) + 40.0))   # run out to the rear edge
        hull = hull2d(grown)
        bm = bmesh.new()
        vb = [bm.verts.new((r_lo - 3.0, y, u)) for u, y in hull]
        vt = [bm.verts.new((R + 8.0, y, u)) for u, y in hull]
        bm.faces.new(vb[::-1])
        bm.faces.new(vt)
        for i in range(len(hull)):
            j = (i + 1) % len(hull)
            bm.faces.new((vb[i], vb[j], vt[j], vt[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bmesh.ops.transform(bm, matrix=Rot("Y", -th), verts=bm.verts[:])
        out.append(tmp_obj(bm))
    S["cut_r_lo"] = r_lo
    return out


# ----------------------------------------------------------------------------- hardware
def washer_bm(y0, t=WASHER_T, ro=11.6, ri=4.35):
    return bm_revolve([(ri, y0), (ro - 0.4, y0), (ro, y0 - 0.4), (ro, y0 - t + 0.4), (ro - 0.4, y0 - t),
                       (ri, y0 - t)], 64, "Y", closed=True)


def prop_nut(name, y0, C, M, h=NUT_H, ext=None):
    """5/16-24 hex prop nut (11 mm across flats, chamfered); `ext` = (length, radius) of a Tru-Turn spinner
    nut's round extension tapped 10-32 for the retaining bolt."""
    nut = make_obj(name, bm_cyl(6.35, (0, y0, 0), (0, y0 - h, 0), 6), C, [M["zinc"] if ext else M["black_oxide"]])
    cham = tmp_obj(bm_revolve([(0, y0 + 0.1), (5.7, y0 + 0.1), (6.6, y0 - 0.8), (6.6, y0 - h + 0.9),
                               (5.7, y0 - h - 0.1), (0, y0 - h - 0.1)], 48, "Y"))
    boolean(nut, [cham], "INTERSECT")
    if ext:
        L_, r_ = ext
        e = tmp_obj(bm_revolve([(0, y0 - h + 0.5), (r_, y0 - h + 0.5), (r_, y0 - h - L_ + 0.5),
                                (r_ - 0.5, y0 - h - L_), (0, y0 - h - L_)], 48, "Y"))
        boolean(nut, [e], "UNION")
        boolean(nut, [tmp_obj(bm_cyl(2.1, (0, y0 - h, 0), (0, y0 - h - L_ - 1, 0), 24))], "DIFFERENCE")
    boolean(nut, [tmp_obj(bm_cyl(3.36, (0, y0 + 1, 0), (0, y0 - h - 0.2, 0), 32))], "DIFFERENCE")
    earclip(nut)
    sharp(nut, 30.0)
    return nut


def cap_screw(name, x_head, length, d, head_d, head_h, ang, rs, C, M, socket=2.5):
    """Socket head cap screw, head bearing face at x_head (spinner frame), shank toward the backplate."""
    bm = be.bm_screw(length, d=d, pitch=0.6 if d < 4 else 0.79, depth=0.3, head_r=head_d / 2, head_h=head_h)
    ob = make_obj(name, bm, C, [M["black_oxide"]])
    boolean(ob, [tmp_obj(bm_cyl(socket / 2 / math.cos(math.pi / 6), (0, 0, head_h - socket * 0.9),
                                (0, 0, head_h + 1), 6))], "DIFFERENCE")
    earclip(ob)
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    pos = Vector((rs * ca, -x_head, rs * sa)) * MM
    # be.bm_screw: head above z = 0, shank along -Z -> shank must point to +Y (toward the backplate)
    q = Vector((0, 0, -1)).rotation_difference(Vector((0, 1, 0)))
    ob.matrix_world = Matrix.Translation(pos) @ q.to_matrix().to_4x4()
    sharp(ob, 30.0)
    return ob


def locknut(name, ang, rs, C, M):
    """M3.5 nylon-insert locknut in its backplate pocket: hex x 4.0 .. 1.4, blue insert crown to x 0.1."""
    p = screw_at(ang, rs)
    body = make_obj(name, bm_cyl(3.0 / math.cos(math.pi / 6), p(1.4), p(4.0), 6), C, [M["zinc"]])
    ins = tmp_obj(bm_cyl(2.7, p(0.1), p(1.45), 24), [M["nyloc"]])
    boolean(body, [ins], "UNION", transfer=True)
    boolean(body, [tmp_obj(bm_cyl(1.6, p(-1.0), p(5.0), 24))], "DIFFERENCE")
    earclip(body)
    sharp(body, 30.0)
    return body


def combo_hardware(ckey, prop, S, C, M):
    """Washer + nut (Dubro) or washer + Tru-Turn spinner nut + 10-32 retaining bolt; Dubro cone screws."""
    tag = f"HW_{ckey}"
    hub_t = prop["hub_t"]
    y_w = -(S["bp_t"] + hub_t)
    out = [make_obj(f"{tag}_Arandela", washer_bm(y_w), C, [M["black_oxide"]])]
    y_n = y_w - WASHER_T
    if S["retainer"] == "bolt":
        x_nut_front = -y_n + NUT_H
        x_ext_end = S["L"] - S["nose_solid"] - 0.6
        out.append(prop_nut(f"{tag}_Tuerca_Spinner", y_n, C, M, ext=(x_ext_end - x_nut_front, 4.75)))
        bolt = cap_screw(f"{tag}_Tornillo_10-32", S["x_bolt_head"], 25.4, 4.83, 7.9, 4.8, 0.0, 0.0, C, M,
                         socket=5 / 32 * IN)
        out.append(bolt)
        S["bolt_engage_mm"] = round(x_ext_end - (S["x_bolt_head"] - 25.4), 1)
        S["nut_x"] = (round(-y_n, 2), round(x_nut_front, 2), round(x_ext_end, 2))
    else:
        out.append(prop_nut(f"{tag}_Tuerca", y_n, C, M))
        S["nut_x"] = (round(-y_n, 2), round(-y_n + NUT_H, 2))
        for i, sc in enumerate(S["screws"]):
            out.append(cap_screw(f"{tag}_Tornillo_M3.5x18_{i}", sc["x_head"], 18.0, 3.5, 6.0, 3.5, sc["ang"],
                                 S["screw_r"], C, M))
            out.append(locknut(f"{tag}_Tuerca_Nyloc_{i}", sc["ang"], S["screw_r"], C, M))
    return out


# ----------------------------------------------------------------------------- main
def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    M = materials()
    LIB = col("LIB_Helices")
    LIBS = col("LIB_Spinners")
    report = {"props": {}, "spinners": {}}
    props = {}
    for spec in G.PROPS:
        if ONLY and spec["key"] not in ONLY and not any(spec["key"] == COMBOS[c][0] for c in COMBOS if c in ONLY):
            continue
        C = col(f"HELICE_{spec['key']}", LIB)
        root = root_empty(f"ROOT_{spec['key']}", C)
        ob, loops, rows, info = build_prop(spec, C, M)
        parent_to([ob], root)
        props[spec["key"]] = ob
        R = spec["D"] * IN / 2
        report["props"][spec["key"]] = dict(
            label=spec["label"], blades=spec["blades"], D_in=spec["D"], P_in=spec["P"], hub_d=spec["hub_d"],
            hub_t=round(spec["hub_t"], 2), mass_spec=spec["mass_spec"], sg=spec["sg"], note=spec["note"],
            tc_scale=round(info.get("tc_scale", 1.0), 3), stations=len(loops),
            rows=[dict(r=round(e["r"], 2), c=round(e["c"], 2), beta=round(math.degrees(e["beta"]), 2),
                       tc=round(e["tc"], 4), q=round(e["q"], 2)) for e in rows],
            pe0_weight_g=round(info["pe0"]["weight_g"], 1) if "pe0" in info else None,
            pe0_volume_cm3=round(info["pe0"]["volume_in3"] * 16.387, 2) if "pe0" in info else None,
            tris=len(ob.data.polygons))
        print("built", spec["key"], len(ob.data.polygons), flush=True)
    for ck, (pk, skey) in COMBOS.items():
        if pk not in props or (ONLY and ck not in ONLY and skey not in ONLY):
            continue
        tag = skey.replace("/", "_")
        C = col(f"SPINNER_{tag}", LIBS)
        root = root_empty(f"ROOT_SPIN_{tag}", C)
        prop = props[pk]
        S = SPINNERS[skey]
        # the prop sits on the backplate for the cut (temporarily moved)
        prop.parent.location = (0, -S["bp_t"] * MM, 0)
        bpy.context.view_layer.update()
        parts, S = build_spinner(skey, prop, C, M)
        for o in parts:
            o["combo"], o["prop"], o["spinner"], o["bp_t"] = ck, pk, skey, S["bp_t"]
        CH = col(f"HERRAJES_{ck}_{tag}", LIBS)
        hw = combo_hardware(ck, prop, S, CH, M)
        prop.parent.location = (0, 0, 0)
        parent_to(parts, root)
        rh = root_empty(f"ROOT_HW_{ck}", CH)
        parent_to(hw, rh)
        report["spinners"][skey] = dict(label=S["label"], prop=pk, combo=ck, R=S["R"], L=round(S["L"], 2),
                                        bp_t=S["bp_t"], wall=S["wall"], retainer=S["retainer"],
                                        cut_r_lo=round(S.get("cut_r_lo", 0), 2), nut_x=S.get("nut_x"),
                                        bolt_engage_mm=S.get("bolt_engage_mm"),
                                        screws=S.get("screws"), tris=sum(len(o.data.polygons) for o in parts))
        print("built spinner", skey, flush=True)
    if SAVE:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(SAVE))
    if JSON_OUT:
        json.dump(report, open(JSON_OUT, "w"), indent=1, default=str)
    print("@@JSON@@" + json.dumps({k: len(v) for k, v in report.items()}), flush=True)


if __name__ == "__main__":
    main()
