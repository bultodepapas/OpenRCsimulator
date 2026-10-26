"""
Skywalker X8 (ala volante FPV/UAV, 2120 mm) - modelo parametrico para Blender 4.2+ / 5.x
======================================================================================

Como usarlo
-----------
* Dentro de Blender: pestana Scripting > Open > este archivo > Run Script.
* Sin interfaz:      blender -b -P x8_skywalker_blender.py
* Como modulo:       python x8_skywalker_blender.py   (con `pip install bpy`)

Fuentes de la geometria
-----------------------
* Plano oficial de vistas (envergadura 2120 mm, longitud de fuselaje 790 mm). El contorno en
  planta se digitalizo pixel a pixel; su area proyectada da 0,742 m2.
* Gryte et al., "Aerodynamic modeling of the Skywalker X8", ICUAS 2018 (NTNU):
  b = 2,10 m, S = 0,75 m2, MAC = 0,357 m, CG a 440 mm de la nariz.
* Ficha del fabricante: area 80 dm2, peso en vuelo 2,5-3 kg, CG 430-440 mm de la nariz,
  helice 12x8 plegable, motor 4250-500KV o 5010-810KV.
* Fotografias del kit (vistas superior, inferior, frontal, trasera y 3/4).

Mecanica y logica de mando (version 2)
--------------------------------------
* Bisagra superior con cinta: el eje es una recta en el extrados (el elevon gira como solido
  rigido) y el intrados del ala lleva un chaflan de 35 grados para que el elevon pueda bajar.
* Por semiala: servo Emax ES3054 (17 g, 3,5 kg cm a 6 V) en una bahia del intrados, brazo de
  14 mm, varilla de acero de 1,5 mm y 95 mm con doblez en Z y horquilla, y cuerno naranja cuyo
  agujero queda 21,95 mm debajo del eje de bisagra, justo en su vertical.
* El elevon cuelga de "X8_Eje_Bisagra_*" y gira sobre su X local; la varilla sigue al agujero
  del brazo (Copy Location) y apunta al agujero del cuerno (Damped Track). La deflexion sale de
  la solucion exacta del cuadrilatero articulado, asi que el largo de la varilla no cambia.
* Logica con drivers de expresion simple (no hace falta permitir scripts):
  X8_Mando_RC (palancas y ajustes) -> X8_Mezclador (mezcla de elevones y PWM) ->
  X8_Servo_ES3054_* (giro del eje y del brazo) -> X8_Agujero_Brazo_* -> X8_Eje_Bisagra_*
  (deflexion). Hay una animacion de prueba en los fotogramas 1-240 y un panel "X8" en la
  barra lateral (tecla N) si se permiten scripts.
* x8_logica_mandos.py repite las mismas cuentas en Python puro, con cargas y equivalencias
  para ArduPilot e INAV.

Convenciones
------------
Unidades de Blender en metros. La nariz apunta a -Y, +Z hacia arriba y X es la envergadura
(el ala derecha del piloto queda en -X). El origen de la escena esta en el CG nominal
(440 mm detras de la nariz). Internamente las tablas estan en mm: x = distancia hacia atras
desde la nariz, s = distancia a la linea central y z = altura.
"""

import math
import numpy as np
import bpy
import bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

# ----------------------------------------------------------------------------------------
# Parametros (mm y grados)
# ----------------------------------------------------------------------------------------
P = dict(
    x_cg=440.0,            # CG nominal desde la nariz (fabricante y NTNU)
    s_joint=236.0,         # union seccion central / ala (costilla naranja)
    rib_w=3.0,             # ancho de la costilla naranja
    s_tip=935.0,           # punta del ala (inicio del winglet curvo)
    z0=8.0,                # altura del plano de cuerdas del ala sobre el eje de la nariz
    dihedral=1.5,          # diedro del panel exterior
    washout=-2.5,          # torsion en la punta (negativa = borde de ataque hacia abajo)
    tc_root=0.11,          # espesor relativo en la raiz
    tc_tip=0.08,           # espesor relativo en la punta
    camber=0.10,           # amplitud de la linea media con reflex (curvatura maxima ~1,3 %)
    te_thick=1.2,          # espesor del borde de salida (espuma EPO)
    # winglet curvo
    wl_radius=45.0,        # radio de la curva ala-winglet
    wl_cant=28.0,          # inclinacion hacia afuera respecto a la vertical
    wl_len=180.0,          # largo del tramo recto del winglet
    wl_tc=0.065,           # espesor relativo del winglet (perfil simetrico)
    # elevones: linea de bisagra RECTA (condicion para que el elevon gire como solido rigido)
    elev_s0=242.0, elev_s1=878.0,  # extremos del elevon en envergadura
    elev_c0=70.0, elev_c1=58.0,    # cuerda del elevon en sus extremos (borde de salida - bisagra)
    gap=2.0,                       # holgura en los extremos del elevon
    hinge_gap=2.0,                 # ranura superior entre ala y elevon (la cubre la cinta)
    bevel_deg=35.0,                # chaflan inferior del ala: deja bajar el elevon hasta ~35 grados
    tape_w=20.0,                   # ancho de la cinta de bisagra (10 mm a cada lado)
    # mecanica de mando (por semiala)
    link_s=515.0,                  # estacion del varillaje (plano del brazo, varilla y cuerno)
    servo_dist=95.0,               # eje del servo -> eje de bisagra = largo de la varilla (mm)
    arm_r=14.0,                    # radio del agujero usado en el brazo del servo (mm)
    horn_drop=10.0,                # agujero del cuerno por debajo del intrados del elevon (mm)
    servo_throw=45.0,              # giro del servo a +-500 us (1000-2000 us)
    pushrod_d=1.5,                 # varilla de acero (mm)
    # helice y motor
    prop_d=12 * 25.4, prop_pitch=8 * 25.4,
    motor_d=42.0, motor_len=40.0,
)
MM = 0.001

# ----------------------------------------------------------------------------------------
# Utilidades numericas (sin scipy, para que corra con el Python de Blender)
# ----------------------------------------------------------------------------------------
def _edge_slope(h0, h1, d0, d1):
    m = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
    if np.sign(m) != np.sign(d0):
        m = 0.0
    elif np.sign(d0) != np.sign(d1) and abs(m) > abs(3 * d0):
        m = 3 * d0
    return m


