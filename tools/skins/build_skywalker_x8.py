"""Generate the portable Skywalker X8 paint kit with Blender 5.2.2.

blender --background --factory-startup --python tools/skins/build_skywalker_x8.py
"""

import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
import zipfile

import bpy


ROOT = Path(__file__).resolve().parents[2]
GLB = ROOT / "app/assets/aircraft/skywalker-x8/skywalker_x8.glb"
OUTPUT = ROOT / "app/assets/skin-kit/skywalker-x8.zip"
EXPORTER = ROOT / "tools/skins/export_openrc_skin.py"
GUIDE = ROOT / "app/assets/skin-kit/guide.html"
EXPECTED_SHA256 = "3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac"
README = """OpenRC Skywalker X8 skin starter

1. Extract this ZIP and open Skywalker-X8.blend in Blender 5.2.2.
2. Paint the existing x8_livery Base Color image in Texture Paint, or change
   a material's Principled Base Color. Keep the model, UVs and slots unchanged.
3. Save your .blend. Pack external images with File > External Data > Pack
   Resources to keep them with your project.
4. Switch to Scripting. In the Text Editor select Export OpenRC Skin.py and
   click Run Script. Choose a filename ending in .orskin and save it. The
   filename becomes the name shown in OpenRC.
5. In OpenRC, import the .orskin from the aircraft's skin controls.

Open guide.html for the complete offline tutorial and a reusable AI prompt.

Only Base Color and a directly connected sRGB Image Texture are exported.
Bake procedural or mixed Base Color nodes to a single image before export.
Other shader channels, geometry and transparency settings come from the
original aircraft. This package is not a 3D model or a flight-physics change.

For noninteractive Blender, run:
  blender --background Skywalker-X8.blend --python "Export OpenRC Skin.py" --
    --output my-design.orskin --label "My design"
(Use one command line; the line break above is for readability.)
"""


def glb_materials(data):
    if data[:4] != b"glTF" or struct.unpack_from("<I", data, 4)[0] != 2:
        raise ValueError("Expected a glTF 2.0 GLB")
    length, kind = struct.unpack_from("<II", data, 12)
    if kind != 0x4E4F534A:
        raise ValueError("GLB JSON chunk is missing")
    document = json.loads(data[20:20 + length])
    names = [m.get("name", "") for m in document["materials"]]
    if len(names) != 9 or len(set(names)) != len(names) or not all(names):
        raise ValueError("Unexpected GLB material identities")
    return names


def add_zip_file(archive, name, data):
    info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    archive.writestr(info, data)


def main():
    glb = GLB.read_bytes()
    digest = hashlib.sha256(glb).hexdigest()
    if digest != EXPECTED_SHA256:
        raise ValueError(f"Default aircraft changed ({digest}); review the skin contract first.")
    names = glb_materials(glb)
    script = EXPORTER.read_text(encoding="utf-8")
    guide = GUIDE.read_bytes()
    library = {"__name__": "openrc_export_library"}
    exec(compile(script, str(EXPORTER), "exec"), library)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    for name in names:
        mat = bpy.data.materials.get(name)
        if mat is None:
            raise ValueError(f"GLB material did not import with its original identity: {name}")
        mat["openrc_material_name"] = name
    for obj in bpy.data.objects:
        obj["openrc_object_id"] = obj.name
        if obj.type == "MESH":
            obj["openrc_mesh_id"] = obj.name
    # Keep all the imported normal, emissive and color images portable.
    bpy.ops.file.pack_all()
    for image in bpy.data.images:
        if image.source == "FILE" and image.has_data and image.packed_file is None:
            raise ValueError(f"Image was not packed: {image.name}")
    livery = bpy.data.materials["x8_livery"]
    shader = library["_shader"](livery)
    image_node = shader.inputs["Base Color"].links[0].from_node
    image_node.select = True
    livery.node_tree.nodes.active = image_node

    baseline = {
        "format": "openrc-skin-starter-baseline-v1",
        "aircraft_id": "skywalker-x8",
        "base_asset_sha256": digest,
        "materials": names,
        "meshes": library["mesh_signatures"](),
    }
    bpy.data.texts.new(library["BASELINE_TEXT"]).write(json.dumps(baseline, indent=2) + "\n")
    exporter_text = bpy.data.texts.new("Export OpenRC Skin.py")
    exporter_text.write(script)
    for workspace in bpy.data.workspaces:
        for screen in workspace.screens:
            for area in screen.areas:
                if area.type == "TEXT_EDITOR":
                    area.spaces.active.text = exporter_text
                elif area.type == "VIEW_3D":
                    area.spaces.active.region_3d.view_distance = 4.5
                    area.spaces.active.shading.type = "MATERIAL"
    wing = bpy.data.objects.get("wing_left_fixed")
    if wing:
        bpy.ops.object.select_all(action="DESELECT")
        wing.select_set(True)
        bpy.context.view_layer.objects.active = wing
        wing.active_material_index = next(
            index for index, slot in enumerate(wing.material_slots)
            if slot.material and slot.material.get("openrc_material_name") == "x8_livery"
        )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="openrc-skin-kit-") as scratch:
        blend = Path(scratch) / "Skywalker-X8.blend"
        bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
        fd, temporary = tempfile.mkstemp(prefix=".skywalker-kit-", suffix=".tmp", dir=str(OUTPUT.parent))
        os.close(fd)
        try:
            with zipfile.ZipFile(temporary, "w") as archive:
                add_zip_file(archive, "Skywalker-X8.blend", blend.read_bytes())
                add_zip_file(archive, "Export OpenRC Skin.py", script.encode("utf-8"))
                add_zip_file(archive, "README.txt", README.encode("utf-8"))
                add_zip_file(archive, "guide.html", guide)
            os.replace(temporary, OUTPUT)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    print(f"OpenRC starter generated: {OUTPUT} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
