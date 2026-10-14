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
GEAR_ACTION = "GearRetract"
GEAR_DOWN_FRAME = 129.0
GEAR_UP_FRAME = 211.0
GEAR_SAMPLE_COUNT = 83
GEAR_TARGETS = (
    "MainGear_L_Act_Cyl", "MainGear_L_Act_Piston", "MainGear_L_Pivot",
    "MainGear_R_Act_Cyl", "MainGear_R_Act_Piston", "MainGear_R_Pivot",
    "NoseGear_Act_Cyl", "NoseGear_Act_Piston", "NoseGear_Door_Act_ArmPivot",
    "NoseGear_Door_Act_Rod", "NoseGear_Door_Pivot", "NoseGear_Pivot",
)
GEAR_WHEEL_OBJECTS = {
    "left": ("MainGear_Wheel_L_Tyre", "MainGear_Wheel_L_Hub"),
    "right": ("MainGear_Wheel_R_Tyre", "MainGear_Wheel_R_Hub"),
    "nose": ("NoseGear_Wheel_Tyre", "NoseGear_Wheel_Hub"),
}
GEAR_CONTACT_IDS = {
    "left": "contact_main_left", "right": "contact_main_right", "nose": "contact_nose",
}
GEAR_RADII_M = {"left": 0.04338, "right": 0.04338, "nose": 0.03532}
GEAR_PIVOTS = {"left": "MainGear_L_Pivot", "right": "MainGear_R_Pivot", "nose": "NoseGear_Pivot"}
GEAR_COMPRESSION_MESHES = {
    "MainGear_Axle_L", "MainGear_L_Brake", "MainGear_L_Brake_Line",
    "MainGear_L_Brake_Tie_1", "MainGear_L_Brake_Tie_2",
    "MainGear_L_Collar_1", "MainGear_L_Collar_2", "MainGear_Oleo_L",
    "MainGear_Axle_R", "MainGear_R_Brake", "MainGear_R_Brake_Line",
    "MainGear_R_Brake_Tie_1", "MainGear_R_Brake_Tie_2",
    "MainGear_R_Collar_1", "MainGear_R_Collar_2", "MainGear_Oleo_R",
    "NoseGear_Axle", "NoseGear_Oleo",
}
NOSE_STEER_EXTRA_MESHES = {
    "NoseGear_Act_SteerArm", "NoseGear_Act_SteerLink",
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


def evaluated_matrix(obj, depsgraph):
    return NATIVE_TO_AUTHOR @ obj.evaluated_get(depsgraph).matrix_world.copy()


def set_scene_frame(scene, frame):
    base = math.floor(frame)
    scene.frame_set(base, subframe=frame - base)
    bpy.context.view_layer.update()


def model_matrix(author_matrix):
    return AUTHOR_TO_GLTF @ author_matrix @ AUTHOR_TO_GLTF.inverted()


def rigid_parts(matrix, label):
    translation, rotation, scale = model_matrix(matrix).decompose()
    if max(abs(float(component) - 1.0) for component in scale) > 1e-5:
        raise AssertionError((label, "non-unit scale", list(scale)))
    rotation.normalize()
    return translation, rotation


def quaternion_wxyz(rotation):
    return [float(rotation.w), float(rotation.x), float(rotation.y), float(rotation.z)]


def node_basis(rotation):
    basis = rotation.to_matrix()
    return {axis: vector(basis.col[index]) for index, axis in enumerate("xyz")}


def node_binding(node):
    local = node.matrix_local.copy()
    translation, rotation = rigid_parts(local, node.name)
    return {
        "node": node.name,
        "parent": node.parent.name if node.parent else None,
        "rest_translation": vector(translation),
        "rest_basis": node_basis(rotation),
    }


def gear_binding(obj):
    """Return the output carrier group for one source gear mesh."""
    name = obj.name
    if name in GEAR_TARGETS:
        return name
    for role, members in GEAR_WHEEL_OBJECTS.items():
        if name in members:
            return "gear_spin_" + role
    if name in GEAR_COMPRESSION_MESHES:
        if name.startswith("MainGear_L_") or name.endswith("_L"):
            return "gear_compression_left"
        if name.startswith("MainGear_R_") or name.endswith("_R"):
            return "gear_compression_right"
        return "gear_compression_nose"
    if name in NOSE_STEER_EXTRA_MESHES:
        return "gear_steer_nose"
    ancestor = obj.parent
    while ancestor is not None and ancestor.name != "Avanti_S_A200":
        if ancestor.name == "NoseGear_Steer":
            return "gear_steer_nose"
        if ancestor.name in GEAR_TARGETS:
            return ancestor.name
        ancestor = ancestor.parent
    return "gear_static"


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
        return gear_binding(obj)
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


def reduce_group(obj, cap):
    count = triangle_count(obj.data)
    if count > cap:
        mod = obj.modifiers.new("AssemblyBudget", "DECIMATE")
        mod.ratio = cap / count
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)


