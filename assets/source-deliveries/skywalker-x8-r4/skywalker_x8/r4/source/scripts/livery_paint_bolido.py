"""Paso 3 de la librea "BOLIDO": pintor procedural en 3D (numpy).

Concepto: la X8 como demostrador de reentrada atmosferica, inspirado en el sistema de
proteccion termica del transbordador espacial (NASA, 1981-2011): vientre de losetas ceramicas
negras de vidrio curado por reaccion, una por una, con tonos distintos segun su edad y las
reemplazadas en negro brillante; losetas blancas en la transicion; mantas aislantes acolchadas
color crema arriba; bordes de ataque y cono de nariz de carbono-carbono gris en paneles con
juntas en T; rellenos de juntas blancos que asoman; fieltro blanco en los elevones; escudo
termico de metal con colores de revenido alrededor del motor.
Encima, el uso: blanqueo y estelas del plasma en la panza (mas fuerte en la nariz y los bordes
de ataque), manchas color tabaco donde el calor se colo a las mantas, desconchones que dejan ver
la silice blanca, una loseta que falta con el fieltro y el adhesivo a la vista, marcas de
inspeccion con lapiz graso, numeros de pieza diminutos en las losetas, dianas de fotogrametria
de ensayo en vuelo, rotulos de rescate y advertencia en espanol y lentes de luces de navegacion (sin emision).

Todo es original: el programa, los nombres (BOLIDO, VR-08) y el emblema son inventados.
Cada texel conoce su posicion 3D, su normal, la pieza y la region (mapas horneados), asi que
las losetas, las mantas y los rotulos se dibujan en el espacio del avion, sin costuras de UV.

  python livery_paint_bolido.py <carpeta_trabajo> <carpeta_texturas> [metadata.json] [submuestreo]

Escribe x8_bolido_{base_color, roughness, metallic, emission, height, iridescence, coat,
heat}.png y las mascaras en <carpeta_texturas>/masks/. (heat, iridescence y coat son solo
para los renders.) Con --no-markings solo escribe layers/x8_bolido_paint_base.png (la misma
pintura sin rotulos ni emblema); paint_layers.py deriva de ahi las capas editables (r4).
"""
import sys, os, json, math, time, gc, resource
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
WORK, TEX = (os.path.abspath(a) for a in argv[:2])
META = next((os.path.abspath(a) for a in argv[2:] if a.endswith(".json")),
            os.path.join(WORK, "build_info.json"))
SUB = next((int(a) for a in argv[2:] if a.isdigit()), 1)
NO_MARKS = "--no-markings" in argv          # r4: capa base sin rotulos ni insignias
PREFIX = "x8_bolido_"
os.makedirs(os.path.join(TEX, "masks"), exist_ok=True)
T0 = time.time()
import x8_skywalker_blender as X            # funciones de planta del maestro (LE, TE, tapa)

_m = json.load(open(META))
D0 = _m["datum_D0"]["master_mm"] if "datum_D0" in _m else _m["D0_master_mm"]
XD0, ZD0 = D0["x_from_nose"], D0["z"]
FONT_DIR = "/usr/share/fonts/truetype/dejavu"
if not os.path.isdir(FONT_DIR):
    import matplotlib
    FONT_DIR = os.path.join(os.path.dirname(matplotlib.__file__), "mpl-data", "fonts", "ttf")
F_BOLD = os.path.join(FONT_DIR, "DejaVuSans-Bold.ttf")
F_MONO = os.path.join(FONT_DIR, "DejaVuSansMono-Bold.ttf")
F_COND = os.path.join(FONT_DIR, "DejaVuSansCondensed-Bold.ttf")
if not os.path.exists(F_COND):
    F_COND = F_BOLD


def log(*a):
    rss = int(open("/proc/self/statm").read().split()[1]) * os.sysconf("SC_PAGE_SIZE") / 1e9
    print(f"[{time.time() - T0:6.1f}s {rss:4.1f}GB]", *a, flush=True)


# ------------------------------------------------------------------------------- datos
Pm = np.load(os.path.join(WORK, "P.npy"), mmap_mode="r")
Nm = np.load(os.path.join(WORK, "N.npy"), mmap_mode="r")
IDz = np.load(os.path.join(WORK, "ID.npz"))
baked = IDz["baked"][::SUB, ::SUB]
RES = baked.shape[0]
idx = np.flatnonzero(baked)
n = idx.size
P = np.asarray(Pm[::SUB, ::SUB]).reshape(-1, 3)[idx].astype(np.float32)
Nn = np.asarray(Nm[::SUB, ::SUB]).reshape(-1, 3)[idx].astype(np.float32)
part = IDz["part"][::SUB, ::SUB].reshape(-1)[idx]
reg = IDz["region"][::SUB, ::SUB].reshape(-1)[idx]
x, y, z = P[:, 0], P[:, 1], P[:, 2]
nx, ny, nz = Nn[:, 0], Nn[:, 1], Nn[:, 2]
s = x * 1000.0                      # envergadura (mm, + derecha)
sa = np.abs(s)
xn = XD0 - y * 1000.0               # mm desde la nariz
zm = z * 1000.0 + ZD0               # altura del maestro (mm)
side = np.where(s >= 0, 1.0, -1.0).astype(np.float32)
log(f"texeles {n} de {RES}x{RES}")

WING = (part == 3) | (part == 4)
ELEV = (part == 5) | (part == 6)
CORE = part == 1
HATCH = part == 2
DOOR = (part == 7) | (part == 8)
PROP = part == 9
BODY = CORE | HATCH | DOOR
FIN = WING | ELEV
WINGLET = FIN & (sa > 960)
LEs = X.LE(np.minimum(sa, 935.0)).astype(np.float32)
TEs = X.TE(np.minimum(sa, 935.0)).astype(np.float32)
chord = np.maximum(TEs - LEs, 1.0)
u = (xn - LEs) / chord                                 # fraccion de cuerda (planta)

# ------------------------------------------------------------------------------- ruido
U32 = np.uint32


CHUNK = 1 << 21                           # trozos de ~2 M texeles: limita la memoria temporal


def _hash3(ix, iy, iz, seed):
    with np.errstate(over="ignore"):
        h = (np.asarray(ix).astype(np.int64).astype(U32) * U32(0x8DA6B343)) ^ \
            (np.asarray(iy).astype(np.int64).astype(U32) * U32(0xD8163841)) ^ \
            (np.asarray(iz).astype(np.int64).astype(U32) * U32(0xCB1AB31F)) ^ \
            U32((seed * 0x9E3779B1) & 0xFFFFFFFF)
        h ^= h >> U32(13)
        h *= U32(0x5BD1E995)
        h ^= h >> U32(15)
    return h.astype(np.float32) * np.float32(1.0 / 4294967295.0)


def hash3(ix, iy, iz, seed=0):
    shp = np.broadcast(np.asarray(ix), np.asarray(iy), np.asarray(iz)).shape
    size = int(np.prod(shp)) if shp else 1
    if size <= CHUNK:
        return _hash3(ix, iy, iz, seed)
    a, b, c = (np.broadcast_to(np.asarray(v), shp).reshape(-1) for v in (ix, iy, iz))
    out = np.empty(size, np.float32)
    for k in range(0, size, CHUNK):
        out[k:k + CHUNK] = _hash3(a[k:k + CHUNK], b[k:k + CHUNK], c[k:k + CHUNK], seed)
    return out.reshape(shp)


def _vnoise(px, py, pz, seed):
    fx, fy, fz = np.floor(px), np.floor(py), np.floor(pz)
    tx, ty, tz = px - fx, py - fy, pz - fz
    tx, ty, tz = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty), tz * tz * (3 - 2 * tz)
    out = np.zeros(np.shape(px), np.float32)
    for dx in (0, 1):
        wx = tx if dx else 1 - tx
        for dy in (0, 1):
            wy = ty if dy else 1 - ty
            for dz in (0, 1):
                wz = tz if dz else 1 - tz
                out += wx * wy * wz * _hash3(fx + dx, fy + dy, fz + dz, seed)
    return out


def vnoise(px, py, pz, seed=0):
    px, py, pz = (np.asarray(v, np.float32) for v in (px, py, pz))
    if px.size <= CHUNK:
        return _vnoise(px, py, pz, seed)
    out = np.empty(px.shape, np.float32)
    a, b, c, o = px.reshape(-1), py.reshape(-1), pz.reshape(-1), out.reshape(-1)
    for k in range(0, a.size, CHUNK):
        o[k:k + CHUNK] = _vnoise(a[k:k + CHUNK], b[k:k + CHUNK], c[k:k + CHUNK], seed)
    return out


