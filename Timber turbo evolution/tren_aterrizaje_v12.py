"""
Tren de aterrizaje principal del Turbo Timber Evolution - modelo parametrico (build123d)

Basado en la foto de detalle del tren:
  - pata: placa blanca plana, ancha arriba y angosta abajo, que gira sobre un pasador paralelo
    al eje del fuselaje dentro de un soporte gris de plastico atornillado a la panza
  - suspension: dos cables de acero cruzados en X; cada cable sale de un ojal de laton junto al
    soporte de un lado y llega a la parte baja de la pata del lado contrario, con un resorte de
    tension cerca de la pata. Al cargar, las patas se abren y los resortes se estiran.
  - rueda: neumatico de espuma redondeado, buje blanco con 5 cavidades, eje-perno con collarin de
    laton por dentro de la pata y arandela + tuerca por fuera de la rueda.

Coordenadas "de foto": x desde el plano de la helice hacia atras, z desde el eje de traccion.
s = +1 lado derecho, -1 lado izquierdo.
"""
import math
from build123d import *

# ======================= PARAMETROS =======================
# v12 (fotos lateral, frontal y de detalle; escala = diametro de rueda 117 mm):
#   soporte en x 250-310; eje bajo el frente del soporte; pata ~27-31 grados de la vertical vista de
#   frente; alto de pata ~ diametro de rueda; trocha / diametro de rueda = 2,24 -> 260 mm
PIVOTE   = (279.0, 46.0, None)      # z = None: se calcula para que el soporte se apoye en la panza
EJE      = (250.0, 106.0, -198.0)   # centro del refuerzo del eje en la pata
RUEDA_C  = (250.0, 132.0, -198.0)   # centro de la rueda
RUEDA_R  = 58.0                     # radio exterior del neumatico
RUEDA_W  = 44.0                     # ancho del neumatico
BUJE_R   = 18.0                     # radio del buje (asiento del neumatico)
PATA_E   = 5.0                      # espesor de la placa de la pata
PATA_ANCHO_SUP, PATA_ANCHO_INF = 58.0, 24.0
SOPORTE  = (58.0, 16.0, 14.0)       # largo (x), ancho (y), alto (z) del soporte gris
OJAL     = (279.0, 22.0, None)      # ojal de laton en la panza, junto al soporte (z sobre la panza)
OJAL_DX  = 7.0                      # el ojal derecho va 7 mm atras y el izquierdo 7 mm adelante: los cables se cruzan sin tocarse
ANCLAJE_T = 20.0                    # distancia (sobre la pata, desde el eje) del anclaje del resorte
RESORTE  = dict(largo=56.0, radio=4.0, alambre=0.6, paso=1.25)   # v12: espira cerrada, ~8 mm de diametro, ~1/3 del cable
ESLABON  = 24.0                     # v12: tramo de alambre entre la pata y el resorte (foto: el resorte queda a media distancia)
CABLE_R  = 0.55
GANCHO   = 6.0                      # largo de los ganchos del resorte

V = lambda *a: Vector(*a)

def lado(p, s):
    return V(p[0], s*p[1], p[2])

def marco_pata(s):
    """origen en el pivote; u = X, t = direccion de la pata (en el plano YZ), w = normal (afuera)"""
    P = lado(PIVOTE, s); A = lado(EJE, s)
    d = A - P
    v = V(0, d.Y, d.Z).normalized()
    w = V(1, 0, 0).cross(v)
    if w.Y*s < 0: w = -w
    L = math.hypot(d.Y, d.Z)
    return P, A, v, w, L, d.X

