"""Generate the portable Skywalker X8 paint kit with Blender 5.2.2.

blender --background --factory-startup --python tools/skins/build_skywalker_x8.py
"""

import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import zipfile
import zlib
from collections import Counter

import bpy


ROOT = Path(__file__).resolve().parents[2]
GLB = ROOT / "app/assets/aircraft/skywalker-x8/skywalker_x8.glb"
OUTPUT = ROOT / "app/assets/skin-kit/skywalker-x8.zip"
EXPORTER = ROOT / "tools/skins/export_openrc_skin.py"
IMAGE_PACKER = ROOT / "tools/skins/pack_image.py"
GUIDE = ROOT / "app/assets/skin-kit/guide.html"
LOCALES = ROOT / "tools/skins/locales"
EXPECTED_SHA256 = "3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac"
LANGUAGES = (("en", "English"), ("es", "Español"), ("de", "Deutsch"),
             ("fr", "Français"), ("it", "Italiano"), ("ja", "日本語"),
             ("pt_BR", "Português (Brasil)"), ("ru", "Русский"), ("zh_Hans", "简体中文"))


def quickstart():
    """Use the guide's translations so the small ZIP README cannot drift."""
    lines = ["OpenRC — guide.html", ""]
    for language, native_name in LANGUAGES:
        data = json.loads((LOCALES / f"{language}.json").read_text(encoding="utf-8"))
        lines.extend([
            f"{native_name} — {data['title']}",
            f"guide.html — {data['title']}",
            data["get_body"], "",
            data["image_title"], data["image_body"], data["image_steps"],
            data["image_limits"], "",
        ])
    lines.extend([
        "Python 3:",
        'python pack_image.py X8-Paint-edited.png --output my-design.orskin --label "My design"',
        "",
    ])
    return "\n".join(lines)


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


def uv_boundary_png(material, size=2048):
    """Rasterize the original livery UV boundary edges on white, without a GPU."""
    edges = Counter()
    for obj in bpy.data.objects:
        if obj.type != "MESH" or not obj.data.uv_layers:
            continue
        layer = obj.data.uv_layers.active.data
        for face in obj.data.polygons:
            if face.material_index >= len(obj.material_slots) or obj.material_slots[face.material_index].material != material:
                continue
            points = [tuple(layer[index].uv) for index in face.loop_indices]
            if any(not 0.0 <= value <= 1.0 for point in points for value in point):
                raise ValueError(f"{obj.name}: livery UV is outside the reference image.")
            for index, start in enumerate(points):
                end = points[(index + 1) % len(points)]
                if start != end:
                    # Count per object: adjacent faces share an edge, while
                    # separate objects can have their own island boundaries.
                    edges[(obj.name, *sorted((start, end)))] += 1
    if not edges or any(count > 2 for count in edges.values()):
        raise ValueError("Cannot make an unambiguous UV-boundary reference.")
    pixels = bytearray([255]) * size * size

    def draw_line(start, end):
        # Blender UV origin is bottom-left; PNG scanlines start at the top.
        x0, y0 = round(start[0] * (size - 1)), round((1 - start[1]) * (size - 1))
        x1, y1 = round(end[0] * (size - 1)), round((1 - end[1]) * (size - 1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        error = dx + dy
        while True:
            pixels[y0 * size + x0] = 0
            if x0 == x1 and y0 == y1:
                return
            twice = 2 * error
            if twice >= dy:
                error += dy
                x0 += sx
            if twice <= dx:
                error += dx
                y0 += sy

    for (_, start, end), count in edges.items():
        if count == 1:
            draw_line(start, end)

    def chunk(kind, data):
        checksum = zlib.crc32(data, zlib.crc32(kind)) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)

    rows = b"".join(b"\0" + pixels[row * size:(row + 1) * size] for row in range(size))
    header = struct.pack(">IIBBBBB", size, size, 8, 0, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


def main(output=OUTPUT):
    glb = GLB.read_bytes()
    digest = hashlib.sha256(glb).hexdigest()
    if digest != EXPECTED_SHA256:
        raise ValueError(f"Default aircraft changed ({digest}); review the skin contract first.")
    names = glb_materials(glb)
    script = EXPORTER.read_text(encoding="utf-8")
    image_packer = IMAGE_PACKER.read_text(encoding="utf-8")
    guide = GUIDE.read_bytes()
    library = {"__name__": "openrc_export_library"}
    exec(compile(script, str(EXPORTER), "exec"), library)
    image_library = {"__name__": "openrc_image_library"}
    exec(compile(image_packer, str(IMAGE_PACKER), "exec"), image_library)
    if image_library["BASE_ASSET_SHA256"] != digest:
        raise ValueError("Image packer and source GLB identities do not match.")

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

    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="openrc-skin-kit-") as scratch:
        blend = Path(scratch) / "Skywalker-X8.blend"
        paint, pixel_count = library["_png_bytes"](image_node.image, "x8_livery", scratch)
        if tuple(image_node.image.size) != (2048, 2048) or pixel_count != 2048 * 2048:
            raise ValueError("Unexpected source paint dimensions.")
        uv_reference = uv_boundary_png(livery)
        for label, png in (("paint", paint), ("UV reference", uv_reference)):
            if image_library["inspect_png"](png) != (2048, 2048):
                raise ValueError(f"Unexpected {label} PNG dimensions.")
        bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
        fd, temporary = tempfile.mkstemp(prefix=".skywalker-kit-", suffix=".tmp", dir=str(output.parent))
        os.close(fd)
        try:
            with zipfile.ZipFile(temporary, "w") as archive:
                add_zip_file(archive, "Skywalker-X8.blend", blend.read_bytes())
                add_zip_file(archive, "Export OpenRC Skin.py", script.encode("utf-8"))
                add_zip_file(archive, "pack_image.py", image_packer.encode("utf-8"))
                add_zip_file(archive, "X8-Paint.png", paint)
                add_zip_file(archive, "X8-UV.png", uv_reference)
                add_zip_file(archive, "README.txt", quickstart().encode("utf-8"))
                add_zip_file(archive, "guide.html", guide)
            os.replace(temporary, output)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    print(f"OpenRC starter generated: {output} ({output.stat().st_size} bytes)")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Generate the X8 skin starter kit")
    parser.add_argument("--output", default=OUTPUT, help="Output ZIP (default: app/assets/skin-kit/skywalker-x8.zip)")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    main(args.output)
