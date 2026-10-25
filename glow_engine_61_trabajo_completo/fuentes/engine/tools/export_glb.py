"""Export the engine to GLB with the skill's export_asset (procedural roughness/bump flattened to
constants first, since only image->BSDF chains survive glTF). The .blend is not modified."""
import json, os, sys
import bpy
S = os.environ.get("BLENDER_SKILLS", "/home/claude/ext/blender-skills-src/skills")
sys.path.insert(0, os.path.join(S, "blender-export-pipelines", "scripts"))
import export_asset  # noqa: E402
a = sys.argv[sys.argv.index("--") + 1:]
out = a[a.index("--out") + 1]
for m in bpy.data.materials:
    if not m.name.startswith("M_") or not m.node_tree:
        continue
    b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    for sock in ("Roughness", "Normal", "Base Color", "Metallic"):
        for l in list(b.inputs[sock].links):
            m.node_tree.links.remove(l)
    b.inputs["Roughness"].default_value = m.roughness
    b.inputs["Base Color"].default_value = m.diffuse_color
    b.inputs["Metallic"].default_value = m.metallic
root = a[a.index("--root") + 1] if "--root" in a else "Glow_Engine_61"
res = export_asset.run(preset="gltf", objects=root.split(","), out=out, no_anim=True)
print("@@JSON@@" + json.dumps(res, default=str))
