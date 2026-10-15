"""
Monster truck RC nitro 1:8 - modelo procedural para Blender
===========================================================
Diseño propio inspirado en la arquitectura típica de un monster truck
nitro 4x4 (chasis de placa, suspensión independiente con doble
amortiguador por rueda, motor de combustión con escape sintonizado).

Uso:
  - Blender 4.2 o superior (probado en 4.2 LTS; compatible con 4.x / 5.x)
  - Pestaña "Scripting" > Abrir este archivo > "Run Script"
  - o desde terminal:  blender -b -P monster_truck_nitro.py

ATENCIÓN: el script limpia la escena actual antes de construir.

Unidades: metros (escala real de un 1:8, largo total ~0.62 m)
Ejes:     X = adelante, Y = izquierda, Z = arriba

Organización en colecciones:
  01_Carroceria, 02_Chasis, 03_Suspension, 04_Ruedas,
  05_Motor_Transmision, 06_Electronica, Estudio (luces/cámaras/piso)
Cada rueda cuelga de un Empty ("Rueda_...") en su centro: rótalo en Y para
hacerla girar o en Z (delanteras) para darle dirección.
Para levantar la carrocería mueve el Empty "Carroceria".
"""

import bpy
import bmesh
import math
from math import pi, sin, cos, radians, atan, atan2
from mathutils import Vector, Matrix, Euler

# ---------------------------------------------------------------------------
# Parámetros principales (puedes cambiarlos y volver a ejecutar)
# ---------------------------------------------------------------------------
WHEELBASE = 0.40      # distancia entre ejes
TRACK = 0.40          # ancho de vía (centro a centro de ruedas)
WZ = 0.0865           # altura del centro de las ruedas (= radio de llanta)
XA = WHEELBASE / 2
YW = TRACK / 2

COLORS = {
    "pintura":      (0.80, 0.16, 0.008),   # carrocería
    "franjas":      (0.015, 0.015, 0.016),
    "anodizado":    (0.85, 0.58, 0.16),   # piezas de aluminio de acento
    "placa_chasis": (0.20, 0.21, 0.23),
    "rin":          (0.06, 0.06, 0.065),
    "espuma":       (0.95, 0.42, 0.08),   # filtro de aire
    "verde":        (0.020, 0.200, 0.045),
    "amarillo":     (0.95, 0.70, 0.010),
    "azul":         (0.012, 0.050, 0.55),
    "brazo":        (0.36, 0.36, 0.37),
}


# ---------------------------------------------------------------------------
# Utilidades generales
# ---------------------------------------------------------------------------
def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for blocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                   bpy.data.lights, bpy.data.cameras):
        for b in list(blocks):
            if b.users == 0:
                blocks.remove(b)


def new_collection(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent if parent else bpy.context.scene.collection).children.link(c)
    return c


def _set(node, names, value):
    if isinstance(names, str):
        names = [names]
    for n in names:
        s = node.inputs.get(n)
        if s is not None:
            try:
                s.default_value = value
                return True
            except Exception:
                pass
    return False


def make_mat(name, rgb, metallic=0.0, rough=0.5, coat=0.0, trans=0.0,
             emit=None, estr=0.0, ior=None, spec=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    _set(b, "Base Color", (*rgb, 1.0))
    _set(b, "Metallic", metallic)
    _set(b, "Roughness", rough)
    if coat:
        _set(b, ["Coat Weight", "Clearcoat"], coat)
        _set(b, ["Coat Roughness", "Clearcoat Roughness"], 0.04)
    if trans:
        _set(b, ["Transmission Weight", "Transmission"], trans)
    if ior:
        _set(b, "IOR", ior)
    if spec is not None:
        _set(b, ["Specular IOR Level", "Specular"], spec)
    if emit:
        _set(b, ["Emission Color", "Emission"], (*emit, 1.0))
        _set(b, "Emission Strength", estr)
    m.diffuse_color = (*rgb, 1.0)          # color en vista sólida
    m.metallic = metallic
    m.roughness = rough
    return m


def build_materials():
    C = COLORS
    mats = {
        "pintura":   make_mat("Pintura_Carroceria", C["pintura"], 0.15, 0.28, coat=1.0),
        "franjas":   make_mat("Vinilo_Franjas", C["franjas"], 0.0, 0.55),
        "vidrio":    make_mat("Vidrio_Polarizado", (0.01, 0.012, 0.015), 0.0, 0.06, spec=0.35),
        "faro":      make_mat("Faro", (0.9, 0.9, 0.85), 0.0, 0.1, emit=(1, 0.95, 0.85), estr=2.0),
        "stop":      make_mat("Stop_LED", (0.6, 0.01, 0.01), 0.0, 0.15, emit=(1.0, 0.03, 0.02), estr=8.0),
        "plastico":  make_mat("Plastico_Negro", (0.022, 0.022, 0.024), 0.0, 0.45),
        "plastico2": make_mat("Plastico_Gris", (0.07, 0.07, 0.075), 0.0, 0.5),
        "caucho":    make_mat("Caucho_Llanta", (0.022, 0.022, 0.024), 0.0, 0.9, spec=0.25),
        "cromo":     make_mat("Cromo", (0.92, 0.92, 0.94), 1.0, 0.06),
        "chasis":    make_mat("Aluminio_Chasis", C["placa_chasis"], 1.0, 0.32),
        "anodizado": make_mat("Aluminio_Anodizado", C["anodizado"], 1.0, 0.24),
        "alu":       make_mat("Aluminio_Fundido", (0.72, 0.72, 0.74), 1.0, 0.38),
        "titanio":   make_mat("Culata_Titanio", (0.32, 0.33, 0.36), 1.0, 0.28),
        "acero":     make_mat("Acero_Oscuro", (0.09, 0.09, 0.1), 1.0, 0.3),
        "rin":       make_mat("Rin_Negro_Cromado", C["rin"], 1.0, 0.16),
        "tanque":    make_mat("Tanque_Translucido", (0.92, 0.95, 1.0), 0.0, 0.18, trans=0.85, ior=1.45),
        "manguera":  make_mat("Manguera_Combustible", (0.35, 0.8, 0.95), 0.0, 0.2, trans=0.6, ior=1.4),
        "espuma":    make_mat("Espuma_Filtro", C["espuma"], 0.0, 1.0),
        "cable_r":   make_mat("Cable_Rojo", (0.6, 0.02, 0.02), 0.0, 0.4),
        "cable_b":   make_mat("Cable_Blanco", (0.8, 0.8, 0.8), 0.0, 0.4),
        "piso":      make_mat("Piso_Estudio", (0.7, 0.7, 0.7), 0.0, 0.9),
        "panel":     make_mat("Panel_Reflejo", (0.01, 0.01, 0.012), 0.0, 1.0),
        "etiqueta":  make_mat("Etiqueta", (0.75, 0.75, 0.72), 0.0, 0.4),
        "silicona":  make_mat("Silicona_Escape", (0.05, 0.05, 0.055), 0.0, 0.55),
        "ceramica":  make_mat("Ceramica_Bujia", (0.85, 0.85, 0.82), 0.0, 0.25),
        "termo":     make_mat("Termoencogible_Bateria", (0.62, 0.05, 0.04), 0.0, 0.35, coat=0.4),
        # esquema de color de la referencia del usuario: placa verde, moldeados amarillos,
        # resortes azules, brazos gris titanio y balancines de aluminio
        "verde":     make_mat("Aluminio_Verde", C["verde"], 1.0, 0.30),
        "amarillo":  make_mat("Nylon_Amarillo", C["amarillo"], 0.0, 0.42),
        "azul":      make_mat("Resorte_Azul", C["azul"], 1.0, 0.25),
        "brazo":     make_mat("Compuesto_Gris_Titanio", C["brazo"], 0.65, 0.36),
        "amarillo_alu": make_mat("Aluminio_Amarillo", C["amarillo"], 1.0, 0.26),
        "uretano":   make_mat("Uretano_Tope", (0.03, 0.03, 0.035), 0.0, 0.6),
        # carrocería "LOCURA": accesorios, luces y neón
        "negro_mate":   make_mat("Plastico_Negro_Mate", (0.016, 0.016, 0.018), 0.0, 0.72),
        "negro_brillo": make_mat("Plastico_Negro_Brillo", (0.010, 0.010, 0.012), 0.0, 0.10, coat=0.8),
        "cromo_pl":     make_mat("Plastico_Cromado", (0.93, 0.93, 0.95), 1.0, 0.045),
        "alu_pulido":   make_mat("Aluminio_Pulido", (0.91, 0.92, 0.93), 1.0, 0.10),
        "gris_metal":   make_mat("Gris_Metalico", (0.22, 0.23, 0.25), 1.0, 0.30),
        "goma":         make_mat("Goma_Correa", (0.03, 0.03, 0.032), 0.0, 0.80),
        "rojo_anodizado": make_mat("Aluminio_Rojo", (0.72, 0.015, 0.02), 1.0, 0.22),
        "recubrimiento": make_mat("Recubrimiento_Caja", (0.022, 0.022, 0.024), 0.0, 0.88),
        "led":       make_mat("LED_Blanco", (0.95, 0.96, 1.0), 0.0, 0.08, emit=(0.86, 0.93, 1.0), estr=14.0),
        "neon_azul": make_mat("Neon_Azul", (0.10, 0.45, 1.0), 0.0, 0.15, emit=(0.12, 0.55, 1.0), estr=12.0),
        "neon_rosa": make_mat("Neon_Rosa", (1.0, 0.10, 0.60), 0.0, 0.15, emit=(1.0, 0.06, 0.55), estr=18.0),
        "neon_verde": make_mat("Neon_Verde", (0.25, 1.0, 0.28), 0.0, 0.15, emit=(0.18, 1.0, 0.22), estr=12.0),
        "ambar":     make_mat("Ambar", (1.0, 0.42, 0.02), 0.0, 0.12, emit=(1.0, 0.38, 0.0), estr=6.0),
    }
    mats["carbono"] = material_imagen("Fibra_Carbono", "fibra_carbono.png", rough=0.28, coat=1.0, repetir=True)
    add_bump(mats["recubrimiento"], 1400, 0.45, 0.0004, 5.0)
    add_bump(mats["negro_mate"], 900, 0.06, 0.00015)
    # relieve fino: plástico inyectado, caucho, aluminio fundido, espuma
    add_bump(mats["plastico"], 900, 0.08, 0.00015)
    add_bump(mats["plastico2"], 900, 0.08, 0.00015)
    add_bump(mats["caucho"], 500, 0.25, 0.0003)
    add_bump(mats["alu"], 1800, 0.20, 0.0002)
    add_bump(mats["espuma"], 2500, 0.60, 0.0006, 6.0)
    add_bump(mats["silicona"], 700, 0.10, 0.0002)
    add_bump(mats["amarillo"], 900, 0.08, 0.00015)
    return mats


# prefijo del objeto -> material del esquema de color de la referencia
COLORES_PIEZAS = [
    (("Chasis_Placa", "Mamparo_Placa_", "Tirante_"), "verde"),
    (("Estabilizadora_Soportes_",), "amarillo"),
    (("Portamangueta_", "Mangueta_Del_Izq_Malla", "Mangueta_Del_Der_Malla", "Mangueta_Tras_Izq_Malla",
      "Mangueta_Tras_Der_Malla", "Diferencial_Del", "Diferencial_Tras", "Diferencial_Alojamientos_",
      "Soporte_Amortiguadores_", "Soporte_Amort_Orejas_", "Mamparo_Orejas_", "Balancin_Poste_",
      "Servo_Direccion", "Servo_Acelerador"), "amarillo"),
    (("Brazo_Inferior_", "Brazo_Superior_Del", "Brazo_Superior_Tras", "Brazo_Superior_Bujes_"), "brazo"),
    (("Balancin_Del_Izq_", "Balancin_Del_Der_", "Balancin_Tras_Izq_", "Balancin_Tras_Der_",
      "Direccion_Bellcrank"), "alu"),
]


def aplicar_colores(C, M):
    import re
    for key in ("chasis", "susp", "elec"):
        for o in C[key].all_objects:
            if o.type != 'MESH':
                continue
            nm = o.name
            mat = None
            if re.match(r"Amort_.*_(Cuerpo_Malla|Copa)$", nm):
                mat = "amarillo_alu"                       # cuerpo y copa: aluminio anodizado amarillo
            elif re.match(r"Amort_.*_(Ojo_Fijo|Rotula)$", nm):
                mat = "amarillo"
            elif re.match(r"Amort_.*_Resorte$", nm):
                mat = "azul"
            else:
                for pref, mk in COLORES_PIEZAS:
                    if nm.startswith(pref) and not nm.startswith(("Diferencial_Salida", "Diferencial_Tapa")):
                        mat = mk
                        break
            if mat:
                o.data.materials.clear()
                o.data.materials.append(M[mat])


# ---------------------------------------------------------------------------
# Geometría con bmesh
# ---------------------------------------------------------------------------
def M_T(loc):
    return Matrix.Translation(Vector(loc))


def M_S(sx, sy, sz):
    return Matrix.Diagonal((sx, sy, sz, 1.0))


def R_X(a):
    return Matrix.Rotation(a, 4, 'X')


def R_Y(a):
    return Matrix.Rotation(a, 4, 'Y')


def R_Z(a):
    return Matrix.Rotation(a, 4, 'Z')


AXIS_ROT = {'X': Matrix.Rotation(pi / 2, 4, 'Y'),
            'Y': Matrix.Rotation(-pi / 2, 4, 'X'),
            'Z': Matrix.Identity(4)}


def look_z(p1, p2):
    """Matriz cuyo eje Z local va de p1 a p2 (origen en p1) y la longitud."""
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    q = d.to_track_quat('Z', 'Y')
    return M_T(p1) @ q.to_matrix().to_4x4(), d.length


def add_box(bm, size, loc=(0, 0, 0), rot=None):
    M = M_T(loc) @ (rot if rot is not None else Matrix.Identity(4)) @ M_S(*size)
    bmesh.ops.create_cube(bm, size=1.0, matrix=M)


def add_box_minmax(bm, mn, mx):
    c = [(a + b) / 2 for a, b in zip(mn, mx)]
    s = [abs(b - a) for a, b in zip(mn, mx)]
    add_box(bm, s, c)


def add_cyl(bm, r, depth, M=None, segs=24, r2=None):
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=r, radius2=(r if r2 is None else r2),
                          depth=depth, matrix=(M if M is not None else Matrix.Identity(4)))


def add_cyl_pts(bm, p1, p2, r, segs=16, r2=None):
    M, L = look_z(p1, p2)
    add_cyl(bm, r, L, M @ M_T((0, 0, L / 2)), segs, r2)


def add_cyl_axis(bm, center, axis, r, length, segs=24, r2=None):
    add_cyl(bm, r, length, M_T(center) @ AXIS_ROT[axis], segs, r2)


def add_lathe(bm, prof, segs=48, M=None, closed=True, a0=0.0, a1=2 * pi):
    """Revoluciona un perfil [(radio, z), ...] alrededor del eje Z local."""
    M = M if M is not None else Matrix.Identity(4)
    full = abs((a1 - a0) - 2 * pi) < 1e-6
    nring = segs if full else segs + 1
    rings = []
    for i in range(nring):
        a = a0 + (a1 - a0) * i / segs
        ca, sa = cos(a), sin(a)
        rings.append([bm.verts.new(M @ Vector((r * ca, r * sa, z))) for (r, z) in prof])
    P = len(prof)
    jr = P if closed else P - 1
    for i in range(segs):
        A = rings[i]
        B = rings[(i + 1) % nring]
        for j in range(jr):
            k = (j + 1) % P
            bm.faces.new((A[j], B[j], B[k], A[k]))
    if (not full) and closed:
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[-1])))


def add_hexa(bm, pts):
    """Hexaedro a partir de 8 puntos: 4 de abajo y 4 de arriba (mismo orden)."""
    v = [bm.verts.new(Vector(p)) for p in pts]
    for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        bm.faces.new([v[i] for i in f])


def add_prism(bm, poly, z0, z1, M=None):
    """Extruye un polígono 2D (x, y) de z0 a z1 en el espacio local de M."""
    M = M if M is not None else Matrix.Identity(4)
    b = [bm.verts.new(M @ Vector((x, y, z0))) for x, y in poly]
    t = [bm.verts.new(M @ Vector((x, y, z1))) for x, y in poly]
    bm.faces.new(list(reversed(b)))
    bm.faces.new(t)
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((b[i], b[j], t[j], t[i]))


def smooth_bm(bm, angle=30):
    """Sombreado suave con bordes duros por ángulo (equivale a 'Smooth by Angle')."""
    lim = radians(angle) if angle is not None else -1
    for f in bm.faces:
        f.smooth = angle is not None
    if angle is None:
        return
    for e in bm.edges:
        if len(e.link_faces) == 2:
            try:
                if e.calc_face_angle() > lim:
                    e.smooth = False
            except ValueError:
                e.smooth = False


def mesh_obj(name, bm, mat, col, parent=None, local=None, smooth=30, recalc=True):
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    smooth_bm(bm, smooth)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in (mat if isinstance(mat, (list, tuple)) else [mat]):
        me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    if parent is not None:
        o.parent = parent
    if local is not None:
        o.matrix_basis = local
    return o


def linked_obj(name, mesh, col, parent=None, local=None):
    o = bpy.data.objects.new(name, mesh)
    col.objects.link(o)
    if parent is not None:
        o.parent = parent
    if local is not None:
        o.matrix_basis = local
    return o


def empty(name, col, parent=None, loc=(0, 0, 0), rot=(0, 0, 0), size=0.04, kind='PLAIN_AXES'):
    o = bpy.data.objects.new(name, None)
    o.empty_display_type = kind
    o.empty_display_size = size
    col.objects.link(o)
    o.parent = parent
    o.location = loc
    o.rotation_euler = rot
    return o


def tube(name, pts, r, mat, col, parent=None, radii=None, res=10, bevel_res=4, caps=True):
    """Tubo a lo largo de una curva Bézier (mangueras, cables, barras)."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_mode = 'ROUND'
    cu.bevel_depth = r
    cu.bevel_resolution = bevel_res
    cu.use_fill_caps = caps
    sp = cu.splines.new('BEZIER')
    sp.bezier_points.add(len(pts) - 1)
    for i, (bp, p) in enumerate(zip(sp.bezier_points, pts)):
        bp.co = Vector(p)
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'
        if radii:
            bp.radius = radii[i]
    sp.resolution_u = res
    sp.use_smooth = True
    cu.materials.append(mat)
    o = bpy.data.objects.new(name, cu)
    col.objects.link(o)
    o.parent = parent
    return o


def helix(name, r, wire, z0, z1, turns, mat, col, parent=None, local=None):
    """Resorte helicoidal a lo largo del eje Z local."""
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_mode = 'ROUND'
    cu.bevel_depth = wire
    cu.bevel_resolution = 2
    sp = cu.splines.new('POLY')
    n = int(turns * 20)
    sp.points.add(n)
    for i in range(n + 1):
        t = i / n
        a = 2 * pi * turns * t
        # espiras finales más juntas, como un resorte real
        tt = 0.5 - 0.5 * cos(pi * t)
        tz = 0.82 * t + 0.18 * tt
        sp.points[i].co = (r * cos(a), r * sin(a), z0 + (z1 - z0) * tz, 1.0)
    sp.use_smooth = True
    cu.materials.append(mat)
    o = bpy.data.objects.new(name, cu)
    col.objects.link(o)
    o.parent = parent
    if local is not None:
        o.matrix_basis = local
    return o


def apply_modifiers(o):
    """Aplica los modificadores de un objeto malla sin usar operadores."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
    old = o.data
    o.modifiers.clear()
    o.data = me
    me.name = o.name
    if old.users == 0:
        bpy.data.meshes.remove(old)


def resmooth(o, angle=30):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    smooth_bm(bm, angle)
    bm.to_mesh(o.data)
    bm.free()


def boolean_cut(o, cutters, solver='EXACT', auto_interseccion=False):
    for c in cutters:
        m = o.modifiers.new("Bool_" + c.name, 'BOOLEAN')
        m.operation = 'DIFFERENCE'
        m.solver = solver
        if auto_interseccion:
            m.use_self = True                     # la malla tiene volúmenes que se solapan (placa + rampas)
        m.object = c
        c.hide_render = True
        c.hide_viewport = True
    apply_modifiers(o)
    for c in cutters:
        me = c.data
        bpy.data.objects.remove(c, do_unlink=True)
        if me.users == 0:
            bpy.data.meshes.remove(me)


def cutter_obj(name, bm, col):
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    return o


def bevel_finish(o, width=0.0008, segments=3, angle=30):
    """Bisel pequeño en aristas vivas + normales ponderadas por área.
    Las caras planas quedan planas y los cilindros suaves (look de pieza real)."""
    if o.type != 'MESH' or width <= 0:
        return
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = True
    bm.to_mesh(o.data)
    bm.free()
    b = o.modifiers.new("Bisel", 'BEVEL')
    b.width = width
    b.segments = segments
    b.limit_method = 'ANGLE'
    b.angle_limit = radians(angle)
    b.use_clamp_overlap = True
    w = o.modifiers.new("Normales", 'WEIGHTED_NORMAL')
    w.mode = 'FACE_AREA'
    w.weight = 50
    w.keep_sharp = False
    apply_modifiers(o)


def bevel_mesh_data(me, col, width, segments=3, angle=30):
    """Bisela un bloque de malla compartido (ruedas) y devuelve la malla nueva."""
    name = me.name
    tmp = bpy.data.objects.new("tmp_bevel", me)
    col.objects.link(tmp)
    bevel_finish(tmp, width, segments, angle)     # reemplaza (y borra) la malla original
    new = tmp.data
    bpy.data.objects.remove(tmp, do_unlink=True)
    new.name = name
    return new


def add_bump(m, scale=600.0, strength=0.2, distance=0.0003, detail=4.0):
    """Relieve procedural fino (plástico inyectado, caucho, fundición)."""
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    tc = nt.nodes.new('ShaderNodeTexCoord')
    nz = nt.nodes.new('ShaderNodeTexNoise')
    nz.inputs['Scale'].default_value = scale
    nz.inputs['Detail'].default_value = detail
    bp = nt.nodes.new('ShaderNodeBump')
    bp.inputs['Strength'].default_value = strength
    if 'Distance' in bp.inputs:
        bp.inputs['Distance'].default_value = distance
    nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    nt.links.new(nz.outputs['Fac'], bp.inputs['Height'])
    nt.links.new(bp.outputs['Normal'], b.inputs['Normal'])


# ---------------------------------------------------------------------------
# Pintura con texturas (atlas de livery.py) y mapeo UV de la carrocería
# ---------------------------------------------------------------------------
def _dir_texturas():
    import os
    cands = [os.environ.get("RC_TEX", "")]
    try:
        cands.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), "tex"))
    except NameError:
        pass
    cands.append(bpy.path.abspath("//tex"))
    for c in cands:
        if c and os.path.isfile(os.path.join(c, "carroceria_color.jpg")):
            return c
    return None


def _imagen(nombre_archivo, color=True):
    import os
    d = _dir_texturas()
    if d is None or not os.path.isfile(os.path.join(d, nombre_archivo)):
        return None
    img = bpy.data.images.load(os.path.join(d, nombre_archivo), check_existing=True)
    img.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
    return img


def _nodo_imagen(nt, img, x, y, repetir=False):
    n = nt.nodes.new('ShaderNodeTexImage')
    n.image = img
    n.extension = 'REPEAT' if repetir else 'EXTEND'
    n.interpolation = 'Cubic' if not repetir else 'Linear'
    n.location = (x, y)
    return n


def material_livery(M):
    """Pintura 'LOCURA': color, rugosidad/metálico (G/B) y emisión (neón) desde el atlas de 4096,
    laca transparente (coat) y escamas metálicas finas bajo la laca. Exportable a glTF."""
    if "livery" in M:
        return M["livery"]
    m = make_mat("Pintura_Livery", (0.02, 0.47, 0.20), 0.6, 0.25, coat=1.0)
    col, mr, em = _imagen("carroceria_color.jpg"), _imagen("carroceria_mr.png", False), _imagen("carroceria_emision.png")
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    _set(b, ["Coat Roughness", "Clearcoat Roughness"], 0.03)
    if col is not None:
        nc = _nodo_imagen(nt, col, -700, 300)
        nt.links.new(nc.outputs['Color'], b.inputs['Base Color'])
    if mr is not None:
        nm_ = _nodo_imagen(nt, mr, -700, 0)
        sp = nt.nodes.new('ShaderNodeSeparateColor')
        sp.location = (-400, 0)
        nt.links.new(nm_.outputs['Color'], sp.inputs['Color'])
        nt.links.new(sp.outputs['Green'], b.inputs['Roughness'])
        nt.links.new(sp.outputs['Blue'], b.inputs['Metallic'])
    if em is not None:
        ne = _nodo_imagen(nt, em, -700, -300)
        nt.links.new(ne.outputs['Color'], b.inputs['Emission Color'] if 'Emission Color' in b.inputs
                     else b.inputs['Emission'])
        _set(b, "Emission Strength", 4.0)
    # escamas del metalizado: relieve muy fino solo en la base (la laca queda lisa)
    tc = nt.nodes.new('ShaderNodeTexCoord')
    nz = nt.nodes.new('ShaderNodeTexNoise')
    nz.inputs['Scale'].default_value = 9000.0
    nz.inputs['Detail'].default_value = 1.0
    bp = nt.nodes.new('ShaderNodeBump')
    bp.inputs['Strength'].default_value = 0.10
    if 'Distance' in bp.inputs:
        bp.inputs['Distance'].default_value = 0.00004
    nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    nt.links.new(nz.outputs['Fac'], bp.inputs['Height'])
    nt.links.new(bp.outputs['Normal'], b.inputs['Normal'])
    M["livery"] = m
    return m


def material_imagen(nombre, archivo, emis=0.0, rough=0.35, metal=0.0, coat=0.0, repetir=False):
    """Material con una imagen como color base (calcomanías, placa, fibra de carbono)."""
    m = bpy.data.materials.get(nombre)
    if m is not None:
        return m
    m = make_mat(nombre, (0.05, 0.05, 0.05), metal, rough, coat=coat)
    img = _imagen(archivo)
    if img is not None:
        nt = m.node_tree
        b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
        ni = _nodo_imagen(nt, img, -500, 200, repetir)
        nt.links.new(ni.outputs['Color'], b.inputs['Base Color'])
        if emis:
            nt.links.new(ni.outputs['Color'], b.inputs['Emission Color'] if 'Emission Color' in b.inputs
                         else b.inputs['Emission'])
            _set(b, "Emission Strength", emis)
    return m


def uv_planar(bm, ejes="xy", escala=0.03):
    """UV plana repetible (u, v) = coordenadas / escala (texturas que se repiten)."""
    uvl = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    ia, ib = "xyz".index(ejes[0]), "xyz".index(ejes[1])
    for f in bm.faces:
        for lp in f.loops:
            lp[uvl].uv = (lp.vert.co[ia] / escala, lp.vert.co[ib] / escala)


# Atlas de la pintura (ver livery.py): rangos en coordenadas locales de la carrocería y casillas en píxeles
LIV_RANGO = {'x': (-0.335, 0.335), 'y': (-0.200, 0.200), 'z': (0.140, 0.360)}
LIV_CASILLAS = {"der": ((0, 0, 4096, 1100), 'x', 'z', False),
                "izq": ((0, 1100, 4096, 2200), 'x', 'z', True),
                "arriba": ((0, 2200, 4096, 3300), 'x', 'y', False),
                "frente": ((0, 3300, 2048, 4096), 'y', 'z', False),
                "cola": ((2048, 3300, 3968, 4096), 'y', 'z', True)}
LIV_NEUTRO = (4032 / 4096, 1 - 3364 / 4096)       # parche negro mate para caras interiores
ARCO_ZL = WZ + 0.005 - 0.020                      # centro de los pasos de rueda en coordenadas de la carrocería
ARCO_R = 0.1255


def _liv_casilla(n, c):
    """Elige la vista del atlas para una cara (normal n, centro c) o None si es interior."""
    for f in (1, -1):
        if (((c.x - f * XA) ** 2 + (c.z - ARCO_ZL) ** 2) ** 0.5 < ARCO_R + 0.004
                and 0.100 < abs(c.y) < HW - 0.0012):
            return None                                       # túnel del paso de rueda
    ax = max(range(3), key=lambda i: abs(n[i]))
    if ax == 2:
        return "arriba" if n.z > 0 else None
    if ax == 1:
        if n.y * c.y <= 0:
            return None
        return "izq" if n.y > 0 else "der"
    if n.x > 0 and c.x > 0:
        return "frente"
    if n.x < 0 and c.x < 0:
        if -0.262 < c.x < -0.104 and c.z < 0.2425:
            return None                                       # pared delantera de la caja (interior)
        return "cola"
    return None


def _liv_uv(casilla, co):
    (a, b, c, d), eu, ev, flip = LIV_CASILLAS[casilla]
    u0, u1 = LIV_RANGO[eu]
    v0, v1 = LIV_RANGO[ev]
    fu = min(max((getattr(co, eu) - u0) / (u1 - u0), 0.001), 0.999)
    if flip:
        fu = 1.0 - fu
    fr = min(max((v1 - getattr(co, ev)) / (v1 - v0), 0.001), 0.999)
    return ((a + fu * (c - a)) / 4096.0, 1.0 - (b + fr * (d - b)) / 4096.0)


