"""
E-flite Turbo Timber Evolution - modelo parametrico v12 (build123d)
Proporciones medidas sobre las fotos de referencia (vista lateral rotada al eje de traccion,
escala tomada de la rueda principal ~115 mm).

Convenciones: mm, X hacia atras, Y hacia la punta derecha, Z arriba.
Se modela en "coordenadas de foto" (x desde el plano de la helice, z desde el eje de traccion)
y al final todo se traslada para que el origen quede en el borde de ataque de la raiz del ala.
"""
import math, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build123d import *

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, "stl_v12")
os.makedirs(OUT, exist_ok=True)
G = 5000.0

# ======================= PARAMETROS =======================
# --- ala ---
ENVERGADURA  = 1550.0
CUERDA       = 213.0        # v9: cuerda/envergadura = 0,137 medido en la foto superior
PERFIL_ALA   = "4412"
X_BA         = 242.0        # borde de ataque de la raiz (desde el plano de la helice)
Z_BA         = 97.0         # altura del borde de ataque sobre el eje de traccion
INCIDENCIA   = 2.0          # grados, borde de salida hacia abajo
DIEDRO       = 2.0
Y_PUNTA      = 700.0        # inicio de la puntera caida
BISAGRA      = 0.74
FLAP_Y       = (58.0, 430.0)
ALERON_Y     = (434.0, 698.0)
FLAP_DEF     = 0.0          # pon 25-40 para verlos bajados
BARRAS_Y     = (227.0, 349.0, 471.0, 593.0, 690.0)   # v9: 5 barras por lado, medidas en la foto superior
SOPORTES_Y   = (180.0, 390.0, 600.0)                                # soportes grises en Λ
# --- cola ---
STAB = dict(x_le=865.0, z=-32.0, cr=147.0, ct=100.0, semi=298.0, bisagra_x=946.0, flecha=28.0)   # v9: planta de la foto superior
# secciones del estabilizador: (y, cuerda, x del borde de ataque, escala de espesor)
STAB_SECS = [(0.0, STAB["cr"], STAB["x_le"], 1.0),
             (STAB["semi"] - 20, STAB["ct"] + 10, STAB["x_le"] + STAB["flecha"]*0.9, 1.0),
             (STAB["semi"], STAB["ct"], STAB["x_le"] + STAB["flecha"], 0.6)]
FIN  = dict(x_le=840.0, cr=234.0, z_top=172.0, x_le_top=950.0, ct=124.0, bisagra_x=980.0, z_bot=-72.0)
# --- superficies de mando ---
def semi_esp(t, xf):
    """semiespesor NACA 4 digitos (fraccion de cuerda) para espesor relativo t en la posicion xf"""
    return 5*t*(0.2969*math.sqrt(xf) - 0.1260*xf - 0.3516*xf**2 + 0.2843*xf**3 - 0.1036*xf**4)
# borde de ataque redondo de cada superficie = semiespesor del perfil en la bisagra: la superficie gira
# dentro de su cavidad sin que la parte gruesa se meta en el plano fijo (corregido en v7)
R_BIS_ALA = semi_esp(0.12, 0.74)*CUERDA
R_BIS_ELEV, R_BIS_TIMON = 3.6, 3.4   # solo de referencia: la cola usa radios variables por estacion
HOLG_BIS = 0.7                                         # holgura con la cavidad del plano fijo
SERVO_ALERON_Y, SERVO_FLAP_Y = 470.0, 150.0
# deflexiones por defecto del controlador en Blender (grados, valores tipicos, verificar con el manual)
MANDOS = dict(alerones=0.0, elevador=0.0, timon=0.0, flaps=0.0, diferencial=0.7,
              max_alerones=22.0, max_elevador=22.0, max_timon=30.0, max_flaps=40.0)
# --- tren ---
RUEDA_R, RUEDA_W = 58.0, 44.0
EJE = (248.0, 138.0, -190.0)
COLA_R = 14.0
COLA_EJE = (1001.0, 0.0, -112.0)
# --- helice ---
HELICE_D = 280.0

# fuselaje: (x, ancho, z_arriba, z_abajo, exponente superelipse)
EST = {
    "nariz":   [(8, 66, 18, -30, 2.5), (30, 90, 25, -40, 2.8), (100, 106, 27, -48, 3.1), (190, 114, 22, -66, 3.3)],
    "cabina":  [(250, 118, 88, -80, 3.5), (330, 120, 88, -90, 3.6), (420, 118, 88, -97, 3.6), (490, 112, 85, -98, 3.5)],
    # v9: cono de cola mas fino (foto superior: 101 mm a 476, 80 a 598, 42 a 772)
    "cola":    [(522, 100, 50, -97, 3.4), (650, 72, 32, -92, 3.2), (800, 40, 8, -82, 3.0),
                (900, 27, -4, -76, 2.8), (975, 16, -10, -70, 2.6)],
}

partes = {}
def add(nombre, solido, mat):
    partes[nombre] = (solido, mat)

# ======================= UTILIDADES =======================
def naca4(code="2412", n=40):
    m, p, t = int(code[0])/100, int(code[1])/10, int(code[2:])/100
    xs = [(1 - math.cos(math.pi*i/n))/2 for i in range(n+1)]
    up, lo = [], []
    for x in xs:
        yt = 5*t*(0.2969*math.sqrt(x) - 0.1260*x - 0.3516*x**2 + 0.2843*x**3 - 0.1036*x**4)
        if m == 0:   yc = 0
        elif x < p:  yc = m/p**2*(2*p*x - x**2)
        else:        yc = m/(1-p)**2*(1 - 2*p + 2*p*x - x**2)
        up.append((x, yc + yt)); lo.append((x, yc - yt))
    return up[::-1] + lo[1:-1]

def desplazar(pts, d):
    """desplaza un perfil cerrado (sentido antihorario) una distancia d normalizada hacia afuera"""
    out, n = [], len(pts)
    for i in range(n):
        (x0, z0), (x1, z1) = pts[i-1], pts[(i+1) % n]
        tx, tz = x1 - x0, z1 - z0; L = math.hypot(tx, tz) or 1
        out.append((pts[i][0] + d*tz/L, pts[i][1] - d*tx/L))
    return out

def perfil_ala(pts, c, y, x_le, z_le, inc=0.0, ez=1.0, off=0.0):
    if off: pts = desplazar(pts, off/c)
    a = math.radians(inc); w = []
    for x, z in pts:
        X, Z = x*c, z*c*ez
        X, Z = X*math.cos(a) + Z*math.sin(a), -X*math.sin(a) + Z*math.cos(a)
        w.append(Vector(x_le + X, y, z_le + Z))
    return Wire.make_polygon(w, close=True)

def perfil_vert(pts, c, z, x_le, off=0.0):
    if off: pts = desplazar(pts, off/c)
    return Wire.make_polygon([Vector(x_le + x*c, zz*c, z) for x, zz in pts], close=True)

def superelipse(x, w, top, bot, n, off=0.0, N=64):
    w, h, zc = w + 2*off, top - bot + 2*off, (top + bot)/2
    pts = []
    for i in range(N):
        t = 2*math.pi*(i + 0.5)/N; c, s = math.cos(t), math.sin(t)
        pts.append(Vector(x, w/2*math.copysign(abs(c)**(2/n), c), zc + h/2*math.copysign(abs(s)**(2/n), s)))
    return Wire([Edge.make_spline(pts, periodic=True)])

def loft_tramos(secs):
    r = Solid.make_loft(secs[:2])
    for i in range(1, len(secs) - 1):
        r = r + Solid.make_loft(secs[i:i+2])
    return r

def varilla(p1, p2, r, r2=None):
    p1, p2 = Vector(*p1), Vector(*p2); d = p2 - p1
    pl = Plane(origin=p1, z_dir=d.normalized())
    return extrude(pl * (Ellipse(r, r2) if r2 else Circle(r)), amount=d.length)

def caja(x0, x1, y0, y1, z0, z1):
    return Pos((x0+x1)/2, (y0+y1)/2, (z0+z1)/2) * Box(x1-x0, y1-y0, z1-z0)

