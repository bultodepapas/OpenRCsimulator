"""Procedural .61-size two-stroke glow engine (side exhaust, rear-of-carb needle) for Blender 5.2+.

Modeled at real scale (1 unit = 1 m) from the reference photos. Brand lettering, cast
logos and the edition plaque are intentionally left off.

Axes: crankshaft along Y (prop end at -Y), cylinder up +Z, exhaust on -X, needle valve on +X.
Origin: crank axis / cylinder axis intersection.

The default carburetor ("os61") was fitted to the owner's photos of this exact SE engine: the photo
cameras (pose, focal length, principal point) were solved by bundle adjustment from crankcase
landmarks, carb features were triangulated, and every part was checked by overlaying renders
from those cameras on the photos (see CARB_OS61_P0 for the measured values, in mm).

Usage (headless, through the blender-skills runner):
  python run_in_blender.py build_engine.py -- --save //glow_engine_61.blend
      [--variant se|standard] [--carb os61|classic|modern] [--head gold|silver] [--no-muffler]
      [--throttle 0..1] [--carb-only]
Controls on the "Glow_Engine_61" empty (Object Properties > Custom Properties):
  crank_deg  crank angle after TDC, CCW seen from the front (keyframe 0 -> 360 to run the engine): the
             crankshaft turns with everything keyed to it (inner races, Woodruff key, hub, washer, nut), the piston
             follows the exact crank-slider law, the rod swings about the wrist pin, balls/cages turn at 0.4x.
  throttle   0..1: carb rotor (throttle barrel), end cap and arm turn 70 deg.
  cutaway    0 off, 1 = +X half removed (crank, rotary valve, intake, bearings, transfers),
             2 = rear half removed (rod, piston, ports, exhaust duct). Booleans switched by drivers.
  mech       JSON with the derived numbers (port heights, timing, rod ratio ...).

Internals (MECH_P0): chrome liner with Schnuerle ports (exhaust, two transfers, boost), ringed piston with
pinned ring, wrist pin + circlips, I-beam rod with bronze bushings, one-piece crankshaft with a front rotary
valve window into its hollow bore, D-shaped web with a tungsten counterweight, rear 15x28x7 and front 10x19x5
ball bearings (raceways, balls, cages), Woodruff-keyed serrated hub, separate front housing, cover plate with crank-chamber
boss, paper gaskets, head shim, combustion bowl + squish band, threaded glow plug, carb rotor / spray bar /
needle / fuel passages, hollow muffler with baffle. Every fastener is a threaded ISO 4762 M3 screw in a
tapped hole (clearance holes in the clamped part). tools/mech_check.py verifies it over a full revolution.
Inside Blender: open in the Text Editor and press Run Script.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

MM = 0.001
MARK = "@@JSON@@"

# ----------------------------------------------------------------------------- options
VARIANT = "se"            # "se" (Special Edition: gold heat-sink head, 7 fins) or "standard"
CARB = "os61"             # "os61" (the SE engine's carb, photo-fitted), "classic" or "modern"
INCLUDE_MUFFLER = True

VARIANTS = {  # measured from the reference photos (mm)
    # SE: 9 fins on a 2.62 mm pitch (fin brightness peaks in photos A and E), the lowest one cast on the case below the
    # z 37.5 joint; head face 57.8, gold head 21.2 mm radius up to the fin crests at 70.7
    "se": dict(head="gold", fins=9, fin_pitch=2.62, fin_z0=35.24, fin_t=1.0, fin_r=20.8, head_r=21.2, head_h=12.9,
               castellated=True, groove_depth=5.5, washer="nut"),
    "standard": dict(head="silver", fins=8, fin_pitch=2.55, fin_t=1.25, fin_r=20.5, head_r=20.75,
                     head_h=16.5, castellated=False, groove_depth=7.5, washer="hub",
                     side_needle=True),
}
FIT = {}  # per-part parameter overrides loaded with --params

CARB_PLACE = {"os61": (0.0, -37.6, 25.4), "classic": (0.0, -36.0, 25.0), "modern": (0.0, -36.0, 31.0)}
THROTTLE_REF = {"os61": 0.75}   # throttle value at which the parts are built (arm angle fitted to the photos)
PEDESTAL_Y = {"os61": -37.6, "classic": -36.0, "modern": -36.0}


def _args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    def val(flag, default):
        return a[a.index(flag) + 1] if flag in a else default
    o = {"save": val("--save", None), "variant": val("--variant", VARIANT), "carb": val("--carb", CARB),
         "muffler": INCLUDE_MUFFLER and "--no-muffler" not in a, "carb_only": "--carb-only" in a,
         "throttle": float(val("--throttle", -1.0)), "head": val("--head", None)}
    if o["throttle"] < 0:   # default = the opening the photos show (the os61 sits 3/4 open: spray bar in view)
        o["throttle"] = THROTTLE_REF.get(o["carb"], 0.0)
    if "--params" in a:  # measured-value overrides: {"head_se": {...}, "muffler": {...}}
        FIT.update(__import__("json").load(open(val("--params", ""))))
    o["V"] = dict(VARIANTS[o["variant"]])
    if o["head"]:
        o["V"]["head"] = o["head"]
    return o


# ----------------------------------------------------------------------------- math helpers
def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def S(sx, sy, sz):
    return Matrix.Diagonal((sx, sy, sz, 1.0))


def Rot(axis, deg):
    return Matrix.Rotation(math.radians(deg), 4, axis)


def along(p0, p1):
    """Matrix placing a local-Z primitive (centered) between p0 and p1, plus its length."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return T(*((p0 + p1) / 2)) @ q.to_matrix().to_4x4(), d.length


def hull2d(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def circle_pts(cx, cy, r, n=24):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


# ----------------------------------------------------------------------------- bmesh builders (mm)
def bm_box(lo, hi, r=0.0, axis=None, segs=4, bm=None):
    bm = bm or bmesh.new()
    c = [(a + b) / 2 for a, b in zip(lo, hi)]
    s = [b - a for a, b in zip(lo, hi)]
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=T(*c) @ S(*s))
    if r > 0:
        vs = set(res["verts"])
        edges = [e for e in bm.edges if e.verts[0] in vs]
        if axis is not None:
            ax = Vector(axis)
            edges = [e for e in edges if abs((e.verts[1].co - e.verts[0].co).normalized().dot(ax)) > 0.99]
        bmesh.ops.bevel(bm, geom=edges + list({v for e in edges for v in e.verts}), offset=r,
                        offset_type="OFFSET", segments=segs, profile=0.5, affect="EDGES",
                        clamp_overlap=True)
    return bm


def bm_cyl(r, p0, p1, segs=32, bm=None, r2=None):
    bm = bm or bmesh.new()
    m, length = along(p0, p1)
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=length, matrix=m)
    return bm


