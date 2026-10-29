"""OpenRC paint exporter. This file is also embedded in the starter .blend.

Run it in Blender's Text Editor, or use --output and --label after Blender's --.
The baseline text in the starter file protects its geometry and material slots.
"""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import tempfile
import zipfile

import bpy


BASELINE_TEXT = "OpenRC Baseline.json"
MAX_PNG_BYTES = 16 * 1024 * 1024
MAX_ARCHIVE_BYTES = 32 * 1024 * 1024
MAX_TOTAL_PIXELS = 16_777_216
MAX_SIDE = 4096


def _bytes(hasher, value):
    data = value.encode("utf-8")
    hasher.update(struct.pack("<I", len(data)))
    hasher.update(data)


def mesh_signature(obj):
    """Fingerprint the parts of a mesh the skin cannot change at runtime."""
    obj.update_from_editmode()
    mesh = obj.data
    h = hashlib.sha256()
    _bytes(h, str(obj.get("openrc_mesh_id", "")))
    parent_id = str(obj.parent.get("openrc_object_id", "")) if obj.parent else ""
    _bytes(h, parent_id)
    for row in obj.matrix_world:
        h.update(struct.pack("<4f", *row))
    h.update(struct.pack("<III", len(mesh.vertices), len(mesh.polygons), len(mesh.loops)))
    for vertex in mesh.vertices:
        h.update(struct.pack("<3f", *vertex.co))
    h.update(struct.pack("<I", len(obj.material_slots)))
    for slot in obj.material_slots:
        _bytes(h, str(slot.material.get("openrc_material_name", "")) if slot.material else "")
    for face in mesh.polygons:
        h.update(struct.pack("<II", face.material_index, len(face.vertices)))
        for index in face.vertices:
            h.update(struct.pack("<I", index))
    h.update(struct.pack("<I", len(mesh.uv_layers)))
    h.update(struct.pack("<i", mesh.uv_layers.active_index))
    for layer in mesh.uv_layers:
        _bytes(h, layer.name)
        h.update(struct.pack("<?", layer.active_render))
        for uv in layer.data:
            h.update(struct.pack("<2f", *uv.uv))
    return h.hexdigest()


def mesh_signatures():
    result = {}
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.update_from_editmode()
    bpy.context.view_layer.update()
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        identity = str(obj.get("openrc_mesh_id", ""))
        if not identity or identity in result:
            raise ValueError("The model contains an added or duplicate mesh. Use the original starter model.")
        result[identity] = mesh_signature(obj)
    return result


def _baseline():
    text = bpy.data.texts.get(BASELINE_TEXT)
    if text is None:
        raise ValueError("Starter baseline is missing. Open a fresh OpenRC starter .blend.")
    baseline = json.loads(text.as_string())
    if baseline.get("format") != "openrc-skin-starter-baseline-v1":
        raise ValueError("Starter baseline is invalid. Open a fresh OpenRC starter .blend.")
    if mesh_signatures() != baseline["meshes"]:
        raise ValueError("The model, its placement, UVs or material slots changed. Restore them or use a fresh starter.")
    return baseline


def _materials(baseline):
    found = {}
    users = {}
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for slot in obj.material_slots:
            mat = slot.material
            if mat is None:
                raise ValueError("A material slot is empty. Restore the original model.")
            identity = str(mat.get("openrc_material_name", ""))
            if identity not in baseline["materials"]:
                raise ValueError("An original material was replaced. Restore the starter's material slots.")
            if identity in found and found[identity] != mat:
                raise ValueError("A material was duplicated. Keep one material per original slot name.")
            found[identity] = mat
            users.setdefault(identity, []).append(obj)
    if set(found) != set(baseline["materials"]):
        raise ValueError("An original material is missing. Restore the starter's material slots.")
    return found, users


def _shader(mat):
    if not mat.use_nodes or mat.node_tree is None:
        raise ValueError(f"{mat.name}: use a Principled BSDF material.")
    nodes = mat.node_tree.nodes
    outputs = [n for n in nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output]
    if len(outputs) != 1:
        raise ValueError(f"{mat.name}: one active Material Output is required.")
    surface = outputs[0].inputs.get("Surface")
    if surface is None or not surface.is_linked or surface.links[0].from_node.type != "BSDF_PRINCIPLED":
        raise ValueError(f"{mat.name}: connect one Principled BSDF directly to Material Output.")
    return surface.links[0].from_node


