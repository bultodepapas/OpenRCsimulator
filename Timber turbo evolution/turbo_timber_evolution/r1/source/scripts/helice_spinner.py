"""
Helice tripala + spinner del Turbo Timber Evolution - modelo parametrico (build123d)

Ejes locales: X = eje del motor, el empuje va hacia -X (adelante); origen en el centro del buje.
Giro: horario visto desde atras (antihorario visto de frente), helice tractora estandar.

Formas tomadas de las fotos: palas negras con raiz angosta que sale del spinner, cuerda maxima
cerca del 55 % del radio, borde de ataque que se curva hacia una punta redondeada; spinner negro
conico de punta fina, casi del diametro de la nariz.
"""
import math
from build123d import *

# ======================= PARAMETROS =======================
DIAMETRO   = 279.4      # 11 in
PASO       = 177.8      # 7 in  (paso geometrico)
N_PALAS    = 3
R_BUJE     = 11.0       # radio del buje central
L_BUJE     = 12.0       # espesor axial del buje
EJE_D      = 5.0        # agujero del eje / adaptador
# distribucion de cuerda (fraccion del radio) y espesor relativo, medidas sobre las fotos
#          r/R    c/R    t/c   flecha/R (desplazamiento hacia el borde de salida)
ESTACIONES = [
    (0.095, 0.092, 0.30, 0.000),
    (0.160, 0.118, 0.24, 0.000),
    (0.240, 0.148, 0.18, 0.000),
    (0.330, 0.170, 0.145, 0.003),
    (0.430, 0.184, 0.125, 0.008),
    (0.530, 0.192, 0.112, 0.014),
    (0.630, 0.194, 0.104, 0.021),
    (0.720, 0.190, 0.098, 0.029),
    (0.800, 0.180, 0.094, 0.037),
    (0.870, 0.163, 0.092, 0.046),
    (0.920, 0.142, 0.090, 0.054),
    (0.958, 0.114, 0.090, 0.062),
    (0.984, 0.076, 0.090, 0.070),
    (1.000, 0.030, 0.090, 0.076),
]
EJE_PASO_CUERDA = 0.33   # posicion del eje de paso a lo largo de la cuerda
N_PERFIL = 22            # puntos por lado del perfil

# spinner
SP_R       = 19.5       # radio de la base (medido: diametro ~39 mm)
SP_L       = 44.0       # largo
SP_PARED   = 1.6
SP_BASE_X  = 12.0       # la base del spinner queda 12 mm detras del centro del buje
PLACA_E    = 3.0        # espesor de la contraplaca
HOLGURA    = 1.2        # holgura de las ranuras alrededor de la raiz de la pala

R = DIAMETRO/2

# ======================= PERFIL =======================
def perfil(m, p, t, n=N_PERFIL):
    """perfil tipo NACA 4 digitos con parametros continuos; antihorario desde el borde de salida"""
    xs = [(1 - math.cos(math.pi*i/n))/2 for i in range(n + 1)]
    up, lo = [], []
    for x in xs:
        yt = 5*t*(0.2969*math.sqrt(x) - 0.1260*x - 0.3516*x**2 + 0.2843*x**3 - 0.1015*x**4)
        if m == 0:  yc = 0.0
        elif x < p: yc = m/p**2*(2*p*x - x**2)
        else:       yc = m/(1 - p)**2*(1 - 2*p + 2*p*x - x**2)
        up.append((x, yc + yt)); lo.append((x, yc - yt))
    return up[::-1] + lo[1:-1]

def angulo_paso(r):
    return math.atan(PASO/(2*math.pi*r))

def seccion(rR, cR, tc, flecha, extra=0.0):
    """seccion de la pala a radio r. extra = crecimiento (mm) para hacer las ranuras del spinner"""
    r = rR*R; c = cR*R + 2*extra; b = angulo_paso(r)
    # cuerda: del borde de ataque (+Y, adelante) al de salida (-Y, atras)
    cu = Vector(math.sin(b), -math.cos(b), 0)
    ar = Vector(-math.cos(b), -math.sin(b), 0)          # cara de succion hacia adelante (-X)
    camber = 0.02 + 0.02*min(1.0, rR/0.45)
    pts = perfil(camber, 0.40, tc + (2*extra/c if extra else 0))
    base = Vector(0, 0, r) + cu*(flecha*R)
    return Wire.make_polygon([base + cu*((x - EJE_PASO_CUERDA)*c) + ar*(z*c) for x, z in pts], close=True)

RAIZ = ((R_BUJE - 3)/R, 11.0/(DIAMETRO/2), 0.55, 0.0)   # cuello grueso que entra en el buje

def pala(extra=0.0, hasta=1.0):
    secs = [seccion(*RAIZ, extra=extra)] + [seccion(*e, extra=extra) for e in ESTACIONES if e[0] <= hasta + 1e-9]
    return Solid.make_loft(secs)

