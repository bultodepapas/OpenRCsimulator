#!/usr/bin/env python3
"""Bake a four-view transparent billboard atlas from a pinned vegetation glTF.

Run from the repository root with Blender 5.2.2:
    blender --background --python tools/landscape/vegetation/bake_hedge_impostor.py -- --source-asset-id bush_common_flowers --frame-size 256

The source mesh and its imported material are rendered directly. This script does
not create or edit vegetation geometry; it only writes view images and provenance.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import tempfile
from typing import Any

import bpy  # type: ignore
from mathutils import Vector  # type: ignore


ROOT = Path(__file__).resolve().parents[3]
CATALOG_PATH = ROOT / "app/assets/landscape/vegetation/catalog.json"
LICENSE_PATH = ROOT / "assets/landscape/vegetation/source/License_Standard.txt"
OUTPUT_DIR = ROOT / "app/assets/landscape/vegetation/impostors"
DEFAULT_SOURCE_ASSET_ID = "bush_common_flowers"
DEFAULT_OUTPUT_STEM = "bush_common_flowers_4view"
AZIMUTHS_DEG = (0, 90, 180, 270)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _created_id_snapshot() -> dict[str, set[int]]:
    names = (
        "objects", "meshes", "materials", "images", "cameras", "lights",
        "curves", "worlds", "collections",
    )
    return {name: {item.as_pointer() for item in getattr(bpy.data, name)} for name in names}


def _remove_created_ids(before: dict[str, set[int]]) -> None:
    for name in ("objects", "collections", "meshes", "materials", "images", "cameras", "lights", "curves", "worlds"):
        datablocks = getattr(bpy.data, name)
        for datablock in list(datablocks):
            if datablock.as_pointer() in before[name]:
                continue
            try:
                if name == "objects":
                    datablocks.remove(datablock, do_unlink=True)
                else:
                    datablocks.remove(datablock)
            except (ReferenceError, RuntimeError):
                pass


def _place_camera(camera: Any, target: Vector, azimuth: float, distance: float) -> None:
    direction = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
    camera.location = target + direction * distance
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def _route_material_to_unlit_albedo(material: Any, alpha_cutoff: float, source_alpha_mode: str) -> dict[str, Any]:
    """Render the imported glTF Base Color/Alpha without lighting or relighting."""
    if not material.use_nodes or material.node_tree is None:
        return {"material": material.name, "base_color_source": "material default", "alpha_mode": source_alpha_mode}
    nodes = material.node_tree.nodes
    principled = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
    if principled is None:
        return {"material": material.name, "base_color_source": "unchanged node surface", "alpha_mode": source_alpha_mode}

    base_input = principled.inputs.get("Base Color")
    alpha_input = principled.inputs.get("Alpha")
    base_link = base_input.links[0].from_socket if base_input is not None and base_input.is_linked else None
    alpha_link = alpha_input.links[0].from_socket if alpha_input is not None and alpha_input.is_linked else None
    base_default = tuple(base_input.default_value) if base_input is not None else (1.0, 1.0, 1.0, 1.0)
    alpha_default = float(alpha_input.default_value) if alpha_input is not None else 1.0

    def upstream_node_types(socket: Any, visited: set[int] | None = None) -> list[str]:
        visited = set() if visited is None else visited
        result: list[str] = []
        for link in socket.links:
            node = link.from_node
            pointer = node.as_pointer()
            if pointer in visited:
                continue
            visited.add(pointer)
            result.append(str(node.type))
            for input_socket in node.inputs:
                if input_socket.is_linked:
                    result.extend(upstream_node_types(input_socket, visited))
        return result

    base_network = upstream_node_types(base_input) if base_input is not None else []
    alpha_network = upstream_node_types(alpha_input) if alpha_input is not None else []

    output = next((node for node in nodes if node.type == "OUTPUT_MATERIAL"), None)
    if output is None:
        output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    alpha_test = nodes.new("ShaderNodeMath")
    alpha_test.operation = "GREATER_THAN"
    alpha_test.inputs[1].default_value = alpha_cutoff
    mix = nodes.new("ShaderNodeMixShader")

    links = material.node_tree.links
    if base_link is not None:
        links.new(base_link, emission.inputs[0])
    else:
        emission.inputs[0].default_value = base_default
    if alpha_link is not None:
        links.new(alpha_link, alpha_test.inputs[0])
    else:
        alpha_test.inputs[0].default_value = alpha_default
    links.new(alpha_test.outputs[0], mix.inputs[0])
    links.new(transparent.outputs[0], mix.inputs[1])
    links.new(emission.outputs[0], mix.inputs[2])
    for link in list(output.inputs["Surface"].links):
        links.remove(link)
    links.new(mix.outputs[0], output.inputs["Surface"])

    # Blender 5.x Eevee's dithered surface mode supports the glTF mask's
    # transparent branch while the explicit Greater Than node retains MASK.
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    material.diffuse_color = base_default
    return {
        "material": material.name,
        "base_color_source": "complete imported glTF Principled Base Color input link, routed to Emission",
        "base_color_input_network": base_network,
        "alpha_source": "complete imported glTF Principled Alpha input link, thresholded",
        "alpha_input_network": alpha_network,
        "alpha_mode": source_alpha_mode,
        "alpha_cutoff": alpha_cutoff,
        "surface_render_method": getattr(material, "surface_render_method", "legacy"),
    }


def _source_vertex_color_metadata(mesh_objects: list[Any]) -> dict[str, Any]:
    attributes = []
    for obj in mesh_objects:
        for attribute in getattr(obj.data, "color_attributes", []):
            samples = [tuple(item.color) for item in attribute.data]
            if not samples:
                continue
            means = [sum(sample[channel] for sample in samples) / len(samples) for channel in range(4)]
            minima = [min(sample[channel] for sample in samples) for channel in range(4)]
            maxima = [max(sample[channel] for sample in samples) for channel in range(4)]
            attributes.append({
                "mesh": obj.name,
                "name": attribute.name,
                "gltf_semantic": "COLOR_0",
                "domain": attribute.domain,
                "data_type": attribute.data_type,
                "sample_count": len(samples),
                "mean_rgba": [round(value, 8) for value in means],
                "min_rgba": [round(value, 8) for value in minima],
                "max_rgba": [round(value, 8) for value in maxima],
            })
    return {"attributes": attributes}


def _render_scene(scene: Any, destination: Path) -> None:
    window = bpy.context.window
    if window is not None:
        window.scene = scene
        bpy.ops.render.render(write_still=True)
        return
    with bpy.context.temp_override(scene=scene, view_layer=scene.view_layers[0]):
        bpy.ops.render.render(write_still=True)


def bake(
	frame_size: int = 256,
	source_asset_id: str = DEFAULT_SOURCE_ASSET_ID,
	output_stem: str = "",
) -> dict[str, Any]:
    if frame_size < 128 or frame_size > 1024 or frame_size % 2:
        raise ValueError("frame size must be an even integer from 128 to 1024")
    if not CATALOG_PATH.is_file():
        raise FileNotFoundError("pinned vegetation catalog is missing")

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    source_asset = next((item for item in catalog.get("assets", []) if item.get("id") == source_asset_id), None)
    if source_asset is None:
        raise ValueError(f"catalog does not contain source asset {source_asset_id!r}")
    scene_resource_path = str(source_asset.get("scene", ""))
    if not scene_resource_path.startswith("res://"):
        raise ValueError(f"catalog source scene is not a Godot resource path: {scene_resource_path!r}")
    source_scene = ROOT / "app" / scene_resource_path.removeprefix("res://")
    if not source_scene.is_file():
        raise FileNotFoundError(f"pinned source scene is missing: {source_scene}")
    if output_stem == "":
        output_stem = DEFAULT_OUTPUT_STEM if source_asset_id == DEFAULT_SOURCE_ASSET_ID else f"{source_asset_id}_4view"
    if Path(output_stem).name != output_stem or output_stem in ("", ".", ".."):
        raise ValueError("output stem must be a simple filename stem")
    output_atlas = OUTPUT_DIR / f"{output_stem}.png"
    output_manifest = OUTPUT_DIR / f"{output_stem}.json"

    source_gltf = json.loads(source_scene.read_text(encoding="utf-8"))
    source_materials = source_gltf.get("materials", []) or [{}]
    source_material = source_materials[0]
    alpha_cutoff = float(source_material.get("alphaCutoff", 0.5))
    alpha_mode = str(source_material.get("alphaMode", "OPAQUE"))

    scene_before = bpy.context.window.scene if bpy.context.window is not None else bpy.context.scene
    before = _created_id_snapshot()
    bake_scene = bpy.data.scenes.new(f"__OpenRC_{source_asset_id}_ImpostorBake")
    window = bpy.context.window
    if window is not None:
        window.scene = bake_scene

    temp_images: list[Any] = []
    try:
        # Blender 5.2 exposes EEVEE as BLENDER_EEVEE (renamed from *_NEXT).
        bake_scene.render.engine = "BLENDER_EEVEE"
        bake_scene.render.resolution_x = frame_size
        bake_scene.render.resolution_y = frame_size
        bake_scene.render.resolution_percentage = 100
        bake_scene.render.image_settings.file_format = "PNG"
        bake_scene.render.image_settings.color_mode = "RGBA"
        bake_scene.render.image_settings.color_depth = "8"
        bake_scene.render.film_transparent = True
        bake_scene.render.image_settings.compression = 12
        bake_scene.view_settings.view_transform = "Standard"
        bake_scene.view_settings.look = "None"
        bake_scene.view_settings.exposure = 0.0
        bake_scene.view_settings.gamma = 1.0

        if window is None:
            with bpy.context.temp_override(scene=bake_scene, view_layer=bake_scene.view_layers[0]):
                bpy.ops.import_scene.gltf(filepath=str(source_scene))
        else:
            bpy.ops.import_scene.gltf(filepath=str(source_scene))
        bpy.context.view_layer.update()
        mesh_objects = [obj for obj in bake_scene.objects if obj.type == "MESH"]
        if not mesh_objects:
            raise RuntimeError(f"{source_asset_id} glTF imported without a mesh")

        world_vertices = [obj.matrix_world @ vertex.co for obj in mesh_objects for vertex in obj.data.vertices]
        minimum = Vector((min(point.x for point in world_vertices), min(point.y for point in world_vertices), min(point.z for point in world_vertices)))
        maximum = Vector((max(point.x for point in world_vertices), max(point.y for point in world_vertices), max(point.z for point in world_vertices)))
        # Blender's glTF importer maps the glTF Y-up source axis to Blender Z-up.
        ground_lift = -minimum.z
        material_records: list[dict[str, Any]] = []
        for obj in mesh_objects:
            world_transform = obj.matrix_world.copy()
            world_transform.translation.z += ground_lift
            obj.matrix_world = world_transform
            for material in obj.data.materials:
                if material is None:
                    continue
                material_record = _route_material_to_unlit_albedo(material, alpha_cutoff, alpha_mode)
                if material_record not in material_records:
                    material_records.append(material_record)
        bpy.context.view_layer.update()
        minimum.z = 0.0
        maximum.z += ground_lift

        source_height = maximum.z - minimum.z
        horizontal_x = maximum.x - minimum.x
        horizontal_y = maximum.y - minimum.y
        if source_height <= 0.0 or max(horizontal_x, horizontal_y) <= 0.0:
            raise RuntimeError(f"{source_asset_id} imported bounds are degenerate")
        frame_scale = max(source_height, horizontal_x, horizontal_y) * 1.10
        target = Vector(((minimum.x + maximum.x) * 0.5, (minimum.y + maximum.y) * 0.5, source_height * 0.5))

        world = bpy.data.worlds.new("__OpenRC_BushCommonBakeWorld")
        bake_scene.world = world
        world.use_nodes = True
        background = next(node for node in world.node_tree.nodes if node.type == "BACKGROUND")
        background.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        background.inputs["Strength"].default_value = 0.0

        camera_data = bpy.data.cameras.new("__OpenRC_BushCommonBakeCamera")
        camera = bpy.data.objects.new("__OpenRC_BushCommonBakeCamera", camera_data)
        bake_scene.collection.objects.link(camera)
        camera_data.type = "ORTHO"
        camera_data.ortho_scale = frame_scale
        camera_data.lens = 50.0
        bake_scene.camera = camera

        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="openrc_bush_impostor_") as temp_dir:
            panel_paths: list[Path] = []
            for view_index, azimuth_degrees in enumerate(AZIMUTHS_DEG):
                _place_camera(camera, target, math.radians(azimuth_degrees), frame_scale * 5.0)
                panel_path = Path(temp_dir) / f"view_{view_index}.png"
                bake_scene.render.filepath = str(panel_path)
                _render_scene(bake_scene, panel_path)
                if not panel_path.is_file():
                    raise RuntimeError(f"Blender failed to write impostor view {view_index}")
                panel_paths.append(panel_path)

            atlas = bpy.data.images.new(
                f"__OpenRC_{source_asset_id}4ViewAtlas",
                width=frame_size * len(AZIMUTHS_DEG),
                height=frame_size,
                alpha=True,
                float_buffer=False,
            )
            atlas.alpha_mode = "STRAIGHT"
            atlas.colorspace_settings.name = "sRGB"
            pixels = [0.0] * (frame_size * len(AZIMUTHS_DEG) * frame_size * 4)
            atlas_width = frame_size * len(AZIMUTHS_DEG)
            row_pixels = frame_size * 4
            for view_index, panel_path in enumerate(panel_paths):
                image = bpy.data.images.load(str(panel_path), check_existing=False)
                temp_images.append(image)
                source_pixels = list(image.pixels[:])
                cell_start = view_index * row_pixels
                for row in range(frame_size):
                    source_start = row * row_pixels
                    target_start = row * atlas_width * 4 + cell_start
                    pixels[target_start:target_start + row_pixels] = source_pixels[source_start:source_start + row_pixels]
            atlas.pixels.foreach_set(pixels)
            atlas.filepath_raw = str(output_atlas)
            atlas.file_format = "PNG"
            atlas.save()

        source_bounds = source_asset.get("source_bounds_m", {})
        source_record = catalog.get("source", {})
        source_texture_records = []
        for texture in source_asset.get("textures", []):
            texture_uri = str(texture.get("uri", ""))
            texture_path = source_scene.parent / texture_uri
            source_texture_records.append({
                **texture,
                "sha256": sha256(texture_path) if texture_path.is_file() else "",
            })
        base_color_factors = []
        for material in source_materials:
            pbr = material.get("pbrMetallicRoughness", {})
            factor_explicit = "baseColorFactor" in pbr
            base_color_factors.append({
                "material": material.get("name", ""),
                "gltf_value": pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0]),
                "explicit_in_source": factor_explicit,
                "gltf_default_when_omitted": [1.0, 1.0, 1.0, 1.0],
            })
        manifest = {
            "format": "openrc-vegetation-impostor v1",
            "asset_id": f"{source_asset_id}_4view_impostor",
            "derived_from_asset_id": source_asset_id,
            "source_name": source_asset.get("source_name", source_asset_id),
            "source_scene": scene_resource_path,
            "source_geometry_sha256": source_asset.get("source_sha256", ""),
            "source_triangles": int(source_asset.get("source_triangles", 0)),
            "source_surfaces": int(source_asset.get("source_surfaces", 0)),
            "source_materials": int(source_asset.get("source_materials", 0)),
            "source_archive_sha256": source_record.get("archive_sha256", ""),
            "license": source_record.get("license", "CC0-1.0 (Quaternius Stylized Nature MegaKit Standard)"),
            "license_evidence": "assets/landscape/vegetation/source/License_Standard.txt",
            "license_evidence_sha256": sha256(LICENSE_PATH) if LICENSE_PATH.is_file() else "",
            "source_textures": source_texture_records,
            "source_base_color_factors": base_color_factors,
            "source_vertex_colors": _source_vertex_color_metadata(mesh_objects),
            "source_bounds_m": source_bounds,
            "source_mesh_bounds_blender_z_up_m": {
                "min": [round(minimum.x, 6), round(minimum.y, 6), 0.0],
                "max": [round(maximum.x, 6), round(maximum.y, 6), round(source_height, 6)],
            },
            "source_height_m": round(source_height, 6),
            "frame_world_size_m": [round(frame_scale, 6), round(frame_scale, 6)],
            "baked_azimuth_deg": list(AZIMUTHS_DEG),
            "view_up": "source Y-up, imported and rendered with Blender Z-up",
            "frame_size_px": [frame_size, frame_size],
            "atlas_size_px": [frame_size * len(AZIMUTHS_DEG), frame_size],
            "atlas_path": f"res://assets/landscape/vegetation/impostors/{output_stem}.png",
            "atlas_sha256": sha256(output_atlas),
            "color_pipeline": {
                "source_color": "glTF material Base Color input, routed directly to Emission Color",
                "source_color_chain": "full Blender-imported Principled Base Color socket link, including the source image and COLOR_0 node chain",
                "lighting": "unshaded emission only; no light objects and world strength 0",
                "view_transform": "Standard",
                "look": "None",
                "exposure": 0.0,
                "gamma": 1.0,
                "output_colorspace": "sRGB PNG",
                "alpha": "source glTF Alpha input thresholded with Greater Than at glTF alphaCutoff",
                "alpha_cutoff": alpha_cutoff,
                "alpha_mode": alpha_mode,
                "png_channels": "RGBA",
                "png_bit_depth": 8,
                "alpha_mode_storage": "straight",
                "material_routes": material_records,
            },
            "renderer": f"Blender {bpy.app.version_string} EEVEE, unshaded source Base Color/Alpha, Standard view transform, transparent background",
            "rebuild_command": (
                "blender --background --python tools/landscape/vegetation/bake_hedge_impostor.py -- "
                f"--source-asset-id {source_asset_id} --output-stem {output_stem} --frame-size 256"
            ),
        }
        output_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        manifest["manifest_sha256"] = sha256(output_manifest)
        return manifest
    finally:
        if window is not None:
            window.scene = scene_before
        if bpy.data.scenes.get(bake_scene.name) is not None:
            bpy.data.scenes.remove(bake_scene)
        _remove_created_ids(before)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frame-size", type=int, default=256)
    parser.add_argument("--source-asset-id", default=DEFAULT_SOURCE_ASSET_ID)
    parser.add_argument("--output-stem", default="")
    parser.add_argument("--check", action="store_true", help="verify generated atlas and manifest match source hashes")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source_asset_id = args.source_asset_id
    output_stem = args.output_stem or (
        DEFAULT_OUTPUT_STEM if source_asset_id == DEFAULT_SOURCE_ASSET_ID else f"{source_asset_id}_4view"
    )
    if Path(output_stem).name != output_stem or output_stem in ("", ".", ".."):
        raise SystemExit("output stem must be a simple filename stem")
    output_atlas = OUTPUT_DIR / f"{output_stem}.png"
    output_manifest = OUTPUT_DIR / f"{output_stem}.json"
    if args.check:
        manifest = json.loads(output_manifest.read_text(encoding="utf-8"))
        catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        source_asset = next((item for item in catalog.get("assets", []) if item.get("id") == source_asset_id), None)
        if source_asset is None:
            raise SystemExit(f"catalog does not contain source asset {source_asset_id!r}")
        scene_resource_path = str(source_asset.get("scene", ""))
        source_scene = ROOT / "app" / scene_resource_path.removeprefix("res://")
        expected_source = catalog.get("source", {})
        archive_path = ROOT / str(expected_source.get("archive", ""))
        if manifest.get("derived_from_asset_id") != source_asset_id \
            or manifest.get("asset_id") != f"{source_asset_id}_4view_impostor" \
            or manifest.get("source_scene") != scene_resource_path \
            or manifest.get("atlas_path") != f"res://assets/landscape/vegetation/impostors/{output_stem}.png":
            raise SystemExit(f"{source_asset_id} impostor manifest identifies a different source or output")
        if not source_scene.is_file() or manifest.get("source_geometry_sha256") != source_asset.get("source_sha256") \
            or manifest.get("source_geometry_sha256") != sha256(source_scene):
            raise SystemExit(f"{source_asset_id} source geometry changed; rebake the atlas")
        for field in ("source_triangles", "source_surfaces", "source_materials"):
            if int(manifest.get(field, -1)) != int(source_asset.get(field, -2)):
                raise SystemExit(f"{source_asset_id} {field} no longer matches the pinned catalog")
        if not archive_path.is_file() or manifest.get("source_archive_sha256") != expected_source.get("archive_sha256") \
            or manifest.get("source_archive_sha256") != sha256(archive_path):
            raise SystemExit("vegetation source archive changed; revalidate the pinned source")
        if manifest.get("license_evidence_sha256") != sha256(LICENSE_PATH) \
            or manifest.get("license_evidence_sha256") != expected_source.get("license_sha256"):
            raise SystemExit("vegetation license evidence changed; rebake provenance")
        expected_textures = source_asset.get("textures", [])
        manifest_textures = manifest.get("source_textures", [])
        if len(manifest_textures) != len(expected_textures):
            raise SystemExit(f"{source_asset_id} source texture list is incomplete; rebake the atlas")
        for expected_texture in expected_textures:
            texture_uri = str(expected_texture.get("uri", ""))
            manifest_texture = next(
                (item for item in manifest_textures if item.get("uri") == texture_uri), None
            )
            texture_path = source_scene.parent / texture_uri
            expected_hash = sha256(texture_path) if texture_path.is_file() else ""
            if manifest_texture is None or manifest_texture.get("source_entry") != expected_texture.get("source_entry") \
                or manifest_texture.get("sha256") != expected_hash or not texture_path.is_file():
                raise SystemExit(f"{source_asset_id} source texture changed or is unrecorded: {texture_uri}")
        if manifest.get("atlas_sha256") != sha256(output_atlas):
            raise SystemExit(f"{source_asset_id} atlas changed since its manifest was written")
        print(json.dumps(manifest, indent=2))
        return
    result = bake(args.frame_size, source_asset_id, output_stem)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
