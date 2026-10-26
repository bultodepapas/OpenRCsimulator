"""Exporta export/aircraft.glb desde source/aircraft_game.blend (pose neutra, sin animacion).

  blender -b source/aircraft_game.blend --python-exit-code 1 --python source/scripts/export_glb.py -- export/aircraft.glb
  python export_glb.py source/aircraft_game.blend export/aircraft.glb      (modulo bpy 5.2.2)
  python export_glb.py source/aircraft_game.blend export/aircraft_bolido.glb --livery bolido
      (r3: misma escena con las cuatro imagenes de textures/bolido/ en el material x8_livery)

Ajustes fijos (los mismos en cualquier maquina): glTF 2.0 binario, Y arriba, solo la coleccion
EXPORT_aircraft, propiedades personalizadas -> extras, modificadores aplicados, sin camaras,
luces, animacion, compresion Draco/meshopt ni extensiones de material sin comprobar. Desde r2
se exportan tangentes: el mapa de normales del atlas se horneo con las tangentes MikkTSpace de
Blender y asi el motor no tiene que recalcularlas.
"""
import sys, os, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
import x8_game_spec as S

GLTF_SETTINGS = dict(
    export_format="GLB",
    export_yup=True,
    use_active_collection=True,
    use_active_collection_with_nested=True,
    use_selection=False,
    use_visible=False,
    use_renderable=False,
    export_extras=True,
    export_apply=True,
    export_cameras=False,
    export_lights=False,
    export_animations=False,
    export_skins=False,
    export_morph=False,
    export_materials="EXPORT",
    export_image_format="AUTO",
    export_texcoords=True,
    export_normals=True,
    export_tangents=True,                 # tangentes MikkTSpace de Blender (mapa de normales horneado)
    export_attributes=False,
    export_draco_mesh_compression_enable=False,
    export_gpu_instances=False,
    export_hierarchy_flatten_objs=False,
    export_hierarchy_full_collections=False,
)


def export(path, settings=GLTF_SETTINGS, collection=S.EXPORT_COLLECTION):
    vl = bpy.context.view_layer
    lc = vl.layer_collection.children[collection]
    vl.active_layer_collection = lc
    opts = dict(settings)
    try:
        bpy.ops.export_scene.gltf(filepath=path, **opts)
    except TypeError as e:                       # opcion desconocida en otra version
        raise SystemExit(f"exportador glTF incompatible: {e}")
    h = hashlib.sha256(open(path, "rb").read()).hexdigest()
    print("EXPORTADO", path, os.path.getsize(path), "bytes sha256", h)
    return h


def swap_livery(name, texroot=None):
    """Pone en el material x8_livery las cuatro imagenes de otra librea (mismo atlas UV). Solo en
    memoria: el .blend no se guarda."""
    if name == S.DEFAULT_LIVERY:
        return
    texroot = texroot or os.path.join(HERE, "..", "..", "textures")
    mat = bpy.data.materials[S.LIVERY_MATERIAL]
    for nd in mat.node_tree.nodes:
        if nd.type != "TEX_IMAGE" or nd.image is None:
            continue
        slot = next(k for k in S.LIVERY_SLOTS if nd.image.name.endswith(k))
        fname = f"x8_{name}_{slot}"
        old = nd.image
        im = bpy.data.images.load(os.path.abspath(os.path.join(texroot, name, fname)))
        im.colorspace_settings.name = old.colorspace_settings.name
        im.pack()
        nd.image = im
        bpy.data.images.remove(old)
        im.name = fname
    print("LIBREA", name)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    liv = None
    if "--livery" in args:
        k = args.index("--livery")
        liv = args[k + 1]
        del args[k:k + 2]
    if args and args[0].endswith(".blend"):
        bpy.ops.wm.open_mainfile(filepath=os.path.abspath(args.pop(0)))
    if liv:
        swap_livery(liv)
    out = os.path.abspath(args[0] if args else os.path.join(HERE, "..", "..", "export",
                                                            "aircraft.glb"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.context.scene.frame_set(1)
    export(out)