def uv_livery(obj):
    """Proyección por caras sobre el atlas: cada cara usa la vista de su normal dominante
    (lados, arriba, frente, cola). Las caras interiores van a un parche neutro."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    uvl = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        cas = _liv_casilla(f.normal, f.calc_center_median())
        for lp in f.loops:
            lp[uvl].uv = LIV_NEUTRO if cas is None else _liv_uv(cas, lp.vert.co)
    bm.to_mesh(obj.data)
    bm.free()


def banda_correa(bm, M, c1, r1, c2, r2, t=0.0012, w=0.005, n=72):
    """Correa cerrada alrededor de dos poleas (círculos en el plano local YZ, ancho w en X)."""
    loops = []
    for rr in (0.0, t):
        pts = []
        for k in range(n):
            a = 2 * pi * k / n
            d = Vector((cos(a), sin(a)))
            cc, r_ = max(((Vector(c1), r1), (Vector(c2), r2)), key=lambda q: q[0].dot(d) + q[1])
            p = cc + d * (r_ + rr)
            pts.append(p)
        loops.append(pts)
    rings = []
    for (ri, xx) in ((0, -w / 2), (1, -w / 2), (1, w / 2), (0, w / 2)):
        rings.append([bm.verts.new(M @ Vector((xx, p.x, p.y))) for p in loops[ri]])
    for j in range(4):
        A, B = rings[j], rings[(j + 1) % 4]
        for k in range(n):
            bm.faces.new((A[k], A[(k + 1) % n], B[(k + 1) % n], B[k]))


def add_pleated_cyl(bm, center, r0, amp, n_pleats, length, segs=144, M_axis=None):
    """Cilindro con pliegues (filtro de espuma), eje Z local."""
    M = M_T(center) @ (M_axis if M_axis is not None else Matrix.Identity(4))
    rings = []
    for z in (-length / 2, length / 2):
        ring = []
        for i in range(segs):
            a = 2 * pi * i / segs
            r = r0 + amp * cos(n_pleats * a)
            ring.append(bm.verts.new(M @ Vector((r * cos(a), r * sin(a), z))))
        rings.append(ring)
    A, B = rings
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((A[i], A[j], B[j], B[i]))
    bm.faces.new(list(reversed(A)))
    bm.faces.new(B)


def stadium(cx, cy, length, width, n=8, along='X'):
    """Contorno de ranura alargada (para cortes de aligeramiento)."""
    r = width / 2
    h = length / 2 - r
    pts = []
    for k in range(n + 1):
        a = -pi / 2 + pi * k / n
        pts.append((h + r * cos(a), r * sin(a)))
    for k in range(n + 1):
        a = pi / 2 + pi * k / n
        pts.append((-h + r * cos(a), r * sin(a)))
    if along == 'Y':
        pts = [(-y, x) for x, y in pts]
    return [(cx + x, cy + y) for x, y in pts]


def rclip(name, center, yaw, mat, col, parent):
    """Clip de alambre en 'R' que atraviesa un poste vertical."""
    c = Vector(center)
    R = Matrix.Rotation(yaw, 3, 'Z')
    loc = [(-0.0095, 0, 0), (0.0080, 0, 0), (0.0108, 0.0028, -0.0004), (0.0080, 0.0056, -0.0010),
           (0.0035, 0.0062, -0.0014), (0.0, 0.0074, -0.0016), (-0.0035, 0.0062, -0.0016),
           (-0.0085, 0.0048, -0.0018), (-0.0118, 0.0064, -0.0022)]
    pts = [c + R @ Vector(p) for p in loc]
    return tube(name, pts, 0.00062, mat, col, parent, res=8, bevel_res=2)


# ---------------------------------------------------------------------------
# Ruedas
# ---------------------------------------------------------------------------
def _profile_curve(prof_half, n=200):
    """Curva suave (Catmull-Rom) del perfil exterior de la llanta: lista de (y, r)
    desde el centro de la banda hacia el flanco, con su longitud de arco."""
    P = [Vector((y, r)) for y, r in prof_half]
    pts = []
    for i in range(len(P) - 1):
        p0 = P[i - 1] if i > 0 else P[i] * 2 - P[i + 1]
        p1, p2 = P[i], P[i + 1]
        p3 = P[i + 2] if i + 2 < len(P) else P[i + 1] * 2 - P[i]
        for k in range(12):
            t = k / 12
            t2, t3 = t * t, t * t * t
            pts.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                              (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    pts.append(P[-1])
    arc = [0.0]
    for i in range(1, len(pts)):
        arc.append(arc[-1] + (pts[i] - pts[i - 1]).length)
    return pts, arc


def _on_profile(pts, arc, t):
    """Punto (y, r) y normal exterior (ny, nr) en la longitud de arco t (t<0 = lado opuesto)."""
    sg = 1.0 if t >= 0 else -1.0
    t = min(abs(t), arc[-1] - 1e-6)
    for i in range(1, len(arc)):
        if arc[i] >= t:
            u = (t - arc[i - 1]) / max(arc[i] - arc[i - 1], 1e-9)
            p = pts[i - 1].lerp(pts[i], u)
            d = (pts[i] - pts[i - 1]).normalized()
            nrm = Vector((-d.y, d.x))                    # normal exterior de la sección (y, r)
            return Vector((sg * p.x, p.y)), Vector((sg * nrm.x, nrm.y))
    p = pts[-1]
    return Vector((sg * p.x, p.y)), Vector((0, 1))


def add_lug(bm, pts, arc, th0, t0, t1, dth, h, skew, nt=7, nv=3, sink=0.0008):
    """Taco que se adapta a la carcasa: va de t0 a t1 por el perfil, ocupa dth radianes
    y se inclina 'skew' radianes por metro de perfil. Eje de la rueda = Y."""
    grid_b, grid_t = [], []
    for i in range(nt + 1):
        t = t0 + (t1 - t0) * i / nt
        (y, r), (ny, nr) = _on_profile(pts, arc, t)
        rowb, rowt = [], []
        for j in range(nv + 1):
            th = th0 + skew * (t - t0) + dth * (j / nv - 0.5)
            ca, sa = cos(th), sin(th)
            pb = Vector(((r - sink * nr) * ca, y - sink * ny, (r - sink * nr) * sa))
            pt = Vector(((r + h * nr) * ca, y + h * ny, (r + h * nr) * sa))
            rowb.append(bm.verts.new(pb))
            rowt.append(bm.verts.new(pt))
        grid_b.append(rowb)
        grid_t.append(rowt)
    for i in range(nt):
        for j in range(nv):
            bm.faces.new((grid_t[i][j], grid_t[i + 1][j], grid_t[i + 1][j + 1], grid_t[i][j + 1]))
            bm.faces.new((grid_b[i][j], grid_b[i][j + 1], grid_b[i + 1][j + 1], grid_b[i + 1][j]))
    for i in range(nt):
        for j in (0, nv):
            a, b = (grid_b[i][j], grid_b[i + 1][j]), (grid_t[i + 1][j], grid_t[i][j])
            bm.faces.new((a[0], a[1], b[0], b[1]))
    for i in (0, nt):
        for j in range(nv):
            bm.faces.new((grid_b[i][j], grid_t[i][j], grid_t[i][j + 1], grid_b[i][j + 1]))


def build_wheels(root, col, M):
    to_y = AXIS_ROT['Y']            # el eje Z del torno pasa a ser el eje Y (eje de la rueda)
    TW = 0.0425                     # media anchura de la carcasa

    # --- carcasa de la llanta: banda, hombro redondeado, flanco y talón ---
    half = [(0.0, 0.0800), (0.0150, 0.0799), (0.0280, 0.0795), (0.0350, 0.0785), (0.0395, 0.0765),
            (0.0420, 0.0735), (0.0428, 0.0700), (0.0425, 0.0660), (0.0412, 0.0620), (0.0395, 0.0585)]
    prof = [(r, y) for y, r in half] + [(0.0572, 0.0372), (0.0565, 0.0)]
    prof = prof + [(r, -y) for r, y in reversed(prof[:-1]) if y > 0]
    prof = [(r, y) for r, y in prof]
    bm = bmesh.new()
    seen, clean = set(), []
    for r, y in prof:
        k = (round(r, 6), round(y, 6))
        if k not in seen:
            seen.add(k)
            clean.append((r, y))
    add_lathe(bm, clean, 96, to_y)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    smooth_bm(bm, 50)
    carcass = bmesh.new()
    me_c = bpy.data.meshes.new("tmp_carc")
    bm.to_mesh(me_c)
    bm.free()

    # --- tacos (patrón propio: bloques escalonados + tacos de hombro que envuelven el flanco) ---
    pts, arc = _profile_curve(half)
    lugs = bmesh.new()
    N = 22
    for i in range(N):
        th = 2 * pi * i / N
        sg = 1 if i % 2 == 0 else -1
        # bloque central inclinado, alterna de lado y cruza el centro
        add_lug(lugs, pts, arc, th, sg * -0.0035, sg * 0.0175, 0.112, 0.0070, sg * 4.2, nt=6, nv=3)
        # bloque intermedio del lado opuesto, desfasado medio paso
        add_lug(lugs, pts, arc, th + pi / N, -sg * 0.0065, -sg * 0.0205, 0.095, 0.0068, -sg * 3.0, nt=5, nv=3)
        # taco de hombro grande (envuelve el hombro hasta el flanco)
        for side in (1, -1):
            off = 0.0 if side == sg else pi / N
            add_lug(lugs, pts, arc, th + off, side * 0.0235, side * 0.0430, 0.120, 0.0064, 0.0, nt=8, nv=3)
            if (i // 1) % 2 == 0:                                          # nervio del flanco, alternado
                add_lug(lugs, pts, arc, th + off + pi / N, side * 0.0440, side * 0.0520, 0.060, 0.0030, 0.0,
                        nt=4, nv=2)
    bmesh.ops.recalc_face_normals(lugs, faces=lugs.faces[:])
    smooth_bm(lugs, None)
    me_l = bpy.data.meshes.new("tmp_lugs")
    lugs.to_mesh(me_l)
    lugs.free()
    lug_obj = bpy.data.objects.new("tmp_lugs", me_l)
    col.objects.link(lug_obj)
    bevel_finish(lug_obj, 0.0012, 2, 35)                                    # tacos con cantos redondeados
    carcass.from_mesh(me_c)
    carcass.from_mesh(lug_obj.data)
    tire_me = bpy.data.meshes.new("Llanta")
    carcass.to_mesh(tire_me)
    carcass.free()
    for o in (lug_obj,):
        me_ = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.meshes.remove(me_)
    bpy.data.meshes.remove(me_c)
    tire_me.materials.append(M["caucho"])

    # --- rin: barril, cara con 6 rayos aligerados, aro beadlock atornillado ---
    def pol(r, a, y):
        return (r * cos(a), y, r * sin(a))

    def solid(name, bm_, cutters_bms=()):
        """Crea un objeto cerrado, le resta cortadores (booleana robusta sobre una sola pieza)."""
        bmesh.ops.recalc_face_normals(bm_, faces=bm_.faces[:])
        me_ = bpy.data.meshes.new(name)
        bm_.to_mesh(me_)
        bm_.free()
        o_ = bpy.data.objects.new(name, me_)
        col.objects.link(o_)
        if cutters_bms:
            boolean_cut(o_, [cutter_obj("cut_" + name, cb_, col) for cb_ in cutters_bms])
        return o_

    parts = []
    bm = bmesh.new()                                                         # barril
    add_lathe(bm, [(0.0560, -0.0415), (0.0612, -0.0415), (0.0612, -0.0372), (0.0575, -0.0350),
                   (0.0570, 0.0300), (0.0600, 0.0320), (0.0600, 0.0340), (0.0545, 0.0340),
                   (0.0532, 0.0300), (0.0528, -0.0380)], 72, to_y)
    parts.append(solid("tmp_barril", bm))
    for k in range(6):                                                       # rayos con ranura
        a = 2 * pi * k / 6
        ri, ro, sw = 0.0185, 0.0540, radians(9)
        wi, wo = 0.0140 / ri / 2, 0.0230 / ro / 2
        bm = bmesh.new()
        add_hexa(bm, [pol(ri, a - wi, 0.0200), pol(ri, a + wi, 0.0200),
                      pol(ro, a + sw + wo, 0.0262), pol(ro, a + sw - wo, 0.0262),
                      pol(ri, a - wi, 0.0330), pol(ri, a + wi, 0.0330),
                      pol(ro, a + sw + wo, 0.0352), pol(ro, a + sw - wo, 0.0352)])
        am = a + sw * 0.55
        c = Vector(pol(0.0370, am, 0.0345))
        Mr = frame_axis(c, (0, 1, 0), Vector(pol(1.0, am, 0.0)), 'Z')
        cb = bmesh.new()
        add_prism(cb, stadium(0.0, 0.0, 0.0175, 0.0050, 8), -0.0030, 0.0030, Mr)
        parts.append(solid(f"tmp_rayo{k}", bm, (cb,)))
    bm = bmesh.new()                                                         # maza con hexágono
    add_lathe(bm, [(0.0080, 0.0170), (0.0205, 0.0170), (0.0215, 0.0200), (0.0215, 0.0335),
                   (0.0195, 0.0350), (0.0080, 0.0350)], 48, to_y)
    cb = bmesh.new()
    add_cyl_axis(cb, (0, 0.0335, 0), 'Y', 0.0098, 0.008, 6)
    parts.append(solid("tmp_maza", bm, (cb,)))
    bm = bmesh.new()
    for o_ in parts:
        bm.from_mesh(o_.data)
        me_ = o_.data
        bpy.data.objects.remove(o_, do_unlink=True)
        bpy.data.meshes.remove(me_)
    smooth_bm(bm, 35)
    rim_me = bpy.data.meshes.new("Rin")
    bm.to_mesh(rim_me)
    bm.free()
    rim_me.materials.append(M["rin"])
    rim_me = bevel_mesh_data(rim_me, col, 0.0005, 2, 30)

    # aro beadlock (pisa el talón de la llanta) + 12 tornillos M2
    bm = bmesh.new()
    add_lathe(bm, [(0.0548, 0.0340), (0.0640, 0.0340), (0.0648, 0.0350), (0.0648, 0.0388),
                   (0.0636, 0.0398), (0.0560, 0.0398), (0.0548, 0.0388)], 72, to_y)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    smooth_bm(bm, 40)
    lip_me = bpy.data.meshes.new("Rin_Beadlock")
    bm.to_mesh(lip_me)
    bm.free()
    lip_me.materials.append(M["anodizado"])

    hwr = Herrajes("Rueda_tmp", col, None, M)
    for k in range(12):
        a = 2 * pi * (k + 0.5) / 12
        hwr.tornillo(Vector(pol(0.0598, a, 0.0398)), (0, 1, 0), 0.008, 0.002, "boton")
    # hexágono de rueda (17 mm) + tuerca M5 con brida dentada + punta del eje
    hwr.casquillo((0, 0.0300, 0), (0, 1, 0), 0.0026, 0.0040, 0.001)
    hw_objs = hwr.build()
    bm = bmesh.new()
    add_cyl_axis(bm, (0, 0.03225, 0), 'Y', 0.0096, 0.0055, 6)               # hexágono (llena el alojamiento de la maza)
    add_cyl_axis(bm, (0, 0.0300, 0), 'Y', 0.0030, 0.0120, 12)
    add_lathe(bm, [(0.0026, 0.0350), (0.0072, 0.0350), (0.0072, 0.0362), (0.0052, 0.0370),
                   (0.0026, 0.0370)], 32, to_y)                              # brida dentada
    for k in range(24):
        a = 2 * pi * k / 24
        add_box(bm, (0.0008, 0.0012, 0.0016), Vector(pol(0.0062, a, 0.0352)), R_Y(-a))
    add_cyl_axis(bm, (0, 0.0395, 0), 'Y', 0.0052, 0.0050, 6)                # tuerca
    add_cyl_axis(bm, (0, 0.0430, 0), 'Y', 0.0024, 0.0030, 12)               # punta roscada del eje
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    smooth_bm(bm, 30)
    nut_me = bpy.data.meshes.new("Tuerca_Rueda")
    bm.to_mesh(nut_me)
    bm.free()
    nut_me.materials.append(M["cromo"])
    nut_me = bevel_mesh_data(nut_me, col, 0.0003, 2, 30)
    # eje de rueda escalonado (pasa por los dos rodamientos de la mangueta) + copa ranurada del palier
    y_copa = (Y_D1 - YW) - 0.0035                                            # boca de la copa (coord. local)
    bm = bmesh.new()
    add_lathe(bm, [(0.0001, y_copa + 0.0120), (0.0060, y_copa + 0.0120), (0.0060, -0.0120),
                   (0.0040, -0.0110), (0.0040, 0.0340), (0.0024, 0.0345), (0.0024, 0.0445),
                   (0.0001, 0.0445)], 24, to_y)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    smooth_bm(bm, 35)
    stub_me = bpy.data.meshes.new("Eje_Rueda")
    bm.to_mesh(stub_me)
    bm.free()
    stub_me.materials.append(M["acero"])
    cup = copa_ranurada("Eje_Copa", M["chasis"], col, Matrix.Identity(4), 0.0120, 0.0060, 0.0090, 0.0050)   # ranura 5 mm: ±1.2 mm de juego al pasador
    cup.data.transform(M_T((0, y_copa, 0)) @ R_Z(pi))                         # boca hacia el centro del auto
    cup_me = cup.data
    bpy.data.objects.remove(cup, do_unlink=True)
    shared = [(o.name.split("_")[-1], o.data) for o in hw_objs]
    for o in hw_objs:
        bpy.data.objects.remove(o, do_unlink=True)

    names = {(1, 1): "Del_Izq", (1, -1): "Del_Der", (-1, 1): "Tras_Izq", (-1, -1): "Tras_Der"}
    wheels = {}
    for (f, s), nm in names.items():
        # las ruedas derechas se giran 180° en Z para que el rin mire hacia afuera
        e = empty("Rueda_" + nm, col, root, (f * XA, s * YW, WZ),
                  (0, 0, 0 if s > 0 else pi), 0.06, 'PLAIN_AXES')
        linked_obj("Llanta_" + nm, tire_me, col, e)
        linked_obj("Rin_" + nm, rim_me, col, e)
        linked_obj("Rin_Beadlock_" + nm, lip_me, col, e)
        linked_obj("Tuerca_" + nm, nut_me, col, e)
        linked_obj("Eje_Rueda_" + nm, stub_me, col, e)
        linked_obj("Eje_Copa_" + nm, cup_me, col, e)
        for key, me in shared:
            linked_obj(f"Herraje_Rueda_{nm}_{key}", me, col, e)
        wheels[nm] = e
    return wheels


# ---------------------------------------------------------------------------
# Amortiguador (eje Z local de 0 a L)
# ---------------------------------------------------------------------------
def ccw(poly):
    """Devuelve el polígono 2D en sentido antihorario."""
    a = 0.0
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        a += x1 * y2 - x2 * y1
    return list(poly) if a > 0 else list(reversed(poly))


def inset_poly(poly, d):
    """Desplaza hacia adentro (d > 0) o hacia afuera (d < 0) un polígono convexo antihorario."""
    n = len(poly)
    lines = []
    for i in range(n):
        p = Vector(poly[i])
        q = Vector(poly[(i + 1) % n])
        t = (q - p).normalized()
        nrm = Vector((-t.y, t.x))
        lines.append((p + nrm * d, t))
    out = []
    for i in range(n):
        p1, t1 = lines[i - 1]
        p2, t2 = lines[i]
        den = t1.x * t2.y - t1.y * t2.x
        a = ((p2.x - p1.x) * t2.y - (p2.y - p1.y) * t2.x) / den
        q = p1 + t1 * a
        out.append((q.x, q.y))
    return out


def round_poly(poly, r, n=5):
    """Redondea las esquinas de un polígono convexo antihorario con radio r."""
    out = []
    m = len(poly)
    for i in range(m):
        p0, p1, p2 = Vector(poly[i - 1]), Vector(poly[i]), Vector(poly[(i + 1) % m])
        d1 = (p0 - p1).normalized()
        d2 = (p2 - p1).normalized()
        ang = d1.angle(d2)
        t = r / math.tan(ang / 2)
        a = p1 + d1 * t
        b = p1 + d2 * t
        c = p1 + (d1 + d2).normalized() * (r / math.sin(ang / 2))
        a0 = atan2(a.y - c.y, a.x - c.x)
        a1 = atan2(b.y - c.y, b.x - c.x)
        da = a1 - a0
        while da > pi:
            da -= 2 * pi
        while da < -pi:
            da += 2 * pi
        for k in range(n + 1):
            ak = a0 + da * k / n
            out.append((c.x + r * cos(ak), c.y + r * sin(ak)))
    return out


def convex_hull_2d(pts):
    pts = sorted(set(pts))
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def add_sweep(bm, pts, r, segs=12):
    """Tubo cerrado de radio r a lo largo de una polilínea (marcos de transporte paralelo):
    alambres doblados como barras estabilizadoras."""
    P = [Vector(p) for p in pts]
    T = []
    for i in range(len(P)):
        a = P[max(i - 1, 0)]
        b = P[min(i + 1, len(P) - 1)]
        T.append((b - a).normalized())
    ref = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
    nrm = (ref - T[0] * ref.dot(T[0])).normalized()
    rings = []
    for i, (p, t) in enumerate(zip(P, T)):
        if i:
            nrm = (nrm - t * nrm.dot(t)).normalized()          # transporte paralelo
        bi = t.cross(nrm)
        rings.append([bm.verts.new(p + (nrm * cos(2 * pi * k / segs) + bi * sin(2 * pi * k / segs)) * r)
                      for k in range(segs)])
    for r0, r1 in zip(rings[:-1], rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def arco(c, a, b, n=8):
    """Puntos de un arco de centro c desde el punto a hasta el punto b (mismo radio)."""
    c, a, b = Vector(c), Vector(a), Vector(b)
    va, vb = a - c, b - c
    ang = va.angle(vb)
    ax = va.cross(vb).normalized()
    from mathutils import Quaternion
    return [c + Quaternion(ax, ang * k / n) @ va for k in range(n + 1)]


def add_beam(bm, p1, p2, w, h, up=(0, 0, 1)):
    """Viga rectangular de p1 a p2 (ancho w, alto h) con el alto hacia 'up'."""
    p1, p2 = Vector(p1), Vector(p2)
    z = (p2 - p1)
    L = z.length
    z.normalize()
    y = Vector(up)
    y = (y - z * y.dot(z)).normalized()
    x = y.cross(z)
    R = Matrix((x, y, z)).transposed().to_4x4()
    add_box(bm, (w, h, L), (p1 + p2) / 2, R)


def frame_axis(origin, axis, ref, which='Z'):
    """Matriz con el eje local `which` (Z o Y) sobre `axis`; `ref` fija el giro."""
    a = Vector(axis).normalized()
    r = Vector(ref)
    r = (r - a * r.dot(a)).normalized()
    if which == 'Z':
        z, x = a, r
        y = z.cross(x)
    else:
        y, z = a, r
        x = y.cross(z)
    M = Matrix((x, y, z)).transposed().to_4x4()
    M.translation = Vector(origin)
    return M


# ---------------------------------------------------------------------------
# Relaciones (rig): pivotes con su pose de reposo registrada
# ---------------------------------------------------------------------------
REST = {}


def rest_of(o):
    return REST.get(o.name, Matrix.Identity(4)) if o is not None else Matrix.Identity(4)


def pivot(name, col, parent, Mw, size=0.012, kind='PLAIN_AXES'):
    """Empty cuya pose de reposo es Mw (mundo); se mueve con su padre."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = size
    col.objects.link(e)
    if parent is not None:
        e.parent = parent
        e.matrix_parent_inverse = rest_of(parent).inverted()
    e.matrix_basis = Mw.copy()
    REST[name] = Mw.copy()
    return e


