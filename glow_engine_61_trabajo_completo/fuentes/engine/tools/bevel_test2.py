import os, sys, json, bpy
S = "/home/claude/ext/blender-skills-src/skills"
for sub in ("blender-hardsurface-modeling", "blender-asset-qa"):
    sys.path.insert(0, os.path.join(S, sub, "scripts"))
import apply_stack, qa_check
a = sys.argv[sys.argv.index("--") + 1:]
names = a
variants = {"w21_a50_s2": (0.00021, 50, 2), "w15_a50_s2": (0.00015, 50, 2), "w21_a60_s2": (0.00021, 60, 2), "w12_a60_s2": (0.00012, 60, 2), "w08_a60_s2": (0.00008, 60, 2), "w06_a70_s2": (0.00006, 70, 2),
            "w10_a30_s3": (0.00010, 30, 3), "w05_a30_s2": (0.00005, 30, 2), "w08_a45_s2": (0.00008, 45, 2)}
out = {}
for n in names:
    ob = bpy.data.objects[n]
    for vn, (w, ang, seg) in variants.items():
        apply_stack.run(objects=[n], preset="render", width=w, segments=seg, angle=ang)
        r = qa_check.run(objects=[n], profile="render", eps=0.0002, tol=0.001, uv=False)
        m = r["objects"][n]
        out.setdefault(n, {})[vn] = (sum(z["tri_pairs"] for z in r.get("zfighting", [])), m.get("degenerate_faces"), m.get("duplicate_verts"), m.get("tris"))
    for md in [md for md in ob.modifiers if md.name.startswith("HS_")]:
        ob.modifiers.remove(md)
print("@@JSON@@" + json.dumps(out))