def semiespacio_bajo(x0, z0, x1, z1):
    """todo lo que queda por debajo de la recta (x0,z0)-(x1,z1) en el plano XZ"""
    if x1 < x0: x0, z0, x1, z1 = x1, z1, x0, z0
    a = math.degrees(math.atan2(z1 - z0, x1 - x0))
    return Pos(x0, 0, z0) * Rot(0, -a, 0) * Pos(0, 0, -G/2) * Box(2*G, 2*G, G)

def banda(x0, z0, x1, z1, espesor):
    return semiespacio_bajo(x0, z0 + espesor/2, x1, z1 + espesor/2) - semiespacio_bajo(x0, z0 - espesor/2, x1, z1 - espesor/2)

def barra_xy(p0, p1, ancho):
    """prisma alto a lo largo del segmento p0-p1 en planta (XY); sirve para recortar calcomanias"""
    (x0, y0), (x1, y1) = p0, p1
    L = math.hypot(x1 - x0, y1 - y0); a = math.degrees(math.atan2(y1 - y0, x1 - x0))
    return Pos((x0 + x1)/2, (y0 + y1)/2, 0) * Rot(0, 0, a) * Box(L, ancho, 2*G)

def semiplano_xy(x0, y0, x1, y1):
    """region a la izquierda (sentido antihorario) de la direccion p0->p1 en planta"""
    a = math.degrees(math.atan2(y1 - y0, x1 - x0))
    return Pos(x0, y0, 0) * Rot(0, 0, a) * Pos(0, G/2, 0) * Box(4*G, G, 2*G)

def espejo(s):
    return s + mirror(s, about=Plane.XZ)

# ======================= FUSELAJE =======================
def fuselaje(off=0.0):
    e = EST
    tramos = [Solid.make_loft([superelipse(*s, off=off) for s in e["nariz"]]),
              Solid.make_loft([superelipse(*e["nariz"][-1], off=off), superelipse(*e["cabina"][0], off=off)]),
              Solid.make_loft([superelipse(*s, off=off) for s in e["cabina"]]),
              Solid.make_loft([superelipse(*e["cabina"][-1], off=off), superelipse(*e["cola"][0], off=off)]),
              Solid.make_loft([superelipse(*s, off=off) for s in e["cola"]])]
    r = tramos[0]
    for t in tramos[1:]: r = r + t
    return r

fus = fuselaje()
casco = fuselaje(0.9)                         # piel 0,9 mm por fuera para calcomanias y vidrios

PANZA = (305, -80, 860, -3)                   # recta que separa la panza roja (medida en la foto)
zona_roja = semiespacio_bajo(*PANZA)
add("fuselaje_blanco", fus - zona_roja, "blanco")
add("fuselaje_panza_roja", fus & zona_roja, "rojo")

def trazo(p0, p1, grosor, mat_x=None):
    """franja recta (calcomania) sobre la piel del fuselaje entre dos puntos (x, z)"""
    x0, x1 = sorted((p0[0], p1[0]))
    return casco & banda(p0[0], p0[1], p1[0], p1[1], grosor) & caja(x0, x1, -G, G, -G, G)

negro = (trazo((PANZA[0], PANZA[1] + 4.5), (PANZA[2], PANZA[3] + 4.5), 5)      # filete sobre la panza
         + trazo((39, -11), (82, -27), 3.5) + trazo((82, -27), (300, -32), 5) + trazo((300, -32), (690, -6), 6)   # v11: trazo bajo la placa + franja larga
         + trazo((489, 17), (366, -24), 22) + trazo((432, -30), (305, -73), 16)) # rayo
add("franjas_negras", negro, "negro")
add("franja_blanca_cola", trazo((597, -58), (900, -14), 8), "blanco")
add("franja_negra_cola", trazo((470, -66), (760, -40), 3), "negro")
# nariz: panel antirreflejo negro + filete rojo
add("panel_nariz", casco & caja(0, 184, -G, G, 8, G), "negro")      # v11: llega al borde, junto al cono
add("filete_nariz", casco & caja(0, 184, -G, G, 3.5, 8), "rojo")

# vidrios
vid = fuselaje(1.3)
parabrisas = vid & caja(182, 254, -G, G, 15, G)
v1 = vid & caja(257, 319, -G, G, -2, 66)
v2 = vid & caja(326, 393, -G, G, -2, 66)
claraboya = vid & caja(398, 486, -G, G, 52, 84)
add("parabrisas", parabrisas, "vidrio")
add("ventanas", v1 + v2 + claraboya, "vidrio")

# luces: baliza superior, luz inferior
add("baliza", Pos(530, 0, 47) * Sphere(6) + Pos(642, 0, -93) * Sphere(5), "led_rojo")

# ======================= BISAGRAS DE PASADOR (v8) =======================
# cada superficie cuelga de bisagras reales: hoja fija embebida en el plano fijo, nudillo con pasador en
# el eje y hoja movil embebida en la superficie (la hoja movil gira con ella). Sin esto la superficie flotaria.
def bisagras(origen, eje, adelante, posiciones, ancho=14.0, hoja=11.0):
    """origen: punto del eje; eje: 'y' o 'z'; adelante: vector hacia el plano fijo; posiciones: coords sobre el eje"""
    fijas, moviles, nudos = None, None, None
    for c in posiciones:
        o = Vector(*origen)
        if eje == "y": o = Vector(o.X, c, o.Z); d = Vector(0, 1, 0)
        else:          o = Vector(o.X, o.Y, c); d = Vector(0, 0, 1)
        f = Vector(*adelante).normalized()
        n_ = d.cross(f)                                     # normal de la hoja
        pl_f = Plane(origin=o + f*(hoja/2 + 1.2), x_dir=f, z_dir=n_)
        pl_m = Plane(origin=o - f*(hoja/2 + 1.2), x_dir=f, z_dir=n_)
        hf = extrude(pl_f * Rectangle(hoja, ancho), amount=0.3, both=True)
        hm = extrude(pl_m * Rectangle(hoja, ancho), amount=0.3, both=True)
        nd = extrude(Plane(origin=o - d*ancho/2, z_dir=d) * Circle(1.1), amount=ancho)
        fijas = hf if fijas is None else fijas + hf
        moviles = hm if moviles is None else moviles + hm
        nudos = nd if nudos is None else nudos + nd
    return fijas + nudos, moviles, nudos

def alojar_bisagras(movil, origen, eje, posiciones, r_nariz, ancho=14.0):
    """cajera en la nariz redonda de la superficie movil en cada bisagra: la hoja fija entra ahi sin
    tocar la superficie en ningun angulo (cilindro coaxial = invariante al giro)"""
    for c in posiciones:
        o = Vector(*origen)
        if eje == "y": pl = Plane(origin=(o.X, c - (ancho + 1)/2, o.Z), z_dir=(0, 1, 0))
        else:          pl = Plane(origin=(o.X, o.Y, c - (ancho + 1)/2), z_dir=(0, 0, 1))
        movil = movil - extrude(pl * Circle(r_nariz + 1.0), amount=ancho + 1)
    return movil


# ======================= ALA =======================
pa = naca4(PERFIL_ALA, 36)
def sec_ala(y, c=CUERDA, dz=0.0, ez=1.0, off=0.0):
    x_le = X_BA + (CUERDA - c)*0.3
    return perfil_ala(pa, c, y, x_le, Z_BA + dz, INCIDENCIA, ez, off)

_k = CUERDA/275.0
PUNTA = [(Y_PUNTA, CUERDA, 0, 1.0), (725, 272*_k, -4, 0.92), (748, 263*_k, -14, 0.80),
         (765, 250*_k, -28, 0.62), (775, 226*_k, -40, 0.40)]

def semiala(off=0.0):
    panel = Solid.make_loft([sec_ala(0, off=off), sec_ala(Y_PUNTA, off=off)])
    puntera = loft_tramos([sec_ala(y, c, dz, ez, off) for y, c, dz, ez in PUNTA])
    return panel, puntera

