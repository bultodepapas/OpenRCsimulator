"""Comprueba interferencias entre piezas en las combinaciones extremas de suspension y direccion.

Uso: python3 check_mt8.py  -> out/interference_report.json
Para cada pose construye BVH en coordenadas de mundo y busca triangulos que se cruzan.
Se ignoran los contactos que existen a proposito (bisagras, rotulas, ojales, copas de transmision).
"""
import itertools
import json
import math
import os
import re
import sys

import bpy
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mt8_spec as S  # noqa: E402
from mt8_pose import pose  # noqa: E402

bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, "out", "MT8_Bisonte.blend"))

OBJS = [o for o in bpy.data.objects if o.type == 'MESH' and not o.name.startswith("COL_")]

# contactos intencionados (pares de patrones; se comparan por esquina cuando aplica)
INTENDED = [
    (r"(..)_ArmLower", r"Chassis"), (r"(..)_ArmUpper", r"Chassis"),
    (r"(..)_ArmLower", r"\1_(Knuckle|Carrier)"), (r"(..)_ArmUpper", r"\1_(Knuckle|Carrier)"),
    (r"(..)_WheelMesh", r"\1_(Knuckle|Carrier)"),
    (r"(..)_Shock._Body", r"Chassis"), (r"(..)_Shock(.)_Body", r"\1_Shock\2_(Shaft|Spring)"),
    (r"(..)_Shock(.)_Spring", r"\1_Shock\2_Shaft"),
    (r"(..)_Shock._Shaft", r"\1_ArmLower"),
    (r"(..)_DriveshaftIn", r"Chassis"), (r"(..)_DriveshaftOut", r"\1_(Knuckle|Carrier)"),
    (r"(..)_DriveshaftIn", r"\1_DriveshaftOut"),
    (r"Bumper_.", r"Chassis"), (r"Propulsion", r"Chassis"),
]


def intended(a, b):
    for pa, pb in INTENDED:
        for x, y in ((a, b), (b, a)):
            m = re.fullmatch(pa, x)
            if m:
                pb2 = pb
                for i, g in enumerate(m.groups(), 1):
                    pb2 = pb2.replace(f"\\{i}", re.escape(g))
                if re.fullmatch(pb2, y):
                    return True
    return False


def bvh_world(o, dg):
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    mw = o.matrix_world
    verts = [mw @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys, all_triangles=False)


def run_pose(travel, steer_deg):
    pose(travel=travel, steer=math.radians(steer_deg))
    dg = bpy.context.evaluated_depsgraph_get()
    trees = {o.name: bvh_world(o, dg) for o in OBJS}
    hits = []
    for a, b in itertools.combinations(sorted(trees), 2):
        if intended(a, b):
            continue
        n = len(trees[a].overlap(trees[b]))
        if n:
            hits.append([a, b, n])
    return hits


cases = []
for t in (-S.TRAVEL_DROOP, -S.TRAVEL_DROOP / 2, 0.0, S.TRAVEL_BUMP / 2, S.TRAVEL_BUMP):
    for d in (-S.STEER_MAX_DEG, -S.STEER_MAX_DEG / 2, 0.0, S.STEER_MAX_DEG / 2, S.STEER_MAX_DEG):
        cases.append(({"travel": t, "steer_deg": d}, run_pose(t, d)))
# articulacion cruzada (una diagonal comprimida, la otra extendida)
for d in (-S.STEER_MAX_DEG, S.STEER_MAX_DEG):
    tr = {"FL": S.TRAVEL_BUMP, "RR": S.TRAVEL_BUMP, "FR": -S.TRAVEL_DROOP, "RL": -S.TRAVEL_DROOP}
    cases.append(({"travel": tr, "steer_deg": d}, run_pose(tr, d)))
pose(0.0, 0.0)

report = {"cases": [{"pose": p, "hits": h} for p, h in cases]}
bad = [c for c in report["cases"] if c["hits"]]
report["summary"] = {"poses": len(cases), "poses_with_hits": len(bad)}
with open(os.path.join(HERE, "out", "interference_report.json"), "w") as f:
    json.dump(report, f, indent=1)
print(json.dumps(report["summary"]))
agg = {}
for c in bad:
    for a, b, n in c["hits"]:
        agg.setdefault((a, b), []).append((c["pose"]["travel"], c["pose"]["steer_deg"], n))
for k, v in sorted(agg.items()):
    print(k, v[:6], "..." if len(v) > 6 else "")
