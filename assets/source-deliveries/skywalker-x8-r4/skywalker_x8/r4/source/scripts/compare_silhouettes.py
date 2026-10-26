"""Compara las siluetas ortograficas del maestro preciso (v3.1) y de la version de juego.

  python compare_silhouettes.py <maestro.blend> <aircraft_game.blend> <carpeta_salida> [--json r.json]

Renderiza mascaras planas (Workbench, sin sombreado) desde frente, lado y arriba con la misma
camara en el marco del juego, y mide el IoU, el area que cambia y la mayor separacion entre
contornos. Escribe tambien una imagen por vista con las diferencias en color.
"""
import sys, os, json, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
MASTER, GAME, OUT = (os.path.abspath(a) for a in argv[:3])
OUT_JSON = argv[argv.index("--json") + 1] if "--json" in argv else None
os.makedirs(OUT, exist_ok=True)
RES_X, RES_Y = 2400, 1500
HIDE = ("X8_LED", "X8_Rotulo", "X8_Marcador", "X8_Palanca", "X8_Hueco", "X8_Volumen", "Suelo",
        "PREVIEW_")
# vistas en el marco del juego (+X derecha, +Y nariz, +Z arriba): direccion de mirada, escala
VIEWS = {"front": (Vector((0, -1, 0)), 2.25), "side": (Vector((-1, 0, 0)), 1.0),
         "top": (Vector((0, 0, -1)), 2.25)}
CENTER = Vector((0.0, -0.15, 0.0))


def setup(world_to_game):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "FLAT"
    sh.color_type = "SINGLE"
    sh.single_color = (1, 1, 1)
    sh.show_cavity = False
    sh.show_object_outline = False
    sh.show_shadows = False
    sh.show_backface_culling = False
    sh.background_type = "VIEWPORT"
    sh.background_color = (0, 0, 0)
    sc.display.render_aa = "OFF"
    sc.render.resolution_x, sc.render.resolution_y = RES_X, RES_Y
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.color_mode = "BW"
    for o in bpy.data.objects:
        if o.name.startswith(HIDE) or o.type in ("FONT", "CURVE"):
            o.hide_render = True
    cam = bpy.data.objects.new("PREVIEW_cam", bpy.data.cameras.new("PREVIEW_cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.clip_end = 50
    g2w = world_to_game.inverted()
    masks = {}
    for name, (d, scale) in VIEWS.items():
        loc = CENTER - d * 5.0
        if d.z < -0.99:
            rot = Matrix.Identity(3)
        else:
            rot = d.to_track_quat("-Z", "Y").to_matrix()
        m = rot.to_4x4()
        m.translation = loc
        cam.matrix_world = g2w @ m
        cam.data.ortho_scale = scale
        path = os.path.join(OUT, f"_mask_{name}.png")
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(path)
        px = np.array(img.pixels[:]).reshape(img.size[1], img.size[0], 4)[::-1, :, 0]
        masks[name] = px > 0.5
        bpy.data.images.remove(img)
        os.remove(path)
    return masks


def dilate(m):
    o = m.copy()
    o[1:, :] |= m[:-1, :]
    o[:-1, :] |= m[1:, :]
    o[:, 1:] |= m[:, :-1]
    o[:, :-1] |= m[:, 1:]
    return o


def hausdorff_px(a, b, cap=60):
    """Pasos de dilatacion (vecindad 4) para que cada mascara cubra a la otra."""
    out = []
    for p, q in ((a, b), (b, a)):
        cur, k = p.copy(), 0
        while (q & ~cur).any() and k < cap:
            cur = dilate(cur)
            k += 1
        out.append(k)
    return max(out)


# maestro: su marco a juego con el D0 guardado en el .blend de juego
bpy.ops.wm.open_mainfile(filepath=GAME)
info = json.loads(bpy.data.texts["build_info.json"].as_string())
d0 = Vector(info["D0_master_blender"])
FLIP = Matrix(((-1, 0, 0, 0), (0, -1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
T = FLIP @ Matrix.Translation(-d0)
game_masks = setup(Matrix.Identity(4))
bpy.ops.wm.open_mainfile(filepath=MASTER)
bpy.context.scene.frame_set(1)
master_masks = setup(T)

from PIL import Image
res = {}
for name, (d, scale) in VIEWS.items():
    a, b = master_masks[name], game_masks[name]
    inter = (a & b).sum()
    union = (a | b).sum()
    mm_per_px = scale * 1000 / RES_X
    res[name] = dict(iou=round(float(inter / union), 5),
                     changed_area_mm2=round(float((a ^ b).sum()) * mm_per_px ** 2, 1),
                     master_area_mm2=round(float(a.sum()) * mm_per_px ** 2, 1),
                     max_outline_gap_mm=round(hausdorff_px(a, b) * mm_per_px, 2),
                     pixel_mm=round(mm_per_px, 3))
    rgb = np.zeros(a.shape + (3,), np.uint8)
    rgb[a & b] = (215, 215, 210)
    rgb[a & ~b] = (227, 73, 72)        # solo en el maestro
    rgb[~a & b] = (42, 120, 214)       # solo en el juego
    rgb[~a & ~b] = (252, 252, 251)
    Image.fromarray(rgb).save(os.path.join(OUT, f"silhouette_{name}.png"))
    print(name, res[name])
summary = dict(views=res, legend="gris = ambos, rojo = solo maestro, azul = solo juego",
               master=os.path.basename(MASTER), game=os.path.basename(GAME),
               note="maestro sin LED, rotulos, marcador de CG, palanca RC, suelo ni cortadores")
if OUT_JSON:
    json.dump(summary, open(OUT_JSON, "w"), indent=1)
