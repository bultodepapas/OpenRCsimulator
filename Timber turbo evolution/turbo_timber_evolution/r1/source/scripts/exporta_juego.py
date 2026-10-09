"""
Version de juego del Turbo Timber Evolution para OpenRC Simulator (Godot).

Construye la escena de exportacion a partir de las mallas livianas (stl_juego, coordenadas CAD
"sidecar": mm, X hacia atras, Y hacia el ala derecha, Z arriba, origen en el borde de ataque de la
raiz a la altura del eje de traccion) y escribe:
  export/aircraft.glb        avion neutro (sin animaciones)
  export/aircraft_demo.glb   mismo avion + animacion de referencia de cada articulacion
  source/aircraft.blend
  _export_data.json          datos medidos en la escena (landmarks, pivotes, conteos) para metadata.json

Marco de autoria de la exportacion (Blender): metros, +X derecha, +Y adelante (nariz), +Z arriba.
El exportador glTF (+Y arriba) lo convierte en: +X derecha, +Y arriba, nariz hacia -Z, que es la
convencion del simulador. Conversion CAD -> Blender export: (x, y, z)mm -> (y, -x, z)/1000.
"""
import bpy, bmesh, math, json, os, sys
from mathutils import Vector, Matrix, Quaternion, Euler

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import mapa
PKG = sys.argv[sys.argv.index("--pkg") + 1]
STL = os.path.join(BASE, "stl_juego")
META = json.load(open(os.path.join(BASE, "..", "modelo_v12.py.brep", "ok.json")))
ESC = json.load(open(os.path.join(BASE, "..", "stl_v12", "escena.json")))
X_BA = META["X_BA"]

CAD2EXP = Matrix(((0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1))) @ Matrix.Scale(0.001, 4)
def p_cad(p):            # punto CAD sidecar (mm) -> export (m)
    return (CAD2EXP @ Vector((p[0], p[1], p[2], 1.0))).xyz
def d_cad(d):            # direccion CAD -> export (unitaria)
    return Vector((d[1], -d[0], d[2])).normalized()
def p_foto(p):           # punto CAD "de foto" (x desde el plano de la helice) -> export
    return p_cad((p[0] - X_BA, p[1], p[2]))
def a_sim(v):            # export Blender -> marco del simulador (+X der, +Y arriba, nariz -Z)
    return [round(v[0], 6), round(v[2], 6), round(-v[1], 6)]

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0
col = bpy.data.collections.new("EXPORT_aircraft"); sc.collection.children.link(col)

# ---------------- materiales consolidados (sobreviven a glTF: Principled BSDF basico) ----------------
def material(nombre, color, rough, metal=0.0, alpha=1.0, emis=0.0):
    m = bpy.data.materials.new(nombre); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1); b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal; b.inputs["Alpha"].default_value = alpha
    if emis:
        b.inputs["Emission Color"].default_value = (*color, 1); b.inputs["Emission Strength"].default_value = emis
    if alpha < 1.0:
        try: m.surface_render_method = 'BLENDED'
        except Exception: m.blend_method = 'BLEND'
    m.diffuse_color = (*color, alpha)
    return m
MAT = {"white": material("white", (0.85, 0.85, 0.84), 0.40), "red": material("red", (0.45, 0.012, 0.008), 0.42),
       "black": material("black", (0.018, 0.018, 0.02), 0.50), "light_grey": material("light_grey", (0.45, 0.46, 0.48), 0.45),
       "dark_grey": material("dark_grey", (0.06, 0.06, 0.065), 0.50), "metal": material("metal", (0.80, 0.80, 0.82), 0.25, metal=1.0),
       "glass": material("glass", (0.20, 0.23, 0.26), 0.08, alpha=0.45), "foam": material("foam", (0.02, 0.02, 0.02), 0.95),
       "light_red": material("light_red", (0.9, 0.05, 0.03), 0.3, emis=3.0), "light_green": material("light_green", (0.1, 0.9, 0.2), 0.3, emis=3.0)}

