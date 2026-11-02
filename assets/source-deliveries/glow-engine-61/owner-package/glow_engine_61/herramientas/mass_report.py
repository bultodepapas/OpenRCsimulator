"""Volumes and estimated mass of every part (closed meshes, divergence theorem), density from the material.
blender -b engine.blend -P mass_report.py -- [--out report.json]"""
import json
import sys

import bmesh
import bpy

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RHO = {  # g/cc by material name fragment (first match wins)
    "Tungsten": 17.5, "Brass": 8.5, "Bronze": 8.8, "Copper": 8.9, "Olive_Anodized": 2.7, "Steel": 7.85, "Chrome": 7.85,
    "Black_Oxide": 7.85, "Nickel": 8.9, "Piston": 2.7, "Alu": 2.7, "Head": 2.7, "Plastic": 1.15, "Rubber": 1.1,
    "Gasket": 0.9, "Oil": 0.9, "Soot": 2.7, "Rust": 7.85,
}
dg = bpy.context.evaluated_depsgraph_get()
parts, groups = {}, {}
for ob in bpy.data.objects:
    if ob.type != "MESH" or not ob.name.startswith(("ENG_", "MUF_", "CARB_")):
        continue
    bm = bmesh.new()
    try:
        bm.from_object(ob, dg)
    except ValueError:
        bm.from_mesh(ob.data)
    bm.transform(ob.matrix_world)
    v = abs(bm.calc_volume(signed=True)) * 1e6          # m^3 -> cc
    bm.free()
    mat = ob.data.materials[0].name if ob.data.materials else ""
    rho = next((r for k, r in RHO.items() if k in mat), 2.7)
    g = "muffler" if ob.name.startswith("MUF_") else "carburettor" if ob.name.startswith("CARB_") else \
        "prop+spinner" if ob.name.startswith(("ENG_Spinner", "ENG_Prop_Blades")) else "engine"
    parts[ob.name] = {"cc": round(v, 3), "g": round(v * rho, 2), "material": mat, "group": g}
    groups[g] = groups.get(g, 0.0) + v * rho
rep = {"groups_g": {k: round(v, 1) for k, v in groups.items()},
       "engine_with_carb_g": round(groups.get("engine", 0) + groups.get("carburettor", 0), 1),
       "with_muffler_g": round(groups.get("engine", 0) + groups.get("carburettor", 0) + groups.get("muffler", 0), 1),
       "heaviest": sorted(((k, p["g"]) for k, p in parts.items()), key=lambda t: -t[1])[:12], "parts": parts}
if "--out" in a:
    json.dump(rep, open(a[a.index("--out") + 1], "w"), indent=1)
print("@@JSON@@" + json.dumps({k: rep[k] for k in ("groups_g", "engine_with_carb_g", "with_muffler_g", "heaviest")}))
