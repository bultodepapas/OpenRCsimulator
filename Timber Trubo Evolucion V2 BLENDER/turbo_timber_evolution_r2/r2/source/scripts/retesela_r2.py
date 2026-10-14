"""
r2 lightweight tessellation from the master CAD BREP caches.

  python3 retesela_r2.py --v15 <modelo_v15.py.brep> --v17 <modelo_v17.py.brep> --out <stl_juego_r2> [--tol 0.3] [--ang 0.35]

1. Loads every exported part (mapa_r2.OBJECTS) from its cache.
2. Cuts parts that straddle the cowl / fuselage joint (sidecar x = -157 mm) into a forward and an aft piece,
   so no exported mesh crosses a crash-section boundary.
3. Overlapping markings: the lower-priority marking loses the overlapping volume (as in r1).
4. Writes one STL per (part, cut) and _report.json (triangles per part, cuts, overlaps).
This step needs the master caches and build123d; the delivered r2 package already contains its output
(source/stl_juego_r2), so the game .blend can be rebuilt without CAD.
"""
import sys, os, json, itertools
from build123d import *
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapa_r2 as M

arg = lambda k, d=None: sys.argv[sys.argv.index(k) + 1] if k in sys.argv else d
CACHE = {"v15": arg("--v15"), "v17": arg("--v17")}
OUT = arg("--out"); TOL = float(arg("--tol", 0.3)); ANG = float(arg("--ang", 0.35))
os.makedirs(OUT, exist_ok=True)
G = 5000.0
FWD = Pos((-G + M.X_COWL_CUT)/2, 0, 0) * Box(G + M.X_COWL_CUT, 2*G, 2*G)    # x < cut
AFT = Pos((G + M.X_COWL_CUT)/2, 0, 0) * Box(G - M.X_COWL_CUT, 2*G, 2*G)     # x > cut
mats = {v: json.load(open(c + "/ok.json"))["materiales"] for v, c in CACHE.items()}

def key(part, cut): return part if cut is None else f"{part}@{cut}"
P, MAT, OWNER, rep = {}, {}, {}, {"cuts": [], "overlaps": [], "empty": []}
for obj, (sec, members, _) in M.OBJECTS.items():
    for ver, part, cut in members:
        s = import_brep(f"{CACHE[ver]}/{part}.brep")
        if cut:
            v0 = s.volume
            s = s & (FWD if cut == "fwd" else AFT)
            rep["cuts"].append(dict(part=part, side=cut, volume_before_mm3=round(v0, 1), volume_after_mm3=round(s.volume if s else 0, 1)))
            if not s or s.volume < 1e-3:
                rep["empty"].append(key(part, cut)); continue
        k = key(part, cut); P[k] = s; MAT[k] = mats[ver][part]; OWNER[k] = obj
def caja(s):
    b = s.bounding_box(); return (b.min.X, b.min.Y, b.min.Z, b.max.X, b.max.Y, b.max.Z)
def solapan(a, b):
    A, B = caja(a), caja(b)
    return all(A[i] <= B[i + 3] and B[i] <= A[i + 3] for i in range(3))
# markings that are solids through their substrate (wing and tail decals of the master): keep only the skin
# outside the substrate solid (the fuselage decals are already skins in v17)
PAINT_ONLY = "--paint-only" in sys.argv
pintado = {}
for owner, (subs_, decs_) in M.PAINT.items():
    for sname in subs_:
        resto = P[sname]
        for d in decs_:
            if d not in P: continue
            try:
                pieza = resto & P[d]
                if pieza and pieza.volume > 1.0:
                    k = f"{sname}#{d}"; P[k] = pieza; MAT[k] = MAT[d]; OWNER[k] = owner
                    resto = resto - P[d]
                    pintado.setdefault(sname, []).append(dict(piece=k, marking=d, material=MAT[d], volume_mm3=round(pieza.volume, 1)))
            except Exception as e:
                pintado.setdefault(sname, []).append(dict(marking=d, error=str(e)))
        P[sname] = resto
    for d in decs_:
        P.pop(d, None)
rep["painted"] = pintado
if PAINT_ONLY: P = {k: v for k, v in P.items() if k.split("#")[0] in pintado}
for k in list(P):
    base = k.split("@")[0]
    if base not in M.DECALS: continue
    subs = [s2 for k2, s2 in P.items() if k2.split("@")[0] in M.SUBSTRATE.get(OWNER[k], []) and OWNER[k2] == OWNER[k]]
    for sub in subs:
        if not solapan(P[k], sub): continue
        try:
            v0 = P[k].volume; n = P[k] - sub
            if n and n.volume > 1.0 and n.volume < v0 - 1.0:
                rep.setdefault("skinned", []).append(dict(decal=k, volume_before_mm3=round(v0, 1), volume_after_mm3=round(n.volume, 1)))
                P[k] = n
        except Exception as e:
            rep.setdefault("skinned", []).append(dict(decal=k, error=str(e)))
decals = [k for k in P if k.split("@")[0] in M.DECALS]
for a, b in itertools.combinations(decals, 2):
    if OWNER[a] != OWNER[b] or not solapan(P[a], P[b]): continue
    try: v = (P[a] & P[b]).volume
    except Exception: v = 0
    if v < 1.0: continue
    hi, lo = (a, b) if M.priority(a) >= M.priority(b) else (b, a)
    try:
        n = P[lo] - P[hi]
        rep["overlaps"].append(dict(lower=lo, upper=hi, overlap_mm3=round(v, 1), volume_before=round(P[lo].volume, 1), volume_after=round(n.volume, 1)))
        P[lo] = n
    except Exception as e:
        rep["overlaps"].append(dict(lower=lo, upper=hi, error=str(e)))