def _material_entry(identity, mat, users, image_number, expected_extension="REPEAT"):
    shader = _shader(mat)
    color_input = shader.inputs["Base Color"]
    alpha_input = shader.inputs["Alpha"]
    if alpha_input.is_linked:
        raise ValueError(f"{identity}: linked Alpha is unsupported; use the PNG or a single Alpha value.")
    alpha = float(alpha_input.default_value)
    image = None
    if color_input.is_linked:
        link = color_input.links[0]
        node = link.from_node
        if node.type != "TEX_IMAGE" or link.from_socket != node.outputs.get("Color") or node.image is None:
            raise ValueError(f"{identity}: bake procedural or mixed Base Color to one Image Texture connected directly to Principled Base Color.")
        mapping = node.texture_mapping
        if (node.inputs["Vector"].is_linked or node.extension != expected_extension or
                node.interpolation != "Linear" or node.projection != "FLAT" or
                tuple(mapping.translation) != (0.0, 0.0, 0.0) or
                tuple(mapping.rotation) != (0.0, 0.0, 0.0) or
                tuple(mapping.scale) != (1.0, 1.0, 1.0) or
                mapping.use_min or mapping.use_max or
                (mapping.mapping_x, mapping.mapping_y, mapping.mapping_z) != ("X", "Y", "Z") or
                mapping.mapping != "FLAT" or mapping.vector_type != "POINT"):
            raise ValueError(f"{identity}: use the original UV mapping and image sampling settings; bake other mappings to the original UVs.")
        image = node.image
        # Packed images are loaded lazily after reopening the .blend.
        _ = image.size[:]
        if image.source not in {"FILE", "GENERATED"} or not image.has_data:
            raise ValueError(f"{identity}: load a single image or pack the missing image first.")
        if image.colorspace_settings.name != "sRGB":
            raise ValueError(f"{identity}: the Base Color image must use the sRGB color space.")
        if any(not obj.data.uv_layers for obj in users):
            raise ValueError(f"{identity}: a mesh using this material has no UV map; use a solid Base Color.")
        color = [1.0, 1.0, 1.0, alpha]
    else:
        color = [float(v) for v in color_input.default_value[:3]] + [alpha]
    if any(not math.isfinite(v) or v < 0.0 or v > 1.0 for v in color):
        raise ValueError(f"{identity}: Base Color and Alpha must be between 0 and 1.")
    entry = {"name": identity, "base_color": color}
    if image is not None:
        entry["texture"] = f"texture-{image_number:02d}.png"
    return entry, image


def _png_bytes(image, identity, directory):
    width, height = image.size
    if width <= 0 or height <= 0 or width > MAX_SIDE or height > MAX_SIDE:
        raise ValueError(f"{identity}: image dimensions must be from 1 to {MAX_SIDE} pixels per side.")
    path = os.path.join(directory, "image.png")
    previous_format = image.file_format
    try:
        image.file_format = "PNG"
        # save_copy reads the current pixels, including unsaved Texture Paint strokes,
        # without changing the image's original path or clearing its dirty state.
        image.save(filepath=path, save_copy=True)
        with open(path, "rb") as source:
            data = source.read(MAX_PNG_BYTES + 1)
    finally:
        image.file_format = previous_format
    if len(data) > MAX_PNG_BYTES:
        raise ValueError(f"{identity}: the PNG is larger than 16 MiB; reduce its size.")
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"{identity}: Blender did not save a PNG image.")
    return data, width * height


