"""F4U-06: slice the neutral R59 wing and tail into chordwise sections (provisional physics geometry).

Poses the rig neutral in memory exactly as F4U-00/measure_neutral.py does (never saved), then intersects mesh edges
with station planes in the R59 root frame (+X aft, +Y right, +Z up, full size). For each station it reports leading
and trailing edge points, chord, incidence (positive leading edge up) and maximum thickness, and integrates planform
areas. The right wing and right stabilizer are measured; the model is symmetric.

    blender -b -Y --factory-startup F4U_Corsair_R59.blend --python measure_sections_r59.py -- OUT.json
"""
import bpy, json, math, sys
from mathutils import Matrix

out_path = sys.argv[sys.argv.index("--") + 1]
ob = bpy.data.objects
root = ob["F4U CORSAIR | avion completo"]
for o in ob:
    if o.animation_data and o.animation_data.action:
        o.animation_data.action = None
for key in ["flaps_deg", "alerones_deg", "compensador_deg", "elevadores_deg", "trim_elevadores_deg", "timon_deg",
            "trim_timon_deg", "cowl_flaps_deg", "tren_retraccion", "gancho_cola_deg"]:
    if key in root.keys():
        root[key] = type(root[key])(0)
wings = ob["R51 | CONTROL ALAS"]
for key, value in {"plegado_derecha": 0.0, "plegado_izquierda": 0.0, "bloqueo_derecha": 1.0,
                   "bloqueo_izquierda": 1.0, "puntal_derecha": 0.0, "puntal_izquierda": 0.0}.items():
    wings[key] = value
root.matrix_world = Matrix.Identity(4)
scene = bpy.context.scene
for _ in range(3):
    scene.frame_set(scene.frame_current)
    bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()

GROUPS = {
    "wing_right": ["Ala derecha | gaviota invertida", "R51 | Panel exterior derecha", "Flap articulado derecha 1",
                   "Flap articulado derecha 2", "Flap articulado derecha 3", "Aleron R8 | derecha"],
    "stabilizer_right": ["Estabilizador derecho", "R11 | elevador derecho"],
    "fin": ["R12 | deriva fija", "R12 | timon articulado"],
}


def world_edges(names):
    edges = []
    for name in names:
        evaluated = ob[name].evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        matrix = evaluated.matrix_world
        points = [matrix @ v.co for v in mesh.vertices]
        edges.extend((points[e.vertices[0]], points[e.vertices[1]]) for e in mesh.edges)
        evaluated.to_mesh_clear()
    return edges


def section(edges, axis, value):
    # axis 1: station plane y = value (wing, stabilizer); axis 2: z = value (fin).
    hits = []
    for a, b in edges:
        da, db = a[axis] - value, b[axis] - value
        if da == db or da * db > 0:
            continue
        t = da / (da - db)
        hits.append(a.lerp(b, t))
    if len(hits) < 4:
        return None
    lead = min(hits, key=lambda p: p.x)
    trail = max(hits, key=lambda p: p.x)
    chord = (trail - lead).length
    other = 2 if axis == 1 else 1  # thickness direction
    if axis == 1:
        incidence = math.degrees(math.atan2(lead.z - trail.z, trail.x - lead.x))
    else:
        incidence = math.degrees(math.atan2(trail.y - lead.y, trail.x - lead.x))
    thickness = max(p[other] for p in hits) - min(p[other] for p in hits)
    mid = (lead + trail) * 0.5
    return {"station": round(value, 4), "le": [round(c, 5) for c in lead], "te": [round(c, 5) for c in trail],
            "chord": round(chord, 5), "incidence_deg": round(incidence, 3), "thickness": round(thickness, 5),
            "thickness_ratio": round(thickness / chord, 4), "mid": [round(c, 5) for c in mid]}


def sweep(edges, axis, start, stop, step):
    rows, value = [], start
    while value <= stop + 1e-9:
        row = section(edges, axis, value)
        if row:
            rows.append(row)
        value += step
    return rows


def area(rows):
    return sum(0.5 * (a["chord"] + b["chord"]) * (b["station"] - a["station"]) for a, b in zip(rows, rows[1:]))


result = {"frame": "R59 root frame, +X aft, +Y right, +Z up, metres, full size, neutral pose", "groups": {}}
specs = {"wing_right": (1, 0.02, 6.24, 0.04), "stabilizer_right": (1, 0.02, 2.54, 0.04), "fin": (2, 2.80, 4.78, 0.04)}
for group, names in GROUPS.items():
    axis, start, stop, step = specs[group]
    rows = sweep(world_edges(names), axis, start, stop, step)
    result["groups"][group] = {"objects": names, "axis": "yz"[axis - 1], "sections": rows,
                               "area_one_side": round(area(rows), 5),
                               "extent": [rows[0]["station"], rows[-1]["station"]] if rows else None}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=1)
for group, data in result["groups"].items():
    print("SECTIONS", group, len(data["sections"]), "area_one_side", data["area_one_side"], "extent", data["extent"])
