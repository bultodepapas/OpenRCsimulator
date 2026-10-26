"""Comprueba que verify_game.py rechaza copias desechables con defectos (salida != 0) y acepta
la copia sin tocar (salida 0). No modifica el .blend entregado.

  python test_verifier_rejects.py source/aircraft_game.blend [--json resultado.json]

Cada caso abre el .blend, aplica un defecto, lo guarda en un directorio temporal y lanza el
verificador en un proceso aparte con el mismo interprete (modulo bpy o Blender):
  base                 sin cambios                              -> debe salir 0
  sin_bisagra          se borra elevon_left_hinge (el elevon     -> debe salir != 0
                       queda colgado de la raiz en su sitio)
  etiqueta_invalida    wing_left_fixed lleva "wing_lft"         -> debe salir != 0
  sin_etiqueta         canopy_hatch sin openrc_section          -> debe salir != 0
  sin_textura_blend    se borra la imagen de normales empaquetada -> debe salir != 0
r4, sobre copias de los GLB de las skins (el .blend no se toca):
  skin_base            export/<skin>.glb sin cambios            -> debe salir 0
  skin_geometria       un vertice del ala izquierda movido 2 mm -> debe salir != 0
  skin_sin_textura     el material x8_livery pierde normalTexture y la imagen -> debe salir != 0
"""
import sys, os, json, subprocess, tempfile, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
import x8_game_spec as S
import glb_util as G
import struct

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
SRC = os.path.abspath(argv[0])
OUT_JSON = argv[argv.index("--json") + 1] if "--json" in argv else None
VERIFY = os.path.join(HERE, "verify_game.py")


def blender_cmd(script, *args):
    exe = sys.executable
    if os.path.basename(exe).lower().startswith("blender"):
        return [exe, "-b", "--factory-startup", "--python-exit-code", "1", "--python", script,
                "--", *args]
    return [exe, script, *args]


def mutate_none(ob):
    pass


def mutate_missing_hinge(ob):
    el, piv = ob["elevon_left"], ob["elevon_left_hinge"]
    mw = el.matrix_world.copy()
    el.parent = ob["SkywalkerX8"]
    el.matrix_parent_inverse.identity()
    el.matrix_basis = mw
    bpy.data.objects.remove(piv)


def mutate_invalid_tag(ob):
    ob["wing_left_fixed"]["openrc_section"] = "wing_lft"


def mutate_missing_tag(ob):
    del ob["canopy_hatch"]["openrc_section"]


def mutate_missing_texture(ob):
    mat = bpy.data.materials[S.LIVERY_MATERIAL]
    for nd in list(mat.node_tree.nodes):
        if nd.type == "TEX_IMAGE" and nd.image and nd.image.name.endswith("normal.png"):
            im = nd.image
            mat.node_tree.nodes.remove(nd)
            bpy.data.images.remove(im)


CASES = [("base", mutate_none, 0), ("sin_bisagra", mutate_missing_hinge, 1),
         ("etiqueta_invalida", mutate_invalid_tag, 1), ("sin_etiqueta", mutate_missing_tag, 1),
         ("sin_textura_blend", mutate_missing_texture, 1)]
tmp = tempfile.mkdtemp(prefix="x8_rechazos_")
res = []
for name, fn, expect_fail in CASES:
    bpy.ops.wm.open_mainfile(filepath=SRC)
    fn(bpy.data.objects)
    path = os.path.join(tmp, f"{name}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=path, copy=True)
    p = subprocess.run(blender_cmd(VERIFY, path), capture_output=True, text=True)
    failed = [l for l in p.stdout.splitlines() if l.startswith("[FALLA]")]
    ok = (p.returncode != 0) if expect_fail else (p.returncode == 0)
    res.append(dict(case=name, expected="nonzero exit" if expect_fail else "exit 0",
                    exit_code=p.returncode, ok=ok, failed_checks=[l[8:60] for l in failed]))
    print(f"{name:20s} salida {p.returncode}  {'OK' if ok else 'MAL'}  {failed[:2]}")
# ---- r4: casos sobre los GLB de cada skin adicional
PKG = os.path.dirname(os.path.dirname(SRC))
ref = os.path.join(PKG, S.livery_glb(S.DEFAULT_LIVERY))
for skin in [k for k in S.SKIN_ORDER if not S.LIVERIES[k]["default"]]:
    src_glb = os.path.join(PKG, S.livery_glb(skin))
    js0, b0 = G.read_glb(src_glb)

    def g_none(js, b):
        return js, b

    def g_geom(js, b):
        b = bytearray(b)
        mi = next(n["mesh"] for n in js["nodes"] if n["name"] == "wing_left_fixed")
        acc = js["meshes"][mi]["primitives"][-1]["attributes"]["POSITION"]
        off, stride, _ = G.accessor_location(js, acc)
        k = min(10, js["accessors"][acc]["count"] - 1)
        v = struct.unpack_from("<f", b, off + stride * k + 8)[0]
        struct.pack_into("<f", b, off + stride * k + 8, v + 0.002)
        return js, bytes(b)

    def g_tex(js, b):
        m = next(m for m in js["materials"] if m["name"] == S.LIVERY_MATERIAL)
        ti = m.pop("normalTexture")["index"]
        src = js["textures"][ti]["source"]
        js["images"].pop(src)                      # la imagen desaparece del todo
        js["textures"].pop(ti)
        for t in js["textures"]:
            if t["source"] > src:
                t["source"] -= 1

        def fix(d):
            if isinstance(d, dict):
                if "index" in d and set(d) <= {"index", "texCoord", "scale", "strength"}:
                    if d["index"] > ti:
                        d["index"] -= 1
                for v in d.values():
                    fix(v)
            elif isinstance(d, list):
                for v in d:
                    fix(v)
        fix(js["materials"])
        return js, b

    for name, fn, expect_fail in ((f"skin_base_{skin}", g_none, 0), (f"skin_geometria_{skin}", g_geom, 1),
                                  (f"skin_sin_textura_{skin}", g_tex, 1)):
        js, b = fn(json.loads(json.dumps(js0)), b0)
        path = os.path.join(tmp, f"{name}.glb")
        G.write_glb(path, js, b)
        p = subprocess.run(blender_cmd(VERIFY, SRC, "--glb", path, "--livery", skin, "--parity-ref", ref),
                           capture_output=True, text=True)
        failed = [l for l in p.stdout.splitlines() if l.startswith("[FALLA]")]
        ok = (p.returncode != 0) if expect_fail else (p.returncode == 0)
        res.append(dict(case=name, expected="nonzero exit" if expect_fail else "exit 0",
                        exit_code=p.returncode, ok=ok, failed_checks=[l[8:60] for l in failed]))
        print(f"{name:28s} salida {p.returncode}  {'OK' if ok else 'MAL'}  {failed[:2]}")
shutil.rmtree(tmp, ignore_errors=True)
all_ok = all(r["ok"] for r in res)
if OUT_JSON:
    json.dump(dict(cases=res, passed=all_ok), open(OUT_JSON, "w"), indent=1)
print("RECHAZOS:", "OK" if all_ok else "FALLA")
sys.exit(0 if all_ok else 1)
