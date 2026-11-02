import sys, os, json, time
import bpy
A = sys.argv[sys.argv.index("--") + 1:]
sys.argv = [sys.argv[0]]
sys.path.insert(0, "/home/claude/engine")
import build_engine as be
sc = be.reset_scene(); be.SCREW_MESHES.clear(); M = be.build_materials(); V = dict(be.VARIANTS["se"])
col = bpy.data.collections.new("HEAD_DEV"); sc.collection.children.link(col)
t0 = time.time()
parts = [be.build_cylinder(col, M, V)] + be.build_head_se(col, M, V)
for p in parts:
    if p.type == "MESH" and p.data.users == 1:
        be.final_clean(p)
print("build s", round(time.time() - t0, 1))
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A[0]))
