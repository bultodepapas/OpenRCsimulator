"""Measure the built props and spinners like a modeller with a Prather gauge and calipers would, and compare
with the source data (APC PE0 tables, UIUC tables, makers' weights).

blender -b props_library.blend -P check_props.py -- --out check.json

Per prop: cylindrical sections of blade 0 at r/R = 0.25 .. 0.95 (unrolled): chord LE-TE, LE-TE pitch,
flat-bottom (Prather) pitch from the longest rear hull edge, max thickness; mass properties from the closed
mesh (volume, mass at the material SG, CG offset from the axis -> static imbalance, polar inertia);
front-view projected area; manifold check.
Per spinner (prop seated on its backplate): clearance from the blade roots to the cone openings, interference.
"""
import json
import math
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, "/home/claude/props")
import propgeom as G  # noqa: E402

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = A[A.index("--out") + 1] if "--out" in A else None
MM = 0.001
IN = 25.4


def mesh_mm(ob):
    me = ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    mw = ob.matrix_world
    vs = [(mw @ v.co) / MM for v in me.vertices]
    me.calc_loop_triangles()
    tris = [tuple(t.vertices) for t in me.loop_triangles]
    edges = [tuple(e.vertices) for e in me.edges]
    ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
    return vs, tris, edges


def mass_props(vs, tris):
    V = 0.0
    c = Vector((0, 0, 0))
    Iyy = 0.0     # about the shaft (Y) axis: integral of x^2 + z^2 dV
    for a, b, d in tris:
        p0, p1, p2 = vs[a], vs[b], vs[d]
        v = p0.dot(p1.cross(p2)) / 6.0
        V += v
        c += v * (p0 + p1 + p2) / 4.0

        def sq(i):
            s0, s1, s2 = p0[i], p1[i], p2[i]
            return (s0 * s0 + s1 * s1 + s2 * s2 + s0 * s1 + s1 * s2 + s0 * s2) / 10.0
        Iyy += v * (sq(0) + sq(2))
    return V, c / V, Iyy


def _parity(tree, p, d):
    n = 0
    q = p
    for _ in range(64):
        h = tree.ray_cast(q, d, 1e4)
        if h[0] is None:
            break
        n += 1
        q = h[0] + d * 1e-4
    return n % 2 == 1


DIRS = [Vector((0.5773, 0.5774, 0.5773)), Vector((-0.6123, 0.3536, 0.7071)), Vector((0.2588, -0.9659, 0.0131))]


def inside(tree, p):
    """Ray-parity majority AND the nearest face's normal (robust where parts sit face to face)."""
    co, n, _, dist = tree.find_nearest(p)
    if co is None or (p - co).dot(n) >= 0:
        return False
    return sum(_parity(tree, p + Vector((1.3e-4, -2.1e-4, 0.7e-4)), d) for d in DIRS) >= 2


def depth(va, tb, vb):
    """Deepest vertex of A inside B (mm): 0 for touching / seated parts."""
    lo = Vector([min(v[i] for v in vb) for i in range(3)])
    hi = Vector([max(v[i] for v in vb) for i in range(3)])
    d = 0.0
    for v in va:
        if all(lo[i] <= v[i] <= hi[i] for i in range(3)) and inside(tb, v):
            d = max(d, tb.find_nearest(v)[3])
    return round(d, 3)


