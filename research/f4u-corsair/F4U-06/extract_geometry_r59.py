"""F4U-06: provisional 1/4.5 physics geometry of the F4U Corsair from the author's R59 master.

Poses the rig neutral in memory (never saved): root at identity, demo actions unassigned, controls and trims zero,
wings spread and locked. Writes metres in the physics le frame, [x_aft, y_right, z_up] from the wing-root leading
edge on the centreline at thrust-line height, scaled 1/4.5 (the owner's 2026-10-22 decision, CARF-Models class).
R59's root frame is +X aft, +Y right, +Z up at full size, so le = (x - X_LE, y, z - Z_THRUST) / 4.5.

Contents: right-wing, stabilizer and fin sections (edge-plane intersections), control-surface spans and chordwise
extents, fuselage stations, spinner, propeller plane, canopy top, crash-hull points, light and exhaust positions,
wheel geometry and retraction paths. Each path follows one material point of a tyre (its lowest vertex with the gear
down) rigidly through R59's own `tren_retraccion` rig, sampled uniformly in extension from stowed (0) to down (1).

    blender -b -Y --factory-startup F4U_Corsair_R59.blend --python extract_geometry_r59.py -- OUT.json SHA256

R59 is an approximate visual reconstruction; g1 metrology replaces this file (F4U-05).
"""
import bpy, json, math, sys
from mathutils import Matrix, Vector

out_path, source_sha = sys.argv[sys.argv.index("--") + 1:][:2]
SCALE = 1 / 4.5
X_LE = -2.923   # root leading edge, R59 x (F4U-06 sections: constant for y <= 0.6 m)
Z_THRUST = 2.420  # spinner tip and hub centre height, R59 z
N_PATH = 129
ob = bpy.data.objects
root = ob["F4U CORSAIR | avion completo"]
for o in ob:
    if o.animation_data and o.animation_data.action:
        o.animation_data.action = None
NEUTRAL = ["flaps_deg", "alerones_deg", "compensador_deg", "elevadores_deg", "trim_elevadores_deg", "timon_deg",
           "trim_timon_deg", "cowl_flaps_deg", "tren_retraccion", "gancho_cola_deg"]
for key in NEUTRAL:
    if key in root.keys():
        root[key] = type(root[key])(0)
wings = ob["R51 | CONTROL ALAS"]
for key, value in {"plegado_derecha": 0.0, "plegado_izquierda": 0.0, "bloqueo_derecha": 1.0,
                   "bloqueo_izquierda": 1.0, "puntal_derecha": 0.0, "puntal_izquierda": 0.0}.items():
    wings[key] = value
root.matrix_world = Matrix.Identity(4)
scene = bpy.context.scene


DRIVEN = [o for o in ob if o.animation_data and o.animation_data.drivers]


def settle():
    # Assigning an ID property does not tag its datablock; tag the controls and every driven object so the rig's
    # drivers re-evaluate (a frame change alone refreshes only time-dependent ones).
    for _ in range(3):
        for o in [root, wings] + DRIVEN:
            o.update_tag()
        scene.frame_set(scene.frame_current)
        bpy.context.view_layer.update()
    return bpy.context.evaluated_depsgraph_get()


def le(p):
    return [round(SCALE * (p[0] - X_LE), 6), round(SCALE * p[1], 6), round(SCALE * (p[2] - Z_THRUST), 6)]


def world_points(names, deps):
    pts = []
    for name in names:
        evaluated = ob[name].evaluated_get(deps)
        mesh = evaluated.to_mesh()
        pts.extend(evaluated.matrix_world @ v.co for v in mesh.vertices)
        evaluated.to_mesh_clear()
    return pts


def world_edges(names, deps):
    edges = []
    for name in names:
        evaluated = ob[name].evaluated_get(deps)
        mesh = evaluated.to_mesh()
        points = [evaluated.matrix_world @ v.co for v in mesh.vertices]
        edges.extend((points[e.vertices[0]], points[e.vertices[1]]) for e in mesh.edges)
        evaluated.to_mesh_clear()
    return edges


def hits(edges, axis, value):
    out = []
    for a, b in edges:
        da, db = a[axis] - value, b[axis] - value
        if da == db or da * db > 0:
            continue
        out.append(a.lerp(b, da / (da - db)))
    return out


def section(edges, axis, value):
    pts = hits(edges, axis, value)
    if len(pts) < 4:
        return None
    lead, trail = min(pts, key=lambda p: p.x), max(pts, key=lambda p: p.x)
    other = 2 if axis == 1 else 1
    chord = (trail - lead).length
    if axis == 1:
        incidence = math.degrees(math.atan2(lead.z - trail.z, trail.x - lead.x))
    else:
        incidence = math.degrees(math.atan2(trail.y - lead.y, trail.x - lead.x))
    thickness = max(p[other] for p in pts) - min(p[other] for p in pts)
    mid = (lead + trail) * 0.5
    return {"station": round(SCALE * value if axis == 1 else SCALE * (value - Z_THRUST), 6),
            "le": le(lead), "te": le(trail), "chord": round(SCALE * chord, 6), "incidence_deg": round(incidence, 4),
            "thickness_ratio": round(thickness / chord, 5), "mid": le(mid)}


