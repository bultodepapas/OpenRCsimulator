import os, sys, json, bpy
S = "/home/claude/ext/blender-skills-src/skills"
for sub in ("blender-hardsurface-modeling", "blender-asset-qa"):
    sys.path.insert(0, os.path.join(S, sub, "scripts"))
import apply_stack, qa_check
names = ["ENG_Crankcase", "ENG_Carb_Body", "ENG_Head", "ENG_Cylinder_Fins", "ENG_Backplate", "ENG_Prop_Nut", "MUF_Can"]
W = {"ENG_Crankcase": 0.0006, "MUF_Can": 0.0006, "ENG_Backplate": 0.00045, "ENG_Cylinder_Fins": 0.00035,
     "ENG_Carb_Body": 0.00035, "ENG_Head": 0.0003, "ENG_Prop_Nut": 0.0002}
variants = {"A30_s3": (30, 3, 1.0), "B40_s2": (40, 2, 1.0), "C50_s2_w07": (50, 2, 0.7), "D60_s2_w05": (60, 2, 0.5)}
out = {}
for n in names:
    ob = bpy.data.objects[n]
    for vn, (ang, seg, wk) in variants.items():
        apply_stack.run(objects=[n], preset="render", width=W[n] * wk, segments=seg, angle=ang)
        r = qa_check.run(objects=[n], profile="render", eps=0.0002, tol=0.001, uv=False)
        m = r["objects"][n]
        zf = sum(z["tri_pairs"] for z in r.get("zfighting", []))
        out.setdefault(n, {})[vn] = (zf, m.get("degenerate_faces"), m.get("duplicate_verts"), m.get("inconsistent_normals_edges"), m.get("tris"))
    for md in [md for md in ob.modifiers if md.name.startswith("HS_")]:
        ob.modifiers.remove(md)
    r = qa_check.run(objects=[n], profile="render", eps=0.0002, tol=0.001, uv=False); m = r["objects"][n]
    out[n]["none"] = (sum(z["tri_pairs"] for z in r.get("zfighting", [])), m.get("degenerate_faces"), m.get("duplicate_verts"), m.get("inconsistent_normals_edges"), m.get("tris"))
print("@@JSON@@" + json.dumps(out))
