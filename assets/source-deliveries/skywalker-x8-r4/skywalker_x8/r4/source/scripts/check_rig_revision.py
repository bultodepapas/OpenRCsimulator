"""Compara el rig muestreado completo entre la revision base y la nueva (r4), no solo los extremos.

  python check_rig_revision.py <base.blend> <nuevo.blend> --json checks/motion_revision.json

Para cada pivote movil se recorre su rango (elevones -26.76..+26.85 grados cada 1 grado, mas los
extremos del barrido de holgura -40/+40; compuertas 0..110 cada 5; helice 0..360 cada 10) con el
resto en reposo, y en cada muestra se comparan las posiciones en el mundo de todos los vertices de
todas las mallas del avion. Tambien se compara el reposo (nombres, padres, matrices, conteos).
Sale con 1 si alguna diferencia supera 1e-6 m.
"""
import sys, os, json, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import bpy
from mathutils import Matrix
import x8_game_spec as S

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
OUT = argv[argv.index("--json") + 1] if "--json" in argv else None
A_, B_ = os.path.abspath(argv[0]), os.path.abspath(argv[1])
TOL = 1e-6


def samples():
    lo, hi = S.ELEVON_RANGES["mechanical_full_servo_travel"]
    out = {}
    for n, a in S.ARTICULATIONS.items():
        if a["kind"] == "elevon":
            v = sorted(set([round(x, 3) for x in np.arange(math.floor(lo), math.ceil(hi) + 1, 1.0)]
                           + [lo, hi, -40.0, 40.0, 0.0]))
        elif a["kind"] == "door":
            v = list(np.arange(S.DOOR_RANGE[0], S.DOOR_RANGE[1] + 0.1, 5.0))
        else:
            v = list(np.arange(0.0, 360.0, 10.0))
        out[n] = [float(x) for x in v]
    return out


SAMP = samples()


def capture(path):
    bpy.ops.wm.open_mainfile(filepath=path)
    sc = bpy.context.scene
    sc.frame_set(1)
    ob = bpy.data.objects
    rest = {n: ob[n].matrix_basis.copy() for n in S.ARTICULATIONS}
    meshes = sorted(o.name for o in ob if o.type == "MESH")
    co = {}
    for m in meshes:
        me = ob[m].data
        a = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", a)
        co[m] = a.reshape(-1, 3)
    info = dict(objects={o.name: dict(parent=o.parent.name if o.parent else None,
                                      basis=[list(r) for r in o.matrix_basis]) for o in ob},
                counts={m: len(co[m]) for m in meshes})

    def world():
        bpy.context.view_layer.update()
        out = {}
        for m in meshes:
            mw = np.array(ob[m].matrix_world)
            out[m] = co[m] @ mw[:3, :3].T + mw[:3, 3]
        return out
    poses = {"rest": world()}
    for n, vals in SAMP.items():
        for v in vals:
            ob[n].matrix_basis = rest[n] @ Matrix.Rotation(math.radians(v), 4, "X")
            poses[f"{n}@{v:g}"] = world()
        ob[n].matrix_basis = rest[n]
    return info, poses


ia, pa = capture(A_)
ib, pb = capture(B_)
errs = []
if ia["counts"] != ib["counts"]:
    errs.append("conteos de vertices distintos")
for k in ia["objects"]:
    if k not in ib["objects"]:
        errs.append(f"falta {k}")
    elif ia["objects"][k]["parent"] != ib["objects"][k]["parent"]:
        errs.append(f"{k}: padre distinto")
    else:
        d = np.max(np.abs(np.array(ia["objects"][k]["basis"]) - np.array(ib["objects"][k]["basis"])))
        if d > TOL:
            errs.append(f"{k}: reposo difiere {d:.2e}")
per_pivot, worst = {}, 0.0
for key in pa:
    if ia["counts"] != ib["counts"]:
        break
    d = max(float(np.max(np.abs(pa[key][m] - pb[key][m]))) for m in pa[key])
    piv = key.split("@")[0]
    per_pivot[piv] = max(per_pivot.get(piv, 0.0), d)
    worst = max(worst, d)
if worst > TOL:
    errs.append(f"posiciones muestreadas difieren hasta {worst:.3e} m")
R = dict(base=os.path.basename(os.path.dirname(os.path.dirname(A_))) + "/" + os.path.basename(A_),
         new=os.path.basename(os.path.dirname(os.path.dirname(B_))) + "/" + os.path.basename(B_),
         samples={k: dict(count=len(v), first=v[0], last=v[-1]) for k, v in SAMP.items()},
         poses_compared=len(pa), vertices_per_pose=sum(ia["counts"].values()),
         max_vertex_diff_m=worst, max_vertex_diff_m_by_pivot=per_pivot, tolerance_m=TOL,
         errors=errs, passed=not errs)
if OUT:
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    json.dump(R, open(OUT, "w"), indent=1)
print("RIG", "OK" if R["passed"] else "FALLA", R["poses_compared"], "poses, dif. max", worst, errs[:3])
sys.exit(0 if R["passed"] else 1)
