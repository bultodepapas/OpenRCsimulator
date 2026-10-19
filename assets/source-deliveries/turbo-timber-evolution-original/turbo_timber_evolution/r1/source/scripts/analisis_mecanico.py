"""
Auditoria mecanica del modelo (build123d). Uso:  python3 analisis_mecanico.py modelo_v7.py
  1. interferencias de cada superficie movil en su recorrido maximo contra las piezas vecinas
  2. holgura de la helice con el suelo (tres puntos y cola arriba) y con el tren
  3. cinematica del tren: trocha, apertura, estiramiento del resorte
  4. presupuesto de masas, centro de gravedad y posicion de la bateria
Escribe analisis.json con los resultados.
"""
import sys, math, json, runpy, os
from build123d import *

ruta = sys.argv[1]
ns = runpy.run_path(ruta, run_name="analisis")
P = ns["partes"]; G_ = ns["grupos"]; M = ns["MANDOS"]
res = {"interferencias": [], "helice": {}, "tren": {}, "cg": {}, "piezas_revisadas": 0}

def solido(n): return P[n][0]
def rotar(s, g, ang):
    p, d = G_[g]["p"], G_[g]["d"]
    return s.rotate(Axis(tuple(p), tuple(d)), ang)
def choque(a, b):
    try:
        v = (a & b).volume
    except Exception:
        v = float("nan")
    return v/1000.0     # cm3

# ---------- 1. interferencias ----------
vecinos = {
    "aleron_der": ["ala_der", "puntera_der", "flap_der", "extrados_rojo_der", "intrados_gris_der"],
    "aleron_izq": ["ala_izq", "puntera_izq", "flap_izq", "extrados_rojo_izq", "intrados_gris_izq"],
    "flap_der":   ["ala_der", "aleron_der", "fuselaje_blanco", "extrados_rojo_der", "intrados_gris_der"],
    "flap_izq":   ["ala_izq", "aleron_izq", "fuselaje_blanco", "extrados_rojo_izq", "intrados_gris_izq"],
    "elevador":   ["estabilizador", "deriva", "timon_direccion", "fuselaje_blanco", "fuselaje_panza_roja"],
    "timon":      ["deriva", "estabilizador", "timon_profundidad", "fuselaje_blanco", "fuselaje_panza_roja",
                   "aleta_dorsal", "estab_superior_rojo"],
}
movil = {"aleron_der": ["aleron_der", "cuerno_aleron_der"], "aleron_izq": ["aleron_izq", "cuerno_aleron_izq"],
         "flap_der": ["flap_der", "cuerno_flap_der"], "flap_izq": ["flap_izq", "cuerno_flap_izq"],
         "elevador": ["timon_profundidad", "cuerno_elevador", "union_elevador"],
         "timon": ["timon_direccion", "cuerno_timon"]}
rangos = {"aleron_der": (-M["max_alerones"], M["max_alerones"]), "aleron_izq": (-M["max_alerones"], M["max_alerones"]),
          "flap_der": (0, M["max_flaps"]), "flap_izq": (0, M["max_flaps"]),
          "elevador": (-M["max_elevador"], M["max_elevador"]), "timon": (-M["max_timon"], M["max_timon"])}
for g, ns_m in movil.items():
  for n in ns_m:
    if n not in P: continue
    base = solido(n)
    for ang in sorted(set(rangos[g] + ((rangos[g][0] + rangos[g][1])/2,))):
        m = rotar(base, g, ang)
        for v in vecinos[g] + (["union_elevador"] if g == "timon" else []):
            if v not in P: continue
            vol = choque(m, solido(v))
            if vol > 0.02:
                res["interferencias"].append(dict(superficie=n, angulo=ang, contra=v, volumen_cm3=round(vol, 2)))
# elevador y timon a la vez (peor caso en la cola)
for ae in (-M["max_elevador"], M["max_elevador"]):
    for at in (-M["max_timon"], M["max_timon"]):
        vol = choque(rotar(solido("timon_profundidad"), "elevador", ae), rotar(solido("timon_direccion"), "timon", at))
        vol += choque(rotar(solido("union_elevador"), "elevador", ae), rotar(solido("timon_direccion"), "timon", at))
        if vol > 0.02:
            res["interferencias"].append(dict(superficie="elevador+timon", angulo=f"{ae}/{at}", contra="entre si",
                                              volumen_cm3=round(vol, 2)))

# ---------- 2. helice ----------
hel = solido("helice"); bb = hel.bounding_box()
R = (bb.max.Z - bb.min.Z)/2 if False else max(abs(bb.max.Z), abs(bb.min.Z), abs(bb.max.Y), abs(bb.min.Y))
c = ns["contactos"]; xm, zm = c["principal"]; xc, zc = c["cola"]
ang3 = math.atan2(zc - zm, xc - xm)
x_h = (bb.min.X + bb.max.X)/2
def z_suelo_rel(x, z, ang):     # altura sobre el suelo de un punto (x, z) del modelo con actitud ang
    zz = -x*math.sin(ang) + z*math.cos(ang); z0 = -xm*math.sin(ang) + zm*math.cos(ang)
    return zz - z0