# separacion anti z-fighting (m): 0.12 mm por nivel de prioridad de calcomania; vidrios y soportes 0.12 mm
INFLADO = {n: 0.00012 * max(1, mapa.prioridad(n)) for n in mapa.CALCOS}
INFLADO.update({n: 0.00012 for n in ("parabrisas", "ventanas", "soporte_tren_der", "soporte_tren_izq")})
INFLADO["fuselaje_panza_roja"] = 0.0002      # panza roja (sin las franjas que la invadian) por encima del casco blanco
INFLADO["aleta_dorsal"] = -0.0008            # aleta dorsal 0.8 mm adentro: las franjas de la deriva la cruzan
INFLADO.update({"panel_nariz": 0.0009, "filete_nariz": 0.0006, "franja_negra_cola": 0.0007})   # ajustes medidos con verifica_glb
def importar(nombre):
    bpy.ops.wm.stl_import(filepath=os.path.join(STL, nombre + ".stl"))
    o = bpy.context.selected_objects[0]; o.name = nombre
    o.data.transform(CAD2EXP); o.data.update()
    eps = INFLADO.get(nombre, 0.0)
    if eps:
        # calcomanias / vidrios: se separan eps a lo largo de la normal de vertice para que ninguna cara
        # quede coplanar (misma orientacion) con la piel de abajo -> sin z-fighting en el motor
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6); bm.normal_update()
        for v in bm.verts: v.co += v.normal * eps
        bm.to_mesh(o.data); bm.free()
    mat = mapa.MATERIAL_FORZADO.get(nombre) or mapa.PALETA[META["materiales"][nombre]]
    o.data.materials.clear(); o.data.materials.append(MAT[mat])
    return o

def unir(objs, nombre):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1: bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active; o.name = nombre; o.data.name = nombre + "_mesh"
    # limpieza: vertices duplicados del STL, caras degeneradas, normales consistentes, suavizado por angulo
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    # caras de area (casi) nula que quedan del STL (astillas de 1e-10 m2): se eliminan
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_area() < 1e-10], context='FACES_ONLY')
    # triangular aqui (y no en el exportador) para poder quitar los triangulos nulos que salen de n-gonos
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_area() < 1e-10], context='FACES_ONLY')
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_edges], context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data); bm.free()
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    for c in o.users_collection: c.objects.unlink(o)
    col.objects.link(o)
    return o

def nodo(nombre, padre, pos, eje=None, props=None):
    """empty-pivote; local +X = eje de giro (regla de la mano derecha = sentido positivo)"""
    e = bpy.data.objects.new(nombre, None); col.objects.link(e)
    e.empty_display_type = 'ARROWS'; e.empty_display_size = 0.03
    R = Matrix.Identity(3)
    if eje is not None:
        X = Vector(eje).normalized()
        ref = Vector((0, 0, 1)) if abs(X.z) < 0.9 else Vector((0, -1, 0))
        Z = (ref - X*ref.dot(X)).normalized(); Y = Z.cross(X)
        R = Matrix((X, Y, Z)).transposed()
    mw = Matrix.Translation(pos) @ R.to_4x4()
    if padre is not None:
        e.parent = padre; e.matrix_parent_inverse = Matrix.Identity(4)
        e.matrix_basis = padre.matrix_world.inverted() @ mw
    else:
        e.matrix_basis = mw
    e.rotation_mode = 'QUATERNION'; e.rotation_quaternion = e.matrix_basis.to_quaternion()
    for k, v in (props or {}).items(): e[k] = v
    bpy.context.view_layer.update()
    return e

def colgar(malla, pivote):
    """la malla queda con transformacion identidad respecto de su pivote (geometria re-expresada)"""
    bpy.context.view_layer.update()
    malla.data.transform(pivote.matrix_world.inverted() @ malla.matrix_world)
    malla.parent = pivote; malla.matrix_parent_inverse = Matrix.Identity(4); malla.matrix_basis = Matrix.Identity(4)

# ---------------- raiz y estructura fija ----------------
root = nodo("TurboTimberEvolution", None, Vector((0, 0, 0)),
            props={"datum": "D0: wing-root leading-edge station x symmetry plane x CAD thrust-axis height",
                   "units": "m", "pose": "neutral body pose (no ground presentation offset or attitude)"})
roles = {}
for rol, (piezas, _) in mapa.ROLES.items():
    if piezas: roles[rol] = unir([importar(n) for n in piezas], rol)

# cables y resortes de bajo poligonaje (solo pose de reposo; extremos documentados en metadata)
def cilindro(a, b, r, lados, nombre):
    a, b = Vector(a), Vector(b); d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=lados, radius=r, depth=d.length, location=(a + b)/2)
    o = bpy.context.object; o.name = nombre
    o.rotation_mode = 'QUATERNION'; o.rotation_quaternion = d.to_track_quat('Z', 'Y')
    bpy.context.view_layer.update(); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.data.materials.append(MAT["metal"]); return o
