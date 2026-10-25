import sys, math
sys.argv=[sys.argv[0]]
sys.path.insert(0, "/home/claude/engine")
import build_engine as be
import bpy, bmesh
be.reset_scene()
V = dict(be.VARIANTS["se"])
P = dict(be.HEAD_SE_P0); Q = dict(be.HEAD_SE2)
z0 = be.fin_top(V) + 0.6; zt = z0 + V["head_h"]; zb = z0 + P["band_h"]
bm = be.heightfield_solid(lambda x, y: be.head_se_height(x, y, P, Q, z0, zb, zt), P["r"], z0, Q["nx"], Q["ny"])
nm = sum(1 for e in bm.edges if not e.is_manifold)
print("HF verts", len(bm.verts), "faces", len(bm.faces), "nonmanifold", nm)
# self-intersection check via BVH overlap of the bmesh with itself is heavy; check zero-area faces
deg = sum(1 for f in bm.faces if f.calc_area() < 1e-8)
print("degenerate", deg)
bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(0.6), verts=bm.verts[:], edges=bm.edges[:])
nm2 = sum(1 for e in bm.edges if not e.is_manifold)
deg2 = sum(1 for f in bm.faces if f.calc_area() < 1e-8)
print("after dissolve faces", len(bm.faces), "nonmanifold", nm2, "degenerate", deg2, "max ngon", max(len(f.verts) for f in bm.faces))
