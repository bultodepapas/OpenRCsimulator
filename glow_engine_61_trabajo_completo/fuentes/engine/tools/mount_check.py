"""Engine-on-mount checks: every BANC_ part against every visible part (engine, carb, muffler, prop and the
other BANC_ parts). Overlapping triangle pairs are classified by penetration depth (vertices of A inside B,
distance to B's surface): <= 0.05 mm is a seated contact; deeper is interference unless the pair is an
intended engagement (screw thread in its tapped hole / blind nut, nut prongs in the ply, letters cast on).
Also: key clearances and the screw thread engagement lengths.
blender -b engine_se_bancada.blend -P mount_check.py -- --out mount_check.json"""
import json
import math
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = A[A.index("--out") + 1] if "--out" in A else None
MM = 0.001
dg = bpy.context.evaluated_depsgraph_get()


def visible(ob):
    return ob.type == "MESH" and not any(c.hide_render for c in ob.users_collection) and not ob.hide_render \
        and ob.name.startswith(("ENG_", "CARB_", "MUF_", "BANC_"))


def data(ob):
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ob.matrix_world
    vs = [(mw @ v.co) / MM for v in me.vertices]
    me.calc_loop_triangles()
    ts = [tuple(t.vertices) for t in me.loop_triangles]
    ev.to_mesh_clear()
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    return BVHTree.FromPolygons(vs, ts, epsilon=0.0), vs, (lo, hi)


objs = [o for o in bpy.data.objects if visible(o)]
D = {o.name: data(o) for o in objs}


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
    """Majority of three ray parities (robust to rays grazing coincident contact faces)."""
    return sum(_parity(tree, p + Vector((1.3e-4, -2.1e-4, 0.7e-4)), d) for d in DIRS) >= 2


def depth(a, b):
    ta, va, _ = D[a]
    tb, vb, (lo, hi) = D[b]
    dmax = 0.0
    for v in va:
        if lo.x <= v.x <= hi.x and lo.y <= v.y <= hi.y and lo.z <= v.z <= hi.z and inside(tb, v):
            dmax = max(dmax, tb.find_nearest(v)[3])
    return dmax


ENGAGE = [("BANC_Tornillo_Motor", "BANC_Bancada_OS905"), ("BANC_Perno_Parallamas", "BANC_Tuerca_Ciega"),
          ("BANC_Tuerca_Ciega", "BANC_Parallamas_Contrachapado"), ("BANC_Letras_OS905", "BANC_Bancada_OS905"),
          ("BANC_Linea_Combustible", "CARB_Fuel_Nipple"), ("BANC_Linea_Presion", "MUF_Pressure_Nipple")]   # line stretched on the barb


def engaged(a, b):
    return any((a.startswith(x) and b.startswith(y)) or (a.startswith(y) and b.startswith(x)) for x, y in ENGAGE)


def boxes_touch(a, b, pad=0.2):
    (la, ha), (lb, hb) = D[a][2], D[b][2]
    return all(la[i] - pad <= hb[i] and lb[i] - pad <= ha[i] for i in range(3))


banc = [n for n in D if n.startswith("BANC_")]
contacts, engagements, interference = {}, {}, {}
seen = set()
for a in banc:
    for b in D:
        if a == b or (b, a) in seen or not boxes_touch(a, b):
            continue
        seen.add((a, b))
        ov = D[a][0].overlap(D[b][0])
        if not ov:
            continue
        dp = max(depth(a, b), depth(b, a))
        k = f"{a} x {b}"
        rec = {"tri_pairs": len(ov), "depth_mm": round(dp, 3)}
        if engaged(a, b):
            engagements[k] = rec
        elif dp <= 0.05:
            contacts[k] = rec
        else:
            interference[k] = rec


def clearance(a, b, step=1):
    ta, va, _ = D[a]
    tb = D[b][0]
    best = (1e9, None)
    for v in va[::step]:
        r = tb.find_nearest(v)
        if r[0] is not None and r[3] < best[0]:
            best = (r[3], v)
    return round(best[0], 2), [round(c, 1) for c in best[1]] if best[1] is not None else None


CL = {}
pairs = [("BANC_Bancada_OS905", "ENG_Crankcase"), ("BANC_Bancada_OS905", "ENG_Backplate"),
         ("BANC_Bancada_OS905", "ENG_Front_Housing"), ("BANC_Bancada_OS905", "CARB_Body"),
         ("BANC_Linea_Combustible", "ENG_Crankcase"), ("BANC_Linea_Combustible", "CARB_Body"),
         ("BANC_Linea_Combustible", "CARB_Needle_Knob"), ("BANC_Linea_Combustible", "BANC_Bancada_OS905"),
         ("BANC_Linea_Combustible", "ENG_Cylinder_Fins"), ("BANC_Linea_Combustible", "CARB_Fuel_Nipple"),
         ("BANC_Linea_Presion", "MUF_Can"), ("BANC_Linea_Presion", "ENG_Head"), ("BANC_Linea_Presion", "MUF_Pressure_Nipple"),
         ("BANC_Linea_Presion", "ENG_Cylinder_Fins"), ("BANC_Parallamas_Contrachapado", "MUF_Can"),
         ("BANC_Fuselaje_Morro", "MUF_Can"), ("BANC_Bancada_OS905", "MUF_Can"), ("ENG_Prop_Blades", "BANC_Bancada_OS905")]
for a, b in pairs:
    if a in D and b in D:
        CL[f"{a} - {b}"] = clearance(a, b, 1 if len(D[a][1]) < 30000 else 3)


def thread_len(screw, part, r_test, length):
    """Length of the shank inside `part` (mm): points at r_test from the screw axis (just outside the hole
    or tap-drill radius) that fall in the part's material, sampled every 0.1 mm over the screw length."""
    ob = bpy.data.objects[screw]
    tb = D[part][0]
    R = ob.matrix_world.to_3x3()
    ax = (R @ Vector((0, 0, -1))).normalized()
    side = (R @ Vector((1, 0, 0))).normalized()
    o = ob.matrix_world.translation / MM
    n = sum(1 for i in range(int(length * 10)) if inside(tb, o + ax * (i * 0.1 + 0.05) + side * r_test))
    return round(n * 0.1, 1)


ENG = {}
for o in objs:
    if o.name.startswith("BANC_Tornillo_Motor"):
        ENG[o.name] = {"in_mount_mm": thread_len(o.name, "BANC_Bancada_OS905", 1.6, 16.0),
                       "through_lug_mm": thread_len(o.name, "ENG_Crankcase", 2.1, 16.0)}
    if o.name.startswith("BANC_Perno_Parallamas"):
        i = o.name.rsplit("_", 1)[1]
        ENG[o.name] = {"in_blind_nut_mm": thread_len(o.name, f"BANC_Tuerca_Ciega_M4_{i}", 2.2, 20.0),
                       "through_plate_mm": thread_len(o.name, "BANC_Bancada_OS905", 2.5, 20.0),
                       "through_firewall_mm": thread_len(o.name, "BANC_Parallamas_Contrachapado", 3.3, 20.0)}
tris = {n: len(bpy.data.objects[n].evaluated_get(dg).data.polygons) for n in banc}
rep = {"interference": interference or "none", "engagements": engagements, "contacts": len(contacts),
       "contact_pairs": sorted(contacts), "clearance_mm": CL, "fasteners": ENG, "banc_parts": len(banc)}
if OUT:
    json.dump(rep, open(OUT, "w"), indent=1)
print("@@JSON@@" + json.dumps({k: rep[k] for k in ("interference", "clearance_mm", "fasteners", "contacts")}), flush=True)