cables = []
for nom, c in ESC["tren"]["cables"].items():
    F, E = p_cad(c["ojal"]), p_cad(c["anclaje"]); u = (E - F).normalized()
    Lw = c["largo_cable"]/1000.0
    cables.append(cilindro(F, F + u*Lw, 0.0006, 6, f"cable_{nom}"))
    cables.append(cilindro(F + u*Lw, E, 0.0040, 10, f"spring_{nom}"))
roles["gear_cables"] = unir(cables, "gear_cables")
colgar(roles["airframe"], root); colgar(roles["gear_cables"], root)

# ---------------- articulaciones ----------------
M = ESC["mandos"]; G = META["grupos"]
ART = {}
def articulacion(ident, rol, padre, pos_exp, eje_exp, rango, positivo, fuente, mando, extra=None):
    props = {"articulation": ident, "axis_local": "+X", "rotation_rule": "right-hand about local +X",
             "positive": positivo, "range_source": fuente, "driven_by": mando}
    if rango[0] is not None: props.update(min_deg=rango[0], max_deg=rango[1])
    else: props["continuous"] = True
    if rol and eje_exp is not None:
        # pivote = punto del eje mas cercano al centro de la pieza movil (mismo eje, posicion legible)
        o = roles[rol]; bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        cen = sum(bb, Vector()) / 8.0; u = Vector(eje_exp).normalized()
        pos_exp = Vector(pos_exp) + u * (cen - Vector(pos_exp)).dot(u)
    piv = nodo(ident, padre, pos_exp, eje_exp, props)
    if rol: colgar(roles[rol], piv)
    ART[ident] = dict(pivot_m=pos_exp, axis=eje_exp, parent=padre.name if padre else None, mesh=rol, range_deg=list(rango),
                      positive=positivo, range_source=fuente, driven_by=mando, **(extra or {}))
    return piv

AUT = "authored approximation (no manufacturer manual available to the modeler)"
for lado_cad, lado in (("izq", "left"), ("der", "right")):
    g = G["aleron_" + lado_cad]
    articulacion(f"aileron_{lado}_hinge", f"aileron_{lado}", root, p_cad(g["p"]), d_cad(g["d"]),
                 (-M["max_alerones"], M["max_alerones"]), "trailing edge down", AUT,
                 "roll: right stick -> right aileron negative (up), left aileron positive (down); authored differential 0.7 (down travel = 0.7 x up travel)")
    g = G["flap_" + lado_cad]
    articulacion(f"flap_{lado}_hinge", f"flap_{lado}", root, p_cad(g["p"]), d_cad(g["d"]),
                 (0.0, M["max_flaps"]), "trailing edge down", AUT, "flap channel (both flaps equal)")
g = G["elevador"]
articulacion("elevator_hinge", "elevator", root, p_cad(g["p"]), d_cad(g["d"]),
             (-M["max_elevador"], M["max_elevador"]), "trailing edge down (nose-down pitch)", AUT,
             "pitch: stick back (nose up) -> negative; single one-piece elevator joined by a torsion rod")
g = G["timon"]
rud = articulacion("rudder_hinge", "rudder", root, p_cad(g["p"]), d_cad(g["d"]),
                   (-M["max_timon"], M["max_timon"]), "trailing edge to the pilot's right (nose right)", AUT, "yaw: right pedal -> positive")
# tren de cola: pivote de direccion coaxial con el timon (sigue al timon 1:1), eje de rodadura propio
g = G["rueda_cola"]; rc = ESC["tren"]["rueda_cola"]
st = articulacion("tailwheel_steer", "tailwheel_fork", root, p_cad(g["p"]), d_cad(g["d"]),
                  (-M["max_timon"], M["max_timon"]), "same sense as rudder (wheel trails to the right)", AUT,
                  "coupled to rudder_hinge 1:1 (wire tip sits inside the rudder)")
articulacion("tailwheel_axle", "tailwheel", st, p_cad(rc["centro"]), d_cad((0, -1, 0)), (None, None),
             "forward rolling", "continuous", "ground contact (rolling without slip, radius %.1f mm)" % rc["radio"],
             {"radius_m": rc["radio"]/1000.0})
