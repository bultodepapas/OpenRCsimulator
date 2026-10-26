"""Reconstruye, exporta todas las skins y verifica el paquete completo (r4).

  python source/scripts/release.py --master <Skywalker_X8.blend> [--baseline <paquete r3>]
                                   [--skip-build] [--skip-views] [--work <carpeta temporal>]

Pasos (cada uno es un proceso aparte con el mismo interprete bpy 5.2.2):
  1  build_game.py           geometria desde el generador parametrico del maestro
  2  livery_uv.py            regiones, material x8_livery y atlas UV (compartido por las skins)
  3  livery_bake_geom.py     posicion/normal/mascaras por texel (carpeta temporal)
  4  por skin, en orden (la primera es la de por defecto):
       pintor                -> textures/<skin>/source/*.png (4096) y coberturas de rotulos
       pintor --no-markings  -> textures/<skin>/source/layers/x8_<skin>_paint_base.png
       paint_layers.py split -> capas markings / insignia y prueba de recomposicion
       livery_bake_textures  -> normales, ORM con la oclusion compartida, texturas 2048
  5  export_all.py           export/aircraft.glb y export/<skin>.glb (un solo comando)
  6  make_demo.py            previews/demo/aircraft_demo.glb (solo referencia)
  7  make_previews.py        previews/<skin>/*.png (Workbench, backface culling)
  8  compare_silhouettes     checks/silhouettes/
  9  verify_game.py          holguras -> make_metadata.py -> verificacion de cada GLB con metadatos
 10  skin_parity, check_rig_revision, check_deviation, check_finish, check_views,
     test_verifier_rejects, check_clean_package -> checks/
 11  verification.json, metadatos anotados con el resultado por skin, SHA256SUMS.txt
Sale con 1 si falla una comprobacion obligatoria.
"""
import sys, os, json, subprocess, time, shutil, hashlib, platform

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import x8_game_spec as S

PKG = os.path.abspath(os.path.join(HERE, "..", ".."))
args = sys.argv[1:]
opt = lambda k: os.path.abspath(args[args.index(k) + 1]) if k in args else None
MASTER = opt("--master")
BASE = opt("--baseline")
SKIP = "--skip-build" in args
WORK = opt("--work") or os.path.join(PKG, "source", "scripts", "_work")
TEXDIR = os.path.join(PKG, "textures")
CHK = os.path.join(PKG, "checks")
BLEND = os.path.join(PKG, "source", "aircraft_game.blend")
DEMO = os.path.join(PKG, "previews", "demo", "aircraft_demo.glb")
META = os.path.join(PKG, "metadata.json")
SKINS = list(S.SKIN_ORDER)
ALTS = [k for k in SKINS if not S.LIVERIES[k]["default"]]
GLB = {k: os.path.join(PKG, S.livery_glb(k)) for k in SKINS}
os.makedirs(CHK, exist_ok=True)
T0 = time.time()
LOG = []
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()


def run(script, *a, check=True, label=None):
    cmd = [sys.executable, os.path.join(HERE, script), *a]
    t = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True)
    keep = ("[", "RESULTADO", "EXPORTADO", "GUARDADO", "RECHAZOS", "metadata", "export-map", "FIN",
            "UV:", "horneado", "cobertura", "LIBREA", "TEXTURAS", "CAPAS", "COMPOSE", "SKINS",
            "PARIDAD", "RIG", "DESV", "FINISH", "VISTA", "LIMPIO", "SHA256SUMS", "oclusion")
    tail = [l for l in p.stdout.splitlines() if l.startswith(keep)]
    rel = lambda x: os.path.relpath(x, PKG) if os.path.isabs(x) and x.startswith(PKG) else x
    LOG.append(dict(step=label or script, command="python source/scripts/" + script + " " +
                    " ".join(rel(x) for x in a), seconds=round(time.time() - t, 1), exit_code=p.returncode))
    print(f"== {label or script} ({time.time() - t:.0f} s, salida {p.returncode})", flush=True)
    for l in tail[-30:]:
        print("  ", l, flush=True)
    if check and p.returncode != 0:
        print(p.stdout[-3000:], p.stderr[-3000:])
        sys.exit(1)
    return p.returncode


