"""Construye source/aircraft_game.blend: version de juego de la Skywalker X8 (r1).

Parte del generador parametrico del maestro (x8_skywalker_blender.py, el mismo que produce el
modelo preciso v3) con un teselado mas bajo y dos correcciones (paso de la helice y separacion
de las caras de union). Despues hornea cada pieza en el marco del juego, crea los pivotes y
borra todo lo demas.

Uso (Blender 5.2.2 LTS):
  blender -b --factory-startup --python-exit-code 1 --python build_game.py -- <salida.blend>
o con el modulo bpy 5.2.2:
  python build_game.py <salida.blend>
"""
import sys, os, math, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix, Euler
import x8_skywalker_blender as X
import x8_game_spec as S

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
OUT = os.path.abspath(ARGS[0] if ARGS else os.path.join(HERE, "..", "aircraft_game.blend"))
FLIP = Matrix(((-1, 0, 0, 0), (0, -1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))   # 180 grados en Z
FLIP3 = FLIP.to_3x3()

# ---------------------------------------------------------------------------------------------
# 1) Maestro con teselado de juego, en pose neutra
# ---------------------------------------------------------------------------------------------
X.set_resolution(**S.GAME_RES)
X.build()
ob = bpy.data.objects
sc = bpy.context.scene
rc, ctl = ob["X8_Mando_RC"], ob["X8_Logica_Tapas"]
rc.animation_data_clear()
ctl.animation_data_clear()
rc["profundidad"], rc["alabeo"] = 0.0, 0.0
for k, v in X.GATE_DEFAULTS.items():
    ctl[k] = v
ctl["incluir_camara"], ctl["incluir_paracaidas"] = 1, 1
ctl["bateria_x_mm"] = 228.0           # CG 435 mm con camara y paracaidas (x8_logica_tapas)
for o in (rc, ctl):
    o.update_tag()
sc.frame_set(1)
for o in ob:                          # biseles mas simples en las cajas de equipos
    for m in o.modifiers:
        if m.type == "BEVEL":
            m.segments = 2 if o.name == "X8_Ventana_Camara" else 1
for nm in ("Der", "Izq"):             # el ala de juego no lleva el hueco del servo
    for m in ob[f"X8_Ala_{nm}"].modifiers:
        if m.type == "BOOLEAN":
            m.show_viewport = m.show_render = False
bpy.context.view_layer.update()
for nm in ("Der", "Izq"):
    assert abs(ob[f"X8_Elevon_{nm}"].rotation_euler.x) < 1e-6, "elevon fuera de neutro"
    assert abs(ob[f"X8_Bisagra_Compuerta_{nm}"].rotation_euler.y) < 1e-9, "compuerta abierta"

# ---------------------------------------------------------------------------------------------
# 2) Datum D0 y transformacion maestro -> juego
# ---------------------------------------------------------------------------------------------
S_JOINT = X.P["s_joint"]
X_LE_ROOT = float(X.LE(S_JOINT))                       # borde de ataque en la union ala-centro
HUB_M = ob["X8_Rotor"].matrix_world.translation.copy()
Z_THRUST = HUB_M.z / X.MM                              # altura del eje de empuje (mm)
D0_M = X.to_blender(X_LE_ROOT, 0.0, Z_THRUST)
T = FLIP @ Matrix.Translation(-D0_M)
T3 = T.to_3x3()


def to_game_mm(x_mm, s_mm, z_mm):
    return T @ X.to_blender(x_mm, s_mm, z_mm)


# ---------------------------------------------------------------------------------------------
# 3) Materiales del juego
# ---------------------------------------------------------------------------------------------
GM = {}
for name, d in S.MATERIALS.items():
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*d["color"], 1.0)
    b.inputs["Roughness"].default_value = d["rough"]
    b.inputs["Metallic"].default_value = d["metal"]
    m.diffuse_color = (*d["color"], 1.0)
    m.roughness = d["rough"]
    m.metallic = d["metal"]
    m.use_backface_culling = True
    try:
        m.surface_render_method = "DITHERED"
    except Exception:
        pass
    GM[name] = m

