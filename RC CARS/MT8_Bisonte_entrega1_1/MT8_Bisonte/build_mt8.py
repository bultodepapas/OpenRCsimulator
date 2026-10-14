"""Construye el blockout articulado del Bisonte MT8 en Blender 5.2.2 LTS (modulo bpy) y lo exporta.

Uso:  python3 build_mt8.py            -> out/MT8_Bisonte.blend, out/MT8_Bisonte.glb, out/mt8_spec.json
Todo se escribe en coordenadas de Godot (ver mt8_geo.py) y se convierte a Blender al crear la malla.
"""
import json
import math
import os
import sys

import bpy  # bpy antes que bmesh
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mt8_spec as S  # noqa: E402
from mt8_geo import Builder, CI, g2b, mat_g2b  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

# ------------------------------------------------------------------ escena limpia
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0


def col(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or scene.collection).children.link(c)
    return c


C_ROOT = col("MT8")
C_CHASSIS = col("MT8_Chassis", C_ROOT)
C_BODY = col("MT8_Body", C_ROOT)
C_PROP = col("MT8_Propulsion", C_ROOT)
C_CORNER = {c: col(f"MT8_Corner_{c}", C_ROOT) for c in S.CORNERS}
C_COL = col("MT8_Collision", C_ROOT)


