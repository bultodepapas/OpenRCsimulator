"""Static checks of the muffler installation.

  - interference: triangle overlaps between every MUF_ part and the engine's static parts (expected contacts listed),
  - clearances: closest approach of the can / arm to the head, fins, crankcase and prop drive,
  - gas path: voxel flood fill from the exhaust duct: it must reach the tail pipe, and with the tail pipe plugged the
    gas volume must be sealed (no leak through the can wall, the arm, the flange or the gasket); reports the volumes.

blender -b engine.blend -P muf_check.py -- [--voxel 0.6] [--out report.json]
"""
import json
import math
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from scipy import ndimage

sys.path.insert(0, "/home/claude/engine")
a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
VOX = float(a[a.index("--voxel") + 1]) if "--voxel" in a else 0.6
OUT = a[a.index("--out") + 1] if "--out" in a else None
MM = 1000.0
dg = bpy.context.evaluated_depsgraph_get()
root = bpy.data.objects.get("Glow_Engine_61")
if root is not None:
    root["crank_deg"] = 75.0   # exhaust port and rotary valve both closed: the gas volume is the muffler side only
    root.update_tag()
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()


def bvh(ob):
    bm = bmesh.new()
    bm.from_object(ob, dg)
    bm.transform(ob.matrix_world)
    bmesh.ops.scale(bm, vec=(MM, MM, MM), verts=bm.verts[:])
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    t = BVHTree.FromBMesh(bm)
    vs = [v.co.copy() for v in bm.verts]
    bm.free()
    return t, vs


mesh = lambda n: n in bpy.data.objects and bpy.data.objects[n].type == "MESH"  # noqa: E731
MUF = [o.name for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("MUF_")]
STATIC = [o.name for o in bpy.data.objects if o.type == "MESH" and o.name.startswith(("ENG_", "CARB_"))
          and not any(c.hide_viewport for c in o.users_collection)       # the optional prop set is not evaluated
          and not o.name.startswith(("ENG_Piston", "ENG_Rod", "ENG_Crankshaft", "ENG_Crank_Counterweight", "ENG_Wrist",
                                     "ENG_Circlip", "ENG_Bearing"))]
T = {n: bvh(bpy.data.objects[n]) for n in MUF + STATIC}
EXPECTED = {  # designed contacts / thread engagement
    ("MUF_Gasket", "ENG_Crankcase"), ("MUF_Gasket", "MUF_Can"),
    ("MUF_Bolt_1", "MUF_Can"), ("MUF_Bolt_2", "MUF_Can"), ("MUF_Bolt_1", "ENG_Crankcase"), ("MUF_Bolt_2", "ENG_Crankcase"),
    ("MUF_Bolt_1", "MUF_Gasket"), ("MUF_Bolt_2", "MUF_Gasket"), ("MUF_Pressure_Nipple", "MUF_Can"), ("MUF_Baffle", "MUF_Can"),
    ("MUF_Letter_744", "MUF_Can"),   # cast lettering: sunk 0.1 mm into the arm so it reads as one casting
}
inter = {}
names = MUF + STATIC
for i, na in enumerate(MUF):
    for nb in names[i + 1:]:
        if nb in MUF[:i + 1]:
            continue
        n = len(T[na][0].overlap(T[nb][0]))
        if n:
            inter[f"{na} - {nb}"] = {"tris": n, "expected": (na, nb) in EXPECTED or (nb, na) in EXPECTED}
unexpected = {k: v for k, v in inter.items() if not v["expected"]}


def clearance(na, nb, step=3):
    tb = T[nb][0]
    best = (1e9, None)
    for v in T[na][1][::step]:
        hit = tb.find_nearest(v)
        if hit[0] is not None and hit[3] < best[0]:
            best = (hit[3], [round(c, 1) for c in v])
    return round(best[0], 2), best[1]


clear = {}
for nb in ("ENG_Head", "ENG_Cylinder_Fins", "ENG_Crankcase", "ENG_GlowPlug_Body", "ENG_Backplate", "ENG_Drive_Hub"):
    if nb in T:
        clear[f"MUF_Can - {nb}"] = clearance("MUF_Can", nb)