panel, puntera = semiala()
def punto_perfil(xf, lado="medio", code=PERFIL_ALA):
    """(x, z) de un punto del perfil del ala en la fraccion xf, con incidencia aplicada"""
    m, p, t = int(code[0])/100, int(code[1])/10, int(code[2:])/100
    yt = 5*t*(0.2969*math.sqrt(xf) - 0.1260*xf - 0.3516*xf**2 + 0.2843*xf**3 - 0.1036*xf**4)
    yc = m/p**2*(2*p*xf - xf**2) if xf < p else m/(1-p)**2*(1 - 2*p + 2*p*xf - xf**2)
    zz = {"medio": yc, "arriba": yc + yt, "abajo": yc - yt}[lado]
    a = math.radians(INCIDENCIA); X, Z = xf*CUERDA, zz*CUERDA
    return X_BA + X*math.cos(a) + Z*math.sin(a), Z_BA - X*math.sin(a) + Z*math.cos(a)

def cil_y(x, z, r, y0, y1):
    return Pos(x, (y0 + y1)/2, z) * Rot(90, 0, 0) * Cylinder(radius=r, height=y1 - y0)
def cil_z(x, y, r, z0, z1):
    return Pos(x, y, (z0 + z1)/2) * Cylinder(radius=r, height=z1 - z0)

xh, zh = punto_perfil(BISAGRA)          # eje de bisagra sobre la linea media del perfil
Y_CORTE = (FLAP_Y[0] - 1, ALERON_Y[1] + 1)
fijo = (panel - caja(xh, 900, *Y_CORTE, -G, G)
        - cil_y(xh, zh, R_BIS_ALA + HOLG_BIS, *Y_CORTE))           # cavidad concava del plano fijo
def superficie_ala(y0, y1):
    return (panel & caja(xh, 900, y0, y1, -G, G)) + (panel & cil_y(xh, zh, R_BIS_ALA, y0, y1))
flap = superficie_ala(*FLAP_Y)
aleron = superficie_ala(*ALERON_Y)

def cuerno_xz(x_bis, z_base, y, alto, largo=22.0, agujero=0):
    """cuerno de mando (placa en el plano XZ) con 3 agujeros alineados bajo la bisagra"""
    pts = [(x_bis + 3, z_base + 3), (x_bis + largo, z_base + 3), (x_bis + 7, z_base - alto), (x_bis - 3, z_base - alto)]
    placa = extrude(Plane.XZ.offset(-y) * Polygon(*pts, align=None), amount=0.8, both=True)
    agujeros = [(x_bis + 1.0, z_base - alto + 3.5), (x_bis + 1.0, z_base - alto + 8.5), (x_bis + 1.0, z_base - alto + 13.5)]   # v8: todos sobre la bisagra
    for ax, az in agujeros:
        placa = placa - Pos(ax, y, az) * Rot(90, 0, 0) * Cylinder(radius=0.9, height=6)
    return placa, (agujeros[agujero][0], y, agujeros[agujero][1])

def servo_ala(ys, x_cuerno_hole, brazo_mm=12.5):
    """tapa del servo en el intrados + brazo del servo; devuelve piezas y punta del brazo"""
    xs = X_BA + 0.47*CUERDA
    _, zl = punto_perfil(0.47, "abajo")
    piel_s = Solid.make_loft([sec_ala(0, off=1.5), sec_ala(Y_PUNTA, off=1.5)])
    tapa = piel_s & abajo_ala & caja(xs - 24, xs + 12, ys - 13, ys + 13, -G, G)
    brazo = Pos(xs + 4, ys, zl + 1 - (brazo_mm + 3)/2 + 1.5) * Box(5, 3.2, brazo_mm + 3)
    return tapa, brazo, (xs + 4, ys, zl + 1 - brazo_mm), (xs + 4, ys, zl + 1)

z_te_ala = Z_BA - CUERDA*math.sin(math.radians(INCIDENCIA))
abajo_ala = semiespacio_bajo(X_BA - 50, Z_BA + 3, X_BA + CUERDA + 50, z_te_ala + 3)
_, zl_b = punto_perfil(BISAGRA + 0.02, "abajo")
cuerno_al, hole_al = cuerno_xz(xh, zl_b, SERVO_ALERON_Y, 16)
cuerno_fl, hole_fl = cuerno_xz(xh, zl_b, SERVO_FLAP_Y, 16, agujero=1)   # agujero central: 40 grados con ~39 de servo
tapa_al, brazo_al, punta_al, piv_al = servo_ala(SERVO_ALERON_Y, hole_al[0])
tapa_fl, brazo_fl, punta_fl, piv_fl = servo_ala(SERVO_FLAP_Y, hole_fl[0], brazo_mm=17.0)   # brazo largo
cuerno_al = cuerno_al - fijo; cuerno_fl = cuerno_fl - fijo
aleron = aleron + (cuerno_al & caja(-G, G, -G, G, zl_b - 1, G))   # la base del cuerno queda dentro
cuerno_al = cuerno_al - aleron
flap = flap + (cuerno_fl & caja(-G, G, -G, G, zl_b - 1, G)); cuerno_fl = cuerno_fl - flap

# barras blancas en el borde de ataque (extrados) y soportes grises en "Λ" debajo
piel_bar = Solid.make_loft([sec_ala(0, off=1.6), sec_ala(Y_PUNTA, off=1.6)])
barras, soportes = None, None
for yb in BARRAS_Y:
    b = piel_bar & caja(X_BA - 30, X_BA + 0.15*CUERDA, yb - 7, yb + 7, Z_BA - 4, G)
    barras = b if barras is None else barras + b
for yb in SOPORTES_Y:
    z_int = Z_BA - 9
    xa = X_BA + 0.12*CUERDA
    lam = (varilla((xa - 26, yb, z_int + 4), (xa, yb, z_int - 34), 4.0, 2.0) +
           varilla((xa + 26, yb, z_int + 3), (xa, yb, z_int - 34), 4.0, 2.0))
    soportes = lam if soportes is None else soportes + lam
soportes = soportes - panel

# ---- decoracion del ala (fotos superior y frontal) ----
# extrados: base blanca, franja roja en el borde de ataque que se ensancha hacia la punta
#           (linea diagonal hasta la bisagra), rayos negros sobre el rojo, flaps y alerones blancos
# intrados: blanco con franjas diagonales gris oscuro
piel1 = Solid.make_loft([sec_ala(0, off=0.9), sec_ala(Y_PUNTA, off=0.9)])
piel2 = Solid.make_loft([sec_ala(0, off=1.3), sec_ala(Y_PUNTA, off=1.3)])
z_te = Z_BA - CUERDA*math.sin(math.radians(INCIDENCIA))
abajo = semiespacio_bajo(X_BA - 50, Z_BA + 3, X_BA + CUERDA + 50, z_te + 3)
arriba = caja(-G, G, -G, G, -G, G) - abajo
BANDA_BA = X_BA + 0.17*CUERDA
LINEA_ROJA = ((BANDA_BA, 170.0), (xh, 480.0))
zona_roja_ala = (caja(-G, BANDA_BA, -G, G, -G, G) +
                 (semiplano_xy(*LINEA_ROJA[0], *LINEA_ROJA[1]) & caja(-G, xh - R_BIS_ALA - 1.5, -G, G, -G, G)))
extrados_rojo = piel1 & arriba & zona_roja_ala & caja(-G, G, 0, Y_PUNTA, -G, G)
trazos = [barra_xy((X_BA + 0.70*CUERDA, 690), (X_BA + 0.28*CUERDA, 470), 16),     # rayo grande
          barra_xy((X_BA + 0.28*CUERDA, 470), (X_BA + 0.50*CUERDA, 440), 11),
          barra_xy((X_BA + 0.50*CUERDA, 440), (X_BA + 0.16*CUERDA, 250), 13),
          barra_xy((X_BA + 0.40*CUERDA, 698), (X_BA + 0.12*CUERDA, 520), 9),      # trazos finos
          barra_xy((X_BA + 0.62*CUERDA, 600), (X_BA + 0.40*CUERDA, 470), 6)]