def bm_revolve(profile, segs=64, axis="Y", center=(0.0, 0.0), closed=False, phase=0.0):
    """Lathe a (radius, height) profile. Points with r=0 become poles."""
    bm = bmesh.new()
    angs = [phase + 2 * math.pi * i / segs for i in range(segs)]

    def P(r, h, a):
        c, s = r * math.cos(a), r * math.sin(a)
        if axis == "Y":
            return (center[0] + c, h, center[1] + s)
        if axis == "X":
            return (h, center[0] + c, center[1] + s)
        return (center[0] + c, center[1] + s, h)
    rings = []
    for r, h in profile:
        rings.append([bm.verts.new(P(0, h, 0))] if r < 1e-6 else [bm.verts.new(P(r, h, a)) for a in angs])
    n = len(rings)
    pairs = [(i, i + 1) for i in range(n - 1)] + ([(n - 1, 0)] if closed else [])
    for i, j in pairs:
        A, B = rings[i], rings[j]
        if len(A) == 1 and len(B) == 1:
            continue
        for k in range(segs):
            k2 = (k + 1) % segs
            if len(A) == 1:
                bm.faces.new((A[0], B[k], B[k2]))
            elif len(B) == 1:
                bm.faces.new((A[k], A[k2], B[0]))
            else:
                bm.faces.new((A[k], A[k2], B[k2], B[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def bm_prism(pts, w0, w1, mapf, bm=None):
    bm = bm or bmesh.new()
    bot = [bm.verts.new(mapf(u, v, w0)) for u, v in pts]
    top = [bm.verts.new(mapf(u, v, w1)) for u, v in pts]
    new = [bm.faces.new(bot[::-1]), bm.faces.new(top)]
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        new.append(bm.faces.new((bot[i], bot[j], top[j], top[i])))
    bmesh.ops.recalc_face_normals(bm, faces=new)
    return bm


def rrect(hx, hy, r, n=6):
    """Rounded rectangle outline (CCW), n segments per corner."""
    pts = []
    for cx, cy, a0 in ((hx - r, hy - r, 0), (-hx + r, hy - r, 90), (-hx + r, -hy + r, 180), (hx - r, -hy + r, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def bm_loft(levels, n=6, cx=0.0, cy=0.0):
    """Loft rounded rectangles [(z, hx, hy, r), ...] into a capped solid (cast fillets / skirts)."""
    bm = bmesh.new()
    rings = [[bm.verts.new((cx + x, cy + y, z)) for x, y in rrect(hx, hy, r, n)] for z, hx, hy, r in levels]
    m = len(rings[0])
    for A, B in zip(rings, rings[1:]):
        for k in range(m):
            k2 = (k + 1) % m
            bm.faces.new((A[k], A[k2], B[k2], B[k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def bm_thread(y0, y1, r_major, pitch, depth, segs=48, per_pitch=10, chamfer=0.9, x=0.0, z=0.0):
    """Helical V-thread along -Y from y0 to y1 (tip), capped, manifold."""
    bm = bmesh.new()
    L = abs(y1 - y0)
    n = max(2, int(L / pitch * per_pitch))
    r_minor = r_major - depth
    rows = []
    for i in range(n + 1):
        s = L * i / n
        y = y0 - s if y1 < y0 else y0 + s
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            u = (s / pitch - a / (2 * math.pi)) % 1.0
            f = max(0.0, min(1.0, 1.7 * (1 - abs(2 * u - 1)) - 0.35))
            r = r_minor + depth * f
            dt = L - s
            if dt < chamfer:
                r = min(r, r_minor - 0.25 + (r_major - r_minor + 0.25) * dt / chamfer)
            ring.append(bm.verts.new((x + r * math.cos(a), y, z + r * math.sin(a))))
        rows.append(ring)
    for i in range(n):
        A, B = rows[i], rows[i + 1]
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((A[k], A[k2], B[k2], B[k]))
    for ring, y in ((rows[0], y0), (rows[-1], y1)):
        c = bm.verts.new((x, y, z))
        for k in range(segs):
            bm.faces.new((ring[k], ring[(k + 1) % segs], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def bm_port(a_c, half, z0, z1, r_in, r_out, corner=1.0, r_ref=12.0, n=4):
    """Cylinder-wall window: rounded rectangle in (arc length at r_ref, z), extruded radially r_in..r_out.
    a_c/half in degrees, measured from +X toward +Y (seen from the top)."""
    hs, hz, zc = r_ref * math.radians(half), (z1 - z0) / 2, (z0 + z1) / 2
    cr = min(corner, hs * 0.9, hz * 0.9)
    pts = rrect(hs, hz, cr, n)
    dense = []
    for i, p in enumerate(pts):  # densify the straight edges so the wrap follows the cylinder
        q = pts[(i + 1) % len(pts)]
        k = max(1, int(math.hypot(q[0] - p[0], q[1] - p[1]) / 0.8))
        dense += [(p[0] + (q[0] - p[0]) * j / k, p[1] + (q[1] - p[1]) * j / k) for j in range(k)]

    def mapf(u, v, w):
        a = math.radians(a_c) + u / r_ref
        return (w * math.cos(a), w * math.sin(a), zc + v)
    bm = bm_prism(dense, r_in, r_out, mapf)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    return bm


def bm_hull(points):
    """Convex hull of a point cloud (mm) as a closed solid (port ducts, transfer connectors)."""
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in points]
    res = bmesh.ops.convex_hull(bm, input=vs)
    bmesh.ops.delete(bm, geom=list(set(res["geom_interior"] + res["geom_unused"])), context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def rrect_yz(x, cy, cz, hy, hz, r, n=5):
    return [(x, cy + u, cz + v) for u, v in rrect(hy, hz, r, n)]


def bm_torus(R, r, a0=0.0, a1=360.0, segs=32, rsegs=10):
    """Torus (or C-shaped arc of one) in the XY plane, axis Z: wire circlips."""
    bm = bmesh.new()
    full = abs(a1 - a0) >= 359.999
    n = segs if full else segs + 1
    rings = []
    for i in range(n):
        a = math.radians(a0 + (a1 - a0) * i / segs)
        rings.append([bm.verts.new(((R + r * math.cos(t)) * math.cos(a), (R + r * math.cos(t)) * math.sin(a),
                                    r * math.sin(t))) for t in (2 * math.pi * k / rsegs for k in range(rsegs))])
    pairs = [(i, (i + 1) % n) for i in range(n)] if full else [(i, i + 1) for i in range(n - 1)]
    for i, j in pairs:
        A, B = rings[i], rings[j]
        for k in range(rsegs):
            bm.faces.new((A[k], A[(k + 1) % rsegs], B[(k + 1) % rsegs], B[k]))
    if not full:
        bm.faces.new(rings[0][::-1])
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


# ----------------------------------------------------------------------------- mechanism parameters
# O.S. publishes bore/stroke for the 55AX (23.0 x 21.5) and 65AX (24.0 x 23.5); the 61 SF is taken as
# 24.0 x 22.0 mm = 9.95 cc. Everything below is derived from that and from the photo-fitted outside.
MECH_P0 = dict(
    bore=24.0, stroke=22.0, rod=40.4, pin_h=9.0,          # rod centres; wrist-pin axis to crown edge
    # crank axis height in the model frame: the front-housing nose, the drive hub and both cover screw patterns
    # are centred 4.4 mm below the frame origin in photos B and B2 (triangulated); the head, cylinder and case stay
    # where the photos put them, so the rod is 4.4 mm longer than the first estimate (40.4 mm, L/r 3.67)
    axis_z=-4.4,
    squish=0.45, gasket=0.25, dome=0.35, bowl_r=9.5, bowl_d=4.0,
    liner_ro=13.4, liner_fr=13.9, liner_ft=1.5, liner_bot=18.0,
    pis_clear=0.03, exh_overlap=0.7, relief_r=15.6, relief_x=-10.0,   # skirt relief clears the crank web
    ring_top=1.2, ring_w=1.0, ring_root=10.6, ring_gap=0.4, ring_gap_ang=125.0,
    pin_r=3.0, pin_len=20.0, boss_r=4.6, boss_in=3.3,
    crankpin_r=3.2, crankpin_bore=1.8, web_y=(-10.0, -3.3), crankpin_end=3.3, web_r=15.0, cw_r=15.0,
    web_side_r=15.0, web_boss_deg=25.0, web_side_deg=55.0, web_cw_deg=95.0,   # full round web (reference photos)
    web_pocket=(6.2, 13.8, 140.0, 3.0),  # pin-side lightening pocket in the front face: r_in, r_out, span deg, depth
    cw_insert=(6.0, 14.1, 110.0, 5.5),   # tungsten crescent: r_in, r_out, span deg, depth from the front face
    journal_r=7.5, valve_r=7.0, valve_clear=0.05, bore_r=4.0, shaft_r=5.0, nose_r=4.0,
    rod_w=3.0, shank_w=2.6, big_r=5.4, big_bore=4.0, small_r=5.0, small_bore=3.6,
    chamber_r=16.9, chamber_y=(-10.5, 4.0), rear_r=15.25, rear_z=-1.75, bp_boss=(12.5, 4.8),
    rear_brg=(15.0, 28.0, 7.0, -17.5, 9), front_brg=(10.0, 19.0, 5.0, -50.3, 8),  # d, D, B, front face y, balls
    exh=(180.0, 32.0), trans=(80.0, 24.0), boost=(0.0, 14.0),   # port centre / half-width (deg, from +X)
    exh_open=105.0, trans_open=119.0, boost_lag=0.3, exh_floor=1.0,
    intake_open=225.0, intake_close=50.0, ped_bore=4.0, win_len=8.0,
    boost_win=(22.0, -3.0, 5.0), boost_floor=22.0,   # piston-fed boost: skirt window half-width deg, local z0, z1
    head_screw_len=12.0,
)


def mech():
    K = dict(MECH_P0, **FIT.get("mech", {}))
    r, L, h, za = K["stroke"] / 2, K["rod"], K["pin_h"], K["axis_z"]

    def crown(th):     # absolute z of the crown edge (frame of the photo-fitted exterior)
        t = math.radians(th)
        return za + r * math.cos(t) + math.sqrt(L * L - (r * math.sin(t)) ** 2) + h
    K.update(r=r, za=za, crown=crown, zp0=za + r + L, zT=crown(0.0), zB=crown(180.0))
    K["z_exh"], K["z_tr"] = crown(K["exh_open"]), crown(K["trans_open"])
    K["z_boost"] = K["z_tr"] - K["boost_lag"]
    K["z_port0"], K["z_exh0"] = K["zB"] - 0.3, K["zB"] + K["exh_floor"]
    # crown-to-skirt on the exhaust side: the skirt must still close the exhaust port at TDC
    K.setdefault("pis_len", K["zT"] - (K["z_exh0"] - K["exh_overlap"]))
    K["z_button"] = K["zT"] + K["squish"]
    K["z_liner_top"] = K["z_button"] - K["gasket"]
    K["z_flange"] = K["z_liner_top"] - K["liner_ft"]
    # rotary valve: the window leads the crankpin so it opens intake_open and closes intake_close deg ATDC
    beta = math.degrees(math.asin(K["ped_bore"] / (K["valve_r"] + K["valve_clear"])))
    dur = (K["intake_close"] - K["intake_open"]) % 360.0
    K.update(beta=beta, win_half=dur / 2 - beta, win_center=(-(K["intake_open"] + dur / 2)) % 360.0)
    return K


def za_bm(bm, K=None):
    """Move crank-frame geometry (built about the axis at z = 0) onto the real crank axis."""
    bmesh.ops.translate(bm, vec=(0.0, 0.0, (K or mech())["za"]), verts=bm.verts[:])
    return bm


def za_ob(ob, K=None):
    """Move a finished crank-frame object (origin and all) onto the real crank axis."""
    ob.location.z += (K or mech())["za"] * MM
    return ob


def crank_pt(psi, rho):
    """(x, z) of a crank-frame point at psi deg from the crankpin, in the rotation sense (CCW seen from the front)."""
    p = math.radians(psi)
    return (-rho * math.sin(p), rho * math.cos(p))


# ----------------------------------------------------------------------------- objects
def make_obj(name, bm, col, mats=(), smooth=True):
    bmesh.ops.scale(bm, vec=(MM, MM, MM), verts=bm.verts[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    for m in mats:
        me.materials.append(m)
    if smooth:
        me.shade_smooth()
    return ob


def boolean(target, operands, op="UNION", transfer=False):
    """Exact boolean with a collection operand, baked through the depsgraph (no operators)."""
    sc = bpy.context.scene
    tmp = bpy.data.collections.new("TMP_Operands")
    sc.collection.children.link(tmp)
    for o in operands:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        tmp.objects.link(o)
    tmp.hide_render = True
    mod = target.modifiers.new("TMP_Bool", "BOOLEAN")
    mod.operation = op
    mod.operand_type = "COLLECTION"
    mod.collection = tmp
    mod.solver = "EXACT"
    if transfer:
        mod.material_mode = "TRANSFER"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(target.evaluated_get(dg), preserve_all_data_layers=True,
                                         depsgraph=dg)
    old = target.data
    target.modifiers.remove(mod)
    target.data = me
    me.name = target.name
    bpy.data.meshes.remove(old)
    for o in operands:
        d = o.data
        bpy.data.objects.remove(o)
        bpy.data.meshes.remove(d)
    bpy.data.collections.remove(tmp)
    cleanup(target)
    return target


def sliver_fix(bm, alt=1.2e-5, short=1.2e-4, iters=20):
    """Remove sliver triangles (altitude under alt, m): collapse their shortest edge when it is short, else flip
    their longest edge when its two faces are coplanar and the flip folds nothing."""
    for _ in range(iters):
        coll, rot = set(), set()
        for f in bm.faces:
            if len(f.verts) != 3:
                continue
            es = sorted(f.edges, key=lambda e: e.calc_length())
            L = es[-1].calc_length()
            if L <= 0.0 or 2.0 * f.calc_area() / L >= alt:
                continue
            if es[0].calc_length() < short:
                coll.add(es[0])
            elif len(es[-1].link_faces) == 2 and \
                    abs(es[-1].link_faces[0].normal.dot(es[-1].link_faces[1].normal)) > 0.9995 and _flip_ok(es[-1]):
                rot.add(es[-1])
        if not coll and not rot:
            break
        if coll:
            bmesh.ops.collapse(bm, edges=[e for e in coll if e.is_valid], uvs=True)
        rot = [e for e in rot if e.is_valid and len(e.link_faces) == 2]
        if rot:
            bmesh.ops.rotate_edges(bm, edges=rot, use_ccw=False)
    # a collapse can fold a sliver pocket flat into two coincident faces: drop both copies
    seen = {}
    for f in bm.faces:
        seen.setdefault(tuple(sorted(v.index for v in f.verts)), []).append(f)
    dup = [f for fs in seen.values() if len(fs) > 1 for f in fs]
    if dup:
        bmesh.ops.delete(bm, geom=dup, context="FACES_ONLY")
    bmesh.ops.dissolve_degenerate(bm, dist=1e-7, edges=bm.edges[:])
    lose = [e for e in bm.edges if not e.link_faces]
    if lose:
        bmesh.ops.delete(bm, geom=lose, context="EDGES")
    hole = [e for e in bm.edges if e.is_boundary]   # a dropped pair that was also needed: close it again
    if hole:
        bmesh.ops.holes_fill(bm, edges=hole, sides=12)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def _flip_ok(e):
    """True if rotating edge e keeps both new triangles unfolded: the quad's diagonals cross in its plane."""
    f1, f2 = e.link_faces
    if len(f1.verts) != 3 or len(f2.verts) != 3:
        return False
    a, b = e.verts
    c = next(v for v in f1.verts if v not in (a, b))
    d = next(v for v in f2.verts if v not in (a, b))
    n = (f1.normal + f2.normal)
    if n.length < 1e-9:
        return False
    n.normalize()
    u = (b.co - a.co)
    if u.length < 1e-12:
        return False
    u = (u - n * n.dot(u)).normalized()
    w = n.cross(u)
    p2 = [Vector(((v.co - a.co).dot(u), (v.co - a.co).dot(w))) for v in (a, b, c, d)]
    from mathutils.geometry import intersect_line_line_2d
    x = intersect_line_line_2d(p2[0], p2[1], p2[2], p2[3])
    return x is not None and (x - p2[0]).length > 1e-9 and (x - p2[1]).length > 1e-9


def final_clean(ob):
    """Sliver removal after all booleans (QA thresholds: faces < 1e-4 mm^2, vertices closer than 0.01 mm)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1.2e-5)
    for _ in range(4):
        bad = [f for f in bm.faces if f.is_valid and f.calc_area() < 1.5e-10]
        if not bad:
            break
        needles, caps = set(), set()
        for f in bad:
            es = sorted(f.edges, key=lambda e: e.calc_length())
            if es[0].calc_length() < 0.05 * es[-1].calc_length():
                needles.add(es[0])
            elif len(es[-1].link_faces) == 2 and _flip_ok(es[-1]):
                caps.add(es[-1])
        if needles:
            bmesh.ops.collapse(bm, edges=list(needles), uvs=True)
        caps = [e for e in caps if e.is_valid]
        if caps:
            bmesh.ops.rotate_edges(bm, edges=caps, use_ccw=False)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-7)
    lv = [v for v in bm.verts if not v.link_faces]
    if lv:
        bmesh.ops.delete(bm, geom=lv, context="VERTS")
    # the liner's long, notched OD facets (a 96-gon revolve with the port windows cut into them) are triangulated here
    # by ear clipping: the default ngon triangulation of exporters and checkers folds one of them over itself
    big = [f for f in bm.faces if len(f.verts) > 12] if ob.name == "ENG_Liner" else []
    if big:
        bmesh.ops.triangulate(bm, faces=big, quad_method="BEAUTY", ngon_method="EAR_CLIP")
    if ob.name == "ENG_Head" and all(len(f.verts) == 3 for f in bm.faces):
        sliver_fix(bm, iters=30)    # the fine height-field head: no slivers left by the cap rotations above
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()


def cleanup(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-7)
    bm.verts.index_update()                 # zero-volume double faces (boolean slivers): drop both sides
    seen, dup = {}, set()
    for f in bm.faces:
        k = frozenset(v.index for v in f.verts)
        if k in seen:
            dup.update((f, seen[k]))
        else:
            seen[k] = f
    if dup:
        bmesh.ops.delete(bm, geom=list(dup), context="FACES_ONLY")
    loose = [e for e in bm.edges if not e.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="EDGES")
    lv = [v for v in bm.verts if not v.link_faces]
    if lv:
        bmesh.ops.delete(bm, geom=lv, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    me = ob.data  # drop the empty slots the operands leave behind, remap face indices
    mats = list(me.materials)
    if any(m is None for m in mats):
        keep = [i for i, m in enumerate(mats) if m is not None]
        remap = {old: new for new, old in enumerate(keep)}
        idx = [remap.get(p.material_index, 0) for p in me.polygons]
        me.materials.clear()
        for i in keep:
            me.materials.append(mats[i])
        me.polygons.foreach_set("material_index", idx)
    me.shade_smooth()


def tmp_obj(bm, mats=()):
    return make_obj("TMP_part", bm, bpy.context.scene.collection, mats, smooth=False)


# ----------------------------------------------------------------------------- materials
def _principled(name, base, metal, rough, rough_var=0.06, noise_scale=180.0, bump=0.0,
                bump_scale=1500.0, coat=0.0, aniso=0.0, grime=0.0, speckle=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*base, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if coat:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.05
    if aniso:
        bsdf.inputs["Anisotropic"].default_value = aniso
    mat.diffuse_color = (*base, 1.0)
    mat.roughness = rough
    mat.metallic = metal
    tc = nt.nodes.new("ShaderNodeTexCoord")
    tc.location = (-900, 0)
    if rough_var > 0:  # roughness carries the realism: break it up
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.location = (-650, 200)
        nz.inputs["Scale"].default_value = noise_scale
        nz.inputs["Detail"].default_value = 6.0
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.location = (-400, 200)
        mr.inputs["From Min"].default_value = 0.3
        mr.inputs["From Max"].default_value = 0.7
        mr.inputs["To Min"].default_value = max(0.0, rough - rough_var)
        mr.inputs["To Max"].default_value = min(1.0, rough + rough_var)
        nt.links.new(nz.outputs["Fac"], mr.inputs["Value"])
        nt.links.new(mr.outputs["Result"], bsdf.inputs["Roughness"])
    if bump > 0:  # cast / bead-blast micro texture
        nb = nt.nodes.new("ShaderNodeTexNoise")
        nb.location = (-650, -200)
        nb.inputs["Scale"].default_value = bump_scale
        nb.inputs["Detail"].default_value = 2.0
        nt.links.new(tc.outputs["Object"], nb.inputs["Vector"])
        bp = nt.nodes.new("ShaderNodeBump")
        bp.location = (-400, -200)
        bp.inputs["Strength"].default_value = bump
        bp.inputs["Distance"].default_value = 0.00005
        nt.links.new(nb.outputs["Fac"], bp.inputs["Height"])
        nt.links.new(bp.outputs["Normal"], bsdf.inputs["Normal"])
    if grime > 0:  # dirt settles in crevices: darker, rougher, dielectric (Cycles AO node as the mask)
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.location = (-900, -450)
        ao.samples, ao.inside, ao.only_local = 8, False, True
        ao.inputs["Distance"].default_value = 0.0025
        inv = nt.nodes.new("ShaderNodeMapRange")
        inv.location = (-650, -450)
        inv.inputs["From Min"].default_value, inv.inputs["From Max"].default_value = 0.35, 1.0
        inv.inputs["To Min"].default_value, inv.inputs["To Max"].default_value = grime, 0.0
        nt.links.new(ao.outputs["AO"], inv.inputs["Value"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.location = (-400, -450)
        mix.data_type = "RGBA"
        nt.links.new(inv.outputs["Result"], mix.inputs[0])
        mix.inputs[6].default_value = (*base, 1.0)
        mix.inputs[7].default_value = (0.07, 0.065, 0.06, 1.0)
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        met = nt.nodes.new("ShaderNodeMapRange")
        met.location = (-400, -650)
        met.inputs["To Min"].default_value, met.inputs["To Max"].default_value = metal, 0.15
        nt.links.new(inv.outputs["Result"], met.inputs["Value"])
        nt.links.new(met.outputs["Result"], bsdf.inputs["Metallic"])
    if speckle > 0:  # cast-surface pits: tiny dark dielectric dots (Voronoi distance mask)
        vo = nt.nodes.new("ShaderNodeTexVoronoi")
        vo.location = (-900, -900)
        vo.inputs["Scale"].default_value = 2600.0
        vo.inputs["Randomness"].default_value = 1.0
        nt.links.new(tc.outputs["Object"], vo.inputs["Vector"])
        sp = nt.nodes.new("ShaderNodeMapRange")
        sp.location = (-650, -900)
        sp.inputs["From Min"].default_value, sp.inputs["From Max"].default_value = 0.0, 0.18
        sp.inputs["To Min"].default_value, sp.inputs["To Max"].default_value = speckle, 0.0
        nt.links.new(vo.outputs["Distance"], sp.inputs["Value"])
        src = bsdf.inputs["Base Color"].links[0].from_socket if bsdf.inputs["Base Color"].is_linked else None
        mx = nt.nodes.new("ShaderNodeMix")
        mx.location = (-200, -900)
        mx.data_type = "RGBA"
        nt.links.new(sp.outputs["Result"], mx.inputs[0])
        if src is not None:
            nt.links.new(src, mx.inputs[6])
        else:
            mx.inputs[6].default_value = (*base, 1.0)
        mx.inputs[7].default_value = (0.05, 0.048, 0.045, 1.0)
        nt.links.new(mx.outputs[2], bsdf.inputs["Base Color"])
    return mat


def _node(nt, kind, loc, **inputs):
    n = nt.nodes.new(kind)
    n.location = loc
    for k, v in inputs.items():
        n.inputs[k].default_value = v
    return n


def _mix(nt, fac, a, b, loc):
    """RGBA mix node; fac / a / b may be sockets or constants."""
    m = nt.nodes.new("ShaderNodeMix")
    m.location = loc
    m.data_type = "RGBA"
    for slot, val in ((0, fac), (6, a), (7, b)):
        if hasattr(val, "node"):
            nt.links.new(val, m.inputs[slot])
        else:
            m.inputs[slot].default_value = val
    return m.outputs[2]


def _mixf(nt, fac, a, b, loc):
    """FLOAT mix node (roughness, metallic)."""
    m = nt.nodes.new("ShaderNodeMix")
    m.location = loc
    m.data_type = "FLOAT"
    for slot, val in ((0, fac), (2, a), (3, b)):
        if hasattr(val, "node"):
            nt.links.new(val, m.inputs[slot])
        else:
            m.inputs[slot].default_value = val
    return m.outputs[0]


def _maprange(nt, src, fmin, fmax, tmin, tmax, loc, clamp=True):
    m = nt.nodes.new("ShaderNodeMapRange")
    m.location = loc
    m.clamp = clamp
    m.inputs["From Min"].default_value, m.inputs["From Max"].default_value = fmin, fmax
    m.inputs["To Min"].default_value, m.inputs["To Max"].default_value = tmin, tmax
    nt.links.new(src, m.inputs["Value"])
    return m.outputs["Result"]


def _math(nt, op, a, b, loc):
    m = nt.nodes.new("ShaderNodeMath")
    m.location = loc
    m.operation = op
    for i, val in enumerate((a, b)):
        if hasattr(val, "node"):
            nt.links.new(val, m.inputs[i])
        else:
            m.inputs[i].default_value = val
    return m.outputs[0]


def _weathered(name, base, metal, rough, patina=(0.46, 0.44, 0.39), patina_amt=0.35, grime=(0.15, 0.12, 0.085),
               grime_amt=0.7, rust=(0.22, 0.10, 0.045), rust_amt=0.6, pits=0.6, grain=0.16, peel=0.06,
               edge=None, soot_y=None, soot=(0.07, 0.055, 0.042), mottle=0.28, stain=0.0, stain_col=(0.17, 0.145, 0.11),
               pit_scale=2600.0, pit_r=0.18, pit_col=(0.05, 0.048, 0.045), pit_mask=0.0, top_wear=None, spec_tint=None):
    """Aged cast / anodized metal, all procedural in object space (no UV needed; baked for export):
    mottled patina (low-frequency noise), dirt and oil in crevices (AO), clustered oxide specks (Voronoi in a
    noise mask), casting pits, sand-cast grain + orange-peel bump, optional bright worn edges (inside AO) and
    an optional soot gradient along object Y (muffler tail)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nt = mat.node_tree
    for n in [n for n in nt.nodes if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL")]:
        nt.nodes.remove(n)
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    mat.diffuse_color, mat.roughness, mat.metallic = (*base, 1.0), rough, metal
    tc = _node(nt, "ShaderNodeTexCoord", (-1800, 0))
    obj = tc.outputs["Object"]
    n1 = _node(nt, "ShaderNodeTexNoise", (-1550, 300), Scale=28.0, Detail=5.0, Roughness=0.55)
    nt.links.new(obj, n1.inputs["Vector"])
    pf = _maprange(nt, n1.outputs["Fac"], 0.38, 0.66, 0.0, patina_amt, (-1300, 300))
    col = _mix(nt, pf, (*base, 1.0), (*patina, 1.0), (-1100, 300))
    if mottle:   # large, soft light/dark clouds (handling, heat and cleaning history) as seen on the castings
        nm = _node(nt, "ShaderNodeTexNoise", (-1550, 1100), Scale=7.0, Detail=3.0, Roughness=0.5)
        nt.links.new(obj, nm.inputs["Vector"])
        mm_ = nt.nodes.new("ShaderNodeMix")
        mm_.location, mm_.data_type, mm_.blend_type = (-1000, 450), "RGBA", "MULTIPLY"
        nt.links.new(_maprange(nt, nm.outputs["Fac"], 0.36, 0.64, 0.0, mottle, (-1300, 1100)), mm_.inputs[0])
        nt.links.new(col, mm_.inputs[6])
        mm_.inputs[7].default_value = (0.55, 0.53, 0.50, 1.0)
        col = mm_.outputs[2]
    ao = _node(nt, "ShaderNodeAmbientOcclusion", (-1550, -50), Distance=0.003)
    ao.samples, ao.only_local = 8, True
    gf = _maprange(nt, ao.outputs["AO"], 0.35, 1.0, grime_amt, 0.0, (-1300, -50))
    col = _mix(nt, gf, col, (*grime, 1.0), (-900, 200))
    vo = _node(nt, "ShaderNodeTexVoronoi", (-1550, -350), Scale=700.0, Randomness=1.0)
    nt.links.new(obj, vo.inputs["Vector"])
    n2 = _node(nt, "ShaderNodeTexNoise", (-1550, -600), Scale=55.0, Detail=3.0)
    nt.links.new(obj, n2.inputs["Vector"])
    spot = _maprange(nt, vo.outputs["Distance"], 0.0, 0.16, 1.0, 0.0, (-1300, -350))
    patch = _maprange(nt, n2.outputs["Fac"], 0.56, 0.68, 0.0, rust_amt, (-1300, -600))
    rf = _math(nt, "MULTIPLY", spot, patch, (-1100, -450))
    col = _mix(nt, rf, col, (*rust, 1.0), (-700, 100))
    vp = _node(nt, "ShaderNodeTexVoronoi", (-1550, -850), Scale=pit_scale, Randomness=1.0)
    nt.links.new(obj, vp.inputs["Vector"])
    pit = _maprange(nt, vp.outputs["Distance"], 0.0, pit_r, pits, 0.0, (-1300, -850))
    if pit_mask:   # clustered, not uniform: a noise mask thins the specks out in patches
        npm = _node(nt, "ShaderNodeTexNoise", (-1550, -1350), Scale=120.0, Detail=3.0, Roughness=0.6)
        nt.links.new(obj, npm.inputs["Vector"])
        pit = _math(nt, "MULTIPLY", pit, _maprange(nt, npm.outputs["Fac"], 0.5 - pit_mask * 0.2, 0.5 + pit_mask * 0.2,
                                                   0.15, 1.3, (-1300, -1350)), (-1100, -900))
    col = _mix(nt, pit, col, (*pit_col, 1.0), (-500, 0))
    dirt = _math(nt, "ADD", gf, rf, (-900, -250))
    if stain:    # old fuel / oil stains: irregular dark blotches of a few mm, as on the owner's engine
        ns = _node(nt, "ShaderNodeTexNoise", (-1550, -1100), Scale=260.0, Detail=4.0, Roughness=0.62)
        nt.links.new(obj, ns.inputs["Vector"])
        sm = _maprange(nt, ns.outputs["Fac"], 0.585, 0.70, 0.0, stain, (-1300, -1100))
        col = _mix(nt, sm, col, (*stain_col, 1.0), (-450, -150))
        dirt = _math(nt, "ADD", dirt, sm, (-800, -300))
    if soot_y is not None:   # muffler: soot and oil darken the rear half toward the outlet
        sep = _node(nt, "ShaderNodeSeparateXYZ", (-1550, 600))
        nt.links.new(obj, sep.inputs["Vector"])
        sf = _maprange(nt, sep.outputs["Y"], soot_y[0], soot_y[1], 0.0, soot_y[2], (-1300, 600))
        sfn = _math(nt, "MULTIPLY", sf, _maprange(nt, n1.outputs["Fac"], 0.3, 0.7, 0.6, 1.2, (-1300, 800)), (-1100, 650))
        col = _mix(nt, sfn, col, (*soot, 1.0), (-300, 300))
        dirt = _math(nt, "ADD", dirt, sfn, (-700, -250))
    met = _maprange(nt, dirt, 0.0, 0.9, metal, 0.15 if metal > 0.5 else metal, (-500, -250))
    rgh = _maprange(nt, dirt, 0.0, 0.9, rough, min(1.0, rough + 0.3), (-500, -400))
    rgh = _math(nt, "ADD", rgh, _maprange(nt, n1.outputs["Fac"], 0.3, 0.7, -0.06, 0.08, (-700, -500)), (-300, -450))
    if edge is not None:     # worn bright edges: little occlusion seen from inside the solid = a convex edge
        aoi = _node(nt, "ShaderNodeAmbientOcclusion", (-1550, 900), Distance=0.0009)
        aoi.samples, aoi.inside, aoi.only_local = 8, True, True
        ef = _maprange(nt, aoi.outputs["AO"], 0.55, 0.92, edge[1], 0.0, (-1300, 900))
        col = _mix(nt, ef, col, (*edge[0], 1.0), (-100, 300))
        rgh = _mixf(nt, ef, rgh, edge[2], (-100, -450))
        met = _mixf(nt, ef, met, 1.0, (-100, -250))
    if top_wear is not None:  # handled / polished crests: the dye worn off the highest surfaces
        # (a band of Generated Z, 0..1 over the part's own bounds: independent of origin and placement)
        tz0, tz1, tcol, tamt, trgh = top_wear
        sp = _node(nt, "ShaderNodeSeparateXYZ", (-1550, 1300))
        nt.links.new(tc.outputs["Generated"], sp.inputs["Vector"])
        tw = _maprange(nt, sp.outputs["Z"], tz0, tz1, 0.0, tamt, (-1300, 1300))
        tw = _math(nt, "MULTIPLY", tw, _maprange(nt, n1.outputs["Fac"], 0.32, 0.68, 0.35, 1.25, (-1300, 1450)),
                   (-1100, 1350))
        col = _mix(nt, tw, col, (*tcol, 1.0), (0, 350))
        rgh = _mixf(nt, tw, rgh, trgh, (0, -450))
    if spec_tint is not None and "Specular Tint" in bsdf.inputs:   # coloured grazing reflections (F82 tint)
        bsdf.inputs["Specular Tint"].default_value = (*spec_tint, 1.0)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(met, bsdf.inputs["Metallic"])
    nt.links.new(rgh, bsdf.inputs["Roughness"])
    ng = _node(nt, "ShaderNodeTexNoise", (-900, -900), Scale=2200.0, Detail=2.0)
    nt.links.new(obj, ng.inputs["Vector"])
    b1 = _node(nt, "ShaderNodeBump", (-500, -900), Strength=grain, Distance=0.00005)
    nt.links.new(ng.outputs["Fac"], b1.inputs["Height"])
    np_ = _node(nt, "ShaderNodeTexNoise", (-900, -1150), Scale=480.0, Detail=2.0)
    nt.links.new(obj, np_.inputs["Vector"])
    b2 = _node(nt, "ShaderNodeBump", (-300, -1000), Strength=peel, Distance=0.0001)
    nt.links.new(np_.outputs["Fac"], b2.inputs["Height"])
    nt.links.new(b1.outputs["Normal"], b2.inputs["Normal"])
    nt.links.new(b2.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def build_materials():
    # Metals: base color = measured F0 (linear), metallic 1.  Dielectrics: metallic 0.
    return {
        # aged castings, as photographed: warm mottled patina, oily dirt in the corners, clustered oxide specks
        "cast": _weathered("M_Alu_Cast", (0.78, 0.755, 0.69), 1.0, 0.46, patina_amt=0.5, grime_amt=0.85, rust_amt=0.8,
                           mottle=0.4, stain=0.55),
        "muf_cast": _weathered("M_Alu_Cast_Muffler", (0.73, 0.71, 0.65), 1.0, 0.48, patina_amt=0.45, rust_amt=0.45, stain=0.6,
                               mottle=0.4,
                               soot_y=(0.010, 0.075, 0.55)),
        # carburettor body casting: greyer and duller than the crankcase in every photo
        "carb_body": _weathered("M_Alu_Carb_Body", (0.57, 0.565, 0.545), 1.0, 0.47, patina=(0.46, 0.45, 0.42),
                                patina_amt=0.4, grime_amt=0.75, rust_amt=0.4, pits=0.4, grain=0.12, peel=0.05, mottle=0.3, stain=0.5,
                                edge=((0.85, 0.85, 0.84), 0.45, 0.25)),
        "satin": _principled("M_Alu_Satin", (0.88, 0.885, 0.89), 1.0, 0.30, 0.04, 80, bump=0.03),
        "polished": _principled("M_Alu_Polished", (0.913, 0.922, 0.924), 1.0, 0.10, 0.03, 300),
        # gold anodizing as on the owner's engine (photos E, Ac): greenish brass, fairly glossy, peppered with dark
        # pits, olive-brown grime in the slot bottoms, the dye worn to pale bare metal on the crests and crescents
        "gold": _weathered("M_Head_GoldAnodized", (0.58, 0.49, 0.18), 1.0, 0.33, patina=(0.40, 0.36, 0.16), patina_amt=0.45,
                           grime=(0.12, 0.085, 0.035), grime_amt=0.85, rust=(0.22, 0.17, 0.07), rust_amt=0.30, pits=0.9,
                           pit_scale=2000.0, pit_r=0.22, pit_col=(0.07, 0.06, 0.035), pit_mask=1.0,
                           grain=0.12, peel=0.04, edge=((0.90, 0.82, 0.55), 0.70, 0.20), mottle=0.22,
                           stain=0.12, stain_col=(0.15, 0.12, 0.05), spec_tint=(0.80, 0.68, 0.32),
                           top_wear=(0.912, 0.99, (0.86, 0.74, 0.40), 0.55, 0.20)),   # z 69.45-70.6 of 56.45-70.7
        "copper": _principled("M_Copper", (0.955, 0.638, 0.538), 1.0, 0.30, 0.05, 400),
        "silver": _weathered("M_Head_Silver", (0.80, 0.80, 0.79), 1.0, 0.40, patina=(0.58, 0.57, 0.55), patina_amt=0.25,
                             rust_amt=0.2, pits=0.4, grain=0.07, peel=0.03, edge=((0.95, 0.95, 0.95), 0.7, 0.15)),
        "steel": _principled("M_Steel", (0.56, 0.57, 0.58), 1.0, 0.30, 0.05, 400),
        "black": _weathered("M_Black_Oxide", (0.035, 0.035, 0.037), 0.6, 0.38, patina=(0.05, 0.05, 0.05), patina_amt=0.2,
                            grime=(0.02, 0.02, 0.02), grime_amt=0.3, rust=(0.12, 0.06, 0.03), rust_amt=0.2, pits=0.0,
                            grain=0.05, peel=0.02, edge=((0.42, 0.42, 0.43), 0.6, 0.25)),
        "brass": _principled("M_Brass", (0.91, 0.778, 0.423), 1.0, 0.25, 0.05, 400),
        "nickel": _principled("M_Nickel", (0.66, 0.609, 0.526), 1.0, 0.22, 0.04, 400),
        "plastic_black": _principled("M_Plastic_Black", (0.025, 0.025, 0.025), 0.0, 0.45, 0.08, 300),
        "plastic_beige": _principled("M_Plastic_Beige", (0.70, 0.60, 0.43), 0.0, 0.50, 0.06, 300),
        "soot": _principled("M_Port_Soot", (0.02, 0.019, 0.018), 0.0, 0.70, 0.08, 300),
        "chrome": _principled("M_Chrome", (0.55, 0.556, 0.554), 1.0, 0.07, 0.02, 400),
        "rubber": _principled("M_Rubber_Olive", (0.20, 0.19, 0.11), 0.0, 0.60, 0.06, 300),
        "brass_dull": _principled("M_Olive_Anodized", (0.55, 0.52, 0.33), 1.0, 0.35, 0.05, 300),
        "rust": _principled("M_Rust", (0.075, 0.045, 0.028), 0.0, 0.80, 0.10, 500, bump=0.1, bump_scale=1800.0),
        "oil": _principled("M_Oil_Grime", (0.045, 0.038, 0.03), 0.25, 0.42, 0.12, 260, bump=0.05),
        # internals
        "piston": _principled("M_Piston_Alu", (0.86, 0.865, 0.87), 1.0, 0.28, 0.05, 260, bump=0.02),
        "bronze": _principled("M_Bronze", (0.80, 0.55, 0.32), 1.0, 0.30, 0.05, 400),
        "tungsten": _principled("M_Tungsten", (0.50, 0.49, 0.47), 1.0, 0.35, 0.05, 400),
        "crank": _principled("M_Steel_Ground", (0.58, 0.585, 0.59), 1.0, 0.22, 0.04, 500),
        "gasket": _principled("M_Gasket", (0.085, 0.07, 0.055), 0.0, 0.85, 0.08, 300),
        "plastic_white": _principled("M_Plastic_White", (0.86, 0.855, 0.83), 0.0, 0.32, 0.05, 300),
    }


# ----------------------------------------------------------------------------- parts
def build_crankcase(col, M, carb="classic", se_plaque=False, V=None):
    K = mech()
    case_fins = [(z0, z1) for z0, z1 in fin_levels(V) if z0 < CASE_JOINT_Z - 1e-6] if V else []
    za = K["za"]
    # main case: rounded box around the crank (all edges R7); bottom 1.2 mm lower than the first fit (photos B, B2, D)
    # the box runs past both joints (front y -24.5, rear y 23.25) so the case sides reach them at full width, flush
    # with the front-housing flange and the cover (photos A, B: hairline joints); its front is cut flat at y -28.75 and
    # the flange slab below (flat face, R5.5 corners) carries the four front screws
    body = make_obj("ENG_Crankcase", bm_box((-19, -31.5, -22.2), (19, 30.5, 13.0), r=7, segs=6), col,
                    [M["cast"]])
    boolean(body, [tmp_obj(bm_box((-80, -150, -80), (80, -28.75, 80)))], "DIFFERENCE")
    ops = []
    # front / rear shoulder lobes (upper screw bosses) and the filleted skirt of the cylinder casting
    ops.append(tmp_obj(bm_box((-18.5, 13.5, 6.0), (18.5, 23.5, 17.8), r=4.8, segs=5)))
    ops.append(tmp_obj(bm_box((-18.5, -25.5, 6.0), (18.5, -15.5, 17.8), r=4.8, segs=5)))
    ops.append(tmp_obj(bm_loft([(7.0, 17.9, 20.6, 8.0), (12.0, 17.3, 19.8, 8.4), (15.5, 16.4, 18.8, 8.7),
                                (19.0, 15.85, 18.25, 8.9), (24.0, 15.6, 18.05, 9.0), (30.0, 15.5, 18.0, 9.0)], 6)))
    # cylinder jacket (rises into the bottom fin)
    ops.append(tmp_obj(bm_box((-15.5, -18, 8), (15.5, 18, 38.1), r=9, axis=(0, 0, 1), segs=6)))
    # beam mounting lugs
    for sx in (-1, 1):
        lo, hi = (17, 29.5) if sx > 0 else (-29.5, -17)
        ops.append(tmp_obj(bm_box((lo, -18, -6.7), (hi, 19, 0.3), r=1.2, segs=2)))
    # tapered panel on the +X side of the jacket (blank: no lettering) with rounded edges ...
    ptop = min(38.3, case_fins[0][0] + 0.3) if case_fins else 38.3   # it ends under the lowest fin
    pw = 4.2 + 2.7 * (ptop - 13.0) / 25.3
    bm = bm_prism([(-pw, ptop), (-4.2, 13.0), (4.2, 13.0), (pw, ptop)], 0, 17.5, lambda u, v, w: (w, u, v))
    edges = [e for e in bm.edges if all(abs(v.co.x - 17.5) < 1e-4 for v in e.verts)]
    bmesh.ops.bevel(bm, geom=edges + list({v for e in edges for v in e.verts}), offset=0.8, offset_type="OFFSET",
                    segments=2, profile=0.5, affect="EDGES", clamp_overlap=True)
    ops.append(tmp_obj(bm))
    # ... and the thin stem rib that runs from the panel down to the lug
    ops.append(tmp_obj(bm_box((0, -1.1, -0.2), (19.9, 1.1, 14.0), r=0.6, segs=2)))
    # exhaust boss + flange (-X)
    ops.append(tmp_obj(bm_box((-19, -15, 22), (-8, 19, 38.0), r=4, axis=(1, 0, 0), segs=4)))
    ops.append(tmp_obj(bm_box((-22.5, -19, 27.7), (-12, 23, 38.0), r=5.0, axis=(1, 0, 0), segs=6)))
    # front housing, measured in photos B and B2: 4.3 mm flange carrying a 30.4 x 28 screw square centred on the
    # crank axis, a round body (r 14.6) to the step at y -45.3, the bearing nose (r 12.6) to y -50.5, and the
    # pointed side rib on the axis line
    ops.append(tmp_obj(bm_box((-18.98, -28.8, -22.18), (18.98, -24.4, 12.98), r=5.5, axis=(0, 1, 0), segs=6)))
    ops.append(tmp_obj(za_bm(bm_revolve([(0, -24), (14.6, -24), (14.6, -44.7), (14.3, -45.15), (12.6, -45.4),
                                         (12.6, -50.0), (12.2, -50.5), (0, -50.5)], 96, "Y"), K)))
    ops.append(tmp_obj(za_bm(bm_prism([(-28.8, -1.4), (-44.8, -0.25), (-44.8, 0.25), (-28.8, 1.4)], -15.9, 15.9,
                                      lambda u, v, w: (w, u, v)), K)))
    # raised plaques on the lug faces; on the SE the +X one is the obround "SPECIAL EDITION" frame (ENG_Letter_*)
    for sx in ((-1,) if se_plaque else (-1, 1)):
        lo, hi = (29.2, 30.25) if sx > 0 else (-30.25, -29.2)
        ops.append(tmp_obj(bm_box((lo, -14.5, -5.45), (hi, 16.5, -0.95), r=2.15, axis=(1, 0, 0), segs=6)))
    # casting parting line down the front of the cylinder jacket (it carries on over the fins), photo E
    ops.append(tmp_obj(bm_box((-0.22, -18.14, 21.0), (0.22, -17.7, 37.45), r=0.1, segs=2)))
    # screw-boss pills on both case sides (upper and lower, front and rear)
    for sx in (-1, 1):
        x0, x1 = (16.0, 19.9) if sx > 0 else (-19.9, -16.0)
        for (y0, y1), zz, xs_ in (((14.6, 23.2), [z for _, z in SCREW_XZ[::2]], (x0, x1)),
                                  ((-25.2, -16.6), [z for _, z in FRONT_SCREW_XZ[::2]],
                                   (17.0, 20.2) if sx > 0 else (-20.2, -17.0))):   # front: clear of the M3 holes at x 15.2
            for zc_ in zz:
                ops.append(tmp_obj(bm_box((xs_[0], y0, zc_ - 2.0), (xs_[1], y1, zc_ + 4.0), r=2.6, segs=4)))
    # -X side: vertical band from the exhaust boss down to the lug, with a blank round boss (the "61" boss)
    ops.append(tmp_obj(bm_box((-16.4, -3.3, -0.2), (0.0, 3.3, 23.0), r=1.0, segs=2)))
    ops.append(tmp_obj(bm_revolve([(0, -15.5), (3.1, -15.5), (3.1, -16.9), (2.7, -17.3), (0, -17.3)], 32, "X",
                                  center=(0.0, 19.0))))
    # carb pedestal (+ clamp ears for the classic carb)
    py = PEDESTAL_Y.get(carb, -36.0)
    ops.append(tmp_obj(bm_cyl(8.62, (0, py, 0), (0, py, 11.8 if carb in ("classic", "os61") else 11.5), 64)))
    if carb in ("classic", "os61"):
        ey = -39.9 if carb == "os61" else -36.0  # clamp screws measured at y -39.9, z 8.3 (os61)
        for sx in (-1, 1):
            lo, hi = (7.3, 11.0) if sx > 0 else (-11.0, -7.3)   # ears reach into the pedestal: retainer threads covered
            ops.append(tmp_obj(bm_box((lo, ey - 3.3, 5.0), (hi, ey + 3.3, 11.6), r=1.4, segs=3)))
    # bosses round the two lower cover-plate screws, where the case corner rounds away under the gasket
    for sx in (-1, 1):
        ops.append(tmp_obj(bm_cyl(2.9, (sx * 13.0, 18.5, -15.6), (sx * 13.0, 23.5, -15.6), 32)))
    # exhaust stack boss below the fins (continued in the cylinder casting): carries the duct roof
    ops.append(tmp_obj(bm_port(180.0, 37.0, 33.0, 37.8, 12.5, 19.5, 2.5, r_ref=16.0)))   # wide enough to roof the duct
    # fins cast on the case below the cylinder joint (SE: the lowest one, photos A, E), with the front flash line
    rf_, c_ = (V["fin_r"], 0.42) if V else (20.8, 0.42)
    for z0_, z1_ in case_fins:
        ops.append(tmp_obj(bm_revolve([(13.0, z0_), (rf_ - c_, z0_), (rf_, z0_ + c_), (rf_, z1_ - c_), (rf_ - c_, z1_),
                                       (13.0, z1_)], 96, "Z", closed=True)))
        ops.append(tmp_obj(bm_box((-0.22, -rf_ - 0.14, z0_ + 0.16), (0.22, -rf_ + 0.9, z1_ - 0.16), r=0.1, segs=2)))
    boolean(body, ops, "UNION")
    boolean(body, [tmp_obj(bm_cyl(LUG_HOLE_R, (sx, y, -10), (sx, y, 4), 24)) for sx in (-LUG_HOLE_X, LUG_HOLE_X)
                   for y in LUG_HOLE_Y], "DIFFERENCE")  # beam-mount bolt holes: 52 x 25 pattern, M3.5 clearance
    # ---- one outer casting, two parts: the front housing (rotary valve, front bearing, intake pedestal) is
    # bolted to the crankcase with four M3 screws and a paper gasket at y -24.5..-24.35
    hous = bpy.data.objects.new("ENG_Front_Housing", body.data.copy())
    col.objects.link(hous)
    boolean(hous, [tmp_obj(bm_box((-80, -24.5, -80), (80, 150, 80)))], "DIFFERENCE")
    boolean(body, [tmp_obj(bm_box((-80, -150, -80), (80, -24.25, 80))), tmp_obj(bm_box((-80, 23.25, -80), (80, 150, 80)))],
            "DIFFERENCE")  # front and rear gasket planes (0.25 mm paper gaskets)
    # ---- fastener holes in the crankcase: tapped M3 (tap drill 2.5) for the cover, front housing and muffler
    taps = []
    for (x, z), (xf, zf) in zip(SCREW_XZ, FRONT_SCREW_XZ):
        taps.append(tmp_obj(bm_cyl(1.25, (x, 23.5, z), (x, 14.3, z), 20)))      # cover plate, M3x10
        taps.append(tmp_obj(bm_cyl(1.25, (xf, -24.5, zf), (xf, -16.4, zf), 20)))  # front housing, M3x12
    for y in MUF_BOLT_Y:
        taps.append(tmp_obj(bm_cyl(1.25, (-22.7, y, 33.0), (-13.2, y, 33.0), 20)))  # muffler, M3x15
    boolean(body, taps, "DIFFERENCE")
    # ---- gas volumes: cylinder bore, two Schnuerle transfers, boost, front-transfer connector
    zt_c = fin_top_max() + 1.0
    # liner slips in here, presses above; the bore runs down into the (lowered) crank chamber so the rod swings clear
    cav = tmp_obj(bm_cyl(K["liner_ro"] + 0.05, (0, 0, 6.0), (0, 0, zt_c), 96))
    boolean(cav, [tmp_obj(bm_) for bm_ in passage_bms(K)], "UNION")
    jr = K["rear_brg"][1] / 2
    keep = tmp_obj(za_bm(bm_cyl(jr + 1.3, (0, K["rear_brg"][3] - 1.5, 0), (0, K["chamber_y"][0], 0), 64), K))  # bearing housing
    boolean(cav, [keep], "DIFFERENCE")
    anl = bpy.data.objects.new("ANL_Crankcase_Cavity", cav.data.copy())
    bpy.context.scene.collection.objects.link(anl)

    def inner_ops():
        y0, y1 = K["chamber_y"]
        yb0, yb1 = K["rear_brg"][3], K["rear_brg"][3] + K["rear_brg"][2]
        return [tmp_obj(za_bm(bm_revolve([(0, y0), (K["chamber_r"] - 1.0, y0), (K["chamber_r"], y0 + 1.0), (K["chamber_r"], y1),
                                          (0, y1)], 96, "Y"), K)),                          # crank chamber
                tmp_obj(bm_cyl(K["rear_r"], (0, y1 - 0.5, K["rear_z"]), (0, 23.6, K["rear_z"]), 96)),  # rear chamber/bore
                tmp_obj(za_bm(bm_cyl(jr, (0, yb0, 0), (0, yb1 + 0.1, 0), 96), K)),          # rear bearing seat
                tmp_obj(za_bm(bm_cyl(K["journal_r"] + 0.1, (0, -24.5, 0), (0, yb0 + 0.1, 0), 64), K)),  # shaft clearance
                tmp_obj(za_bm(bm_cyl(12.45, (0, -24.5, 0), (0, -21.5, 0), 96), K))]         # front-housing spigot
    boolean(body, [cav] + inner_ops(), "DIFFERENCE")
    boolean(anl, inner_ops(), "UNION")
    # exhaust duct from the liner window to the photo-measured outlet in the flange (sooty inside)
    hy = K["bore"] / 2 * math.sin(math.radians(K["exh"][1])) + 0.3
    boolean(body, [tmp_obj(b, [M["soot"]]) for b in exhaust_duct_bms(K)], "DIFFERENCE", transfer=True)
    # the finned cylinder casting owns everything inside the fin envelope above its lower face (no doubled walls)
    boolean(body, [tmp_obj(bm_cyl(20.95, (0, 0, 37.5), (0, 0, zt_c + 5), 96))], "DIFFERENCE")
    return body, hous, anl


def passage_bms(K, shrink=0.0):
    """Transfer passages (lower wide part, upper part inside the fin core), boost passage, front connector.
    shrink (deg) steps the walls at the crankcase / cylinder-casting joint so they are never flush."""
    out = []
    for s, zb_ in ((1, 10.5), (-1, 15.9)):          # +80 deg = rear (+Y), -80 deg = front
        out.append(bm_port(s * K["trans"][0], K["trans"][1], zb_, 37.0, 13.0, 16.5, 1.5, r_ref=14.75))
        out.append(bm_port(s * K["trans"][0], K["trans"][1] - 1.5 - shrink, 34.0, K["z_tr"], 13.0, 15.0 - shrink * 0.25, 1.5,
                           r_ref=14.0))
    # boost: a blind pocket behind the liner's tall boost slot; it is fed through the window in the piston skirt
    out.append(bm_port(K["boost"][0], K["boost"][1] - shrink, K["boost_floor"] - 0.5, K["z_boost"], 13.0, 15.0 - shrink * 0.25,
                       1.0, r_ref=14.0))
    out.append(bm_box((-4.0, -14.0, 11.2), (9.2, -9.5, 17.8), r=1.0, segs=2))   # over the rear bearing housing
    out.append(bm_box((-4.0, -10.6, 9.0), (9.2, -7.5, 17.8), r=1.0, segs=2))    # down into the (lowered) crank chamber
    return out


def exhaust_duct_bms(K):
    """Exhaust duct: liner window -> photo-measured outlet in the flange face. Two hulls: the roof drops quickly
    inside the stack boss, then runs under the flange top with a real wall (no breakthrough into the fin root)."""
    hy = K["bore"] / 2 * math.sin(math.radians(K["exh"][1])) + 0.3
    win = rrect_yz(-10.5, 0.0, (K["z_exh0"] + K["z_exh"]) / 2, hy, (K["z_exh"] - K["z_exh0"]) / 2, 1.5)
    mid_a = rrect_yz(-17.0, 1.0, 34.7, 8.8, 2.1, 1.6)       # the two hulls overlap by a volume, never by a face;
    mid_b = rrect_yz(-16.5, 1.0, 34.7, 9.0, 2.3, 1.8)       # both stay clear of the z 37.5 casting joint
    return [bm_hull(win + mid_a), bm_hull(mid_b + rrect_yz(-23.2, 2.0, 33.0, 13.0, 3.5, 2.0))]


# beam-mount lugs: hole pattern 52 x 25 mm (Model Airplane News test of the 61SF/RF, "mounting hole spacing"),
# clearance for the M3.5 x 16 screws that come with the O.S. 905 radial mount (71905200); lug seat at z -6.7
LUG_HOLE_X, LUG_HOLE_Y, LUG_HOLE_R, LUG_SEAT_Z = 26.0, (14.5, -10.5), 1.9, -6.7
SCREW_XZ = [(13, 9.4), (-13, 9.4), (13, -15.6), (-13, -15.6)]   # cover-plate screws (x, z)
# front-housing screws, triangulated in photos B + B2: a 30.4 x 28 mm square centred on the crank axis
FRONT_SCREW_XZ = [(15.2, MECH_P0["axis_z"] + 14.0), (-15.2, MECH_P0["axis_z"] + 14.0),
                  (15.2, MECH_P0["axis_z"] - 14.0), (-15.2, MECH_P0["axis_z"] - 14.0)]
FRONT_FLANGE = (19.0, -17.8, 17.4)     # joint outline at y -24.5 (the case box section), axis-relative
MUF_BOLT_Y = (17.75, -13.75)


def fin_top_max():
    return max(fin_top(v) for v in VARIANTS.values()) + 0.6


def build_front_housing(hous, col, M, carb, K, anl):
    """Front housing internals: spigot into the case, rotary-valve journal bore, front bearing seat, intake
    pedestal bore + carb spigot seat, clearance holes for its 4 screws, tapped holes for the carb retainers."""
    yf0, yf1 = K["front_brg"][3], K["front_brg"][3] + K["front_brg"][2]
    py = PEDESTAL_Y.get(carb, -36.0)
    boolean(hous, [tmp_obj(za_bm(bm_revolve([(0, -24.6), (12.4, -24.6), (12.4, -21.9), (12.1, -21.6), (0, -21.6)], 96, "Y"),
                                 K))], "UNION")
    rv = K["valve_r"] + K["valve_clear"]

    def ops():
        return [tmp_obj(za_bm(bm_cyl(rv, (0, -21.5, 0), (0, yf1 - 0.1, 0), 96), K)),
                tmp_obj(za_bm(bm_cyl(K["front_brg"][1] / 2, (0, yf1, 0), (0, yf0 - 0.6, 0), 96), K)),
                tmp_obj(bm_cyl(K["ped_bore"], (0, py, K["za"] + 4.0), (0, py, 8.3), 48))]
    cuts = ops() + [tmp_obj(bm_cyl(5.25, (0, py, 8.1), (0, py, 13.0), 48))]
    for x, z in FRONT_SCREW_XZ:
        cuts.append(tmp_obj(bm_cyl(1.65, (x, -29.0, z), (x, -24.3, z), 20)))
    if carb == "os61":
        for sx in (1, -1):
            cuts.append(tmp_obj(bm_cyl(1.25, (sx * 11.3, -39.9, 8.3), (sx * 4.7, -39.9, 8.3), 20)))
    boolean(hous, cuts, "DIFFERENCE")
    boolean(anl, ops(), "UNION")
    return hous


def build_gaskets(col, M, K):
    """Paper gaskets: crankcase/front housing, crankcase/cover plate (the head shim is built with the liner)."""
    out = []
    fx, fz0, fz1 = FRONT_FLANGE
    za = K["za"]
    for name, y0, y1, hole, rz, box, holes in (
            ("ENG_Gasket_Front", -24.5, -24.25, 12.5, za, (fx - 0.12, za + fz0 + 0.12, za + fz1 - 0.12, 6.88), FRONT_SCREW_XZ),
            ("ENG_Gasket_Cover", 23.25, 23.5, K["rear_r"], K["rear_z"], (17.38, -18.88, 15.38, 4.88), SCREW_XZ)):
        # outline set 0.12 mm inside the castings: the joint reads as a fine dark line, as in the photos
        g = make_obj(name, bm_box((-box[0], y0, box[1]), (box[0], y1, box[2]), r=box[3], axis=(0, 1, 0), segs=5), col,
                     [M["gasket"]])
        cuts = [tmp_obj(bm_cyl(hole, (0, y0 - 1, rz), (0, y1 + 1, rz), 96))]
        cuts += [tmp_obj(bm_cyl(1.65, (x, y0 - 1, z), (x, y1 + 1, z), 20)) for x, z in holes]
        boolean(g, cuts, "DIFFERENCE")
        out.append(g)
    return out


def fin_top(V):
    return V.get("fin_z0", 37.5) + (V["fins"] - 1) * V["fin_pitch"] + V["fin_t"]


def fin_levels(V):
    """(z_bottom, z_top) of every cylinder fin, lowest first."""
    z0 = V.get("fin_z0", 37.5)
    return [(z0 + i * V["fin_pitch"], z0 + i * V["fin_pitch"] + V["fin_t"]) for i in range(V["fins"])]


CASE_JOINT_Z = 37.5   # crankcase / finned-cylinder casting joint: fins below it are cast on the case


def build_cylinder(col, M, V):
    rc, rf, c, t = 15.5, V["fin_r"], 0.42, V["fin_t"]
    lv = [(z0, z1) for z0, z1 in fin_levels(V) if z0 >= CASE_JOINT_Z - 1e-6]   # the lower ones belong to the case
    prof = [(0, CASE_JOINT_Z)] + ([(rc, CASE_JOINT_Z)] if lv[0][0] > CASE_JOINT_Z + 1e-6 else [])
    for z0, z1 in lv:  # cooling fins on a 15.5 mm core
        prof += [(rc, z0), (rf - c, z0), (rf, z0 + c), (rf, z1 - c), (rf - c, z1), (rc, z1)]
    head_z0 = fin_top(V) + 0.6
    prof += [(rc, head_z0), (0, head_z0)]  # the core carries on up to the head face
    cyl = make_obj("ENG_Cylinder_Fins", bm_revolve(prof, 96, "Z"), col, [M["cast"]])
    # casting parting line: a fine flash ridge across every fin rim at the front (photo E)
    boolean(cyl, [tmp_obj(bm_box((-0.22, -rf - 0.14, z0 + 0.16), (0.22, -rf + 0.9, z1 - 0.16), r=0.1, segs=2))
                  for z0, z1 in lv], "UNION")
    K = mech()
    P = dict(HEAD_SE_P0, **FIT.get("head_se", {}))
    seat = head_screw_seat(V)
    tip = seat - K["head_screw_len"]
    pos = [(P["allen_r"] * math.cos(math.radians(a)), P["allen_r"] * math.sin(math.radians(a))) for a in P["allen_angles"]]
    # bosses for the six head screws (they show between the top fins only) and the exhaust stack boss that
    # bridges the lowest fins on the exhaust side, behind the muffler (it carries the exhaust duct roof)
    bridge = []
    if lv[0][0] > CASE_JOINT_Z + 1e-6:   # the joint is in a fin gap: a root web on the exhaust side roofs the duct
        bridge.append(tmp_obj(bm_port(180.0, 46.0, CASE_JOINT_Z, 39.8, 13.0, 19.2, 0.8, r_ref=16.0)))
    boolean(cyl, [tmp_obj(bm_cyl(2.7, (x, y, tip - 1.6), (x, y, head_z0), 32)) for x, y in pos]
            + [tmp_obj(bm_port(180.0, 37.0, 37.5, 44.0, 13.0, 21.2, 2.5, r_ref=16.0))] + bridge, "UNION")
    cuts = [tmp_obj(bm_cyl(K["liner_ro"], (0, 0, 36.0), (0, 0, head_z0 + 1), 96)),                 # bore for the liner
            tmp_obj(bm_cyl(K["liner_fr"] + 0.05, (0, 0, K["z_flange"]), (0, 0, head_z0 + 1), 96))]  # flange counterbore
    cuts += [tmp_obj(bm_cyl(1.25, (x, y, tip - 0.9), (x, y, head_z0 + 0.5), 20)) for x, y in pos]  # M3 tapped
    ka = math.radians(LINER_KEY_DEG)
    kx, ky = (K["liner_fr"] + 0.05) * math.cos(ka), (K["liner_fr"] + 0.05) * math.sin(ka)
    cuts.append(tmp_obj(bm_cyl(0.5, (kx, ky, K["z_flange"] - 1.25), (kx, ky, K["z_flange"] + 0.1), 16)))  # dowel hole
    cuts += [tmp_obj(bm_) for bm_ in passage_bms(K, shrink=1.0)[:-1]]                        # passage tops
    boolean(cyl, cuts, "DIFFERENCE")
    boolean(cyl, [tmp_obj(b, [M["soot"]]) for b in exhaust_duct_bms(K)], "DIFFERENCE", transfer=True)  # exhaust roof
    return cyl


def head_screw_seat(V):
    """Seat height of the six M3 head screws: SE counterbores between the fins, standard head flat at +6.1."""
    if V.get("castellated"):
        return dict(HEAD_SE_P0, **FIT.get("head_se", {}))["allen_seat"]
    return fin_top(V) + 0.6 + 6.1


def head_internals(head, col, M, V, K, plug_top, seat, counterbore=False):
    """Combustion side of the head: spigot (button) into the liner counterbore with the squish band, spherical
    bowl, plug passage and 1/4-32 tapped plug hole, clearance holes for the six M3 head screws. Returns the
    glow plug's threaded body and its coil element."""
    z0 = fin_top(V) + 0.6
    zb, fr = K["z_button"], K["liner_fr"]
    boolean(head, [tmp_obj(bm_revolve([(0, zb), (fr - 0.3, zb), (fr, zb + 0.3), (fr, z0 + 0.6), (0, z0 + 0.6)], 96, "Z"))],
            "UNION")
    a, d = K["bowl_r"], K["bowl_d"]
    Rs = (a * a + d * d) / (2 * d)
    bowl = [(0, zb - 1.0), (a, zb - 1.0)]
    bowl += [(a * (1 - k / 12), zb + d - Rs + math.sqrt(Rs * Rs - (a * (1 - k / 12)) ** 2)) for k in range(0, 13)]
    pb = plug_top - 4.9                              # bottom of the plug thread
    cuts = [tmp_obj(bm_revolve(bowl, 96, "Z")),
            tmp_obj(bm_cyl(2.0, (0, 0, zb + d - 0.4), (0, 0, pb + 0.2), 32)),
            tmp_obj(bm_cyl(2.8, (0, 0, pb), (0, 0, plug_top + 0.1), 40))]
    P = dict(HEAD_SE_P0, **FIT.get("head_se", {}))
    for a_ in P["allen_angles"]:
        x, y = P["allen_r"] * math.cos(math.radians(a_)), P["allen_r"] * math.sin(math.radians(a_))
        cuts.append(tmp_obj(bm_cyl(1.65, (x, y, z0 - 0.5), (x, y, seat + 0.3), 20)))
        if counterbore:
            cuts.append(tmp_obj(bm_cyl(3.0, (x, y, seat), (x, y, seat + 30.0), 24)))
    boolean(head, cuts, "DIFFERENCE")
    th = bm_thread(0.0, -5.5, 3.17, 0.794, 0.45, segs=32, per_pitch=8, chamfer=0.4)   # 1/4-32 UNEF
    bmesh.ops.rotate(th, verts=th.verts[:], cent=(0, 0, 0), matrix=Rot("X", 90).to_3x3())
    bmesh.ops.translate(th, verts=th.verts[:], vec=(0, 0, plug_top + 0.6))
    body = make_obj("ENG_GlowPlug_Thread", th, col, [M["nickel"]])
    boolean(body, [tmp_obj(bm_cyl(1.6, (0, 0, pb - 0.5), (0, 0, pb + 1.8), 32))], "DIFFERENCE")   # element recess
    turns, z_a, z_b = 4.5, pb + 0.3, pb + 1.55
    pts = [(1.0 * math.cos(2 * math.pi * turns * i / 54), 1.0 * math.sin(2 * math.pi * turns * i / 54),
            z_a + (z_b - z_a) * i / 54) for i in range(55)]
    pts = [(0.0, 0.0, pb + 0.3)] + pts + [(0.2, 0.0, pb + 1.95)]
    coil = wire_obj("ENG_GlowPlug_Element", pts, 0.11, col, M["steel"])
    return [body, coil]


def build_head(col, M, V):
    mat = M["gold"] if V["head"] == "gold" else M["silver"]
    r, z0 = V["head_r"], fin_top(V) + 0.6
    zt = z0 + V["head_h"]
    head = make_obj("ENG_Head", bm_revolve([(0, z0), (r - 0.5, z0), (r, z0 + 0.5), (r, zt - 0.5),
                                            (r - 0.5, zt), (0, zt)], 96, "Z"), col, [mat])
    cuts = []
    gd = V["groove_depth"]
    for k in range(-5, 6):  # parallel heat-sink fins across the top (front-to-back)
        x = k * 3.6
        cuts.append(tmp_obj(bm_box((x - 0.9, -30, zt - gd), (x + 0.9, 30, zt + 3))))
    if V["castellated"]:  # SE head: castellated rim all round
        for i in range(24):
            a = i * 15 + 7.5
            bm = bm_box((-1.1, r - 1.9, zt - 7.0), (1.1, r + 3, zt + 3))
            bmesh.ops.rotate(bm, verts=bm.verts[:], cent=(0, 0, 0), matrix=Rot("Z", a).to_3x3())
            cuts.append(tmp_obj(bm))
    boolean(head, cuts, "DIFFERENCE")
    boss = tmp_obj(bm_revolve([(0, zt - gd - 1.5), (6.4, zt - gd - 1.5), (6.4, zt - 0.8), (5.9, zt - 0.3),
                               (0, zt - 0.3)], 48, "Z"))    # just under the fin tops: no coplanar faces
    boolean(head, [boss], "UNION")
    K = mech()
    seat = head_screw_seat(V)
    extra = head_internals(head, col, M, V, K, plug_top=zt, seat=seat, counterbore=True)
    me = screw_mesh(M, K["head_screw_len"])
    P = dict(HEAD_SE_P0, **FIT.get("head_se", {}))
    for i, a in enumerate(P["allen_angles"]):
        th = math.radians(a)
        ob = bpy.data.objects.new(f"ENG_Head_Screw_{i + 1}", me)
        ob.matrix_world = T(P["allen_r"] * math.cos(th) * MM, P["allen_r"] * math.sin(th) * MM, seat * MM) @ Rot("Z", 17 * i)
        col.objects.link(ob)
        extra.append(ob)
    # glow plug: nickel hex body + brass terminal
    plug = make_obj("ENG_GlowPlug_Body", bm_cyl(4.56, (0, 0, zt), (0, 0, zt + 2.1), 6), col, [M["nickel"]])
    pin = make_obj("ENG_GlowPlug_Pin", bm_revolve([(0, zt + 1.8), (2.0, zt + 1.8), (2.0, zt + 2.7), (0.8, zt + 3.0),
                                                   (0.8, zt + 4.6), (1.15, zt + 4.8), (1.15, zt + 5.3),
                                                   (0.6, zt + 5.7), (0, zt + 5.7)], 24, "Z"), col, [M["brass"]])
    return [head, plug, pin] + extra


HEAD_SE_P0 = dict(  # SE heat-sink head, measured from the owner's photos (mm, model frame)
    r=21.2, band_h=6.5, pitch=3.28, fin_t=1.6, n_half=5, end_r=2.2, fin_inset=0.0,   # 11 fins (k = -5..5), slot floor 64.3
    lip_rin=17.6, lip_ang=56.0, lip_drop=1.6, lip_base=0.22, lip_pow=0.55,  # solid crescents on the +-X sides
    well_r=6.2, well_floor=64.5,                        # recessed glow-plug well
    allen_r=16.0, allen_seat=63.6, allen_angles=(0, 60, 120, 180, 240, 300), cb_r=3.0,
    plug_tip=75.4,
)


def bm_arc_sweep(r_in, r_out, zb, height, a0, a1, segs=32, top_r=1.2, prof=6):
    """Sweep a round-topped radial section along an arc (deg). height(t) for t in [-1, 1]."""
    bm = bmesh.new()
    rings = []
    for i in range(segs + 1):
        t = -1 + 2 * i / segs
        ang = math.radians(a0 + (a1 - a0) * i / segs)
        h = max(height(t), top_r * 1.05)
        zt_ = zb + h
        rm, hw = (r_in + r_out) / 2, (r_out - r_in) / 2
        sec = [(r_in, zb), (r_out, zb), (r_out, zt_ - top_r)]
        for k in range(1, prof):  # rounded top from outer to inner
            th = math.pi * k / prof
            sec.append((rm + hw * math.cos(th), zt_ - top_r + top_r * math.sin(th)))
        sec.append((r_in, zt_ - top_r))
        rings.append([bm.verts.new((rr * math.cos(ang), rr * math.sin(ang), zz)) for rr, zz in sec])
    n = len(rings[0])
    for A, B in zip(rings, rings[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            bm.faces.new((A[k], A[k2], B[k2], B[k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def fin_plate(x, t, L, zr, zf, er, bev=0.45):
    """One heat-sink fin: plate in the YZ plane, rounded ends, softened top edges."""
    pts = [(-L, zr), (L, zr)]
    for k in range(7):
        th = math.pi / 2 * k / 6
        pts.append((L - er + er * math.cos(th), zf - er + er * math.sin(th)))
    for k in range(7):
        th = math.pi / 2 + math.pi / 2 * k / 6
        pts.append((-L + er + er * math.cos(th), zf - er + er * math.sin(th)))
    bm = bm_prism(pts, x - t / 2, x + t / 2, lambda u, v, w: (w, u, v))
    top = [e for e in bm.edges if all(abs(v.co.z - zf) < 1e-4 for v in e.verts)
           and abs((e.verts[1].co - e.verts[0].co).normalized().y) > 0.99]
    if top and bev > 0:
        bmesh.ops.bevel(bm, geom=top + list({v for e in top for v in e.verts}), offset=bev, offset_type="OFFSET",
                        segments=2, profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


HEAD_SE2 = dict(  # SE heat-sink head, v2: shapes from the owner's photos (E, D, Ac, B2, A) and a removed FSR head
    fin_wb=2.15, fin_wc=1.2,           # fin width at the root / at the crest: tapered, full-round crest
    end_corner_r=0.9,                  # the fins run out flush with the band wall; rounded top corner at the wall
    root_r=0.30, rim_round=0.5,        # fillet at the fin roots; small round where the slot floor meets the wall
    cres_b=1.5,                        # crescents: solid fill between the outer fins and the wall, domed down 1.5 mm (B2, new SE on eBay)
    well_r=6.2, boss_pad=0.55,         # glow-plug well (flat floor), plateau under it
    pocket_r=3.25, nx=520, ny=241,     # screw pockets (6.5 mm), heightfield resolution (0.105 x 0.177 mm at the centre)
    bot_chamfer=1.4,                   # bottom outer chamfer: the gold face starts ~59 mm (photos A, B2, E)
)


def _smin(a, b, k):
    import numpy as np
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def _smax(a, b, k):
    return -_smin(-a, -b, k)


def head_se_height(xg, yg, P, Q, z0, zb, zt):
    """Top surface of the SE head as a height field z = F(x, y) (numpy arrays, mm). Measured on the owner's photos:
    11 parallel fins on a 3.28 mm pitch with the centre fin on the plug axis (crest brightness peaks in D and E),
    tapered with round crests, running out flush with the band wall (rounded top corners, slots notch the wall
    down to ~64.2 mm: B2, E); the two outer fins carry the solid crescents out to the wall, domed over (Ac, B2);
    flat plateau under the plug well."""
    import numpy as np
    R = P["r"]
    H = zt - zb
    r = np.hypot(xg, yg)
    re = Q["rim_round"]
    floor = np.where(r <= R - re, zb, zb - re + np.sqrt(np.clip(re * re - (r - (R - re)) ** 2, 0.0, None)))
    rho = Q["fin_wc"] / 2
    hb = Q["fin_wb"] / 2
    n = P["n_half"]
    fins = np.full(xg.shape, -5.0)
    for k in range(-n, n + 1):
        d = np.abs(xg - k * P["pitch"])
        cap = (H - rho) + np.sqrt(np.clip(rho * rho - d * d, 0.0, None))
        flank = (H - rho) * (hb - d) / (hb - rho)
        fins = np.maximum(fins, np.where(d <= rho, cap, flank))
    # crescents: from the outer fins' crest line out to the wall, flat then an elliptic dome meeting the wall
    x5 = n * P["pitch"]
    xc = x5 + rho
    ax = np.abs(xg)
    xw = np.sqrt(np.clip(R * R - yg * yg, 0.0, None))
    a = np.maximum(xw - xc, 1e-3)
    u = np.clip((ax - xc) / a, 0.0, 1.0)
    dome = H - Q["cres_b"] * (1.0 - np.sqrt(np.clip(1.0 - u * u, 0.0, None)))
    cres = np.where(ax >= x5, np.where(ax <= xc, H, dome), -5.0)
    h = np.maximum(fins, cres)
    # fin ends at the wall: rounded top corner (along the fin)
    rc = Q["end_corner_r"]
    dw = np.clip(np.sqrt(np.clip(R * R - xg * xg, 0.0, None)) - np.abs(yg), 0.0, rc)
    h = np.minimum(h, H - rc + np.sqrt(np.clip(rc * rc - (rc - dw) ** 2, 0.0, None)))
    F = _smax(floor, zb + h, Q["root_r"])
    # plateau: plug-well floor (flat, solid under the gaps)
    wf = P["well_floor"]
    rw = Q["well_r"] + Q["boss_pad"]
    wp = wf + 0.15            # 0.15 above the cut floor: the well cutter never lies in the plateau's plane
    F = _smax(F, np.clip(wp - (r - rw) * 3.0, zb - 3.0, wp), 0.25)
    return F


def heightfield_solid(F, R, z0, nx, ny, chamfer=0.45, edge_bias=0.35):
    """Closed disk-shaped solid: top = height field F(x, y) over the disk of radius R, vertical band wall,
    chamfered bottom edge, flat bottom (one n-gon) at z0. Columns in x (denser toward +-R, edge_bias), each with
    as many rows as its chord needs at an even spacing, adjacent columns stitched by a zipper of triangles: no
    collapsed rows at the sides, so no needle or zero-area faces anywhere."""
    import numpy as np
    u = np.linspace(-1.0, 1.0, nx)
    xs = R * (1.0 - 0.015 / R) * ((1.0 - edge_bias) * u + edge_bias * np.sin(np.pi * u / 2.0))
    Y = np.sqrt(np.clip(R * R - xs * xs, 0.0, None))
    dy = 2.0 * R / (ny - 1)
    bm = bmesh.new()
    cols = []
    for i, x in enumerate(xs):
        m = max(3, int(math.ceil(2.0 * Y[i] / dy)) + 1)
        ys = np.linspace(-Y[i], Y[i], m)
        zs = F(np.full(m, x), ys)
        cols.append([bm.verts.new((float(x), float(y), float(z))) for y, z in zip(ys, zs)])
    for A, B in zip(cols, cols[1:]):
        i = j = 0
        while i < len(A) - 1 or j < len(B) - 1:
            if j < len(B) - 1 and (i == len(A) - 1 or B[j + 1].co.y <= A[i + 1].co.y):
                bm.faces.new((A[i], B[j], B[j + 1]))
                j += 1
            else:
                bm.faces.new((A[i], B[j], A[i + 1]))
                i += 1
    loop = [c[0] for c in cols] + cols[-1][1:] + [c[-1] for c in cols[-2::-1]] + cols[0][-2:0:-1]
    ring1, ring2 = [], []
    for v in loop:
        x, y = v.co.x, v.co.y
        rr = math.hypot(x, y)
        ring1.append(bm.verts.new((x, y, z0 + chamfer)))
        f = (rr - chamfer) / rr
        ring2.append(bm.verts.new((x * f, y * f, z0)))
    n = len(loop)
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((loop[k2], loop[k], ring1[k], ring1[k2]))
        bm.faces.new((ring1[k2], ring1[k], ring2[k], ring2[k2]))
    # bottom: the fine outer ring zippered to a coarse 128-gon 1.2 mm inside it (the holes and the spigot are cut
    # in that), so no triangle is ever made of three nearly collinear points of the fine ring
    r3 = R - chamfer - 1.2
    a0 = math.atan2(ring2[0].co.y, ring2[0].co.x)
    ring3 = [bm.verts.new((r3 * math.cos(a0 + 2 * math.pi * m / 128), r3 * math.sin(a0 + 2 * math.pi * m / 128), z0))
             for m in range(128)]

    def unwrap(vs, start):
        out, prev = [], start
        for v in vs:
            a = math.atan2(v.co.y, v.co.x)
            while a < prev - 1e-9:
                a += 2 * math.pi
            out.append(a)
            prev = a
        return out
    A2 = unwrap(ring2, a0 - 1e-6) + [None]
    A3 = [a0 + 2 * math.pi * m / 128 for m in range(129)]
    A2[-1] = A2[0] + 2 * math.pi
    i = j = 0
    while i < n or j < 128:
        if j < 128 and (i == n or A3[j + 1] <= A2[i + 1]):
            bm.faces.new((ring2[i % n], ring3[(j + 1) % 128], ring3[j]))
            j += 1
        else:
            bm.faces.new((ring2[i % n], ring2[(i + 1) % n], ring3[j % 128]))
            i += 1
    bm.faces.new(ring3[::-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def glow_plug_os8(col, M, wf):
    """O.S. No.8 short-body plug, proportions measured on the owner's photo E (tip at ~74.9 mm, well floor 64.5):
    copper washer, 8 mm hex body (double-chamfered) whose top is a heavy rounded ring around a shallow dish,
    dark insulator round the centre post, nickel terminal: ring, groove, ring and a bullet tip."""
    out = [make_obj("ENG_GlowPlug_Washer", bm_revolve([(3.25, wf), (4.7, wf), (4.8, wf + 0.1), (4.8, wf + 0.5),
                                                       (4.7, wf + 0.6), (3.25, wf + 0.6)], 48, "Z", closed=True),
                    col, [M["copper"]])]
    h0, h1 = wf + 0.6, wf + 3.6
    hexb = make_obj("ENG_GlowPlug_Body", bm_cyl(8.0 / math.sqrt(3.0), (0, 0, h0), (0, 0, h1), 6), col, [M["black"]])
    boolean(hexb, [tmp_obj(bm_revolve([(0, h0 - 0.1), (3.75, h0 - 0.1), (4.75, h0 + 0.55), (4.75, h1 - 0.55),
                                       (3.75, h1 + 0.1), (0, h1 + 0.1)], 64, "Z"))], "INTERSECT")
    rc, rt = (2.95, h1 + 0.15), 0.95               # the rounded ring on top of the hex
    ring = [(0, h1 - 0.3), (3.3, h1 - 0.3)]
    for i in range(0, 15):
        th = math.radians(-20 + 200 * i / 14)
        ring.append((rc[0] + rt * math.cos(th), rc[1] + rt * math.sin(th)))
    ring += [(1.75, h1 + 0.2), (1.3, h1 + 0.45), (0, h1 + 0.45)]
    boolean(hexb, [tmp_obj(bm_revolve(ring, 64, "Z"))], "UNION")
    out.append(hexb)
    post = [(0, h1 + 0.3), (0.82, h1 + 0.3), (0.82, wf + 6.45), (0.7, wf + 6.6), (0, wf + 6.6)]
    out.append(make_obj("ENG_GlowPlug_Insulator", bm_revolve(post, 32, "Z"), col, [M["black"]]))
    z = wf + 6.4
    prof = [(0, z), (0.95, z), (1.0, z + 0.15), (1.0, z + 1.3), (0.78, z + 1.45), (0.78, z + 1.65), (1.0, z + 1.8),
            (1.0, z + 2.15), (0.92, z + 2.3)]
    for i in range(1, 9):   # bullet (tangent ogive) to a small round tip
        t = i / 8
        prof.append((0.92 * math.sqrt(max(0.0, 1 - t * t)) * 0.92 + 0.07 * (1 - t), z + 2.3 + 1.95 * t))
    prof[-1] = (0.0, z + 4.25)
    out.append(make_obj("ENG_GlowPlug_Pin", bm_revolve(prof, 32, "Z"), col, [M["nickel"]]))
    return out


def knurled_screw_mesh(M, length):
    """Socket head cap screw with the knurled head of the O.S. head screws (photo E): 36 shallow grooves."""
    key = ("knurl", round(float(length), 2))
    me = SCREW_MESHES.get(key)
    if me is not None and me.name in bpy.data.meshes:
        return me
    s = make_obj("ENG_Screw_M3K", bm_screw(length), bpy.context.scene.collection, [M["black"]])
    cuts = [tmp_obj(bm_cyl(1.443, (0, 0, 1.4), (0, 0, 3.6), 6))]
    for i in range(36):
        a = 2 * math.pi * i / 36
        g = bm_box((-0.19, -0.085, 0.3), (0.19, 0.085, 2.55))
        bmesh.ops.translate(g, verts=g.verts[:], vec=(2.81, 0, 0))
        bmesh.ops.rotate(g, verts=g.verts[:], cent=(0, 0, 0), matrix=Rot("Z", math.degrees(a)).to_3x3())
        cuts.append(tmp_obj(g))
    boolean(s, cuts, "DIFFERENCE")
    for c in list(s.users_collection):
        c.objects.unlink(s)
    me = s.data
    bpy.data.objects.remove(s)
    me.name = f"ME_Screw_M3x{length:g}_knurl"
    SCREW_MESHES[key] = me
    return me


def build_head_se(col, M, V):
    """Heat-sink head of the SE engine (v2): one height-field top (tapered fins with round crests and steep rounded
    ends, slots running out through the rounded rim, solid crescents on +-X, flat plateaus) on the band, then the
    plug well, six screw pockets and clearance holes cut, combustion side from head_internals; knurled M3 socket
    screws and an O.S. No.8 plug."""
    import numpy as np  # noqa: F401
    P = dict(HEAD_SE_P0, **FIT.get("head_se", {}))
    Q = dict(HEAD_SE2, **FIT.get("head_se2", {}))
    r, z0 = P["r"], fin_top(V) + 0.6
    zt = z0 + V["head_h"]
    zb = z0 + P["band_h"]
    mat = M["gold"] if V["head"] == "gold" else M["silver"]
    bm = heightfield_solid(lambda xg, yg: head_se_height(xg, yg, P, Q, z0, zb, zt), r, z0, Q["nx"], Q["ny"],
                           chamfer=Q["bot_chamfer"])
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
    head = make_obj("ENG_Head", bm, col, [mat])
    wf = P["well_floor"]
    cuts = [tmp_obj(bm_cyl(Q["well_r"], (0, 0, wf), (0, 0, zt + 3), 96))]
    for a in P["allen_angles"]:
        th = math.radians(a)
        c = (P["allen_r"] * math.cos(th), P["allen_r"] * math.sin(th))
        cuts.append(tmp_obj(bm_cyl(Q["pocket_r"], (c[0], c[1], P["allen_seat"]), (c[0], c[1], zt + 3), 48)))
    boolean(head, cuts, "DIFFERENCE")
    K = mech()
    out = [head] + head_internals(head, col, M, V, K, plug_top=wf, seat=P["allen_seat"])
    # the cutters cross the fine top grid in tiny facets along every rim: collapse edges under 0.04 mm, then
    # triangulate and clear the slivers (altitude < 12 um) that a checker would read as overlapping faces
    bm = bmesh.new()
    bm.from_mesh(head.data)
    bmesh.ops.dissolve_degenerate(bm, dist=4e-5, edges=bm.edges[:])
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method="BEAUTY",
                          ngon_method="BEAUTY")
    sliver_fix(bm)
    bm.to_mesh(head.data)
    bm.free()
    me = knurled_screw_mesh(M, K["head_screw_len"])
    for i, a in enumerate(P["allen_angles"]):
        th = math.radians(a)
        ob = bpy.data.objects.new(f"ENG_Head_Screw_{i + 1}", me)
        ob.matrix_world = T(P["allen_r"] * math.cos(th) * MM, P["allen_r"] * math.sin(th) * MM,
                            P["allen_seat"] * MM) @ Rot("Z", 17 * i)
        col.objects.link(ob)
        out.append(ob)
    out += glow_plug_os8(col, M, wf)
    head.data.set_sharp_from_angle(angle=math.radians(40))
    return out


def build_backplate(col, M):
    """Cover plate (backplate): rim flange with the four screws, a cup that slides into the case bore (its
    recessed face is what shows from behind) and a boss that fills the rear of the crank chamber (primary
    compression). One part; seals on the paper gasket."""
    K = mech()
    rz, (br, by0) = K["rear_z"], K["bp_boss"]
    bp = make_obj("ENG_Backplate", bm_box((-17.5, 23.5, -19), (17.5, 25.3, 15.5), r=5, axis=(0, 1, 0), segs=5), col,
                  [M["cast"]])
    cup = bm_revolve([(0, 19.05), (K["rear_r"] - 0.35, 19.05), (K["rear_r"] - 0.05, 19.35), (K["rear_r"] - 0.05, 23.6),
                      (0, 23.6)], 96, "Y", center=(0, rz))
    boss = bm_revolve([(0, by0), (br - 0.8, by0), (br, by0 + 0.8), (br, 19.2), (0, 19.2)], 96, "Y", center=(0, rz))
    boolean(bp, [tmp_obj(cup), tmp_obj(boss)], "UNION")
    cuts = [tmp_obj(bm_cyl(14.6, (0, 19.6, rz), (0, 26.0, rz), 96))]
    cuts += [tmp_obj(bm_cyl(1.65, (x, 23.3, z), (x, 25.6, z), 20)) for x, z in SCREW_XZ]
    boolean(bp, cuts, "DIFFERENCE")
    lug = tmp_obj(bm_cyl(2.4, (0, 19.5, 14.0), (0, 25.24, 14.0), 24))     # 12 o'clock lug inside the bore ...
    boolean(lug, [tmp_obj(bm_cyl(K["rear_r"] - 0.06, (0, 19.0, rz), (0, 26.0, rz), 96))], "INTERSECT")  # ... in the cup
    boolean(bp, [lug], "UNION")
    # the recess you look into from behind is dark with old oil and soot in the photos (D, T)
    bp.data.materials.append(M["oil"])
    for f in bp.data.polygons:
        c = f.center / MM
        if c.y < 25.2 and math.hypot(c.x, c.z - rz) < 14.62:
            f.material_index = 1
    return [bp]


SCREW_MESHES = {}


def bm_screw(length, d=3.0, pitch=0.5, depth=0.28, segs=32, per_pitch=6, head_r=2.75, head_h=3.0, chamfer=0.35):
    """Socket head cap screw as ONE closed mesh: right-hand helical thread along -Z whose first ring is
    bridged straight into the head's underside (no boolean, so the seat face stays clean)."""
    bm = bmesh.new()
    rM = d / 2
    rm = rM - depth
    n = max(2, int(length / pitch * per_pitch))
    rows = []
    for i in range(n + 1):
        s_ = length * i / n
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            u = (s_ / pitch + a / (2 * math.pi)) % 1.0          # crest moves toward +Z as a grows: right hand
            f = max(0.0, min(1.0, 1.7 * (1 - abs(2 * u - 1)) - 0.35))
            r = rm + depth * f
            dt = length - s_
            if dt < chamfer:
                r = min(r, rm - 0.25 + (rM - rm + 0.25) * dt / chamfer)
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), -s_)))
        rows.append(ring)
    head = [rows[0]]
    for r, z in ((head_r, 0.0), (head_r, head_h - 0.35), (head_r - 0.3, head_h)):
        head.append([bm.verts.new((r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs), z))
                     for k in range(segs)])
    seq = list(reversed(rows)) + head[1:]
    for A, B in zip(seq, seq[1:]):
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((A[k], A[k2], B[k2], B[k]))
    for ring, z in ((rows[-1], -length), (head[-1], head_h)):
        c = bm.verts.new((0.0, 0.0, z))
        for k in range(segs):
            bm.faces.new((ring[k], ring[(k + 1) % segs], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def screw_mesh(M, length=10.0):
    """ISO 4762 M3 socket head cap screw (head 5.5 x 3.0, 2.5 hex socket), fully threaded M3x0.5 shank.
    Axis +Z, under-head seat at z=0, thread tip at z=-length. One shared mesh per length (instances)."""
    key = round(float(length), 2)
    me = SCREW_MESHES.get(key)
    if me is not None and me.name in bpy.data.meshes:
        return me
    col = bpy.context.scene.collection
    s = make_obj("ENG_Screw_M3", bm_screw(length), col, [M["black"]])
    boolean(s, [tmp_obj(bm_cyl(1.443, (0, 0, 1.4), (0, 0, 3.6), 6))], "DIFFERENCE")   # 2.5 hex socket
    for c in list(s.users_collection):
        c.objects.unlink(s)
    me = s.data
    bpy.data.objects.remove(s)
    me.name = f"ME_Screw_M3x{key:g}"
    SCREW_MESHES[key] = me
    return me


def place_screw(me, name, pos, direction, col, spin=0.0):
    ob = bpy.data.objects.new(name, me)
    q = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized())
    ob.matrix_world = T(*(Vector(pos) * MM)) @ q.to_matrix().to_4x4() @ Rot("Z", spin)
    col.objects.link(ob)
    return ob


def build_screws(col, M, carb="os61"):
    """Cover plate and front housing: 4 + 4 M3x10. Carb retainers (os61): 2 M3x6 whose tips sit over the
    spigot's shoulder. Heads seat on the real faces; shanks run in the tapped holes cut in the castings."""
    me = screw_mesh(M, 10.0)
    me12 = screw_mesh(M, 12.0)       # front housing: 4.3 mm flange + 7.4 mm of thread in the case
    out = []
    for i, ((x, z), (xf, zf)) in enumerate(zip(SCREW_XZ, FRONT_SCREW_XZ)):
        out.append(place_screw(me, f"ENG_Screw_Rear_{i + 1}", (x, 25.3, z), (0, 1, 0), col, spin=17 * i))
        out.append(place_screw(me12, f"ENG_Screw_Front_{i + 1}", (xf, -28.8, zf), (0, -1, 0), col, spin=11 * i))
    if carb == "os61":
        me6 = screw_mesh(M, 6.0)
        for i, sx in enumerate((1, -1)):
            out.append(place_screw(me6, f"ENG_Screw_CarbClamp_{i + 1}", (sx * 11.0, -39.9, 8.3), (sx, 0, 0), col,
                                   spin=23 * i))
    elif carb == "classic":
        me6 = screw_mesh(M, 6.0)
        for i, sx in enumerate((1, -1)):
            out.append(place_screw(me6, f"ENG_Screw_CarbClamp_{i + 1}", (sx * 11.0, -36.0, 9.1), (sx, 0, 0), col,
                                   spin=23 * i))
    return me, out


def wire_obj(name, pts, radius, col, mat):
    """Bent spring wire: NURBS path (mm points) with a round bevel, baked to a capped mesh."""
    cu = bpy.data.curves.new("TMP_wire", "CURVE")
    cu.dimensions = "3D"
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for p, c in zip(sp.points, pts):
        p.co = (c[0] * MM, c[1] * MM, c[2] * MM, 1.0)
    sp.order_u, sp.use_endpoint_u, sp.resolution_u = 3, True, 10
    cu.bevel_depth, cu.bevel_resolution, cu.use_fill_caps = radius * MM, 3, True
    tmp = bpy.data.objects.new("TMP_wire", cu)
    bpy.context.scene.collection.objects.link(tmp)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg), depsgraph=dg)
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cu)
    me.name = name
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    me.materials.append(mat)
    cleanup(ob)
    return ob


def build_carb_modern(col, M, place=(0.0, -36.0, 31.0), throttle=0.0):
    """Rotary-barrel carburetor, modeled after the carb reference photos (no logo pad/lettering).

    Local frame (mm): barrel axis = X through the origin, needle valve on +X, throttle arm on -X,
    intake chimney +Z, spigot -Z, mounting-boss face +Y. `place` moves it onto the engine,
    `throttle` rotates barrel + arm about the barrel axis (deg, 0 = wide open)."""
    parts = []
    # ---- body casting: barrel housing + tapered lower body + chimney + bosses + gusseted cone
    body = make_obj("CARB_Body", bm_revolve([(0, -13.0), (7.9, -13.0), (8.5, -12.4), (8.5, 12.4),
                                             (7.9, 13.0), (0, 13.0)], 64, "X"), col, [M["cast"]])
    ops = [tmp_obj(bm_loft([(-15.4, 8.3, 8.0, 3.6), (-9.0, 10.0, 8.5, 3.8), (-1.0, 11.6, 8.5, 3.9),
                            (0.8, 11.8, 8.4, 3.9)], 5)),
           tmp_obj(bm_revolve([(0, 2.0), (7.75, 2.0), (7.75, 11.5), (7.35, 12.0), (0, 12.0)], 64, "Z")),
           tmp_obj(bm_revolve([(0, 12.0), (4.6, 12.0), (4.6, 13.9), (4.2, 14.3), (0, 14.3)], 48, "X")),
           tmp_obj(bm_revolve([(0, 6.0), (5.0, 6.0), (5.0, 10.5), (2.9, 25.5), (2.4, 26.1), (0, 26.1)], 48, "X",
                              center=(5.6, -4.6))),
           tmp_obj(bm_prism([(9.0, -4.6), (18.5, -4.6), (9.0, 0.8)], 5.0, 6.2, lambda u, v, w: (u, w, v))),
           tmp_obj(bm_prism([(8.0, -11.8), (20.5, -4.6), (8.0, -4.6)], 5.0, 6.2, lambda u, v, w: (u, w, v)))]
    for sx in (-6.4, 6.4):  # mounting-screw bosses
        ops.append(tmp_obj(bm_revolve([(0, 4.0), (2.9, 4.0), (2.9, 10.6), (2.5, 11.0), (0, 11.0)], 32, "Y",
                                      center=(sx, -12.6))))
    boolean(body, ops, "UNION")
    cuts = [tmp_obj(bm_cyl(6.0, (-12.4, 0, 0), (10.8, 0, 0), 48)),              # barrel bore
            tmp_obj(bm_cyl(4.0, (0, 0, 4.0), (0, 0, -16.5), 48)),               # venturi
            tmp_obj(bm_revolve([(0, 3.5), (4.0, 3.5), (5.3, 6.5), (5.3, 9.6), (6.2, 9.9), (6.2, 13.0),
                                (0, 13.0)], 48, "Z")),                         # intake + counterbore
            tmp_obj(bm_cyl(1.2, (20.0, 5.6, -4.6), (26.6, 5.6, -4.6), 20))]     # cone outlet
    boolean(body, cuts, "DIFFERENCE")
    parts.append(body)

    # ---- rotary barrel (chrome), seal, arm hub and throttle arm
    barrel = make_obj("CARB_Barrel", bm_revolve([(0, 10.5), (5.75, 10.5), (5.75, -12.1), (3.6, -12.1),
                                                 (3.6, -16.8), (3.3, -17.1), (0, -17.1)], 48, "X"), col,
                      [M["chrome"]])
    boolean(barrel, [tmp_obj(bm_cyl(3.9, (0, 0, 7), (0, 0, -7), 40))], "DIFFERENCE")
    seal = make_obj("CARB_Barrel_Seal", bm_revolve([(3.3, -12.6), (5.0, -12.6), (5.0, -16.2), (4.6, -16.6),
                                                    (3.3, -16.6)], 48, "X", closed=True), col, [M["rubber"]])
    hub = make_obj("CARB_Arm_Hub", bm_revolve([(0, -16.3), (4.6, -16.3), (4.6, -20.1), (4.2, -20.6),
                                               (0, -20.6)], 48, "X"), col, [M["plastic_black"]])
    outline = hull2d(circle_pts(0, 0, 4.0, 28) + circle_pts(0, 17.5, 1.9, 20))
    arm = make_obj("CARB_Throttle_Arm", bm_prism(outline, -19.3, -21.1, lambda u, v, w: (w, u, v)), col,
                   [M["plastic_black"]])
    boolean(arm, [tmp_obj(bm_cyl(0.75, (-18.7, 0, z), (-21.7, 0, z), 16)) for z in (17.3, 14.1)],
            "DIFFERENCE")
    parts += [barrel, seal, hub, arm]

    # ---- needle valve assembly on the barrel axis (+X)
    holder = make_obj("CARB_Needle_Holder", bm_revolve([(0, 14.0), (3.6, 14.0), (3.6, 20.4), (3.2, 20.8),
                                                        (0, 20.8)], 40, "X"), col, [M["cast"]])
    boolean(holder, [tmp_obj(bm_revolve([(0, 0.0), (2.5, 0.0), (2.5, 4.4), (2.2, 4.7), (0, 4.7)], 32, "Z",
                                        center=(18.0, 0)))], "UNION")
    nipple = make_obj("CARB_Fuel_Nipple", bm_cyl(2.54, (18.0, 0, 4.4), (18.0, 0, 6.0), 6), col, [M["nickel"]])
    boolean(nipple, [tmp_obj(bm_revolve([(0.65, 5.8), (1.35, 5.8), (1.35, 9.4), (1.85, 9.8), (1.85, 10.4),
                                         (1.4, 10.8), (1.4, 11.3), (0.65, 11.3)], 24, "Z", center=(18.0, 0),
                                        closed=True))], "UNION")
    nut = make_obj("CARB_Needle_LockNut", bm_cyl(3.81, (20.2, 0, 0), (23.0, 0, 0), 6), col, [M["steel"]])
    boolean(nut, [tmp_obj(bm_revolve([(0, 20.1), (3.3, 20.1), (3.95, 20.8), (3.95, 22.4), (3.3, 23.1),
                                      (0, 23.1)], 40, "X"))], "INTERSECT")
    sleeve = make_obj("CARB_Needle_Sleeve", bm_revolve([(0, 22.4), (3.05, 22.4), (3.05, 26.0), (2.8, 26.2),
                                                        (2.8, 26.7), (3.05, 26.9), (3.05, 30.3), (2.8, 30.6),
                                                        (0, 30.6)], 40, "X"), col, [M["black"]])
    teeth = 40
    star = [((3.55 if i % 2 == 0 else 3.28) * math.cos(math.pi * i / teeth),
             (3.55 if i % 2 == 0 else 3.28) * math.sin(math.pi * i / teeth)) for i in range(2 * teeth)]
    knob = make_obj("CARB_Needle_Knob", bm_prism(star, 30.4, 41.4, lambda u, v, w: (w, u, v)), col,
                    [M["steel"]])
    boolean(knob, [tmp_obj(bm_revolve([(0, 30.2), (3.7, 30.2), (3.7, 40.6), (3.0, 41.4), (0, 41.4)], 48,
                                      "X"))], "INTERSECT")
    boolean(knob, [tmp_obj(bm_cyl(0.8, (39.4, -5, 0), (39.4, 5, 0), 16)),
                   tmp_obj(bm_cyl(0.9, (40.0, 0, 0), (41.8, 0, 0), 16))], "DIFFERENCE")
    spring = wire_obj("CARB_Needle_Spring", [(23.2, 0, 2.6), (24.4, 0, 4.4), (25.8, 0, 5.4), (27.4, 0, 4.4),
                                             (31.0, 0, 3.95), (35.6, 0, 3.72)], 0.32, col, M["black"])
    parts += [holder, nipple, nut, sleeve, knob, spring]

    # ---- spigot side: polished retaining collar with set screw, spigot tube with flare
    collar = make_obj("CARB_Collar", bm_revolve([(4.6, -15.0), (7.85, -15.0), (8.25, -15.4), (8.25, -19.4),
                                                 (7.85, -19.8), (4.6, -19.8)], 64, "Z", closed=True), col,
                      [M["polished"]])
    boolean(collar, [tmp_obj(bm_cyl(0.9, (0, 4.0, -17.4), (0, 9.5, -17.4), 16))], "DIFFERENCE")
    setscrew = make_obj("CARB_Collar_SetScrew", bm_cyl(0.6, (0, 5.0, -17.4), (0, 7.0, -17.4), 16), col,
                        [M["black"]])
    spigot = make_obj("CARB_Spigot", bm_revolve([(3.7, -14.5), (5.15, -14.5), (5.15, -29.4), (5.5, -30.0),
                                                 (6.45, -30.5), (6.45, -31.2), (3.7, -31.2)], 64, "Z",
                                                closed=True), col, [M["polished"]])
    parts += [collar, setscrew, spigot]
    for i, sx in enumerate((-6.4, 6.4)):  # pan-head mounting screws in the bosses
        sc = make_obj(f"CARB_Mount_Screw_{i + 1}", bm_revolve([(0, 10.7), (2.7, 10.7), (2.7, 11.6), (2.4, 12.3),
                                                               (1.6, 12.7), (0, 12.8)], 32, "Y",
                                                              center=(sx, -12.6)), col, [M["black"]])
        boolean(sc, [tmp_obj(bm_cyl(0.98, (sx, 11.9, -12.6), (sx, 13.5, -12.6), 6))], "DIFFERENCE")
        parts.append(sc)

    # ---- throttle angle, then onto the engine
    for ob in (barrel, hub, arm):
        ob.data.transform(Rot("X", throttle))
    for ob in parts:
        ob.data.transform(T(*(Vector(place) * MM)))
        ob.data.update()
    return parts


def build_carb_classic(col, M, place=(0.0, -36.0, 25.0), side_needle=False):
    """Classic rotary-barrel carb of the reference engines: intake tilted 15 deg forward, needle valve on
    top behind the intake, beige barrel washer + throttle arm on the -X end, D-cap + mixture screw on +X,
    rearward fuel nipple. Local mm frame: barrel axis = X through the origin, spigot -Z."""
    # intake leans 15 deg forward and 22 deg out toward the needle side (+X), as in the photos
    d = Vector((math.tan(math.radians(22.0)), -math.tan(math.radians(15.0)), 1.0)).normalized()
    base = Vector((0.0, -1.0, 1.0))
    top = base + d * 20.0
    nx, ny = -3.6, 4.8  # needle valve position (just behind the intake rim)
    body = make_obj("CARB_Body", bm_revolve([(0, -9.6), (6.4, -9.6), (7.0, -9.0), (7.0, 9.0), (6.4, 9.6),
                                             (0, 9.6)], 64, "X"), col, [M["cast"]])
    ops = [tmp_obj(bm_box((-7.4, -7.6, -10.5), (7.4, 6.6, 4.5), r=2.4, segs=3)),
           tmp_obj(bm_cyl(7.5, base, top, 64)),
           tmp_obj(bm_cyl(8.0, top - d * 1.7, top, 64)),
           tmp_obj(bm_revolve([(0, -13.6), (6.6, -13.6), (7.0, -13.2), (7.0, -10.0), (0, -10.0)], 48, "Z",
                              center=(0, -0.5))),
           tmp_obj(bm_revolve([(0, -4.0), (3.1, -4.0), (3.1, 7.2), (2.8, 7.6), (0, 7.6)], 32, "Z",
                              center=(nx, ny))),
           tmp_obj(bm_revolve([(0, 9.0), (5.3, 9.0), (5.3, 10.5), (4.9, 10.9), (0, 10.9)], 48, "X"))]
    boolean(body, ops, "UNION")
    cuts = [tmp_obj(bm_cyl(5.4, top - d * 13.0, top + d * 1.0, 48)),          # intake bore
            tmp_obj(bm_cyl(6.3, top - d * 2.0, top + d * 1.0, 48)),           # filter counterbore
            tmp_obj(bm_cyl(4.3, (0, -1.2, 7.0), (0, -0.5, -14.5), 48)),       # venturi -> spigot
            tmp_obj(bm_cyl(5.7, (-9.1, 0, 0), (8.7, 0, 0), 48))]              # barrel bore
    boolean(body, cuts, "DIFFERENCE")
    parts = [body]
    barrel = make_obj("CARB_Barrel", bm_revolve([(0, 8.4), (5.4, 8.4), (5.4, -8.8), (4.2, -8.8), (4.2, -11.6),
                                                 (3.9, -11.9), (0, -11.9)], 48, "X"), col, [M["chrome"]])
    boolean(barrel, [tmp_obj(bm_cyl(4.15, (0, 0, 6.5), (0, 0, -6.5), 40))], "DIFFERENCE")
    washer = make_obj("CARB_Barrel_Washer", bm_revolve([(3.8, -9.3), (6.2, -9.3), (6.2, -10.1), (5.9, -10.4),
                                                        (3.8, -10.4)], 48, "X", closed=True), col,
                      [M["plastic_beige"]])
    a = math.radians(235)  # throttle arm points down and slightly forward
    ux, uz = math.cos(a), math.sin(a)
    outline = hull2d(circle_pts(0, 0, 3.3, 28) + circle_pts(13 * ux, 13 * uz, 2.0, 20))
    arm = make_obj("CARB_Throttle_Arm", bm_prism(outline, -11.4, -12.9, lambda u, v, w: (w, u, v)), col,
                   [M["plastic_black"]])
    boolean(arm, [tmp_obj(bm_cyl(0.75, (-11.0, k * ux, k * uz), (-13.3, k * ux, k * uz), 16)) for k in (9.5, 12.5)],
            "DIFFERENCE")
    idle = make_obj("CARB_Idle_Screw", bm_cyl(1.1, (-12.4, 0, 0), (-14.2, 0, 0), 16), col, [M["brass"]])
    boolean(idle, [tmp_obj(bm_box((-14.5, -0.25, -1.3), (-13.7, 0.25, 1.3)))], "DIFFERENCE")
    parts += [barrel, washer, arm, idle]
    if side_needle:  # standard-engine photo: needle valve leaving the +X end, angled rearward and down
        dv = Vector((0.55, 0.55, -0.63)).normalized()
        m = T(10.2, 0, 0) @ Vector((0, 0, 1)).rotation_difference(dv).to_matrix().to_4x4()

        def along_dv(bm):
            bmesh.ops.transform(bm, matrix=m, verts=bm.verts[:])
            return bm
        holder2 = make_obj("CARB_SideNeedle_Holder", along_dv(bm_revolve([(0, -1.0), (2.7, -1.0), (2.7, 6.2),
                                                                          (2.3, 6.6), (0, 6.6)], 32, "Z")),
                           col, [M["satin"]])
        ring = make_obj("CARB_SideNeedle_Ring", along_dv(bm_revolve([(0, 6.3), (2.95, 6.3), (2.95, 8.2), (2.7, 8.5),
                                                                     (0, 8.5)], 32, "Z")), col,
                        [M["plastic_black"]])
        teeth = [((3.0 if i % 2 == 0 else 2.74) * math.cos(math.pi * i / 24),
                  (3.0 if i % 2 == 0 else 2.74) * math.sin(math.pi * i / 24)) for i in range(48)]
        knob2 = make_obj("CARB_SideNeedle_Knob", along_dv(bm_prism(teeth, 8.2, 14.4, lambda u, v, w: (u, v, w))),
                         col, [M["steel"]])
        boolean(knob2, [tmp_obj(along_dv(bm_revolve([(0, 8.1), (3.1, 8.1), (3.1, 13.7), (2.4, 14.5), (0, 14.5)],
                                                    32, "Z")))], "INTERSECT")
        parts += [holder2, ring, knob2]
    else:  # SE photos: D-shaped cap with the mixture screw
        cap = make_obj("CARB_Barrel_Cap", bm_revolve([(0, 10.6), (5.0, 10.6), (5.0, 11.6), (4.6, 12.0), (0, 12.0)],
                                                     40, "X"), col, [M["polished"]])
        boolean(cap, [tmp_obj(bm_box((10.0, -6, -6), (12.5, 6, -3.4)))], "DIFFERENCE")  # D-shaped cap
        mix = make_obj("CARB_Mixture_Screw", bm_cyl(1.0, (11.6, 0, 0.6), (13.6, 0, 0.6), 16), col, [M["steel"]])
        boolean(mix, [tmp_obj(bm_box((13.0, -0.22, -0.6), (13.9, 0.22, 1.8)))], "DIFFERENCE")
        parts += [cap, mix]
    # needle valve on top: brass hex holder + collar, steel needle, knurled black knob, ratchet spring
    holder = make_obj("CARB_Needle_Holder", bm_cyl(2.66, (nx, ny, 7.2), (nx, ny, 10.6), 6), col, [M["brass"]])
    boolean(holder, [tmp_obj(bm_revolve([(0, 7.1), (2.3, 7.1), (2.75, 7.6), (2.75, 10.1), (2.3, 10.7), (0, 10.7)],
                                        32, "Z", center=(nx, ny)))], "INTERSECT")
    boolean(holder, [tmp_obj(bm_revolve([(0, 10.4), (1.9, 10.4), (1.9, 11.5), (1.6, 11.8), (0, 11.8)], 24, "Z",
                                        center=(nx, ny)))], "UNION")
    needle = make_obj("CARB_Needle", bm_cyl(0.9, (nx, ny, 11.5), (nx, ny, 21.0), 16), col, [M["steel"]])
    star = [((2.4 if i % 2 == 0 else 2.15) * math.cos(math.pi * i / 16),
             (2.4 if i % 2 == 0 else 2.15) * math.sin(math.pi * i / 16)) for i in range(32)]
    knob = make_obj("CARB_Needle_Knob", bm_prism(star, 20.6, 25.5, lambda u, v, w: (nx + u, ny + v, w)), col,
                    [M["plastic_black"]])
    boolean(knob, [tmp_obj(bm_revolve([(0, 20.5), (2.5, 20.5), (2.5, 24.7), (1.9, 25.6), (0, 25.6)], 32, "Z",
                                      center=(nx, ny)))], "INTERSECT")
    spring = wire_obj("CARB_Needle_Spring", [(nx + 1.8, ny, 10.9), (nx + 2.45, ny, 13.5), (nx + 2.5, ny, 18.5),
                                             (nx + 2.25, ny, 21.6)], 0.28, col, M["black"])
    bmn = bm_revolve([(0.65, 6.2), (1.35, 6.2), (1.35, 10.4), (1.8, 10.8), (1.8, 11.4), (1.4, 11.8), (1.4, 13.6),
                      (0.65, 13.6)], 24, "Y", center=(4.6, 0.5), closed=True)
    bmesh.ops.rotate(bmn, verts=bmn.verts[:], cent=(4.6, 6.6, 0.5), matrix=Rot("X", 15).to_3x3())
    nipple = make_obj("CARB_Fuel_Nipple", bmn, col, [M["brass"]])
    parts += [holder, needle, knob, spring, nipple]
    for ob in parts:
        ob.data.transform(T(*(Vector(place) * MM)))
        ob.data.update()
    return parts


CARB_OS61_P0 = dict(
    y0=-37.6, z0=25.4,                       # barrel axis (along X)
    xa=-16.4, xb=12.0, rh=8.7,               # barrel housing: -X face, +X end, radius
    rim=(1.2, -43.8, 42.6), tilt_f=18.0, tilt_x=3.0, rc=7.4, rci=6.1, ch_len=13.0,
    col_r=8.3, col_h=3.0,                    # collar where the chimney meets the body
    blk=(-12.0, 8.5, -45.0, -30.0, 13.0, 33.0, 3.0),   # main body block x0 x1 y0 y1 z0 z1 r
    nb=(10.0, 23.0, 4.3),                    # needle boss: cylinder on the needle axis (x0, x1, r)
    col_box=(12.3, 16.7, -34.8, -28.2, 29.0, 40.6, 1.6),  # narrow column up to the rear set screw
    web=(6.0, 13.5, -34.6, -28.4, 25.0, 37.0, 1.5),       # web joining the column to the body
    nyz=(-27.6, 25.5), nx_end=29.6, n_r=3.0, n_sleeve=(23.0, 24.3), tab_len=8.0,
    nip=(19.0, -14.8, 28.2), nip_base_y=-23.0, nip_boss=(-27.0, 3.0),
    k5=(14.5, -31.5, 42.3), k1=(-8.5, -33.6, 48.4), k1_base=38.0,
    stop=(-13.5, -29.5, 28.0),
    tube_r=3.4, tube_x=(11.0, 22.8),         # lower front tube on the barrel axis
    up_yz=(-39.5, 32.5), up_r=2.3,           # upper boss carrying the slotted screw
    plate_x=(22.8, 23.6), sock=(26.0, 2.0),  # stop plate, black knurled socket screw (end x, r)
    spig_r=5.2, spig_z=(8.0, 14.0),
    arm_len=10.3, arm_ang=12.0,              # arm direction (deg from straight down, + = toward front)
)


def build_carb_os61(col, M, place=None, P=None):
    """The carb of the user's engine (fitted to the SE photos through solved cameras). Model frame, mm."""
    P = dict(CARB_OS61_P0, **(P or {}))
    y0, z0 = P["y0"], P["z0"]
    parts = []

    # ---- chimney axis
    tf, tx = math.radians(P["tilt_f"]), math.radians(P["tilt_x"])
    n = Vector((math.tan(tx), -math.tan(tf), 1.0)).normalized()
    rim = Vector(P["rim"])
    base = rim - n * P["ch_len"]

    # ---- body casting: barrel housing + block + chimney + collar + needle block
    body = make_obj("CARB_Body", bm_revolve([(0, P["xa"]), (P["rh"] - 0.5, P["xa"]), (P["rh"], P["xa"] + 0.5),
                                             (P["rh"], P["xb"]), (0, P["xb"])], 64, "X", center=(y0, z0)),
                    col, [M["carb_body"]])
    x0, x1, by0, by1, bz0, bz1, br = P["blk"]
    ops = [tmp_obj(bm_box((x0, by0, bz0), (x1, by1, bz1), r=br, segs=3)),
           tmp_obj(bm_cyl(P["rc"], base - n * 2.0, rim, 64)),
           tmp_obj(bm_cyl(P["col_r"], base - n * 2.0, base + n * P["col_h"], 64))]
    nx0, nx1, nbr_ = P["nb"]
    ops.append(tmp_obj(bm_revolve([(0, nx0), (nbr_, nx0), (nbr_, nx1 - 0.6), (nbr_ - 0.6, nx1), (0, nx1)], 48, "X",
                                  center=P["nyz"])))
    cx0, cx1, cy0, cy1, cz0, cz1, cr = P["col_box"]
    ops.append(tmp_obj(bm_box((cx0, cy0, cz0), (cx1, cy1, cz1), r=cr, segs=3)))
    wx0, wx1, wy0, wy1, wz0, wz1, wr = P["web"]
    ops.append(tmp_obj(bm_box((wx0, wy0, wz0), (wx1, wy1, wz1), r=wr, segs=3)))
    tx0, tx1 = P["tube_x"]
    ops.append(tmp_obj(bm_cyl(P["tube_r"], (tx0, y0, z0), (tx1, y0, z0), 40)))   # +X lower front tube
    uy, uz = P["up_yz"]
    ops.append(tmp_obj(bm_cyl(P["up_r"], (tx0, uy, uz), (tx1, uy, uz), 32)))      # +X upper boss
    nby, nbr = P["nip_boss"]
    ops.append(tmp_obj(bm_cyl(nbr, (P["nip"][0], nby, P["nip"][2]), (P["nip"][0], P["nip_base_y"] + 0.3, P["nip"][2]), 32)))
    k1 = Vector(P["k1"])
    ops.append(tmp_obj(bm_cyl(3.4, (k1.x, k1.y, bz1 - 2.0), (k1.x, k1.y, P["k1_base"]), 6)))   # K1 boss hex
    k5 = Vector(P["k5"])
    ops.append(tmp_obj(bm_cyl(P["spig_r"] + 1.6, (0, y0, P["spig_z"][1] + 1.0), (0, y0, z0 - 4.0), 48)))
    boolean(body, ops, "UNION")
    cuts = [tmp_obj(bm_cyl(P["rci"], rim - n * 8.0, rim + n * 1.0, 48)),                    # intake bore
            tmp_obj(bm_cyl(4.4, rim - n * 30.0, rim - n * 6.0, 48)),                       # venturi
            tmp_obj(bm_cyl(P["rh"] - 2.2, (P["xa"] - 1, y0, z0), (P["xa"] + 0.8, y0, z0), 48))]  # face recess
    # internals: rotor bore, spray-bar bore, outlet down to the spigot, fuel passages needle -> spray bar
    ny_, nz_ = P["nyz"]
    nip_ = Vector(P["nip"])
    cuts += [tmp_obj(bm_cyl(5.65, (P["xa"] + 0.5, y0, z0), (10.1, y0, z0), 64)),
             tmp_obj(bm_cyl(1.55, (9.9, y0, z0), (12.7, y0, z0), 24)),
             tmp_obj(bm_cyl(3.9, (0, y0, P["spig_z"][1] + 1.0), (0, y0, z0), 48)),
             tmp_obj(bm_cyl(P["spig_r"], (0, y0, P["spig_z"][0] + 4.0), (0, y0, P["spig_z"][1] + 1.0), 48)),   # spigot seat
             tmp_obj(bm_cyl(0.55, (12.0, y0, z0), (12.0, y0, z0 + 1.6), 12)),          # up from the spray bar
             tmp_obj(bm_cyl(0.55, (12.0, y0, z0 + 1.6), (12.0, ny_, z0 + 1.6), 12)),    # across to the needle
             tmp_obj(bm_cyl(0.55, (12.0, ny_, z0 + 1.6), (12.0, ny_, nz_), 12)),        # down into its seat
             tmp_obj(bm_cyl(0.8, (11.8, ny_, nz_), (P["n_sleeve"][0] + 0.3, ny_, nz_), 16)),
             tmp_obj(bm_cyl(0.55, (nip_.x, P["nip_base_y"] - 0.5, nip_.z), (nip_.x, ny_, nip_.z), 12)),
             tmp_obj(bm_cyl(0.55, (nip_.x, ny_, nip_.z + 0.4), (nip_.x, ny_, nz_), 12))]
    boolean(body, cuts, "DIFFERENCE")
    parts.append(body)
    # throttle rotor, built 3/4 open as photographed (spray bar visible through the venturi): the hole lines up
    # with the venturi at full throttle (rotor turned a further -17.5 deg) and closes at idle (+52.5 deg)
    d_loc = Matrix.Rotation(math.radians(70.0 * (1.0 - THROTTLE_REF["os61"])), 3, "X") @ n
    rot = make_obj("CARB_Rotor", bm_revolve([(0, P["xa"] + 0.8), (5.6, P["xa"] + 0.8), (5.6, 9.7), (5.3, 10.0), (0, 10.0)],
                                            64, "X", center=(y0, z0)), col, [M["brass_dull"]])
    c0 = Vector((-0.5, y0, z0))
    boolean(rot, [tmp_obj(bm_cyl(4.2, c0 - d_loc * 8.0, c0 + d_loc * 8.0, 48)),
                  tmp_obj(bm_cyl(1.6, (P["xa"], y0, z0), (10.5, y0, z0), 24))], "DIFFERENCE")
    parts.append(rot)
    bar = make_obj("CARB_Spray_Bar", bm_revolve([(0, -13.0), (1.5, -13.0), (1.5, 12.5), (0.6, 12.5), (0.6, -0.8), (0, -0.8)],
                                                24, "X", center=(y0, z0)), col, [M["brass"]])
    boolean(bar, [tmp_obj(bm_cyl(0.4, (-0.5, y0, z0), Vector((-0.5, y0, z0)) - n * 2.5, 12)),       # jet, downstream
                  tmp_obj(bm_cyl(0.5, (11.7, y0, z0), (11.7, y0, z0 + 2.0), 12))], "DIFFERENCE")  # fuel inlet (top)
    parts.append(bar)
    parts.append(make_obj("CARB_Needle", bm_revolve([(0, 11.9), (0.75, 12.8), (0.75, P["n_sleeve"][0]), (0, P["n_sleeve"][0])],
                                                    24, "X", center=(ny_, nz_)), col, [M["steel"]]))

    # ---- -X face: barrel end (khaki), black arm hub, arm, Phillips pivot screw
    xa = P["xa"]
    parts.append(make_obj("CARB_Barrel_End", bm_revolve([(0, xa + 0.8), (P["rh"] - 2.3, xa + 0.8), (P["rh"] - 2.3, xa - 0.3),
                                                         (P["rh"] - 2.6, xa - 0.6), (0, xa - 0.6)], 48, "X",
                                                        center=(y0, z0)), col, [M["brass_dull"]]))
    parts.append(make_obj("CARB_Arm_Hub", bm_revolve([(0, xa - 0.5), (4.3, xa - 0.5), (4.3, xa - 2.0), (3.9, xa - 2.4),
                                                      (0, xa - 2.4)], 40, "X", center=(y0, z0)), col,
                          [M["plastic_black"]]))
    a = math.radians(P["arm_ang"])
    du, dv = -math.sin(a), -math.cos(a)        # (y, z) direction of the arm
    L = P["arm_len"]
    outline = hull2d(circle_pts(0, 0, 3.6, 28) + circle_pts(L * du, L * dv, 2.3, 20))
    arm = make_obj("CARB_Throttle_Arm", bm_prism(outline, xa - 1.9, xa - 3.2,
                                                 lambda u, v, w: (w, y0 + u, z0 + v)), col, [M["plastic_black"]])
    boolean(arm, [tmp_obj(bm_cyl(0.65, (xa - 1.5, y0 + k * du, z0 + k * dv), (xa - 3.6, y0 + k * du, z0 + k * dv), 16))
                  for k in (L * 0.48, L * 0.74, L)], "DIFFERENCE")
    parts.append(arm)
    piv = make_obj("CARB_Arm_Screw", bm_revolve([(0, xa - 3.1), (2.1, xa - 3.1), (2.1, xa - 3.9), (1.6, xa - 4.5),
                                                 (0, xa - 4.6)], 24, "X", center=(y0, z0)), col, [M["black"]])
    boolean(piv, [tmp_obj(bm_box((xa - 5, y0 - 1.5, z0 - 0.3), (xa - 4.1, y0 + 1.5, z0 + 0.3))),
                  tmp_obj(bm_box((xa - 5, y0 - 0.3, z0 - 1.5), (xa - 4.1, y0 + 0.3, z0 + 1.5)))], "DIFFERENCE")
    parts.append(piv)

    # ---- throttle stop screw (rear of the -X end) with knurled lock ring
    st = Vector(P["stop"])
    parts.append(make_obj("CARB_Stop_Screw", bm_revolve([(0, st.y - 1.2), (1.25, st.y - 1.2), (1.25, st.y + 2.4), (1.6, st.y + 2.6),
                                                         (1.6, st.y + 3.8), (0, st.y + 3.8)], 20, "Y",
                                                        center=(st.x, st.z)), col, [M["steel"]]))
    parts.append(make_obj("CARB_Stop_Ring", bm_cyl(2.2, (st.x, st.y - 0.2, st.z), (st.x, st.y + 1.4, st.z), 20), col,
                          [M["black"]]))

    # ---- +X front: stop plate between the two bosses, black knurled socket screw, slotted screw
    px0, px1 = P["plate_x"]
    outline = hull2d(circle_pts(y0, z0, 2.7, 24) + circle_pts(uy, uz, 2.4, 24))
    plate = make_obj("CARB_Stop_Plate", bm_prism(outline, px0, px1, lambda u, v, w: (w, u, v)), col, [M["steel"]])
    boolean(plate, [tmp_obj(bm_box((px0 - 0.5, uy - 0.4, uz - 4.2), (px1 + 0.5, uy + 0.4, uz - 2.0)))], "DIFFERENCE")
    parts.append(plate)
    sx1, sr = P["sock"]
    teeth = [((sr if i % 2 == 0 else sr - 0.18) * math.cos(math.pi * i / 18),
              (sr if i % 2 == 0 else sr - 0.18) * math.sin(math.pi * i / 18)) for i in range(36)]
    sock = make_obj("CARB_Idle_Screw", bm_prism(teeth, px1, sx1, lambda u, v, w: (w, y0 + u, z0 + v)), col, [M["black"]])
    boolean(sock, [tmp_obj(bm_cyl(0.85, (sx1 - 1.4, y0, z0), (sx1 + 0.5, y0, z0), 6))], "DIFFERENCE")
    parts.append(sock)
    ss = make_obj("CARB_Slot_Screw", bm_revolve([(0, px1), (1.9, px1), (1.9, px1 + 1.0), (1.6, px1 + 1.3), (0, px1 + 1.3)],
                                                24, "X", center=(uy, uz)), col, [M["steel"]])
    boolean(ss, [tmp_obj(bm_box((px1 + 0.7, uy - 2.5, uz - 0.25), (px1 + 1.6, uy + 2.5, uz + 0.25)))], "DIFFERENCE")
    parts.append(ss)

    # ---- needle valve along +X: polished sleeve, black knob (hollow end), flat ratchet tab
    ny, nz = P["nyz"]
    s0, s1 = P["n_sleeve"]
    parts.append(make_obj("CARB_Needle_Sleeve", bm_revolve([(0, s0 - 0.3), (2.9, s0 - 0.3), (2.9, s1), (0, s1)], 32, "X",
                                                           center=(ny, nz)), col, [M["polished"]]))
    xe = P["nx_end"]
    knob = make_obj("CARB_Needle_Knob", bm_revolve([(0, s1 - 0.1), (P["n_r"], s1 - 0.1), (P["n_r"], xe - 0.4),
                                                    (P["n_r"] - 0.4, xe), (1.9, xe), (1.9, xe - 3.0), (0, xe - 3.0)],
                                                   40, "X", center=(ny, nz)), col, [M["plastic_black"]])
    parts.append(knob)
    parts.append(make_obj("CARB_Needle_Tab", bm_box((xe - 2.5, ny - 0.45, nz - 1.3), (xe - 2.5 + P["tab_len"], ny + 0.45, nz + 0.6),
                                                    r=0.3, segs=2), col, [M["plastic_black"]]))
    parts.append(make_obj("CARB_Needle_Tip", bm_cyl(0.9, (xe - 3.2, ny, nz), (xe - 0.6, ny, nz), 16), col, [M["steel"]]))

    # ---- fuel nipple from the needle block (points rearward)
    nip = Vector(P["nip"])
    yb = P["nip_base_y"]
    parts.append(make_obj("CARB_Fuel_Nipple", bm_revolve([(0.6, yb - 0.3), (2.3, yb - 0.3), (2.3, yb + 2.0), (1.3, yb + 2.2),
                                                          (1.3, nip.y - 2.2), (1.75, nip.y - 1.8), (1.75, nip.y - 1.0),
                                                          (1.25, nip.y - 0.4), (1.25, nip.y), (0.6, nip.y)], 24, "Y",
                                                         center=(nip.x, nip.z), closed=True), col, [M["nickel"]]))

    # ---- K5: rusty set screw on the rear boss
    parts.append(make_obj("CARB_Set_Screw", bm_cyl(1.7, (k5.x, k5.y, P["col_box"][5] - 0.6), (k5.x, k5.y, k5.z), 24), col,
                          [M["rust"]]))

    # ---- K1: top screw on a threaded stud with lock nut (rear, -X side)
    kb = P["k1_base"]
    parts.append(make_obj("CARB_Top_Stud", bm_cyl(1.5, (k1.x, k1.y, kb - 0.5), (k1.x, k1.y, k1.z - 1.6), 16), col, [M["steel"]]))
    parts.append(make_obj("CARB_Top_Nut", bm_cyl(3.1, (k1.x, k1.y, kb - 0.05), (k1.x, k1.y, kb + 2.8), 6), col, [M["steel"]]))
    head = make_obj("CARB_Top_Screw", bm_revolve([(0, k1.z - 2.0), (2.6, k1.z - 2.0), (2.6, k1.z - 0.3), (2.3, k1.z),
                                                  (0, k1.z)], 24, "Z", center=(k1.x, k1.y)), col, [M["steel"]])
    boolean(head, [tmp_obj(bm_box((k1.x - 3, k1.y - 0.25, k1.z - 0.8), (k1.x + 3, k1.y + 0.25, k1.z + 0.5)))], "DIFFERENCE")
    parts.append(head)

    # ---- spigot down into the crankcase pedestal
    # spigot: reduced lower step (the two M3x6 retainers in the pedestal ears sit over its shoulder)
    parts.append(make_obj("CARB_Spigot", bm_revolve([(3.9, 8.25), (4.6, 8.25), (4.6, 10.0), (P["spig_r"], 10.3),
                                                     (P["spig_r"], 10.9), (4.55, 10.9), (4.55, 11.7), (P["spig_r"], 11.7),
                                                     (P["spig_r"], P["spig_z"][1] + 1.0), (3.9, P["spig_z"][1] + 1.0)],
                                                    48, "Z", center=(0, y0), closed=True), col, [M["cast"]]))
    orb = bm_torus(4.89, 0.32, segs=48, rsegs=10)                  # O-ring sealing the spigot in the pedestal
    bmesh.ops.translate(orb, verts=orb.verts[:], vec=(0, y0, 11.3))
    parts.append(make_obj("CARB_Spigot_ORing", orb, col, [M["plastic_black"]]))
    return parts


def build_carb(col, M, kind="os61", place=None, side_needle=False):
    if kind == "os61":
        parts = build_carb_os61(col, M)
        if place is not None:  # carb-only builds: move the barrel axis to `place`
            off = (Vector(place) - Vector(CARB_PLACE["os61"])) * MM
            for ob in parts:
                ob.data.transform(T(*off))
                ob.data.update()
        return parts
    place = place if place is not None else CARB_PLACE[kind]
    if kind == "modern":
        return build_carb_modern(col, M, place=place, throttle=0.0)
    return build_carb_classic(col, M, place=place, side_needle=side_needle)


THROTTLE_PARTS = {"os61": ("CARB_Barrel_End", "CARB_Rotor", "CARB_Arm_Hub", "CARB_Throttle_Arm", "CARB_Arm_Screw"),
                  "classic": ("CARB_Barrel", "CARB_Throttle_Arm", "CARB_Idle_Screw"),
                  "modern": ("CARB_Barrel", "CARB_Arm_Hub", "CARB_Throttle_Arm")}
DRIVE_PARTS = ("ENG_Drive_Hub", "ENG_Woodruff_Key", "ENG_Thrust_Washer", "ENG_Prop_Washer", "ENG_Prop_Nut",
               "ENG_Crankshaft_Thread")


def set_origin(ob, p_mm):
    """Move the object origin to p (mm, world) without moving the geometry."""
    p = Vector(p_mm) * MM - ob.matrix_world.translation
    ob.data.transform(T(*(-p)))
    ob.location = ob.location + p


def add_driver(ob, index, root, prop, expr, path="rotation_euler"):
    fc = ob.driver_add(path, index) if index is not None else ob.driver_add(path)
    drv = fc.driver
    drv.type = "SCRIPTED"
    v = drv.variables.new()
    v.name, v.type = "v", "SINGLE_PROP"
    v.targets[0].id_type = "OBJECT"
    v.targets[0].id = root
    v.targets[0].data_path = f'["{prop}"]'
    drv.expression = expr  # simple expressions only: they run without Python auto-exec
    return drv


def rig_controls(root, parts, carb, place_mm, throttle=0.0, drive=True, mech_roles=None, K=None):
    """Pivot origins + custom-property drivers on the root empty:
      throttle (0..1): carb rotor, end cap and arm turn 70 deg about the barrel axis;
      crank_deg: crankshaft (with hub, key, nut, washer, thread, inner races as children) turns CCW seen
      from the front; the piston follows the exact crank-slider law and the rod swings about the wrist pin;
      balls and cages turn at 0.4x;
      cutaway (0 / 1 / 2): section views (1 = +X half removed, 2 = rear half removed)."""
    names = {p.name: p for p in parts}
    for p in parts:  # tidy origins: bounding-box centre for static parts (instanced screws keep theirs)
        if (p.type == "MESH" and p.data.users == 1 and p.name not in THROTTLE_PARTS[carb] + DRIVE_PARTS
                and not p.get("pivot") and p.parent in (None, root)):
            bpy.context.view_layer.update()
            c = sum((p.matrix_world @ Vector(v) for v in p.bound_box), Vector()) / 8
            set_origin(p, c / MM)
    root["throttle"] = float(throttle)
    root.id_properties_ui("throttle").update(min=0.0, max=1.0, soft_min=0.0, soft_max=1.0, step=5,
                                             description="Carburetor opening: 0 = idle, 1 = full throttle")
    for n in THROTTLE_PARTS[carb]:
        if n in names:
            set_origin(names[n], place_mm)
            ref = THROTTLE_REF.get(carb, 0.0)   # 70 deg of barrel travel, parts built at throttle = ref
            add_driver(names[n], 0, root, "throttle", f"(v - {ref}) * -1.2217" if ref else "v * -1.2217")
    if not drive:
        return
    root["crank_deg"] = 0.0
    root.id_properties_ui("crank_deg").update(soft_min=-360.0, soft_max=360.0,
                                              description="Crank angle after TDC (deg), CCW seen from the front. "
                                                          "Keyframe it to run the engine")
    if not mech_roles:
        return
    r, L = K["r"] * MM, K["rod"] * MM
    add_driver(mech_roles["crank"], 1, root, "crank_deg", "-radians(v)")
    za = K["za"] * MM
    add_driver(mech_roles["piston"], 2, root, "crank_deg",
               f"{za!r}+{r!r}*cos(radians(v))+sqrt({L * L!r}-pow({r!r}*sin(radians(v)),2))", path="location")
    add_driver(mech_roles["rod"], 1, root, "crank_deg", f"asin({r / L!r}*sin(radians(v)))")
    for ob in mech_roles["spin"]:
        add_driver(ob, 1, root, "crank_deg", "-radians(v)*0.4")


CUT_MODES = {1: ((0.011, -300.0, -300.0), (300.0, 300.0, 300.0)),   # +X half removed: crank, intake, transfers
             2: ((-300.0, 0.011, -300.0), (300.0, 300.0, 300.0))}   # rear half removed: rod, piston, ports
# (planes sit 0.011 mm off the symmetry planes: exact booleans dislike cut planes through mesh vertices)


def add_cutaway(root, objs, col):
    """Section views without touching the meshes: one boolean per mode on every part, switched by
    root["cutaway"] through simple-expression drivers (off by default, so nothing is evaluated)."""
    root["cutaway"] = 0
    root.id_properties_ui("cutaway").update(min=0, max=len(CUT_MODES), description="0 off, 1 +X half, 2 rear half")
    cutters = {}
    for k, (lo, hi) in CUT_MODES.items():
        c = make_obj(f"CUT_Section_{k}", bm_box(lo, hi), col, smooth=False)
        c.display_type, c.hide_render = "WIRE", True
        c.hide_set(True)
        cutters[k] = c
    for ob in objs:
        if ob.type != "MESH":
            continue
        for k, c in cutters.items():
            m = ob.modifiers.new(f"CUT_{k}", "BOOLEAN")
            m.operation, m.solver, m.object = "DIFFERENCE", "EXACT", c
            m.use_hole_tolerant = True     # threaded fasteners carry a few non-manifold edges at the thread run-out
            m.show_viewport = m.show_render = False
            for prop in ("show_viewport", "show_render"):
                add_driver(ob, None, root, "cutaway", f"v=={k}", path=f'modifiers["CUT_{k}"].{prop}')
    return list(cutters.values())


def K_front_brg_face():
    return mech()["front_brg"][3]


def build_front(col, M, V=None):
    """Drive hub keyed to the shaft with a Woodruff key (serrated prop face), brass thrust washer against the
    front bearing's inner race, black
    drive washer, prop space, nut and the 5/16-24 crankshaft thread (photo layout outside)."""
    h0, h1 = HUB_Y
    hub = make_obj("ENG_Drive_Hub", bm_revolve([(4.02, h0), (10.6, h0), (11.0, h0 - 0.4), (11.0, -53.9), (10.4, -54.3),
                                                (10.4, -55.0), (11.6, -55.3), (12.0, -55.7), (12.0, -59.0), (11.3, -59.35),
                                                (11.3, -59.95), (12.0, -60.3), (12.0, h1 + 0.5), (11.5, h1), (4.02, h1)],
                                               96, "Y", closed=True), col, [M["polished"]])
    cuts = [tmp_obj(bm_box((-1.03, h1 - 0.7, 3.4), (1.03, h0 + 0.7, 5.12)))]      # keyway for the Woodruff key
    for k in range(48):                                  # radial, slightly swept serrations on the prop face
        g = bm_box((-0.26, h1 - 0.4, 5.4), (0.26, h1 + 0.3, 11.2))
        bmesh.ops.rotate(g, verts=g.verts[:], cent=(0, 0, 5.4), matrix=Rot("Y", 14.0).to_3x3())
        bmesh.ops.rotate(g, verts=g.verts[:], cent=(0, 0, 0), matrix=Rot("Y", 7.5 * k).to_3x3())
        cuts.append(tmp_obj(g))
    boolean(hub, cuts, "DIFFERENCE")
    key = make_obj("ENG_Woodruff_Key", woodruff_bm(0.0), col, [M["steel"]])
    t0 = K_front_brg_face() - 0.01                      # brass thrust washer on the front bearing's inner race
    thrust = make_obj("ENG_Thrust_Washer", bm_revolve([(4.05, t0 - 0.28), (6.3, t0 - 0.28), (6.3, t0), (4.05, t0)], 48,
                                                      "Y", closed=True), col, [M["brass"]])
    # washer against the hub (standard photo) or in front of the prop (SE photos: prop, backplate, cone)
    w0 = h1 + 0.4 if (V or {}).get("washer", "hub") == "hub" else PROP_P0["prop_y"][1] - 0.05
    washer = make_obj("ENG_Prop_Washer", bm_revolve([(4.35, w0), (11.2, w0), (11.6, w0 - 0.4), (11.6, w0 - 2.0),
                                                     (11.2, w0 - 2.4), (4.35, w0 - 2.4)], 64, "Y", closed=True),
                      col, [M["black"]])
    n0 = w0 - 9.6 if (V or {}).get("washer", "hub") == "hub" else w0 - 1.9
    nut = make_obj("ENG_Prop_Nut", bm_cyl(6.35, (0, n0, 0), (0, n0 - 6.5, 0), 6), col, [M["black"]])
    cham = tmp_obj(bm_revolve([(0, n0 + 0.1), (5.7, n0 + 0.1), (6.6, n0 - 0.8), (6.6, n0 - 5.6), (5.7, n0 - 6.6),
                               (0, n0 - 6.6)], 48, "Y"))
    boolean(nut, [cham], "INTERSECT")
    boolean(nut, [tmp_obj(bm_cyl(3.36, (0, n0 + 1, 0), (0, n0 - 8, 0), 32))], "DIFFERENCE")   # tapped 5/16-24
    shaft = make_obj("ENG_Crankshaft_Thread", bm_thread(h1 - 0.1, -88.0, 3.97, 1.058, 0.62), col, [M["steel"]])
    parts = [hub, key, thrust, washer, nut, shaft]
    for p_ in parts:                                    # built about z = 0: onto the crank axis
        za_ob(p_)
    return parts


WOODRUFF = dict(y=-56.1, D=8.0, h=3.0, b=2.0, top=5.0)   # 2 x 3 x 8 mm key on the 8 mm hub seat
# drive hub (photos B, B2): 11 mm long, 24 mm across, two turned grooves; serrated prop face at HUB_Y[1]
HUB_Y = (-50.6, -61.6)


def woodruff_bm(grow=0.0, slot=False):
    """Woodruff (half-moon) key in the YZ plane: circle segment, flat edge up at z=top. slot=True gives the
    seat cut in the shaft (open above the shaft surface)."""
    W = WOODRUFF
    R, zc = W["D"] / 2 + grow, W["top"] - W["h"] + W["D"] / 2
    top = (W["top"] + 2.0) if slot else W["top"]
    pts = []
    t0 = math.degrees(math.asin(max(-1.0, min(1.0, (top - zc) / R))))
    a0, a1 = 180.0 - t0, 360.0 + t0
    for i in range(33):
        a = math.radians(a0 + (a1 - a0) * i / 32)
        pts.append((W["y"] + R * math.cos(a), zc + R * math.sin(a)))
    bm = bm_prism(pts, -W["b"] / 2 - grow, W["b"] / 2 + grow, lambda u, v, w: (w, u, v))
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    return bm


MUF_P0 = dict(  # muffler of the SE engine, least-squares fitted to silhouettes in photos B, A, T, E (mm, model frame)
    tip=(-62.69, -35.76, 48.5), end=(-82.04, 111.73, 49.89),   # front dome tip and outlet end (on the can axis)
    R=18.72, kx=1.125, dome=19.8, seam=77.3,               # R = vertical semi-axis; kx = horizontal / vertical
    cone=(0.878, 0.768, 0.463),                            # ogive radii at 1/4, 1/2, 3/4 of the cone (fraction)
    out_r=5.6, out_ri=4.2, out_len=13.0, wall=1.6,
    collar=(2.6, 0.5, 0.85),          # seam: collar length, collar step, cone step (front casting overlaps the cone)
    # raised panel on the top of the front casting: s_front, s_rear at phi0, s_rear at phi1, phi0, phi1 (deg from
    # the top toward +X), height; ribs: count, radius, phi range, front s
    panel=(17.5, 62.0, 70.0, -44.0, 30.0, 1.1), ribs=8, rib_r=1.05, rib_h=0.8, rib_phi=(-37.0, 23.0), rib_s0=19.8,
    # manifold arm (box under the can's inner side) and its six cross ribs (triangulated in photos T, E, D)
    arm=(-62.0, -23.0, -10.5, 12.5, 29.5, 42.9, 2.0), arm_ribs=6, arm_rib_x=(-29.7, -46.5), arm_rib_y=(-7.6, 9.8),
    arm_low=(-62.0, -34.2, -12.5, 17.0, 30.0, 37.0, 1.5),   # wider lower body: ledges in front of / behind the arm
    flange=(-30.3, -22.75, -19.35, 23.35, 27.35, 38.55, 5.3),
    plate=(-66.0, -52.0, -19.0, 30.0, 27.6, 32.4, 2.4),    # long lower plate under the can (seen from -X)
    nipple=(60.0, 44.0), pad=(6.0, 3.0, 9.2, 1.2), pad_hole=7.7,   # nipple s, phi; pad width, ahead, behind, height
    tab=(33.5, -123.0, 4.0, 3.0, 4.5),                     # lug on the lower -X side: s, phi, width, thickness, reach
    baffle_s=95.0,
)


def _pchip(xs, ys, m0=None):
    """Monotone cubic (Fritsch-Carlson) through the points; returns f(x). m0 overrides the first slope."""
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [d[0]] + [0.0] * (n - 2) + [d[-1]]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    if m0 is not None:
        m[0] = m0

    def f(x):
        i = max(0, min(n - 2, next((k for k in range(n - 1) if x <= xs[k + 1]), n - 2)))
        t = (x - xs[i]) / h[i]
        h00, h10, h01, h11 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t, -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
        return h00 * ys[i] + h10 * h[i] * m[i] + h01 * ys[i + 1] + h11 * h[i] * m[i + 1]
    return f


def muf_geom(P):
    """Can frame and profile functions: W (local->model, +Y along the axis from the tip), r(s), kx(s), surf(s, phi, dh)."""
    F, O = Vector(P["tip"]), Vector(P["end"])
    d = O - F
    L = d.length
    W = T(*F) @ Vector((0, 1, 0)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    R, dm, sz = P["R"], P["dome"], P["seam"]
    so = L - P["out_len"]
    cl, st1, st2 = P["collar"]
    c1, c2, c3 = P["cone"]
    r0 = R - st2
    ro = P["out_r"]
    xs = [sz, sz + 0.25 * (so - sz), sz + 0.5 * (so - sz), sz + 0.75 * (so - sz), so]
    cone = _pchip(xs, [r0, ro + c1 * (R - ro), ro + c2 * (R - ro), ro + c3 * (R - ro), ro + 0.45], m0=0.0)

    def r(s):
        if s < dm:
            return R * math.sqrt(max(0.0, 1 - (1 - s / dm) ** 2))
        if s < sz - cl:
            return R
        if s < sz:
            return R - st1
        if s <= so:
            return cone(s)
        return ro
    sk = sz + 0.6 * (so - sz)

    def kx(s):
        if s <= sk:
            return P["kx"]
        if s >= so:
            return 1.0
        t = (s - sk) / (so - sk)
        return P["kx"] + (1.0 - P["kx"]) * t * t * (3 - 2 * t)

    def surf(s, phi, dh=0.0):
        a, b = kx(s) * r(s), r(s)
        sp, cp = math.sin(math.radians(phi)), math.cos(math.radians(phi))
        n = Vector((b * sp, 0.0, a * cp))
        n = n.normalized() if n.length > 1e-9 else Vector((0, 0, 1))
        return Vector((a * sp, s, b * cp)) + n * dh
    return dict(W=W, L=L, so=so, r=r, kx=kx, surf=surf, cone=cone)


def bm_patch(Pf, nu, nv, dense=True):
    """Closed solid from a parametric patch Pf(u, v, w) -> Vector (u, v in [0, 1]; w = 0 inner, 1 outer)."""
    bm = bmesh.new()

    def sp(t):   # half cosine spacing: denser rows along the ramped edges
        return 0.5 * t + 0.25 - 0.25 * math.cos(math.pi * t) if dense else t
    G = [[[bm.verts.new(Pf(sp(i / nu), sp(j / nv), w)) for j in range(nv + 1)] for i in range(nu + 1)] for w in (0, 1)]
    for w in (0, 1):
        g = G[w]
        for i in range(nu):
            for j in range(nv):
                bm.faces.new((g[i][j], g[i + 1][j], g[i + 1][j + 1], g[i][j + 1]))
    loop = ([(i, 0) for i in range(nu)] + [(nu, j) for j in range(nv)] + [(i, nv) for i in range(nu, 0, -1)]
            + [(0, j) for j in range(nv, 0, -1)])
    for k in range(len(loop)):
        a, b = loop[k], loop[(k + 1) % len(loop)]
        bm.faces.new((G[0][a[0]][a[1]], G[0][b[0]][b[1]], G[1][b[0]][b[1]], G[1][a[0]][a[1]]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def bm_capsule(r, s0, s1, center=(0.0, 0.0), n=6, segs=16):
    """Round-ended bar along +Y (local) from s0 to s1 (cast ribs)."""
    prof = [(0.0, s0)] + [(r * math.sin(math.pi / 2 * k / n), s0 + r * (1 - math.cos(math.pi / 2 * k / n))) for k in range(1, n + 1)]
    nl = max(1, int((s1 - s0 - 2 * r) / 1.5))      # rings along the bar keep boolean cuts well conditioned
    prof += [(r, s0 + r + (s1 - s0 - 2 * r) * k / nl) for k in range(1, nl)]
    prof += [(r * math.cos(math.pi / 2 * k / n), s1 - r + r * math.sin(math.pi / 2 * k / n)) for k in range(0, n)] + [(0.0, s1)]
    return bm_revolve(prof, segs, "Y", center=center)


def bm_sweep(pts, radius, segs=8, up=(0, 0, 1)):
    """Tube of `radius` along a polyline lying in the plane normal to `up` (closed with flat caps)."""
    bm = bmesh.new()
    up = Vector(up)
    rings = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        nrm = t.cross(up).normalized()
        rings.append([bm.verts.new(p + radius * (math.cos(2 * math.pi * k / segs) * nrm + math.sin(2 * math.pi * k / segs) * up))
                      for k in range(segs)])
    for A, B in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((A[k], A[(k + 1) % segs], B[(k + 1) % segs], B[k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def build_muffler(col, M, screw_me):
    """Oval cast front section (domed, ribbed top panel, parting line, seam collar) pressed onto an ogive tail;
    ribbed manifold arm with the bolted flange block, long lower plate, pressure nipple, side lug."""
    P = dict(MUF_P0, **FIT.get("muffler", {}))
    G = muf_geom(P)
    W, L, so, rf, kxf, surf = G["W"], G["L"], G["so"], G["r"], G["kx"], G["surf"]

    def to_world(bm):
        bmesh.ops.transform(bm, matrix=W, verts=bm.verts[:])
        return bm

    def ovalize(bm, grow=0.0):
        for v in bm.verts:
            v.co.x *= kxf(v.co.y + grow)
        return bm
    R, dm, sz = P["R"], P["dome"], P["seam"]
    cl, st1, st2 = P["collar"]
    # ---- can: dome, front casting with its collar, groove at the joint, ogive, outlet tube (one revolve)
    prof = [(0.0, 0.0)]
    for k in range(1, 25):
        t = math.pi / 2 * k / 24
        prof.append((R * math.sin(t), dm * (1 - math.cos(t))))
    nc = int((sz - cl - 0.35 - dm) / 0.9)   # rings every ~0.9 mm along the front casting: the panel, ribs and parting
    prof += [(R, dm + (sz - cl - 0.35 - dm) * k / nc) for k in range(1, nc + 1)]   # line cut it into tidy faces
    prof += [(R - st1, sz - cl + 0.05), (R - st1, sz - 0.35), (R - st2 - 0.3, sz - 0.1),
             (R - st2 - 0.3, sz + 0.1), (R - st2, sz + 0.3)]
    n_c = 28
    for k in range(1, n_c + 1):
        s_ = sz + 0.3 + (so - sz - 0.3) * k / n_c
        prof.append((rf(s_), s_))
    ro_ = P["out_r"]   # the tail tube is pressed into the cone: a small bead at the joint
    prof += [(ro_ + 0.62, so + 0.25), (ro_ + 0.62, so + 1.05), (ro_ + 0.2, so + 1.45), (ro_, so + 1.75),
             (ro_, L - 0.4), (ro_ - 0.4, L),
             (P["out_ri"], L), (P["out_ri"], so + 2.0), (0.0, so + 2.0)]
    can = make_obj("MUF_Can", to_world(ovalize(bm_revolve(prof, 72, "Y"))), col, [M["muf_cast"]])
    ops = []
    # ---- raised panel: follows the oval top, slanted rear edge, ramped (cast-draft) edges
    s0, sr0, sr1, ph0, ph1, ph = P["panel"]

    n_r, rr, rh = P["ribs"], P["rib_r"], P["rib_h"]
    pa, pb = P["rib_phi"]
    rphi = [pa + (pb - pa) * k / max(n_r - 1, 1) for k in range(n_r)]
    rend = [sr0 + (sr1 - sr0) * (f - ph0) / (ph1 - ph0) - 2.6 for f in rphi]
    arc = math.radians(1.0) * R * 0.5 * (1 + P["kx"])   # mm of surface per degree (mean of the oval's radii)

    def panel_pt(u, v, w):
        """Panel and its eight round-ended ribs as ONE height field over the can (no rib booleans)."""
        phi = ph0 + (ph1 - ph0) * u
        s1 = sr0 + (sr1 - sr0) * u
        s = s0 + (s1 - s0) * v
        if w == 0:
            return surf(s, phi, -1.4)
        e = min(min(u, 1 - u) * (ph1 - ph0) * arc / 1.1, (s - s0) / 2.2, (s1 - s) / 1.6, 1.0)
        e = e * e * (3 - 2 * e)
        h = -0.3 + (ph + 0.3) * e
        for f, se in zip(rphi, rend):
            dx = (phi - f) * arc
            if abs(dx) >= rr:
                continue
            de = max(P["rib_s0"] + rr - s, 0.0, s - (se - rr))      # beyond the straight part: round end
            q = (dx * dx + de * de) / (rr * rr)
            if q < 1.0:
                h += rh * (1.0 - q) * (1.0 + 0.35 * q)   # full-bodied rounded bar, finite flank slope (no aliasing)
        return surf(s, phi, h)
    ops.append(tmp_obj(to_world(bm_patch(panel_pt, int((ph1 - ph0) * arc / 0.2), int((sr1 - s0) / 0.33), dense=False))))
    # ---- manifold arm (merges into the can's lower inner quadrant), flange block, lower plate
    a0, a1, ay0, ay1, az0, az1, ar = P["arm"]
    ops.append(tmp_obj(bm_box((a0, ay0, az0), (a1, ay1, az1), r=ar, axis=(1, 0, 0), segs=4)))
    l0, l1, ly0, ly1, lz0, lz1, lr = P["arm_low"]
    ops.append(tmp_obj(bm_box((l0, ly0, lz0), (l1, ly1, lz1), r=lr, axis=(1, 0, 0), segs=3)))
    fx0, fx1, fy0, fy1, fz0, fz1, fr = P["flange"]
    ops.append(tmp_obj(bm_box((fx0, fy0, fz0), (fx1, fy1, fz1), r=fr, axis=(1, 0, 0), segs=6)))
    p0, p1, py0, py1, pz0, pz1, pr = P["plate"]
    ops.append(tmp_obj(bm_box((p0, py0, pz0), (p1, py1, pz1), r=pr, segs=4)))
    rx0, rx1 = P["arm_rib_x"]
    ry0, ry1 = P["arm_rib_y"]
    for k in range(P["arm_ribs"]):
        x = rx0 + (rx1 - rx0) * k / max(P["arm_ribs"] - 1, 1)
        ops.append(tmp_obj(bm_capsule(0.8, ry0, ry1, center=(x, az1 - 0.1), segs=14)))
    # ---- pressure-nipple pad and the lug on the lower -X side
    ns, nphi = P["nipple"]
    pw, pa_, pb_, phh = P["pad"]
    pad = bm_box((-pw / 2, -pa_, -2.5), (pw / 2, pb_, phh), r=1.6, axis=(0, 0, 1), segs=3)
    cpad = surf(ns, nphi, 0.0)
    bmesh.ops.transform(pad, matrix=T(cpad.x, ns, cpad.z) @ Rot("Y", nphi), verts=pad.verts[:])
    ops.append(tmp_obj(to_world(pad)))
    ts, tphi, tw, tt, treach = P["tab"]
    tab = bm_box((-tt / 2, -tw / 2, -3.0), (tt / 2, tw / 2, treach), r=1.2, axis=(1, 0, 0), segs=3)
    ctab = surf(ts, tphi, 0.0)
    bmesh.ops.transform(tab, matrix=T(ctab.x, ts, ctab.z) @ Rot("Y", tphi), verts=tab.verts[:])
    ops.append(tmp_obj(to_world(tab)))
    # ---- casting parting line: a fine ridge in the horizontal mid-plane, round the dome and along both sides
    pts = []
    for k in range(60, -1, -1):
        s_ = (sz - cl - 0.6) * (1 - math.cos(math.pi / 2 * k / 60))
        pts.append(Vector((kxf(s_) * rf(s_), s_, 0.6)))    # 0.6 mm off the mid-plane: clear of the dome pole
    pts += [Vector((-p.x, p.y, 0.6)) for p in reversed(pts[:-1])]   # or the revolve's seam vertices
    ops.append(tmp_obj(to_world(bm_sweep(pts, 0.32, 8))))
    boolean(can, ops, "UNION")
    # ---- cuts: pressure tap, bolt clearance, hollow interior, inlet duct
    cuts = []
    for ds, z0, rh in ((0.0, -2.6, 0.5), (P["pad_hole"], P["pad"][3] - 1.0, 0.9)):   # tap under the nipple; blind spare hole
        hole = bm_cyl(rh, (0, 0, z0), (0, 0, 3.0), 16)
        bmesh.ops.transform(hole, matrix=T(cpad.x, ns + ds, cpad.z) @ Rot("Y", nphi), verts=hole.verts[:])
        cuts.append(tmp_obj(to_world(hole)))
    cuts += [tmp_obj(bm_cyl(1.65, (fx0 - 0.3, y, 33.0), (fx1 + 0.4, y, 33.0), 20)) for y in MUF_BOLT_Y]
    tw_ = P["wall"]
    iprof = [(0.0, tw_)]
    for k in range(1, 25):
        t = math.pi / 2 * k / 24
        iprof.append(((R - tw_) * math.sin(t), tw_ + (dm - tw_) * (1 - math.cos(t))))
    for k in range(0, 41):
        s_ = dm + (so - 1.0 - dm) * k / 40
        ri = rf(s_) - tw_
        if ri > P["out_ri"] + 0.05:
            iprof.append((ri, s_))
    iprof += [(P["out_ri"] - 0.15, iprof[-1][1] + 1.0), (P["out_ri"] - 0.15, so + 2.6), (0.0, so + 2.6)]
    cuts.append(tmp_obj(to_world(ovalize(bm_revolve(iprof, 72, "Y")))))
    boolean(can, cuts, "DIFFERENCE")
    mid_a = rrect_yz(-31.6, 2.0, 34.75, 9.2, 2.9, 1.9)      # overlapping hulls (no shared face)
    mid_b = rrect_yz(-31.0, 2.0, 34.6, 9.5, 3.2, 2.0)
    duct = [bm_hull(rrect_yz(-21.9, 2.0, 33.25, 13.4, 4.25, 2.0) + mid_a),
            bm_hull(mid_b + rrect_yz(-57.0, 1.0, 40.0, 7.0, 3.5, 2.0))]
    boolean(can, [tmp_obj(b, [M["soot"]]) for b in duct], "DIFFERENCE", transfer=True)
    bm = bmesh.new()   # the boolean leaves concave n-gons where the panel ramps meet the can: triangulate them
    bm.from_mesh(can.data)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method="BEAUTY",
                          ngon_method=os.environ.get("E61_NGON", "BEAUTY"))
    bm.to_mesh(can.data)
    bm.free()
    can.data.shade_smooth()
    out = [can]
    # ---- perforated baffle across the can, ahead of the taper
    sb = P["baffle_s"]
    rbf = rf(sb) - tw_ - 0.08
    baf = make_obj("MUF_Baffle", to_world(ovalize(bm_revolve([(0, sb), (rbf, sb), (rbf, sb + 1.0), (0, sb + 1.0)], 72, "Y"))),
                   col, [M["cast"]])
    holes = [tmp_obj(to_world(bm_cyl(2.0, (0, sb - 1, 0), (0, sb + 2, 0), 24)))]
    for k in range(6):
        a = 2 * math.pi * k / 6
        x, z = 0.62 * rbf * kxf(sb) * math.cos(a), 0.62 * rbf * math.sin(a)
        holes.append(tmp_obj(to_world(bm_cyl(1.4, (x, sb - 1, z), (x, sb + 2, z), 20))))
    boolean(baf, holes, "DIFFERENCE")
    out.append(baf)
    gk = make_obj("MUF_Gasket", bm_box((-22.75, -18.85, 27.85), (-22.5, 22.85, 37.85), r=4.85, axis=(1, 0, 0), segs=6), col,
                  [M["gasket"]])   # 0.15 mm inside both flanges
    boolean(gk, [tmp_obj(bm_box((-23, -11.2, 29.2), (-22, 15.2, 37.3), r=2, axis=(1, 0, 0), segs=3))]
            + [tmp_obj(bm_cyl(1.65, (-23, y, 33.0), (-22, y, 33.0), 20)) for y in MUF_BOLT_Y], "DIFFERENCE")
    out.append(gk)
    for i, y in enumerate(MUF_BOLT_Y):
        out.append(place_screw(screw_me, f"MUF_Bolt_{i + 1}", (fx0, y, 33), (-1, 0, 0), col, spin=9 * i))
    # ---- pressure nipple: radial, hex base + barb, on the pad at the +X rear corner of the panel
    nb = bm_revolve([(0.55, -1.0), (1.45, -1.0), (1.45, 0.2), (1.75, 0.2), (1.75, 1.6), (1.15, 1.9), (1.1, 4.6),
                     (1.45, 4.9), (1.45, 5.5), (1.05, 5.9), (0.55, 5.9)], 6 * 4, "Z", closed=True)
    for v in nb.verts:           # hex flats on the base
        if 0.1 < v.co.z < 1.7:
            a = math.atan2(v.co.y, v.co.x)
            rr_ = math.hypot(v.co.x, v.co.y)
            lim = 1.55 / math.cos(((a + math.pi / 6) % (math.pi / 3)) - math.pi / 6)
            k = min(1.0, lim / max(rr_, 1e-6))
            v.co.x, v.co.y = v.co.x * k, v.co.y * k
    cn = surf(ns, nphi, phh)
    bmesh.ops.transform(nb, matrix=W @ T(cn.x, ns, cn.z) @ Rot("Y", nphi), verts=nb.verts[:])
    out.append(make_obj("MUF_Pressure_Nipple", nb, col, [M["nickel"]]))
    return out


# ----------------------------------------------------------------------------- cast lettering, prop + spinner
FONT_DIR = "/usr/share/fonts/truetype/dejavu/"


def text_bm(body, size, depth, font="DejaVuSans-Bold.ttf", fit_w=None):
    """Raised cast letters as a closed bmesh (mm): text in the XY plane, centred, from z = 0 to z = depth."""
    fpath = os.path.join(FONT_DIR, font)
    fnt = bpy.data.fonts.load(fpath, check_existing=True) if os.path.exists(fpath) else None
    cu = bpy.data.curves.new("TMP_Text", "FONT")
    cu.body = body
    if fnt:
        cu.font = fnt
    cu.size = size
    cu.align_x, cu.align_y = "CENTER", "CENTER"
    cu.extrude = depth / 2.0
    cu.resolution_u = 6
    ob = bpy.data.objects.new("TMP_Text", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    sx = 1.0
    if fit_w and max(xs) - min(xs) > fit_w:
        sx = fit_w / (max(xs) - min(xs))
    for v in bm.verts:
        v.co.x = (v.co.x - cx) * sx
        v.co.y -= cy
        v.co.z += depth / 2.0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def frame_basis(xdir, ydir, origin):
    """4x4 placing local X (reading direction), Y (letter up) and their normal Z = X x Y at `origin` (mm)."""
    X, Y = Vector(xdir).normalized(), Vector(ydir).normalized()
    Z = X.cross(Y)
    m = Matrix(((X.x, Y.x, Z.x, origin[0]), (X.y, Y.y, Z.y, origin[1]), (X.z, Y.z, Z.z, origin[2]), (0, 0, 0, 1)))
    return m


def obround_ring(hl, hh, w, depth):
    """Raised obround frame (stadium outline): half-length hl, half-height hh, wall w (mm), z 0..depth."""
    outer = bm_prism(rrect(hl, hh, hh - 0.01, 10), 0.0, depth, lambda u, v, z: (u, v, z))
    ob = tmp_obj(outer)
    boolean(ob, [tmp_obj(bm_prism(rrect(hl - w, hh - w, hh - w - 0.01, 10), -0.1, depth + 0.1, lambda u, v, z: (u, v, z)))],
            "DIFFERENCE")
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.scale(bm, vec=(1 / MM, 1 / MM, 1 / MM), verts=bm.verts[:])   # tmp objects live in metres
    me = ob.data
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    return bm


def build_lettering(col, M, V, muf_col=None):
    """Cast lettering read off the owner's photos (generic words and numbers only; the maker's logos stay blank):
    SPECIAL EDITION in its obround frame on the +X lug (SE only), 61 on the -X boss, 744 on the muffler arm."""
    out = []
    if V.get("castellated"):
        # +X lug face x = 29.5, plaque centre y 1.0, z -3.2; reads front -> rear seen from +X
        # measured against the lug's bolt holes in photo Ac: frame 23.1 mm long centred at y 2.35, text 19.8 mm
        B = frame_basis((0, 1, 0), (0, 0, 1), (29.4, 2.35, -3.2))
        ring = obround_ring(11.55, 2.3, 0.55, 0.45)
        bmesh.ops.transform(ring, matrix=B, verts=ring.verts[:])
        out.append(make_obj("ENG_Letter_SE_Frame", ring, col, [M["cast"]]))
        tx = text_bm("SPECIAL EDITION", 3.05, 0.42, "DejaVuSansCondensed-Bold.ttf", fit_w=19.8)
        bmesh.ops.transform(tx, matrix=B, verts=tx.verts[:])
        out.append(make_obj("ENG_Letter_SE_Text", tx, col, [M["cast"]]))
    # "61" on the round boss of the -X band: face x = -17.3, centre (y 0, z 19); reads rear -> front seen from -X
    tx = text_bm("61", 4.3, 0.42, "DejaVuSans-Bold.ttf", fit_w=4.9)
    bmesh.ops.transform(tx, matrix=frame_basis((0, -1, 0), (0, 0, 1), (-17.2, 0.0, 19.0)), verts=tx.verts[:])
    out.append(make_obj("ENG_Letter_61", tx, col, [M["cast"]]))
    if muf_col is not None:
        # "744" on the manifold arm top (z 42.9) next to the cylinder, read along -Y with the tops toward +X (T, E)
        tx = text_bm("744", 3.0, 0.38, "DejaVuSans-Bold.ttf", fit_w=4.6)
        bmesh.ops.transform(tx, matrix=frame_basis((0, -1, 0), (1, 0, 0), (-25.0, 1.0, 42.8)), verts=tx.verts[:])
        out.append(make_obj("MUF_Letter_744", tx, muf_col, [M["cast"]]))
    return out


PROP_P0 = dict(  # optional prop + spinner as mounted in the owner's photos (A, B, B2, T); hidden by default
    # measured along the shaft in photos B and A: backplate straight on the hub face, prop in front of it,
    # cone from the backplate rim to the tip at y -119
    bp_r=33.0, bp_y=(-61.75, -65.8),
    cone_tip=-119.0, prop_y=(-65.9, -75.8), prop_r=133.0, pitch=152.0, hub_r=11.0,
)


def blade_bm(P, side=1.0):
    """One blade: flat-bottomed sections lofted from the hub to the tip, twisted for the pitch (mm, crank frame)."""
    rs = [P["hub_r"] - 1.0 + (P["prop_r"] - P["hub_r"] + 1.0) * (1 - math.cos(math.pi / 2 * k / 22)) ** 0.9 for k in range(23)]
    yc = (P["prop_y"][0] + P["prop_y"][1]) / 2
    secs = []
    for i, r in enumerate(rs):
        t = (r - P["hub_r"]) / (P["prop_r"] - P["hub_r"])
        chord = 10.0 + 15.0 * math.sin(math.pi * min(1.0, t * 1.6) / 1.6) * (1 - 0.7 * t) if t > 0 else 10.0
        if t > 0.9:                      # rounded tip
            chord = max(2.0, chord * math.sqrt(max(0.0, 1 - ((t - 0.9) / 0.1) ** 2)))
        thick = chord * (0.30 - 0.22 * min(1.0, t * 2.2)) if t < 0.45 else chord * 0.085
        ang = math.atan2(P["pitch"], 2 * math.pi * max(r, 8.0))
        pts = []
        n = 14
        for k in range(n):        # upper surface, leading -> trailing
            u = 1 - math.cos(math.pi * k / (n - 1))
            u /= 2.0
            pts.append((chord * (u - 0.35), thick * 1.2 * math.sqrt(max(u, 0)) * (1 - u) ** 1.1))
        for k in range(n - 2, 0, -1):   # flat bottom back to the leading edge
            u = (1 - math.cos(math.pi * k / (n - 1))) / 2.0
            pts.append((chord * (u - 0.35), -0.06 * thick * (1 - u)))
        wr = 1.0 - min(1.0, max(0.0, t / 0.16)) ** 2 * (3 - 2 * min(1.0, max(0.0, t / 0.16)))
        if wr > 0:              # round hub root blended into the airfoil, same point order (leading edge, over the top)
            nn = len(pts)
            rnd = [(chord * (0.15 + 0.5 * math.cos(math.pi - 2 * math.pi * k / nn)),
                    max(thick, 0.55 * chord) * 0.5 * math.sin(math.pi - 2 * math.pi * k / nn)) for k in range(nn)]
            pts = [(wr * r_[0] + (1 - wr) * p_[0], wr * r_[1] + (1 - wr) * p_[1]) for r_, p_ in zip(rnd, pts)]
        ca, sa = math.cos(ang), math.sin(ang)
        sec = []
        for c, h in pts:    # chord along +Z rotated by the blade angle about the radial (X) axis; thrust along -Y
            z_ = c * ca - h * sa
            y_ = -(c * sa + h * ca)
            sec.append(Vector((side * r, yc + y_, side * z_)))
        secs.append(sec)
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in s] for s in secs]
    m = len(rings[0])
    for A, Bv in zip(rings, rings[1:]):
        for k in range(m):
            bm.faces.new((A[k], A[(k + 1) % m], Bv[(k + 1) % m], Bv[k]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def build_prop(col, M):
    """2-blade prop (~10.5 x 6) with a 66 mm spinner (polished backplate + white cone), as seen in the photos."""
    P = dict(PROP_P0, **FIT.get("prop", {}))
    y0, y1 = P["bp_y"]
    bp = make_obj("ENG_Spinner_Backplate", bm_revolve([(4.1, y0), (P["bp_r"] - 1.2, y0), (P["bp_r"], y0 - 0.9),
                                                       (P["bp_r"], y1 + 0.5), (P["bp_r"] - 0.5, y1), (4.1, y1)],
                                                      96, "Y", closed=True), col, [M["polished"]])
    yb, yt = y1 - 0.05, P["cone_tip"]
    def ogive(t):            # pointed ogive with a softly rounded tip (photo A)
        return max(0.0, 1 - t ** 1.9) ** 0.7
    prof = [(0.0, yb)] + [((P["bp_r"] - 0.6) * ogive(k / 32), yb + (yt - yb) * k / 32) for k in range(32)] + [(0.0, yt)]
    cone = make_obj("ENG_Spinner_Cone", bm_revolve(prof, 96, "Y"), col, [M["plastic_white"]])
    yti = yt + 1.6                                # 1.4 mm wall, tip left solid
    inn = [((P["bp_r"] - 2.0) * ogive(k / 32), yb + (yti - yb) * k / 32) for k in range(31)]
    cuts = [tmp_obj(bm_revolve([(0.0, yb + 0.5), (inn[0][0], yb + 0.5)] + inn + [(0.0, yti)], 96, "Y"))]
    for side in (1, -1):    # blade cut-outs
        cuts.append(tmp_obj(bm_box((side * 16.0 - 12.0, P["prop_y"][1] - 2.0, -9.0), (side * 16.0 + 12.0, yb + 0.5, 9.0), r=3.0,
                                   axis=(0, 1, 0), segs=4)))
    boolean(cone, cuts, "DIFFERENCE")
    hub = make_obj("ENG_Prop_Blades", bm_cyl(P["hub_r"], (0, P["prop_y"][0], 0), (0, P["prop_y"][1], 0), 48), col,
                   [M["plastic_black"]])
    boolean(hub, [tmp_obj(blade_bm(P, 1.0)), tmp_obj(blade_bm(P, -1.0))], "UNION")
    boolean(hub, [tmp_obj(bm_cyl(4.1, (0, P["prop_y"][0] + 1, 0), (0, P["prop_y"][1] - 1, 0), 32))], "DIFFERENCE")
    for p_ in (bp, cone, hub):   # onto the crank axis in the mesh itself: the Prop collection is not evaluated while hidden
        p_.data.transform(T(0.0, 0.0, mech()["za"] * MM))
    return [bp, cone, hub]


# ----------------------------------------------------------------------------- internals (moving parts)
def attach(child, parent):
    """Parent keeping the world transform (children of the piston / crankshaft follow their drivers)."""
    bpy.context.view_layer.update()
    # an unparented object in a collection the view layer does not evaluate (the hidden Prop set) has a stale
    # matrix_world: its basis matrix is its world transform
    mw = child.matrix_world.copy() if child.parent is not None else child.matrix_basis.copy()
    child.parent = parent
    child.matrix_parent_inverse = Matrix.Identity(4)
    child.matrix_world = mw
    child["pivot"] = True


LINER_KEY_DEG = 132.0      # liner locating notch / dowel, between the rear transfer and the exhaust window


def build_liner(col, M, K):
    """Chrome-plated liner with exhaust, two transfer and boost windows (Schnuerle), top flange + head shim."""
    ri, ro, fr = K["bore"] / 2, K["liner_ro"], K["liner_fr"]
    zb, zf, zt = K["liner_bot"], K["z_flange"], K["z_liner_top"]
    prof = [(ri, zb + 0.4), (ri + 0.4, zb), (ro - 0.3, zb), (ro, zb + 0.3), (ro, zf), (fr - 0.2, zf), (fr, zf + 0.2),
            (fr, zt - 0.2), (fr - 0.2, zt), (ri + 0.4, zt), (ri, zt - 0.4)]
    lin = make_obj("ENG_Liner", bm_revolve(prof, 96, "Z", closed=True), col, [M["chrome"]])
    cuts = [tmp_obj(bm_port(K["exh"][0], K["exh"][1], K["z_exh0"], K["z_exh"], ri - 1.0, ro + 1.0, 1.5))]
    for s in (1, -1):
        cuts.append(tmp_obj(bm_port(s * K["trans"][0], K["trans"][1], K["z_port0"], K["z_tr"], ri - 1.0, ro + 1.0, 1.2)))
    cuts.append(tmp_obj(bm_port(K["boost"][0], K["boost"][1], K["boost_floor"], K["z_boost"], ri - 1.0, ro + 1.0, 1.0)))
    nb = bm_box((-0.55, K["liner_ro"] - 0.05, zf - 0.3), (0.55, fr + 1.0, zt + 1.0), r=0.3, axis=(0, 0, 1), segs=2)
    bmesh.ops.rotate(nb, verts=nb.verts[:], cent=(0, 0, 0), matrix=Rot("Z", LINER_KEY_DEG - 90.0).to_3x3())
    cuts.append(tmp_obj(nb))                                           # locating notch in the flange
    boolean(lin, cuts, "DIFFERENCE")
    a = math.radians(LINER_KEY_DEG)
    dw = make_obj("ENG_Liner_Dowel", bm_cyl(0.5, ((fr + 0.05) * math.cos(a), (fr + 0.05) * math.sin(a), zf - 1.2),
                                         ((fr + 0.05) * math.cos(a), (fr + 0.05) * math.sin(a), zf + 1.0), 16), col, [M["steel"]])
    shim = make_obj("ENG_Gasket_Head", bm_revolve([(ri + 0.05, zt), (fr - 0.05, zt), (fr - 0.05, K["z_button"]),
                                                    (ri + 0.05, K["z_button"])], 96, "Z", closed=True), col, [M["copper"]])
    return [lin, shim, dw]


def build_piston_group(col, M, K):
    """Ringed aluminium piston (domed crown, pinned ring, pin bosses, web relief in the front skirt), steel
    wrist pin along Y, two wire circlips, steel ring. Built at TDC; origin on the pin axis."""
    zp = K["zp0"]
    R = K["bore"] / 2 - K["pis_clear"]
    zc = zp + K["pin_h"]
    zb = zc - K["pis_len"]
    a, d = R - 0.25, K["dome"]
    Rs = (a * a + d * d) / (2 * d)
    prof = [(0, zb), (R - 0.3, zb), (R, zb + 0.3), (R, zc - 0.25), (a, zc)]
    prof += [(a * (1 - k / 8), zc - (Rs - d) + math.sqrt(Rs * Rs - (a * (1 - k / 8)) ** 2)) for k in range(1, 9)]
    pis = make_obj("ENG_Piston", bm_revolve(prof, 96, "Z"), col, [M["piston"]])
    zg1 = zc - K["ring_top"]
    zg0 = zg1 - K["ring_w"]
    ri_sk = R - 1.2
    cav = [(0, zb - 1), (ri_sk, zb - 1), (ri_sk, zc - 4.6), (9.4, zc - 3.4), (0, zc - 3.0)]
    groove = [(K["ring_root"], zg0), (R + 1, zg0), (R + 1, zg1), (K["ring_root"], zg1)]
    boolean(pis, [tmp_obj(bm_revolve(cav, 96, "Z")), tmp_obj(bm_revolve(groove, 96, "Z", closed=True))], "DIFFERENCE")
    # pin bosses joined to the crown, trimmed to the skirt
    bi, br = K["boss_in"], K["boss_r"]
    bosses = tmp_obj(bm_cyl(br, (0, bi, zp), (0, 11.6, zp), 40))
    ops = [tmp_obj(bm_cyl(br, (0, -11.6, zp), (0, -bi, zp), 40))]
    for y0, y1 in ((bi, 11.6), (-11.6, -bi)):
        ops.append(tmp_obj(bm_box((-br * 0.85, y0, zp), (br * 0.85, y1, zc - 2.5))))
    boolean(bosses, ops, "UNION")
    boolean(bosses, [tmp_obj(bm_cyl(ri_sk + 0.6, (0, 0, zb), (0, 0, zc - 1.0), 96))], "INTERSECT")
    ga = math.radians(K["ring_gap_ang"])                      # ring locating peg, radial at the ring gap
    peg = bm_cyl(0.15, ((K["ring_root"] - 0.6) * math.cos(ga), (K["ring_root"] - 0.6) * math.sin(ga), (zg0 + zg1) / 2),
                 ((R - 0.35) * math.cos(ga), (R - 0.35) * math.sin(ga), (zg0 + zg1) / 2), 12)
    boolean(pis, [bosses, tmp_obj(peg)], "UNION")
    yg = K["pin_len"] / 2
    cuts = [tmp_obj(bm_cyl(K["pin_r"], (0, -14, zp), (0, 14, zp), 40))]
    for y0, y1 in ((yg + 0.15, yg + 0.85), (-yg - 0.85, -yg - 0.15)):
        cuts.append(tmp_obj(bm_cyl(K["pin_r"] + 0.45, (0, y0, zp), (0, y1, zp), 40)))
    # skirt arches on both pin sides (circle about the crank axis at BDC: the web passes under the front one);
    # the exhaust and boost faces stay long, so the exhaust port is closed to the crankcase at TDC
    zc_bdc = zp - (K["rod"] - K["r"])
    for y0, y1 in ((-14.0, K["web_y"][1] + 0.15), (-K["web_y"][1] - 0.15, 14.0)):
        rel = tmp_obj(bm_cyl(K["relief_r"], (0, y0, zc_bdc), (0, y1, zc_bdc), 128))
        boolean(rel, [tmp_obj(bm_box((K["relief_x"], y0 - 1, zb - 2), (-K["relief_x"], y1 + 1, zp), r=1.5, axis=(0, 1, 0),
                                     segs=3))], "INTERSECT")
        cuts.append(rel)
    bw, bz0, bz1 = K["boost_win"]                       # boost-side skirt window, lines up with the boost slot at BDC
    cuts.append(tmp_obj(bm_port(K["boost"][0], bw, zp + bz0, zp + bz1, R - 2.5, R + 1.0, 1.6, r_ref=R)))
    boolean(pis, cuts, "DIFFERENCE")
    set_origin(pis, (0, 0, zp))
    pis["pivot"] = True
    # ring: steel, gap at the peg (never over a port), sits free in the groove
    ring = make_obj("ENG_Piston_Ring", bm_revolve([(K["ring_root"] + 0.2, zg0 + 0.01), (K["bore"] / 2 - 0.004, zg0 + 0.01),
                                                    (K["bore"] / 2 - 0.004, zg1 - 0.01), (K["ring_root"] + 0.2, zg1 - 0.01)],
                                                   96, "Z", closed=True), col, [M["black"]])
    gap = bm_box((-K["ring_gap"] / 2, 9.0, zg0 - 1), (K["ring_gap"] / 2, 13.5, zg1 + 1))
    bmesh.ops.rotate(gap, verts=gap.verts[:], cent=(0, 0, 0), matrix=Rot("Z", K["ring_gap_ang"] - 90).to_3x3())
    boolean(ring, [tmp_obj(gap)], "DIFFERENCE")
    pin = make_obj("ENG_Wrist_Pin", bm_revolve([(1.8, -yg), (K["pin_r"] - 0.25, -yg), (K["pin_r"] - 0.002, -yg + 0.25),
                                                (K["pin_r"] - 0.002, yg - 0.25), (K["pin_r"] - 0.25, yg), (1.8, yg)],
                                               48, "Y", center=(0, zp), closed=True), col, [M["crank"]])
    clips = []
    for i, s in enumerate((1, -1)):
        bm = bm_torus(K["pin_r"] + 0.1, 0.33, 20, 340, segs=36, rsegs=10)
        bmesh.ops.transform(bm, matrix=T(0, s * (yg + 0.5), zp) @ Rot("X", 90), verts=bm.verts[:])
        clips.append(make_obj(f"ENG_Circlip_{i + 1}", bm, col, [M["steel"]]))
    for c in [ring, pin] + clips:
        attach(c, pis)
    return pis, [ring, pin] + clips


def build_rod(col, M, K, piston):
    """Machined aluminium rod (flat shank with chamfered edges, raised eyes), bronze bushings, oil holes;
    swings in the XZ plane."""
    zs, zb = K["zp0"], K["za"] + K["r"]
    rs, rb, w, sw = K["small_r"], K["big_r"], K["rod_w"], K["shank_w"]

    def half_w(z):                     # soft max of eye circles and the tapered shank -> filleted outline
        # eye circles 0.3 mm inside the raised eye bosses: no near-tangent faces for the union below
        terms = [math.sqrt(rr * rr - (z - zc_) ** 2) for zc_, rr in ((zs, rs - 0.3), (zb, rb - 0.3)) if abs(z - zc_) < rr]
        if zb <= z <= zs:
            terms.append(3.25 + (2.35 - 3.25) * (z - zb) / (zs - zb))
        if not terms:
            return 0.0
        m, k = max(terms), 0.5
        return m + k * math.log(sum(math.exp((v - m) / k) for v in terms))
    lo, hi, N = zb - rb + 0.3, zs + rs - 0.3, 120
    zz = [lo + (hi - lo) * (1 - math.cos(math.pi * i / N)) / 2 for i in range(N + 1)]
    right = [(half_w(z), z) for z in zz]
    right[0], right[-1] = (0.0, lo), (0.0, hi)
    outline = right + [(-x, z) for x, z in reversed(right[1:-1])]
    rbm = bm_prism(outline, -sw, sw, lambda u, v, w_: (u, w_, v))
    rim = [e for e in rbm.edges if all(abs(abs(v.co.y) - sw) < 1e-4 for v in e.verts) and
           abs(e.verts[0].co.y - e.verts[1].co.y) < 1e-4]
    bmesh.ops.bevel(rbm, geom=rim + list({v for e in rim for v in e.verts}), offset=0.35, offset_type="OFFSET",
                    segments=1, profile=0.5, affect="EDGES", clamp_overlap=True)
    bmesh.ops.triangulate(rbm, faces=[f for f in rbm.faces if len(f.verts) > 4])
    rod = make_obj("ENG_Rod", rbm, col, [M["satin"]])
    boolean(rod, [tmp_obj(bm_cyl(rs, (0, -w, zs), (0, w, zs), 64)), tmp_obj(bm_cyl(rb, (0, -w, zb), (0, w, zb), 64))], "UNION")
    z_lo, z_hi = zb + rb + 0.9, zs - rs - 0.5
    pk = []
    for i in range(25):
        t = i / 24
        z = z_lo + (z_hi - z_lo) * t
        pk.append((max(half_w(z) - 0.95, 0.3) * math.sqrt(max(0.0, 1 - (2 * t - 1) ** 10)), z))
    pocket = [(x, z) for x, z in pk] + [(-x, z) for x, z in reversed(pk[1:-1])]
    cuts = [tmp_obj(bm_cyl(K["small_bore"], (0, -5, zs), (0, 5, zs), 48)),
            tmp_obj(bm_cyl(K["big_bore"], (0, -5, zb), (0, 5, zb), 48)),
            tmp_obj(bm_cyl(0.6, (0, 0, zs + 1.0), (0, 0, hi + 1.0), 16)),                  # small-end oil hole
            tmp_obj(bm_cyl(0.7, (0, 0, zb), (rb * 1.4 * math.sin(math.radians(35)), 0, zb + rb * 1.4 * math.cos(math.radians(35))), 16))]
    boolean(rod, cuts, "DIFFERENCE")
    bush_s = make_obj("ENG_Rod_Bush_Small", bm_revolve([(K["pin_r"] + 0.006, -w), (K["small_bore"], -w), (K["small_bore"], w),
                                                        (K["pin_r"] + 0.006, w)], 48, "Y", center=(0, zs), closed=True),
                      col, [M["bronze"]])
    bush_b = make_obj("ENG_Rod_Bush_Big", bm_revolve([(K["crankpin_r"] + 0.02, -w), (K["big_bore"], -w), (K["big_bore"], w),
                                                      (K["crankpin_r"] + 0.02, w)], 48, "Y", center=(0, zb), closed=True),
                      col, [M["bronze"]])
    boolean(bush_s, [tmp_obj(bm_cyl(0.6, (0, 0, zs), (0, 0, hi + 1.0), 16))], "DIFFERENCE")
    boolean(bush_b, [tmp_obj(bm_cyl(0.7, (0, 0, zb), (rb * 1.4 * math.sin(math.radians(35)), 0, zb + rb * 1.4 * math.cos(math.radians(35))), 16))],
            "DIFFERENCE")
    set_origin(rod, (0, 0, zs))
    attach(rod, piston)
    for b in (bush_s, bush_b):
        attach(b, rod)
    return [rod, bush_s, bush_b]


def web_rho(psi, K):
    """Crank web outline (crank frame): boss of full radius round the crankpin, D-shaped (cut down) pin side,
    full-radius counterweight half. The relieved front skirt clears it at every angle."""
    a = abs(((psi + 180.0) % 360.0) - 180.0)
    b0, b1, b2 = K["web_boss_deg"], K["web_side_deg"], K["web_cw_deg"]
    R, Rs, Rc = K["web_r"], K["web_side_r"], K["cw_r"]

    def blend(t, r0, r1):
        return r0 + (r1 - r0) * (1 - math.cos(math.pi * t)) / 2
    if a <= b0:
        return R
    if a <= b1:
        return blend((a - b0) / (b1 - b0), R, Rs)
    if a <= b2:
        return blend((a - b1) / (b2 - b1), Rs, Rc)
    return Rc


def build_crankshaft(col, M, K):
    """One-piece steel crankshaft (built at TDC, origin on the axis): 5/16-24 thread (separate object),
    keyed hub seat (Woodruff key), front-bearing seat, rotary-valve journal with a flat-milled, ball-end
    scooped window into the hollow bore, rear-bearing journal, shoulder, round web with a pin-side pocket and a
    tungsten counterweight, hollow crankpin."""
    jr, vr, sr, nr = K["journal_r"], K["valve_r"], K["shaft_r"], K["nose_r"]
    yb0, yb1 = K["rear_brg"][3], K["rear_brg"][3] + K["rear_brg"][2]
    w0, w1 = K["web_y"]
    yf1 = K["front_brg"][3] + K["front_brg"][2]
    yf0 = K["front_brg"][3]
    hy1 = HUB_Y[1] - 0.1
    prof = [(0, hy1 - 0.05), (nr - 0.05, hy1 - 0.05), (nr, hy1), (nr, yf0), (sr, yf0 + 0.01), (sr, yf1 + 0.1), (sr + 0.3, yf1 + 0.4),
            (vr - 0.3, yf1 + 0.4), (vr, yf1 + 0.7), (vr, yb0 - 0.4), (jr, yb0), (jr, yb1 - 0.1), (8.6, yb1), (8.6, w0 - 0.25),
            (9.0, w0 + 0.05), (0, w0 + 0.05)]
    cs = make_obj("ENG_Crankshaft", bm_revolve(prof, 64, "Y"), col, [M["crank"]])
    web = bm_prism([crank_pt(p, web_rho(p, K)) for p in range(0, 360, 3)], w0, w1, lambda u, v, w_: (u, w_, v))
    rim = [e for e in web.edges if all(abs(v.co.y - w0) < 1e-4 for v in e.verts) or all(abs(v.co.y - w1) < 1e-4 for v in e.verts)]
    bmesh.ops.bevel(web, geom=rim + list({v for e in rim for v in e.verts}), offset=0.4, offset_type="OFFSET", segments=2,
                    profile=0.5, affect="EDGES", clamp_overlap=True)
    bmesh.ops.triangulate(web, faces=[f for f in web.faces if len(f.verts) > 4])
    cr, ce = K["crankpin_r"], K["crankpin_end"]
    pinb = bm_revolve([(0, w1 - 0.1), (cr + 0.4, w1 - 0.1), (cr + 0.4, w1), (cr, w1 + 0.2), (cr, ce - 0.3), (cr - 0.3, ce),
                       (0, ce)], 48, "Y", center=crank_pt(0, K["r"]))
    boolean(cs, [tmp_obj(web), tmp_obj(pinb)], "UNION")
    psi_c, wh = K["win_center"], K["win_half"]
    py = PEDESTAL_Y.get(K.get("carb", "os61"), -36.0)
    wy0, wy1 = py - K["win_len"] / 2, py + K["win_len"] / 2
    hf = vr * math.cos(math.radians(wh))            # flat at hf from the axis: its edges give the valve timing
    flat = bm_box((-10.0, wy0, hf), (10.0, wy1, hf + 6.0), r=1.0, axis=(0, 0, 1), segs=3)
    bmesh.ops.rotate(flat, verts=flat.verts[:], cent=(0, 0, 0), matrix=Rot("Y", -psi_c).to_3x3())
    rs_ = 3.4                                         # ball-end scoop into the bore (rounded ends of the opening)
    yc0, yc1 = wy0 + rs_ + 0.3, wy1 - rs_ - 0.3
    cap = [(0.0, yc0 - rs_)] + [(rs_ * math.sin(math.pi / 2 * k / 8), yc0 - rs_ * math.cos(math.pi / 2 * k / 8)) for k in range(1, 9)]
    cap += [(rs_ * math.cos(math.pi / 2 * k / 8), yc1 + rs_ * math.sin(math.pi / 2 * k / 8)) for k in range(0, 8)] + [(0.0, yc1 + rs_)]
    scoop = bm_revolve(cap, 32, "Y", center=crank_pt(psi_c, hf - 0.3))
    cuts = [tmp_obj(bm_revolve([(0, -41.8), (K["bore_r"], -41.0), (K["bore_r"], w1 + 0.3), (0, w1 + 0.3)], 48, "Y")),  # hollow bore
            tmp_obj(flat), tmp_obj(scoop),                                                                          # valve window
            tmp_obj(bm_revolve([(0, w1 - 0.4), (K["crankpin_bore"], w1 + 0.2), (K["crankpin_bore"], ce + 1), (0, ce + 1)], 24,
                               "Y", center=crank_pt(0, K["r"])))]                                                  # hollow pin
    ri_, ro_, span, depth = K["cw_insert"]

    def crescent(dr):
        n_ = 36
        arc = [180 - span / 2 + span * i / n_ for i in range(n_ + 1)]
        pts_ = [crank_pt(p_, ro_ - dr) for p_ in arc] + [crank_pt(p_, ri_ + dr) for p_ in reversed(arc)]
        bm_ = bm_prism(pts_, w0 - (1.0 if dr == 0 else -0.02), w0 + depth - dr, lambda u, v, w_: (u, w_, v))
        bmesh.ops.triangulate(bm_, faces=bm_.faces[:])
        return bm_
    cuts.append(tmp_obj(crescent(0.0)))                                                                        # pocket
    pi_, po_, pspan, pdep = K["web_pocket"]                          # pin-side lightening pocket (front face)
    arc = [-pspan / 2 + pspan * i / 36 for i in range(37)]
    pp = [crank_pt(p_, po_) for p_ in arc] + [crank_pt(p_, pi_) for p_ in reversed(arc)]
    pocket = bm_prism(pp, w0 - 1.0, w0 + pdep, lambda u, v, w_: (u, w_, v))
    bmesh.ops.triangulate(pocket, faces=pocket.faces[:])
    cuts.append(tmp_obj(pocket))
    # Woodruff key seat in the hub section of the shaft (key on top at TDC)
    cuts.append(tmp_obj(woodruff_bm(0.02, slot=True)))
    boolean(cs, cuts, "DIFFERENCE")
    slug = make_obj("ENG_Crank_Counterweight", crescent(0.02), col, [M["tungsten"]])
    cs["pivot"] = True
    attach(slug, cs)
    za_ob(cs, K)                                     # origin on the real crank axis; the slug follows
    return cs, [slug]


def build_bearing(col, M, tag, d, D, B, y0, nballs):
    """Deep-groove ball bearing: inner ring (turns with the shaft), outer ring (in the housing), balls and a
    riveted cage turning at ~0.4x shaft speed. Grooves are true raceways for the balls."""
    ri, ro = d / 2, D / 2
    pm, rb = (ri + ro) / 2, 0.3 * (ro - ri)
    y1, yc = y0 + B, y0 + B / 2
    rio, roi = pm - 0.55 * rb, pm + 0.55 * rb
    inner = make_obj(f"ENG_Bearing_{tag}_Inner", bm_revolve([(ri, y0 + 0.3), (ri + 0.3, y0), (rio - 0.2, y0), (rio, y0 + 0.2),
                                                              (rio, y1 - 0.2), (rio - 0.2, y1), (ri + 0.3, y1), (ri, y1 - 0.3)],
                                                             96, "Y", closed=True), col, [M["steel"]])
    outer = make_obj(f"ENG_Bearing_{tag}_Outer", bm_revolve([(roi, y0 + 0.2), (roi + 0.2, y0), (ro - 0.3, y0), (ro, y0 + 0.3),
                                                              (ro, y1 - 0.3), (ro - 0.3, y1), (roi + 0.2, y1), (roi, y1 - 0.2)],
                                                             96, "Y", closed=True), col, [M["steel"]])

    def race():
        return tmp_obj(bm_revolve([(pm + rb * 1.04 * math.cos(2 * math.pi * k / 24), yc + rb * 1.04 * math.sin(2 * math.pi * k / 24))
                                   for k in range(24)], 96, "Y", closed=True))
    boolean(inner, [race()], "DIFFERENCE")
    boolean(outer, [race()], "DIFFERENCE")
    bm = bmesh.new()
    for k in range(nballs):
        x, z = crank_pt(360.0 * k / nballs, pm)
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=rb, matrix=T(x, yc, z))
    balls = make_obj(f"ENG_Bearing_{tag}_Balls", bm, col, [M["chrome"]])
    cage = make_obj(f"ENG_Bearing_{tag}_Cage", bm_revolve([(pm - 0.45, yc - 0.42 * B), (pm + 0.45, yc - 0.42 * B),
                                                            (pm + 0.45, yc + 0.42 * B), (pm - 0.45, yc + 0.42 * B)],
                                                           96, "Y", closed=True), col, [M["brass"]])
    pk = []
    for k in range(nballs):                           # stamped ribbon cage: radially drilled pockets
        x0, z0_ = crank_pt(360.0 * k / nballs, pm - 1.5)
        x1, z1_ = crank_pt(360.0 * k / nballs, pm + 1.5)
        pk.append(tmp_obj(bm_cyl(rb + 0.12, (x0, yc, z0_), (x1, yc, z1_), 24)))
    boolean(cage, pk, "DIFFERENCE")
    for ob in (balls, cage):
        set_origin(ob, (0, yc, 0))
        ob["pivot"] = True
    for ob in (inner, outer, balls, cage):
        za_ob(ob)
    return inner, outer, balls, cage


def build_internals(col, M, K, front_parts):
    """Everything that moves, plus the liner. Returns (parts, roles)."""
    parts = build_liner(col, M, K)
    pis, pis_kids = build_piston_group(col, M, K)
    rod_parts = build_rod(col, M, K, pis)
    cs, cs_kids = build_crankshaft(col, M, K)
    parts += [pis] + pis_kids + rod_parts + [cs] + cs_kids
    spin = []
    for tag, (d, D, B, y0, n) in (("Rear", K["rear_brg"]), ("Front", K["front_brg"])):
        inner, outer, balls, cage = build_bearing(col, M, tag, d, D, B, y0, n)
        attach(inner, cs)
        parts += [inner, outer, balls, cage]
        spin += [balls, cage]
    for p in front_parts:            # hub, key, washer, nut, thread, thrust washer turn with the shaft
        if p.name in DRIVE_PARTS:
            attach(p, cs)
    return parts, {"piston": pis, "rod": rod_parts[0], "crank": cs, "spin": spin}


# ----------------------------------------------------------------------------- scene
def reset_scene():
    """Headless: start from an empty file. Inside an open Blender session: only remove what a
    previous run of this script created (ENG_/MUF_/TMP_ objects, Engine/Muffler collections, M_ materials)."""
    sc = bpy.context.scene
    if bpy.app.background:
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o)
        for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
            for d in list(coll):
                coll.remove(d)
        for c in list(bpy.data.collections):
            bpy.data.collections.remove(c)
        sc.unit_settings.system = "METRIC"
        sc.unit_settings.scale_length = 1.0
        sc.unit_settings.length_unit = "MILLIMETERS"
        return sc
    for o in [o for o in bpy.data.objects if o.name.startswith(("ENG_", "MUF_", "TMP_", "CARB_", "ANL_", "CUT_", "Glow_Engine_61",
                                                                 "Carburetor_Assembly"))]:
        bpy.data.objects.remove(o)
    for me in [m for m in bpy.data.meshes if m.users == 0 and m.name.startswith(("ENG_", "MUF_", "TMP_", "ME_"))]:
        bpy.data.meshes.remove(me)
    for c in [c for c in bpy.data.collections if c.name.split(".")[0] in ("Engine", "Engine_61", "E61_Body", "E61_Carburetor", "E61_Drive", "E61_Fasteners",
                                                                   "E61_Internals", "E61_Analysis",
                                                                   "E61_Muffler", "Muffler", "Carburetor", "TMP_Operands")]:
        bpy.data.collections.remove(c)
    for m in [m for m in bpy.data.materials if m.name.startswith("M_")]:
        m.use_fake_user = False
        if m.users == 0:
            bpy.data.materials.remove(m)
    return sc


SHARP_PREFIXES = ("ENG_Crankshaft", "ENG_GlowPlug", "ENG_Head_Screw", "MUF_Pressure", "CARB_Fuel", "CARB_Needle_Knob",
                  "CARB_Needle_Spring", "CARB_Collar_Set", "CARB_Needle", "CARB_Idle", "CARB_Mixture",
                  "CARB_SideNeedle_Knob", "CARB_Slot_Screw", "CARB_Stop", "CARB_Top", "CARB_Set", "CARB_Arm_Screw")


def carb_only(o, sc, M):
    """Just the carburetor at the origin (barrel axis), for close-up work and renders."""
    col = bpy.data.collections.new("E61_Carburetor")
    sc.collection.children.link(col)
    parts = build_carb(col, M, kind=o["carb"], place=(0.0, 0.0, 0.0))
    root = bpy.data.objects.new("Carburetor_Assembly", None)
    root.empty_display_type, root.empty_display_size = "ARROWS", 0.015
    col.objects.link(root)
    for p in parts:
        p.parent = root
        if p.type == "MESH" and p.data.users == 1:
            final_clean(p)
        if p.name.startswith(SHARP_PREFIXES):
            p.data.set_sharp_from_angle(angle=math.radians(35))
    rig_controls(root, parts, o["carb"], (0.0, 0.0, 0.0), o["throttle"], drive=False)
    bpy.context.view_layer.update()
    lo, hi = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
    for p in parts:
        for c in p.bound_box:
            w = p.matrix_world @ Vector(c)
            lo, hi = Vector(map(min, lo, w)), Vector(map(max, hi, w))
    info = {"ok": True, "carb": o["carb"], "objects": len(parts), "meshes": [p.name for p in parts],
            "size_mm": [round(v / MM, 1) for v in (hi - lo)]}
    if o["save"]:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(bpy.path.abspath(o["save"])))
        info["saved"] = o["save"]
    print(MARK + __import__("json").dumps(info), flush=True)
    return info


def mech_report(K):
    """Key numbers of the mechanism (stored on the root empty as JSON)."""
    sw = math.pi * (K["bore"] / 2) ** 2 * K["stroke"]
    return {"bore_mm": K["bore"], "stroke_mm": K["stroke"], "swept_cc": round(sw / 1000, 3), "rod_mm": K["rod"],
            "rod_ratio": round(K["rod"] / K["r"], 2), "crown_TDC_z": round(K["zT"], 3), "crown_BDC_z": round(K["zB"], 3),
            "exhaust_top_z": round(K["z_exh"], 3), "transfer_top_z": round(K["z_tr"], 3),
            "exhaust_deg": [K["exh_open"], 360 - K["exh_open"]], "transfer_deg": [K["trans_open"], 360 - K["trans_open"]],
            "intake_deg": [K["intake_open"], K["intake_close"]], "valve_window_deg": round(2 * K["win_half"], 1),
            "valve_window_lead_deg": round(K["win_center"], 1), "squish_mm": K["squish"]}


def main():
    o = _args()
    sc = reset_scene()
    SCREW_MESHES.clear()
    M = build_materials()
    if o["carb_only"]:
        return carb_only(o, sc, M)
    V = o["V"]
    K = mech()
    K["carb"] = o["carb"]
    top = bpy.data.collections.new("Engine_61")
    sc.collection.children.link(top)
    cols = {}
    for k in ("Body", "Internals", "Carburetor", "Drive", "Fasteners", "Muffler", "Lettering", "Prop", "Analysis"):
        cols[k] = bpy.data.collections.new(f"E61_{k}")
        top.children.link(cols[k])

    case, hous, anl = build_crankcase(cols["Body"], M, o["carb"], se_plaque=bool(V.get("castellated")), V=V)
    build_front_housing(hous, cols["Body"], M, o["carb"], K, anl)
    parts = [case, hous, build_cylinder(cols["Body"], M, V)]
    parts += build_gaskets(cols["Body"], M, K)
    parts += build_backplate(cols["Body"], M)
    parts += build_head_se(cols["Body"], M, V) if V.get("castellated") else build_head(cols["Body"], M, V)
    parts += build_carb(cols["Carburetor"], M, kind=o["carb"], side_needle=V.get("side_needle", False))
    front = build_front(cols["Drive"], M, V)
    parts += front
    iparts, roles = build_internals(cols["Internals"], M, K, front)
    parts += iparts
    _, screws = build_screws(cols["Fasteners"], M, o["carb"])
    parts += screws
    mparts = build_muffler(cols["Muffler"], M, screw_mesh(M, 15.0))
    cols["Muffler"].hide_render = cols["Muffler"].hide_viewport = not o["muffler"]
    lparts = build_lettering(cols["Lettering"], M, V, muf_col=cols["Muffler"])
    mparts += [p for p in lparts if p.name.startswith("MUF_")]
    parts += [p for p in lparts if not p.name.startswith("MUF_")]
    if V.get("washer", "hub") != "hub":            # the SE photos show it mounted (washer moved out to the nut)
        pparts = build_prop(cols["Prop"], M)       # optional: shown for comparisons with the photos
        for p in pparts:
            attach(p, roles["crank"])
    else:
        pparts = []
    cols["Prop"].hide_render = cols["Prop"].hide_viewport = True
    for p in parts + mparts + pparts:              # last pass: weld, collapse needle slivers, flip cap slivers
        if p.type == "MESH" and p.data.users == 1:
            final_clean(p)
    for c in list(anl.users_collection):
        c.objects.unlink(anl)
    cols["Analysis"].objects.link(anl)
    anl.display_type, anl.hide_render = "WIRE", True

    root = bpy.data.objects.new("Glow_Engine_61", None)
    root.empty_display_type = "ARROWS"
    root.empty_display_size = 0.03
    top.objects.link(root)
    for p in parts + mparts + [anl]:
        if p.parent is None:
            p.parent = root
    root["variant"], root["carb"] = o["variant"], o["carb"]
    bpy.context.view_layer.update()
    zmin = min((p.matrix_world @ Vector(c)).z for p in parts + mparts if p.type == "MESH" for c in p.bound_box)
    piv = bpy.data.objects.new("PIVOT_Base_Montaje", None)   # lowest point of the engine: snap it to z = 0 to set it down
    piv.empty_display_type, piv.empty_display_size = "PLAIN_AXES", 0.02
    piv.location = (0.0, 0.0, zmin)
    top.objects.link(piv)
    piv.parent = root
    root["base_z_mm"] = round(zmin / MM, 2)
    root["mech"] = __import__("json").dumps(mech_report(K))
    for m in M.values():  # keep both head finishes in the file (swap the material on ENG_Head)
        m.use_fake_user = True
    # sharp edges by angle on the small parts that skip the bevel stack
    for p in parts + mparts:
        if p.type == "MESH" and p.data.users == 1 and p.name.startswith(SHARP_PREFIXES):
            p.data.set_sharp_from_angle(angle=math.radians(35))
    rig_controls(root, parts + mparts, o["carb"], CARB_PLACE[o["carb"]], o["throttle"], mech_roles=roles, K=K)
    for c in add_cutaway(root, [p for p in parts + mparts if p.type == "MESH"], cols["Analysis"]):
        c.parent = root
    anl.hide_set(True)

    bpy.context.view_layer.update()
    info = {"ok": True, "variant": o["variant"], "carb": o["carb"], "objects": len(parts) + len(mparts),
            "mech": mech_report(K)}
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for p in parts + (mparts if o["muffler"] else []):
        for c in p.bound_box:
            w = p.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    info["size_mm"] = [round(v / MM, 1) for v in (hi - lo)]
    if o["save"]:
        path = bpy.path.abspath(o["save"]) if o["save"].startswith("//") else o["save"]
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(path))
        info["saved"] = path
    print(MARK + __import__("json").dumps(info), flush=True)


if __name__ == "__main__":
    main()
