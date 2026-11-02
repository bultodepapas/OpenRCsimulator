"""Rebuild only the SE head body with parameter overrides (FIT head_se) inside an engine blend.
blender -b engine.blend -P head_iter.py -- --set fin_inset=1.8 [--set end_r=3] --save out.blend"""
import importlib.util
import sys

import bpy

a = sys.argv[sys.argv.index("--") + 1:]
spec = importlib.util.spec_from_file_location("be", "/home/claude/engine/build_engine.py")
be = importlib.util.module_from_spec(spec)
spec.loader.exec_module(be)
ov = {}
for i, t in enumerate(a):
    if t == "--set":
        k, v = a[i + 1].split("=")
        ov[k] = float(v)
be.FIT["head_se"] = ov
old = bpy.data.objects["ENG_Head"]
col = old.users_collection[0]
parent, mats = old.parent, list(old.data.materials)
before = set(bpy.data.objects)
M = be.build_materials()
be.SCREW_MESHES.clear()
V = dict(be.VARIANTS["se"])
new = be.build_head_se(col, M, V)
head = new[0]
for o in set(bpy.data.objects) - before - {head}:
    bpy.data.objects.remove(o, do_unlink=True)
mw = old.matrix_world.copy()
bpy.data.objects.remove(old, do_unlink=True)
head.name = "ENG_Head"
head.data.materials.clear()
for m in mats:
    head.data.materials.append(m)
head.parent = parent
bpy.ops.wm.save_as_mainfile(filepath=a[a.index("--save") + 1])
print("@@JSON@@{\"ok\": true}")