# ------------------------------------------------------------------ materiales
def srgb(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def hexc(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


MAT_DEFS = {
    # nombre: (color sRGB, metalico, rugosidad, emision)
    "MT8_Paint_Orange": ("#E8641B", 0.0, 0.32, None),
    "MT8_Plastic_Orange": ("#E06A22", 0.0, 0.55, None),
    "MT8_Plastic_Black": ("#141414", 0.0, 0.60, None),
    "MT8_Plastic_Grey": ("#3A3D40", 0.0, 0.55, None),
    "MT8_Glass_Dark": ("#0B0F14", 0.0, 0.08, None),
    "MT8_Decal_White": ("#F2F2EE", 0.0, 0.40, None),
    "MT8_Decal_Black": ("#0E0E0E", 0.0, 0.45, None),
    "MT8_Alu_Teal": ("#1F8A9E", 0.85, 0.35, None),
    "MT8_Alu_Raw": ("#B9BEC2", 1.0, 0.30, None),
    "MT8_Steel": ("#8C9196", 1.0, 0.35, None),
    "MT8_Chrome": ("#E6E8EA", 1.0, 0.10, None),
    "MT8_Spring_Yellow": ("#F2C230", 0.35, 0.40, None),
    "MT8_Rim_Bronze": ("#B8862B", 1.0, 0.28, None),
    "MT8_Tire_Rubber": ("#1C1C1C", 0.0, 0.88, None),
    "MT8_Motor_Red": ("#B5241B", 0.85, 0.32, None),
    "MT8_Battery_Wrap": ("#1E2E6B", 0.0, 0.45, None),
    "MT8_Light_Amber": ("#FFC24A", 0.0, 0.30, ("#FFB020", 2.0)),
    "MT8_Light_White": ("#F5F3EA", 0.0, 0.20, ("#FFF6E0", 1.5)),
    "MT8_COL_Proxy": ("#FF00FF", 0.0, 1.00, None),
}
MATS = {}
for name, (c, met, rough, emi) in MAT_DEFS.items():
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    lin = srgb(hexc(c))
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Metallic"].default_value = met
    bsdf.inputs["Roughness"].default_value = rough
    if emi:
        bsdf.inputs["Emission Color"].default_value = (*srgb(hexc(emi[0])), 1.0)
        bsdf.inputs["Emission Strength"].default_value = emi[1]
    m.diffuse_color = (*lin, 1.0)
    m.metallic = met
    m.roughness = rough
    if name == "MT8_COL_Proxy":
        m.diffuse_color = (*lin, 0.35)
    MATS[name] = m


# ------------------------------------------------------------------ objetos y jerarquia
def link(obj, collection):
    collection.objects.link(obj)
    return obj


def place(obj, parent, mg_local):
    """mg_local: transformacion local (marco Godot) respecto al padre."""
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = mat_g2b(mg_local)


def empty(name, collection, parent, pos=(0, 0, 0), size=0.03, kind='PLAIN_AXES'):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = size
    link(e, collection)
    place(e, parent, Matrix.Translation(Vector(pos)))
    return e


def mesh_obj(name, builder, collection, parent, mg_local=None, mirror_x=False):
    me = builder.to_mesh(name, MATS, mirror_x=mirror_x)
    o = bpy.data.objects.new(name, me)
    link(o, collection)
    place(o, parent, mg_local if mg_local is not None else Matrix.Identity(4))
    return o


def T(v):
    return Matrix.Translation(Vector(v))


def RX(a):
    return Matrix.Rotation(a, 4, 'X')


def RY(a):
    return Matrix.Rotation(a, 4, 'Y')


def RZ(a):
    return Matrix.Rotation(a, 4, 'Z')


root = bpy.data.objects.new("MT8_Root", None)
root.empty_display_type = 'ARROWS'
root.empty_display_size = 0.1
link(root, C_ROOT)

# ================================================================== CHASIS
ch = Builder()
PX = S.CHASSIS_PLATE_X
for s in (-1, 1):
    ch.box((s * (PX + S.CHASSIS_PLATE_T / 2), S.CHASSIS_PLATE_H / 2, 0.0),
           (S.CHASSIS_PLATE_T, S.CHASSIS_PLATE_H, S.CHASSIS_LEN), "MT8_Alu_Teal", bevel=0.0015)
    # aligeramientos (ventanas) simulados con insertos oscuros
    for zc in (-0.13, -0.045, 0.045, 0.13):
        ch.box((s * (PX + S.CHASSIS_PLATE_T + 0.0004), 0.029, zc), (0.0008, 0.028, 0.055), "MT8_Plastic_Black", bevel=0.0003)
    # bandeja lateral (bateria a la izquierda, ESC a la derecha)
    ch.box((s * 0.074, -0.002, 0.0), (0.060, 0.004, 0.16 if s < 0 else 0.08), "MT8_Alu_Teal", bevel=0.001)
# travesanos
for zc in (-0.12, 0.12):
    ch.cyl((-PX, 0.050, zc), (PX, 0.050, zc), 0.004, "MT8_Alu_Raw", segs=10)
for za in (S.Z_FRONT, S.Z_REAR):
    fz = -1 if za < 0 else 1
    # bulkhead / caja del diferencial
    ch.box((0, -0.010, za), (0.120, 0.090, 0.072), "MT8_Plastic_Grey", bevel=0.006)
    ch.cyl((-0.050, S.RIDE_Y_WHEEL, za), (0.050, S.RIDE_Y_WHEEL, za), 0.034, "MT8_Plastic_Grey", segs=24, bevel=0.003)
    for s in (-1, 1):
        ch.cyl((s * 0.050, S.RIDE_Y_WHEEL, za), (s * 0.066, S.RIDE_Y_WHEEL, za), 0.012, "MT8_Alu_Raw", segs=16)
        # soporte bieleta superior
        ch.box((s * 0.054, S.Y_ARM_UP, za), (0.016, 0.016, 0.024), "MT8_Plastic_Grey", bevel=0.002)
        ch.cyl((s * S.ARM_X_IN, S.Y_ARM_UP, za - 0.012), (s * S.ARM_X_IN, S.Y_ARM_UP, za + 0.012), 0.0028, "MT8_Steel", segs=8)
        # soportes y pasadores del brazo inferior
        for dz in (-S.ARM_PIN_DZ, S.ARM_PIN_DZ):
            ch.box((s * 0.052, S.Y_ARM_LO, za + dz), (0.018, 0.016, 0.010), "MT8_Plastic_Grey", bevel=0.002)
        ch.cyl((s * S.ARM_X_IN, S.Y_ARM_LO, za - 0.056), (s * S.ARM_X_IN, S.Y_ARM_LO, za + 0.056), 0.0028, "MT8_Steel", segs=8)
        # pasadores superiores de amortiguador
        ch.cyl((s * S.SHOCK_UP[0], S.SHOCK_UP[1], za - 0.037), (s * S.SHOCK_UP[0], S.SHOCK_UP[1], za + 0.037), 0.003, "MT8_Steel", segs=8)
        # tirantes torreta -> placas
        ch.cyl((s * 0.030, 0.105, za), (s * (PX + 0.003), 0.050, za - fz * 0.085), 0.0035, "MT8_Alu_Raw", segs=8)
        # postes de carroceria
        ch.cyl((s * 0.030, 0.034, za + fz * 0.02), (s * 0.030, 0.149 if fz < 0 else 0.141, za + fz * 0.02), 0.0035, "MT8_Plastic_Black", segs=8)
    # torreta de amortiguadores (trapecio, espesor 6 mm en z)
    tower = [(-0.050, 0.030), (0.050, 0.030), (0.100, 0.136), (-0.100, 0.136)]
    ch.prism([(x, -y) for x, y in tower], za - 0.003, za + 0.003, "MT8_Alu_Teal", bevel=0.0012,
             matrix=Matrix.Translation((0, 0, 0)) @ Matrix.Rotation(math.radians(90), 4, 'X'))
    ch.cyl((-0.098, 0.136, za), (0.098, 0.136, za), 0.004, "MT8_Alu_Raw", segs=10)
    # patin (skid plate) bajo el diferencial + rampa
    ch.box((0, -0.064, za), (0.110, 0.008, 0.100), "MT8_Plastic_Orange", bevel=0.003)
    ch.box((0, -0.048, za + fz * 0.070), (0.100, 0.007, 0.060), "MT8_Plastic_Orange", bevel=0.003,
           rot=Matrix.Rotation(fz * math.radians(-32), 4, 'X'))
# transmision central, servo, ejes centrales
ch.box((0, 0.030, -0.010), (0.072, 0.060, 0.090), "MT8_Plastic_Grey", bevel=0.006)
ch.cyl((0, 0.012, -0.056), (0, S.RIDE_Y_WHEEL + 0.004, S.Z_FRONT + 0.038), 0.005, "MT8_Steel", segs=10)
ch.cyl((0, 0.012, 0.036), (0, S.RIDE_Y_WHEEL + 0.004, S.Z_REAR - 0.038), 0.005, "MT8_Steel", segs=10)
ch.box((0, 0.030, -0.118), (0.040, 0.036, 0.022), "MT8_Plastic_Black", bevel=0.002)
ch.cyl((0, 0.050, -0.118), (0, 0.054, -0.118), 0.008, "MT8_Alu_Raw", segs=12)
CHASSIS = mesh_obj("Chassis", ch, C_CHASSIS, root)

# ================================================================== CARROCERIA
# 1) casco inferior: perfil lateral extruido, cortado por pasos de rueda, vaciado (Lexan 2 mm)
shell = Builder()
profile = [(-0.285, 0.070), (-0.288, 0.128), (-0.274, 0.150), (-0.100, 0.160), (0.075, 0.162), (0.080, 0.157),
           (0.282, 0.156), (0.286, 0.076), (0.200, 0.060), (-0.200, 0.060)]
shell.side_extrude(profile, -S.BODY_HALF_W, S.BODY_HALF_W, "MT8_Paint_Orange", bevel=0.010)
shell_obj = mesh_obj("Body_shell_tmp", shell, C_BODY, None)


def cutter_cyl(name, p0, p1, r, segs=64):
    b = Builder()
    b.cyl(p0, p1, r, "MT8_COL_Proxy", segs=segs)
    o = mesh_obj(name, b, C_BODY, None)
    return o


def cutter_box(name, center, size):
    b = Builder()
    b.box(center, size, "MT8_COL_Proxy")
    return mesh_obj(name, b, C_BODY, None)


ARCH_R = 0.162
cutters = []
for za in (S.Z_FRONT, S.Z_REAR):
    for s in (-1, 1):
        cutters.append(cutter_cyl("cut", (s * 0.105, S.RIDE_Y_WHEEL, za), (s * 0.30, S.RIDE_Y_WHEEL, za), ARCH_R))
cutters.append(cutter_box("cut_bed", (0, 0.175, 0.185), (0.33, 0.06, 0.19)))
for i, cobj in enumerate(cutters):
    mod = shell_obj.modifiers.new(f"bool{i}", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.object = cobj
    mod.solver = 'EXACT'
dg = bpy.context.evaluated_depsgraph_get()
ev = shell_obj.evaluated_get(dg)
bm_shell = bmesh.new()
bm_shell.from_mesh(ev.to_mesh())
ev.to_mesh_clear()
bmesh.ops.transform(bm_shell, matrix=CI, verts=bm_shell.verts)  # de vuelta a coords Godot
bm_shell.normal_update()
# abrir la parte inferior (las carrocerias RC son cascos huecos)
bottom = [f for f in bm_shell.faces if f.normal.y < -0.5 and f.calc_center_median().y < 0.10]
# paredes internas que deja el cortador: los pasos de rueda quedan abiertos hacia dentro, como en un casco de Lexan
bottom += [f for f in bm_shell.faces if abs(f.normal.x) > 0.9 and abs(abs(f.calc_center_median().x) - 0.105) < 0.003]
bmesh.ops.delete(bm_shell, geom=bottom, context='FACES')
for cobj in cutters:
    bpy.data.objects.remove(cobj, do_unlink=True)
bpy.data.objects.remove(shell_obj, do_unlink=True)
# espesor con solidify a traves de un objeto temporal
tmp_me = bpy.data.meshes.new("tmp")
bm_tmp = bm_shell.copy()
bmesh.ops.transform(bm_tmp, matrix=Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1))), verts=bm_tmp.verts)
bm_tmp.to_mesh(tmp_me)
tmp_me.materials.append(MATS["MT8_Paint_Orange"])
tmp_o = bpy.data.objects.new("tmp", tmp_me)
C_BODY.objects.link(tmp_o)
sol = tmp_o.modifiers.new("solid", 'SOLIDIFY')
sol.thickness = 0.002
sol.offset = -1.0
dg = bpy.context.evaluated_depsgraph_get()
ev = tmp_o.evaluated_get(dg)
bm_solid = bmesh.new()
bm_solid.from_mesh(ev.to_mesh())
ev.to_mesh_clear()
bmesh.ops.transform(bm_solid, matrix=CI, verts=bm_solid.verts)
bpy.data.objects.remove(tmp_o, do_unlink=True)
for f in bm_solid.faces:
    f.smooth = True