def sweep(edges, axis, start, stop, step):
    rows, k = [], 0
    while start + k * step <= stop + 1e-9:
        row = section(edges, axis, start + k * step)
        if row:
            rows.append(row)
        k += 1
    return rows


def extent(names, deps):
    pts = world_points(names, deps)
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    return pts, lo, hi


deps = settle()
WING = ["Ala derecha | gaviota invertida", "R51 | Panel exterior derecha", "Flap articulado derecha 1",
        "Flap articulado derecha 2", "Flap articulado derecha 3", "Aleron R8 | derecha"]
STAB = ["Estabilizador derecho", "R11 | elevador derecho"]
FIN = ["R12 | deriva fija", "R12 | timon articulado"]
SURFACES = {"aileron_right": "Aleron R8 | derecha", "flap_right_1": "Flap articulado derecha 1",
            "flap_right_2": "Flap articulado derecha 2", "flap_right_3": "Flap articulado derecha 3",
            "elevator_right": "R11 | elevador derecho"}
geometry = {
    "format": "openrc-f4u-geometry v1",
    "status": "PROVISIONAL: measured on the author's R59 visual master; g1 metrology replaces it (F4U-05)",
    "source": {"file": "F4U_Corsair_R59.blend", "sha256": source_sha, "blender": bpy.app.version_string,
               "script": "research/f4u-corsair/F4U-06/extract_geometry_r59.py"},
    "frame": "le frame [x_aft, y_right, z_up], metres, origin at the root leading edge on the centreline at thrust-line height",
    "scale": {"factor": SCALE, "r59_root_le_x": X_LE, "r59_thrust_z": Z_THRUST},
    "wing_sections": sweep(world_edges(WING, deps), 1, 0.02, 6.24, 0.04),
    "stabilizer_sections": sweep(world_edges(STAB, deps), 1, 0.02, 2.54, 0.04),
    "fin_sections": sweep(world_edges(FIN, deps), 2, 2.80, 4.78, 0.04),
    "surfaces": {},
}
for key, name in SURFACES.items():
    edges = world_edges([name], deps)
    _, lo, hi = extent([name], deps)
    rows = sweep(edges, 1, lo[1] + 0.02, hi[1] - 0.02, 0.04)
    geometry["surfaces"][key] = {"object": name, "span": [round(SCALE * lo[1], 6), round(SCALE * hi[1], 6)],
                                 "sections": [{"station": r["station"], "le": r["le"], "te": r["te"], "chord": r["chord"]} for r in rows]}
rudder_edges = world_edges(["R12 | timon articulado"], deps)
_, lo, hi = extent(["R12 | timon articulado"], deps)
geometry["surfaces"]["rudder"] = {"object": "R12 | timon articulado", "span_z": [round(SCALE * (lo[2] - Z_THRUST), 6), round(SCALE * (hi[2] - Z_THRUST), 6)],
                                  "sections": [{"station": r["station"], "le": r["le"], "te": r["te"], "chord": r["chord"]}
                                               for r in sweep(rudder_edges, 2, lo[2] + 0.02, hi[2] - 0.02, 0.04)]}

# Fuselage stations: the main shell and the cowl, width and vertical extent every 0.1 m (full size).
fuse_edges = world_edges(["Fuselaje | volumen continuo", "Capot radial | boca abierta y labio redondeado"], deps)
stations = []
x = -4.55
while x <= 5.14:
    pts = hits(fuse_edges, 0, x)
    if len(pts) >= 4:
        stations.append({"x": round(SCALE * (x - X_LE), 6), "half_width": round(SCALE * max(abs(p.y) for p in pts), 6),
                         "top": round(SCALE * (max(p.z for p in pts) - Z_THRUST), 6), "bottom": round(SCALE * (min(p.z for p in pts) - Z_THRUST), 6)})
    x += 0.1