tri = {}
# small or detailed parts: coarser angular tolerance (they are seen from metres away)
FINE_ANG = {"soportes_slat": 0.9, "buje_": 0.8, "arandela": 0.9, "tuerca": 0.9, "escapes": 0.6, "collarin": 0.9,
            "perno_eje": 0.9, "eslabon": 0.9, "cuerno_": 0.8, "base_baliza": 0.8, "lente_baliza": 0.6, "luz_nav": 0.6,
            "tapa_servo": 0.8, "soporte_tren": 0.8, "soporte_rueda_cola": 0.8, "alambre": 0.8, "placas_escape": 0.6,
            "contraplaca": 0.6, "campana": 0.6, "union_elevador": 0.8}
TOL_PART = {"estabilizador": 0.4, "timon_profundidad": 0.4, "deriva": 0.4, "timon_direccion": 0.4, "rueda_cola": 0.25}
import struct
def area_stl(f):
    raw = open(f, "rb").read(); n = struct.unpack_from("<I", raw, 80)[0]; A = 0.0
    for i in range(n):
        v = struct.unpack_from("<9f", raw, 84 + 50*i + 12)
        ax, ay, az = v[3] - v[0], v[4] - v[1], v[5] - v[2]; bx, by, bz = v[6] - v[0], v[7] - v[1], v[8] - v[2]
        A += 0.5*((ay*bz - az*by)**2 + (az*bx - ax*bz)**2 + (ax*by - ay*bx)**2)**0.5
    return n, A
def trozos(s, prof=0):
    """bisect a solid at the middle of its longest side (faces with holes left by a boolean sometimes fail to
    mesh in OCC; cut in two they mesh)"""
    b = s.bounding_box(); L = [b.max.X - b.min.X, b.max.Y - b.min.Y, b.max.Z - b.min.Z]; i = L.index(max(L))
    c = [(b.min.X + b.max.X)/2, (b.min.Y + b.max.Y)/2, (b.min.Z + b.max.Z)/2]
    lo = [c[j] - G/2 if j != i else c[i] - G/2 for j in range(3)]
    caja_ = Pos(*[c[j] if j != i else c[i] - G/4 for j in range(3)]) * Box(*[G if j != i else G/2 for j in range(3)])
    return [x for x in (s & caja_, s - caja_) if x and x.volume > 1e-3]
TESS = {}
def exportar_ok(s, f, tol, ang, prof=0):
    """export s to f; if the mesh misses area (> 5 % of the CAD area: missing faces, not chordal error) bisect and retry (depth <= 4)"""
    export_stl(s, f, tolerance=tol, angular_tolerance=ang); n, A = area_stl(f)
    if A >= 0.95*s.area or prof >= 4: return [(f, n, A, s.area)]
    out = []
    for j, t in enumerate(trozos(s)):
        out += exportar_ok(t, f"{f[:-4]}%{prof}{j}.stl", tol, ang, prof + 1)
    os.remove(f); return out
for k, s in P.items():
    if PAINT_ONLY and k.split("#")[0] not in pintado: continue
    f = f"{OUT}/{k}.stl"
    base = k.split("@")[0].split("#")[0]
    ang = next((v for kk, v in FINE_ANG.items() if base.startswith(kk)), ANG)
    partes_ = exportar_ok(s, f, TOL_PART.get(base, TOL), ang)
    if len(partes_) > 1:          # chunks: own STLs "<key>%<id>"; the exporter welds them and drops the hidden split walls
        for x in partes_:
            kc = os.path.basename(x[0])[:-4]; tri[kc] = x[1]; MAT[kc] = MAT[k]; OWNER[kc] = OWNER[k]
        TESS[k] = dict(chunks=[os.path.basename(x[0])[:-4] for x in partes_], stl_area_mm2=round(sum(x[2] for x in partes_), 1),
                       cad_area_mm2=round(s.area, 1))
        continue
    n, A = area_stl(f)
    TESS[k] = dict(chunks=1, stl_area_mm2=round(A, 1), cad_area_mm2=round(s.area, 1), ratio=round(A/s.area, 4))
    tri[k] = n
rep["tessellation_area_check"] = TESS
if PAINT_ONLY:            # merge into the existing report: painted decals replace their marking sheets
    old = json.load(open(f"{OUT}/_report.json"))
    for kk in list(old["triangles"]):
        if kk.split("#")[0].split("%")[0] in pintado: old["triangles"].pop(kk)
    for d in M.PAINTED_DECALS:
        old["triangles"].pop(d, None)
        if os.path.exists(f"{OUT}/{d}.stl"): os.remove(f"{OUT}/{d}.stl")
    old["triangles"].update(tri); old["materials_cad"].update(MAT); old["owner"].update(OWNER); old["painted"] = pintado
    old.setdefault("tessellation_area_check", {}).update(TESS)
    old["total"] = sum(old["triangles"].values()); json.dump(old, open(f"{OUT}/_report.json", "w"), indent=1)
    print("PAINT TOTAL", old["total"], {k: v for k, v in tri.items()}); sys.exit(0)
rep.update(triangles=tri, total=sum(tri.values()), tol_mm=TOL, tol_ang_rad=ANG, materials_cad=MAT, owner=OWNER,
           caches={k: os.path.basename(v) for k, v in CACHE.items()})
json.dump(rep, open(f"{OUT}/_report.json", "w"), indent=1)
print("TOTAL", sum(tri.values())); print(sorted(tri.items(), key=lambda kv: -kv[1])[:15]); print(rep["overlaps"], rep["empty"])
