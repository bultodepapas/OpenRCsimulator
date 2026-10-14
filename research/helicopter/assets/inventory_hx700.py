"""Read-only audit of the supplied HX-700 Blender source.

Run with Blender 5.2+ from the repository root:

    blender -b "Helicopter 3d acrobatic/HX-700_Helicoptero_RC.blend" \
      --python research/helicopter/assets/inventory_hx700.py -- \
      --out .tools/heli25

The script never saves the loaded .blend. Its inventory and temporary camera
renders go to the requested output directory (ignored .tools by default).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import sys
from collections import Counter
from pathlib import Path

import bpy
from mathutils import Vector


REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_BLEND = REPO_ROOT / "Helicopter 3d acrobatic" / "HX-700_Helicoptero_RC.blend"
DEFAULT_PDF = REPO_ROOT / "Helicopter 3d acrobatic" / "UYjm3SGvvYxnGgggCnqPGIuKhQHNNSeM98oX8uMr.pdf"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def rounded(value: float) -> float:
    return round(float(value), 8)


def vector_json(value) -> list[float]:
    return [rounded(component) for component in value]


def property_values(id_block) -> dict:
    result = {}
    for key in id_block.keys():
        if key == "_RNA_UI":
            continue
        value = id_block[key]
        if isinstance(value, (str, bool, int, float)):
            result[str(key)] = value
        elif hasattr(value, "to_list"):
            result[str(key)] = value.to_list()
        else:
            result[str(key)] = str(value)
    return result


def eigenvectors_symmetric3(matrix):
    """Return ascending eigenvalue/eigenvector pairs using Jacobi rotations."""
    a = [[float(matrix[i][j]) for j in range(3)] for i in range(3)]
    v = [[1.0 if i == j else 0.0 for j in range(3)] for i in range(3)]
    for _ in range(48):
        p, q = max(((0, 1), (0, 2), (1, 2)), key=lambda ij: abs(a[ij[0]][ij[1]]))
        if abs(a[p][q]) < 1e-14:
            break
        angle = 0.5 * math.atan2(2.0 * a[p][q], a[q][q] - a[p][p])
        c, s = math.cos(angle), math.sin(angle)
        app, aqq, apq = a[p][p], a[q][q], a[p][q]
        a[p][p] = c * c * app - 2.0 * s * c * apq + s * s * aqq
        a[q][q] = s * s * app + 2.0 * s * c * apq + c * c * aqq
        a[p][q] = a[q][p] = 0.0
        for r in range(3):
            if r not in (p, q):
                arp, arq = a[r][p], a[r][q]
                a[r][p] = a[p][r] = c * arp - s * arq
                a[r][q] = a[q][r] = s * arp + c * arq
            vrp, vrq = v[r][p], v[r][q]
            v[r][p], v[r][q] = c * vrp - s * vrq, s * vrp + c * vrq
    pairs = []
    for i in range(3):
        axis = Vector((v[0][i], v[1][i], v[2][i])).normalized()
        pairs.append((max(0.0, a[i][i]), axis))
    return sorted(pairs, key=lambda pair: pair[0])


def evaluate_mesh(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        mesh.calc_loop_triangles()
        points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        return mesh, points, len(mesh.loop_triangles)
    except Exception:
        evaluated.to_mesh_clear()
        raise


def bounds(points):
    if not points:
        return None
    lo = [min(point[axis] for point in points) for axis in range(3)]
    hi = [max(point[axis] for point in points) for axis in range(3)]
    return {"min": vector_json(lo), "max": vector_json(hi), "size": vector_json(hi[i] - lo[i] for i in range(3)),
            "center": vector_json((lo[i] + hi[i]) * 0.5 for i in range(3))}


def name_bucket(name: str) -> str | None:
    value = name.casefold().replace("_", " ").replace("-", " ")
    if re.search(r"tail.*(rotor|blade|paddle|prop|hub|fan)|(?:rotor|blade|paddle|prop|hub|fan).*tail|pala.*cola|cola.*pala", value):
        return "tail_rotor"
    if re.search(r"(?:main|head).*(rotor|blade|paddle|hub)|(?:rotor|blade|paddle).*main|rotorhead|mainshaft|flybar|pala.*principal|principal.*pala", value):
        return "main_rotor"
    return None


def assembly_estimate(objects, point_map, pivot_obj=None):
    points = [point for obj in objects for point in point_map.get(obj.name, [])]
    if not points:
        return {"center_scene_units": None, "spin_axis_world": None, "method": "no named mesh candidates"}
    box = bounds(points)
    center = pivot_obj.matrix_world.translation.copy() if pivot_obj else Vector(box["center"])
    mean = sum(points, Vector((0.0, 0.0, 0.0))) / len(points)
    covariance = [[0.0] * 3 for _ in range(3)]
    for point in points:
        d = point - mean
        for i in range(3):
            for j in range(3):
                covariance[i][j] += d[i] * d[j]
    covariance = [[entry / len(points) for entry in row] for row in covariance]
    eig = eigenvectors_symmetric3(covariance)
    values = [max(0.0, value) for value, _ in eig]
    flatness = values[0] / max(values[1], 1e-30)
    axis = eig[0][1]
    radial_extents = []
    for point in points:
        delta = point - center
        radial_extents.append((delta - axis * delta.dot(axis)).length)
    confidence = "geometry-plane estimate" if flatness < 0.2 else "low: candidate geometry is not a clear plane"
    return {
        "center_scene_units": vector_json(center),
        "pivot_name": pivot_obj.name if pivot_obj else None,
        "pivot_rest_euler_world_degrees": vector_json(math.degrees(value) for value in pivot_obj.matrix_world.to_euler()) if pivot_obj else None,
        "blade_geometry_bounds_world": box,
        "blade_geometry_bounds_center_scene_units": box["center"],
        "spin_axis_world_unsigned": vector_json(axis),
        "spin_direction": "undetermined from static geometry",
        "blade_root_radius_min_scene_units": rounded(min(radial_extents)),
        "blade_tip_radius_max_scene_units": rounded(max(radial_extents)),
        "diameter_from_mesh_tip_radius_scene_units": rounded(2.0 * max(radial_extents)),
        "pca_eigenvalues": [rounded(value) for value in values],
        "plane_flatness_ratio": rounded(flatness),
        "estimate_quality": confidence,
        "method": "combined named mesh candidates; center is world-bounds center; axis is least-variance PCA direction",
        "object_names": [obj.name for obj in objects],
    }


def transform_record(obj):
    return {
        "location_world_scene_units": vector_json(obj.matrix_world.translation),
        "rotation_euler_world_degrees": vector_json(math.degrees(value) for value in obj.matrix_world.to_euler()),
        "scale_local": vector_json(obj.scale),
        "dimensions_world_scene_units": vector_json(obj.dimensions),
    }


def driver_records(animation_data):
    records = []
    if not animation_data:
        return records
    for curve in animation_data.drivers:
        driver = curve.driver
        variables = []
        for variable in driver.variables:
            targets = []
            for target in variable.targets:
                target_record = {"id": target.id.name if target.id else None,
                                 "data_path": target.data_path}
                if target.bone_target:
                    target_record["bone_target"] = target.bone_target
                if target.transform_type:
                    target_record["transform_type"] = target.transform_type
                if target.transform_space:
                    target_record["transform_space"] = target.transform_space
                targets.append(target_record)
            variables.append({"name": variable.name, "type": variable.type, "targets": targets})
        records.append({"data_path": curve.data_path, "array_index": curve.array_index,
                        "expression": driver.expression, "type": driver.type, "variables": variables})
    return records


def descendants(root):
    result = []
    pending = list(root.children)
    while pending:
        obj = pending.pop()
        result.append(obj)
        pending.extend(obj.children)
    return result


def write_renders(scene, out_dir: Path, world_bounds, visible_names):
    if not world_bounds:
        return []
    render_dir = out_dir / "renders"
    render_dir.mkdir(parents=True, exist_ok=True)
    low, high = Vector(world_bounds["min"]), Vector(world_bounds["max"])
    center = (low + high) * 0.5
    radius = max((high - low).length * 0.5, 0.01)
    old_engine = scene.render.engine
    old_camera = scene.camera
    old_world = scene.world
    old_settings = (scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage,
                    scene.render.image_settings.file_format, scene.render.film_transparent, scene.render.filepath)
    old_hidden = [(obj, obj.hide_render) for obj in scene.objects]
    created = []
    outputs = []
    try:
        for obj, _ in old_hidden:
            obj.hide_render = obj.name not in visible_names
        scene.render.engine = "BLENDER_EEVEE"
        scene.render.resolution_x = 960
        scene.render.resolution_y = 720
        scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = "PNG"
        scene.render.film_transparent = False
        render_world = bpy.data.worlds.new("HELI-25 temporary neutral render world")
        created.append(render_world)
        background = render_world.node_tree.nodes.get("Background")
        if background:
            background.inputs["Color"].default_value = (0.055, 0.065, 0.08, 1.0)
            background.inputs["Strength"].default_value = 0.7
        scene.world = render_world
        camera_data = bpy.data.cameras.new("HELI-25 temporary orthographic camera")
        camera_obj = bpy.data.objects.new("HELI-25 temporary orthographic camera", camera_data)
        scene.collection.objects.link(camera_obj)
        created.append(camera_data)
        created.append(camera_obj)
        scene.camera = camera_obj
        camera_data.type = "ORTHO"
        camera_data.lens = 50
        camera_data.ortho_scale = max(radius * 2.45, 0.1)
        camera_distance = radius * 4.0
        camera_data.clip_start = max(radius * 0.0001, 0.001)
        camera_data.clip_end = max(radius * 20.0, 100.0)

        light_data = bpy.data.lights.new("HELI-25 temporary area light", "AREA")
        light_obj = bpy.data.objects.new("HELI-25 temporary area light", light_data)
        scene.collection.objects.link(light_obj)
        created.append(light_data)
        created.append(light_obj)
        light_data.energy = 1800
        light_data.shape = "DISK"
        light_data.size = radius * 2.5
        light_obj.location = center + Vector((radius * 2.5, -radius * 3.2, radius * 3.5))
        light_obj.rotation_euler = (center - light_obj.location).to_track_quat("-Z", "Y").to_euler()

        views = {
            "top": (Vector((0, 0, 1)), "Y"),
            "side_x": (Vector((0, -1, 0)), "Z"),
            "front_x": (Vector((1, 0, 0)), "Z"),
            "oblique": (Vector((1, -1, 0.75)).normalized(), "Z"),
        }
        for name, (direction, up_axis) in views.items():
            camera_obj.location = center + direction * camera_distance
            camera_obj.rotation_euler = (-direction).to_track_quat("-Z", up_axis).to_euler()
            scene.render.filepath = str((render_dir / f"hx700-{name}.png").resolve())
            bpy.ops.render.render(write_still=True)
            outputs.append(str(Path(scene.render.filepath).relative_to(REPO_ROOT)))
    finally:
        scene.camera = old_camera
        scene.world = old_world
        scene.render.engine = old_engine
        (scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage,
         scene.render.image_settings.file_format, scene.render.film_transparent, scene.render.filepath) = old_settings
        for obj, value in old_hidden:
            obj.hide_render = value
        for block in reversed(created):
            try:
                if isinstance(block, bpy.types.Object):
                    bpy.data.objects.remove(block, do_unlink=True)
                elif isinstance(block, bpy.types.Camera):
                    bpy.data.cameras.remove(block)
                elif isinstance(block, bpy.types.Light):
                    bpy.data.lights.remove(block)
                elif isinstance(block, bpy.types.World):
                    bpy.data.worlds.remove(block)
            except (ReferenceError, RuntimeError):
                pass
    return outputs


def read_glb_json(path: Path) -> dict:
    with path.open("rb") as stream:
        header = stream.read(12)
        if len(header) != 12:
            raise ValueError("GLB header is incomplete")
        magic, version, declared_length = struct.unpack("<4sII", header)
        if magic != b"glTF" or version != 2 or declared_length != path.stat().st_size:
            raise ValueError(f"Invalid GLB header: magic={magic!r}, version={version}, length={declared_length}")
        while True:
            chunk_header = stream.read(8)
            if not chunk_header:
                break
            chunk_length, chunk_type = struct.unpack("<II", chunk_header)
            chunk = stream.read(chunk_length)
            if len(chunk) != chunk_length:
                raise ValueError("GLB chunk is truncated")
            if chunk_type == 0x4E4F534A:
                return json.loads(chunk.decode("utf-8"))
    raise ValueError("GLB JSON chunk was not found")


def export_preview(out_dir: Path, source_path: Path, root, model_objects, model_names, replace_preview=False) -> dict:
    tools_dir = (REPO_ROOT / ".tools").resolve()
    try:
        out_dir.resolve().relative_to(tools_dir)
    except ValueError as error:
        raise ValueError("Preview GLB output must remain under the ignored repository .tools directory") from error
    path = (out_dir / "hx700-preview.glb").resolve()
    if path == source_path.resolve() or path.suffix.casefold() != ".glb":
        raise ValueError("Preview output must be a separate .glb file")
    if path.exists() and not replace_preview:
        raise FileExistsError(f"Refusing to overwrite existing preview output: {path}")
    if not hasattr(bpy.ops.export_scene, "gltf"):
        raise RuntimeError("Blender glTF exporter is unavailable")

    scene = bpy.context.scene
    selected_before = [(obj, obj.select_get()) for obj in scene.objects]
    active_before = bpy.context.view_layer.objects.active
    had_marker = "openrc_presentation_only" in root
    old_marker = root.get("openrc_presentation_only") if had_marker else None
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        for obj, _ in selected_before:
            obj.select_set(False)
        for obj in [root] + list(model_objects):
            obj.select_set(True)
        bpy.context.view_layer.objects.active = root
        root["openrc_presentation_only"] = "Static frame-1 visual preview; physics and driver animation excluded."
        result = bpy.ops.export_scene.gltf(
            filepath=str(path),
            check_existing=False,
            export_format="GLB",
            use_selection=True,
            export_animations=False,
            export_skins=False,
            export_morph=False,
            export_lights=False,
            export_cameras=False,
            export_apply=False,
            export_extras=True,
            export_materials="EXPORT",
            export_yup=True,
            export_draco_mesh_compression_enable=False,
        )
        if "FINISHED" not in result or not path.is_file():
            raise RuntimeError(f"Blender glTF export did not finish: {result}")
    finally:
        if had_marker:
            root["openrc_presentation_only"] = old_marker
        else:
            del root["openrc_presentation_only"]
        for obj, selected in selected_before:
            obj.select_set(selected)
        bpy.context.view_layer.objects.active = active_before

    gltf = read_glb_json(path)
    nodes = gltf.get("nodes", [])
    node_names = [node.get("name") for node in nodes if node.get("name")]
    missing_required = sorted({"HX-700", "Pivote_Rotor_Principal", "Pivote_Rotor_Cola",
                               "Pala_Principal_A", "Pala_Principal_B", "Pala_Cola_A", "Pala_Cola_B"} - set(node_names))
    if missing_required:
        raise RuntimeError(f"Preview GLB omitted required root/pivot/blade nodes: {missing_required}")
    root_node = next(node for node in nodes if node.get("name") == "HX-700")
    pivot_nodes = {name: next(node for node in nodes if node.get("name") == name)
                   for name in ("Pivote_Rotor_Principal", "Pivote_Rotor_Cola")}
    return {
        "path": str(path.relative_to(REPO_ROOT)),
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
        "presentation_only": True,
        "static_frame": scene.frame_current,
        "driver_animation_exported": False,
        "physics_exported": False,
        "coordinate_conversion": "Blender Z-up source converted by Blender glTF exporter to glTF Y-up",
        "gltf_version": gltf.get("asset", {}).get("version"),
        "root_node": root_node,
        "pivot_nodes": pivot_nodes,
        "node_count": len(nodes),
        "mesh_count": len(gltf.get("meshes", [])),
        "material_count": len(gltf.get("materials", [])),
        "image_count": len(gltf.get("images", [])),
        "texture_count": len(gltf.get("textures", [])),
        "animation_count": len(gltf.get("animations", [])),
        "node_names": node_names,
        "missing_required_nodes": missing_required,
        "source_aircraft_object_count": len(model_names) + 1,
        "source_sha256": sha256_file(source_path),
    }


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=REPO_ROOT / ".tools" / "heli25")
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF)
    parser.add_argument("--export-preview", action="store_true",
                        help="export selected HX-700 source hierarchy to a static, presentation-only GLB under --out")
    parser.add_argument("--replace-preview", action="store_true",
                        help="replace only the generated hx700-preview.glb in --out; requires --export-preview")
    args = parser.parse_args(argv)
    if args.replace_preview and not args.export_preview:
        parser.error("--replace-preview requires --export-preview")
    return args


def main():
    args = parse_args()
    out_dir = args.out if args.out.is_absolute() else REPO_ROOT / args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    blend_path = Path(bpy.data.filepath).resolve()
    if not blend_path.exists():
        raise FileNotFoundError(f"Blender must open the source .blend first: {blend_path}")
    if blend_path != DEFAULT_BLEND.resolve():
        raise ValueError(f"Unexpected source file; expected {DEFAULT_BLEND.resolve()}, got {blend_path}")

    scene = bpy.context.scene
    depsgraph = bpy.context.evaluated_depsgraph_get()
    objects = sorted(scene.objects, key=lambda obj: obj.name.casefold())
    point_map = {}
    object_rows = []
    triangle_total = 0
    base_triangle_total = 0
    source_points = []
    type_counts = Counter(obj.type for obj in objects)
    for obj in objects:
        row = {
            "name": obj.name,
            "type": obj.type,
            "parent": obj.parent.name if obj.parent else None,
            "children": sorted(child.name for child in obj.children),
            "collections": sorted(collection.name for collection in obj.users_collection),
            "transform": transform_record(obj),
            "hide_viewport": bool(obj.hide_viewport),
            "hide_render": bool(obj.hide_render),
            "constraints": [{"name": constraint.name, "type": constraint.type} for constraint in obj.constraints],
            "modifiers": [{"name": modifier.name, "type": modifier.type, "show_viewport": modifier.show_viewport,
                           "show_render": modifier.show_render} for modifier in obj.modifiers],
            "custom_properties": property_values(obj),
        }
        if obj.type == "MESH":
            base_mesh = obj.data
            base_mesh.calc_loop_triangles()
            base_triangle_total += len(base_mesh.loop_triangles)
            mesh, points, triangles = evaluate_mesh(obj, depsgraph)
            point_map[obj.name] = points
            source_points.extend(points)
            triangle_total += triangles
            row["mesh"] = {
                "data_name": base_mesh.name,
                "vertices": len(mesh.vertices),
                "edges": len(mesh.edges),
                "polygons": len(mesh.polygons),
                "evaluated_triangles": triangles,
                "base_triangles": len(base_mesh.loop_triangles),
                "bounds_world": bounds(points),
                "materials": sorted({slot.material.name for slot in obj.material_slots if slot.material}),
            }
            obj.evaluated_get(depsgraph).to_mesh_clear()
        if obj.type == "ARMATURE":
            row["armature_bones"] = [{"name": bone.name, "parent": bone.parent.name if bone.parent else None}
                                     for bone in obj.data.bones]
        anim = obj.animation_data
        action = anim.action if anim else None
        action_curves = []
        action_curve_error = None
        if action:
            try:
                action_curves = [{"data_path": curve.data_path, "array_index": curve.array_index,
                                  "keyframes": len(curve.keyframe_points)} for curve in action.fcurves]
            except (AttributeError, RuntimeError, TypeError) as error:
                action_curve_error = f"{type(error).__name__}: {error}"
        row["animation"] = {
            "action": action.name if action else None,
            "action_curves": action_curves,
            "action_curve_error": action_curve_error,
            "drivers": len(anim.drivers) if anim else 0,
            "driver_details": driver_records(anim),
            "nla_tracks": len(anim.nla_tracks) if anim else 0,
        }
        bucket = name_bucket(obj.name)
        if bucket:
            row["rotor_candidate"] = bucket
        object_rows.append(row)

    material_rows = []
    material_user_counts = Counter()
    for obj in objects:
        for slot in obj.material_slots:
            if slot.material:
                material_user_counts[slot.material.name] += 1
    for material in sorted(bpy.data.materials, key=lambda item: item.name.casefold()):
        base_color = None
        principled = []
        if material.node_tree:
            for node in material.node_tree.nodes:
                if node.type == "BSDF_PRINCIPLED":
                    base = node.inputs.get("Base Color")
                    if base:
                        base_color = vector_json(base.default_value)
                    principled.append(node.name)
        material_rows.append({"name": material.name, "users": material_user_counts[material.name],
                              "use_nodes": material.node_tree is not None, "principled_nodes": principled,
                              "principled_base_color": base_color, "custom_properties": property_values(material)})

    image_rows = []
    for image in sorted(bpy.data.images, key=lambda item: item.name.casefold()):
        path = bpy.path.abspath(image.filepath) if image.filepath else ""
        packed_file = getattr(image, "packed_file", None)
        packed = bool(packed_file)
        image_rows.append({"name": image.name, "source": image.source, "filepath": image.filepath,
                           "resolved_path": path, "exists": bool(path and Path(path).exists()),
                           "packed": packed, "packed_size_bytes": packed_file.size if packed_file else 0,
                           "has_data": bool(image.has_data)})

    texts_dir = out_dir / "embedded-texts"
    embedded_texts = []
    for text in sorted(bpy.data.texts, key=lambda item: item.name.casefold()):
        body = text.as_string()
        payload = body.encode("utf-8")
        dest = texts_dir / Path(text.name).name
        texts_dir.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(payload)
        embedded_texts.append({"name": text.name, "characters": len(body), "sha256": hashlib.sha256(payload).hexdigest(),
                               "extracted_to": str(dest.relative_to(REPO_ROOT))})

    candidates = {"main_rotor": [], "tail_rotor": []}
    for obj in objects:
        bucket = name_bucket(obj.name)
        if bucket and obj.type == "MESH":
            candidates[bucket].append(obj)
    world_box = bounds(source_points)
    root = bpy.data.objects.get("HX-700")
    model_objects = descendants(root) if root else []
    model_names = {obj.name for obj in model_objects}
    model_points = [point for obj in model_objects for point in point_map.get(obj.name, [])]
    model_box = bounds(model_points)
    unit = scene.unit_settings
    rotor_pivot_names = {"main_rotor": "Pivote_Rotor_Principal", "tail_rotor": "Pivote_Rotor_Cola"}
    data = {
        "schema": "openrc-heli-asset-inventory-v1",
        "audit": {"read_only_source": True, "source_saved": False, "blender_version": bpy.app.version_string,
                  "script": Path(__file__).name},
        "source": {"path": str(blend_path.relative_to(REPO_ROOT)), "size_bytes": blend_path.stat().st_size,
                   "sha256": sha256_file(blend_path), "file_version": list(bpy.app.version),
                   "bpy_file_saved": bpy.data.is_saved, "project_filepath": bpy.data.filepath},
        "reference_pdf": {"path": str(args.pdf.resolve().relative_to(REPO_ROOT)), "size_bytes": args.pdf.stat().st_size,
                          "sha256": sha256_file(args.pdf), "purpose": "supplied reference; identity checked separately"},
        "scene": {"name": scene.name, "unit_system": unit.system, "scale_length": rounded(unit.scale_length),
                  "length_unit": unit.length_unit, "frame": scene.frame_current,
                  "bounds_all_scene_meshes_world_scene_units": world_box,
                  "object_count": len(objects), "object_type_counts": dict(sorted(type_counts.items())),
                  "evaluated_mesh_triangles": triangle_total, "base_mesh_triangles": base_triangle_total,
                  "collections": sorted(collection.name for collection in bpy.data.collections),
                  "custom_properties": property_values(scene)},
        "hierarchy": [{"name": obj.name, "type": obj.type, "parent": obj.parent.name if obj.parent else None,
                       "children": sorted(child.name for child in obj.children)} for obj in objects],
        "objects": object_rows,
        "aircraft": {"root_object": root.name if root else None,
                     "hierarchy_object_count_including_root": len(model_objects) + (1 if root else 0),
                     "mesh_object_names": [obj.name for obj in model_objects if obj.type == "MESH"],
                     "bounds_world_scene_units": model_box,
                     "dominant_bbox_axis": max("XYZ", key=lambda axis: model_box["size"]["XYZ".index(axis)]) if model_box else None,
                     "evaluated_mesh_triangles": sum(row["mesh"]["evaluated_triangles"] for row in object_rows
                                                     if row["name"] in model_names and "mesh" in row),
                     "base_mesh_triangles": sum(row["mesh"]["base_triangles"] for row in object_rows
                                                 if row["name"] in model_names and "mesh" in row)},
        "materials": material_rows,
        "images": image_rows,
        "embedded_texts": embedded_texts,
        "rotors": {key: assembly_estimate(value, point_map, bpy.data.objects.get(rotor_pivot_names[key]))
                   for key, value in candidates.items()},
        "animation_summary": {
            "armature_objects": [obj.name for obj in objects if obj.type == "ARMATURE"],
            "animated_objects": [row["name"] for row in object_rows if row["animation"]["action"] or row["animation"]["drivers"] or row["animation"]["nla_tracks"]],
            "objects_with_constraints": [row["name"] for row in object_rows if row["constraints"]],
            "shape_key_meshes": [obj.name for obj in objects if obj.type == "MESH" and obj.data.shape_keys],
        },
    }
    data["preview_renders"] = write_renders(scene, out_dir, model_box, model_names | {root.name} if root else model_names)
    if args.export_preview and not root:
        raise RuntimeError("The expected HX-700 hierarchy root was not found; preview export is unavailable")
    data["preview_export"] = export_preview(out_dir, blend_path, root, model_objects, model_names,
                                            replace_preview=args.replace_preview) if args.export_preview else None
    out_path = out_dir / "hx700-inventory.json"
    out_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"HX-700 inventory: {out_path}")
    print(f"Source SHA-256: {data['source']['sha256']}")
    print(f"Objects: {len(objects)}; evaluated triangles: {triangle_total}; materials: {len(material_rows)}")
    print("Rotor candidates:", json.dumps(data["rotors"], ensure_ascii=False))
    print("Preview renders:", ", ".join(data["preview_renders"]))


if __name__ == "__main__":
    main()