def fbm(px, py, pz, octaves=4, seed=0, lac=2.03, gain=0.5):
    px, py, pz = (np.asarray(v, np.float32) for v in (px, py, pz))
    out = np.empty(px.shape, np.float32)
    a_, b_, c_, o_ = px.reshape(-1), py.reshape(-1), pz.reshape(-1), out.reshape(-1)
    for k in range(0, max(a_.size, 1), CHUNK):
        sl = slice(k, k + CHUNK)
        a, f, norm = 1.0, 1.0, 0.0
        tot = np.zeros(a_[sl].shape, np.float32)
        for o in range(octaves):
            tot += a * _vnoise(a_[sl] * f, b_[sl] * f, c_[sl] * f, seed + 17 * o)
            norm += a
            a *= gain
            f *= lac
        o_[sl] = tot / norm
    return out


def sstep(e0, e1, v):
    t = np.clip((np.asarray(v, np.float32) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def hexcol(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


def mix(a, b, t):
    """Mezcla de colores: a y b (3,) o (n, 3); t escalar o (n,)."""
    t = np.asarray(t, np.float32)
    if t.ndim == 1:
        t = t[:, None]
    return np.asarray(a, np.float32) * (1 - t) + np.asarray(b, np.float32) * t


def paint(mask, color, alpha, rough=None, metal=None, h=None, e=None):
    """Mezcla una capa en los texeles de mask (bool o indices) con opacidad alpha."""
    ii = np.flatnonzero(mask) if mask.dtype == bool else mask
    if ii.size == 0:
        return
    a = np.broadcast_to(np.asarray(alpha, np.float32), (ii.size,)) if np.ndim(alpha) == 0 else alpha
    a = np.clip(a, 0, 1).astype(np.float32)
    c = np.asarray(color, np.float32)
    c = np.broadcast_to(c, (ii.size, 3)) if c.ndim == 1 else c
    COL[ii] = COL[ii] * (1 - a[:, None]) + c * a[:, None]
    if rough is not None:
        RGH[ii] = RGH[ii] * (1 - a) + np.asarray(rough, np.float32) * a
    if metal is not None:
        MET[ii] = MET[ii] * (1 - a) + np.asarray(metal, np.float32) * a
    if h is not None:
        HGT[ii] = HGT[ii] * (1 - a) + np.asarray(h, np.float32) * a
    if e is not None:
        ec = np.asarray(e, np.float32)
        ec = np.broadcast_to(ec, (ii.size, 3)) if ec.ndim == 1 else ec
        EMI[ii] = np.maximum(EMI[ii], ec * a[:, None])


COL = np.zeros((n, 3), np.float32)
RGH = np.full(n, 0.5, np.float32)
MET = np.zeros(n, np.float32)
HGT = np.zeros(n, np.float32)            # mm
EMI = np.zeros((n, 3), np.float32)
IRI = np.zeros(n, np.float32)            # pelicula delgada (renders: colores de revenido)
COAT = np.zeros(n, np.float32)           # barniz (renders: losetas nuevas, lentes)
HEAT = np.zeros(n, np.float32)           # incandescencia de reentrada (solo renders)
MARK_A = np.zeros(n, np.float32)         # cobertura de rotulos/marcas (capa markings)
INS_A = np.zeros(n, np.float32)          # cobertura de insignias (capa insignia: emblema)


def accumulate(acc, jj, a):
    acc[jj] = 1 - (1 - acc[jj]) * (1 - np.clip(a, 0, 1))

# ------------------------------------------------------------------------------- 1 rejillas
log("rejillas de losetas y mantas por zona")
T = 22.0                                  # loseta negra (HRSI a escala)
GAP = 0.55                                # junta (mm)
Q = 11.0                                  # cuadro del acolchado de las mantas
k_le = (float(X.LE(878)) - float(X.LE(300))) / (878 - 300)      # flecha del borde de ataque
k_hg = (float(X.hinge_x(878)) - float(X.hinge_x(300))) / (878 - 300)
L1, L2 = math.hypot(1, k_le), math.hypot(1, k_hg)
proj_side = np.abs(nx) > np.abs(nz)
ZK = np.zeros(n, np.int8)                 # 0 sin rejilla (helice)
A = np.zeros(n, np.float32)
B = np.zeros(n, np.float32)
front = np.abs(ny) > np.maximum(np.abs(nx), np.abs(nz))       # caras de frente (nariz, cola)
m_ = BODY & ~proj_side & ~front
ZK[m_], A[m_], B[m_] = np.where(nz[m_] < 0, 1, 10), xn[m_], s[m_]
m_ = BODY & proj_side & ~front
ZK[m_], A[m_], B[m_] = 2 + (s[m_] > 0), xn[m_], zm[m_]
m_ = BODY & front
ZK[m_], A[m_], B[m_] = np.where(ny[m_] > 0, 17, 18), s[m_], zm[m_]
m_ = WING & ~WINGLET
ZK[m_] = np.where(nz[m_] < 0, 4, 11) + (s[m_] > 0)
A[m_] = (sa[m_] + xn[m_] * k_le) / L1           # a lo largo del borde de ataque
B[m_] = (-sa[m_] * k_le + xn[m_]) / L1          # perpendicular, hacia atras
m_ = ELEV & ~WINGLET
ZK[m_] = np.where(nz[m_] < 0, 6, 13) + (s[m_] > 0)
A[m_] = (sa[m_] + xn[m_] * k_hg) / L2
B[m_] = (-sa[m_] * k_hg + xn[m_]) / L2
m_ = WINGLET
ZK[m_], A[m_], B[m_] = np.where(side[m_] * nx[m_] > 0, 8, 15) + (s[m_] > 0), xn[m_], zm[m_]
GRID = ZK > 0

# celdas de 22 mm: indice global y estadisticas por celda
I = np.floor(A / T).astype(np.int64)
J = np.floor(B / T).astype(np.int64)
fu = (A / T - I).astype(np.float32)
fv = (B / T - J).astype(np.float32)
de = (np.minimum(np.minimum(fu, 1 - fu), np.minimum(fv, 1 - fv)) * T).astype(np.float32)   # mm al borde
OFF, SHAPE, CELL = {}, {}, np.full(n, -1, np.int32)
tot = 0
for k in range(1, 19):
    mk = ZK == k
    if not mk.any():
        continue
    i0, i1, j0, j1 = I[mk].min() - 1, I[mk].max() + 1, J[mk].min() - 1, J[mk].max() + 1
    ni, nj = int(i1 - i0 + 1), int(j1 - j0 + 1)
    OFF[k], SHAPE[k] = (tot, i0, j0), (ni, nj)
    CELL[mk] = tot + (I[mk] - i0) * nj + (J[mk] - j0)
    tot += ni * nj
NC = tot
cnt = np.bincount(CELL[GRID], minlength=NC).astype(np.float32)
safe = np.maximum(cnt, 1)


def cmean(v):
    return np.bincount(CELL[GRID], weights=v[GRID], minlength=NC) / safe


c_nz, c_xn, c_u, c_zm = cmean(nz), cmean(xn), cmean(u), cmean(zm)
c_hatch = cmean(HATCH.astype(np.float32))
c_door = cmean(DOOR.astype(np.float32))
c_te = cmean(np.where(FIN, TEs - xn, 999).astype(np.float32))
# cuerda local de los winglets por franja de altura
wl = np.flatnonzero(WINGLET)
zb = np.clip(((zm[wl] - 20) / 4).astype(int), 0, 60)
le_w = np.full(61, 1e9)
te_w = np.full(61, -1e9)
np.minimum.at(le_w, zb, xn[wl])
np.maximum.at(te_w, zb, xn[wl])
le_w = np.minimum.accumulate(le_w[::-1])[::-1]       # rellenar franjas vacias
for arr in (le_w, te_w):
    ok = np.abs(arr) < 1e8
    arr[~ok] = np.interp(np.flatnonzero(~ok), np.flatnonzero(ok), arr[ok])
uw = np.zeros(n, np.float32)
uw[wl] = (xn[wl] - le_w[zb]) / np.maximum(te_w[zb] - le_w[zb], 1)
c_uw = cmean(uw)

# clase por celda: 1 losa negra (HRSI), 2 losa blanca (LRSI), 3 manta (FIB), 4 fieltro (FRSI)
CK = np.zeros(NC, np.int64)
for k, (o, i0, j0) in OFF.items():
    ni, nj = SHAPE[k]
    CK[o:o + ni * nj] = k
thr = -0.15 + 1.3 * sstep(150, 95, c_xn)            # el negro sube por la nariz
CLS = np.zeros(NC, np.int8)
body_k = np.isin(CK, (1, 2, 3, 10, 17, 18))
CLS[body_k & (c_nz < thr)] = 1
CLS[body_k & (c_nz >= thr)] = 2
CLS[body_k & (c_nz >= thr) & (CK == 10) & (c_xn > 175) & (c_nz > 0.35)] = 3
CLS[body_k & (c_hatch > 0.5)] = 3
CLS[body_k & (c_xn > 600) & (CK == 10) & (c_nz > 0.2)] = 3
wk = np.isin(CK, (4, 5, 11, 12))
CLS[wk & (c_nz < 0)] = 1
CLS[wk & (c_nz >= 0)] = 2
CLS[wk & (c_nz >= 0) & (c_u > 0.24)] = 3
ek = np.isin(CK, (6, 7, 13, 14))
CLS[ek & (c_nz < 0)] = 1
CLS[ek & (c_nz >= 0)] = 4
CLS[ek & (c_nz >= 0) & (c_te < 15)] = 1
lk = np.isin(CK, (8, 9, 15, 16))
CLS[lk] = 3
CLS[lk & (c_uw < 0.30)] = 1
CLS[lk & (c_uw >= 0.30) & (c_zm < 70)] = 2
CLS[cnt == 0] = 0
cls = np.where(GRID, CLS[np.maximum(CELL, 0)], 0).astype(np.int8)


def neighbor_class():
    """Clase de la celda vecina al otro lado del borde mas cercano de cada texel."""
    e = np.argmin(np.stack([fu, 1 - fu, fv, 1 - fv]), axis=0)
    di = np.array([-1, 1, 0, 0])[e]
    dj = np.array([0, 0, -1, 1])[e]
    out = np.zeros(n, np.int8)
    for k, (o, i0, j0) in OFF.items():
        ni, nj = SHAPE[k]
        mk = np.flatnonzero(ZK == k)
        ii = I[mk] - i0 + di[mk]
        jj = J[mk] - j0 + dj[mk]
        ok = (ii >= 0) & (ii < ni) & (jj >= 0) & (jj < nj)
        out[mk[ok]] = CLS[o + ii[ok] * nj + jj[ok]]
    return out, e


NB, EDGE = neighbor_class()
# losetas blancas de 44 mm (2x2): bordes propios y bordes hacia otra clase
I2, J2 = np.floor(A / (2 * T)), np.floor(B / (2 * T))
fu2, fv2 = A / (2 * T) - I2, B / (2 * T) - J2
de2 = np.minimum(np.minimum(fu2, 1 - fu2), np.minimum(fv2, 1 - fv2)) * 2 * T
de_L = np.where(NB != 2, np.minimum(de, de2), de2)
# distancia (mm) a la zona negra por zona, para las manchas de calor en el blanco
DIST_H = np.full(n, 999.0, np.float32)
for k, (o, i0, j0) in OFF.items():
    ni, nj = SHAPE[k]
    G = CLS[o:o + ni * nj].reshape(ni, nj)
    if not (G == 1).any():
        continue
    D = ndimage.distance_transform_edt(G != 1) * T
    mk = np.flatnonzero(ZK == k)
    DIST_H[mk] = ndimage.map_coordinates(D, [A[mk] / T - i0 - 0.5, B[mk] / T - j0 - 0.5], order=1,
                                         mode="nearest")
log("celdas", NC, "negras", int((CLS == 1).sum()), "blancas", int((CLS == 2).sum()),
    "mantas", int((CLS == 3).sum()), "fieltro", int((CLS == 4).sum()))

# ------------------------------------------------------------------------------- 2 materiales
log("materiales base: losetas, mantas, fieltro")
ch = lambda v, sd: hash3(np.maximum(CELL, 0), CELL * 0 + 7, CELL * 0 + 11, sd)   # azar por celda
r_age, r_tone, r_new, r_step, r_num = (ch(None, k) for k in (1, 2, 3, 4, 5))
clus = cmean(fbm(x * 9, y * 9, z * 9, 3, seed=7))[np.maximum(CELL, 0)]          # parches
fresh = ((r_new < 0.05) | ((clus > 0.6) & (r_new < 0.55))).astype(np.float32)

# calor de reentrada: fuerte en la nariz y en los bordes de ataque, se apaga hacia atras
d_le = np.maximum(xn - LEs, 0)
heat_flux = np.maximum(np.exp(-xn / 230.0), np.exp(-d_le / 140.0) * (FIN | (CORE & (sa > 100))))
heat_flux = np.where(WINGLET, np.exp(-np.maximum(uw, 0) * 3.0), heat_flux).astype(np.float32)
bleach_flux = np.maximum(0.5 * np.exp(-xn / 230.0), np.exp(-d_le / 140.0) * (FIN | (CORE & (sa > 100))))
streak = fbm(x * 520, y * 22, z * 520, 4, seed=13)                 # estelas a lo largo del flujo
streak2 = fbm(x * 1500, y * 60, z * 1500, 3, seed=15)

# --- negro HRSI
H = cls == 1
hi = np.flatnonzero(H)
NEW, BASE, AGED, BLEACH = hexcol("#08090b"), hexcol("#131417"), hexcol("#2f3236"), hexcol("#666a6f")
patch = cmean(fbm(x * 6, y * 6, z * 6, 3, seed=19))[np.maximum(CELL, 0)][hi]       # zonas de ~15 cm
age = (0.12 * r_age[hi] + 0.28 * (r_age[hi] > 0.96) + 0.22 * sstep(0.5, 0.75, patch)) * (1 - fresh[hi])
b_heat = bleach_flux[hi] * (0.45 + 0.75 * (streak[hi] - 0.5) + 0.25 * (streak2[hi] - 0.5))
bleach = np.clip(age + b_heat * 0.62 * (1 - 0.7 * fresh[hi]), 0, 1)
tile_col = mix(BASE, AGED, sstep(0.08, 0.5, bleach))
tile_col = mix(tile_col, BLEACH, sstep(0.45, 1.0, bleach))
tile_col = mix(tile_col, NEW, fresh[hi])
tile_col *= (0.95 + 0.1 * r_tone[hi])[:, None]
COL[hi] = tile_col
RGH[hi] = 0.30 + 0.35 * bleach - 0.12 * fresh[hi]
COAT[hi] = 0.6 * fresh[hi]
HGT[hi] = (r_step[hi] - 0.5) * 0.16                              # escalon entre losetas
# junta y canto redondeado
grv = 1 - sstep(GAP * 0.5, GAP * 0.5 + 0.9, de[hi])
HGT[hi] -= 0.38 * grv
COL[hi] = mix(COL[hi], hexcol("#040405"), sstep(GAP * 0.5 + 0.15, GAP * 0.5 - 0.05, de[hi]))
RGH[hi] = np.where(de[hi] < GAP * 0.5, 0.75, RGH[hi])
edge_wear = np.exp(-((de[hi] - GAP * 0.5 - 0.35) / 0.35) ** 2) * (0.3 + 0.7 * age)
COL[hi] = mix(COL[hi], hexcol("#55585d"), 0.35 * edge_wear)

# --- blanco LRSI (losetas de 44 mm)
L = cls == 2
li = np.flatnonzero(L)
r2t = hash3(I2[li] + ZK[li].astype(np.int64) * 1000, J2[li], J2[li] * 0 + 3, 21)
LR0, LR1 = hexcol("#e4e0d5"), hexcol("#cfc9ba")
COL[li] = mix(LR0, LR1, 0.25 + 0.6 * r2t) * (0.97 + 0.05 * fbm(x[li] * 300, y[li] * 300, z[li] * 300, 2, seed=23))[:, None]
RGH[li] = 0.42 + 0.1 * r2t
HGT[li] = (r2t - 0.5) * 0.12
grvL = 1 - sstep(GAP * 0.5, GAP * 0.5 + 0.9, de_L[li])
HGT[li] -= 0.34 * grvL
COL[li] = mix(COL[li], hexcol("#6f6b63"), sstep(GAP * 0.5 + 0.2, GAP * 0.5 - 0.05, de_L[li]))

# --- mantas FIB (acolchado de 11 mm, paneles de 10 x 8 cuadros)
F = cls == 3
fi = np.flatnonzero(F)
qa, qb = A[fi] / Q, B[fi] / Q
qi, qj = np.floor(qa), np.floor(qb)
qu, qv = qa - qi, qb - qj
pid_a, pid_b = np.floor(qi / 10), np.floor(qj / 8)
r_pan = hash3(pid_a + ZK[fi].astype(np.int64) * 100, pid_b, pid_b * 0 + 5, 31)
FB0, FB1, FB2 = hexcol("#ebe5d4"), hexcol("#ddd3bb"), hexcol("#f2efe6")
fcol = mix(FB0, FB1, sstep(0.3, 1.0, r_pan))
fcol = mix(fcol, FB2, (r_pan < 0.12).astype(np.float32) * 0.8)              # mantas nuevas
weave = 0.5 + 0.5 * np.sin(A[fi] * 9.0) * np.sin(B[fi] * 9.0)
fcol *= (0.965 + 0.035 * weave)[:, None]
pillow = (np.sin(np.pi * qu) * np.sin(np.pi * qv)) ** 0.55
HGT[fi] = 0.30 * pillow
qe = np.minimum(np.minimum(qu, 1 - qu), np.minimum(qv, 1 - qv)) * Q
stitch_line = 1 - sstep(0.18, 0.42, qe)
dash = (np.mod(np.where(np.minimum(qu, 1 - qu) < np.minimum(qv, 1 - qv), B[fi], A[fi]), 1.6) < 0.9)
HGT[fi] -= 0.10 * stitch_line
fcol = mix(fcol, fcol * 0.78, stitch_line * dash * 0.55)
fcol = mix(fcol, fcol * 0.88, (1 - pillow) * 0.35)                          # sombra del acolchado
pe = np.minimum(np.minimum(np.mod(qa, 10), 10 - np.mod(qa, 10)),
                np.minimum(np.mod(qb, 8), 8 - np.mod(qb, 8))) * Q
pe = np.where(NB[fi] != 3, np.minimum(pe, de[fi]), pe)                      # borde hacia losetas
seam_f = 1 - sstep(0.4, 1.6, pe)
HGT[fi] -= 0.22 * seam_f
fcol = mix(fcol, hexcol("#8f8676"), 0.65 * (1 - sstep(0.2, 0.8, pe)))
COL[fi] = fcol
RGH[fi] = 0.86

# --- fieltro FRSI (elevones arriba)
S_ = cls == 4
si = np.flatnonzero(S_)
fib = fbm(x[si] * 2500, y[si] * 2500, z[si] * 2500, 2, seed=41)
COL[si] = mix(hexcol("#ece9e0"), hexcol("#d8d3c6"), 0.4 * fib + 0.3 * hash3(np.floor(A[si] / 130), ZK[si], ZK[si] * 0, 43))
RGH[si] = 0.9
HGT[si] = 0.04 * fib
pe_s = np.minimum(np.mod(A[si], 130.0), 130.0 - np.mod(A[si], 130.0))
pe_s = np.where(NB[si] != 4, np.minimum(pe_s, de[si]), pe_s)
paint(si, hexcol("#9b9486"), 1 - sstep(0.3, 1.0, pe_s), h=HGT[si] - 0.12)

del I, J, I2, J2, fu2, fv2, de2, de_L, NB, r_tone, r_step, streak2, chord      # memoria
gc.collect()

# ------------------------------------------------------------------------------- 3 carbono-carbono
log("carbono-carbono en bordes de ataque y nariz, escudo del motor, regiones")
le_band = np.where(nz < 0, np.float32(21.0), np.float32(13.0))
RCC = ((FIN & ~WINGLET & (sa > 236) & (ny > 0.42) & (d_le < le_band))
       | (CORE & (xn < 30))
       | (CORE & (sa > 70) & (ny > 0.62) & (d_le < 18))
       | (WINGLET & (ny > 0.5) & (uw < 0.05)))
RCC &= (reg == 0)
ri = np.flatnonzero(RCC)
pan_a = np.where(FIN[ri], A[ri], 0.0)
pan = np.floor(pan_a / 85.0)
r_rc = hash3(pan, ZK[ri].astype(np.float32), pan * 0, 51)
mott = fbm(x[ri] * 380, y[ri] * 380, z[ri] * 380, 4, seed=53)
RC0, RC1, RC2 = hexcol("#5c5f63"), hexcol("#7b7e82"), hexcol("#9a9c9d")
rcol = mix(RC0, RC1, sstep(0.25, 0.75, mott))
rcol = mix(rcol, RC2, sstep(0.62, 0.8, fbm(x[ri] * 90, y[ri] * 90, z[ri] * 90, 3, seed=55)) * 0.6)
rcol *= (0.94 + 0.12 * r_rc)[:, None]
pit = (vnoise(x[ri] * 4000, y[ri] * 4000, z[ri] * 4000, seed=57) > 0.86).astype(np.float32)
rcol = mix(rcol, hexcol("#3e4042"), pit * 0.6)
COL[ri] = rcol
RGH[ri] = 0.62 + 0.1 * mott
MET[ri] = 0.0
HGT[ri] = 0.05 * mott - 0.12 * pit
tseal = np.minimum(np.mod(pan_a, 85.0), 85.0 - np.mod(pan_a, 85.0))
ts = (1 - sstep(0.35, 0.9, tseal)) * FIN[ri]
paint(ri, hexcol("#2a2c2e"), ts, h=HGT[ri] - 0.25, rough=0.7)
# junta RCC / losetas: relleno blanco
rc_edge = np.flatnonzero(FIN & ~RCC & (sa > 236) & ~WINGLET & (np.abs(d_le - le_band) < 1.4) & (reg == 0))
paint(rc_edge, hexcol("#e9e6dc"), 1 - sstep(0.4, 1.2, np.abs(d_le[rc_edge] - le_band[rc_edge] - 0.3)),
      rough=0.95, h=0.2)
# junta del cono de nariz
nc = np.flatnonzero(CORE & (np.abs(xn - 30) < 1.5))
paint(nc, hexcol("#222324"), 1 - sstep(0.3, 1.2, np.abs(xn[nc] - 30)), h=-0.2)

# escudo termico metalico de la cola (colores de revenido)
MT = CORE & (xn > 708) & (reg == 0)
mi = np.flatnonzero(MT)
tt = sstep(708, 796, xn[mi]) + 0.18 * (fbm(x[mi] * 160, y[mi] * 40, z[mi] * 160, 3, seed=61) - 0.5)
TEMPER = [hexcol(c) for c in ("#9a9b9c", "#c8b06a", "#b07a3c", "#7a3f6e", "#3d4f9a", "#5c7fa8", "#8c9196")]
tq = np.clip(tt, 0, 0.999) * (len(TEMPER) - 1)
k0 = np.floor(tq).astype(int)
fr = tq - k0
tcol = np.stack(TEMPER)[k0] * (1 - fr)[:, None] + np.stack(TEMPER)[np.minimum(k0 + 1, len(TEMPER) - 1)] * fr[:, None]
COL[mi] = tcol
MET[mi] = 1.0
RGH[mi] = 0.32 + 0.12 * fbm(x[mi] * 700, y[mi] * 700, z[mi] * 700, 2, seed=63)
IRI[mi] = 0.12
HGT[mi] = 0.0
riv = np.flatnonzero(CORE & (np.abs(xn - 713) < 2.5))
rv_t = np.mod(np.arctan2(zm[riv] - 10, s[riv]) * 40 / np.pi, 1.0)
paint(riv, hexcol("#b9bcbf"), (np.abs(rv_t - 0.5) < 0.18) * (np.abs(xn[riv] - 713) < 1.1), rough=0.3, metal=1.0, h=0.15)
paint(riv, hexcol("#2c2d2f"), np.exp(-((xn[riv] - 709.5) / 0.6) ** 2), h=-0.2)

# regiones de la malla
tp = np.flatnonzero(reg == 1)                                  # sello de bisagra: tela negra
tw = 0.5 + 0.5 * np.sign(np.sin(A[tp] * 3.2) * np.sin(B[tp] * 3.2))
paint(tp, mix(hexcol("#121314"), hexcol("#1d1e20"), tw), np.ones(tp.size), rough=0.8, metal=0.0, h=0.03 * tw)
cv = np.flatnonzero(reg == 2)                                  # tapas de servo: panel de acceso
paint(cv, hexcol("#101113"), np.ones(cv.size), rough=0.35, metal=0.0, h=0.05)
for sd in (-1, 1):
    jj = np.flatnonzero((reg == 2) & (side == sd))
    if jj.size == 0:
        continue
    x0, x1 = xn[jj].min() + 4, xn[jj].max() - 4
    s0, s1 = sa[jj].min() + 4, sa[jj].max() - 4
    border = np.minimum.reduce([xn[jj] - x0 + 4, x1 + 4 - xn[jj], sa[jj] - s0 + 4, s1 + 4 - sa[jj]])
    paint(jj, hexcol("#e8e4d8"), 1 - sstep(0.5, 1.3, border), rough=0.95, h=0.25)   # relleno
    for cx_ in (x0, (x0 + x1) / 2, x1):
        for cs_ in (s0, s1):
            d = np.hypot(xn[jj] - cx_, sa[jj] - cs_)
            paint(jj, hexcol("#a9aeb3"), 1 - sstep(1.3, 1.7, d), rough=0.3, metal=1.0, h=0.12)
            paint(jj, hexcol("#2a2e33"), (1 - sstep(0.35, 0.55, d)), h=0.0)
rb = np.flatnonzero(reg == 3)                                  # costilla y cuernos: aluminio
paint(rb, hexcol("#9ea3a8"), np.ones(rb.size), rough=0.42, metal=1.0, h=0.0)
rib_r = np.flatnonzero((reg == 3) & (sa < 245))
rt = np.mod(xn[rib_r], 14.0)
paint(rib_r, hexcol("#5a5e63"), np.exp(-((rt - 7) / 0.9) ** 2) * 0.8, h=0.1)
pi_ = np.flatnonzero(PROP)                                     # helice: carbono 2x2 sarga
rp = np.hypot(x[pi_], z[pi_]) * 1000
ta, tb = rp / 1.6, (y[pi_] * 1000 + rp * 0.15) / 1.6
twill = (np.mod(np.floor(ta) + np.floor(tb), 4) < 2).astype(np.float32)
paint(pi_, mix(hexcol("#0d0e10"), hexcol("#26282c"), twill * 0.8), np.ones(pi_.size), rough=0.25, metal=0.0,
      h=0.03 * twill)
COAT[pi_] = 0.9
paint(pi_, hexcol("#e8b923"), (rp > 132).astype(np.float32), rough=0.4)
paint(pi_, hexcol("#141414"), ((rp > 129.5) & (rp < 132)).astype(np.float32), rough=0.4)
paint(pi_, hexcol("#8f9296"), (rp < 26).astype(np.float32), rough=0.55)          # cono

# ------------------------------------------------------------------------------- 4 detalles
log("detalles de losetas: numeros, agujeros, golpes, rellenos, loseta faltante")
GL = []
gfont = ImageFont.truetype(F_MONO, 40)
for ch_ in "0123456789":
    im = Image.new("L", (26, 44), 0)
    ImageDraw.Draw(im).text((1, -2), ch_, font=gfont, fill=255)
    GL.append(np.asarray(im, np.float32) / 255)
GL = np.stack(GL)
numbered = H & (r_num < 0.45)
bx0, bx1, by0, by1 = 0.16, 0.84, 0.60, 0.80
inb = numbered & (fu > bx0) & (fu < bx1) & (fv > by0) & (fv < by1)
nbi = np.flatnonzero(inb)
gx_ = (fu[nbi] - bx0) / (bx1 - bx0) * 6
kc = np.floor(gx_).astype(np.int64)
gx_ = gx_ - kc
gy_ = 1 - (fv[nbi] - by0) / (by1 - by0)
dig = (hash3(CELL[nbi], kc, kc * 0 + 9, 71) * 10).astype(np.int64) % 10
dig = np.where(kc == 0, 3 + (hash3(CELL[nbi], 0, 1, 73) > 0.5), dig)            # serie 3xxxxx/4xxxxx
gv = GL[dig, np.clip((gy_ * 43).astype(int), 0, 43), np.clip((gx_ * 25).astype(int), 0, 25)]
paint(nbi, hexcol("#d8d8d2"), gv * 0.55 * (0.5 + 0.5 * (COL[nbi, 0] < 0.2)), rough=0.5)
# agujeros de impermeabilizacion (uno o dos por loseta)
for kk in (0, 1):
    cxh = 0.25 + 0.5 * ch(None, 80 + kk)[hi]
    cyh = 0.18 + 0.3 * ch(None, 90 + kk)[hi]
    dh = np.hypot(fu[hi] - cxh, fv[hi] - cyh) * T
    on = (ch(None, 100 + kk)[hi] < (0.8 if kk == 0 else 0.35))
    paint(hi, hexcol("#9c9d9b"), (1 - sstep(0.22, 0.4, dh)) * on, h=HGT[hi] - 0.05)
# golpes que dejan ver la silice blanca
dg = H & (ch(None, 110) < 0.06)
dgi = np.flatnonzero(dg)
ang_d = ch(None, 111)[dgi] * 4
ex_ = np.where(ang_d < 1, 0.02, np.where(ang_d < 2, 0.98, ch(None, 112)[dgi]))
ey_ = np.where(ang_d < 2, ch(None, 113)[dgi], np.where(ang_d < 3, 0.02, 0.98))
rad = 0.9 + 2.6 * ch(None, 114)[dgi] ** 2
dd = np.hypot(fu[dgi] - ex_, fv[dgi] - ey_) * T
rough_r = rad * (0.75 + 0.5 * vnoise(x[dgi] * 2500, y[dgi] * 2500, z[dgi] * 2500, seed=115))
ding = 1 - sstep(rough_r - 0.25, rough_r + 0.1, dd)
paint(dgi, hexcol("#efeee8"), ding, rough=0.97, h=HGT[dgi] - 0.45 * ding)
paint(dgi, hexcol("#1b1b1c"), np.exp(-((dd - rough_r) / 0.25) ** 2) * 0.5)
COAT[dgi] *= 1 - ding
# rellenos de junta blancos que asoman
cand = H & (de < 0.75)
near_door = BODY & (np.abs(xn - 540) < 50) & (sa < 60)
p_gf = np.where(near_door, np.float32(0.35), np.float32(0.03))
eh = hash3(np.maximum(CELL, 0), EDGE.astype(np.int64), EDGE * 0 + 13, 121)
gf = cand & (eh < p_gf)
gfi = np.flatnonzero(gf)
along = np.where(EDGE[gfi] < 2, fv[gfi], fu[gfi])
seg = (along > 0.15 + 0.3 * eh[gfi]) & (along < 0.6 + 0.35 * eh[gfi])
fuzz = vnoise(x[gfi] * 6000, y[gfi] * 6000, z[gfi] * 6000, seed=123)
paint(gfi, hexcol("#f1eee4"), seg * (1 - sstep(0.35 + 0.25 * fuzz, 0.75, de[gfi])), rough=0.98, h=0.35)
# loseta faltante en el intrados izquierdo
tgt = np.flatnonzero((ZK == 4) & H)
pick = tgt[np.argmin(np.abs(sa[tgt] - 430) + np.abs(u[tgt] - 0.45) * 400)]
mc = np.flatnonzero(CELL == CELL[pick])
inner_m = de[mc]
paint(mc, hexcol("#d9d1bb"), np.ones(mc.size), rough=0.95, metal=0.0, h=-1.6)          # fieltro SIP
paint(mc, hexcol("#8d9848"), sstep(4.0, 2.0, inner_m) * 0.85)                              # imprimante
rtv = vnoise(A[mc] * 0.5, B[mc] * 0.5, 0 * A[mc], seed=131)
paint(mc, hexcol("#a8352a"), sstep(0.72, 0.8, rtv) * sstep(3.5, 5.0, inner_m), rough=0.5, h=-1.45)
paint(mc, hexcol("#f2f0e8"), 1 - sstep(0.5, 1.0, inner_m), rough=0.97, h=-0.6)               # cantos de silice
paint(mc, hexcol("#0a0a0b"), np.exp(-((inner_m - 1.15) / 0.3) ** 2) * 0.7)
COAT[mc] = 0
MISSING_CELL = CELL[pick]
# marcas de inspeccion con lapiz graso alrededor de losetas golpeadas
dcells = np.unique(CELL[dgi])
sel_c = dcells[hash3(dcells, dcells * 0 + 1, dcells * 0 + 2, 141) < 0.12]
sel_c = np.append(sel_c, MISSING_CELL)
# anillo: usar celdas vecinas tambien (el circulo sale de la loseta)
for cc in sel_c[:60]:
    mm_ = np.flatnonzero(CELL == cc)
    if mm_.size == 0:
        continue
    ca, cb = A[mm_].mean(), B[mm_].mean()
    k_ = ZK[mm_[0]]
    near = np.flatnonzero((ZK == k_) & (np.abs(A - ca) < T * 1.2) & (np.abs(B - cb) < T * 1.2))
    da_, db_ = A[near] - ca, B[near] - cb
    rr = np.hypot(da_, db_)
    th = np.arctan2(db_, da_)
    hc = hash3(cc, 3, 5, 143)
    R0 = T * (0.62 + 0.12 * hc) * (1 + 0.06 * np.sin(th * 3 + hc * 9) + 0.03 * np.sin(th * 7))
    ring = np.exp(-((rr - R0) / 0.45) ** 2) * (np.mod(th + hc * 6.3, 2 * np.pi) > 0.35)
    colm = hexcol("#e9cf3c") if hc < 0.7 else hexcol("#eeeeea")
    paint(near, colm, ring * 0.9, rough=0.6, h=HGT[near] + 0.04)

del EDGE, eh, uw, r_age, r_new, r_num, clus, p_gf, tile_col, fcol, grv, age, bleach, patch, edge_wear, dh, pe, TEs
gc.collect()

# ------------------------------------------------------------------------------- 5 calor y uso
log("calor, estelas, manchas, suciedad")
white = L | F | S_
wi = np.flatnonzero(white & ~HATCH)
# manchas color tabaco donde el plasma se colo: junto al negro y detras del carbono
scorch = np.exp(-DIST_H[wi] / 30.0) * (0.55 + 0.9 * (streak[wi] - 0.5))
scorch = np.maximum(scorch, FIN[wi] * np.exp(-np.maximum(d_le[wi] - 13, 0) / 25.0) * (0.4 + 0.8 * (streak[wi] - 0.5)))
scorch = np.clip(scorch, 0, 1) * sstep(0.3, 0.6, fbm(x[wi] * 60, y[wi] * 14, z[wi] * 60, 3, seed=151))
paint(wi, hexcol("#9a7448"), scorch * 0.55, rough=0.8)
paint(wi, hexcol("#5f4630"), sstep(0.55, 0.95, scorch) * 0.35)
# hollin gris detras de juntas y del sello de bisagra
soot = np.zeros(n, np.float32)
soot[wi] = sstep(0.62, 0.9, streak[wi]) * 0.18
hinge_d = np.abs(xn - X.hinge_x(np.clip(sa, 242, 878)).astype(np.float32))
soot = np.maximum(soot, (FIN & (nz > 0) & (sa > 236)) * np.exp(-(hinge_d / 9.0) ** 2) * 0.45)
paint(np.arange(n), hexcol("#3b3935"), soot * (white | (reg == 1)) * sstep(0.3, 0.7, fbm(x * 200, y * 30, z * 200, 3, seed=153)))
# polvo y manos de los tecnicos sobre las mantas
for (xc, sc_) in ((230, -70), (240, 70), (470, -40), (480, 45), (560, 0)):
    jj = np.flatnonzero(HATCH & (np.abs(xn - xc) < 40) & (np.abs(s - sc_) < 40))
    d = np.hypot(xn[jj] - xc, s[jj] - sc_)
    blot = (1 - sstep(8, 22, d)) * sstep(0.45, 0.6, fbm(x[jj] * 90, y[jj] * 90, z[jj] * 90, 3, seed=157))
    paint(jj, hexcol("#8c8578"), blot * 0.35, rough=0.9)
dust = sstep(0.55, 0.85, fbm(x * 30, y * 30, z * 30, 4, seed=161)) * sstep(0.4, 0.95, nz) * white
paint(np.arange(n), hexcol("#a69f90"), dust * 0.25)
# estelas claras en las losetas negras detras de los rellenos y golpes
st_i = np.flatnonzero(H)
plume = sstep(0.7, 0.95, fbm(x[st_i] * 900, y[st_i] * 18, z[st_i] * 900, 3, seed=163)) * bleach_flux[st_i]
paint(st_i, hexcol("#9a9c9e"), plume * 0.4 * (1 - fresh[st_i]), rough=0.6)

del DIST_H, soot, hinge_d, dust, plume
gc.collect()

# ------------------------------------------------------------------------------- 6 rotulos
log("rotulos, emblema, dianas")
_FONTS = {}


def font(path, px):
    key = (path, px)
    if key not in _FONTS:
        _FONTS[key] = ImageFont.truetype(path, px)
    return _FONTS[key]


def text_image(lines, fpath, px_mm, height_mm, spacing=0.25, align="left"):
    px = max(8, int(round(height_mm * px_mm)))
    f = font(fpath, px)
    widths = [f.getbbox(t)[2] for t in lines]
    W = max(widths) + 8
    H_ = int(len(lines) * px * (1 + spacing)) + 8
    im = Image.new("L", (W, H_), 0)
    d = ImageDraw.Draw(im)
    for i, t in enumerate(lines):
        xo = 4 if align == "left" else (W - widths[i]) // 2
        d.text((xo, 4 + i * px * (1 + spacing)), t, font=f, fill=255)
    return np.asarray(im, np.float32) / 255.0, W / px_mm, H_ / px_mm


def surf_point(sel, target):
    jj = np.flatnonzero(sel)
    d = np.linalg.norm(P[jj] - np.asarray(target, np.float32), axis=1)
    j = jj[np.argmin(d)]
    return P[j].astype(np.float64), Nn[j].astype(np.float64)


def decal(img, w_mm, h_mm, origin, U, V, sel, color=None, opacity=1.0, wear=0.0, rough=0.55,
          depth=0.012, emis=None, metal=None, hgt=0.02, center=True, follow=True, layer="markings"):
    """Calcomania plana: img (alfa, o RGBA) con ancho/alto en mm, origen 3D (m), ejes U y V del
    texto. Solo texeles de sel cuya normal mira hacia el plano: como U x V apunta hacia afuera,
    el texto nunca queda espejado visto desde afuera."""
    if NO_MARKS:
        return 0
    U = np.asarray(U, np.float64)
    U /= np.linalg.norm(U)
    V = np.asarray(V, np.float64)
    V = V - V.dot(U) * U
    V /= np.linalg.norm(V)
    W = np.cross(U, V)
    o = np.asarray(origin, np.float64)
    jj = np.flatnonzero(sel)
    d = P[jj].astype(np.float64) - o
    uu = d @ U * 1000
    vv = d @ V * 1000
    ww = d @ W
    if center:
        uu += w_mm / 2
        vv += h_mm / 2
    keep = (uu >= 0) & (uu <= w_mm) & (vv >= 0) & (vv <= h_mm) & (np.abs(ww) < depth) & \
           ((Nn[jj].astype(np.float64) @ W) > 0.25)
    jj, uu, vv = jj[keep], uu[keep], vv[keep]
    if jj.size == 0:
        return 0
    H_, W_ = img.shape[:2]
    cr = [(1 - vv / h_mm) * (H_ - 1), uu / w_mm * (W_ - 1)]
    if img.ndim == 3:
        a = ndimage.map_coordinates(img[..., 3], cr, order=1)
        c = np.stack([ndimage.map_coordinates(img[..., k], cr, order=1) for k in range(3)], -1)
    else:
        a = ndimage.map_coordinates(img, cr, order=1)
        c = color
    if wear > 0:
        wn = fbm(P[jj, 0] * 400, P[jj, 1] * 400, P[jj, 2] * 400, 3, seed=41)
        a *= sstep(wear - 0.08, wear + 0.08, wn)
    a = a * opacity
    paint(jj, c, a, rough=rough, metal=metal, h=HGT[jj] + hgt if follow else hgt, e=emis)
    accumulate(MARK_A if layer == "markings" else INS_A, jj, a)
    return jj.size


BLACK = hexcol("#121315")
WHITE = hexcol("#ecebe6")
YEL = hexcol("#efc12b")
RED = hexcol("#c0202a")
PX = 16 if SUB == 1 else 8
up = np.array([0, 0, 1.0])


def top_pt(xn_mm, s_mm, sel):
    return surf_point(sel & (nz > 0.3), (s_mm / 1000, (XD0 - xn_mm) / 1000, 0.2))


def bot_pt(xn_mm, s_mm, sel):
    return surf_point(sel & (nz < -0.3), (s_mm / 1000, (XD0 - xn_mm) / 1000, -0.2))


def side_pt(xn_mm, zz_mm, sd, sel):
    return surf_point(sel & (sd * nx > 0.3), (sd * 0.5, (XD0 - xn_mm) / 1000, (zz_mm - ZD0) / 1000))


ue = (1.0, k_le, 0.0)                          # direccion del borde de ataque (planta)
# nombre del programa en las alas (se lee desde arriba, nariz arriba)
img, w_, h_ = text_image(["BÓLIDO"], F_BOLD, 2.0 if SUB == 1 else 1.0, 105)
o, _ = top_pt(565, -585, WING)
decal(img, w_, h_, o, U=(1, 0.40, 0), V=(-0.40, 1, 0), sel=WING & (s < 0) & (nz > 0), color=BLACK,
      opacity=0.93, wear=0.18, rough=0.7, depth=0.05)
img, w_, h_ = text_image(["VR-08"], F_BOLD, 2.0 if SUB == 1 else 1.0, 105)
o, _ = top_pt(560, 560, WING)
decal(img, w_, h_, o, U=(1, -0.40, 0), V=(0.40, 1, 0), sel=WING & (s > 0) & (nz > 0), color=BLACK,
      opacity=0.93, wear=0.18, rough=0.7, depth=0.05)
img, w_, h_ = text_image(["DEMOSTRADOR DE REENTRADA"], F_COND, PX, 13)
o, _ = top_pt(652, 600, WING)
decal(img, w_, h_, o, U=(1, -0.40, 0), V=(0.40, 1, 0), sel=WING & (s > 0) & (nz > 0), color=BLACK,
      opacity=0.9, wear=0.2, rough=0.7, depth=0.04)
# nombre a los costados del fuselaje (zona blanca)
for sd in (-1, 1):
    U_side = np.array([0, 1.0, 0]) * sd
    img, w_, h_ = text_image(["BÓLIDO"], F_BOLD, PX, 15)
    o, _ = side_pt(330, 26, sd, CORE)
    decal(img, w_, h_, o, U=U_side, V=up, sel=CORE & (cls == 2), color=BLACK, opacity=0.92, wear=0.15)
# CG
for sd in (-1, 1):
    for xc in (430, 440):
        o, _ = top_pt(xc, sd * 262, WING)
        ti = Image.new("L", (40, 40), 0)
        ImageDraw.Draw(ti).polygon([(20, 2), (38, 36), (2, 36)], fill=255)
        decal(np.asarray(ti, np.float32) / 255, 7, 7, o, U=(1, 0, 0), V=(0, 1, 0), sel=WING,
              color=YEL, opacity=0.95, wear=0.1, depth=0.02)
    img, w_, h_ = text_image(["CG 430-440"], F_MONO, PX, 6.5)
    o, _ = top_pt(436, sd * 305, WING)
    decal(img, w_, h_, o, U=(1, 0, 0), V=(0, 1, 0), sel=WING, color=BLACK, opacity=0.9, wear=0.15, depth=0.02)
# no pisar (con marco) en la raiz de las alas, sobre las mantas
for sd in (-1, 1):
    im = Image.new("L", (300, 90), 0)
    dr = ImageDraw.Draw(im)
    dr.rectangle([3, 3, 296, 86], outline=255, width=5)
    dr.text((22, 14), "NO PISAR", font=font(F_BOLD, 60), fill=255)
    o, _ = top_pt(600, sd * 330, WING)
    decal(np.asarray(im, np.float32) / 255, 40, 12, o, U=(1, -sd * 0.15, 0), V=(sd * 0.15, 1, 0), sel=WING,
          color=BLACK, opacity=0.85, wear=0.2, depth=0.03)
# elevones
for sd in (-1, 1):
    img, w_, h_ = text_image(["NO EMPUJAR"], F_MONO, PX, 5)
    o, _ = top_pt(float(X.TE(800)) - 32, sd * 800, ELEV)
    decal(img, w_, h_, o, U=(0.989, -0.146 * sd, 0), V=(0.146 * sd, 0.989, 0),
          sel=ELEV, color=BLACK, opacity=0.8, wear=0.25)
# winglets: numero grande afuera, serie adentro
for sd in (-1, 1):
    selo = WINGLET & (side == sd) & (sd * nx > 0.3)
    o, _ = surf_point(selo, (sd * 1.1, (XD0 - 860) / 1000, (125 - ZD0) / 1000))
    img, w_, h_ = text_image(["08"], F_BOLD, PX, 70)
    decal(img, w_, h_, o, U=(0, -sd, 0), V=up, sel=selo, color=BLACK, opacity=0.92, wear=0.15, depth=0.03)
    seli = WINGLET & (side == sd) & (-sd * nx > 0.3)
    o, _ = surf_point(seli, (sd * 1.0, (XD0 - 860) / 1000, (100 - ZD0) / 1000))
    img, w_, h_ = text_image(["SN 0811-BLD", "LOTE 26-10"], F_MONO, PX, 5)
    decal(img, w_, h_, o, U=(0, sd, 0), V=up, sel=seli, color=BLACK, opacity=0.8, wear=0.25, depth=0.02)
# tapa: flecha de rescate y texto
im = Image.new("L", (900, 200), 0)
dr = ImageDraw.Draw(im)
dr.polygon([(10, 70), (640, 70), (640, 20), (890, 100), (640, 180), (640, 130), (10, 130)], fill=255)
arrow = np.asarray(im, np.float32) / 255
inner = np.asarray(Image.fromarray((arrow * 255).astype(np.uint8)).filter(
    __import__("PIL.ImageFilter", fromlist=["MinFilter"]).MinFilter(15)), np.float32) / 255
txt = Image.new("L", (900, 200), 0)
ImageDraw.Draw(txt).text((40, 72), "RESCATE · LEVANTAR", font=font(F_BOLD, 54), fill=255)
txt = np.asarray(txt, np.float32) / 255
rgba = np.zeros((200, 900, 4), np.float32)
rgba[..., :3] = BLACK
rgba[..., 3] = arrow
yel_a = inner * (1 - txt)
rgba[..., :3] = rgba[..., :3] * (1 - yel_a[..., None]) + YEL * yel_a[..., None]
for sd in (-1, 1):
    o, _ = top_pt(455, sd * 52, HATCH)
    decal(rgba, 72, 16, o, U=(0, -1, 0), V=(1, 0, 0), sel=HATCH & (side == sd),
          opacity=0.95, wear=0.12, rough=0.6, depth=0.03)
# emblema de mision (circulo de 64 mm) en la tapa
E = 640
em = Image.new("RGBA", (E, E), (0, 0, 0, 0))
dr = ImageDraw.Draw(em)
dr.ellipse([0, 0, E - 1, E - 1], fill=(18, 19, 21, 255))
dr.ellipse([70, 70, E - 71, E - 71], fill=(16, 38, 82, 255))
dr.pieslice([70, 70, E - 71, E - 71], 0, 360, fill=(16, 38, 82, 255))
# tierra: arco inferior
earth = Image.new("RGBA", (E, E), (0, 0, 0, 0))
ed = ImageDraw.Draw(earth)
ed.ellipse([-260, 400, E + 260, 1400], fill=(42, 112, 170, 255))
ed.ellipse([-252, 412, E + 252, 1400], fill=(30, 84, 140, 255))
mask = Image.new("L", (E, E), 0)
ImageDraw.Draw(mask).ellipse([70, 70, E - 71, E - 71], fill=255)
em.paste(earth, (0, 0), Image.composite(earth, Image.new("RGBA", (E, E)), mask).split()[3])
# estela del bolido y ala volante
for k_, wdt in ((0, 46), (1, 30), (2, 16)):
    colk = [(255, 120, 30, 255), (255, 190, 80, 255), (255, 245, 210, 255)][k_]
    dr.line([(150, 170), (430, 400)], fill=colk, width=wdt)
dr.polygon([(430, 400), (500, 352), (470, 420), (520, 470), (440, 445), (410, 470)], fill=(240, 240, 236, 255))
for st_ in range(40):
    sx_, sy_ = (np.random.RandomState(st_).rand(2) * 360 + 140)
    if sy_ < 380:
        dr.ellipse([sx_ - 3, sy_ - 3, sx_ + 3, sy_ + 3], fill=(230, 230, 220, 255))
# texto alrededor
ring_txt = "BÓLIDO · VUELO 08 · REENTRADA · "
rf = font(F_BOLD, 44)
for kch, chh in enumerate(ring_txt):
    ang = -90 + kch * 360 / len(ring_txt)
    gi = Image.new("RGBA", (60, 60), (0, 0, 0, 0))
    ImageDraw.Draw(gi).text((30, 30), chh, font=rf, fill=(236, 235, 230, 255), anchor="mm")
    gi = gi.rotate(-ang - 90, resample=Image.BICUBIC)
    cxp = E / 2 + 285 * math.cos(math.radians(ang)) - 30
    cyp = E / 2 + 285 * math.sin(math.radians(ang)) - 30
    em.alpha_composite(gi, (int(cxp), int(cyp)))
ImageDraw.Draw(em).ellipse([66, 66, E - 67, E - 67], outline=(236, 235, 230, 255), width=6)
emb = np.asarray(em, np.float32) / 255
o, _ = top_pt(300, 0, HATCH)
decal(emb, 64, 64, o, U=(1, 0, 0), V=(0, 1, 0), sel=HATCH, opacity=0.97, wear=0.08, rough=0.55, layer="insignia",
      depth=0.04, hgt=0.04)
Image.fromarray((emb * 255).astype(np.uint8)).save(os.path.join(TEX, "masks", "emblem.png"))
# dianas de fotogrametria (cuadrantes blanco/negro)
TG = 256
yy_, xx_ = np.mgrid[0:TG, 0:TG]
rr_ = np.hypot(xx_ - TG / 2 + 0.5, yy_ - TG / 2 + 0.5) / (TG / 2)
q_ = ((xx_ < TG / 2) ^ (yy_ < TG / 2))
tgt_rgba = np.zeros((TG, TG, 4), np.float32)
tgt_rgba[..., :3] = np.where(((rr_ < 0.78) & q_ | (rr_ > 0.88))[..., None], BLACK, WHITE)
tgt_rgba[..., 3] = (rr_ < 1.0)
for (xn_t, s_t, sel_t) in ((780, -860, WING), (780, 860, WING), (160, 0, HATCH), (640, 0, CORE),
                           (500, -120, CORE), (500, 120, CORE)):
    o, _ = top_pt(xn_t, s_t, sel_t & (cls >= 2))
    decal(tgt_rgba, 26, 26, o, U=(1, 0, 0), V=(0, 1, 0), sel=sel_t, opacity=0.95, wear=0.05, depth=0.03)
for sd in (-1, 1):
    selo = WINGLET & (side == sd) & (sd * nx > 0.3)
    o, _ = surf_point(selo, (sd * 1.1, (XD0 - 905) / 1000, (185 - ZD0) / 1000))
    decal(tgt_rgba, 22, 22, o, U=(0, -sd, 0), V=up, sel=selo, opacity=0.95, wear=0.05, depth=0.03)
# advertencia de helice: anillo rojo y blanco antes del escudo y texto rojo
ti = np.flatnonzero(CORE & (xn > 690) & (xn < 706))
angt = np.degrees(np.arctan2(zm[ti] - 10, s[ti]))
diag = np.mod((xn[ti] - 690) + angt * 0.3, 10.0) < 5.0
if not NO_MARKS:                                  # banda de advertencia = marca (capa markings)
    paint(ti, np.where(diag[:, None], RED, WHITE), np.full(ti.size, 0.95), rough=0.55)
    accumulate(MARK_A, ti, np.full(ti.size, 0.95, np.float32))
img, w_, h_ = text_image(["PELIGRO", "HÉLICE"], F_BOLD, PX, 7, align="center")
o, _ = top_pt(668, 0, CORE)
decal(img, w_, h_, o, U=(1, 0, 0), V=(0, 1, 0), sel=CORE, color=RED, opacity=0.95, wear=0.1)
# compuertas: texto pequeno blanco
img, w_, h_ = text_image(["CAM"], F_MONO, PX, 5, align="center")
for sd in (-1, 1):
    o, _ = bot_pt(540, sd * 18, DOOR)
    decal(img, w_, h_, o, U=(-1, 0, 0), V=(0, 1, 0), sel=DOOR, color=WHITE, opacity=0.8, wear=0.2)
# borde blanco de las compuertas (barrera termica)
gx_d = np.arange(490, 590, 0.5)
gs_d = np.arange(-50, 50, 0.5)
dmask = np.zeros((gx_d.size, gs_d.size), bool)
dj_ = np.flatnonzero(DOOR)
ix_ = np.clip(((xn[dj_] - 490) / 0.5).astype(int), 0, gx_d.size - 1)
is_ = np.clip(((s[dj_] + 50) / 0.5).astype(int), 0, gs_d.size - 1)
dmask[ix_, is_] = True
dmask = ndimage.binary_closing(dmask, iterations=3)
ddist = ndimage.distance_transform_edt(dmask) * 0.5
dd_ = ndimage.map_coordinates(ddist, [(xn[dj_] - 490) / 0.5, (s[dj_] + 50) / 0.5], order=1)
paint(dj_, hexcol("#efece2"), 1 - sstep(0.8, 1.6, dd_), rough=0.97, h=0.3)

# ------------------------------------------------------------------------------- 7 luces
log("lentes de luces de navegacion (sin emision: el X8 UAV no lleva sistema de luces)")
# r4: los lentes son pintura inerte. La emision siempre encendida de r3 se quito porque el
# simulador controla el estado de las luces y esta configuracion no tiene lamparas.
LIGHT_ANCHORS = []
for sd, colr in ((-1, np.array([1.0, 0.08, 0.05])), (1, np.array([0.1, 1.0, 0.35]))):
    selo = WINGLET & (side == sd) & (sd * nx > 0.2)
    o, _ = surf_point(selo, (sd * 1.1, (XD0 - 690) / 1000, (60 - ZD0) / 1000))
    jj = np.flatnonzero(selo | (WINGLET & (side == sd)))
    d = np.linalg.norm(P[jj] - o.astype(np.float32), axis=1) * 1000
    paint(jj, hexcol("#202224"), 1 - sstep(5.8, 6.4, d), rough=0.3, metal=0.6, h=0.2)
    paint(jj, colr * 0.42 + 0.02, 1 - sstep(4.2, 4.7, d), rough=0.05, h=0.45)
    paint(jj, colr * 0.75 + 0.2, np.exp(-((d - 1.3) / 0.5) ** 2) * 0.7, rough=0.05)   # reflector
    COAT[jj] = np.maximum(COAT[jj], 1 - sstep(4.2, 4.7, d))
    LIGHT_ANCHORS.append(dict(node="wing_left_fixed" if sd < 0 else "wing_right_fixed",
                              group="navigation", color="red" if sd < 0 else "green",
                              position_blender_m=[round(float(v), 5) for v in o],
                              lens_radius_mm=4.5))
o, _ = top_pt(648, 0, CORE)
jj = np.flatnonzero(CORE & (nz > 0.2) & (xn > 630) & (xn < 670))
d = np.linalg.norm(P[jj] - o.astype(np.float32), axis=1) * 1000
paint(jj, hexcol("#202224"), 1 - sstep(4.8, 5.4, d), rough=0.3, metal=0.6, h=0.2)
paint(jj, hexcol("#9aa0aa"), 1 - sstep(3.4, 3.9, d), rough=0.05, h=0.4)
paint(jj, hexcol("#e8ecf4"), np.exp(-((d - 1.0) / 0.4) ** 2) * 0.7, rough=0.05)
COAT[jj] = np.maximum(COAT[jj], 1 - sstep(3.4, 3.9, d))
LIGHT_ANCHORS.append(dict(node="fuselage_core", group="navigation", color="white (tail)",
                          position_blender_m=[round(float(v), 5) for v in o], lens_radius_mm=3.6))

# ------------------------------------------------------------------------------- 8 calor (renders)
hsharp = np.maximum(np.exp(-xn / 95.0), np.exp(-d_le / 50.0) * (FIN | (CORE & (sa > 100))))
HEAT[:] = np.clip(hsharp ** 1.2 * H * (0.8 + 0.35 * (streak - 0.5)) + 0.12 * heat_flux * H, 0, 1)
HEAT[RCC] = np.maximum(HEAT[RCC], 0.85 + 0.15 * np.exp(-d_le[RCC] / 6.0))
HEAT *= (nz < 0.35) | RCC
RGH[:] = np.clip(RGH + 0.04 * (fbm(x * 500, y * 500, z * 500, 2, seed=171) - 0.5), 0.03, 1)

# ------------------------------------------------------------------------------- salida
log("escribiendo mapas")


def to_img(vals, fill, dtype=np.float32):
    chn = 1 if vals.ndim == 1 else vals.shape[1]
    out = np.empty((RES * RES, chn), dtype)
    out[:] = fill
    out[idx] = vals.reshape(n, chn)
    return out.reshape(RES, RES, chn)[::-1]          # fila 0 = arriba de la imagen (v alto)


def save(name, arr, mode):
    a = np.clip(arr, 0, 1)
    if a.shape[2] == 1:
        a = a[..., 0]
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), mode).save(os.path.join(TEX, name))


if NO_MARKS:                                     # solo la capa base, nada mas se toca
    os.makedirs(os.path.join(TEX, "layers"), exist_ok=True)
    save("layers/" + PREFIX + "paint_base.png", to_img(COL, hexcol("#141518")), "RGB")
    log("FIN sin rotulos", RES)
    sys.exit(0)
for nm_, arr in (("marking_alpha", MARK_A), ("insignia_alpha", INS_A)):
    Image.fromarray(np.round(np.clip(to_img(arr, 0.0)[..., 0], 0, 1) * 65535).astype(np.uint16)).save(
        os.path.join(TEX, "masks", f"{nm_}.png"))
json.dump(dict(status="decorative unlit lenses; no lamp system in the X8 UAV configuration",
               anchors=LIGHT_ANCHORS), open(os.path.join(TEX, "masks", "light_lenses.json"), "w"),
          indent=1)
save(PREFIX + "base_color.png", to_img(COL, hexcol("#141518")), "RGB")
save(PREFIX + "roughness.png", to_img(RGH, 0.5), "L")
save(PREFIX + "metallic.png", to_img(MET, 0.0), "L")
save(PREFIX + "emission.png", to_img(EMI, 0.0), "RGB")
save(PREFIX + "iridescence.png", to_img(IRI, 0.0), "L")
save(PREFIX + "coat.png", to_img(COAT, 0.0), "L")
save(PREFIX + "heat.png", to_img(HEAT, 0.0), "L")
Hm = to_img(HGT, 0.0)[..., 0]
np.save(os.path.join(WORK, "height_mm.npy"), Hm.astype(np.float32))
Image.fromarray(np.round(np.clip((Hm + 2.0) / 4.0, 0, 1) * 65535).astype(np.uint16)).save(
    os.path.join(TEX, PREFIX + "height.png"))
Image.fromarray(np.clip(Hm / 1.6 + 0.5, 0, 1) * 255).convert("L").save(
    os.path.join(TEX, "masks", "height_preview.png"))
cls_col = np.array([[0, 0, 0], [20, 20, 24], [220, 215, 200], [240, 232, 205], [250, 250, 250]], np.float32) / 255
cmap = cls_col[cls]
cmap[RCC] = (0.55, 0.56, 0.58)
cmap[MT] = (0.75, 0.55, 0.3)
save("masks/tps_zones.png", to_img(cmap, 0.0), "RGB")
save("masks/heat_flux.png", to_img(heat_flux, 0.0), "L")
save("masks/fresh_tiles.png", to_img(fresh * H, 0.0), "L")
log("FIN", RES, f"memoria maxima {resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e6:.2f} GB")
