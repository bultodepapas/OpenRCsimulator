"""Seat each combo's prop on its spinner backplate and lay the combos / loose props out for previews.
blender -b props_library.blend -P arrange.py -- --save out.blend [--mode combos|props]"""
import math, sys
import bpy
from mathutils import Vector
A = sys.argv[sys.argv.index("--") + 1:]
SAVE = A[A.index("--save") + 1]
MODE = A[A.index("--mode") + 1] if "--mode" in A else "combos"
MM = 0.001
cones = sorted([o for o in bpy.data.objects if o.name.endswith("_Cono") and "combo" in o], key=lambda o: o["combo"])
used = set()
if MODE == "combos":
    for i, cone in enumerate(cones):
        x = (i - (len(cones) - 1) / 2) * 0.36
        sroot = cone.parent
        sroot.location = (x, 0, 0)
        hw = bpy.data.objects.get(f"ROOT_HW_{cone['combo']}")
        if hw:
            hw.location = (x, 0, 0)
        p = bpy.data.objects[f"PROP_{cone['prop']}"].parent
        p.location = (x, -cone["bp_t"] * MM, 0)
        used.add(p.name)
    for o in bpy.data.objects:
        if o.name.startswith("ROOT_") and not o.name.startswith(("ROOT_SPIN", "ROOT_HW")) and o.name not in used:
            for c in o.children:
                c.hide_render = True
else:
    roots = [o for o in bpy.data.objects if o.name.startswith("ROOT_") and not o.name.startswith(("ROOT_SPIN", "ROOT_HW"))]
    for i, o in enumerate(roots):
        o.location = ((i % 3 - 1) * 0.34, 0, -(i // 3) * 0.09)
    for o in bpy.data.objects:
        if o.name.startswith(("ROOT_SPIN", "ROOT_HW")):
            for c in o.children:
                c.hide_render = True
bpy.ops.wm.save_as_mainfile(filepath=SAVE)
