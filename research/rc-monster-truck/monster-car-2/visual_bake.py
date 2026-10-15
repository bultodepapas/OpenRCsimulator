#!/usr/bin/env python3
"""Bake authored Blender rig transforms for the Godot monster-car-2 visual.

Run with Blender 5.2:
  blender -b monster_truck_nitro_1.blend --python visual_bake.py -- \
    --glb assets/vehicles/monster-car-2/monster_truck_nitro_1.glb \
    --out assets/vehicles/monster-car-2/visual_rig

The supplied GLB is intentionally left untouched. This emits transform tracks
for its authored mesh nodes, sampled from the original Blender driver rig.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import sys
from collections import defaultdict
from itertools import product
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


SOURCE_AXES = {
    "h_FL": ("Control_Suspension_Del_Izq", -0.044, 0.036, 0.002),
    "h_FR": ("Control_Suspension_Del_Der", -0.044, 0.036, 0.002),
    "h_RL": ("Control_Suspension_Tras_Izq", -0.044, 0.036, 0.002),
    "h_RR": ("Control_Suspension_Tras_Der", -0.044, 0.036, 0.002),
    "steer": ("Control_Direccion", -0.42, 0.42, 0.02),
    # Wheel and engine phase are driven separately by the simulator state.
    "advance": ("Control_Avance", 0.0, 0.0, 1.0),
}
CONTROL_TO_AXIS = {control: axis for axis, (control, *_rest) in SOURCE_AXES.items()}
GLTF_FROM_SOURCE = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
SOURCE_FROM_GLTF = GLTF_FROM_SOURCE.transposed()
EXPECTED_GLTF_GLBS = 1
WHEELS = {
    "FL": ("Llanta_Del_Izq", "Rueda_Del_Izq", 1.0),
    "FR": ("Llanta_Del_Der", "Rueda_Del_Der", -1.0),
    "RL": ("Llanta_Tras_Izq", "Rueda_Tras_Izq", 1.0),
    "RR": ("Llanta_Tras_Der", "Rueda_Tras_Der", -1.0),
}
HEADLIGHT_MESH_NAMES = ["Faros", "Faros_Diurna", "LED_Frontal", "Focos_Antivuelco_LED"]
BRAKE_LIGHT_MESH_NAMES = ["Calaveras"]
FRONT_BUMPER_MESH = "Parachoques_Del.001"
REAR_BUMPER_MESH = "Parachoques_Tras.001"
ENGINE_PIVOT_OBJECT = "Cigueñal_Giro"


def _parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True, type=Path)
    parser.add_argument("--spec", type=Path, default=Path("assets/vehicles/monster-car-2/datos_simulacion_1.json"))
    parser.add_argument("--out", required=True, type=Path, help="Output prefix without extension")
    parser.add_argument("--diagnostics-only", action="store_true")
    return parser.parse_args(argv)


def _read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"Not a GLB: {path}")
    total = struct.unpack_from("<I", data, 8)[0]
    if total != len(data):
        raise ValueError(f"GLB length mismatch: header {total}, file {len(data)}")
    json_len, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError("First GLB chunk is not JSON")
    return json.loads(data[20 : 20 + json_len]), data


def _node_matrix(node: dict) -> Matrix:
    if "matrix" in node:
        raw = node["matrix"]
        return Matrix(tuple(tuple(float(raw[column * 4 + row]) for column in range(4)) for row in range(4)))
    translation = Vector(node.get("translation", (0.0, 0.0, 0.0)))
    quaternion = node.get("rotation", (0.0, 0.0, 0.0, 1.0))
    rotation = Quaternion((float(quaternion[3]), float(quaternion[0]), float(quaternion[1]), float(quaternion[2])))
    scale = Vector(node.get("scale", (1.0, 1.0, 1.0)))
    return Matrix.LocRotScale(translation, rotation, scale)


def _dependent_axes(obj: bpy.types.Object) -> list[str]:
    """Resolve controls affecting an object's evaluated world transform."""
    axes: set[str] = set()
    visited: set[int] = set()

    def visit(current: bpy.types.Object | None) -> None:
        if current is None or current.as_pointer() in visited:
            return
        visited.add(current.as_pointer())
        if current.parent is not None:
            visit(current.parent)
        for constraint in current.constraints:
            for attr in ("target", "pole_target"):
                target = getattr(constraint, attr, None)
                if isinstance(target, bpy.types.Object):
                    visit(target)
        animation = current.animation_data
        if animation is None:
            return
        for curve in animation.drivers:
            for variable in curve.driver.variables:
                for target in variable.targets:
                    target_id = target.id
                    if not isinstance(target_id, bpy.types.Object):
                        continue
                    axis = CONTROL_TO_AXIS.get(target_id.name)
                    if axis:
                        axes.add(axis)
                    else:
                        visit(target_id)

    visit(obj)
    # Source engine phase and wheel spin are applied from state at runtime.
    axes.discard("advance")
    return sorted(axes)


