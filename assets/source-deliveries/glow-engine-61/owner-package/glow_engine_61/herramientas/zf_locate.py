"""Locate qa_check-style z-fighting pairs (parallel same-facing tris within eps whose areas overlap).
blender -b file.blend -P zf_locate.py -- OBJ1 [OBJ2] [--eps 0.0002]"""
import sys, bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from collections import Counter
a = sys.argv[sys.argv.index("--") + 1:]
eps = 0.0002
if "--eps" in a:
    eps = float(a[a.index("--eps") + 1]); a = a[:a.index("--eps")]
dg = bpy.context.evaluated_depsgraph_get()
verts, tris, meta = [], [], []
for k, name in enumerate(a):
    ob = bpy.data.objects[name].evaluated_get(dg)
    me = ob.to_mesh()
    bm = bmesh.new(); bm.from_mesh(me); bm.transform(ob.matrix_world)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    off = len(verts)
    verts += [v.co.copy() for v in bm.verts]
    for f in bm.faces:
        tris.append(tuple(off + v.index for v in f.verts)); meta.append((k, f.normal.copy()))
    bm.free()
bvh = BVHTree.FromPolygons(verts, tris, epsilon=0.0)
sets = [set(t) for t in tris]
def pit(q, a, b, c, n):
    for p0, p1 in ((a, b), (b, c), (c, a)):
        if (p1 - p0).cross(q - p0).dot(n) < -1e-9:
            return False
    return True
pairs = set()
for ti, t in enumerate(tris):
    A, B, C = (verts[i] for i in t); n = meta[ti][1]
    if n.length < 0.5: continue
    cen = (A + B + C) / 3
    for p in (cen, cen.lerp(A, .6), cen.lerp(B, .6), cen.lerp(C, .6)):
        for _, _, tj, _ in bvh.find_nearest_range(p, eps):
            if tj is None or tj == ti or sets[ti] & sets[tj]: continue
            if len(a) > 1 and meta[ti][0] == meta[tj][0]: continue
            n2 = meta[tj][1]; d = n.dot(n2)
            if d < 0.999: continue
            a2, b2, c2 = (verts[i] for i in tris[tj])
            q = p - n2 * n2.dot(p - a2)
            if pit(q, a2, b2, c2, n2):
                pairs.add((min(ti, tj), max(ti, tj)))
print("PAIRS", len(pairs))
cnt = Counter()
for i, j in list(pairs):
    c = sum((verts[k] for k in tris[i]), Vector()) / 3 * 1000
    n = meta[i][1]
    cnt[(round(c.z, 1), "n=%.2f,%.2f,%.2f" % tuple(n))] += 1
for k, v in cnt.most_common(25):
    print("ZF", k, v)
for i, j in list(pairs)[:8]:
    print("EX", [tuple(round(x * 1000, 3) for x in verts[k]) for k in tris[i]], [tuple(round(x * 1000, 3) for x in verts[k]) for k in tris[j]])
