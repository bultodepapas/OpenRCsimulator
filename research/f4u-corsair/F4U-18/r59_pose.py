"""F4U-18: shared R59 helpers. Pose the rig neutral in memory (never saved) and list render-visible aircraft objects.

Neutral as in F4U-00/F4U-06: root at identity, demo actions unassigned, controls and trims zero, gear down, wings
spread and locked, stores and demo motion off. Exclusions follow F4U-00 measure_neutral.py.
"""
import re
import bpy
from mathutils import Matrix

ROOT = "F4U CORSAIR | avion completo"
# Studio, plan scans, superseded propeller, audits, zebra layers, stores, controls.
EXCLUDE = re.compile(r"^(08 Estudio|09 Planos|05A Helice anterior|R3\d \||R4[0-2] \||R51 \| Auditoria|02I \| R58|R45 \||R47 \||Collection$)")
# g1.21 metadata D0_r59_m: centreline x root leading edge x thrust-axis height, R59 root frame.
D0 = (-2.922903537750244, 0.0, 2.4200000762939453)


def pose_neutral():
    ob = bpy.data.objects
    root = ob[ROOT]
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
    for name, values in {"R47 | CONTROL movimiento": {"usar_animacion": False, "separacion_global": 0.0},
                         "R45 | CONTROL cargas externas": {"cargas_interiores": 0, "cohetes_visibles": False,
                                                           "mostrar_soportes_vacios": False}}.items():
        if name in ob:
            for key, value in values.items():
                ob[name][key] = value
    root.matrix_world = Matrix.Identity(4)
    scene = bpy.context.scene
    driven = [o for o in ob if o.animation_data and o.animation_data.drivers]
    # Assigning an ID property does not tag its datablock; tag the controls and every driven object (F4U-06).
    for _ in range(3):
        for o in [root, wings] + driven:
            o.update_tag()
        scene.frame_set(scene.frame_current)
        bpy.context.view_layer.update()
    return bpy.context.evaluated_depsgraph_get()


def collection_paths(scene):
    paths = {}
    def walk(coll, path):
        for child in coll.children:
            paths[child.name] = path + [child.name]
            walk(child, path + [child.name])
    walk(scene.collection, [])
    return paths


def aircraft_objects(deps):
    """Yield (object, evaluated object, collection path) for every render-visible aircraft mesh, curve or text."""
    paths = collection_paths(bpy.context.scene)
    layer = bpy.context.view_layer.objects
    for o in bpy.data.objects:
        if o.type not in ("MESH", "CURVE", "FONT") or o.name not in layer:
            continue
        evaluated = o.evaluated_get(deps)
        if evaluated.hide_render or any(c.hide_render for c in o.users_collection):
            continue
        coll = o.users_collection[0].name if o.users_collection else ""
        path = paths.get(coll, [coll])
        if any(EXCLUDE.search(c.name) for c in o.users_collection) or any(EXCLUDE.search(p) for p in path):
            continue
        yield o, evaluated, path
