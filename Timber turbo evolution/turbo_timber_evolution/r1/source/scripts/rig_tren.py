"""
Rig del tren de aterrizaje (Blender).

Empty "Tren" con dos propiedades:
  compresion  (0-1): las patas giran sobre su pasador hasta 12 grados hacia afuera; los resortes de
                     los cables cruzados se estiran (Stretch To) y los cables siguen el anclaje.
  rodadura_mm : distancia recorrida; las ruedas principales y la de cola giran sin deslizar.
"""
import bpy, math, os
from mathutils import Vector

S = 0.001
APERTURA_MAX = 12.0     # grados de giro de cada pata con compresion = 1

def _empty(nombre, padre, loc, rot=(0, 0, 0), tipo='ARROWS', tam=0.02):
    e = bpy.data.objects.new(nombre, None); bpy.context.scene.collection.objects.link(e)
    e.empty_display_type = tipo; e.empty_display_size = tam
    e.parent = padre; e.location = loc; e.rotation_euler = rot
    return e

def _reparent(nombre, padre):
    o = bpy.data.objects.get(nombre)
    if o is None: return
    bpy.context.view_layer.update()
    mw = o.matrix_world.copy(); o.parent = padre; o.matrix_world = mw

def _driver(obj, expr, vars_, eje=0):
    d = obj.driver_add("rotation_euler", eje).driver; d.type = 'SCRIPTED'
    for nombre, (id_, ruta) in vars_.items():
        v = d.variables.new(); v.name = nombre; v.type = 'SINGLE_PROP'
        v.targets[0].id = id_; v.targets[0].data_path = ruta
    d.expression = expr