EXPORT = bpy.data.collections.new(S.EXPORT_COLLECTION)
sc.collection.children.link(EXPORT)
GAME = {}


def set_materials(me, order, index_of_poly):
    me.materials.clear()
    for nm in order:
        me.materials.append(GM[nm])
    me.polygons.foreach_set("material_index", index_of_poly)
    me.update()


def dedupe_slots(obj):
    me = obj.data
    names = [m.name for m in me.materials]
    idx = [names[p.material_index] for p in me.polygons]
    order = [n for n in S.MATERIALS if n in set(idx)]
    set_materials(me, order, [order.index(n) for n in idx])


def bake(name, srcs, local=Matrix.Identity(4), default_mat="x8_epo_white"):
    """Une las mallas evaluadas (modificadores aplicados) en el marco local dado."""
    deps = bpy.context.evaluated_depsgraph_get()
    linv = local.inverted()
    pieces = []
    for o in srcs:
        oe = o.evaluated_get(deps)
        me = bpy.data.meshes.new_from_object(oe, preserve_all_data_layers=True, depsgraph=deps)
        M = linv @ T @ oe.matrix_world
        me.transform(M)
        if M.to_3x3().determinant() < 0:
            me.flip_normals()
        if len(me.materials) == 0:
            me.materials.append(GM[default_mat])
        else:
            for i, m in enumerate(me.materials):
                me.materials[i] = GM[S.MASTER_TO_GAME_MATERIAL.get(m.name if m else "", default_mat)]
        t = bpy.data.objects.new(name + "__tmp", me)
        sc.collection.objects.link(t)
        pieces.append(t)
    with bpy.context.temp_override(active_object=pieces[0], object=pieces[0],
                                   selected_objects=pieces, selected_editable_objects=pieces):
        bpy.ops.object.join()
    obj = pieces[0]
    obj.name = name
    obj.data.name = name
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    EXPORT.objects.link(obj)
    dedupe_slots(obj)
    for k in list(obj.data.keys()):
        del obj.data[k]
    return obj


def empty(name, mat_world, display="ARROWS", size=0.06):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = display
    e.empty_display_size = size
    EXPORT.objects.link(e)
    e.rotation_mode = "QUATERNION"
    e.matrix_world = mat_world
    return e


def attach(child, parent):
    """Padre con inversa identidad: la transformacion local es la que se exporta."""
    pw = parent.matrix_world.copy()
    cw = child.matrix_world.copy()
    child.parent = parent
    child.matrix_parent_inverse = Matrix.Identity(4)
    child.matrix_basis = pw.inverted() @ cw
    bpy.context.view_layer.update()


def assign_where(obj, mat_name, pred):
    me = obj.data
    names = [m.name for m in me.materials]
    if mat_name not in names:
        me.materials.append(GM[mat_name])
        names.append(mat_name)
    k = names.index(mat_name)
    n = 0
    for p in me.polygons:
        if pred(p, names[p.material_index]):
            p.material_index = k
            n += 1
    dedupe_slots(obj)
    return n


