"""Desviacion geometrica del modelo de juego contra el maestro detallado (r4).

  python check_deviation.py <maestro.blend> <aircraft_game.blend> <export-map.json> --json checks/deviation.json

Usa las correspondencias de export-map.json (estado "included"; las piezas "simplified" se usan
solo como superficie de referencia y bay_equipment, que son cajas simplificadas, no se mide).
Ambos modelos en reposo, en el marco del juego (game = Rz(180) * (maestro - D0)). Mide:
  juego -> maestro: distancia de cada vertice del juego a la superficie del maestro correspondiente
  maestro -> juego: distancia de cada vertice del maestro (piezas incluidas) a la malla de juego
y reporta maximo, percentil 95 y media por malla, en mm.

Umbrales PROVISIONALES (no hay umbrales aprobados para este avion; se declaran antes de medir,
r4): percentil 95 <= 1.0 mm y maximo <= 10.0 mm en las dos direcciones, por malla. Las
diferencias conocidas y documentadas (piezas agregadas en el juego como las tapas de ranura de
los elevones, o simplificadas como la cinta de bisagra) se reportan, no se ocultan.
"""
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
MASTER, GAME, EMAP = (os.path.abspath(a) for a in argv[:3])
OUT = argv[argv.index("--json") + 1] if "--json" in argv else None
P95_MM, MAX_MM = 1.0, 10.0
FLIP = Matrix(((-1, 0, 0, 0), (0, -1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))

E = json.load(open(EMAP))
by_target, inc = {}, {}
for e in E["parts"]:
    if e["status"] == "excluded" or not e["target"] or e["target"] == "bay_equipment":
        continue
    for t in [x.strip() for x in e["target"].split("/")]:
        by_target.setdefault(t, []).append(e["source"])
        if e["status"] == "included":
            inc.setdefault(t, []).append(e["source"])

# ---- juego
bpy.ops.wm.open_mainfile(filepath=GAME)
bpy.context.scene.frame_set(1)
info = json.loads(bpy.data.texts["build_info.json"].as_string())
D0 = Vector(info["D0_master_blender"])
T = FLIP @ Matrix.Translation(-D0)


def world_mesh(o, M=None):
    dg = bpy.context.evaluated_depsgraph_get()
    oe = o.evaluated_get(dg)
    me = oe.to_mesh()
    me.calc_loop_triangles()
    mw = np.array((M or Matrix()) @ o.matrix_world)
    v = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", v)
    v = v.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
    tris = np.empty(len(me.loop_triangles) * 3, np.int64)
    me.loop_triangles.foreach_get("vertices", tris)
    oe.to_mesh_clear()
    return v, tris.reshape(-1, 3)


game = {}
for t in by_target:
    if t in bpy.data.objects:
        game[t] = world_mesh(bpy.data.objects[t])
# ---- maestro
bpy.ops.wm.open_mainfile(filepath=MASTER)
bpy.context.scene.frame_set(1)
mast, missing = {}, []
for t, srcs in by_target.items():
    vs, ts, off = [], [], 0
    for sname in srcs:
        o = bpy.data.objects.get(sname)
        if o is None or o.type != "MESH":
            missing.append(sname)
            continue
        v, tr = world_mesh(o, T)
        vs.append(v)
        ts.append(tr + off)
        off += len(v)
    mast[t] = (np.concatenate(vs), np.concatenate(ts))
mast_inc = {}
for t, srcs in inc.items():
    vs = []
    for sname in srcs:
        o = bpy.data.objects.get(sname)
        if o is not None and o.type == "MESH":
            vs.append(world_mesh(o, T)[0])
    mast_inc[t] = np.concatenate(vs) if vs else np.zeros((0, 3))


def bvh(v, t):
    return BVHTree.FromPolygons([tuple(p) for p in v], [tuple(int(i) for i in f) for f in t],
                                all_triangles=True)


def dists(points, tree):
    out = np.empty(len(points))
    for i, p in enumerate(points):
        r = tree.find_nearest(Vector(p))
        out[i] = (r[3] if r[0] is not None else np.inf)
    return out * 1000.0


XD0, ZD0 = info["D0_master_mm"]["x_from_nose"], info["D0_master_mm"]["z"]


def stats(d, pts):
    if not len(d):
        return dict(n=0)
    i = int(np.argmax(d))
    p = pts[i]
    frac = lambda lim: round(float((d > lim).mean()), 5)
    return dict(n=int(len(d)), max_mm=round(float(d.max()), 3), p95_mm=round(float(np.percentile(d, 95)), 3),
                p99_mm=round(float(np.percentile(d, 99)), 3), mean_mm=round(float(d.mean()), 3),
                fraction_over_1mm=frac(1.0), fraction_over_5mm=frac(5.0),
                max_at=dict(blender_m=[round(float(c), 4) for c in p], s_mm=round(float(p[0] * 1000), 1),
                            x_from_nose_mm=round(float(XD0 - p[1] * 1000), 1),
                            z_master_mm=round(float(p[2] * 1000 + ZD0), 1)))


per, errs = {}, []
for t in sorted(game):
    gv, gt = game[t]
    mv, mt = mast[t]
    g2m = dists(gv, bvh(mv, mt))
    m2g = dists(mast_inc.get(t, np.zeros((0, 3))), bvh(gv, gt))
    per[t] = dict(master_objects=by_target[t], game_to_master=stats(g2m, gv),
                  master_to_game=stats(m2g, mast_inc.get(t, np.zeros((0, 3)))))
    for k, st in (("juego->maestro", per[t]["game_to_master"]), ("maestro->juego", per[t]["master_to_game"])):
        if st.get("n") and (st["p95_mm"] > P95_MM or st["max_mm"] > MAX_MM):
            errs.append(f"{t} {k}: p95 {st['p95_mm']} mm, max {st['max_mm']} mm")
R = dict(master=os.path.basename(MASTER), game=os.path.basename(GAME), frame="game frame, rest pose, mm",
         thresholds=dict(p95_mm=P95_MM, max_mm=MAX_MM, status="provisional, declared before "
                         "measuring; no approved thresholds were supplied for this aircraft"),
         not_measured=["bay_equipment (simplified boxes, see export-map.json)"],
         missing_master_objects=missing, per_mesh=per, exceedances=errs, passed=not errs)
if OUT:
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    json.dump(R, open(OUT, "w"), indent=1)
for t, v in per.items():
    print(f"DESV {t:20s} juego->maestro p95 {v['game_to_master'].get('p95_mm')} max {v['game_to_master'].get('max_mm')} | "
          f"maestro->juego p95 {v['master_to_game'].get('p95_mm')} max {v['master_to_game'].get('max_mm')}")
print("DESVIACION", "OK" if R["passed"] else "AVISO", errs[:6])
