"""export/aircraft_demo.glb: demostracion de articulaciones y secciones (solo referencia).

Linea de tiempo (24 fps, una sola animacion "demo"):
  1-24     neutro
  25-96    elevon izquierdo: 0 -> +26.85 (borde de salida abajo) -> -26.76 -> 0
  97-168   elevon derecho:   igual
  169-240  compuerta izquierda: 0 -> 110 -> 0
  241-312  compuerta derecha:  0 -> 110 -> 0
  313-408  helice: 4 vueltas en sentido positivo (horario visto desde atras)
  409-432  neutro
  433-480  vista explosionada: cada seccion se aleja
  481-520  pausa
  521-560  vuelve a armarse y queda en neutro

  python make_demo.py source/aircraft_game.blend export/aircraft_demo.glb
  blender -b source/aircraft_game.blend --python source/scripts/make_demo.py -- export/aircraft_demo.glb
El .blend no se guarda: la animacion solo vive en el GLB de demostracion.
"""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
from mathutils import Matrix, Quaternion
import x8_game_spec as S
import export_glb as E

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
if args and args[0].endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.pop(0)))
OUT = os.path.abspath(args[0] if args else os.path.join(HERE, "..", "..", "export",
                                                        "aircraft_demo.glb"))
sc = bpy.context.scene
ob = bpy.data.objects
sc.render.fps = 24
sc.frame_start, sc.frame_end = 1, 560
mx = S.ELEVON_RANGES["mechanical_full_servo_travel"]
REST = {n: ob[n].matrix_basis.copy() for n in S.ARTICULATIONS}
LAST = {}


def key_angle(node, frame, deg):
    o = ob[node]
    q = (REST[node] @ Matrix.Rotation(math.radians(deg), 4, "X")).to_quaternion()
    if node in LAST and LAST[node].dot(q) < 0:          # camino corto en la interpolacion
        q.negate()
    LAST[node] = q
    o.rotation_quaternion = q
    o.keyframe_insert("rotation_quaternion", frame=frame)


def sweep(node, f0, f1, a0, a1, step=3):
    n = max(1, (f1 - f0) // step)
    for i in range(n + 1):
        f = f0 + (f1 - f0) * i / n
        key_angle(node, round(f), a0 + (a1 - a0) * i / n)


for n in S.ARTICULATIONS:
    key_angle(n, 1, 0.0)
    key_angle(n, 24, 0.0)
for node, f0 in (("elevon_left_hinge", 25), ("elevon_right_hinge", 97)):
    sweep(node, f0, f0 + 24, 0.0, mx[1])
    sweep(node, f0 + 24, f0 + 48, mx[1], mx[0])
    sweep(node, f0 + 48, f0 + 71, mx[0], 0.0)
for node, f0 in (("camera_door_left_hinge", 169), ("camera_door_right_hinge", 241)):
    sweep(node, f0, f0 + 30, 0.0, S.DOOR_RANGE[1])
    sweep(node, f0 + 30, f0 + 42, S.DOOR_RANGE[1], S.DOOR_RANGE[1])
    sweep(node, f0 + 42, f0 + 71, S.DOOR_RANGE[1], 0.0)
sweep("propeller_spin", 313, 408, 0.0, 4 * 360.0, step=2)
for n in S.ARTICULATIONS:
    key_angle(n, 432, 0.0)
    key_angle(n, 560, 0.0)

OFF = {"wing_left": (-0.35, 0, 0), "wing_right": (0.35, 0, 0), "canopy": (0, 0, 0.30),
       "engine": (0, -0.22, 0), "propeller": (0, -0.45, 0)}
for o in ob:
    if o.parent and o.parent.name == S.ROOT:
        sec = "propeller" if o.name == "thrust_frame" else o.get(S.SECTION_KEY)
        if sec in OFF:
            base = o.location.copy()
            for f, k in ((1, 0), (432, 0), (480, 1), (520, 1), (560, 0)):
                o.location = base + k * __import__("mathutils").Vector(OFF[sec])
                o.keyframe_insert("location", frame=f)
            o.location = base
for act in bpy.data.actions:
    try:
        curves = act.fcurves
    except Exception:
        curves = [fc for l in act.layers for st in l.strips for cb in st.channelbags
                  for fc in cb.fcurves]
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"

demo = dict(E.GLTF_SETTINGS, export_animations=True, export_animation_mode="SCENE",
            export_anim_scene_split_object=False, export_anim_slide_to_zero=True,
            export_frame_range=True, export_force_sampling=True, export_frame_step=1,
            export_optimize_animation_size=True)
sc.name = "demo"                       # nombre de la animacion en el GLB
sc.frame_set(1)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
E.export(OUT, demo)