from mt8_geo import smooth_by_angle  # noqa: E402
smooth_by_angle(bm_solid, 35)

body = Builder()
body.add_bm(bm_solid, "MT8_Paint_Orange")
# 2) cabina (greenhouse): tronco de piramide con bisel
gh = bmesh.new()
bot = [(-0.170, -0.098), (0.170, -0.098), (0.170, 0.074), (-0.170, 0.074)]
topc = [(-0.142, -0.040), (0.142, -0.040), (0.142, 0.058), (-0.142, 0.058)]
vb = [gh.verts.new((x, 0.158, z)) for x, z in bot]
vt = [gh.verts.new((x, S.BODY_ROOF_Y, z)) for x, z in topc]
gh.faces.new(vb[::-1])
gh.faces.new(vt)
for i in range(4):
    j = (i + 1) % 4
    gh.faces.new((vb[i], vb[j], vt[j], vt[i]))
bmesh.ops.recalc_face_normals(gh, faces=gh.faces)
bmesh.ops.bevel(gh, geom=[e for e in gh.edges if not (e.verts[0].co.y < 0.16 and e.verts[1].co.y < 0.16)],
                offset=0.010, segments=3, profile=0.5, affect='EDGES', clamp_overlap=True)
smooth_by_angle(gh, 35)
body.add_bm(gh, "MT8_Paint_Orange")
gh.free()