def pata(s):
    P, A, v, w, L, du = marco_pata(s)
    pl = Plane(origin=P, x_dir=(1, 0, 0), z_dir=w)
    if pl.y_dir.dot(v) < 0:                   # que el eje local y apunte hacia la rueda
        pl = Plane(origin=P, x_dir=(-1, 0, 0), z_dir=w); fx = -1
    else:
        fx = 1
    a1, a2 = PATA_ANCHO_SUP/2, PATA_ANCHO_INF/2
    pts = [(-a1, -8), (a1, -8), (a1, 0), (du + a2, L), (du - a2, L), (-a1, 0)]
    pts = [(fx*x, y) for x, y in pts]
    placa = extrude(pl * Polygon(*pts, align=None), amount=PATA_E/2, both=True)
    placa = placa + extrude(pl * Pos(fx*du, L) * Circle(11), amount=PATA_E/2, both=True)
    # refuerzo del eje: su cara exterior sobresale del disco inclinado del extremo de la pata, asi el
    # espaciador apoya en una cara plana (v12, la auditoria encontro el disco metido 2,4 mm)
    sg_ = 1 if A.Y > 0 else -1
    refuerzo = Pos(A.X, A.Y + sg_*1.4, A.Z) * Rot(90, 0, 0) * Cylinder(radius=10, height=12.8)
    # agujero de anclaje del resorte
    H = P + V(du*(1 - ANCLAJE_T/L), 0, 0) + v*(L - ANCLAJE_T)
    placa = placa - Pos(H.X, H.Y, H.Z) * Plane(origin=(0, 0, 0), z_dir=w) * Cylinder(radius=1.4, height=20)
    return placa + refuerzo, H - w*(PATA_E/2 + 0.5)

def soporte(s):
    lx, ly, lz = SOPORTE
    P = lado(PIVOTE, s)
    x0 = P.X - lx/2
    blk = extrude(Plane.YZ.offset(x0) * Pos(P.Y, P.Z + 3) * RectangleRounded(ly, lz, 3.5), amount=lx)
    for zz in (P.Z + 6.5, P.Z):               # agujeros de tornillo y del pasador en la cara delantera
        blk = blk - Pos(x0, P.Y, zz) * Rot(0, 90, 0) * Cylinder(radius=1.9, height=8)
    pasador = Pos(P.X, P.Y, P.Z) * Rot(0, 90, 0) * Cylinder(radius=1.5, height=lx + 1.5)
    return blk, pasador

def ojal(s):
    O = lado(OJAL, s) + V(s*OJAL_DX, 0, 0)
    cuerpo = Pos(O.X, O.Y, O.Z - 1) * Cylinder(radius=3.0, height=4)
    anillo = Pos(O.X, O.Y, O.Z - 4.6) * Rot(90, 0, 0) * Torus(major_radius=2.0, minor_radius=0.7)
    return cuerpo + anillo, V(O.X, O.Y, O.Z - 6.0)

def rueda_local():
    """neumatico y buje con el eje de giro en Z (cara exterior hacia +Z)"""
    n = 40; rc = (RUEDA_R + BUJE_R)/2; hr = (RUEDA_R - BUJE_R)/2; ha = RUEDA_W/2; ex = 2.6
    sec = []
    for i in range(n):
        t = 2*math.pi*i/n; c, sn = math.cos(t), math.sin(t)
        sec.append((rc + hr*math.copysign(abs(c)**(2/ex), c), ha*math.copysign(abs(sn)**(2/ex), sn)))
    with BuildPart() as bn:
        with BuildSketch(Plane.XZ):
            with BuildLine():
                Spline(*sec, periodic=True)
            make_face()
        revolve(axis=Axis.Z)
    neum = bn.part - Cylinder(radius=BUJE_R - 0.3, height=RUEDA_W + 4)
    # buje blanco: barril + cara exterior con 5 cavidades, cubo central y agujero del eje
    buje = Cylinder(radius=BUJE_R, height=RUEDA_W*0.62)
    # v12: 5 cavidades en forma de rinon (foto de detalle), por las dos caras
    for k in range(5):
        a0 = 72*k + 18 - 24
        rinon = SlotArc(CenterArc((0, 0), 11.3, a0, 48), 5.6)
        for zc, d in ((RUEDA_W*0.31, -1), (-RUEDA_W*0.31, 1)):
            buje = buje - extrude(Plane.XY.offset(zc) * rinon, amount=4.5*d if d > 0 else -4.5)
    buje = buje + Pos(0, 0, RUEDA_W*0.31) * Cylinder(radius=6.2, height=3) + Pos(0, 0, -RUEDA_W*0.31) * Cylinder(radius=6.2, height=3)
    buje = buje - Cylinder(radius=1.8, height=RUEDA_W*2)
    z_ext = RUEDA_W*0.31 + 1.5
    arandela = Pos(0, 0, z_ext + 0.5) * (Cylinder(radius=4.2, height=1.0) - Cylinder(radius=1.8, height=2))
    tuerca = Pos(0, 0, z_ext + 2.5) * (extrude(RegularPolygon(3.2, 6), amount=3, both=False) - Cylinder(radius=1.4, height=8))
    tuerca = Pos(0, 0, -1.5) * tuerca
    return dict(neumatico=neum, buje=buje, arandela=arandela, tuerca=tuerca)

