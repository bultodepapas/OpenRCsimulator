"""F4U-17: the wing-fold kinematics of the F4U Corsair from the author's R59 master.

Poses the rig as F4U-06 does (root at identity, demo actions unassigned, wings spread and locked; never saved) and
reads R51's two outer-panel pivots: their location and axis in R59's root frame (+X aft, +Y right, +Z up, metres,
full size), the fold angle (R51 | CONTROL ALAS `angulo_maximo`) and the travel law of the pivot drivers
(angle = sign * max * clamp((q - release) / travel, 0, 1)). It then unlocks and folds both panels fully in memory
and checks that Blender's own evaluation equals that rotation at each pivot and at the panel's navigation light.

    blender -b -Y --factory-startup F4U_Corsair_R59.blend --python extract_wing_fold.py -- OUT.json SHA256

compile_model.py maps the result to the model frame; the game model carries no fold pivot of its own.
"""
import bpy, json, math, re, sys
from mathutils import Matrix, Vector

out_path, source_sha = sys.argv[sys.argv.index("--") + 1:][:2]
ob = bpy.data.objects
root = ob["F4U CORSAIR | avion completo"]
for o in ob:
    if o.animation_data and o.animation_data.action:
        o.animation_data.action = None
control = ob["R51 | CONTROL ALAS"]
SIDES = {"left": ("izquierda", "R51 | PIVOTE panel izquierda", "Luz de posicion R8 | izquierda"),
         "right": ("derecha", "R51 | PIVOTE panel derecha", "Luz de posicion R8 | derecha")}


def pose(fold):
    for side, _, _ in SIDES.values():
        control[f"plegado_{side}"] = fold
        control[f"bloqueo_{side}"] = 0.0 if fold > 0.0 else 1.0
        control[f"puntal_{side}"] = 0.0
    root.matrix_world = Matrix.Identity(4)
    # Custom-property edits do not tag the depsgraph; the drivers read them through two levels (state q, pivot).
    for o in ob:
        if o.animation_data and o.animation_data.drivers:
            o.update_tag()
    control.update_tag()
    scene = bpy.context.scene
    for _ in range(3):
        scene.frame_set(scene.frame_current)
        bpy.context.view_layer.update()


def world(o):
    return o.evaluated_get(bpy.context.evaluated_depsgraph_get()).matrix_world


def centre(o):
    """The mesh's bounding-box centre in the root frame (R59 objects often keep their origin at the root's)."""
    local = sum((Vector(corner) for corner in o.bound_box), Vector()) / 8.0
    return world(o) @ local


def law(pivot):
    driver = next(fc.driver for fc in pivot.animation_data.drivers if fc.data_path == "rotation_axis_angle" and fc.array_index == 0)
    expression = driver.expression.replace(" ", "")
    match = re.fullmatch(r"(-?1)\*m\*pi/180\*min\(1,max\(0,\(q-([0-9.]+)\)/([0-9.]+)\)\)", expression)
    assert match, expression
    return {"sign": int(match.group(1)), "release": float(match.group(2)), "travel": float(match.group(3)), "expression": driver.expression}


pose(0.0)
max_deg = float(control["angulo_maximo"])
spread = {}
for key, (_, pivot_name, light_name) in SIDES.items():
    pivot = ob[pivot_name]
    assert pivot.parent == root and pivot.rotation_mode == "AXIS_ANGLE"
    assert all(abs(pivot.matrix_parent_inverse[i][j] - (1.0 if i == j else 0.0)) < 1e-9 for i in range(4) for j in range(4))
    axis = Vector(pivot.rotation_axis_angle[1:]).normalized()
    spread[key] = {"pivot": list(pivot.location), "axis": list(axis), "law": law(pivot),
                   "light": list(centre(ob[light_name])), "carried_objects": len(pivot.children_recursive)}

pose(1.0)
result = {"format": "openrc-f4u-wing-fold v1",
          "source": {"file": "F4U_Corsair_R59.blend", "sha256": source_sha, "blender": bpy.app.version_string,
                     "script": "research/f4u-corsair/F4U-17/extract_wing_fold.py"},
          "frame": "R59 root frame [x_aft, y_right, z_up], metres, full size",
          "max_angle_deg": max_deg, "sides": {}}
for key, (_, pivot_name, light_name) in SIDES.items():
    pivot = ob[pivot_name]
    record = spread[key]
    law_record = record.pop("law")
    angle = law_record["sign"] * math.radians(max_deg)
    p = Vector(record["pivot"])
    turn = Matrix.Translation(p) @ Matrix.Rotation(angle, 4, Vector(record["axis"])) @ Matrix.Translation(-p)
    predicted_light = turn @ Vector(record["light"])
    folded_light = centre(ob[light_name])
    expected = Matrix.Rotation(angle, 3, Vector(record["axis"]))
    actual = world(pivot).to_3x3()
    basis_error = [[actual[i][j] - expected[i][j] for j in range(3)] for i in range(3)]
    record.update({"sign": law_record["sign"], "lock_release_fraction": law_record["release"],
                   "travel_fraction": law_record["travel"], "driver_expression": law_record["expression"],
                   "check_folded_light_error_m": (predicted_light - folded_light).length,
                   "check_folded_basis_error": max(abs(v) for row in basis_error for v in row),
                   "light_folded": list(folded_light)})
    result["sides"][key] = record
with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(result, handle, indent=1)
    handle.write("\n")
print("WING_FOLD", {k: (round(v["check_folded_light_error_m"], 6), round(v["check_folded_basis_error"], 6)) for k, v in result["sides"].items()})