res["helice"] = dict(radio_mm=round(R, 1), actitud_3_puntos_grados=round(math.degrees(ang3), 1),
                     holgura_3_puntos_mm=round(z_suelo_rel(x_h, -R*math.cos(ang3), ang3), 1),
                     holgura_cola_arriba_mm=round(-R - zm, 1))
# holgura entre la punta de la pala y la rueda (en el plano de la helice)
rc = ns["RIG_TREN"]["ruedas"]["der"]; Rw = ns["RIG_TREN"]["radio_rueda"]
res["helice"]["distancia_plano_helice_a_rueda_mm"] = round((rc[0] - ns["X_BA"]) - Rw - bb.max.X, 1)

# ---------- 3. tren ----------
T = ns["RIG_TREN"]; piv = T["pivotes"]["der"]; rue = T["ruedas"]["der"]
r_rueda = math.hypot(rue[1] - piv[1], rue[2] - piv[2]); phi0 = math.atan2(rue[2] - piv[2], rue[1] - piv[1])
def rueda_en(a):
    a = math.radians(a); return piv[1] + r_rueda*math.cos(phi0 + a), piv[2] + r_rueda*math.sin(phi0 + a)
y0, z0 = rueda_en(0); y1, z1 = rueda_en(12)
cab = T["cables"]["der"]; F = Vector(*cab["ojal"]); H0 = Vector(*cab["anclaje"])
pivI = Vector(*T["pivotes"]["izq"])
def anclaje_en(a):
    a = math.radians(-a)       # pata izquierda gira al reves
    d = H0 - pivI; y, z = d.Y, d.Z
    return Vector(H0.X, pivI.Y + y*math.cos(a) - z*math.sin(a), pivI.Z + y*math.sin(a) + z*math.cos(a))
L0 = (H0 - F).length; L1 = (anclaje_en(12) - F).length
res["tren"] = dict(trocha_mm=round(2*y0, 0), trocha_comprimido_mm=round(2*y1, 0),
                   bajada_avion_mm=round(z0 - z1, 1), resorte_libre_mm=cab["largo_resorte"],
                   estiramiento_resorte_mm=round(L1 - L0, 1),
                   estiramiento_pct=round(100*(L1 - L0)/cab["largo_resorte"], 1),
                   angulo_tres_puntos_grados=round(math.degrees(ang3), 1))

# ---------- 4. centro de gravedad ----------
X_BA, CU = ns["X_BA"], ns["CUERDA"]
mac = CU         # ala rectangular: MAC = cuerda (las punteras se desprecian)
def cx(nombres):
    tot, acc = 0.0, 0.0
    for n in nombres:
        if n in P:
            s = solido(n); a = s.area; acc += a*s.center().X; tot += a
    return acc/tot if tot else 0.0, tot
# estructura de espuma: masa repartida segun area de piel (aprox. de una pieza moldeada de pared uniforme)
grupos_masa = {
    "ala (2 semialas, flaps, alerones)": (["ala_der", "ala_izq", "puntera_der", "puntera_izq", "flap_der", "flap_izq",
                                          "aleron_der", "aleron_izq"], 330.0*ns["CUERDA"]/275.0),   # escala con el area
    "fuselaje": (["fuselaje_blanco", "fuselaje_panza_roja"], 290.0),
    "cola": (["estabilizador", "timon_profundidad", "deriva", "timon_direccion", "aleta_dorsal"],
             75.0*(0.45 + 0.55*(ns["STAB"]["cr"] + ns["STAB"]["ct"])/370.0)),   # el estabilizador es ~55 % de la cola
    "tren principal": (["pata_der", "pata_izq", "neumatico_der", "neumatico_izq", "buje_der", "buje_izq"], 135.0),
    "rueda de cola": (["rueda_cola", "alambre_rueda_cola", "soporte_rueda_cola"], 12.0),
    "helice y cono": (["helice", "spinner", "contraplaca"], 32.0),
}
items = []
for k, (ns_, m) in grupos_masa.items():
    x, _ = cx(ns_); items.append((k, m, x))
CMP = ns["COMPONENTES"]
for k, v in CMP.items():
    if k == "bateria": continue
    items.append((k, v["masa"], v["x"] - X_BA))
