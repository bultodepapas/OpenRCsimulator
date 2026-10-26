"""Paso 4 de la librea: mapa de normales (desde la altura pintada) y oclusion ambiental con
Cycles, texturas de juego 2048 y material glTF del atlas.

  python livery_bake_textures.py source/aircraft_game.blend <trabajo> textures/<librea> [--livery <librea>] [--no-material]

Entrada: <carpeta_textures>/source/x8_<librea>_*.png (4096, del pintor) y la altura: height_mm.npy
de la carpeta de trabajo o, si no existe, textures/<librea>/source/x8_<librea>_height.png (16 bits). Para
retocar la librea a mano: editar las PNG de textures/<librea>/source y volver a correr solo este
paso. Con --no-material (skins que no son la de por defecto) solo se escriben las texturas: el
.blend no se toca.
Salida:
  textures/<librea>/source/x8_<librea>_normal.png            4096, espacio tangente (MikkTSpace)
  textures/shared/x8_airframe_occlusion.png  2048, oclusion de la geometria ya como canal R del ORM
                                             (una para todas las skins; se hornea solo si falta
                                             o con --rebake-ao)
  textures/<librea>/x8_<librea>_base_color.jpg               2048 sRGB      (van empaquetadas en el GLB)
  textures/<librea>/x8_<librea>_orm.png                      2048 lineal: R oclusion, G rugosidad, B metal
  textures/<librea>/x8_<librea>_normal.png                   2048 lineal
  textures/<librea>/x8_<librea>_emission.jpg                 2048 sRGB
y el material x8_livery del .blend con esas cuatro imagenes empaquetadas (Principled + nodo
"glTF Material Output" para la oclusion).
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import bpy
from PIL import Image
import x8_game_spec as S

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
LIV = argv[argv.index("--livery") + 1] if "--livery" in argv else S.DEFAULT_LIVERY
NO_MAT = "--no-material" in argv
pos = [a for i, a in enumerate(argv) if not a.startswith("--") and (i == 0 or argv[i - 1] != "--livery")]
BLEND, WORK, TEX = (os.path.abspath(a) for a in pos[:3])
SRC = os.path.join(TEX, "source")
PRE = f"x8_{LIV}_"
RS, RR = S.LIVERY_RES_SOURCE, S.LIVERY_RES_RUNTIME
bpy.ops.wm.open_mainfile(filepath=BLEND)
sc = bpy.context.scene
ob = bpy.data.objects
objs = [ob[n] for n in S.LIVERY_PARTS]
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.render.bake.use_clear = True
sc.render.bake.target = "IMAGE_TEXTURES"
SAVED = {o.name: [m.name for m in o.data.materials] for o in objs}


def np_to_image(name, arr, colorspace="Non-Color", float_buffer=True):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=float_buffer)
    img.colorspace_settings.name = colorspace
    rgba = np.ones((h, w, 4), np.float32)
    if arr.ndim == 2:
        rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = arr
    else:
        rgba[..., :3] = arr[..., :3]
    img.pixels.foreach_set(rgba[::-1].ravel())          # Blender: fila 0 abajo
    return img


def image_to_np(img):
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    return px.reshape(h, w, 4)[::-1]


def run_bake(kind, target, shader, samples=1, margin=16, **kw):
    dummy = bpy.data.images.new("bake_dummy", 8, 8)
    dm = bpy.data.materials.new("BAKE_dummy")
    dm.use_nodes = True
    dn = dm.node_tree.nodes.new("ShaderNodeTexImage")
    dn.image = dummy
    dm.node_tree.nodes.active = dn
    mat = bpy.data.materials.new("BAKE_" + kind)
    mat.use_nodes = True
    nt = mat.node_tree
    shader(nt)
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = target
    nt.nodes.active = tn
    for o in objs:
        for i, nm in enumerate(SAVED[o.name]):
            o.data.materials[i] = mat if nm == "x8_livery" else dm
    for o in ob:
        o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    sc.cycles.samples = samples
    sc.render.bake.margin = margin
    sc.render.bake.margin_type = "EXTEND"
    bpy.ops.object.bake(type=kind, margin=margin, use_clear=True, **kw)
    for o in objs:
        for i, nm in enumerate(SAVED[o.name]):
            o.data.materials[i] = bpy.data.materials[nm]
    print("horneado", kind, target.size[:])


# ------------------------------------------------------------------ normales desde la altura
_hn = os.path.join(WORK, "height_mm.npy")
if os.path.exists(_hn):
    H = np.load(_hn)
else:                                                   # altura de 16 bits de textures/source
    H = np.asarray(Image.open(os.path.join(SRC, PRE + "height.png")), np.float64) / 65535 * 4 - 2
from scipy import ndimage
H = ndimage.gaussian_filter(H, 0.6)                    # quita escalones de un texel
himg = np_to_image("height_m", (H + 2.0) / 4.0)       # 0..1 = -2..+2 mm
nimg = bpy.data.images.new("normal_bake", RS, RS, alpha=False, float_buffer=True)
nimg.colorspace_settings.name = "Non-Color"


def bump_shader(nt):
    b = nt.nodes.get("Principled BSDF")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = himg
    t.interpolation = "Cubic"
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 1.0
    bp.inputs["Distance"].default_value = 0.004          # 1.0 de textura = 4 mm
    nt.links.new(t.outputs["Color"], bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])


run_bake("NORMAL", nimg, bump_shader, samples=1, normal_space="TANGENT")
N4 = image_to_np(nimg)[..., :3]
Image.fromarray((np.clip(N4, 0, 1) * 255 + 0.5).astype(np.uint8)).save(
    os.path.join(SRC, PRE + "normal.png"))

# ------------------------------------------------------------------ oclusion ambiental (2048)
# r4: la oclusion depende solo de la geometria y es la misma para todas las skins. Se guarda una
# vez, ya como canal R del ORM (0.25 + 0.75 x AO, 8 bits lineal), en
# textures/shared/x8_airframe_occlusion.png y se reutiliza (no se duplica por skin); con
# --rebake-ao se vuelve a hornear con Cycles y se reemplaza el archivo compartido.
AO_SHARED = os.path.join(os.path.dirname(TEX), "shared", "x8_airframe_occlusion.png")
if not os.path.exists(AO_SHARED) or "--rebake-ao" in argv:
    sc.world.light_settings.distance = 0.18
    aoimg = bpy.data.images.new("ao_bake", RR, RR, alpha=False, float_buffer=True)
    aoimg.colorspace_settings.name = "Non-Color"
    run_bake("AO", aoimg, lambda nt: None, samples=96, margin=8)
    AO = image_to_np(aoimg)[..., 0]
    os.makedirs(os.path.dirname(AO_SHARED), exist_ok=True)
    Image.fromarray(np.clip(np.clip(0.25 + 0.75 * AO, 0, 1) * 255 + 0.5, 0, 255).astype(np.uint8)).save(AO_SHARED)
print("oclusion compartida", AO_SHARED)
# ------------------------------------------------------------------ texturas de juego 2048


def load(name, mode):
    return Image.open(os.path.join(SRC, name)).convert(mode)


base = load(PRE + "base_color.png", "RGB").resize((RR, RR), Image.LANCZOS)
base.save(os.path.join(TEX, PRE + "base_color.jpg"), quality=92, subsampling=0)
emis = load(PRE + "emission.png", "RGB").resize((RR, RR), Image.LANCZOS)
emis.save(os.path.join(TEX, PRE + "emission.jpg"), quality=92, subsampling=0)
rough = np.asarray(load(PRE + "roughness.png", "L").resize((RR, RR), Image.LANCZOS), np.float32)
metal = np.asarray(load(PRE + "metallic.png", "L").resize((RR, RR), Image.LANCZOS), np.float32)
occ = np.asarray(Image.open(AO_SHARED).convert("L"), np.uint8)       # ya es 0.25 + 0.75 x AO
orm = np.stack([occ, np.clip(rough + 0.5, 0, 255).astype(np.uint8),
                np.clip(metal + 0.5, 0, 255).astype(np.uint8)], -1)
Image.fromarray(orm).save(os.path.join(TEX, PRE + "orm.png"))
n2 = np.asarray(Image.fromarray((np.clip(N4, 0, 1) * 255 + 0.5).astype(np.uint8)).resize(
    (RR, RR), Image.LANCZOS), np.float32) / 127.5 - 1
n2 /= np.maximum(np.linalg.norm(n2, axis=-1, keepdims=True), 1e-6)
Image.fromarray(((n2 + 1) * 127.5 + 0.5).astype(np.uint8)).save(os.path.join(TEX, PRE + "normal.png"))

if NO_MAT:                                  # skin adicional: solo texturas, el .blend no cambia
    print("TEXTURAS", LIV, TEX)
    raise SystemExit(0)
# ------------------------------------------------------------------ material glTF del atlas
for nm in ("height_m", "normal_bake", "ao_bake", "bake_dummy"):
    for im in [i for i in bpy.data.images if i.name.startswith(nm)]:
        bpy.data.images.remove(im)
for m in [m for m in bpy.data.materials if m.name.startswith("BAKE_")]:
    bpy.data.materials.remove(m)


def packed(fname, colorspace):
    img = bpy.data.images.load(os.path.join(TEX, fname))
    img.colorspace_settings.name = colorspace
    img.pack()
    img.name = fname
    return img


mat = bpy.data.materials["x8_livery"]
mat.use_backface_culling = True
nt = mat.node_tree
for n_ in list(nt.nodes):
    nt.nodes.remove(n_)
out = nt.nodes.new("ShaderNodeOutputMaterial")
out.location = (900, 0)
b = nt.nodes.new("ShaderNodeBsdfPrincipled")
b.location = (550, 0)
nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
tb = nt.nodes.new("ShaderNodeTexImage")
tb.image = packed(PRE + "base_color.jpg", "sRGB")
tb.location = (-300, 300)
nt.links.new(tb.outputs["Color"], b.inputs["Base Color"])
to = nt.nodes.new("ShaderNodeTexImage")
to.image = packed(PRE + "orm.png", "Non-Color")
to.location = (-300, 0)
sep = nt.nodes.new("ShaderNodeSeparateColor")
sep.location = (50, 0)
nt.links.new(to.outputs["Color"], sep.inputs["Color"])
nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
tn = nt.nodes.new("ShaderNodeTexImage")
tn.image = packed(PRE + "normal.png", "Non-Color")
tn.location = (-300, -300)
nm_ = nt.nodes.new("ShaderNodeNormalMap")
nm_.space = "TANGENT"
nm_.uv_map = "UVMap"
nm_.location = (50, -300)
nt.links.new(tn.outputs["Color"], nm_.inputs["Color"])
nt.links.new(nm_.outputs["Normal"], b.inputs["Normal"])
te = nt.nodes.new("ShaderNodeTexImage")
te.image = packed(PRE + "emission.jpg", "sRGB")
te.location = (-300, -600)
ek = "Emission Color" if "Emission Color" in b.inputs else "Emission"
nt.links.new(te.outputs["Color"], b.inputs[ek])
b.inputs["Emission Strength"].default_value = 1.0
grp = bpy.data.node_groups.get("glTF Material Output")
if grp is None:
    grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    grp.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    grp.nodes.new("NodeGroupInput")
g = nt.nodes.new("ShaderNodeGroup")
g.node_tree = grp
g.location = (550, -450)
nt.links.new(sep.outputs["Red"], g.inputs["Occlusion"])
for n_ in (tb, to, tn, te):
    n_.interpolation = "Linear"
nt.nodes.active = tb                     # Workbench (modo textura) muestra el color base
rd = bpy.data.texts.get("README_export.txt")
if rd is not None and "ABISAL" not in rd.as_string():
    rd.write("""
Libreas (r3): material x8_livery = un atlas 2048 (UVMap) con color base, ORM (R oclusion,
G rugosidad, B metal), normales (tangente, MikkTSpace) y emision. Aqui van empaquetadas las de
ABISAL (por defecto). La skin BOLIDO usa el mismo atlas: sus cuatro imagenes estan en
textures/bolido/ y se exporta con
  python source/scripts/export_glb.py source/aircraft_game.blend export/aircraft_bolido.glb --livery bolido
Fuentes 4096 y mascaras en textures/<librea>/source/. Retoque a mano: editar esas PNG y correr
  python source/scripts/livery_bake_textures.py source/aircraft_game.blend <carpeta> textures/<librea> --livery <librea> [--no-material]
Iridiscencia, barniz, incandescencia y plasma solo en los renders (render_livery.py, render_bolido.py).
""")
bpy.ops.wm.save_as_mainfile(filepath=BLEND, compress=True)
print("GUARDADO", BLEND)