def quad_panel(b, pts, mat, push=0.0012, inset=0.0):
    """Panel plano (ventana / calca) a partir de 4 puntos, desplazado hacia fuera a lo largo de su normal."""
    p = [Vector(x) for x in pts]
    n = (p[1] - p[0]).cross(p[3] - p[0]).normalized()
    c = sum(p, Vector()) / 4
    p = [c + (q - c) * (1 - inset) + n * push for q in p]
    bb = bmesh.new()
    vs = [bb.verts.new(q) for q in p]
    bb.faces.new(vs)
    # pequeno espesor para que se vea desde ambos lados
    ext = bmesh.ops.extrude_face_region(bb, geom=bb.faces[:])
    for v in [e for e in ext['geom'] if isinstance(e, bmesh.types.BMVert)]:
        v.co -= n * 0.0008
    bmesh.ops.recalc_face_normals(bb, faces=bb.faces)
    for f in bb.faces:
        f.smooth = False
    b.add_bm(bb, mat)
    bb.free()


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# ventanas (en caras de la cabina; esquinas recortadas con inset)
yb, yt = 0.163, S.BODY_ROOF_Y - 0.006
for s in (-1, 1):
    # laterales: plano entre (s*0.170, 0.158, z) y (s*0.142, 0.225, z)
    def sidept(z, y):
        t = (y - 0.158) / (S.BODY_ROOF_Y - 0.158)
        return (s * (0.170 + (0.142 - 0.170) * t), y, z)
    pts = [sidept(-0.070, yb), sidept(0.055, yb), sidept(0.045, yt), sidept(-0.030, yt)]
    if s > 0:
        pts = pts[::-1]
    quad_panel(body, pts, "MT8_Glass_Dark", inset=0.06)
# parabrisas y luneta
def front_pt(x, y):
    t = (y - 0.158) / (S.BODY_ROOF_Y - 0.158)
    return (x * (1 + (0.142 / 0.170 - 1) * t), y, -0.098 + 0.058 * t)


quad_panel(body, [front_pt(-0.150, yb), front_pt(0.150, yb), front_pt(0.125, yt), front_pt(-0.125, yt)][::-1],
           "MT8_Glass_Dark", inset=0.04)


def rear_pt(x, y):
    t = (y - 0.158) / (S.BODY_ROOF_Y - 0.158)
    return (x * (1 + (0.142 / 0.170 - 1) * t), y, 0.074 + (0.058 - 0.074) * t)


quad_panel(body, [rear_pt(-0.150, yb), rear_pt(0.150, yb), rear_pt(0.125, yt), rear_pt(-0.125, yt)],
           "MT8_Glass_Dark", inset=0.05)
# toma de aire en el capo, rejilla y faros
body.box((0, 0.163, -0.190), (0.110, 0.026, 0.120), "MT8_Paint_Orange", bevel=0.006)
body.box((0, 0.172, -0.2505), (0.080, 0.012, 0.004), "MT8_Plastic_Black", bevel=0.001)
body.box((0, 0.100, -0.2885), (0.240, 0.040, 0.003), "MT8_Plastic_Black", bevel=0.001)
for s in (-1, 1):
    body.cyl((s * 0.150, 0.110, -0.287), (s * 0.150, 0.110, -0.292), 0.016, "MT8_Light_White", segs=20)
    body.box((s * 0.150, 0.110, 0.2865), (0.040, 0.020, 0.004), "MT8_Light_Amber", bevel=0.001)
# barra de luces en el techo
body.box((0, S.BODY_ROOF_Y + 0.008, -0.034), (0.200, 0.012, 0.016), "MT8_Plastic_Black", bevel=0.002)
for xi in (-0.07, -0.025, 0.025, 0.07):
    body.cyl((xi, S.BODY_ROOF_Y + 0.008, -0.042), (xi, S.BODY_ROOF_Y + 0.008, -0.0445), 0.0065, "MT8_Light_Amber", segs=16)
# barandillas de la caja
for s in (-1, 1):
    body.cyl((s * 0.172, 0.170, 0.095), (s * 0.172, 0.170, 0.270), 0.0045, "MT8_Plastic_Black", segs=10)
    for zc in (0.100, 0.265):
        body.cyl((s * 0.172, 0.155, zc), (s * 0.172, 0.170, zc), 0.004, "MT8_Plastic_Black", segs=10)
# guardabarros (aletas) negros sobre los pasos de rueda
for za in (S.Z_FRONT, S.Z_REAR):
    for s in (-1, 1):
        prof = [(0.150, ARCH_R - 0.001), (0.150, ARCH_R + 0.010), (0.212, ARCH_R + 0.006), (0.212, ARCH_R - 0.004),
                (0.150, ARCH_R - 0.001)]
        rr = ARCH_R + 0.004
        ok = [a for a in range(-180, 1) if S.RIDE_Y_WHEEL - rr * math.sin(math.radians(a)) >= 0.066
              and abs(za + rr * math.cos(math.radians(a))) <= 0.280]
        a0, a1 = min(ok), max(ok)
        body.lathe_x(prof, "MT8_Plastic_Black", segs=20, x_sign=s, center=(0, S.RIDE_Y_WHEEL, za),
                     angle=math.radians(a1 - a0), start=math.radians(a0), smooth_deg=50)