geometry["fuselage_stations"] = stations
spinner_pts, s_lo, s_hi = extent(["Tapa hidromatica | perfil alargado", "Asiento tapon frontal"], deps)
hub_pts, h_lo, h_hi = extent(["Buje | cuerpo fundido continuo"], deps)
blade_pts, b_lo, b_hi = extent([f"Helice referencia | pala {i}" for i in range(1, 5)], deps)
hub_centre = Vector(((b_lo[0] + b_hi[0]) / 2, 0.0, Z_THRUST))
tip_radius = max(math.hypot(p.y, p.z - Z_THRUST) for p in blade_pts)
cowl_pts, c_lo, c_hi = extent(["Capot radial | boca abierta y labio redondeado"], deps)
canopy_pts, cn_lo, cn_hi = extent(["Cubierta R7 | acrilico curvo"], deps)
canopy_top = max(canopy_pts, key=lambda p: p.z)
geometry["nose"] = {
    "spinner_tip": le(Vector((s_lo[0], 0.0, Z_THRUST))),
    "spinner_back_x": round(SCALE * (s_hi[0] - X_LE), 6),
    "spinner_radius": round(SCALE * max(s_hi[1], -s_lo[1]), 6),
    "propeller_plane": le(hub_centre),
    "propeller_visual_diameter": round(SCALE * 2 * tip_radius, 6),
    "propeller_visual_blades": 4,
    "cowl_front_x": round(SCALE * (c_lo[0] - X_LE), 6), "cowl_rear_x": round(SCALE * (c_hi[0] - X_LE), 6),
    "cowl_half_width": round(SCALE * c_hi[1], 6),
}
geometry["canopy_top"] = le(canopy_top)
exhausts = [n for n in ob.keys() if n.startswith("Escape oval hueco")]
geometry["exhaust_exits"] = {n: le(Vector([(a + b) / 2 for a, b in zip(*extent([n], deps)[1:])])) for n in sorted(exhausts)}
geometry["lights"] = {n: le(Vector([(a + b) / 2 for a, b in zip(*extent([n], deps)[1:])])) for n in ["Luz de posicion R8 | derecha", "Luz de posicion R8 | izquierda"]}

# Crash hull points from the neutral meshes.
wing_pts = world_points(["R51 | Panel exterior derecha"], deps)
tip = max(wing_pts, key=lambda p: p.y)
tip_band = [p for p in wing_pts if p.y > tip.y - 0.25]
stab_pts = world_points(["Estabilizador derecho", "R11 | elevador derecho"], deps)
stab_tip = max(stab_pts, key=lambda p: p.y)
fin_pts = world_points(FIN, deps)
fus_pts = world_points(["Fuselaje | volumen continuo"], deps)
rudder_pts = world_points(["R12 | timon articulado"], deps)
geometry["hull"] = {
    "wing_tip_le": le(min(tip_band, key=lambda p: p.x)), "wing_tip_te": le(max(tip_band, key=lambda p: p.x)),
    "wing_tip": le(tip), "stab_tip": le(stab_tip), "fin_top": le(max(fin_pts, key=lambda p: p.z)),
    "rudder_bottom_te": le(max((p for p in rudder_pts if p.z < min(q.z for q in rudder_pts) + 0.15), key=lambda p: p.x)),
    "tail_end": le(max(fus_pts, key=lambda p: p.x)), "belly": le(min(fus_pts, key=lambda p: p.z)),
    "cowl_bottom": le(min(cowl_pts, key=lambda p: p.z)),
}

# Gear: down-pose geometry, then rigid material-point paths through R59's retraction rig.
TYRES = {"main_left": "R22 | neumatico principal izquierda", "main_right": "R22 | neumatico principal derecha", "tail": "R27 | neumatico cola"}


def tyre_vertices(name, deps_):
    evaluated = ob[name].evaluated_get(deps_)
    mesh = evaluated.to_mesh()
    pts = [evaluated.matrix_world @ v.co for v in mesh.vertices]
    evaluated.to_mesh_clear()
    return pts


down = {k: tyre_vertices(n, deps) for k, n in TYRES.items()}
contact_index = {k: min(range(len(p)), key=lambda i: p[i].z) for k, p in down.items()}
gear = {}
for k, pts in down.items():
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    centre = Vector([(a + b) / 2 for a, b in zip(lo, hi)])
    gear[k] = {"object": TYRES[k], "centre_down": le(centre), "contact_down": le(pts[contact_index[k]]),
               "radius": round(SCALE * (hi[2] - lo[2]) / 2, 6), "width": round(SCALE * (hi[1] - lo[1]), 6), "path": [], "centre_path": []}
for i in range(N_PATH):
    extension = i / (N_PATH - 1)
    root["tren_retraccion"] = 1.0 - extension
    d = settle()
    for k, name in TYRES.items():
        pts = tyre_vertices(name, d)
        lo = [min(p[j] for p in pts) for j in range(3)]
        hi = [max(p[j] for p in pts) for j in range(3)]
        gear[k]["path"].append(le(pts[contact_index[k]]))
        gear[k]["centre_path"].append(le(Vector([(a + b) / 2 for a, b in zip(lo, hi)])))
root["tren_retraccion"] = 0.0
settle()
for k in gear:
    gear[k]["path_end_error_m"] = round(max(abs(a - b) for a, b in zip(gear[k]["path"][-1], gear[k]["contact_down"])), 9)
geometry["gear"] = {"samples": N_PATH, "extension": "0 = stowed, 1 = down and locked; R59 tren_retraccion = 1 - extension", "wheels": gear}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(geometry, f, indent=1)
    f.write("\n")
print("GEOMETRY", len(geometry["wing_sections"]), "wing,", len(geometry["fuselage_stations"]), "fuselage stations;",
      {k: v["path_end_error_m"] for k, v in gear.items()})
