"""Generate paint kits from the verified stock or prepared aircraft scenes.

Run in Blender 5.2.2: blender --background --factory-startup
    --python-exit-code 1 --python tools/skins/build_skin_kits.py -- [family ...]
"""

from collections import Counter
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import sys
import tempfile
import zipfile
import zlib

import bpy


ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "app/assets/skin-kit/models.json"
EXPORTER = ROOT / "tools/skins/export_openrc_skin.py"
IMAGE_PACKER = ROOT / "tools/skins/pack_image.py"
GUIDE = ROOT / "app/assets/skin-kit/guide.html"
LOCALES = ROOT / "tools/skins/locales"
LANGUAGES = (("en", "English"), ("es", "Español"), ("de", "Deutsch"),
             ("fr", "Français"), ("it", "Italiano"), ("ja", "日本語"),
             ("pt_BR", "Português (Brasil)"), ("ru", "Русский"), ("zh_Hans", "简体中文"))


def quickstart():
    lines = ["OpenRC — guide.html", ""]
    for language, native_name in LANGUAGES:
        data = json.loads((LOCALES / f"{language}.json").read_text(encoding="utf-8"))
        lines.extend([f"{native_name} — {data['title']}", f"guide.html — {data['title']}",
                      data["get_body"], "", data["image_title"], data["image_body"],
                      data["image_steps"], data["image_limits"], ""])
    lines += ["Python 3:", 'python pack_image.py --output my-design.orskin --label "My design"', ""]
    return "\n".join(lines)


def local_path(path):
    if not path.startswith("res://"):
        raise ValueError("Registry paths must use res://")
    result = (ROOT / "app" / path[6:]).resolve()
    if not result.is_relative_to((ROOT / "app").resolve()):
        raise ValueError("Registry path escapes app/")
    return result


def glb_materials(data):
    if data[:4] != b"glTF" or struct.unpack_from("<I", data, 4)[0] != 2:
        raise ValueError("Expected a glTF 2.0 GLB")
    length, kind = struct.unpack_from("<II", data, 12)
    if kind != 0x4E4F534A:
        raise ValueError("GLB JSON chunk is missing")
    document = json.loads(data[20:20 + length])
    names = [m.get("name", "") for m in document["materials"]]
    if not names or len(set(names)) != len(names) or not all(names):
        raise ValueError("The GLB must have unique named materials")
    return names


def add_zip_file(archive, name, data):
    info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    archive.writestr(info, data)


def blender_glb(data, scratch):
    """Translate Godot's node-visibility extension for Blender's importer.

    The source bytes remain unchanged. The returned names must be hidden along
    with their descendants after import, preserving the preview hierarchy.
    """
    length, kind = struct.unpack_from("<II", data, 12)
    if data[:4] != b"glTF" or kind != 0x4E4F534A:
        raise ValueError("Expected a glTF JSON chunk")
    document = json.loads(data[20:20 + length])
    extension = "KHR_node_visibility"
    if extension not in document.get("extensionsUsed", []):
        return None, []
    hidden = []
    for node in document.get("nodes", []):
        extensions = node.get("extensions", {})
        if extension in extensions:
            state = extensions.pop(extension)
            if not isinstance(state, dict) or not isinstance(state.get("visible", True), bool):
                raise ValueError("Unsupported node visibility record")
            if not state.get("visible", True):
                if not node.get("name"):
                    raise ValueError("A hidden source node has no name")
                hidden.append(node["name"])
            if not extensions:
                node.pop("extensions", None)
    for key in ("extensionsUsed", "extensionsRequired"):
        if key in document:
            document[key] = [item for item in document[key] if item != extension]
            if not document[key]:
                del document[key]
    encoded = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    encoded += b" " * (-len(encoded) % 4)
    tail = data[20 + length:]
    total = 20 + len(encoded) + len(tail)
    path = Path(scratch) / "blender-import.glb"
    path.write_bytes(b"glTF" + struct.pack("<II", 2, total) +
                     struct.pack("<II", len(encoded), 0x4E4F534A) + encoded + tail)
    return path, hidden


