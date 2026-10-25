"""Render the model from a camera matched to the catalog photo (+X side, slightly from the front) and
report where key 3D points land, for overlay comparison."""
import bpy, math, sys, json
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view
a = sys.argv[sys.argv.index("--") + 1:]
out = a[a.index("--out") + 1]
az = float(a[a.index("--az") + 1]) if "--az" in a else 12.0
el = float(a[a.index("--el") + 1]) if "--el" in a else 4.0
lens = float(a[a.index("--lens") + 1]) if "--lens" in a else 100.0
sc = bpy.context.scene
hide = ("LD_",) if "--muffler" in a else ("Muffler", "E61_Muffler", "MUF_", "LD_")
for c in bpy.data.collections:
    if c.name.startswith(hide):
        c.hide_render = True
    elif c.name.endswith("Muffler"):
        c.hide_render = False
for o in bpy.data.objects:
    o.hide_render = o.name.startswith(hide)
MM = 0.001
center = Vector((5, -27, 28)) * MM
cd = bpy.data.cameras.new("MATCH"); cd.lens = lens
cam = bpy.data.objects.new("MATCH", cd); sc.collection.objects.link(cam)
A, E = math.radians(az), math.radians(el)
d = 0.62 * lens / 100
cam.location = center + Vector((math.cos(A) * math.cos(E), -math.sin(A) * math.cos(E), math.sin(E))) * d
cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
sc.camera = cam
sc.render.engine = "BLENDER_WORKBENCH"
sc.render.resolution_x, sc.render.resolution_y = 948, 628
sc.render.film_transparent = True
sh = sc.display.shading
sh.light, sh.color_type, sh.show_cavity = "STUDIO", "MATERIAL", True
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
pin = bpy.data.objects["ENG_GlowPlug_Pin"]
ztop = max((pin.matrix_world @ v.co).z for v in pin.data.vertices) / MM
pts = {"shaft_tip": (0, -85.0, 0), "plug_tip": (0, 0, ztop), "case_bottom": (0, 0, -21),
       "rear_screw_low": (13, 27.8, -15.6), "rear_screw_high": (13, 27.8, 9.4), "front_face_low": (13, -30, -15.6)}
res = {}
for k, p in pts.items():
    v = world_to_camera_view(sc, cam, Vector(p) * MM)
    res[k] = (round(v.x * 948, 1), round((1 - v.y) * 628, 1))
print("@@JSON@@" + json.dumps(res))