for nb in ("MUF_Can",):
    for bolt in ("MUF_Bolt_1", "MUF_Bolt_2"):
        if bolt in T:
            # head-to-casting wrench clearance: nearest can point to the bolt-head rim (head is the -X end)
            vs = [v for v in T[bolt][1] if v.x < min(p.x for p in T[bolt][1]) + 2.9]
            d = min(T[nb][0].find_nearest(v)[3] for v in vs[::2])
            clear[f"{bolt} head - MUF_Can (nearest)"] = round(d, 2)

# ---- gas path by voxel flood fill (parity along +Y rays per solid, union over solids)
SOLIDS = [n for n in MUF + STATIC + ["ENG_Piston", "ENG_Piston_Ring"] if mesh(n)]
for n in ("ENG_Piston", "ENG_Piston_Ring"):
    if n not in T and mesh(n):
        T[n] = bvh(bpy.data.objects[n])
lo = np.array([-110.0, -45.0, 12.0])
hi = np.array([-8.0, 122.0, 78.0])
shape = np.ceil((hi - lo) / VOX).astype(int)
xs = lo[0] + (np.arange(shape[0]) + 0.5) * VOX
ys = lo[1] + (np.arange(shape[1]) + 0.5) * VOX
zs = lo[2] + (np.arange(shape[2]) + 0.5) * VOX
GRID = (xs, ys, zs)


def mark(ax):
    """Solid mask from rays cast along axis `ax` (parity per solid, union over solids)."""
    m = np.zeros(shape, bool)
    u_ax, v_ax = [k for k in range(3) if k != ax]
    d = [3.1e-4, 2.3e-4, 1.7e-4]
    d[ax] = 1.0
    d = Vector(d).normalized()
    for n in SOLIDS:
        tb = T[n][0]
        vs = np.array([[v.x, v.y, v.z] for v in T[n][1]])
        bl, bh = vs.min(0), vs.max(0)
        if (bh < lo).any() or (bl > hi).any():
            continue
        iu = np.where((GRID[u_ax] >= bl[u_ax] - VOX) & (GRID[u_ax] <= bh[u_ax] + VOX))[0]
        iv = np.where((GRID[v_ax] >= bl[v_ax] - VOX) & (GRID[v_ax] <= bh[v_ax] + VOX))[0]
        for i in iu:
            for k in iv:
                o = [0.0, 0.0, 0.0]
                o[u_ax], o[v_ax], o[ax] = GRID[u_ax][i] + 0.0071, GRID[v_ax][k] - 0.0053, lo[ax] - 1.0
                p = Vector(o)
                hits = []
                for _ in range(80):
                    h = tb.ray_cast(p, d, hi[ax] - p[ax] + 2.0)
                    if h[0] is None:
                        break
                    hits.append(h[0][ax])
                    p = h[0] + d * 1e-4
                for c0, c1 in zip(hits[0::2], hits[1::2]):
                    j0, j1 = np.searchsorted(GRID[ax], c0), np.searchsorted(GRID[ax], c1)
                    sl = [i, k]
                    idx = [None, None, None]
                    idx[u_ax], idx[v_ax], idx[ax] = i, k, slice(j0, j1)
                    m[tuple(idx)] = True
    return m


# majority of three ray directions: robust where a wall runs nearly parallel to one ray family
solid = (mark(0).astype(np.int8) + mark(1).astype(np.int8) + mark(2).astype(np.int8)) >= 2
# the exhaust window is covered by the piston at this crank angle (mech_check proves it); the 0.03 mm piston
# clearance is below the voxel size, so the bore itself is treated as closed: the check covers the exhaust side only
XX, YY = np.meshgrid(xs, ys, indexing="ij")
bore = (XX ** 2 + YY ** 2) < 13.6 ** 2     # bore + liner + its 0.05 mm press-fit gap
zb = (zs > 15.0) & (zs < 62.0)
solid[:, :, zb] |= bore[:, :, None]
air = ~solid


