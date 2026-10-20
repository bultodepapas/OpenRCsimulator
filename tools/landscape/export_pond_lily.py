"""Export the retained CC0 Nymphaea leaf to a small, source-preserving GLB.

Run with Blender 5.2.2:
  blender -b --python tools/landscape/export_pond_lily.py
"""

from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile
import bpy


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/landscape/pond-plants/source/water_lilly.blend"
DEST = ROOT / "app/assets/landscape/pond-plants/nymphaea_leaf.glb"
FLOWER_SOURCE = ROOT / "assets/landscape/pond-plants/source/waterlily.zip"
FLOWER_DEST = ROOT / "app/assets/landscape/pond-plants/white_waterlily_flower.glb"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
leaf = bpy.data.objects["Nymph Original"]
for obj in list(bpy.data.objects):
    if obj != leaf:
        bpy.data.objects.remove(obj, do_unlink=True)

leaf.name = "NymphaeaLeaf"
leaf.data.name = "NymphaeaLeafSourceMesh"
leaf.data.flip_normals()  # Source top faces down; orient the exposed leaf upward.
bpy.ops.object.select_all(action="DESELECT")
leaf.select_set(True)
bpy.context.view_layer.objects.active = leaf
for modifier in list(leaf.modifiers):
    if modifier.type == "NODES":
        leaf.modifiers.remove(modifier)
    else:
        bpy.ops.object.modifier_apply(modifier=modifier.name)

# The supplied radial UVs and leaf/notch topology are retained. Godot supplies
# the lake-specific color/venation and analytic water-height material at runtime.
leaf.data.materials.clear()
DEST.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(DEST), export_format="GLB", use_selection=True,
    export_apply=True, export_yup=True,
)
print(f"Exported {DEST}: {len(leaf.data.polygons)} source-derived faces")

bpy.ops.wm.read_factory_settings(use_empty=True)
with TemporaryDirectory() as directory:
    with ZipFile(FLOWER_SOURCE) as archive:
        archive.extract("waterlily_white_flower.obj", directory)
        archive.extract("waterlily_white_flower.mtl", directory)
    bpy.ops.wm.obj_import(filepath=str(Path(directory) / "waterlily_white_flower.obj"))
flower = next(obj for obj in bpy.data.objects if obj.type == "MESH")
flower.name = "WhiteWaterlilyFlower"
flower.rotation_euler.x = 1.5707963267948966  # OBJ's Y-up to Blender's Z-up.
bpy.context.view_layer.objects.active = flower
flower.select_set(True)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
corners = [flower.matrix_world @ __import__("mathutils").Vector(corner) for corner in flower.bound_box]
cx = (min(v.x for v in corners) + max(v.x for v in corners)) * 0.5
cy = (min(v.y for v in corners) + max(v.y for v in corners)) * 0.5
bottom = min(v.z for v in corners)
for vertex in flower.data.vertices:
    vertex.co.x -= cx
    vertex.co.y -= cy
    vertex.co.z -= bottom
bpy.ops.export_scene.gltf(
    filepath=str(FLOWER_DEST), export_format="GLB", use_selection=True,
    export_apply=True, export_yup=True,
)
print(f"Exported {FLOWER_DEST}: {len(flower.data.polygons)} source-derived faces")
