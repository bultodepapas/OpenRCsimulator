"""Renderiza las capturas de la entrega 1 (blockout) a partir de out/MT8_Bisonte.blend.

Uso: python3 render_mt8.py [solo_estas ...]   -> out/renders/*.png
Cycles (CPU) con denoise para todas las vistas; la escena de estudio se crea aqui y no se exporta.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mt8_spec as S  # noqa: E402
from mt8_geo import g2b, mat_g2b  # noqa: E402
from mt8_pose import pose  # noqa: E402

OUTR = os.path.join(HERE, "out", "renders")
os.makedirs(OUTR, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, "out", "MT8_Bisonte.blend"))
sc = bpy.context.scene
root = bpy.data.objects["MT8_Root"]
COLS = [o for o in bpy.data.objects if o.name.startswith("COL_")]
for o in COLS:
    o.hide_render = True

stage = bpy.data.collections.new("Stage")
sc.collection.children.link(stage)

# --- suelo
me = bpy.data.meshes.new("ground")
s = 6.0
me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
ground = bpy.data.objects.new("Ground", me)
stage.objects.link(ground)
gm = bpy.data.materials.new("Ground")
gm.use_nodes = True
bs = gm.node_tree.nodes["Principled BSDF"]
bs.inputs["Base Color"].default_value = (0.62, 0.63, 0.64, 1)
bs.inputs["Roughness"].default_value = 0.9
me.materials.append(gm)

# --- mundo y luces
world = bpy.data.worlds.new("World")
sc.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.78, 0.82, 0.88, 1)
bg.inputs["Strength"].default_value = 0.55


def light(name, kind, loc_g, energy, size=1.0, target=(0, 0, 0)):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    if kind == 'AREA':
        ld.size = size
    if kind == 'SUN':
        ld.angle = math.radians(4)
    o = bpy.data.objects.new(name, ld)
    stage.objects.link(o)
    o.location = g2b(loc_g)
    d = g2b(target) - o.location
    o.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return o


light("Key", 'SUN', (-1.2, 2.0, -1.0), 3.2)
light("Fill", 'AREA', (1.5, 0.8, -0.6), 60, size=1.5)
light("Rim", 'AREA', (0.4, 1.0, 1.6), 80, size=1.2)

cam_d = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_d)
stage.objects.link(cam)
sc.camera = cam

sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = 20
sc.cycles.use_adaptive_sampling = True
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 6
sc.render.resolution_x = 1280
sc.render.resolution_y = 800
sc.render.film_transparent = False
sc.view_settings.view_transform = 'AgX'
sc.view_settings.look = 'AgX - Medium High Contrast'


def aim(loc_g, target_g, ortho=None, lens=50):
    cam.location = g2b(loc_g)
    d = g2b(target_g) - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y' if abs(d.normalized().z) < 0.99 else 'X').to_euler()
    if ortho:
        cam_d.type = 'ORTHO'
        cam_d.ortho_scale = ortho
    else:
        cam_d.type = 'PERSP'
        cam_d.lens = lens
    cam_d.clip_start = 0.01
    cam_d.clip_end = 50


def aim_top(ortho, below=False):
    """Vista cenital/inferior alineada con la lateral: delante a la izquierda de la imagen."""
    cam.location = (0, 0, -4.0 if below else 4.0)
    cam.rotation_euler = (math.pi, 0, -math.pi / 2) if below else (0, 0, -math.pi / 2)
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = ortho
    cam_d.clip_start = 0.01
    cam_d.clip_end = 50


def place_root(rot_g=None, ground_y=S.GROUND_Y, show_ground=True):
    mg = rot_g if rot_g is not None else Matrix.Identity(4)
    root.matrix_basis = mat_g2b(mg)
    ground.location = (0, 0, ground_y)
    ground.hide_render = not show_ground


def render(name):
    if ONLY and name not in ONLY:
        return
    sc.render.filepath = os.path.join(OUTR, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("render", name)


ONLY = set(sys.argv[1:])
GY = S.GROUND_Y
mid = (0, 0.05, 0)

# ---------------- pose de diseno
pose(0.0, 0.0)
place_root()
aim((-1.15, 0.55, -1.25), (0, 0.04, -0.02), lens=58)
render("01_tres_cuartos_delantero")
aim((1.25, 0.50, 1.10), (0, 0.04, 0.02), lens=58)
render("02_tres_cuartos_trasero")
aim((0, 0.06, -4.0), mid, ortho=0.80)
render("03_frontal")
aim((-4.0, 0.06, 0), mid, ortho=0.80)
render("04_lateral_izquierdo")
aim_top(0.88)
render("05_superior")
place_root(show_ground=False)
aim_top(0.88, below=True)
render("06_inferior")
aim((-0.95, -0.55, -0.85), (0, -0.02, 0), lens=50)
render("07_bajos_tres_cuartos")

# ---------------- extremos de suspension y direccion
place_root()
pose(S.TRAVEL_BUMP, math.radians(S.STEER_MAX_DEG))
aim((-1.15, 0.55, -1.25), (0, 0.04, -0.02), lens=58)
render("10_compresion_max_giro_izq_30")
pose(-S.TRAVEL_DROOP, -math.radians(S.STEER_MAX_DEG))
aim((-1.15, 0.55, -1.25), (0, 0.0, -0.02), lens=58)
place_root(ground_y=GY - S.TRAVEL_DROOP)
render("11_extension_max_giro_der_30")
place_root(ground_y=GY - S.TRAVEL_DROOP)
aim((0, 0.0, -4.0), (0, 0.0, 0), ortho=0.85)
render("12_frontal_extension_max")
pose(S.TRAVEL_BUMP, 0.0)
place_root(ground_y=GY + S.TRAVEL_BUMP)
aim((0, 0.06, -4.0), (0, 0.06, 0), ortho=0.80)
render("13_frontal_compresion_max")
pose(0.0, math.radians(S.STEER_MAX_DEG))
place_root()
aim_top(0.88)
render("14_superior_giro_izq_30")
tw = {"FL": S.TRAVEL_BUMP, "RR": S.TRAVEL_BUMP, "FR": -S.TRAVEL_DROOP, "RL": -S.TRAVEL_DROOP}
pose(tw, math.radians(-15))
place_root(ground_y=GY - S.TRAVEL_DROOP)
rocks = []
for cz, cx in ((S.Z_FRONT, -S.X_WHEEL), (S.Z_REAR, S.X_WHEEL)):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    r = bpy.context.active_object
    h = S.TRAVEL_BUMP + S.TRAVEL_DROOP
    r.scale = (0.16, 0.22, h)
    r.location = g2b((cx, GY - S.TRAVEL_DROOP + h / 2, cz))
    r.data.materials.append(gm)
    rocks.append(r)
aim((-1.15, 0.45, -1.25), (0, 0.0, -0.02), lens=58)
render("15_articulacion_cruzada")
for r in rocks:
    bpy.data.objects.remove(r, do_unlink=True)

# ---------------- volcado
pose(-S.TRAVEL_DROOP, 0.0)
place_root(rot_g=Matrix.Rotation(math.pi, 4, 'Z'), ground_y=-0.2405)
aim((-1.1, 0.30, -1.2), (0, -0.05, 0), lens=55)
render("20_volcado_techo")
pose(0.0, 0.0)
place_root(rot_g=Matrix.Rotation(math.radians(90), 4, 'Z'), ground_y=-0.2625)
aim((-1.05, 0.75, -1.15), (0, -0.08, 0), lens=55)
render("21_volcado_costado")

# ---------------- proxies de colision sobre el modelo
pose(0.0, 0.0)
place_root()
for o in COLS:
    if True:
        o.hide_render = False
        m = bpy.data.materials["MT8_COL_Proxy"]
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Alpha"].default_value = 0.35
        b.inputs["Base Color"].default_value = (1.0, 0.0, 0.6, 1)
        b.inputs["Emission Color"].default_value = (1.0, 0.0, 0.6, 1)
        b.inputs["Emission Strength"].default_value = 0.3
aim((-1.15, 0.55, -1.25), (0, 0.04, -0.02), lens=58)
render("30_proxies_colision")
print("DONE")
