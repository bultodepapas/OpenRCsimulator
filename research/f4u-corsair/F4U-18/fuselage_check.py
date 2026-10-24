"""F4U-18: compare a game fuselage with R59's skin: cross-sections and outward-facing normals. Never saves.

Run once on R59 (MODE r59: 'Fuselaje | volumen continuo' posed neutral and mapped to the 1/4.5 export frame) and
once on a game .blend (MODE game: fuselage_core, scaled by SCALE to 1/4.5). Writes, per station along the nose axis,
the half-width and the top and bottom of the section (mm), and the area share of faces whose normal points toward
the fuselage axis (inward) instead of away from it.

    blender -b -Y --factory-startup R59.blend --python fuselage_check.py -- r59 OUT.json
    blender -b --factory-startup --disable-autoexec GAME.blend --python fuselage_check.py -- game OUT.json SCALE
"""
import bpy, json, os, sys
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
mode, out_path = args[0], args[1]
if mode == "r59":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import r59_pose
    deps = r59_pose.pose_neutral()
    R = Matrix(((0, 1, 0), (-1, 0, 0), (0, 0, 1)))
    G = (R * (1 / 4.5)).to_4x4()
    G.translation = -(R @ Vector(r59_pose.D0)) / 4.5
    obj = bpy.data.objects["Fuselaje | volumen continuo"].evaluated_get(deps)
    matrix = G @ obj.matrix_world
else:
    deps = bpy.context.evaluated_depsgraph_get()
    obj = bpy.data.objects["fuselage_core"].evaluated_get(deps)
    scale = float(args[2])
    matrix = Matrix.Scale(scale, 4) @ obj.matrix_world
mesh = obj.to_mesh()
verts = [matrix @ v.co for v in mesh.vertices]
normal_matrix = matrix.to_3x3().inverted().transposed()
# Fuselage axis: thrust line (z = 0) from spinner to tail; Blender export frame +Y nose, +Z up.
inward = total = 0.0
for p in mesh.polygons:
    c = sum((verts[i] for i in p.vertices), Vector()) / len(p.vertices)
    n = (normal_matrix @ p.normal).normalized()
    radial = Vector((c.x, 0.0, c.z - 0.0))
    area = p.area
    total += area
    if radial.length > 1e-4 and n.dot(radial) < 0:
        inward += area
stations = []
for y in [0.30, 0.20, 0.10, 0.0, -0.10, -0.20, -0.30, -0.40, -0.55, -0.70, -0.90, -1.10, -1.30]:
    band = [v for v in verts if abs(v.y - y) < 0.006]
    if band:
        stations.append({"y_m": y, "half_width_mm": round(1000 * max(abs(v.x) for v in band), 1),
                         "top_mm": round(1000 * max(v.z for v in band), 1),
                         "bottom_mm": round(1000 * min(v.z for v in band), 1), "vertices": len(band)})
result = {"mode": mode, "object": obj.name, "triangles": sum(len(p.vertices) - 2 for p in mesh.polygons),
          "inward_area_share": round(inward / total, 4), "custom_normals": mesh.has_custom_normals,
          "sharp_edges": sum(1 for e in mesh.edges if e.use_edge_sharp) if hasattr(mesh.edges[0], "use_edge_sharp") else None,
          "stations": stations}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=1)
print("FUSELAGE", json.dumps(result))
