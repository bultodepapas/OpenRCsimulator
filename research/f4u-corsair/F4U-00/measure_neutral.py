"""Pose the R59 rig neutral in memory (never saved) and measure landmarks in the aircraft frame.
Run: blender -b -Y --factory-startup FILE --python measure_neutral.py -- OUT.json"""
import bpy, json, sys, re
from mathutils import Vector, Matrix

out_path = sys.argv[sys.argv.index("--") + 1]
ob = bpy.data.objects
root = ob["F4U CORSAIR | avion completo"]

# Drop demo actions so drivers read our values.
for o in ob:
    if o.animation_data and o.animation_data.action:
        o.animation_data.action = None

neutral = {"flaps_deg": 0.0, "alerones_deg": 0.0, "compensador_deg": 0.0, "elevadores_deg": 0.0,
           "trim_elevadores_deg": 0.0, "timon_deg": 0.0, "trim_timon_deg": 0.0, "cowl_flaps_deg": 0.0,
           "tren_retraccion": 0.0, "gancho_cola_deg": 0.0}
for k, v in neutral.items():
    if k in root.keys():
        root[k] = type(root[k])(v) if isinstance(root[k], (int, float)) else v
ctl = ob.get("R51 | CONTROL ALAS")
if ctl:
    for k, v in {"plegado_derecha": 0.0, "plegado_izquierda": 0.0, "bloqueo_derecha": 1.0, "bloqueo_izquierda": 1.0,
                 "puntal_derecha": 0.0, "puntal_izquierda": 0.0}.items():
        ctl[k] = v
mv = ob.get("R47 | CONTROL movimiento")
if mv:
    mv["usar_animacion"] = False
    mv["separacion_global"] = 0.0
cg = ob.get("R45 | CONTROL cargas externas")
if cg:
    cg["cargas_interiores"] = 0
    cg["cohetes_visibles"] = False
    cg["mostrar_soportes_vacios"] = False
cab = ob.get("CABINA | apertura 0 cerrada 1 abierta")
cab_props = dict(cab.items()) if cab else None
root.matrix_world = Matrix.Identity(4)
sc = bpy.context.scene
for _ in range(3):
    sc.frame_set(sc.frame_current)
    bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()

# Collections that are not aircraft content.
excl_re = re.compile(r"^(08 Estudio|09 Planos|05A Helice anterior|R3\d \||R4[0-2] \||R51 \| Auditoria|02I \| R58|R45 \||R47 \||Collection$)")
def excluded_coll(o):
    return any(excl_re.search(c.name) for c in o.users_collection)

def lc_visible(o):
    # Collection-level render visibility (any containing collection hidden -> hidden)
    return not any(c.hide_render for c in o.users_collection)

meshes = []
for o in ob:
    if o.type not in ("MESH", "CURVE", "FONT"):
        continue
    if o.name not in bpy.context.view_layer.objects:
        continue
    eo = o.evaluated_get(dg)
    if eo.hide_render or not lc_visible(o):
        continue
    try:
        me = eo.to_mesh()
    except Exception:
        continue
    if me is None or not me.vertices:
        eo.to_mesh_clear(); continue
    me.calc_loop_triangles()
    mw = eo.matrix_world
    pts = [mw @ v.co for v in me.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    meshes.append({"name": o.name, "type": o.type, "coll": o.users_collection[0].name if o.users_collection else "",
                   "excluded": excluded_coll(o), "tris": len(me.loop_triangles),
                   "lo": [round(x, 5) for x in lo], "hi": [round(x, 5) for x in hi]})
    eo.to_mesh_clear()

air = [m for m in meshes if not m["excluded"]]
def bbox(ms):
    lo = [min(m["lo"][i] for m in ms) for i in range(3)]
    hi = [max(m["hi"][i] for m in ms) for i in range(3)]
    return [[round(x, 4) for x in lo], [round(x, 4) for x in hi]]

res = {
    "root_props_after": {k: root[k] for k in neutral if k in root.keys()},
    "cabin_ctl": {k: (v if isinstance(v, (int, float, str)) else str(v)) for k, v in (cab_props or {}).items()},
    "aircraft_bbox": bbox(air),
    "aircraft_tris": sum(m["tris"] for m in air),
    "aircraft_meshes": len(air),
    "excluded_visible": len(meshes) - len(air),
    "excluded_tris": sum(m["tris"] for m in meshes if m["excluded"]),
    "by_coll": {},
    "meshes": meshes,
}
for m in air:
    e = res["by_coll"].setdefault(m["coll"], [0, 0])
    e[0] += 1; e[1] += m["tris"]
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(res, f, indent=1, ensure_ascii=False)
print("NEUTRAL bbox", res["aircraft_bbox"], "tris", res["aircraft_tris"], "meshes", res["aircraft_meshes"],
      "excluded", res["excluded_visible"], res["excluded_tris"])
