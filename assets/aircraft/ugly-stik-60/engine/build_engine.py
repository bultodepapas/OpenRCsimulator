"""US-V13: runtime O.S. 61 SF engine for the Ugly Stik from the owner's Blender delivery.

Run with Blender 5.2.2 from the repository root:
    blender --background --factory-startup --python assets/aircraft/ugly-stik-60/engine/build_engine.py [-- --check]

Inputs are the delivery's real-time engine GLB (baked textures) and its O.S. 905 aircraft-mount GLB, pinned by
SHA-256 in source-manifest.json. The engine meshes are not remodelled. The mount keeps its beams, washers, lines and
grommets; its screws and lines are decimated, the grommets move inboard onto the Stik's narrower F1, and the stand-in
firewall and nose box are dropped because the Stik supplies its own F1. The body atlas is halved to 1024 px and every map is written as WebP.

Output frame (Godot, after the glTF Y-up conversion): metres, +X right, +Y up, -Z forward, origin on the crankshaft
axis at the drive-hub face that the propeller seats against. The builder (app/aircraft/ugly_stik_equipment.gd) places
it against the native propeller hub. Nodes:
  engine_assembly       every static part, one mesh with one surface per material
  engine_throttle_arm   carburettor lever, hub and screw, origin on the barrel axis (turns about +X)
  engine_drive_rear     crank nose and drive hub (spins with the propeller)
  engine_drive_front    propeller washer, nut and shaft end (spins with the propeller)
  engine_* empties      throttle-arm ball link, intake mouth/inner bore point, silencer outlet/upstream point, the
                        propeller washer face (the drive splits across the propeller seat) and the mount flange's
                        back face, which seats on the firewall
--check rebuilds into a temporary file and fails unless the bundled GLB and the build record match byte for byte.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
MANIFEST = HERE / "source-manifest.json"
RECORD = HERE / "engine-build.json"

# Mount-GLB parts kept, by name prefix; everything else in that file (the engine copy, the 90 mm plywood plate and the
# red nose box) is dropped. Values are Blender decimate (collapse) ratios; 1.0 keeps the part as delivered.
MOUNT_PARTS = {
    "BANC_Bancada_OS905": 1.0,
    "BANC_Letras_OS905": 1.0,
    "BANC_Arandela_M4_": 1.0,
    "BANC_Arandela_Presion_": 1.0,
    "BANC_Pasamuros_Goma_": 1.0,
    "BANC_Perno_Parallamas_M4x20_": 0.03,
    "BANC_Tornillo_Motor_M3_5x16_": 0.03,
    "BANC_Linea_Combustible": 0.12,
    "BANC_Linea_Presion": 0.12,
}
# Delivered parts that locate the lever, intake and drive split (mount-GLB frame, before the real-time offset).
LEVER_PARTS = ("CARB_Throttle_Arm", "CARB_Arm_Hub", "CARB_Arm_Screw")
LEVER_X_MAX = -0.0167  # the lever side of the barrel end; the carburettor body stops at x = -0.0164
BODY_ATLAS_PX = 1024
# The delivery's 90 mm firewall puts the line grommets 38 mm either side of the crank axis, outside the Stik's 78 mm F1.
# They move to the strip between the flange top (33 mm) and the F1 top (43 mm above the axis), at 80 % size, and the
# last 35 mm of each line bends after its grommet. Pairs are (grommet, line).
GROMMETS = (("BANC_Pasamuros_Goma_1", "BANC_Linea_Combustible"), ("BANC_Pasamuros_Goma_2", "BANC_Linea_Presion"))
GROMMET_X = 0.033
GROMMET_HEIGHT = 0.038
GROMMET_SCALE = 0.8
LINE_BEND = 0.035
# Godot re-encodes embedded images to Basis Universal on import; lossy WebP only shrinks the bundled file (glTF
# EXT_texture_webp), from 13 MB of PNG.
IMAGE_QUALITY = 90


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _inputs(manifest: dict) -> dict[str, Path]:
    root = ROOT / manifest["delivery_root"]
    paths = {}
    for key, entry in manifest["inputs"].items():
        path = root / entry["path"]
        if not path.is_file():
            raise FileNotFoundError(f"missing delivery input {path}")
        if _sha256(path) != entry["sha256"]:
            raise RuntimeError(f"delivery input changed: {path}")
        paths[key] = path
    return paths


def _import(path: Path) -> list[bpy.types.Object]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return sorted(set(bpy.data.objects) - before, key=lambda obj: obj.name)


def _bake_world(obj: bpy.types.Object) -> None:
    """Moves the world transform into single-user mesh data and leaves the object at the identity."""
    world = obj.matrix_world.copy()
    obj.parent = None
    if obj.type == "MESH":
        obj.data = obj.data.copy()
        obj.data.transform(world)
        obj.matrix_world = Matrix.Identity(4)
    else:
        obj.matrix_world = world


def _world_points(obj: bpy.types.Object) -> list[Vector]:
    return [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]


def _bounds(points: list[Vector]) -> tuple[Vector, Vector]:
    return (Vector([min(p[i] for p in points) for i in range(3)]), Vector([max(p[i] for p in points) for i in range(3)]))


def _triangles(obj: bpy.types.Object) -> int:
    return sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)


def _split(obj: bpy.types.Object, name: str, keep) -> bpy.types.Object:
    """Moves the faces whose centroid satisfies `keep` into a new object called `name`."""
    part = obj.copy()
    part.data = obj.data.copy()
    part.name = name
    part.data.name = name
    bpy.context.scene.collection.objects.link(part)
    for target, wanted in ((part, True), (obj, False)):
        mesh = bmesh.new()
        mesh.from_mesh(target.data)
        doomed = [face for face in mesh.faces if bool(keep(face.calc_center_median())) != wanted]
        bmesh.ops.delete(mesh, geom=doomed, context="FACES")
        mesh.to_mesh(target.data)
        mesh.free()
    if not part.data.polygons or not obj.data.polygons:
        raise RuntimeError(f"split {name} left an empty mesh")
    return part


def _decimate(obj: bpy.types.Object, ratio: float) -> None:
    modifier = obj.modifiers.new("decimate", "DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    obj.modifiers.clear()
    obj.data = mesh


def _repair_winding(obj: bpy.types.Object) -> int:
    """Reverses the few delivered or decimated triangles whose winding opposes their baked shading normals, keeping
    every corner's normal vector. Blender draws both sides, but Godot culls by winding, so these would be pinholes."""
    mesh = obj.data
    normals = [Vector(corner.vector) for corner in mesh.corner_normals]
    doomed = [polygon.index for polygon in mesh.polygons if polygon.area > 1e-12
        and polygon.normal.dot(sum((normals[i] for i in polygon.loop_indices), Vector())) <= 0.0]
    if not doomed:
        return 0
    kept = {(polygon.index, mesh.loops[i].vertex_index): normals[i] for polygon in mesh.polygons for i in polygon.loop_indices}
    edit = bmesh.new()
    edit.from_mesh(mesh)
    edit.faces.ensure_lookup_table()
    for index in doomed:
        edit.faces[index].normal_flip()
    edit.to_mesh(mesh)
    edit.free()
    mesh.normals_split_custom_set([kept[(polygon.index, mesh.loops[i].vertex_index)]
        for polygon in mesh.polygons for i in polygon.loop_indices])
    return len(doomed)


