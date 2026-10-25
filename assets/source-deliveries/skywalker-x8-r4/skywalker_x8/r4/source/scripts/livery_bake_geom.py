"""Paso 2 de la librea: hornea en el atlas la posicion 3D, la normal y las mascaras de pieza y
region de cada texel (Cycles, tipo EMIT). El pintor trabaja luego en 3D con esos mapas, asi el
dibujo no depende de las costuras del UV.

  python livery_bake_geom.py source/aircraft_game.blend <carpeta_trabajo> [resolucion]

Escribe en la carpeta: build_info.json (D0), P.npy (float32, posicion en el marco del juego, m), N.npy (float16),
ID.npz (pieza, region, cobertura sin margen) y uv_layout.png. No guarda el .blend.
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import bpy
import x8_game_spec as S

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
BLEND, WORK = os.path.abspath(argv[0]), os.path.abspath(argv[1])
RES = int(argv[2]) if len(argv) > 2 else S.LIVERY_RES_SOURCE
os.makedirs(WORK, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=BLEND)
# el pintor necesita D0 del maestro: se copia el build_info.json del .blend a la carpeta
open(os.path.join(WORK, "build_info.json"), "w").write(bpy.data.texts["build_info.json"].as_string())
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 1
sc.render.bake.use_clear = True
sc.render.bake.target = "IMAGE_TEXTURES"
ob = bpy.data.objects
objs = [ob[n] for n in S.LIVERY_PARTS]

main = bpy.data.images.new("bake_main", RES, RES, alpha=True, float_buffer=True)
dummy = bpy.data.images.new("bake_dummy", 8, 8, float_buffer=True)


def bake_material(name, expr):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    expr(nt, em)
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = main
    nt.nodes.active = img
    return m


def geo_affine(socket):
    def f(nt, em):
        g = nt.nodes.new("ShaderNodeNewGeometry")
        v = nt.nodes.new("ShaderNodeVectorMath")
        v.operation = "MULTIPLY_ADD"
        nt.links.new(g.outputs[socket], v.inputs[0])
        if socket == "Position":
            v.inputs[1].default_value = (1 / 3, 1 / 3, 1 / 3)
            v.inputs[2].default_value = (0.5, 0.5, 0.5)       # (P + 1.5) / 3
        else:
            v.inputs[1].default_value = (0.5, 0.5, 0.5)
            v.inputs[2].default_value = (0.5, 0.5, 0.5)       # (N + 1) / 2
        nt.links.new(v.outputs[0], em.inputs["Color"])
    return f


def ids(nt, em):
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_type = "GEOMETRY"
    a.attribute_name = "x8_part"
    r = nt.nodes.new("ShaderNodeAttribute")
    r.attribute_type = "GEOMETRY"
    r.attribute_name = "x8_region"
    c = nt.nodes.new("ShaderNodeCombineXYZ")
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = "DIVIDE"
    m1.inputs[1].default_value = 16.0
    m2 = nt.nodes.new("ShaderNodeMath")
    m2.operation = "DIVIDE"
    m2.inputs[1].default_value = 8.0
    nt.links.new(a.outputs["Fac"], m1.inputs[0])
    nt.links.new(r.outputs["Fac"], m2.inputs[0])
    nt.links.new(m1.outputs[0], c.inputs[0])
    nt.links.new(m2.outputs[0], c.inputs[1])
    c.inputs[2].default_value = 1.0
    nt.links.new(c.outputs[0], em.inputs["Color"])


dm = bpy.data.materials.new("BAKE_dummy")
dm.use_nodes = True
dn = dm.node_tree.nodes.new("ShaderNodeTexImage")
dn.image = dummy
dm.node_tree.nodes.active = dn
SAVED = {o.name: [m.name for m in o.data.materials] for o in objs}


def run(tag, mat, margin):
    for o in objs:
        for i, nm in enumerate(SAVED[o.name]):
            o.data.materials[i] = mat if nm == "x8_livery" else dm
    for o in ob:
        o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    sc.render.bake.margin = margin
    sc.render.bake.margin_type = "EXTEND"
    bpy.ops.object.bake(type="EMIT", margin=margin, use_clear=True)
    px = np.empty(RES * RES * 4, np.float32)
    main.pixels.foreach_get(px)
    print("horneado", tag)
    return px.reshape(RES, RES, 4)


P = run("P", bake_material("BAKE_P", geo_affine("Position")), 16)
np.save(os.path.join(WORK, "P.npy"), (P[..., :3] * 3 - 1.5).astype(np.float32))
del P
N = run("N", bake_material("BAKE_N", geo_affine("Normal")), 16)
Nn = N[..., :3] * 2 - 1
Nn /= np.maximum(np.linalg.norm(Nn, axis=-1, keepdims=True), 1e-6)
np.save(os.path.join(WORK, "N.npy"), Nn.astype(np.float16))
del N, Nn
mid = bake_material("BAKE_ID", ids)
I = run("ID", mid, 16)
C = run("COV", mid, 0)
np.savez_compressed(os.path.join(WORK, "ID.npz"),
                    part=np.rint(I[..., 0] * 16).astype(np.uint8),
                    region=np.rint(I[..., 1] * 8).astype(np.uint8),
                    baked=(I[..., 2] > 0.5), inside=(C[..., 2] > 0.5))
print("cobertura con margen", float((I[..., 2] > 0.5).mean()), "sin margen", float((C[..., 2] > 0.5).mean()))
# dibujo del UV para editar a mano
from PIL import Image
lay = (C[..., 2] > 0.5)[::-1]
Image.fromarray((lay * 255).astype(np.uint8)).resize((2048, 2048)).save(os.path.join(WORK, "uv_layout.png"))
print("FIN", WORK)