def _pose_values(axes: list[str]):
    ranges = []
    for axis in axes:
        _control, low, high, step = SOURCE_AXES[axis]
        count = round((high - low) / step)
        values = [low + i * step for i in range(count + 1)]
        values[-1] = high
        ranges.append(values)
    if not axes:
        yield ()
    else:
        yield from product(*ranges)


def _set_controls(axes: list[str], values: tuple[float, ...]) -> None:
    for name, (control_name, _lo, _hi, _step) in SOURCE_AXES.items():
        control = bpy.data.objects.get(control_name)
        if control is None:
            raise ValueError(f"Missing authored control: {control_name}")
        if name in axes:
            value = values[axes.index(name)]
        elif name == "advance":
            value = 0.0
        elif name == "steer":
            value = 0.0
        else:
            value = 0.0
        if name.startswith("h_"):
            control.location.z = value
        elif name == "steer":
            control.rotation_euler.z = value
        elif name == "advance":
            control.location.x = value


def _matrix_gltf(obj: bpy.types.Object) -> Matrix:
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    source = evaluated.matrix_world.copy()
    return GLTF_FROM_SOURCE @ source @ SOURCE_FROM_GLTF


def _matrix_floats(matrix: Matrix) -> tuple[float, ...]:
    # Godot Transform3D's three Basis columns followed by origin.
    return tuple(float(matrix[r][c]) for c in range(3) for r in range(3)) + tuple(float(matrix[r][3]) for r in range(3))


def _matrix_from_floats(values: tuple[float, ...] | list[float]) -> Matrix:
    return Matrix((
        (values[0], values[3], values[6], values[9]),
        (values[1], values[4], values[7], values[10]),
        (values[2], values[5], values[8], values[11]),
        (0.0, 0.0, 0.0, 1.0),
    ))


def _is_descendant(obj: bpy.types.Object, ancestor: bpy.types.Object) -> bool:
    current = obj
    while current is not None:
        if current == ancestor:
            return True
        current = current.parent
    return False


def _source_to_vehicle(point: Vector, *, position: bool) -> list[float]:
    return [float(-point.y), float(point.z - 0.087 if position else point.z), float(-point.x)]


def _gltf_to_vehicle(point: Vector, *, position: bool) -> list[float]:
    # GLTF = (source X, source Z, -source Y); target = (right, up, aft).
    return [float(point.z), float(point.y - 0.087 if position else point.y), float(-point.x)]


def _evaluated_world_points(obj: bpy.types.Object) -> list[Vector]:
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    evaluated.to_mesh_clear()
    return points


