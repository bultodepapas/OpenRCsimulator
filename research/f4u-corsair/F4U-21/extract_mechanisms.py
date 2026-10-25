"""F4U-21: the Corsair's auxiliary mechanisms from the author's R59 master: canopy slide, tailhook and cowl flaps.

Poses the rig neutral as F4U-18 does (root at identity, demo actions unassigned; never saved) and reads each
mechanism's law from its drivers, in R59's root frame (+X aft, +Y right, +Z up, metres, full size):

- canopy: `CABINA | apertura 0 cerrada 1 abierta` slides by (0.70, 0, -0.0385) * apertura, straight;
- tailhook: `R27 | pivote gancho` turns about its local Y by `gancho_cola_deg`, 0-45 degrees;
- cowl flaps: each `R14 | bisagra sector NN` turns about its local Y by -min(28, max(0, cowl_flaps_deg)).

It then opens each mechanism fully in memory and checks that Blender's own evaluation equals the analytic motion at
the moved parts' centres. Centres at rest are landmarks for compile_model.py, which maps them to the model frame.

    blender -b -Y --factory-startup F4U_Corsair_R59.blend --python extract_mechanisms.py -- OUT.json SHA256
"""
import bpy, json, math, os, re, sys
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "F4U-18"))
import r59_pose

out_path, source_sha = sys.argv[sys.argv.index("--") + 1:][:2]
ob = bpy.data.objects
root = ob[r59_pose.ROOT]
canopy = ob["CABINA | apertura 0 cerrada 1 abierta"]
hook = ob["R27 | pivote gancho"]
SECTORS = [ob[f"R14 | bisagra sector {i:02d}"] for i in range(1, 17)]


def evaluate():
    driven = [o for o in ob if o.animation_data and o.animation_data.drivers]
    for _ in range(3):
        for o in [root, canopy] + driven:
            o.update_tag()
        bpy.context.scene.frame_set(bpy.context.scene.frame_current)
        bpy.context.view_layer.update()
    return bpy.context.evaluated_depsgraph_get()


def centre(objects):
    """Centre of the evaluated bounding boxes of the objects, in the root frame (the root is at identity)."""
    deps = bpy.context.evaluated_depsgraph_get()
    corners = [o.evaluated_get(deps).matrix_world @ Vector(c) for o in objects for c in o.evaluated_get(deps).bound_box]
    return (Vector([min(c[i] for c in corners) for i in range(3)]) + Vector([max(c[i] for c in corners) for i in range(3)])) / 2.0


def expression(o, channel):
    for fc in o.animation_data.drivers:
        if f"{fc.data_path}[{fc.array_index}]" == channel:
            return fc.driver.expression.replace(" ", "")
    raise AssertionError(f"{o.name} has no driver on {channel}")


def assert_rooted(o):
    assert o.parent == root and o.parent_type == "OBJECT", o.name
    assert all(abs(o.matrix_parent_inverse[i][j] - (1.0 if i == j else 0.0)) < 1e-9 for i in range(4) for j in range(4)), o.name


def turn(pivot, axis, degrees):
    return Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(degrees), 4, axis) @ Matrix.Translation(-pivot)


r59_pose.pose_neutral()
canopy["apertura"] = 0.0
evaluate()

# Canopy: two linear location drivers on a control parented to the root, nothing else.
assert_rooted(canopy)
coefficients = {}
for index in range(3):
    channel = f"location[{index}]"
    if any(f"{fc.data_path}[{fc.array_index}]" == channel for fc in canopy.animation_data.drivers):
        match = re.fullmatch(r"(-?\.?[0-9.]+)\*apertura", expression(canopy, channel))
        assert match, expression(canopy, channel)
        coefficients[index] = float(match.group(1))
assert set(coefficients) == {0, 2} and not any(fc.data_path.startswith("rotation") for fc in canopy.animation_data.drivers)
offset = Vector([coefficients.get(i, 0.0) for i in range(3)])
canopy_parts = [c for c in canopy.children_recursive if c.type in ("MESH", "CURVE") and c.name.startswith("Cubierta R7 | ")]
glass = [ob["Cubierta R7 | acrilico curvo"]]
canopy_rest = {"glass": centre(glass), "parts": centre(canopy_parts), "control": canopy.matrix_world.translation.copy()}