def _join(name: str, parts: list[bpy.types.Object]) -> bpy.types.Object:
    target = parts[0]
    with bpy.context.temp_override(active_object=target, selected_editable_objects=parts, selected_objects=parts):
        bpy.ops.object.join()
    target.name = name
    target.data.name = name
    return target


def _empty(name: str, location: Vector) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    obj.location = location
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _tree(obj: bpy.types.Object) -> BVHTree:
    return BVHTree.FromPolygons(_world_points(obj), [list(polygon.vertices) for polygon in obj.data.polygons])


def _free(tree: BVHTree, point: Vector, direction: Vector, far: float) -> float:
    hit = tree.ray_cast(point, direction, far)
    return hit[3] if hit[0] is not None else far


def _centred(tree: BVHTree, point: Vector, axis: Vector) -> tuple[Vector, float]:
    """Moves `point` to the middle of a round bore across `axis` by probing its walls; returns it and the bore radius."""
    u = axis.orthogonal().normalized()
    v = axis.cross(u).normalized()
    for _ in range(4):
        point = point + u * (_free(tree, point, u, 0.02) - _free(tree, point, -u, 0.02)) * 0.5
        point = point + v * (_free(tree, point, v, 0.02) - _free(tree, point, -v, 0.02)) * 0.5
    return point, sum(_free(tree, point, d, 0.02) for d in (u, -u, v, -v)) * 0.25


