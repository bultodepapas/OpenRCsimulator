"""Teselado liviano desde la cache BREP del CAD v12 + correccion de calcomanias superpuestas.
Uso: python3 retesela.py <cache.brep> <salida_stl> <tol_mm> <tol_ang_rad>"""
import sys, os, json, itertools
from build123d import *
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapa
cache, out, tol, ang = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
os.makedirs(out, exist_ok=True)
meta = json.load(open(cache + "/ok.json"))
usar = [n for r, (ps, _) in mapa.ROLES.items() for n in ps]
P = {n: import_brep(f"{cache}/{n}.brep") for n in usar}
# calcomanias que se superponen en volumen: a la de menor prioridad se le resta la de mayor
def caja(s):
    b = s.bounding_box(); return (b.min.X, b.min.Y, b.min.Z, b.max.X, b.max.Y, b.max.Z)
def solapan(a, b):
    A, B = caja(a), caja(b)
    return all(A[i] <= B[i + 3] and B[i] <= A[i + 3] for i in range(3))
informe = []
for a, b in itertools.combinations(mapa.CALCOS, 2):
    if not solapan(P[a], P[b]): continue
    try: v = (P[a] & P[b]).volume
    except Exception: v = 0
    if v < 1.0: continue          # mm3
    alto, bajo = (a, b) if mapa.prioridad(a) >= mapa.prioridad(b) else (b, a)
    try:
        nuevo = P[bajo] - P[alto]
        informe.append(dict(bajo=bajo, alto=alto, solape_mm3=round(v, 1), vol_antes=round(P[bajo].volume, 1), vol_despues=round(nuevo.volume, 1)))
        P[bajo] = nuevo
    except Exception as e:
        informe.append(dict(bajo=bajo, alto=alto, error=str(e)))
# calcomanias que invaden en volumen una pieza de casco (p. ej. la franja blanca de la cola, hecha como
# trozo del fuselaje, dentro de la panza roja): la calcomania manda y se resta del casco
# (solo la panza roja: es el unico casco con calcomanias hechas como trozo de volumen; comprobado en el CAD v12)
CASCO = ["fuselaje_panza_roja"]
CALCO_FUS = ["franjas_negras", "franja_blanca_cola", "franja_negra_cola", "panel_nariz", "filete_nariz"]
for base in CASCO:
    for c in CALCO_FUS:
        if not solapan(P[base], P[c]): continue
        try: v = (P[base] & P[c]).volume
        except Exception: v = 0
        if v < 1.0: continue
        try:
            nuevo = P[base] - P[c]
            informe.append(dict(bajo=base, alto=c, solape_mm3=round(v, 1), vol_antes=round(P[base].volume, 1), vol_despues=round(nuevo.volume, 1)))
            P[base] = nuevo
        except Exception as e:
            informe.append(dict(bajo=base, alto=c, error=str(e)))
tri = {}
for n, s in P.items():
    f = f"{out}/{n}.stl"
    export_stl(s, f, tolerance=tol, angular_tolerance=ang)
    tri[n] = (os.path.getsize(f) - 84)//50
json.dump(dict(calcomanias=informe, triangulos=tri, total=sum(tri.values()), tol_mm=tol, tol_ang_rad=ang),
          open(f"{out}/_informe.json", "w"), indent=1)
print("TOTAL", sum(tri.values())); print(sorted(tri.items(), key=lambda kv: -kv[1])[:15]); print(informe)