def repetir(s):
    out = s
    for k in range(1, N_PALAS):
        out = out + Rot(360.0*k/N_PALAS, 0, 0) * s
    return out

# ======================= PIEZAS =======================
def construir():
    una = pala()
    buje = Rot(0, 90, 0) * Cylinder(radius=R_BUJE, height=L_BUJE)
    helice = repetir(una) + buje
    helice = helice - Rot(0, 90, 0) * Cylinder(radius=EJE_D/2, height=L_BUJE + 4)

    # spinner: revolucion de un perfil ojival con punta fina redondeada
    def perfil_sp(rb, lb, n=24):
        pts = []
        for i in range(n + 1):
            u = i/n
            pts.append((SP_BASE_X - u*lb, rb*(1 - u**1.25)**0.72))   # cono casi recto, punta fina
        pts[-1] = (SP_BASE_X - lb, 0.0)
        return pts
    def solido_rev(pts):
        with BuildPart() as bp:
            with BuildSketch(Plane.XY):
                with BuildLine():
                    Spline(*pts[:-1])
                    Line(pts[-2], pts[-1])
                    Line(pts[-1], (SP_BASE_X, 0))
                    Line((SP_BASE_X, 0), pts[0])
                make_face()
            revolve(axis=Axis.X)
        return bp.part
    exterior = solido_rev(perfil_sp(SP_R, SP_L))
    interior = solido_rev([(x + 0.0, y) for x, y in perfil_sp(SP_R - SP_PARED, SP_L - 2.5*SP_PARED)])
    spinner = exterior - interior
    # ranuras por donde salen las palas
    env = pala(extra=HOLGURA, hasta=0.33)
    spinner = spinner - repetir(env)

    # contraplaca con escalon que entra en el spinner
    placa = (Pos(SP_BASE_X + PLACA_E/2, 0, 0) * Rot(0, 90, 0) * Cylinder(radius=SP_R, height=PLACA_E)
             + Pos(SP_BASE_X - 2, 0, 0) * Rot(0, 90, 0) * Cylinder(radius=SP_R - SP_PARED - 0.2, height=4))
    placa = placa - Rot(0, 90, 0) * Cylinder(radius=EJE_D/2, height=200)
    placa = placa - repetir(env)

    # tornillos del spinner: entran de lado cerca de la base, entre pala y pala
    torn = None
    for k in range(N_PALAS):
        a = 360.0*(k + 0.5)/N_PALAS
        t = Rot(a, 0, 0) * (Pos(SP_BASE_X - 3.0, 0, SP_R - 0.9) * (Cylinder(radius=1.6, height=1.4)
                                                                   - Pos(0, 0, 0.5) * Box(2.4, 0.5, 1.0)))
        torn = t if torn is None else torn + t

    # tuerca del eje (se ve por la ranura)
    tuerca = Pos(-L_BUJE/2 - 3, 0, 0) * Rot(0, 90, 0) * (Cylinder(radius=4.5, height=6) - Cylinder(radius=EJE_D/2, height=8))

    return {"helice": helice, "spinner": spinner, "contraplaca": placa,
            "tornillos_spinner": torn, "tuerca": tuerca}

def datos():
    sig = 0.0
    filas = []
    for (rR, cR, tc, fl) in ESTACIONES:
        filas.append((rR, rR*R, cR*R, math.degrees(angulo_paso(rR*R)), tc))
    # area de una pala (trapecios)
    A = sum((filas[i+1][1] - filas[i][1])*(filas[i][2] + filas[i+1][2])/2 for i in range(len(filas) - 1))
    solidez = N_PALAS*A/(math.pi*R**2)
    return filas, A, solidez

if __name__ == "__main__":
    import os, json
    BASE = os.path.dirname(os.path.abspath(__file__)); OUT = os.path.join(BASE, "helice_out"); os.makedirs(OUT, exist_ok=True)
    piezas = construir()
    for k, s in piezas.items():
        b = s.bounding_box(optimal=True)
        print(f"{k:18s} x[{b.min.X:6.1f},{b.max.X:6.1f}] y[{b.min.Y:7.1f},{b.max.Y:7.1f}] z[{b.min.Z:7.1f},{b.max.Z:7.1f}]"
              f" vol {s.volume/1000:7.2f} cm3 valido {s.is_valid}")
        export_stl(s, os.path.join(OUT, f"{k}.stl"), tolerance=0.05, angular_tolerance=0.08)
    export_step(Compound(children=list(piezas.values())), os.path.join(OUT, "helice_spinner.step"))
    filas, A, sol = datos()
    print(f"D={DIAMETRO} mm  P={PASO} mm  area/pala={A/100:.1f} cm2  solidez={sol:.3f}")
    for f in filas: print("r/R %.3f  r %6.1f  c %5.1f  beta %5.1f  t/c %.3f" % f)
