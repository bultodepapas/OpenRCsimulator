"""AV-31: prepare the supplied Avanti master for the common Godot model contract.

Run with the pinned Blender 5.2.2 executable, --background --python this_file.
The supplied master is immutable. No download or third-party Python package is needed.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = HERE / "source/avanti_s.blend"
TARGET = ROOT / "app/assets/aircraft/avanti-s-a200/avanti_s.glb"
GAME = HERE / "game/avanti_s_game.blend"
REVISION = "av31-blender-flight-1"
IDENTITY = "sebart-avanti-s-a200-p100rx"
NATIVE_TO_AUTHOR = Matrix.Rotation(math.pi, 4, "Z")
# Blender Z-up to glTF Y-up. The combined mapping is (-x, z, y), a proper rotation.
AUTHOR_TO_GLTF = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
CONTROL_NAMES = {
    "Aileron_L": "aileron_left", "Aileron_R": "aileron_right",
    "Elevator_L": "elevator_left", "Elevator_R": "elevator_right",
    "Rudder": "rudder", "Flap_L": "flap_left", "Flap_R": "flap_right",
}
SECTION = {"fuselage_core": "core", "cockpit": "core", "fuel_tank": "core",
           "wing_left_fixed": "wing_left", "wing_right_fixed": "wing_right",
           "horizontal_tail_fixed": "horizontal_tail", "vertical_tail_fixed": "vertical_tail",
           "canopy_glass": "canopy", "canopy_frame": "canopy", "gear_stowed": "gear",
           "turbine": "engine", "exhaust_pipe": "engine"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8", newline="\n")


def vector(value):
    return [round(float(x), 8) for x in value]


def control_section(key):
    if key.startswith(("aileron", "flap")):
        return "wing_left" if key.endswith("left") else "wing_right"
    return "vertical_tail" if key == "rudder" else "horizontal_tail"


def group_for(obj):
    name = obj.name
    # Control meshes and their attached horns only. A source servo body parented to a
    # hinge must not rotate with the control surface in the simulator.
    ancestor = obj
    while ancestor is not None:
        if ancestor.name in CONTROL_NAMES:
            return CONTROL_NAMES[ancestor.name]
        ancestor = ancestor.parent
    if name.startswith("Link_"):
        return None
    if name.startswith("Equip_Turbine_") or name.startswith("Equip_Mount_Turbine_"):
        return "turbine"
    if name == "Equip_Fuel_Tank":
        return "fuel_tank"
    if name.startswith("Equip_"):
        return None  # concealed hoses, cables, trays and electronics dominate the master
    if name.startswith("Exhaust_"):
        return "exhaust_pipe"
    if name.startswith(("NoseGear", "MainGear")):
        return "gear_stowed"
    if name == "Canopy_Glass":
        return "canopy_glass"
    if name.startswith("Canopy_"):
        return "canopy_frame"
    if name.startswith(("Cockpit_", "Instrument_", "Seat_", "Stick", "Throttle", "Glare_")):
        return "cockpit"
    if name.startswith(("Wing_", "Aileron_", "Flap_")):
        # Source L is native +X; after the proper rotation it is the pilot's left.
        if "_L" in name:
            return "wing_left_fixed"
        if "_R" in name:
            return "wing_right_fixed"
        return None  # hidden central spar
    if name.startswith(("Stabilizer_", "Stab_", "Elevator_")):
        return "horizontal_tail_fixed"
    if name.startswith(("Fin", "Rudder_")):
        return "vertical_tail_fixed"
    if name == "Fuselage" or name.startswith("Intake_"):
        return "fuselage_core"
    raise ValueError("Unclassified source mesh: " + name)


def triangle_count(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def simplify(obj):
    # Preserve the exterior texture coordinates and the authored hinge geometry.
    # Explicit per-object budgets keep small parts intact. All reduction is reversible
    # by re-exporting the master, and silhouette bounds are checked below.
    count = triangle_count(obj.data)
    cap = 32000 if obj.name == "Fuselage" else 11000 if obj.name.startswith("Wing_") else 7000 if obj.name.startswith("Canopy_") else 2500
    if count > cap:
        mod = obj.modifiers.new("GameTriangleBudget", "DECIMATE")
        mod.ratio = cap / count
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)


def main():
    if bpy.app.version != (5, 2, 2):
        raise RuntimeError("Export is qualified with Blender 5.2.2; found " + bpy.app.version_string)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene = bpy.context.scene
    original = bpy.data.objects["Avanti_S_A200"]
    source_objects = list(original.children_recursive)
    scene.frame_set(0)
    bpy.context.view_layer.update()
    control_rest = {key: bpy.data.objects[name + "_Hinge"].matrix_world.copy() for name, key in CONTROL_NAMES.items()}
    # The source animation contains the complete retract linkage. Bake its accepted
    # up pose; no visual gear state is invented independently of the no-gear physics.
    scene.frame_set(211)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    objects = []
    source_triangles = 0
    source_bounds = []
    for obj in sorted(source_objects, key=lambda x: x.name):
        if obj.type != "MESH":
            continue
        group = group_for(obj)
        if group is None:
            continue
        evaluated = obj.evaluated_get(deps)
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=deps)
        world = NATIVE_TO_AUTHOR @ evaluated.matrix_world
        mesh.transform(world)
        source_triangles += triangle_count(mesh)
        source_bounds.extend(AUTHOR_TO_GLTF @ v.co for v in mesh.vertices)
        objects.append((obj.name, group, mesh))
    # All source objects have been evaluated; deleting from this isolated process
    # cannot alter the supplied master or the user's live Blender scene.
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    scene.frame_set(0)
    root = bpy.data.objects.new("VentageJet", None)
    scene.collection.objects.link(root)
    root["openrc_asset"] = IDENTITY
    root["openrc_revision"] = REVISION
    pivots = {}
    for key, rest in control_rest.items():
        pivot = bpy.data.objects.new(key + "_hinge", None)
        scene.collection.objects.link(pivot)
        pivot.parent = root
        pivot.matrix_world = NATIVE_TO_AUTHOR @ rest
        pivot["openrc_section"] = control_section(key)
        pivots[key] = pivot
    groups = {}
    for name, group, mesh in objects:
        obj = bpy.data.objects.new(name, mesh)
        scene.collection.objects.link(obj)
        simplify(obj)
        groups.setdefault(group, []).append(obj)
    final = []
    for group, items in sorted(groups.items()):
        bpy.ops.object.select_all(action="DESELECT")
        for obj in items:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = items[0]
        if len(items) > 1:
            bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        obj.name = group
        obj.data.name = group + "_mesh"
        parent = pivots.get(group, root)
        local = parent.matrix_world.inverted()
        obj.data.transform(local)
        obj.parent = parent
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = Matrix.Identity(4)
        obj["openrc_section"] = control_section(group) if group in pivots else SECTION[group]
        final.append(obj)
    bpy.context.view_layer.update()
    # 2k maximum dimension retains the delivered livery while avoiding 4k maps on
    # this 2 m model. Packed images make the game .blend and GLB self-contained.
    for img in bpy.data.images:
        if max(img.size) > 2048:
            ratio = 2048 / max(img.size)
            img.scale(round(img.size[0] * ratio), round(img.size[1] * ratio))
        if img.has_data:
            img.pack()
    bounds = [AUTHOR_TO_GLTF @ obj.matrix_world @ v.co for obj in final for v in obj.data.vertices]
    minimum = Vector(tuple(min(v[i] for v in bounds) for i in range(3)))
    maximum = Vector(tuple(max(v[i] for v in bounds) for i in range(3)))
    source_min = Vector(tuple(min(v[i] for v in source_bounds) for i in range(3)))
    source_max = Vector(tuple(max(v[i] for v in source_bounds) for i in range(3)))
    assert (minimum - source_min).length < 0.002 and (maximum - source_max).length < 0.002, "Simplification changed extremal silhouette"
    assert abs(minimum.x + maximum.x) < 0.0005 and 1.99 < maximum.x - minimum.x < 2.01
    assert minimum.z < -0.93 and maximum.z > 1.28, "Incorrect nose/tail orientation"
    articulations = {}
    for key, pivot in pivots.items():
        transform = AUTHOR_TO_GLTF @ pivot.matrix_world @ AUTHOR_TO_GLTF.inverted()
        obj = next(o for o in final if o.name == key)
        points = [AUTHOR_TO_GLTF @ obj.matrix_world @ v.co for v in obj.data.vertices]
        witness = max(points, key=lambda p: p.z)
        axis = transform.to_3x3().col[0]
        delta = axis.cross(witness - transform.translation)
        direction = Vector((1, 0, 0)) if key == "rudder" else Vector((0, -1 if key.startswith("flap") else 1, 0))
        assert abs(delta.dot(direction)) > 0.005, (key, "degenerate trailing-edge witness")
        articulations[pivot.name] = {
            "node": pivot.name, "parent": root.name,
            "rest_translation": vector(transform.translation),
            "rest_basis": [vector(transform.to_3x3().col[i]) for i in range(3)],
            "range_deg": [0, 50] if key.startswith("flap") else [-25, 30] if key.startswith("aileron") else [-30, 30],
            "app_sign": 1 if delta.dot(direction) > 0 else -1,
            "positive": "trailing edge right" if key == "rudder" else "trailing edge down" if key.startswith("flap") else "trailing edge up",
            "witness_model": vector(witness),
        }
    # Store actual scene observations independently of the old physical surrogate.
    delivered = json.loads((HERE / "source/geometry_blender.json").read_text(encoding="utf-8"))
    nozzle_y, nozzle_z = delivered["installation"]["nozzle_center_yz"]
    geometry = {
        "schema": "openrc-avanti-blender-model-v1", "catalog_id": IDENTITY,
        "revision": REVISION, "source_alias": "User-supplied Avanti S A200 Blender master",
        "status": "Imported Blender presentation; experimental P100-RX physics; gear stowed, flaps visual-only.",
        "units": "m", "axes": {"nose": "-Z", "right": "+X", "up": "+Y"},
        "nominal": delivered["nominal"], "datum": delivered["datum"],
        "bounds": {"min": vector(minimum), "max": vector(maximum)},
        "articulations": articulations,
        "turbine": {"model": "JetCat P100-RX", "outlet_position": [0, nozzle_y, nozzle_z],
                    "outlet_direction": [0, 0, 1], "physical_source": "research/avanti-s/av06/inputs.json",
                    "geometry_evidence": "User-authored installation estimate, not a measured P100-RX installation."},
        "gear_pose": {"state": "stowed", "source_action": "GearRetract", "source_frame": 211},
    }
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    # Export only the aircraft, with no demo actions, cameras or lighting.
    export_options = dict(filepath=str(TARGET), export_format="GLB", use_selection=True,
                          export_yup=True, export_apply=True, export_animations=False,
                          export_extras=True, export_cameras=False, export_lights=False)
    bpy.ops.export_scene.gltf(**export_options)
    write_json(HERE / "blender-geometry.json", geometry)
    # The GLB is authoritative for game triangle/material counts (UV seams add vertices).
    import struct
    raw = TARGET.read_bytes()
    gltf = json.loads(raw[20:20 + struct.unpack_from("<I", raw, 12)[0]])
    triangles = sum(gltf["accessors"][p["indices"]]["count"] // 3 for m in gltf["meshes"] for p in m["primitives"])
    assert triangles < 150000, triangles
    manifest = {
        "schema": "openrc-avanti-blender-source-v1", "revision": REVISION,
        "blender_version": bpy.app.version_string, "blender_build_hash": bpy.app.build_hash.decode(),
        "source_blend_sha256": digest(SOURCE),
        "source_geometry_sha256": digest(HERE / "source/geometry_blender.json"),
        "asset_sha256": digest(TARGET), "asset_bytes": len(raw),
        "selected_source_triangles": source_triangles, "game_triangles": triangles,
        "mesh_nodes": len(gltf["meshes"]), "material_surfaces": sum(len(m["primitives"]) for m in gltf["meshes"]),
        "materials": len(gltf["materials"]), "textures": len(gltf.get("images", [])),
        "source_bounds": {"min": vector(source_min), "max": vector(source_max)},
        "game_bounds": geometry["bounds"], "native_to_godot": "(-x, z, y), metres; proper rotation, no scale",
        "gear_pose": geometry["gear_pose"], "export_options": {k: v for k, v in export_options.items() if k != "filepath"},
        "physical_validation": False,
    }
    write_json(HERE / "source-manifest.json", manifest)
    # Keep a usable, editable prepared file with packed textures. Root coordinates in
    # this file are Blender Z-up, nose +Y; export_yup converts it to nose -Z.
    for area in bpy.context.screen.areas if bpy.context.screen else []:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_distance = 3.0
            area.spaces.active.region_3d.view_location = Vector((0, -0.18, 0.1))
    GAME.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(GAME), compress=True)
    print("AV31_EXPORT_OK " + json.dumps(manifest))


if __name__ == "__main__":
    main()
