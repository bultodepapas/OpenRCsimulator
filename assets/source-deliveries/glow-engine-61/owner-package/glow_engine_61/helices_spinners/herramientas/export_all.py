"""GLB of every prop (alone) and every combo (spinner + prop seated on its backplate + hardware), Y-up glTF,
procedural roughness / bump flattened to constants (only image -> BSDF chains survive glTF). The .blend is not
saved. blender -b props_library.blend -P export_all.py -- --out DIR"""
import json
import os
import sys

import bpy

S = os.environ.get("BLENDER_SKILLS", "/home/claude/ext/blender-skills-src/skills")
sys.path.insert(0, os.path.join(S, "blender-export-pipelines", "scripts"))
import export_asset  # noqa: E402

a = sys.argv[sys.argv.index("--") + 1:]
OUT = a[a.index("--out") + 1]
os.makedirs(OUT, exist_ok=True)
MM = 0.001
for m in bpy.data.materials:
    if not m.node_tree:
        continue
    b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if b is None:
        continue
    for sock in ("Roughness", "Normal", "Base Color", "Metallic"):
        for l in list(b.inputs[sock].links):
            m.node_tree.links.remove(l)
    b.inputs["Roughness"].default_value = m.roughness
    b.inputs["Base Color"].default_value = m.diffuse_color
    b.inputs["Metallic"].default_value = m.metallic
res = {}
props = [o for o in bpy.data.objects if o.name.startswith("ROOT_") and not o.name.startswith(("ROOT_SPIN", "ROOT_HW"))]
for r in props:
    k = r.name[5:]
    out = os.path.join(OUT, f"helice_{k}.glb")
    res[k] = export_asset.run(preset="gltf", objects=[r.name], out=out, no_anim=True).get("ok", None)
for cone in [o for o in bpy.data.objects if o.name.endswith("_Cono") and "combo" in o]:
    ck, pk, sk = cone["combo"], cone["prop"], cone["spinner"]
    pr = bpy.data.objects[f"ROOT_{pk}"]
    pr.location = (0, -cone["bp_t"] * MM, 0)
    bpy.context.view_layer.update()
    roots = [pr.name, cone.parent.name, f"ROOT_HW_{ck}"]
    out = os.path.join(OUT, f"conjunto_{ck}_{sk.replace('/', '_')}_{pk}.glb")
    res[f"combo_{ck}"] = export_asset.run(preset="gltf", objects=roots, out=out, no_anim=True).get("ok", None)
    pr.location = (0, 0, 0)
print("@@JSON@@" + json.dumps(res, default=str))