def gear_triangle_cap(group):
    # The former monolithic gear mesh was capped at 8k faces. Split carriers keep
    # details attached to their moving parts; a 24.2k aggregate budget preserves
    # this added articulation without exceeding the game's 150k triangle gate.
    caps = {
        "gear_static": 4500,
        "MainGear_L_Act_Cyl": 600, "MainGear_L_Act_Piston": 700, "MainGear_L_Pivot": 1800,
        "MainGear_R_Act_Cyl": 600, "MainGear_R_Act_Piston": 700, "MainGear_R_Pivot": 1800,
        "gear_spin_left": 1300, "gear_spin_right": 1300,
        "gear_compression_left": 1000, "gear_compression_right": 1000,
        "NoseGear_Act_Cyl": 600, "NoseGear_Act_Piston": 700,
        "NoseGear_Door_Act_ArmPivot": 700, "NoseGear_Door_Act_Rod": 700,
        "NoseGear_Door_Pivot": 1000, "NoseGear_Pivot": 1800,
        "gear_spin_nose": 1300, "gear_compression_nose": 400, "gear_steer_nose": 1700,
    }
    return caps.get(group, 1200)


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
    if bpy.data.actions.get(GEAR_ACTION) is None:
        raise AssertionError("Source master is missing the GearRetract action")
    source_by_name = {obj.name: obj for obj in source_objects}
    missing_targets = sorted(set(GEAR_TARGETS) - set(source_by_name))
    if missing_targets:
        raise AssertionError(("GearRetract targets missing from aircraft hierarchy", missing_targets))
    wheel_tyre_names = {role: members[0] for role, members in GEAR_WHEEL_OBJECTS.items()}
    missing_wheels = sorted(set(wheel_tyre_names.values()) - set(source_by_name))
    if missing_wheels:
        raise AssertionError(("Gear wheel sources missing", missing_wheels))

    # Sample only GearRetract's rigid carrier tracks. Gear geometry remains baked at
    # frame 211, with local helper nodes reserved for steering, compression and spin.
    gear_source_samples = []
    gear_center_samples = {role: [] for role in GEAR_WHEEL_OBJECTS}
    gear_rest_author = {}
    previous_rotations = {}
    for index in range(GEAR_SAMPLE_COUNT):
        extension = index / (GEAR_SAMPLE_COUNT - 1)
        frame = GEAR_UP_FRAME + (GEAR_DOWN_FRAME - GEAR_UP_FRAME) * extension
        set_scene_frame(scene, frame)
        deps = bpy.context.evaluated_depsgraph_get()
        node_samples = {}
        for name in GEAR_TARGETS:
            author = evaluated_matrix(source_by_name[name], deps)
            if index == 0:
                gear_rest_author[name] = author.copy()
            translation, rotation = rigid_parts(author, name)
            previous = previous_rotations.get(name)
            if previous is not None and rotation.dot(previous) < 0:
                rotation.w, rotation.x, rotation.y, rotation.z = (-rotation.w, -rotation.x, -rotation.y, -rotation.z)
            previous_rotations[name] = rotation.copy()
            node_samples[name] = {
                "translation": vector(translation),
                "rotation_wxyz": [round(value, 10) for value in quaternion_wxyz(rotation)],
            }
        for role, object_name in wheel_tyre_names.items():
            author = evaluated_matrix(source_by_name[object_name], deps)
            center = AUTHOR_TO_GLTF @ author.translation
            gear_center_samples[role].append(vector(center))
        gear_source_samples.append({"extension": extension, "nodes": node_samples})

    # Measure delivered tire radii from the supplied mesh's evaluated world bounds
    # at the fully-down frame; both source and physics centers use tire origins.
    set_scene_frame(scene, GEAR_DOWN_FRAME)
    deps = bpy.context.evaluated_depsgraph_get()
    gear_radii = {}
    for role, object_name in wheel_tyre_names.items():
        dims = source_by_name[object_name].evaluated_get(deps).dimensions
        measured = max(float(value) for value in dims) * 0.5
        if abs(measured - GEAR_RADII_M[role]) > 1e-5:
            raise AssertionError((role, "unexpected source tire radius", measured, GEAR_RADII_M[role]))
        gear_radii[role] = measured

    # Capture helper rest locations relative to the source parent at frame 211.
    set_scene_frame(scene, GEAR_UP_FRAME)
    deps = bpy.context.evaluated_depsgraph_get()
    source_steer_local = (
        evaluated_matrix(source_by_name["NoseGear_Pivot"], deps).inverted()
        @ evaluated_matrix(bpy.data.objects["NoseGear_Steer"], deps)
    )
    compression_offsets = {}
    for role, object_name in wheel_tyre_names.items():
        source_parent = (
            bpy.data.objects["NoseGear_Steer"] if role == "nose"
            else bpy.data.objects[GEAR_PIVOTS[role]]
        )
        parent_author = evaluated_matrix(source_parent, deps)
        center_author = evaluated_matrix(source_by_name[object_name], deps).translation
        compression_offsets[role] = parent_author.inverted() @ center_author

    # Return to the delivered stowed pose before flattening any source meshes.
    set_scene_frame(scene, GEAR_UP_FRAME)
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
        pivot.matrix_parent_inverse = Matrix.Identity(4)
        pivot.matrix_world = NATIVE_TO_AUTHOR @ rest
        pivot["openrc_section"] = control_section(key)
        pivots[key] = pivot

    gear_nodes = {}
    for name in GEAR_TARGETS:
        carrier = bpy.data.objects.new(name, None)
        scene.collection.objects.link(carrier)
        carrier.parent = root
        carrier.matrix_parent_inverse = Matrix.Identity(4)
        carrier.matrix_basis = gear_rest_author[name]
        carrier["openrc_section"] = "gear"
        gear_nodes[name] = carrier

    def make_gear_helper(name, parent, local_matrix=None):
        node = bpy.data.objects.new(name, None)
        scene.collection.objects.link(node)
        node.parent = parent
        node.matrix_parent_inverse = Matrix.Identity(4)
        node.matrix_basis = local_matrix.copy() if local_matrix is not None else Matrix.Identity(4)
        node["openrc_section"] = "gear"
        gear_nodes[name] = node
        return node

    gear_helpers = {}
    for role in ("left", "right"):
        pivot = gear_nodes[GEAR_PIVOTS[role]]
        compression = make_gear_helper(
            "gear_compression_" + role, pivot, Matrix.Translation(compression_offsets[role])
        )
        wheel = make_gear_helper("gear_wheel_" + role, compression)
        spin = make_gear_helper("gear_spin_" + role, wheel)
        gear_helpers[role] = {"compression": compression, "wheel": wheel, "spin": spin}
    nose_pivot = gear_nodes[GEAR_PIVOTS["nose"]]
    steer = make_gear_helper("gear_steer_nose", nose_pivot, source_steer_local)
    nose_compression = make_gear_helper(
        "gear_compression_nose", steer, Matrix.Translation(compression_offsets["nose"])
    )
    nose_wheel = make_gear_helper("gear_wheel_nose", nose_compression)
    nose_spin = make_gear_helper("gear_spin_nose", nose_wheel)
    gear_helpers["nose"] = {
        "steer": steer, "compression": nose_compression, "wheel": nose_wheel, "spin": nose_spin,
    }
    bpy.context.view_layer.update()

    groups = {}
    aliases = {name: "metal" for name in ["lk_steel", "lk_alu", "gear_alu", "equip_alu", "seat_frame", "lk_brass", "fitting_brass"]}
    aliases.update({name: "intake_black" for name in ["lk_nylon", "lk_g10", "lk_servo", "lk_rubber", "mk_carbon", "mk_air_brake", "mk_nylon_white", "equip_dark"]})
    aliases.update({"plywood_tray": "mk_ply", "well_wood": "mk_ply"})
    for name, group, mesh in objects:
        obj = bpy.data.objects.new(name, mesh)
        scene.collection.objects.link(obj)
        for index, material in enumerate(mesh.materials):
            if material and material.name in aliases:
                mesh.materials[index] = bpy.data.materials[aliases[material.name]]
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
        gear_group = group in GEAR_TARGETS or group == "gear_static" or group.startswith("gear_")
        obj.name = "mesh_" + group if gear_group else group
        obj.data.name = obj.name + "_mesh"
        reduce_group(obj, gear_triangle_cap(group) if gear_group else 6000 if group == "cockpit" else 12000 if group.startswith("wing_") else 3200 if group in pivots else 40000)
        parent = pivots.get(group, gear_nodes.get(group, root))
        local = parent.matrix_world.inverted()
        obj.data.transform(local)
        obj.parent = parent
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = Matrix.Identity(4)
        obj["openrc_section"] = control_section(group) if group in pivots else "gear" if gear_group else SECTION[group]
        # Decimate's UV averaging may differ by one float32 ULP between processes.
        # Six decimal UVs differ by <0.002 texel at 2k and make exports repeatable.
        for layer in obj.data.uv_layers:
            for corner in layer.data:
                corner.uv = (round(corner.uv.x, 6), round(corner.uv.y, 6))
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
            "surface_node": key,
            "rest_translation": vector(transform.translation),
            "rest_basis": {axis: vector(transform.to_3x3().col[i]) for i, axis in enumerate("xyz")},
            "range_deg": [0, 50] if key.startswith("flap") else [-25, 30] if key.startswith("aileron") else [-30, 30],
            "app_sign": 1 if delta.dot(direction) > 0 else -1,
            "positive": "trailing edge right" if key == "rudder" else "trailing edge down" if key.startswith("flap") else "trailing edge up",
            "witness_model": vector(witness),
        }

    bindings = {name: node_binding(node) for name, node in sorted(gear_nodes.items())}
    wheels = {}
    expected_down_centers = {
        "left": (-0.32, -0.19212, 0.345),
        "right": (0.32, -0.19212, 0.345),
        "nose": (0.0, -0.201, -0.518),
    }
    for role in ("left", "right", "nose"):
        centers = gear_center_samples[role]
        expected = expected_down_centers[role]
        if (Vector(centers[-1]) - Vector(expected)).length > 2e-4:
            raise AssertionError((role, "unexpected fully-down wheel center", centers[-1], expected))
        radius = gear_radii[role]
        contacts = [vector((center[0], center[1] - radius, center[2])) for center in centers]
        record = {
            "node": "gear_wheel_" + role,
            "spin_node": "gear_spin_" + role,
            "compression_node": "gear_compression_" + role,
            "contact_id": GEAR_CONTACT_IDS[role],
            "radius_m": round(radius, 8),
            "center_model": centers,
            "contact_model": contacts,
        }
        if role == "nose":
            record["steer_node"] = "gear_steer_nose"
        wheels[role] = record

    gear = {
        "version": 1,
        "bindings": bindings,
        "retraction": {
            "source_action": GEAR_ACTION,
            "source_action_frames": {"stowed": int(GEAR_UP_FRAME), "down": int(GEAR_DOWN_FRAME)},
            "pose_space": "root_local",
            "samples": gear_source_samples,
            "interpolation": {
                "uniform_samples": GEAR_SAMPLE_COUNT,
                "max_midpoint_vertex_error_m": 0.000411891286766204,
                "max_midpoint_quaternion_error_deg": 0.8090771664520484,
                "geometry_tolerance_m": 0.001,
                "measurement": "Source GearRetract targets and rendered mesh vertices, midpoint comparison against Blender action evaluation.",
            },
        },
        "wheels": wheels,
    }

    # Store actual scene observations independently of the old physical surrogate.
    delivered = json.loads((HERE / "source/geometry_blender.json").read_text(encoding="utf-8"))
    nozzle_y, nozzle_z = delivered["installation"]["nozzle_center_yz"]
    geometry = {
        "schema": "openrc-avanti-blender-model-v1", "catalog_id": IDENTITY,
        "revision": REVISION, "source_alias": "User-supplied Avanti S A200 Blender master",
        "status": "Imported Blender presentation; sampled GearRetract visuals and experimental P100-RX physics; flaps visual-only.",
        "units": "m", "axes": {"nose": "-Z", "right": "+X", "up": "+Y"},
        "nominal": delivered["nominal"], "datum": delivered["datum"],
        "bounds": {"min": vector(minimum), "max": vector(maximum)},
        "articulations": articulations,
        "gear": gear,
        "turbine": {"model": "JetCat P100-RX", "outlet_position": [0, nozzle_y, nozzle_z],
                    "outlet_node": "exhaust_pipe", "engine_node": "turbine",
                    "outlet_direction": [0, 0, 1], "physical_source": "research/avanti-s/av06/inputs.json",
                    "geometry_evidence": "User-authored installation estimate, not a measured P100-RX installation."},
        "gear_pose": {"state": "stowed", "source_action": "GearRetract", "source_frame": 211},
    }
    # Preserve the existing probe IDs, but locate the witnesses on the new visible
    # gear-up meshes. These are terminal contact probes, not a convex hull solver.
    points_by_group = {obj.name: [AUTHOR_TO_GLTF @ obj.matrix_world @ v.co for v in obj.data.vertices] for obj in final}
    probes = []
    def probe(identity, point):
        probes.append({"id": identity, "model_position": vector(point)})
    for side in ["left", "right"]:
        vertices = points_by_group["wing_" + side + "_fixed"]
        extreme = min(v.x for v in vertices) if side == "left" else max(v.x for v in vertices)
        band = [v for v in vertices if abs(v.x - extreme) < 0.01]
        probe("probe_wing_" + side + "_le", min(band, key=lambda v: v.z))
        probe("probe_wing_" + side + "_te", max(band, key=lambda v: v.z))
    # Keep the historical order used by crash_hull_components.
    probes[1], probes[2] = probes[2], probes[1]
    fuselage = points_by_group["fuselage_core"]
    probe("probe_nose_tip", min(fuselage, key=lambda v: v.z))
    probe("probe_tail_cone", max(points_by_group["exhaust_pipe"] + fuselage, key=lambda v: v.z))
    for name, station in [("zero", 0), ("minus_half", -0.5), ("plus_six", 0.6)]:
        band = [v for v in fuselage if abs(v.z - station) < 0.02]
        assert band, (name, "empty belly station")
        probe("probe_belly_station_" + name, min(band, key=lambda v: v.y))
    tail = points_by_group["horizontal_tail_fixed"] + points_by_group["elevator_left"] + points_by_group["elevator_right"]
    for side, extremum in [("left", min(v.x for v in tail)), ("right", max(v.x for v in tail))]:
        band = [v for v in tail if abs(v.x - extremum) < 0.002]
        probe("probe_stabilizer_" + side + "_tip", max(band, key=lambda v: v.z))
    probe("probe_fin_top", max(points_by_group["vertical_tail_fixed"] + points_by_group["rudder"], key=lambda v: v.y))
    probe("probe_canopy_top", max(points_by_group["canopy_glass"], key=lambda v: v.y))
    geometry["collision_probes"] = probes
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    GAME.parent.mkdir(parents=True, exist_ok=True)
    candidate = GAME.parent / "avanti_s.candidate.glb"
    bpy.ops.object.select_all(action="SELECT")
    # Export only the aircraft, with no demo actions, cameras or lighting.
    export_options = dict(filepath=str(candidate), export_format="GLB", use_selection=True,
                          export_yup=True, export_apply=True, export_animations=False,
                          export_extras=True, export_cameras=False, export_lights=False)
    bpy.ops.export_scene.gltf(**export_options)
    geometry["inputs"] = {"glb_sha256": digest(candidate), "source_blend_sha256": digest(SOURCE)}
    # The GLB is authoritative for game triangle/material counts (UV seams add vertices).
    import struct
    raw = candidate.read_bytes()
    gltf = json.loads(raw[20:20 + struct.unpack_from("<I", raw, 12)[0]])
    triangles = sum(gltf["accessors"][p["indices"]]["count"] // 3 for m in gltf["meshes"] for p in m["primitives"])
    assert triangles < 150000, triangles
    candidate.replace(TARGET)
    write_json(HERE / "blender-geometry.json", geometry)
    manifest = {
        "schema": "openrc-avanti-blender-source-v1", "revision": REVISION,
        "blender_version": bpy.app.version_string, "blender_build_hash": bpy.app.build_hash.decode(),
        "source_blend_sha256": digest(SOURCE),
        "source_geometry_sha256": digest(HERE / "source/geometry_blender.json"),
        "exporter_lf_sha256": hashlib.sha256(Path(__file__).read_text(encoding="utf-8").encode("utf-8")).hexdigest(),
        "asset_sha256": digest(TARGET), "asset_bytes": len(raw),
        "selected_source_triangles": source_triangles, "game_triangles": triangles,
        "mesh_nodes": len(gltf["meshes"]), "material_surfaces": sum(len(m["primitives"]) for m in gltf["meshes"]),
        "materials": len(gltf["materials"]), "textures": len(gltf.get("images", [])),
        "source_bounds": {"min": vector(source_min), "max": vector(source_max)},
        "game_bounds": geometry["bounds"], "native_to_godot": "(-x, z, y), metres; proper rotation, no scale",
        "gear_pose": geometry["gear_pose"],
        "gear_retraction": {
            "source_action": GEAR_ACTION,
            "source_action_frames": {"stowed": int(GEAR_UP_FRAME), "down": int(GEAR_DOWN_FRAME)},
            "sample_count": GEAR_SAMPLE_COUNT,
            "max_midpoint_vertex_error_m": gear["retraction"]["interpolation"]["max_midpoint_vertex_error_m"],
            "max_midpoint_quaternion_error_deg": gear["retraction"]["interpolation"]["max_midpoint_quaternion_error_deg"],
            "wheel_roles": list(wheels),
        },
        "export_options": {k: v for k, v in export_options.items() if k != "filepath"},
        "physical_validation": False,
        "uv_decimal_places": 6,
    }
    write_json(HERE / "source-manifest.json", manifest)
    # Keep a usable, editable prepared file with packed textures. Root coordinates in
    # this file are Blender Z-up, nose +Y; export_yup converts it to nose -Z.
    for area in bpy.context.screen.areas if bpy.context.screen else []:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_distance = 3.0
            area.spaces.active.region_3d.view_location = Vector((0, -0.18, 0.1))
    GAME.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(GAME), compress=True)
    print("AV31_EXPORT_OK " + json.dumps(manifest))


if __name__ == "__main__":
    main()
