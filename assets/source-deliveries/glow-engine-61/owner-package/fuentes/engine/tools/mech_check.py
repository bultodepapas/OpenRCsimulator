"""Mechanical check of the glow engine: turns the crank through a full revolution and reports
  - interference (triangle intersections) between every moving group and the static parts / other groups,
  - minimum clearances for the key pairs,
  - port heights + timing measured on the liner mesh, rotary-valve timing measured by ray casts,
  - exhaust port closed to the crankcase at TDC (skirt coverage),
  - combustion-chamber and crankcase volumes -> compression ratios (exact booleans),
  - crankshaft balance factor (mass properties of the meshes).

blender -b engine.blend -P mech_check.py -- [--step 4] [--out report.json]
"""
import json
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, "/home/claude/engine")
import build_engine as H  # noqa: E402

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(k, d=None):
    return a[a.index(k) + 1] if k in a else d


STEP = float(arg("--step", 4))
for c in bpy.data.collections:          # evaluate the optional prop set too (it turns with the shaft)
    if c.name.endswith("Prop"):
        c.hide_viewport = False
root = bpy.data.objects["Glow_Engine_61"]
K = H.mech()

sc = bpy.context.scene
MM = 1000.0

GROUPS = {
    "piston": ["ENG_Piston", "ENG_Piston_Ring", "ENG_Wrist_Pin", "ENG_Circlip_1", "ENG_Circlip_2"],
    "rod": ["ENG_Rod", "ENG_Rod_Bush_Small", "ENG_Rod_Bush_Big"],
    "crank": ["ENG_Crankshaft", "ENG_Crank_Counterweight", "ENG_Bearing_Rear_Inner", "ENG_Bearing_Front_Inner",
              "ENG_Drive_Hub", "ENG_Woodruff_Key", "ENG_Thrust_Washer", "ENG_Prop_Washer", "ENG_Prop_Nut",
              "ENG_Crankshaft_Thread", "ENG_Spinner_Backplate", "ENG_Spinner_Cone", "ENG_Prop_Blades"],
    "balls": ["ENG_Bearing_Rear_Balls", "ENG_Bearing_Rear_Cage", "ENG_Bearing_Front_Balls", "ENG_Bearing_Front_Cage"],
}
moving = {n for g in GROUPS.values() for n in g}
static = [o for o in bpy.data.objects if o.type == "MESH" and o.name not in moving
          and not o.name.startswith(("ANL_", "CUT_", "LD_", "PHOTO", "FIT_"))]
PAIRS = [("piston", "static"), ("rod", "static"), ("crank", "static"), ("balls", "static"),
         ("piston", "rod"), ("piston", "crank"), ("rod", "crank"), ("balls", "crank")]
# designed contact / press fits that are allowed to touch
ALLOW = {("ENG_Wrist_Pin", "ENG_Rod_Bush_Small")}


def tris_world(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ob.matrix_world
    vs = [mw @ v.co for v in me.vertices]
    me.calc_loop_triangles()
    ts = [tuple(t.vertices) for t in me.loop_triangles]
    ev.to_mesh_clear()
    return vs, ts


def bvh(ob):
    vs, ts = tris_world(ob)
    return BVHTree.FromPolygons(vs, ts, epsilon=0.0), vs


def set_crank(deg):
    root["crank_deg"] = float(deg)
    root.update_tag()                      # drivers read the evaluated copy: tag the root first
    bpy.context.view_layer.update()


def mass_props(ob):
    vs, ts = tris_world(ob)
    V, C = 0.0, Vector()
    for i, j, k in ts:
        a_, b_, c_ = vs[i], vs[j], vs[k]
        v = a_.dot(b_.cross(c_)) / 6.0
        V += v
        C += (a_ + b_ + c_) * (v / 4.0)
    return abs(V) * 1e9, (C / V) * MM if V else Vector()   # mm^3, centroid mm


def gas_volume(target_ob, minus, cap=None):
    """volume (mm^3) of copy(target) minus copies of `minus` (evaluated, world space) [minus a cap solid]."""
    dg = bpy.context.evaluated_depsgraph_get()

    def copy(ob):
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), depsgraph=dg)
        me.transform(ob.matrix_world)
        c = bpy.data.objects.new("TMP_gas", me)
        sc.collection.objects.link(c)
        return c
    tgt = copy(target_ob)
    ops = [copy(o) for o in minus if o.name in bpy.data.objects]
    if cap is not None:
        ops.append(H.tmp_obj(cap))
    H.boolean(tgt, ops, "DIFFERENCE")
    bm = bmesh.new()
    bm.from_mesh(tgt.data)
    v = bm.calc_volume(signed=False) * 1e9
    bm.free()
    me = tgt.data
    bpy.data.objects.remove(tgt)
    bpy.data.meshes.remove(me)
    return v