def _bore(tree: BVHTree, start: Vector, guess: Vector) -> tuple[Vector, Vector, float]:
    """Centre line of a straight round bore near `start` that opens towards `guess`: (mouth, outward axis, radius)."""
    a, _ = _centred(tree, start - guess * 0.004, guess)
    b, _ = _centred(tree, start + guess * 0.002, guess)
    axis = (b - a).normalized()
    centre, radius = _centred(tree, b, axis)
    # The mouth is where a ray across the bore first escapes the part.
    side = axis.orthogonal().normalized()
    travel = 0.0
    while _free(tree, centre + axis * travel, side, 0.03) < 0.015:
        travel += 0.0002
        if travel > 0.03:
            raise RuntimeError("bore never opens")
    return centre + axis * travel, axis, radius


def build(output: Path) -> dict:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    paths = _inputs(manifest)
    offset = Vector((0.0, 0.0, float(manifest["realtime_base_offset_m"])))
    bpy.ops.wm.read_factory_settings(use_empty=True)

    engine = {obj.name: obj for obj in _import(paths["engine_realtime"])}
    for obj in engine.values():
        _bake_world(obj)
    meshes = {name: obj for name, obj in engine.items() if obj.type == "MESH"}
    if sorted(meshes) != ["RT_Body", "RT_Carb", "RT_Drive", "RT_Head", "RT_Muffler"]:
        raise RuntimeError(f"unexpected real-time engine parts {sorted(meshes)}")
    source_triangles = sum(_triangles(obj) for obj in meshes.values())

    mount_objects = _import(paths["mount"])
    by_name = {obj.name: obj for obj in mount_objects}
    # The real-time export lifted the engine by its base offset; the mount file keeps the delivered frame.
    crankcase_floor = _bounds(_world_points(by_name["ENG_Crankcase"]))[0].z + offset.z
    if abs(_bounds(_world_points(meshes["RT_Body"]))[0].z - crankcase_floor) > 1e-4:
        raise RuntimeError("real-time engine and mount file no longer share a frame")
    lever_points = [p + offset for name in LEVER_PARTS for p in _world_points(by_name[name])]
    lever_low, lever_high = _bounds(lever_points)
    hub_points = [p + offset for p in _world_points(by_name["CARB_Arm_Hub"])]
    pivot = sum(hub_points, Vector()) / len(hub_points)
    arm_points = [p + offset for p in _world_points(by_name["CARB_Throttle_Arm"])]
    arm_floor = min(p.z for p in arm_points)
    # The ball-link hole is the ring of lever vertices 1.5 mm above the lever's lower end.
    link_ring = [p for p in arm_points if arm_floor + 0.0008 <= p.z <= arm_floor + 0.0035]
    lever_tip = Vector((pivot.x, sum(p.y for p in link_ring) / len(link_ring), arm_floor + 0.0023))
    # The intake bore opens upwards and leans towards the propeller; start 10 mm below the body's top, which is still
    # above the spray bar, because the slanted mouth lets side probes escape near its rim.
    carb_top = max(p.z for p in _world_points(by_name["CARB_Body"])) + offset.z
    intake_start = _bounds([p + offset for p in _world_points(by_name["CARB_Spray_Bar"])])
    intake_mouth, intake_axis, intake_radius = _bore(_tree(meshes["RT_Carb"]),
        Vector(((intake_start[0].x + intake_start[1].x) * 0.5, (intake_start[0].y + intake_start[1].y) * 0.5, carb_top - 0.010)),
        Vector((0.0, 0.0, 1.0)))
    intake_inner = intake_mouth - intake_axis * 0.008
    # The propeller seats between the drive-hub face and the washer; the round hub centres the crank axis.
    hub_low, hub_high = _bounds(_world_points(by_name["ENG_Drive_Hub"]))
    washer_face_y = _bounds(_world_points(by_name["ENG_Prop_Washer"]))[1].y
    hub_face_y = hub_low.y
    seat_y = (hub_face_y + washer_face_y) * 0.5
    shaft_z = (hub_low.z + hub_high.z) * 0.5 + offset.z

    kept = []
    for obj in mount_objects:
        ratio = next((value for prefix, value in MOUNT_PARTS.items() if obj.name.startswith(prefix)), None)
        if obj.type != "MESH" or ratio is None:
            continue
        _bake_world(obj)
        obj.data.transform(Matrix.Translation(offset))
        if ratio < 1.0:
            _decimate(obj, ratio)
        kept.append(obj)
    if len(kept) != 22:
        raise RuntimeError(f"expected 22 mount parts, kept {len(kept)}")
    for obj in mount_objects:
        if obj not in kept:
            bpy.data.objects.remove(obj, do_unlink=True)
    firewall_y = _bounds(_world_points(by_name["BANC_Bancada_OS905"]))[1].y
    moved = {}
    for grommet_name, line_name in GROMMETS:
        grommet_low, grommet_high = _bounds(_world_points(by_name[grommet_name]))
        old_centre = (grommet_low + grommet_high) * 0.5
        new_centre = Vector((math.copysign(GROMMET_X, old_centre.x), old_centre.y, shaft_z + GROMMET_HEIGHT))
        by_name[grommet_name].data.transform(
            Matrix.Translation(new_centre) @ Matrix.Scale(GROMMET_SCALE, 4) @ Matrix.Translation(-old_centre))
        shift = new_centre - old_centre
        for vertex in by_name[line_name].data.vertices:
            t = min(max((vertex.co.y - firewall_y + LINE_BEND) / LINE_BEND, 0.0), 1.0)
            vertex.co += shift * (t * t * (3.0 - 2.0 * t))
        moved[grommet_name] = [round(c, 5) for c in (-shift.x, shift.z, shift.y)]

    margin = Vector((0.0003, 0.0003, 0.0003))
    low, high = lever_low - margin, lever_high + margin

    def on_lever(c: Vector) -> bool:
        return c.x < LEVER_X_MAX and low.y <= c.y <= high.y and low.z <= c.z <= high.z

    lever = _split(meshes["RT_Carb"], "engine_throttle_arm", on_lever)
    drive_front = _split(meshes["RT_Drive"], "engine_drive_front", lambda c: c.y < seat_y)
    drive_rear = meshes["RT_Drive"]
    drive_rear.name = drive_rear.data.name = "engine_drive_rear"

    # The silencer ends in a plain round tube that turns slightly outboard; probe it from just inside its rim.
    muffler_points = _world_points(meshes["RT_Muffler"])
    tail = max(muffler_points, key=lambda p: p.y)
    rim = [p for p in muffler_points if p.y > tail.y - 0.0008]
    rim_low, rim_high = _bounds(rim)
    outlet, outlet_axis, outlet_radius = _bore(_tree(meshes["RT_Muffler"]),
        Vector(((rim_low.x + rim_high.x) * 0.5, tail.y - 0.004, (rim_low.z + rim_high.z) * 0.5)), Vector((0.0, 1.0, 0.0)))
    upstream = outlet - outlet_axis * 0.011

    for image in bpy.data.images:
        if image.name.startswith("T_Engine61_Body_") and tuple(image.size) != (BODY_ATLAS_PX, BODY_ATLAS_PX):
            image.scale(BODY_ATLAS_PX, BODY_ATLAS_PX)

    static = _join("engine_assembly", [meshes["RT_Body"], meshes["RT_Head"], meshes["RT_Carb"], meshes["RT_Muffler"]] + kept)
    # Delivered frame (-Y forward, +Z up, muffler on -X) -> Blender frame whose glTF export is the Godot output frame.
    frame = Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Translation((0.0, -hub_face_y, -shaft_z))
    flipped = {}
    for obj in (static, lever, drive_front, drive_rear):
        obj.data.transform(frame)
        flipped[obj.name] = _repair_winding(obj)
    lever_origin = frame @ pivot
    lever.data.transform(Matrix.Translation(-lever_origin))
    lever.location = lever_origin
    anchors = {
        "engine_throttle_arm_tip": frame @ lever_tip,
        "engine_intake_mouth": frame @ intake_mouth,
        "engine_intake_inner": frame @ intake_inner,
        "engine_exhaust_outlet": frame @ outlet,
        "engine_exhaust_upstream": frame @ upstream,
        "engine_washer_face": frame @ Vector((0.0, washer_face_y, shaft_z)),
        "engine_firewall_face": frame @ Vector((0.0, firewall_y, shaft_z)),
    }
    for root in [obj for obj in bpy.data.objects if obj.type == "EMPTY"]:
        bpy.data.objects.remove(root, do_unlink=True)
    empties = [_empty(name, location) for name, location in anchors.items()]

    nodes = [static, lever, drive_rear, drive_front]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in nodes + empties:
        obj.select_set(True)
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB", use_selection=True, export_yup=True,
        export_apply=False, export_animations=False, export_cameras=False, export_lights=False, export_extras=False,
        export_tangents=False, export_image_format="WEBP", export_image_quality=IMAGE_QUALITY,
        export_draco_mesh_compression_enable=False)

    def godot(v: Vector) -> list[float]:
        return [round(v.x, 6), round(v.z, 6), round(-v.y, 6)]

    return {
        "format": "openrc-stik-engine-build v1",
        "step": manifest["step"],
        "blender": bpy.app.version_string,
        "inputs": {key: manifest["inputs"][key]["sha256"] for key in sorted(manifest["inputs"])},
        "output": {"path": manifest["output"], "sha256": _sha256(output), "bytes": output.stat().st_size},
        "frame": "Godot metres, +X right, +Y up, -Z forward; origin on the crank axis at the drive-hub face",
        "delivered_shaft_height_m": round(shaft_z, 6),
        "propeller_seat_m": round(hub_face_y - washer_face_y, 6),
        "intake_bore_radius_m": round(intake_radius, 5),
        "outlet_bore_radius_m": round(outlet_radius, 5),
        "source_engine_triangles": source_triangles,
        "triangles": {obj.name: _triangles(obj) for obj in nodes},
        "winding_flipped": flipped,
        "grommet_shift_godot_m": moved,
        "materials": sorted(slot.material.name for slot in static.material_slots if slot.material),
        "throttle_arm_pivot": godot(lever_origin),
        "anchors": {name: godot(location) for name, location in anchors.items()},
        "body_atlas_px": BODY_ATLAS_PX,
    }


def main(argv: list[str]) -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    bundled = ROOT / manifest["output"]
    if "--check" in argv:
        with tempfile.TemporaryDirectory() as scratch:
            record = build(Path(scratch) / bundled.name)
            fresh = (Path(scratch) / bundled.name).read_bytes()
        stored = json.loads(RECORD.read_text(encoding="utf-8")) if RECORD.is_file() else None
        if not bundled.is_file() or bundled.read_bytes() != fresh or stored != record:
            print("Stik engine GLB or build record is stale; rerun build_engine.py")
            return 1
        print("Stik engine GLB and build record match the delivery")
        return 0
    record = build(bundled)
    RECORD.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {bundled} ({record['output']['bytes']} bytes) and {RECORD}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []))