def colocar_rueda(piezas, s):
    C = lado(RUEDA_C, s)
    giro = Rot(-90, 0, 0) if s > 0 else Rot(90, 0, 0)     # cara exterior hacia afuera
    return {k: Pos(C.X, C.Y, C.Z) * giro * v for k, v in piezas.items()}

def perno_y_collarin(s):
    C = lado(RUEDA_C, s); A = lado(EJE, s)
    y_int = A.Y - s*5.0                                   # cara interior del refuerzo de la pata
    perno = Pos(C.X, (y_int + C.Y + s*16)/2 - s*2, C.Z) * Rot(90, 0, 0) * Cylinder(radius=1.6, height=abs(C.Y + s*16 - y_int) + 4)
    # v12: espaciador de laton entre la pata y el buje: fija la rueda de lado sin dejar juego
    # (pila: pata | espaciador | buje | arandela | tuerca)
    y_pata = A.Y + s*7.8                                  # cara exterior del refuerzo de la pata
    y_buje = C.Y - s*(RUEDA_W*0.31 + 1.5)                 # cara interior del cubo del buje
    largo = abs(y_buje - y_pata) - 0.2
    collarin = Pos(C.X, (y_pata + y_buje)/2, C.Z) * Rot(90, 0, 0) * (Cylinder(radius=4.6, height=largo) - Cylinder(radius=1.6, height=largo + 2))
    tornillo_c = Pos(C.X, (y_pata + y_buje)/2, C.Z + 4.6) * Cylinder(radius=1.0, height=2)
    cabeza = Pos(C.X, y_int - s*7.0, C.Z) * Rot(90, 0, 0) * extrude(RegularPolygon(3.0, 6), amount=1.2, both=True)
    return perno + cabeza, collarin + tornillo_c

def resorte_local():
    """resorte de tension a lo largo de +Z desde 0 hasta RESORTE['largo'] (ganchos incluidos)"""
    Ls, r, a, p = RESORTE["largo"], RESORTE["radio"], RESORTE["alambre"], RESORTE["paso"]
    Lc = Ls - 2*GANCHO
    hel = Helix(pitch=p, height=Lc, radius=r)
    perfil = Plane(origin=hel @ 0, z_dir=hel % 0) * Circle(a)
    espiras = sweep(perfil, path=hel, is_frenet=True)
    espiras = Pos(0, 0, GANCHO) * espiras
    g1 = Pos(0, 0, GANCHO/2) * Cylinder(radius=a, height=GANCHO) + Pos(0, 0, 1.2) * Rot(90, 0, 0) * Torus(major_radius=1.2, minor_radius=a)
    g2 = Pos(0, 0, Ls - GANCHO/2) * Cylinder(radius=a, height=GANCHO) + Pos(0, 0, Ls - 1.2) * Rot(90, 0, 0) * Torus(major_radius=1.2, minor_radius=a)
    trans = []
    for t in (0.0, 1.0):   # transiciones radiales de la espira al gancho
        q = hel @ t
        trans.append(varilla_entre(V(0, 0, GANCHO if t == 0 else Ls - GANCHO), V(q.X, q.Y, q.Z + GANCHO), a))
    # sin uniones booleanas: la helice barrida se une mal; se entrega como compuesto
    return Compound(children=[espiras, g1, g2] + trans)

def varilla_entre(p0, p1, r):
    d = p1 - p0
    return extrude(Plane(origin=p0, z_dir=d.normalized()) * Circle(r), amount=d.length)

