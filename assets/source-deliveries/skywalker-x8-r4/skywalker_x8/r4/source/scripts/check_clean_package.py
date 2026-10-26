"""Prueba de paquete limpio (r4): copia el paquete a una carpeta temporal y, desde la copia,
abre el .blend con ajustes de fabrica, exporta todas las skins con el comando documentado,
compara los hashes con los GLB entregados y reimporta cada GLB en una escena vacia.

  python check_clean_package.py <raiz_del_paquete> --json checks/clean_package.json
"""
import sys, os, json, shutil, subprocess, tempfile, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import x8_game_spec as S

argv = sys.argv[1:]
PKG = os.path.abspath(argv[0])
OUT = argv[argv.index("--json") + 1] if "--json" in argv else None
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
tmp = tempfile.mkdtemp(prefix="x8_paquete_limpio_")
dst = os.path.join(tmp, os.path.basename(PKG))
shutil.copytree(PKG, dst, ignore=shutil.ignore_patterns("_work", "_tmp", "__pycache__", "*.blend1"))
probe = os.path.join(tmp, "probe.py")
open(probe, "w").write(r'''
import bpy, os, sys, json
blend = sys.argv[-2]; out = sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.open_mainfile(filepath=blend)
imgs = [dict(name=i.name, packed=bool(i.packed_file),
             exists=bool(i.packed_file) or os.path.exists(bpy.path.abspath(i.filepath))) for i in bpy.data.images]
res = dict(libraries=[l.filepath for l in bpy.data.libraries], images=imgs,
           missing=[i["name"] for i in imgs if not i["exists"]],
           texts=[t.name for t in bpy.data.texts],
           collections=[c.name for c in bpy.data.collections],
           objects=len(bpy.data.objects), cache_files=len(bpy.data.cache_files),
           extensions_used=[a for a in bpy.context.preferences.addons.keys()])
json.dump(res, open(out, "w"))
''')
r = dict(copy=dst, steps=[])
p = subprocess.run([sys.executable, probe, os.path.join(dst, "source", "aircraft_game.blend"),
                    os.path.join(tmp, "probe.json")], capture_output=True, text=True)
pr = json.load(open(os.path.join(tmp, "probe.json")))
ok_open = p.returncode == 0 and not pr["missing"] and not pr["libraries"] and pr["cache_files"] == 0
r["steps"].append(dict(step="open source/aircraft_game.blend (factory settings)", ok=ok_open, detail=pr))
exp_dir = os.path.join(tmp, "export_from_copy")
p = subprocess.run([sys.executable, os.path.join(dst, "source", "scripts", "export_all.py"),
                    os.path.join(dst, "source", "aircraft_game.blend"), exp_dir], capture_output=True, text=True)
hashes = []
for skin in S.SKIN_ORDER:
    rel = S.livery_glb(skin)
    a, b = os.path.join(PKG, rel), os.path.join(exp_dir, os.path.basename(rel))
    hashes.append(dict(skin=skin, delivered=rel, delivered_sha256=sha(a),
                       from_clean_copy_sha256=sha(b) if os.path.exists(b) else None,
                       identical=os.path.exists(b) and sha(a) == sha(b)))
r["steps"].append(dict(step="python source/scripts/export_all.py source/aircraft_game.blend <dir> (in the copy)",
                       ok=p.returncode == 0 and all(h["identical"] for h in hashes), exit_code=p.returncode,
                       hashes=hashes))
imp = os.path.join(tmp, "imp.py")
open(imp, "w").write(r'''
import bpy, sys, json
res = []
for g in sys.argv[sys.argv.index("--") + 1:-1]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ok = True
    try:
        bpy.ops.import_scene.gltf(filepath=g)
    except Exception as e:
        ok = False
    res.append(dict(glb=g.split("/")[-1], ok=ok, objects=len(bpy.data.objects),
                    meshes=sum(1 for o in bpy.data.objects if o.type == "MESH"),
                    materials=len(bpy.data.materials), images=len(bpy.data.images),
                    actions=len(bpy.data.actions), cameras=len(bpy.data.cameras), lights=len(bpy.data.lights)))
json.dump(res, open(sys.argv[-1], "w"))
''')
glbs = [os.path.join(dst, S.livery_glb(k)) for k in S.SKIN_ORDER]
p = subprocess.run([sys.executable, imp, "--", *glbs, os.path.join(tmp, "imp.json")], capture_output=True, text=True)
ir = json.load(open(os.path.join(tmp, "imp.json")))
ok_imp = p.returncode == 0 and all(x["ok"] and x["actions"] == 0 and x["cameras"] == 0 and x["lights"] == 0 and
                                   x["images"] == 4 for x in ir)
r["steps"].append(dict(step="clean re-import of every GLB (factory settings)", ok=ok_imp, detail=ir))
r["passed"] = all(s_["ok"] for s_ in r["steps"])
shutil.rmtree(tmp, ignore_errors=True)
r["copy"] = "temporary copy (deleted after the check)"
if OUT:
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    json.dump(r, open(OUT, "w"), indent=1)
print("LIMPIO", "OK" if r["passed"] else "FALLA", [s_["ok"] for s_ in r["steps"]])
sys.exit(0 if r["passed"] else 1)
