"""Exporta TODAS las skins desde la misma geometria y el mismo rig (r4): un solo comando.

  python source/scripts/export_all.py source/aircraft_game.blend [carpeta_export] [--textures carpeta]
  blender -b --factory-startup --python-exit-code 1 --python source/scripts/export_all.py -- \
          source/aircraft_game.blend export/

Orden = x8_game_spec.SKIN_ORDER; la primera (por defecto) va a export/aircraft.glb, las demas a
export/<skin_id>.glb. Cada skin se exporta desde el .blend recien abierto, cambiando solo las cuatro
imagenes del material x8_livery (export_glb.swap_livery); el .blend no se guarda. Ajustes del
exportador: export_glb.GLTF_SETTINGS. Imprime el sha256 de cada GLB y deja export_manifest.json
en la carpeta de salida si se pasa --manifest.
"""
import sys, os, json, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
import x8_game_spec as S
import export_glb as E

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
tex = None
if "--textures" in args:
    k = args.index("--textures")
    tex = os.path.abspath(args[k + 1])
    del args[k:k + 2]
manifest = "--manifest" in args
args = [a for a in args if a != "--manifest"]
BLEND = os.path.abspath(args[0])
OUTDIR = os.path.abspath(args[1]) if len(args) > 1 else os.path.join(os.path.dirname(BLEND), "..", "export")
os.makedirs(OUTDIR, exist_ok=True)
res = []
for skin in S.SKIN_ORDER:
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    bpy.context.scene.frame_set(1)
    E.swap_livery(skin, tex)
    out = os.path.join(OUTDIR, os.path.basename(S.livery_glb(skin)))
    h = E.export(out)
    res.append(dict(skin=skin, default=S.LIVERIES[skin]["default"], path=out, sha256=h,
                    bytes=os.path.getsize(out)))
if manifest:
    json.dump(res, open(os.path.join(OUTDIR, "export_manifest.json"), "w"), indent=1)
print("SKINS", len(res), [r["skin"] for r in res])