# 3) calcas en relieve: numero "08" (puertas y techo) y nombre en el porton
def text_bm(txt, size, extrude=0.0006):
    cu = bpy.data.curves.new("txt", 'FONT')
    cu.body = txt
    cu.size = size
    cu.extrude = extrude
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.space_character = 1.05
    o = bpy.data.objects.new("txt", cu)
    scene.collection.objects.link(o)
    dg2 = bpy.context.evaluated_depsgraph_get()
    m = o.evaluated_get(dg2).to_mesh()
    bb = bmesh.new()
    bb.from_mesh(m)
    o.evaluated_get(dg2).to_mesh_clear()
    bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.curves.remove(cu)
    bmesh.ops.triangulate(bb, faces=bb.faces)
    for f in bb.faces:
        f.smooth = False
    return bb


def frame(u, v, n, pos):
    return Matrix(((u[0], v[0], n[0], pos[0]), (u[1], v[1], n[1], pos[1]), (u[2], v[2], n[2], pos[2]), (0, 0, 0, 1)))


num = text_bm("08", 0.070)
body.add_bm(num, "MT8_Decal_White", frame((0, 0, -1), (0, 1, 0), (1, 0, 0), (S.BODY_HALF_W + 0.0006, 0.106, 0.0)))
body.add_bm(num, "MT8_Decal_White", frame((0, 0, 1), (0, 1, 0), (-1, 0, 0), (-S.BODY_HALF_W - 0.0006, 0.106, 0.0)))
num_big = text_bm("08", 0.075)
body.add_bm(num_big, "MT8_Decal_Black", frame((1, 0, 0), (0, 0, -1), (0, 1, 0), (0, S.BODY_ROOF_Y + 0.0006, 0.012)))
name = text_bm("BISONTE", 0.034)
body.add_bm(name, "MT8_Decal_White", frame((1, 0, 0), (0, 1, 0), (0, 0, 1), (0, 0.112, 0.2856)))
# franja negra en los costados (identidad de lejos)
for s in (-1, 1):
    quad_panel(body, [(s * S.BODY_HALF_W, 0.138, -0.068), (s * S.BODY_HALF_W, 0.138, 0.068),
                      (s * S.BODY_HALF_W, 0.150, 0.068), (s * S.BODY_HALF_W, 0.150, -0.068)][::(-1 if s > 0 else 1)],
               "MT8_Decal_Black", push=0.0006)
BODY = mesh_obj("Body", body, C_BODY, root)

# ================================================================== PARACHOQUES
for tag, fz in (("F", -1), ("R", 1)):
    b = Builder()
    o = (0.0, 0.0, fz * 0.255)  # origen del nodo: anclaje al extremo del chasis
    def P(x, y, z):
        return (x - o[0], y - o[1], z - o[2])
    zb = fz * S.BUMPER_Z
    W = S.BUMPER_HALF_W
    b.cyl(P(-W, 0.030, zb), P(W, 0.030, zb), 0.010, "MT8_Plastic_Black", segs=16)
    for s in (-1, 1):
        b.sphere(P(s * W, 0.030, zb), 0.010, "MT8_Plastic_Black")
        b.cyl(P(s * 0.100, -0.020, fz * 0.305), P(s * W, 0.030, zb), 0.008, "MT8_Plastic_Black", segs=12)
        b.sphere(P(s * 0.100, -0.020, fz * 0.305), 0.008, "MT8_Plastic_Black")
        b.cyl(P(s * 0.036, -0.020, fz * 0.250), P(s * 0.100, -0.020, fz * 0.305), 0.008, "MT8_Plastic_Black", segs=12)
        b.cyl(P(s * 0.036, 0.020, fz * 0.250), P(s * 0.080, 0.030, zb), 0.007, "MT8_Plastic_Black", segs=12)
    b.cyl(P(-0.100, -0.020, fz * 0.305), P(0.100, -0.020, fz * 0.305), 0.008, "MT8_Plastic_Black", segs=12)
    b.box(P(0, -0.030, fz * 0.294), (0.170, 0.006, 0.050), "MT8_Plastic_Orange", bevel=0.002,
          rot=Matrix.Rotation(fz * math.radians(-25), 4, 'X'))
    b.box(P(0, 0.030, zb + fz * 0.0105), (0.070, 0.022, 0.002), "MT8_Decal_White", bevel=0.0005)
    mesh_obj(f"Bumper_{tag}", b, C_CHASSIS, root, T(o))

# ================================================================== PROPULSION (electrica, separable)
PROP_O = (0.0, 0.060, 0.0)
pb = Builder()


def Q(x, y, z):
    return (x - PROP_O[0], y - PROP_O[1], z - PROP_O[2])


pb.cyl(Q(0, 0.089, -0.036), Q(0, 0.089, 0.040), 0.022, "MT8_Motor_Red", segs=28, bevel=0.002)
pb.cyl(Q(0, 0.089, 0.040), Q(0, 0.089, 0.050), 0.019, "MT8_Plastic_Black", segs=28)
for k in range(5):
    zc = -0.026 + k * 0.014
    pb.cyl(Q(0, 0.089, zc), Q(0, 0.089, zc + 0.004), 0.0245, "MT8_Alu_Raw", segs=28)