extrados_negro = None
for t in trazos:
    p = piel2 & arriba & t & zona_roja_ala & caja(-G, G, 0, Y_PUNTA, -G, G)
    extrados_negro = p if extrados_negro is None else extrados_negro + p
intrados_gris = None
for y0 in (70.0, 150.0, 230.0, 310.0, 390.0, 470.0, 550.0):
    p = piel1 & abajo & barra_xy((X_BA - 15, y0), (X_BA + 0.55*CUERDA, y0 + 70), 22) & caja(-G, G, 0, Y_PUNTA, -G, G)
    intrados_gris = p if intrados_gris is None else intrados_gris + p

# luz de navegacion en la puntera
luz = Pos(X_BA + 30, 768, Z_BA - 26) * Sphere(9)

# ala (se construye plana y luego se le aplica el diedro junto con las demas piezas)
bis_fl_f, bis_fl_m, nud_fl = bisagras((xh, 0, zh), "y", (-1, 0, 0), (FLAP_Y[0] + 30, sum(FLAP_Y)/2, FLAP_Y[1] - 30))
bis_al_f, bis_al_m, nud_al = bisagras((xh, 0, zh), "y", (-1, 0, 0), (ALERON_Y[0] + 30, sum(ALERON_Y)/2, ALERON_Y[1] - 30))
POS_FL = (FLAP_Y[0] + 30, sum(FLAP_Y)/2, FLAP_Y[1] - 30); POS_AL = (ALERON_Y[0] + 30, sum(ALERON_Y)/2, ALERON_Y[1] - 30)
flap = alojar_bisagras(flap, (xh, 0, zh), "y", POS_FL, R_BIS_ALA) + bis_fl_m
aleron = alojar_bisagras(aleron, (xh, 0, zh), "y", POS_AL, R_BIS_ALA) + bis_al_m
fijo = fijo + bis_fl_f + bis_al_f


piezas_ala = {"ala": (fijo, "blanco"), "puntera": (puntera, "rojo"), "flap": (flap, "blanco"),
              "aleron": (aleron, "blanco"), "cuerno_aleron": (cuerno_al, "gris_claro"), "cuerno_flap": (cuerno_fl, "gris_claro"),
              "tapa_servo_aleron": (tapa_al, "gris_claro"), "tapa_servo_flap": (tapa_fl, "gris_claro"),
              "brazo_servo_aleron": (brazo_al, "blanco"), "brazo_servo_flap": (brazo_fl, "blanco"), "barras_ala": (barras, "blanco"),
              "soportes_slat": (soportes, "gris_claro"),
              "extrados_rojo": (extrados_rojo, "rojo"), "extrados_negro": (extrados_negro, "negro"),
              "intrados_gris": (intrados_gris, "gris_oscuro")}
for k, (s, mat) in piezas_ala.items():
    s = Rot(DIEDRO, 0, 0) * s
    add(k + "_der", s, mat); add(k + "_izq", mirror(s, about=Plane.XZ), mat)
luz_d = Rot(DIEDRO, 0, 0) * luz
# v8: el ala va atornillada al fuselaje con dos tornillos de nylon detras del larguero
_xt = X_BA + 0.86*CUERDA; _zt = punto_perfil(0.86, "arriba")[1]
torn_ala = None
for _y in (-24.0, 24.0):
    t_ = Pos(_xt, _y, _zt + 1.0) * Cylinder(radius=4.5, height=2.4) + Pos(_xt, _y, _zt - 22) * Cylinder(radius=2.0, height=46)
    torn_ala = t_ if torn_ala is None else torn_ala + t_
add("tornillos_ala", torn_ala, "blanco")
add("luz_nav_der", luz_d, "led_verde"); add("luz_nav_izq", mirror(luz_d, about=Plane.XZ), "led_rojo")

# ======================= COLA =======================
pc = naca4("0006", 30)
def semi_estab():
    s = STAB
    return loft_tramos([perfil_ala(pc, c, y, xl, s["z"], ez=ez) for y, c, xl, ez in STAB_SECS])
st = semi_estab(); xb = STAB["bisagra_x"]; zs = STAB["z"]
def barra_bisagra(eje, centro, estaciones, extra=0.0):
    """varilla de radio variable sobre la linea de bisagra (loft de circulos); estaciones = [(coord, r)]"""
    secs = []
    for c, r in estaciones:
        if eje == "y": pl = Plane(origin=(centro[0], c, centro[1]), z_dir=(0, 1, 0))
        else:          pl = Plane(origin=(centro[0], centro[1], c), z_dir=(0, 0, 1))
        secs.append((pl * Circle(r + extra)).wire())
    return loft_tramos(secs)
_S = STAB
EST_BIS_E = [(y if y > 0 else -1.0, ez*semi_esp(0.06, (xb - xl)/c)*c) for y, c, xl, ez in STAB_SECS]
EST_BIS_E[-1] = (EST_BIS_E[-1][0] + 1, EST_BIS_E[-1][1])
# muesca en el estabilizador y el elevador para que el timon gire su recorrido completo (corregido en v7)
_xr = FIN["bisagra_x"]; _fr = (_xr - FIN["x_le"])/FIN["cr"]
T_TIM_COLA = semi_esp(0.06, 0.5)*FIN["cr"]                 # semiespesor maximo del timon a la altura de la cola
_tan = math.tan(math.radians(MANDOS["max_timon"] + 4)); _w0 = T_TIM_COLA + 2.5; _xf = 1200
# v9: la bisagra del elevador queda delante del timon; las mitades del elevador se separan del cono de
# cola y de la deriva (_w1) y detras del timon se abren en V para su recorrido
_w1 = max(w for x, w, *_ in EST["cola"] if x >= xb - 60)/2 + 2.5
muesca_cola = extrude(Plane.XY.offset(zs) * Polygon((xb - 6, -_w1), (_xr - 5, -_w1), (_xf, -_w0 - (_xf - _xr)*_tan),
                      (_xf, _w0 + (_xf - _xr)*_tan), (_xr - 5, _w1), (xb - 6, _w1), align=None), amount=30, both=True)
estab = st - caja(xb, 2000, 0, 2000, -G, G) - barra_bisagra("y", (xb, zs), EST_BIS_E, HOLG_BIS) - muesca_cola
elev = ((st & caja(xb, 2000, 0, 2000, -G, G)) + (st & barra_bisagra("y", (xb, zs), EST_BIS_E))) - muesca_cola
# v9: barra de torsion sobre el eje de la bisagra; atraviesa el cono de cola por un buje y entra 25 mm en cada mitad
union_elev = Pos(xb, 0, zs) * Rot(90, 0, 0) * Cylinder(radius=1.3, height=2*(_w1 + 25))
_be_f, _be_m, _ = bisagras((xb, 0, zs), "y", (-1, 0, 0), (55.0, 160.0, 250.0), ancho=12, hoja=9)
estab = estab + _be_f
elev = alojar_bisagras(elev, (xb, 0, zs), "y", (55.0, 160.0, 250.0), max(r for _, r in EST_BIS_E), ancho=12) + _be_m
cuerno_el, hole_el = cuerno_xz(xb, zs - 2, 24.0, 20)
elev_d = elev + (cuerno_el & caja(-G, G, -G, G, zs - 4, G)); cuerno_el = cuerno_el - elev_d
add("estabilizador", espejo(estab) - fus, "blanco")
add("timon_profundidad", elev_d + mirror(elev, about=Plane.XZ), "blanco")
add("union_elevador", union_elev, "metal")
add("cuerno_elevador", cuerno_el, "gris_claro")
def piel_estab(off):
    s_ = STAB
    return loft_tramos([perfil_ala(pc, c, y, xl, s_["z"], ez=ez, off=off) for y, c, xl, ez in STAB_SECS])
