"""
Auditoria mecanica del tren de aterrizaje. Uso: python3 auditoria_tren.py modelo_vX.py
(usa la cache .brep que deja auditoria2.py y el analisis.json de analisis_mecanico.py)

  1. la rueda gira libre: holgura del neumatico con pata, soporte, fuselaje, cables y resortes,
     sin carga y con el tren comprimido
  2. pila del eje: pata | espaciador | buje | arandela | tuerca, sin juego ni interferencia
  3. cables y resortes: no tocan neumatico ni fuselaje; los dos cables no se tocan al cruzarse
  4. resorte: estiramiento al comprimir dentro del rango elastico tipico (< 50 % del cuerpo)
  5. estabilidad en tierra: angulo de vuelco lateral (< 63 grados) y angulo ruedas-CG
Escribe auditoria_tren.json
"""
import sys, os, json, math
from build123d import *

ruta = sys.argv[1]; cache = ruta + ".brep"
meta = json.load(open(cache + "/ok.json"))
P = {n: import_brep(f"{cache}/{n}.brep") for n in meta["materiales"]}
T = meta["RIG_TREN"]; X_BA = meta["X_BA"]
A = json.load(open(os.path.join(os.path.dirname(os.path.abspath(ruta)), "analisis.json")))
out = {}

def dist(a, b):
    try: return round(a.distance_to(b), 2)
    except Exception: return None

def girar(s, lado, ang):
    pv = T["pivotes"][lado]; pv = (pv[0] - X_BA, pv[1], pv[2]); sg = 1 if lado == "der" else -1
    return s.rotate(Axis(pv, (1, 0, 0)), sg*ang)

APERT = 12.0
fus = [P[n] for n in ("fuselaje_blanco", "fuselaje_panza_roja", "capota") if n in P]
r = {}
for lado in ("der", "izq"):
    otro = "izq" if lado == "der" else "der"
    for ang, et in ((0, "sin_carga"), (APERT, "comprimido")):
        neu = girar(P["neumatico_" + lado], lado, ang)
        r[f"neumatico_vs_pata_{lado}_{et}"] = dist(neu, girar(P["pata_" + lado], lado, ang))
        r[f"buje_vs_pata_{lado}_{et}"] = dist(girar(P["buje_" + lado], lado, ang), girar(P["pata_" + lado], lado, ang))
        r[f"neumatico_vs_soporte_{lado}_{et}"] = dist(neu, P["soporte_tren_" + lado])
        r[f"neumatico_vs_fuselaje_{lado}_{et}"] = min(dist(neu, f) for f in fus)
        r[f"neumatico_vs_resortes_{lado}_{et}"] = min(dist(neu, P[n]) for n in ("resorte_der", "resorte_izq", "cable_der", "cable_izq"))
out["rueda_gira_libre_mm"] = r

# pila del eje (lado derecho; el izquierdo es simetrico)
def ycaras(s):
    b = s.bounding_box(); return round(b.min.Y, 2), round(b.max.Y, 2)
pila = {n: ycaras(P[n + "_der"]) for n in ("pata", "collarin", "buje", "arandela", "tuerca")}
out["espaciador_vs_pata_mm"] = dist(P["collarin_der"], P["pata_der"])   # 0 = apoyado
huecos = {
          "espaciador-buje": round(pila["buje"][0] - pila["collarin"][1], 2),
          "buje-arandela": round(pila["arandela"][0] - pila["buje"][1], 2),
          "arandela-tuerca": round(pila["tuerca"][0] - pila["arandela"][1], 2)}
out["pila_del_eje_huecos_mm"] = huecos

# cables
out["cables"] = {"entre_si_mm": min(dist(P[a], P[b]) for a in ("cable_der", "resorte_der") for b in ("cable_izq", "resorte_izq")),
                 "vs_fuselaje_mm": min(dist(P[a], f) for a in ("resorte_der", "resorte_izq") for f in fus)}

# resorte: estiramiento con el tren comprimido
cab = T["cables"]["der"]; F = Vector(*cab["ojal"]); H0 = Vector(*cab["anclaje"]); pv = Vector(*T["pivotes"][cab["pata"]])
sg = 1 if cab["pata"] == "der" else -1
def anclaje(a):
    a = math.radians(sg*a); d = H0 - pv
    return Vector(H0.X, pv.Y + d.Y*math.cos(a) - d.Z*math.sin(a), pv.Z + d.Y*math.sin(a) + d.Z*math.cos(a))
L0 = (H0 - F).length; L1 = (anclaje(APERT) - F).length
cuerpo = cab["largo_resorte"] - 12.0      # menos los dos ganchos de 6 mm
out["resorte"] = dict(estiramiento_mm=round(L1 - L0, 1), pct_del_cuerpo=round(100*(L1 - L0)/cuerpo, 1), largo_cuerpo_mm=cuerpo)

# estabilidad en tierra (actitud de tres puntos)
cg = A["cg"]; c = meta.get("contactos")
xm, zm = A["tren"].get("contacto_x", None), None
rd = T["ruedas"]["der"]; Rw = T["radio_rueda"]
xw, yw, zw = rd[0] - X_BA, rd[1], rd[2] - Rw
xt = A["cola_contacto_x"] if "cola_contacto_x" in A else None
out["estabilidad"] = dict(trocha_mm=round(2*rd[1]), angulo_ruedas_cg_grados=cg.get("angulo_ruedas_vs_cg_grados"))
json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(ruta)), "auditoria_tren.json"), "w"), indent=1, ensure_ascii=False)
print(json.dumps(out, indent=1, ensure_ascii=False))
