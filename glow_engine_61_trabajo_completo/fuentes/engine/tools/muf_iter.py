"""Rebuild only the muffler inside an existing engine blend (fast iteration on the MUF_ parts).

blender -b engine_model.blend -P muf_iter.py -- --save out.blend [--params p.json]
"""
import importlib.util
import json
import sys

import bpy

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
spec = importlib.util.spec_from_file_location("be", "/home/claude/engine/build_engine.py")
be = importlib.util.module_from_spec(spec)
spec.loader.exec_module(be)
if "--params" in a:
    be.FIT.update(json.load(open(a[a.index("--params") + 1])))
for o in [o for o in bpy.data.objects if o.name.startswith("MUF_")]:
    bpy.data.objects.remove(o, do_unlink=True)
col = bpy.data.collections["E61_Muffler"]
M = be.build_materials()
be.SCREW_MESHES.clear()
parts = be.build_muffler(col, M, be.screw_mesh(M, 15.0))
root = bpy.data.objects.get("Glow_Engine_61")
for p in parts:
    if p.parent is None and root:
        p.parent = root
out = a[a.index("--save") + 1]
bpy.ops.wm.save_as_mainfile(filepath=out)
info = {"ok": True, "parts": [p.name for p in parts],
        "tris": sum(sum(len(f.vertices) - 2 for f in p.data.polygons) for p in parts if p.type == "MESH")}
print("@@JSON@@" + json.dumps(info))
