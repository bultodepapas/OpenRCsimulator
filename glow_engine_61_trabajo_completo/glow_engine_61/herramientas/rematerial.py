"""Rebuild the procedural materials of an existing .blend from build_engine.build_materials() (same names, nodes
replaced in place) -- material iterations without rebuilding the geometry.
blender -b in.blend -P rematerial.py -- --save out.blend"""
import sys
import bpy
sys.path.insert(0, "/home/claude/engine")
import build_engine as H  # noqa: E402
a = sys.argv[sys.argv.index("--") + 1:]
M = H.build_materials()
print("@@JSON@@{\"ok\": true, \"materials\": %d}" % len(M))
bpy.ops.wm.save_as_mainfile(filepath=a[a.index("--save") + 1])