def bisect(obj, co, no, face_pred):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    faces = [f for f in bm.faces if face_pred(f.calc_center_median(), f.normal)]
    if faces:
        edges = list({e for f in faces for e in f.edges})
        verts = list({v for f in faces for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=faces + edges + verts, plane_co=co, plane_no=no,
                               dist=1e-7)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


# ---------------------------------------------------------------------------------------------
# 4) Raiz y piezas fijas
# ---------------------------------------------------------------------------------------------
root = empty(S.ROOT, Matrix.Identity(4), "PLAIN_AXES", 0.15)
GAME[S.ROOT] = root

core = bake("fuselage_core", [ob["X8_Fuselaje_Central"], ob["X8_Ventana_Camara"],
                              ob["X8_Bisagra_Piano_Der"], ob["X8_Bisagra_Piano_Izq"]])
x_cap_core = (S_JOINT - X.P["rib_w"] / 2 - X.RES["joint_clear"]) * X.MM
n_cap_core = assign_where(core, "x8_foam_interior",
                          lambda p, m: m == "x8_epo_white" and abs(p.normal.x) > 0.999
                          and abs(abs(p.center.x) - x_cap_core) < 3e-4)

equip_names = ["X8_Bateria_6S_5000", "X8_Bandeja_Bateria", "X8_Camara_FPV_VTX",
               "X8_Controlador_Vuelo", "X8_Receptor_Telemetria", "X8_GPS_Brujula", "X8_ESC_60A",
               "X8_Paracaidas_Paquete", "X8_Camara_Mapeo", "X8_Camara_Mapeo_Objetivo",
               "X8_Amortiguador_Camara_1", "X8_Amortiguador_Camara_2", "X8_Servo_Pestillo_9g",
               "X8_Servo_Compuertas_9g"]
equip = bake("bay_equipment", [ob[n] for n in equip_names])
hatch = bake("canopy_hatch", [ob["X8_Tapa_Principal"]])
motor = bake("motor_mount", [ob["X8_Soporte_Motor"], ob["X8_Motor_Estator"]],
             default_mat="x8_black")

HINGE = {}
COVER_RECT = {}
for nm, side, lr in (("Izq", -1, "left"), ("Der", 1, "right")):
    w = bake(f"wing_{lr}_fixed", [ob[f"X8_Ala_{nm}"], ob[f"X8_Punta_Winglet_{nm}"],
                                  ob[f"X8_Costilla_Raiz_{nm}"]])
    # cara de union del ala (queda tapada por la costilla naranja): espuma
    x_cap_w = (S_JOINT + X.P["rib_w"] / 2 + X.RES["joint_clear"]) * X.MM
    n_cap_w = assign_where(w, "x8_foam_interior",
                           lambda p, m: m == "x8_epo_white" and abs(p.normal.x) > 0.98
                           and abs(abs(p.center.x) - x_cap_w) < 1.5e-3)
    # cinta de bisagra como region de material (10 mm del lado del ala)
    Mm = ob[f"X8_Eje_Bisagra_{nm}"].matrix_world.copy()
    Mg = T @ Mm
    h0 = Mg.translation.copy()
    Xh, Yh, Zh = (Mg.to_3x3().col[i].normalized() for i in range(3))      # Y hacia atras
    yh = lambda c: (c - h0).dot(Yh)
    bisect(w, h0 - 0.010 * Yh, Yh, lambda c, n: -0.030 < yh(c) < 0.004)
    n_tape_w = assign_where(w, "x8_black", lambda p, m: m == "x8_epo_white"
                            and p.normal.dot(Zh) > 0.2 and -0.010 < yh(Vector(p.center)) < 0.0005)
    # pared de la ranura del lado del ala (mira hacia atras, junto al extrados): tambien negra
    n_tape_w += assign_where(w, "x8_black", lambda p, m: m == "x8_epo_white"
                             and p.normal.dot(Yh) > 0.3 and -0.004 < yh(Vector(p.center)) < 0.0005
                             and (Vector(p.center) - h0).dot(Zh) > -0.003)
    # tapa del servo como region de material del intrados
    cut = ob[f"X8_Hueco_Bahia_{nm}"]
    pts = [cut.matrix_world @ v.co for v in cut.data.vertices]
    xs = [p.y / X.MM + X.P["x_cg"] for p in pts]
    ss = [-p.x / X.MM for p in pts]
    x0, x1 = min(xs) - 4, max(xs) + 4
    s0, s1 = min(ss) - 4, max(ss) + 4
    COVER_RECT[lr] = dict(x_mm=[x0, x1], s_mm=[s0, s1])
    gx0, gx1 = sorted([s0 * X.MM, s1 * X.MM])
    gy0, gy1 = sorted([(X_LE_ROOT - x1) * X.MM, (X_LE_ROOT - x0) * X.MM])
    near = lambda c, n: (n.z < -0.2 and gx0 - 0.02 < c.x < gx1 + 0.02
                         and gy0 - 0.02 < c.y < gy1 + 0.02)
    for co, no in (((gx0, 0, 0), (1, 0, 0)), ((gx1, 0, 0), (1, 0, 0)),
                   ((0, gy0, 0), (0, 1, 0)), ((0, gy1, 0), (0, 1, 0))):
        bisect(w, Vector(co), Vector(no), near)
    n_cov = assign_where(w, "x8_servo_cover", lambda p, m: m == "x8_epo_white" and p.normal.z < -0.2
                         and gx0 < p.center.x < gx1 and gy0 < p.center.y < gy1)
    HINGE[lr] = dict(h0=h0, Xh=Xh, Yh=Yh, Zh=Zh, Mm=Mm, caps=n_cap_w, tape=n_tape_w, cover=n_cov)
    GAME[w.name] = w

# ---------------------------------------------------------------------------------------------
# 5) Pivotes y piezas moviles
# ---------------------------------------------------------------------------------------------
PIVOT_INFO = {}
for nm, lr in (("Izq", "left"), ("Der", "right")):
    h = HINGE[lr]
    # +X del pivote = -X de la bisagra del maestro: un giro positivo baja el borde de salida
    R = Matrix((h["Xh"], h["Yh"], h["Zh"])).transposed() @ Matrix(((-1, 0, 0), (0, -1, 0), (0, 0, 1)))
    mat = R.to_4x4()
    mat.translation = h["h0"]
    piv = empty(f"elevon_{lr}_hinge", mat, "SINGLE_ARROW", 0.12)
    el = bake(f"elevon_{lr}", [ob[f"X8_Elevon_{nm}"], ob[f"X8_Cuerno_{nm}"]], local=mat)
    # cinta del lado del elevon: 10 mm detras de la bisagra (y local negativo: +Y local = adelante)
    bisect(el, Vector((0, -0.010, 0)), Vector((0, 1, 0)), lambda c, n: -0.03 < c.y < 0.004)
    n_tape_e = assign_where(el, "x8_black", lambda p, m: m == "x8_epo_white" and p.normal.z > 0.2
                            and -0.010 < p.center.y < 0.0005)
    n_tape_e += assign_where(el, "x8_black", lambda p, m: m == "x8_epo_white" and p.normal.y > 0.3
                             and p.center.y > -0.004 and p.center.z > -0.003)
    el.matrix_world = mat
    # tapa negra de la ranura de bisagra (2 mm) a la altura del eje, parte del elevon: hace de
    # la cinta que en el maestro cruza la ranura; gira con un radio <= 1 mm alrededor del eje
    xs_l = [v.co.x for v in el.data.vertices if abs(v.co.y) < 0.003]   # extremos junto al eje
    sv, sf = [], []
    for x_ in (min(xs_l) + 0.001, max(xs_l) - 0.001):
        for y_ in (-0.0010, 0.0009):
            for z_ in (-0.0003, 0.0001):
                sv.append((x_, y_, z_))
    sf = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    sme = bpy.data.meshes.new("slot_cover")
    sme.from_pydata(sv, [], sf)
    sme.validate()
    bm_ = bmesh.new()
    bm_.from_mesh(sme)
    bmesh.ops.recalc_face_normals(bm_, faces=bm_.faces)
    bm_.to_mesh(sme)
    bm_.free()
    sme.materials.append(GM["x8_black"])
    strip = bpy.data.objects.new("slot_cover", sme)
    sc.collection.objects.link(strip)
    strip.matrix_world = mat
    with bpy.context.temp_override(active_object=el, object=el, selected_objects=[el, strip],
                                   selected_editable_objects=[el, strip]):
        bpy.ops.object.join()
    dedupe_slots(el)
    attach(piv, root)
    attach(el, piv)
    GAME[piv.name], GAME[el.name] = piv, el
    PIVOT_INFO[piv.name] = dict(source="X8_Eje_Bisagra_" + nm, tape_faces=n_tape_e)

for nm, lr, sg in (("Izq", "left", -1), ("Der", "right", 1)):
    H = ob[f"X8_Bisagra_Compuerta_{nm}"]
    Hm = H.matrix_world.copy()
    A = (T3 @ Hm.to_3x3().col[1]).normalized() * sg      # la compuerta abre con +X
    up = Vector((0, 0, 1))
    Zp = (up - up.dot(A) * A).normalized()
    Yp = Zp.cross(A)
    mat = Matrix((A, Yp, Zp)).transposed().to_4x4()
    mat.translation = T @ Hm.translation
    piv = empty(f"camera_door_{lr}_hinge", mat, "SINGLE_ARROW", 0.06)
    door = bake(f"camera_door_{lr}", [ob[f"X8_Compuerta_Camara_{nm}"]], local=mat)
    door.matrix_world = mat
    attach(piv, root)
    attach(door, piv)
    GAME[piv.name], GAME[door.name] = piv, door
    PIVOT_INFO[piv.name] = dict(source="X8_Bisagra_Compuerta_" + nm)

hub = T @ HUB_M
tmat = Matrix(((0, -1, 0), (1, 0, 0), (0, 0, 1))).to_4x4()     # +X = adelante (empuje)
tmat.translation = hub
thrust = empty("thrust_frame", tmat, "SINGLE_ARROW", 0.10)
spin = empty("propeller_spin", tmat, "CIRCLE", 0.17)
rotor = bake("propeller_rotor", [ob[n] for n in ("X8_Pala_1", "X8_Pala_2", "X8_Buje_Helice",
                                                  "X8_Cono_Helice", "X8_Motor_Campana", "X8_Eje")],
             local=tmat, default_mat="x8_black")
rotor.matrix_world = tmat
attach(thrust, root)
attach(spin, thrust)
attach(rotor, spin)
GAME.update({"thrust_frame": thrust, "propeller_spin": spin, "propeller_rotor": rotor})
for o in (core, equip, hatch, motor, GAME["wing_left_fixed"], GAME["wing_right_fixed"]):
    attach(o, root)
    GAME[o.name] = o

# limpieza de mallas: los n-gonos de los booleanos y de los cortes con vertices alineados
# se triangulan (BEAUTY) y se disuelve lo degenerado, para que el GLB no lleve triangulos de
# area nula
CLEAN = {}
for name, parent, typ, sec in S.NODES:
    o = GAME[name]
    if o.type != "MESH":
        continue
    bm = bmesh.new()
    bm.from_mesh(o.data)
    n0 = len(bm.faces)
    merged = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=2e-5)     # aristas < 0,02 mm
    merged -= len(bm.verts)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-7, edges=bm.edges[:])
    ngons = [f for f in bm.faces if len(f.verts) > 4]
    bmesh.ops.triangulate(bm, faces=ngons, quad_method="BEAUTY", ngon_method="BEAUTY")
    bmesh.ops.dissolve_degenerate(bm, dist=1e-7, edges=bm.edges[:])
    # triangulos aguja que quedan: girar su arista mas larga (comparten area con el vecino)
    flips = 0
    for _ in range(6):
        bad = [f for f in bm.faces if len(f.verts) == 3 and f.calc_area() < 1e-10]
        if not bad:
            break
        for f in bad:
            if not f.is_valid:
                continue
            e = max(f.edges, key=lambda e: e.calc_length())
            if len(e.link_faces) == 2 and all(len(g.verts) == 3 for g in e.link_faces):
                bmesh.ops.rotate_edges(bm, edges=[e], use_ccw=False)
                flips += 1
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    o.data.calc_loop_triangles()
    tri = o.data.loop_triangles
    deg = sum(1 for t in tri if t.area < 1e-10)
    CLEAN[name] = dict(vertices_merged=merged, ngons_triangulated=len(ngons),
                       sliver_edges_rotated=flips,
                       degenerate_left=deg)