pb.box(Q(0, 0.066, -0.040), (0.050, 0.012, 0.008), "MT8_Alu_Raw", bevel=0.001)
pb.box(Q(-0.074, 0.024, 0.0), (0.050, 0.046, 0.150), "MT8_Battery_Wrap", bevel=0.004)
pb.box(Q(-0.074, 0.048, 0.0), (0.054, 0.003, 0.016), "MT8_Alu_Teal", bevel=0.0008)
pb.box(Q(-0.074, 0.030, 0.0761), (0.040, 0.020, 0.001), "MT8_Decal_White")
pb.box(Q(0.072, 0.020, 0.0), (0.044, 0.036, 0.055), "MT8_Plastic_Black", bevel=0.004)
pb.cyl(Q(0.072, 0.038, 0.0), Q(0.072, 0.043, 0.0), 0.015, "MT8_Alu_Raw", segs=20)
for (a, b_, c_) in (((-0.050, 0.040, 0.06), (-0.010, 0.080, 0.05), "MT8_Motor_Red"),
                    ((0.050, 0.030, 0.02), (0.012, 0.075, 0.05), "MT8_Plastic_Black"),
                    ((0.050, 0.030, -0.02), (-0.050, 0.040, -0.06), "MT8_Motor_Red")):
    pb.cyl(Q(*a), Q(*b_), 0.0028, c_, segs=8)
PROP = mesh_obj("Propulsion", pb, C_PROP, root, T(PROP_O))

# ================================================================== ESQUINAS (suspension, direccion, ruedas)


def build_wheel():
    w = Builder()
    hw = S.TIRE_W / 2
    base = 0.0892
    prof = [(-0.036, 0.060), (-0.041, 0.066), (-0.0455, 0.074), (-0.0455, 0.080), (-0.043, 0.0852),
            (-0.037, 0.0882), (-0.025, base), (0.0, base + 0.0004), (0.025, base), (0.037, 0.0882),
            (0.043, 0.0852), (0.0455, 0.080), (0.0455, 0.074), (0.041, 0.066), (0.036, 0.060)]
    w.lathe_x(prof, "MT8_Tire_Rubber", segs=56, smooth_deg=35)
    n = 18
    for row, (xc, ang) in enumerate(((-0.019, 14), (0.019, -14))):
        for i in range(n):
            phi = 2 * math.pi * (i + 0.5 * row) / n
            r = (base + S.TIRE_R) / 2 - 0.0003
            c = (xc, r * math.cos(phi), r * math.sin(phi))
            w.box(c, (0.034, S.TIRE_R - base + 0.0006, 0.019), "MT8_Tire_Rubber", bevel=0.0018, segs=1,
                  rot=RX(phi) @ RY(math.radians(ang)))
            # taco de hombro
            xs = -0.040 if row == 0 else 0.040
            c2 = (xs, 0.087 * math.cos(phi), 0.087 * math.sin(phi))
            w.box(c2, (0.010, 0.012, 0.016), "MT8_Tire_Rubber", bevel=0.0015, segs=1,
                  rot=RX(phi) @ RZ(math.radians(-35 if row == 0 else 35)))
    # llanta (lado exterior = +X)
    rim = [(-0.039, 0.0650), (-0.033, 0.0650), (-0.033, 0.0585), (0.033, 0.0585), (0.033, 0.0650),
           (0.042, 0.0662), (0.042, 0.0520), (0.020, 0.0520), (-0.033, 0.0540), (-0.039, 0.0590), (-0.039, 0.0650)]
    w.lathe_x(rim, "MT8_Rim_Bronze", segs=48, smooth_deg=40)
    for k in range(6):
        phi = 2 * math.pi * k / 6
        rc = (0.018 + 0.053) / 2
        w.box((S.RIM_FACE - 0.001, rc * math.cos(phi), rc * math.sin(phi)), (0.010, 0.036, 0.012),
              "MT8_Rim_Bronze", bevel=0.002, rot=RX(phi))
    w.cyl((0.010, 0, 0), (0.030, 0, 0), 0.019, "MT8_Rim_Bronze", segs=24, bevel=0.002)
    w.cyl((0.030, 0, 0), (0.038, 0, 0), 0.0095, "MT8_Chrome", segs=6)
    for k in range(12):
        phi = 2 * math.pi * (k + 0.5) / 12
        w.cyl((0.042, 0.059 * math.cos(phi), 0.059 * math.sin(phi)), (0.0445, 0.059 * math.cos(phi), 0.059 * math.sin(phi)),
              0.0022, "MT8_Chrome", segs=6)
    return w


def build_knuckle(front):
    k = Builder()
    k.box((-0.004, 0.0, 0.0), (0.016, 0.060, 0.026), "MT8_Plastic_Black", bevel=0.003)
    for dy in (-S.BJ_DY, S.BJ_DY):
        k.sphere((0, dy, 0), 0.0065, "MT8_Steel")
    k.cyl((0.004, 0, 0), (0.009, 0, 0), 0.014, "MT8_Plastic_Black", segs=20)
    k.cyl((0.009, 0, 0), (0.024, 0, 0), 0.006, "MT8_Steel", segs=12)
    k.cyl((-S.CV_OFF - 0.004, 0, 0), (-S.CV_OFF + 0.012, 0, 0), 0.0085, "MT8_Steel", segs=16)
    if front:
        k.box((-0.010, 0.020, 0.024), (0.010, 0.008, 0.034), "MT8_Plastic_Black", bevel=0.002)
        k.sphere((-0.012, 0.026, 0.038), 0.0045, "MT8_Steel")
    else:
        k.box((-0.010, 0.020, -0.020), (0.010, 0.008, 0.024), "MT8_Plastic_Black", bevel=0.002)
    return k