# Tailhook: one Euler Y driver, gancho_cola_deg in degrees; the hook's two curves are its children.
assert_rooted(hook)
assert hook.rotation_mode == "XYZ" and re.fullmatch(r"g\*0\.0174532925[0-9]*", expression(hook, "rotation_euler[1]")), expression(hook, "rotation_euler[1]")
hook_parts = [c for c in hook.children if c.type in ("MESH", "CURVE")]
assert sorted(c.name for c in hook_parts) == ["R27 | asta gancho", "R27 | punta curva gancho"], [c.name for c in hook_parts]
hook_range = root.id_properties_ui("gancho_cola_deg").as_dict()
hook_pivot = hook.matrix_world.translation.copy()
hook_axis = (hook.matrix_world.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
hook_rest = centre(hook_parts)

# Cowl flaps: per sector, an Euler Y driver -min(28, max(0, q)) in degrees on a hinge under its support.
sectors = []
limit = None
for hinge in SECTORS:
    law = expression(hinge, "rotation_euler[1]")
    match = re.fullmatch(r"-min\(([0-9.]+),max\(0,q\)\)\*pi/180", law)
    assert match and hinge.rotation_mode == "XYZ", (hinge.name, law)
    limit = float(match.group(1)) if limit is None else limit
    assert float(match.group(1)) == limit, hinge.name
    support = hinge.parent
    assert_rooted(support)
    number = hinge.name[-2:]
    gate = ob[f"R14 | compuerta curva {number}"]
    assert gate in hinge.children_recursive, gate.name
    sectors.append({"sector": number, "hinge": hinge.name, "pivot": hinge.matrix_world.translation.copy(),
                    # rotation_euler[1] = -angle: a positive opening turns about the hinge's local -Y.
                    "axis": (hinge.matrix_world.to_3x3() @ Vector((0.0, -1.0, 0.0))).normalized(),
                    "gate": gate, "gate_rest": centre([gate])})
cowl_range = root.id_properties_ui("cowl_flaps_deg").as_dict()
assert float(cowl_range["max"]) == limit, (cowl_range, limit)

# Open everything in memory and compare Blender's evaluation with the analytic motions: each moved object's whole
# world matrix, which checks its position and orientation at once.
moved = {"canopy": canopy_parts, "tailhook": hook_parts, "cowl_flaps": [s["gate"] for s in sectors]}
rest = {o.name: o.matrix_world.copy() for objects in moved.values() for o in objects}
canopy["apertura"] = 1.0
root["gancho_cola_deg"] = type(root["gancho_cola_deg"])(hook_range["max"])
root["cowl_flaps_deg"] = type(root["cowl_flaps_deg"])(limit)
evaluate()


def matrix_error(o, motion):
    expected = motion @ rest[o.name]
    return max(abs(o.matrix_world[i][j] - expected[i][j]) for i in range(3) for j in range(4))


errors = {"canopy": max(matrix_error(o, Matrix.Translation(offset)) for o in canopy_parts),
          "tailhook": max(matrix_error(o, turn(hook_pivot, hook_axis, float(hook_range["max"]))) for o in hook_parts),
          "cowl_flaps": max(matrix_error(s["gate"], turn(s["pivot"], s["axis"], limit)) for s in sectors)}
canopy["apertura"] = 0.0
root["gancho_cola_deg"] = type(root["gancho_cola_deg"])(0)
root["cowl_flaps_deg"] = type(root["cowl_flaps_deg"])(0)
evaluate()
assert max(errors.values()) < 1e-5, errors


def v(vector):
    return [round(float(c), 9) for c in vector]


result = {"format": "openrc-f4u-mechanisms v1",
          "source": {"file": "F4U_Corsair_R59.blend", "sha256": source_sha, "blender": bpy.app.version_string,
                     "script": "research/f4u-corsair/F4U-21/extract_mechanisms.py"},
          "frame": "R59 root frame [x_aft, y_right, z_up], metres, full size",
          "canopy": {"control": canopy.name, "law": {f"location[{i}]": expression(canopy, f"location[{i}]") for i in sorted(coefficients)},
                     "offset": v(offset), "glass_centre": v(canopy_rest["glass"]), "parts_centre": v(canopy_rest["parts"]),
                     "parts": sorted(c.name for c in canopy_parts), "check_open_matrix_error": errors["canopy"]},
          "tailhook": {"pivot_object": hook.name, "law": expression(hook, "rotation_euler[1]"), "pivot": v(hook_pivot),
                       "axis": v(hook_axis), "max_angle_deg": float(hook_range["max"]), "parts": sorted(c.name for c in hook_parts),
                       "parts_centre": v(hook_rest), "check_lowered_matrix_error": errors["tailhook"]},
          "cowl_flaps": {"control": "F4U CORSAIR | avion completo[cowl_flaps_deg]", "law": expression(SECTORS[0], "rotation_euler[1]"),
                         "max_angle_deg": limit, "check_open_matrix_error": errors["cowl_flaps"],
                         "sectors": [{"sector": s["sector"], "hinge": s["hinge"], "pivot": v(s["pivot"]), "axis": v(s["axis"]),
                                      "gate": s["gate"].name, "gate_centre": v(s["gate_rest"])} for s in sectors]}}
with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(result, handle, indent=1, ensure_ascii=False)
    handle.write("\n")
print("MECHANISMS", {k: f"{e:.1e}" for k, e in errors.items()})