def manifold(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    nm = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()
    return nm


def section(vs, edges, r, theta=0.0, half=60.0):
    """Points where mesh edges cross the cylinder of radius r, near the blade at angle theta (deg)."""
    ct, st = math.cos(math.radians(theta)), math.sin(math.radians(theta))
    pts = []
    for i, j in edges:
        a, b = vs[i], vs[j]
        # blade frame: x' along the blade, z' = rotation direction
        ax, az = a.x * ct + a.z * st, -a.x * st + a.z * ct
        bx, bz = b.x * ct + b.z * st, -b.x * st + b.z * ct
        if ax < 0 or bx < 0 or abs(az) > half or abs(bz) > half:
            continue
        ra, rb = math.hypot(ax, az), math.hypot(bx, bz)
        if (ra - r) * (rb - r) > 0 or ra == rb:
            continue
        t = (r - ra) / (rb - ra)
        x = ax + t * (bx - ax)
        z = az + t * (bz - az)
        y = a.y + t * (b.y - a.y)
        pts.append((r * math.atan2(z, x), -y))          # (u = arc length toward rotation, a = forward)
    return pts


def analyse(pts, r):
    if len(pts) < 8:
        return None
    best = (0, None, None)
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            d = math.dist(pts[i], pts[j])
            if d > best[0]:
                best = (d, pts[i], pts[j])
    c, p, q = best
    le, te = (p, q) if p[0] > q[0] else (q, p)          # leading edge ahead in the rotation direction
    beta = math.atan2(le[1] - te[1], le[0] - te[0])
    # thickness perpendicular to the chord line
    du, da = (le[0] - te[0]) / c, (le[1] - te[1]) / c
    offs = [(-(x - te[0]) * da + (y - te[1]) * du) for x, y in pts]
    tmax = max(offs) - min(offs)
    # Prather / flat-bottom angle: the longest convex-hull edge on the rear (pressure) side
    hull = hull2d(pts)
    fb = None
    for k in range(len(hull)):
        a_, b_ = hull[k], hull[(k + 1) % len(hull)]
        ln = math.dist(a_, b_)
        mid = ((a_[0] + b_[0]) / 2, (a_[1] + b_[1]) / 2)
        side = -(mid[0] - te[0]) * da + (mid[1] - te[1]) * du
        if side <= tmax * 0.35 and (fb is None or ln > fb[0]):
            ang = math.atan2(b_[1] - a_[1], b_[0] - a_[0])
            if ang > math.pi / 2:
                ang -= math.pi
            if ang < -math.pi / 2:
                ang += math.pi
            fb = (ln, ang)
    p_lete = 2 * math.pi * r * math.tan(beta) / IN
    p_flat = 2 * math.pi * r * math.tan(fb[1]) / IN if fb else None
    return dict(chord=round(c, 2), beta=round(math.degrees(beta), 2), pitch_lete_in=round(p_lete, 2),
                pitch_flat_in=round(p_flat, 2) if p_flat else None, flat_len=round(fb[0], 1) if fb else None,
                tmax=round(tmax, 2), le_u=round(le[0], 2), te_u=round(te[0], 2))


def hull2d(pts):
    pts = sorted(set(pts))

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


def ref_data(spec, s):
    """Reference chord / pitch at r/R = s from the source tables."""
    R = spec["D"] * IN / 2
    if spec["kind"] == "apc":
        d = G.read_pe0(spec["pe0"])
        rs = [x["r"] * IN for x in d["rows"]]
        f = lambda k: G.interp(rs, [x[k] for x in d["rows"]], s * R)
        return dict(src="APC PE0", chord=round(f("c") * IN, 2), pitch_flat_in=round(f("p_q"), 2),
                    pitch_lete_in=round(f("p_lete"), 2), tmax=round(f("tmax") * IN, 2))
    geo = G.read_uiuc(spec["uiuc"])
    gs = [g[0] for g in geo]
    k_p = (spec["P"] / spec["D"]) / (spec.get("P_ref", spec["P"]) / spec.get("D_ref", spec["D"]))
    b = math.atan(math.tan(math.radians(G.interp(gs, [g[2] for g in geo], s))) * k_p)
    out = dict(src="UIUC" + (" (escalado)" if k_p != 1 else ""), beta=round(math.degrees(b), 2),
               pitch_lete_in=round(2 * math.pi * s * R * math.tan(b) / IN, 2))
    if spec.get("planform") != "MA3":
        out["chord_uiuc_table"] = round(G.interp(gs, [g[1] for g in geo], s) * R, 2)
        up, dn = G.silhouette(spec["front"], s)
        out["front_width_photo"] = round((up + dn) * R, 2)
    return out


def main():
    rep = {"props": {}, "spinners": {}}
    for spec in G.PROPS:
        ob = bpy.data.objects.get(f"PROP_{spec['key']}")
        if ob is None:
            continue
        vs, tris, edges = mesh_mm(ob)
        V, cg, Iyy = mass_props(vs, tris)
        R = spec["D"] * IN / 2
        sg = spec["sg"]
        m = V / 1000 * sg
        secs = {}
        for s in (0.25, 0.4, 0.5, 0.6, 0.75, 0.9):
            a = analyse(section(vs, edges, s * R), s * R)
            if a:
                a["front_width"] = round(abs(a["le_u"] - a["te_u"]), 2)
                secs[f"{s:.2f}"] = dict(model=a, ref=ref_data(spec, s))
        rmax = max(math.hypot(v.x, v.z) for v in vs)
        ys = [v.y for v in vs]
        e = dict(label=spec["label"], volume_cm3=round(V / 1000, 2), sg=sg, mass_g=round(m, 1),
                 mass_spec_g=spec["mass_spec"], mass_err_pct=round((m / spec["mass_spec"] - 1) * 100, 1)
                 if spec["mass_spec"] else None,
                 implied_sg=round(spec["mass_spec"] / (V / 1000), 2) if spec["mass_spec"] else None,
                 diameter_in=round(2 * rmax / IN, 3), cg_offset_mm=round(math.hypot(cg.x, cg.z), 3),
                 static_imbalance_gmm=round(m * math.hypot(cg.x, cg.z), 2),
                 polar_inertia_kgm2=round(Iyy * sg * 1e-3 * 1e-6 * 1e-3, 7),
                 axial_extent_mm=(round(min(ys), 2), round(max(ys), 2)), non_manifold=manifold(ob),
                 tris=len(tris), sections=secs)
        if spec["kind"] == "apc":
            d = G.read_pe0(spec["pe0"])
            e["pe0_weight_g"] = round(d["weight_g"], 1)
            e["pe0_volume_cm3"] = round(d["volume_in3"] * 16.387, 2)
        rep["props"][spec["key"]] = e
        print(spec["key"], e["mass_g"], e["diameter_in"], {k: (v["model"]["pitch_flat_in"], v["model"]["pitch_lete_in"],
                                                                 v["model"]["chord"]) for k, v in secs.items()},
              flush=True)
    # spinners: put each combo's prop on its backplate and measure the openings
    for cone in [o for o in bpy.data.objects if o.name.endswith("_Cono") and "combo" in o]:
        ck, pk, skey, bpt = cone["combo"], cone["prop"], cone["spinner"], cone["bp_t"]
        bp = bpy.data.objects.get(cone.name.replace("_Cono", "_Placa"))
        prop = bpy.data.objects.get(f"PROP_{pk}")
        if not (bp and prop):
            continue
        prop.parent.location = (0, -bpt * MM, 0)
        bpy.context.view_layer.update()
        pv, pt, _ = mesh_mm(prop)
        cv, ct, _ = mesh_mm(cone)
        bv, bt, _ = mesh_mm(bp)
        tp = BVHTree.FromPolygons(pv, pt)
        tc = BVHTree.FromPolygons(cv, ct)
        tb = BVHTree.FromPolygons(bv, bt)
        dmin = min(tc.find_nearest(v)[3] for v in pv if v.y > -60)
        dmin2 = min(tp.find_nearest(v)[3] for v in cv)
        hw = [o for o in bpy.data.objects if o.name.startswith(f"HW_{ck}_") and o.type == "MESH"]
        hw_c = {}
        for o in hw:
            hv, ht, _ = mesh_mm(o)
            th = BVHTree.FromPolygons(hv, ht)
            hw_c[o.name] = dict(cone=round(min(tc.find_nearest(v)[3] for v in hv), 2),
                                overlap_cone=len(th.overlap(tc)), overlap_prop=len(th.overlap(tp)))
        pen = dict(prop_cone=max(depth(pv, tc, cv), depth(cv, tp, pv)) if tp.overlap(tc) else 0.0,
                   prop_backplate=max(depth(pv, tb, bv), depth(bv, tp, pv)) if tp.overlap(tb) else 0.0,
                   cone_backplate=max(depth(cv, tb, bv), depth(bv, tc, cv)) if tc.overlap(tb) else 0.0)
        for o in hw:
            hv, ht, _ = mesh_mm(o)
            th = BVHTree.FromPolygons(hv, ht)
            for nm_, (tt, vv) in (("cone", (tc, cv)), ("prop", (tp, pv)), ("backplate", (tb, bv))):
                if th.overlap(tt):
                    hw_c[o.name][f"depth_{nm_}"] = max(depth(hv, tt, vv), depth(vv, th, hv))
        rep["spinners"][skey] = dict(prop=pk, combo=ck, blade_to_cone_min_mm=round(min(dmin, dmin2), 2),
                                     penetration_mm=pen, hardware=hw_c,
                                     non_manifold=dict(cone=manifold(cone), backplate=manifold(bp)))
        prop.parent.location = (0, 0, 0)
        print(skey, rep["spinners"][skey], flush=True)
    if OUT:
        json.dump(rep, open(OUT, "w"), indent=1)
    print("@@JSON@@done", flush=True)


main()
