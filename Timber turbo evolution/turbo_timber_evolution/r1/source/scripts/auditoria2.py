"""
Auditoria mecanica 2 (logica de piezas). Uso: python3 auditoria2.py modelo_vX.py
  A. conectividad: cada pieza debe tocar (o penetrar) al menos otra pieza; las flotantes no tienen sentido
  B. holguras de piezas que giran: helice/spinner/contraplaca vs nariz, rueda de cola en su recorrido,
     ruedas principales con el tren comprimido
  C. geometria de varillas: cuerno sobre la bisagra, varilla perpendicular al brazo del servo en neutro,
     giro de servo necesario para el recorrido maximo
Escribe auditoria2.json
"""
import sys, math, json, runpy, os
from build123d import *

ruta = sys.argv[1]
cache = ruta + ".brep"
if os.path.isdir(cache) and os.path.getmtime(cache + "/ok.json") > os.path.getmtime(ruta):
    meta = json.load(open(cache + "/ok.json"))
    ns = dict(meta, partes={n: (import_brep(f"{cache}/{n}.brep"), m) for n, m in meta["materiales"].items()})
else:
    ns_full = runpy.run_path(ruta, run_name="auditoria")
    os.makedirs(cache, exist_ok=True)
    for n, (s_, m) in ns_full["partes"].items(): export_brep(s_, f"{cache}/{n}.brep")
    ns = {k: ns_full[k] for k in ("partes", "grupos", "MANDOS", "X_BA", "RIG_TREN", "varillas", "REFRIG") if k in ns_full}
    meta = {k: v for k, v in ns.items() if k != "partes"}
    meta["materiales"] = {n: m for n, (s_, m) in ns_full["partes"].items()}
    json.dump(meta, open(cache + "/ok.json", "w"))
P = {k: v[0] for k, v in ns["partes"].items()}
G_ = ns["grupos"]; M = ns["MANDOS"]; X_BA = ns["X_BA"]
out = {"flotantes": [], "holguras": {}, "varillas": {}}

def bb(s):
    b = s.bounding_box(); return (b.min.X, b.min.Y, b.min.Z), (b.max.X, b.max.Y, b.max.Z)
def cerca(a, b, m=3.0):
    (a0, a1), (b0, b1) = cajas_c(a), cajas_c(b)
    return all(a0[i] - m <= b1[i] and b0[i] - m <= a1[i] for i in range(3))
def dist(a, b):
    try:
        return a.distance_to(b)
    except Exception:
        return float("nan")

# ---------- A. conectividad (grafo: piezas que se tocan) ----------
nombres = list(P)
_cb = {}
def cajas_c(s):
    k = id(s)
    if k not in _cb: _cb[k] = bb(s)
    return _cb[k]
padre = {n: n for n in nombres}
def raiz(n):
    while padre[n] != n:
        padre[n] = padre[padre[n]]; n = padre[n]
    return n
TOQUE = 0.3
for i, n in enumerate(nombres):
    for m in nombres[i + 1:]:
        if raiz(n) == raiz(m) or not cerca(P[n], P[m], 1.0): continue
        if dist(P[n], P[m]) <= TOQUE: padre[raiz(n)] = raiz(m)
grupos_c = {}
for n in nombres: grupos_c.setdefault(raiz(n), []).append(n)
principal = max(grupos_c.values(), key=len)
for g in grupos_c.values():
    if g is principal: continue
    # distancia del grupo suelto al resto
    d_min, con = 1e9, None
    for n in g:
        for m in principal:
            if cerca(P[n], P[m], 15.0):
                d = dist(P[n], P[m])
                if d < d_min: d_min, con = d, m
    out["flotantes"].append(dict(piezas=g, separacion_mm=round(d_min, 2) if d_min < 1e8 else None, mas_cercana=con))
out["piezas_conectadas"] = f"{len(principal)} de {len(nombres)}"
out["ala_vs_fuselaje_mm"] = round(min(dist(P["ala_der"], P[f]) for f in ("fuselaje_blanco", "fuselaje_panza_roja")), 2)

