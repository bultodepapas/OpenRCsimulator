"""Vistas previas de la version de juego: frente, lado, arriba, abajo, 3/4, extremos de mando
y vista explosionada por secciones (Workbench). Desde r2 el modo de color es TEXTURA: se ve el
color base del atlas de la librea (sin emision, sin iridiscencia; para eso estan los renders de
Cycles en previews/renders/); los materiales planos se ven con su color.

  blender -b source/aircraft_game.blend --python source/scripts/make_previews.py -- previews/
  python make_previews.py source/aircraft_game.blend previews/
  python make_previews.py source/aircraft_game.blend previews/bolido --livery bolido
"""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
from mathutils import Vector, Matrix, Quaternion
import x8_game_spec as S

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
LIV = None
if "--livery" in ARGS:
    k_ = ARGS.index("--livery")
    LIV = ARGS[k_ + 1]
    del ARGS[k_:k_ + 2]
if ARGS and ARGS[0].endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(ARGS.pop(0)))
if LIV:                                          # r3: vistas de otra librea (skin)
    import export_glb as E
    E.swap_livery(LIV)
OUT = os.path.abspath(ARGS[0] if ARGS else os.path.join(HERE, "..", "..", "previews"))
os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
ob = bpy.data.objects
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"
sh.color_type = "TEXTURE"
sh.show_cavity = True
sh.cavity_type = "BOTH"
sh.show_object_outline = True
sh.show_backface_culling = True
sc.display.render_aa = "16"
sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
sc.render.film_transparent = False
sc.world.color = (0.86, 0.88, 0.9)
sh.background_type = "WORLD"
for m in bpy.data.materials:                     # nodo activo = color base del atlas
    if m.use_nodes:
        for nd in m.node_tree.nodes:
            if nd.type == "TEX_IMAGE" and nd.image and "base_color" in nd.image.name:
                m.node_tree.nodes.active = nd
REST = {n: ob[n].matrix_basis.copy() for n in S.ARTICULATIONS}
BASE = {o.name: o.matrix_basis.copy() for o in ob}


def pose(**ang):
    for n, m in REST.items():
        a = math.radians(ang.get(n, 0.0))
        ob[n].matrix_basis = m @ Matrix.Rotation(a, 4, "X")
    bpy.context.view_layer.update()


def bbox():
    pts = []
    for o in ob:
        if o.type == "MESH":
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    return lo, hi


cam = bpy.data.objects.new("PREVIEW_cam", bpy.data.cameras.new("PREVIEW_cam"))
sc.collection.objects.link(cam)
sc.camera = cam


def shoot(name, direction, up=(0, 0, 1), ortho=True, scale=1.08, target=None, dist=6.0, lens=50):
    lo, hi = bbox()
    c = target or (lo + hi) / 2
    d = Vector(direction).normalized()
    cam.location = c - d * dist
    if d.z < -0.99:
        cam.rotation_euler = (0.0, 0.0, 0.0)            # desde arriba, nariz hacia arriba
    elif d.z > 0.99:
        cam.rotation_euler = (0.0, math.pi, 0.0)        # desde abajo, nariz hacia arriba
    else:
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO" if ortho else "PERSP"
    cam.data.lens = lens
    cam.data.clip_end = 100
    if ortho:
        ext = hi - lo
        # ancho y alto visibles segun la direccion
        if abs(d.x) > 0.9:
            w, h = ext.y, ext.z
        elif abs(d.y) > 0.9:
            w, h = ext.x, ext.z
        else:
            w, h = ext.x, ext.y
        aspect = sc.render.resolution_x / sc.render.resolution_y
        cam.data.ortho_scale = max(w, h * aspect) * scale
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("vista", name)


pose()
shoot("front", (0, -1, 0))                        # desde delante, mirando hacia atras
shoot("side_right", (-1, 0, 0))                   # desde la derecha del piloto
shoot("top", (0, 0, -1))
shoot("underside", (0, 0, 1))
shoot("three_quarter", (0.55, -0.75, -0.42), ortho=False, dist=3.4, lens=50)
shoot("three_quarter_rear", (-0.6, 0.7, -0.35), ortho=False, dist=3.4, lens=50)
mx = S.ELEVON_RANGES["mechanical_full_servo_travel"]
pose(elevon_left_hinge=mx[1], elevon_right_hinge=mx[0])
shoot("controls_roll_right_elevons", (0.55, 0.55, -0.35), ortho=False, dist=3.0, lens=50)
pose(elevon_left_hinge=mx[0], elevon_right_hinge=mx[0])
shoot("controls_pitch_up_elevons", (-0.42, 0.8, -0.42), ortho=False, dist=3.0, lens=50)
pose(elevon_left_hinge=mx[1], elevon_right_hinge=mx[1])
shoot("controls_pitch_down_elevons", (-0.42, 0.8, -0.42), ortho=False, dist=3.0, lens=50)
pose(elevon_left_hinge=mx[0], elevon_right_hinge=mx[1])
shoot("controls_roll_left_elevons", (-0.42, 0.8, -0.42), ortho=False, dist=3.0, lens=50)
pose(camera_door_left_hinge=S.DOOR_RANGE[1], camera_door_right_hinge=S.DOOR_RANGE[1])
lo, hi = bbox()
shoot("controls_camera_doors_open", (0.35, -0.45, 0.82), ortho=False, dist=1.3, lens=50,
      target=ob["camera_door_left_hinge"].matrix_world.translation * 0.5
      + ob["camera_door_right_hinge"].matrix_world.translation * 0.5)
pose()

# vista explosionada: cada seccion se aleja en su direccion (las bisagras van con su seccion)
OFF = {"wing_left": (-0.35, 0, 0), "wing_right": (0.35, 0, 0), "canopy": (0, 0, 0.30),
       "engine": (0, -0.22, 0), "propeller": (0, -0.45, 0)}
for o in ob:
    if o.parent and o.parent.name == S.ROOT:
        sec = o.get(S.SECTION_KEY)
        if o.name == "thrust_frame":
            sec = "propeller"
        if sec in OFF:
            o.matrix_basis = Matrix.Translation(OFF[sec]) @ BASE[o.name]
bpy.context.view_layer.update()
shoot("exploded_sections", (0.55, -0.7, -0.45), ortho=False, dist=4.2, lens=50)
shoot("exploded_sections_top", (0, 0, -1), ortho=True, scale=1.05)
shoot("exploded_sections_underside", (0.3, -0.5, 0.8), ortho=False, dist=4.2, lens=50)
for o in ob:
    if o.name in BASE:
        o.matrix_basis = BASE[o.name]
pose()
print("FIN", OUT)