def export_skin(output, label=None):
    """Write a self-contained skin package; raise a clear error on unsupported edits."""
    output = Path(output).expanduser().resolve()
    if output.suffix.lower() != ".orskin":
        output = output.with_suffix(".orskin")
    label = (label if label is not None else output.stem).strip()
    if not 1 <= len(label) <= 48 or not label.isprintable():
        raise ValueError("The skin name must contain 1–48 printable characters.")
    if not output.parent.is_dir():
        raise ValueError("The destination folder does not exist.")
    baseline = _baseline()
    materials, users = _materials(baseline)
    manifest = {
        "format": "openrc-skin",
        "version": 1,
        "aircraft_id": baseline["aircraft_id"],
        "base_asset_sha256": baseline["base_asset_sha256"],
        "label": label,
        "materials": [],
    }
    textures = {}
    image_names = {}
    total_pixels = 0
    selected = baseline.get("export_materials", baseline["materials"])
    if not isinstance(selected, list) or not 1 <= len(selected) <= 9 or len(set(selected)) != len(selected):
        raise ValueError("The starter paint material list is invalid.")
    if any(identity not in materials for identity in selected):
        raise ValueError("A starter paint material is missing.")
    with tempfile.TemporaryDirectory(prefix="openrc-skin-") as scratch:
        for identity in selected:
            extension = baseline.get("image_extensions", {}).get(identity, "REPEAT")
            entry, image = _material_entry(identity, materials[identity], users[identity], len(textures) + 1, extension)
            if image is not None:
                if identity in baseline.get("image_base_colors", {}):
                    entry["base_color"] = baseline["image_base_colors"][identity]
                if image.as_pointer() in image_names:
                    entry["texture"] = image_names[image.as_pointer()]
                else:
                    data, pixels = _png_bytes(image, identity, scratch)
                    total_pixels += pixels
                    if total_pixels > MAX_TOTAL_PIXELS:
                        raise ValueError("Paint images exceed the combined 16,777,216-pixel limit.")
                    textures[entry["texture"]] = data
                    image_names[image.as_pointer()] = entry["texture"]
            manifest["materials"].append(entry)
        manifest_bytes = json.dumps(manifest, ensure_ascii=True, indent=2).encode("utf-8") + b"\n"
        if len(manifest_bytes) > 64 * 1024:
            raise ValueError("The skin manifest exceeds 64 KiB.")
        if len(manifest_bytes) + sum(len(data) for data in textures.values()) > MAX_ARCHIVE_BYTES:
            raise ValueError("The expanded skin package exceeds 32 MiB; reduce the paint images.")
        # Build next to the destination and atomically replace it only after validation.
        fd, temporary = tempfile.mkstemp(prefix=".openrc-skin-", suffix=".tmp", dir=str(output.parent))
        os.close(fd)
        try:
            with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("manifest.json", manifest_bytes)
                for name, data in textures.items():
                    archive.writestr(name, data)
            if os.path.getsize(temporary) > MAX_ARCHIVE_BYTES:
                raise ValueError("The skin package exceeds 32 MiB; reduce the paint images.")
            os.replace(temporary, output)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    print(f"OpenRC skin exported: {output}")
    return output


def _run():
    import sys
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if args:
        parser = argparse.ArgumentParser(description="Export an OpenRC skin from the starter .blend")
        parser.add_argument("--output", required=True, help="Destination .orskin file")
        parser.add_argument("--label", help="Name shown in OpenRC (default: output filename)")
        parsed = parser.parse_args(args)
        export_skin(parsed.output, parsed.label)
        return
    if bpy.app.background:
        raise ValueError("Headless export requires -- --output <file.orskin> [--label <name>].")

    from bpy.props import StringProperty
    from bpy_extras.io_utils import ExportHelper

    class OPENRC_OT_export_skin(bpy.types.Operator, ExportHelper):
        bl_idname = "openrc.export_skin"
        bl_label = "Export OpenRC Skin"
        bl_description = "Save an OpenRC skin; the filename becomes its display name"
        filename_ext = ".orskin"
        filter_glob: StringProperty(default="*.orskin", options={"HIDDEN"})

        def execute(self, context):
            try:
                path = export_skin(self.filepath)
            except Exception as exc:
                self.report({"ERROR"}, str(exc))
                return {"CANCELLED"}
            self.report({"INFO"}, f"Saved {path.name}. Import it in OpenRC.")
            return {"FINISHED"}

    existing = getattr(bpy.types, "OPENRC_OT_export_skin", None)
    if existing is not None:
        bpy.utils.unregister_class(existing)
    bpy.utils.register_class(OPENRC_OT_export_skin)
    bpy.ops.openrc.export_skin("INVOKE_DEFAULT")


if __name__ == "__main__":
    _run()