def build_arm_lower():
    a = Builder()
    poly = [(0.004, -0.050), (0.060, -0.040), (0.074, -0.010), (0.150, -0.008), (0.150, 0.008), (0.074, 0.010),
            (0.060, 0.040), (0.004, 0.050)]
    a.prism(poly, -0.008, 0.0, "MT8_Plastic_Black", bevel=0.002)
    for z0, z1 in ((-0.052, -0.037), (0.037, 0.052)):
        a.cyl((0, 0, z0), (0, 0, z1), 0.0068, "MT8_Plastic_Black", segs=14)
    for dz in (-S.SHOCK_DZ, S.SHOCK_DZ):
        a.box((S.SHOCK_LO_ARM[0], 0.002, dz + (0.009 if dz < 0 else -0.009)), (0.014, 0.022, 0.005), "MT8_Plastic_Black", bevel=0.0015)
        a.cyl((S.SHOCK_LO_ARM[0], S.SHOCK_LO_ARM[1], dz - 0.009), (S.SHOCK_LO_ARM[0], S.SHOCK_LO_ARM[1], dz + 0.009), 0.0028,
              "MT8_Steel", segs=8)
    a.cyl((S.ARM_L, -0.009, 0), (S.ARM_L, 0.001, 0), 0.0085, "MT8_Plastic_Black", segs=16)
    return a


def build_link_upper():
    a = Builder()
    for xc in (0.0, S.ARM_L):
        a.cyl((xc, 0, -0.0065), (xc, 0, 0.0065), 0.0068, "MT8_Plastic_Black", segs=14)
    a.cyl((0.006, 0, 0), (S.ARM_L - 0.006, 0, 0), 0.0032, "MT8_Steel", segs=10)
    a.cyl((0.060, 0, 0), (0.095, 0, 0), 0.0050, "MT8_Alu_Raw", segs=6)
    return a


def build_shock_body():
    b = Builder()
    L = S.SHOCK_BODY_LEN
    b.cyl((0, 0, -0.005), (0, 0, 0.005), 0.0062, "MT8_Plastic_Black", segs=12)
    b.cyl((0, -0.004, 0), (0, -0.016, 0), 0.0120, "MT8_Alu_Raw", segs=20, bevel=0.0012)
    b.cyl((0, -0.016, 0), (0, -(L - 0.006), 0), 0.0095, "MT8_Alu_Teal", segs=20)
    for k in range(3):
        y = -0.030 - k * 0.025
        b.cyl((0, y, 0), (0, y - 0.0025, 0), 0.0102, "MT8_Alu_Raw", segs=20)
    b.cyl((0, -(L - 0.006), 0), (0, -L, 0), 0.0108, "MT8_Alu_Raw", segs=20, bevel=0.001)
    return b


def build_shock_shaft():
    b = Builder()
    b.cyl((0, 0, -0.005), (0, 0, 0.005), 0.0062, "MT8_Plastic_Black", segs=12)
    b.box((0, 0.008, 0), (0.008, 0.012, 0.008), "MT8_Plastic_Black", bevel=0.0015)
    b.cyl((0, S.SHOCK_CAP_LO - 0.004, 0), (0, S.SHOCK_CAP_LO, 0), 0.0145, "MT8_Alu_Raw", segs=20)
    b.cyl((0, 0.012, 0), (0, S.SHOCK_SHAFT_LEN, 0), 0.0032, "MT8_Chrome", segs=10)
    return b


def build_spring():
    b = Builder()
    b.helix((0, 0, 0), (0, -1, 0), S.SPRING_REST, 0.0128, 0.0016, 7.5, "MT8_Spring_Yellow")
    return b


def build_driveshaft_in():
    b = Builder()
    b.cyl((0.0, 0, 0), (0.012, 0, 0), 0.0095, "MT8_Steel", segs=16, bevel=0.0015)
    b.cyl((0.010, 0, 0), (S.DS_IN_LEN, 0, 0), 0.0052, "MT8_Steel", segs=12)
    return b


def build_driveshaft_out():
    b = Builder()
    b.sphere((0, 0, 0), 0.0065, "MT8_Steel", segs=14)
    b.cyl((-0.004, 0, 0), (-S.DS_OUT_LEN, 0, 0), 0.0034, "MT8_Chrome", segs=10)
    return b


def lookdir_rot(rest, cur):
    return Vector(rest).rotation_difference(Vector(cur).normalized()).to_matrix().to_4x4()


