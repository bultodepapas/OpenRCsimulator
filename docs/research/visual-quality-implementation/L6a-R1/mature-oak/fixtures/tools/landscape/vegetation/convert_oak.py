#!/usr/bin/env python3
"""Reproducibly convert the supplied OpenGameArt Quercus LOD0 to glTF.

Run from CPython with Blender 5.2.2 LTS:
  python tools/landscape/vegetation/convert_oak.py --blender "C:/.../blender.exe"

The script reads the archived .blend, reuses its mesh parts, UVs, normals and packed
atlas, bakes supplied object transforms for one draw part, and writes the glTF.
It does not create or edit tree geometry. Original ZIP and BLEND inputs are verified
against pinned SHA-256 values before Blender starts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

EXPECTED_ZIP_SHA256 = "496f250c29eb1f56e391e55989530028e156ae43a3d1eb9f52ab09aa1bccbebf"
EXPECTED_BLEND_SHA256 = "3b32573acd4e8eb5b7e0a96aa363932ec785a854d6e8c71f56f29b10f5abd37c"
BLEND_MEMBER = "quercus_A_packed_v1.blend"
SOURCE_RELATIVE = Path("assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026")
OUTPUT_RELATIVE = Path("gltf/lod0")
EXPECTED_TRIANGLES = 5303
EXPECTED_POLYGONS = 2791
EXPECTED_VERTICES = 4407
EXPECTED_MATERIAL = "M_Quercus"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def parse_external_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender", required=True, help="absolute path to Blender 5.2.2 LTS executable")
    parser.add_argument("--repo-root", type=Path, default=repo_root())
    parser.add_argument("--source-dir", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    return parser.parse_args()


def verify_inputs(source_dir: Path) -> tuple[Path, Path, str, str]:
    archive_path = source_dir / "quercus_A_packed_v1_0.zip"
    blend_path = source_dir / BLEND_MEMBER
    if not archive_path.is_file() or not blend_path.is_file():
        raise SystemExit(f"Required source input missing: {archive_path} or {blend_path}")
    archive_hash = sha256_file(archive_path)
    blend_hash = sha256_file(blend_path)
    if archive_hash != EXPECTED_ZIP_SHA256:
        raise SystemExit(f"Source ZIP SHA-256 mismatch: {archive_hash}")
    if blend_hash != EXPECTED_BLEND_SHA256:
        raise SystemExit(f"Source BLEND SHA-256 mismatch: {blend_hash}")
    with zipfile.ZipFile(archive_path, "r") as archive:
        if BLEND_MEMBER not in archive.namelist():
            raise SystemExit(f"Expected source member {BLEND_MEMBER} missing from ZIP")
        member_hash = sha256_bytes(archive.read(BLEND_MEMBER))
    if member_hash != blend_hash:
        raise SystemExit("Extracted BLEND does not match the immutable ZIP member")
    return archive_path, blend_path, archive_hash, blend_hash


def run_outside_blender() -> None:
    args = parse_external_args()
    root = args.repo_root.resolve()
    source_dir = args.source_dir.resolve() if args.source_dir else (root / SOURCE_RELATIVE).resolve()
    output_dir = args.output_dir.resolve() if args.output_dir else (source_dir / OUTPUT_RELATIVE).resolve()
    blender = Path(args.blender).resolve()
    if not blender.is_file():
        raise SystemExit(f"Blender executable not found: {blender}")
    archive_path, blend_path, archive_hash, blend_hash = verify_inputs(source_dir)
    command = [
        str(blender), "--background", str(blend_path), "--python", str(Path(__file__).resolve()), "--",
        "--blender-child", "--source-dir", str(source_dir), "--output-dir", str(output_dir),
        "--archive-sha256", archive_hash, "--blend-sha256", blend_hash,
    ]
    print(json.dumps({"command": command, "source_archive": str(archive_path), "output_dir": str(output_dir)}, indent=2))
    subprocess.run(command, check=True)


def parse_blender_args() -> argparse.Namespace:
    if "--" not in sys.argv:
        raise SystemExit("Expected Blender arguments after --")
    parser = argparse.ArgumentParser()
    parser.add_argument("--blender-child", action="store_true")
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--archive-sha256", required=True)
    parser.add_argument("--blend-sha256", required=True)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])


def run_inside_blender() -> None:
    import bpy  # type: ignore[import-not-found]
    from mathutils import Vector

    args = parse_blender_args()
    source_dir = args.source_dir.resolve()
    output_dir = args.output_dir.resolve()
    archive_path, blend_path, archive_hash, blend_hash = verify_inputs(source_dir)
    if archive_hash != args.archive_sha256 or blend_hash != args.blend_sha256:
        raise SystemExit("Source input changed between wrapper verification and Blender conversion")
    if tuple(bpy.app.version) != (5, 2, 2):
        raise SystemExit(f"Pinned Blender version is 5.2.2; found {bpy.app.version_string}")

    output_dir.mkdir(parents=True, exist_ok=True)
    source_textures_dir = source_dir / "textures"
    source_textures_dir.mkdir(parents=True, exist_ok=True)

    # The packed PNG payloads are copied byte-for-byte from the original .blend.
    packed_images = []
    image_names = [
        ("I_Quercus", "Quercus_A_1024.png"),
        ("I_Quercus_LOD1", "Quercus_A_LOD1_LOD2_512.png"),
    ]
    for image_name, filename in image_names:
        image = bpy.data.images.get(image_name)
        if image is None or image.packed_file is None:
            raise SystemExit(f"Expected packed source image {image_name}")
        payload = bytes(image.packed_file.data)
        path = source_textures_dir / filename
        path.write_bytes(payload)
        packed_images.append({"name": image_name, "path": f"textures/{filename}", "bytes": len(payload), "sha256": sha256_bytes(payload)})

    source_material = bpy.data.materials.get(EXPECTED_MATERIAL)
    if source_material is None:
        raise SystemExit(f"Source material {EXPECTED_MATERIAL} missing")
    legacy_specular = float(getattr(source_material, "specular_intensity", 0.0))
    if abs(legacy_specular) > 1e-9:
        raise SystemExit(f"Expected authored legacy specular_intensity 0; found {legacy_specular}")
    source_principled = next((node for node in source_material.node_tree.nodes if node.bl_idname == "ShaderNodeBsdfPrincipled"), None)
    source_principled_specular = None
    if source_principled is not None and "Specular IOR Level" in source_principled.inputs:
        source_principled_specular = float(source_principled.inputs["Specular IOR Level"].default_value)

    # Reviewed legacy material translation. The supplied diffuse/alpha atlas is
    # unchanged. A roughness scalar of 1.0 prevents the highlight artifact seen
    # with an exporter-default 0.5; it is not an authored roughness map. Godot
    # 4.7 ignores KHR_materials_specular, so this output stays core glTF and its
    # native StandardMaterial3D specular scalar remains the engine default 0.5.
    image = bpy.data.images["I_Quercus"]
    atlas_path = source_textures_dir / "Quercus_A_1024.png"
    image.filepath_raw = str(atlas_path)
    source_material.use_nodes = True
    source_material.use_backface_culling = False
    nodes = source_material.node_tree.nodes
    links = source_material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    texture = nodes.new("ShaderNodeTexImage")
    uv_map = nodes.new("ShaderNodeUVMap")
    uv_map.uv_map = "UVTex"
    texture.image = image
    texture.interpolation = "Linear"
    links.new(uv_map.outputs["UV"], texture.inputs["Vector"])
    links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    links.new(texture.outputs["Alpha"], shader.inputs["Alpha"])
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.0
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])

    collection = bpy.data.collections.get("Collection 1")
    if collection is None:
        raise SystemExit("Source collection 'Collection 1' missing")
    source_objects = sorted((obj for obj in collection.objects if obj.type == "MESH"), key=lambda obj: obj.name)
    if len(source_objects) != 36:
        raise SystemExit(f"Expected 36 supplied LOD0 mesh parts, got {len(source_objects)}")

    vertices = []
    faces = []
    corner_uvs = []
    corner_normals = []
    smooth_flags = []
    source_triangles = 0
    source_polygons = 0
    source_vertices = 0
    source_material_names = set()
    bounds_min = [float("inf")] * 3
    bounds_max = [float("-inf")] * 3
    negative_determinants = []

    for obj in source_objects:
        mesh = obj.data
        mesh.update()
        mesh.calc_loop_triangles()
        source_triangles += len(mesh.loop_triangles)
        source_polygons += len(mesh.polygons)
        source_vertices += len(mesh.vertices)
        source_material_names.update(mat.name for mat in mesh.materials if mat)
        transform = obj.matrix_world.copy()
        normal_matrix = transform.to_3x3().inverted().transposed()
        determinant = transform.to_3x3().determinant()
        if determinant < 0.0:
            negative_determinants.append(obj.name)
        offset = len(vertices)
        for vertex in mesh.vertices:
            world = transform @ vertex.co
            values = [float(world[i]) for i in range(3)]
            vertices.append(values)
            for axis in range(3):
                bounds_min[axis] = min(bounds_min[axis], values[axis])
                bounds_max[axis] = max(bounds_max[axis], values[axis])
        uv_layer = mesh.uv_layers.get("UVTex") or mesh.uv_layers.active_render or mesh.uv_layers.active
        if uv_layer is None and len(mesh.uv_layers) > 0:
            uv_layer = mesh.uv_layers[0]
        if uv_layer is None:
            raise SystemExit(f"Missing UV layer on {obj.name}")
        for polygon in mesh.polygons:
            loop_ids = list(polygon.loop_indices)
            vertex_ids = list(polygon.vertices)
            if len(loop_ids) != len(vertex_ids):
                raise SystemExit(f"Loop/vertex mismatch on {obj.name}")
            if determinant < 0.0:
                loop_ids.reverse()
                vertex_ids.reverse()
            faces.append([offset + int(vertex_id) for vertex_id in vertex_ids])
            smooth_flags.append(bool(polygon.use_smooth))
            for loop_id in loop_ids:
                loop = mesh.loops[loop_id]
                world_normal = (normal_matrix @ loop.normal).normalized()
                corner_normals.append(tuple(float(world_normal[i]) for i in range(3)))
                uv = uv_layer.data[loop_id].uv
                corner_uvs.append((float(uv.x), float(uv.y)))

    if source_material_names != {EXPECTED_MATERIAL}:
        raise SystemExit(f"Expected only material {EXPECTED_MATERIAL}; got {sorted(source_material_names)}")
    if negative_determinants:
        raise SystemExit(f"Reflected source mesh parts need review: {negative_determinants}")
    if (source_vertices, source_polygons, source_triangles) != (EXPECTED_VERTICES, EXPECTED_POLYGONS, EXPECTED_TRIANGLES):
        raise SystemExit(f"Source geometry counts changed: {source_vertices} verts, {source_polygons} polygons, {source_triangles} triangles")

    joined_mesh = bpy.data.meshes.new("Quercus_A_LOD0_Mesh")
    joined_mesh.from_pydata(vertices, [], faces)
    joined_mesh.update(calc_edges=True)
    joined_mesh.materials.append(source_material)
    for index, polygon in enumerate(joined_mesh.polygons):
        polygon.material_index = 0
        polygon.use_smooth = smooth_flags[index]
    output_uv = joined_mesh.uv_layers.new(name="UVTex")
    for index, uv in enumerate(corner_uvs):
        output_uv.data[index].uv = uv
    joined_mesh.uv_layers.active = output_uv
    joined_mesh.uv_layers.active_render = output_uv
    joined_mesh.normals_split_custom_set(corner_normals)
    joined_mesh.calc_loop_triangles()

    result_obj = bpy.data.objects.new("Quercus_A_LOD0", joined_mesh)
    bpy.context.scene.collection.objects.link(result_obj)
    result_obj.matrix_world.identity()
    if len(joined_mesh.loop_triangles) != EXPECTED_TRIANGLES or len(joined_mesh.polygons) != EXPECTED_POLYGONS:
        raise SystemExit("Baked output geometry count mismatch")

    max_position_error = 0.0
    max_normal_error = 0.0
    max_uv_error = 0.0
    output_loop_index = 0
    for obj in source_objects:
        mesh = obj.data
        transform = obj.matrix_world
        normal_matrix = transform.to_3x3().inverted().transposed()
        uv_layer = mesh.uv_layers.get("UVTex") or mesh.uv_layers.active_render or mesh.uv_layers.active
        if uv_layer is None and len(mesh.uv_layers) > 0:
            uv_layer = mesh.uv_layers[0]
        for polygon in mesh.polygons:
            for loop_id in polygon.loop_indices:
                source_loop = mesh.loops[loop_id]
                source_position = transform @ mesh.vertices[source_loop.vertex_index].co
                output_loop = joined_mesh.loops[output_loop_index]
                output_position = joined_mesh.vertices[output_loop.vertex_index].co
                source_normal = (normal_matrix @ source_loop.normal).normalized()
                output_normal = output_loop.normal
                source_uv = uv_layer.data[loop_id].uv
                output_uv_value = output_uv.data[output_loop_index].uv
                max_position_error = max(max_position_error, (source_position - output_position).length)
                max_normal_error = max(max_normal_error, (source_normal - output_normal).length)
                max_uv_error = max(max_uv_error, (source_uv - output_uv_value).length)
                output_loop_index += 1

    output_dir.mkdir(parents=True, exist_ok=True)
    gltf_path = output_dir / "oak_lod0.gltf"
    bpy.ops.object.select_all(action="DESELECT")
    result_obj.select_set(True)
    bpy.context.view_layer.objects.active = result_obj
    bpy.ops.export_scene.gltf(
        filepath=str(gltf_path),
        export_format="GLTF_SEPARATE",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_cameras=False,
        export_lights=False,
    )
    # Ensure the external atlas is the exact packed PNG, without re-encoding.
    output_atlas = output_dir / "Quercus_A_1024.png"
    shutil.copyfile(atlas_path, output_atlas)
    if not (output_dir / "oak_lod0.bin").is_file():
        raise SystemExit("glTF exporter did not create oak_lod0.bin")

    document = json.loads(gltf_path.read_text(encoding="utf-8"))
    if len(document.get("nodes", [])) != 1 or len(document.get("meshes", [])) != 1:
        raise SystemExit("Expected a one-node, one-mesh export")
    node = document["nodes"][0]
    if any(key in node for key in ("matrix", "translation", "rotation", "scale")):
        raise SystemExit("Output mesh node must not carry transforms")
    primitives = document["meshes"][0].get("primitives", [])
    if len(primitives) != 1:
        raise SystemExit(f"Expected one glTF primitive, got {len(primitives)}")
    if len(document.get("materials", [])) != 1:
        raise SystemExit("Expected one glTF material")
    material = document["materials"][0]
    # Strip an exporter-added specular extension: Godot 4.7 does not import it.
    material_extensions = material.get("extensions", {})
    material_extensions.pop("KHR_materials_specular", None)
    if material_extensions:
        material["extensions"] = material_extensions
    else:
        material.pop("extensions", None)
    for key in ("extensionsUsed", "extensionsRequired"):
        if key in document:
            document[key] = [extension for extension in document[key] if extension != "KHR_materials_specular"]
            if not document[key]:
                document.pop(key)
    pbr = material.setdefault("pbrMetallicRoughness", {})
    pbr["metallicFactor"] = 0.0
    pbr["roughnessFactor"] = 1.0
    material["alphaMode"] = "BLEND"
    material["doubleSided"] = True
    material.pop("normalTexture", None)
    material.pop("occlusionTexture", None)
    material.pop("emissiveTexture", None)
    image_entries = document.get("images", [])
    if len(image_entries) != 1:
        raise SystemExit(f"Expected one external base-color image, got {len(image_entries)}")
    image_entries[0]["uri"] = "Quercus_A_1024.png"
    document["images"] = image_entries
    # JSON formatting and key insertion order are fixed for stable hashes.
    gltf_path.write_text(json.dumps(document, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")

    # Confirm the exported core material/shape contract before recording pins.
    material = document["materials"][0]
    if material.get("alphaMode") != "BLEND" or material.get("pbrMetallicRoughness", {}).get("roughnessFactor") != 1.0:
        raise SystemExit("Material adaptation failed to retain BLEND or set scalar roughness 1")
    if "KHR_materials_specular" in material.get("extensions", {}):
        raise SystemExit("Unsupported KHR_materials_specular extension was not removed")

    max_size = [bounds_max[i] - bounds_min[i] for i in range(3)]
    proof = {
        "format": "openrc-oak-conversion-proof v2",
        "inputs": {
            "archive": {"path": archive_path.name, "bytes": archive_path.stat().st_size, "sha256": archive_hash},
            "archive_blend_member": {"path": BLEND_MEMBER, "sha256": args.blend_sha256},
            "blend": {"path": blend_path.name, "bytes": blend_path.stat().st_size, "sha256": blend_hash},
            "packed_images": packed_images,
        },
        "toolchain": {
            "converter": "tools/landscape/vegetation/convert_oak.py",
            "converter_sha256": sha256_file(Path(__file__).resolve()),
            "blender": bpy.app.version_string,
            "gltf_exporter": str(document.get("asset", {}).get("generator", "")),
        },
        "conversion": {
            "method": "batched the 36 supplied Collection 1 LOD0 mesh parts into one glTF primitive; baked source object transforms; preserved supplied positions, polygons, UVs, and inverse-transpose loop normals",
            "geometry_created": False,
            "decimation": False,
            "source_object_count": len(source_objects),
            "source_object_names": [obj.name for obj in source_objects],
            "source_vertex_count_sum": source_vertices,
            "source_polygon_count_sum": source_polygons,
            "source_triangulated_triangle_count": source_triangles,
            "baked_vertex_count": len(joined_mesh.vertices),
            "baked_polygon_count": len(joined_mesh.polygons),
            "baked_triangulated_triangle_count": len(joined_mesh.loop_triangles),
            "baked_loop_count": len(joined_mesh.loops),
            "source_material_names": sorted(source_material_names),
            "bounds_blender_xyz_m": {"min": bounds_min, "max": bounds_max, "size": max_size},
            "max_source_to_baked_error": {
                "world_position_m": max_position_error,
                "normal_unit_vector": max_normal_error,
                "uv_unitless": max_uv_error,
            },
            "triangles_preserved": source_triangles == len(joined_mesh.loop_triangles),
            "polygons_preserved": source_polygons == len(joined_mesh.polygons),
            "custom_loop_normals": bool(joined_mesh.has_custom_normals),
        },
        "output_directory": output_dir.relative_to(source_dir).as_posix() if output_dir.is_relative_to(source_dir) else "external_test_output",
        "material_mapping": {
            "source_legacy_specular_intensity": legacy_specular,
            "source_principled_specular_ior_level": source_principled_specular,
            "glTF_metallic_factor": 0.0,
            "glTF_roughness_factor": 1.0,
            "roughness_note": "reviewed scalar legacy-material adaptation; not authored roughness texture data",
            "specular_note": "glTF core metallic-roughness does not encode source specular_intensity 0.0. KHR_materials_specular was tested but Godot 4.7 ignores it, so omitted. Godot's imported StandardMaterial3D metallic_specular remains default 0.5; no runtime workaround is applied.",
            "alpha_mode": "BLEND",
            "alpha_source": "original packed diffuse/alpha atlas; unchanged",
            "added_maps": [],
        },
        "outputs": [],
    }
    for name in ("oak_lod0.gltf", "oak_lod0.bin", "Quercus_A_1024.png"):
        path = output_dir / name
        if not path.is_file():
            raise SystemExit(f"Required output missing: {path}")
        proof["outputs"].append({"path": name, "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    canonical_output_dir = (source_dir / OUTPUT_RELATIVE).resolve()
    proof_path = (source_dir / "CONVERSION-PROOF-LOD0.json") if output_dir == canonical_output_dir else (output_dir / "CONVERSION-PROOF-LOD0.json")
    proof_path.write_text(json.dumps(proof, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"proof": str(proof_path), "outputs": proof["outputs"], "triangles": len(joined_mesh.loop_triangles), "material": proof["material_mapping"]}, indent=2))


if __name__ == "__main__":
    try:
        import bpy  # type: ignore[import-not-found]
    except ImportError:
        run_outside_blender()
    else:
        run_inside_blender()