# ---------- B. holguras de piezas que giran ----------
fus = [P[n] for n in ("fuselaje_blanco", "fuselaje_panza_roja", "panel_nariz", "filete_nariz", "capota") if n in P]
gira_helice = [P[n] for n in ("helice", "spinner", "contraplaca", "tornillos_spinner") if n in P]
if "campana_motor" in P:   # v10: la campana del outrunner gira: holgura con todo lo fijo que la rodea
    fijos_c = [P[n] for n in ("capota", "panel_nariz", "filete_nariz", "bancada_motor", "tornillos_capota") if n in P]
    out["holguras"]["campana_motor_vs_capota_y_bancada_mm"] = round(min(dist(P["campana_motor"], f) for f in fijos_c), 2)
if "REFRIG" in ns: out["refrigeracion"] = ns["REFRIG"]
d_h = min(dist(a, b) for a in gira_helice for b in fus)
out["holguras"]["helice_y_cono_vs_nariz_mm"] = round(d_h, 2)

def rot(s, g, a):
    return s.rotate(Axis(tuple(G_[g]["p"]), tuple(G_[g]["d"])), a)
cola_m = [n for n in G_["rueda_cola"]["miembros"] if n in P and n != "alambre_rueda_cola"]
fijo_cola = [P[n] for n in ("fuselaje_blanco", "fuselaje_panza_roja", "deriva", "estabilizador", "soporte_rueda_cola") if n in P]
peor = 1e9
for a in (-M["max_timon"], 0, M["max_timon"]):
    for n in cola_m:
        s = rot(P[n], "rueda_cola", a)
        for f in fijo_cola: peor = min(peor, dist(s, f))
        # contra el timon girado lo mismo (deben moverse juntos: solo cuenta si se meten)
out["holguras"]["rueda_cola_vs_fuselaje_en_recorrido_mm"] = round(peor, 2)

T = ns["RIG_TREN"]
peor_r = 1e9
for lado in ("der", "izq"):
    s_ = 1 if lado == "der" else -1
    pv = Vector(*T["pivotes"][lado]); pv = Vector(pv.X - X_BA, pv.Y, pv.Z)
    for a in (0, 12):
        for n in ("neumatico_" + lado, "pata_" + lado):
            s = P[n].rotate(Axis(tuple(pv), (1, 0, 0)), s_*a)
            for f in fus: peor_r = min(peor_r, dist(s, f))
out["holguras"]["tren_vs_fuselaje_comprimido_mm"] = round(peor_r, 2)

# ---------- C. varillas ----------
def ang(u, v):
    u, v = Vector(*u), Vector(*v)
    return math.degrees(math.acos(max(-1, min(1, u.normalized().dot(v.normalized())))))
for g, v in ns["varillas"].items():
    v = dict(v)
    hole = Vector(*v["cuerno"]); srv = Vector(*v["servo"])
    gp = Vector(*G_[g]["p"]); gd = Vector(*G_[g]["d"]).normalized()
    # distancia del agujero a la bisagra, medida en el plano perpendicular a la bisagra
    rel = hole - gp; rel_perp = rel - gd*rel.dot(gd)
    brazo_cuerno = rel_perp.length
    # adelanto del agujero respecto de la bisagra (ideal 0: agujero sobre la linea de bisagra)
    adelanto = rel_perp.X if abs(gd.X) < 0.5 else rel_perp.Y
    varilla = hole - srv
    info = dict(brazo_cuerno_mm=round(brazo_cuerno, 1), agujero_fuera_de_bisagra_mm=round(adelanto, 1),
                angulo_varilla_cuerno_grados=round(ang(varilla, rel_perp), 1))
    if "pivote" in v:
        pv = Vector(*v["pivote"]); brazo = srv - pv
        info["brazo_servo_mm"] = round(brazo.length, 1)
        info["angulo_varilla_brazo_servo_grados"] = round(ang(varilla, brazo), 1)
        rng = {"aleron": M["max_alerones"], "flap": M["max_flaps"], "elevador": M["max_elevador"], "timon": M["max_timon"]}[g.split("_")[0]]
        info["giro_servo_necesario_grados"] = round(math.degrees(math.asin(min(1, brazo_cuerno*math.sin(math.radians(rng))/brazo.length))), 1)
    out["varillas"][g] = info

json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(ruta)), "auditoria2.json"), "w"), indent=1, ensure_ascii=False)
print(json.dumps(out, indent=1, ensure_ascii=False))