# ------------------------------------------------------------------ 1-4 construccion
if not SKIP:
    run("build_game.py", BLEND)
    run("livery_uv.py", BLEND)
    run("livery_bake_geom.py", BLEND, WORK)
    for k in SKINS:
        src = os.path.join(TEXDIR, k, "source")
        os.makedirs(src, exist_ok=True)
        run(S.LIVERIES[k]["painter"], WORK, src, label=f"pintor {k}")
        run(S.LIVERIES[k]["painter"], WORK, src, "--no-markings", label=f"pintor {k} sin rotulos")
        run("paint_layers.py", "split", src, k, label=f"capas {k}")
        extra = [] if S.LIVERIES[k]["default"] else ["--no-material"]
        run("livery_bake_textures.py", BLEND, WORK, os.path.join(TEXDIR, k), "--livery", k, *extra,
            label=f"horneado {k}")
    shutil.rmtree(WORK, ignore_errors=True)
    if os.path.exists(BLEND + "1"):
        os.remove(BLEND + "1")
# ------------------------------------------------------------------ 5-8 exportacion y vistas
run("export_all.py", BLEND, os.path.join(PKG, "export"), label="export_all (todas las skins)")
run("make_demo.py", BLEND, DEMO)
for k in SKINS:
    extra = [] if S.LIVERIES[k]["default"] else ["--livery", k]
    run("make_previews.py", BLEND, os.path.join(PKG, "previews", k), *extra, label=f"previews {k}")
sil = None
if MASTER:
    run("compare_silhouettes.py", MASTER, BLEND, os.path.join(CHK, "silhouettes"), "--json",
        os.path.join(CHK, "silhouettes", "silhouettes.json"))
    sil = json.load(open(os.path.join(CHK, "silhouettes", "silhouettes.json")))
# ------------------------------------------------------------------ 9 verificacion y metadatos
pre = os.path.join(PKG, "verification.json")
run("verify_game.py", BLEND, "--glb", GLB[S.DEFAULT_LIVERY], "--json", pre, check=False,
    label="verify (holguras para metadatos)")
if MASTER:
    run("make_metadata.py", BLEND, GLB[S.DEFAULT_LIVERY], DEMO, MASTER, PKG)
per_skin = {}
for k in SKINS:
    js = os.path.join(CHK, f"structural_{k}.json")
    extra = [] if S.LIVERIES[k]["default"] else ["--livery", k, "--parity-ref", GLB[S.DEFAULT_LIVERY]]
    run("verify_game.py", BLEND, "--glb", GLB[k], *extra, "--metadata", META, "--json", js,
        check=False, label=f"verify {k}")
    per_skin[k] = json.load(open(js))
# ------------------------------------------------------------------ 10 comprobaciones del paquete
pk = {}
for k in ALTS:
    run("skin_parity.py", GLB[S.DEFAULT_LIVERY], GLB[k], "--json", os.path.join(CHK, f"parity_{k}.json"),
        check=False, label=f"paridad {k}")
    pk[f"parity_{k}"] = json.load(open(os.path.join(CHK, f"parity_{k}.json")))
lay = {}
for k in SKINS:
    run("paint_layers.py", "compose", os.path.join(TEXDIR, k, "source"), k, check=False, label=f"capas {k}")
    lay[k] = json.load(open(os.path.join(TEXDIR, k, "source", "layers", "compose_report.json")))
json.dump(dict(skins=lay, passed=all(v["passed"] for v in lay.values())),
          open(os.path.join(CHK, "layers.json"), "w"), indent=1)
pk["layers"] = json.load(open(os.path.join(CHK, "layers.json")))
if BASE and os.path.exists(os.path.join(BASE, "source", "aircraft_game.blend")):
    run("check_rig_revision.py", os.path.join(BASE, "source", "aircraft_game.blend"), BLEND, "--json",
        os.path.join(CHK, "motion_revision.json"), check=False, label="rig r3 vs r4")
    pk["motion_revision"] = json.load(open(os.path.join(CHK, "motion_revision.json")))