def montar_tren(cfg, avion, materiales, stl_dir):
    t = cfg["tren"]; R = t["radio_rueda"]
    tren = _empty("Tren", avion, Vector(t["pivotes"]["der"])*S*Vector((1, 0, 1)) + Vector((0, 0, -0.12)), tipo='CIRCLE', tam=0.06)
    for k, val, lo, hi, desc in (("compresion", 0.0, 0.0, 1.0, "Carga sobre el tren: abre las patas y estira los resortes"),
                                 ("rodadura_mm", 0.0, -1e6, 1e6, "Distancia recorrida (mm): hace girar las ruedas")):
        tren[k] = float(val); tren.id_properties_ui(k).update(min=lo, max=hi, soft_min=lo, soft_max=min(hi, 5000.0), description=desc)
    V = lambda *n: {k: (tren, f'["{k}"]') for k in n}
    piv, anc = {}, {}
    for nom, s in (("der", 1), ("izq", -1)):
        p = _empty("Pivote_tren_" + nom, avion, Vector(t["pivotes"][nom])*S, tam=0.015)
        _driver(p, f"{s}*radians({APERTURA_MAX}*compresion)", V("compresion"))
        piv[nom] = p
        for n in ("pata_", "perno_eje_", "collarin_", "eslabon_"):
            _reparent(n + nom, p)
        e = _empty("Eje_rueda_" + nom, avion, Vector(t["ruedas"][nom])*S, (0, 0, math.pi/2), tam=0.012)
        _reparent(e.name, p)
        _driver(e, f"-rodadura_mm/{R}", V("rodadura_mm"))       # rueda hacia adelante sin deslizar
        for n in ("neumatico_", "buje_", "arandela_", "tuerca_"):
            _reparent(n + nom, e)
        a = _empty("Anclaje_resorte_" + nom, avion, Vector(t["anclajes"][nom])*S, tipo='SPHERE', tam=0.002)
        _reparent(a.name, p); anc[nom] = a
    # el avion baja lo que suben las ruedas al abrirse las patas (las ruedas siguen apoyadas)
    P = Vector(t["pivotes"]["der"]); C = Vector(t["ruedas"]["der"])
    rr = math.hypot(C.y - P.y, C.z - P.z); phi0 = math.atan2(C.z - P.z, C.y - P.y)
    z0 = avion.location.z
    d = avion.driver_add("location", 2).driver; d.type = 'SCRIPTED'
    v = d.variables.new(); v.name = "compresion"; v.type = 'SINGLE_PROP'
    v.targets[0].id = tren; v.targets[0].data_path = '["compresion"]'
    d.expression = f"{z0:.6f} - {rr*S:.6f}*(sin({phi0:.6f} + radians({APERTURA_MAX}*compresion)) - sin({phi0:.6f}))"
    # cables cruzados: cable rigido + resorte que se estira hasta el anclaje de la pata opuesta
    acero = materiales.get("cromo")
    for nom, c in t["cables"].items():
        for viejo in ("cable_" + nom, "resorte_" + nom):
            o = bpy.data.objects.get(viejo)
            if o: bpy.data.objects.remove(o, do_unlink=True)
        F = Vector(c["ojal"])*S; H = Vector(c["anclaje"])*S; Lw = c["largo_cable"]*S; Ls = c["largo_resorte"]*S
        tr = _empty("Cable_" + nom, avion, F, tam=0.008)
        tr.rotation_euler = (H - F).to_track_quat('Y', 'Z').to_euler()
        k = tr.constraints.new('DAMPED_TRACK'); k.target = anc[c["pata"]]; k.track_axis = 'TRACK_Y'
        bpy.ops.mesh.primitive_cylinder_add(radius=0.55*S, depth=Lw, vertices=10)
        cab = bpy.context.object; cab.name = "cable_" + nom
        for v in cab.data.vertices:
            x, y, z = v.co; v.co = Vector((x, z + Lw/2, -y))
        cab.parent = tr; cab.location = (0, 0, 0); cab.rotation_euler = (0, 0, 0)
        bpy.ops.wm.stl_import(filepath=os.path.join(stl_dir, "_resorte_local.stl"))
        res = bpy.context.selected_objects[0]; res.name = "resorte_" + nom
        res.scale = (S, S, S); bpy.context.view_layer.objects.active = res
        bpy.ops.object.transform_apply(scale=True)
        res.parent = tr; res.location = (0, Lw, 0); res.rotation_euler = (0, 0, 0)
        st = res.constraints.new('STRETCH_TO'); st.target = anc[c["pata"]]; st.rest_length = Ls; st.volume = 'NO_VOLUME'
        if acero:
            cab.data.materials.append(acero); res.data.materials.append(acero)
    # rueda de cola: gira con la rodadura (y sigue dirigiendose con el timon)
    rc = t["rueda_cola"]
    padre = bpy.data.objects.get("Bisagra_rueda_cola") or avion
    ec = _empty("Eje_rueda_cola", avion, Vector(rc["centro"])*S, (0, 0, math.pi/2), tam=0.008)
    _reparent(ec.name, padre)
    _driver(ec, f"-rodadura_mm/{rc['radio']}", V("rodadura_mm"))
    for n in ("rueda_cola", "buje_cola"):
        _reparent(n, ec)
    # animacion: el avion rueda 3 m en 240 cuadros y el tren absorbe dos golpes
    sc = bpy.context.scene
    for f, d in ((1, 0.0), (240, 3000.0)):
        tren["rodadura_mm"] = d; tren.keyframe_insert('["rodadura_mm"]', frame=f)
    fc = tren.animation_data.action.fcurves if hasattr(tren.animation_data.action, "fcurves") else []
    for f, c in ((1, 0.0), (20, 1.0), (35, 0.0), (50, 0.45), (65, 0.0)):
        tren["compresion"] = c; tren.keyframe_insert('["compresion"]', frame=f)
    try:
        for cu in tren.animation_data.action.fcurves:
            if cu.data_path == '["rodadura_mm"]':
                for kp in cu.keyframe_points: kp.interpolation = 'LINEAR'
    except Exception:
        pass
    tren["compresion"] = 0.0; tren["rodadura_mm"] = 0.0
    sc.frame_set(1)
    return tren