arriba_e = caja(-G, G, -G, G, zs + 0.5, G)
fijo_e = caja(STAB["x_le"] + 12, xb - EST_BIS_E[0][1] - 2.0, 10, STAB["semi"] - 8, -G, G)    # deja margen blanco
movil_e = caja(xb + EST_BIS_E[0][1] + 1.0, 1046, 12, STAB["semi"] - 8, -G, G)
pe1, pe2 = piel_estab(0.7) - muesca_cola, piel_estab(1.2) - muesca_cola
_xte = STAB["x_le"] + STAB["cr"]
rayo_e = (barra_xy((STAB["x_le"] + 20, 40), (_xte - 15, 240), 12) + barra_xy((_xte - 15, 240), (STAB["x_le"] + 55, 262), 8))
add("estab_superior_rojo", espejo(pe1 & arriba_e & fijo_e) - fus, "rojo")
add("estab_superior_negro", espejo(pe2 & arriba_e & fijo_e & rayo_e) - fus, "negro")
add("elevador_superior_rojo", espejo(pe1 & arriba_e & movil_e), "rojo")
add("elevador_superior_negro", espejo(pe2 & arriba_e & movil_e & rayo_e), "negro")

f = FIN; xr = f["bisagra_x"]
def deriva_full(off=0.0):
    return loft_tramos([perfil_vert(pc, f["cr"], f["z_bot"], f["x_le"], off),
                        perfil_vert(pc, f["cr"], 0, f["x_le"], off),
                        perfil_vert(pc, f["ct"], f["z_top"], f["x_le_top"], off),
                        perfil_vert(pc, f["ct"] - 14, f["z_top"] + 6, f["x_le_top"] + 10, off)])
df = deriva_full()
EST_BIS_T = [(f["z_bot"] - 1, semi_esp(0.06, (xr - f["x_le"])/f["cr"])*f["cr"]),
             (0.0, semi_esp(0.06, (xr - f["x_le"])/f["cr"])*f["cr"]),
             (f["z_top"], semi_esp(0.06, (xr - f["x_le_top"])/f["ct"])*f["ct"]),
             (f["z_top"] + 7, semi_esp(0.06, max(0.05, (xr - f["x_le_top"] - 10)/(f["ct"] - 14)))*(f["ct"] - 14))]
deriva = df - caja(xr, 2000, -G, G, -G, G) - barra_bisagra("z", (xr, 0), EST_BIS_T, HOLG_BIS)
timon = (df & caja(xr, 2000, -G, G, -G, G)) + (df & barra_bisagra("z", (xr, 0), EST_BIS_T))
timon = timon - caja(xb - 3, xb + 12, -G, G, zs - 5, zs + 5)        # ranura para la union del elevador
# holgura con el extremo del fuselaje en todo el recorrido: frente al cono de cola el timon empieza a un
# radio mayor que la distancia de la bisagra al fin del fuselaje (v7)
_x_fin_fus = EST["cola"][-1][0]
timon = timon - cil_z(xr, 0, (xr - _x_fin_fus) + 1.5, -72.5, EST["cola"][-1][2] + 2) - fuselaje(0.8)
timon = timon - caja(-G, G, -G, G, -G, -70.4)          # 0,6 mm sobre el soporte fijo de la rueda de cola (v8)
_bt_f, _bt_m, _ = bisagras((xr, 0, 0), "z", (-1, 0, 0), (-45.0, 40.0, 130.0), ancho=12, hoja=9)
deriva = deriva + _bt_f
timon = alojar_bisagras(timon, (xr, 0, 0), "z", (-45.0, 40.0, 130.0), max(r for _, r in EST_BIS_T), ancho=12) + _bt_m
# cuerno del timon: lado izquierdo, abajo (placa horizontal)
Z_CT = -60.0
pts = [(xr + 3, -3), (xr + 22, -3), (xr + 7, -24), (xr - 3, -24)]
cuerno_ti = extrude(Plane.XY.offset(Z_CT) * Polygon(*pts, align=None), amount=0.8, both=True)
ag_ti = [(xr + 1.0, -21.0), (xr + 1.0, -16.0), (xr + 1.0, -11.0)]   # v8: sobre la bisagra
for ax, ay in ag_ti:
    cuerno_ti = cuerno_ti - Pos(ax, ay, Z_CT) * Cylinder(radius=0.9, height=6)
hole_ti = (ag_ti[1][0], ag_ti[1][1], Z_CT)          # agujero central: el servo gira ~40 grados para 30 de timon
timon = timon + (cuerno_ti & caja(-G, G, -2, G, -G, G)); cuerno_ti = cuerno_ti - timon
add("deriva", deriva - fus, "blanco")
add("timon_direccion", timon, "blanco")
add("cuerno_timon", cuerno_ti, "gris_claro")
aleta = Solid.make_loft([perfil_vert(pc, 330, -8, 740), perfil_vert(pc, 220, 30, 852)])
aleta = aleta & caja(-G, xr - EST_BIS_T[1][1] - HOLG_BIS - 2, -G, G, -G, G)   # no invade el timon (v7)
add("aleta_dorsal", aleta - fus - deriva, "blanco")
# calcomanias de la deriva: se separan en parte fija y parte del timon
piel_fin = deriva_full(0.7); piel_fin2 = deriva_full(1.1)
fijo_f = caja(-G, xr - EST_BIS_T[1][1] - 2.0, -G, G, -G, G); movil_f = caja(xr + EST_BIS_T[1][1] + 1.0, G, -G, G, -G, G)
roja_f = (piel_fin & caja(800, 1100, -G, G, 2, 20)) + (piel_fin & banda(925, 172, 1015, 105, 14) & caja(920, 1018, -G, G, 95, 180))
negra_f = ((piel_fin & caja(800, 1100, -G, G, 22, 27)) + (piel_fin & banda(945, 150, 1062, 72, 12) & caja(940, 1066, -G, G, 60, 160))
           + (piel_fin & banda(958, 72, 1050, 42, 9) & caja(952, 1052, -G, G, 34, 80)))
add("deriva_franja_roja", roja_f & fijo_f, "rojo")
add("deriva_franjas_negras", negra_f & fijo_f, "negro")
# lado izquierdo del timon rojo con franja negra (foto superior)
roja_izq = piel_fin & caja(xr + EST_BIS_T[1][1] + 1.0, 1062, -G, 0, 30, 166)
negra_izq = piel_fin2 & caja(-G, G, -G, 0, -G, G) & banda(990, 150, 1062, 95, 9) & caja(985, 1066, -G, G, 90, 160)
add("timon_franja_roja", (roja_f & movil_f) + roja_izq, "rojo")
add("timon_franjas_negras", (negra_f & movil_f) + negra_izq, "negro")

# guias de salida de las varillas de la cola (costados del fuselaje)
# servos de cola dentro del fuselaje; cada varilla va recta del brazo del servo al cuerno y sale del
# fuselaje por una guia colocada donde la linea cruza la piel (calculado, v8)
BRAZO_COLA = 12.5
SERVO_EL = dict(pivote=(470.0, 14.0, -40.0), eje=(0, 1, 0))                 # brazo hacia abajo
SERVO_TI = dict(pivote=(470.0, -14.0, -54.0), eje=(0, 0, 1))                # brazo hacia la izquierda
punta_el = (SERVO_EL["pivote"][0], SERVO_EL["pivote"][1], SERVO_EL["pivote"][2] - BRAZO_COLA)
punta_ti = (SERVO_TI["pivote"][0], SERVO_TI["pivote"][1] - BRAZO_COLA, SERVO_TI["pivote"][2])
brazo_el = varilla((punta_el[0], punta_el[1], SERVO_EL["pivote"][2] + 2), (punta_el[0], punta_el[1], punta_el[2] - 1.5), 2.4, 1.4)
brazo_ti = varilla((punta_ti[0], SERVO_TI["pivote"][1] + 2, punta_ti[2]), (punta_ti[0], punta_ti[1] - 1.5, punta_ti[2]), 2.4, 1.4)
add("brazo_servo_elevador", brazo_el, "blanco"); add("brazo_servo_timon", brazo_ti, "blanco")
def salida(p0, p1, n=400):
    p0, p1 = Vector(*p0), Vector(*p1)
    for i in range(n + 1):
        q = p0 + (p1 - p0)*(i/n)
        if not fus.is_inside(q): return q, (p1 - p0).normalized()
    return p1, (p1 - p0).normalized()