def vox(p):
    return tuple(int(v) for v in np.floor((np.array(p) - lo) / VOX))


seed = vox((-26.0, 2.0, 33.5))           # in the muffler inlet duct, just outside the gasket
lab, nlab = ndimage.label(air)
sid = lab[seed]
comp = lab == sid
touch_open = bool(comp[0].any() or comp[-1].any() or comp[:, 0].any() or comp[:, -1].any() or comp[:, :, 0].any()
                  or comp[:, :, -1].any())
# plug the tail pipe: remove the air in a short slice of the tube bore, then the gas volume must be closed
from build_engine import MUF_P0, FIT, muf_geom  # noqa: E402
P = dict(MUF_P0, **FIT.get("muffler", {}))
G = muf_geom(P)
W = G["W"]
plugged = air.copy()
for s_ in np.arange(G["L"] - 6.0, G["L"] - 2.0, VOX / 2):
    for r_ in np.arange(0.0, P["out_ri"] + 0.4, VOX / 2):
        for t_ in np.linspace(0, 2 * math.pi, max(8, int(2 * math.pi * r_ / (VOX / 2)) + 1)):
            q = W @ Vector((r_ * math.cos(t_), s_, r_ * math.sin(t_)))
            iv = vox(q)
            if all(0 <= iv[m] < shape[m] for m in range(3)):
                plugged[iv] = False
# the pressure nipple feeds the fuel tank through a silicone line: plug its bore too
ns, nphi = P["nipple"]
base = G["surf"](ns, nphi, 0.0)
nax = Vector((math.sin(math.radians(nphi)), 0.0, math.cos(math.radians(nphi))))
for t_ in np.arange(-3.0, P["pad"][3] + 7.5, VOX / 2):
    for r_ in np.arange(0.0, 1.3, VOX / 2):
        for a_ in np.linspace(0, 2 * math.pi, 12, endpoint=False):
            u = Vector((math.cos(a_), 0, -math.sin(a_))) * 0 + nax.cross(Vector((0, 1, 0))).normalized() * math.cos(a_) \
                + Vector((0, 1, 0)) * math.sin(a_)
            q = W @ (base + nax * t_ + u * r_)
            iv = vox(q)
            if all(0 <= iv[m] < shape[m] for m in range(3)):
                plugged[iv] = False
tipn = W @ (base + nax * (P["pad"][3] + 6.6))
ivn = vox(tipn)
nipple_open = bool(comp[ivn]) if all(0 <= ivn[m] < shape[m] for m in range(3)) else None
lab2, _ = ndimage.label(plugged)
comp2 = lab2 == lab2[seed]
sealed = not bool(comp2[0].any() or comp2[-1].any() or comp2[:, 0].any() or comp2[:, -1].any() or comp2[:, :, 0].any()
                  or comp2[:, :, -1].any())
leak_at = None
if not sealed:
    b = np.argwhere(comp2 & ~ndimage.binary_erosion(np.ones(shape, bool)))
    leak_at = (lo + (b[len(b) // 2] + 0.5) * VOX).round(1).tolist() if len(b) else None
vol = float(comp2.sum()) * VOX ** 3 / 1000.0
outlet = W @ Vector((0.0, G["L"] + 1.5, 0.0))
iv = vox(outlet)
reaches_outlet = bool(comp[iv]) if all(0 <= iv[m] < shape[m] for m in range(3)) else touch_open
rep = {"interference_unexpected": unexpected or "none", "contacts_expected": sorted(k for k, v in inter.items() if v["expected"]),
       "clearance_mm": clear, "gas_path": {"voxel_mm": VOX, "reaches_tail_pipe": reaches_outlet, "pressure_tap_open": nipple_open, "sealed_when_plugged": sealed,
                                          "leak_at_mm": leak_at, "gas_volume_cc": round(vol, 1)}}
np.save(OUT + ".comp2.npy", comp2); np.save(OUT + ".solid.npy", solid)
if OUT:
    json.dump(rep, open(OUT, "w"), indent=1)
print("@@JSON@@" + json.dumps(rep))
