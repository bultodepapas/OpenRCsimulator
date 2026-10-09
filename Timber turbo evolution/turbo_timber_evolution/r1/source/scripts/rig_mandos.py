"""
Rig de las superficies de mando del Turbo Timber Evolution (Blender).

- Un empty "Mandos" con deslizadores (propiedades personalizadas, en grados):
    alerones  (+ = alabeo a la derecha: aleron derecho sube, izquierdo baja)
    elevador  (+ = borde de salida arriba, nariz arriba)
    timon     (+ = borde de salida a la derecha, guinada a la derecha)
    flaps     (+ = bajan)
    diferencial (0-1: cuanto baja el aleron respecto de lo que sube)
- Cada superficie cuelga de un empty "Bisagra_*" cuyo eje X local es la linea de bisagra.
- Las varillas son cilindros con restriccion Stretch To hacia el agujero del cuerno, asi siguen
  el movimiento. La rueda de cola gira con el timon.
"""
import bpy, math
from mathutils import Vector, Euler

S = 0.001   # mm -> m

def _empty(nombre, padre, loc, rot=(0, 0, 0), tipo='ARROWS', tam=0.02):
    e = bpy.data.objects.new(nombre, None)
    bpy.context.scene.collection.objects.link(e)
    e.empty_display_type = tipo; e.empty_display_size = tam
    e.parent = padre; e.location = loc; e.rotation_euler = rot
    return e

def _rot_para_eje(d):
    d = Vector(d).normalized()
    el = -math.asin(max(-1, min(1, d.z))); az = math.atan2(d.y, d.x)
    return (0.0, el, az)            # XYZ: el eje X local queda sobre la bisagra

def _prop(obj, nombre, valor, mini, maxi, desc):
    obj[nombre] = float(valor)
    ui = obj.id_properties_ui(nombre)
    ui.update(min=mini, max=maxi, soft_min=mini, soft_max=maxi, description=desc, subtype='NONE')

def _driver(obj, expr, vars_):
    fc = obj.driver_add("rotation_euler", 0); d = fc.driver; d.type = 'SCRIPTED'
    for nombre, (id_, ruta) in vars_.items():
        v = d.variables.new(); v.name = nombre; v.type = 'SINGLE_PROP'
        v.targets[0].id = id_; v.targets[0].data_path = ruta
    d.expression = expr
    return fc

