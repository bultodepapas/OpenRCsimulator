"""
Re-export export/aircraft.glb from the editable source/aircraft_game.blend (the documented export preset).

  blender -b source/aircraft_game.blend --python source/scripts/exporta_desde_blend.py -- export/aircraft.glb
  python3 source/scripts/exporta_desde_blend.py source/aircraft_game.blend export/aircraft.glb   (bpy module)

Settings (identical to the build): glTF binary, only the collection EXPORT_aircraft, +Y up, apply modifiers,
custom properties (extras) ON, materials exported, no cameras, no lights, no animation, no compression.
The saved .blend holds the rest pose and no animation; keep pivots at rest when editing (or revert) before export.
"""
import bpy, sys, os
a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
if len(a) == 2:
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(a[0])); out = os.path.abspath(a[1])
else:
    out = os.path.abspath(a[0])
SETTINGS = dict(export_format='GLB', use_active_collection=True, export_yup=True, export_apply=True, export_extras=True,
                export_animations=False, export_cameras=False, export_lights=False, export_materials='EXPORT',
                export_draco_mesh_compression_enable=False)
sc = bpy.context.scene
sc.frame_set(1)
for o in bpy.data.collections["EXPORT_aircraft"].all_objects:
    if o.animation_data: o.animation_data.action = None
vl = bpy.context.view_layer
vl.active_layer_collection = vl.layer_collection.children["EXPORT_aircraft"]
bpy.ops.export_scene.gltf(filepath=out, **SETTINGS)
print("EXPORTED", out)