def pivot_local(name, col, parent, size=0.012, kind='PLAIN_AXES'):
    """Empty pegado al padre con transformación local nula (para rotar en sus ejes)."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = size
    col.objects.link(e)
    e.parent = parent
    REST[name] = rest_of(parent).copy()
    return e


def attach(o, parent):
    """Cuelga un objeto (construido en coordenadas de mundo) de un pivote sin moverlo."""
    o.parent = parent
    o.matrix_parent_inverse = rest_of(parent).inverted()
    return o


def c_damped(o, target, axis='TRACK_Z'):
    c = o.constraints.new('DAMPED_TRACK')
    c.target = target
    c.track_axis = axis
    return c


def c_stretch(o, target, rest):
    c = o.constraints.new('STRETCH_TO')
    c.target = target
    c.volume = 'NO_VOLUME'
    c.keep_axis = 'SWING_Y'
    c.rest_length = rest
    return c


def drive(obj, path, index, expr, var, ctrl, prop):
    """Driver con expresión simple (no requiere habilitar scripts de Python)."""
    fc = obj.driver_add(path, index)
    d = fc.driver
    d.type = 'SCRIPTED'
    v = d.variables.new()
    v.name = var
    v.type = 'SINGLE_PROP'
    v.targets[0].id_type = 'OBJECT'
    v.targets[0].id = ctrl
    v.targets[0].data_path = prop
    d.expression = expr
    for m in list(fc.modifiers):
        fc.modifiers.remove(m)
    return fc


def drive_multi(obj, path, index, expr, variables):
    """Driver con varias variables [(nombre, objeto, ruta)], expresión simple."""
    fc = obj.driver_add(path, index)
    d = fc.driver
    d.type = 'SCRIPTED'
    for name, ctrl, prop in variables:
        v = d.variables.new()
        v.name = name
        v.type = 'SINGLE_PROP'
        v.targets[0].id_type = 'OBJECT'
        v.targets[0].id = ctrl
        v.targets[0].data_path = prop
    d.expression = expr
    for m in list(fc.modifiers):
        fc.modifiers.remove(m)
    return fc


def helix_mesh(name, r, wire, length, turns, mat, col, sides=6, steps_per_turn=24):
    """Resorte como malla, a lo largo del eje Y local (para estirarlo con Stretch To)."""
    bm = bmesh.new()
    n = int(turns * steps_per_turn)
    rings = []
    for i in range(n + 1):
        t = i / n
        a = 2 * pi * turns * t
        tt = 0.5 - 0.5 * cos(pi * t)
        y = length * (0.84 * t + 0.16 * tt)
        c = Vector((r * cos(a), y, r * sin(a)))
        tan = Vector((-r * sin(a) * 2 * pi * turns, length, r * cos(a) * 2 * pi * turns)).normalized()
        nrm = Vector((cos(a), 0, sin(a)))
        nrm = (nrm - tan * nrm.dot(tan)).normalized()
        bin_ = tan.cross(nrm)
        rings.append([bm.verts.new(c + wire * (cos(2 * pi * k / sides) * nrm + sin(2 * pi * k / sides) * bin_))
                      for k in range(sides)])
    for i in range(n):
        A, B = rings[i], rings[i + 1]
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new((A[k], A[k2], B[k2], B[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f_ in bm.faces:
        f_.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    return o


# ---------------------------------------------------------------------------
# Geometría de la suspensión (balancín / pushrod)
# ---------------------------------------------------------------------------
# Esquema por rueda (f = +1 delante / -1 detrás, s = +1 izquierda / -1 derecha):
#   brazo inferior  L0 -> L1     (pivote interior en el mamparo, eje X)
#   brazo superior  U0 -> U1     (pivote interior en el mamparo, eje X)
#   mangueta        L1 -> U1     (eje de pivote de dirección = L1->U1)
#   varilla empuje  A  -> R      (A en el extremo del brazo inferior, R en el balancín)
#   balancín        gira en P alrededor del eje n (inclinado 35° hacia afuera del auto)
#   amortiguador    S  -> B      (S en el balancín, B en el soporte central)
# Balancín tipo "bellcrank" con eje perpendicular a la varilla y al amortiguador:
#   n = varilla x X  ->  la varilla y el amortiguador se mueven en el plano del balancín,
#   así las rótulas trabajan perpendiculares a sus pernos (sin forzar la bola).
#   Brazo hacia la varilla: paralelo a X (largo ROCK_B); brazo hacia el amortiguador:
#   paralelo a la varilla (largo ROCK_A). Los ojos quedan desplazados sobre el eje n,
#   lo que no cambia la cinemática (puntos sobre el eje de giro).
ROCK_A, ROCK_B = 0.020, 0.034      # brazo hacia el amortiguador / hacia la varilla
# cardanes centrales (extremos del eje, las copas quedan 4 mm hacia dentro): transmisión -> diferencial
CARDAN_DEL = (Vector((0.0745, -0.0200, 0.0740)), Vector((0.1510, 0.0000, 0.0810)))
CARDAN_TRAS = (Vector((0.0090, 0.0070, 0.0590)), Vector((-0.1510, 0.0100, 0.0620)))
OFF_R, OFF_S = 0.0080, 0.0085      # bola de la varilla bajo la placa / del amortiguador sobre la placa
PUSH_AY, PUSH_AZ, PUSH_DX = 0.115, 0.0715, 0.0095   # rótula inferior de la varilla en el brazo
PUSH_RY, PUSH_RZ = 0.050, 0.140    # rótula superior de la varilla
BRIDGE_X = {1: 0.080, -1: -0.0825}
TRAVEL = (-0.044, 0.036)           # recorrido de rueda: extensión / compresión (80 mm, 45 % de "sag")
# puntos de los brazos (y, z) desde el centro del auto; los exteriores entran en la rueda
Y_L0, Y_L1, Z_L = 0.045, 0.164, 0.060          # brazo inferior: 119 mm
Y_U0, Z_U0, Y_U1, Z_U1 = 0.050, 0.106, 0.155, 0.1165   # brazo superior: 105.5 mm
T_Y = 0.153                                     # rótula exterior de la bieleta (brazo de dirección)
# barra estabilizadora (por eje): bieleta vertical del brazo de la barra a una oreja del balancín
ESTAB_A, ESTAB_Y, ESTAB_QZ = 0.020, 0.040, 0.150   # bola de la bieleta: 20 mm sobre el brazo de la varilla, y=±40, z=150
                                                     # (espárrago horizontal en Y, perpendicular a la bieleta)
ESTAB_XT, ESTAB_ZT = 0.250, 0.128                    # tramo transversal delante/detrás del mamparo exterior
ESTAB_D = {1: 0.0034, -1: 0.0032}                    # diámetro del alambre (acero de resorte), ver calcular_estabilizadoras
CASTER = {1: 8.0, -1: 0.0}                      # grados: eje de dirección con la parte alta hacia atrás;
                                                # pasa por el centro de rueda -> avance (trail) = WZ·tan(caster)


def y_pivote(z):
    """y del eje de pivote (L1 -> U1) a la altura z."""
    return Y_L1 + (Y_U1 - Y_L1) * (z - Z_L) / (Z_U1 - Z_L)


Y_D1 = y_pivote(WZ)                             # centro de la copa exterior del palier (sobre el pivote)
Y_RD = Y_L1 + 0.0075                            # centro de la carcasa de rodamientos de la mangueta


def corner_points(f, s):
    xa = f * XA
    tc = math.tan(math.radians(CASTER[f]))
    x_l1 = xa + f * tc * (WZ - Z_L)                 # rótula inferior adelante del centro de rueda
    x_u1 = xa - f * tc * (Z_U1 - WZ)                # rótula superior atrás
    A = Vector((xa + f * PUSH_DX, s * PUSH_AY, PUSH_AZ))
    R = Vector((A.x, s * PUSH_RY, PUSH_RZ))
    d = (R - A).normalized()                         # dirección de la varilla (de abajo hacia arriba)
    X = Vector((1.0, 0.0, 0.0))
    n = d.cross(X).normalized()
    if n.z < 0:
        n = -n
    Rp = R + n * OFF_R                               # punto de la varilla en el plano de la placa
    P = Rp - X * (f * ROCK_B)                        # pivote hacia el centro del auto
    Sp = P + d * ROCK_A                              # brazo del amortiguador, paralelo a la varilla
    S = Sp + n * OFF_S
    v = n.cross(X).normalized()                      # segundo eje del plano de la placa
    b_q = (s * (ESTAB_Y + 0.0060) - P.y) / v.y
    Qp = P + X * (f * ESTAB_A) + v * b_q             # centro de la oreja en el plano de la placa
    Q = Vector((Qp.x, s * ESTAB_Y, ESTAB_QZ))        # bola de la bieleta, bajo la placa
    # la bola de abajo va bajo el punto medio del arco que recorre Q (balancín -31°..+36°):
    # así la bieleta se inclina lo mismo hacia cada lado
    from mathutils import Quaternion
    rango = (-31, 36) if f * s > 0 else (-36, 31)            # giro del balancín (signo según el lado)
    qs = [P + Quaternion(n, math.radians(a_)) @ (Q - P) for a_ in rango]
    E = Vector(((qs[0].x + qs[1].x) / 2, (qs[0].y + qs[1].y) / 2, ESTAB_ZT))
    Ax = Vector((f * ESTAB_XT, Q.y, ESTAB_ZT))       # eje de giro de la barra
    return dict(f=f, s=s, xa=xa, n=n, d=d, u=X, v=v, P=P, Sp=Sp, Rp=Rp, S=S, R=R, A=A, Qp=Qp, Q=Q, E=E, Ax=Ax,
                B=Vector((BRIDGE_X[f], S.y, S.z)),
                L0=Vector((xa, s * Y_L0, Z_L)), L1=Vector((x_l1, s * Y_L1, Z_L)),
                U0=Vector((xa, s * Y_U0, Z_U0)), U1=Vector((x_u1, s * Y_U1, Z_U1)),
                W=Vector((xa, s * YW, WZ)), D0=Vector((xa, s * 0.0525, WZ)), D1=Vector((xa, s * Y_D1, WZ)),
                T=Vector((xa - 0.026, s * T_Y, 0.094)))   # brazo de dirección hacia dentro (Ackermann)


def solve_corner(g):
    """Cinemática exacta: para cada ángulo del brazo inferior resuelve el brazo superior
    (cuadrilátero articulado), la mangueta, la rueda, la varilla y el balancín."""
    import numpy as np
    V = lambda v: np.array([v.x, v.y, v.z], dtype=float)
    Lf = np.linalg.norm

    def Rx(a):
        c, s_ = cos(a), sin(a)
        return np.array([[1, 0, 0], [0, c, -s_], [0, s_, c]])

    def rotx(v, c, a):
        return c + Rx(a) @ (v - c)

    def rot_axis(v, c, k, a):
        vv = v - c
        return c + vv * cos(a) + np.cross(k, vv) * sin(a) + k * np.dot(k, vv) * (1 - cos(a))

    def newton(fun, x0):
        x = x0
        for _ in range(80):
            fv = fun(x)
            d = (fun(x + 1e-8) - fv) / 1e-8
            if d == 0:
                break
            x -= fv / d
            if abs(fv) < 1e-14:
                break
        return x

    s = g['s']
    L0, L1, U0, U1, W = V(g['L0']), V(g['L1']), V(g['U0']), V(g['U1']), V(g['W'])
    A0, R0, S0, B, P, k = V(g['A']), V(g['R']), V(g['S']), V(g['B']), V(g['P']), V(g['n'])
    c_len, Lp, Ls0 = Lf(U1 - L1), Lf(R0 - A0), Lf(S0 - B)
    rows = []
    for direction in (1, -1):
        bb, pp = 0.0, 0.0
        for th in np.arange(0.0 if direction > 0 else 0.003, 0.70, 0.003) * direction:
            al = s * th
            l1 = rotx(L1, L0, al)
            bb = newton(lambda q: Lf(rotx(U1, U0, q) - l1) - c_len, bb)
            u1 = rotx(U1, U0, bb)
            v0, v1 = U1 - L1, u1 - l1
            gam = atan2(v1[2], v1[1]) - atan2(v0[2], v0[1])
            w = l1 + Rx(gam) @ (W - L1)
            a_ = rotx(A0, L0, al)
            pp = newton(lambda q: Lf(rot_axis(R0, P, k, q) - a_) - Lp, pp)
            s_ = rot_axis(S0, P, k, pp)
            rows.append((w[2] - W[2], al, bb, pp, Ls0 - Lf(s_ - B), gam * s, (w[1] - W[1]) * s))
    rows.sort()
    return np.array(rows)


def fit_expr(h, y, var='h', deg=5):
    import numpy as np
    X = np.vstack([h ** k for k in range(1, deg + 1)]).T
    c = np.linalg.lstsq(X, y, rcond=None)[0]
    err = float(np.abs(X @ c - y).max())
    expr = "+".join(f"({ck:.10g})*" + "*".join([var] * k) for k, ck in enumerate(c, 1))
    return expr, err


def corner_kinematics(g):
    import numpy as np
    d = solve_corner(g)
    m = (d[:, 0] >= TRAVEL[0] - 0.004) & (d[:, 0] <= TRAVEL[1] + 0.004)
    d = d[m]
    h = d[:, 0]
    out = {}
    for key, col in (("brazo_inf", 1), ("brazo_sup", 2), ("balancin", 3)):
        out[key], out[key + "_err"] = fit_expr(h, d[:, col])
    out["mangueta"], out["mangueta_err"] = fit_expr(h, d[:, 5] * g['s'] - d[:, 1])   # giro relativo al brazo inf.
    out["amort"], out["amort_err"] = fit_expr(h, d[:, 4])                             # acortamiento del amortiguador
    sel = (h >= TRAVEL[0]) & (h <= TRAVEL[1])
    out["amort_min"], out["amort_max"] = float(d[sel, 4].min()), float(d[sel, 4].max())
    def mr(lo, hi):
        mm = (h >= lo) & (h <= hi)
        return float(np.polyfit(h[mm], d[mm, 4], 1)[0])
    out["mr"] = (mr(TRAVEL[0], TRAVEL[0] + 0.01), mr(-0.005, 0.005), mr(TRAVEL[1] - 0.01, TRAVEL[1]))
    out["caida"] = (float(d[sel, 5].min() * 180 / pi), float(d[sel, 5].max() * 180 / pi))
    return out

# ---------------------------------------------------------------------------
# Tornillería y rodamientos (métrica de RC: M3, M4, M5)
# ---------------------------------------------------------------------------
class Herrajes:
    """Acumula tornillos, tuercas, arandelas, bolas y rodamientos de un mismo
    'dueño' (pivote o chasis) y los crea al final como pocos objetos."""
    MATS = {"acero": "acero", "hueco": "plastico", "nylon": "etiqueta", "cromo": "cromo",
            "sello": "silicona", "bronce": "anodizado"}

    def __init__(self, name, col, owner, M):
        self.name, self.col, self.owner, self.M = name, col, owner, M
        self.bms = {}

    def _bm(self, key):
        if key not in self.bms:
            self.bms[key] = bmesh.new()
        return self.bms[key]

    @staticmethod
    def _frame(origin, axis):
        a = Vector(axis).normalized()
        ref = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((1, 0, 0))
        return frame_axis(origin, a, ref, 'Z')

    def tornillo(self, origin, axis, length, d=0.003, head="boton"):
        """origin = cara de apoyo de la cabeza; axis = hacia donde mira la cabeza.
        Cabezas: 'boton' (ISO 7380), 'cilindrica' (DIN 912), 'avellanada' (DIN 7991)."""
        M = self._frame(origin, axis)
        k = d / 0.003
        if head == "boton":
            prof, htop = [(1e-4, 0), (0.0029, 0), (0.0029, 0.0004), (0.0024, 0.0012), (0.0013, 0.00165),
                          (1e-4, 0.00165)], 0.00165
        elif head == "cilindrica":
            prof, htop = [(1e-4, 0), (0.00275, 0), (0.00275, 0.0027), (0.0025, 0.003), (1e-4, 0.003)], 0.003
        else:
            prof, htop = [(1e-4, -0.0016), (0.0015, -0.0016), (0.0030, 0.0), (1e-4, 0.0)], 0.0
        add_lathe(self._bm("acero"), [(r * k, z * k) for r, z in prof], 20, M)
        add_cyl(self._bm("acero"), 0.46 * d, length, M @ M_T((0, 0, -length / 2)), 12)
        add_cyl(self._bm("hueco"), 0.00118 * k, 0.0003, M @ M_T((0, 0, htop * k - 0.0001)), 6)   # hexágono Allen

    def tuerca(self, origin, axis, d=0.003, nylon=True):
        """Tuerca autoblocante: origin = cara de apoyo, axis = hacia afuera."""
        M = self._frame(origin, axis)
        k = d / 0.003
        add_cyl(self._bm("acero"), 0.0032 * k, 0.0024 * k, M @ M_T((0, 0, 0.0012 * k)), 6)
        if nylon:
            add_cyl(self._bm("nylon"), 0.0026 * k, 0.0011 * k, M @ M_T((0, 0, 0.00295 * k)), 20)

    def arandela(self, origin, axis, d=0.003, ro=None):
        M = self._frame(origin, axis)
        k = d / 0.003
        ro = ro or 0.0035 * k
        add_lathe(self._bm("acero"), [(0.0017 * k, 0), (ro, 0), (ro, 0.0005 * k), (0.0017 * k, 0.0005 * k)], 24, M)

    def rodamiento(self, center, axis, ri, ro, w, flange=0.0, sello="sello"):
        """Rodamiento sellado (pista interior, exterior, sello); opcionalmente con pestaña."""
        M = self._frame(center, axis)
        t = 0.2 * (ro - ri)
        add_lathe(self._bm("cromo"), [(ri, -w / 2), (ri + t, -w / 2), (ri + t, w / 2), (ri, w / 2)], 32, M)
        po = [(ro - t, -w / 2), (ro, -w / 2), (ro, w / 2), (ro - t, w / 2)]
        if flange:
            po = [(ro - t, -w / 2), (ro, -w / 2), (ro, w / 2 - 0.0006), (ro + flange, w / 2 - 0.0006),
                  (ro + flange, w / 2), (ro - t, w / 2)]
        add_lathe(self._bm("cromo"), po, 32, M)
        add_lathe(self._bm(sello), [(ri + t, -w / 2 + 0.0003), (ro - t, -w / 2 + 0.0003), (ro - t, w / 2 - 0.0003),
                                    (ri + t, w / 2 - 0.0003)], 32, M)

    def bola(self, center, r=0.0032):
        bmesh.ops.create_uvsphere(self._bm("cromo"), u_segments=18, v_segments=10, radius=r, matrix=M_T(center))

    def pasador(self, a, b, r, key="cromo"):
        add_cyl_pts(self._bm(key), a, b, r, 12)

    def clip_e(self, center, axis, r=0.0040):
        M = self._frame(center, axis)
        add_cyl(self._bm("bronce"), r, 0.0008, M, 14)

    def casquillo(self, center, axis, ri, ro, w):
        M = self._frame(center, axis)
        add_lathe(self._bm("bronce"), [(ri, -w / 2), (ro, -w / 2), (ro, w / 2), (ri, w / 2)], 20, M)

    def build(self):
        out = []
        for key, bm in self.bms.items():
            if not bm.verts:
                bm.free()
                continue
            o = mesh_obj(f"Herraje_{self.name}_{key}", bm, self.M[self.MATS[key]], self.col, None, smooth=35)
            if self.owner is not None:
                attach(o, self.owner)
            out.append(o)
        self.bms = {}
        return out


def ring_profile(ri, ro, w, n=6):
    """Sección de un terminal de rótula con asiento esférico (radio ri) para la bola:
    la bola puede girar sin que el anillo la atraviese."""
    hw_ = w / 2
    prof = [(ro, -hw_), (ro + 0.0004, 0.0), (ro, hw_)]
    for k in range(n + 1):
        z = hw_ - 2 * hw_ * k / n
        prof.append((max((ri * ri - z * z), 1e-8) ** 0.5, z))
    return prof


def copa_ranurada(name, mat, col, M_loc, depth, bore, outer, slot_w, stem_r=0.0, stem_len=0.0,
                  boca=0.0012, boca_largo=0.0025):
    """Copa de salida (outdrive) con dos ranuras para el pasador del palier.
    Eje local +Y: la boca de la copa está en y=0 y el fondo en y=-depth.
    La boca se abre 'boca' en radio a lo largo de 'boca_largo' (avellanado): deja que el cuello
    del palier trabaje a más de 30° con el émbolo hundido."""
    bm = bmesh.new()
    prof = [(bore + boca, 0.0), (outer - 0.0006, 0.0), (outer, -0.0006), (outer, -depth), (stem_r or bore, -depth)]
    if stem_r:
        prof += [(stem_r, -depth - stem_len), (0.0001, -depth - stem_len)]
    else:
        prof += [(0.0001, -depth)]
    prof += [(0.0001, -depth + 0.0015), (bore, -depth + 0.0015), (bore, -boca_largo)]
    add_lathe(bm, prof, 36, AXIS_ROT['Y'])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    cutters = []
    for sg in (1, -1):
        cb = bmesh.new()
        add_box(cb, (slot_w, depth * 0.85, outer), (0, -depth * 0.85 / 2 + 0.0002, sg * (bore + outer) / 2))
        cutters.append(cutter_obj("cut_" + name, cb, col))
    boolean_cut(o, cutters)
    resmooth(o, 35)
    o.data.materials.append(mat)
    o.matrix_basis = M_loc
    return o


def rod_end(bm, joint, along, ring_axis, ri=0.0034, ro=0.0058, w=0.0055, body_len=0.011, body_r=0.0034):
    """Terminal de rótula: anillo con asiento esférico alrededor de la bola + cuerpo roscado."""
    ra = Vector(ring_axis)
    al = Vector(along).normalized()
    ra = (ra - al * ra.dot(al)).normalized()
    Mr = frame_axis(joint, ra, al, 'Z')
    add_lathe(bm, ring_profile(ri + 0.0002, ro, w), 24, Mr)
    a = Vector(joint) + al * (ro - 0.0005)
    add_cyl_pts(bm, a, a + al * body_len, body_r, 16)


# ---------------------------------------------------------------------------
# Cinemática de dirección (incluye bump steer) y brazo del servo
# ---------------------------------------------------------------------------
RACK_K = -0.022                     # desplazamiento de la cremallera por radián del control
HORN_C = Vector((0.1245, -0.046, 0.0962))   # brazo entre la rótula interior (abajo) y la cremallera
HORN_L = 0.018
LINK_K = Vector((0.148, -0.018, 0.0995))
RACK_X = 0.1500                    # cremallera / bellcrank
TIE_IN = (0.0460, 0.0915)           # rótula interior (y, z): optimizada -> bump steer < 0.05° en 80 mm
TIE_DZ = 0.0050                     # altura de la bola exterior sobre el brazo de dirección


def _carrier_tables(g):
    import numpy as np
    d = solve_corner(g)
    return d[:, 0], d[:, 1], d[:, 5] * g['s']       # h, ángulo brazo inf., giro mangueta (con signo real)


def steering_fit(g, I0, T0):
    """Ángulo de la mangueta alrededor del pivote (L1->U1) para cada (recorrido h, dirección d)."""
    import numpy as np
    Lf = np.linalg.norm
    V = lambda v: np.array([v[0], v[1], v[2]], dtype=float)
    hs_t, al_t, gam_t = _carrier_tables(g)
    L0, L1, U1, T0 = V(g['L0']), V(g['L1']), V(g['U1']), V(T0)
    I0 = V(I0)
    k0 = (U1 - L1) / Lf(U1 - L1)
    Lt = Lf(T0 - I0)

    def Rx(a):
        c, s_ = cos(a), sin(a)
        return np.array([[1, 0, 0], [0, c, -s_], [0, s_, c]])

    def rod(v, k, a):
        return v * cos(a) + np.cross(k, v) * sin(a) + k * np.dot(k, v) * (1 - cos(a))

    rows = []
    for h in np.unique(np.concatenate([np.linspace(TRAVEL[0], TRAVEL[1], 9), [0.0]])):
        al = float(np.interp(h, hs_t, al_t))
        gam = float(np.interp(h, hs_t, gam_t))
        l1 = L1 if al == 0 else (L0 + Rx(al) @ (L1 - L0))
        phi = 0.0
        for dd in np.concatenate([np.linspace(0, 0.42, 8), np.linspace(0, -0.42, 8)[1:]]):
            if dd == 0:
                phi = 0.0
            I = I0 + np.array([0.0, RACK_K * dd, 0.0])
            fun = lambda p: Lf(l1 + Rx(gam) @ rod(T0 - L1, k0, p) - I) - Lt
            for _ in range(60):
                fv = fun(phi)
                dv = (fun(phi + 1e-8) - fv) / 1e-8
                if dv == 0:
                    break
                phi -= fv / dv
                if abs(fv) < 1e-13:
                    break
            rows.append((h, dd, phi))
    a = np.array(rows)
    terms = [(i, j) for i in range(4) for j in range(4) if 0 < i + j <= 3]     # expresión corta (<256 car.)
    X = np.vstack([a[:, 0] ** i * a[:, 1] ** j for i, j in terms]).T
    c = np.linalg.lstsq(X, a[:, 2], rcond=None)[0]
    err = float(np.abs(X @ c - a[:, 2]).max())
    parts = []
    for (i, j), ck in zip(terms, c):
        if abs(ck) < 1e-9:
            continue
        mon = "*".join(["h"] * i + ["d"] * j)
        parts.append(f"{ck:+.6g}*{mon}")
    lock = (a[(a[:, 0] == 0) & (a[:, 1] == a[:, 1].max()), 2], a[(a[:, 0] == 0) & (a[:, 1] == a[:, 1].min()), 2])
    expr = "".join(parts).lstrip("+")
    assert len(expr) < 250, "expresión de dirección demasiado larga"
    return expr, err, lock


def horn_fit():
    """Ángulo del brazo del servo para que la varilla al bellcrank conserve su largo."""
    import numpy as np
    Lf = np.linalg.norm
    C = np.array(HORN_C[:])
    H0 = C + np.array([HORN_L, 0.0, 0.0])
    K0 = np.array(LINK_K[:])
    Ld = Lf(K0 - H0)
    rows, gam = [], 0.0
    for dd in np.concatenate([np.linspace(0, 0.42, 15), np.linspace(0, -0.42, 15)[1:]]):
        if dd == 0:
            gam = 0.0
        K = K0 + np.array([0.0, RACK_K * dd, 0.0])
        fun = lambda q: Lf(C + np.array([HORN_L * cos(q), HORN_L * sin(q), 0.0]) - K) - Ld
        for _ in range(60):
            fv = fun(gam)
            dv = (fun(gam + 1e-8) - fv) / 1e-8
            if dv == 0:
                break
            gam -= fv / dv
            if abs(fv) < 1e-13:
                break
        rows.append((dd, gam))
    a = np.array(rows)
    return fit_expr(a[:, 0], a[:, 1], var='d', deg=5)

# ---------------------------------------------------------------------------
# Chasis
# ---------------------------------------------------------------------------
def build_chassis(root, C, M):
    col = C["chasis"]
    bm = bmesh.new()
    # placa angosta: espina de ±52 mm con alerones solo donde apoyan componentes
    # (caja de radio, tanque, servos y pies de las torres); ±56 mm bajo los mamparos
    izq = [(0.245, 0.040), (0.245, 0.050), (0.2425, 0.056), (0.153, 0.056), (0.147, 0.076), (0.081, 0.076), (0.076, 0.071),
           (0.064, 0.071), (0.060, 0.054), (0.052, 0.054), (0.048, 0.077), (-0.071, 0.077), (-0.074, 0.072),
           (-0.092, 0.072), (-0.098, 0.052), (-0.146, 0.052), (-0.152, 0.056), (-0.2425, 0.056), (-0.245, 0.050), (-0.245, 0.040)]
    der = [(-0.245, -0.040), (-0.245, -0.050), (-0.2425, -0.056), (-0.152, -0.056), (-0.146, -0.052), (-0.098, -0.052),
           (-0.092, -0.072), (-0.066, -0.072), (-0.060, -0.052), (0.058, -0.052), (0.064, -0.082),
           (0.141, -0.082), (0.153, -0.056), (0.2425, -0.056), (0.245, -0.050), (0.245, -0.040)]
    plate = round_poly(ccw(izq + der), 0.0030, 3)
    add_prism(bm, plate, 0.045, 0.049)                              # placa de 4 mm (7075)
    for f in (1, -1):
        x0, x1 = f * 0.243, f * 0.298                   # la rampa se solapa 2 mm con la placa (unión limpia)
        pts = [(x0, -0.040, 0.045), (x0, 0.040, 0.045), (x1, 0.034, 0.073), (x1, -0.034, 0.073),
               (x0, -0.040, 0.049), (x0, 0.040, 0.049), (x1, 0.034, 0.077), (x1, -0.034, 0.077)]
        add_hexa(bm, pts)
    pl = mesh_obj("Chasis_Placa", bm, M["chasis"], col, root, smooth=None)
    cutters = []
    for (cx, cy, ln, wd) in ((-0.125, 0.030, 0.032, 0.009), (-0.125, -0.030, 0.032, 0.009),
                             (-0.030, 0.046, 0.060, 0.008), (0.112, 0.0, 0.03, 0.008), (0.112, 0.060, 0.03, 0.008)):
        cb = bmesh.new()
        add_prism(cb, stadium(cx, cy, ln, wd, 8), 0.040, 0.053)
        cutters.append(cutter_obj("cut_placa", cb, col))
    boolean_cut(pl, cutters, auto_interseccion=True)

    hw_c = Herrajes("Chasis", col, root, M)
    for (x, y) in ((0.062, 0.050), (0.062, -0.052), (0.112, -0.020), (-0.062, -0.054), (-0.110, 0.040),
                   (-0.110, -0.040), (0.268, 0.022), (0.268, -0.022), (-0.268, 0.022), (-0.268, -0.022)):
        # avellanados desde abajo, al ras de la cara inferior de la placa (nada sobresale hacia el piso)
        zb = 0.045 if abs(x) < 0.245 else 0.045 + (abs(x) - 0.245) * (0.028 / 0.053)
        nrm = (0, 0, -1) if abs(x) < 0.245 else ((1 if x > 0 else -1) * 0.467, 0, -0.884)
        hw_c.tornillo((x, y, zb), nrm, 0.010, 0.003, "avellanada")

    for f, nm in ((1, "Del"), (-1, "Tras")):
        bm = bmesh.new()
        add_box(bm, (0.026, 0.05, 0.022), (f * 0.290, 0, 0.088))
        poly = [(f * 0.284, 0.065), (f * 0.312, 0.045), (f * 0.312, -0.045), (f * 0.284, -0.065)]
        if f < 0:
            poly = poly[::-1]
        add_prism(bm, poly, 0.076, 0.082)
        mesh_obj("Parachoques_Base_" + nm, bm, M["plastico"], col, root, smooth=None)
        pts = [(f * 0.284, 0.098, 0.100), (f * 0.304, 0.084, 0.094), (f * 0.316, 0.045, 0.090),
               (f * 0.316, -0.045, 0.090), (f * 0.304, -0.084, 0.094), (f * 0.284, -0.098, 0.100)]
        tube("Parachoques_" + nm, pts, 0.0068, M["plastico2"], col, root)

    # postes de carrocería (por fuera de los balancines) + clips en "R"
    bm = bmesh.new()
    for f in (1, -1):
        for y in (-0.028, 0.028):
            add_cyl_pts(bm, (f * 0.230, y, 0.112), (f * 0.230, y, 0.258), 0.0042, 16)
    mesh_obj("Postes_Carroceria", bm, M["plastico"], col, root)
    k = 0
    for f in (1, -1):
        for y in (-0.028, 0.028):
            k += 1
            rclip(f"Clip_R_{k}", (f * 0.230, y, 0.2515), 0.0 if y > 0 else pi, M["cromo"], col, root)

    # soportes centrales de los amortiguadores: dos torres + travesaño + orejas por amortiguador
    # (abiertos al centro para que pasen el cardán, el freno y el arranque)
    for f, nm in ((1, "Del"), (-1, "Tras")):
        gl = corner_points(f, 1)
        B0, zc = gl["B"], gl["B"].z
        xa0, xa1 = sorted((B0.x - f * 0.009, B0.x + f * 0.0025))
        yt0, yt1 = B0.y + 0.0075, B0.y + 0.0175                               # torre fuera del ojo
        bm = bmesh.new()
        for sg in (1, -1):
            add_box_minmax(bm, (xa0, min(sg * yt0, sg * yt1), 0.049), (xa1, max(sg * yt0, sg * yt1), zc + 0.0165))
            add_box_minmax(bm, (xa0 - 0.004, min(sg * yt0, sg * yt1) - 0.002, 0.049),
                           (xa1 + 0.004, max(sg * yt0, sg * yt1) + 0.002, 0.0535))   # pie
        add_box_minmax(bm, (xa0, -yt1, zc + 0.0115), (xa1, yt1, zc + 0.0165))      # travesaño
        mesh_obj("Soporte_Amortiguadores_" + nm, bm, M["chasis"], col, root, smooth=None)
        bm = bmesh.new()
        ex0, ex1 = sorted((B0.x - f * 0.0070, B0.x + f * 0.0030))
        for sg in (1, -1):
            for dz in (-0.0072, 0.0072):                      # orejas arriba y abajo del ojo
                add_box_minmax(bm, (ex0, min(sg * (B0.y - 0.0065), sg * yt0), zc + dz - 0.00125),
                               (ex1, max(sg * (B0.y - 0.0065), sg * yt0), zc + dz + 0.00125))
        mesh_obj("Soporte_Amort_Orejas_" + nm, bm, M["chasis"], col, root, smooth=None)
        # tirante diagonal: del travesaño de la torre al techo del diferencial (triangula la torre)
        x_tr = xa1 if f > 0 else xa0
        p1 = Vector((x_tr - f * 0.0045, 0.0, zc + 0.0210))          # apoyado sobre el tirante central
        p2 = Vector((f * 0.1665, 0.0, 0.1225))
        bm = bmesh.new()
        add_beam(bm, p1, p2, 0.012, 0.003)
        add_box_minmax(bm, (min(f * 0.1630, f * 0.1700), -0.008, 0.1150), (max(f * 0.1630, f * 0.1700), 0.008, 0.1215))  # pie
        tir = mesh_obj("Tirante_Superior_" + nm, bm, M["chasis"], col, root, smooth=None)
        cb = bmesh.new()
        L_t = (p2 - p1).length
        for k_ in range(3):                                                   # ranuras de aligeramiento
            c_ = p1.lerp(p2, 0.25 + 0.25 * k_)
            add_beam(cb, c_ - (p2 - p1).normalized() * 0.0065, c_ + (p2 - p1).normalized() * 0.0065, 0.005, 0.02)
        boolean_cut(tir, [cutter_obj("cut_tirante", cb, col)])
        hw_c.tornillo((f * 0.1665, 0.0, 0.1215), (0, 0, 1), 0.012, 0.003, "boton")
        hw_c.tornillo((x_tr - f * 0.0030, 0.0, zc + 0.0222), (0, 0, 1), 0.012, 0.003, "boton")
        hw_c.tornillo(((xa0 + 0.0035) if f > 0 else (xa1 - 0.0035), 0.0, zc + 0.0195), (0, 0, 1), 0.010, 0.003, "boton")
        # placa protectora de UHMW bajo la rampa del chasis (reemplazable)
        # sigue la cara inferior de la rampa (de x=0.243, z=45 a x=0.298, z=73) desde x=0.252:
        # su punto más bajo queda por encima de la placa, no resta distancia al piso
        a0, a1 = Vector((f * 0.243, 0.040, 0.045)), Vector((f * 0.298, 0.034, 0.073))
        pa = a0.lerp(a1, (0.252 - 0.243) / 0.055)
        k_n = Vector((f * 0.028, 0.0, -0.055)).normalized() * 0.002          # 2 mm hacia afuera de la rampa
        pts = [Vector((pa.x, -pa.y, pa.z)), Vector((pa.x, pa.y, pa.z)), Vector((a1.x, a1.y, a1.z)), Vector((a1.x, -a1.y, a1.z))]
        bot = [q + k_n for q in pts]
        bm = bmesh.new()
        add_hexa(bm, bot + pts)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        mesh_obj("Placa_Protectora_" + nm, bm, M["plastico2"], col, root, smooth=None)
        for yy in (-0.020, 0.020):
            q_ = a0.lerp(a1, (0.2735 - 0.243) / 0.055); q_ = Vector((q_.x, yy, q_.z)) + k_n
            hw_c.tornillo(q_, tuple(k_n.normalized()), 0.008, 0.003, "avellanada")
        for sg in (1, -1):
            Bp = Vector((B0.x, sg * B0.y, zc))
            hw_c.bola(Bp, 0.0034)                                                # bola de la rótula
            hw_c.tornillo(Bp - Vector((0, 0, 0.0085)), (0, 0, -1), 0.019, 0.003, "boton")
            hw_c.tuerca(Bp + Vector((0, 0, 0.0085)), (0, 0, 1))
            for dx in (-0.0035, 0.0035):                                         # pies de las torres
                hw_c.tornillo(((xa0 + xa1) / 2 + dx * 2.2, sg * (yt0 + yt1) / 2, 0.0535), (0, 0, 1),
                              0.008, 0.003, "boton")
    # tirante central: une los travesaños de las dos torres por encima del motor (cierra la caja
    # torre-placa-torre y le devuelve rigidez a torsión a la placa angosta)
    zc = corner_points(1, 1)["B"].z
    bm = bmesh.new()
    xs = (-0.0850, 0.0825)
    add_box_minmax(bm, (xs[0], -0.0075, zc + 0.0165), (xs[1], 0.0075, zc + 0.0195))
    tc = mesh_obj("Tirante_Central", bm, M["chasis"], col, root, smooth=None)
    cb = bmesh.new()
    for xx in (-0.050, -0.017, 0.017, 0.050):
        add_prism(cb, stadium(xx, 0.0, 0.024, 0.006, 8), zc + 0.010, zc + 0.026)
    boolean_cut(tc, [cutter_obj("cut_tirante_c", cb, col)])
    hw_c.build()


# ---------------------------------------------------------------------------
# Suspensión con relaciones mecánicas
# ---------------------------------------------------------------------------
def build_shock_rig(nm, g, rocker_pv, M, col, root):
    """Amortiguador telescópico: el cuerpo apunta al ojo del balancín y el vástago al
    soporte central; el resorte se estira entre sus dos asientos."""
    import numpy as np
    S, B, n = g["S"], g["B"], g["n"]
    L = (S - B).length
    d_ = solve_corner(g)
    dc = float(np.interp(TRAVEL[1], d_[:, 0], d_[:, 4]))          # acortamiento en compresión total
    de = -float(np.interp(TRAVEL[0], d_[:, 0], d_[:, 4]))         # alargamiento en extensión total
    body_len = L - dc - 0.0455                 # copa del resorte a 1.5 mm del sello en compresión total
    sobra = body_len - (dc + de + 0.013)       # holgura extra: se reparte entre fondo y enganche
    assert sobra > -1e-4, f"amortiguador {nm} demasiado corto ({sobra * 1000:.1f} mm)"
    g["amort_interno"] = dict(largo=L, compresion=dc, extension=de, cuerpo=body_len,
                              margen_fondo=0.003 + sobra / 2, enganche=0.010 + sobra / 2)
    s_t = pivot(f"Amort_{nm}_Ojo_Balancin", col, rocker_pv, M_T(S), 0.006)
    body = pivot(f"Amort_{nm}_Cuerpo", col, root, frame_axis(B, S - B, (0, 0, 1)), 0.01)
    shaft = pivot(f"Amort_{nm}_Vastago", col, rocker_pv, frame_axis(S, B - S, n), 0.01)
    c_damped(body, s_t)
    c_damped(shaft, body)
    # --- cuerpo (coordenadas locales: z desde el soporte hacia el balancín)
    ring = ring_profile(0.0036, 0.0058, 0.0056)
    bm = bmesh.new()
    add_lathe(bm, ring, 24, AXIS_ROT['X'])                                  # ojo con bola (perno vertical)
    add_cyl(bm, 0.0050, 0.006, M_T((0, 0, 0.0075)), 18)
    mesh_obj(f"Amort_{nm}_Ojo_Fijo", bm, M["plastico"], col, body)
    bm = bmesh.new()
    add_cyl(bm, 0.0118, 0.008, M_T((0, 0, 0.008)), 32)                       # tapa
    add_cyl(bm, 0.0105, body_len, M_T((0, 0, 0.012 + body_len / 2)), 32)      # cuerpo
    add_cyl(bm, 0.0095, 0.004, M_T((0, 0, 0.012 + body_len + 0.002)), 32)    # sello
    for i in range(10):                                                      # rosca
        add_cyl(bm, 0.01085, 0.0007, M_T((0, 0, 0.014 + 0.0011 * i)), 32)
    add_cyl(bm, 0.0140, 0.004, M_T((0, 0, 0.030)), 32)                       # tuerca de precarga
    mesh_obj(f"Amort_{nm}_Cuerpo_Malla", bm, M["anodizado"], col, body)
    seat = pivot_local(f"Amort_{nm}_Asiento", col, body, 0.004)
    seat.location = (0, 0, 0.032)
    # --- vástago (z desde el balancín hacia el soporte)
    bm = bmesh.new()
    add_lathe(bm, ring, 24, AXIS_ROT['X'])                                  # rótula alrededor de la bola
    add_cyl(bm, 0.0050, 0.008, M_T((0, 0, 0.0095)), 18)
    mesh_obj(f"Amort_{nm}_Rotula", bm, M["plastico"], col, shaft)
    z_r = 0.012 + 0.003 + dc + sobra / 2                                      # punta del vástago en reposo (marco del cuerpo)
    z_end = L - z_r                                                          # pistón siempre dentro, sin tocar fondo
    bm = bmesh.new()
    add_cyl(bm, 0.0032, z_end - 0.010, M_T((0, 0, 0.010 + (z_end - 0.010) / 2)), 18)
    mesh_obj(f"Amort_{nm}_Vastago_Malla", bm, M["cromo"], col, shaft)
    bm = bmesh.new()
    add_cyl(bm, 0.0125, 0.004, M_T((0, 0, 0.026)), 32)                       # copa del resorte
    mesh_obj(f"Amort_{nm}_Copa", bm, M["anodizado"], col, shaft)
    # --- tope de compresión de uretano en el vástago (se apoya en la copa y toca el sello en
    #     los últimos 8 mm de recorrido de rueda; se aplasta con un driver de escala)
    hs_, comp_ = d_[:, 0], d_[:, 4]
    gap = lambda h: 0.0015 + dc - float(np.interp(h, hs_, comp_))
    h_b = TRAVEL[1] - 0.008
    Lb = gap(h_b)
    tb = pivot_local(f"Amort_{nm}_Tope_Base", col, shaft, 0.003)
    tb.location = (0, 0, 0.028)
    bm = bmesh.new()
    add_lathe(bm, [(0.0035, 0.0), (0.0058, 0.0), (0.0062, 0.15 * Lb), (0.0062, 0.85 * Lb), (0.0058, Lb),
                   (0.0035, Lb)], 24)
    tope = mesh_obj(f"Amort_{nm}_Tope", bm, M["uretano"], col, tb)
    g["tope"] = dict(largo_libre=Lb, h_contacto=h_b, aplastado_max=Lb - 0.0015)
    # --- resorte entre la copa (vástago) y el asiento (cuerpo)
    ls = L - 0.028 - 0.032
    spr = helix_mesh(f"Amort_{nm}_Resorte", 0.0118, 0.00125, ls, 6, M["acero"], col)
    spr.parent = shaft
    spr.matrix_basis = M_T((0, 0, 0.028)) @ R_X(pi / 2)
    c_stretch(spr, seat, ls)
    return body, shaft


def build_suspension(root, C, M):
    col = C["susp"]
    rig = {}
    for f, ej in ((1, "Del"), (-1, "Tras")):
        xa = f * XA
        # --- mamparo / caja del diferencial (fijo) ---
        bm = bmesh.new()
        add_box(bm, (0.075, 0.074, 0.066), (xa, 0, 0.082))                       # caja (deja libres los bujes)
        add_cyl_axis(bm, (xa, 0, WZ), 'Y', 0.032, 0.07, 40)
        dh = mesh_obj("Diferencial_" + ej, bm, M["plastico"], col, root, smooth=None)
        bv = dh.modifiers.new("Bevel", 'BEVEL')
        bv.width = 0.004
        bv.segments = 3
        bv.limit_method = 'ANGLE'
        bv.angle_limit = radians(40)
        apply_modifiers(dh)
        hw = Herrajes(f"Mamparo_{ej}", col, root, M)
        bm = bmesh.new()
        for s in (1, -1):                                                        # alojamiento del rodamiento
            add_lathe(bm, [(0.0096, -0.0035), (0.0118, -0.0035), (0.0118, 0.0035), (0.0096, 0.0035)], 32,
                      M_T((xa, s * 0.0405, WZ)) @ AXIS_ROT['Y'])
        ent = (CARDAN_DEL if f > 0 else CARDAN_TRAS)[1]
        add_cyl_axis(bm, (f * 0.1595, ent.y, ent.z), 'X', 0.0068, 0.0080, 28)    # entrada del piñón
        mesh_obj("Diferencial_Alojamientos_" + ej, bm, M["plastico"], col, root)
        for s, lado in ((1, "Izq"), (-1, "Der")):
            Mo = frame_axis((xa, s * 0.0560, WZ), (0, s, 0), (0, 0, 1), 'Y')
            so = copa_ranurada(f"Diferencial_Salida_{ej}_{lado}", M["chasis"], col, Mo, 0.0120, 0.0060, 0.0090,
                               0.0050, stem_r=0.0050, stem_len=0.0075)
            so.parent = root
            REST[so.name] = so.matrix_basis.copy()
            hw.rodamiento((xa, s * 0.0405, WZ), (0, s, 0), 0.0050, 0.0095, 0.004)  # rodamiento de salida
        Myz = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        for px in (xa - 0.0395, xa + 0.0395):
            bm = bmesh.new()
            add_prism(bm, [(-0.056, 0.049), (0.056, 0.049), (0.056, 0.066), (0.050, 0.118),
                           (-0.050, 0.118), (-0.056, 0.066)], px - 0.0016, px + 0.0016, Myz)
            plt = mesh_obj(f"Mamparo_Placa_{ej}_{'Ext' if (px - xa) * f > 0 else 'Int'}", bm,
                           M["chasis"], col, root, smooth=None)
            cutters = []
            pasos = [(0.0, 0.0865, 0.0105), (0.0, 0.108, 0.005)]
            if (px - xa) * f < 0:                                               # paso del cardán central
                ent = (CARDAN_DEL if f > 0 else CARDAN_TRAS)[1]
                pasos.append((ent.y, ent.z, 0.0095))
            for (cy, cz, r) in pasos:
                cb = bmesh.new()
                add_cyl_axis(cb, (px, cy, cz), 'X', r, 0.01, 24)
                cutters.append(cutter_obj("cut_mamparo", cb, col))
            boolean_cut(plt, cutters)
        for px, sg in ((xa - 0.0411, -1), (xa + 0.0411, 1)):
            for (cy, cz) in ((-0.028, 0.054), (0.028, 0.054), (-0.028, 0.100), (0.028, 0.100)):
                hw.tornillo((px, cy, cz), (sg, 0, 0), 0.010, 0.003, "boton")
        bm = bmesh.new()                                                         # tapa del diferencial
        add_box_minmax(bm, (xa - 0.030, -0.021, 0.1145), (xa + 0.016, 0.021, 0.1172))
        for k_ in range(3):
            add_box_minmax(bm, (xa - 0.026 + 0.017 * k_, -0.017, 0.1172), (xa - 0.0245 + 0.017 * k_, 0.017, 0.1192))
        mesh_obj("Diferencial_Tapa_" + ej, bm, M["chasis"], col, root, smooth=None)
        for (px_, py_) in ((xa - 0.026, -0.017), (xa - 0.026, 0.017), (xa + 0.012, -0.017), (xa + 0.012, 0.017)):
            hw.tornillo((px_, py_, 0.1172), (0, 0, 1), 0.012, 0.003, "cilindrica")

        for s, lado in ((1, "Izq"), (-1, "Der")):
            nm = f"{ej}_{lado}"
            g = corner_points(f, s)
            P, S, R, A, n = g["P"], g["S"], g["R"], g["A"], g["n"]
            L0, L1, U0, U1 = g["L0"], g["L1"], g["U0"], g["U1"]

            # ===== pivotes (relaciones) =====
            pv_li = pivot(f"Pivote_Brazo_Inf_{nm}", col, root, M_T(L0), 0.015, 'SINGLE_ARROW')
            pv_ls = pivot(f"Pivote_Brazo_Sup_{nm}", col, root, M_T(U0), 0.015, 'SINGLE_ARROW')
            e_u1 = pivot(f"Rotula_Sup_{nm}", col, pv_ls, M_T(U1), 0.006, 'SPHERE')
            # la portamangueta gira sobre el pasador exterior del brazo (eje X por L1); el ángulo
            # sale del cuadrilátero exacto (driver), no de un Damped Track: con caster el eje del
            # pivote no es paralelo a X y el giro mínimo del Damped Track torcería la pieza
            pin = pivot(f"Mangueta_Pasador_{nm}", col, pv_li, M_T(L1), 0.008, 'SINGLE_ARROW')
            mang = pivot(f"Mangueta_{nm}", col, pin, frame_axis(L1, U1 - L1, (1, 0, 0)), 0.02, 'ARROWS')
            if f > 0:
                knuckle = pivot_local(f"Direccion_{nm}", col, mang, 0.02, 'CIRCLE')
            else:
                knuckle = mang
            rk_base = pivot(f"Balancin_Eje_{nm}", col, root, frame_axis(P, n, g["u"]), 0.012, 'SINGLE_ARROW')
            rk = pivot_local(f"Balancin_{nm}", col, rk_base, 0.012)
            e_r = pivot(f"Varilla_Ojo_Balancin_{nm}", col, rk, M_T(R), 0.005, 'SPHERE')
            e_d1 = pivot(f"Palier_Ext_{nm}", col, knuckle, M_T(g["D1"]), 0.005, 'SPHERE')
            hw_li = Herrajes(f"Brazo_Inf_{nm}", col, pv_li, M)
            hw_mg = Herrajes(f"Portamangueta_{nm}", col, mang, M)
            hw_kn = Herrajes(f"Mangueta_{nm}", col, knuckle, M) if f > 0 else hw_mg
            hw_rk = Herrajes(f"Balancin_{nm}", col, rk, M)

            # ===== brazo inferior en celosía (gira con su pivote) =====
            # dos largueros de sección en I que convergen en la horquilla, travesaños y
            # diagonales en W (cada panel es un triángulo), nudos con cartelas redondas
            yi, yl = s * Y_L0, s * (Y_L1 - 0.020)                               # raíz y arranque de la horquilla
            xo_i, xo_o = 0.0330, 0.0145
            def larguero(t, sg):
                xc = xa + (L1.x - xa) * t                                        # el centro se corre hacia L1
                return Vector((xc + sg * (xo_i + (xo_o - xo_i) * t), yi + (yl - yi) * t, Z_L))
            bm = bmesh.new()
            for sg in (-1, 1):
                p0, p1 = larguero(0.0, sg) + Vector((0, s * 0.004, 0)), larguero(1.0, sg)
                add_beam(bm, p0, p1, 0.0024, 0.0110)                               # alma
                for dz in (-0.0045, 0.0045):                                       # alas de la I
                    add_beam(bm, p0 + Vector((0, 0, dz)), p1 + Vector((0, 0, dz)), 0.0056, 0.0020)
            nudos = [(0.0, -1), (0.36, 1), (0.36, -1), (0.70, 1), (0.70, -1), (1.0, 1), (1.0, -1)]
            for t in (0.36, 0.70):                                                # travesaños
                add_beam(bm, larguero(t, -1), larguero(t, 1), 0.0040, 0.0080)
            for (t0, s0), (t1, s1) in (((0.04, -1), (0.36, 1)), ((0.36, 1), (0.70, -1)), ((0.70, -1), (1.0, 1))):
                add_beam(bm, larguero(t0, s0), larguero(t1, s1), 0.0034, 0.0070)  # diagonales en W
            for t, sg in nudos[1:]:
                add_cyl(bm, 0.0052, 0.0090, M_T(larguero(t, sg)), 16)            # cartelas de los nudos
            arm = mesh_obj("Brazo_Inferior_" + nm, bm, M["plastico"], col, root, smooth=None)
            attach(arm, pv_li)
            bm = bmesh.new()                                                     # bujes + horquilla + base de la varilla
            add_cyl_axis(bm, (xa, yi, Z_L), 'X', 0.0062, 0.074, 24)
            for dx in (-0.0145, 0.0145):
                add_box_minmax(bm, (L1.x + dx - 0.0045, min(yl, s * (Y_L1 + 0.006)), 0.0545),
                               (L1.x + dx + 0.0045, max(yl, s * (Y_L1 + 0.006)), 0.0655))
                add_cyl_axis(bm, (L1.x + dx, s * Y_L1, Z_L), 'X', 0.0060, 0.009, 24)
            add_box_minmax(bm, (A.x - 0.0065, A.y - 0.0065, 0.0585), (A.x + 0.0065, A.y + 0.0065, 0.0640))
            tA = (A.y - yi) / (yl - yi)                                          # puente de la base al larguero
            add_beam(bm, (A.x, A.y, 0.0612), larguero(tA, f), 0.0060, 0.0055)
            add_beam(bm, (A.x, A.y, 0.0612), larguero(tA, -f), 0.0045, 0.0055)
            for sg in (-1, 1):                                                   # orejas de la rótula
                add_box_minmax(bm, (A.x + sg * 0.0050 - 0.0010, A.y - 0.0050, 0.0630),
                               (A.x + sg * 0.0050 + 0.0010, A.y + 0.0050, PUSH_AZ + 0.0045))
            attach(mesh_obj("Brazo_Inferior_Nervios_" + nm, bm, M["plastico"], col, root, smooth=None), pv_li)
            bm = bmesh.new()
            add_cyl_axis(bm, (L1.x, s * Y_L1, Z_L), 'X', 0.0028, 0.040, 12)      # pasador exterior
            for dx in (-0.0195, 0.0195):                                         # clips E
                add_cyl_axis(bm, (L1.x + dx, s * Y_L1, Z_L), 'X', 0.0040, 0.0008, 12)
            attach(mesh_obj("Pasadores_Brazo_" + nm, bm, M["cromo"], col, root), pv_li)
            hw_li.bola(A, 0.0032)                                                # bola de la rótula inferior
            hw_li.tornillo((A.x + 0.0062, A.y, A.z), (1, 0, 0), 0.016, 0.003, "boton")
            hw_li.tuerca((A.x - 0.0062, A.y, A.z), (-1, 0, 0))
            bm = bmesh.new()
            add_cyl_axis(bm, (xa, yi, 0.06), 'X', 0.0032, 0.080, 12)             # pasador interior (fijo)
            for dx in (-0.0395, 0.0395):
                add_cyl_axis(bm, (xa + dx, yi, 0.06), 'X', 0.0042, 0.0008, 12)
            mesh_obj("Pasador_Interior_" + nm, bm, M["cromo"], col, root)

            # ===== brazo superior moldeado (marco en A que deja pasar la varilla) =====
            O_ = Vector((xa, s * Y_U0, U0.z))
            ydir = Vector((0.0, U1.y - O_.y, U1.z - O_.z))
            Lu = ydir.length
            ydir.normalize()
            xdir = Vector((1.0, 0.0, 0.0))
            zdir = xdir.cross(ydir)
            if zdir.z < 0:
                zdir = -zdir
            Mu = Matrix((xdir, ydir, zdir)).transposed().to_4x4()
            Mu.translation = O_
            # marco en A en celosía: dos patas, travesaño y diagonal en la mitad exterior
            # (la mitad interior queda abierta para que pase la varilla de empuje)
            def pata(t, sg):
                return Mu @ Vector(((U1.x - xa) * t + sg * (0.0290 + (0.0040 - 0.0290) * t),
                                    0.0020 + (Lu - 0.0060) * t, 0.0))
            bm = bmesh.new()
            for sg in (-1, 1):
                add_beam(bm, pata(0.0, sg), pata(1.0, sg), 0.0046, 0.0055, zdir)
            add_beam(bm, pata(0.58, -1), pata(0.58, 1), 0.0036, 0.0045, zdir)       # travesaño
            add_beam(bm, pata(0.58, 1), pata(0.84, -1), 0.0032, 0.0042, zdir)       # diagonal
            for t, sg in ((0.58, -1), (0.58, 1), (0.84, -1)):
                add_cyl(bm, 0.0042, 0.0060, Matrix.Translation(pata(t, sg)) @ Mu.to_3x3().to_4x4(), 14)
            ua = mesh_obj("Brazo_Superior_" + nm, bm, M["plastico"], col, root, smooth=None)
            cb2 = bmesh.new()
            kp0 = (U1 - L1).normalized()
            add_cyl_pts(cb2, U1 - kp0 * 0.006, U1 + kp0 * 0.006, 0.0036, 20)      # paso de la bola
            boolean_cut(ua, [cutter_obj("cut_bola_sup", cb2, col)])
            attach(ua, pv_ls)
            bm = bmesh.new()
            add_cyl_axis(bm, (xa, s * Y_U0, U0.z), 'X', 0.0048, 0.067, 20)
            add_lathe(bm, ring_profile(0.0035, 0.0062, 0.0045), 24, frame_axis(U1, kp0, (1, 0, 0)))  # copa de la bola
            attach(mesh_obj("Brazo_Superior_Bujes_" + nm, bm, M["plastico"], col, root, smooth=None), pv_ls)
            bm = bmesh.new()
            add_cyl_axis(bm, (xa, s * Y_U0, U0.z), 'X', 0.0022, 0.083, 10)
            for dx in (-0.0410, 0.0410):
                add_cyl_axis(bm, (xa + dx, s * Y_U0, U0.z), 'X', 0.0036, 0.0008, 12)
            mesh_obj("Brazo_Superior_Pasador_" + nm, bm, M["cromo"], col, root)
            bm = bmesh.new()
            for dx in (-0.0375, 0.0375):
                add_box_minmax(bm, (xa + dx - 0.0030, s * 0.040 - 0.006, U0.z - 0.009),
                               (xa + dx + 0.0030, s * 0.040 + 0.006, U0.z + 0.006))
            mesh_obj("Mamparo_Orejas_" + nm, bm, M["plastico"], col, root, smooth=None)

            # ===== portamangueta / mangueta =====
            # Delanteras: portamangueta en "C" (sigue a los brazos) + mangueta que gira sobre el
            # eje de pivote L1->U1 (kingpins cortos arriba y abajo, el palier pasa por el centro).
            # Traseras: una sola pieza que sigue a los brazos.
            kp = (U1 - L1).normalized()
            Lk = (U1 - L1).length
            Fk = frame_axis((0, 0, 0), kp, (1, 0, 0))
            X_ = Vector((1, 0, 0))
            X_ = (X_ - kp * X_.dot(kp)).normalized()                             # "adelante" perpendicular al pivote
            Mh = frame_axis((xa, s * Y_RD, WZ), (0, s, 0), (0, 0, 1))           # eje local Z = eje de rueda
            carcasa = [(0.0125, -0.0135), (0.0125, 0.0135), (0.0098, 0.0135), (0.0098, 0.0120),
                       (0.0115, 0.0120), (0.0115, 0.0080), (0.0098, 0.0080), (0.0098, 0.0020),
                       (0.0115, 0.0020), (0.0115, -0.0020), (0.0098, -0.0020), (0.0098, -0.0135)]
            t_l, t_u = 0.0095, Lk - 0.0125
            if f > 0:
                bm = bmesh.new()                                                 # portamangueta en C
                add_cyl_axis(bm, L1, 'X', 0.0060, 0.018, 20)                     # buje inferior (pasador X)
                add_box(bm, (0.0166, 0.014, 0.007), L1 + kp * t_l, Fk)           # oreja inferior (entre patas)
                add_box(bm, (0.036, 0.014, 0.007), L1 + kp * t_u + X_ * 0.0085, Fk)   # oreja superior
                yb0, yb1 = sorted((L1.y + kp.y * 0.012 - 0.007, L1.y + kp.y * 0.012 + 0.007))
                add_box_minmax(bm, (L1.x + 0.0080, yb0, 0.0705), (L1.x + 0.0265, yb1, 0.0735))   # puente a la espina
                add_box(bm, (0.005, 0.014, t_u - t_l), L1 + kp * ((t_l + t_u) / 2 + 0.002) + X_ * 0.024, Fk)
                add_cyl_pts(bm, L1 + kp * (t_u + 0.0030), U1 - kp * 0.0058, 0.0045, 18)   # base de la bola
                attach(mesh_obj("Portamangueta_" + nm, bm, M["plastico"], col, root, smooth=None), mang)
                bm = bmesh.new()                                                 # mangueta (gira)
                add_lathe(bm, carcasa, 40, Mh)                                   # carcasa hueca de rodamientos
                for ta, tb in ((0.0135, 0.0165), (Lk - 0.0205, Lk - 0.0170)):     # resaltes de los kingpins
                    add_cyl_pts(bm, L1 + kp * ta, L1 + kp * tb, 0.0042, 16)
                Tb = g["T"] - Vector((0, 0, 0.0050))                              # brazo 5 mm bajo la rótula
                add_beam(bm, (xa - 0.0115, s * (Y_L1 - 0.0005), Tb.z), Tb, 0.008, 0.0065)  # brazo de dirección
                add_cyl(bm, 0.0045, 0.0075, M_T(Tb), 18)
                attach(mesh_obj("Mangueta_" + nm + "_Malla", bm, M["plastico"], col, root, smooth=None), knuckle)
                hw_mg.pasador(L1 + kp * 0.0060, L1 + kp * 0.0165, 0.0020, "acero")       # kingpin inferior
                hw_kn.bola(g["T"] + Vector((0, 0, TIE_DZ)), 0.0030)                 # rótula de la bieleta
                hw_kn.pasador(g["T"] - Vector((0, 0, 0.0050)), g["T"] + Vector((0, 0, TIE_DZ - 0.0026)), 0.0016, "acero")
                hw_kn.tornillo(g["T"] + Vector((0, 0, TIE_DZ + 0.0032)), (0, 0, 1), 0.018, 0.003, "boton")
            else:
                bm = bmesh.new()
                add_lathe(bm, carcasa, 40, Mh)
                add_cyl_axis(bm, L1, 'X', 0.0060, 0.018, 20)                     # buje inferior
                add_box_minmax(bm, (xa - 0.0088, min(s * (Y_L1 - 0.005), s * (Y_L1 + 0.005)), 0.060),
                               (xa + 0.0088, max(s * (Y_L1 - 0.005), s * (Y_L1 + 0.005)), 0.0755))  # pata inferior
                add_box_minmax(bm, (xa - 0.0070, min(s * (Y_U1 - 0.003), s * Y_L1), 0.0980),
                               (xa + 0.0070, max(s * (Y_U1 - 0.003), s * Y_L1), U1.z - 0.0060))  # pata superior
                attach(mesh_obj("Mangueta_" + nm + "_Malla", bm, M["plastico"], col, root, smooth=None), knuckle)
            # bola superior (la copa está en el brazo superior) y su espárrago
            hw_mg.bola(U1, 0.0034)
            hw_mg.pasador(U1 - kp * (0.0195 if f > 0 else 0.010), U1 - kp * 0.0045, 0.0020, "acero")  # kingpin sup.
            hw_mg.pasador(U1 - kp * 0.0046, U1 - kp * 0.0028, 0.0015, "acero")                       # cuello de la bola
            for sg in (-1, 1):                                                   # casquillos del pasador inferior
                hw_mg.casquillo(L1 + Vector((sg * 0.0094, 0, 0)), (sg, 0, 0), 0.0029, 0.0048, 0.0007)
            # rodamientos de la rueda (el eje y su copa giran con la rueda)
            hw_kn.rodamiento((xa, s * Y_RD, WZ), (0, s, 0), 0.0060, 0.0115, 0.0040)          # rodamiento interior
            hw_kn.rodamiento((xa, s * (Y_RD + 0.010), WZ), (0, s, 0), 0.0060, 0.0115, 0.0040)  # rodamiento exterior

            # ===== palier tipo hueso (dogbone): cabezas esféricas con pasador en copas ranuradas =====
            D0, D1 = g["D0"], g["D1"]
            Lpal = (D1 - D0).length
            bm = bmesh.new()
            add_lathe(bm, [(0.0001, 0.0040), (0.0028, 0.0040), (0.0028, 0.0085), (0.0040, 0.0120),
                           (0.0040, Lpal - 0.0120), (0.0028, Lpal - 0.0085), (0.0028, Lpal - 0.0040),
                           (0.0001, Lpal - 0.0040)], 20, AXIS_ROT['Y'])
            for yy in (0.0, Lpal):                                               # cabezas esféricas + pasador
                bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.0050, matrix=M_T((0, yy, 0)))
                add_cyl_axis(bm, (0, yy, 0), 'Z', 0.0013, 0.0140, 10)
            pal = mesh_obj("Palier_" + nm, bm, M["acero"], col, root)
            pal.matrix_basis = frame_axis(D0, D1 - D0, (0, 0, 1), 'Y')
            c_damped(pal, e_d1, 'TRACK_Y')

            # ===== balancín en "L" (plano perpendicular a su eje n) =====
            u_, v_ = g["u"], g["v"]
            Mrk = Matrix((u_, v_, n)).transposed().to_4x4()
            Mrk.translation = P
            to2 = lambda q: ((q - P).dot(u_), (q - P).dot(v_))
            sv, rv, qv = to2(g["Sp"]), to2(g["Rp"]), to2(g["Qp"])
            circ = []
            for (cu, cv, rr) in ((0, 0, 0.0085), (sv[0], sv[1], 0.0068), (rv[0], rv[1], 0.0068),
                                 (qv[0], qv[1], 0.0055)):
                for kk in range(24):
                    a_ = 2 * pi * kk / 24
                    circ.append((round(cu + rr * cos(a_), 6), round(cv + rr * sin(a_), 6)))
            bm = bmesh.new()
            add_prism(bm, convex_hull_2d(circ), -0.0025, 0.0025, Mrk)
            rkm = mesh_obj("Balancin_" + nm + "_Malla", bm, M["anodizado"], col, root, smooth=None)
            gx, gy = (sv[0] + rv[0]) / 3, (sv[1] + rv[1]) / 3
            tri = [(gx + 0.0040 * cos(a_), gy + 0.0040 * sin(a_)) for a_ in (0.3, 2.4, 4.5)]
            cutters = []
            cb = bmesh.new()
            add_prism(cb, ccw(tri), -0.006, 0.006, Mrk)
            cutters.append(cutter_obj("cut_balancin", cb, col))
            cb = bmesh.new()                                                     # alojamiento de rodamientos
            add_cyl_pts(cb, P - n * 0.006, P + n * 0.006, 0.0050, 24)
            cutters.append(cutter_obj("cut_balancin_rod", cb, col))
            boolean_cut(rkm, cutters)
            attach(rkm, rk)
            # dos rodamientos con pestaña en el pivote
            hw_rk.rodamiento(P + n * 0.00125, n, 0.0025, 0.0050, 0.0025, flange=0.0008)
            hw_rk.rodamiento(P - n * 0.00125, -n, 0.0025, 0.0050, 0.0025, flange=0.0008)
            # amortiguador: bola sobre la placa (+n), tornillo desde arriba y tuerca por debajo
            hw_rk.bola(S, 0.0034)
            hw_rk.tornillo(S + n * 0.0040, n, 0.017, 0.003, "boton")
            hw_rk.pasador(g["Sp"], S - n * 0.0030, 0.0016, "acero")
            hw_rk.tuerca(g["Sp"] - n * 0.0025, -n)
            # varilla: bola bajo la placa (-n), tornillo desde abajo y tuerca arriba
            hw_rk.bola(R, 0.0034)
            hw_rk.tornillo(R - n * 0.0040, -n, 0.015, 0.003, "boton")
            hw_rk.pasador(g["Rp"], R + n * 0.0030, 0.0016, "acero")
            hw_rk.tuerca(g["Rp"] + n * 0.0025, n)
            # bieleta de la barra estabilizadora: oreja que baja de la placa y espárrago horizontal
            # (perpendicular a la bieleta: la rótula trabaja centrada)
            Q_, Qp_ = g["Q"], g["Qp"]
            y_in, y_out = s * (ESTAB_Y + 0.0045), s * (ESTAB_Y + 0.0075)        # deja inclinar la rótula ±23°
            P_bot = P - n * 0.0025                                               # cara inferior de la placa
            def z_bot(xx, yy):
                b_ = (yy - P_bot.y) / g["v"].y
                return P_bot.z + b_ * g["v"].z
            cs = []
            for (xx, yy) in ((Q_.x - 0.0045, y_in), (Q_.x + 0.0045, y_in), (Q_.x + 0.0045, y_out), (Q_.x - 0.0045, y_out)):
                cs.append((xx, yy))
            bm = bmesh.new()
            add_hexa(bm, [Vector((xx, yy, Q_.z - 0.0028)) for xx, yy in cs] +
                     [Vector((xx, yy, z_bot(xx, yy))) for xx, yy in cs])
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            attach(mesh_obj(f"Balancin_{nm}_Oreja", bm, M["anodizado"], col, root, smooth=None), rk)
            hw_rk.bola(Q_, 0.0028)
            hw_rk.pasador(Vector((Q_.x, y_out, Q_.z)), Q_, 0.0013, "acero")
            hw_rk.tuerca(Vector((Q_.x, y_out, Q_.z)), (0, s, 0), 0.0025)
            e_q = pivot(f"Estabilizadora_Ojo_Balancin_{nm}", col, rk, M_T(Q_), 0.004, 'SPHERE')
            # torre del balancín: bloque sobre el diferencial + poste + perno M5 del pivote
            base = P - n * 0.0095
            y_in, y_out = sorted((s * 0.030, base.y + s * 0.007))
            bm = bmesh.new()
            add_cyl_pts(bm, (base.x, base.y, 0.1155), base, 0.0050, 20)
            Mq, Lq = look_z(P - n * 0.012, P - n * 0.0040)
            add_cyl(bm, 0.0058, Lq, Mq @ M_T((0, 0, Lq / 2)), 20)
            add_box_minmax(bm, (base.x - 0.008, y_in, 0.1135), (base.x + 0.008, y_out, 0.1180))
            mesh_obj("Balancin_Poste_" + nm, bm, M["chasis"], col, root)
            hw.arandela(P + n * 0.0026, n, 0.005, 0.0052)
            hw.tornillo(P + n * 0.0031, n, 0.020, 0.005, "boton")                 # perno M5 del pivote
            for dx in (-0.0055, 0.0055):
                hw.tornillo((base.x + dx, (y_in + y_out) / 2 + s * 0.004, 0.1180), (0, 0, 1), 0.0045, 0.0025, "boton")

            # ===== varilla de empuje rígida con rótulas en ambos extremos =====
            Lp = (R - A).length
            Mv = frame_axis(A, R - A, (1, 0, 0), 'Y')
            Mv_inv = Mv.inverted()
            bm = bmesh.new()
            add_cyl_axis(bm, (0, Lp / 2, 0), 'Y', 0.0024, Lp - 0.026, 14)
            mesh_obj_v = mesh_obj("Varilla_Empuje_" + nm, bm, M["cromo"], col, root)
            bm = bmesh.new()
            add_cyl_axis(bm, (0, Lp * 0.74, 0), 'Y', 0.0037, 0.012, 6)            # hexágono de ajuste (sobre el brazo sup.)
            mesh_obj_h = mesh_obj("Varilla_Empuje_Ajuste_" + nm, bm, M["anodizado"], col, root)
            bm = bmesh.new()
            ax_loc = lambda v: (Mv_inv.to_3x3() @ Vector(v))
            rod_end(bm, (0, 0, 0), (0, 1, 0), ax_loc((1, 0, 0)), body_r=0.0028)   # rótula inferior (perno en X)
            rod_end(bm, (0, Lp, 0), (0, -1, 0), ax_loc(n), body_r=0.0028)         # rótula superior (perno en n)
            mesh_obj_r = mesh_obj("Varilla_Empuje_Rotulas_" + nm, bm, M["plastico"], col, root)
            for o in (mesh_obj_v, mesh_obj_h, mesh_obj_r):
                o.matrix_basis = Mv
                attach(o, pv_li)
                o.matrix_basis = Mv
                c_damped(o, e_r, 'TRACK_Y')

            # ===== amortiguador =====
            build_shock_rig(nm, g, rk, M, col, root)

            for h_ in (hw_li, hw_mg, hw_rk) + ((hw_kn,) if f > 0 else ()):
                h_.build()
            rig[nm] = dict(f=f, s=s, g=g, li=pv_li, ls=pv_ls, rk=rk, mang=mang, pin=pin, knuckle=knuckle, palier=pal, e_q=e_q,
                           palier_ext=e_d1, Lpal=Lpal)
        hw.build()

    # ===== dirección: cremallera, bieletas rígidas y brazo del servo =====
    rack = pivot("Direccion_Cremallera", col, root, M_T((RACK_X, 0.0, 0.1005)), 0.01, 'CUBE')
    bm = bmesh.new()
    for y in (-0.020, 0.020):
        add_cyl_pts(bm, (RACK_X, y, 0.049), (RACK_X, y, 0.0955), 0.0042, 16)
    add_box_minmax(bm, (RACK_X - 0.008, -0.024, 0.0955), (RACK_X + 0.008, 0.024, 0.0975))   # guía
    mesh_obj("Direccion_Postes", bm, M["chasis"], col, root, smooth=None)
    hw_dir = Herrajes("Direccion_Guia", col, root, M)
    for y in (-0.020, 0.020):                                                    # tornillos de la guía (fijos)
        hw_dir.tornillo((RACK_X, y, 0.0975), (0, 0, 1), 0.008, 0.0025, "avellanada")
    hw_dir.build()
    bm = bmesh.new()
    add_box(bm, (0.011, 0.072, 0.004), (RACK_X, 0, 0.1005))
    for sg in (-1, 1):                                                           # brazos de la cremallera
        add_beam(bm, (RACK_X, sg * 0.034, 0.1005), (RACK_X, sg * TIE_IN[0], 0.1005), 0.007, 0.004)
        add_cyl(bm, 0.0040, 0.004, M_T((RACK_X, sg * TIE_IN[0], 0.1005)), 20)
    attach(mesh_obj("Direccion_Bellcrank", bm, M["anodizado"], col, root, smooth=None), rack)
    hw_rack = Herrajes("Cremallera", col, rack, M)
    for s, lado in ((1, "Izq"), (-1, "Der")):
        g = rig[f"Del_{lado}"]["g"]
        I = Vector((RACK_X, s * TIE_IN[0], TIE_IN[1]))
        T = g["T"] + Vector((0, 0, TIE_DZ))
        e_t = pivot(f"Bieleta_Ojo_Ext_{lado}", col, rig[f"Del_{lado}"]["knuckle"], M_T(T), 0.005, 'SPHERE')
        hw_rack.bola(I, 0.0030)
        hw_rack.tornillo(Vector((RACK_X, s * TIE_IN[0], 0.1025)), (0, 0, 1), 0.014, 0.003, "boton")
        hw_rack.pasador(I + Vector((0, 0, 0.0027)), Vector((RACK_X, s * TIE_IN[0], 0.0985)), 0.0016, "acero")
        Lt = (T - I).length
        Mt = frame_axis(I, T - I, (0, 0, 1), 'Y')
        ax_l = Mt.inverted().to_3x3() @ Vector((0, 0, 1))
        bm = bmesh.new()
        add_cyl_axis(bm, (0, Lt / 2, 0), 'Y', 0.0022, Lt - 0.024, 12)
        trod = mesh_obj("Bieleta_Direccion_" + lado, bm, M["cromo"], col, root)
        bm = bmesh.new()
        rod_end(bm, (0, 0, 0), (0, 1, 0), ax_l, 0.0031, 0.0052, 0.0040, 0.010, 0.0027)
        rod_end(bm, (0, Lt, 0), (0, -1, 0), ax_l, 0.0031, 0.0052, 0.0040, 0.010, 0.0027)
        add_cyl_axis(bm, (0, Lt / 2, 0), 'Y', 0.0034, 0.008, 6)
        trr = mesh_obj("Bieleta_Rotulas_" + lado, bm, M["plastico"], col, root)
        for o in (trod, trr):
            o.matrix_basis = Mt
            attach(o, rack)
            o.matrix_basis = Mt
            c_damped(o, e_t, 'TRACK_Y')
        rig[f"Del_{lado}"]["tie_inner"] = I
        rig[f"Del_{lado}"]["tie_outer"] = T
    # brazo del servo de dirección (gira) y varilla rígida al bellcrank
    horn = pivot("Servo_Direccion_Brazo_Pivote", col, root, M_T(HORN_C), 0.01, 'SINGLE_ARROW')
    H = HORN_C + Vector((HORN_L, 0.0, 0.0))
    bm = bmesh.new()
    add_cyl(bm, 0.0060, 0.0040, M_T(HORN_C + Vector((0, 0, -0.001))), 24)        # servo saver
    add_cyl_pts(bm, HORN_C + Vector((0, 0, -0.0072)), HORN_C + Vector((0, 0, -0.0025)), 0.0024, 16)  # eje estriado
    add_beam(bm, HORN_C, H, 0.0055, 0.0030)
    add_cyl(bm, 0.0032, 0.0030, M_T(H), 16)
    attach(mesh_obj("Servo_Brazo_Direccion", bm, M["anodizado"], col, root, smooth=None), horn)
    hw_h = Herrajes("Servo_Direccion", col, horn, M)
    hw_h.tornillo(HORN_C + Vector((0, 0, 0.0010)), (0, 0, 1), 0.006, 0.0025, "cilindrica")
    Hb = H + Vector((0, 0, 0.0090))                                              # bolas altas: la rótula
    hw_h.bola(Hb, 0.0026)                                                        # pasa sobre brazo y cremallera
    hw_h.pasador(H + Vector((0, 0, 0.0015)), Hb, 0.0016, "acero")
    Kb = LINK_K + Vector((0, 0, 0.0070))                                         # 1.4 mm sobre la cremallera
    hw_rack.bola(Kb, 0.0026)
    hw_rack.pasador(LINK_K + Vector((0, 0, 0.0030)), Kb, 0.0016, "acero")
    e_k = pivot("Direccion_Ojo_Servo", col, rack, M_T(Kb), 0.004, 'SPHERE')
    Ld = (Kb - Hb).length
    Md = frame_axis(Hb, Kb - Hb, (0, 0, 1), 'Y')
    ax_d = Md.inverted().to_3x3() @ Vector((0, 0, 1))
    bm = bmesh.new()
    add_cyl_axis(bm, (0, Ld / 2, 0), 'Y', 0.0016, Ld - 0.016, 10)
    rod_end(bm, (0, 0, 0), (0, 1, 0), ax_d, 0.0027, 0.0045, 0.0042, 0.006, 0.0026)
    rod_end(bm, (0, Ld, 0), (0, -1, 0), ax_d, 0.0027, 0.0045, 0.0042, 0.006, 0.0026)
    dl = mesh_obj("Varilla_Direccion", bm, M["cromo"], col, root)
    dl.matrix_basis = Md
    attach(dl, horn)
    dl.matrix_basis = Md
    c_damped(dl, e_k, 'TRACK_Y')
    hw_rack.build()
    hw_h.build()
    rig["_horn"] = horn
    rig["_rack"] = rack
    return rig


def palier_plunge_fit(nm, r, wheel, st):
    """Deslizamiento del palier dentro de la copa de la rueda: la cabeza exterior se mueve SOBRE el
    eje de la rueda (no sobre el eje del palier) para que el hueso conserve su largo."""
    import numpy as np
    ctrl, e = r["ctrl"], r["palier_ext"]
    D0, L = r["g"]["D0"], r["Lpal"]
    ds = np.linspace(-0.42, 0.42, 7) if r["f"] > 0 else np.array([0.0])
    rows = []
    for h in np.linspace(TRAVEL[0], TRAVEL[1], 7):
        for d in ds:
            ctrl.location.z = float(h)
            st.rotation_euler.z = float(d)
            bpy.context.view_layer.update()
            Dw = e.matrix_world.translation.copy()
            w = wheel.matrix_world.to_3x3().col[1].normalized()        # eje de la rueda (hacia afuera)
            if w.dot(Vector((0, r["s"], 0))) < 0:
                w = -w
            q = Dw - D0
            b = w.dot(q)
            disc = b * b - (q.dot(q) - L * L)
            v = -b + (disc ** 0.5) if disc > 0 else -b
            if abs(-b - (disc ** 0.5)) < abs(v):
                v = -b - (disc ** 0.5)
            rows.append((h, d, v))
    ctrl.location.z = 0.0
    st.rotation_euler.z = 0.0
    bpy.context.view_layer.update()
    a = np.array(rows)
    terms = [(i, j) for i in range(3) for j in range(3) if 0 < i + j <= 2] if r["f"] > 0 else [(1, 0), (2, 0)]
    X = np.vstack([a[:, 0] ** i * a[:, 1] ** j for i, j in terms]).T
    c = np.linalg.lstsq(X, a[:, 2], rcond=None)[0]
    expr = "".join(f"{ck:+.5g}*" + "*".join(["h"] * i + ["d"] * j) for (i, j), ck in zip(terms, c)).lstrip("+")
    return expr, float(a[:, 2].min()), float(a[:, 2].max())


def palier_roll_fit(nm, r, wheel, st):
    """Giro propio del palier (sobre su eje) que deja el pasador centrado entre las ranuras
    de la copa del diferencial y la de la rueda. Devuelve (expresión, desalineación máx. en grados)."""
    import numpy as np
    O = bpy.data.objects
    ctrl, pal = r["ctrl"], r["palier"]
    so = O[f"Diferencial_Salida_{'Del' if r['f'] > 0 else 'Tras'}_{'Izq' if r['s'] > 0 else 'Der'}"]
    ds = np.linspace(-0.42, 0.42, 7) if r["f"] > 0 else np.array([0.0])
    rows = []
    for h in np.linspace(TRAVEL[0], TRAVEL[1], 7):
        for d in ds:
            ctrl.location.z = float(h)
            st.rotation_euler.z = float(d)
            bpy.context.view_layer.update()
            Mp = pal.matrix_world.to_3x3()
            xp, zp = Mp.col[0], Mp.col[2]
            def psi(nx):
                return atan2(-zp.dot(nx), xp.dot(nx))
            p_out = psi(wheel.matrix_world.to_3x3().col[0].normalized())
            p_in = psi(so.matrix_world.to_3x3().col[0].normalized())
            # ambas soluciones (+-180°) son válidas: elegir la más cercana entre sí
            if abs(p_out - p_in) > pi / 2:
                p_out -= pi * np.sign(p_out - p_in)
            rows.append((h, d, 0.5 * (p_out + p_in), 0.5 * abs(p_out - p_in)))
    ctrl.location.z = 0.0
    st.rotation_euler.z = 0.0
    bpy.context.view_layer.update()
    a = np.array(rows)
    desal = float(np.degrees(a[:, 3].max()))
    if np.abs(a[:, 2]).max() < radians(0.2):
        return "", desal
    terms = [(i, j) for i in range(3) for j in range(3) if 0 < i + j <= 2] if r["f"] > 0 else [(1, 0), (2, 0)]
    X = np.vstack([a[:, 0] ** i * a[:, 1] ** j for i, j in terms]).T
    c = np.linalg.lstsq(X, a[:, 2], rcond=None)[0]
    expr = "".join(f"{ck:+.5g}*" + "*".join(["h"] * i + ["d"] * j) for (i, j), ck in zip(terms, c)).lstrip("+")
    return expr, desal


def build_estabilizadoras(root, C, M, rig):
    """Barra estabilizadora por eje: alambre de acero doblado en U (tramo transversal en dos
    bujes delante del mamparo exterior + dos brazos hacia los balancines) y bieletas con rótulas.
    Cada mitad gira con su brazo; la torsión queda escondida en el casquillo central."""
    col = C["susp"]
    for f, ej in ((1, "Del"), (-1, "Tras")):
        r_w = ESTAB_D[f] / 2
        hw = Herrajes(f"Estabilizadora_{ej}", col, root, M)
        xt = f * ESTAB_XT
        bm = bmesh.new()                                                     # soportes con buje en el mamparo
        x_cara = f * (XA + 0.0411)
        for sg in (1, -1):
            yb = sg * 0.022
            x0, x1 = sorted((x_cara, xt + f * 0.0035))
            add_box_minmax(bm, (x0, yb - 0.006, 0.108), (x1, yb + 0.006, ESTAB_ZT - 0.0015))
            add_lathe(bm, [(r_w + 0.0002, -0.004), (0.0048, -0.004), (0.0048, 0.004), (r_w + 0.0002, 0.004)], 24,
                      M_T((xt, yb, ESTAB_ZT)) @ AXIS_ROT['Y'])
            for zz in (0.112, 0.124):
                hw.tornillo((x1, yb, zz) if f > 0 else (x0, yb, zz), (f, 0, 0), 0.010, 0.0025, "boton")
        mesh_obj(f"Estabilizadora_Soportes_{ej}", bm, M["amarillo"], col, root, smooth=None)
        bm = bmesh.new()                                                     # casquillo central (oculta la torsión)
        add_cyl_axis(bm, (xt, 0, ESTAB_ZT), 'Y', r_w + 0.0012, 0.008, 18)
        mesh_obj(f"Estabilizadora_Centro_{ej}", bm, M["anodizado"], col, root)
        for s, lado in ((1, "Izq"), (-1, "Der")):
            nm = f"{ej}_{lado}"
            g = rig[nm]["g"]
            E, Q, Ax = g["E"], g["Q"], g["Ax"]
            yb = E.y + s * 0.006                                             # el alambre va 6 mm afuera de la bola
            arm = pivot(f"Estabilizadora_Brazo_{nm}", col, root, M_T(Vector((xt, 0, ESTAB_ZT))), 0.01, 'SINGLE_ARROW')
            rb = 0.006
            c1 = Vector((xt - f * rb, yb - s * rb, ESTAB_ZT))
            pts = [Vector((xt, s * 0.0005, ESTAB_ZT)), Vector((xt, yb - s * rb, ESTAB_ZT))]
            pts += arco(c1, Vector((xt, yb - s * rb, ESTAB_ZT)), Vector((xt - f * rb, yb, ESTAB_ZT)), 6)[1:]
            pts += [Vector((E.x + f * 0.0045, yb, ESTAB_ZT))]
            bm = bmesh.new()
            add_sweep(bm, pts, r_w, 14)
            add_cyl_axis(bm, (E.x, yb, ESTAB_ZT), 'Y', 0.0040, 0.0030, 18)     # ojo aplanado del brazo
            add_box_minmax(bm, (min(E.x, E.x + f * 0.006), yb - 0.0015, ESTAB_ZT - 0.0025),
                           (max(E.x, E.x + f * 0.006), yb + 0.0015, ESTAB_ZT + 0.0025))
            attach(mesh_obj(f"Estabilizadora_{nm}", bm, M["acero"], col, root, smooth=30), arm)
            hwa = Herrajes(f"Estabilizadora_Brazo_{nm}", col, arm, M)
            hwa.bola(E, 0.0026)
            hwa.pasador(Vector((E.x, yb, E.z)), E, 0.0012, "acero")
            hwa.tuerca(Vector((E.x, yb + s * 0.0015, E.z)), (0, s, 0), 0.0025)
            hwa.build()
            # bieleta rígida E -> Q (rótulas en los dos extremos)
            Ll = (Q - E).length
            Mv = frame_axis(E, Q - E, (1, 0, 0), 'Y')
            inv = Mv.inverted().to_3x3()
            bm = bmesh.new()
            add_cyl_axis(bm, (0, Ll / 2, 0), 'Y', 0.0014, Ll - 0.010, 10)
            rod_end(bm, (0, 0, 0), (0, 1, 0), inv @ Vector((0, 1, 0)), 0.0026, 0.0042, 0.0034, 0.004, 0.0022)
            rod_end(bm, (0, Ll, 0), (0, -1, 0), inv @ Vector((0, 1, 0)), 0.0028, 0.0044, 0.0034, 0.004, 0.0022)
            lk = mesh_obj(f"Estabilizadora_Bieleta_{nm}", bm, M["plastico"], col, root)
            lk.matrix_basis = Mv
            attach(lk, arm)
            lk.matrix_basis = Mv
            c_damped(lk, rig[nm]["e_q"], 'TRACK_Y')
            rig[nm]["estab"] = dict(arm=arm, Ll=Ll, La=abs(E.x - xt))
        hw.build()


def estabilizadora_fit(r):
    """Ángulo del brazo de la barra (giro en Y) para que la bieleta conserve su largo."""
    import numpy as np
    g = r["g"]
    d = solve_corner(g)
    V = lambda v: np.array([v[0], v[1], v[2]], dtype=float)
    P, n, Q0, E0 = V(g["P"]), V(g["n"]), V(g["Q"]), V(g["E"])
    A0 = np.array([g["f"] * ESTAB_XT, 0.0, ESTAB_ZT])
    Ll = np.linalg.norm(Q0 - E0)

    def rot_n(v, a):
        return v * cos(a) + np.cross(n, v) * sin(a) + n * np.dot(n, v) * (1 - cos(a))

    def Ey(q):
        c, s_ = cos(q), sin(q)
        R = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])
        return A0 + R @ (E0 - A0)
    rows = []
    sel = (d[:, 0] >= TRAVEL[0] - 0.003) & (d[:, 0] <= TRAVEL[1] + 0.003)
    hs_all, pp_all = d[sel, 0], d[sel, 3]
    i0 = int(np.argmin(np.abs(hs_all)))
    tramos = [list(range(i0, len(hs_all))), list(range(i0, -1, -1))]     # desde el reposo hacia cada lado
    for tramo in tramos:
      q = 0.0
      for i in tramo:
        h, pp = hs_all[i], pp_all[i]
        Qh = P + rot_n(Q0 - P, pp)
        for _ in range(60):
            fv = np.linalg.norm(Qh - Ey(q)) - Ll
            dv = (np.linalg.norm(Qh - Ey(q + 1e-8)) - Ll - fv) / 1e-8
            q -= fv / dv
            if abs(fv) < 1e-13:
                break
        rows.append((h, q))
    a = np.array(sorted(set(rows)))
    expr, err = fit_expr(a[:, 0], a[:, 1], var='h', deg=7)
    dpsi = float(np.polyfit(a[np.abs(a[:, 0]) < 0.006, 0], a[np.abs(a[:, 0]) < 0.006, 1], 1)[0])
    return expr, err, dict(psi_min=float(a[:, 1].min()), psi_max=float(a[:, 1].max()), dpsi_dh=dpsi)


def setup_rig(root, C, rig, wheels):
    """Controles, drivers (expresiones simples) y animación de demostración."""
    col = C["ctrl"]
    report = {}
    for nm, r in rig.items():
        if nm.startswith("_"):
            continue
        f, s, g = r["f"], r["s"], r["g"]
        attach(wheels[nm], r["knuckle"])                     # la rueda cuelga de la mangueta
        anchor = bpy.data.objects.new(f"Ancla_Control_{nm}", None)
        anchor.empty_display_size = 0.004
        col.objects.link(anchor)
        anchor.parent = root
        anchor.location = (f * XA, s * 0.33, WZ)
        ctrl = bpy.data.objects.new(f"Control_Suspension_{nm}", None)
        ctrl.empty_display_type = 'SINGLE_ARROW'
        ctrl.empty_display_size = 0.05
        col.objects.link(ctrl)
        ctrl.parent = anchor
        ctrl.lock_location = (True, True, False)
        ctrl.lock_rotation = (True, True, True)
        ctrl.lock_scale = (True, True, True)
        lim = ctrl.constraints.new('LIMIT_LOCATION')
        lim.use_min_z = lim.use_max_z = True
        lim.min_z, lim.max_z = TRAVEL
        lim.owner_space = 'LOCAL'
        lim.use_transform_limit = True
        ctrl["recorrido_mm"] = "mueve en Z: + comprime, - extiende"
        k = corner_kinematics(g)
        report[nm] = k
        drive(r["li"], "rotation_euler", 0, k["brazo_inf"], "h", ctrl, "location[2]")
        drive(r["ls"], "rotation_euler", 0, k["brazo_sup"], "h", ctrl, "location[2]")
        drive(r["rk"], "rotation_euler", 2, k["balancin"], "h", ctrl, "location[2]")
        drive(r["pin"], "rotation_euler", 0, k["mangueta"], "h", ctrl, "location[2]")
        tp = g["tope"]
        gap0 = 0.0015 + g["amort_interno"]["compresion"] - 0.0001
        drive(bpy.data.objects[f"Amort_{nm}_Tope_Base"], "scale", 2,
              f"min(1.0,({gap0:.6f}-({k['amort']}))/{tp['largo_libre']:.6f})", "h", ctrl, "location[2]")
        if "estab" in r:
            ex, er, info = estabilizadora_fit(r)
            drive(r["estab"]["arm"], "rotation_euler", 1, ex, "h", ctrl, "location[2]")
            r["estab"].update(info, err=er)
        r["ctrl"] = ctrl
    # dirección
    anchor = bpy.data.objects.new("Ancla_Control_Direccion", None)
    anchor.empty_display_size = 0.004
    col.objects.link(anchor)
    anchor.parent = root
    anchor.location = (0.37, 0.0, 0.11)
    st = bpy.data.objects.new("Control_Direccion", None)
    st.empty_display_type = 'CIRCLE'
    st.empty_display_size = 0.04
    col.objects.link(st)
    st.parent = anchor
    st.lock_location = (True, True, True)
    st.lock_rotation = (True, True, False)
    st.lock_scale = (True, True, True)
    ind = bpy.data.objects.new("Control_Direccion_Indicador", None)
    ind.empty_display_type = 'SINGLE_ARROW'
    ind.empty_display_size = 0.05
    col.objects.link(ind)
    ind.parent = st
    ind.rotation_euler = (0, pi / 2, 0)
    ind.hide_select = True
    lr = st.constraints.new('LIMIT_ROTATION')
    lr.use_limit_z = True
    lr.min_z, lr.max_z = -0.42, 0.42
    lr.owner_space = 'LOCAL'
    lr.use_transform_limit = True
    # mangueta: ángulo exacto para que la bieleta no cambie de largo (incluye bump steer)
    for lado in ("Izq", "Der"):
        r_ = rig[f"Del_{lado}"]
        expr, err, lock = steering_fit(r_["g"], r_["tie_inner"], r_["tie_outer"])
        report["direccion_" + lado] = (err, float(lock[0][0]) * 180 / pi, float(lock[1][0]) * 180 / pi)
        drive_multi(r_["knuckle"], "rotation_euler", 2, expr,
                    [("h", r_["ctrl"], "location[2]"), ("d", st, "rotation_euler[2]")])
    drive(rig["_rack"], "location", 1, f"({RACK_K})*d", "d", st, "rotation_euler[2]")
    hexpr, herr = horn_fit()
    report["brazo_servo_err"] = herr
    drive(rig["_horn"], "rotation_euler", 2, hexpr, "d", st, "rotation_euler[2]")

    # ----- giro de los palieres para que el pasador quede dentro de las dos ranuras -----
    report["palier_desalineacion_max_grados"] = {}
    # (se calcula más abajo, una vez creado el control de avance)

    # ----- avance: ruedas, palieres, salidas del diferencial, cardanes, freno y motor -----
    anchor = bpy.data.objects.new("Ancla_Control_Avance", None)
    anchor.empty_display_size = 0.004
    col.objects.link(anchor)
    anchor.parent = root
    anchor.location = (0.40, 0.0, 0.03)
    av = bpy.data.objects.new("Control_Avance", None)
    av.empty_display_type = 'SINGLE_ARROW'
    av.empty_display_size = 0.05
    col.objects.link(av)
    av.parent = anchor
    av.rotation_euler = (0, pi / 2, 0)
    av.lock_location = (False, True, True)
    av.lock_rotation = (True, True, True)
    av["info"] = "mueve en X local: metros recorridos por el camión"
    kw = 1.0 / WZ                                     # rad de rueda por metro
    for nm_, r_ in rig.items():
        if nm_.startswith("_"):
            continue
        sg = 1 if r_["s"] > 0 else -1
        e_ = f"({sg * kw:.6f})*x"
        drive(wheels[nm_], "rotation_euler", 1, e_, "x", av, "location[0]")
        r_["giro_expr"] = e_
        so = bpy.data.objects[f"Diferencial_Salida_{'Del' if r_['f'] > 0 else 'Tras'}_{'Izq' if sg > 0 else 'Der'}"]
        drive(so, "rotation_euler", 1, e_, "x", av, "location[0]")
    report["palier_deslizamiento_mm"] = {}
    for nm_, r_ in rig.items():
        if nm_.startswith("_"):
            continue
        pexpr, vmin, vmax = palier_plunge_fit(nm_, r_, wheels[nm_], st)
        report["palier_deslizamiento_mm"][nm_] = (round(vmin * 1000, 2), round(vmax * 1000, 2))
        base = r_["palier_ext"].location[1]
        drive_multi(r_["palier_ext"], "location", 1, f"{base:.6f}+({r_['s']})*({pexpr})",
                    [("h", r_["ctrl"], "location[2]"), ("d", st, "rotation_euler[2]")])
    for nm_, r_ in rig.items():
        if nm_.startswith("_"):
            continue
        expr, desal = palier_roll_fit(nm_, r_, wheels[nm_], st)
        report["palier_desalineacion_max_grados"][nm_] = round(desal, 2)
        drive_multi(r_["palier"], "rotation_euler", 1, r_["giro_expr"] + ("+" + expr if expr else ""),
                    [("x", av, "location[0]"), ("h", r_["ctrl"], "location[2]"), ("d", st, "rotation_euler[2]")])
    for nm_c, sg in (("Cardan_Central_Del", 1), ("Cardan_Central_Tras", -1)):
        drive(bpy.data.objects[nm_c], "rotation_euler", 1, f"({sg * kw * RATIO_DIF:.6f})*x", "x", av, "location[0]")
    drive(bpy.data.objects["Cigueñal_Giro"], "rotation_euler", 1, f"({kw * RATIO_DIF * RATIO_TRANS:.6f})*x",
          "x", av, "location[0]")

    # ----- animación de demostración (144 cuadros) -----
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, 144
    sc.render.fps = 24
    keys = [  # (cuadro, DelIzq, DelDer, TrasIzq, TrasDer, dirección)
        (1, 0, 0, 0, 0, 0), (18, .032, .032, .032, .032, 0), (34, -.040, -.040, -.040, -.040, 0),
        (46, 0, 0, 0, 0, 0), (62, .032, -.040, .032, -.040, 0), (78, -.040, .032, -.040, .032, 0),
        (90, 0, 0, 0, 0, 0), (104, .030, .030, -.036, -.036, .35), (118, -.036, -.036, .030, .030, -.35),
        (132, 0, 0, 0, 0, 0), (144, 0, 0, 0, 0, 0)]
    names = ["Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der"]
    import numpy as np
    pos = {nm_: (rig[nm_]["f"] * XA, rig[nm_]["s"] * YW) for nm_ in names}
    for fr, *vals in keys:
        for nm_, v in zip(names, vals[:4]):
            c = rig[nm_]["ctrl"]
            c.location.z = v
            c.keyframe_insert("location", index=2, frame=fr)
        st.rotation_euler.z = vals[4]
        st.keyframe_insert("rotation_euler", index=2, frame=fr)
        # el chasis se mueve para que las 4 ruedas sigan apoyadas en el piso:
        #   z0 + y*rx - x*ry + h = 0  (mínimos cuadrados)
        Aq = np.array([[1.0, pos[nm_][1], -pos[nm_][0]] for nm_ in names])
        bq = -np.array(vals[:4], dtype=float)
        z0, rxx, ryy = np.linalg.lstsq(Aq, bq, rcond=None)[0]
        root.location.z = z0
        root.rotation_euler = (rxx, ryy, 0.0)
        root.keyframe_insert("location", index=2, frame=fr)
        root.keyframe_insert("rotation_euler", frame=fr)
    root.location.z = 0.0
    root.rotation_euler = (0.0, 0.0, 0.0)
    prefs = bpy.context.preferences.edit
    old = prefs.keyframe_new_interpolation_type
    prefs.keyframe_new_interpolation_type = 'LINEAR'
    av.location.x = 0.0
    av.keyframe_insert("location", index=0, frame=1)
    av.location.x = 6 * 2 * pi * WZ                     # 6 vueltas de rueda
    av.keyframe_insert("location", index=0, frame=144)
    av.location.x = 0.0
    report["apoyo_ruedas_mm"] = _apoyar_en_piso(root, wheels, sc)
    prefs.keyframe_new_interpolation_type = old
    sc.frame_set(1)
    return report


def _apoyar_en_piso(root, wheels, sc, iters=3):
    """Corrige el chasis cuadro a cuadro (altura, balanceo y cabeceo) para que las cuatro
    llantas toquen el piso z=0 sin atravesarlo: el arrastre por la inclinación del pivote,
    la caída y los tacos de la llanta cambian el punto de apoyo en cada cuadro."""
    import numpy as np
    O = bpy.data.objects
    tires = [O["Llanta_" + nm] for nm in wheels]
    ctrls = [O["Control_Suspension_" + nm] for nm in wheels]
    me = tires[0].data
    V = np.array([v.co[:] for v in me.vertices])
    r = np.hypot(V[:, 0], V[:, 2])
    V = V[r > r.max() - 0.012]                                   # sólo la banda de rodadura
    V = np.c_[V, np.ones(len(V))]
    rot_fc = None
    peor = 0.0
    for fr in range(sc.frame_start, sc.frame_end + 1):
        sc.frame_set(fr)
        z0, rx, ry = root.location.z, root.rotation_euler.x, root.rotation_euler.y
        for it in range(iters + 2):
            pts = []
            for t in tires:
                W = V @ np.array(t.matrix_world).T
                k = int(np.argmin(W[:, 2]))
                pts.append(W[k, :3])
            pts = np.array(pts)
            if it >= iters:
                # la llanta que quedó en el aire: el resorte la extiende hasta tocar el piso
                for c, z in zip(ctrls, pts[:, 2]):
                    if z > 2e-5:
                        c.location.z = max(TRAVEL[0], c.location.z - z)
                bpy.context.view_layer.update()
                continue
            A = np.c_[np.ones(4), pts[:, 1], -pts[:, 0]]
            dz, drx, dry = np.linalg.lstsq(A, -pts[:, 2], rcond=None)[0]
            res = pts[:, 2] + A @ np.array([dz, drx, dry])
            dz += max(0.0, -res.min())                               # ninguna llanta bajo el piso
            z0, rx, ry = z0 + dz, rx + drx, ry + dry
            root.location.z, root.rotation_euler.x, root.rotation_euler.y = z0, rx, ry
            bpy.context.view_layer.update()
        root.keyframe_insert("location", index=2, frame=fr)
        root.keyframe_insert("rotation_euler", frame=fr)
        for c in ctrls:
            c.keyframe_insert("location", index=2, frame=fr)
        zs = [float((V @ np.array(t.matrix_world).T)[:, 2].min()) for t in tires]
        peor = max(peor, max(zs) - min(zs))
    return round(peor * 1000, 2)


# ---------------------------------------------------------------------------
# Motor nitro, escape y transmisión
# ---------------------------------------------------------------------------
def build_engine(root, C, M):
    col = C["motor"]
    ey, ez = -0.02, 0.075            # eje del cigüeñal (a lo largo de X)
    hx = -0.045                      # posición del cilindro

    # --- soportes del motor (dos bloques) y tornillos ---
    bm = bmesh.new()
    for y0, y1 in ((ey - 0.022, ey - 0.011), (ey + 0.011, ey + 0.021)):
        add_box_minmax(bm, (-0.074, y0, 0.049), (-0.010, y1, 0.0565))
    mesh_obj("Motor_Soportes", bm, M["chasis"], col, root, smooth=None)
    hw_m = Herrajes("Motor", col, root, M)
    for x in (-0.064, -0.020):
        for y in (ey - 0.0165, ey + 0.016):
            hw_m.arandela((x, y, 0.0620), (0, 0, 1), 0.003)
            hw_m.tornillo((x, y, 0.0625), (0, 0, 1), 0.014, 0.003, "cilindrica")

    # --- cárter con patas, nariz y tapa trasera ---
    bm = bmesh.new()
    add_cyl_axis(bm, (-0.040, ey, ez), 'X', 0.0215, 0.066, 40)
    add_cyl_pts(bm, (-0.007, ey, ez), (0.0, ey, ez), 0.016, 32, 0.0125)
    add_cyl_axis(bm, (-0.0745, ey, ez), 'X', 0.0225, 0.004, 40)
    add_box_minmax(bm, (-0.069, ey - 0.0215, 0.0565), (-0.015, ey + 0.0205, 0.0620))
    add_cyl(bm, 0.0165, 0.016, M_T((hx, ey, 0.096)), 36)                       # camisa
    add_box(bm, (0.018, 0.007, 0.016), (hx, ey - 0.0175, 0.0975))               # brida de escape
    add_cyl(bm, 0.0080, 0.012, M_T((-0.008, ey, 0.098)), 28)                    # toma del carburador
    for k in range(4):                                                         # costillas de fundición
        a = radians(30 + 40 * k)
        add_box(bm, (0.050, 0.0025, 0.004), (-0.040, ey + 0.0215 * cos(a), ez - 0.0215 * sin(a)),
                R_X(-a))
    mesh_obj("Motor_Carter", bm, M["alu"], col, root, smooth=35)
    bm = bmesh.new()
    for k in range(4):
        a = radians(45 + 90 * k)
        add_cyl_axis(bm, (-0.0770, ey + 0.0165 * cos(a), ez + 0.0165 * sin(a)), 'X', 0.0021, 0.0016, 12)
    for y in (ey - 0.0175, ):
        for x in (hx - 0.006, hx + 0.006):
            add_cyl_axis(bm, (x, y - 0.0040, 0.0975), 'Y', 0.0018, 0.0012, 12)
    mesh_obj("Motor_Tornillos", bm, M["acero"], col, root)

    # --- culata con aletas (torneada) + ranuras de alivio ---
    prof = [(0.0006, 0.1032), (0.0135, 0.1032)]
    z = 0.1040
    for i in range(9):
        r = 0.0246 - 0.00035 * i
        prof += [(0.0135, z), (r - 0.0004, z), (r, z + 0.0004), (r, z + 0.0018), (r - 0.0004, z + 0.0022),
                 (0.0135, z + 0.0022)]
        z += 0.0047
    prof += [(0.0135, 0.1466), (0.0168, 0.1466), (0.0168, 0.1512), (0.0156, 0.1526), (0.0006, 0.1526)]
    bm = bmesh.new()
    add_lathe(bm, prof, 72, M_T((hx, ey, 0)))
    head = mesh_obj("Motor_Culata", bm, M["titanio"], col, root, smooth=40)
    cutters = []
    for a in (0, pi / 2, pi, 3 * pi / 2):
        cb = bmesh.new()
        d = Vector((cos(a), sin(a), 0))
        add_box(cb, (0.016, 0.0028, 0.040), Vector((hx, ey, 0.1275)) + d * 0.027, R_Z(a))
        cutters.append(cutter_obj("cut_culata", cb, col))
    boolean_cut(head, cutters)
    resmooth(head, 40)
    bm = bmesh.new()
    for k in range(6):
        a = 2 * pi * k / 6 + pi / 6
        add_cyl(bm, 0.0021, 0.0026, M_T((hx + 0.0198 * cos(a), ey + 0.0198 * sin(a), 0.1451)), 16)
    mesh_obj("Motor_Tornillos_Culata", bm, M["acero"], col, root)
    bm = bmesh.new()
    add_cyl(bm, 0.0052, 0.0058, M_T((hx, ey, 0.1555)), 6)                      # bujía incandescente
    add_cyl(bm, 0.0018, 0.003, M_T((hx, ey, 0.1640)), 12)
    mesh_obj("Motor_Bujia", bm, M["anodizado"], col, root)
    bm = bmesh.new()
    add_cyl(bm, 0.0030, 0.0034, M_T((hx, ey, 0.1601)), 16)
    mesh_obj("Motor_Bujia_Aislante", bm, M["ceramica"], col, root)

    # --- carburador: cuerpo, tambor, agujas y palanca ---
    cy = ey
    bm = bmesh.new()
    add_box(bm, (0.017, 0.019, 0.013), (-0.008, cy, 0.1105))
    add_cyl_axis(bm, (-0.008, cy, 0.1105), 'Y', 0.0068, 0.028, 28)              # tambor
    add_cyl_axis(bm, (-0.008, cy + 0.017, 0.1065), 'Y', 0.0028, 0.008, 16)      # porta-aguja
    add_cyl_axis(bm, (0.0035, cy + 0.006, 0.1065), 'X', 0.0016, 0.007, 12)      # niple de combustible
    add_cyl_axis(bm, (-0.008, cy - 0.016, 0.1045), 'Y', 0.0016, 0.007, 12)     # tornillo de ralentí
    mesh_obj("Carburador", bm, M["alu"], col, root, smooth=35)
    bm = bmesh.new()
    add_cyl_axis(bm, (-0.008, cy + 0.0245, 0.1065), 'Y', 0.0011, 0.008, 10)      # aguja de alta
    mesh_obj("Carburador_Aguja", bm, M["cromo"], col, root)
    bm = bmesh.new()
    add_cyl_axis(bm, (-0.008, cy + 0.0300, 0.1065), 'Y', 0.0034, 0.005, 12)      # perilla moleteada
    mesh_obj("Carburador_Perilla", bm, M["anodizado"], col, root, smooth=20)
    bm = bmesh.new()
    add_box(bm, (0.0035, 0.0018, 0.0135), (-0.008, cy - 0.0150, 0.1160))        # palanca
    add_cyl_axis(bm, (-0.008, cy - 0.0150, 0.1215), 'Y', 0.0016, 0.004, 12)
    mesh_obj("Carburador_Palanca", bm, M["anodizado"], col, root, smooth=None)

    # --- filtro de aire: codo de goma, base con abrazadera, espuma plisada, tapa ---
    tube("Filtro_Codo", [(-0.008, cy, 0.1165), (-0.008, cy, 0.127), (-0.008, 0.0, 0.129),
                         (-0.008, 0.0090, 0.129)], 0.0074, M["silicona"], col, root, res=14)
    Ay = AXIS_ROT['Y']
    bm = bmesh.new()
    add_lathe(bm, [(0.0040, 0.0085), (0.0186, 0.0085), (0.0190, 0.0100), (0.0186, 0.0150), (0.0040, 0.0150)],
              48, M_T((-0.008, 0.0, 0.129)) @ Ay)
    add_lathe(bm, [(0.0040, 0.0495), (0.0184, 0.0495), (0.0189, 0.0510), (0.0189, 0.0525), (0.0178, 0.0538),
                   (0.0040, 0.0538)], 48, M_T((-0.008, 0.0, 0.129)) @ Ay)
    add_cyl_axis(bm, (-0.008, 0.0558, 0.129), 'Y', 0.0052, 0.004, 24)
    mesh_obj("Filtro_Base_y_Tapa", bm, M["plastico"], col, root, smooth=40)
    bm = bmesh.new()
    add_lathe(bm, [(0.0192, 0.0108), (0.0198, 0.0110), (0.0198, 0.0128), (0.0192, 0.0130)], 48,
              M_T((-0.008, 0.0, 0.129)) @ Ay)
    mesh_obj("Filtro_Abrazadera", bm, M["acero"], col, root, smooth=40)
    bm = bmesh.new()
    add_pleated_cyl(bm, (-0.008, 0.0323, 0.129), 0.0171, 0.00028, 30, 0.0345, 180, Ay)
    mesh_obj("Filtro_Espuma", bm, M["espuma"], col, root, smooth=60)

    # --- arranque de tirón con nervios y manija ---
    bm = bmesh.new()
    add_cyl_axis(bm, (-0.0865, ey, ez), 'X', 0.0245, 0.020, 48)
    add_cyl_pts(bm, (-0.0965, ey, ez), (-0.1005, ey, ez), 0.0225, 48, 0.0175)
    for k in range(10):
        a = 2 * pi * k / 10
        add_box(bm, (0.016, 0.0022, 0.0028), (-0.0865, ey + 0.0250 * cos(a), ez + 0.0250 * sin(a)), R_X(a))
    mesh_obj("Arranque_Carcasa", bm, M["plastico"], col, root, smooth=35)
    tube("Arranque_Cuerda", [(-0.0925, ey - 0.024, 0.066), (-0.099, ey - 0.026, 0.064),
                             (-0.1045, ey - 0.020, 0.0635)], 0.0007, M["plastico2"], col, root, res=8, bevel_res=2)
    bm = bmesh.new()
    add_cyl_axis(bm, (-0.106, ey - 0.012, 0.0635), 'Y', 0.0046, 0.026, 20)
    mesh_obj("Arranque_Manija", bm, M["silicona"], col, root, smooth=35)

    # --- volante y campana de embrague ---
    crank = pivot("Cigueñal_Giro", col, root, frame_axis((0.0, ey, ez), (1, 0, 0), (0, 0, 1), 'Y'), 0.03, 'CIRCLE')
    bm = bmesh.new()
    add_cyl_axis(bm, (0.0045, ey, ez), 'X', 0.0195, 0.008, 48)            # 0.5 mm libre de la nariz
    mesh_obj("Volante_Motor", bm, M["chasis"], col, root, smooth=35)
    cutters = []
    vol = bpy.data.objects["Volante_Motor"]
    for k in range(6):
        a = 2 * pi * k / 6
        cb = bmesh.new()
        add_cyl_axis(cb, (0.0045, ey + 0.012 * cos(a), ez + 0.012 * sin(a)), 'X', 0.0028, 0.012, 16)
        cutters.append(cutter_obj("cut_volante", cb, col))
    boolean_cut(vol, cutters)
    resmooth(vol, 35)
    attach(vol, crank)
    bm = bmesh.new()
    add_cyl_axis(bm, (0.0115, ey, ez), 'X', 0.0175, 0.006, 48)
    add_cyl_axis(bm, (0.0155, ey, ez), 'X', 0.0050, 0.003, 6)                     # tuerca del volante
    attach(mesh_obj("Campana_Embrague", bm, M["anodizado"], col, root, smooth=35), crank)
    hw_m.rodamiento((-0.0045, ey, ez), (1, 0, 0), 0.0060, 0.0120, 0.0035)       # rodamiento delantero

    # --- escape: colector con brida, acople, resortes, sintonizado con soldadura y soporte ---
    PY, PZ = -0.085, 0.168                      # eje del escape sintonizado
    tube("Escape_Colector", [(hx, -0.0415, 0.0975), (hx, -0.062, 0.104), (-0.050, -0.080, 0.135),
                             (-0.058, PY, 0.160), (-0.066, PY, 0.1675), (-0.075, PY, PZ)],
         0.0068, M["cromo"], col, root, res=18)
    bm = bmesh.new()
    prof = [(0.0080, 0.000), (0.0080, 0.010), (0.0095, 0.022), (0.0135, 0.040),
            (0.0172, 0.058), (0.0186, 0.070), (0.0188, 0.095), (0.0180, 0.106),
            (0.0145, 0.118), (0.0095, 0.128), (0.0060, 0.134), (0.0058, 0.150)]
    Mp = M_T((-0.068, PY, PZ)) @ R_Y(-pi / 2)
    add_lathe(bm, prof, 48, Mp, closed=False)
    add_lathe(bm, [(0.0187, 0.0815), (0.0193, 0.0820), (0.0193, 0.0830), (0.0187, 0.0835)], 48, Mp)  # soldadura
    mesh_obj("Escape_Sintonizado", bm, M["cromo"], col, root, smooth=50, recalc=False)
    bm = bmesh.new()
    add_cyl_axis(bm, (-0.0735, PY, PZ), 'X', 0.0100, 0.017, 32)
    mesh_obj("Escape_Acople", bm, M["silicona"], col, root, smooth=35)
    for k, dy in enumerate((-0.0105, 0.0105)):
        p1 = Vector((-0.0610, PY + dy, PZ + 0.0005))
        p2 = Vector((-0.0890, PY + dy * 1.25, PZ + 0.0012))
        Mw, L = look_z(p1, p2)
        helix(f"Escape_Resorte_{k + 1}", 0.0013, 0.00035, 0.0015, L - 0.0015, 13, M["acero"], col, root, Mw)
    bm = bmesh.new()
    for dy in (-0.0105, 0.0105):
        add_cyl(bm, 0.0011, 0.004, M_T((-0.0610, PY + dy, PZ - 0.001)), 10)
        add_cyl(bm, 0.0011, 0.004, M_T((-0.0890, PY + dy * 1.25, PZ - 0.0005)), 10)
    mesh_obj("Escape_Ganchos", bm, M["cromo"], col, root)
    bm = bmesh.new()
    add_cyl(bm, 0.0018, 0.008, M_T((-0.158, PY, PZ + 0.0205)), 12)               # toma de presión
    mesh_obj("Escape_Toma_Presion", bm, M["cromo"], col, root)
    tube("Escape_Deflector", [(-0.2155, PY, PZ), (-0.2255, PY, PZ - 0.002), (-0.2310, PY - 0.004, PZ - 0.009)],
         0.0064, M["silicona"], col, root, res=12)

    # --- transmisión de 2 velocidades ---
    # salidas: resaltes a lo largo de X (eje de los piñones); los cardanes entran con ángulo
    # en copas, separados 1.5 mm o más para que nada roce al girar
    bm = bmesh.new()
    add_box_minmax(bm, (0.0175, -0.045, 0.049), (0.064, 0.005, 0.072))
    add_cyl_axis(bm, (0.04075, ey, 0.074), 'X', 0.022, 0.0465, 40)
    add_cyl_axis(bm, (0.01475, CARDAN_TRAS[0].y, CARDAN_TRAS[0].z), 'X', 0.0060, 0.0065, 24)   # salida trasera
    add_box_minmax(bm, (0.0125, CARDAN_TRAS[0].y - 0.005, 0.049), (0.0180, CARDAN_TRAS[0].y + 0.005,
                                                                    CARDAN_TRAS[0].z))       # pedestal
    mesh_obj("Transmision", bm, M["plastico"], col, root, smooth=35)
    bm = bmesh.new()
    add_cyl_axis(bm, (0.0645, ey, 0.074), 'X', 0.0225, 0.004, 40)
    add_cyl_axis(bm, (0.0675, ey, 0.074), 'X', 0.0060, 0.005, 24)               # salida delantera
    for k in range(4):
        a = radians(45 + 90 * k)
        add_cyl_axis(bm, (0.0645, ey + 0.016 * cos(a), 0.074 + 0.016 * sin(a)), 'X', 0.0021, 0.0016, 12)
    mesh_obj("Transmision_Anillo", bm, M["chasis"], col, root, smooth=35)
    # cardanes centrales: giran sobre su propio eje (modo YXZ: el ángulo Y es giro puro)
    for nm_c, (a_, b_) in (("Del", CARDAN_DEL), ("Tras", CARDAN_TRAS)):
        Lc = (b_ - a_).length
        bm = bmesh.new()
        add_cyl_axis(bm, (0, Lc / 2, 0), 'Y', 0.0045, Lc, 16)
        sh = mesh_obj("Cardan_Central_" + nm_c, bm, M["acero"], col, root)
        sh.rotation_mode = 'YXZ'
        sh.matrix_basis = frame_axis(a_, b_ - a_, (0, 0, 1), 'Y')
        REST[sh.name] = sh.matrix_basis.copy()
        bm = bmesh.new()
        for yy in (0.004, Lc - 0.004):
            add_cyl_axis(bm, (0, yy, 0), 'Y', 0.0075, 0.010, 20)
            add_cyl_axis(bm, (0, yy, 0), 'X', 0.0013, 0.0165, 8)
        mesh_obj("Cardan_Copas_" + nm_c, bm, M["chasis"], col, sh)                 # coordenadas locales del eje
    hw_m.build()


# ---------------------------------------------------------------------------
# Tanque, radio y servos
# ---------------------------------------------------------------------------
def build_electronics(root, C, M):
    col = C["elec"]
    # --- tanque de combustible translúcido con tapa abatible ---
    bm = bmesh.new()
    add_box_minmax(bm, (-0.068, 0.020, 0.0495), (0.045, 0.072, 0.104))
    tk = mesh_obj("Tanque_Combustible", bm, M["tanque"], col, root, smooth=None)
    bv = tk.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.007
    bv.segments = 4
    apply_modifiers(tk)
    resmooth(tk, 35)
    bm = bmesh.new()
    add_cyl(bm, 0.0118, 0.004, M_T((0.026, 0.046, 0.1058)), 32)                  # base de la tapa
    add_cyl(bm, 0.0122, 0.003, M_T((0.026, 0.046, 0.1093)), 32)                  # tapa
    add_box(bm, (0.006, 0.010, 0.006), (0.0115, 0.046, 0.1075))                  # bisagra
    add_box(bm, (0.006, 0.006, 0.002), (0.0400, 0.046, 0.1100))                  # pestaña
    mesh_obj("Tanque_Tapa", bm, M["plastico"], col, root, smooth=35)
    bm = bmesh.new()
    add_cyl_axis(bm, (0.0115, 0.046, 0.1078), 'Y', 0.0009, 0.016, 8)             # pasador de bisagra
    mesh_obj("Tanque_Bisagra_Pasador", bm, M["cromo"], col, root)
    bm = bmesh.new()
    for p in ((0.006, 0.050), (0.035, 0.060), (-0.005, 0.064)):
        add_cyl(bm, 0.0017, 0.006, M_T((p[0], p[1], 0.1065)), 12)                # niples
    mesh_obj("Tanque_Niples", bm, M["tanque"], col, root)
    bm = bmesh.new()
    for x in (-0.052, -0.012):                                                    # correas de goma
        add_box_minmax(bm, (x - 0.0045, 0.0185, 0.1040), (x + 0.0045, 0.0735, 0.1062))
        add_box_minmax(bm, (x - 0.0045, 0.0172, 0.049), (x + 0.0045, 0.0192, 0.1062))
        add_box_minmax(bm, (x - 0.0045, 0.0728, 0.049), (x + 0.0045, 0.0748, 0.1062))
    mesh_obj("Tanque_Correas", bm, M["silicona"], col, root, smooth=None)
    # mangueras de combustible
    tube("Manguera_Carburador", [(0.006, 0.050, 0.1095), (0.014, 0.042, 0.1130), (0.0158, 0.015, 0.1100),
                                 (0.0125, -0.008, 0.1068), (0.0068, -0.014, 0.1065)],
         0.0022, M["manguera"], col, root, res=14)
    tube("Manguera_Presion", [(0.035, 0.060, 0.1095), (0.031, 0.052, 0.1360), (0.006, 0.030, 0.1790),
                              (-0.062, 0.002, 0.1940), (-0.122, -0.058, 0.2000),   # pasa sobre el tirante central (-0.158, -0.085, 0.1985),
                              (-0.158, -0.085, 0.1935)],
         0.0022, M["manguera"], col, root, res=14)
    tube("Manguera_Respiradero", [(-0.005, 0.064, 0.1095), (-0.012, 0.074, 0.112), (-0.030, 0.079, 0.10),
                                  (-0.050, 0.080, 0.080)], 0.0018, M["manguera"], col, root, res=10)

    # --- caja de radio: bandeja hueca, tapa con bisagra, batería y receptor ---
    X0, X1, Y0, Y1, Z0, Z1 = 0.086, 0.144, 0.018, 0.072, 0.0495, 0.089
    bm = bmesh.new()
    for xt in (0.125, 0.138):                                                    # pestañas de cierre (lado interior)
        add_box_minmax(bm, (xt - 0.004, Y0 - 0.0070, 0.0830), (xt + 0.004, Y0 + 0.0005, 0.0860))
    add_box_minmax(bm, (0.0790, 0.0650, 0.068), (0.0865, 0.0745, 0.086))         # soporte de antena
    for x in (0.093, 0.137):                                                     # nudillos de bisagra
        add_cyl_axis(bm, (x, Y1 + 0.0010, Z1 + 0.0015), 'X', 0.0026, 0.010, 16)
    mesh_obj("Caja_Radio_Detalles", bm, M["plastico"], col, root, smooth=None)
    bm = bmesh.new()
    add_box_minmax(bm, (X0, Y0, Z0), (X1, Y1, Z1))
    box = mesh_obj("Caja_Radio", bm, M["plastico"], col, root, smooth=None)
    cutters = []
    cb = bmesh.new()
    add_box_minmax(cb, (X0 + 0.002, Y0 + 0.002, Z0 + 0.002), (X1 - 0.002, Y1 - 0.002, Z1 + 0.010))
    cutters.append(cutter_obj("cut_caja", cb, col))
    cb = bmesh.new()
    add_cyl_axis(cb, (0.095, Y0, 0.080), 'Y', 0.0040, 0.010, 20)                 # pasacables
    cutters.append(cutter_obj("cut_pasacables", cb, col))
    cb = bmesh.new()
    add_cyl_axis(cb, (X0, 0.066, 0.080), 'X', 0.0021, 0.008, 12)                # salida del cable de antena
    cutters.append(cutter_obj("cut_antena", cb, col))
    boolean_cut(box, cutters)
    bm = bmesh.new()
    add_lathe(bm, [(0.0028, -0.0030), (0.0050, -0.0030), (0.0056, 0.0), (0.0050, 0.0030), (0.0028, 0.0030)], 24,
              M_T((0.095, Y0, 0.080)) @ AXIS_ROT['Y'])
    mesh_obj("Pasacables_Goma", bm, M["silicona"], col, root, smooth=45)
    bm = bmesh.new()
    for xt in (0.125, 0.138):                                                    # pasadores de cierre
        add_cyl_pts(bm, (xt, Y0 - 0.0035, 0.0815), (xt, Y0 - 0.0035, 0.0935), 0.0011, 8)
    add_cyl_axis(bm, (0.115, Y1 + 0.0010, Z1 + 0.0015), 'X', 0.0010, 0.056, 8)   # pasador de bisagra
    mesh_obj("Caja_Radio_Pasadores", bm, M["cromo"], col, root)
    # tapa articulada (gira en X alrededor de la bisagra; 0° = cerrada)
    hinge = pivot("Bisagra_Tapa_Radio", col, root, M_T((0.115, Y1 + 0.0010, Z1 + 0.0015)), 0.012, 'SINGLE_ARROW')
    bm = bmesh.new()
    add_box_minmax(bm, (0.084, 0.016, 0.0885), (0.146, 0.0745, 0.0960))
    add_box_minmax(bm, (0.094, 0.026, 0.0960), (0.136, 0.064, 0.0975))           # panel en relieve
    add_box_minmax(bm, (X0 + 0.0022, Y0 + 0.0022, 0.0855), (X1 - 0.0022, Y1 - 0.0022, 0.0885))  # labio
    for xt in (0.125, 0.138):                                                    # pestañas de la tapa
        add_box_minmax(bm, (xt - 0.004, Y0 - 0.0070, 0.0885), (xt + 0.004, 0.016, 0.0915))
    add_cyl_axis(bm, (0.115, Y1 + 0.0010, Z1 + 0.0015), 'X', 0.0026, 0.033, 16)  # nudillo central
    lid = mesh_obj("Caja_Radio_Tapa", bm, M["plastico2"], col, root, smooth=None)
    cutters = []
    for xk in (0.093, 0.137):
        cb = bmesh.new()
        add_cyl_axis(cb, (xk, Y1 + 0.0010, Z1 + 0.0015), 'X', 0.0034, 0.0112, 20)
        cutters.append(cutter_obj("cut_tapa_nudillo", cb, col))
    boolean_cut(lid, cutters)
    attach(lid, hinge)
    bm = bmesh.new()
    add_box_minmax(bm, (0.104, 0.034, 0.0975), (0.126, 0.056, 0.0978))
    attach(mesh_obj("Caja_Radio_Tapa_Etiqueta", bm, M["etiqueta"], col, root, smooth=None), hinge)
    hinge.rotation_euler.x = radians(-105)                                      # abierta para ver adentro
    # interruptor (funda exterior + cuerpo interior)
    bm = bmesh.new()
    add_box_minmax(bm, (0.096, Y1, 0.062), (0.112, Y1 + 0.0055, 0.078))
    mesh_obj("Interruptor_Funda", bm, M["silicona"], col, root, smooth=None)
    bm = bmesh.new()
    add_box_minmax(bm, (0.098, Y1 - 0.0085, 0.064), (0.110, Y1 - 0.002, 0.076))
    mesh_obj("Interruptor_Cuerpo", bm, M["plastico"], col, root, smooth=None)
    # batería: 4 pilas AA en termoencogible
    bm = bmesh.new()
    for yy in (0.0285, 0.0429):
        for zz in (0.0589, 0.0733):
            add_cyl_axis(bm, (0.1150, yy, zz), 'X', 0.0072, 0.049, 28)
    add_box_minmax(bm, (0.0905, 0.0285, 0.0589), (0.1395, 0.0429, 0.0733))
    mesh_obj("Bateria_Receptor", bm, M["termo"], col, root, smooth=35)
    bm = bmesh.new()
    add_box_minmax(bm, (0.100, 0.0300, 0.0805), (0.130, 0.0415, 0.08065))
    mesh_obj("Bateria_Etiqueta", bm, M["etiqueta"], col, root, smooth=None)
    # receptor con conectores
    bm = bmesh.new()
    add_box_minmax(bm, (0.098, 0.0510, 0.0515), (0.130, 0.0625, 0.0735))
    mesh_obj("Receptor", bm, M["plastico2"], col, root, smooth=None)
    bm = bmesh.new()
    add_box_minmax(bm, (0.101, 0.0525, 0.07352), (0.127, 0.0610, 0.07362))
    mesh_obj("Receptor_Etiqueta", bm, M["etiqueta"], col, root, smooth=None)
    plugs_x = (0.1035, 0.1095, 0.1155, 0.1215)
    bm = bmesh.new()
    for px_ in plugs_x:
        add_box_minmax(bm, (px_ - 0.0014, 0.0525, 0.0735), (px_ + 0.0014, 0.0610, 0.0795))
    mesh_obj("Receptor_Conectores", bm, M["plastico"], col, root, smooth=None)
    # cable de antena del receptor al tubo
    tube("Antena_Cable", [(0.0985, 0.058, 0.070), (0.091, 0.065, 0.078), (0.0865, 0.066, 0.080),
                          (0.0840, 0.0690, 0.0835), (0.0825, 0.0698, 0.0890)], 0.0006, M["plastico"], col, root,
         res=8, bevel_res=2)
    bm = bmesh.new()
    add_cyl_pts(bm, (0.0825, 0.0698, 0.086), (0.0825, 0.0698, 0.335), 0.0025, 12)
    add_cyl(bm, 0.0042, 0.012, M_T((0.0825, 0.0698, 0.338)), 16)
    add_cyl(bm, 0.0045, 0.006, M_T((0.0825, 0.0698, 0.089)), 16)
    mesh_obj("Antena", bm, M["plastico"], col, root)
    # cables de batería al interruptor y del interruptor al receptor
    for k, (mat, dz) in enumerate(((M["cable_r"], 0.0008), (M["plastico"], -0.0008))):
        tube(f"Cable_Bateria_{k}", [(0.1398, 0.0357, 0.0661 + dz), (0.1415, 0.050, 0.083 + dz),
                                    (0.122, 0.062, 0.0845 + dz), (0.108, Y1 - 0.009, 0.072 + dz)],
             0.0008, mat, col, root, res=10, bevel_res=2)
    for k, (mat, dz) in enumerate(((M["plastico"], -0.0011), (M["cable_r"], 0.0), (M["cable_b"], 0.0011))):
        tube(f"Cable_Interruptor_{k}", [(0.100, Y1 - 0.009, 0.075 + dz), (0.104, 0.064, 0.083 + dz),
                                        (plugs_x[3], 0.0567, 0.0815 + dz), (plugs_x[3], 0.0567, 0.0795)],
             0.0007, mat, col, root, res=10, bevel_res=2)

    hw_e = Herrajes("Electronica", col, root, M)
    # --- servos de dirección y acelerador (carcasa en 3 piezas) ---
    for nm, x0, plug in (("Direccion", 0.112, plugs_x[0]), ("Acelerador", 0.084, plugs_x[1])):
        bm = bmesh.new()
        add_box_minmax(bm, (x0, -0.078, 0.0545), (x0 + 0.025, -0.036, 0.0835))   # cuerpo
        add_box_minmax(bm, (x0 - 0.001, -0.086, 0.074), (x0 + 0.026, -0.028, 0.0765))  # orejas
        mesh_obj("Servo_" + nm, bm, M["plastico"], col, root, smooth=None)
        bm = bmesh.new()
        add_box_minmax(bm, (x0 - 0.0003, -0.0783, 0.0495), (x0 + 0.0253, -0.0357, 0.0542))   # tapa inferior
        add_box_minmax(bm, (x0 - 0.0003, -0.0783, 0.0838), (x0 + 0.0253, -0.0357, 0.0880))   # tapa superior
        add_cyl(bm, 0.0058, 0.0030, M_T((x0 + 0.0125, -0.046, 0.0895)), 24)                  # domo del eje
        mesh_obj("Servo_Tapas_" + nm, bm, M["plastico2"], col, root, smooth=None)
        bm = bmesh.new()
        for xx in (x0 + 0.004, x0 + 0.021):
            for yy in (-0.0825, -0.0315):
                add_lathe(bm, [(0.0012, 0.0765), (0.0030, 0.0765), (0.0032, 0.0773), (0.0030, 0.0781),
                               (0.0012, 0.0781)], 16, M_T((xx, yy, 0)))                    # gomas
        mesh_obj("Servo_Gomas_" + nm, bm, M["silicona"], col, root, smooth=40)
        for xx in (x0 + 0.004, x0 + 0.021):
            for yy in (-0.0825, -0.0315):
                hw_e.arandela((xx, yy, 0.0781), (0, 0, 1), 0.0025, 0.0030)
                hw_e.tornillo((xx, yy, 0.0786), (0, 0, 1), 0.010, 0.0025, "boton")
        bm = bmesh.new()
        add_box_minmax(bm, (x0 + 0.002, -0.0785, 0.057), (x0 + 0.023, -0.0782, 0.080))
        mesh_obj("Servo_Etiqueta_" + nm, bm, M["etiqueta"], col, root, smooth=None)
        if nm == "Acelerador":
            bm = bmesh.new()
            add_cyl(bm, 0.0045, 0.004, M_T((x0 + 0.0125, -0.046, 0.0925)), 16)
            add_box(bm, (0.006, 0.022, 0.003), (x0 + 0.0125, -0.046, 0.0955))
            mesh_obj("Servo_Brazo_" + nm, bm, M["anodizado"], col, root, smooth=None)
            hw_e.tornillo((x0 + 0.0125, -0.046, 0.0970), (0, 0, 1), 0.006, 0.0025, "cilindrica")
        # cables: salen del servo, suben, cruzan sobre el cardán y entran por el pasacables
        bundle = []
        for k, (mat, dy) in enumerate(((M["plastico"], -0.0011), (M["cable_r"], 0.0), (M["cable_b"], 0.0011))):
            pts = [(x0 + 0.004 + dy, -0.0362, 0.068), (x0 + 0.004 + dy, -0.030, 0.090),
                   (x0 + 0.003 + dy, -0.010, 0.099), (x0 + 0.002 + dy, 0.008, 0.097),
                   (0.095 + dy, 0.0145, 0.0805), (0.095 + dy, 0.024, 0.081),
                   (plug + dy * 0.6, 0.047, 0.0835), (plug + dy * 0.6, 0.0567, 0.0815), (plug + dy * 0.6, 0.0567, 0.0795)]
            tube(f"Cable_Servo_{nm}_{k}", pts, 0.0007, mat, col, root, res=10, bevel_res=2)
        # amarras plásticas
        bm = bmesh.new()
        for (px_, py_, pz_) in ((x0 + 0.003, -0.010, 0.099), (x0 + 0.002, 0.004, 0.0985)):
            add_box_minmax(bm, (px_ - 0.0034, py_ - 0.0007, pz_ - 0.0019), (px_ + 0.0034, py_ + 0.0007, pz_ + 0.0019))
            add_box_minmax(bm, (px_ + 0.0030, py_ - 0.0012, pz_ - 0.0012), (px_ + 0.0052, py_ + 0.0012, pz_ + 0.0012))
        mesh_obj("Amarras_Servo_" + nm, bm, M["plastico"], col, root, smooth=None)

    # --- freno: disco en el cardán delantero + pinza con leva ---
    ey = -0.02
    a_, b_ = CARDAN_DEL
    dsh = (b_ - a_).normalized()
    cdisc = a_ + dsh * 0.0014        # sobre la copa: libre del resalte de salida y de las orejas del servo
    Md, _ = look_z(cdisc - dsh * 0.0011, cdisc + dsh * 0.0011)
    bm = bmesh.new()
    add_cyl(bm, 0.0165, 0.0022, Md @ M_T((0, 0, 0.0011)), 48)
    add_cyl(bm, 0.0062, 0.0050, Md @ M_T((0, 0, 0.0011)), 24)
    disc = mesh_obj("Freno_Disco", bm, M["acero"], col, root)
    cutters = []
    for k in range(8):
        aa = 2 * pi * k / 8
        cb = bmesh.new()
        add_cyl(cb, 0.0016, 0.01, Md @ M_T((0.0110 * cos(aa), 0.0110 * sin(aa), 0.0011)), 10)
        cutters.append(cutter_obj("cut_disco", cb, col))
    boolean_cut(disc, cutters)
    resmooth(disc, 35)
    attach(disc, bpy.data.objects["Cardan_Central_Del"])                        # gira con el cardán
    top = cdisc + Vector((0, 0, 0.0145))
    Fd = frame_axis(Vector((0, 0, 0)), dsh, (0, 0, 1), 'Z')                    # Z = eje del cardán, X = arriba
    bm = bmesh.new()
    for sg in (-1, 1):                                                         # dos mitades, una a cada lado
        add_box(bm, (0.0105, 0.012, 0.0030), cdisc + Fd.to_3x3() @ Vector((0.0158, 0, sg * 0.0031)), Fd)
    add_box(bm, (0.0030, 0.012, 0.0088), cdisc + Fd.to_3x3() @ Vector((0.0225, 0, 0)), Fd)   # puente
    # soporte en L atornillado a la cara del anillo de la transmisión, por encima de la
    # salida (no toca la copa ni el resalte que giran debajo)
    add_box_minmax(bm, (0.0665, ey - 0.006, 0.0835), (0.0680, ey + 0.006, top.z + 0.008))
    add_box_minmax(bm, (0.0665, ey - 0.006, top.z + 0.005), (cdisc.x + 0.004, ey + 0.006, top.z + 0.008))
    mesh_obj("Freno_Pinza", bm, M["plastico"], col, root, smooth=None)
    bm = bmesh.new()
    for sg in (-1, 1):                                                         # pastillas
        add_box(bm, (0.0080, 0.009, 0.0007), cdisc + Fd.to_3x3() @ Vector((0.0145, 0, sg * 0.00165)), Fd)
    mesh_obj("Freno_Pastillas", bm, M["acero"], col, root, smooth=None)
    lev_a = top + Vector((0, 0, 0.0100))
    lev_b = Vector((cdisc.x, -0.033, 0.0995))
    bm = bmesh.new()
    add_cyl(bm, 0.0022, 0.004, M_T(lev_a + Vector((0, 0, -0.001))), 12)
    add_beam(bm, lev_a, lev_b, 0.0030, 0.0022)
    mesh_obj("Freno_Leva", bm, M["anodizado"], col, root, smooth=None)
    BA = Vector((0.0965, -0.0545, 0.0965))
    bm = bmesh.new()
    add_cyl_pts(bm, BA, lev_b, 0.0010, 10)
    mesh_obj("Varilla_Freno", bm, M["cromo"], col, root)
    Mw, L = look_z(BA, lev_b)
    bm = bmesh.new()
    add_cyl(bm, 0.0024, 0.0030, Mw @ M_T((0, 0, L * 0.30)), 16)
    add_cyl(bm, 0.0022, 0.005, Mw @ M_T((0, 0, 0.003)), 12)
    add_cyl(bm, 0.0022, 0.005, Mw @ M_T((0, 0, L - 0.003)), 12)
    mesh_obj("Varilla_Freno_Topes", bm, M["anodizado"], col, root)
    helix("Varilla_Freno_Resorte", 0.0018, 0.00035, L * 0.30 + 0.0016, L * 0.62, 8, M["acero"], col, root, Mw)

    hw_e.tornillo((0.0705, ey, top.z + 0.0080), (0, 0, 1), 0.008, 0.003, "cilindrica")   # pinza
    hw_e.build()
    # --- filtro de combustible en línea ---
    f1 = Vector((0.014, 0.042, 0.1130))
    f2 = Vector((0.0158, 0.015, 0.1100))
    fc_ = (f1 + f2) / 2
    fd = (f2 - f1).normalized()
    Mf, _ = look_z(fc_ - fd * 0.008, fc_ + fd * 0.008)
    bm = bmesh.new()
    add_cyl(bm, 0.0045, 0.012, Mf @ M_T((0, 0, 0.008)), 24)
    mesh_obj("Filtro_Combustible", bm, M["tanque"], col, root)
    bm = bmesh.new()
    add_cyl(bm, 0.0030, 0.010, Mf @ M_T((0, 0, 0.008)), 16)
    mesh_obj("Filtro_Combustible_Malla", bm, M["acero"], col, root)
    bm = bmesh.new()
    for z_ in (0.0010, 0.0150):
        add_cyl(bm, 0.0036, 0.0022, Mf @ M_T((0, 0, z_)), 16)
    mesh_obj("Filtro_Combustible_Tapas", bm, M["anodizado"], col, root)

    # --- varilla del acelerador con resorte de retorno ---
    A = Vector((0.0965, -0.0375, 0.0965))
    B = Vector((-0.0060, -0.0350, 0.1215))
    bm = bmesh.new()
    add_cyl_pts(bm, A, B, 0.0010, 10)
    mesh_obj("Varilla_Acelerador", bm, M["cromo"], col, root)
    Mw, L = look_z(A, B)
    bm = bmesh.new()
    for t in (0.50, 0.80):
        add_cyl(bm, 0.0026, 0.0032, Mw @ M_T((0, 0, L * t)), 16)                 # topes
    add_cyl(bm, 0.0022, 0.005, Mw @ M_T((0, 0, 0.003)), 12)                      # rótulas
    add_cyl(bm, 0.0022, 0.005, Mw @ M_T((0, 0, L - 0.003)), 12)
    mesh_obj("Varilla_Acelerador_Topes", bm, M["anodizado"], col, root)
    helix("Varilla_Acelerador_Resorte", 0.0019, 0.00035, L * 0.80 + 0.0016, L - 0.006, 9,
          M["acero"], col, root, Mw)


# ---------------------------------------------------------------------------
# Carrocería tipo pickup monster truck
# ---------------------------------------------------------------------------
HW = 0.163                    # media anchura de la carrocería
GH_B = dict(z=0.236, xf=0.068, xr=-0.097, y=0.150)   # base de la cabina
GH_T = dict(z=0.312, xf=0.002, xr=-0.086, y=0.122)   # techo de la cabina


def hood_z(x):
    return 0.218 + (0.266 - x) * (0.020 / 0.196)


def window(bm, Pbl, Pbr, Ptl, Ptr, u0, u1, v0, v1, center, off=0.0012, rad=0.008, n=5):
    """Ventana con esquinas redondeadas sobre una cara cuadrilátera de la cabina."""
    Pbl, Pbr, Ptl, Ptr = map(Vector, (Pbl, Pbr, Ptl, Ptr))
    def P(u, v):
        return (Pbl.lerp(Pbr, u)).lerp(Ptl.lerp(Ptr, u), v)
    lu = ((Pbr - Pbl).length + (Ptr - Ptl).length) / 2
    lv = ((Ptl - Pbl).length + (Ptr - Pbr).length) / 2
    ru, rv = rad / lu, rad / lv
    pts = []
    corners = [(u1 - ru, v0 + rv, -pi / 2), (u1 - ru, v1 - rv, 0.0),
               (u0 + ru, v1 - rv, pi / 2), (u0 + ru, v0 + rv, pi)]
    for cu, cv, a0 in corners:
        for i in range(n + 1):
            a = a0 + (pi / 2) * i / n
            pts.append(P(cu + ru * cos(a), cv + rv * sin(a)))
    nrm = (Pbr - Pbl).cross(Ptl - Pbl).normalized()
    if nrm.dot(P(0.5, 0.5) - Vector(center)) < 0:
        nrm = -nrm
    vs = [bm.verts.new(p + nrm * off) for p in pts]
    f = bm.faces.new(vs)
    f.normal_update()
    if f.normal.dot(nrm) < 0:
        f.normal_flip()


def build_body(root, C, M):
    """Carrocería "LOCURA": pickup monstruo con casco esculpido (loft de secciones), pintura y
    calcomanías en un atlas de 4096 (livery.py), guardabarros atornillados, soplador en el capó,
    barra de luces LED, parachoques con defensa tubular, faros de proyector, alerón de fibra de
    carbono, barra antivuelco con focos, escapes laterales, estribos y neón bajo la carrocería."""
    col = C["body"]
    body = empty("Carroceria", col, root, size=0.08, kind='CUBE')
    body.location.z = 0.020           # carrocería elevada para dar recorrido a las ruedas
    body.empty_display_size = 0.02
    L = M_livery = material_livery(M)

    def cortar(o, cutters, **kw):
        for c_ in cutters:
            c_.parent = body
        boolean_cut(o, cutters, **kw)

    def gancho(c, r, n=10):
        """Gancho en U bajo un parachoques (plano XZ), extremos hacia arriba."""
        return [c + Vector((-r * cos(pi * k / n), 0, -r * sin(pi * k / n))) for k in range(n + 1)]

    # ------------------------------------------------------------------ casco (loft)
    def capo(x):
        return 0.2165 + (0.270 - x) * (0.0195 / 0.202)

    def params(x):
        hw = 0.163
        for xx, v in ((0.2895, 0.150), (0.2875, 0.155), (0.284, 0.159), (0.278, 0.162)):
            if abs(x - xx) < 1e-6:
                hw = v
        for xx, v in ((-0.268, 0.162), (-0.2725, 0.160), (-0.2745, 0.157)):
            if abs(x - xx) < 1e-6:
                hw = v
        if x >= 0.068:
            zt = capo(x)
            zt -= {0.2895: 0.012, 0.2875: 0.006, 0.284: 0.003, 0.278: 0.001}.get(round(x, 4), 0.0)
        elif x >= -0.092:
            zt = 0.236
        elif x >= -0.108:
            zt = 0.236 + 0.006 * (-0.092 - x) / 0.016
        else:
            zt = 0.242
        zt -= {-0.268: 0.001, -0.2725: 0.003, -0.2745: 0.006}.get(round(x, 4), 0.0)
        zb = {0.2895: 0.163, 0.2875: 0.160}.get(round(x, 4), 0.157)
        r = 0.008 if (x > 0.283 or x < -0.266) else 0.012
        crown = 0.004 * max(0.0, min(1.0, (x - 0.07) / 0.03, (0.278 - x) / 0.02)) if x >= 0.07 else 0.0
        return hw, zb, zt, r, 0.004, crown

    def seccion(x):
        hw, zb, zt, r, tb, cr = params(x)
        rb, n_a, n_t = 0.003, 6, 7
        half = [(0.0, zb), (hw - rb, zb)]
        for k in range(1, n_a):
            a = -pi / 2 + (pi / 2) * k / n_a
            half.append((hw - rb + rb * cos(a), zb + rb + rb * sin(a)))
        half.append((hw, zb + rb))
        cx, cz = hw - tb - r, zt - r
        for k in range(0, n_a + 1):
            a = (pi / 2) * k / n_a
            half.append((cx + r * cos(a), cz + r * sin(a)))
        ytop = cx
        for j in range(1, n_t + 1):
            y = ytop * (1 - j / n_t)
            half.append((y, zt + cr * (1 - (y / ytop) ** 2)))
        loop = half + [(-y, z) for (y, z) in reversed(half[1:-1])]
        return [Vector((x, y, z)) for (y, z) in loop]

    xs = [0.2895, 0.2875, 0.284, 0.278, 0.270, 0.258, 0.240, 0.215, 0.190, 0.160, 0.130, 0.100, 0.080,
          0.068, 0.040, 0.000, -0.040, -0.080, -0.092, -0.100, -0.108, -0.130, -0.160, -0.190, -0.220,
          -0.245, -0.262, -0.268, -0.2725, -0.2745]
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in seccion(x)] for x in xs]
    n = len(rings[0])
    for r0, r1 in zip(rings[:-1], rings[1:]):
        for k in range(n):
            bm.faces.new((r0[k], r0[(k + 1) % n], r1[(k + 1) % n], r1[k]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    shell = mesh_obj("Carroceria_Casco", bm, L, col, body, smooth=None)
    cutters = []
    cb = bmesh.new()
    add_box_minmax(cb, (-0.259, -0.153, 0.215), (-0.108, 0.153, 0.40))
    cutters.append(cutter_obj("cut_caja", cb, col))
    for f in (1, -1):
        for s in (1, -1):
            cb = bmesh.new()
            add_cyl_axis(cb, (f * XA, s * HW, ARCO_ZL), 'Y', ARCO_R, 0.11, 96)
            cutters.append(cutter_obj("cut_paso", cb, col))
    for (x, y, r) in ((0.230, 0.028, 0.0035), (0.230, -0.028, 0.0035), (-0.230, 0.028, 0.0035),
                      (-0.230, -0.028, 0.0035), (0.0825, 0.0698, 0.0030)):
        cb = bmesh.new()
        add_cyl(cb, r, 0.2, M_T((x, y, 0.25)), 16)
        cutters.append(cutter_obj("cut_poste", cb, col))
    cortar(shell, cutters)
    bm = bmesh.new()                                     # vaciar por debajo y dar espesor
    bm.from_mesh(shell.data)
    bm.normal_update()
    bmesh.ops.delete(bm, geom=[f_ for f_ in bm.faces if f_.normal.z < -0.9 and f_.calc_center_median().z < 0.165],
                     context='FACES')
    bm.to_mesh(shell.data)
    bm.free()
    so = shell.modifiers.new("Espesor", 'SOLIDIFY')
    so.thickness = 0.0022
    so.offset = -1
    apply_modifiers(shell)
    resmooth(shell, 32)
    uv_livery(shell)

    # ------------------------------------------------------------------ cabina
    b, t = GH_B, GH_T
    pts = [(b["xf"], -b["y"], b["z"]), (b["xf"], b["y"], b["z"]), (b["xr"], b["y"], b["z"]), (b["xr"], -b["y"], b["z"]),
           (t["xf"], -t["y"], t["z"]), (t["xf"], t["y"], t["z"]), (t["xr"], t["y"], t["z"]), (t["xr"], -t["y"], t["z"])]
    bm = bmesh.new()
    add_hexa(bm, pts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.delete(bm, geom=[f_ for f_ in bm.faces if f_.normal.z < -0.9], context='FACES')
    cab = mesh_obj("Carroceria_Cabina", bm, L, col, body, smooth=None, recalc=False)
    bv = cab.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.008
    bv.segments = 6
    bv.limit_method = 'ANGLE'
    bv.angle_limit = radians(15)
    so = cab.modifiers.new("Espesor", 'SOLIDIFY')
    so.thickness = 0.0018
    so.offset = -1
    apply_modifiers(cab)
    resmooth(cab, 30)
    uv_livery(cab)

    def cara(Pbl, Pbr, Ptl, Ptr):
        Pbl, Pbr, Ptl, Ptr = map(Vector, (Pbl, Pbr, Ptl, Ptr))
        return lambda u, v: (Pbl.lerp(Pbr, u)).lerp(Ptl.lerp(Ptr, u), v)

    cc = ((b["xf"] + b["xr"]) / 2, 0, (b["z"] + t["z"]) / 2)
    bm = bmesh.new()
    lados = {}
    for s in (1, -1):
        Pbl = (b["xf"], s * b["y"], b["z"]); Pbr = (b["xr"], s * b["y"], b["z"])
        Ptl = (t["xf"], s * t["y"], t["z"]); Ptr = (t["xr"], s * t["y"], t["z"])
        window(bm, Pbl, Pbr, Ptl, Ptr, 0.07, 0.60, 0.24, 0.87, cc)
        window(bm, Pbl, Pbr, Ptl, Ptr, 0.66, 0.93, 0.24, 0.87, cc)
        lados[s] = cara(Pbl, Pbr, Ptl, Ptr)
    window(bm, (b["xf"], -b["y"], b["z"]), (b["xf"], b["y"], b["z"]),
           (t["xf"], -t["y"], t["z"]), (t["xf"], t["y"], t["z"]), 0.06, 0.94, 0.16, 0.92, cc)
    window(bm, (b["xr"], b["y"], b["z"]), (b["xr"], -b["y"], b["z"]),
           (t["xr"], t["y"], t["z"]), (t["xr"], -t["y"], t["z"]), 0.12, 0.88, 0.32, 0.86, cc)
    mesh_obj("Carroceria_Ventanas", bm, M["vidrio"], col, body, smooth=None, recalc=False)
    # banda del parabrisas (calcomanía sobre el vidrio)
    fr = cara((b["xf"], -b["y"], b["z"]), (b["xf"], b["y"], b["z"]), (t["xf"], -t["y"], t["z"]), (t["xf"], t["y"], t["z"]))
    nrm_f = Vector((t["z"] - b["z"], 0, b["xf"] - t["xf"])).normalized()
    bm = bmesh.new()
    q = [fr(0.10, 0.80), fr(0.90, 0.80), fr(0.90, 0.92), fr(0.10, 0.92)]
    vs = [bm.verts.new(p + nrm_f * 0.0019) for p in q]
    fb = bm.faces.new(vs)
    uvl = bm.loops.layers.uv.new("UVMap")
    for lp, uv in zip(fb.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        lp[uvl].uv = uv
    mesh_obj("Banda_Parabrisas", bm, material_imagen("Banda_Parabrisas", "banda_parabrisas.png", emis=0.0),
             col, body, smooth=None, recalc=False)
    # redes de ventana (lado del conductor y acompañante)
    bm = bmesh.new()
    for s in (1, -1):
        P_ = lados[s]
        nrm = Vector((0, s * (t["z"] - b["z"]), (b["y"] - t["y"]))).normalized()
        u0, u1, v0, v1 = 0.10, 0.57, 0.28, 0.83
        for k in range(7):
            u = u0 + (u1 - u0) * k / 6
            add_beam(bm, P_(u, v0) + nrm * 0.0022, P_(u, v1) + nrm * 0.0022, 0.0012, 0.0008, nrm)
        for k in range(5):
            v = v0 + (v1 - v0) * k / 4
            add_beam(bm, P_(u0, v) + nrm * 0.0029, P_(u1, v) + nrm * 0.0029, 0.0012, 0.0008, nrm)
        add_beam(bm, P_(u0, v1) + nrm * 0.0026, P_(u1, v1) + nrm * 0.0026, 0.0035, 0.0015, nrm)   # varilla superior
    mesh_obj("Red_Ventana", bm, M["negro_mate"], col, body, smooth=None)

    # ------------------------------------------------------------------ capó: bulto, soplador, rejillas, pasadores
    ang = atan(0.0195 / 0.202)
    Ry = R_Y(ang)
    bm = bmesh.new()
    xb0, xb1 = 0.098, 0.212
    add_box(bm, (xb1 - xb0, 0.112, 0.020), ((xb0 + xb1) / 2, 0, capo((xb0 + xb1) / 2) + 0.004), Ry)
    bulto = mesh_obj("Capo_Bulto", bm, L, col, body, smooth=None)
    bv = bulto.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.0055
    bv.segments = 6
    apply_modifiers(bulto)
    resmooth(bulto, 35)
    uv_livery(bulto)
    xs_c = 0.165
    zb_c = capo(xs_c) + 0.014
    bm = bmesh.new()
    add_box(bm, (0.066, 0.060, 0.004), (xs_c, 0, zb_c + 0.002), Ry)                      # base
    mesh_obj("Soplador_Base", bm, M["negro_mate"], col, body, smooth=None)
    bm = bmesh.new()
    Mc = M_T((xs_c, 0, zb_c)) @ Ry
    Myz = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))              # prisma (y, z) a lo largo de X
    perfil_c = round_poly([(-0.025, 0.004), (0.025, 0.004), (0.025, 0.026), (-0.025, 0.026)], 0.0095, 6)
    add_prism(bm, perfil_c, -0.029, 0.029, Mc @ Myz)                                    # carcasa de lóbulos
    perfil_n = round_poly([(-0.0265, 0.0035), (0.0265, 0.0035), (0.0265, 0.0275), (-0.0265, 0.0275)], 0.0105, 6)
    for k in range(8):                                                                   # nervios
        x0 = -0.0245 + 0.007 * k
        add_prism(bm, perfil_n, x0, x0 + 0.0016, Mc @ Myz)
    sop = mesh_obj("Soplador", bm, M["rojo_anodizado"], col, body, smooth=35)
    bm = bmesh.new()                                                                     # tapas pulidas
    perfil_t = round_poly([(-0.0262, 0.0038), (0.0262, 0.0038), (0.0262, 0.0272), (-0.0262, 0.0272)], 0.0102, 6)
    for x0 in (-0.0315, 0.0285):
        add_prism(bm, perfil_t, x0, x0 + 0.003, Mc @ Myz)
    for x0 in (-0.0320, 0.0310):                                                         # tornillos de las tapas
        for (yy, zz) in ((-0.019, 0.008), (0.019, 0.008), (-0.019, 0.023), (0.019, 0.023)):
            add_cyl(bm, 0.0013, 0.0012, Mc @ M_T((x0 + (0.0006 if x0 > 0 else 0.0), yy, zz)) @ AXIS_ROT['X'], 10)
    tp = mesh_obj("Soplador_Tapas", bm, M["alu_pulido"], col, body, smooth=35)
    bv = tp.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.0006
    bv.segments = 2
    bv.limit_method = 'ANGLE'
    apply_modifiers(tp)
    bm = bmesh.new()                                                                     # poleas (eje X) y correa
    Mp = Mc @ M_T((0.0355, 0, 0))
    add_cyl(bm, 0.0042, 0.006, Mc @ M_T((0.0335, 0, 0.016)) @ AXIS_ROT['X'], 20)      # eje del rotor
    add_cyl(bm, 0.0085, 0.006, Mp @ M_T((0, 0, 0.016)) @ AXIS_ROT['X'], 32)
    add_cyl(bm, 0.0060, 0.006, Mp @ M_T((0, 0, -0.010)) @ AXIS_ROT['X'], 28)
    add_cyl(bm, 0.0030, 0.009, Mp @ M_T((0.0015, 0, 0.016)) @ AXIS_ROT['X'], 16)     # tuerca del eje
    mesh_obj("Soplador_Poleas", bm, M["cromo_pl"], col, body)
    bm = bmesh.new()
    banda_correa(bm, Mp, (0.0, 0.016), 0.0085, (0.0, -0.010), 0.0060, 0.0012, 0.0050)
    mesh_obj("Soplador_Correa", bm, M["goma"], col, body, smooth=None)
    bm = bmesh.new()                                                                     # toma "atrapa insectos"
    top_c = Mc @ Vector((0, 0, 0.026))
    prof_t = [(-0.020, 0.0), (0.024, 0.0), (0.024, 0.026), (0.014, 0.026), (-0.020, 0.010)]
    Mt = Mc @ M_T((0, 0, 0.026))
    add_prism(bm, prof_t, -0.020, 0.020, Mt @ R_X(pi / 2))
    toma = mesh_obj("Soplador_Toma", bm, M["cromo_pl"], col, body, smooth=None)
    bv = toma.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.0015
    bv.segments = 3
    apply_modifiers(toma)
    bm = bmesh.new()                                                                     # malla de la toma
    for k in range(6):
        add_box(bm, (0.0008, 0.036, 0.0006), Mt @ Vector((0.0242, 0, 0.003 + 0.004 * k)), Ry)
    for k in range(7):
        add_box(bm, (0.0008, 0.0006, 0.022), Mt @ Vector((0.0242, -0.018 + 0.006 * k, 0.013)), Ry)
    add_box(bm, (0.0004, 0.038, 0.024), Mt @ Vector((0.0225, 0, 0.013)), Ry)
    add_box(bm, (0.044, 0.046, 0.0030), Mt @ Vector((0.002, 0, -0.0005)), Ry)              # adaptador
    mesh_obj("Soplador_Malla", bm, M["negro_mate"], col, body, smooth=None)
    bm = bmesh.new()                                                                     # rejillas del capó
    for s in (1, -1):
        for k in range(5):
            x = 0.118 + 0.011 * k
            add_box(bm, (0.0045, 0.040, 0.0018), (x, s * 0.112, capo(x) + 0.0012), Ry @ R_Y(-0.35))
    mesh_obj("Capo_Rejillas", bm, M["negro_mate"], col, body, smooth=None)
    hwb = Herrajes("Carroceria", col, body, M)
    for (x, y) in ((0.268, 0.122), (0.268, -0.122), (0.090, 0.135), (0.090, -0.135)):    # pasadores del capó
        z = capo(x) + 0.0005
        hwb.pasador(Vector((x, y, z)), Vector((x, y, z + 0.006)), 0.0011, "cromo")
        hwb.arandela(Vector((x, y, z)), (0, 0, 1), 0.003, 0.0032)
        hwb.pasador(Vector((x - 0.004, y, z + 0.004)), Vector((x + 0.004, y, z + 0.004)), 0.0005, "cromo")
    hwb.casquillo(Vector((0.0825, 0.0698, capo(0.0825) + 0.0005)), (0, 0, 1), 0.0026, 0.0045, 0.0015)  # pasacable antena
    # ------------------------------------------------------------------ frente: parrilla, faros, parachoques
    xf = 0.2895
    bm = bmesh.new()
    add_box_minmax(bm, (xf - 0.002, -0.090, 0.172), (xf + 0.0035, 0.090, 0.2035))           # marco
    marco = mesh_obj("Parrilla_Marco", bm, M["cromo_pl"], col, body, smooth=None)
    cb = bmesh.new()
    add_box_minmax(cb, (xf - 0.010, -0.084, 0.1755), (xf + 0.010, 0.084, 0.2000))
    cortar(marco, [cutter_obj("cut_parrilla", cb, col)])
    bm = bmesh.new()
    add_box_minmax(bm, (xf - 0.003, -0.085, 0.175), (xf - 0.0015, 0.085, 0.2005))           # fondo
    mesh_obj("Parrilla", bm, M["negro_mate"], col, body, smooth=None)
    bm = bmesh.new()                                                                      # panal de abeja
    rh = 0.0034
    for j in range(7):
        for i in range(-24, 25):
            y = i * rh * 1.5
            z = 0.1775 + j * rh * 1.73 + (rh * 0.866 if i % 2 else 0)
            if abs(y) < 0.081 and z < 0.1985:
                add_cyl_axis(bm, (xf - 0.001, y, z), 'X', rh * 0.86, 0.0022, 6)
    mesh_obj("Parrilla_Celdas", bm, M["gris_metal"], col, body, smooth=None)
    # emblema "L" sobre la parrilla
    bm = bmesh.new()
    add_prism(bm, [(-0.010, -0.007), (0.010, -0.007), (0.010, -0.003), (-0.004, -0.003), (-0.004, 0.007), (-0.010, 0.007)],
              0, 0.0020, M_T((xf - 0.0002, 0, 0.1878)) @ R_Y(pi / 2) @ R_Z(pi / 2))
    mesh_obj("Emblema", bm, M["cromo_pl"], col, body, smooth=None)
    # faros de proyector con luz diurna en "C" y direccional ámbar
    bm_h, bm_l, bm_d, bm_a = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    for s in (1, -1):
        yc = s * 0.116
        add_box_minmax(bm_h, (xf - 0.004, yc - 0.024, 0.181), (xf + 0.003, yc + 0.024, 0.2035))
        for dy in (-0.011, 0.010):
            add_cyl_axis(bm_l, (xf + 0.0035, yc + dy, 0.1925), 'X', 0.0062, 0.0012, 28)
        for (y0, y1, z0, z1) in ((yc - 0.022, yc + 0.022, 0.2005, 0.2023), (yc + s * 0.0205 - 0.0009, yc + s * 0.0205 + 0.0009, 0.183, 0.2023)):
            add_box_minmax(bm_d, (xf + 0.003, min(y0, y1), z0), (xf + 0.0042, max(y0, y1), z1))
        add_box_minmax(bm_a, (xf + 0.003, min(yc - s * 0.022, yc + s * 0.012), 0.1825),
                       (xf + 0.0040, max(yc - s * 0.022, yc + s * 0.012), 0.1845))
    mesh_obj("Faros_Carcasa", bm_h, M["negro_brillo"], col, body, smooth=None)
    mesh_obj("Faros", bm_l, M["led"], col, body)
    mesh_obj("Faros_Diurna", bm_d, M["neon_azul"], col, body, smooth=None)
    mesh_obj("Faros_Direccional", bm_a, M["ambar"], col, body, smooth=None)
    bm = bmesh.new()
    for s in (1, -1):
        for dy in (-0.011, 0.010):
            add_lathe(bm, [(0.0062, -0.001), (0.0072, -0.001), (0.0076, 0.0012), (0.0066, 0.0016)], 28,
                      M_T((xf + 0.0030, s * 0.116 + dy, 0.1925)) @ AXIS_ROT['X'])
    mesh_obj("Faros_Biseles", bm, M["cromo_pl"], col, body)
    # parachoques delantero: viga negra + defensa tubular + barra LED + antiniebla + ganchos
    bm = bmesh.new()
    add_prism(bm, [(-0.112, 0.000), (0.112, 0.000), (0.118, 0.008), (0.118, 0.018), (0.112, 0.022),
                   (-0.112, 0.022), (-0.118, 0.018), (-0.118, 0.008)], xf, xf + 0.016,
              M_T((0, 0, 0.150)) @ Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
    dfn = mesh_obj("Defensas", bm, M["negro_mate"], col, body, smooth=None)
    bv = dfn.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.0015
    bv.segments = 2
    apply_modifiers(dfn)
    xbb = xf + 0.024
    bm = bmesh.new()
    for s in (1, -1):
        add_sweep(bm, [Vector((xf + 0.012, s * 0.072, 0.172)), Vector((xbb, s * 0.072, 0.180)),
                       Vector((xbb, s * 0.070, 0.205))] + arco(Vector((xbb, s * 0.058, 0.205)),
                                                               Vector((xbb, s * 0.070, 0.205)),
                                                               Vector((xbb, s * 0.058, 0.217)), 5)[1:] +
                  [Vector((xbb, s * 0.002, 0.217))], 0.0033, 12)
    add_sweep(bm, [Vector((xbb, -0.068, 0.194)), Vector((xbb, 0.068, 0.194))], 0.0026, 12)
    for s in (1, -1):
        add_sweep(bm, [Vector((xbb, s * 0.068, 0.186)), Vector((xf - 0.0012, s * 0.068, 0.188))], 0.0022, 10)
    mesh_obj("Defensa_Tubular", bm, M["cromo_pl"], col, body, smooth=40)
    bm = bmesh.new()
    add_box_minmax(bm, (xf + 0.014, -0.060, 0.1716), (xf + 0.024, 0.060, 0.1815))
    mesh_obj("Barra_LED_Frontal", bm, M["negro_brillo"], col, body, smooth=None)
    bm = bmesh.new()
    for k in range(12):
        y = -0.055 + 0.010 * k
        add_box_minmax(bm, (xf + 0.0240, y - 0.0035, 0.1740), (xf + 0.0247, y + 0.0035, 0.1800))
    mesh_obj("LED_Frontal", bm, M["led"], col, body, smooth=None)
    bm_f, bm_fl = bmesh.new(), bmesh.new()
    for s in (1, -1):
        add_cyl_axis(bm_f, (xf + 0.0165, s * 0.092, 0.161), 'X', 0.0075, 0.006, 28)
        add_cyl_axis(bm_fl, (xf + 0.0198, s * 0.092, 0.161), 'X', 0.0062, 0.0008, 28)
    mesh_obj("Antiniebla", bm_f, M["negro_brillo"], col, body)
    mesh_obj("Antiniebla_Lente", bm_fl, M["ambar"], col, body)
    bm = bmesh.new()
    for s in (1, -1):
        add_sweep(bm, gancho(Vector((xf + 0.016, s * 0.040, 0.1500)), 0.006), 0.0022, 10)
    mesh_obj("Ganchos_Remolque", bm, M["rojo_anodizado"], col, body, smooth=40)

    # ------------------------------------------------------------------ guardabarros atornillados
    to_y = AXIS_ROT['Y']
    bolts = Herrajes("Guardabarros", col, body, M)
    x_fin = {1: 0.2895, -1: -0.2745}                      # los guardabarros terminan al ras de frente y cola
    for f in (1, -1):
        for s in (1, -1):
            yi, yo = HW - 0.003, HW + 0.024
            prof = [(0.1266, yi), (0.1395, yi), (0.1418, yi + 0.008), (0.1405, yo - 0.003),
                    (0.1375, yo), (0.1266, yo)]
            prof = [(r_, s * y_) for r_, y_ in prof]
            if s < 0:
                prof = prof[::-1]
            bm = bmesh.new()
            add_lathe(bm, prof, 56, M_T((f * XA, 0, ARCO_ZL)) @ to_y, closed=True,
                      a0=radians(-144), a1=radians(-36))
            gf = mesh_obj(f"Guardafango_{'Del' if f > 0 else 'Tras'}_{'Izq' if s > 0 else 'Der'}",
                          bm, M["negro_mate"], col, body, smooth=40)
            cb = bmesh.new()
            add_box_minmax(cb, (x_fin[f] if f > 0 else x_fin[f] - 0.1, -0.3, 0.0),
                           (x_fin[f] + 0.1 if f > 0 else x_fin[f], 0.3, 0.4))
            cortar(gf, [cutter_obj("cut_guardafango", cb, col)])
            resmooth(gf, 40)
            for k in range(8):
                a = radians(-137 + 94 * k / 7)
                p_ = Vector((f * XA + 0.1330 * cos(a), s * (yo + 0.0002), ARCO_ZL - 0.1330 * sin(a)))
                if (p_.x < x_fin[1] - 0.004) and (p_.x > x_fin[-1] + 0.004):
                    bolts.tornillo(p_, (0, s, 0), 0.004, 0.0022, "boton")

    # ------------------------------------------------------------------ costados: espejos, manijas, estribos, escapes
    bm = bmesh.new()
    bm_v = bmesh.new()
    for s in (1, -1):
        base = Vector((0.052, s * 0.144, 0.242))
        add_sweep(bm, [base, base + Vector((-0.002, s * 0.014, 0.007)), base + Vector((-0.004, s * 0.024, 0.011))], 0.0018, 10)
        add_box(bm, (0.012, 0.022, 0.016), base + Vector((-0.008, s * 0.030, 0.014)))
        add_box(bm_v, (0.0006, 0.019, 0.013), base + Vector((-0.0142, s * 0.030, 0.014)))
    esp = mesh_obj("Espejos", bm, M["negro_brillo"], col, body, smooth=None)
    bv = esp.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.003
    bv.segments = 4
    bv.limit_method = 'ANGLE'
    apply_modifiers(esp)
    mesh_obj("Espejos_Luna", bm_v, M["cromo_pl"], col, body, smooth=None)
    bm = bmesh.new()
    for s in (1, -1):
        add_box_minmax(bm, (-0.058, min(s * 0.1584, s * 0.1606), 0.2205), (-0.044, max(s * 0.1584, s * 0.1606), 0.2235))
    mnj = mesh_obj("Manijas", bm, M["cromo_pl"], col, body, smooth=None)
    bv = mnj.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.0007
    bv.segments = 2
    apply_modifiers(mnj)
    bm = bmesh.new()                                                                       # estribos tubulares
    for s in (1, -1):
        yy = s * 0.172
        add_sweep(bm, [Vector((0.072, s * 0.150, 0.162)), Vector((0.068, yy, 0.150)), Vector((-0.068, yy, 0.150)),
                       Vector((-0.072, s * 0.150, 0.162))], 0.0042, 14)
        add_box_minmax(bm, (-0.060, min(yy, s * 0.160) - 0.0005, 0.1445), (0.060, max(yy, s * 0.160) + 0.0005, 0.1475))
    mesh_obj("Estribos", bm, M["negro_mate"], col, body, smooth=40)
    bm = bmesh.new()                                                                       # escapes verticales (tubo hueco)
    bm_s, bm_b = bmesh.new(), bmesh.new()
    XE, YE, ZE = -0.142, 0.118, 0.2150
    for s in (1, -1):
        p0 = Vector((XE, s * YE, ZE))
        add_lathe(bm, [(0.0050, 0.0), (0.0060, 0.0), (0.0060, 0.132), (0.0050, 0.132)], 28, M_T(p0))
        add_lathe(bm_s, [(0.0059, 0.030), (0.0071, 0.030), (0.0071, 0.095), (0.0059, 0.095)], 28, M_T(p0))   # protector
        for zc in (0.034, 0.091):                                                          # abrazaderas
            add_lathe(bm_b, [(0.0070, zc - 0.002), (0.0077, zc - 0.002), (0.0077, zc + 0.002), (0.0070, zc + 0.002)],
                      24, M_T(p0))
        add_lathe(bm_b, [(0.0059, -0.0005), (0.0100, -0.0005), (0.0100, 0.0020), (0.0059, 0.0040)], 28, M_T(p0))  # brida
    esc = mesh_obj("Escapes_Laterales", bm, M["cromo_pl"], col, body, smooth=30)
    cb = bmesh.new()
    for s in (1, -1):
        add_box(cb, (0.03, 0.03, 0.03), Vector((XE - 0.004, s * YE, ZE + 0.132 + 0.0105)), R_Y(0.6))   # corte en bisel
    cortar(esc, [cutter_obj("cut_escape", cb, col)])
    resmooth(esc, 30)
    prot = mesh_obj("Escapes_Protector", bm_s, M["negro_mate"], col, body, smooth=30)
    cb = bmesh.new()                                                                       # ranuras del protector
    for s in (1, -1):
        for k in range(5):
            for j in range(10):
                a = 2 * pi * j / 10 + (0.3 if k % 2 else 0.0)
                c_ = Vector((XE + 0.0066 * cos(a), s * YE + 0.0066 * sin(a), ZE + 0.040 + 0.011 * k))
                add_box(cb, (0.004, 0.0020, 0.0070), c_, R_Z(a))
    cortar(prot, [cutter_obj("cut_protector", cb, col)])
    resmooth(prot, 30)
    mesh_obj("Escapes_Abrazaderas", bm_b, M["alu_pulido"], col, body, smooth=30)

    # ------------------------------------------------------------------ caja: pasos de rueda internos, barra antivuelco
    bm = bmesh.new()                                                                       # rieles de la caja
    for s in (1, -1):
        y = s * 0.1560
        add_sweep(bm, [Vector((-0.112, y, 0.2418)), Vector((-0.255, y, 0.2418))], 0.0021, 12)
        for x in (-0.116, -0.183, -0.251):
            add_cyl_axis(bm, (x, y, 0.2405), 'Z', 0.0030, 0.0040, 16)
    mesh_obj("Caja_Rieles", bm, M["cromo_pl"], col, body, smooth=40)
    bm = bmesh.new()                                                                       # amarres en el piso de la caja
    for x in (-0.172, -0.245):
        for s in (1, -1):
            add_lathe(bm, [(0.0020, 0.0), (0.0040, 0.0), (0.0040, 0.0012), (0.0020, 0.0012)], 16,
                      M_T((x, s * 0.140, 0.2149)))
            add_sweep(bm, gancho(Vector((x, s * 0.140, 0.2161)), -0.0030, 8), 0.0009, 8)
    mesh_obj("Caja_Amarres", bm, M["rojo_anodizado"], col, body, smooth=40)
    bm = bmesh.new()                                                                       # tapón de combustible
    add_lathe(bm, [(0.0001, 0.0), (0.0085, 0.0), (0.0085, 0.0008), (0.0072, 0.0018), (0.0001, 0.0018)], 32,
              M_T((-0.131, 0.1590, 0.221)) @ R_X(-pi / 2))
    for k in range(6):
        a = 2 * pi * k / 6
        add_box(bm, (0.0012, 0.0012, 0.0012), Vector((-0.131 + 0.0062 * cos(a), 0.1606, 0.221 + 0.0062 * sin(a))))
    mesh_obj("Tapon_Combustible", bm, M["cromo_pl"], col, body)
    xr_ = -0.122
    bm = bmesh.new()
    for s in (1, -1):
        add_sweep(bm, [Vector((xr_, s * 0.128, 0.216)), Vector((xr_, s * 0.128, 0.300))] +
                  arco(Vector((xr_, s * 0.110, 0.300)), Vector((xr_, s * 0.128, 0.300)), Vector((xr_, s * 0.110, 0.318)), 5)[1:] +
                  [Vector((xr_, 0.0, 0.318))], 0.0042, 14)
        add_sweep(bm, [Vector((xr_, s * 0.128, 0.290)), Vector((-0.240, s * 0.1545, 0.2425))], 0.0034, 12)  # tirante al riel
    add_sweep(bm, [Vector((xr_, -0.124, 0.232)), Vector((xr_, 0.124, 0.296))], 0.0030, 12)                  # diagonal
    mesh_obj("Barra_Antivuelco", bm, M["negro_brillo"], col, body, smooth=40)
    bm_c, bm_l = bmesh.new(), bmesh.new()
    for y in (-0.072, -0.024, 0.024, 0.072):
        add_cyl_axis(bm_c, (xr_ + 0.006, y, 0.3270), 'X', 0.0105, 0.012, 28)
        add_cyl_axis(bm_c, (xr_ + 0.000, y, 0.3190), 'Z', 0.0025, 0.008, 12)
        add_cyl_axis(bm_l, (xr_ + 0.0124, y, 0.3270), 'X', 0.0086, 0.0012, 28)
    mesh_obj("Focos_Antivuelco", bm_c, M["negro_brillo"], col, body)
    mesh_obj("Focos_Antivuelco_LED", bm_l, M["led"], col, body)

    # ------------------------------------------------------------------ alerón trasero (fibra de carbono)
    cuerda, x_bs, z_bs, semi = 0.070, -0.266, 0.330, 0.1490

    def naca(xx):
        """Espesor y curvatura del perfil (NACA 4412 aproximado, montado invertido)."""
        yt = 0.12 / 0.2 * (0.2969 * xx ** 0.5 - 0.126 * xx - 0.3516 * xx ** 2 + 0.2843 * xx ** 3 - 0.1015 * xx ** 4)
        yc = 0.04 / 0.16 * (2 * 0.4 * xx - xx * xx) if xx < 0.4 else 0.04 / 0.36 * ((1 - 0.8) + 2 * 0.4 * xx - xx * xx)
        return yt, yc

    def ala_sup(x):
        """Altura de la cara superior (intradós del perfil invertido) en la posición x."""
        xx = min(max((x_bs - x) / cuerda, 0.0), 1.0)
        yt, yc = naca(xx)
        return z_bs + cuerda * (-yc + yt)

    up, low = [], []
    for k in range(25):
        xx = (1 - cos(pi * k / 24)) / 2
        yt, yc = naca(xx)
        up.append((x_bs - cuerda * xx, z_bs + cuerda * (-yc + yt)))
        low.append((x_bs - cuerda * xx, z_bs + cuerda * (-yc - yt)))
    loop = up + list(reversed(low))[1:-1]
    bm = bmesh.new()
    Mxz = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    add_prism(bm, loop, -semi, semi, Mxz)
    uv_planar(bm, "xy", 0.03)
    mesh_obj("Aleron", bm, M["carbono"], col, body, smooth=25)
    bm = bmesh.new()                                                                       # gurney (filo neón)
    x_te = x_bs - cuerda
    add_box_minmax(bm, (x_te - 0.0004, -semi, z_bs - 0.0010), (x_te + 0.0012, semi, z_bs + 0.0060))
    mesh_obj("Aleron_Gurney", bm, M["neon_verde"], col, body, smooth=None)
    bm = bmesh.new()                                                                       # aletas laterales
    prof_e = [(-0.250, 0.334), (-0.256, 0.304), (-0.282, 0.292), (-0.339, 0.300), (-0.339, 0.346), (-0.262, 0.346)]
    for s in (1, -1):
        add_prism(bm, prof_e, s * (semi - 0.0005), s * (semi + 0.0015), Mxz)
    aletas = mesh_obj("Aleron_Aletas", bm, L, col, body, smooth=None)
    bv = aletas.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.0006
    bv.segments = 2
    apply_modifiers(aletas)
    uv_livery(aletas)
    bm = bmesh.new()                                                                       # cuellos de cisne
    for s in (1, -1):
        y = s * 0.090
        path = [Vector((-0.2655, y, 0.2440)), Vector((-0.2630, y, 0.272)), Vector((-0.2575, y, 0.304)),
                Vector((-0.2560, y, 0.324)), Vector((-0.2600, y, 0.3355))]
        path += [Vector((x, y, ala_sup(x) + 0.0024)) for x in (-0.2680, -0.2740, -0.2810, -0.2880)]
        add_sweep(bm, path, 0.0026, 12)
        add_box_minmax(bm, (-0.2715, y - 0.006, 0.2392), (-0.2595, y + 0.006, 0.2440))     # base en la compuerta
        add_box(bm, (0.016, 0.010, 0.0015), Vector((-0.282, y, ala_sup(-0.282) + 0.0004)),
                R_Y(atan2(ala_sup(-0.274) - ala_sup(-0.290), 0.016)))                         # placa sobre el ala
    mesh_obj("Aleron_Soportes", bm, M["alu_pulido"], col, body, smooth=40)

    # ------------------------------------------------------------------ cola: calaveras LED, placa, parachoques
    xt = -0.2745
    bm_c, bm_s = bmesh.new(), bmesh.new()
    for s in (1, -1):
        add_box_minmax(bm_c, (xt - 0.0025, min(s * 0.137, s * 0.153), 0.178), (xt + 0.001, max(s * 0.137, s * 0.153), 0.226))
        for k in range(5):
            z = 0.1815 + 0.0085 * k
            add_box_minmax(bm_s, (xt - 0.0032, min(s * 0.139, s * 0.151), z), (xt - 0.0024, max(s * 0.139, s * 0.151), z + 0.0055))
    add_box_minmax(bm_c, (-0.0760, -0.030, 0.3112), (-0.0660, 0.030, 0.3165))             # 3a luz de freno (techo)
    add_box_minmax(bm_s, (-0.0766, -0.027, 0.3123), (-0.0758, 0.027, 0.3155))
    mesh_obj("Calaveras_Carcasa", bm_c, M["negro_brillo"], col, body, smooth=None)
    mesh_obj("Calaveras", bm_s, M["stop"], col, body, smooth=None)
    bm = bmesh.new()
    q = [Vector((xt - 0.0012, 0.020, 0.1655)), Vector((xt - 0.0012, -0.020, 0.1655)),
         Vector((xt - 0.0012, -0.020, 0.1855)), Vector((xt - 0.0012, 0.020, 0.1855))]
    fb = bm.faces.new([bm.verts.new(p) for p in q])
    uvl = bm.loops.layers.uv.new("UVMap")
    for lp, uv in zip(fb.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        lp[uvl].uv = uv
    mesh_obj("Placa_Matricula", bm, material_imagen("Placa", "placa.png", rough=0.4), col, body, smooth=None,
             recalc=False)
    bm = bmesh.new()
    add_prism(bm, [(-0.120, 0.000), (0.120, 0.000), (0.120, 0.016), (-0.120, 0.016)], xt - 0.014, xt,
              M_T((0, 0, 0.148)) @ Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
    add_box_minmax(bm, (xt - 0.024, -0.010, 0.149), (xt - 0.013, 0.010, 0.159))          # enganche
    dt = mesh_obj("Defensa_Trasera", bm, M["negro_mate"], col, body, smooth=None)
    bv = dt.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.0012
    bv.segments = 2
    apply_modifiers(dt)
    bm = bmesh.new()
    for s in (1, -1):
        add_sweep(bm, gancho(Vector((xt - 0.016, s * 0.075, 0.1490)), 0.006), 0.0022, 10)
    add_cyl_axis(bm, (xt - 0.0195, 0, 0.154), 'Y', 0.0016, 0.024, 12)                      # pasador del enganche
    mesh_obj("Ganchos_Traseros", bm, M["rojo_anodizado"], col, body, smooth=40)

    # ------------------------------------------------------------------ techo: barra LED y marcadores ámbar
    bm = bmesh.new()
    add_box_minmax(bm, (-0.012, -0.104, 0.3135), (0.004, 0.104, 0.3245))
    for s in (1, -1):
        add_box_minmax(bm, (-0.009, s * 0.090 - 0.003, 0.3110), (-0.001, s * 0.090 + 0.003, 0.3140))
    lb = mesh_obj("Barra_Luces", bm, M["negro_brillo"], col, body, smooth=None)
    bv = lb.modifiers.new("Bevel", 'BEVEL')
    bv.width = 0.0015
    bv.segments = 3
    apply_modifiers(lb)
    bm = bmesh.new()
    for k in range(16):
        y = -0.094 + 0.0125 * k
        add_box_minmax(bm, (0.0040, y - 0.0048, 0.3155), (0.0046, y + 0.0048, 0.3225))
    mesh_obj("LED_Techo", bm, M["led"], col, body, smooth=None)
    bm = bmesh.new()                                                                       # marcadores sobre la barra
    for k in range(5):
        y = -0.072 + 0.036 * k
        add_lathe(bm, [(0.0001, 0.0), (0.0034, 0.0), (0.0031, 0.0016), (0.0001, 0.0022)], 16,
                  M_T((-0.004, y, 0.3243)) @ R_Y(0.35))
    mesh_obj("Marcadores_Ambar", bm, M["ambar"], col, body)

    # ------------------------------------------------------------------ neón bajo la carrocería
    bm_r, bm_v = bmesh.new(), bmesh.new()
    for s in (1, -1):
        add_sweep(bm_r, [Vector((0.094, s * 0.1605, 0.1557)), Vector((-0.094, s * 0.1605, 0.1557))], 0.0016, 10)
    add_sweep(bm_v, [Vector((xf + 0.004, -0.085, 0.1486)), Vector((xf + 0.004, 0.085, 0.1486))], 0.0016, 10)
    add_sweep(bm_v, [Vector((xt - 0.003, -0.085, 0.1466)), Vector((xt - 0.003, 0.085, 0.1466))], 0.0016, 10)
    mesh_obj("Neon_Lateral", bm_r, M["neon_rosa"], col, body)
    mesh_obj("Neon_Frente_Cola", bm_v, M["neon_verde"], col, body)
    hwb.build()
    bolts.build()
    return body


# ---------------------------------------------------------------------------
# Estudio: piso, luces y cámaras
# ---------------------------------------------------------------------------
def look_at(o, target):
    d = Vector(target) - o.location
    o.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()


def build_studio(C, M):
    col = C["studio"]
    sc = bpy.context.scene
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=6.0)
    piso = mesh_obj("Piso", bm, M["piso"], col, smooth=None, recalc=False)
    piso.is_shadow_catcher = True        # sólo recibe sombras: fondo blanco limpio

    def area(name, loc, target, energy, size):
        ld = bpy.data.lights.new(name, 'AREA')
        ld.energy = energy
        ld.size = size
        o = bpy.data.objects.new(name, ld)
        col.objects.link(o)
        o.location = loc
        look_at(o, target)
        return o
    key = area("Luz_Principal", (0.9, -1.0, 1.5), (0, 0, 0.1), 85, 1.2)
    key.visible_glossy = False           # evita que los vidrios y el capó se "quemen"
    area("Luz_Brillo", (0.3, -0.4, 1.6), (0, 0, 0.1), 25, 0.5)
    area("Luz_Relleno", (-1.2, 0.7, 0.9), (0, 0, 0.1), 35, 1.5)
    rim = area("Luz_Contra", (-0.9, -1.0, 0.6), (0, 0, 0.15), 30, 0.8)
    rim.visible_glossy = False

    # paneles oscuros que sólo se ven en los reflejos (dan contraste al cromo)
    for nm, loc, rot, sz in (("Panel_Reflejo_1", (0.0, 1.4, 0.7), (radians(70), 0, pi), 1.6),
                             ("Panel_Reflejo_2", (-1.5, -0.2, 0.6), (0, radians(-70), 0), 1.4),
                             ("Panel_Reflejo_3", (0.0, 0.0, 1.9), (0, 0, 0), 0.9)):
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=sz / 2)
        pc = mesh_obj(nm, bm, M["panel"], col, smooth=None, recalc=False)
        pc.location = loc
        pc.rotation_euler = rot
        pc.visible_camera = False
        pc.visible_shadow = False
        pc.visible_diffuse = False
        pc.visible_transmission = False

    # mundo: ilumina suave, pero la cámara ve un fondo blanco puro
    w = sc.world or bpy.data.worlds.new("Mundo")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    lp = nt.nodes.new("ShaderNodeLightPath")
    amb = nt.nodes.new("ShaderNodeBackground")
    amb.inputs[0].default_value = (0.92, 0.94, 1.0, 1)
    amb.inputs[1].default_value = 0.30
    white = nt.nodes.new("ShaderNodeBackground")
    white.inputs[0].default_value = (1, 1, 1, 1)
    white.inputs[1].default_value = 1.0
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(amb.outputs[0], mix.inputs[1])
    nt.links.new(white.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])

    cams = {}
    def cam(name, loc, target, lens=50, ortho=None):
        cd = bpy.data.cameras.new(name)
        cd.lens = lens
        cd.clip_start = 0.01
        if ortho:
            cd.type = 'ORTHO'
            cd.ortho_scale = ortho
        o = bpy.data.objects.new(name, cd)
        col.objects.link(o)
        o.location = loc
        look_at(o, target)
        cams[name] = o
        return o
    cam("Cam_Frontal_34", (0.95, -0.80, 0.34), (0.0, 0.0, 0.135), 55)
    cam("Cam_Chasis_34", (0.62, -0.78, 0.78), (0.0, 0.0, 0.08), 50)
    cam("Cam_Superior", (0.0, 0.0, 1.6), (0.0, 0.0, 0.0), 50, ortho=0.84)
    cams["Cam_Superior"].rotation_euler = (0, 0, 0)
    cam("Cam_Motor", (-0.30, 0.34, 0.40), (-0.02, -0.01, 0.10), 50)
    el = cam("Cam_Electronica", (0.160, 0.115, 0.295), (0.114, 0.044, 0.068), 42)
    el.data.dof.use_dof = True
    el.data.dof.focus_distance = (Vector((0.160, 0.115, 0.295)) - Vector((0.112, 0.040, 0.078))).length
    el.data.dof.aperture_fstop = 5.6
    ba = cam("Cam_Brazo", (0.315, 0.010, 0.215), (0.200, 0.096, 0.068), 42)
    ba.data.dof.use_dof = True
    ba.data.dof.focus_distance = (Vector((0.315, 0.010, 0.215)) - Vector((0.200, 0.095, 0.065))).length
    ba.data.dof.aperture_fstop = 5.6
    mg = cam("Cam_Mangueta", (0.330, 0.285, 0.150), (0.198, 0.140, 0.090), 50)   # renderizar sin ruedas
    mg.data.dof.use_dof = True
    mg.data.dof.focus_distance = (Vector((0.330, 0.285, 0.150)) - Vector((0.200, 0.150, 0.090))).length
    mg.data.dof.aperture_fstop = 5.6
    dr = cam("Cam_Direccion", (0.205, -0.150, 0.175), (0.150, -0.020, 0.098), 45)
    dr.data.dof.use_dof = True
    dr.data.dof.focus_distance = (Vector((0.205, -0.150, 0.175)) - Vector((0.150, -0.025, 0.100))).length
    dr.data.dof.aperture_fstop = 5.6
    rd = cam("Cam_Rueda", (0.450, 0.520, 0.190), (0.200, 0.195, 0.088), 55)
    rd.data.dof.use_dof = True
    rd.data.dof.focus_distance = (Vector((0.450, 0.520, 0.190)) - Vector((0.205, 0.235, 0.090))).length
    rd.data.dof.aperture_fstop = 8.0
    fr = cam("Cam_Frente_Suspension", (0.80, 0.0, 0.25), (0.20, 0.0, 0.115), 55)
    sus = cam("Cam_Suspension", (0.315, 0.215, 0.345), (0.165, 0.045, 0.112), 45)
    sus.data.dof.use_dof = True
    sus.data.dof.focus_distance = (Vector((0.315, 0.215, 0.345)) - Vector((0.195, 0.055, 0.135))).length
    sus.data.dof.aperture_fstop = 5.6
    det = cam("Cam_Detalle_Motor", (0.150, 0.330, 0.350), (-0.050, -0.020, 0.100), 45)
    det.data.dof.use_dof = True
    det.data.dof.focus_distance = (Vector((0.150, 0.330, 0.350)) - Vector((-0.040, -0.020, 0.125))).length
    det.data.dof.aperture_fstop = 4.0
    tr = cam("Cam_Transmision", (0.215, 0.135, 0.255), (0.108, -0.012, 0.074), 42)   # cardán, freno, salidas
    tr.data.dof.use_dof = True
    tr.data.dof.focus_distance = (Vector((0.215, 0.135, 0.255)) - Vector((0.108, -0.012, 0.076))).length
    tr.data.dof.aperture_fstop = 6.3
    sc.camera = cams["Cam_Frontal_34"]

    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 96
    try:
        sc.cycles.use_denoising = True
    except Exception:
        pass
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 1000
    sc.view_settings.view_transform = 'Standard'
    sc.unit_settings.system = 'METRIC'
    return cams


# Piezas que ya tienen su propio acabado o que no deben biselarse
NO_BEVEL = ("Herraje_", "Palier_", "Varilla_Empuje_Rotulas", "Bieleta_Rotulas", "Varilla_Direccion",
            "Carroceria_", "Escape_Sintonizado", "Tanque_Combustible", "Filtro_Espuma",
            "Servo_Etiqueta", "Caja_Receptor_Etiqueta",
            # carrocería LOCURA: piezas con UV de pintura, emisivas, láminas o con bisel propio
            "Capo_Bulto", "Aleron", "Red_Ventana", "Neon_", "LED_", "Banda_", "Placa_Matricula",
            "Parrilla_Celdas", "Escapes_", "Barra_Antivuelco", "Guardafango_", "Soplador", "Defensa",
            "Estribos", "Caja_Rieles", "Caja_Amarres", "Calaveras", "Faros", "Marcadores_", "Espejos",
            "Manijas", "Tapon_", "Focos_Antivuelco", "Ganchos_", "Emblema", "Barra_Luces")
FINE_BEVEL = ("Motor_Culata", "Motor_Tornillos", "Motor_Bujia", "Carburador", "Servo_Tornillos",
              "Chasis_Tornillos", "Escape_Ganchos", "Tanque_Bisagra", "Tanque_Niples", "Volante_Motor",
              "Transmision_Anillo", "Filtro_Abrazadera", "Escape_Abrazadera", "Pasadores", "Tensor",
              "Varilla", "Bieleta", "Escape_Toma", "Caja_Receptor_Pasadores")


def finish_details(C):
    """Bisela todas las piezas duras para que las aristas atrapen la luz."""
    for key in ("body", "chasis", "susp", "motor", "elec"):
        for o in list(C[key].all_objects):
            if o.type != 'MESH' or o.data.users > 1 or o.name.startswith(NO_BEVEL) or "Resorte" in o.name:
                continue
            w = 0.00035 if o.name.startswith(FINE_BEVEL) else 0.0008
            bevel_finish(o, w, 2 if w < 0.0005 else 3, 30)


# ---------------------------------------------------------------------------
# Verificación de interferencias (para usar desde la consola de Blender)
# ---------------------------------------------------------------------------
def pares_criticos():
    """Pares de piezas que NUNCA deben tocarse (las uniones a propósito se excluyen)."""
    pares = []
    for ej in ("Del", "Tras"):
        for lado in ("Izq", "Der"):
            nm = f"{ej}_{lado}"
            pares += [(f"Varilla_Empuje_{nm}", f"Brazo_Superior_{nm}"),
                      (f"Varilla_Empuje_{nm}", f"Palier_{nm}"),
                      (f"Varilla_Empuje_Rotulas_{nm}", f"Brazo_Superior_{nm}"),
                      (f"Palier_{nm}", f"Brazo_Superior_{nm}"),
                      (f"Palier_{nm}", f"Brazo_Inferior_{nm}"),
                      (f"Amort_{nm}_Resorte", f"Balancin_{nm}_Malla"),
                      (f"Llanta_{nm}", f"Brazo_Superior_{nm}"),
                      (f"Llanta_{nm}", "Carroceria_Casco"),
                      (f"Llanta_{nm}", f"Guardafango_{ej}_{lado}"),
                      (f"Llanta_{nm}", "Defensas"),
                      (f"Llanta_{nm}", "Estribos"),
                      (f"Llanta_{nm}", "Defensa_Trasera" if ej == "Tras" else "Defensa_Tubular"),
                      (f"Rin_{nm}", f"Mangueta_{nm}_Malla"),
                      (f"Rin_{nm}", f"Brazo_Inferior_{nm}"),
                      (f"Rin_{nm}", f"Brazo_Superior_{nm}"),
                      (f"Balancin_{nm}_Malla", "Postes_Carroceria")]
            if ej == "Del":
                pares += [(f"Bieleta_Direccion_{lado}", f"Brazo_Superior_{nm}"),
                          (f"Bieleta_Direccion_{lado}", f"Palier_{nm}"),
                          (f"Bieleta_Rotulas_{lado}", f"Brazo_Superior_{nm}"),
                          (f"Llanta_{nm}", f"Brazo_Inferior_{nm}"),
                          (f"Llanta_{nm}", "Parachoques_Del")]
    pares += [("Varilla_Direccion", "Bieleta_Rotulas_Der"), ("Varilla_Direccion", "Bieleta_Direccion_Der")]
    return pares


def verificar_interferencias(recorridos=(-0.026, 0.0, 0.026), direcciones=(-0.42, 0.0, 0.42), pares=None):
    """Mueve los controles por todas las combinaciones y devuelve los pares que se cruzan."""
    from mathutils.bvhtree import BVHTree
    O = bpy.data.objects
    pares = pares or pares_criticos()
    ctrls = [O[f"Control_Suspension_{nm}"] for nm in ("Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der")]
    st = O["Control_Direccion"]
    guard = [(c, c.location.z) for c in ctrls] + [(st, st.rotation_euler.z)]
    hallazgos = []
    def tree(o, dg):
        oe = o.evaluated_get(dg)
        me = oe.to_mesh()
        mw = oe.matrix_world
        t = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
        oe.to_mesh_clear()
        return t
    for h in recorridos:
        for d in direcciones:
            for c in ctrls:
                c.location.z = h
            st.rotation_euler.z = d
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            cache = {}
            for a, b in pares:
                if a not in O or b not in O:
                    continue
                for n_ in (a, b):
                    if n_ not in cache:
                        cache[n_] = tree(O[n_], dg)
                if cache[a].overlap(cache[b]):
                    hallazgos.append((round(h * 1000), round(d, 2), a, b))
    for c, v in guard[:-1]:
        c.location.z = v
    st.rotation_euler.z = guard[-1][1]
    bpy.context.view_layer.update()
    return hallazgos


# ---------------------------------------------------------------------------
# Paquete para simulador: colisiones, masas, centro de gravedad, puntos y curvas
# ---------------------------------------------------------------------------
# Densidades en kg/m³ por material. Las marcadas como "efectiva" no son del
# material macizo: representan una pieza hueca o con aire (ajustables).
DENSIDADES = {
    "Plastico_Negro": 1150, "Plastico_Gris": 1150, "Silicona_Escape": 1200, "Etiqueta": 1150,
    "Termoencogible_Bateria": 2400,           # efectiva: pilas NiMH dentro del termoencogible
    "Aluminio_Chasis": 2700, "Aluminio_Anodizado": 2700, "Aluminio_Fundido": 2700, "Culata_Titanio": 2700,
    "Acero_Oscuro": 7850, "Cromo": 7850, "Rin_Negro_Cromado": 1150,
    "Caucho_Llanta": 250,                     # efectiva: carcasa de caucho + inserto de espuma
    "Tanque_Translucido": 380,                # efectiva: tanque de polietileno con media carga
    "Manguera_Combustible": 1100, "Espuma_Filtro": 60, "Cable_Rojo": 1300, "Cable_Blanco": 1300,
    "Pintura_Carroceria": 1200, "Pintura_Franjas": 1200, "Vinilo_Franjas": 1200, "Vidrio_Polarizado": 1200,
    "Faro": 1200, "Stop": 1200, "Ceramica_Bujia": 3000,
    "Aluminio_Verde": 2810, "Nylon_Amarillo": 1150, "Resorte_Azul": 7850, "Aluminio_Amarillo": 2700,
    "Uretano_Tope": 1200,
    "Compuesto_Gris_Titanio": 1400,           # nylon con fibra (aspecto metálico)
    # carrocería LOCURA (accesorios de plástico inyectado salvo donde se indica)
    "Pintura_Livery": 1200, "Plastico_Negro_Mate": 1150, "Plastico_Negro_Brillo": 1150,
    "Plastico_Cromado": 1150, "Aluminio_Pulido": 2700, "Gris_Metalico": 1150, "Goma_Correa": 1200,
    "Aluminio_Rojo": 2700, "Recubrimiento_Caja": 1150, "LED_Blanco": 1200, "Neon_Azul": 1200,
    "Neon_Rosa": 1200, "Neon_Verde": 1200, "Ambar": 1200, "Stop_LED": 1200, "Fibra_Carbono": 1550,
    "Banda_Parabrisas": 1200, "Placa": 1200,
}
RATIO_DIF, RATIO_TRANS = 43 / 13, 2.6        # diferencial y 1a marcha (valores del modelo, ajustables)
# Piezas de lámina: se pesan por área × espesor real (no por el volumen modelado)
LAMINAS = {"Pintura_Carroceria": 0.0008, "Pintura_Franjas": 0.0001, "Vinilo_Franjas": 0.0001,
           "Vidrio_Polarizado": 0.0010, "Etiqueta": 0.0001, "Pintura_Livery": 0.0008,
           "Banda_Parabrisas": 0.0001, "Placa": 0.0005}
ESPESOR_PIEZA_ABIERTA = 0.0010               # pared supuesta para mallas abiertas (tubos, escape)
# Piezas que en la realidad son huecas (carcasas con engranajes, piezas moldeadas con pared delgada):
# fracción del volumen modelado que es material.
LLENADO = {"Diferencial_Tras": 0.30, "Diferencial_Del": 0.30, "Motor_Carter": 0.45, "Transmision": 0.40,
           "Arranque_Carcasa": 0.35, "Rin_": 0.50, "Caja_Radio_Tapa": 0.6, "Servo_Direccion": 0.8,
           "Servo_Acelerador": 0.8, "Filtro_Base": 0.5, "Campana_Embrague": 0.6, "Volante_Motor": 0.8,
           "Mangueta_": 0.7, "Portamangueta_": 0.7, "Defensas": 0.25,
           # accesorios huecos de la carrocería (pared delgada)
           "Guardafango_": 0.12, "Soplador": 0.15, "Aleron_Soportes": 1.0, "Aleron_Gurney": 1.0,
           "Aleron": 0.10, "Defensa_Trasera": 0.25, "Defensa_Tubular": 0.40, "Estribos": 0.40,
           "Escapes_Laterales": 0.60, "Barra_Antivuelco": 0.35, "Barra_Luces": 0.40, "Focos_Antivuelco": 0.50,
           "Parrilla_Celdas": 0.50, "Faros_Carcasa": 0.40, "Antiniebla": 0.50}


def _mass_props(obj, dg):
    """Volumen, centroide e inercia (densidad 1) de una malla cerrada, en coordenadas de mundo."""
    import numpy as np
    oe = obj.evaluated_get(dg)
    try:
        me = oe.to_mesh()
    except RuntimeError:
        return None
    if me is None or not me.polygons:
        oe.to_mesh_clear()
        return None
    me.calc_loop_triangles()
    mw = np.array(oe.matrix_world)
    V = np.array([v.co[:] for v in me.vertices], dtype=float)
    V = V @ mw[:3, :3].T + mw[:3, 3]
    T = np.array([t.vertices[:] for t in me.loop_triangles], dtype=int)
    mats = [m.name if m else "" for m in me.materials]
    tri_mat = np.array([t.material_index for t in me.loop_triangles], dtype=int) if len(mats) else None
    me_keys = [p.edge_keys for p in me.polygons]
    oe.to_mesh_clear()
    if len(T) == 0:
        return None
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    mat = mats[np.bincount(tri_mat).argmax()] if tri_mat is not None and len(mats) else ""
    from collections import Counter
    uso = Counter(k for p in me_keys for k in p)
    cerrada = all(n == 2 for n in uso.values())
    if mat in LAMINAS or not cerrada:
        # lámina delgada: masa por área; centroide e inercia de la superficie
        esp = LAMINAS.get(mat, ESPESOR_PIEZA_ABIERTA)
        area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
        if cerrada:
            area = area * 0.5                                    # lámina con espesor modelado: una cara
        A_t = area.sum()
        if A_t < 1e-12:
            return None
        ct = (a + b + c) / 3.0
        cen = (area[:, None] * ct).sum(0) / A_t
        r = ct - cen
        I = (area[:, None, None] * (np.einsum('ni,ni->n', r, r)[:, None, None] * np.eye(3) -
                                     np.einsum('ni,nj->nij', r, r))).sum(0) * esp
        return dict(vol=A_t * esp, cen=cen, I=I, mat=mat)
    det = np.einsum('ij,ij->i', a, np.cross(b, c))
    vol = det.sum() / 6.0
    sgn = 1.0 if vol >= 0 else -1.0
    det, vol = det * sgn, abs(vol)
    if vol < 1e-12:
        return None
    cen = (det[:, None] * (a + b + c)).sum(0) / 24.0 / vol
    Cc = np.array([[2, 1, 1], [1, 2, 1], [1, 1, 2]]) / 120.0
    A = np.stack([a, b, c], axis=2)                              # (n, 3, 3) columnas a, b, c
    Cov = np.einsum('n,nij,jk,nlk->il', det, A, Cc, A)
    Cov_c = Cov - vol * np.outer(cen, cen)
    I = np.trace(Cov_c) * np.eye(3) - Cov_c
    return dict(vol=vol, cen=cen, I=I, mat=mat)


def _grupo_masa(o):
    """Clasifica una pieza: ('no_suspendida', esquina, fracción) o ('suspendida', None, 1)."""
    esquinas = ("Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der")
    p = o
    while p is not None:
        for e in esquinas:
            if p.name in (f"Rueda_{e}", f"Mangueta_{e}", f"Direccion_{e}"):
                return "no_suspendida", e, 1.0
            if p.name in (f"Pivote_Brazo_Inf_{e}", f"Pivote_Brazo_Sup_{e}"):
                return "no_suspendida", e, 0.5
        p = p.parent
    for e in esquinas:
        if o.name.startswith(f"Palier_{e}"):
            return "no_suspendida", e, 0.5
    for lado in ("Izq", "Der"):
        if o.name.startswith((f"Bieleta_Direccion_{lado}", f"Bieleta_Rotulas_{lado}")):
            return "no_suspendida", f"Del_{lado}", 0.5
    return "suspendida", None, 1.0


def calcular_masas(C):
    """Masa, centro de gravedad e inercias estimadas a partir de la geometría y DENSIDADES."""
    import numpy as np
    dg = bpy.context.evaluated_depsgraph_get()
    piezas, sin_densidad = [], set()
    for key in ("body", "chasis", "susp", "ruedas", "motor", "elec"):
        for o in C[key].all_objects:
            if o.type not in ('MESH', 'CURVE', 'FONT') or o.name.startswith(("cut_", "tmp_")):
                continue
            mp = _mass_props(o, dg)
            if mp is None:
                continue
            rho = DENSIDADES.get(mp["mat"])
            if rho is None:
                sin_densidad.add(mp["mat"])
                rho = 1150
            for pref, fill in LLENADO.items():
                if o.name.startswith(pref):
                    rho *= fill
                    break
            grupo, esq, frac = _grupo_masa(o)
            piezas.append(dict(nombre=o.name, m=mp["vol"] * rho, cen=mp["cen"], I=mp["I"] * rho,
                               grupo=grupo, esquina=esq, frac=frac))

    def combinar(lista):
        m = sum(p["m"] * p["w"] for p in lista)
        if m <= 0:
            return 0.0, np.zeros(3), np.zeros((3, 3))
        c = sum(p["m"] * p["w"] * p["cen"] for p in lista) / m
        I = np.zeros((3, 3))
        for p in lista:
            d = p["cen"] - c
            I += p["w"] * (p["I"] + p["m"] * (np.dot(d, d) * np.eye(3) - np.outer(d, d)))
        return m, c, I

    total = [dict(p, w=1.0) for p in piezas]
    susp = [dict(p, w=1.0 - p["frac"]) for p in piezas if p["grupo"] == "no_suspendida"] + \
           [dict(p, w=1.0) for p in piezas if p["grupo"] == "suspendida"]
    m_t, c_t, I_t = combinar(total)
    m_s, c_s, I_s = combinar(susp)
    esquinas = {}
    for e in ("Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der"):
        lst = [dict(p, w=p["frac"]) for p in piezas if p["esquina"] == e]
        m_e, c_e, _ = combinar(lst)
        esquinas[e] = dict(masa_no_suspendida_kg=round(m_e, 4), cg_m=[round(v, 4) for v in c_e])
    top = sorted(piezas, key=lambda p: -p["m"])[:20]
    return dict(
        masa_total_kg=round(m_t, 3), cg_total_m=[round(v, 4) for v in c_t],
        masa_suspendida_kg=round(m_s, 3), cg_suspendida_m=[round(v, 4) for v in c_s],
        inercia_suspendida_kg_m2=[[round(v, 6) for v in fila] for fila in I_s],
        inercia_total_kg_m2=[[round(v, 6) for v in fila] for fila in I_t],
        no_suspendida=esquinas,
        piezas_mas_pesadas=[(p["nombre"], round(p["m"] * 1000, 1)) for p in top],
        materiales_sin_densidad=sorted(sin_densidad),
        supuestos=dict(densidades_kg_m3=DENSIDADES, laminas_espesor_m=LAMINAS,
                       pared_mallas_abiertas_m=ESPESOR_PIEZA_ABIERTA, fraccion_llenado=LLENADO,
                       nota="estimación a partir de la geometría del modelo; reemplazar por masas medidas si se tienen"),
    )


def crear_colisiones(C, root, rig, wheels):
    """Formas simples por cuerpo rígido (prefijo COL_), en una colección oculta."""
    col = C["sim"]
    O = bpy.data.objects
    mat = bpy.data.materials.get("Colision") or make_mat("Colision", (0.1, 0.9, 0.3), 0.0, 0.6)
    dg = bpy.context.evaluated_depsgraph_get()

    def hull(name, objs, owner, inflate=0.0):
        bm = bmesh.new()
        for o in objs:
            oe = o.evaluated_get(dg)
            me = oe.to_mesh()
            mw = oe.matrix_world
            for v in me.vertices:
                bm.verts.new(mw @ v.co)
            oe.to_mesh_clear()
        res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
        keep = set(v for g in res["geom"] if isinstance(g, bmesh.types.BMFace) for v in g.verts)
        P = [v.co.copy() for v in keep]
        bm.free()
        # simplificar a <= 48 vértices (límite típico de los motores de física) por muestreo del más lejano
        if len(P) > 48:
            sel = [max(range(len(P)), key=lambda i: P[i].length)]
            dmin = [(p - P[sel[0]]).length for p in P]
            while len(sel) < 48:
                i = max(range(len(P)), key=lambda k: dmin[k])
                sel.append(i)
                dmin = [min(dmin[k], (P[k] - P[i]).length) for k in range(len(P))]
            P = [P[i] for i in sel]
        bm = bmesh.new()
        for p in P:
            bm.verts.new(p)
        res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
        keep = set(v for g in res["geom"] if isinstance(g, bmesh.types.BMFace) for v in g.verts)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v not in keep], context='VERTS')
        if inflate:
            bm.normal_update()
            for v in bm.verts:
                v.co += v.normal * inflate
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        o = mesh_obj(name, bm, mat, col, None, smooth=None, recalc=False)
        o.display_type = 'WIRE'
        if owner is not None:
            attach(o, owner)
        return o

    out = []
    body_objs = [o for o in C["body"].all_objects if o.type == 'MESH' and o.name.startswith(("Carroceria_Casco",
                                                                                               "Carroceria_Cabina"))]
    out.append(hull("COL_Carroceria", body_objs, root))
    out.append(hull("COL_Chasis_Placa", [O["Chasis_Placa"]], root))
    for ej in ("Del", "Tras"):
        out.append(hull(f"COL_Mamparo_{ej}", [O[f"Diferencial_{ej}"]] +
                        [o for o in O if o.name.startswith(f"Mamparo_Placa_{ej}")], root))
        out.append(hull(f"COL_Parachoques_{ej}", [O[f"Parachoques_Base_{ej}"], O[f"Parachoques_{ej}"]], root))
    out.append(hull("COL_Motor", [O["Motor_Carter"], O["Motor_Culata"], O["Arranque_Carcasa"]], root))
    for nm, r in rig.items():
        if nm.startswith("_"):
            continue
        out.append(hull(f"COL_Brazo_Inf_{nm}", [O[f"Brazo_Inferior_{nm}"]], r["li"]))
        out.append(hull(f"COL_Brazo_Sup_{nm}", [O[f"Brazo_Superior_{nm}"]], r["ls"]))
        # rueda: cilindro exacto (radio y ancho medidos de la llanta)
        tire = O[f"Llanta_{nm}"]
        vs = [v.co for v in tire.data.vertices]
        rad = max((v.x * v.x + v.z * v.z) ** 0.5 for v in vs)
        wid = max(v.y for v in vs) - min(v.y for v in vs)
        bm = bmesh.new()
        add_cyl_axis(bm, (0, 0, 0), 'Y', rad, wid, 32)
        o = mesh_obj(f"COL_Rueda_{nm}", bm, mat, col, wheels[nm], smooth=None)
        o.display_type = 'WIRE'
        o["radio_m"], o["ancho_m"] = round(rad, 5), round(wid, 5)
        out.append(o)
    return out


FREC_MARCHA_HZ = 2.2          # frecuencia natural de marcha objetivo (cuerpo suspendido)
AMORT_ZETA = (0.35, 0.55)     # fracción del amortiguamiento crítico: compresión / extensión
G = 9.81


def calcular_resortes(masas, esquinas, rig):
    """Resorte, precarga y amortiguador por eje para que el reposo quede en h=0.
    - reparto de la masa suspendida por eje con el CG (palanca entre ejes)
    - rigidez en rueda para FREC_MARCHA_HZ; resorte = rigidez en rueda / MR²
    - precarga: el resorte ya empuja en extensión total y llega justo al peso en reposo
    - largo libre = largo instalado en extensión total + compresión de precarga"""
    import numpy as np
    m_s = masas["masa_suspendida_kg"]
    x_cg = masas["cg_suspendida_m"][0]
    f_del = (x_cg + XA) / (2 * XA)
    m_t = masas["masa_total_kg"]
    xt = masas["cg_total_m"][0]
    out = dict(frecuencia_objetivo_Hz=FREC_MARCHA_HZ, zeta_compresion=AMORT_ZETA[0], zeta_extension=AMORT_ZETA[1])
    por_eje = {}
    for ej, frac in (("Del", f_del), ("Tras", 1 - f_del)):
        nm = ej + "_Izq"
        cur = esquinas[nm]["curvas"]
        hs = np.array(cur["recorrido_rueda"]); sh = np.array(cur["compresion_amortiguador"])
        mr = np.array(cur["relacion_palanca"])
        mr0 = float(np.interp(0.0, hs, mr))
        m_c = m_s * frac / 2
        k_w = m_c * (2 * pi * FREC_MARCHA_HZ) ** 2
        k_s = k_w / mr0 ** 2
        F0 = m_c * G / mr0                                       # fuerza del resorte en reposo
        x_pre = (F0 - k_s * (0.0 - float(np.interp(TRAVEL[0], hs, sh)))) / k_s   # compresión en extensión total
        ai = rig[nm]["g"].get("amort_interno", {})
        L_ext = ai.get("largo", 0.0) + ai.get("extension", 0.0)
        ls_ext = L_ext - 0.060                                   # largo instalado con la rueda colgando
        c_crit = 2 * (k_w * m_c) ** 0.5
        F_tope = F0 + k_s * float(np.interp(TRAVEL[1], hs, sh))
        por_eje[ej] = dict(
            fraccion_masa_suspendida=round(frac, 3), masa_suspendida_esquina_kg=round(m_c, 3),
            relacion_palanca_reposo=round(mr0, 4), rigidez_en_rueda_N_m=round(k_w, 1),
            rigidez_resorte_N_m=round(k_s, 1), rigidez_resorte_N_mm=round(k_s / 1000, 3),
            fuerza_resorte_reposo_N=round(F0, 2), precarga_en_extension_mm=round(x_pre * 1000, 2),
            largo_instalado_extension_mm=round(ls_ext * 1000, 1),
            largo_libre_resorte_mm=round((ls_ext + x_pre) * 1000, 1),
            fuerza_resorte_compresion_total_N=round(F_tope, 1),
            amortiguador_N_s_m=dict(compresion=round(AMORT_ZETA[0] * c_crit / mr0 ** 2, 1),
                                    extension=round(AMORT_ZETA[1] * c_crit / mr0 ** 2, 1)),
            hundimiento_estatico_mm=round(-TRAVEL[0] * 1000, 1),
            ok_precarga_positiva=bool(x_pre > 0))
    out["por_eje"] = por_eje
    out["nota"] = ("con estos resortes el auto queda en h=0 (44 mm sobre la extensión total y 36 mm "
                   "antes del tope); ajustar FREC_MARCHA_HZ / AMORT_ZETA y recalcular")
    out["reparto_peso"] = dict(delantero=round((xt + XA) / (2 * XA), 3), trasero=round(1 - (xt + XA) / (2 * XA), 3),
                               carga_eje_del_N=round(m_t * G * (xt + XA) / (2 * XA), 2),
                               carga_eje_tras_N=round(m_t * G * (1 - (xt + XA) / (2 * XA)), 2),
                               altura_cg_total_mm=round(masas["cg_total_m"][2] * 1000, 1),
                               altura_cg_suspendida_mm=round(masas["cg_suspendida_m"][2] * 1000, 1))
    return out


G_ACERO, E_ACERO = 79e9, 200e9          # módulo de corte y de elasticidad del acero de resorte


def calcular_estabilizadoras(rig):
    """Rigidez de cada barra: torsión del tramo transversal + flexión de los dos brazos (en serie),
    llevada a rigidez al balanceo del eje con dψ/dh medido en el rig."""
    out = {}
    t = 2 * YW
    for f, ej in ((1, "Del"), (-1, "Tras")):
        r = rig[f"{ej}_Izq"]
        es = r["estab"]
        d = ESTAB_D[f]
        yb = abs(r["g"]["E"].y) + 0.006
        L_t = 2 * (yb - 0.006)                              # tramo recto entre dobleces
        J, I = pi * d ** 4 / 32, pi * d ** 4 / 64
        k_t = G_ACERO * J / L_t
        k_b = 3 * E_ACERO * I / es["La"]
        k_eff = 1 / (1 / k_t + 2 / k_b)
        dpsi = abs(es["dpsi_dh"])
        out[ej] = dict(diametro_mm=round(d * 1000, 2), tramo_torsion_mm=round(L_t * 1000, 1),
                       brazo_mm=round(es["La"] * 1000, 1), bieleta_mm=round(es["Ll"] * 1000, 1),
                       rigidez_torsion_Nm_rad=round(k_t, 2), rigidez_efectiva_Nm_rad=round(k_eff, 2),
                       dpsi_dh_rad_m=round(dpsi, 3), giro_brazo_grados=[round(es["psi_min"] * 180 / pi, 1),
                                                                         round(es["psi_max"] * 180 / pi, 1)],
                       rigidez_balanceo_Nm_rad=round(k_eff * dpsi ** 2 * t ** 2, 2),
                       rigidez_rueda_contraria_N_m=round(k_eff * dpsi ** 2, 1))
    return out


def analisis_todo_terreno(C, rig, masas, resortes):
    """Geometría todo terreno: centros de balanceo, rigidez y gradiente de balanceo, transferencia
    de carga, estabilidad, distancia al piso y ángulos de ataque / salida / ventral."""
    import numpy as np
    O = bpy.data.objects
    E4 = ("Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der")
    out = {}
    # --- centros de balanceo (vista frontal, en reposo) ---
    rc = {}
    for ej in ("Del", "Tras"):
        g = rig[ej + "_Izq"]["g"]
        def linea(p, q):
            return np.array([p.y, p.z]), np.array([q.y - p.y, q.z - p.z])
        (a1, d1), (a2, d2) = linea(g["L0"], g["L1"]), linea(g["U0"], g["U1"])
        Am = np.array([d1, -d2]).T
        tt = np.linalg.solve(Am, a2 - a1)
        ic = a1 + d1 * tt[0]
        cp = np.array([YW, 0.0])                              # contacto de la llanta
        k = (0.0 - cp[0]) / (ic[0] - cp[0])
        rc[ej] = dict(centro_instantaneo_mm=[round(ic[0] * 1000, 1), round(ic[1] * 1000, 1)],
                      altura_centro_balanceo_mm=round((cp[1] + k * (ic[1] - cp[1])) * 1000, 1))
    out["centro_balanceo"] = rc
    # --- rigidez al balanceo ---
    t = 2 * YW
    bars = calcular_estabilizadoras(rig)
    K = {}
    for ej in ("Del", "Tras"):
        kw = resortes["por_eje"][ej]["rigidez_en_rueda_N_m"]
        K[ej] = dict(resortes_Nm_rad=round(kw * t ** 2 / 2, 2), barra_Nm_rad=bars[ej]["rigidez_balanceo_Nm_rad"])
        K[ej]["total_Nm_rad"] = round(K[ej]["resortes_Nm_rad"] + K[ej]["barra_Nm_rad"], 2)
    Kt = K["Del"]["total_Nm_rad"] + K["Tras"]["total_Nm_rad"]
    K_sin = K["Del"]["resortes_Nm_rad"] + K["Tras"]["resortes_Nm_rad"]
    m_s, cg_s = masas["masa_suspendida_kg"], masas["cg_suspendida_m"]
    m_t, cg_t = masas["masa_total_kg"], masas["cg_total_m"]
    xr = (cg_s[0] + XA) / (2 * XA)
    h_ra = (rc["Tras"]["altura_centro_balanceo_mm"] * (1 - xr) + rc["Del"]["altura_centro_balanceo_mm"] * xr) / 1000
    M_g = m_s * 9.81 * (cg_s[2] - h_ra)
    grad = M_g / Kt
    grad0 = M_g / K_sin
    out["balanceo"] = dict(
        rigidez_por_eje=K, reparto_rigidez_delantero=round(K["Del"]["total_Nm_rad"] / Kt, 3),
        brazo_de_balanceo_mm=round((cg_s[2] - h_ra) * 1000, 1),
        gradiente_grados_por_g=round(grad * 180 / pi, 2),
        gradiente_sin_barras_grados_por_g=round(grad0 * 180 / pi, 2),
        barras=bars)
    # --- estabilidad al vuelco ---
    ssf = t / (2 * cg_t[2])
    a_lim = (t / 2) / (cg_t[2] + (cg_s[2] - h_ra) * grad * m_s / m_t)
    out["estabilidad"] = dict(factor_estabilidad_estatica=round(ssf, 3),
                              aceleracion_lateral_vuelco_g=round(a_lim, 3),
                              nota="cuerpo rígido = SSF; con balanceo, el CG se corre hacia afuera y baja el límite")
    # --- antihundimiento: ejes de los brazos paralelos a X ---
    out["anti_squat_anti_dive"] = dict(
        anti_squat_trasero_pct=0.0, anti_dive_delantero_pct=0.0,
        nota="pivotes de los brazos paralelos a X: brazo oscilante lateral infinito -> 0 %. "
             "Inclinar 3-5° los pivotes traseros daría ~20-35 % de antihundimiento al acelerar.")
    # --- geometría de dirección con caster ---
    g = rig["Del_Izq"]["g"]
    kp = (g["U1"] - g["L1"]).normalized()
    out["direccion_geometria"] = dict(caster_grados=round(math.degrees(math.atan2(-kp.x, kp.z)), 2),
                                      inclinacion_pivote_grados=round(math.degrees(math.atan2(abs(kp.y), kp.z)), 2),
                                      avance_mecanico_mm=round(WZ * math.tan(math.radians(CASTER[1])) * 1000, 1))
    # --- distancia al piso y ángulos (piezas que no son llanta ni rin) ---
    backup = {}
    for o in O:
        if o.animation_data and o.animation_data.action:
            backup[o.name] = o.animation_data.action
            o.animation_data.action = None
    O["MonsterTruck_Root"].location = (0, 0, 0)
    O["MonsterTruck_Root"].rotation_euler = (0, 0, 0)
    excl = ("Llanta_", "Rin_", "Tuerca_", "Eje_Rueda", "Eje_Copa", "Herraje_Rueda", "COL_", "Piso", "Panel_")
    objs = [o for k in ("body", "chasis", "susp", "ruedas", "motor", "elec") for o in C[k].all_objects
            if o.type == 'MESH' and not o.name.startswith(excl)]
    dg = bpy.context.evaluated_depsgraph_get()
    loc = {}
    for o in objs:
        oe = o.evaluated_get(dg)
        me = oe.to_mesh()
        loc[o.name] = np.array([v.co[:] for v in me.vertices] or [[0, 0, 0]])
        oe.to_mesh_clear()
    tire = O["Llanta_Del_Izq"].data
    R_t = max((v.co.x ** 2 + v.co.z ** 2) ** 0.5 for v in tire.vertices)
    def nube(h):
        _aplicar_pose({e: h for e in E4}, 0.0)
        pts, quien = [], []
        for o in objs:
            Mw = np.array(o.matrix_world)
            V = loc[o.name] @ Mw[:3, :3].T + Mw[:3, 3]
            pts.append(V)
            quien += [o.name] * len(V)
        return np.vstack(pts), quien
    piso = {}
    for nm_p, h in (("reposo", 0.0), ("compresion_total", TRAVEL[1])):
        P_, quien = nube(h)
        z = P_[:, 2] - h                                   # el piso sube h respecto del chasis
        i = int(np.argmin(z))
        mitad = np.abs(P_[:, 0]) < XA - 0.03
        j = int(np.argmin(np.where(mitad, z, 9)))
        piso[nm_p] = dict(minimo_mm=round(float(z[i]) * 1000, 1), pieza=quien[i],
                          minimo_entre_ejes_mm=round(float(z[j]) * 1000, 1), pieza_entre_ejes=quien[j])
    out["distancia_al_piso"] = piso
    P_, quien = nube(0.0)
    zc_ = WZ                                              # centro de rueda en reposo (piso en z=0)
    def angulo_tangente(px, pz, cx, lado):
        # ángulo con el piso de la recta que pasa por el punto y es tangente a la llanta por abajo
        dx, dz = (px - cx) * lado, pz - zc_
        dist = (dx * dx + dz * dz) ** 0.5
        if dist <= R_t:
            return pi / 2                                 # tapado por la llanta en vista lateral
        return math.atan2(-dz, dx) * -1 + math.asin(R_t / dist) if False else (math.atan2(dz, dx) + math.asin(R_t / dist))
    ang = {}
    for nombre, cx, lado in (("ataque", XA, 1), ("salida", -XA, -1)):
        sel = (P_[:, 0] - cx) * lado > 0
        best = (pi / 2, "")
        for (px, pz), who in zip(P_[sel][:, [0, 2]], np.array(quien)[sel]):
            a_ = angulo_tangente(px, pz, cx, lado)
            if a_ < best[0]:
                best = (a_, who)
        ang[nombre] = dict(grados=round(math.degrees(best[0]), 1), limita=best[1])
    sel = np.abs(P_[:, 0]) < XA
    best = (pi, "")
    for (px, pz), who in zip(P_[sel][:, [0, 2]], np.array(quien)[sel]):
        a_ = angulo_tangente(px, pz, XA, -1) + angulo_tangente(px, pz, -XA, 1)
        if a_ < best[0]:
            best = (a_, who)
    ang["ventral"] = dict(grados=round(math.degrees(best[0]), 1), limita=best[1])
    out["angulos"] = ang
    _aplicar_pose({e: 0.0 for e in E4}, 0.0)
    for nm_, act in backup.items():
        O[nm_].animation_data.action = act
    return out


def exportar_datos_simulacion(C, rig, ruta=None):
    """Reúne puntos de suspensión, curvas, dirección, transmisión y masas en un JSON."""
    import json
    import numpy as np
    O = bpy.data.objects
    sc = bpy.context.scene
    sc.frame_set(1)
    ctrls = {nm: O[f"Control_Suspension_{nm}"] for nm in ("Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der")}
    st = O["Control_Direccion"]
    anim_backup = {}
    for o in list(ctrls.values()) + [st, O["MonsterTruck_Root"]]:
        if o.animation_data and o.animation_data.action:
            anim_backup[o.name] = o.animation_data.action
            o.animation_data.action = None
    for c in ctrls.values():
        c.location.z = 0.0
    st.rotation_euler.z = 0.0
    O["MonsterTruck_Root"].location = (0, 0, 0)
    O["MonsterTruck_Root"].rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()

    v3 = lambda v: [round(float(x), 5) for x in v]
    tire = O["Llanta_Del_Izq"]
    vs = [v.co for v in tire.data.vertices]
    radio = max((v.x * v.x + v.z * v.z) ** 0.5 for v in vs)
    ancho = max(v.y for v in vs) - min(v.y for v in vs)
    data = dict(
        modelo="Monster truck RC nitro 1:8 (diseño propio)",
        unidades="metros, kilogramos, radianes salvo indicación",
        ejes_blender="X adelante, Y izquierda, Z arriba; origen en el centro del chasis a nivel del piso",
        ejes_gltf="glTF usa Y arriba: (x, y, z)_gltf = (x, z, -y)_blender",
        geometria=dict(distancia_ejes=XA * 2, ancho_via=YW * 2, radio_rueda=round(radio, 5),
                       ancho_rueda=round(ancho, 5), altura_eje_reposo=WZ,
                       recorrido_rueda=dict(extension=TRAVEL[0], compresion=TRAVEL[1])),
        esquinas={},
    )
    for nm, r in rig.items():
        if nm.startswith("_"):
            continue
        g = r["g"]
        pts = {k: v3(g[k]) for k in ("L0", "L1", "U0", "U1", "A", "R", "P", "S", "B", "W", "D0", "D1")}
        pts["eje_balancin"] = v3(g["n"])
        if "tie_inner" in r:
            pts["bieleta_interior"] = v3(r["tie_inner"])
            pts["bieleta_exterior"] = v3(r["tie_outer"])
        d = solve_corner(g)
        hs = np.arange(TRAVEL[0], TRAVEL[1] + 1e-9, 0.002)
        sh = np.interp(hs, d[:, 0], d[:, 4])
        cam = np.interp(hs, d[:, 0], d[:, 5]) * 180 / pi
        scrub = np.interp(hs, d[:, 0], d[:, 6]) if d.shape[1] > 6 else np.zeros_like(hs)
        mr = np.gradient(sh, hs)
        data["esquinas"][nm] = dict(
            puntos=pts,
            leyenda=dict(L0="pivote interior brazo inferior", L1="rótula exterior brazo inferior",
                         U0="pivote interior brazo superior", U1="rótula exterior brazo superior",
                         A="varilla de empuje en el brazo", R="varilla de empuje en el balancín",
                         P="pivote del balancín", S="amortiguador en el balancín",
                         B="amortiguador en el chasis", W="centro de rueda", D0="palier interior",
                         D1="palier exterior"),
            largo_amortiguador_reposo=round(float((g["S"] - g["B"]).length), 5),
            curvas=dict(recorrido_rueda=[round(float(x), 4) for x in hs],
                        compresion_amortiguador=[round(float(x), 5) for x in sh],
                        relacion_palanca=[round(float(x), 4) for x in mr],
                        caida_grados=[round(float(x), 3) for x in cam],
                        desplazamiento_lateral_rueda=[round(float(x), 5) for x in scrub]),
        )
    # dirección medida en el propio rig (incluye Ackermann)
    tabla = []
    for dd in np.linspace(-0.42, 0.42, 15):
        st.rotation_euler.z = float(dd)
        bpy.context.view_layer.update()
        tabla.append(dict(control=round(float(dd), 4),
                          cremallera_m=round(float(RACK_K * dd), 5),
                          rueda_izq_grados=round(O["Direccion_Del_Izq"].rotation_euler.z * 180 / pi, 3),
                          rueda_der_grados=round(O["Direccion_Del_Der"].rotation_euler.z * 180 / pi, 3)))
    st.rotation_euler.z = 0.0
    data["direccion"] = dict(control_max=0.42, tabla=tabla,
                             nota="ángulo de la mangueta alrededor del eje de pivote; + = gira a la izquierda")
    data["transmision"] = dict(relacion_diferencial=round(RATIO_DIF, 4), relacion_1a_marcha=RATIO_TRANS,
                               traccion="4x4, diferenciales delantero y trasero",
                               nota="relaciones del modelo, no de un producto real; ajustables")
    masas = calcular_masas(C)
    data["masas"] = masas
    data["resortes_sugeridos"] = calcular_resortes(masas, data["esquinas"], rig)
    data["reparto_peso"] = data["resortes_sugeridos"].pop("reparto_peso")
    data["topes_compresion"] = {nm: dict(largo_libre_mm=round(r["g"]["tope"]["largo_libre"] * 1000, 2),
                                         contacto_recorrido_mm=round(r["g"]["tope"]["h_contacto"] * 1000, 1),
                                         aplastado_max_mm=round(r["g"]["tope"]["aplastado_max"] * 1000, 2),
                                         fuerza_N=dict(ley="F = 12·x + 4·x³ (x en mm de aplastamiento, uretano 90A)",
                                                       a_tope=round(12 * r["g"]["tope"]["aplastado_max"] * 1000 +
                                                                    4 * (r["g"]["tope"]["aplastado_max"] * 1000) ** 3, 1)))
                                for nm, r in rig.items() if not nm.startswith("_")}
    data["todo_terreno"] = analisis_todo_terreno(C, rig, masas, data["resortes_sugeridos"])
    data["colisiones"] = sorted(o.name for o in C["sim"].all_objects)
    for name, act in anim_backup.items():
        O[name].animation_data.action = act
    sc.frame_set(1)
    txt = json.dumps(data, ensure_ascii=False, indent=2)
    t = bpy.data.texts.get("datos_simulacion.json") or bpy.data.texts.new("datos_simulacion.json")
    t.clear()
    t.write(txt)
    if ruta:
        with open(ruta, "w", encoding="utf-8") as fh:
            fh.write(txt)
    return data


# ---------------------------------------------------------------------------
# Análisis global de choques (todas las piezas, todo el rango de movimiento)
# ---------------------------------------------------------------------------
def poses_de_prueba():
    """(nombre, {esquina: recorrido}, dirección) que cubren compresión, extensión,
    balanceo, cabeceo, cruce de ejes y dirección a tope."""
    E = ("Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der")
    lo, hi = TRAVEL
    base = []
    for h in (lo, lo / 2, 0.0, hi / 2, hi):
        base.append((f"todas {h * 1000:+.0f} mm", {e: h for e in E}))
    base.append(("balanceo izq", {"Del_Izq": hi, "Tras_Izq": hi, "Del_Der": lo, "Tras_Der": lo}))
    base.append(("balanceo der", {"Del_Izq": lo, "Tras_Izq": lo, "Del_Der": hi, "Tras_Der": hi}))
    base.append(("cabeceo frenada", {"Del_Izq": hi, "Del_Der": hi, "Tras_Izq": lo, "Tras_Der": lo}))
    base.append(("cabeceo acelera", {"Del_Izq": lo, "Del_Der": lo, "Tras_Izq": hi, "Tras_Der": hi}))
    base.append(("cruce de ejes", {"Del_Izq": hi, "Tras_Der": hi, "Del_Der": lo, "Tras_Izq": lo}))
    poses = []
    for nm, hs in base:
        for d in (-0.42, 0.0, 0.42):
            # avance distinto en cada pose: ruedas, palieres, cardanes y cigüeñal giran a
            # ángulos variados, así las piezas giratorias quedan como cuerpos propios
            giro = 0.0071 * (len(poses) + 1)
            poses.append((f"{nm}, dirección {d:+.2f}", hs, d, giro))
    return poses


def _aplicar_pose(hs, d, giro=0.0):
    O = bpy.data.objects
    for e, h in hs.items():
        O[f"Control_Suspension_{e}"].location.z = h
    O["Control_Direccion"].rotation_euler.z = d
    O["Control_Avance"].location.x = giro
    bpy.context.view_layer.update()


def analizar_choques(colecciones=("body", "chasis", "susp", "ruedas", "motor", "elec"), C=None,
                     poses=None, tolerancia=0.0, verbose=True):
    """Devuelve (choques_por_movimiento, contactos_permanentes_entre_cuerpos, cuerpos).
    - choques_por_movimiento: pares que NO se tocan en reposo pero sí en alguna pose.
    - contactos_permanentes: pares de cuerpos rígidos distintos que se tocan siempre
      (uniones a propósito: bola-rótula, pasador-buje... o errores a revisar)."""
    import numpy as np
    from mathutils.bvhtree import BVHTree
    O = bpy.data.objects
    sc = bpy.context.scene
    poses = poses or poses_de_prueba()
    # quitar animación mientras se analiza
    backup = {}
    for o in O:
        if o.animation_data and o.animation_data.action:
            backup[o.name] = o.animation_data.action
            o.animation_data.action = None
    O["MonsterTruck_Root"].location = (0, 0, 0)
    O["MonsterTruck_Root"].rotation_euler = (0, 0, 0)
    names = []
    if C is not None:
        for k in colecciones:
            names += [o.name for o in C[k].all_objects if o.type in ('MESH', 'CURVE')]
    else:
        names = [o.name for o in O if o.type == 'MESH' and not o.name.startswith(("COL_", "Piso", "Panel_"))]
    names = sorted(set(names))
    # poses: reposo + prueba
    todas = [("reposo", {e: 0.0 for e in ("Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der")}, 0.0, 0.0)] + poses
    mats = {n: [] for n in names}
    for p in todas:
        _aplicar_pose(p[1], p[2], p[3] if len(p) > 3 else 0.0)
        for n in names:
            mats[n].append(O[n].matrix_world.copy())
    # cuerpos rígidos: piezas cuya transformación relativa no cambia en ninguna pose
    def firma(n):
        # movimiento en espacio de mundo respecto al reposo: igual para piezas unidas rígidamente
        m0inv = mats[n][0].inverted()
        return [m @ m0inv for m in mats[n]]
    cuerpos, rep_firma = {}, {}
    for n in names:
        f = firma(n)
        asignado = None
        for r, fr in rep_firma.items():
            if all(max(abs(a - b) for ra, rb in zip(x, y) for a, b in zip(ra, rb)) < 2e-5 for x, y in zip(f, fr)):
                asignado = r
                break
        if asignado is None:
            rep_firma[n] = f
            asignado = n
        cuerpos[n] = asignado
    # geometría en mundo por pose (sólo se recalcula lo que se mueve)
    dg = bpy.context.evaluated_depsgraph_get()
    local = {}
    for n in names:
        oe = O[n].evaluated_get(dg)
        me = oe.to_mesh()
        local[n] = ([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
        oe.to_mesh_clear()
    def aabb(n, k):
        vs = local[n][0]
        if not vs:
            return None
        bb = [mats[n][k] @ Vector(c) for c in O[n].bound_box]
        lo_ = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        hi_ = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        return lo_, hi_
    def bvh(n, k, cache):
        key = (n, k if mats[n][k] != mats[n][0] else 0)
        if key not in cache:
            mw = mats[n][key[1]]
            vs, ps = local[n]
            cache[key] = BVHTree.FromPolygons([mw @ v for v in vs], ps, epsilon=tolerancia)
        return cache[key]
    estado = {}
    cache = {}
    for k in range(len(todas)):
        boxes = {n: aabb(n, k) for n in names}
        for i, a in enumerate(names):
            ba = boxes[a]
            if ba is None:
                continue
            for b in names[i + 1:]:
                if cuerpos[a] == cuerpos[b]:
                    continue
                bb_ = boxes[b]
                if bb_ is None:
                    continue
                if any(ba[1][j] < bb_[0][j] or bb_[1][j] < ba[0][j] for j in range(3)):
                    continue
                if bvh(a, k, cache).overlap(bvh(b, k, cache)):
                    estado.setdefault((a, b), set()).add(k)
        # liberar los árboles de piezas que se mueven en esta pose
        for key in [kk for kk in cache if kk[1] == k and k != 0]:
            del cache[key]
    choques, permanentes, intermitentes = [], [], []
    for (a, b), ks in estado.items():
        if 0 in ks:
            if len(ks) == len(todas):
                permanentes.append((a, b))
            else:                           # se tocan en reposo y se separan en alguna pose
                intermitentes.append((a, b, [todas[k][0] for k in sorted(ks) if k]))
        else:
            choques.append((a, b, [todas[k][0] for k in sorted(ks)]))
    analizar_choques.intermitentes = intermitentes
    _aplicar_pose({e: 0.0 for e in ("Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der")}, 0.0)
    for nm, act in backup.items():
        O[nm].animation_data.action = act
    sc.frame_set(sc.frame_current)
    n_cuerpos = len(set(cuerpos.values()))
    if verbose:
        print(f"piezas {len(names)}, cuerpos rígidos {n_cuerpos}, poses {len(todas)}")
        print(f"choques por movimiento: {len(choques)}; contactos permanentes: {len(permanentes)}")
    return choques, permanentes, cuerpos


def analizar_holguras(C, cuerpos, margen=0.0008, colecciones=("body", "chasis", "susp", "ruedas", "motor", "elec"),
                      poses=None, excluir=("Herraje_", "Cable_", "Amarras", "Clip_R")):
    """Holgura mínima entre piezas de cuerpos rígidos distintos que NO se tocan, en todas
    las poses de prueba. Devuelve [(holgura_mm, a, b, pose)] para las que pasan a menos de
    'margen' (roces probables por tolerancias de fabricación o flexión)."""
    from mathutils.bvhtree import BVHTree
    O = bpy.data.objects
    poses = poses or poses_de_prueba()
    todas = [("reposo", {e: 0.0 for e in ("Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der")}, 0.0, 0.0)] + poses
    backup = {}
    for o in O:
        if o.animation_data and o.animation_data.action:
            backup[o.name] = o.animation_data.action
            o.animation_data.action = None
    O["MonsterTruck_Root"].location = (0, 0, 0)
    O["MonsterTruck_Root"].rotation_euler = (0, 0, 0)
    names = sorted({o.name for k in colecciones for o in C[k].all_objects
                    if o.type == 'MESH' and o.name in cuerpos and not o.name.startswith(excluir)})
    dg = bpy.context.evaluated_depsgraph_get()
    local = {}
    for n in names:
        oe = O[n].evaluated_get(dg)
        me = oe.to_mesh()
        local[n] = ([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
        oe.to_mesh_clear()
    mejor = {}
    for p in todas:
        _aplicar_pose(p[1], p[2], p[3] if len(p) > 3 else 0.0)
        W = {n: [O[n].matrix_world @ v for v in local[n][0]] for n in names}
        box = {}
        for n in names:
            V = W[n]
            if V:
                box[n] = (Vector((min(v.x for v in V), min(v.y for v in V), min(v.z for v in V))),
                          Vector((max(v.x for v in V), max(v.y for v in V), max(v.z for v in V))))
        arb = {}
        def tree(n):
            if n not in arb:
                arb[n] = BVHTree.FromPolygons(W[n], local[n][1])
            return arb[n]
        for i, a in enumerate(names):
            if a not in box:
                continue
            la, ha = box[a]
            for b in names[i + 1:]:
                if b not in box or cuerpos[a] == cuerpos[b]:
                    continue
                lb, hb = box[b]
                if any(ha[j] + margen < lb[j] or hb[j] + margen < la[j] for j in range(3)):
                    continue
                ta, tb = tree(a), tree(b)
                if ta.overlap(tb):
                    continue                                   # se tocan: lo cubre analizar_choques
                dmin = margen
                for V, t, lo, hi in ((W[a], tb, lb, hb), (W[b], ta, la, ha)):
                    for v in V:
                        if any(v[j] < lo[j] - margen or v[j] > hi[j] + margen for j in range(3)):
                            continue
                        hit = t.find_nearest(v, dmin)
                        if hit[0] is not None and hit[3] < dmin:
                            dmin = hit[3]
                if dmin < margen and dmin < mejor.get((a, b), (margen, ""))[0]:
                    mejor[(a, b)] = (dmin, p[0])
    _aplicar_pose({e: 0.0 for e in ("Del_Izq", "Del_Der", "Tras_Izq", "Tras_Der")}, 0.0)
    for nm, act in backup.items():
        O[nm].animation_data.action = act
    return sorted((round(d * 1000, 2), a, b, ps) for (a, b), (d, ps) in mejor.items())


_RAYOS = (Vector((0.5773, 0.5774, 0.5774)), Vector((-0.6247, 0.7071, -0.3313)), Vector((0.2673, -0.5345, 0.8018)))


def _dentro_por_rayos(t, v, rayos=_RAYOS):
    """Paridad de cruces: un punto está dentro de una malla cerrada si un rayo cruza
    la superficie un número impar de veces. Se vota con 3 direcciones oblicuas para que
    las aristas y los bordes de cáscaras no den falsos positivos."""
    votos = 0
    for d in rayos:
        d = d.normalized()
        o, n = v.copy(), 0
        for _ in range(64):
            loc, _, _, _ = t.ray_cast(o, d)
            if loc is None:
                break
            n += 1
            o = loc + d * 1e-6
        votos += n % 2
    return votos >= 2


def analizar_interpenetracion(cuerpos, tolerancia=0.0015, minimo=6, excluir=("Herraje_", "Pasador", "Tornillo",
                                                                            "Cable_", "Clip_R", "Amarras")):
    """Piezas del MISMO cuerpo rígido que se atraviesan más de 'tolerancia' (vértices de una
    dentro de la otra). Sirve para encontrar errores de montaje que el movimiento no revela."""
    from mathutils.bvhtree import BVHTree
    O = bpy.data.objects
    dg = bpy.context.evaluated_depsgraph_get()
    geo = {}
    for n in cuerpos:
        if n.startswith(excluir):
            continue
        oe = O[n].evaluated_get(dg)
        me = oe.to_mesh()
        mw = oe.matrix_world
        V = [mw @ v.co for v in me.vertices]
        P = [tuple(p.vertices) for p in me.polygons]
        from collections import Counter
        uso = Counter(k for p in me.polygons for k in p.edge_keys)
        cerrada = all(c == 2 for c in uso.values())
        oe.to_mesh_clear()
        if len(V) < 4 or not P:
            continue
        lo = Vector((min(v.x for v in V), min(v.y for v in V), min(v.z for v in V)))
        hi = Vector((max(v.x for v in V), max(v.y for v in V), max(v.z for v in V)))
        geo[n] = (V, BVHTree.FromPolygons(V, P), lo, hi, cerrada)
    names = sorted(geo)
    res = []
    for i, a in enumerate(names):
        Va, ta, la, ha, ca = geo[a]
        for b in names[i + 1:]:
            if cuerpos[a] != cuerpos[b]:
                continue
            Vb, tb, lb, hb, cb_ = geo[b]
            if any(ha[j] < lb[j] or hb[j] < la[j] for j in range(3)):
                continue
            def dentro(V, t, lo, hi):
                k = 0
                for v in V:
                    if any(v[j] < lo[j] or v[j] > hi[j] for j in range(3)):
                        continue
                    hit = t.find_nearest(v)
                    if hit[0] is None:
                        continue
                    loc, nrm, _, dist = hit
                    if dist > tolerancia and (v - loc).dot(nrm) < 0 and _dentro_por_rayos(t, v):
                        k += 1
                return k
            ka = dentro(Va, tb, lb, hb) if cb_ else 0
            kb = dentro(Vb, ta, la, ha) if ca else 0
            if ka + kb >= minimo:
                res.append((ka + kb, a, b))
    res.sort(reverse=True)
    return res


# ---------------------------------------------------------------------------
# Construcción completa
# ---------------------------------------------------------------------------
def build():
    clear_scene()
    M = build_materials()
    top = new_collection("MonsterTruck_Nitro")
    C = {
        "body":   new_collection("01_Carroceria", top),
        "chasis": new_collection("02_Chasis", top),
        "susp":   new_collection("03_Suspension", top),
        "ruedas": new_collection("04_Ruedas", top),
        "motor":  new_collection("05_Motor_Transmision", top),
        "elec":   new_collection("06_Electronica", top),
        "ctrl":   new_collection("00_Controles", top),
        "sim":    new_collection("07_Simulacion", top),
        "studio": new_collection("Estudio"),
    }
    root = empty("MonsterTruck_Root", C["chasis"], None, size=0.15, kind='ARROWS')
    build_chassis(root, C, M)
    rig = build_suspension(root, C, M)
    build_estabilizadoras(root, C, M, rig)
    wheels = build_wheels(root, C["ruedas"], M)
    build_engine(root, C, M)
    build_electronics(root, C, M)
    C["_report"] = setup_rig(root, C, rig, wheels)
    build_body(root, C, M)
    aplicar_colores(C, M)
    finish_details(C)
    bpy.context.scene.frame_set(1)
    crear_colisiones(C, root, rig, wheels)
    C["sim"].hide_render = True
    bpy.context.view_layer.layer_collection.children["MonsterTruck_Nitro"].children["07_Simulacion"].hide_viewport = True
    C["_rig"] = rig
    C["_sim"] = exportar_datos_simulacion(C, rig)
    build_studio(C, M)
    return C


if __name__ == "__main__":
    build()
