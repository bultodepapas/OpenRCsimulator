"""F4U-21: R59's extra mechanisms, read-only (never saved): canopy slide, cowl flaps, tailhook, wing-fold hardware.

For each control, prints the driver expressions of the objects it moves and samples the rig in memory: the world
transform of each moved object and of the meshes it carries, at several control values, in R59's root frame
(+X aft, +Y right, +Z up, metres, full size). Tells whether a motion is a rotation about a fixed axis, a straight
slide or a path that needs sampling.

    blender -b -Y --factory-startup F4U_Corsair_R59.blend --python probe_extras.py -- OUT.json
"""
import bpy, json, math, os, sys
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "F4U-18"))
import r59_pose

out_path = sys.argv[sys.argv.index("--") + 1]
ob = bpy.data.objects
root = ob[r59_pose.ROOT]
canopy = ob["CABINA | apertura 0 cerrada 1 abierta"]


def evaluate():
    driven = [o for o in ob if o.animation_data and o.animation_data.drivers]
    for _ in range(3):
        for o in [root, canopy, ob["R51 | CONTROL ALAS"]] + driven:
            o.update_tag()
        bpy.context.scene.frame_set(bpy.context.scene.frame_current)
        bpy.context.view_layer.update()
    return bpy.context.evaluated_depsgraph_get()


def matrix(o, deps):
    return o.evaluated_get(deps).matrix_world.copy()


def centre(o, deps):
    e = o.evaluated_get(deps)
    return e.matrix_world @ (sum((Vector(c) for c in e.bound_box), Vector()) / 8.0)


def drivers(o):
    if not (o.animation_data and o.animation_data.drivers):
        return []
    return [{"channel": f"{fc.data_path}[{fc.array_index}]", "expression": fc.driver.expression,
             "variables": [{"name": v.name, "id": v.targets[0].id.name if v.targets[0].id else None,
                            "path": v.targets[0].data_path} for v in fc.driver.variables]} for fc in o.animation_data.drivers]


def meshes_under(o):
    return [c for c in [o] + list(o.children_recursive) if c.type == "MESH"]


def motion(names, set_value, values):
    """World matrices of each named object and the centres of the meshes it carries, per control value."""
    record = {}
    for v in values:
        set_value(v)
        deps = evaluate()
        for n in names:
            o = ob[n]
            entry = record.setdefault(n, {"drivers": drivers(o), "parent": o.parent.name if o.parent else None,
                                          "rotation_mode": o.rotation_mode, "carried_meshes": [m.name for m in meshes_under(o)][:40],
                                          "samples": []})
            m = matrix(o, deps)
            entry["samples"].append({"value": v, "origin": list(m.translation),
                                     "basis": [list(m.to_3x3().col[i]) for i in range(3)],
                                     "mesh_centres": {c.name: list(centre(c, deps)) for c in meshes_under(o)[:6]}})
    return record


def rotation_fit(samples):
    """Angle and axis of each sample's basis relative to the first: a fixed-axis rotation keeps one axis."""
    b0 = Matrix([samples[0]["basis"][i] for i in range(3)]).transposed()
    fits = []
    for s in samples:
        b = Matrix([s["basis"][i] for i in range(3)]).transposed()
        r = (b @ b0.inverted()).to_quaternion()
        axis, angle = r.to_axis_angle()
        fits.append({"value": s["value"], "angle_deg": math.degrees(angle), "axis": list(axis),
                     "translation_m": list(Vector(s["origin"]) - Vector(samples[0]["origin"]))})
    return fits


r59_pose.pose_neutral()
result = {"file": bpy.data.filepath, "frame": "R59 root frame [x_aft, y_right, z_up], metres, full size", "controls": {}}

# Canopy: the control object itself moves (location and rotation); list its children and the R7 canopy meshes.
canopy_keys = [k for k in canopy.keys() if not k.startswith("_")]
canopy_moved = sorted({canopy.name} | {o.name for o in ob if any(v["id"] == canopy.name for d in drivers(o) for v in d["variables"])})
def set_canopy(v):
    canopy["apertura"] = v
result["controls"]["canopy"] = {"keys": {k: canopy[k] for k in canopy_keys if isinstance(canopy[k], (int, float))},
                                "children": [c.name for c in canopy.children][:40],
                                "moved": canopy_moved,
                                "motion": motion(canopy_moved, set_canopy, [0.0, 0.25, 0.5, 0.75, 1.0])}
result["controls"]["canopy"]["fit"] = {n: rotation_fit(r["samples"]) for n, r in result["controls"]["canopy"]["motion"].items()}
set_canopy(0.0)

# Root-property controls.
for key, values, names in [
        ("cowl_flaps_deg", [0.0, 11.0, 22.0], [f"R14 | bisagra sector {i:02d}" for i in range(1, 17)]),
        ("gancho_cola_deg", [0.0, 30.0, 60.0, 90.0], ["R27 | pivote gancho"])]:
    original = root[key]
    def set_root(v, key=key):
        root[key] = type(root[key])(v)
    rec = motion(names, set_root, values)
    result["controls"][key] = {"motion": rec, "fit": {n: rotation_fit(r["samples"]) for n, r in rec.items()},
                               "property_ui": dict(root.id_properties_ui(key).as_dict()) if hasattr(root, "id_properties_ui") else {}}
    set_root(0.0)

# Wing-fold hardware: what the lock, strut and fold states move besides the panel pivots.
wings = ob["R51 | CONTROL ALAS"]
hardware = sorted({o.name for o in ob for d in drivers(o) for v in d["variables"]
                   if v["id"] in (wings.name, "R53 | izquierda ESTADO MECANICO", "R53 | derecha ESTADO MECANICO")})
result["controls"]["wing_fold_hardware"] = {n: {"drivers": drivers(ob[n]), "parent": ob[n].parent.name if ob[n].parent else None,
                                                "type": ob[n].type, "carried_meshes": [m.name for m in meshes_under(ob[n])][:20],
                                                "hide_render_neutral": ob[n].hide_render} for n in hardware}

with open(out_path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(result, f, indent=1, ensure_ascii=False)
for name, control in result["controls"].items():
    if "fit" in control:
        for n, fits in list(control["fit"].items())[:3]:
            print(name, n, [(f["value"], round(f["angle_deg"], 2), [round(a, 3) for a in f["axis"]], [round(t, 4) for t in f["translation_m"]]) for f in fits])
print("hardware:", len(result["controls"]["wing_fold_hardware"]))