guias = None
SALIDAS = {}
for nom, a, b in (("elevador", punta_el, hole_el), ("timon", punta_ti, hole_ti)):
    q, u = salida(a, b); SALIDAS[nom] = q
    g = varilla(tuple(q - u*14), tuple(q + u*4), 2.2) - varilla(tuple(q - u*16), tuple(q + u*6), 1.2)
    guias = g if guias is None else guias + g
add("guias_varillas", guias, "negro")

# ======================= TREN =======================
def rueda(c, R, W):
    x, y, z = c
    neum = Rot(90, 0, 0) * (Torus(major_radius=R - W*0.42, minor_radius=W*0.42) +
                            Cylinder(radius=R - W*0.42, height=W*0.84))
    buje = Rot(90, 0, 0) * Cylinder(radius=R*0.27, height=W*0.9)
    return Pos(x, y, z) * neum, Pos(x, y, z) * buje

# tren principal detallado (tren_aterrizaje.py): patas que giran en soportes, cables cruzados
# con resortes de tension, ruedas de espuma con buje de 5 cavidades, perno, collarin y tuerca
import tren_aterrizaje_v12 as tr          # v12: geometria del tren medida en las fotos
piezas_tren, RIG_TREN, RESORTE_LOCAL = tr.construir(fus)
EJE, RUEDA_R = tr.RUEDA_C, tr.RUEDA_R      # el contacto con el suelo sale del tren real
for k, (s_, m_) in piezas_tren.items():
    add(k, s_, m_)

cn, cb = rueda(COLA_EJE, COLA_R, 9)
add("rueda_cola", cn, "espuma"); add("buje_cola", cb, "gris_claro")
# v8 (foto de la cola): soporte gris FIJO atornillado bajo el fin del fuselaje con 2 tornillos de laton;
# el alambre sube por el soporte en el eje de la bisagra del timon y su punta doblada entra en el timon,
# asi la rueda gira exactamente con el timon; abajo se dobla hacia atras (avance de la rueda = estabilidad)
Z_SOP = (-78.0, -71.0)
soporte_cola = Pos((938 + 988)/2, 0, sum(Z_SOP)/2) * Box(50, 13, Z_SOP[1] - Z_SOP[0])
soporte_cola = soporte_cola - Pos(xr, 0, sum(Z_SOP)/2) * Cylinder(radius=1.3, height=20)
torn_cola = Pos(946, 0, Z_SOP[0] - 0.6) * Cylinder(radius=2.4, height=1.8) + Pos(962, 0, Z_SOP[0] - 0.6) * Cylinder(radius=2.4, height=1.8)
add("soporte_rueda_cola", soporte_cola - fus, "gris_claro")
add("tornillos_rueda_cola", torn_cola, "laton")
alambre_cola = (varilla((xr + 12, 0, -56), (xr, 0, -64), 1.1) + varilla((xr, 0, -64), (xr, 0, -90), 1.1)
                + varilla((xr, 0, -90), (COLA_EJE[0], 0, COLA_EJE[2]), 1.1)
                + varilla((COLA_EJE[0], -6, COLA_EJE[2]), (COLA_EJE[0], 6, COLA_EJE[2]), 1.1))
add("alambre_rueda_cola", alambre_cola, "metal")

# ======================= HELICE TRIPALA Y SPINNER =======================
# modelo detallado en helice_spinner.py (paso real por radio, perfil, spinner hueco con ranuras)
import helice_spinner as hs
X_BUJE = -9.5                    # centro del buje: deja 2,5 mm entre la contraplaca que gira y la nariz (v8)
CAIDA_MOTOR, DERECHA_MOTOR = 2.0, 2.0   # grados de caida y de desviacion a la derecha del eje del motor (v7)
def eje_motor(s_):
    return (Pos(X_BUJE, 0, 0) * Rot(0, 0, -DERECHA_MOTOR) * Rot(0, -CAIDA_MOTOR, 0) * Pos(-X_BUJE, 0, 0)) * s_
GIRO_INICIAL = 15.0              # posicion angular de las palas en la escena
MAT_HELICE = {"helice": "nylon_negro", "spinner": "spinner_negro", "contraplaca": "aluminio",
              "tornillos_spinner": "cromo", "tuerca": "cromo"}
for k, s_ in hs.construir().items():
    add(k, eje_motor(Pos(X_BUJE, 0, 0) * Rot(GIRO_INICIAL, 0, 0) * s_), MAT_HELICE[k])

# ======================= COMPONENTES INTERNOS =======================
# masas estimadas (g) y posicion x (mm desde el plano de la helice). Verificar con la bascula.
COMPONENTES = {
    "motor":      dict(masa=160.0, x=29.5,  caja=(37, 42, 42),  z=0.0,   mat=None),        # outrunner 15: campana 11-41 + soporte 41-48 (v10)
    "variador":   dict(masa=60.0,  x=100.0, caja=(70, 32, 14),  z=-4.0,  mat="negro"),     # ESC 60 A, sobre la bateria
    "bateria":    dict(masa=340.0, x=190.0, caja=(140, 44, 36), z=-29.0, mat="bateria", recorrido=150.0),  # 4S 3200; v9: dentro del fuselaje
    "receptor":   dict(masa=12.0,  x=360.0, caja=(40, 24, 12),  z=-62.0, mat="negro"),
    "servos_cola": dict(masa=26.0, x=470.0, caja=(32, 40, 30),  z=-55.0, mat="negro"),     # 2 x 13 g
    "servos_ala": dict(masa=36.0,  x=X_BA + 0.47*CUERDA, caja=(0, 0, 0), z=0.0, mat=None),   # 4 x 9 g, ya modelados
    "cableado_luces": dict(masa=40.0, x=300.0, caja=(0, 0, 0), z=0.0, mat=None),
}
for k, c in COMPONENTES.items():
    if c["mat"]:
        lx, ly, lz = c["caja"]
        caja_c = Pos(c["x"], 0, c["z"]) * Box(lx, ly, lz)
        add("interno_" + k, eje_motor(caja_c) if k == "motor" else caja_c, c["mat"])
_tramos = [(0, CUERDA)] + [(y, c) for y, c, _, _ in PUNTA]
S_ALA_DM2 = 2*sum((c0 + c1)/2*(y1 - y0) for (y0, c0), (y1, c1) in zip(_tramos, _tramos[1:]))/1e4
# v8: la helice no flota: eje del motor (5 mm) desde el motor, a traves de contraplaca, helice y cono,
# con la tuerca al frente; el motor se atornilla a una bancada (cortafuegos) pegada al fuselaje
_xm0 = COMPONENTES["motor"]["x"] - COMPONENTES["motor"]["caja"][0]/2
# v10: el eje atraviesa la campana y llega a los rodamientos del soporte fijo (si no, la helice "flota")
_xe = 47.0
add("eje_motor", eje_motor(Pos((_xe + X_BUJE - 16)/2, 0, 0) * Rot(0, 90, 0) * Cylinder(radius=2.5, height=_xe - (X_BUJE - 16))), "metal")
_xb = COMPONENTES["motor"]["x"] + COMPONENTES["motor"]["caja"][0]/2
# ======================= CAPOTA, MOTOR Y REFRIGERACION (v10, foto de la nariz) =======================
X_CAPOTA = 85.0                       # la capota de plastico termina aqui; detras empieza la espuma
X_BANC = (_xb, _xb + 4)               # bancada (cortafuegos) que llena la seccion de la nariz
def y_superficie(x, z):
    """y de la piel del fuselaje (lado derecho) en (x, z), por biseccion"""
    lo, hi = 0.0, 80.0
    for _ in range(30):
        m = (lo + hi)/2
        if fus.is_inside(Vector(x, m, z)): lo = m
        else: hi = m
    return lo
