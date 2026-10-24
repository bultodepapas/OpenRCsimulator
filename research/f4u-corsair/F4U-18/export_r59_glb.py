"""F4U-18: export the whole R59 aircraft (posed neutral, gear down) as benchmark GLBs at 1/4.5. Never saves R59.

Every render-visible aircraft object (r59_pose.aircraft_objects) is baked with its modifiers into a new mesh in the
GLB model frame of the delivery request: export = (1/4.5) x R x (r59 - D0), Blender +X right, +Y nose, +Z up.
Writes two files into OUT_DIR:
  r59_split.glb   one node per source object, as R59 is built (draw-call cost of the master as is)
  r59_merged.glb  the same triangles joined into one mesh per material (triangle cost without the draw calls)
Benchmark assets only: no sections, pivots or gear rig.

    blender -b -Y --factory-startup F4U_Corsair_R59.blend --python export_r59_glb.py -- OUT_DIR
"""
import bpy, json, os, sys, time
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r59_pose

out_dir = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out_dir, exist_ok=True)
t0 = time.time()
deps = r59_pose.pose_neutral()
R = Matrix(((0, 1, 0), (-1, 0, 0), (0, 0, 1)))
G = (R * (1 / 4.5)).to_4x4()
G.translation = -(R @ Vector(r59_pose.D0)) / 4.5

scene = bpy.data.scenes.new("F4U18_EXPORT")
coll = bpy.data.collections.new("F4U18_aircraft")
scene.collection.children.link(coll)
mirrored = 0
baked = []
for o, evaluated, path in r59_pose.aircraft_objects(deps):
    try:
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=deps)
    except Exception:
        continue
    if mesh is None or not mesh.polygons:
        continue
    matrix = G @ evaluated.matrix_world
    mesh.transform(matrix)
    if matrix.determinant() < 0:
        mesh.flip_normals()
        mirrored += 1
    for i, slot in enumerate(o.material_slots):
        if i < len(mesh.materials):
            mesh.materials[i] = slot.material
    copy = bpy.data.objects.new(o.name.encode("ascii", "replace").decode()[:60], mesh)
    coll.objects.link(copy)
    baked.append(copy)
tris = sum(sum(len(p.vertices) - 2 for p in b.data.polygons) for b in baked)
print("BAKED", len(baked), "objects", tris, "triangles", mirrored, "mirrored", round(time.time() - t0, 1), "s", flush=True)

bpy.context.window.scene = scene
layer = scene.view_layers[0]


def export(name):
    bpy.ops.object.select_all(action="DESELECT")
    for b in coll.objects:
        b.select_set(True)
    path = os.path.join(out_dir, name)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_extras=False, export_cameras=False, export_lights=False,
                              export_animations=False, export_materials="EXPORT", export_image_format="AUTO",
                              export_texcoords=True, export_normals=True, export_tangents=False)
    print("EXPORTED", name, os.path.getsize(path), "bytes", round(time.time() - t0, 1), "s", flush=True)
    return path


summary = {"source": bpy.data.filepath, "objects": len(baked), "triangles": tris, "mirrored": mirrored}
export("r59_split.glb")
summary["split_nodes"] = len(coll.objects)

bpy.ops.object.select_all(action="DESELECT")
for b in coll.objects:
    b.select_set(True)
layer.objects.active = baked[0]
bpy.ops.object.join()
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="MATERIAL")
bpy.ops.object.mode_set(mode="OBJECT")
summary["merged_nodes"] = len(coll.objects)
summary["merged_triangles"] = sum(sum(len(p.vertices) - 2 for p in b.data.polygons) for b in coll.objects)
export("r59_merged.glb")
with open(os.path.join(out_dir, "r59_export.json"), "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=1)
print("R59_EXPORT", json.dumps(summary), flush=True)