# helice: marco fijo del eje (caida y derecha) + rotor que gira
mo = ESC["motor"]; hub = p_cad(mo["buje"])
f = Euler((0, math.radians(-mo["caida"]), math.radians(-mo["derecha"])), 'XYZ').to_matrix() @ Vector((-1, 0, 0))
thrust_dir = d_cad(f)
tf = nodo("thrust_frame", root, hub, thrust_dir, {"fixed": True, "downthrust_deg": mo["caida"], "right_thrust_deg": mo["derecha"],
                                                  "note": "fixed shaft orientation; +X = thrust direction"})
articulacion("propeller_spin", "propeller_rotor", tf, hub, thrust_dir, (None, None),
             "normal tractor rotation: clockwise seen from behind (pilot view)", "continuous", "throttle / motor rpm")
ART["thrust_frame"] = dict(pivot_m=hub, axis=thrust_dir, parent=root.name, mesh=None, fixed=True)
# tren principal: suspension (patas que se abren) + eje de rueda
T = ESC["tren"]
for lado_cad, lado, sg in (("izq", "left", -1), ("der", "right", 1)):
    pv = p_cad(T["pivotes"][lado_cad]); eje_s = d_cad((sg, 0, 0))     # derecha: +atras; izquierda: -atras
    leg = articulacion(f"gear_{lado}_suspension", f"gear_{lado}_leg", root, pv, eje_s, (0.0, 12.0),
                       "leg swings outboard (compression)", AUT + "; cross-wire springs limit it",
                       "ground load (suspension); springs: cross cables with tension springs, see metadata")
    articulacion(f"wheel_{lado}_axle", f"wheel_{lado}", leg, p_cad(T["ruedas"][lado_cad]), d_cad((0, -1, 0)), (None, None),
                 "forward rolling", "continuous", "ground contact (rolling without slip, radius %.1f mm)" % T["radio_rueda"],
                 {"radius_m": T["radio_rueda"]/1000.0})

# ---------------- comprobaciones y conteos ----------------
bpy.context.view_layer.update()
mallas = [o for o in col.objects if o.type == 'MESH']
def tri(o): return sum(len(p.vertices) - 2 for p in o.data.polygons)
def superficies(o): return len({p.material_index for p in o.data.polygons})
conteo = {o.name: dict(triangles=tri(o), surfaces=superficies(o), materials=[o.data.materials[i].name for i in sorted({p.material_index for p in o.data.polygons})]) for o in mallas}
def area_cero(o):
    return sum(1 for p in o.data.polygons if p.area < 1e-10)
problemas = {o.name: area_cero(o) for o in mallas if area_cero(o)}

def pts(nombres):
    out = []
    for n in nombres:
        o = bpy.data.objects[n]; out += [o.matrix_world @ v.co for v in o.data.vertices]
    return out
P_all = pts([o.name for o in mallas])
af = pts(["airframe"])
lm = {
    "left_wingtip": min(af, key=lambda v: v.x), "right_wingtip": max(af, key=lambda v: v.x),
    "nose_spinner_tip": max(pts(["propeller_rotor"]), key=lambda v: v.y),
    "tail_rudder_trailing_edge": min(pts(["rudder"]), key=lambda v: v.y),
    "left_main_wheel_center": bpy.data.objects["wheel_left_axle"].matrix_world.translation.copy(),
    "right_main_wheel_center": bpy.data.objects["wheel_right_axle"].matrix_world.translation.copy(),
    "tailwheel_center": bpy.data.objects["tailwheel_axle"].matrix_world.translation.copy(),
    "propeller_hub": hub, "datum_D0": Vector((0, 0, 0)),
}
xs = [v.x for v in P_all]; ys = [v.y for v in P_all]; zs = [v.z for v in P_all]
datos = dict(
    landmarks_export={k: [round(c, 6) for c in v] for k, v in lm.items()},
    landmarks_sim={k: a_sim(v) for k, v in lm.items()},
    bbox_export=dict(min=[min(xs), min(ys), min(zs)], max=[max(xs), max(ys), max(zs)]),
    span_m=round(lm["right_wingtip"].x - lm["left_wingtip"].x, 4),
    length_m=round(lm["nose_spinner_tip"].y - lm["tail_rudder_trailing_edge"].y, 4),
    articulations={k: dict(v, pivot_m=[round(c, 6) for c in v["pivot_m"]], pivot_sim=a_sim(v["pivot_m"]),
                           axis=[round(c, 6) for c in v["axis"]], axis_sim=a_sim(v["axis"]))
                   for k, v in ART.items()},
    mesh_counts=conteo, total_triangles=sum(c["triangles"] for c in conteo.values()),
    total_surfaces=sum(c["surfaces"] for c in conteo.values()), zero_area_faces=problemas,
    blender_version=bpy.app.version_string)