def pchip(xk, yk):
    """Interpolador cubico monotono (Fritsch-Carlson)."""
    xk = np.asarray(xk, float)
    yk = np.asarray(yk, float)
    h = np.diff(xk)
    d = np.diff(yk) / h
    m = np.zeros_like(yk)
    for i in range(1, len(xk) - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    m[0] = _edge_slope(h[0], h[1], d[0], d[1])
    m[-1] = _edge_slope(h[-1], h[-2], d[-1], d[-2])

    def f(x):
        x = np.asarray(x, float)
        xc = np.clip(x, xk[0], xk[-1])
        i = np.clip(np.searchsorted(xk, xc) - 1, 0, len(xk) - 2)
        t = (xc - xk[i]) / h[i]
        return ((2 * t**3 - 3 * t**2 + 1) * yk[i] + (t**3 - 2 * t**2 + t) * h[i] * m[i]
                + (-2 * t**3 + 3 * t**2) * yk[i + 1] + (t**3 - t**2) * h[i] * m[i + 1])
    return f


def smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def cosine_spacing(n):
    return 0.5 * (1 - np.cos(np.linspace(0, math.pi, n)))


# ----------------------------------------------------------------------------------------
# Planta (digitalizada del plano oficial, promedio de ambas semialas)
# ----------------------------------------------------------------------------------------
_LE_S = [0, 10, 24, 40, 59, 77, 92, 102, 110, 116, 124, 130, 135, 142, 148, 155, 160, 166,
         174, 184, 195, 209, 228, 260, 294, 330, 390, 490, 590, 690, 790, 890, 935, 1000]
_LE_X = [0, 0.45, 2.6, 7.3, 17, 32, 48, 63, 79, 94, 110, 125, 141, 156, 172, 187, 202, 218,
         233, 249, 264, 280, 295, 311, 327, 345.8, 374.5, 422.4, 470.2, 518.0, 565.8, 613.6,
         635.2, 666.3]
_TE_S = [0, 10, 26, 41, 58, 81, 115, 142, 190, 240, 290, 340, 390, 440, 490, 540, 590, 640,
         690, 740, 790, 840, 890, 935, 1000]
_TE_X = [796, 794.5, 788, 773, 758, 742, 727, 718, 714, 713.5, 714.6, 716.1, 719.8, 724.7,
         731.0, 739.3, 747.0, 755.3, 763.1, 771.8, 779.3, 788.8, 797.5, 806, 818]
LE = pchip(_LE_S, _LE_X)
TE = pchip(_TE_S, _TE_X)

# Perfil lateral del fuselaje sobre la linea central (z arriba / abajo, mm)
_FX = [0, 2, 4, 6, 9, 12, 18, 25, 44, 76, 108, 140, 171, 203, 235, 267, 299, 331, 363, 395,
       427, 458, 490, 522, 554, 586, 618, 650, 682, 714, 746, 772, 796]
_FT = [3, 9, 12.5, 15, 18, 21, 27, 33, 44, 57, 66, 73, 78, 82, 84, 84, 82.5, 81, 78, 74, 70,
       66, 61, 58, 54, 50, 48, 45, 43, 39, 34, 29, 24]
_FB = [3, -2, -4, -5.5, -7.5, -9, -13, -17, -25, -35, -40, -43, -45, -47, -47.5, -47.5, -47,
       -46, -45, -44, -43, -42, -40, -39, -37, -36, -35, -33, -31, -29, -26, -24, -22]
ZFT = pchip(_FX, _FT)
ZFB = pchip(_FX, _FB)

# Semiancho de la "capsula" del fuselaje. En la nariz coincide exactamente con el borde de
# ataque (inversa numerica de LE); detras se estrecha hacia el soporte del motor.
_S_DENSE = np.linspace(0, 166, 4001)
_LE_DENSE = LE(_S_DENSE)
_XJ = float(_LE_DENSE[-1])
_W_AFT = pchip([187, 202, _XJ, 250, 300, 360, 420, 480, 540, 600, 650, 690, 720, 750, 775, 796],
               [float(np.interp(187, _LE_DENSE, _S_DENSE)), float(np.interp(202, _LE_DENSE, _S_DENSE)),
                166, 160, 152, 150, 147, 141, 132, 120, 106, 93, 80, 64, 48, 32])


def pod_halfwidth(x):
    x = np.asarray(x, float)
    return np.where(x <= _XJ, np.interp(x, _LE_DENSE, _S_DENSE), _W_AFT(x))


def pod_exponent(x):
    return 0.6 + 0.65 * smoothstep((np.asarray(x, float) - 120.0) / 140.0)


def pod_factor(x, s):
    W = pod_halfwidth(x)
    if s <= 1e-9:
        return np.ones_like(W)
    r = s / np.maximum(W, 1e-9)
    F = np.where(r < 1.0, np.clip(1 - r * r, 0, 1) ** pod_exponent(x), 0.0)
    return F


# ----------------------------------------------------------------------------------------
# Perfil aerodinamico: espesor NACA de 4 digitos + linea media con reflex (tipo MH45)
# ----------------------------------------------------------------------------------------
def airfoil(u, tc, camb, te_rel):
    yt = 5 * tc * (0.2969 * np.sqrt(u) - 0.1260 * u - 0.3516 * u**2 + 0.2843 * u**3
                   - 0.1036 * u**4) + 0.5 * te_rel * u
    yc = camb * u * (1 - u) * (1 - u / 0.85)
    return yc + yt, yc - yt


def tc_of(s):
    t = np.clip((s - P["s_joint"]) / (P["s_tip"] - P["s_joint"]), 0, 1)
    return P["tc_root"] + (P["tc_tip"] - P["tc_root"]) * t


def twist_of(s):
    t = np.clip((s - P["s_joint"]) / (P["s_tip"] - P["s_joint"]), 0, 1)
    return P["washout"] * t


def section_2d(u, le, te, tc, camb, twist_deg, with_pod_s=None):
    """Devuelve (xu, zu), (xl, zl) en mm para fracciones de cuerda u (sin z0)."""
    c = te - le
    zu, zl = airfoil(u, tc, camb, P["te_thick"] / c)
    th = math.radians(twist_deg)
    xr = (u - 0.25) * c
    out = []
    for z in (zu, zl):
        zz = z * c
        x_ = le + 0.25 * c + xr * math.cos(th) + zz * math.sin(th)
        z_ = zz * math.cos(th) - xr * math.sin(th)
        out.append([x_, z_])
    if with_pod_s is not None:
        s = with_pod_s
        xu_ = le + u * c
        F = pod_factor(xu_, s)
        F[u <= 0] = 0.0
        for k, zf in ((0, ZFT(xu_) - P["z0"]), (1, ZFB(xu_) - P["z0"])):
            out[k][0] = out[k][0] * (1 - F) + xu_ * F
            out[k][1] = out[k][1] + (zf - out[k][1]) * F
    return out


def loop_full(up, lo):
    """Contorno cerrado: extrados de salida a ataque y luego intrados (ataque compartido)."""
    x = np.concatenate([up[0][::-1], lo[0][1:]])
    z = np.concatenate([up[1][::-1], lo[1][1:]])
    return x, z


def loop_open(up, lo):
    """Contorno sin punto compartido (para elevones: cara frontal y borde de salida)."""
    x = np.concatenate([up[0][::-1], lo[0]])
    z = np.concatenate([up[1][::-1], lo[1]])
    return x, z


# ----------------------------------------------------------------------------------------
# Trayectoria de envergadura del panel exterior (diedro + curva + winglet)
# ----------------------------------------------------------------------------------------
_S0 = P["s_joint"] + P["rib_w"] / 2       # inicio del ala (despues de la costilla)
_RAMP = 100.0
_TD = math.tan(math.radians(P["dihedral"]))


def path_A(s):
    """Tramo con diedro, con entrada suave en la raiz para empalmar con la seccion central."""
    d = s - _S0
    if d < _RAMP:
        z = _TD * d * d / (2 * _RAMP)
        dz = _TD * d / _RAMP
    else:
        z = _TD * (d - _RAMP / 2)
        dz = _TD
    return s, P["z0"] + z, math.atan(dz)


_ST, _ZT, _PHT = path_A(P["s_tip"])
_PHW = math.radians(90 - P["wl_cant"])
_R = P["wl_radius"]
_CX, _CZ = _ST - _R * math.sin(_PHT), _ZT + _R * math.cos(_PHT)
_QARC = _R * (_PHW - _PHT)
_PB_END = (_CX + _R * math.sin(_PHW), _CZ - _R * math.cos(_PHW))
_H_TOP = _PB_END[1] + P["wl_len"] * math.sin(_PHW) - _ZT


def path_BC(q):
    """q = longitud de arco desde la punta del ala."""
    if q <= _QARC:
        a = _PHT + q / _R
        return _CX + _R * math.sin(a), _CZ - _R * math.cos(a), a
    l = q - _QARC
    return _PB_END[0] + l * math.cos(_PHW), _PB_END[1] + l * math.sin(_PHW), _PHW


def winglet_le(h):
    hr = np.clip(h / _H_TOP, 0, 1)
    return 969.0 - 299.0 * (1 - hr**1.6) ** (1 / 1.6)


def winglet_te(h):
    return 905.0 + (980.0 - 905.0) * np.clip(h / _H_TOP, 0, 1)


# ----------------------------------------------------------------------------------------
# Constructor de mallas por loft de secciones
# ----------------------------------------------------------------------------------------
def to_blender(x_mm, s_mm, z_mm):
    """(x hacia atras, s envergadura, z arriba) en mm -> coordenadas de Blender en m."""
    return Vector(((-s_mm) * MM, (x_mm - P["x_cg"]) * MM, z_mm * MM))


def place_section(xs, zs, s_path, z_path, phi, side=1):
    pts = []
    sp, cp = math.sin(phi), math.cos(phi)
    for x, z in zip(xs, zs):
        s = s_path - z * sp
        zz = z_path + z * cp
        pts.append(to_blender(x, side * s, zz))
    return pts


def build_loft(name, sections, cap_start=True, cap_end=True, mat=None, smooth_angle=35):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rows = [[bm.verts.new(p) for p in sec] for sec in sections]
    n = len(rows[0])
    for a, b in zip(rows[:-1], rows[1:]):
        for i in range(n):
            j = (i + 1) % n
            try:
                bm.faces.new((a[i], a[j], b[j], b[i]))
            except ValueError:
                pass
    if cap_start:
        bm.faces.new(rows[0])
    if cap_end:
        bm.faces.new(rows[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    shade(obj, smooth_angle)
    if mat:
        obj.data.materials.append(mat)
    return obj


def shade(obj, angle_deg=35):
    me = obj.data
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    try:
        me.set_sharp_from_angle(angle=math.radians(angle_deg))
    except Exception:
        pass
    me.update()


def offset_loop(xs, zs, d):
    """Desplaza un contorno cerrado (sentido antihorario en x-z) hacia afuera d mm."""
    P2 = np.stack([xs, zs], 1)
    prev = np.roll(P2, 1, 0)
    nxt = np.roll(P2, -1, 0)
    t = nxt - prev
    nrm = np.stack([t[:, 1], -t[:, 0]], 1)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    Q = P2 + d * nrm
    return Q[:, 0], Q[:, 1]


# ----------------------------------------------------------------------------------------
# Materiales
# ----------------------------------------------------------------------------------------
def principled(name, color, rough=0.5, metal=0.0, spec=0.5, bump=None, sss=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    for key in ("Specular IOR Level", "Specular"):
        if key in b.inputs:
            b.inputs[key].default_value = spec
            break
    if sss and "Subsurface Weight" in b.inputs:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = (0.004, 0.004, 0.004)
    if bump:
        scale, strength = bump
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = scale
        nz.inputs["Detail"].default_value = 2.0
        bp = nt.nodes.new("ShaderNodeBump")
        bp.inputs["Strength"].default_value = strength
        if "Distance" in bp.inputs:
            bp.inputs["Distance"].default_value = 0.0004
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        nt.links.new(nz.outputs["Fac"], bp.inputs["Height"])
        nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    m.diffuse_color = (*color, 1)
    return m


# ----------------------------------------------------------------------------------------
# Piezas
# ----------------------------------------------------------------------------------------
NU = 90                     # puntos por cara del perfil
G = cosine_spacing(NU)

# Resolucion de teselado. El maestro usa estos valores; la version de juego los baja con
# set_resolution() (reteselado controlado: mismas ecuaciones, mismas lineas de bisagra).
RES = dict(nu=90, body=70, wing=64, outer=(8, 16, 34), elevon=48, blade=(26, 24), cav=(61, 64),
           tape=70, cyl=48, prop_pitch_sign=-1.0, joint_clear=0.0)


def set_resolution(**kw):
    """Cambia la resolucion (y dos correcciones opcionales) antes de llamar a build().

    prop_pitch_sign=-1 (por defecto desde v3.1) da una helice empujadora correcta: borde de
    ataque y cara curva hacia adelante, empuje hacia la nariz al girar con el borde de ataque
    delante (giro positivo alrededor del eje de empuje, que apunta a la nariz). Con +1 (v3)
    el paso quedaba invertido. joint_clear separa (mm) las caras de union del ala y del cuerpo
    de la costilla naranja, para que no queden coplanares.
    """
    global NU, G
    RES.update(kw)
    NU = int(RES["nu"])
    G = cosine_spacing(NU)
    _HINGE_CACHE.clear()


def body_section(s):
    s_abs = abs(s)
    le, te = float(LE(s_abs)), float(TE(s_abs))
    up, lo = section_2d(G, le, te, float(tc_of(s_abs)), P["camber"], float(twist_of(s_abs)),
                        with_pod_s=s_abs)
    x, z = loop_full(up, lo)
    return x, z + P["z0"]


def make_center_body(mat):
    half = P["s_joint"] - P["rib_w"] / 2 - RES["joint_clear"]
    n = RES["body"]
    k = np.linspace(0, 1, n)
    s_pos = half * k**1.5
    s_all = np.concatenate([-s_pos[::-1], s_pos[1:]])
    secs = []
    for s in s_all:
        x, z = body_section(s)
        secs.append([to_blender(xx, s, zz) for xx, zz in zip(x, z)])
    return build_loft("X8_Fuselaje_Central", secs, mat=mat, smooth_angle=50)


def make_rib(side, mat):
    s0 = P["s_joint"] - P["rib_w"] / 2
    secs = []
    for s in (s0, s0 + P["rib_w"]):
        x, z = body_section(s)
        x, z = offset_loop(x, z, 0.7)
        secs.append([to_blender(xx, side * s, zz) for xx, zz in zip(x, z)])
    return build_loft("X8_Costilla_Raiz_" + ("Der" if side > 0 else "Izq"), secs, mat=mat,
                      smooth_angle=50)


_HX0 = float(TE(P["elev_s0"])) - P["elev_c0"]
_HX1 = float(TE(P["elev_s1"])) - P["elev_c1"]


def hinge_x(s):
    """Linea de bisagra recta en planta (x hacia atras, mm), extrapolada linealmente."""
    return _HX0 + (s - P["elev_s0"]) / (P["elev_s1"] - P["elev_s0"]) * (_HX1 - _HX0)


def surface_at(s, x):
    """Puntos (x, z) del extrados y del intrados en la cuerda x de la estacion s (mm, sin trayectoria)."""
    le, te, tc, cb, tw = wing_station(s)
    u = np.array([(x - le) / (te - le)])
    up, lo = section_2d(u, le, te, tc, cb, tw)
    return (float(up[0][0]), float(up[1][0])), (float(lo[0][0]), float(lo[1][0]))


def thickness_at(s, x):
    up, lo = surface_at(s, x)
    return up[1] - lo[1]


def surface_point_world(s, x, side, upper=True):
    """Punto del extrados (o intrados) en coordenadas de Blender."""
    up, lo = surface_at(s, x)
    xx, zz = up if upper else lo
    sp, zp, ph = path_A(s)
    return place_section([xx], [zz], sp, zp, ph, side)[0]


def wing_station(s):
    le, te = float(LE(s)), float(TE(s))
    return le, te, float(tc_of(s)), P["camber"], float(twist_of(s))


def make_wing_main(side, mat):
    """Panel desde la costilla hasta el final del elevon, cortado en la linea de bisagra.

    Bisagra superior: el extrados llega hasta la bisagra (alli va la cinta) y el intrados
    termina antes, con un chaflan de bevel_deg, para que el elevon pueda bajar sin chocar.
    """
    s_list = np.linspace(_S0 + RES["joint_clear"], P["elev_s1"] + P["gap"], RES["wing"])
    tb = math.tan(math.radians(P["bevel_deg"]))
    secs = []
    for s in s_list:
        le, te, tc, cb, tw = wing_station(s)
        xh = hinge_x(s)
        th = thickness_at(s, xh)
        u_top = (xh - P["hinge_gap"] / 2 - le) / (te - le)
        u_bot = (xh - P["hinge_gap"] / 2 - th * tb - le) / (te - le)
        up = section_2d(G * u_top, le, te, tc, cb, tw)[0]
        lo = section_2d(G * u_bot, le, te, tc, cb, tw)[1]
        x, z = loop_full(up, lo)
        sp, zp, ph = path_A(s)
        secs.append(place_section(x, z, sp, zp, ph, side))
    return build_loft("X8_Ala_" + ("Der" if side > 0 else "Izq"), secs, mat=mat, smooth_angle=40)


def make_wing_outer(side, mat):
    """Punta del ala con cuerda completa + curva + winglet, en una sola superficie."""
    stations = []
    nA, nB, nC = RES["outer"]
    for s in np.linspace(P["elev_s1"] + P["gap"], _ST, nA):
        stations.append(("A", s))
    for q in np.linspace(0, _QARC, nB)[1:]:
        stations.append(("B", q))
    for k in np.linspace(0, 1, nC)[1:]:
        stations.append(("B", _QARC + P["wl_len"] * (1 - (1 - k) ** 1.8)))
    le_t, te_t, tc_t, cb_t, tw_t = wing_station(_ST)
    qblend = _QARC + 35.0
    secs = []
    for kind, v in stations:
        if kind == "A":
            le, te, tc, cb, tw = wing_station(v)
            sp, zp, ph = path_A(v)
        else:
            sp, zp, ph = path_BC(v)
            h = zp - _ZT
            w = float(smoothstep(v / qblend))
            le = (1 - w) * le_t + w * float(winglet_le(h))
            te = (1 - w) * te_t + w * float(winglet_te(h))
            if te - le < 6.0:
                mid = 0.5 * (le + te)
                le, te = mid - 3.0, mid + 3.0
            tc = (1 - w) * tc_t + w * P["wl_tc"]
            cb = (1 - w) * cb_t
            tw = (1 - w) * tw_t
        up, lo = section_2d(G, le, te, tc, cb, tw)
        x, z = loop_full(up, lo)
        secs.append(place_section(x, z, sp, zp, ph, side))
    return build_loft("X8_Punta_Winglet_" + ("Der" if side > 0 else "Izq"), secs, mat=mat,
                      smooth_angle=40)


def make_elevon(side, mat):
    s_list = np.linspace(P["elev_s0"] + P["gap"], P["elev_s1"], RES["elevon"])
    secs = []
    for s in s_list:
        le, te, tc, cb, tw = wing_station(s)
        u0 = (hinge_x(s) + P["hinge_gap"] / 2 - le) / (te - le)
        up, lo = section_2d(u0 + (1 - u0) * G, le, te, tc, cb, tw)
        x, z = loop_open(up, lo)
        sp, zp, ph = path_A(s)
        secs.append(place_section(x, z, sp, zp, ph, side))
    return build_loft("X8_Elevon_" + ("Der" if side > 0 else "Izq"), secs, mat=mat,
                      smooth_angle=40)


# ----------------------------------------------------------------------------------------
# Motor y helice (empujadora)
# ----------------------------------------------------------------------------------------
def add_cylinder(name, r, depth, loc, mat, verts=None, rot=(math.pi / 2, 0, 0)):
    verts = verts or RES["cyl"]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc,
                                        rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    shade(o, 40)
    return o


def make_prop_blade(name, mat, sign=1.0):
    """Pala plegable 12x8 desplegada: perfil de fondo plano con paso geometrico real."""
    R = P["prop_d"] / 2
    r_hub = 19.0
    rs = np.linspace(r_hub, R, RES["blade"][0])
    chord = np.interp(rs / R, [0.12, 0.25, 0.45, 0.7, 0.9, 1.0], [14, 21, 23, 19, 13, 6])
    tcs = np.interp(rs / R, [0.12, 0.4, 1.0], [0.22, 0.11, 0.08])
    g = cosine_spacing(RES["blade"][1])
    secs = []
    for r, c, tc in zip(rs, chord, tcs):
        beta = RES["prop_pitch_sign"] * math.atan(P["prop_pitch"] / (2 * math.pi * r))
        zu = 5 * tc * (0.2969 * np.sqrt(g) - 0.126 * g - 0.3516 * g**2 + 0.2843 * g**3 - 0.1015 * g**4)
        zu = zu + 0.03 * g * (1 - g)
        zl = -0.15 * zu
        xu = (g - 0.35) * c
        X = np.concatenate([xu[::-1], xu[1:]])
        Z = np.concatenate([(zu * c)[::-1], (zl * c)[1:]])
        cb, sb = math.cos(beta), math.sin(beta)
        pts = []
        for x, z in zip(X, Z):
            # eje y: radial; la cuerda gira beta respecto al plano de rotacion (x-z local)
            tang = x * cb - z * sb
            axial = x * sb + z * cb
            pts.append(Vector((tang * MM * sign, r * MM, axial * MM)))
        secs.append(pts)
    return build_loft(name, secs, mat=mat, smooth_angle=50)


def make_powertrain(mats):
    x_mount = 796.0
    zc = float(ZFT(x_mount) + ZFB(x_mount)) / 2
    objs = []
    y0 = (x_mount - P["x_cg"]) * MM
    # soporte 0,3 mm detras del borde de salida del fuselaje; base del motor 0,5 mm antes de
    # la campana que gira (sin caras coplanares entre piezas fijas y giratorias)
    objs.append(add_cylinder("X8_Soporte_Motor", 24 * MM, 4 * MM, (0, y0 + 2.3 * MM, zc * MM),
                             mats["motor"]))
    objs.append(add_cylinder("X8_Motor_Estator", P["motor_d"] / 2 * MM, 11.2 * MM,
                             (0, y0 + 9.9 * MM, zc * MM), mats["motor"]))
    objs.append(add_cylinder("X8_Motor_Campana", P["motor_d"] / 2 * MM, (P["motor_len"] - 12) * MM,
                             (0, y0 + (16 + (P["motor_len"] - 12) / 2) * MM, zc * MM),
                             mats["motor_bell"]))
    y_hub = y0 + (P["motor_len"] + 10) * MM
    objs.append(add_cylinder("X8_Eje", 4 * MM, 14 * MM, (0, y_hub - 6 * MM, zc * MM),
                             mats["metal"], verts=max(12, RES["cyl"] // 2)))
    objs.append(add_cylinder("X8_Buje_Helice", 16 * MM, 9 * MM, (0, y_hub, zc * MM),
                             mats["prop"]))
    bpy.ops.mesh.primitive_cone_add(vertices=RES["cyl"], radius1=15 * MM, radius2=3 * MM, depth=24 * MM,
                                    location=(0, y_hub + 16 * MM, zc * MM),
                                    rotation=(-math.pi / 2, 0, 0))
    sp = bpy.context.active_object
    sp.name = "X8_Cono_Helice"
    sp.data.materials.append(mats["prop"])
    shade(sp, 40)
    objs.append(sp)
    # palas: el plano de giro es X-Z (perpendicular al eje Y del avion)
    for k, ang in enumerate((math.radians(55), math.radians(235))):
        b = make_prop_blade(f"X8_Pala_{k + 1}", mats["prop"])
        b.rotation_euler = (0, 0, 0)
        # la pala se construye con el radio en +Y local; se gira para que el radio quede en Z
        b.matrix_world = (Matrix.Translation((0, y_hub, zc * MM))
                          @ Matrix.Rotation(ang, 4, "Y")
                          @ Matrix.Rotation(math.pi / 2, 4, "X"))
        objs.append(b)
    return objs


# ----------------------------------------------------------------------------------------
# Detalles proyectados sobre la superficie (tapa, orificio, servos, cuernos, varillas)
# ----------------------------------------------------------------------------------------
def bvh_of(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    return [(o, BVHTree.FromObject(o, dg)) for o in objs]


def raycast(trees, origin, direction):
    best = None
    for o, t in trees:
        mw = o.matrix_world
        inv = mw.inverted()
        lo = inv @ origin
        ld = (inv.to_3x3() @ direction).normalized()
        hit = t.ray_cast(lo, ld)
        if hit[0] is not None:
            p = mw @ hit[0]
            n = (mw.to_3x3() @ hit[1]).normalized()
            d = (p - origin).length
            if best is None or d < best[2]:
                best = (p, n, d)
    return best


def seam_curve(name, pts_xs, trees, mat, from_top=True, radius=0.55):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius * MM
    cu.bevel_resolution = 2
    spl = cu.splines.new("POLY")
    pts = []
    dense = []
    for (xa, sa), (xb, sb) in zip(pts_xs, pts_xs[1:] + pts_xs[:1]):
        n = max(1, int(math.hypot(xb - xa, sb - sa) / 4.0))
        dense += [(xa + (xb - xa) * t / n, sa + (sb - sa) * t / n) for t in range(n)]
    for x, s in dense:
        o = to_blender(x, s, 300 if from_top else -300)
        hit = raycast(trees, o, Vector((0, 0, -1 if from_top else 1)))
        if hit:
            pts.append(hit[0] + hit[1] * 0.05 * MM)
    spl.points.add(len(pts) - 1)
    for p_, v in zip(spl.points, pts):
        p_.co = (v.x, v.y, v.z, 1)
    spl.use_cyclic_u = True
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def rounded_rect(x0, x1, w0, w1, r, n=10):
    """Rectangulo redondeado en (x, s), con semiancho w0 adelante y w1 atras."""
    def w(x):
        return w0 + (w1 - w0) * (x - x0) / (x1 - x0)
    pts = []
    corners = [(x0 + r, w(x0 + r) - r, math.pi), (x1 - r, w(x1 - r) - r, math.pi / 2),
               (x1 - r, -(w(x1 - r) - r), 0.0), (x0 + r, -(w(x0 + r) - r), -math.pi / 2)]
    for cx, cs, a0 in corners:
        for t in np.linspace(0, math.pi / 2, n):
            a = a0 - t
            pts.append((cx + r * math.cos(a), cs + r * math.sin(a)))
    return pts


def place_on_surface(obj, trees, x, s, from_top=True, lift=0.0):
    o = to_blender(x, s, 300 if from_top else -300)
    hit = raycast(trees, o, Vector((0, 0, -1 if from_top else 1)))
    if not hit:
        return None
    p, n, _ = hit
    obj.location = p + n * lift * MM
    obj.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
    return hit


def make_details(body, wings_main, elevons, mats):
    trees = bvh_of([body])
    objs = []
    # Ventana de camara FPV en la nariz
    o = to_blender(-50, 0, 6)
    hit = raycast(trees, o, Vector((0, 1, 0)))
    if hit:
        bpy.ops.mesh.primitive_cube_add(size=1)
        cam = bpy.context.active_object
        cam.name = "X8_Ventana_Camara"
        cam.scale = (26 * MM / 2, 1.0 * MM, 18 * MM / 2)
        cam.location = hit[0] + hit[1] * 0.2 * MM
        cam.rotation_euler = hit[1].to_track_quat("-Y", "Z").to_euler()
        bpy.ops.object.transform_apply(scale=True)
        bev = cam.modifiers.new("Bisel", "BEVEL")
        bev.width = 4 * MM
        bev.segments = 4
        cam.data.materials.append(mats["glass"])
        objs.append(cam)
    return objs


# ----------------------------------------------------------------------------------------
# Mecanica de mando: bisagras, servos, brazos, varillas y cuernos
# ----------------------------------------------------------------------------------------
# Convencion de signos (igual en ambas alas):
#   delta (deflexion del elevon) > 0  = borde de salida hacia ABAJO
#   theta (giro del brazo del servo) > 0 = la punta del brazo se mueve hacia ATRAS
#   Con la geometria elegida, theta > 0 empuja el cuerno hacia atras y SUBE el borde de salida.
# Marco de bisagra: X a lo largo del eje, Y hacia atras (perpendicular al eje), Z hacia arriba.
# Un giro positivo alrededor de X sube el borde de salida en las dos alas.

SIDE_NAME = {1: "Der", -1: "Izq"}       # side = +1: ala derecha del piloto (X negativo en Blender)
SERVO_ES3054 = dict(                     # Emax ES3054, 17 g (dimensiones del fabricante)
    L=28.45, W=13.0, H=31.1, torque_kgcm_6v=3.5, torque_kgcm_48v=3.0, speed_s60_6v=0.13,
)


_HINGE_CACHE = {}


def hinge_frame(side):
    """Matriz 4x4 del eje de bisagra (origen en el extremo interior).

    El extrados a lo largo de la bisagra no es una recta perfecta (diedro con entrada suave,
    torsion y espesor variable). El eje se toma como la recta de apoyo inferior de ese
    extrados: toca la superficie en dos puntos y queda por debajo (dentro del material) en el
    resto, a menos de 2 mm. Asi el elevon gira como solido rigido sin morder el ala.
    """
    if side in _HINGE_CACHE:
        return _HINGE_CACHE[side]
    ss = np.linspace(P["elev_s0"], P["elev_s1"], 61)
    pts = [surface_point_world(float(v), hinge_x(float(v)), side, upper=True) for v in ss]
    a0, a1 = pts[0], pts[-1]
    up = Vector((0, 0, 1))
    Xa = (a1 - a0).normalized()
    Za = (up - up.dot(Xa) * Xa).normalized()
    t = (ss - ss[0]) / (ss[-1] - ss[0])
    dev = np.array([(p_ - (a0 + float(tt) * (a1 - a0))).dot(Za) for p_, tt in zip(pts, t)])
    best = None
    for i in range(len(ss)):
        for j in range(i + 1, len(ss)):
            line = dev[i] + (dev[j] - dev[i]) * (t - t[i]) / (t[j] - t[i])
            if np.all(line <= dev + 1e-9):
                gap = float(np.sum(dev - line))
                if best is None or gap < best[0]:
                    best = (gap, line)
    line = best[1]
    h0 = a0 + float(line[0]) * Za
    h1 = a1 + float(line[-1]) * Za
    X = (h1 - h0).normalized()
    up = Vector((0, 0, 1))
    Z = (up - up.dot(X) * X).normalized()
    Y = Z.cross(X)
    if Y.y < 0:                          # que Y apunte hacia atras (+Y de Blender) en ambas alas
        X = -X
        Y = Z.cross(X)
    M = Matrix((X, Y, Z)).transposed().to_4x4()
    M.translation = h0
    _HINGE_CACHE[side] = (M, h0, h1, float(np.max(dev - line)))
    return _HINGE_CACHE[side]


def link_geometry(side):
    """Geometria del cuadrilatero articulado servo-varilla-cuerno en la estacion link_s."""
    M, h0, h1, _ = hinge_frame(side)
    t = (P["link_s"] - P["elev_s0"]) / (P["elev_s1"] - P["elev_s0"])
    H = h0 + t * (h1 - h0)
    t_h = thickness_at(P["link_s"], hinge_x(P["link_s"]))
    r_h = t_h + P["horn_drop"]
    r_s = P["arm_r"]
    D = P["servo_dist"]
    R3 = M.to_3x3()
    X, Y, Z = R3.col[0], R3.col[1], R3.col[2]
    O_s = H - D * MM * Y + (r_s - r_h) * MM * Z
    return dict(M=M, H=H, X=X, Y=Y, Z=Z, t_h=t_h, r_h=r_h, r_s=r_s, D=D, O_s=O_s,
                L=D, inboard=side)


def linkage_delta(theta, r_s, r_h, D):
    """Deflexion exacta del elevon (rad, + = abajo) para un giro de brazo theta (rad).

    Brazo: A = Os + r_s (sin t, -cos t); cuerno: B = H + r_h (-sin d, -cos d); |A - B| = D.
    En neutro el brazo y el cuerno apuntan hacia abajo y la varilla queda horizontal.
    """
    ay = -D + r_s * math.sin(theta)
    az = (r_s - r_h) - r_s * math.cos(theta)
    k = (D * D - ay * ay - az * az - r_h * r_h) / (2 * r_h)
    return math.atan2(ay, az) + math.acos(max(-1.0, min(1.0, k / math.hypot(ay, az))))


def mesh_from_polys(name, verts, faces, mat=None, smooth=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if mat:
        obj.data.materials.append(mat)
    if smooth:
        shade(obj, smooth)
    return obj


def box_verts(x0, x1, y0, y1, z0, z1):
    v = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return v, f


def extrude_profile(pts_yz, x0, x1):
    """Placa: poligono en el plano Y-Z extruido entre x0 y x1 (mm)."""
    n = len(pts_yz)
    verts = [(x0, y, z) for y, z in pts_yz] + [(x1, y, z) for y, z in pts_yz]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return verts, faces


def scaled(verts, side_mirror=1):
    return [Vector((side_mirror * x * MM, y * MM, z * MM)) for x, y, z in verts]


def capsule_profile(r1, r2, length, n=14):
    """Contorno de un brazo de servo: circulo r1 en (0,0) y circulo r2 en (0,-length)."""
    pts = []
    for a in np.linspace(0, math.pi, n):                       # mitad superior del cubo
        pts.append((r1 * math.cos(a), r1 * math.sin(a)))
    for a in np.linspace(math.pi, 2 * math.pi, n):             # mitad inferior de la punta
        pts.append((r2 * math.cos(a), -length + r2 * math.sin(a)))
    return pts


def make_hinge_tape(name, trees, M, side, y0, y1, mat, ns=None, ny=5):
    """Cinta de bisagra proyectada sobre el extrados entre y0 y y1 (mm, marco de bisagra)."""
    R3 = M.to_3x3()
    Y, Z = R3.col[1], R3.col[2]
    _, h0, h1, _ = hinge_frame(side)
    verts, rows = [], []
    for s in np.linspace(P["elev_s0"] - 1.0, P["elev_s1"] + 1.0, ns or RES["tape"]):
        t = float((s - P["elev_s0"]) / (P["elev_s1"] - P["elev_s0"]))
        base = h0 + t * (h1 - h0)
        row = []
        for y in (float(v) for v in np.linspace(y0, y1, ny)):
            o = base + y * MM * Y + 0.05 * Z
            hit = raycast(trees, o, -Z)
            p = hit[0] + hit[1] * 0.25 * MM if hit else base + y * MM * Y
            row.append(len(verts))
            verts.append(p)
        rows.append(row)
    faces = []
    for a, b in zip(rows[:-1], rows[1:]):
        for j in range(ny - 1):
            faces.append((a[j], a[j + 1], b[j + 1], b[j]))
    obj = mesh_from_polys(name, verts, faces, mat)
    sol = obj.modifiers.new("Espesor", "SOLIDIFY")
    sol.thickness = 0.18 * MM
    sol.offset = 1.0
    shade(obj, 30)
    return obj


def make_mechanism(side, wing, elevon, mats):
    """Bisagra, servo ES3054, brazo, varilla con Z y horquilla, cuerno y bahia del servo."""
    nm = SIDE_NAME[side]
    g = link_geometry(side)
    M = g["M"]
    Minv = M.inverted()
    objs = []

    # 1) Eje de bisagra: vacio con el marco; el elevon pasa a ser su hijo (gira sobre X local)
    hinge = bpy.data.objects.new(f"X8_Eje_Bisagra_{nm}", None)
    hinge.empty_display_type = "SINGLE_ARROW"
    hinge.empty_display_size = 0.08
    bpy.context.scene.collection.objects.link(hinge)
    hinge.matrix_world = M
    hinge.parent = wing
    hinge.matrix_parent_inverse = wing.matrix_world.inverted()
    elevon.data.transform(Minv @ elevon.matrix_world)
    elevon.matrix_world = Matrix.Identity(4)
    elevon.parent = hinge
    elevon.matrix_parent_inverse = Matrix.Identity(4)
    elevon.matrix_basis = Matrix.Identity(4)
    elevon.rotation_mode = "XYZ"
    objs.append(hinge)

    # 2) Cinta de bisagra: mitad fija sobre el ala y mitad movil sobre el elevon
    tw = P["tape_w"] / 2
    t_fix = make_hinge_tape(f"X8_Cinta_Bisagra_Ala_{nm}", bvh_of([wing]), M, side, -tw, 0.0,
                            mats["tape"])
    t_fix.parent = wing
    t_mov = make_hinge_tape(f"X8_Cinta_Bisagra_Elevon_{nm}", bvh_of([elevon]), M, side, 0.0, tw,
                            mats["tape"])
    t_mov.data.transform(Minv)
    t_mov.parent = elevon
    t_mov.matrix_parent_inverse = Matrix.Identity(4)
    objs += [t_fix, t_mov]

    # 3) Cuerno de nailon en el intrados del elevon, en el plano del varillaje
    tree_e = bvh_of([elevon])
    def zb(y):                                 # intrados del elevon (mm) a y mm detras del eje
        hit = raycast(tree_e, g["H"] + y * MM * g["Y"] - 0.1 * g["Z"], g["Z"])
        return ((hit[0] - g["H"]).dot(g["Z"]) / MM) if hit else -g["t_h"]
    r_h = g["r_h"]
    lobe = [(4.6 * math.cos(a), -r_h + 4.6 * math.sin(a))
            for a in np.linspace(math.radians(15), math.radians(-200), 16)]
    prof = [(2.0, zb(2.0) + 1.5), (21.0, zb(21.0) + 1.5), (21.0, zb(21.0) - 1.0)] + lobe
    hv, hf = extrude_profile(prof, -0.8, 0.8)
    horn = mesh_from_polys(f"X8_Cuerno_{nm}", [
        g["H"] + x * MM * g["X"] + y * MM * g["Y"] + z * MM * g["Z"] for x, y, z in hv], hf,
        mats["horn"], 30)
    horn.data.transform(Minv)
    horn.parent = elevon
    horn.matrix_parent_inverse = Matrix.Identity(4)
    hole_h = bpy.data.objects.new(f"X8_Agujero_Cuerno_{nm}", None)
    hole_h.empty_display_type = "SPHERE"
    hole_h.empty_display_size = 0.002
    bpy.context.scene.collection.objects.link(hole_h)
    hole_h.parent = elevon
    hole_h.location = Minv @ (g["H"] - r_h * MM * g["Z"])
    objs += [horn, hole_h]

    # 4) Servo: marco en el eje de salida, cuerpo hacia el interior del ala
    sm = side                                   # +x canonico = hacia el encastre
    frame = M.copy()
    frame.translation = g["O_s"]
    sframe = bpy.data.objects.new(f"X8_Eje_Servo_{nm}", None)
    sframe.empty_display_type = "CIRCLE"
    sframe.empty_display_size = 0.006
    bpy.context.scene.collection.objects.link(sframe)
    sframe.matrix_world = frame
    sframe.parent = wing
    sframe.matrix_parent_inverse = wing.matrix_world.inverted()
    S = SERVO_ES3054
    parts_v, parts_f = [], []
    def add_box(*lim):
        v, f = box_verts(*lim)
        o = len(parts_v)
        parts_v.extend(v)
        parts_f.extend([tuple(i + o for i in ff) for ff in f])
    add_box(3.0, 3.0 + S["H"] - 4.0, -(S["L"] - 7.5), 7.5, -S["W"] / 2, S["W"] / 2)   # caja
    add_box(8.0, 10.0, -(S["L"] - 7.5) - 5.0, 7.5 + 5.0, -S["W"] / 2, S["W"] / 2)       # orejas
    add_box(1.2, 3.0, -5.5, 5.5, -5.5, 5.5)                                             # buje
    servo = mesh_from_polys(f"X8_Servo_ES3054_{nm}", scaled(parts_v, sm), parts_f,
                            mats["servo_case"])
    servo.parent = sframe
    servo.matrix_parent_inverse = Matrix.Identity(4)
    objs += [sframe, servo]

    # 5) Brazo del servo (gira con theta alrededor de X local del marco del servo)
    arm_len = g["r_s"] + 3.0
    av, af = extrude_profile(capsule_profile(4.2, 2.6, arm_len), -1.0, 1.0)
    arm = mesh_from_polys(f"X8_Brazo_Servo_{nm}", scaled(av), af, mats["horn_white"], 30)
    arm.parent = sframe
    arm.matrix_parent_inverse = Matrix.Identity(4)
    arm.rotation_mode = "XYZ"
    hole_a = bpy.data.objects.new(f"X8_Agujero_Brazo_{nm}", None)
    hole_a.empty_display_type = "SPHERE"
    hole_a.empty_display_size = 0.002
    bpy.context.scene.collection.objects.link(hole_a)
    hole_a.parent = arm
    hole_a.location = (0, 0, -g["r_s"] * MM)
    objs += [arm, hole_a]

    # 6) Varilla de acero: sigue al agujero del brazo y apunta al agujero del cuerno
    rd = P["pushrod_d"] / 2
    rv, rf = [], []
    def add_cyl(axis, c0, c1, r, n=12):
        o = len(rv)
        for c in (c0, c1):
            for a in np.linspace(0, 2 * math.pi, n, endpoint=False):
                u, w = r * math.cos(a), r * math.sin(a)
                rv.append((c, u, w) if axis == "x" else (u, c, w))
        rf.extend([(o + i, o + (i + 1) % n, o + n + (i + 1) % n, o + n + i) for i in range(n)])
        rf.append(tuple(o + i for i in range(n)))
        rf.append(tuple(o + n + i for i in range(n - 1, -1, -1)))
    add_cyl("y", 0.0, g["L"], rd)                       # varilla
    add_cyl("x", -2.5, 2.5, rd)                         # doblez en Z que atraviesa el brazo
    clev_v, clev_f = box_verts(-2.2, 2.2, g["L"] - 9.0, g["L"] + 2.5, -1.6, 1.6)
    o = len(rv)
    rv.extend(clev_v)
    rf.extend([tuple(i + o for i in ff) for ff in clev_f])  # horquilla (clevis) en el cuerno
    rod = mesh_from_polys(f"X8_Varilla_{nm}", scaled(rv), rf, mats["metal"], 40)
    rod.matrix_world = Matrix.LocRotScale(hole_a.matrix_world.translation, M.to_quaternion(), None)
    c1 = rod.constraints.new("COPY_LOCATION")
    c1.target = hole_a
    c2 = rod.constraints.new("DAMPED_TRACK")
    c2.target = hole_h
    c2.track_axis = "TRACK_Y"
    objs.append(rod)

    # 7) Bahia del servo: hueco booleano en el intrados (servo y barrido del brazo)
    cv, cf = box_verts(-4.0, 3.0 + S["H"] - 3.0, -(S["L"] - 7.5) - 6.5, 18.0, -60.0,
                       S["W"] / 2 + 1.0)
    cutter = mesh_from_polys(f"X8_Hueco_Bahia_{nm}", scaled(cv, sm), cf)
    cutter.matrix_world = frame            # sin padre: evita el ciclo ala -> hueco -> ala
    cutter.display_type = "WIRE"
    cutter.hide_render = True
    cutter.hide_set(True)
    mod = wing.modifiers.new("Bahia_Servo", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    try:
        mod.solver = "EXACT"
    except Exception:
        pass
    objs.append(cutter)

    for o_ in objs:
        o_["mecanica"] = True
    return dict(side=side, name=nm, g=g, hinge=hinge, elevon=elevon, arm=arm, servo=servo,
                hole_a=hole_a, hole_h=hole_h, rod=rod, horn=horn, objs=objs)


# ----------------------------------------------------------------------------------------
# Logica de mando: palancas -> expo y dual rate -> mezcla de elevones -> PWM -> servo ->
# varillaje -> deflexion. Todo con drivers de expresion simple (no requiere Auto Run).
# ----------------------------------------------------------------------------------------
LOGIC_DEFAULTS = dict(
    profundidad=0.0,          # palanca de profundidad, -1..1 (+ = tirar, nariz arriba)
    alabeo=0.0,               # palanca de alabeo, -1..1 (+ = derecha)
    expo=0.25,                # exponencial (0 = lineal)
    mezcla_profundidad=0.70,  # porcentaje de profundidad en la mezcla (dual rate)
    mezcla_alabeo=0.85,       # porcentaje de alabeo en la mezcla (dual rate)
    invertir_izq=1,           # inversion del canal: con servos en espejo, uno va invertido
    invertir_der=0,
    subtrim_izq_us=0.0,
    subtrim_der_us=0.0,
    extremo_izq_pct=100.0,    # recorrido maximo (end point)
    extremo_der_pct=100.0,
)


def add_prop(obj, name, value, lo=None, hi=None, desc=""):
    obj[name] = value
    try:
        ui = obj.id_properties_ui(name)
        kw = {"description": desc}
        if lo is not None:
            kw.update(min=lo, soft_min=lo)
        if hi is not None:
            kw.update(max=hi, soft_max=hi)
        ui.update(**kw)
    except Exception:
        pass


def add_driver(obj, path, expr, variables, index=-1):
    fc = obj.driver_add(path, index) if index >= 0 else obj.driver_add(path)
    drv = fc.driver
    drv.type = "SCRIPTED"
    for vname, tgt, dpath in variables:
        v = drv.variables.new()
        v.name = vname
        v.type = "SINGLE_PROP"
        v.targets[0].id_type = "OBJECT"
        v.targets[0].id = tgt
        v.targets[0].data_path = dpath
    drv.expression = expr
    return drv


def mix_expr(side):
    """Mezcla de elevones en espacio de deflexion (+ = borde de salida abajo).

    Alabeo a la derecha: elevon derecho sube, izquierdo baja. Profundidad arriba: ambos suben.
    """
    curve_p = "mp*((1-e)*P + e*P*P*P)"
    curve_r = "mr*((1-e)*R + e*R*R*R)"
    sgn = "" if side == -1 else "-"
    return f"clamp({sgn}{curve_r} - {curve_p}, -1, 1)"


def make_logic(mechs, mats):
    objs = []
    rc = bpy.data.objects.new("X8_Mando_RC", None)
    rc.empty_display_type = "CUBE"
    rc.empty_display_size = 0.02
    bpy.context.scene.collection.objects.link(rc)
    rc.location = (1.35, -0.55, -0.12)
    desc = dict(
        profundidad="Palanca de profundidad (-1..1). + = tirar, nariz arriba",
        alabeo="Palanca de alabeo (-1..1). + = derecha",
        expo="Exponencial de las dos palancas (0 = lineal)",
        mezcla_profundidad="Fraccion de profundidad en la mezcla de elevones",
        mezcla_alabeo="Fraccion de alabeo en la mezcla de elevones",
        invertir_izq="Inversion del canal del elevon izquierdo (0/1)",
        invertir_der="Inversion del canal del elevon derecho (0/1)",
        subtrim_izq_us="Subtrim del servo izquierdo (us)",
        subtrim_der_us="Subtrim del servo derecho (us)",
        extremo_izq_pct="Recorrido maximo del servo izquierdo (%)",
        extremo_der_pct="Recorrido maximo del servo derecho (%)",
    )
    rng = dict(profundidad=(-1, 1), alabeo=(-1, 1), expo=(0, 1), mezcla_profundidad=(0, 1),
               mezcla_alabeo=(0, 1), invertir_izq=(0, 1), invertir_der=(0, 1),
               subtrim_izq_us=(-100, 100), subtrim_der_us=(-100, 100),
               extremo_izq_pct=(0, 125), extremo_der_pct=(0, 125))
    for k, v in LOGIC_DEFAULTS.items():
        add_prop(rc, k, v, *rng[k], desc[k])
    objs.append(rc)

    mixer = bpy.data.objects.new("X8_Mezclador", None)
    mixer.empty_display_type = "PLAIN_AXES"
    mixer.empty_display_size = 0.01
    bpy.context.scene.collection.objects.link(mixer)
    mixer.location = (1.35, -0.45, -0.12)
    objs.append(mixer)
    base_vars = [("P", rc, '["profundidad"]'), ("R", rc, '["alabeo"]'), ("e", rc, '["expo"]'),
                 ("mp", rc, '["mezcla_profundidad"]'), ("mr", rc, '["mezcla_alabeo"]')]
    simple = []
    for m in mechs:
        side = m["side"]
        key = "izq" if side == -1 else "der"
        add_prop(mixer, f"elevon_{key}", 0.0, -1, 1, "Salida de la mezcla (+ = borde de salida abajo)")
        add_prop(mixer, f"pwm_{key}_us", 1500.0, 900, 2100, "Pulso enviado al servo (us)")
        d = add_driver(mixer, f'["elevon_{key}"]', mix_expr(side), base_vars)
        simple.append(d.is_simple_expression)
        pv = base_vars + [("inv", rc, f'["invertir_{key}"]'), ("st", rc, f'["subtrim_{key}_us"]'),
                          ("ep", rc, f'["extremo_{key}_pct"]')]
        d = add_driver(mixer, f'["pwm_{key}_us"]',
                       f"1500 + st + 5*ep*{mix_expr(side)}*(1 - 2*inv)", pv)
        simple.append(d.is_simple_expression)

        # Servo: el pulso sube -> el eje gira antihorario mirando la cara de salida (ES3054).
        # Los ejes miran hacia afuera en las dos alas, asi que el mismo pulso gira el brazo en
        # sentidos opuestos: izquierdo theta = +antihorario, derecho theta = -antihorario.
        g = m["g"]
        sv = m["servo"]
        add_prop(sv, "angulo_eje_deg", 0.0, -60, 60, "Giro antihorario del eje visto desde la cara de salida")
        add_prop(sv, "theta_brazo_deg", 0.0, -60, 60, "Giro del brazo (+ = punta hacia atras)")
        add_prop(sv, "r_brazo_mm", round(g["r_s"], 3), desc="Radio del agujero usado en el brazo")
        add_prop(sv, "r_cuerno_mm", round(g["r_h"], 3), desc="Eje de bisagra -> agujero del cuerno")
        add_prop(sv, "largo_varilla_mm", round(g["L"], 3), desc="Largo de la varilla")
        thr = P["servo_throw"]
        pw = [("pwm", mixer, f'["pwm_{key}_us"]')]
        sgn = 1.0 if side == -1 else -1.0
        d = add_driver(sv, '["angulo_eje_deg"]', f"(pwm - 1500)/500*{thr}", pw)
        simple.append(d.is_simple_expression)
        d = add_driver(sv, '["theta_brazo_deg"]', f"{sgn}*(pwm - 1500)/500*{thr}", pw)
        simple.append(d.is_simple_expression)
        # Varillaje en dos pasos (Blender limita cada expresion a 256 caracteres):
        #   agujero del brazo (ay, az) respecto del eje de bisagra -> deflexion exacta
        ha, hg = m["hole_a"], m["hinge"]
        rs, rh, D = g["r_s"], g["r_h"], g["D"]
        add_prop(ha, "ay_mm", -D, desc="Agujero del brazo: coordenada hacia atras desde la bisagra")
        add_prop(ha, "az_mm", -rh, desc="Agujero del brazo: coordenada vertical desde la bisagra")
        th = [("th", sv, '["theta_brazo_deg"]')]
        d = add_driver(ha, '["ay_mm"]', f"-{D:.4f} + {rs:.4f}*sin(radians(th))", th)
        simple.append(d.is_simple_expression)
        d = add_driver(ha, '["az_mm"]', f"{rs - rh:.4f} - {rs:.4f}*cos(radians(th))", th)
        simple.append(d.is_simple_expression)
        add_prop(hg, "deflexion_deg", 0.0, -40, 40, "Deflexion del elevon (+ = borde de salida abajo)")
        yz = [("ay", ha, '["ay_mm"]'), ("az", ha, '["az_mm"]')]
        d = add_driver(hg, '["deflexion_deg"]',
                       f"degrees(atan2(ay, az) + acos(clamp(({D * D:.4f} - ay*ay - az*az - "
                       f"{rh * rh:.4f})/{2 * rh:.4f}/sqrt(ay*ay + az*az), -1, 1)))", yz)
        simple.append(d.is_simple_expression)
        # Transformaciones: brazo y elevon
        d = add_driver(m["arm"], "rotation_euler", "radians(th)", th, index=0)
        simple.append(d.is_simple_expression)
        d = add_driver(m["elevon"], "rotation_euler", "-radians(dl)",
                       [("dl", hg, '["deflexion_deg"]')], index=0)
        simple.append(d.is_simple_expression)

    # Palanca visual (gimbal) que repite la entrada de la emisora
    bv, bf = box_verts(-30, 30, -30, 30, -10, 0)
    base = mesh_from_polys("X8_Palanca_Base", scaled(bv), bf, mats["servo_case"])
    base.parent = rc
    stick_v, stick_f = [], []
    n = 16
    for zc in (0.0, 70.0):
        for a in np.linspace(0, 2 * math.pi, n, endpoint=False):
            stick_v.append((2.5 * math.cos(a), 2.5 * math.sin(a), zc))
    stick_f = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    stick_f += [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    stick = mesh_from_polys("X8_Palanca", scaled(stick_v), stick_f, mats["metal"], 40)
    stick.parent = rc
    stick.rotation_mode = "XYZ"
    d = add_driver(stick, "rotation_euler", "-radians(25*P)", [("P", rc, '["profundidad"]')], 0)
    simple.append(d.is_simple_expression)
    d = add_driver(stick, "rotation_euler", "-radians(25*R)", [("R", rc, '["alabeo"]')], 1)
    simple.append(d.is_simple_expression)
    objs += [base, stick]
    return dict(rc=rc, mixer=mixer, objs=objs, simple=all(simple))


def animate_inputs(rc, fps=24):
    """Secuencia de prueba: profundidad, alabeo y combinaciones (con saturacion)."""
    seq = [(1, 0, 0), (24, 1, 0), (48, -1, 0), (72, 0, 0), (96, 0, 1), (120, 0, -1), (144, 0, 0),
           (168, 1, 1), (192, -1, -1), (216, 0, 0), (240, 0, 0)]
    for f, p, r in seq:
        rc["profundidad"] = float(p)
        rc["alabeo"] = float(r)
        rc.keyframe_insert('["profundidad"]', frame=f)
        rc.keyframe_insert('["alabeo"]', frame=f)
    rc["profundidad"] = 0.0
    rc["alabeo"] = 0.0
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, 240
    sc.render.fps = fps
    sc.frame_set(1)


def elevon_area():
    s = np.linspace(P["elev_s0"], P["elev_s1"], 400)
    c = TE(s) - np.array([hinge_x(v) for v in s])
    trap = np.trapezoid if hasattr(np, "trapezoid") else np.trapz
    S = trap(c, s)
    return S * 1e-6, float(S / (s[-1] - s[0])) * 1e-3


PANEL_CODE = '''"""Panel "X8" en la barra lateral del visor 3D (tecla N): palancas, ajustes y salidas."""
import bpy


class X8_OT_animacion_prueba(bpy.types.Operator):
    """Crea o borra la animacion de prueba de las palancas (fotogramas 1-240)"""
    bl_idname = "x8.animacion_prueba"
    bl_label = "Animacion de prueba"
    accion: bpy.props.StringProperty(default="borrar")

    def execute(self, context):
        rc = bpy.data.objects.get("X8_Mando_RC")
        if rc is None:
            return {"CANCELLED"}
        rc.animation_data_clear()
        if self.accion == "crear":
            seq = [(1, 0, 0), (24, 1, 0), (48, -1, 0), (72, 0, 0), (96, 0, 1), (120, 0, -1),
                   (144, 0, 0), (168, 1, 1), (192, -1, -1), (216, 0, 0), (240, 0, 0)]
            for f, p, r in seq:
                rc["profundidad"], rc["alabeo"] = float(p), float(r)
                rc.keyframe_insert('["profundidad"]', frame=f)
                rc.keyframe_insert('["alabeo"]', frame=f)
        rc["profundidad"], rc["alabeo"] = 0.0, 0.0
        rc.update_tag()
        return {"FINISHED"}


class X8_PT_mandos(bpy.types.Panel):
    bl_label = "X8 - Mandos"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "X8"

    def draw(self, context):
        ob = bpy.data.objects
        rc, mx = ob.get("X8_Mando_RC"), ob.get("X8_Mezclador")
        lay = self.layout
        if rc is None or mx is None:
            lay.label(text="No hay rig de mandos en la escena")
            return
        col = lay.column(align=True)
        col.label(text="Palanca derecha")
        col.prop(rc, '["profundidad"]', slider=True, text="Profundidad (+ nariz arriba)")
        col.prop(rc, '["alabeo"]', slider=True, text="Alabeo (+ derecha)")
        anim = rc.animation_data is not None and rc.animation_data.action is not None
        row = lay.row(align=True)
        if anim:
            row.label(text="Animacion de prueba activa", icon="ACTION")
            op = row.operator("x8.animacion_prueba", text="Quitar")
            op.accion = "borrar"
        else:
            op = row.operator("x8.animacion_prueba", text="Crear animacion de prueba")
            op.accion = "crear"
        box = lay.box()
        box.label(text="Emisora / controlador")
        for k, t in (("expo", "Expo"), ("mezcla_profundidad", "Mezcla profundidad"),
                     ("mezcla_alabeo", "Mezcla alabeo"), ("invertir_izq", "Invertir izq"),
                     ("invertir_der", "Invertir der"), ("subtrim_izq_us", "Subtrim izq (us)"),
                     ("subtrim_der_us", "Subtrim der (us)"), ("extremo_izq_pct", "Extremo izq (%)"),
                     ("extremo_der_pct", "Extremo der (%)")):
            box.prop(rc, '["%s"]' % k, text=t)
        box = lay.box()
        box.label(text="Salidas (+ = borde de salida abajo)")
        for side in ("Izq", "Der"):
            key = side.lower()
            sv, hg = ob.get("X8_Servo_ES3054_" + side), ob.get("X8_Eje_Bisagra_" + side)
            if sv is None or hg is None:
                continue
            box.label(text="%s  mezcla %+.2f   PWM %4.0f us" % (side, mx["elevon_" + key],
                                                              mx["pwm_%s_us" % key]))
            box.label(text="      brazo %+5.1f deg   elevon %+5.1f deg" % (
                sv["theta_brazo_deg"], hg["deflexion_deg"]))


class X8_OT_prueba_tapas(bpy.types.Operator):
    """Quita o vuelve a poner la secuencia de prueba de tapas y logica (fotogramas 260-640)"""
    bl_idname = "x8.prueba_tapas"
    bl_label = "Secuencia de prueba de tapas"

    def execute(self, context):
        ctl = bpy.data.objects.get("X8_Logica_Tapas")
        act = bpy.data.actions.get("X8_Prueba_Tapas")
        if ctl is None:
            return {"CANCELLED"}
        if ctl.animation_data is None:
            ctl.animation_data_create()
        ctl.animation_data.action = None if ctl.animation_data.action else act
        ctl.update_tag()
        return {"FINISHED"}


class X8_PT_tapas(bpy.types.Panel):
    bl_label = "X8 - Tapas y logica"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "X8"

    def draw(self, context):
        ob = bpy.data.objects
        c, e, g = ob.get("X8_Logica_Tapas"), ob.get("X8_Estado"), ob.get("X8_Marcador_CG")
        lay = self.layout
        if c is None or e is None or g is None:
            lay.label(text="No hay logica de tapas en la escena")
            return
        anim = c.animation_data is not None and c.animation_data.action is not None
        row = lay.row(align=True)
        row.label(text="Prueba 260-640 activa" if anim else "Entradas a mano",
                  icon="ACTION" if anim else "HAND")
        row.operator("x8.prueba_tapas", text="Quitar" if anim else "Poner prueba")
        col = lay.column(align=True)
        col.label(text="Configuracion")
        col.prop(c, '["incluir_camara"]', text="Camara de mapeo")
        col.prop(c, '["incluir_paracaidas"]', text="Paracaidas")
        col.prop(c, '["bateria_x_mm"]', slider=True, text="Bateria (mm desde la nariz)")
        col = lay.column(align=True)
        col.label(text="Tapas")
        col.prop(c, '["desbloqueo_tapa"]', slider=True, text="Desbloqueo (cierre o pasador)")
        col.prop(c, '["abrir_tapa"]', slider=True, text="Abrir tapa")
        col.prop(c, '["tapas_servo_retiradas"]', slider=True, text="Tapas de servo fuera")
        col = lay.column(align=True)
        col.label(text="Vuelo")
        for k, t in (("armar", "Armar"), ("acelerador", "Acelerador"),
                     ("fase_mision", "Fase (3 = levantamiento)"), ("altitud_m", "Altura (m)"),
                     ("disparo_paracaidas", "Liberar paracaidas"),
                     ("frame_disparo", "Fotograma de la orden")):
            col.prop(c, '["%s"]' % k, text=t)
        box = lay.box()
        box.label(text="CG %.1f mm (430-440)  %s   masa %.0f g" % (
            g["cg_mm"], "OK" if g["cg_ok"] > 0.5 else "FUERA", g["masa_total_g"]))
        box.label(text="Tapa %s   armado %d   motor %d" % (
            "cerrada y bloqueada" if e["tapa_cerrada_bloqueada"] > 0.5 else "ABIERTA",
            e["armado"], e["motor"]))
        box.label(text="Compuertas %.0f%%   pestillo %4.0f us   compuertas %4.0f us" % (
            100 * e["compuerta_camara"], e["servo_pestillo_us"], e["servo_compuertas_us"]))
        if c["armar"] and not e["armado"]:
            why = []
            if e["tapa_cerrada_bloqueada"] < 0.5:
                why.append("tapa abierta o sin bloquear")
            if c["tapas_servo_retiradas"] > 0.5:
                why.append("faltan las tapas de servo")
            if g["cg_ok"] < 0.5:
                why.append("CG fuera de 430-440 mm")
            if e["bateria_cabe"] < 0.5:
                why.append("la bateria no cabe ahi")
            if e["paracaidas_liberado"] > 0.5:
                why.append("paracaidas liberado")
            for w in why:
                box.label(text="No arma: " + w, icon="ERROR")


CLASSES = (X8_OT_animacion_prueba, X8_PT_mandos, X8_OT_prueba_tapas, X8_PT_tapas)


def register():
    for c in CLASSES:
        try:
            bpy.utils.register_class(c)
        except ValueError:
            bpy.utils.unregister_class(c)
            bpy.utils.register_class(c)


def unregister():
    for c in reversed(CLASSES):
        bpy.utils.unregister_class(c)


if __name__ == "__main__":
    register()
'''


def install_panel():
    """Guarda el panel como texto del .blend (se registra al abrir si se permiten scripts)."""
    name = "x8_panel_mandos.py"
    txt = bpy.data.texts.get(name) or bpy.data.texts.new(name)
    txt.clear()
    txt.write(PANEL_CODE)
    txt.use_module = True
    if not bpy.app.background:
        exec(compile(PANEL_CODE, name, "exec"), {"__name__": "__main__"})
    return txt


# ----------------------------------------------------------------------------------------
# Volumenes internos, tapas y compuertas
# ----------------------------------------------------------------------------------------
# Kit de serie: bahia unica bajo una tapa superior grande que se sujeta con 6 imanes en
# placas de contrachapado, dos lenguetas delanteras y un cierre giratorio trasero (el
# agujero redondo de la tapa). Tapas de servo en el intrados de cada ala.
# Configuracion UAV opcional (un interruptor la activa): camara de mapeo con dos compuertas
# ventrales tipo bodega y paracaidas que se libera expulsando la tapa superior con un resorte
# cuando un servo de 9 g suelta el pestillo trasero.

BAY = dict(
    wall=8.0,                 # pared de EPO (mm)
    cav_s=150.0,              # semiancho de la bahia
    cav_x0=95.0, cav_x1=700.0,
    min_h=6.0,                # altura interior minima en los extremos
    hatch_x0=115.0, hatch_x1=520.0,
    kerf=1.0,                 # holgura de corte de la tapa
    tube_x=(480.0, 600.0),    # tubos de carbono pasantes (x desde la nariz)
    tube_d=8.0, tube_s=520.0,
    lock_x=470.0,             # cierre giratorio (el agujero redondo de las fotos)
    mag_d=8.0, mag_h=3.0,     # imanes N52 de 8x3 mm
    cam_door=(510.0, 570.0, 36.0),   # compuertas ventrales: x0, x1, semiancho
)

# Componentes: nombre, masa (g), medidas (x largo, s ancho, z alto, mm), centro (x, s),
# apoyo ("suelo" o "techo"), grupo ("serie" o "camara"/"paracaidas")
# Criterio de distribucion: la carga variable (camara) entre los tubos, cerca del CG, para que
# ponerla o quitarla mueva poco el CG; el paracaidas bajo la tapa, que es por donde sale; la
# bateria delante, como lastre ajustable.
LOCK = dict(cam_r=17.0, cam_dz=8.0, gap=1.0, ledge_t=3.0, ledge_w=24.0, ledge_l=14.0, slot=7.0,
            post_s=27.0)    # leva de 34 mm; repisas de s=7 a 31; postes en s=+-27 (fuera del FC)
DOOR_DEG = 110.0               # apertura maxima: a 110 grados dejan libre un cono de 80 grados
BAT_RANGE = (175.5, 338.5)     # recorrido del centro de la bateria (mm desde la nariz)
BAT_TRAY_T = 3.0               # bandeja de contrachapado de 3 mm
BAY_CHUTE_X0 = 326.0           # comienzo del paquete del paracaidas

COMPONENTS = [
    ("Bateria_6S_5000", 780, (155, 48, 50), (247, 0), "suelo", "serie"),
    ("Camara_FPV_VTX", 30, (22, 22, 24), (52, 0), "nariz", "serie"),
    ("Controlador_Vuelo", 30, (52, 36, 15), (455, 0), "suelo", "serie"),
    ("Receptor_Telemetria", 18, (40, 22, 10), (420, 55), "suelo", "serie"),
    ("GPS_Brujula", 30, (28, 28, 10), (640, 0), "techo", "serie"),
    ("ESC_60A", 60, (70, 30, 15), (662, 0), "suelo", "serie"),
    ("Camara_Mapeo", 240, (102, 58, 41), (539, 0), "suelo", "camara"),
    ("Paracaidas_Paquete", 150, (88, 80, 55), (370, 0), "suelo", "paracaidas"),
]
FIXED_MASSES = [   # masas que no ocupan la bahia: nombre, g, x, s, z (mm)
    ("Motor_4250_500KV", 190, 818, 0, 0),
    ("Helice_12x8_adaptador", 30, 846, 0, 0),
    ("Servo_Elevon_Der", 17, None, 515, None),
    ("Servo_Elevon_Izq", 17, None, -515, None),
    ("Cables_y_conectores", 60, 420, 0, 0),
]
AIRFRAME_MASS = 880.0     # kit vacio (manual de Skywalker)


def body_profile(s):
    """Extrados e intrados de la seccion central en la estacion s (x creciente, mm)."""
    s_abs = abs(s)
    le, te = float(LE(s_abs)), float(TE(s_abs))
    up, lo = section_2d(G, le, te, float(tc_of(s_abs)), P["camber"], float(twist_of(s_abs)),
                        with_pod_s=s_abs)
    return (np.asarray(up[0]), np.asarray(up[1]) + P["z0"],
            np.asarray(lo[0]), np.asarray(lo[1]) + P["z0"])


def ceiling_floor(x, s):
    """Techo y suelo interiores de la bahia (mm) en (x, s)."""
    xu, zu, xl, zl = body_profile(s)
    w = BAY["wall"]
    return float(np.interp(x, xu, zu)) - w, float(np.interp(x, xl, zl)) + w


def cavity_station(s, n=64):
    xu, zu, xl, zl = body_profile(s)
    w = BAY["wall"]
    xs = np.linspace(xu[0], xu[-1], 1500)
    h = np.interp(xs, xu, zu) - np.interp(xs, xl, zl) - 2 * w
    ok = xs[h >= BAY["min_h"]]
    xa = max(BAY["cav_x0"], float(ok[0]))
    xb = min(BAY["cav_x1"], float(ok[-1]))
    xx = xa + (xb - xa) * cosine_spacing(n)
    zt = np.interp(xx, xu, zu) - w
    zb = np.interp(xx, xl, zl) + w
    zt = np.maximum(zt, zb + 2.0)
    x = np.concatenate([xx[::-1], xx])
    z = np.concatenate([zt[::-1], zb])
    return x, z, xa, xb


def footprint_limits(x0, x1, s0, s1, n=7):
    """Suelo mas alto y techo mas bajo bajo una huella rectangular (mm): un equipo plano se
    apoya en los puntos altos del suelo curvo y no debe tocar el techo en sus esquinas."""
    fl, ce = -1e9, 1e9
    for x in np.linspace(x0, x1, n):
        for s in np.linspace(s0, s1, n):
            c, f = ceiling_floor(float(x), float(s))
            fl, ce = max(fl, f), min(ce, c)
    return fl, ce


def seat_z(cx, cs, lx, ls, lz, sup, gap=0.5):
    """Altura del centro de un equipo apoyado en el suelo o colgado del techo de la bahia."""
    fl, ce = footprint_limits(cx - lx / 2, cx + lx / 2, cs - ls / 2, cs + ls / 2)
    if ce - fl < lz + 2 * gap:
        raise ValueError(f"no cabe en altura: {ce - fl:.1f} mm < {lz} mm en x={cx}, s={cs}")
    return fl + gap + lz / 2 if sup == "suelo" else ce - gap - lz / 2


def make_cavity(mat):
    secs = []
    for s in np.linspace(-BAY["cav_s"], BAY["cav_s"], RES["cav"][0]):
        x, z, _, _ = cavity_station(float(s), RES["cav"][1])
        secs.append([to_blender(xx, float(s), zz) for xx, zz in zip(x, z)])
    cav = build_loft("X8_Volumen_Bahia", secs, mat=mat, smooth_angle=50)
    return cav


def apply_boolean(obj, cutter, op):
    mod = obj.modifiers.new("Booleano", "BOOLEAN")
    mod.operation = op
    mod.object = cutter
    try:
        mod.solver = "EXACT"
        mod.material_mode = "TRANSFER"
    except Exception:
        pass
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    obj.modifiers.remove(mod)
    old = obj.data
    obj.data = me
    bpy.data.meshes.remove(old)
    return obj


def chaikin(pts, it=4):
    for _ in range(it):
        out = []
        n = len(pts)
        for i in range(n):
            a, b = np.array(pts[i]), np.array(pts[(i + 1) % n])
            out += [tuple(0.75 * a + 0.25 * b), tuple(0.25 * a + 0.75 * b)]
        pts = out
    return pts


def round_rect(x0, x1, s0, s1, r, only=None, n=6):
    """Rectangulo en (x, s) con esquinas redondeadas (antihorario). only='s1' o 's0' redondea
    solo las dos esquinas de ese lado (la otra arista es el corte central entre compuertas)."""
    corners = [((x0, s0), (x0 + r, s0 + r), 180), ((x1, s0), (x1 - r, s0 + r), 270),
               ((x1, s1), (x1 - r, s1 - r), 0), ((x0, s1), (x0 + r, s1 - r), 90)]
    pts = []
    for (cx, cs), (ox, os_), a0 in corners:
        side = "s0" if cs == s0 else "s1"
        if only and side != only:
            pts.append((cx, cs))
            continue
        for k in range(n + 1):
            a = math.radians(a0 + 90.0 * k / n)
            pts.append((ox + r * math.cos(a), os_ + r * math.sin(a)))
    return pts


def hatch_outline():
    """Contorno de la tapa en (x, s): estrecha en la nariz, ancha sobre la bahia."""
    xs = np.linspace(BAY["hatch_x0"], BAY["hatch_x1"], 24)
    hw = pchip([115, 150, 210, 300, 420, 490, 520], [46, 70, 90, 100, 96, 88, 80])(xs)
    left = [(float(x), float(w)) for x, w in zip(xs, hw)]
    right = [(float(x), -float(w)) for x, w in zip(xs[::-1], hw[::-1])]
    return chaikin(left + right, 4)


def offset_outline(pts, d):
    P2 = np.array(pts)
    prev, nxt = np.roll(P2, 1, 0), np.roll(P2, -1, 0)
    t = nxt - prev
    n_ = np.stack([t[:, 1], -t[:, 0]], 1)
    n_ /= np.maximum(np.linalg.norm(n_, axis=1, keepdims=True), 1e-9)
    # (ty, -tx) es la normal a la derecha de la tangente: apunta afuera si el contorno va en
    # sentido antihorario (area con signo > 0); d > 0 agranda el contorno, d < 0 lo achica
    area = 0.5 * np.sum(P2[:, 0] * np.roll(P2[:, 1], -1) - np.roll(P2[:, 0], -1) * P2[:, 1])
    sgn = 1.0 if area > 0 else -1.0
    return [tuple(p) for p in P2 + sgn * d * n_]


def prism_from_outline(name, pts, z0, z1):
    n = len(pts)
    verts = [to_blender(x, s, z0) for x, s in pts] + [to_blender(x, s, z1) for x, s in pts]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return mesh_from_polys(name, verts, faces)


def rect_outline(x0, x1, s0, s1, r=6.0):
    pts = [(x0, s0), (x1, s0), (x1, s1), (x0, s1)]
    return chaikin(pts, 3) if r else pts


def mesh_volume_centroid(obj):
    """Volumen (mm3) y centroide (Blender) de una malla cerrada, por tetraedros."""
    deps = bpy.context.evaluated_depsgraph_get()
    oe = obj.evaluated_get(deps)
    me = oe.to_mesh()
    mw = oe.matrix_world
    me.calc_loop_triangles()
    V = np.array([tuple(mw @ v.co) for v in me.vertices]) * 1000.0
    T = np.array([tuple(t.vertices) for t in me.loop_triangles])
    oe.to_mesh_clear()
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    v6 = np.einsum("ij,ij->i", a, np.cross(b, c))
    vol = v6.sum() / 6.0
    cen = ((a + b + c) * v6[:, None]).sum(0) / (4.0 * v6.sum())
    return abs(vol), Vector(cen / 1000.0)


def hollow_and_cut(body, mats):
    """Vacia la seccion central y separa la tapa superior. Devuelve (tapa, cavidad)."""
    cav = make_cavity(mats["epo_int"])
    apply_boolean(body, cav, "DIFFERENCE")
    out_pts = offset_outline(hatch_outline(), BAY["kerf"] / 2)
    in_pts = offset_outline(hatch_outline(), -BAY["kerf"] / 2)
    pr_in = prism_from_outline("X8_Prisma_Tapa_in", in_pts, 5.0, 300.0)
    pr_out = prism_from_outline("X8_Prisma_Tapa_out", out_pts, 5.0, 300.0)
    lid = body.copy()
    lid.data = body.data.copy()
    lid.name = "X8_Tapa_Principal"
    bpy.context.scene.collection.objects.link(lid)
    apply_boolean(lid, pr_in, "INTERSECT")
    apply_boolean(body, pr_out, "DIFFERENCE")
    for o in (pr_in, pr_out):
        bpy.data.objects.remove(o)
    cav.display_type = "WIRE"
    cav.hide_render = True
    shade(lid, 50)
    shade(body, 50)
    return lid, cav


def keep_parent(o, parent):
    """Emparenta conservando la posicion en el mundo (refresca matrices antes de leerlas)."""
    bpy.context.view_layer.update()
    o.parent = parent
    o.matrix_parent_inverse = parent.matrix_world.inverted()


def box_obj(name, cx, cs, cz, lx, ls, lz, mat, bevel=0.0, parent=None):
    """Caja en mm (centro x, s, z y medidas) en coordenadas de Blender."""
    v, f = box_verts(-lx / 2, lx / 2, -ls / 2, ls / 2, -lz / 2, lz / 2)
    verts = [to_blender(cx + x, cs + s, cz + z) for x, s, z in v]
    o = mesh_from_polys(name, verts, f, mat)
    if bevel:
        b = o.modifiers.new("Bisel", "BEVEL")
        b.width = bevel * MM
        b.segments = 2
    if parent:
        keep_parent(o, parent)
    return o


def cyl_obj(name, cx, cs, cz, r, h, axis, mat, n=24, parent=None):
    """Cilindro en mm; axis = 'z' (vertical), 's' (envergadura) o 'x' (longitudinal)."""
    verts, faces = [], []
    for k in (-0.5, 0.5):
        for a in np.linspace(0, 2 * math.pi, n, endpoint=False):
            u, w = r * math.cos(a), r * math.sin(a)
            if axis == "z":
                verts.append(to_blender(cx + u, cs + w, cz + k * h))
            elif axis == "s":
                verts.append(to_blender(cx + u, cs + k * h, cz + w))
            else:
                verts.append(to_blender(cx + k * h, cs + u, cz + w))
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces += [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    o = mesh_from_polys(name, verts, faces, mat, 40)
    if parent:
        keep_parent(o, parent)
    return o


def make_hatch_hardware(body, lid, mats):
    """Imanes con placas, apoyos, lenguetas delanteras, cierre giratorio y pivote de la tapa."""
    objs = []
    # Pivote: arista delantera EXTERIOR de la tapa. Al levantar la parte de atras, todo el
    # canto delantero (que queda por debajo del eje) se mueve hacia atras y no muerde el labio
    # fijo; las lenguetas bajan y se separan de la cara interior del labio.
    x0 = BAY["hatch_x0"]
    xu0, zu0, _, _ = body_profile(0.0)
    z_out = float(np.interp(x0, xu0, zu0))
    piv = bpy.data.objects.new("X8_Pivote_Tapa", None)
    piv.empty_display_type = "ARROWS"
    piv.empty_display_size = 0.03
    bpy.context.scene.collection.objects.link(piv)
    piv.location = to_blender(x0, 0.0, z_out)
    piv.parent = body
    keep_parent(lid, piv)
    objs.append(piv)
    # Imanes: 3 pares por lado (delante, centro, detras), 6 mm hacia dentro del borde
    hwf = pchip([115, 150, 210, 300, 420, 490, 520], [46, 70, 90, 100, 96, 88, 80])
    spots = []
    for x in (175.0, 330.0, 470.0):
        w = float(hwf(x)) - 8.0
        spots += [(x, w), (x, -w)]
    k = 0
    for x, s in spots:
        k += 1
        # la cara interior de la tapa es curva: la placa plana de la tapa asoma 0,2 mm por
        # debajo de su punto mas bajo (el resto queda embutido en la espuma)
        _, c = footprint_limits(x - 8, x + 8, s - 8, s + 8, 5)
        zc = c - 0.2                                   # plano de contacto de los imanes
        objs.append(box_obj(f"X8_Placa_Tapa_{k}", x, s, zc + 0.75, 16, 16, 1.5, mats["plywood"],
                            parent=lid))
        objs.append(cyl_obj(f"X8_Iman_Tapa_{k}", x, s, zc + 0.3, BAY["mag_d"] / 2, 0.6, "z",
                            mats["magnet"], parent=lid))
        # placa e iman del fuselaje, sobre un apoyo de EPO pegado a la pared
        objs.append(box_obj(f"X8_Placa_Fuselaje_{k}", x, s, zc - 0.75, 16, 16, 1.5,
                            mats["plywood"], parent=body))
        objs.append(cyl_obj(f"X8_Iman_Fuselaje_{k}", x, s, zc - 0.3, BAY["mag_d"] / 2, 0.6, "z",
                            mats["magnet"], parent=body))
        so = s + (12.0 if s > 0 else -12.0)
        objs.append(box_obj(f"X8_Apoyo_Iman_{k}", x, (s + so) / 2, zc - 1.5 - 6.0, 18, 30, 12,
                            mats["epo_int"], parent=body))
    # Lenguetas delanteras: entran bajo el borde de la abertura
    # (la cara superior va 0,75 mm por debajo del punto mas bajo del labio que tapan; un taco
    # pegado a la tapa rellena el escalon hasta su cara interior)
    for s in (-24.0, 24.0):
        nm = 'I' if s > 0 else 'D'
        _, c_lip = footprint_limits(x0 - 9, x0, s - 7, s + 7)
        t_top = c_lip - 0.75
        objs.append(box_obj(f"X8_Lengueta_Tapa_{nm}", x0 + 2, s, t_top - 0.75, 22, 14, 1.5,
                            mats["plywood"], parent=lid))
        _, c_lid = footprint_limits(x0 + 2, x0 + 13, s - 7, s + 7)
        h = c_lid + 0.5 - t_top
        objs.append(box_obj(f"X8_Taco_Lengueta_{nm}", x0 + 7.5, s, t_top + h / 2, 11, 14, h,
                            mats["epo_int"], parent=lid))
    # Cierre giratorio trasero: perilla sobre la tapa y leva debajo
    xl = BAY["lock_x"]
    trees = bvh_of([lid])
    hit = raycast(trees, to_blender(xl, 0.0, 300.0), Vector((0, 0, -1)))
    ztop = (hit[0].z / MM) if hit else ceiling_floor(xl, 0.0)[0] + BAY["wall"]
    c, _ = ceiling_floor(xl, 0.0)
    knob_axis = bpy.data.objects.new("X8_Eje_Cierre", None)
    knob_axis.empty_display_type = "SINGLE_ARROW"
    knob_axis.empty_display_size = 0.02
    bpy.context.scene.collection.objects.link(knob_axis)
    knob_axis.location = to_blender(xl, 0.0, ztop)
    keep_parent(knob_axis, lid)
    knob_axis.rotation_mode = "XYZ"
    knob = cyl_obj("X8_Perilla_Cierre", xl, 0.0, ztop + 2.0, 8.0, 4.0, "z", mats["lock"],
                   parent=knob_axis)
    grip = box_obj("X8_Perilla_Agarre", xl, 0.0, ztop + 5.0, 14, 3.5, 3.0, mats["lock"],
                   parent=knob_axis)
    zb = c - LOCK["cam_dz"] - 1.5                       # cara inferior de la leva
    shaft = cyl_obj("X8_Perilla_Eje", xl, 0.0, (ztop + 3 + zb) / 2, 2.5, ztop + 3 - zb, "z",
                    mats["lock"], parent=knob_axis)
    L = LOCK
    cam = box_obj("X8_Leva_Cierre", xl, 0.0, c - L["cam_dz"], 8, 2 * L["cam_r"], 3.0,
                  mats["lock"], parent=knob_axis)
    # Tope fijo: dos repisas de contrachapado sobre postes que salen del suelo. Bloqueada, la
    # leva queda atravesada (a lo largo de s) por debajo de las repisas y la tapa no sube;
    # girada 90 grados queda a lo largo de x y pasa por la ranura entre las repisas.
    lock_fixed = []
    for sg, nm in ((1, "Der"), (-1, "Izq")):
        sm = sg * (L["slot"] + L["ledge_w"] / 2)
        ztop = c - L["cam_dz"] + 1.5 + L["gap"] + L["ledge_t"]
        lock_fixed.append(box_obj(f"X8_Tope_Cierre_{nm}", xl, sm, ztop - L["ledge_t"] / 2,
                                  L["ledge_l"], L["ledge_w"], L["ledge_t"], mats["plywood"],
                                  parent=body))
        sp = sg * L["post_s"]
        fl, _ = footprint_limits(xl - 4, xl + 4, sp - 4, sp + 4)
        hz = ztop - L["ledge_t"] - fl - 0.5
        lock_fixed.append(box_obj(f"X8_Poste_Cierre_{nm}", xl, sp, fl + 0.5 + hz / 2, 8, 8, hz,
                                  mats["plywood"], parent=body))
    objs += [knob_axis, knob, grip, shaft, cam] + lock_fixed
    return dict(objs=objs, pivot=piv, knob_axis=knob_axis, spots=spots,
                lock=[knob, grip, shaft, cam] + lock_fixed, cam=cam, ledges=lock_fixed[0::2])


def make_spar_tubes(mats):
    objs = []
    for i, x in enumerate(BAY["tube_x"]):
        z = P["z0"] + 2.0                      # plano medio del ala en la raiz
        objs.append(cyl_obj(f"X8_Tubo_Carbono_{i + 1}", x, 0.0, z, BAY["tube_d"] / 2,
                            2 * BAY["tube_s"], "s", mats["carbon"], n=20))
    return objs


def drape_plate(name, tree_objs, x0, x1, s0, s1, side_up, mat, lift=0.3, n=8, thick=1.2):
    """Placa delgada que copia la superficie (raycast sobre la malla base, sin modificadores)."""
    trees = []
    for o in tree_objs:
        me = o.data
        verts = [o.matrix_world @ v.co for v in me.vertices]
        trees.append((None, BVHTree.FromPolygons(verts, [tuple(p.vertices) for p in me.polygons])))
    d = Vector((0, 0, -1 if side_up else 1))
    verts, rows = [], []
    for x in np.linspace(x0, x1, n):
        row = []
        for s in np.linspace(s0, s1, n):
            o = to_blender(float(x), float(s), 300 if side_up else -300)
            best = None
            for _, t in trees:
                h = t.ray_cast(o, d)
                if h[0] is not None and (best is None or h[3] < best[3]):
                    best = h
            p = best[0] + best[1] * lift * MM if best else o
            row.append(len(verts))
            verts.append(p)
        rows.append(row)
    faces = [(a[j], a[j + 1], b[j + 1], b[j]) for a, b in zip(rows[:-1], rows[1:])
             for j in range(n - 1)]
    obj = mesh_from_polys(name, verts, faces, mat)
    sol = obj.modifiers.new("Espesor", "SOLIDIFY")
    sol.thickness = thick * MM
    sol.offset = 1.0
    shade(obj, 30)
    return obj


def make_servo_covers(mechs, mats):
    """Tapas de servo: placa de 1,2 mm sobre la bahia, sujeta con cinta (se retira hacia abajo)."""
    covers = []
    for m in mechs:
        # huella de la bahia en (x, s): proyectar el cortador del servo al plano
        cut = bpy.data.objects[f"X8_Hueco_Bahia_{m['name']}"]
        pts = [cut.matrix_world @ v.co for v in cut.data.vertices]
        xs = [p.y / MM + P["x_cg"] for p in pts]
        ss = [-p.x / MM for p in pts]
        x0, x1 = min(xs) - 4, max(xs) + 4
        s0, s1 = min(ss) - 4, max(ss) + 4
        wing = m["hinge"].parent
        cov = drape_plate(f"X8_Tapa_Servo_{m['name']}", [wing], x0, x1, s0, s1, False,
                          mats["cover"], lift=0.2)
        cov.parent = wing
        cov["x_mm"], cov["s_mm"] = (x0 + x1) / 2, (s0 + s1) / 2
        covers.append(cov)
    return covers


def make_camera_module(body, mats):
    """Camara de mapeo con dos compuertas ventrales tipo bodega, bisagra en los bordes laterales.

    Cada mitad gira hacia abajo hasta DOOR_DEG grados alrededor de una bisagra de piano paralela al
    eje longitudinal; abiertas quedan a los lados y dejan libre el campo de vision de la camara.
    """
    x0, x1, hw = BAY["cam_door"]
    xc = (x0 + x1) / 2
    objs = []
    r = 6.0                                       # radio de las esquinas de la abertura
    pts_out = round_rect(x0 - 0.5, x1 + 0.5, -hw - 0.5, hw + 0.5, r + 0.5)
    # el corte atraviesa la pared entera: llega 1 mm por encima del suelo interior mas alto
    fl_top, _ = footprint_limits(x0 - 1, x1 + 1, -hw - 1, hw + 1)
    fl = fl_top + 1.0
    pr_out = prism_from_outline("X8_Prisma_Puerta_out", pts_out, -300.0, fl)
    halves = {}
    for side, (s0, s1) in ((1, (0.4, hw - 0.5)), (-1, (-hw + 0.5, -0.4))):
        nm = SIDE_NAME[side]
        pts = round_rect(x0 + 0.5, x1 - 0.5, s0, s1, r - 0.5, only=("s1" if side == 1 else "s0"))
        pr = prism_from_outline(f"X8_Prisma_Puerta_{nm}", pts, -300.0, fl)
        door = body.copy()
        door.data = body.data.copy()
        door.name = f"X8_Compuerta_Camara_{nm}"
        bpy.context.scene.collection.objects.link(door)
        apply_boolean(door, pr, "INTERSECT")
        bpy.data.objects.remove(pr)
        shade(door, 50)
        door.data.materials.clear()
        door.data.materials.append(mats["door"])
        halves[side] = door
    apply_boolean(body, pr_out, "DIFFERENCE")
    bpy.data.objects.remove(pr_out)
    hinges = {}
    # Eje de bisagra: recta que sigue el intrados a lo largo del borde lateral (el fondo sube
    # ~3,4 mm de x0 a x1), bajada lo justo para quedar por debajo de la piel en todo el borde.
    # Todos los puntos de la compuerta quedan hacia dentro del eje y giran hacia abajo y hacia
    # dentro: no muerden el borde fijo.
    xu, zu, xl, zl = body_profile(hw)
    xs_e = np.linspace(x0, x1, 25)
    zs_e = np.interp(xs_e, xl, zl)
    za, zb = float(zs_e[0]), float(zs_e[-1])
    line = za + (zb - za) * (xs_e - x0) / (x1 - x0)
    drop = max(0.0, float(np.max(line - zs_e))) + 0.1
    za, zb = za - drop, zb - drop
    zh = (za + zb) / 2                                   # en xc
    tilt = math.atan2((zb - za) * MM, (x1 - x0) * MM)    # giro del eje alrededor de X
    for side, door in halves.items():
        nm = SIDE_NAME[side]
        h = bpy.data.objects.new(f"X8_Bisagra_Compuerta_{nm}", None)
        h.empty_display_type = "SINGLE_ARROW"
        h.empty_display_size = 0.02
        bpy.context.scene.collection.objects.link(h)
        h.location = to_blender(xc, side * hw, zh)
        h.parent = body
        # 'ZYX': matriz = Rx(inclinacion) * Ry(apertura): la apertura gira alrededor del eje
        # ya inclinado
        h.rotation_mode = "ZYX"
        h.rotation_euler = (tilt, 0.0, 0.0)
        keep_parent(door, h)
        c0 = Vector(to_blender(xc, side * hw, zh))
        tilt_m = Matrix.Translation(c0) @ Matrix.Rotation(tilt, 4, "X") @ Matrix.Translation(-c0)
        # borde central recortado por un cilindro de radio (hw - 0,4) con eje en la bisagra:
        # ningun punto de la compuerta pasa del plano de simetria al abrir, asi que las dos
        # mitades pueden abrirse a la vez sin tocarse
        trim = cyl_obj(f"X8_Recorte_Compuerta_{nm}", xc, side * hw, zh, hw - 0.4, x1 - x0 + 10,
                       "x", None, n=96)
        trim.data.transform(tilt_m)
        apply_boolean(door, trim, "INTERSECT")
        bpy.data.objects.remove(trim)
        # pasador de la bisagra de piano: radio 0,4 mm sobre el eje, dentro de la ranura de
        # 1 mm entre la compuerta y el borde fijo
        rod = cyl_obj(f"X8_Bisagra_Piano_{nm}", xc, side * hw, zh, 0.4, x1 - x0 - 6, "x",
                      mats["metal"], n=12)
        rod.data.transform(tilt_m)
        keep_parent(rod, body)
        hinges[side] = h
        objs += [door, h, rod]
    # servo de 9 g que abre las dos mitades con varillas (accionamiento simbolico)
    objs.append(box_obj("X8_Servo_Compuertas_9g", 615.0, 40.0,
                        seat_z(615.0, 40.0, 12, 23, 22, "suelo", 1.0), 12, 23, 22,
                        mats["servo_case"]))
    # camara: cuerpo y objetivo apuntando hacia abajo
    for nm_, m, dims, (cx, cs), sup, grp in COMPONENTS:
        if nm_ == "Camara_Mapeo":
            lx, ls, lz = dims
            ccx = cx
    cam_z = seat_z(ccx, 0.0, lx, ls, lz, "suelo") + 4.0     # sobre dos amortiguadores
    body_cam = box_obj("X8_Camara_Mapeo", ccx, 0.0, cam_z, lx, ls, lz, mats["comp_cam"], 2.0)
    lens = cyl_obj("X8_Camara_Mapeo_Objetivo", xc, 0.0, cam_z - lz / 2 - 3.0, 15.0, 6.0, "z",
                   mats["glass"])
    for k, dx in enumerate((-lx / 2 + 8, lx / 2 - 8)):
        fl_p, _ = footprint_limits(ccx + dx - 5, ccx + dx + 5, -20, 20)
        h_p = cam_z - lz / 2 - fl_p - 0.5
        objs.append(box_obj(f"X8_Amortiguador_Camara_{k + 1}", ccx + dx, 0.0, fl_p + 0.5 + h_p / 2,
                            10, 40, h_p, mats["epo_int"]))
    keep_parent(lens, body_cam)
    objs += [body_cam, lens]
    return dict(objs=objs, doors=halves, hinges=hinges, camera=body_cam)


def make_parachute_module(body, lid, mats):
    """Paquete de paracaidas con placa de resorte y servo de pestillo que retiene la tapa."""
    objs = []
    for nm_, m, dims, (cx, cs), sup, grp in COMPONENTS:
        if nm_ == "Paracaidas_Paquete":
            lx, ls, lz = dims
            x, s = cx, cs
    fl = seat_z(x, s, lx, ls, lz, "suelo") - lz / 2 - 0.5
    pack = box_obj("X8_Paracaidas_Paquete", x, s, fl + lz / 2 + 0.5, lx, ls, lz,
                   mats["chute"], 6.0)
    spring = cyl_obj("X8_Paracaidas_Resorte", x, s, fl + 4.0, 22.0, 6.0, "z", mats["metal"])
    keep_parent(spring, pack)
    # servo de 9 g colgado del techo, fuera del recorrido del pasador (s = 42-54 mm)
    latch = box_obj("X8_Servo_Pestillo_9g", 505.0, 48.0, seat_z(505.0, 48.0, 23, 12, 22, "techo", 1.0),
                    23, 12, 22, mats["servo_case"])
    pin_axis = bpy.data.objects.new("X8_Guia_Pestillo", None)
    pin_axis.empty_display_type = "PLAIN_AXES"
    pin_axis.empty_display_size = 0.01
    bpy.context.scene.collection.objects.link(pin_axis)
    pin_axis.parent = body
    cp = min(ceiling_floor(512.0, s_)[0] for s_ in (-1.0, 19.0, 39.0))
    pin = cyl_obj("X8_Pestillo", 512.0, 9.0, cp - 6.0, 1.5, 20.0, "s", mats["metal"])
    pin.parent = pin_axis
    pin.matrix_parent_inverse = Matrix.Identity(4)
    # enganche colgado de la tapa: el pasador (s = -1 a 19) lo atraviesa; al retirarse 20 mm
    # hacia +s (servo a 1900 us) queda en s = 19-39 mm y la tapa queda libre
    # placa de 3 mm con un agujero de 4 x 4 mm (el pasador de 3 mm pasa con 0,5 mm de juego)
    cc = ceiling_floor(512.0, 9.5)[0]
    zp = cp - 6.0
    parts_ = [(505, 519, zp + 2, cc + 0.5), (505, 519, zp - 4, zp - 2),
              (505, 510, zp - 2, zp + 2), (514, 519, zp - 2, zp + 2)]
    verts, faces = [], []
    for xa, xb, za, zb in parts_:
        v, f = box_verts(xa, xb, 8.0, 11.0, za, zb)
        faces += [tuple(i + len(verts) for i in ff) for ff in f]
        verts += [to_blender(x_, s_, z_) for x_, s_, z_ in v]
    catch = mesh_from_polys("X8_Enganche_Tapa", verts, faces, mats["plywood"])
    keep_parent(catch, lid)
    objs += [pack, spring, latch, pin_axis, pin, catch]
    return dict(objs=objs, pack=pack, pin_axis=pin_axis)


def make_components(mats, mechs):
    """Bloques de los equipos con su masa (propiedad masa_g) en la bahia."""
    comps = {}
    for nm_, m, (lx, ls, lz), (cx, cs), sup, grp in COMPONENTS:
        if grp != "serie":
            continue
        if sup == "nariz":
            cz = P["z0"] + 2.0
        elif nm_.startswith("Bateria"):
            # bandeja plana de contrachapado sobre los puntos altos del suelo en todo el
            # recorrido permitido de la bateria (la correa de velcro la sujeta en cada posicion)
            bx0, bx1 = BAT_RANGE[0] - lx / 2, BAT_RANGE[1] + lx / 2
            fl, ce = footprint_limits(bx0, bx1, cs - 30, cs + 30, 15)
            tray_z = fl + 0.5 + BAT_TRAY_T / 2
            for nm_t, a, b in (("X8_Bandeja_Bateria", bx0, BAY_CHUTE_X0 - 1.0),
                               ("X8_Bandeja_Bateria_Ext", BAY_CHUTE_X0, bx1)):
                t = box_obj(nm_t, (a + b) / 2, cs, tray_z, b - a, 60, BAT_TRAY_T, mats["plywood"])
                t["masa_g"] = 0.0
                comps[nm_t] = t
            cz = tray_z + BAT_TRAY_T / 2 + lz / 2
            if cz + lz / 2 > ce - 1.0:
                raise ValueError("la bateria no cabe sobre la bandeja")
        else:
            cz = seat_z(cx, cs, lx, ls, lz, sup)
        mat = mats["comp_bat"] if nm_.startswith("Bateria") else mats["comp"]
        o = box_obj(f"X8_{nm_}", cx, cs, cz, lx, ls, lz, mat, 2.0)
        o["masa_g"] = float(m)
        o["grupo"] = grp
        comps[nm_] = o
    return comps

# ----------------------------------------------------------------------------------------
# Logica de tapas, compuertas, armado y centro de gravedad (drivers de expresion simple)
# ----------------------------------------------------------------------------------------
GATE_DEFAULTS = dict(
    desbloqueo_tapa=0.0,        # 0 = cierre trasero girado a bloqueo, 1 = desbloqueado (90 grados)
    abrir_tapa=0.0,             # 0 cerrada ... 1 retirada (levantar detras, deslizar, sacar)
    tapas_servo_retiradas=0.0,  # 0 puestas, 1 retiradas
    incluir_camara=1,           # configuracion UAV: camara de mapeo y compuerta ventral
    incluir_paracaidas=1,       # configuracion UAV: paracaidas con expulsion de la tapa
    fase_mision=0.0,            # 0 tierra, 1 despegue, 2 crucero, 3 levantamiento, 4 aproximacion, 5 aterrizaje
    armar=0,                    # orden de armado del piloto
    acelerador=0.0,
    altitud_m=0.0,
    disparo_paracaidas=0,       # orden de liberacion (manual, MAVLink o failsafe)
    frame_disparo=0,            # fotograma en que se dio la orden
    chute_alt_min_m=10.0,       # CHUTE_ALT_MIN de ArduPilot
    chute_delay_ms=500.0,       # retardo entre parar el motor y soltar el pestillo
    bateria_x_mm=247.0,         # centro de la bateria desde la nariz
)
GATE_DESC = dict(
    desbloqueo_tapa="Cierre trasero: 0 bloqueado, 1 desbloqueado (giro de 90 grados)",
    abrir_tapa="Apertura pedida de la tapa (solo se mueve si el cierre esta desbloqueado)",
    tapas_servo_retiradas="Tapas de servo: 0 puestas, 1 retiradas",
    incluir_camara="Camara de mapeo y compuerta ventral (0/1)",
    incluir_paracaidas="Paracaidas con expulsion de la tapa (0/1)",
    fase_mision="0 tierra, 1 despegue, 2 crucero, 3 levantamiento, 4 aproximacion, 5 aterrizaje",
    armar="Orden de armado (0/1)",
    acelerador="Acelerador (0..1)",
    altitud_m="Altura sobre el despegue (m)",
    disparo_paracaidas="Orden de liberar el paracaidas (0/1)",
    frame_disparo="Fotograma de la orden de liberacion",
    chute_alt_min_m="Altura minima para liberar (CHUTE_ALT_MIN)",
    chute_delay_ms="Retardo motor parado -> pestillo (ms)",
    bateria_x_mm="Centro de la bateria medido desde la nariz (mm)",
)
FPS = 24


def gate_vars(ctl, names):
    short = dict(desbloqueo_tapa="de", abrir_tapa="ab", tapas_servo_retiradas="ts",
                 incluir_camara="ic", incluir_paracaidas="ip", fase_mision="fa", armar="ar",
                 acelerador="ac", altitud_m="h", disparo_paracaidas="dp", frame_disparo="fd",
                 chute_alt_min_m="am", chute_delay_ms="dl", bateria_x_mm="bx")
    return [(short[n], ctl, f'["{n}"]') for n in names]


# expresiones reutilizables (cada driver lleva su copia: Blender no encadena bien propiedades
# de un mismo objeto)
E_OPEN = "ab*(de > 0.99)"
E_REL = "ip*dp*(h >= am)"
E_EJECT = f"{E_REL}*clamp((frame - fd - dl*{FPS}/1000)/15, 0, 1)"
E_DOOR = "ic*clamp(1 - abs(fa - 3), 0, 1)"
E_PIN = f"{E_REL}*(frame >= fd + dl*{FPS}/1000)"      # pasador retirado por la liberacion
E_LOCKED = "(ab < 0.01)*(de < 0.01)"
# la bateria (155 mm) no puede tocar la camara FPV (frente >= 98 mm), ni invadir la zona de
# electronica (empieza en 416 mm) ni, con paracaidas, su paquete (empieza en 326 mm)
E_BATFIT = "(bx >= 175.5)*(bx + 77.5 <= 416 - 91*ip)"


def airframe_mass_model(parts):
    """Masa del kit repartida por volumen de espuma (densidad uniforme)."""
    vols = []
    for o in parts:
        v, c = mesh_volume_centroid(o)
        vols.append((o.name, v, c))
    vt = sum(v for _, v, _ in vols)
    rho = AIRFRAME_MASS / vt                     # g/mm3
    cy = sum(v * c.y for _, v, c in vols) / vt
    x_cg = cy / MM + P["x_cg"]
    return dict(vol_mm3=vt, rho_g_cm3=rho * 1000.0, x_mm=x_cg, parts=vols)


def cg_constants(airframe, comps, mechs, cam_mod, chute_mod):
    """Suma de momentos fija (g*mm) y masa fija (g); bateria y opcionales van aparte."""
    K = AIRFRAME_MASS * airframe["x_mm"]
    M = AIRFRAME_MASS
    for nm_, m, x, s, z in FIXED_MASSES:
        if x is None:      # servos: tomar su posicion real
            side = 1 if s > 0 else -1
            sv = bpy.data.objects[f"X8_Servo_ES3054_{SIDE_NAME[side]}"]
            vv = [sv.matrix_world @ v.co for v in sv.data.vertices]
            x = sum(p.y for p in vv) / len(vv) / MM + P["x_cg"]
        K += m * x
        M += m
    for nm_, m, dims, (cx, cs), sup, grp in COMPONENTS:
        if grp == "serie" and not nm_.startswith("Bateria"):
            K += m * cx
            M += m
    mb = [m for nm_, m, *_ in COMPONENTS if nm_.startswith("Bateria")][0]
    mc, xc = [(m, c[0]) for nm_, m, d, c, *_ in COMPONENTS if nm_ == "Camara_Mapeo"][0]
    mp, xp = [(m, c[0]) for nm_, m, d, c, *_ in COMPONENTS if nm_ == "Paracaidas_Paquete"][0]
    return dict(K=K, M=M, mb=mb, mc=mc, xc=xc, mp=mp, xp=xp)


def cg_expr(c):
    return (f"({c['K']:.1f} + {c['mb']}*bx + ic*{c['mc'] * c['xc']:.1f} + ip*{c['mp'] * c['xp']:.1f})"
            f"/({c['M']:.1f} + {c['mb']} + ic*{c['mc']} + ip*{c['mp']})")


def led_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.05, 0.05, 0.05, 1)
    key = "Emission Color" if "Emission Color" in b.inputs else "Emission"
    b.inputs[key].default_value = (1, 0, 0, 1)
    if "Emission Strength" in b.inputs:
        b.inputs["Emission Strength"].default_value = 3.0
    return m, b.inputs[key]


def drive_led(mat, inp, expr_ok, variables, simple):
    path = inp.path_from_id("default_value")
    for i, e in ((0, f"1 - ({expr_ok})"), (1, f"{expr_ok}"), (2, "0")):
        fc = mat.node_tree.driver_add(path, i)
        d = fc.driver
        d.type = "SCRIPTED"
        for vname, tgt, dpath in variables:
            v = d.variables.new()
            v.name = vname
            v.type = "SINGLE_PROP"
            v.targets[0].id_type = "OBJECT"
            v.targets[0].id = tgt
            v.targets[0].data_path = dpath
        d.expression = e
        simple.append(d.is_simple_expression)


def make_gate_logic(parts, mats):
    """Controlador, estado, drivers de tapas/compuertas, CG y luces de estado."""
    simple = []
    ctl = bpy.data.objects.new("X8_Logica_Tapas", None)
    ctl.empty_display_type = "CUBE"
    ctl.empty_display_size = 0.02
    bpy.context.scene.collection.objects.link(ctl)
    ctl.location = (1.35, -0.2, -0.12)
    for k, v in GATE_DEFAULTS.items():
        lo, hi = {"fase_mision": (0, 5), "altitud_m": (0, 500), "frame_disparo": (0, 10000),
                  "chute_alt_min_m": (0, 100), "chute_delay_ms": (0, 3000),
                  "bateria_x_mm": (175, 339)}.get(k, (0, 1))
        add_prop(ctl, k, v, lo, hi, GATE_DESC[k])
    est = bpy.data.objects.new("X8_Estado", None)
    est.empty_display_type = "PLAIN_AXES"
    est.empty_display_size = 0.01
    bpy.context.scene.collection.objects.link(est)
    est.location = (1.35, -0.1, -0.12)

    cgc = parts["cg_const"]
    allv = list(GATE_DEFAULTS.keys())
    V = gate_vars(ctl, allv)

    # --- CG ------------------------------------------------------------------------------
    cgm = cyl_obj("X8_Marcador_CG", P["x_cg"], 0.0, 95.0, 9.0, 2.0, "z", mats["cg"])
    add_prop(cgm, "cg_mm", P["x_cg"], 300, 600, "CG desde la nariz (mm)")
    add_prop(cgm, "cg_ok", 1.0, 0, 1, "1 si el CG esta entre 430 y 440 mm")
    add_prop(cgm, "masa_total_g", 0.0, 0, 6000, "Masa total (g)")
    e_cg = cg_expr(cgc)
    simple.append(add_driver(cgm, '["cg_mm"]', e_cg, V).is_simple_expression)
    simple.append(add_driver(cgm, '["cg_ok"]', f"(({e_cg}) >= 430)*(({e_cg}) <= 440)",
                             V).is_simple_expression)
    simple.append(add_driver(cgm, '["masa_total_g"]',
                             f"{cgc['M'] + cgc['mb']:.1f} + ic*{cgc['mc']} + ip*{cgc['mp']}",
                             V).is_simple_expression)
    simple.append(add_driver(cgm, "location", f"(({e_cg}) - {P['x_cg']})/1000", V,
                             index=1).is_simple_expression)
    Vcg = V + [("ok", cgm, '["cg_ok"]')]

    # --- Estado (cada salida se calcula solo con entradas) ----------------------------------
    outs = {
        "tapa_cerrada_bloqueada": f"{E_LOCKED}*(1 - {E_REL})",
        "apertura_efectiva": E_OPEN,
        "paracaidas_liberado": E_REL,
        "eyeccion": E_EJECT,
        "servo_pestillo_us": f"1100 + 800*max(ip*de, {E_PIN})",
        "compuerta_camara": E_DOOR,
        "bateria_cabe": E_BATFIT,
        "armado": f"ar*{E_LOCKED}*(1 - ts)*ok*{E_BATFIT}*(1 - {E_REL})",
        "motor": f"ar*{E_LOCKED}*(1 - ts)*ok*{E_BATFIT}*(1 - {E_REL})*(ac > 0.05)",
    }
    for k, e in outs.items():
        add_prop(est, k, 0.0, desc=k)
        d = add_driver(est, f'["{k}"]', e, Vcg)
        simple.append(d.is_simple_expression)

    # --- Tapa principal: abrir a mano o expulsion por paracaidas ----------------------------
    piv = parts["hatch"]["pivot"]
    y0, z0 = piv.location.y, piv.location.z
    # mismo orden en las dos maniobras: 1) girar levantando la parte de atras (el canto trasero
    # sube por encima del labio), 2) deslizar hacia atras (las lenguetas salen de debajo del
    # labio delantero), 3) subir. A mano: 28 grados, 18 mm y 160 mm. Expulsion: 75 grados,
    # 140 mm y 300 mm, empujada por el resorte y arrastrada por la corriente.
    EE = E_EJECT
    e_ang = f"radians(max(28*clamp(({E_OPEN})/0.4, 0, 1), 75*clamp({EE}/0.3, 0, 1)))"
    e_y = (f"{y0:.5f} + (18*clamp(({E_OPEN} - 0.4)/0.2, 0, 1)"
           f" + 140*clamp(({EE} - 0.1)/0.9, 0, 1))/1000")
    e_z = (f"{z0:.5f} + (160*clamp(({E_OPEN} - 0.6)/0.4, 0, 1)"
           f" + 300*clamp(({EE} - 0.25)/0.75, 0, 1))/1000")
    piv.rotation_mode = "XYZ"
    for path, idx, e in (("rotation_euler", 0, e_ang), ("location", 1, e_y), ("location", 2, e_z)):
        simple.append(add_driver(piv, path, e, V, index=idx).is_simple_expression)
    simple.append(add_driver(parts["hatch"]["knob_axis"], "rotation_euler", "radians(90*de)", V,
                             index=2).is_simple_expression)
    # con paracaidas el cierre giratorio no se monta: la tapa la retiene el pasador del servo
    for o in parts["hatch"]["lock"]:
        for p_ in ("hide_viewport", "hide_render"):
            simple.append(add_driver(o, p_, "ip > 0.5", V).is_simple_expression)

    # --- Tapas de servo ------------------------------------------------------------------
    for cov in parts["covers"]:
        simple.append(add_driver(cov, "location", "-0.045*ts", V, index=2).is_simple_expression)

    # --- Camara: compuertas ventrales tipo bodega -----------------------------------------
    cam = parts["camera"]
    for side, h in cam["hinges"].items():
        sg = "" if side == 1 else "-"
        simple.append(add_driver(h, "rotation_euler", f"{sg}radians({DOOR_DEG:g}*{E_DOOR})", V,
                                 index=1).is_simple_expression)
    add_prop(est, "servo_compuertas_us", 1100.0, desc="Servo de las compuertas (us)")
    simple.append(add_driver(est, '["servo_compuertas_us"]', f"1100 + 800*{E_DOOR}", V).is_simple_expression)
    for o in cam["objs"]:
        if o.type == "MESH":
            for p_ in ("hide_viewport", "hide_render"):
                simple.append(add_driver(o, p_, "ic < 0.5", V).is_simple_expression)

    # --- Paracaidas: pestillo y expulsion del paquete --------------------------------------
    ch = parts["chute"]
    # pasador: se retira 20 mm (hacia +s) con el desbloqueo en tierra o con la liberacion
    simple.append(add_driver(ch["pin_axis"], "location", f"-0.020*max(de, {E_PIN})", V,
                             index=0).is_simple_expression)
    # el resorte lanza el paquete hacia arriba; la corriente lo arrastra hacia atras despues
    simple.append(add_driver(ch["pack"], "location", f"0.25*{E_EJECT}*{E_EJECT}", V,
                             index=1).is_simple_expression)
    simple.append(add_driver(ch["pack"], "location", f"0.30*{E_EJECT}", V,
                             index=2).is_simple_expression)
    for o in ch["objs"]:
        if o.type == "MESH":
            for p_ in ("hide_viewport", "hide_render"):
                simple.append(add_driver(o, p_, "ip < 0.5", V).is_simple_expression)

    # --- Bateria deslizable ----------------------------------------------------------------
    ext = parts["comps"]["X8_Bandeja_Bateria_Ext"]
    for p_ in ("hide_viewport", "hide_render"):
        simple.append(add_driver(ext, p_, "ip > 0.5", V).is_simple_expression)
    bat = parts["comps"]["Bateria_6S_5000"]
    simple.append(add_driver(bat, "location", f"(bx - {GATE_DEFAULTS['bateria_x_mm']})/1000", V,
                             index=1).is_simple_expression)

    # --- Rotor: gira solo si el motor esta habilitado ---------------------------------------
    rotor = parts["rotor"]
    simple.append(add_driver(rotor, "rotation_euler", "-frame*0.9*m",
                             [("m", est, '["motor"]')], index=1).is_simple_expression)

    # --- Luces de estado -------------------------------------------------------------------
    leds = []
    for i, (lab, expr, vs) in enumerate((
            ("TAPA", "t", [("t", est, '["tapa_cerrada_bloqueada"]')]),
            ("CG", "ok", [("ok", cgm, '["cg_ok"]')]),
            ("ARMADO", "a", [("a", est, '["armado"]')]),
            ("PARACAIDAS", "1 - r", [("r", est, '["paracaidas_liberado"]')]))):
        mat, inp = led_material(f"LED_{lab}")
        drive_led(mat, inp, expr, vs, simple)
        led = cyl_obj(f"X8_LED_{lab}", P["x_cg"], 0, 0, 7.0, 4.0, "z", mat)
        led.location = (1.25, -0.30 + 0.05 * i, -0.115)
        cu = bpy.data.curves.new(f"X8_Rotulo_{lab}", "FONT")
        cu.body = lab
        cu.size = 0.012
        cu.align_y = "CENTER"
        tx = bpy.data.objects.new(f"X8_Rotulo_{lab}", cu)
        bpy.context.scene.collection.objects.link(tx)
        tx.location = (1.27, -0.30 + 0.05 * i, -0.115)
        tx.data.materials.append(mats["servo_case"])
        leds += [led, tx]
    return dict(ctl=ctl, est=est, cg=cgm, leds=leds, simple=simple)


def animate_gates(ctl):
    """Secuencia de prueba (fotogramas 260-640): tapa, interbloqueos, mision y paracaidas."""
    keys = {
        "desbloqueo_tapa": [(260, 0), (272, 0), (284, 1), (372, 1), (384, 0)],
        "abrir_tapa": [(284, 0), (330, 1), (340, 1), (372, 0)],
        "tapas_servo_retiradas": [(392, 0), (396, 1), (420, 1), (424, 0)],
        "armar": [(260, 0), (376, 1)],
        "acelerador": [(430, 0), (440, 0.7)],
        "fase_mision": [(430, 0), (440, 1), (460, 2), (480, 2), (492, 3), (540, 3), (552, 4),
                        (580, 4)],
        "altitud_m": [(430, 0), (480, 120), (580, 120)],
        "disparo_paracaidas": [(580, 0), (590, 1)],
        "frame_disparo": [(590, 590)],
        "bateria_x_mm": [(260, 200), (392, 200), (404, 228)],
    }
    const = {"tapas_servo_retiradas", "armar", "disparo_paracaidas", "frame_disparo"}
    for k, seq in keys.items():
        for f, v in seq:
            ctl[k] = type(GATE_DEFAULTS[k])(v)
            ctl.keyframe_insert(f'["{k}"]', frame=f)
    try:
        fcs = ctl.animation_data.action.fcurves
    except Exception:
        fcs = []
        for layer in ctl.animation_data.action.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    fcs += list(cb.fcurves)
    for fc in fcs:
        name = fc.data_path.split('"')[1]
        for kp in fc.keyframe_points:
            kp.interpolation = "CONSTANT" if name in const else "LINEAR"
    for k, v in GATE_DEFAULTS.items():
        ctl[k] = v
    act = ctl.animation_data.action
    act.name = "X8_Prueba_Tapas"
    act.use_fake_user = True          # el panel la puede quitar y volver a poner
    sc = bpy.context.scene
    sc.frame_end = 640


def volume_report(cav, lid, airframe):
    """Volumenes de la bahia por zonas (integracion por estaciones) y ocupacion."""
    zones = [("nariz", 95, 120), ("bateria", 120, 326), ("paracaidas", 326, 416),
             ("electronica", 416, 476), ("camara", 484, 596), ("cola_ESC", 604, 700)]
    ss = np.linspace(-BAY["cav_s"], BAY["cav_s"], 121)
    ds = ss[1] - ss[0]
    res = {z[0]: 0.0 for z in zones}
    w = BAY["wall"]
    for s in ss:
        xu, zu, xl, zl = body_profile(float(s))
        _, _, ca, cb = cavity_station(float(s), 16)
        for name, xa, xb in zones:
            xs = np.linspace(max(xa, ca), min(xb, cb), 60)
            if xs[-1] <= xs[0]:
                continue
            h = np.clip(np.interp(xs, xu, zu) - np.interp(xs, xl, zl) - 2 * w, 0, None)
            tr = np.trapezoid if hasattr(np, "trapezoid") else np.trapz
            res[name] += float(tr(h, xs)) * ds
    res = {k: v / 1e6 for k, v in res.items()}
    vc, _ = mesh_volume_centroid(cav)
    vl, _ = mesh_volume_centroid(lid)
    comp_vol = sum(d[0] * d[1] * d[2] for _, _, d, *_ in COMPONENTS) / 1e6
    return dict(bahia_total_L=vc / 1e6, zonas_L=res, tapa_L=vl / 1e6,
                espuma_total_L=airframe["vol_mm3"] / 1e6, densidad_g_cm3=airframe["rho_g_cm3"],
                componentes_L=comp_vol, cg_estructura_mm=airframe["x_mm"])


# ----------------------------------------------------------------------------------------
# Escena: iluminacion de estudio, suelo, camaras con nombre
# ----------------------------------------------------------------------------------------
def setup_world():
    sc = bpy.context.scene
    w = bpy.data.worlds.new("Estudio")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes.get("Background")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.50, 0.52, 0.55, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.92, 0.94, 0.97, 1)
    mp = nt.nodes.new("ShaderNodeMapRange")
    mp.inputs["From Min"].default_value = -1.0
    mp.inputs["From Max"].default_value = 1.0
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], mp.inputs["Value"])
    nt.links.new(mp.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.32


def add_light(name, kind, loc, rot, energy, size=1.0, color=(1, 1, 1)):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    if kind == "AREA":
        ld.size = size
    if kind == "SUN":
        ld.angle = math.radians(5.0)
    ob = bpy.data.objects.new(name, ld)
    ob.location = loc
    ob.rotation_euler = rot
    bpy.context.scene.collection.objects.link(ob)
    return ob


def setup_lights():
    """Luz de estudio: clave calida arriba-adelante, relleno frio y contraluz."""
    lights = [
        add_light("Sol", "SUN", (1.1, -1.3, 4.0), (0, 0, 0), 2.8, color=(1.0, 0.95, 0.88)),
        add_light("Relleno", "AREA", (-3.2, -2.4, 1.6), (0, 0, 0), 150, size=3.0,
                  color=(0.88, 0.93, 1.0)),
        add_light("Contra", "AREA", (1.5, 3.4, 2.6), (0, 0, 0), 260, size=2.5),
        add_light("Bajo", "AREA", (0.0, -1.0, -2.2), (0, 0, 0), 90, size=4.0),
    ]
    for lo in lights:
        look_at(lo, (0, 0, 0))
        if lo.name != "Sol":            # solo el sol proyecta sombra: una sombra limpia en el suelo
            if hasattr(lo.data, "use_shadow"):
                lo.data.use_shadow = False
            try:
                lo.data.cycles.cast_shadow = False
            except Exception:
                pass
    return lights


def setup_ground(mat):
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.20))
    g = bpy.context.active_object
    g.name = "Suelo"
    g.data.materials.append(mat)
    g.is_shadow_catcher = True          # sombra sobre fondo transparente
    return g


def look_at(cam, target):
    d = Vector(target) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


CAMERAS = {
    # nombre: (tipo, ubicacion, objetivo, escala_orto o lente, suelo visible)
    "Cam_Frontal":       ("ORTHO", (0, -5, 0.02), (0, 0, 0.02), 2.35, False),
    "Cam_Trasera":       ("ORTHO", (0, 5, 0.02), (0, 0, 0.02), 2.35, False),
    "Cam_Lateral":       ("ORTHO", (5, -0.0, 0.02), (0, -0.0, 0.02), 1.25, False),
    "Cam_Superior":      ("ORTHO", (0, -0.05, 5), (0, -0.05, 0), 2.35, False),
    "Cam_Inferior":      ("ORTHO", (0, -0.05, -5), (0, -0.05, 0), 2.35, False),
    "Cam_34_Frontal":    ("PERSP", (2.2, -2.45, 1.25), (0.14, 0.04, -0.03), 50, True),
    "Cam_34_Trasera":    ("PERSP", (-2.05, 2.05, 1.05), (0, 0.02, -0.03), 50, True),
    "Cam_Rasante":       ("PERSP", (1.25, -3.25, 0.10), (0, 0.10, 0.03), 50, True),
}


def setup_cameras():
    cams = {}
    for name, (kind, loc, tgt, val, _) in CAMERAS.items():
        cd = bpy.data.cameras.new(name)
        cd.type = kind
        if kind == "ORTHO":
            cd.ortho_scale = val
        else:
            cd.lens = val
        cd.clip_end = 100
        cam = bpy.data.objects.new(name, cd)
        cam.location = loc
        bpy.context.scene.collection.objects.link(cam)
        if name == "Cam_Superior":
            cam.rotation_euler = (0, 0, 0)
        elif name == "Cam_Inferior":
            cam.rotation_euler = (math.pi, 0, 0)
        else:
            look_at(cam, tgt)
        cams[name] = cam
    bpy.context.scene.camera = cams["Cam_34_Frontal"]
    return cams


def setup_turntable(frames=72):
    sc = bpy.context.scene
    piv = bpy.data.objects.new("Pivote_Giro", None)
    sc.collection.objects.link(piv)
    cd = bpy.data.cameras.new("Cam_Giro")
    cd.lens = 50
    cam = bpy.data.objects.new("Cam_Giro", cd)
    sc.collection.objects.link(cam)
    cam.parent = piv
    cam.location = (0, -3.85, 1.15)
    look_at(cam, (0, 0, -0.08))
    sc.frame_start, sc.frame_end = 1, frames
    piv.rotation_euler = (0, 0, 0)
    piv.keyframe_insert("rotation_euler", index=2, frame=1)
    piv.rotation_euler = (0, 0, 2 * math.pi * frames / (frames))
    piv.keyframe_insert("rotation_euler", index=2, frame=frames + 1)
    try:
        for fc in piv.animation_data.action.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"
    except Exception:
        try:
            for layer in piv.animation_data.action.layers:
                for strip in layer.strips:
                    for cb in strip.channelbags:
                        for fc in cb.fcurves:
                            for kp in fc.keyframe_points:
                                kp.interpolation = "LINEAR"
        except Exception:
            pass
    return cam


# ----------------------------------------------------------------------------------------
# Datos geometricos para el informe
# ----------------------------------------------------------------------------------------
def geometry_report():
    s = np.linspace(0, P["s_tip"], 4000)
    c = TE(s) - LE(s)
    S_half = np.trapezoid(c, s) if hasattr(np, "trapezoid") else np.trapz(c, s)
    mac = (np.trapezoid(c**2, s) if hasattr(np, "trapezoid") else np.trapz(c**2, s)) / S_half
    x_le_mac = (np.trapezoid(c * LE(s), s) if hasattr(np, "trapezoid") else np.trapz(c * LE(s), s)) / S_half
    sweep_le = math.degrees(math.atan((LE(890) - LE(390)) / 500))
    S = 2 * S_half * 1e-6
    b = 2 * (_PB_END[0] + P["wl_len"] * math.cos(_PHW)) * 1e-3
    # punto neutro aproximado: cuarto de cuerda local ponderado por una carga eliptica
    se = np.linspace(0, P["s_tip"], 4000)
    lift = np.sqrt(np.clip(1 - (se / (b * 500)) ** 2, 0, 1))
    xqc = LE(se) + 0.25 * (TE(se) - LE(se))
    trap = np.trapezoid if hasattr(np, "trapezoid") else np.trapz
    x_np = trap(lift * xqc, se) / trap(lift, se)
    return dict(
        envergadura_m=round(b, 3),
        superficie_proyectada_m2=round(S, 3),
        alargamiento=round((2 * P["s_tip"] * 1e-3) ** 2 / S, 2),
        cuerda_media_aerodinamica_mm=round(float(mac), 1),
        borde_ataque_MAC_desde_nariz_mm=round(float(x_le_mac), 1),
        cuerda_media_geometrica_S_b_mm=round(S / b * 1000, 1),
        cuarto_MAC_desde_nariz_mm=round(float(x_le_mac + 0.25 * mac), 1),
        punto_neutro_aprox_mm=round(float(x_np), 1),
        margen_estatico_CG440_pct_MAC=round(float((x_np - P["x_cg"]) / mac * 100), 1),
        flecha_borde_ataque_deg=round(sweep_le, 1),
        cuerda_raiz_ala_mm=round(float(TE(P["s_joint"]) - LE(P["s_joint"])), 1),
        cuerda_punta_mm=round(float(TE(P["s_tip"]) - LE(P["s_tip"])), 1),
        longitud_fuselaje_mm=float(_TE_X[0]),
        altura_winglet_mm=round(_H_TOP, 1),
    )


# ----------------------------------------------------------------------------------------
# Construccion principal
# ----------------------------------------------------------------------------------------
def clear_scene():
    """Vacia la escena sin borrar los textos (seguro al ejecutar desde el editor de Blender)."""
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                 bpy.data.cameras, bpy.data.lights, bpy.data.worlds, bpy.data.actions):
        for block in list(coll):
            coll.remove(block)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)


def build(clear=True):
    if clear:
        if bpy.app.background:
            bpy.ops.wm.read_factory_settings(use_empty=True)
        else:
            clear_scene()
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.length_unit = "MILLIMETERS"

    mats = dict(
        epo=principled("EPO_Blanco", (0.80, 0.805, 0.79), rough=0.58, spec=0.35,
                       bump=(900.0, 0.06), sss=0.03),
        rib=principled("Plastico_Naranja", (0.95, 0.30, 0.02), rough=0.35, spec=0.5),
        seam=principled("Linea_Union", (0.12, 0.12, 0.12), rough=0.7),
        dark=principled("Orificio_Oscuro", (0.02, 0.02, 0.02), rough=0.6),
        glass=principled("Ventana_Camara", (0.01, 0.01, 0.012), rough=0.05, spec=0.8),
        motor=principled("Motor_Negro", (0.025, 0.025, 0.03), rough=0.35, metal=0.9),
        motor_bell=principled("Campana_Motor", (0.55, 0.06, 0.04), rough=0.3, metal=0.9),
        metal=principled("Acero", (0.75, 0.75, 0.77), rough=0.25, metal=1.0),
        prop=principled("Helice_Negra", (0.02, 0.02, 0.02), rough=0.32, spec=0.5),
        servo=principled("Tapa_Servo", (0.42, 0.43, 0.45), rough=0.4),
        ground=principled("Suelo_Estudio", (0.62, 0.63, 0.64), rough=0.85, spec=0.2),
        tape=principled("Cinta_Bisagra", (0.02, 0.02, 0.022), rough=0.35, spec=0.5),
        horn=principled("Cuerno_Naranja", (0.95, 0.33, 0.03), rough=0.4, spec=0.5),
        horn_white=principled("Brazo_Nylon", (0.86, 0.86, 0.83), rough=0.45),
        servo_case=principled("Caja_Servo", (0.03, 0.03, 0.035), rough=0.4, spec=0.5),
        epo_int=principled("EPO_Interior", (0.62, 0.62, 0.60), rough=0.7, spec=0.2),
        plywood=principled("Contrachapado", (0.72, 0.55, 0.33), rough=0.7),
        magnet=principled("Iman_Neodimio", (0.7, 0.7, 0.72), rough=0.2, metal=1.0),
        lock=principled("Cierre_Nylon", (0.05, 0.05, 0.06), rough=0.4),
        carbon=principled("Fibra_Carbono", (0.015, 0.015, 0.018), rough=0.25, spec=0.6),
        cover=principled("Tapa_Servo_Plastico", (0.55, 0.57, 0.60), rough=0.35),
        door=principled("Compuerta_EPO", (0.70, 0.74, 0.80), rough=0.55, spec=0.3),
        comp=principled("Equipo_Electronico", (0.10, 0.32, 0.60), rough=0.5),
        comp_bat=principled("Bateria_LiPo", (0.85, 0.75, 0.10), rough=0.45),
        comp_cam=principled("Camara_Mapeo", (0.08, 0.08, 0.09), rough=0.3),
        chute=principled("Paracaidas", (0.90, 0.30, 0.05), rough=0.8),
        cg=principled("Marcador_CG", (0.1, 0.1, 0.1), rough=0.4),
    )

    body = make_center_body(mats["epo"])
    lid, cavity = hollow_and_cut(body, mats)
    ribs = [make_rib(sd, mats["rib"]) for sd in (1, -1)]
    wings = [make_wing_main(sd, mats["epo"]) for sd in (1, -1)]
    tips = [make_wing_outer(sd, mats["epo"]) for sd in (1, -1)]
    elevs = [make_elevon(sd, mats["epo"]) for sd in (1, -1)]
    power = make_powertrain(mats)
    details = make_details(body, wings, elevs, mats)
    # Mecanica de mando y logica (sides: wings/elevs estan en orden (Der, Izq))
    mechs = [make_mechanism(sd, w, e, mats) for sd, w, e in zip((1, -1), wings, elevs)]
    logic = make_logic(mechs, mats)
    # Volumenes, tapas, compuertas y equipos
    hatch = make_hatch_hardware(body, lid, mats)
    tubes = make_spar_tubes(mats)
    covers = make_servo_covers(mechs, mats)
    cam_mod = make_camera_module(body, mats)
    chute_mod = make_parachute_module(body, lid, mats)
    comps = make_components(mats, mechs)
    hub = bpy.data.objects["X8_Buje_Helice"]
    rotor = bpy.data.objects.new("X8_Rotor", None)
    rotor.empty_display_type = "CIRCLE"
    rotor.empty_display_size = 0.03
    sc.collection.objects.link(rotor)
    rotor.location = hub.matrix_world.translation
    rotor.rotation_mode = "XYZ"
    for nm_ in ("X8_Buje_Helice", "X8_Cono_Helice", "X8_Pala_1", "X8_Pala_2"):
        keep_parent(bpy.data.objects[nm_], rotor)     # refresca la matriz del rotor antes
    airframe = airframe_mass_model([body, lid, *ribs, *wings, *tips, *elevs])
    cgc = cg_constants(airframe, comps, mechs, cam_mod, chute_mod)
    gates = make_gate_logic(dict(hatch=hatch, covers=covers, camera=cam_mod, chute=chute_mod,
                                 comps=comps, rotor=rotor, cg_const=cgc), mats)

    # Colecciones ordenadas y un vacio raiz en el CG
    root = bpy.data.objects.new("Skywalker_X8", None)
    root.empty_display_type = "ARROWS"
    root.empty_display_size = 0.15
    sc.collection.objects.link(root)
    col = {}
    for cname in ("X8_Estructura", "X8_Superficies_Control", "X8_Mecanica_Mandos",
                  "X8_Logica_Mando", "X8_Tapas_Compuertas", "X8_Equipos", "X8_Logica_Tapas",
                  "X8_Propulsion", "X8_Detalles", "Escena"):
        c = bpy.data.collections.new(cname)
        sc.collection.children.link(c)
        col[cname] = c

    def move(objs, cname):
        for o in objs:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            col[cname].objects.link(o)
            if o.parent is None and o is not root:
                o.parent = root

    move([body, *ribs, *wings, *tips], "X8_Estructura")
    move(elevs, "X8_Superficies_Control")
    move(power, "X8_Propulsion")
    move(details, "X8_Detalles")
    move([o for m in mechs for o in m["objs"]], "X8_Mecanica_Mandos")
    move(logic["objs"], "X8_Logica_Mando")
    move([lid, cavity, *hatch["objs"], *tubes, *covers, *cam_mod["objs"], *chute_mod["objs"]],
         "X8_Tapas_Compuertas")
    move(list(comps.values()), "X8_Equipos")
    move([gates["ctl"], gates["est"], gates["cg"], *gates["leds"], rotor], "X8_Logica_Tapas")
    move([root], "X8_Estructura")

    setup_world()
    setup_lights()
    sc.render.film_transparent = False   # el atrapasombras se compone sobre el fondo
    ground = setup_ground(mats["ground"])
    cams = setup_cameras()
    turn = setup_turntable()
    scene_objs = [ground, *cams.values(), turn, bpy.data.objects["Pivote_Giro"],
                  *[o for o in bpy.data.objects if o.type == "LIGHT"]]
    for o in scene_objs:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col["Escena"].objects.link(o)

    # Camara de trabajo para ver el varillaje izquierdo desde abajo y atras
    gl = mechs[1]["g"]
    tgt = (gl["O_s"] + gl["H"]) / 2
    cd = bpy.data.cameras.new("Cam_Mecanismo_Izq")
    cd.lens = 35
    cd.clip_start = 0.005
    cmo = bpy.data.objects.new("Cam_Mecanismo_Izq", cd)
    col["Escena"].objects.link(cmo)
    cmo.location = tgt + Vector((0.11, 0.17, -0.16))
    look_at(cmo, tgt)
    animate_inputs(logic["rc"])
    animate_gates(gates["ctl"])
    vol = volume_report(cavity, lid, airframe)
    ctl = gates["ctl"]
    ctl["vol_bahia_L"] = round(vol["bahia_total_L"], 3)
    ctl["vol_espuma_L"] = round(vol["espuma_total_L"], 3)
    ctl["densidad_espuma_g_cm3"] = round(vol["densidad_g_cm3"], 4)
    ctl["cg_estructura_mm"] = round(vol["cg_estructura_mm"], 1)
    for k_, v_ in vol["zonas_L"].items():
        ctl[f"vol_zona_{k_}_L"] = round(v_, 3)
    install_panel()

    sc.render.engine = "CYCLES"
    sc.cycles.samples = 96
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
    sc.view_settings.view_transform = "AgX" if "AgX" in [
        i.identifier for i in sc.view_settings.bl_rna.properties["view_transform"].enum_items
    ] else "Filmic"
    sc.view_settings.exposure = -0.35
    try:
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    return dict(body=body, wings=wings, tips=tips, elevons=elevs, ground=ground, cams=cams,
                turn=turn, mechs=mechs, logic=logic, lid=lid, cavity=cavity, gates=gates,
                comps=comps, vol=vol, airframe=airframe, cgc=cgc,
                simple=logic["simple"] and all(gates["simple"]))


if __name__ == "__main__":
    build()
    for k, v in geometry_report().items():
        print(f"{k:35s} {v}")