def cable_con_resorte(F, H, resorte_z):
    """cable rigido desde el ojal F hasta el resorte, y el resorte hasta el anclaje H de la pata"""
    d = H - F; L = d.length; u = d.normalized()
    Ls = RESORTE["largo"]
    Lw = L - Ls
    cable = varilla_entre(F, F + u*Lw, CABLE_R)
    pl = Plane(origin=F + u*Lw, z_dir=u)
    res = pl * resorte_z
    return cable, res, Lw

def z_panza(fus, x, y):
    """z de la piel inferior del fuselaje en (x, y), por biseccion"""
    lo, hi = -200.0, 0.0                     # lo: fuera (debajo), hi: dentro
    for _ in range(40):
        m = (lo + hi)/2
        if fus.is_inside(Vector(x, y, m)): hi = m
        else: lo = m
    return hi

def construir(fus=None):
    global PIVOTE, OJAL
    if fus is not None:
        # el bloque (alto 14, centrado 3 mm sobre el pasador) queda 2 mm metido en la panza
        zs = min(z_panza(fus, PIVOTE[0] + dx, PIVOTE[1] + dy) for dx in (-29, 0, 29) for dy in (-8, 8))
        PIVOTE = (PIVOTE[0], PIVOTE[1], zs - 8.0)
        OJAL = (OJAL[0], OJAL[1], z_panza(fus, OJAL[0], OJAL[1]) - 1.0)
    elif PIVOTE[2] is None:
        PIVOTE = (PIVOTE[0], PIVOTE[1], -80.0); OJAL = (OJAL[0], OJAL[1], -76.0)
    piezas, rig = {}, {"pivotes": {}, "ruedas": {}, "anclajes": {}, "ojales": {}, "cables": {}}
    rl = rueda_local()
    rz = resorte_local()
    for s, nom in ((1, "der"), (-1, "izq")):
        pt, H = pata(s)
        blk, pas = soporte(s)
        oj, Fp = ojal(s)
        if fus is not None:
            blk = blk - fus; oj = oj - fus
        piezas[f"pata_{nom}"] = (pt, "blanco")
        piezas[f"soporte_tren_{nom}"] = (blk, "gris_claro")
        piezas[f"pasador_tren_{nom}"] = (pas, "cromo")
        piezas[f"ojal_{nom}"] = (oj, "laton")
        for k, v in colocar_rueda(rl, s).items():
            piezas[f"{k}_{nom}"] = (v, {"neumatico": "espuma", "buje": "blanco", "arandela": "cromo", "tuerca": "cromo"}[k])
        perno, coll = perno_y_collarin(s)
        piezas[f"perno_eje_{nom}"] = (perno, "cromo")
        piezas[f"collarin_{nom}"] = (coll, "laton")
        rig["pivotes"][nom] = list(lado(PIVOTE, s))
        rig["ruedas"][nom] = list(lado(RUEDA_C, s))
        rig["anclajes"][nom] = list(H)
        rig["ojales"][nom] = list(Fp)
    # cables cruzados: ojal de un lado -> pata del otro
    for nom, otro in (("der", "izq"), ("izq", "der")):
        F = V(*rig["ojales"][nom]); H = V(*rig["anclajes"][otro])
        # eslabon de alambre desde el agujero de la pata hacia el ojal: se mueve con la pata
        u = (F - H).normalized(); E = H + u*ESLABON
        piezas[f"eslabon_{otro}"] = (varilla_entre(H - u*1.5, E, CABLE_R) + Pos(*H) * Sphere(1.2), "cromo")
        cab, res, Lw = cable_con_resorte(F, E, rz)
        piezas[f"cable_{nom}"] = (cab, "cromo")
        piezas[f"resorte_{nom}"] = (res, "cromo")
        rig["anclajes"][otro] = list(E)
        rig["cables"][nom] = dict(ojal=list(F), anclaje=list(E), pata=otro, largo_cable=Lw, largo_resorte=RESORTE["largo"])
    rig["radio_rueda"] = RUEDA_R
    return piezas, rig, rz

if __name__ == "__main__":
    import os
    piezas, rig, rz = construir()
    for k, (s, m) in piezas.items():
        b = s.bounding_box()
        print(f"{k:22s} {m:10s} vol {s.volume/1000:7.2f} cm3 valido {s.is_valid}  z[{b.min.Z:.0f},{b.max.Z:.0f}]")
    print(rig)