# etiquetas de seccion
for name, parent, typ, sec in S.NODES:
    o = GAME[name]
    if sec:
        o[S.SECTION_KEY] = sec
    assert o.type == typ, (name, o.type)
    assert (o.parent.name if o.parent else None) == parent, (name, o.parent)

# ---------------------------------------------------------------------------------------------
# 6) Limpieza: solo queda la coleccion de exportacion
# ---------------------------------------------------------------------------------------------
keep = set(GAME.values())
COVER_INFO = {k: v for k, v in COVER_RECT.items()}
hinge_master = {lr: dict(h0_master=list(HINGE[lr]["Mm"].translation),
                         axis_master=list(HINGE[lr]["Mm"].to_3x3().col[0])) for lr in HINGE}
for o in list(bpy.data.objects):
    if o not in keep:
        bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    if c != EXPORT:
        bpy.data.collections.remove(c)
for coll in (bpy.data.texts, bpy.data.actions, bpy.data.cameras, bpy.data.lights,
             bpy.data.curves, bpy.data.images, bpy.data.worlds):
    for blk in list(coll):
        coll.remove(blk)
for m in list(bpy.data.materials):
    if m.name not in GM:
        bpy.data.materials.remove(m)
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
for k in list(sc.keys()):
    del sc[k]
