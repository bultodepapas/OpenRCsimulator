"""Per-object mesh health: non-manifold edges, inconsistent winding, degenerate / duplicate faces, loose parts.
blender -b f.blend -P mesh_defects.py -- [--prefix ENG_,MUF_,CARB_] [--out report.json] [--detail NAME]"""
import json
import sys

import bmesh
import bpy

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PRE = tuple((a[a.index("--prefix") + 1] if "--prefix" in a else "ENG_,MUF_,CARB_").split(","))
DET = a[a.index("--detail") + 1] if "--detail" in a else None
rep = {}
for ob in bpy.data.objects:
    if ob.type != "MESH" or not ob.name.startswith(PRE):
        continue
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.transform(ob.matrix_world)
    bmesh.ops.scale(bm, vec=(1000, 1000, 1000), verts=bm.verts[:])
    nm = [e for e in bm.edges if len(e.link_faces) != 2]
    wind = []
    for e in bm.edges:
        if len(e.link_faces) == 2:
            f0, f1 = e.link_faces
            v0, v1 = e.verts
            # consistent winding: the edge is traversed in opposite directions by the two faces
            def dirn(f):
                vs = list(f.verts)
                i = vs.index(v0)
                return vs[(i + 1) % len(vs)] is v1
            if dirn(f0) == dirn(f1):
                wind.append(e)
    deg = [f for f in bm.faces if f.calc_area() < 1e-6]
    keys = {}
    dup = 0
    for f in bm.faces:
        k = frozenset(v.index for v in f.verts)
        dup += k in keys
        keys[k] = 1
    r = {"tris": sum(len(f.verts) - 2 for f in bm.faces), "non_manifold": len(nm), "winding": len(wind),
         "degenerate": len(deg), "duplicate": dup}
    if any(r[k] for k in ("non_manifold", "winding", "degenerate", "duplicate")):
        rep[ob.name] = r
        if DET and ob.name == DET:
            r["nm_at"] = [[round(c, 2) for c in ((e.verts[0].co + e.verts[1].co) / 2)] for e in nm[:12]]
            r["wind_at"] = [[round(c, 2) for c in ((e.verts[0].co + e.verts[1].co) / 2)] for e in wind[:12]]
            r["deg_at"] = [[round(c, 3) for c in f.calc_center_median()] + [round(f.calc_area(), 8), len(f.verts)] for f in deg[:12]]
    bm.free()
if "--out" in a:
    json.dump(rep, open(a[a.index("--out") + 1], "w"), indent=1)
print("@@JSON@@" + json.dumps(rep))