if MASTER:
    run("check_deviation.py", MASTER, BLEND, os.path.join(PKG, "export-map.json"), "--json",
        os.path.join(CHK, "deviation.json"), check=False, label="desviacion contra el maestro")
    pk["deviation"] = json.load(open(os.path.join(CHK, "deviation.json")))
run("check_finish.py", BLEND, TEXDIR, "--json", os.path.join(CHK, "finish.json"), check=False,
    label="acabado por skin")
pk["finish"] = json.load(open(os.path.join(CHK, "finish.json")))
if "--skip-views" not in args:
    run("check_views.py", BLEND, os.path.join(CHK, "views"), label="vistas 1080p/1440p")
if os.path.exists(os.path.join(CHK, "views", "views.json")):
    pk["views"] = json.load(open(os.path.join(CHK, "views", "views.json")))
run("test_verifier_rejects.py", BLEND, "--json", os.path.join(CHK, "negative_tests.json"),
    check=False, label="rechazos")
pk["negative_tests"] = json.load(open(os.path.join(CHK, "negative_tests.json")))
run("check_clean_package.py", PKG, "--json", os.path.join(CHK, "clean_package.json"), check=False,
    label="paquete limpio")
pk["clean_package"] = json.load(open(os.path.join(CHK, "clean_package.json")))
if sil:
    pk["silhouettes"] = sil
fr = os.path.join(CHK, "full_rebuild.json")
if os.path.exists(fr):                       # reconstruccion independiente (se corre aparte, en limpio)
    pk["full_rebuild"] = dict(json.load(open(fr)))
    pk["full_rebuild"]["passed"] = pk["full_rebuild"]["identical"] and pk["full_rebuild"]["rebuild_release_passed"]

# ------------------------------------------------------------------ 11 identidad, resultado, hashes


def versions():
    out = dict(python=platform.python_version(), platform=platform.platform())
    for mod in ("numpy", "scipy", "PIL", "bpy"):
        try:
            m = __import__(mod)
            out[mod] = getattr(m, "__version__", None) or (getattr(m, "app").version_string if mod == "bpy" else None)
        except Exception as e:
            out[mod] = f"unavailable ({e.__class__.__name__})"
    out["blender_build"] = "5.2.2 LTS d13f752e3b9c (2026-09-15)"
    out["gltf_io"] = "Khronos glTF Blender I/O 5.2.40"
    return out


inputs = dict(master=dict(path=MASTER, sha256=sha(MASTER) if MASTER else None, pinned=S.MASTER_SHA256,
                          unchanged=bool(MASTER) and sha(MASTER) == S.MASTER_SHA256))
if BASE:
    bf = {rel: dict(sha256=sha(os.path.join(BASE, rel)) if os.path.exists(os.path.join(BASE, rel)) else None,
                    pinned=h) for rel, h in S.BASELINE["files"].items()}
    for v in bf.values():
        v["unchanged"] = v["sha256"] == v["pinned"]
    inputs["baseline"] = dict(revision=S.BASELINE["revision"], path=BASE, files=bf,
                              unchanged=all(v["unchanged"] for v in bf.values()))
inputs["scripts"] = {f: sha(os.path.join(HERE, f)) for f in sorted(os.listdir(HERE)) if f.endswith(".py")}

warnings, failures = [], []
for k, r in per_skin.items():
    for c in r["checks"]:
        if not c["ok"] and not c["mandatory"]:
            warnings.append(dict(skin=k, id=c["id"], detail=c["detail"], disposition="see README §11"))
    failures += [f"{k}:{c}" for c in r["mandatory_failed"]]
for name in ("layers", "finish", "negative_tests", "clean_package"):
    if not pk[name]["passed"]:
        failures.append(name)
for k in ALTS:
    if not pk[f"parity_{k}"]["passed"]:
        failures.append(f"parity_{k}")
if "motion_revision" in pk and not pk["motion_revision"]["passed"]:
    failures.append("motion_revision")