world = bpy.data.worlds.new("Preview_World")
world.color = (0.42, 0.47, 0.55)
sc.world = world
sc.unit_settings.system = "METRIC"
sc.unit_settings.scale_length = 1.0
sc.unit_settings.length_unit = "METERS"
sc.frame_start, sc.frame_end = 1, 1
sc.frame_set(1)
for o in keep:
    o.select_set(False)

# vista 3/4 encuadrada y sombreado con materiales
for scr in bpy.data.screens:
    for area in scr.areas:
        if area.type == "VIEW_3D":
            sp = area.spaces.active
            r3 = sp.region_3d
            r3.view_perspective = "PERSP"
            r3.view_location = (0.0, -0.18, 0.0)
            r3.view_distance = 2.9
            r3.view_rotation = Euler((math.radians(60), 0, math.radians(-140))).to_quaternion()
            sp.clip_start, sp.clip_end = 0.01, 200.0
            sp.shading.type = "SOLID"
            sp.shading.color_type = "MATERIAL"

INFO = dict(
    generator="x8_skywalker_blender.py (master v3 generator) with x8_game_spec.GAME_RES",
    game_resolution=S.GAME_RES,
    D0_definition="symmetry plane; x = leading edge of the wing at the orange root rib "
                  "(s = 236 mm, wing/centre-body joint); z = thrust-axis height (motor shaft)",
    D0_master_mm=dict(x_from_nose=X_LE_ROOT, s=0.0, z=Z_THRUST),
    D0_master_blender=list(D0_M),
    servo_cover_rect_master_mm=COVER_INFO,
    elevon_hinge_master=hinge_master,
    closure_faces=dict(core=n_cap_core, wing_left=HINGE["left"]["caps"],
                       wing_right=HINGE["right"]["caps"]),
    tape_faces={lr: HINGE[lr]["tape"] for lr in HINGE},
    cover_faces={lr: HINGE[lr]["cover"] for lr in HINGE},
    pivots=PIVOT_INFO,
    mesh_cleanup=CLEAN,
    battery_center_mm=228.0,
    blender=bpy.app.version_string,
)
txt = bpy.data.texts.new("build_info.json")
txt.write(json.dumps(INFO, indent=1, default=str))
readme = bpy.data.texts.new("README_export.txt")
readme.write(f"""Skywalker X8 - version de juego {S.REVISION}

Exportar (Blender 5.2.2 LTS, exportador glTF 5.2.40):
  blender -b source/aircraft_game.blend --python-exit-code 1 --python source/scripts/export_glb.py -- export/aircraft.glb
Desde esta ventana: Scripting > abrir source/scripts/export_glb.py > Run Script.

Marco: +X ala derecha del piloto, +Y nariz, +Z arriba, metros, origen en D0
(plano de simetria, borde de ataque del ala en la costilla naranja s = 236 mm, altura del
eje del motor). El GLB es Y-up: godot = (x, z, -y).

Coleccion que se exporta: {S.EXPORT_COLLECTION}. Seccion de choque: propiedad
"{S.SECTION_KEY}" en cada objeto (sale en extras de glTF).

Pivotes moviles (eje = +X local, cero = reposo guardado, rest * Rx(angulo)):
  elevon_left_hinge / elevon_right_hinge   + = borde de salida abajo
  camera_door_left_hinge / camera_door_right_hinge   + = abre (0 a 110 grados)
  propeller_spin   + = horario visto desde atras hacia la nariz (borde de ataque delante)
Mezcla de elevones: izq = alabeo - profundidad, der = -alabeo - profundidad
  (profundidad + = nariz arriba, alabeo + = derecha; los dos en grados de superficie).
""")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
print("GUARDADO", OUT)
print(json.dumps(INFO, indent=1, default=str))