rep = {"mech": json.loads(root["mech"])}
# ---------------------------------------------------------------- interference over a revolution
set_crank(0)
sb = {o.name: bvh(o) for o in static}
hits, clear = {}, {}
CLR = [("ENG_Piston", "ENG_Liner"), ("ENG_Piston", "ENG_Crankcase"), ("ENG_Piston", "ENG_Backplate"),
       ("ENG_Rod", "ENG_Crankcase"), ("ENG_Rod", "ENG_Backplate"), ("ENG_Crankshaft", "ENG_Crankcase"),
       ("ENG_Crankshaft", "ENG_Backplate"), ("ENG_Crankshaft", "ENG_Liner"), ("ENG_Piston_Ring", "ENG_Liner"),
       ("ENG_Rod_Bush_Big", "ENG_Crankshaft"), ("ENG_Rod", "ENG_Crankshaft"), ("ENG_Piston", "ENG_Crankshaft"),
       ("ENG_Rod", "ENG_Piston"), ("ENG_Crankshaft", "ENG_Front_Housing")]
n_steps = int(round(360 / STEP))
for s in range(n_steps):
    th = s * STEP
    set_crank(th)
    mb = {n: bvh(bpy.data.objects[n]) for g in GROUPS.values() for n in g if n in bpy.data.objects}
    for ga, gb in PAIRS:
        A = [n for n in GROUPS[ga] if n in mb]
        B = list(sb) if gb == "static" else [n for n in GROUPS[gb] if n in mb]
        for na in A:
            for nb in B:
                if (na, nb) in ALLOW or (nb, na) in ALLOW:
                    continue
                tb = sb[nb][0] if gb == "static" else mb[nb][0]
                ov = mb[na][0].overlap(tb)
                if ov:
                    k = f"{na} x {nb}"
                    h = hits.setdefault(k, {"tri_pairs_max": 0, "angles": []})
                    h["tri_pairs_max"] = max(h["tri_pairs_max"], len(ov))
                    h["angles"].append(th)
    for na, nb in CLR:
        if na not in mb:
            continue
        tree = mb[nb][0] if nb in mb else sb[nb][0]
        vs = mb[na][1]
        stp = max(1, len(vs) // 4000)
        dmin = min((tree.find_nearest(v)[3] for v in vs[::stp]), default=None)
        if dmin is not None:
            c = clear.setdefault(f"{na} - {nb}", [1e9, None])
            if dmin * MM < c[0]:
                clear[f"{na} - {nb}"] = [round(dmin * MM, 3), th]
for h in hits.values():
    ang = h["angles"]
    h["angles"] = f"{len(ang)} of {n_steps} steps, {min(ang)}..{max(ang)} deg"
rep["interference"] = hits or "none"
rep["min_clearance_mm_at_deg"] = clear

# ---------------------------------------------------------------- ports measured on the liner
set_crank(0)
lin = bpy.data.objects["ENG_Liner"]
vs, _ = tris_world(lin)
crown = K["crown"]


def solve_open(z):
    lo, hi = 0.0, 180.0           # crown(th) decreasing on [0, 180]
    for _ in range(60):
        mid = (lo + hi) / 2
        if crown(mid) > z:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


ports = {}
for name, (ac, half) in (("exhaust", K["exh"]), ("transfer_rear", (K["trans"][0], K["trans"][1])),
                         ("transfer_front", (-K["trans"][0], K["trans"][1])), ("boost", K["boost"])):
    zs_ = []
    for v in vs:
        x, y, z = v * MM
        if abs(math.hypot(x, y) - K["bore"] / 2) > 0.02 or not (20 < z < 45):
            continue
        d = (math.degrees(math.atan2(y, x)) - ac + 180) % 360 - 180
        if abs(d) < half - 2:
            zs_.append(z)
    top, bot = max(zs_), min(zs_)
    o = solve_open(top)
    ports[name] = {"top_z": round(top, 2), "bottom_z": round(bot, 2), "height_mm": round(top - bot, 2),
                   "opens_deg_ATDC": round(o, 1), "closes_deg_ATDC": round(360 - o, 1), "duration_deg": round(360 - 2 * o, 1)}
rep["ports"] = ports
rep["blowdown_deg"] = round(ports["transfer_rear"]["opens_deg_ATDC"] - ports["exhaust"]["opens_deg_ATDC"], 1)

# exhaust closed to the crankcase at TDC: lowest skirt point facing the exhaust window
pis = bpy.data.objects["ENG_Piston"]
pv, _ = tris_world(pis)
ex_lo = []
for v in pv:
    x, y, z = v * MM
    if math.hypot(x, y) > K["bore"] / 2 - 0.1:
        d = (math.degrees(math.atan2(y, x)) - K["exh"][0] + 180) % 360 - 180
        if abs(d) < K["exh"][1]:
            ex_lo.append(z)
rep["exhaust_overlap_at_TDC_mm"] = round(ports["exhaust"]["bottom_z"] - min(ex_lo), 2)

# ---------------------------------------------------------------- rotary valve by ray casts
cs = bpy.data.objects["ENG_Crankshaft"]
py = H.PEDESTAL_Y.get(root["carb"], -36.0)
samples = [(x, py + y) for x in (-3.95, -3.0, -1.5, 0.0, 1.5, 3.0, 3.95) for y in (-3.0, -1.5, -0.4, 0.0, 0.4, 1.5, 3.0)
           if x * x + y * y < K["ped_bore"] ** 2]
open_frac = []
for th in range(0, 360, 2):
    set_crank(th)
    tree, _ = bvh(cs)
    n_open = 0
    for x, y in samples:
        hit = tree.ray_cast(Vector((x, y, 9.0)) / MM, Vector((0, 0, -1)), 0.02)
        z_surf = K.get("za", 0.0) + math.sqrt(max(K["valve_r"] ** 2 - x * x, 0.0))   # journal surface under this ray
        if hit[0] is None or hit[0].z * MM < z_surf - 0.15:          # ray enters the window (flat / scoop)
            n_open += 1
    open_frac.append((th, n_open / len(samples)))
op = [t for t, f in open_frac if f > 0]
# opening window is contiguous across TDC: find first/last open angle around it
seq = [f > 0 for _, f in open_frac]
starts = [open_frac[i][0] for i in range(len(seq)) if seq[i] and not seq[i - 1]]
ends = [open_frac[i][0] for i in range(len(seq)) if seq[i] and not seq[(i + 1) % len(seq)]]
rep["intake_measured"] = {"opens_deg_ATDC": starts, "closes_deg_ATDC": ends,
                          "open_steps": f"{len(op)} of {len(open_frac)} (2 deg steps)",
                          "full_open_deg": [t for t, f in open_frac if f == 1.0][:1] + [t for t, f in open_frac if f == 1.0][-1:]}

# ---------------------------------------------------------------- boost port fed through the piston window
def _feed_rays(th):
    set_crank(th)
    tp, tl = bvh(bpy.data.objects["ENG_Piston"])[0], bvh(bpy.data.objects["ENG_Liner"])[0]
    ok = 0
    for i in range(36):
        z = 18.0 + 0.5 * i
        for a_ in (-10, -5, 0, 5, 10):
            d = Vector((math.cos(math.radians(a_ + K["boost"][0])), math.sin(math.radians(a_ + K["boost"][0])), 0.0))
            o = Vector((0, 0, z)) / MM + d * 0.006
            if tp.ray_cast(o, d, 0.01)[0] is None and tl.ray_cast(o, d, 0.01)[0] is None:
                ok += 1
    return ok


rep["boost_feed_open_rays"] = {f"{th}deg": _feed_rays(th) for th in (180, 150, 120)}

# ---------------------------------------------------------------- volumes and compression
set_crank(0)
zT = K["zT"]
z0 = H.fin_top(H.VARIANTS[root["variant"]]) + 0.6           # head face; the head is solid for >= 3 mm above it
gp = bpy.data.objects["ENG_GlowPlug_Thread"]
plug_top = max((gp.matrix_world @ Vector(c)).z for c in gp.bound_box) * MM - 0.6
cyl_ob = H.tmp_obj(H.bm_cyl(K["bore"] / 2 - K["pis_clear"], (0, 0, zT - 1.0), (0, 0, z0 + 3.0), 96))
H.boolean(cyl_ob, [H.tmp_obj(H.bm_cyl(2.85, (0, 0, z0 + 2.9), (0, 0, plug_top - 0.1), 32))], "UNION")
names = ["ENG_Piston", "ENG_Head", "ENG_Gasket_Head", "ENG_GlowPlug_Thread", "ENG_GlowPlug_Element", "ENG_Liner",
         "ENG_Piston_Ring", "ENG_Cylinder_Fins"]
vc = gas_volume(cyl_ob, [bpy.data.objects[n] for n in names if n in bpy.data.objects])
bpy.data.objects.remove(cyl_ob)
swept = math.pi * (K["bore"] / 2) ** 2 * K["stroke"]
trapped = math.pi * (K["bore"] / 2) ** 2 * (zT - ports["exhaust"]["top_z"])
rep["combustion_chamber_cc"] = round(vc / 1000, 3)
rep["compression_geometric"] = round((swept + vc) / vc, 2)
rep["compression_trapped_from_exhaust_close"] = round((trapped + vc) / vc, 2)
anl = bpy.data.objects["ANL_Crankcase_Cavity"]
solids = [bpy.data.objects[n] for g in ("piston", "rod", "crank", "balls") for n in GROUPS[g]
          if n in bpy.data.objects and n not in ("ENG_Prop_Washer", "ENG_Prop_Nut", "ENG_Crankshaft_Thread")]
solids += [bpy.data.objects[n] for n in ("ENG_Liner", "ENG_Backplate", "ENG_Bearing_Rear_Outer", "ENG_Bearing_Front_Outer",
                                         "ENG_Front_Housing", "ENG_Crankcase") if n in bpy.data.objects]
# crankcase volume by voxels (repeatable, unlike a 20-operand boolean): air = inside the cavity envelope and
# outside every solid, below the piston crown (the bore above the crown belongs to the combustion side)
sys.path.insert(0, "/home/claude/engine/tools")
import numpy as np  # noqa: E402
import voxel_util as VU  # noqa: E402
VOXC = float(arg("--voxel", 0.4))


def tree_mm(ob):
    vs, ts = tris_world(ob)
    vs = [v * MM for v in vs]
    arr = np.array([[v.x, v.y, v.z] for v in vs])
    return BVHTree.FromPolygons(vs, ts, epsilon=0.0), (arr.min(0), arr.max(0))


cav_t = tree_mm(anl)
lo_c, sh_c, ax_c = VU.grid(cav_t[1][0] - 0.5, cav_t[1][1] + 0.5, VOXC)
air_static = VU.inside([cav_t], lo_c, sh_c, ax_c, VOXC)
stat = [o for o in solids if o.name not in moving]
air_static &= ~VU.inside([tree_mm(o) for o in stat], lo_c, sh_c, ax_c, VOXC)
XX, YY = np.meshgrid(ax_c[0], ax_c[1], indexing="ij")
vols = {}
for tag, deg in (("TDC", 0.0), ("BDC", 180.0)):
    set_crank(deg)
    zc = K["zT"] if deg == 0.0 else K["zB"]
    air = air_static & ~VU.inside([tree_mm(o) for o in solids if o.name in moving], lo_c, sh_c, ax_c, VOXC)
    air[:, :, ax_c[2] > zc] &= ~((XX ** 2 + YY ** 2) < (K["bore"] / 2 + 0.05) ** 2)[:, :, None]   # cylinder side of the crown
    vols[tag] = float(air.sum()) * VOXC ** 3
set_crank(0)
rep["crankcase_volume_TDC_cc"] = round(vols["TDC"] / 1000, 2)
rep["crankcase_volume_BDC_cc"] = round(vols["BDC"] / 1000, 2)
rep["crankcase_delta_vs_swept_pct"] = round(100 * ((vols["TDC"] - vols["BDC"]) / swept - 1), 1)
rep["crankcase_compression"] = round(vols["TDC"] / vols["BDC"], 3)
rep["crankcase_voxel_mm"] = VOXC

# ---------------------------------------------------------------- balance
RHO = {"ENG_Crankshaft": 7.85, "ENG_Crank_Counterweight": 17.5, "ENG_Rod": 2.81, "ENG_Rod_Bush_Small": 8.8,
       "ENG_Rod_Bush_Big": 8.8, "ENG_Piston": 2.70, "ENG_Piston_Ring": 7.8, "ENG_Wrist_Pin": 7.85,
       "ENG_Circlip_1": 7.85, "ENG_Circlip_2": 7.85}
mp = {n: mass_props(bpy.data.objects[n]) for n in RHO if n in bpy.data.objects}
g = {n: (v * RHO[n] / 1000.0, c) for n, (v, c) in mp.items()}            # grams, centroid mm
za = K.get("za", 0.0)
zs, zb = K["zp0"], za + K["r"]
m_rod, c_rod = g["ENG_Rod"]
f_big = (zs - c_rod.z) / (zs - zb)
m_recip = sum(g[n][0] for n in ("ENG_Piston", "ENG_Piston_Ring", "ENG_Wrist_Pin", "ENG_Circlip_1", "ENG_Circlip_2",
                                "ENG_Rod_Bush_Small")) + m_rod * (1 - f_big)
m_rot_pin = m_rod * f_big + g["ENG_Rod_Bush_Big"][0]
crank_moment = sum(g[n][0] * (g[n][1].z - za) for n in ("ENG_Crankshaft", "ENG_Crank_Counterweight"))  # g*mm along +Z = pin dir
crank_side = sum(g[n][0] * g[n][1].x for n in ("ENG_Crankshaft", "ENG_Crank_Counterweight"))
bf = (-crank_moment - m_rot_pin * K["r"]) / (m_recip * K["r"])
rep["masses_g"] = {n: round(m, 2) for n, (m, _) in g.items()}
rep["reciprocating_mass_g"] = round(m_recip, 2)
rep["balance_factor_pct"] = round(100 * bf, 1)
rep["crank_side_unbalance_gmm"] = round(crank_side, 2)
set_crank(0)
out = arg("--out")
if out:
    json.dump(rep, open(out, "w"), indent=1)
print("@@JSON@@" + json.dumps(rep))
