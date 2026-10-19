#!/usr/bin/env python3
"""Convert LOLIPOP's supplied Acer large_3 LOD1 to a pinned glTF asset.

Run from CPython with Blender 5.2.2 LTS:
  python tools/landscape/vegetation/convert_maple.py --blender "C:/.../blender.exe"
  python tools/landscape/vegetation/convert_maple.py --check

The converter uses the supplied FBX mesh and material maps. It removes the FBX
gallery placement, bakes the axis conversion into vertex data, keeps the stem
ground at the origin, and does not create or decimate geometry.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


ARCHIVE_NAME = "maple-trees-pack-lowpoly-game-ready-lods.zip"
ARCHIVE_BYTES = 150_673_952
ARCHIVE_SHA256 = "338c3373fa656cfa83b4c3c847ad4996f7236b0236204bdabbe068240e10af9a"
BLENDER_VERSION = (5, 2, 2)
SOURCE_RELATIVE = Path("assets/landscape/vegetation/source/lolipop_maple_2026")
DERIVED_RELATIVE = Path("assets/landscape/vegetation/derived/lolipop_maple_2026")
SOURCE_FBX = Path("source/Acer tree pack.fbx")
SOURCE_MESH = "Acer_large_3_LOD1"
OUTPUT_GLTF = "maple_large_3_lod1.gltf"
OUTPUT_BIN = "maple_large_3_lod1.bin"
MANIFEST_NAME = "conversion_manifest.json"
EXPECTED_GEOMETRY = {"vertices": 4729, "polygons": 5541, "triangles": 5541}
EXPECTED_MATERIAL_TRIANGLES = {"Bark_Mat": 2614, "Cluster_Mat": 2927}

SOURCE_INPUTS = {
    "LICENSE_MAPLE.txt": "56e3dda18eef50e5b1a4fd321fcb914d25c03bb0f5b3648590afe8bfe209f574",
    "source/Acer tree pack.fbx": "b8f4ad7fe58178846acda10c59089425a2aa9a708947e8d7873a887bc3d02888",
    "textures/bark_ambientocclusion.png": "fefc86ebc8139ca628c73a9703d73ebe5f287672a1f3244386f3ccd4edbb3547",
    "textures/bark_basecolor.png": "c1d6538651a02b64050595c9fe9acd927040af5fafd56c7a83a587abda817a66",
    "textures/bark_normal.png": "be4347e5d286f15c5fa29b314ed185dd36b5ed7e62fc29f9902649abb765f905",
    "textures/bark_roughness.png": "f47c57ea7e79b7f7d7fe5f092e697d213bbef471f72a415d1653202663414408",
    "textures/Cluster_albedo.png": "05273a9b5c7c0eea559ffe1431737381495628018b2c34074b79fcb71dfeea07",
    "textures/Cluster_AO.png": "7febff6876b88c20656c9512b7dfe58dbf2236f7964ee0899355516f53ef35a4",
    "textures/Cluster_Normal.png": "e5407c5bad3093a8a1564d0be24c6fa99af183a816a87b6b436f1f6b8a97a8d4",
    "textures/Cluster_Opacity.png": "72947dc551bbc6868b37df9bbce82ebdaab230fc7d6bae68d1d331ceb41607f7",
    "textures/Cluster_Roughness.jpg": "d2980612fed98dce3257328daef98ce731c1be5fc5e729125a56f9685304485c",
}

ORIGINAL_ARCHIVE_ENTRIES = [
    "source/Acer tree pack.fbx",
    "textures/bark_ambientocclusion.png",
    "textures/bark_basecolor.png",
    "textures/bark_normal.png",
    "textures/bark_roughness.png",
    "textures/Cluster_albedo.png",
    "textures/Cluster_AO.png",
    "textures/Cluster_Normal.png",
    "textures/Cluster_Opacity.png",
    "textures/Cluster_Roughness.jpg",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def parse_external_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender", type=Path, help="absolute path to Blender 5.2.2 LTS")
    parser.add_argument("--repo-root", type=Path, default=repo_root())
    parser.add_argument("--source-dir", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--check", action="store_true", help="verify pinned inputs and derived output hashes")
    parser.add_argument("--preview", action="store_true", help="render a neutral EEVEE preview into tmp/maple-intake")
    return parser.parse_args()


def input_records(source_dir: Path, verify: bool = True) -> list[dict[str, Any]]:
    records = []
    for relative, expected in sorted(SOURCE_INPUTS.items()):
        path = source_dir / Path(relative)
        if not path.is_file():
            raise SystemExit(f"Required pinned source input missing: {path}")
        actual = sha256_file(path)
        if verify and actual != expected:
            raise SystemExit(f"Pinned input SHA-256 mismatch for {relative}: {actual}")
        records.append({"path": relative, "bytes": path.stat().st_size, "sha256": actual})
    return records


def check_conversion(source_dir: Path, output_dir: Path) -> None:
    inputs = input_records(source_dir)
    manifest_path = output_dir / MANIFEST_NAME
    if not manifest_path.is_file():
        raise SystemExit(f"Conversion manifest missing: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("format") != "openrc-maple-conversion-manifest v1":
        raise SystemExit("Unknown maple conversion manifest format")
    if manifest.get("source", {}).get("archive", {}).get("sha256") != ARCHIVE_SHA256:
        raise SystemExit("Source archive hash in conversion manifest changed")
    if manifest.get("inputs") != inputs:
        raise SystemExit("Pinned source file list or hashes differ from the conversion manifest")
    for output in manifest.get("outputs", []):
        path = output_dir / Path(output["path"])
        if not path.is_file():
            raise SystemExit(f"Derived output missing: {path}")
        if path.stat().st_size != output["bytes"] or sha256_file(path) != output["sha256"]:
            raise SystemExit(f"Derived output hash mismatch: {output['path']}")
    gltf_path = output_dir / OUTPUT_GLTF
    document = json.loads(gltf_path.read_text(encoding="utf-8"))
    validate_gltf_document(document)
    print(json.dumps({"check": "ok", "manifest": str(manifest_path), "outputs": len(manifest.get("outputs", []))}, indent=2))


def run_outside_blender() -> None:
    args = parse_external_args()
    root = args.repo_root.resolve()
    source_dir = args.source_dir.resolve() if args.source_dir else (root / SOURCE_RELATIVE).resolve()
    output_dir = args.output_dir.resolve() if args.output_dir else (root / DERIVED_RELATIVE).resolve()
    input_records(source_dir)
    if args.check:
        check_conversion(source_dir, output_dir)
        return
    prepare_textures(source_dir, output_dir)
    if args.blender is None:
        raise SystemExit("--blender is required for conversion; use --check to verify an existing output")
    blender = args.blender.resolve()
    if not blender.is_file():
        raise SystemExit(f"Blender executable not found: {blender}")
    command = [
        str(blender), "--background", "--disable-autoexec", "--python", str(Path(__file__).resolve()), "--",
        "--blender-child", "--source-dir", str(source_dir), "--output-dir", str(output_dir),
        "--archive-sha256", ARCHIVE_SHA256,
    ]
    if args.preview:
        command.append("--preview")
    print(json.dumps({"command": command, "source_dir": str(source_dir), "output_dir": str(output_dir)}, indent=2))
    subprocess.run(command, check=True)


def prepare_textures(source_dir: Path, output_dir: Path) -> None:
    """Derive export maps outside Blender to avoid color-managed pixel changes."""
    try:
        from PIL import Image
        import numpy as np
    except ImportError as exc:
        raise SystemExit("Texture preparation requires Pillow in the Python running this converter") from exc
    output = output_dir / "textures"
    output.mkdir(parents=True, exist_ok=True)

    def save_jpeg(source_name: str, output_name: str, quality: int) -> None:
        Image.open(source_dir / "textures" / source_name).convert("RGB").save(
            output / output_name, format="JPEG", quality=quality, subsampling=0, optimize=False, progressive=False
        )

    def save_16bit_gray_png(source_name: str, output_name: str) -> None:
        source = np.asarray(Image.open(source_dir / "textures" / source_name), dtype=np.uint32)
        if source.ndim != 2 or int(source.max()) > 65535:
            raise SystemExit(f"Expected a single-channel unsigned 16-bit map: {source_name}")
        # glTF's common runtime texture path is 8-bit UNORM. Round the full
        # source range rather than clipping 16-bit values to white.
        quantized = ((source + 128) // 257).astype(np.uint8)
        Image.fromarray(quantized, mode="L").save(output / output_name, format="PNG", optimize=False, compress_level=9)

    # Keep tangent-space data byte-for-byte: lossy normal maps cause visible shading noise.
    shutil.copyfile(source_dir / "textures" / "bark_normal.png", output / "maple_bark_normal.png")
    shutil.copyfile(source_dir / "textures" / "Cluster_Normal.png", output / "maple_leaves_normal.png")
    save_jpeg("bark_basecolor.png", "maple_bark_basecolor.jpg", 93)
    save_16bit_gray_png("bark_roughness.png", "maple_bark_roughness.png")
    save_16bit_gray_png("bark_ambientocclusion.png", "maple_bark_ao.png")
    shutil.copyfile(source_dir / "textures" / "Cluster_Roughness.jpg", output / "maple_leaves_roughness.jpg")
    shutil.copyfile(source_dir / "textures" / "Cluster_AO.png", output / "maple_leaves_ao.png")
    save_jpeg("Cluster_AO.png", "maple_leaves_ao.jpg", 98)
    base = Image.open(source_dir / "textures" / "Cluster_albedo.png").convert("RGBA")
    opacity = Image.open(source_dir / "textures" / "Cluster_Opacity.png").convert("RGB").getchannel("R")
    if base.size != opacity.size:
        raise SystemExit("Leaf albedo and opacity dimensions differ")
    base.putalpha(opacity)
    base.save(output / "maple_leaves_basecolor.png", format="PNG", optimize=False, compress_level=9)


def parse_blender_args() -> argparse.Namespace:
    if "--" not in sys.argv:
        raise SystemExit("Expected Blender child arguments after --")
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender-child", action="store_true")
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--archive-sha256", required=True)
    parser.add_argument("--preview", action="store_true")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])


def validate_gltf_document(document: dict[str, Any]) -> None:
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    if len(nodes) != 1 or len(meshes) != 1:
        raise SystemExit(f"Expected one glTF node and mesh; got {len(nodes)} nodes and {len(meshes)} meshes")
    if any(key in nodes[0] for key in ("matrix", "translation", "rotation", "scale")):
        raise SystemExit("Output glTF mesh node must not carry transforms")
    if len(document.get("materials", [])) != 2:
        raise SystemExit(f"Expected two glTF materials; got {len(document.get('materials', []))}")
    primitives = meshes[0].get("primitives", [])
    if len(primitives) != 2:
        raise SystemExit(f"Expected two glTF material primitives; got {len(primitives)}")
    if any("COLOR_0" in primitive.get("attributes", {}) for primitive in primitives):
        raise SystemExit("Output must not expose AO/bark-blend channels as glTF vertex RGB")
    expected_modes = {"Maple_Bark_PBR": "OPAQUE", "Maple_Leaves_PBR": "MASK"}
    for material in document["materials"]:
        expected = expected_modes.get(material.get("name"))
        if expected is None or material.get("alphaMode", "OPAQUE") != expected:
            raise SystemExit(f"Unexpected alpha mode for material {material.get('name')}: {material.get('alphaMode')}")
    leaves = next((item for item in document["materials"] if item.get("name") == "Maple_Leaves_PBR"), None)
    if not leaves or leaves.get("doubleSided") is not True or abs(float(leaves.get("alphaCutoff", 0.0)) - 0.5) > 1e-6:
        raise SystemExit("Leaves must export as double-sided MASK with alphaCutoff 0.5")


def run_inside_blender() -> None:
    import bpy  # type: ignore[import-not-found]
    from mathutils import Matrix, Vector

    args = parse_blender_args()
    source_dir = args.source_dir.resolve()
    output_dir = args.output_dir.resolve()
    inputs = input_records(source_dir)
    if args.archive_sha256 != ARCHIVE_SHA256:
        raise SystemExit("Source archive hash changed between wrapper verification and Blender conversion")
    if tuple(bpy.app.version) != BLENDER_VERSION:
        raise SystemExit(f"Pinned Blender version is 5.2.2; found {bpy.app.version_string}")

    fbx_path = source_dir / SOURCE_FBX
    output_dir.mkdir(parents=True, exist_ok=True)
    texture_dir = output_dir / "textures"
    texture_dir.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.fbx(filepath=str(fbx_path), use_custom_normals=True, use_image_search=False)
    obj = bpy.data.objects.get(SOURCE_MESH)
    if obj is None or obj.type != "MESH":
        raise SystemExit(f"Source mesh {SOURCE_MESH} missing from FBX")
    mesh = obj.data
    mesh.update()
    mesh.calc_loop_triangles()
    if (len(mesh.vertices), len(mesh.polygons), len(mesh.loop_triangles)) != (
        EXPECTED_GEOMETRY["vertices"], EXPECTED_GEOMETRY["polygons"], EXPECTED_GEOMETRY["triangles"]
    ):
        raise SystemExit("Source mesh geometry counts differ from the pinned 5541-triangle variant")
    if len(mesh.uv_layers) == 0:
        raise SystemExit("Source mesh has no UV map")

    source_material_counts: dict[str, int] = {}
    source_polygon_material_indices = [polygon.material_index for polygon in mesh.polygons]
    for polygon in mesh.polygons:
        index = polygon.material_index
        material = obj.material_slots[index].material if index < len(obj.material_slots) else None
        name = material.name if material else "<none>"
        source_material_counts[name] = source_material_counts.get(name, 0) + len(polygon.vertices) - 2
    if source_material_counts != EXPECTED_MATERIAL_TRIANGLES:
        raise SystemExit(f"Source material triangle counts changed: {source_material_counts}")

    source_positions = [vertex.co.copy() for vertex in mesh.vertices]
    source_local_bounds = {
        "min": [min(float(v[axis]) for v in source_positions) for axis in range(3)],
        "max": [max(float(v[axis]) for v in source_positions) for axis in range(3)],
    }
    source_local_bounds["size"] = [source_local_bounds["max"][i] - source_local_bounds["min"][i] for i in range(3)]
    source_local_bounds["center_offset_from_stem"] = [
        (source_local_bounds["max"][i] + source_local_bounds["min"][i]) * 0.5 for i in range(3)
    ]
    active_uv = mesh.uv_layers.active_render or mesh.uv_layers.active or mesh.uv_layers[0]
    source_uvs = [tuple(float(c) for c in item.uv) for item in active_uv.data]
    source_loop_normals = [loop.normal.copy() for loop in mesh.loops]
    source_color_summary = []
    for attribute in mesh.color_attributes:
        colors = [tuple(float(channel) for channel in item.color) for item in attribute.data]
        if colors:
            source_color_summary.append({
                "name": attribute.name,
                "domain": attribute.domain,
                "type": attribute.data_type,
                "count": len(colors),
                "channel_min_rgba": [min(color[i] for color in colors) for i in range(4)],
                "channel_max_rgba": [max(color[i] for color in colors) for i in range(4)],
            })

    source_matrix = obj.matrix_world.copy()
    gallery_origin = source_matrix @ Vector((0.0, 0.0, 0.0))
    axis_transform = source_matrix.copy()
    axis_transform.translation = Vector((0.0, 0.0, 0.0))
    normal_matrix = axis_transform.to_3x3().inverted().transposed()
    expected_positions = [axis_transform @ vertex for vertex in source_positions]
    expected_normals = [(normal_matrix @ normal).normalized() for normal in source_loop_normals]
    mesh.transform(axis_transform)
    mesh.normals_split_custom_set([tuple(float(v) for v in normal) for normal in expected_normals])
    mesh.update()
    for attribute in list(mesh.color_attributes):
        mesh.color_attributes.remove(attribute)
    obj.matrix_world = Matrix.Identity(4)
    obj.name = "maple_tree"
    mesh.name = "maple_tree_mesh"
    mesh.calc_loop_triangles()

    max_position_error = max((mesh.vertices[i].co - expected_positions[i]).length for i in range(len(expected_positions)))
    max_uv_error = max(
        (active_uv.data[i].uv - Vector(source_uvs[i])).length for i in range(len(source_uvs))
    ) if source_uvs else 0.0
    max_normal_error = max(
        (mesh.loops[i].normal - expected_normals[i]).length for i in range(len(expected_normals))
    ) if expected_normals else 0.0
    if max_position_error > 1e-6 or max_uv_error > 1e-6 or max_normal_error > 0.01:
        raise SystemExit(
            f"Baked geometry check failed: position={max_position_error}, uv={max_uv_error}, normal={max_normal_error}"
        )

    image_settings = bpy.context.scene.render.image_settings
    texture_spec = {
        "maple_bark_basecolor.jpg": "sRGB",
        "maple_bark_normal.png": "Non-Color",
        "maple_bark_roughness.png": "Non-Color",
        "maple_bark_ao.png": "Non-Color",
        "maple_leaves_normal.png": "Non-Color",
        "maple_leaves_roughness.jpg": "Non-Color",
        "maple_leaves_ao.png": "Non-Color",
        "maple_leaves_basecolor.png": "sRGB",
    }
    texture_images = {}
    for output_name, colorspace in texture_spec.items():
        image = bpy.data.images.load(str(texture_dir / output_name), check_existing=False)
        image.colorspace_settings.name = colorspace
        # Blender defers decoding file-backed images until a pixel is queried.
        # Force the decode so the headless EEVEE preview can upload them.
        _first_pixel = image.pixels[0]
        texture_images[output_name] = image

    # Leaf RGB is the supplied albedo and leaf alpha is the supplied opacity map.
    # Both are combined by prepare_textures outside Blender without color transforms.

    gltf_output_group = bpy.data.node_groups.get("glTF Material Output")
    if gltf_output_group is None:
        gltf_output_group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        gltf_output_group.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        gltf_output_group.nodes.new("NodeGroupInput")
        gltf_output_group.nodes.new("NodeGroupOutput")

    def create_pbr_material(name: str, mapping: dict[str, str], alpha_mask: bool, double_sided: bool) -> Any:
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        material.use_backface_culling = not double_sided
        material.blend_method = "CLIP" if alpha_mask else "OPAQUE"
        material.alpha_threshold = 0.5
        if hasattr(material, "surface_render_method"):
            material.surface_render_method = "BLENDED" if alpha_mask else "DITHERED"
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        shader.inputs["Metallic"].default_value = 0.0
        shader.inputs["Roughness"].default_value = 1.0
        links.new(shader.outputs["BSDF"], output.inputs["Surface"])

        def texture_node(image_name: str, label: str, location: tuple[float, float]) -> Any:
            tex = nodes.new("ShaderNodeTexImage")
            tex.label = label
            tex.image = texture_images[image_name]
            tex.interpolation = "Linear"
            tex.extension = "REPEAT"
            tex.location = location
            return tex

        def red_channel(tex: Any, label: str, location: tuple[float, float]) -> Any:
            split = nodes.new("ShaderNodeSeparateColor")
            split.mode = "RGB"
            split.label = label
            split.location = location
            links.new(tex.outputs["Color"], split.inputs["Color"])
            return split.outputs["Red"]

        base = texture_node(mapping["base_color"], "Base color", (-900, 300))
        links.new(base.outputs["Color"], shader.inputs["Base Color"])
        if alpha_mask:
            links.new(base.outputs["Alpha"], shader.inputs["Alpha"])
        normal = texture_node(mapping["normal"], "Tangent-space normal", (-900, 0))
        normal_map = nodes.new("ShaderNodeNormalMap")
        normal_map.space = "TANGENT"
        normal_map.location = (-500, 0)
        links.new(normal.outputs["Color"], normal_map.inputs["Color"])
        links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
        roughness = texture_node(mapping["roughness"], "Roughness", (-900, -280))
        links.new(red_channel(roughness, "Roughness channel", (-620, -280)), shader.inputs["Roughness"])
        ao = texture_node(mapping["occlusion"], "Ambient occlusion", (-900, -540))
        output_group = nodes.new("ShaderNodeGroup")
        output_group.node_tree = gltf_output_group
        output_group.label = "glTF occlusion"
        output_group.location = (-300, -500)
        links.new(red_channel(ao, "AO channel", (-620, -500)), output_group.inputs["Occlusion"])
        return material

    bark_material = create_pbr_material(
        "Maple_Bark_PBR",
        {"base_color": "maple_bark_basecolor.jpg", "normal": "maple_bark_normal.png", "roughness": "maple_bark_roughness.png", "occlusion": "maple_bark_ao.png"},
        alpha_mask=False,
        double_sided=False,
    )
    leaves_material = create_pbr_material(
        "Maple_Leaves_PBR",
        {"base_color": "maple_leaves_basecolor.png", "normal": "maple_leaves_normal.png", "roughness": "maple_leaves_roughness.jpg", "occlusion": "maple_leaves_ao.png"},
        alpha_mask=True,
        double_sided=True,
    )
    mesh.materials.clear()
    mesh.materials.append(bark_material)
    mesh.materials.append(leaves_material)
    for polygon, source_index in zip(mesh.polygons, source_polygon_material_indices, strict=True):
        polygon.material_index = source_index
    exported_material_counts = {"Maple_Bark_PBR": 0, "Maple_Leaves_PBR": 0}
    for polygon in mesh.polygons:
        material_name = mesh.materials[polygon.material_index].name
        exported_material_counts[material_name] += len(polygon.vertices) - 2
    if exported_material_counts != {"Maple_Bark_PBR": 2614, "Maple_Leaves_PBR": 2927}:
        raise SystemExit(f"Material triangle assignments changed during PBR rewrite: {exported_material_counts}")
    obj.select_set(False)

    if args.preview:
        render_preview(bpy, obj, output_dir)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    gltf_path = output_dir / OUTPUT_GLTF
    bpy.ops.export_scene.gltf(
        filepath=str(gltf_path),
        export_format="GLTF_SEPARATE",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_texture_dir="textures",
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_vertex_color="NONE",
        export_cameras=False,
        export_lights=False,
    )
    if not (output_dir / OUTPUT_BIN).is_file():
        raise SystemExit("glTF exporter did not create the external binary buffer")
    document = json.loads(gltf_path.read_text(encoding="utf-8"))
    postprocess_materials(document)
    validate_gltf_document(document)
    gltf_path.write_text(json.dumps(document, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    referenced_images = {Path(str(item.get("uri", ""))).name for item in document.get("images", [])}
    for image_path in texture_dir.iterdir():
        if image_path.is_file() and image_path.name not in referenced_images:
            image_path.unlink()

    source_bounds_y_up = {
        "min": [source_local_bounds["min"][0], source_local_bounds["min"][1], source_local_bounds["min"][2]],
        "max": [source_local_bounds["max"][0], source_local_bounds["max"][1], source_local_bounds["max"][2]],
        "size": source_local_bounds["size"],
        "center_offset_from_stem": source_local_bounds["center_offset_from_stem"],
    }
    output_bounds_y_up = output_position_bounds(document)
    manifest = {
        "format": "openrc-maple-conversion-manifest v1",
        "asset_id": "maple_tree",
        "source": {
            "name": "Maple trees pack (lowpoly, game ready, LODs)",
            "creator": "LOLIPOP (@lolipop_1707)",
            "url": "https://sketchfab.com/3d-models/maple-trees-pack-lowpoly-game-ready-lods-b5d2833c258f4054a01ee2b4ef85adf0",
            "license": "CC BY 4.0",
            "archive": {"name": ARCHIVE_NAME, "bytes": ARCHIVE_BYTES, "sha256": ARCHIVE_SHA256},
            "original_entries": ORIGINAL_ARCHIVE_ENTRIES,
            "mesh": {
                "object": SOURCE_MESH,
                "triangles": EXPECTED_GEOMETRY["triangles"],
                "polygons": EXPECTED_GEOMETRY["polygons"],
                "vertices": EXPECTED_GEOMETRY["vertices"],
                "material_triangles": EXPECTED_MATERIAL_TRIANGLES,
                "bounds_y_up_m": source_bounds_y_up,
                "gallery_origin_world": [float(v) for v in gallery_origin],
            },
        },
        "inputs": inputs,
        "toolchain": {
            "converter": "tools/landscape/vegetation/convert_maple.py",
            "converter_sha256": sha256_file(Path(__file__).resolve()),
            "blender": bpy.app.version_string,
            "gltf_exporter": str(document.get("asset", {}).get("generator", "")),
        },
        "conversion": {
            "geometry_created": False,
            "decimation": False,
            "method": "selected supplied Acer_large_3_LOD1; removed FBX gallery placement; baked the FBX axis rotation into the supplied vertices and custom loop normals; preserved UVs and topology; exported one identity-root glTF node with two material primitives",
            "source_to_baked_max_error": {
                "position_m": float(max_position_error),
                "normal_unit_vector": float(max_normal_error),
                "uv_unitless": float(max_uv_error),
            },
            "triangles_preserved": len(mesh.loop_triangles) == EXPECTED_GEOMETRY["triangles"],
            "polygons_preserved": len(mesh.polygons) == EXPECTED_GEOMETRY["polygons"],
            "source_vertex_color_attributes": source_color_summary,
            "vertex_color_policy": "The source page defines R as baked AO and B as bark blending. The FBX color layer imports with R=0.051..0.965 and G/B/A=1.0; it is removed so AO and bark-blend data are never used as base-color RGB. Separate authored AO maps are retained; source Bark_Mat and Cluster_Mat material regions remain separate.",
            "texture_policy": "Pillow combines source Cluster albedo RGB and opacity R into PNG RGBA without color transforms. Source 16-bit bark AO and roughness are rounded to 8-bit UNORM for glTF, not clipped; source tangent normal maps and leaf roughness/AO images are copied byte-for-byte. Bark base color is JPEG quality 93. Blender packs AO in ORM red and roughness in ORM green; blue is unused/white.",
            "origin": "stem_ground at (0, 0, 0) metres; source object origin retained, canopy bounds not recentered",
            "gallery_translation_removed": [float(v) for v in gallery_origin],
            "axis_conversion": "FBX Y-up to Blender Z-up baked into vertices; glTF Y-up export; no root-node transforms",
            "source_bounds_y_up_m": source_bounds_y_up,
            "gltf_bounds_y_up_m": output_bounds_y_up,
            "source_height_m": float(source_bounds_y_up["size"][1]),
            "runtime_target_height_m": 14.0,
            "runtime_uniform_scale_to_14m": 14.0 / float(source_bounds_y_up["size"][1]),
            "runtime_dimensions_at_14m": [
                14.0 * float(source_bounds_y_up["size"][0]) / float(source_bounds_y_up["size"][1]),
                14.0,
                14.0 * float(source_bounds_y_up["size"][2]) / float(source_bounds_y_up["size"][1]),
            ],
        },
        "materials": [
            {
                "name": "Maple_Bark_PBR",
                "source_material": "Bark_Mat",
                "triangles": EXPECTED_MATERIAL_TRIANGLES["Bark_Mat"],
                "base_color": "textures/maple_bark_basecolor.jpg",
                "normal": "textures/maple_bark_normal.png",
                "roughness": "textures/maple_bark_ao-maple_bark_roughness.png (G)",
                "occlusion": "textures/maple_bark_ao-maple_bark_roughness.png (R)",
                "metallic_factor": 0.0,
                "alpha_mode": "OPAQUE",
                "double_sided": False,
            },
            {
                "name": "Maple_Leaves_PBR",
                "source_material": "Cluster_Mat",
                "triangles": EXPECTED_MATERIAL_TRIANGLES["Cluster_Mat"],
                "base_color": "textures/maple_leaves_basecolor.png",
                "normal": "textures/maple_leaves_normal.png",
                "roughness": "textures/maple_leaves_ao-maple_leaves_roughness.png (G)",
                "occlusion": "textures/maple_leaves_ao-maple_leaves_roughness.png (R)",
                "alpha_source": "Cluster_Opacity.png composited into baseColorTexture alpha",
                "metallic_factor": 0.0,
                "alpha_mode": "MASK",
                "alpha_cutoff": 0.5,
                "double_sided": True,
            },
        ],
        "outputs": [],
    }
    for path in sorted(output_dir.rglob("*")):
        if path.is_file() and path.name != MANIFEST_NAME:
            manifest["outputs"].append({
                "path": path.relative_to(output_dir).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            })
    manifest_path = output_dir / MANIFEST_NAME
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"manifest": str(manifest_path), "outputs": manifest["outputs"], "bounds_y_up_m": output_bounds_y_up}, indent=2))


def output_position_bounds(document: dict[str, Any]) -> dict[str, list[float]]:
    accessors = document.get("accessors", [])
    min_bound = [float("inf")] * 3
    max_bound = [float("-inf")] * 3
    for primitive in document["meshes"][0]["primitives"]:
        accessor_index = primitive.get("attributes", {}).get("POSITION")
        if accessor_index is None:
            raise SystemExit("glTF primitive has no POSITION attribute")
        accessor = accessors[accessor_index]
        if "min" not in accessor or "max" not in accessor:
            raise SystemExit("glTF POSITION accessor is missing bounds")
        for axis in range(3):
            min_bound[axis] = min(min_bound[axis], float(accessor["min"][axis]))
            max_bound[axis] = max(max_bound[axis], float(accessor["max"][axis]))
    return {"min": min_bound, "max": max_bound, "size": [max_bound[i] - min_bound[i] for i in range(3)]}


def postprocess_materials(document: dict[str, Any]) -> None:
    images = document.get("images", [])
    textures = document.get("textures", [])
    texture_by_image_name: dict[str, int] = {}
    for texture_index, texture in enumerate(textures):
        source_index = texture.get("source")
        if source_index is None or source_index >= len(images):
            continue
        uri = str(images[source_index].get("uri", "")).replace("\\", "/")
        texture_by_image_name[Path(uri).name] = texture_index

    def texture_ref(name: str) -> dict[str, int]:
        if name not in texture_by_image_name:
            raise SystemExit(f"glTF exporter omitted expected texture {name}; found {sorted(texture_by_image_name)}")
        return {"index": texture_by_image_name[name]}

    mappings = {
        "Maple_Bark_PBR": {
            "base": "maple_bark_basecolor.jpg", "normal": "maple_bark_normal.png",
            "roughness": "maple_bark_roughness.png", "ao": "maple_bark_ao.png", "orm": "maple_bark_ao-maple_bark_roughness.png", "alpha": "OPAQUE", "double": False,
        },
        "Maple_Leaves_PBR": {
            "base": "maple_leaves_basecolor.png", "normal": "maple_leaves_normal.png",
            "roughness": "maple_leaves_roughness.jpg", "ao": "maple_leaves_ao.png", "orm": "maple_leaves_ao-maple_leaves_roughness.png", "alpha": "MASK", "double": True,
        },
    }
    if len(document.get("materials", [])) != 2:
        raise SystemExit("Expected exactly two source PBR materials in glTF output")
    for material in document["materials"]:
        mapping = mappings.get(material.get("name"))
        if mapping is None:
            raise SystemExit(f"Unexpected material name in glTF output: {material.get('name')}")
        pbr = material.setdefault("pbrMetallicRoughness", {})
        pbr["baseColorTexture"] = texture_ref(mapping["base"])
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 1.0
        pbr["metallicRoughnessTexture"] = texture_ref(mapping["orm"])
        material["normalTexture"] = texture_ref(mapping["normal"])
        material["occlusionTexture"] = {**texture_ref(mapping["orm"]), "strength": 1.0}
        material["doubleSided"] = bool(mapping["double"])
        material["alphaMode"] = mapping["alpha"]
        if mapping["alpha"] == "MASK":
            material["alphaCutoff"] = 0.5
        else:
            material.pop("alphaCutoff", None)


def render_preview(bpy: Any, obj: Any, output_dir: Path) -> None:
    from mathutils import Vector

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 1100
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Preview World")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.22, 0.24, 0.23, 1.0)
    background.inputs["Strength"].default_value = 0.7

    ground_mesh = bpy.data.meshes.new("Preview Ground Mesh")
    ground_mesh.from_pydata([(-100, -100, 0), (100, -100, 0), (100, 100, 0), (-100, 100, 0)], [], [(0, 1, 2, 3)])
    ground = bpy.data.objects.new("Preview Ground", ground_mesh)
    scene.collection.objects.link(ground)
    ground_material = bpy.data.materials.new("Preview Ground Neutral")
    ground_material.diffuse_color = (0.28, 0.30, 0.27, 1.0)
    ground_material.use_nodes = True
    ground_material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.28, 0.30, 0.27, 1.0)
    ground_material.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(ground_material)

    light_data = bpy.data.lights.new("Preview Sun", type="SUN")
    light_data.energy = 2.0
    light = bpy.data.objects.new("Preview Sun", light_data)
    scene.collection.objects.link(light)
    light.location = (15, -25, 28)
    light.rotation_euler = Vector((-0.4, 0.5, -1.0)).to_track_quat("-Z", "Y").to_euler()

    camera_data = bpy.data.cameras.new("Preview Camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 27.0
    camera = bpy.data.objects.new("Preview Camera", camera_data)
    scene.collection.objects.link(camera)
    target = Vector((0.0, 0.0, 9.0))
    camera.location = (22.0, -32.0, 19.0)
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.filepath = str(repo_root() / "tmp" / "maple-intake" / "maple_tree_preview.png")
    Path(scene.render.filepath).parent.mkdir(parents=True, exist_ok=True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    try:
        import bpy  # type: ignore[import-not-found]
    except ImportError:
        run_outside_blender()
    else:
        if "--blender-child" in sys.argv:
            run_inside_blender()
        else:
            run_inside_blender()