cavidad = fuselaje(-2.5) & caja(10.5, X_BANC[0], -G, G, -G, G)
capota = (fus & caja(-G, X_CAPOTA, -G, G, -G, G)) - cavidad
partes["fuselaje_blanco"] = (partes["fuselaje_blanco"][0] - caja(-G, X_CAPOTA, -G, G, -G, G), "blanco")
# motor outrunner: la campana gira con la helice; el soporte en cruz queda fijo en la bancada
campana = eje_motor(Pos(26, 0, 0) * Rot(0, 90, 0) * (Cylinder(radius=21, height=30) - Pos(0, 0, 13) * Cylinder(radius=17, height=4.5)))
soporte_m = eje_motor(Pos(44.5, 0, 0) * Rot(0, 90, 0) * Cylinder(radius=13, height=7) + Pos(X_BANC[0] - 1, 0, 0) * Box(2, 44, 6) + Pos(X_BANC[0] - 1, 0, 0) * Box(2, 6, 44))
bancada = fuselaje(-2.5) & eje_motor(caja(X_BANC[0], X_BANC[1], -G, G, -G, G))
# holgura de la campana que gira: 2,5 mm en todo su contorno (abre la capota arriba, como en la foto)
hueco_campana = eje_motor(Pos(23.5, 0, 0) * Rot(0, 90, 0) * Cylinder(radius=23.5, height=39))
capota = capota - hueco_campana
for _n in ("panel_nariz", "filete_nariz"):
    partes[_n] = (partes[_n][0] - hueco_campana, partes[_n][1])
# tomas de aire ovaladas en la parte baja del frente (fotos de frente y de la nariz)
TOMAS = [(sy*17.0, -21.0, 8.0, 5.5) for sy in (1, -1)]          # (y, z, semieje y, semieje z)
for ty, tz, a_, b_ in TOMAS:
    capota = capota - extrude(Plane.YZ.offset(0) * Pos(ty, tz) * Ellipse(a_, b_), amount=14)
# salida de aire en la panza de la capota, delante de la bancada (no se ve en las fotos: supuesta)
SALIDA = (18.0, 46.0, 17.0)                                       # x0, x1, semiancho
capota = capota - caja(SALIDA[0], SALIDA[1], -SALIDA[2], SALIDA[2], -80, -20)
# hueco ovalado para el tornillo inferior y tornillos que sujetan la capota a la bancada
X_TORN = (X_BANC[0] + X_BANC[1])/2
torn_cap, huecos = None, None
for sy in (1, -1):
    ys = y_superficie(38, -23)
    # v11: depresion lisa (elipsoide) de 1,8 mm, inclinada 12 grados (sube hacia la nariz, como en la foto)
    h_ = Pos(38, sy*(ys + 6.0 - 2.2), -23) * Rot(0, 12, 0) * scale(Sphere(1.0), by=(15.0, 6.0, 6.0))
    huecos = h_ if huecos is None else huecos + h_
    for xz in ((X_TORN, 3.4), (X_TORN, -25.5)):
        y0 = y_superficie(*xz) - (2.2 if xz[1] < 0 else 0.0)
        t_ = (Pos(xz[0], sy*(y0 + 0.4), xz[1]) * Rot(90, 0, 0) * Cylinder(radius=2.4, height=1.2)
              + Pos(xz[0], sy*(y0 - 7), xz[1]) * Rot(90, 0, 0) * Cylinder(radius=1.1, height=15))
        torn_cap = t_ if torn_cap is None else torn_cap + t_
capota = capota - huecos
# placa del escape (panel aparte con tornillo en la esquina superior) y escape cromado:
# cerrado y redondeado adelante, abierto atras con ranura horizontal (decorativo: motor electrico)
# v11: contorno de la placa medido en la foto (borde delantero recto con el tornillo arriba, bordes
# inferior y trasero curvos)
CONTORNO_PLACA = [(39, 9), (62, 10), (80, 9), (87, 5), (90, -8), (88, -21), (80, -31), (64, -33), (55, -27), (47, -18), (39, -12)]
_cp = Wire([Edge.make_spline([Vector(x, 0, z) for x, z in CONTORNO_PLACA], periodic=True)])
mascara_placa = extrude(Plane.XZ * Face(Wire([Edge.make_spline([Vector(x, z, 0) for x, z in CONTORNO_PLACA], periodic=True)])), amount=G, both=True)
placa = ((fuselaje(0.6) - fus) & mascara_placa) - caja(-G, G, -20, 20, -G, G) - huecos
esc = []
for sy in (1, -1):
    # tubo apoyado sobre la placa; cerrado y redondeado adelante; atras abierto, con borde en bisel
    # hacia afuera y un separador horizontal en la boca ("boca de pez", foto)
    # v11: medido en la foto: diametro ~16 mm y ~6 mm de separacion bajo el filete rojo
    ZE, RE = -9.0, (7.5, 8.0)            # semiejes (vertical, lateral)
    def tubo_el(a, b, rz, ry):
        a, b = Vector(*a) if not isinstance(a, Vector) else a, Vector(*b) if not isinstance(b, Vector) else b
        pl = Plane(origin=a, x_dir=(0, 0, 1), z_dir=(b - a).normalized())
        return extrude(pl * Ellipse(rz, ry), amount=(b - a).length)
    p0 = Vector(58, sy*(y_superficie(58, ZE) + RE[1] - 0.6), ZE); p1 = Vector(108, sy*(y_superficie(108, ZE) + RE[1] - 0.6), ZE)
    u = (p1 - p0).normalized()
    _ang = math.degrees(math.atan2(u.Y, u.X))
    ext = tubo_el(p0, p1, *RE) + Pos(*p0) * Rot(0, 0, _ang) * scale(Sphere(1.0), by=(9.0, RE[1]*0.995, RE[0]*0.995))
    hueco_t = tubo_el(p0 + u*6, p1 + u*3, RE[0] - 1.3, RE[1] - 1.3)
    tubo = ext - hueco_t
    separador = (tubo_el(p0 + u*30, p1, RE[0] - 1.2, RE[1] - 1.2) & caja(-G, G, -G, G, ZE - 0.5, ZE + 0.5))
    a_b = math.radians(22)                                   # bisel: el lado de afuera queda mas corto
    n_b = Vector(u.X*math.cos(a_b) - sy*(-u.Y)*0 , u.Y*math.cos(a_b) + sy*math.sin(a_b)*abs(u.X), 0).normalized()
    pl_b = Plane(origin=p1 - u*3.0, z_dir=n_b)
    corte = pl_b * Pos(0, 0, 60) * Box(200, 200, 120)
    tubo = (tubo + separador) - corte
    # (no se resta el fuselaje: ese booleano falla con esta geometria; el tubo solo se apoya 0,6 mm en la placa)
    assert tubo.volume > 1000, "escape vacio"
    esc.append(tubo)
torn_placa = None
for sy in (1, -1):
    yp = y_superficie(47, 6) + 0.6
    t_ = Pos(47, sy*(yp + 0.5), 6) * Rot(90, 0, 0) * Cylinder(radius=2.0, height=1.0) + Pos(47, sy*(yp - 5), 6) * Rot(90, 0, 0) * Cylinder(radius=0.9, height=11)
    torn_placa = t_ if torn_placa is None else torn_placa + t_
add("capota", capota, "plastico")
add("campana_motor", campana, "cromo")
add("soporte_motor", soporte_m, "metal")
add("bancada_motor", bancada, "madera")
add("tornillos_capota", torn_cap, "cromo")
add("placas_escape", placa, "plastico")
add("escapes", esc[0] + esc[1], "cromo")
add("tornillos_placa_escape", torn_placa, "cromo")
# refrigeracion: area de entrada (tomas + anillo alrededor del cono) contra area de salida
_cara = Face(Wire.make_polygon([Vector(0, p.Y, p.Z) for p in [superelipse(*EST["nariz"][0]) @ (i/64) for i in range(64)]], close=True))
_anillo = Face(Wire.make_polygon([Vector(0, 23.5*math.cos(t), 23.5*math.sin(t)) for t in [2*math.pi*i/72 for i in range(72)]], close=True))
_cono = Face(Wire.make_polygon([Vector(0, 19.5*math.cos(t), 19.5*math.sin(t)) for t in [2*math.pi*i/72 for i in range(72)]], close=True))
A_anillo = (_cara & _anillo).area - (_cara & _cono).area
A_tomas = sum(math.pi*a_*b_ for _, _, a_, b_ in TOMAS)
A_salida = (SALIDA[1] - SALIDA[0])*2*SALIDA[2]
REFRIG = dict(entrada_tomas_mm2=round(A_tomas), entrada_anillo_mm2=round(A_anillo),
              salida_mm2=round(A_salida), relacion_salida_entrada=round(A_salida/(A_tomas + A_anillo), 2))
