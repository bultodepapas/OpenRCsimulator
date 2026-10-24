"""F4U-18: read-only detail inventory of the R59 master, posed neutral in memory (never saved).

For every render-visible aircraft mesh, curve or text object: collection path, triangles with modifiers (viewport
levels, as the depsgraph evaluates in background mode), triangles of the base mesh, Subdivision levels, materials,
UV presence and world-space size. Groups by top-level collection so the game revisions can be compared part by part.

    blender -b -Y --factory-startup F4U_Corsair_R59.blend --python inventory_r59.py -- OUT.json
"""
import bpy, json, os, sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r59_pose

out_path = sys.argv[sys.argv.index("--") + 1]
deps = r59_pose.pose_neutral()

rows = []
for o, evaluated, path in r59_pose.aircraft_objects(deps):
    try:
        mesh = evaluated.to_mesh()
    except Exception:
        continue
    if mesh is None or not mesh.vertices:
        evaluated.to_mesh_clear()
        continue
    mesh.calc_loop_triangles()
    used = {t.material_index for t in mesh.loop_triangles}
    mats = sorted({(o.material_slots[i].material.name if i < len(o.material_slots) and o.material_slots[i].material
                    else "<none>") for i in used})
    mw = evaluated.matrix_world
    pts = [mw @ v.co for v in mesh.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    base = sum(len(p.vertices) - 2 for p in o.data.polygons) if o.type == "MESH" else None
    rows.append({
        "name": o.name, "type": o.type, "path": path, "tris": len(mesh.loop_triangles), "verts": len(mesh.vertices),
        "base_tris": base, "materials": mats, "has_uv": bool(mesh.uv_layers),
        "subsurf": [[m.levels, m.render_levels] for m in o.modifiers if m.type == "SUBSURF" and m.show_viewport],
        "modifiers": sorted({m.type for m in o.modifiers if m.show_viewport}),
        "size_m": [round(x, 4) for x in (hi - lo)], "lo": [round(x, 4) for x in lo], "hi": [round(x, 4) for x in hi],
    })
    evaluated.to_mesh_clear()

def group(key):
    acc = {}
    for r in rows:
        e = acc.setdefault(key(r), {"objects": 0, "tris": 0, "base_tris": 0, "subsurf_objects": 0, "materials": set()})
        e["objects"] += 1
        e["tris"] += r["tris"]
        e["base_tris"] += r["base_tris"] or r["tris"]
        e["subsurf_objects"] += bool(r["subsurf"])
        e["materials"].update(r["materials"])
    return {k: dict(v, materials=len(v["materials"])) for k, v in sorted(acc.items(), key=lambda kv: -kv[1]["tris"])}

result = {
    "file": bpy.data.filepath, "blender": bpy.app.version_string,
    "objects": len(rows), "tris": sum(r["tris"] for r in rows),
    "base_tris": sum((r["base_tris"] or r["tris"]) for r in rows),
    "materials": len({m for r in rows for m in r["materials"]}),
    "surfaces": sum(len(r["materials"]) for r in rows),
    "by_top": group(lambda r: r["path"][0] if r["path"] else ""),
    "rows": rows,
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=1, ensure_ascii=False)
print("INVENTORY objects", result["objects"], "tris", result["tris"], "base", result["base_tris"],
      "materials", result["materials"], "surfaces", result["surfaces"])