def _clip_line(start, end, tile_x, tile_y):
    """Clip a UV segment to one repeat tile and map it to the base image."""
    x, y = start
    dx, dy = end[0] - x, end[1] - y
    lo, hi = 0.0, 1.0
    for p, q in ((-dx, x - tile_x), (dx, tile_x + 1 - x),
                 (-dy, y - tile_y), (dy, tile_y + 1 - y)):
        if p == 0:
            if q < 0:
                return None
        elif p < 0:
            lo = max(lo, q / p)
        else:
            hi = min(hi, q / p)
        if lo > hi:
            return None
    return ((x + dx * lo - tile_x, y + dy * lo - tile_y),
            (x + dx * hi - tile_x, y + dy * hi - tile_y))


def uv_boundary_png(materials, width, height, repeat=True):
    """Rasterize stock UV boundary edges, including UVs in repeated tiles."""
    edges = Counter()
    for obj in bpy.data.objects:
        if obj.type != "MESH" or not obj.data.uv_layers:
            continue
        layer = obj.data.uv_layers.active.data
        for face in obj.data.polygons:
            if face.material_index >= len(obj.material_slots) or obj.material_slots[face.material_index].material not in materials:
                continue
            points = [tuple(layer[index].uv) for index in face.loop_indices]
            if any(not math.isfinite(v) for point in points for v in point):
                raise ValueError(f"{obj.name}: UV contains a non-finite value")
            for index, start in enumerate(points):
                end = points[(index + 1) % len(points)]
                if start != end:
                    edges[(obj.name, *sorted((start, end)))] += 1
    if not edges:
        raise ValueError("Paint surfaces have no usable UV boundaries")
    pixels = bytearray([255]) * width * height
    drawn = 0
    interior = 0

    def draw_line(start, end, value):
        nonlocal drawn, interior
        x0 = round(max(0, min(1, start[0])) * (width - 1))
        y0 = round((1 - max(0, min(1, start[1]))) * (height - 1))
        x1 = round(max(0, min(1, end[0])) * (width - 1))
        y1 = round((1 - max(0, min(1, end[1]))) * (height - 1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        error = dx + dy
        while True:
            pixels[y0 * width + x0] = min(pixels[y0 * width + x0], value)
            drawn += 1
            if 1 < x0 < width - 2 and 1 < y0 < height - 2:
                interior += 1
            if x0 == x1 and y0 == y1:
                return
            twice = 2 * error
            if twice >= dy:
                error += dy
                x0 += sx
            if twice <= dx:
                error += dx
                y0 += sy

    def rasterize(start, end, value):
        if not repeat:
            start = tuple(max(0, min(1, v)) for v in start)
            end = tuple(max(0, min(1, v)) for v in end)
        x0, x1 = math.floor(min(start[0], end[0])), math.floor(max(start[0], end[0]))
        y0, y1 = math.floor(min(start[1], end[1])), math.floor(max(start[1], end[1]))
        if (x1 - x0 + 1) * (y1 - y0 + 1) > 256:
            raise ValueError("UV edge spans too many repeat tiles")
        for tx in range(x0, x1 + 1):
            for ty in range(y0, y1 + 1):
                segment = _clip_line(start, end, tx, ty)
                if segment:
                    draw_line(*segment, value)

    for (_, start, end), count in edges.items():
        if count != 2:
            rasterize(start, end, 0)
    if interior < 20:
        # A full-tile cylinder can have its entire island boundary on the
        # image border. Include real internal UV edges so its reference is
        # useful without inventing islands.
        for (_, start, end), count in edges.items():
            if count == 2:
                rasterize(start, end, 160)
    if not drawn:
        raise ValueError("Paint surfaces produced an empty UV reference")

    def chunk(kind, data):
        checksum = zlib.crc32(data, zlib.crc32(kind)) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)

    rows = b"".join(b"\0" + pixels[row * width:(row + 1) * width] for row in range(height))
    header = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


def build(family, model, output=None, source_override=None):
    if not family or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in family):
        raise ValueError("Unsafe aircraft family identity")
    if source_override:
        source = Path(source_override).resolve()
    elif model.get("adapter") == "procedural_skin":
        source = ROOT / "tmp/skin-standard-procedural" / f"{family}.glb"
    else:
        source = local_path(model["source_path"])
    glb = source.read_bytes()
    digest = hashlib.sha256(glb).hexdigest()
    # A prepared runtime adapter may supply a separate generation fingerprint.
    expected = model.get("source_sha256", model["stock_sha256"])
    if digest != expected:
        raise ValueError(f"{family}: source changed ({digest}); review the compatibility contract")
    names = glb_materials(glb)
    script = EXPORTER.read_text(encoding="utf-8")
    image_packer = IMAGE_PACKER.read_text(encoding="utf-8")
    lib = {"__name__": "openrc_export_library"}
    exec(compile(script, str(EXPORTER), "exec"), lib)
    pnglib = {"__name__": "openrc_image_library"}
    exec(compile(image_packer, str(IMAGE_PACKER), "exec"), pnglib)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with tempfile.TemporaryDirectory(prefix="openrc-blender-import-") as scratch:
        translated, hidden = blender_glb(glb, scratch)
        bpy.ops.import_scene.gltf(filepath=str(translated or source))
    for name in hidden:
        node = bpy.data.objects.get(name)
        if node is None:
            raise ValueError(f"Could not restore hidden source node: {name}")
        todo = [node]
        while todo:
            obj = todo.pop()
            obj.hide_set(True)
            obj.hide_render = True
            todo.extend(obj.children)
    for name in names:
        mat = bpy.data.materials.get(name)
        if mat is None:
            raise ValueError(f"GLB material did not import with its original identity: {name}")
        mat["openrc_material_name"] = name
    for obj in bpy.data.objects:
        obj["openrc_object_id"] = obj.name
        if obj.type == "MESH":
            obj["openrc_mesh_id"] = obj.name

    selected, colors, extensions, group_images = [], {}, {}, []
    for group in model["paints"]:
        materials = [bpy.data.materials[name] for name in group["materials"]]
        if not materials or any(name in selected for name in group["materials"]):
            raise ValueError("Empty or repeated paint material group")
        nodes = []
        for mat in materials:
            color = lib["_shader"](mat).inputs["Base Color"]
            node = color.links[0].from_node if color.is_linked else None
            if not node or node.type != "TEX_IMAGE" or not node.image:
                raise ValueError(f"{family}: {mat.name} has no original paint image")
            nodes.append(node)
            extensions[mat.name] = node.extension
            colors[mat.name] = group["base_colors"][mat.name]
        if any(node.image != nodes[0].image for node in nodes):
            raise ValueError(f"{family}: grouped materials do not share an original image")
        if len({node.extension for node in nodes}) != 1 or nodes[0].extension not in {"REPEAT", "EXTEND"}:
            raise ValueError(f"{family}: incompatible texture sampling in paint group")
        image = nodes[0].image
        target = (group["width"], group["height"])
        if tuple(image.size) != target:
            original = tuple(image.size)
            if (original != (group.get("source_width"), group.get("source_height")) or
                    not (original[0] > 4096 or original[1] > 4096) or
                    original[0] * target[1] != original[1] * target[0]):
                raise ValueError(f"{family}: unexpected paint image size {original}")
            image.scale(*target)
            # The imported FILE image may already be packed: refresh those
            # bytes so reopening the starter does not restore its old size.
            image.pack()
        nodes[0].select = True
        materials[0].node_tree.nodes.active = nodes[0]
        selected.extend(group["materials"])
        group_images.append((group, materials, image, nodes[0].extension))
    if len(selected) > 9:
        raise ValueError("More than nine paint material records")
    bpy.ops.file.pack_all()
    for image in bpy.data.images:
        if image.source == "FILE" and image.has_data and image.packed_file is None:
            raise ValueError(f"Image was not packed: {image.name}")
    baseline = {"format": "openrc-skin-starter-baseline-v1", "aircraft_id": family,
                "base_asset_sha256": model["stock_sha256"], "materials": names,
                "export_materials": selected, "image_base_colors": colors,
                "image_extensions": extensions, "meshes": lib["mesh_signatures"]()}
    bpy.data.texts.new(lib["BASELINE_TEXT"]).write(json.dumps(baseline, indent=2) + "\n")
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
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type == "MESH" and any(slot.material == group_images[0][1][0] for slot in obj.material_slots):
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            obj.active_material_index = next(i for i, slot in enumerate(obj.material_slots) if slot.material == group_images[0][1][0])
            break
    output = Path(output).resolve() if output else local_path(model["kit"])
    output.parent.mkdir(parents=True, exist_ok=True)
    kit = {"format": "openrc-skin-kit-v1", "aircraft_id": family,
           "display_name": model["display_name"], "stock_sha256": model["stock_sha256"], "paints": model["paints"]}
    guide = GUIDE.read_bytes()
    needle = b'data-aircraft-id=""'
    if guide.count(needle) != 1:
        raise ValueError("Guide must contain exactly one empty aircraft identity field")
    guide = guide.replace(needle, f'data-aircraft-id="{family}"'.encode("ascii"), 1)
    with tempfile.TemporaryDirectory(prefix="openrc-skin-kit-") as scratch:
        files = {}
        for group, materials, image, extension in group_images:
            paint, _ = lib["_png_bytes"](image, group["image"], scratch)
            reference = uv_boundary_png(materials, group["width"], group["height"], extension == "REPEAT")
            for data in (paint, reference):
                if pnglib["inspect_png"](data) != (group["width"], group["height"]):
                    raise ValueError("Unexpected paint or UV reference dimensions")
            files[group["image"]], files[group["uv"]] = paint, reference
        blend = Path(scratch) / "Aircraft.blend"
        bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
        fd, temporary = tempfile.mkstemp(prefix=".openrc-kit-", suffix=".tmp", dir=str(output.parent))
        os.close(fd)
        try:
            with zipfile.ZipFile(temporary, "w") as archive:
                add_zip_file(archive, "Aircraft.blend", blend.read_bytes())
                add_zip_file(archive, "Export OpenRC Skin.py", script.encode("utf-8"))
                add_zip_file(archive, "pack_image.py", image_packer.encode("utf-8"))
                add_zip_file(archive, "kit.json", (json.dumps(kit, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
                for name, data in files.items():
                    add_zip_file(archive, name, data)
                add_zip_file(archive, "README.txt", quickstart().encode("utf-8"))
                add_zip_file(archive, "guide.html", guide)
            os.replace(temporary, output)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    print(f"OpenRC starter generated: {family}: {output} ({output.stat().st_size} bytes)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate OpenRC aircraft skin kits")
    parser.add_argument("families", nargs="*", help="Family IDs (default: every registry entry)")
    parser.add_argument("--output-dir", help="Write kits to this directory instead of the app")
    parser.add_argument("--prepared-dir", help="Directory containing generated procedural <family>.glb scenes")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    models = json.loads(REGISTRY.read_text(encoding="utf-8"))["models"]
    for family in args.families or list(models):
        model = models[family]
        destination = Path(args.output_dir) / Path(model["kit"]).name if args.output_dir else None
        prepared = Path(args.prepared_dir) / f"{family}.glb" if args.prepared_dir and model.get("adapter") == "procedural_skin" else None
        build(family, model, output=destination, source_override=prepared)