def _geometry_bindings(objects: dict[str, bpy.types.Object], gltf_nodes: dict[str, dict]) -> dict[str, object]:
    by_source_name = {}
    for glb_name, obj in objects.items():
        by_source_name.setdefault(obj.name, []).append(glb_name)
    body_root = bpy.data.objects.get("Carroceria")
    body_nodes = []
    if body_root is not None:
        body_nodes = sorted(name for name, obj in objects.items() if _is_descendant(obj, body_root))
    wheel_groups = {}
    for corner, (source_name, rig_pivot_name, spin_sign) in WHEELS.items():
        wheel = bpy.data.objects.get(source_name)
        rig_pivot = bpy.data.objects.get(rig_pivot_name)
        wheel_meshes = sorted(name for name, obj in objects.items() if rig_pivot is not None and _is_descendant(obj, rig_pivot))
        if wheel is None or rig_pivot is None or not wheel_meshes:
            raise ValueError(f"Missing authored wheel pivot/family for {corner}: {source_name} / {rig_pivot_name}")
        wheel_groups[corner] = {
            "pivot_track": f"@wheel_{corner}",
            "source_object": source_name,
            "source_rig_object": rig_pivot_name,
            "spin_sign": spin_sign,
            "mesh_nodes": wheel_meshes,
        }

    source_lamp = bpy.data.objects.get("Faros")
    if source_lamp is None:
        raise ValueError("Missing authored headlight lens mesh: Faros")
    lamp_points = _evaluated_world_points(source_lamp)
    front_x = max(point.x for point in lamp_points)
    front_points = [point for point in lamp_points if point.x >= front_x - 0.0015]
    headlight_positions = []
    for side in (1, -1):
        side_points = [point for point in front_points if side * point.y > 0.001]
        if not side_points:
            side_points = [point for point in lamp_points if side * point.y > 0.001]
        if not side_points:
            raise ValueError("Faros lens mesh has no left/right light points")
        center = sum(side_points, Vector()) / len(side_points)
        headlight_positions.append(_source_to_vehicle(center, position=True))

    exhaust_source = bpy.data.objects.get("Escape_Deflector")
    if exhaust_source is None:
        exhaust_source = bpy.data.objects.get("Escape_Sintonizado")
    if exhaust_source is None:
        raise ValueError("Missing authored exhaust outlet/pipe mesh")
    exhaust_points = _evaluated_world_points(exhaust_source)
    rear_x = min(point.x for point in exhaust_points)
    outlet_points = [point for point in exhaust_points if point.x <= rear_x + 0.0015]
    exhaust_position_source = sum(outlet_points, Vector()) / len(outlet_points)
    exhaust_center = sum(exhaust_points, Vector()) / len(exhaust_points)
    exhaust_direction_source = (exhaust_position_source - exhaust_center).normalized()
    if exhaust_direction_source.length_squared < 0.5:
        exhaust_direction_source = Vector((-1.0, 0.0, 0.0))
    exhaust_direction = Vector(_source_to_vehicle(exhaust_direction_source, position=False)).normalized()

    engine_pivot = bpy.data.objects.get(ENGINE_PIVOT_OBJECT)
    if engine_pivot is None:
        raise ValueError(f"Missing authored engine rotation control: {ENGINE_PIVOT_OBJECT}")
    engine_mesh_nodes = sorted(
        name for name, obj in objects.items() if _is_descendant(obj, engine_pivot)
    )
    if not engine_mesh_nodes:
        raise ValueError("Authored engine rotation control has no exported mesh descendants")
    engine_reference_name = engine_mesh_nodes[0]
    engine_reference_source = _matrix_gltf(objects[engine_reference_name])
    engine_reference_glb = _node_matrix(gltf_nodes[engine_reference_name])
    engine_coordinate_correction = engine_reference_glb @ engine_reference_source.inverted()
    engine_pivot_gltf = _matrix_floats(engine_coordinate_correction @ _matrix_gltf(engine_pivot))

    def actual_nodes(names: list[str]) -> list[str]:
        return sorted(name for name, obj in objects.items() if obj.name in names)

    return {
        "body_nodes": body_nodes,
        "wheel_groups": wheel_groups,
        "headlight_nodes": actual_nodes(HEADLIGHT_MESH_NAMES),
        "brake_light_nodes": actual_nodes(BRAKE_LIGHT_MESH_NAMES),
        "headlight_positions": headlight_positions,
        "exhaust_position": _source_to_vehicle(exhaust_position_source, position=True),
        "exhaust_direction": [float(value) for value in exhaust_direction],
        "exhaust_source_object": exhaust_source.name,
        "engine_pivot_gltf": [float(value) for value in engine_pivot_gltf],
        "engine_phase_axis_gltf": [0.0, 0.0, -1.0],
        "engine_nodes": engine_mesh_nodes,
        "bumper_nodes": {"front": FRONT_BUMPER_MESH, "rear": REAR_BUMPER_MESH},
        "damage_basis": "Basis(Vector3.UP, PI/2): imported glTF local -> app vehicle axes",
    }


def _sample_pose(objects: dict[str, bpy.types.Object], axes: list[str], values: tuple[float, ...]):
    _set_controls(axes, values)
    bpy.context.view_layer.update()
    return {name: _matrix_floats(_matrix_gltf(obj)) for name, obj in objects.items()}


def _disable_actions_and_neutralize() -> None:
    for obj in bpy.data.objects:
        if obj.animation_data is not None:
            obj.animation_data.action = None
    scene = bpy.context.scene
    scene.frame_set(scene.frame_start)
    for name, (control_name, *_rest) in SOURCE_AXES.items():
        control = bpy.data.objects.get(control_name)
        if control is None:
            raise ValueError(f"Missing authored control: {control_name}")
        if name.startswith("h_"):
            control.location.z = 0.0
        elif name == "steer":
            control.rotation_euler.z = 0.0
        elif name == "advance":
            control.location.x = 0.0
    bpy.context.view_layer.update()