# orientacion de reposo de cada pivote (cuaternion local respecto del padre, w x y z), marco export
for o in col.objects:
    if o.type == 'EMPTY':
        q = o.matrix_basis.to_quaternion()
        datos.setdefault("rest_local_quaternion_wxyz", {})[o.name] = [round(q.w, 6), round(q.x, 6), round(q.y, 6), round(q.z, 6)]
json.dump(datos, open(os.path.join(BASE, "_export_data.json"), "w"), indent=1)

# ---------------- exportar ----------------
os.makedirs(f"{PKG}/export", exist_ok=True); os.makedirs(f"{PKG}/source", exist_ok=True)
def exportar(ruta, anim):
    bpy.ops.object.select_all(action='DESELECT')
    for o in col.objects: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=ruta, export_format='GLB', use_selection=True, export_yup=True,
                              export_apply=True, export_extras=True, export_animations=anim, export_cameras=False,
                              export_lights=False, export_materials='EXPORT')
exportar(f"{PKG}/export/aircraft.glb", False)
bpy.ops.wm.save_as_mainfile(filepath=f"{PKG}/source/aircraft.blend")

# animacion de referencia: cada mando a neutro, +max, neutro, -max, neutro (24 fps)
sc.render.fps = 24; f0 = 1
DEMO = [("aileron_left_hinge", 22), ("aileron_right_hinge", 22), ("flap_left_hinge", 40), ("flap_right_hinge", 40),
        ("elevator_hinge", 22), ("rudder_hinge", 30), ("tailwheel_steer", 30),
        ("gear_left_suspension", 12), ("gear_right_suspension", 12)]
for n, amax in DEMO:
    o = bpy.data.objects[n]; q0 = o.rotation_quaternion.copy()
    neg = 0 if n.startswith(("flap", "gear")) else -amax
    for k, a in enumerate((0, amax, 0, neg, 0)):
        o.rotation_quaternion = q0 @ Quaternion((1, 0, 0), math.radians(a))
        o.keyframe_insert("rotation_quaternion", frame=f0 + 12*k)
    o.rotation_quaternion = q0; f0 += 48
for n in ("propeller_spin", "wheel_left_axle", "wheel_right_axle", "tailwheel_axle"):
    o = bpy.data.objects[n]; q0 = o.rotation_quaternion.copy()
    for k in range(9):
        o.rotation_quaternion = q0 @ Quaternion((1, 0, 0), math.radians(90*k))
        o.keyframe_insert("rotation_quaternion", frame=1 + k*6)
    o.rotation_quaternion = q0
sc.frame_start, sc.frame_end = 1, f0
exportar(f"{PKG}/export/aircraft_demo.glb", True)

def fusionar_animaciones(ruta, nombre="control_demo"):
    """el exportador deja una animacion por nodo; se fusionan en una sola linea de tiempo"""
    import struct
    raw = open(ruta, "rb").read()
    ln = struct.unpack_from("<I", raw, 12)[0]; gl = json.loads(raw[20:20 + ln]); resto = raw[20 + ln:]
    anims = gl.get("animations", [])
    if len(anims) <= 1: return
    canales, muestras = [], []
    for a in anims:
        off = len(muestras); muestras += a["samplers"]
        for c in a["channels"]:
            c = dict(c); c["sampler"] += off; canales.append(c)
    gl["animations"] = [{"name": nombre, "channels": canales, "samplers": muestras}]
    js = json.dumps(gl, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    cuerpo = struct.pack("<II", len(js), 0x4E4F534A) + js + resto
    open(ruta, "wb").write(struct.pack("<III", 0x46546C67, 2, 12 + len(cuerpo)) + cuerpo)
fusionar_animaciones(f"{PKG}/export/aircraft_demo.glb")
print("EXPORT OK", datos["total_triangles"], datos["total_surfaces"], datos["span_m"], datos["length_m"])