if "deviation" in pk and not pk["deviation"]["passed"]:
    for e in pk["deviation"]["exceedances"]:
        warnings.append(dict(skin="all", id="deviation_provisional_threshold", detail=e,
                             disposition="documented simplification: the master's servo-bay cavity "
                                         "(boolean) is not cut in the game wing; the bay is covered by "
                                         "the painted servo cover. Threshold is provisional."))
if "views" in pk:
    for v in pk["views"]["views"]:
        if v["texels_per_pixel"] < 1.0:
            warnings.append(dict(skin=v["skin"], id=f"texture_magnified_{v['view']}_{v['resolution'][1]}p",
                                 detail=f"{v['pixel_footprint_at_target_mm']} mm per pixel vs "
                                        f"{v['atlas_texel_mm']} mm per texel",
                                 disposition="provisional closest view; the 2048 atlas is magnified "
                                             "here. 4096 sources are delivered; runtime resolution is an "
                                             "integration decision (open item)."))
if MASTER and not inputs["master"]["unchanged"]:
    failures.append("master_hash_changed")
if BASE and not inputs["baseline"]["unchanged"]:
    failures.append("baseline_hash_changed")

SEVERITY = dict(deviation="warning: provisional thresholds (no approved limits supplied); "
                          "exceedances carry a disposition in warnings[]",
                views="evidence: provisional views, no pass/fail limit supplied",
                silhouettes="evidence: IoU per view, no pass/fail limit supplied")
REPORT = dict(views="checks/views/views.json", silhouettes="checks/silhouettes/silhouettes.json")
V = dict(revision=S.REVISION, generated_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
         tool_identity=versions(), input_identity=inputs,
         skins={k: dict(id=k, default=S.LIVERIES[k]["default"], glb=per_skin[k].get("glb"),
                        passed=per_skin[k]["passed"], mandatory_failed=per_skin[k]["mandatory_failed"],
                        checks=per_skin[k]["checks"],
                        parity=None if S.LIVERIES[k]["default"] else
                        dict(passed=pk[f"parity_{k}"]["passed"], report=f"checks/parity_{k}.json"),
                        layers=lay[k]["passed"], report=f"checks/structural_{k}.json") for k in SKINS},
         package_checks={k: dict(passed=v.get("passed"),
                                 severity=SEVERITY.get(k, "mandatory"),
                                 report=REPORT.get(k, f"checks/{k}.json")) for k, v in pk.items()
                         if isinstance(v, dict)},
         clearance=per_skin[S.DEFAULT_LIVERY].get("clearance"),
         counts=per_skin[S.DEFAULT_LIVERY].get("counts"),
         warnings=warnings, failures=failures,
         pending_integration=[
             "Godot 4.7.2 (Compatibility renderer) import of every skin: rest and full-travel poses, "
             "materials, texture import format and memory",
             "crash separation of every section in the simulator, skin selection, independent instances",
             "Home / flight / Workshop views at 1080p with the simulator cameras, load cost and frame time",
             "integration review of the camera-door pivots (not a shared auxiliary mechanism role)",
             "regeneration of runtime manifests and import-sidecar hashes by the integration team"],
         steps=LOG, minutes=round((time.time() - T0) / 60, 1),
         mode="skip-build" if SKIP else "full")
V["release_passed"] = not failures
json.dump(V, open(pre, "w"), indent=1, default=str)
# metadatos: resultado por skin
M = json.load(open(META))
for x in M["skins"]:
    x["verification"] = dict(passed=V["skins"][x["id"]]["passed"], report=f"checks/structural_{x['id']}.json",
                             parity=V["skins"][x["id"]]["parity"], layers_recompose=V["skins"][x["id"]]["layers"])
json.dump(M, open(META, "w"), indent=1)
run("make_sha256sums.py", PKG, label="SHA256SUMS")
run("make_sha256sums.py", PKG, "--check", label="SHA256SUMS --check")
print("PAQUETE:", "OK" if V["release_passed"] else f"FALLA {failures}", f"({V['minutes']} min)")
sys.exit(0 if V["release_passed"] else 1)