def _hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _steer_inverse_map(spec_path: Path) -> list[dict[str, float]]:
    source = json.loads(spec_path.read_text(encoding="utf-8"))
    rows = source.get("direccion", {}).get("tabla", [])
    if len(rows) < 2:
        raise ValueError("Supplied geometry spec has no usable steering table")
    result = []
    for row in rows:
        control = float(row["control"])
        wheel_degrees = 0.5 * (float(row["rueda_izq_grados"]) + float(row["rueda_der_grados"]))
        result.append({"wheel_angle_rad": math.radians(wheel_degrees), "control_rad": control})
    result.sort(key=lambda row: row["wheel_angle_rad"])
    for previous, current in zip(result, result[1:]):
        if current["wheel_angle_rad"] <= previous["wheel_angle_rad"]:
            raise ValueError("Supplied steering map is not strictly monotonic")
    return result


def main() -> None:
    args = _parse_args()
    glb_path = args.glb.resolve()
    spec_path = args.spec.resolve()
    gltf, glb_bytes = _read_glb(glb_path)
    mesh_nodes = [node["name"] for node in gltf["nodes"] if "mesh" in node]
    if len(mesh_nodes) != len(set(mesh_nodes)):
        raise ValueError("The GLB has duplicate mesh node names; stable name binding is ambiguous")
    objects = {}
    node_source_names = {}
    missing = []
    for name in mesh_nodes:
        obj = bpy.data.objects.get(name)
        if obj is None and "." in name and name.rsplit(".", 1)[1].isdigit():
            obj = bpy.data.objects.get(name.rsplit(".", 1)[0])
        if obj is None or obj.type not in {"MESH", "CURVE", "SURFACE", "FONT"}:
            missing.append(name)
        else:
            objects[name] = obj
            node_source_names[name] = obj.name
    if missing:
        raise ValueError(f"GLB mesh nodes missing from Blender source: {missing[:20]}")

    track_objects = dict(objects)
    for corner, (source_name, _rig_pivot_name, _spin_sign) in WHEELS.items():
        wheel = bpy.data.objects.get(source_name)
        if wheel is None:
            raise ValueError(f"Missing authored wheel control object: {source_name}")
        track_objects[f"@wheel_{corner}"] = wheel
        node_source_names[f"@wheel_{corner}"] = wheel.name

    _disable_actions_and_neutralize()
    tracks: dict[str, dict[str, object]] = {}
    gltf_nodes_by_name = {node["name"]: node for node in gltf["nodes"]}
    bindings = _geometry_bindings(objects, gltf_nodes_by_name)
    diagnostics: dict[str, object] = {"mesh_count": len(mesh_nodes), "animated": {}, "errors": []}
    for node_name, obj in track_objects.items():
        axes = _dependent_axes(obj)
        if not axes:
            continue
        # The source has a small number of anti-roll links that depend on both
        # wheels of one axle. Avoid emitting a hidden, unbounded product table.
        sample_count = math.prod(round((SOURCE_AXES[a][2] - SOURCE_AXES[a][1]) / SOURCE_AXES[a][3]) + 1 for a in axes)
        if sample_count > 4000:
            diagnostics["errors"].append({"node": node_name, "axes": axes, "sample_count": sample_count})
            continue
        diagnostics["animated"][node_name] = axes

    diagnostics["animated_count"] = len(diagnostics["animated"])
    diagnostics["source_object_names"] = node_source_names
    diagnostics["unsupported_count"] = len(diagnostics["errors"])
    diagnostics["unsupported_examples"] = diagnostics["errors"][:40]
    if args.diagnostics_only:
        groups = defaultdict(list)
        for node_name, axes in diagnostics["animated"].items():
            groups["+".join(axes)].append(node_name)
        print(json.dumps({
            "mesh_count": diagnostics["mesh_count"],
            "animated_count": diagnostics["animated_count"],
            "groups": {key: {"count": len(names), "examples": names[:6]} for key, names in sorted(groups.items())},
            "unsupported_count": diagnostics["unsupported_count"],
            "unsupported_examples": diagnostics["unsupported_examples"],
        }, indent=2, ensure_ascii=False))
        return
    if diagnostics["errors"]:
        raise ValueError(f"{len(diagnostics['errors'])} mesh transforms exceed the bounded bake grid")

    prefix = args.out.resolve()
    prefix.parent.mkdir(parents=True, exist_ok=True)
    binary_path = Path(str(prefix) + ".bin")
    index_path = Path(str(prefix) + ".json")
    offset = 0
    with binary_path.open("wb") as binary:
        groups = defaultdict(list)
        for node_name, axes in diagnostics["animated"].items():
            groups[tuple(axes)].append(node_name)
        for axes_tuple, node_names in sorted(groups.items()):
            axes = list(axes_tuple)
            values_axes = []
            for axis in axes:
                _control, low, high, step = SOURCE_AXES[axis]
                count = round((high - low) / step)
                axis_values = [low + i * step for i in range(count + 1)]
                axis_values[-1] = high
                values_axes.append(axis_values)
            sampled_tracks = {node_name: bytearray() for node_name in sorted(node_names)}
            group_objects = {name: track_objects[name] for name in sampled_tracks}
            neutral_values = tuple(0.0 for _axis in axes)
            neutral = _sample_pose(group_objects, axes, neutral_values)
            corrections = {}
            for node_name in sampled_tracks:
                glb_name = node_source_names[node_name] if node_name.startswith("@wheel_") else node_name
                glb_node = gltf_nodes_by_name.get(glb_name)
                if glb_node is None:
                    corrections[node_name] = Matrix.Identity(4)
                else:
                    corrections[node_name] = _node_matrix(glb_node) @ _matrix_from_floats(neutral[node_name]).inverted()
            for values in product(*values_axes):
                sampled = _sample_pose(group_objects, axes, values)
                for node_name, pose in sampled.items():
                    sampled_tracks[node_name].extend(struct.pack("<12f", *pose))
            for node_name, track_bytes in sampled_tracks.items():
                start_offset = offset
                binary.write(track_bytes)
                offset += len(track_bytes)
                tracks[node_name] = {
                    "axes": axes,
                    "ranges": [[values[0], values[-1], values[1] - values[0] if len(values) > 1 else 0.0, len(values)] for values in values_axes],
                    "offset": start_offset,
                    "float_count": len(track_bytes) // 4,
                    "correction": _matrix_floats(corrections[node_name]),
                }
                print(f"Baked {node_name}: {axes}, {len(track_bytes):,} bytes")

    # Compare world-space rest wheel centers from Blender, the imported GLB and
    # the source geometry datum. This remains a render boundary measurement.
    wheel_centers_gltf = {}
    rest_wheel_centers_vehicle = {}
    for corner, (source_name, _rig_pivot_name, _spin_sign) in WHEELS.items():
        # The supplied export is flattened: these wheel mesh nodes are all GLTF
        # scene roots, so their node transform is the imported wheel center.
        wheel_matrix = _node_matrix(gltf_nodes_by_name[source_name])
        center = wheel_matrix.to_translation()
        wheel_centers_gltf[corner] = [float(value) for value in center]
        rest_wheel_centers_vehicle[corner] = _gltf_to_vehicle(center, position=True)
    manifest = {
        "schema": "openrc-monster-car-2-visual-rig-v1",
        "source_blend": "monster_truck_nitro_1.blend",
        "source_glb_sha256": hashlib.sha256(glb_bytes).hexdigest(),
        "source_spec": args.spec.as_posix(),
        "source_spec_sha256": _hash(spec_path),
        "source_glb_mesh_nodes": len(mesh_nodes),
        "source_axes": "Blender +X forward, +Y left, +Z up; generated tracks are in glTF local axes.",
        "target_axes": "Godot vehicle +X right, +Y up, -Z forward; art child maps glTF through +90 deg about +Y and subtracts source Z=0.087 m datum height.",
        "controls": {axis: {"object": values[0], "min": values[1], "max": values[2], "step": values[3]} for axis, values in SOURCE_AXES.items()},
        "tracks": tracks,
        "bindings": bindings,
        "steer_inverse_map": _steer_inverse_map(spec_path),
        "diagnostics": diagnostics,
        "binary_sha256": _hash(binary_path),
        "wheel_centers_glb_gltf_xyz_m": wheel_centers_gltf,
        "wheel_centers_vehicle_local_m_from_datum": rest_wheel_centers_vehicle,
    }
    index_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {binary_path} ({binary_path.stat().st_size:,} bytes)")
    print(f"Wrote {index_path} ({index_path.stat().st_size:,} bytes)")
    print(f"Animated nodes: {len(tracks)} / {len(mesh_nodes)}")


if __name__ == "__main__":
    main()
