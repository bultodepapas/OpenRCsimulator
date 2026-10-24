"""F4U-18: export a game .blend (the author's EXPORT_aircraft collection) as a benchmark GLB with the gear down.

Used for the author's g1.21 sources and for the budget-variant derivations of derive.py. SCALE converts a 1:5
derivation to 1:4.5 (10/9) through the root node only; 1 leaves the file as delivered. FLIP, optional, is a
comma-separated list of meshes whose faces are reversed in memory (the F4U-18 inside-out fuselage experiment).
Never saves the .blend.

    blender -b --factory-startup --disable-autoexec GAME.blend --python export_game_glb.py -- OUT.glb SCALE [FLIP]
"""
import bpy, json, os, sys

args = sys.argv[sys.argv.index("--") + 1:]
out_path, scale = args[:2]
scale = float(scale)
for name in (args[2].split(",") if len(args) > 2 else []):
    bpy.data.objects[name].data.flip_normals()
scene = bpy.context.scene
scene.frame_set(0)  # GearRetract frame 0: down and locked
coll = bpy.data.collections["EXPORT_aircraft"]
root = bpy.data.objects["F4UCorsair"]
root.scale = (scale, scale, scale)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
for o in coll.objects:
    o.hide_set(False)
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True, export_yup=True,
                          export_apply=False, export_extras=False, export_cameras=False, export_lights=False,
                          export_animations=False, export_current_frame=True, export_materials="EXPORT",
                          export_image_format="AUTO", export_texcoords=True, export_normals=True,
                          export_tangents=False)
meshes = [o for o in coll.objects if o.type == "MESH"]
summary = {"source": bpy.data.filepath, "meshes": len(meshes),
           "triangles": sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes),
           "surfaces": sum(len({p.material_index for p in o.data.polygons}) for o in meshes),
           "scale": scale, "bytes": os.path.getsize(out_path)}
print("GAME_EXPORT", json.dumps(summary), flush=True)