m_sin = sum(m for _, m, _ in items); mx_sin = sum(m*x for _, m, x in items)
bat = CMP["bateria"]
cg_obj = (0.25*mac, 0.30*mac)
x_bat = [((m_sin + bat["masa"])*c - mx_sin)/bat["masa"] for c in cg_obj]
x_bat_nom = bat["x"] - X_BA
cg_nom = (mx_sin + bat["masa"]*x_bat_nom)/(m_sin + bat["masa"])
# altura del CG y angulo de las ruedas principales (taildragger): con el fuselaje nivelado, la linea
# CG-contacto de la rueda debe quedar 12-25 grados por delante de la vertical (si es menor, tiende a capotar)
def cz(nombres):
    tot, acc = 0.0, 0.0
    for n in nombres:
        if n in P:
            s = solido(n); a_ = s.area; acc += a_*s.center().Z; tot += a_
    return acc/tot if tot else 0.0
zs_ = [(m, cz(ns_)) for k, (ns_, m) in grupos_masa.items()] + [(v["masa"], v.get("z", 0.0)) for k, v in CMP.items()]
z_cg = sum(m*z for m, z in zs_)/sum(m for m, _ in zs_)
ang_ruedas = math.degrees(math.atan2(cg_nom - xm, z_cg - zm))
carga_cola = 100*(cg_nom - xm)/(xc - xm)
res["cg"] = dict(masa_total_g=round(m_sin + bat["masa"]), mac_mm=mac,
                 cg_recomendado_mm=[round(c, 0) for c in cg_obj],
                 cg_con_bateria_en_su_bahia_mm=round(cg_nom, 1),
                 cg_pct_mac=round(100*cg_nom/mac, 1),
                 bateria_centro_para_cg_25_30_mm=[round(x, 0) for x in x_bat],
                 bahia_bateria_mm=[round(bat["x"] - X_BA - bat["recorrido"]/2), round(bat["x"] - X_BA + bat["recorrido"]/2)],
                 desglose=[dict(pieza=k, masa_g=m, x_mm=round(x, 1)) for k, m, x in items] +
                          [dict(pieza="bateria", masa_g=bat["masa"], x_mm=round(x_bat_nom, 1))],
                 carga_alar_g_dm2=round((m_sin + bat["masa"])/(ns["S_ALA_DM2"]), 1),
                 superficie_alar_dm2=round(ns["S_ALA_DM2"], 1),
                 altura_cg_mm=round(z_cg, 1), angulo_ruedas_vs_cg_grados=round(ang_ruedas, 1),
                 peso_en_rueda_cola_pct=round(carga_cola, 1))
# angulo de vuelco lateral (taildragger): plano del suelo por las 3 ruedas; distancia del CG proyectado
# a la linea rueda principal - rueda de cola; angulo = atan(altura / distancia). Regla: < 63 grados
_yw = ns["RIG_TREN"]["ruedas"]["der"][1]
_M = Vector(xm, _yw, zm); _T = Vector(xc, 0, zc); _M2 = Vector(xm, -_yw, zm)
_n = (_M - _T).cross(_M2 - _T).normalized()
if _n.Z < 0: _n = -_n
_C = Vector(cg_nom, 0, z_cg)
_h = (_C - _T).dot(_n); _Cp = _C - _n*_h
_u = (_M - _T).normalized(); _q = _Cp - _T; _d = (_q - _u*_q.dot(_u)).length
res["cg"]["angulo_vuelco_lateral_grados"] = round(math.degrees(math.atan2(_h, _d)), 1)
res["cg"]["trocha_mm"] = round(2*_yw)
# volumen de cola horizontal
_st = ns["STAB"]; _secs = ns.get("STAB_SECS")
if _secs:
    Sh = 2*sum((c0 + c1)/2*(y1 - y0) for (y0, c0, _, _), (y1, c1, _, _) in zip(_secs, _secs[1:]))
    x_ac_c = _st["x_le"] + 0.25*(_st["cr"] + _st["ct"])/2 + _st["flecha"]*0.4
    Lt = x_ac_c - (ns["X_BA"] + 0.25*mac)
    res["cola"] = dict(Sh_dm2=round(Sh/1e4, 2), Lt_mm=round(Lt), Vh=round(Sh*Lt/(ns["S_ALA_DM2"]*1e4*mac), 2))
# componentes internos: deben quedar completamente dentro del fuselaje
_fus = Pos(-ns["X_BA"], 0, 0) * ns["fus"]     # envolvente completa del fuselaje (incluye la capota y su interior)
res["componentes_fuera"] = {}
for n in [k for k in P if k.startswith("interno_")] + ["bancada_motor"]:
    if n in P:
        fuera = (solido(n) - _fus).volume/1000.0
        if fuera > 0.05: res["componentes_fuera"][n] = round(fuera, 2)
json.dump(res, open(os.path.join(os.path.dirname(os.path.abspath(ruta)), "analisis.json"), "w"), indent=1, ensure_ascii=False)
print(json.dumps(res, indent=1, ensure_ascii=False))