print("REFRIGERACION", REFRIG)

# v9: perforacion para la barra de torsion del elevador en las piezas fijas que atraviesa (con buje)
_perf = Pos(xb, 0, zs) * Rot(90, 0, 0) * Cylinder(radius=1.8, height=2*_w1 + 4)
for _n in list(partes):
    _s, _m = partes[_n]
    if _n in ("timon_profundidad", "union_elevador") or _n.startswith("elevador"): continue
    try:
        if (_s & _perf).volume > 1e-3: partes[_n] = (_s - _perf, _m)
    except Exception: pass
_buje = Pos(xb, 0, zs) * Rot(90, 0, 0) * (Cylinder(radius=3.2, height=2*_w1 - 3) - Cylinder(radius=1.8, height=2*_w1))
add("buje_torsion_elevador", _buje - fus, "gris_claro")

# ======================= EXPORTAR =======================
mover = Pos(-X_BA, 0, 0)              # origen en el borde de ataque de la raiz
mats = {}
for nombre, (s, mat) in partes.items():
    s = mover * s
    b = s.bounding_box()
    print(f"{nombre:24s} x[{b.min.X:6.0f},{b.max.X:6.0f}] y[{b.min.Y:6.0f},{b.max.Y:6.0f}] "
          f"z[{b.min.Z:5.0f},{b.max.Z:5.0f}] vol {s.volume/1000:7.1f} cm3 valido {s.is_valid}")
    export_stl(s, os.path.join(OUT, f"{nombre}.stl"), tolerance=0.2, angular_tolerance=0.12)
    mats[nombre] = mat
    partes[nombre] = (s, mat)

def dihedro_pt(p, lado):
    a = math.radians(DIEDRO); x, y, z = p
    y2, z2 = y*math.cos(a) - z*math.sin(a), y*math.sin(a) + z*math.cos(a)
    return [x - X_BA, (y2 if lado > 0 else -y2), z2]
def dihedro_dir(lado):
    a = math.radians(DIEDRO)
    return [0.0, math.cos(a), (math.sin(a) if lado > 0 else -math.sin(a))]   # TE abajo = giro positivo
d_ = lambda p: [p[0] - X_BA, p[1], p[2]]
grupos = {
    "aleron_der": dict(p=dihedro_pt((xh, ALERON_Y[0], zh), 1), d=dihedro_dir(1), miembros=["aleron_der"]),
    "aleron_izq": dict(p=dihedro_pt((xh, ALERON_Y[0], zh), -1), d=dihedro_dir(-1), miembros=["aleron_izq"]),
    "flap_der": dict(p=dihedro_pt((xh, FLAP_Y[0], zh), 1), d=dihedro_dir(1), miembros=["flap_der"]),
    "flap_izq": dict(p=dihedro_pt((xh, FLAP_Y[0], zh), -1), d=dihedro_dir(-1), miembros=["flap_izq"]),
    "elevador": dict(p=d_((xb, 0, zs)), d=[0, 1, 0], miembros=["timon_profundidad", "union_elevador",
                                                               "elevador_superior_rojo", "elevador_superior_negro"]),
    "timon": dict(p=d_((xr, 0, 0)), d=[0, 0, 1], miembros=["timon_direccion", "timon_franja_roja", "timon_franjas_negras"]),
    "rueda_cola": dict(p=d_((xr, 0, -64)), d=[0, 0, 1], miembros=["rueda_cola", "buje_cola", "alambre_rueda_cola"]),
}
rel_al = (zh - hole_al[2])/(piv_al[2] - punta_al[2])     # brazo del cuerno / brazo del servo
rel_fl = (zh - hole_fl[2])/(piv_fl[2] - punta_fl[2])
varillas = {
    "aleron_der": dict(servo=dihedro_pt(punta_al, 1), cuerno=dihedro_pt(hole_al, 1), r=0.8,
                       pivote=dihedro_pt(piv_al, 1), d=dihedro_dir(1), relacion=rel_al, brazo="brazo_servo_aleron_der"),
    "aleron_izq": dict(servo=dihedro_pt(punta_al, -1), cuerno=dihedro_pt(hole_al, -1), r=0.8,
                       pivote=dihedro_pt(piv_al, -1), d=dihedro_dir(-1), relacion=rel_al, brazo="brazo_servo_aleron_izq"),
    "flap_der": dict(servo=dihedro_pt(punta_fl, 1), cuerno=dihedro_pt(hole_fl, 1), r=0.8,
                     pivote=dihedro_pt(piv_fl, 1), d=dihedro_dir(1), relacion=rel_fl, brazo="brazo_servo_flap_der"),
    "flap_izq": dict(servo=dihedro_pt(punta_fl, -1), cuerno=dihedro_pt(hole_fl, -1), r=0.8,
                     pivote=dihedro_pt(piv_fl, -1), d=dihedro_dir(-1), relacion=rel_fl, brazo="brazo_servo_flap_izq"),
    "elevador": dict(servo=d_(punta_el), cuerno=d_(hole_el), r=0.9, pivote=d_(SERVO_EL["pivote"]), d=list(SERVO_EL["eje"]),
                     relacion=(zs - hole_el[2])/BRAZO_COLA, brazo="brazo_servo_elevador"),
    "timon": dict(servo=d_(punta_ti), cuerno=d_(hole_ti), r=0.9, pivote=d_(SERVO_TI["pivote"]), d=list(SERVO_TI["eje"]),
                  relacion=abs(hole_ti[1])/BRAZO_COLA, brazo="brazo_servo_timon"),
}
def mv(p): return [p[0] - X_BA, p[1], p[2]]
componentes = {k: dict(v, x=v['x'] - X_BA) for k, v in COMPONENTES.items()}
rig_tren = dict(radio_rueda=RIG_TREN["radio_rueda"],
                pivotes={k: mv(v) for k, v in RIG_TREN["pivotes"].items()},
                ruedas={k: mv(v) for k, v in RIG_TREN["ruedas"].items()},
                anclajes={k: mv(v) for k, v in RIG_TREN["anclajes"].items()},
                cables={k: dict(v, ojal=mv(v["ojal"]), anclaje=mv(v["anclaje"])) for k, v in RIG_TREN["cables"].items()},
                rueda_cola=dict(centro=mv(COLA_EJE), radio=COLA_R))
export_stl(Rot(-90, 0, 0) * RESORTE_LOCAL, os.path.join(OUT, "_resorte_local.stl"), tolerance=0.02, angular_tolerance=0.1)
contactos = dict(principal=[EJE[0] - X_BA, EJE[2] - RUEDA_R], cola=[COLA_EJE[0] - X_BA, COLA_EJE[2] - COLA_R])
json.dump(dict(materiales=mats, contactos_mm=contactos, bisagras=grupos, varillas=varillas, mandos=MANDOS, tren=rig_tren, componentes=componentes, refrigeracion=REFRIG,
               motor=dict(buje=[X_BUJE - X_BA, 0, 0], caida=CAIDA_MOTOR, derecha=DERECHA_MOTOR, mac=CUERDA)), open(os.path.join(OUT, "escena.json"), "w"), indent=1)
todo = Compound(children=[s for s, _ in partes.values()])
export_step(todo, os.path.join(BASE, "turbo_timber_evolution_v12.step"))
bb = todo.bounding_box()
print("CONJUNTO", bb.min, bb.max, bb.size)