RIG = {}
for c in S.CORNERS:
    s = S.side_of(c)
    za = S.axle_z(c)
    front = c[0] == "F"
    cc = C_CORNER[c]
    mirror = s < 0
    grp = empty(f"Corner_{c}", cc, root, (0, 0, 0), size=0.02)
    arm_lo = mesh_obj(f"{c}_ArmLower", build_arm_lower(), cc, grp, T((s * S.ARM_X_IN, S.Y_ARM_LO, za)), mirror_x=mirror)
    arm_up = mesh_obj(f"{c}_ArmUpper", build_link_upper(), cc, grp, T((s * S.ARM_X_IN, S.Y_ARM_UP, za)), mirror_x=mirror)
    wc = (s * S.X_WHEEL, S.RIDE_Y_WHEEL, za)
    susp = empty(f"{c}_Suspension", cc, grp, wc, size=0.04, kind='CUBE')
    if front:
        steer = empty(f"{c}_Steer", cc, susp, (0, 0, 0), size=0.05, kind='SINGLE_ARROW')
        knuckle_parent = steer
    else:
        steer = None
        knuckle_parent = susp
    kn = mesh_obj(f"{c}_Knuckle" if front else f"{c}_Carrier", build_knuckle(front), cc, knuckle_parent, Matrix.Identity(4),
                  mirror_x=mirror)
    spin = empty(f"{c}_Spin", cc, knuckle_parent, (0, 0, 0), size=0.06, kind='CIRCLE')
    wheel = mesh_obj(f"{c}_WheelMesh", build_wheel(), cc, spin, Matrix.Identity(4), mirror_x=mirror)
    shocks = {}
    for w in ("A", "B"):
        up, lo = S.shock_points(c, w, 0.0)
        d = Vector(lo) - Vector(up)
        beta = math.atan2(d.x, -d.y)
        sb = mesh_obj(f"{c}_Shock{w}_Body", build_shock_body(), cc, grp, T(up) @ RZ(beta))
        sp = mesh_obj(f"{c}_Shock{w}_Spring", build_spring(), cc, sb, T((0, -S.SHOCK_CAP_UP, 0)))
        lo_local = Vector((s * S.SHOCK_LO_ARM[0], S.SHOCK_LO_ARM[1], (lo[2] - za)))
        sh = mesh_obj(f"{c}_Shock{w}_Shaft", build_shock_shaft(), cc, arm_lo, T(lo_local) @ RZ(beta))
        shocks[w] = (sb, sp, sh)
    pin, pout = S.cv_points(c, 0.0, 0.0)
    ds = mesh_obj(f"{c}_DriveshaftIn", build_driveshaft_in(), cc, grp, T(pin), mirror_x=mirror)
    dso = mesh_obj(f"{c}_DriveshaftOut", build_driveshaft_out(), cc, knuckle_parent, T((-s * S.CV_OFF, 0, 0)), mirror_x=mirror)
    dso["rest_dir"] = [-s, 0.0, 0.0]
    RIG[c] = dict(arm_lo=arm_lo, arm_up=arm_up, susp=susp, steer=steer, spin=spin, shocks=shocks, ds=ds)
    # metadatos (se exportan como glTF extras)
    susp["travel_bump_m"] = S.TRAVEL_BUMP
    susp["travel_droop_m"] = S.TRAVEL_DROOP
    susp["arm_length_m"] = S.ARM_L
    if steer:
        steer["steer_min_deg"] = -S.STEER_MAX_DEG
        steer["steer_max_deg"] = S.STEER_MAX_DEG
        steer["axis"] = "+Y"
    spin["axis"] = "+X"
    ds["rest_dir"] = [s, 0.0, 0.0]

# ================================================================== PROXIES DE COLISION
COLLISION = {
    "COL_Chassis": ((0.0, -0.0025, 0.0), (0.200, 0.125, 0.540)),
    "COL_Roof": ((0.0, 0.205, 0.005), (0.320, 0.070, 0.150)),
    "COL_Side_L": ((-0.180, 0.1125, 0.0), (0.040, 0.105, 0.560)),
    "COL_Side_R": ((0.180, 0.1125, 0.0), (0.040, 0.105, 0.560)),
    "COL_Bumper_F": ((0.0, 0.0035, -0.2925), (0.280, 0.077, 0.085)),
    "COL_Bumper_R": ((0.0, 0.0035, 0.2925), (0.280, 0.077, 0.085)),
}
col_grp = empty("Collision", C_COL, root, (0, 0, 0), size=0.02)
for nm, (cen, size) in COLLISION.items():
    b = Builder()
    b.box((0, 0, 0), size, "MT8_COL_Proxy")
    o = mesh_obj(nm, b, C_COL, col_grp, T(cen))
    o["collision_proxy"] = True
    o["box_size_m"] = list(size)
    o.display_type = 'WIRE'
    o.hide_render = True

# ------------------------------------------------------------------ guardar spec + blend + glb
spec = S.spec_dict()
spec["collision_boxes"] = {k: {"center": list(v[0]), "size": list(v[1])} for k, v in COLLISION.items()}
spec["propulsion_origin"] = list(PROP_O)
spec["bumper_origins"] = {"Bumper_F": [0, 0, -0.255], "Bumper_R": [0, 0, 0.255]}
spec["blender"] = bpy.app.version_string
root["mt8_spec_version"] = S.VERSION

tris = {}
for o in C_ROOT.all_objects:
    if o.type == 'MESH' and not o.name.startswith("COL_"):
        o.data.calc_loop_triangles()
        tris[o.name] = len(o.data.loop_triangles)
spec["triangles"] = {"total_visual": sum(tris.values()), "per_object": tris}
with open(os.path.join(OUT, "mt8_spec.json"), "w") as f:
    json.dump(spec, f, indent=1)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "MT8_Bisonte.blend"))

# exportar solo la jerarquia del vehiculo
for o in bpy.data.objects:
    o.select_set(False)
for o in C_ROOT.all_objects:
    o.select_set(True)
GLTF_SETTINGS = dict(
    export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
    export_texcoords=True, export_normals=True, export_tangents=False, export_materials='EXPORT',
    export_extras=True, export_cameras=False, export_lights=False, export_animations=False,
    export_skins=False, export_morph=False, export_image_format='AUTO',
)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "MT8_Bisonte.glb"), **GLTF_SETTINGS)
with open(os.path.join(OUT, "gltf_export_settings.json"), "w") as f:
    json.dump(GLTF_SETTINGS, f, indent=1)
print("TRIS", spec["triangles"]["total_visual"])
print("OK")