def montar(cfg, avion, materiales):
    sc = bpy.context.scene
    m = cfg["mandos"]
    mandos = _empty("Mandos", avion, (0.25, 0, 0.35), tipo='SINGLE_ARROW', tam=0.12)
    _prop(mandos, "alerones", m["alerones"], -m["max_alerones"], m["max_alerones"], "Alabeo: + derecha (grados de subida)")
    _prop(mandos, "elevador", m["elevador"], -m["max_elevador"], m["max_elevador"], "+ = borde de salida arriba (grados)")
    _prop(mandos, "timon", m["timon"], -m["max_timon"], m["max_timon"], "+ = guinada derecha (grados)")
    _prop(mandos, "flaps", m["flaps"], 0.0, m["max_flaps"], "Bajada de flaps (grados)")
    _prop(mandos, "diferencial", m["diferencial"], 0.0, 1.0, "Bajada del aleron / subida (diferencial)")
    V = lambda *n: {k: (mandos, f'["{k}"]') for k in n}
    # rotacion positiva alrededor del eje de bisagra = borde de salida abajo (alas y elevador)
    expr = {
        "aleron_der": ("radians(-max(alerones, 0) + diferencial*max(-alerones, 0))", V("alerones", "diferencial")),
        "aleron_izq": ("radians(diferencial*max(alerones, 0) - max(-alerones, 0))", V("alerones", "diferencial")),
        "flap_der":   ("radians(flaps)", V("flaps")),
        "flap_izq":   ("radians(flaps)", V("flaps")),
        "elevador":   ("radians(-elevador)", V("elevador")),
        "timon":      ("radians(timon)", V("timon")),
        "rueda_cola": ("radians(timon)", V("timon")),     # coaxial con el timon, misma relacion (v7)
    }
    bis = {}
    bpy.context.view_layer.update()
    for g, info in cfg["bisagras"].items():
        e = _empty("Bisagra_" + g, avion, Vector(info["p"])*S, _rot_para_eje(info["d"]))
        bis[g] = e
    bpy.context.view_layer.update()
    for g, info in cfg["bisagras"].items():
        e = bis[g]
        extra = {"aleron_der": ["cuerno_aleron_der"], "aleron_izq": ["cuerno_aleron_izq"],
                 "flap_der": ["cuerno_flap_der"], "flap_izq": ["cuerno_flap_izq"],
                 "elevador": ["cuerno_elevador"], "timon": ["cuerno_timon"]}.get(g, [])
        for nombre in info["miembros"] + extra:
            o = bpy.data.objects.get(nombre)
            if o is None or o.parent == e: continue
            mw = o.matrix_world.copy(); o.parent = e; o.matrix_world = mw
        _driver(e, *expr[g])
    # varillas con Stretch To
    acero = materiales.get("cromo")
    for g, v in cfg["varillas"].items():
        p0 = Vector(v["servo"])*S; p1 = Vector(v["cuerno"])*S
        objetivo = _empty("Agujero_" + g, avion, p1, tipo='SPHERE', tam=0.002)
        bpy.context.view_layer.update()
        mw = objetivo.matrix_world.copy(); objetivo.parent = bis[g]; objetivo.matrix_world = mw
        L = (p1 - p0).length
        bpy.ops.mesh.primitive_cylinder_add(radius=v["r"]*S, depth=L, vertices=12)
        o = bpy.context.object; o.name = "varilla_" + g
        # cilindro a lo largo de +Y desde el origen
        for vert in o.data.vertices:
            x, y, z = vert.co
            vert.co = Vector((x, z + L/2, -y))
        o.parent = avion; o.location = p0
        o.rotation_euler = (p1 - p0).to_track_quat('Y', 'Z').to_euler()
        if "pivote" in v:
            # el brazo del servo gira con la superficie (relacion de brazos) y arrastra la varilla
            sv = _empty("Servo_" + g, avion, Vector(v["pivote"])*S, _rot_para_eje(v["d"]), tam=0.01)
            ex, vs = expr[g]
            _driver(sv, f"{v['relacion']:.3f}*" + ex, vs)
            bpy.context.view_layer.update()
            for n in (v["brazo"], o.name):
                ob = bpy.data.objects[n]; mw = ob.matrix_world.copy(); ob.parent = sv; ob.matrix_world = mw
        if acero: o.data.materials.append(acero)
        c = o.constraints.new('STRETCH_TO'); c.target = objetivo; c.rest_length = L; c.volume = 'NO_VOLUME'
        # horquilla (clevis) en la punta: pequena pieza que sigue al cuerno
        bpy.ops.mesh.primitive_cube_add(size=1)
        h = bpy.context.object; h.name = "horquilla_" + g; h.scale = (0.006, 0.0035, 0.0035)
        bpy.ops.object.transform_apply(scale=True)
        h.parent = objetivo; h.location = (0, 0, 0)
        if acero: h.data.materials.append(acero)
    # animacion de prueba de mandos (frames 1-240)
    claves = [(1, 0, 0, 0, 0), (30, 22, 0, 0, 0), (60, -22, 0, 0, 0), (80, 0, 0, 0, 0), (105, 0, 20, 0, 0),
              (130, 0, -20, 0, 0), (150, 0, 0, 0, 0), (175, 0, 0, 30, 0), (200, 0, 0, -30, 0), (215, 0, 0, 0, 0),
              (230, 0, 0, 0, 40), (240, 0, 0, 0, 0)]
    for f, a, e_, t, fl in claves:
        for k, val in (("alerones", a), ("elevador", e_), ("timon", t), ("flaps", fl)):
            mandos[k] = float(val); mandos.keyframe_insert(f'["{k}"]', frame=f)
    sc.frame_start, sc.frame_end = 1, 240
    for k, val in (("alerones", m["alerones"]), ("elevador", m["elevador"]), ("timon", m["timon"]), ("flaps", m["flaps"])):
        mandos[k] = float(val)
    sc.frame_set(1)
    return mandos, bis
