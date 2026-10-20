"""Export Poly Haven's authored Concrete Road Barrier LOD2 for the track.

Run with Blender 5.2.2:
    blender --background --factory-startup --python tools/landscape/export_track_barrier_lod.py

The source mesh is not remodelled or decimated. Its original UVs receive the
supplier's glTF PBR material so the compact 1K JPG maps remain intact.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/source-deliveries/concrete-road-barrier-polyhaven"
MANIFEST = SOURCE / "source-manifest.json"
OUTPUT = ROOT / "app/assets/landscape/track-barrier/concrete-road-barrier-lod2.glb"
MESH_NAME = "concrete_road_barrier_LOD2"


def check_sources() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for entry in manifest["files"]:
        path = SOURCE / entry["path"]
        if not path.is_file():
            raise FileNotFoundError(path)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != entry["sha256"]:
            raise RuntimeError(f"Source hash mismatch: {path}")


def export() -> None:
    check_sources()
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE / "blend/concrete_road_barrier_1k.blend"))
    lod = bpy.data.objects[MESH_NAME]
    source_verts = len(lod.data.vertices)
    source_tris = sum(len(face.vertices) - 2 for face in lod.data.polygons)
    if (source_verts, source_tris) != (2359, 4722):
        raise RuntimeError(f"Unexpected supplier LOD2: {source_verts} vertices, {source_tris} triangles")

    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE / "gltf/concrete_road_barrier_1k.gltf"))
    imported = set(bpy.data.objects) - before
    donor = next(obj for obj in imported if obj.type == "MESH")
    if len(donor.data.materials) != 1:
        raise RuntimeError("Expected one supplier glTF PBR material")
    lod.data.materials.clear()
    lod.data.materials.append(donor.data.materials[0])
    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)

    bpy.ops.object.select_all(action="DESELECT")
    lod.hide_set(False)
    lod.hide_render = False
    lod.select_set(True)
    bpy.context.view_layer.objects.active = lod
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_tangents=True,
        export_image_format="AUTO",
    )
    print(f"Exported {OUTPUT} ({source_tris} supplier triangles)")


if __name__ == "__main__":
    export()
