"""Paso 3 de la librea "ABISAL": pintor procedural en 3D (numpy).

Concepto: la X8 como un rape de las profundidades. Piel negro-azulada con escamas iridiscentes
en el lomo, vientre plateado con hileras de fotoforos, aletas con radios segmentados y borde
violeta, linea lateral bioluminiscente, boca abierta con colmillos en la nariz, un senuelo
luminoso sobre la cabeza, ojos falsos en los winglets, branquias coral en la union del ala.
Encima, el uso real: bordes desconchados que dejan ver la espuma EPO, rayones y manchas de
pasto en la panza (aterriza de barriga), insectos en los bordes de ataque, suciedad en
ranuras, huellas de manos, una reparacion con cinta y rotulacion tecnica gastada.

Cada texel del atlas sabe su posicion y su normal en 3D (mapas horneados), asi que todo se
dibuja en el espacio del avion: no hay costuras ni estiramientos del UV.

  python livery_paint.py <carpeta_trabajo> <carpeta_texturas> [metadata.json] [submuestreo] [--no-markings]

Con --no-markings solo escribe layers/x8_abisal_paint_base.png (la misma pintura sin rotulos ni
marcas); paint_layers.py deriva de ahi las capas editables (r4).

D0 sale de metadata.json si se pasa; si no, del build_info.json que deja livery_bake_geom.py.

Escribe (a la resolucion de trabajo): base_color.png (sRGB), roughness.png, metallic.png,
height_mm.npy (+ x8_abisal_height.png de 16 bits y height_preview.png), emission.png, iridescence.png, coat.png y las mascaras
editables en <carpeta_texturas>/source/masks/.
"""
import sys, os, json, math, time
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
NO_MARKS = "--no-markings" in argv          # r4: capa base sin rotulos (fuente editable por capas)
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
    print(f"[{time.time() - T0:6.1f}s]", *a, flush=True)


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
LEs = X.LE(np.minimum(sa, 935.0)).astype(np.float32)
TEs = X.TE(np.minimum(sa, 935.0)).astype(np.float32)
chord = np.maximum(TEs - LEs, 1.0)
u = (xn - LEs) / chord                                 # fraccion de cuerda (planta)
WINGLET = FIN & (sa > 960)

# ------------------------------------------------------------------------------- ruido
U32 = np.uint32


def hash3(ix, iy, iz, seed=0):
    h = (ix.astype(np.int64).astype(U32) * U32(0x8DA6B343)) ^ \
        (iy.astype(np.int64).astype(U32) * U32(0xD8163841)) ^ \
        (iz.astype(np.int64).astype(U32) * U32(0xCB1AB31F)) ^ U32((seed * 0x9E3779B1) & 0xFFFFFFFF)
    h ^= h >> U32(13)
    h *= U32(0x5BD1E995)
    h ^= h >> U32(15)
    return h.astype(np.float32) * np.float32(1.0 / 4294967295.0)


def vnoise(px, py, pz, seed=0):
    fx, fy, fz = np.floor(px), np.floor(py), np.floor(pz)
    tx, ty, tz = px - fx, py - fy, pz - fz
    tx, ty, tz = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty), tz * tz * (3 - 2 * tz)
    out = np.zeros(px.shape, np.float32)
    for dx in (0, 1):
        wx = tx if dx else 1 - tx
        for dy in (0, 1):
            wy = ty if dy else 1 - ty
            for dz in (0, 1):
                wz = tz if dz else 1 - tz
                out += wx * wy * wz * hash3(fx + dx, fy + dy, fz + dz, seed)
    return out


def fbm(px, py, pz, octaves=4, seed=0, lac=2.03, gain=0.5):
    a, f, tot, norm = 1.0, 1.0, np.zeros(px.shape, np.float32), 0.0
    for o in range(octaves):
        tot += a * vnoise(px * f, py * f, pz * f, seed + 17 * o)
        norm += a
        a *= gain
        f *= lac
    return tot / norm


def sstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
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
    global COL, RGH, MET, HGT, EMI
    ii = np.flatnonzero(mask) if mask.dtype == bool else mask
    if ii.size == 0:
        return
    a = np.broadcast_to(np.asarray(alpha, np.float32), (ii.size,)) if np.ndim(alpha) == 0 else alpha
    a = np.clip(a, 0, 1)
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
RGH = np.full(n, 0.48, np.float32)
MET = np.zeros(n, np.float32)
HGT = np.zeros(n, np.float32)            # mm
EMI = np.zeros((n, 3), np.float32)
IRI = np.zeros(n, np.float32)            # mascara de pelicula delgada (renders)
COAT = np.zeros(n, np.float32)           # mascara de barniz (renders)
MARK_A = np.zeros(n, np.float32)         # cobertura de rotulos/marcas (capa markings)
INS_A = np.zeros(n, np.float32)          # cobertura de insignias (capa insignia)


def accumulate(acc, jj, a):
    acc[jj] = 1 - (1 - acc[jj]) * (1 - np.clip(a, 0, 1))

# ------------------------------------------------------------------------------- 1 piel base
log("piel base y contrasombra")
ABYSS0, ABYSS1, ABYSS2 = hexcol("#05080f"), hexcol("#0b1322"), hexcol("#122038")
PETROL, VIOLET = hexcol("#0d3d47"), hexcol("#2c1f57")
BELLY0, BELLY1, SHEEN = hexcol("#4f5d70"), hexcol("#8d9aab"), hexcol("#2e4560")
mott = fbm(x * 9, y * 9, z * 9, 4, seed=3)            # manchas de ~10 cm
mott2 = fbm(x * 31, y * 31, z * 31, 3, seed=5)
top = sstep(-0.35, 0.45, nz)
dorsal = mix(mix(ABYSS0, ABYSS1, sstep(0.35, 0.75, mott)), ABYSS2, sstep(0.6, 0.85, mott2) * 0.6)
sheen_col = mix(PETROL, VIOLET, sstep(0.3, 0.7, fbm(x * 4 + 3, y * 4, z * 4, 3, seed=9)))
dorsal = mix(dorsal, sheen_col, 0.35 * sstep(0.45, 0.8, mott))
belly = mix(BELLY0, BELLY1, sstep(0.2, 0.8, fbm(x * 12, y * 12, z * 12, 3, seed=11)))
COL[:] = mix(belly, dorsal, top)
# banda plateada lateral (transicion del vientre), como un pez hacha
band = np.exp(-((nz + 0.05) / 0.22) ** 2) * BODY
COL[:] = mix(COL, SHEEN * 1.35, 0.45 * band)
RGH[:] = 0.5 - 0.12 * (1 - top)
MET[:] = 0.18 * (1 - top) + 0.25 * band
IRI[:] = 0.25 * band
HGT[:] = 0.015 * fbm(x * 1400, y * 1400, z * 1400, 2, seed=21)       # piel de naranja
del belly, dorsal, sheen_col

# ------------------------------------------------------------------------------- 2 escamas
log("escamas (voronoi hexagonal triplanar)")


def hex_scales(a, b, S, seed):
    """Escamas sobre el plano (a, b) en mm; a crece hacia atras. Devuelve F1, F2, t (posicion
    dentro de la escama, 0 delante 1 detras) y un aleatorio por escama."""
    h = S * 0.866
    row = np.floor(b / h)
    F1 = np.full(a.shape, 1e9, np.float32)
    F2 = np.full(a.shape, 1e9, np.float32)
    T = np.zeros(a.shape, np.float32)
    R = np.zeros(a.shape, np.float32)
    for dr in (-1, 0, 1):
        r = row + dr
        off = (np.mod(r, 2)) * 0.5 * S
        col = np.floor((a - off) / S)
        for dc in (-1, 0, 1):
            c = col + dc
            j1 = hash3(c, r, np.zeros_like(c), seed) - 0.5
            j2 = hash3(c, r, np.ones_like(c), seed) - 0.5
            ca = (c + 0.5) * S + off + 0.22 * S * j1
            cb = (r + 0.5) * h + 0.18 * S * j2
            d = np.hypot((a - ca) * 0.85, b - cb)
            closer = d < F1
            F2 = np.where(closer, F1, np.minimum(F2, d))
            T = np.where(closer, (a - ca) / S + 0.5, T)
            R = np.where(closer, hash3(c, r, np.full_like(c, 2), seed), R)
            F1 = np.where(closer, d, F1)
    return F1, F2, T, R


SC = BODY | (WING & (sa < 520))
ii = np.flatnonzero(SC)
Ssz = np.where(BODY[ii], 15.0, 15.0 + (sa[ii] - 236) * 0.06).astype(np.float32)
wx_, wy_, wz_ = np.abs(nx[ii]) ** 4, np.abs(ny[ii]) ** 4, np.abs(nz[ii]) ** 4
wsum = wx_ + wy_ + wz_ + 1e-6
acc = {k: np.zeros(ii.size, np.float32) for k in ("edge", "arc", "rim", "rise", "rnd")}
for (aa, bb, w) in ((xn[ii], zm[ii], wx_), (xn[ii], s[ii], wz_), (zm[ii] + 300, s[ii], wy_)):
    F1, F2, Tt, Rr = hex_scales(aa / Ssz, bb / Ssz, 1.0, seed=7)
    ww = w / wsum
    post = sstep(0.46, 0.62, Tt)                       # mitad trasera de la escama
    acc["edge"] += ww * (1 - sstep(0.02, 0.10, F2 - F1))
    # escamas cicloides imbricadas: se ve el arco del borde libre trasero
    acc["arc"] += ww * np.exp(-((F1 - 0.47) / 0.035) ** 2) * post
    acc["rim"] += ww * sstep(0.30, 0.45, F1) * (1 - sstep(0.45, 0.5, F1)) * post
    acc["rise"] += ww * np.clip(Tt, 0, 1) * (F1 < 0.5)
    acc["rnd"] += ww * Rr
fade = np.where(BODY[ii], 1.0, 1 - sstep(330, 520, sa[ii])).astype(np.float32)
topw = sstep(-0.2, 0.5, nz[ii])
contrast = fade * (0.3 + 0.7 * topw)                   # el vientre plateado casi liso
# color por escama: cada una con su propio tono iridiscente; mas marcado en el lomo
hue = acc["rnd"]
scale_tint = mix(mix(PETROL, VIOLET, hue), hexcol("#1d5d6b"), sstep(0.75, 1.0, hue))
COL[ii] = mix(COL[ii], COL[ii] * 0.72, 0.5 * acc["edge"] * contrast)
COL[ii] = mix(COL[ii], COL[ii] * 0.35, 0.9 * acc["arc"] * contrast)
COL[ii] = mix(COL[ii], scale_tint * (0.9 + 0.8 * topw[:, None]), 0.6 * acc["rim"] * contrast)
HGT[ii] += fade * (0.12 * acc["rise"] - 0.14 * acc["arc"] - 0.04 * acc["edge"])
RGH[ii] -= 0.14 * acc["rim"] * fade
IRI[ii] = np.maximum(IRI[ii], fade * (0.35 + 0.65 * acc["rim"]) * (0.4 + 0.6 * topw))
SCALE_EDGE = np.zeros(n, np.float32)
SCALE_EDGE[ii] = np.maximum(acc["arc"], 0.5 * acc["edge"]) * fade
del acc, F1, F2, Tt, Rr

# ------------------------------------------------------------------------------- 3 aletas
log("aletas: radios segmentados y borde")
fi = np.flatnonzero(FIN & ~WINGLET)
C0x, C0s = 255.0, 175.0
dxp = xn[fi] - C0x
dsp = sa[fi] - C0s
rr = np.hypot(dxp, dsp)
phi = np.degrees(np.arctan2(dsp, dxp))
dphi = 2.15
k = np.round(phi / dphi)
dist = rr * np.abs(np.radians(phi - k * dphi))
# radios que se bifurcan hacia afuera
k2 = np.round(phi / dphi - 0.5) + 0.5
dist2 = rr * np.abs(np.radians(phi - k2 * dphi))
dist = np.where(rr > 560, np.minimum(dist, dist2 + 0.4 * (rr < 640)), dist)
width = np.clip(2.3 - 0.0011 * rr, 0.9, 2.3)
seg = np.mod(rr + 13 * hash3(k, k, k, 4) * 40, 38.0)
joint = (seg < 2.2).astype(np.float32)
ray = (1 - sstep(width * 0.45, width, dist)) * sstep(240, 420, rr)
ray *= np.where(WING[fi], sstep(300, 470, sa[fi]), 1.0)
ray_hi = np.exp(-((dist - width * 0.55) / 0.45) ** 2) * ray
membrane = sstep(0.0, 1.0, np.abs(np.mod(phi / dphi, 1) - 0.5) * 2)
rayw = np.where(WING[fi], sstep(300, 480, sa[fi]), 1.0).astype(np.float32)
topf = sstep(-0.2, 0.4, nz[fi])
mem_col = mix(hexcol("#0b1830"), hexcol("#1b2f5a"), 0.5 * (1 - membrane) * rayw)
mem_col = mix(mem_col, mix(hexcol("#5b6b84"), hexcol("#90a2bb"), 1 - membrane), (1 - topf) * 0.7)
COL[fi] = mix(COL[fi], mem_col, 0.75 * rayw)
COL[fi] = mix(COL[fi], hexcol("#03050a") * (1 - joint)[:, None] + hexcol("#3d4c69") * joint[:, None],
              0.9 * ray)
COL[fi] = mix(COL[fi], hexcol("#6f88b8"), 0.35 * ray_hi * topf)
HGT[fi] += 0.18 * ray * (1 - 0.6 * joint) - 0.04 * membrane * rayw
RGH[fi] = np.where(ray > 0.5, 0.36, RGH[fi])
IRI[fi] = np.maximum(IRI[fi], 0.45 * rayw * (1 - membrane) * topf)
# borde de la aleta: franja violeta y cuentas luminosas en el borde de salida
dTE = (TEs[fi] - xn[fi])
edge = np.exp(-(dTE / 22.0) ** 2) * (sa[fi] > 260)
COL[fi] = mix(COL[fi], hexcol("#2a124d"), 0.75 * edge)
COL[fi] = mix(COL[fi], hexcol("#6a3fb0"), 0.5 * np.exp(-(dTE / 5.0) ** 2) * (sa[fi] > 260))
bead_k = np.round((sa[fi] - 280) / 32.0)
bead_s = 280 + bead_k * 32.0
bd = np.hypot(sa[fi] - bead_s, dTE - 9.0)
bead = (1 - sstep(2.0, 3.6, bd)) * (sa[fi] > 270) * (sa[fi] < 905) * topf
paint(fi, hexcol("#d7c2ff"), bead, rough=0.08, h=0.25, e=hexcol("#a46bff"))
# uno de cada cinco radios lleva un conducto luminoso en su mitad exterior
glow_ray = (np.mod(k, 5) == 0) * (1 - sstep(0.25, 0.6, dist)) * sstep(380, 620, rr) * rayw * \
    (1 - sstep(0.0, 1.0, np.abs(np.mod(rr, 46.0) - 23) / 23 - 0.92))
paint(fi, hexcol("#7ff1ff"), glow_ray * 0.9, rough=0.1, e=hexcol("#2fe6ff") * 0.75)
COAT[fi] = np.maximum(COAT[fi], bead)
del rr, phi, dist, dist2, ray, ray_hi, membrane, edge, bead, glow_ray

# winglets: aletas dorsales con radios verticales
wi = np.flatnonzero(WINGLET)
hh = zm[wi]
rays_w = np.mod(xn[wi] + 0.35 * hh, 26.0)
rw = (1 - sstep(0.9, 1.9, np.minimum(rays_w, 26 - rays_w))) * sstep(40, 90, hh)
COL[wi] = mix(COL[wi], hexcol("#0c1a33"), 0.6 * sstep(30, 120, hh))
COL[wi] = mix(COL[wi], hexcol("#03050a"), 0.85 * rw)
HGT[wi] += 0.15 * rw
tip = sstep(150, 205, hh)
COL[wi] = mix(COL[wi], hexcol("#2a124d"), 0.6 * tip)

# ------------------------------------------------------------------------------- 4 rotulos
log("rotulacion tecnica")
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
    H = int(len(lines) * px * (1 + spacing)) + 8
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    for i, t in enumerate(lines):
        xo = 4 if align == "left" else (W - widths[i]) // 2
        d.text((xo, 4 + i * px * (1 + spacing)), t, font=f, fill=255)
    return np.asarray(im, np.float32) / 255.0, W / px_mm, H / px_mm


def surf_point(sel, target):
    """Punto de la superficie (texel real) mas cercano al objetivo (m) dentro de sel."""
    jj = np.flatnonzero(sel)
    d = np.linalg.norm(P[jj] - np.asarray(target, np.float32), axis=1)
    j = jj[np.argmin(d)]
    return P[j].astype(np.float64), Nn[j].astype(np.float64)


def decal(img, w_mm, h_mm, origin, U, V, sel, color, opacity=1.0, wear=0.0, rough=0.55,
          depth=0.012, emis=None, metal=None, hgt=0.03, center=True, layer="markings"):
    """Calcomania plana: img (alfa) con ancho/alto en mm, origen 3D (m), ejes U (derecha del
    texto) y V (arriba del texto). Solo texeles de sel cuya normal mira hacia el plano: como
    U x V apunta hacia afuera, el texto nunca queda espejado visto desde afuera."""
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
    H_, W_ = img.shape
    a = ndimage.map_coordinates(img, [(1 - vv / h_mm) * (H_ - 1), uu / w_mm * (W_ - 1)], order=1)
    if wear > 0:
        wn = fbm(P[jj, 0] * 400, P[jj, 1] * 400, P[jj, 2] * 400, 3, seed=41)
        a *= sstep(wear - 0.08, wear + 0.08, wn)
    a *= opacity
    paint(jj, color, a, rough=rough, metal=metal, h=HGT[jj] + hgt, e=emis)
    accumulate(MARK_A if layer == "markings" else INS_A, jj, a)
    return jj.size


WHITE = hexcol("#d6dadc")
BONE = hexcol("#cfc6ad")
YEL = hexcol("#f0bd2c")
RED = hexcol("#b0182c")
PX = 16 if SUB == 1 else 8
up = np.array([0, 0, 1.0])
fwd = np.array([0, 1.0, 0])


def top_pt(xn_mm, s_mm, sel):
    return surf_point(sel & (nz > 0.3), (s_mm / 1000, (XD0 - xn_mm) / 1000, 0.2))


def bot_pt(xn_mm, s_mm, sel):
    return surf_point(sel & (nz < -0.3), (s_mm / 1000, (XD0 - xn_mm) / 1000, -0.2))


def side_pt(xn_mm, zz_mm, sd, sel):
    return surf_point(sel & (sd * nx > 0.3), (sd * 0.5, (XD0 - xn_mm) / 1000, (zz_mm - ZD0) / 1000))


# nombre grande en las alas (se lee desde arriba con la nariz hacia arriba)
img, w_, h_ = text_image(["ABISAL"], F_BOLD, 2.0 if SUB == 1 else 1.0, 120)
o, _ = top_pt(560, -560, WING)
decal(img, w_, h_, o, U=(1, 0.40, 0), V=(-0.40, 1, 0),
      sel=WING & (s < 0), color=BONE, opacity=0.78, wear=0.42, rough=0.6, depth=0.05)
img, w_, h_ = text_image(["X8·08"], F_BOLD, 2.0 if SUB == 1 else 1.0, 120)
o, _ = top_pt(560, 560, WING)
decal(img, w_, h_, o, U=(1, -0.40, 0), V=(0.40, 1, 0), sel=WING & (s > 0), color=BONE,
      opacity=0.78, wear=0.42, rough=0.6, depth=0.05)
# debajo del ala izquierda, al reves para que se lea desde abajo
img, w_, h_ = text_image(["ABISAL-08"], F_BOLD, 1.6 if SUB == 1 else 0.8, 95)
o, _ = bot_pt(600, -600, WING)
decal(img, w_, h_, o, U=(-1, -0.40, 0), V=(-0.40, 1, 0), sel=WING & (s < 0), color=WHITE,
      opacity=0.7, wear=0.45, depth=0.05)
# regla de calibracion bajo el ala derecha (camara de mapeo)
ruler = np.zeros((60, 1200), np.float32)
rd = Image.fromarray((ruler * 255).astype(np.uint8))
dr_ = ImageDraw.Draw(rd)
for i in range(0, 51):
    xx = 20 + i * 23
    ln = 34 if i % 10 == 0 else (24 if i % 5 == 0 else 14)
    dr_.line([(xx, 2), (xx, 2 + ln)], fill=255, width=3 if i % 10 == 0 else 2)
    if i % 10 == 0:
        dr_.text((xx - 6, 38), str(i), font=font(F_MONO, 18), fill=255)
dr_.line([(20, 2), (20 + 50 * 23, 2)], fill=255, width=3)
o, _ = bot_pt(0, 0, WING & (s > 0) & (u > 0.40) & (u < 0.44) & (sa > 878) & (sa < 882))
decal(np.asarray(rd, np.float32) / 255, 500, 26, o, U=(-1, 0.48, 0), V=(0.48, 1, 0),
      sel=WING & (s > 0), color=WHITE, opacity=0.85, wear=0.3, depth=0.03, center=False)
# CG: marcas a 430 y 440 mm sobre la raiz de las alas
for sd in (-1, 1):
    for xc in (430, 440):
        o, _ = top_pt(xc, sd * 255, WING)
        tri = np.zeros((40, 40), np.float32)
        ti = Image.fromarray((tri * 255).astype(np.uint8))
        ImageDraw.Draw(ti).polygon([(20, 2), (38, 36), (2, 36)], fill=255)
        decal(np.asarray(ti, np.float32) / 255, 7, 7, o, U=(1, 0, 0), V=(0, 1, 0), sel=WING,
              color=YEL, opacity=0.95, wear=0.2, depth=0.02)
    img, w_, h_ = text_image(["CG 430-440"], F_MONO, PX, 7)
    o, _ = top_pt(435, sd * 300, WING)
    decal(img, w_, h_, o, U=(1, 0, 0), V=(0, 1, 0), sel=WING, color=YEL, opacity=0.95, wear=0.2,
          depth=0.02)
# costados del fuselaje
for sd in (-1, 1):
    U_side = np.array([0, 1.0, 0]) * sd          # se lee de izquierda a derecha desde ese costado
    img, w_, h_ = text_image(["LIPO 6S 5000", "BATERIA 228 mm"], F_MONO, PX, 5.5)
    o, _ = side_pt(260, 30, sd, CORE)
    decal(img, w_, h_, o, U=U_side, V=up, sel=CORE, color=WHITE, opacity=0.85, wear=0.35)
    img, w_, h_ = text_image(["EPO · X8 · 2120 · SN 0811-ABY"], F_MONO, PX, 4.5)
    o, _ = side_pt(640, 24, sd, CORE)
    decal(img, w_, h_, o, U=U_side, V=up, sel=CORE, color=WHITE, opacity=0.8, wear=0.35)
# tapa: levantar aqui y paracaidas
img, w_, h_ = text_image(["▲ LEVANTAR ▲", "IMANES"], F_MONO, PX, 6.5, align="center")
o, _ = top_pt(492, 0, HATCH)
decal(img, w_, h_, o, U=(1, 0, 0), V=(0, 1, 0), sel=HATCH, color=YEL, opacity=0.9, wear=0.3)
img, w_, h_ = text_image(["PARACAIDAS", "NO OBSTRUIR"], F_MONO, PX, 5, align="center")
o, _ = top_pt(380, 0, HATCH)
decal(img, w_, h_, o, U=(1, 0, 0), V=(0, 1, 0), sel=HATCH, color=WHITE, opacity=0.65, wear=0.4)
# compuertas
img, w_, h_ = text_image(["CAM", "LIBRE"], F_MONO, PX, 6, align="center")
for sd in (-1, 1):
    o, _ = bot_pt(540, sd * 18, DOOR)
    decal(img, w_, h_, o, U=(-1, 0, 0), V=(0, 1, 0), sel=DOOR, color=YEL, opacity=0.9, wear=0.3)
# elevones
for sd in (-1, 1):
    img, w_, h_ = text_image(["NO EMPUJAR"], F_MONO, PX, 5)
    o, _ = top_pt(float(X.TE(800)) - 25, sd * 800, ELEV)
    decal(img, w_, h_, o, U=(0.989, -0.146 * sd, 0), V=(0.146 * sd, 0.989, 0),
          sel=ELEV, color=WHITE, opacity=0.75, wear=0.35)
# advertencia de helice: cheurones amarillo/negro alrededor de la cola
ti = np.flatnonzero(CORE & (xn > 742) & (xn < 790))
ang = np.degrees(np.arctan2(zm[ti] - 24, s[ti]))
chev = np.mod((xn[ti] - 742) + np.abs(ang) * 0.35, 12.0) < 6.0
wearc = sstep(0.32, 0.4, fbm(x[ti] * 300, y[ti] * 300, z[ti] * 300, 3, seed=55))
if not NO_MARKS:                                 # los cheurones son marcas (capa markings)
    paint(ti, np.where(chev[:, None], YEL, hexcol("#0b0b0b")), 0.92 * wearc, rough=0.5)
    accumulate(MARK_A, ti, 0.92 * wearc)
img, w_, h_ = text_image(["PELIGRO", "HELICE"], F_MONO, PX, 6, align="center")
o, _ = top_pt(712, 0, CORE)
decal(img, w_, h_, o, U=(1, 0, 0), V=(0, 1, 0), sel=CORE, color=RED, opacity=0.95, wear=0.25)
# numero de serie en la cara interior de los winglets
for sd in (-1, 1):
    sel = WINGLET & (side == sd) & (-sd * nx > 0.3)
    if sel.any():
        o, _ = surf_point(sel, (sd * 1.0, (XD0 - 760) / 1000, (120 - ZD0) / 1000))
        img, w_, h_ = text_image(["SN 0811-ABY", "LOTE 26-10"], F_MONO, PX, 5)
        decal(img, w_, h_, o, U=(0, -sd, 0), V=up, sel=sel, color=WHITE,
              opacity=0.8, wear=0.3, depth=0.02)

# ------------------------------------------------------------------------------- 5 luz
log("bioluminiscencia: linea lateral, fotoforos, senuelo")
CYAN, CYAN_CORE = hexcol("#2fe6ff"), hexcol("#c8fdff")
# linea lateral del cuerpo: de la nariz a la cola, a media altura del costado
li = np.flatnonzero(CORE & (np.abs(nx) > 0.35) & (xn > 140) & (xn < 735))
zl = 18 + 12 * np.cos((xn[li] - 140) / 600 * math.pi)                    # mm
dz = np.abs(zm[li] - zl)
dash = np.mod(xn[li], 24.0)
dot = np.hypot(np.minimum(dash, 24 - dash), dz)
line = (1 - sstep(0.6, 1.2, dz)) * (np.mod(xn[li], 6.0) < 4.2)
pore = 1 - sstep(1.4, 2.2, dot)
halo = np.exp(-(dz / 4.5) ** 2) * 0.35
paint(li, CYAN * 0.55 + 0.1, halo, e=CYAN * 0.35)
paint(li, CYAN, line, rough=0.25, e=CYAN * 0.9)
paint(li, CYAN_CORE, pore, rough=0.06, h=0.15, e=CYAN_CORE)
COAT[li] = np.maximum(COAT[li], pore)
# ventral: dos hileras en la panza y una bajo cada ala
def photophores(sel, centers_fn, r_core=2.2, r_cup=4.2):
    jj = np.flatnonzero(sel)
    cx, cs = centers_fn(xn[jj], s[jj])
    d = np.hypot(xn[jj] - cx, s[jj] - cs)
    cup = 1 - sstep(r_cup - 0.6, r_cup, d)
    core_ = 1 - sstep(r_core - 0.5, r_core, d)
    ring = np.exp(-((d - (r_core + 0.9)) / 0.5) ** 2)
    paint(jj, hexcol("#020306"), cup * 0.95, rough=0.2, h=-0.08)
    paint(jj, hexcol("#7ff6ff"), ring * cup * 0.6, e=CYAN * 0.4)
    paint(jj, CYAN_CORE, core_, rough=0.05, h=0.2, e=CYAN_CORE)
    COAT[jj] = np.maximum(COAT[jj], cup)


door_rect = (xn > 505) & (xn < 575) & (sa < 41)
for row_s in (-34.0, 34.0):
    photophores(CORE & (nz < -0.55) & ~door_rect & (xn > 120) & (xn < 700),
                lambda a, b, rs=row_s: (120 + np.round((a - 120) / 17.0) * 17.0, np.full_like(b, rs)))
def wing_row(a, b):
    ss = 290 + np.round((np.abs(b) - 290) / 26.0) * 26.0
    sc_ = np.clip(ss, 0, 935)
    return X.LE(sc_) + 0.09 * (X.TE(sc_) - X.LE(sc_)), np.sign(b) * ss


photophores(WING & (nz < -0.3) & (sa > 290) & (sa < 900), wing_row, r_core=1.8, r_cup=3.6)
# anillo de fotoforos alrededor de la compuerta de la camara
ri = np.flatnonzero(CORE & (nz < -0.4) & (xn > 480) & (xn < 600) & (sa < 70))
ang = np.arctan2(s[ri], (xn[ri] - 540) * 1.15)
rad = np.hypot(s[ri], (xn[ri] - 540) * 1.15)
kq = np.round(ang / (2 * math.pi / 22))
pc = (np.hypot(rad * np.cos(ang) - 52 * np.cos(kq * 2 * math.pi / 22),
               rad * np.sin(ang) - 52 * np.sin(kq * 2 * math.pi / 22)))
paint(ri, hexcol("#020306"), (1 - sstep(3.0, 3.6, pc)) * 0.9, rough=0.2)
paint(ri, CYAN_CORE, 1 - sstep(1.3, 1.9, pc), rough=0.05, h=0.15, e=CYAN_CORE)
# anillo de puntos dentro del borde de la tapa
hx = np.array(X.hatch_outline())
from matplotlib.path import Path as MPath
gx = np.arange(80, 560, 0.5)
gs_ = np.arange(-130, 130, 0.5)
GX, GS = np.meshgrid(gx, gs_, indexing="ij")
inside = MPath(hx).contains_points(np.c_[GX.ravel(), GS.ravel()]).reshape(GX.shape)
dist_in = ndimage.distance_transform_edt(inside) * 0.5
dist_out = ndimage.distance_transform_edt(~inside) * 0.5
sdf = np.where(inside, -dist_in, dist_out)                  # <0 dentro de la tapa


def sample_grid(G, a, b, x0, b0, step):
    return ndimage.map_coordinates(G, [(a - x0) / step, (b - b0) / step], order=1, mode="nearest")


hi_ = np.flatnonzero((CORE | HATCH) & (nz > 0.2) & (xn > 80) & (xn < 560) & (sa < 130))
hs = sample_grid(sdf, xn[hi_], s[hi_], 80, -130, 0.5)
SEAM = np.zeros(n, np.float32)
SEAM[hi_] = np.exp(-(hs / 2.5) ** 2)
ring_line = np.exp(-((hs + 7.0) / 0.9) ** 2)
per = np.mod(xn[hi_] * 0.7 + np.abs(s[hi_]) * 0.7, 16.0)
dots = ring_line * (per < 3.0)
paint(hi_, CYAN, dots, rough=0.06, h=0.12, e=CYAN * 0.9)
# senuelo: tallo sobre la linea central y bulbo luminoso sobre la nariz
st = np.flatnonzero(CORE & (nz > 0.2) & (xn > 30) & (xn < 112))
s_line = 3.5 * np.sin(xn[st] / 11.0)
dl = np.abs(s[st] - s_line)
stalk = (1 - sstep(1.2, 1.9, dl)) * (xn[st] > 48)
paint(st, hexcol("#1b0f24"), stalk, rough=0.3, h=0.2)
paint(st, hexcol("#5a3a7a"), np.exp(-((dl - 0.9) / 0.3) ** 2) * stalk * 0.6)
bulb_c = np.array([0.0, 42.0])
db = np.hypot(xn[st] - bulb_c[1], s[st] - bulb_c[0])
paint(st, CYAN * 0.5, np.exp(-(db / 16.0) ** 2) * 0.55, e=CYAN * 0.55)
paint(st, CYAN_CORE, 1 - sstep(6.5, 8.0, db), rough=0.04, h=0.5, e=np.array([0.92, 1.0, 1.0]))
COAT[st] = np.maximum(COAT[st], 1 - sstep(6.5, 8.0, db))
fil = np.flatnonzero(CORE & (nz > 0.1) & (xn < 70))
dbf = np.hypot(xn[fil] - 42, s[fil])
angf = np.arctan2(s[fil], xn[fil] - 42)
fl = (np.abs(np.mod(angf * 9 / math.pi, 1) - 0.5) < 0.06) * (dbf > 8) * (dbf < 18)
paint(fil, CYAN, fl * (1 - sstep(10, 18, dbf)), e=CYAN * 0.7)

# ------------------------------------------------------------------------------- 6 boca
log("boca, dientes, ojos y branquias")
# la boca se dibuja en la vista lateral (xn, z): labio superior y mandibula suben hacia atras y
# se juntan en la comisura (xn ~ 210 mm); en la cara frontal la misma regla cubre la mitad
# inferior de la nariz. L = xn + 0.9|s| recorre el labio desde la punta.
mi = np.flatnonzero(CORE & (xn < 230) & (ny > -0.35))
mxn, mz_, ms = xn[mi], zm[mi], s[mi]
zu = 11.0 + 0.10 * mxn                        # labio superior
zl_ = -24.0 + 0.265 * mxn                     # mandibula
gap = np.clip(zu - zl_, 0, None)
inside_m = (mz_ < zu) & (mz_ > zl_)
depth_m = np.clip(np.minimum(zu - mz_, mz_ - zl_) / np.maximum(gap * 0.5, 1e-3), 0, 1)
maw = mix(hexcol("#4a0d26"), hexcol("#020001"), sstep(0.0, 0.6, depth_m))
throat = sstep(0.5, 1.0, depth_m) * sstep(60, 0, mxn)
maw = mix(maw, hexcol("#1b0410"), throat)
paint(mi, maw, inside_m.astype(np.float32), rough=0.5, h=-0.3)
lip_u = np.exp(-((mz_ - zu) / 1.4) ** 2) * (gap > 0.5)
lip_l = np.exp(-((mz_ - zl_) / 1.4) ** 2) * (gap > 0.5)
paint(mi, hexcol("#170612"), np.maximum(lip_u, lip_l), rough=0.32, h=0.18)
paint(mi, hexcol("#7c1838"), np.maximum(np.exp(-((mz_ - zu + 2.2) / 0.7) ** 2),
                                        np.exp(-((mz_ - zl_ - 2.2) / 0.7) ** 2)) * inside_m * 0.8)
Lp = mxn + 0.9 * np.abs(ms)
for lip, sgn, spacing, Lmax, seed in ((zu, -1, 7.0, 17.0, 61), (zl_, 1, 8.5, 13.0, 67)):
    kk = np.round(Lp / spacing)
    jit = hash3(kk, kk * 0 + seed, kk * 0, seed)
    cxk = kk * spacing + (jit - 0.5) * 2.0
    L = Lmax * (0.4 + 0.6 * hash3(kk, kk * 0 + 1, kk * 0, seed)) * sstep(230, 120, cxk)
    t = sgn * (mz_ - lip) / np.maximum(L, 1e-3)            # 0 en el labio, 1 en la punta
    tc = np.clip(t, 0, 1)
    halfw = 2.2 * (1 - tc) ** 1.3 + 0.15
    curve = 0.35 * tc ** 2 * L * np.where(hash3(kk, kk * 0 + 2, kk * 0, seed) > 0.5, 1, -1)
    inT = (t > -0.08) & (t < 1) & (np.abs(Lp - cxk - curve) < halfw) & (L > 3) & (gap > 2)
    tooth = mix(hexcol("#f1e8cc"), hexcol("#c3eef2"), sstep(0.5, 1.0, tc))
    tooth = mix(tooth, hexcol("#8a7a55"), 0.35 * np.exp(-((np.abs(Lp - cxk - curve) - halfw) / 0.35) ** 2))
    paint(mi, tooth, inT.astype(np.float32), rough=0.14, h=0.35)
    COAT[mi] = np.maximum(COAT[mi], inT)
# ojos verdaderos (pequenos) sobre las comisuras
for sd in (-1, 1):
    sel = CORE & (sd * nx > 0.25) & (xn < 200)
    c, cn = surf_point(sel, (sd * 0.2, (XD0 - 96) / 1000, (42 - ZD0) / 1000))
    jj = np.flatnonzero(CORE & (xn < 200))
    d = np.linalg.norm(P[jj] - c.astype(np.float32), axis=1) * 1000
    paint(jj, hexcol("#000000"), 1 - sstep(10.5, 11.5, d), rough=0.04, h=0.45)
    paint(jj, hexcol("#1d6f7a"), np.exp(-((d - 9.0) / 0.9) ** 2) * (d < 11.5), e=CYAN * 0.25)
    paint(jj, hexcol("#0b0b0b"), np.exp(-((d - 12.5) / 0.9) ** 2) * 0.8)
    COAT[jj] = np.maximum(COAT[jj], 1 - sstep(10.5, 11.5, d))
# branquias: cuatro hendiduras curvas detras de la boca
for sd in (-1, 1):
    gi = np.flatnonzero(CORE & (sd * nx > 0.3) & (xn > 210) & (xn < 300))
    for kq, xg in enumerate((226, 243, 260, 277)):
        curve_x = xg + 7 * np.cos((zm[gi] - 10) / 30)
        dg = np.abs(xn[gi] - curve_x)
        span = (zm[gi] > -22 + kq * 2) & (zm[gi] < 42 - kq * 3)
        slit = (1 - sstep(0.9, 1.6, dg)) * span
        paint(gi, hexcol("#120309"), slit, rough=0.4, h=-0.2)
        paint(gi, hexcol("#c2263a"), np.exp(-((xn[gi] - curve_x + 1.6) / 0.6) ** 2) * span * 0.8,
              e=hexcol("#ff3b4f") * 0.25)
# costilla de union (coral) y cuerno (hueso)
rb = np.flatnonzero(FIN & (reg == 3) & WING)
lam = np.mod(xn[rb], 9.0) < 1.2
paint(rb, hexcol("#b8213a"), np.ones(rb.size), rough=0.35, e=hexcol("#ff3b4f") * 0.18)
paint(rb, hexcol("#5e0c1c"), lam.astype(np.float32), rough=0.5)
hn = np.flatnonzero(ELEV & (reg == 3))
paint(hn, hexcol("#d8cdb2"), np.ones(hn.size), rough=0.3, h=0.0)
# ojos falsos en la cara exterior de los winglets
for sd in (-1, 1):
    sel = WINGLET & (side == sd) & (sd * nx > 0.3)
    if not sel.any():
        continue
    jj = np.flatnonzero(sel)
    zz = zm[jj]
    yc = np.median(xn[jj][(zz > 110) & (zz < 130)])
    c, cn = surf_point(sel, (sd * 1.0, (XD0 - yc) / 1000, (122 - ZD0) / 1000))
    cn = cn / np.linalg.norm(cn)
    Uv = np.cross(cn, up)
    Uv /= np.linalg.norm(Uv)
    Vv = np.cross(Uv, cn)
    d3 = P[jj].astype(np.float64) - c
    eu, ev = d3 @ Uv * 1000, d3 @ Vv * 1000
    R = 34.0
    r_ = np.hypot(eu, ev) / R
    th = np.arctan2(ev, eu)
    iris_n = fbm(np.cos(th) * 3 + 5, np.sin(th) * 3, r_ * 6, 3, seed=71)
    striae = 0.5 + 0.5 * np.sin(th * 46 + iris_n * 6)
    iris = mix(hexcol("#7b8f12"), hexcol("#e3c53a"), sstep(0.22, 0.7, r_) * 0.8 + 0.2 * striae)
    iris = mix(iris, hexcol("#3a2a05"), sstep(0.58, 0.7, r_))
    pupil = (np.abs(eu) / (0.075 * R)) ** 2 + (np.abs(ev) / (0.36 * R)) ** 2 < 1
    paint(jj, hexcol("#120d1f"), (1 - sstep(1.12, 1.2, r_)), rough=0.3)
    paint(jj, hexcol("#6b58ff") * 0.7, np.exp(-((r_ - 0.9) / 0.06) ** 2), e=hexcol("#7d6bff") * 0.8)
    paint(jj, iris, (1 - sstep(0.7, 0.74, r_)), rough=0.05)
    paint(jj, hexcol("#010102"), pupil.astype(np.float32), rough=0.03)
    # la cornea es lisa: se borra el relieve de los radios bajo el ojo y se pone un domo
    HGT[jj] = np.where(r_ < 1.2, 0.6 * np.clip(1 - r_ ** 2, 0, 1) * (r_ < 0.8), HGT[jj])
    COAT[jj] = np.maximum(COAT[jj], (r_ < 0.8).astype(np.float32))

# ------------------------------------------------------------------------------- 7 regiones
log("cinta de bisagra, tapas de servo, helice")
tp = np.flatnonzero(reg == 1)
wrk = 0.5 + 0.5 * np.sin(np.hypot(xn[tp], s[tp]) * 1.9)
paint(tp, hexcol("#06080d"), np.ones(tp.size), rough=0.38, h=0.03 * wrk)
cv = np.flatnonzero(reg == 2)
paint(cv, hexcol("#2b3442"), np.ones(cv.size), rough=0.42, metal=0.35)
# tornillos de la tapa del servo
for sd in (-1, 1):
    jj = np.flatnonzero(WING & (reg == 2) & (side == sd))
    if jj.size == 0:
        continue
    x0, x1 = xn[jj].min() + 4, xn[jj].max() - 4
    s0, s1 = sa[jj].min() + 4, sa[jj].max() - 4
    for cx_ in (x0, x1):
        for cs_ in (s0, s1):
            d = np.hypot(xn[jj] - cx_, sa[jj] - cs_)
            paint(jj, hexcol("#8f96a0"), 1 - sstep(1.4, 1.8, d), rough=0.3, metal=0.9, h=0.12)
            cross = ((np.abs(xn[jj] - cx_) < 0.25) | (np.abs(sa[jj] - cs_) < 0.25)) & (d < 1.4)
            paint(jj, hexcol("#2a2e33"), cross.astype(np.float32), h=0.05)
    border = np.minimum.reduce([xn[jj] - x0 + 4, x1 + 4 - xn[jj], sa[jj] - s0 + 4, s1 + 4 - sa[jj]])
    paint(jj, hexcol("#11161e"), np.exp(-(border / 0.6) ** 2), h=-0.05)
pi_ = np.flatnonzero(PROP)
rp = np.hypot(x[pi_], z[pi_]) * 1000
paint(pi_, hexcol("#0a0b0d"), np.ones(pi_.size), rough=0.32)
weave = (np.mod(np.floor(rp / 1.2) + np.floor(y[pi_] * 1000 / 1.2), 2)).astype(np.float32)
paint(pi_, hexcol("#16181c"), 0.35 * weave * (rp > 25), rough=0.26)
paint(pi_, CYAN, (rp > 132).astype(np.float32), rough=0.2, e=CYAN * 0.85)
paint(pi_, hexcol("#e7f1f2"), ((rp > 124) & (rp < 129)).astype(np.float32), rough=0.3)

# ------------------------------------------------------------------------------- 8 desgaste
log("desgaste: desconchones, panza, insectos, suciedad, reparaciones")
FOAM = hexcol("#e6e2d6")
bead_n = vnoise(x * 900, y * 900, z * 900, seed=81)
foam_col = mix(FOAM * 0.9, FOAM, bead_n)
edge_w = np.zeros(n, np.float32)
fw = FIN & ~WINGLET
edge_w[fw] = np.exp(-(np.maximum(xn[fw] - LEs[fw], 0) / 4.0) ** 2)            # borde de ataque
edge_w[fw] = np.maximum(edge_w[fw], np.exp(-(np.maximum(TEs[fw] - xn[fw], 0) / 2.0) ** 2) * 0.6)
edge_w = np.maximum(edge_w, (WINGLET * sstep(0.6, 0.9, ny)).astype(np.float32))
edge_w = np.maximum(edge_w, (CORE * sstep(0.75, 0.95, ny) * (xn < 70)).astype(np.float32))
edge_w = np.maximum(edge_w, SEAM * 0.8)
edge_w = np.maximum(edge_w, (WINGLET * sstep(190, 207, zm)).astype(np.float32))
chipn = fbm(x * 260, y * 260, z * 260, 5, seed=83)
chips = sstep(0.03, 0.0, (1 - edge_w) * 0.75 + (0.62 - chipn) * 1.0)
chips = np.clip(chips, 0, 1) * (~PROP)
paint(np.arange(n), foam_col, chips, rough=0.88, metal=0.0, h=HGT - 0.12)
rim = np.clip(chips * (1 - chips) * 4, 0, 1)
COL[:] = mix(COL, COL * 0.6 + 0.02, 0.5 * rim)
# panza: rayones longitudinales y pasto (aterriza de barriga)
bi = np.flatnonzero(CORE & (nz < -0.5) & (xn > 40) & (xn < 560))
scr = vnoise(x[bi] * 2600, y[bi] * 60, z[bi] * 2600, seed=91)
scr2 = vnoise(x[bi] * 5200, y[bi] * 90, z[bi] * 5200, seed=93)
belly_w = sstep(-0.5, -0.9, nz[bi]) * (1 - sstep(400, 560, xn[bi]))
paint(bi, hexcol("#b8bcc0"), sstep(0.86, 0.94, scr) * belly_w * 0.8, rough=0.75, metal=0.1, h=-0.04)
paint(bi, hexcol("#e8e6dc"), sstep(0.93, 0.97, scr2) * belly_w, rough=0.85, h=-0.06)
grass = fbm(x[bi] * 140, y[bi] * 18, z[bi] * 140, 4, seed=95)
paint(bi, hexcol("#56622c"), sstep(0.64, 0.76, grass) * belly_w * 0.35, rough=0.85)
paint(bi, hexcol("#4b3b2a"), sstep(0.62, 0.8, fbm(x[bi] * 40, y[bi] * 15, z[bi] * 40, 3, seed=97)) * belly_w * 0.5,
      rough=0.9)
# rayones finos al azar en todo el lomo
ri2 = np.flatnonzero((nz > 0.2) & ~PROP)
for kseed in range(3):
    ang = 0.6 + kseed * 1.1
    ca, sa_ = math.cos(ang), math.sin(ang)
    a_ = (x[ri2] * ca + y[ri2] * sa_) * 1000
    b_ = (-x[ri2] * sa_ + y[ri2] * ca) * 1000
    cell = np.floor(b_ / 9.0)
    pos = hash3(cell, np.floor(a_ / 140), cell * 0 + kseed, 101 + kseed)
    line_ = np.abs(np.mod(b_, 9.0) - pos * 9) < 0.18
    on = hash3(cell, np.floor(a_ / 140), cell * 0 + 3, 107 + kseed) > 0.93
    paint(ri2, hexcol("#5c6a80"), (line_ & on).astype(np.float32) * 0.55, rough=0.6, h=HGT[ri2] - 0.02)
# insectos en los bordes de ataque
bg = np.flatnonzero(fw & (xn - LEs < 18) & (ny > 0.2))
cellb = np.floor(np.c_[x[bg], y[bg], z[bg]] * 1000 / 6.0)
hb = hash3(cellb[:, 0], cellb[:, 1], cellb[:, 2], 121)
cc = (cellb + 0.5) * 6.0
db_ = np.linalg.norm(np.c_[x[bg], y[bg], z[bg]] * 1000 - cc, axis=1)
splat = (hb > 0.9) * (1 - sstep(0.5, 1.3, db_))
halo_b = (hb > 0.9) * np.exp(-((db_ - 1.6) / 0.6) ** 2) * 0.5
paint(bg, hexcol("#2b2412"), splat, rough=0.3, h=0.05)
paint(bg, hexcol("#9c8a3c"), halo_b, rough=0.4)
# suciedad en ranuras: bisagras, junta de la tapa, union del ala, motor
grime = np.zeros(n, np.float32)
grime = np.maximum(grime, SEAM * 0.8)
hinge_d = np.abs(xn - X.hinge_x(np.clip(sa, 242, 878)).astype(np.float32))
grime = np.maximum(grime, (fw & (sa > 236)) * np.exp(-(hinge_d / 6.0) ** 2) * 0.7)
grime = np.maximum(grime, CORE * sstep(700, 790, xn) * 0.8)
grime = np.maximum(grime, (WING & (sa < 245)) * 0.6)
gn = fbm(x * 120, y * 120, z * 120, 4, seed=131)
paint(np.arange(n), hexcol("#1a1712"), grime * sstep(0.35, 0.75, gn) * 0.6, rough=0.75)
# huellas de manos: atras de la tapa y bajo el CG (lanzamiento a mano)
for (xc, sc_, nzs) in ((500, 0, 1), (430, -60, -1), (430, 60, -1)):
    jj = np.flatnonzero(BODY & (nzs * nz > 0.3) & (np.abs(xn - xc) < 60) & (np.abs(s - sc_) < 60))
    d = np.hypot(xn[jj] - xc, s[jj] - sc_)
    ridges = 0.5 + 0.5 * np.sin(np.hypot(xn[jj] - xc - 8 * hash3(np.floor(d / 30), d * 0, d * 0, 141),
                                         s[jj] - sc_) * 4.2)
    blot = (1 - sstep(10, 28, d)) * sstep(0.45, 0.6, fbm(x[jj] * 90, y[jj] * 90, z[jj] * 90, 3, seed=143))
    paint(jj, COL[jj] * 0.82 + 0.03, blot * ridges * 0.6, rough=RGH[jj] - 0.18)
# reparacion con cinta plateada en el borde de ataque izquierdo
tj = np.flatnonzero(WING & (s < -690) & (s > -760) & (xn - LEs < 34))
fray = fbm(x[tj] * 900, y[tj] * 900, z[tj] * 900, 3, seed=151)
edge_t = np.minimum(np.abs(s[tj] + 690), np.abs(s[tj] + 760))
tape_a = sstep(0.4, 2.5, edge_t + (fray - 0.5) * 3) * (1 - sstep(30, 34, xn[tj] - LEs[tj]))
cross_w = 0.5 + 0.5 * np.sin(s[tj] * 7) * np.sin(xn[tj] * 7)
paint(tj, mix(hexcol("#8e949a"), hexcol("#a9afb5"), cross_w), tape_a, rough=0.42, metal=0.45,
      h=HGT[tj] + 0.18)
# grieta pegada en la nariz (pegamento amarillento)
gj = np.flatnonzero(CORE & (nx < -0.3) & (xn > 60) & (xn < 135))
crack_path = 12 + 9 * np.sin(xn[gj] / 9.0) + 4 * np.sin(xn[gj] / 3.1)
dc = np.abs(zm[gj] - crack_path)
paint(gj, hexcol("#c6ad62"), np.exp(-(dc / 1.3) ** 2) * 0.55, rough=0.15, h=HGT[gj] + 0.08)
paint(gj, hexcol("#0d0a06"), (dc < 0.35).astype(np.float32) * 0.9, h=HGT[gj] - 0.1)
# polvo leve en el lomo
dust = sstep(0.55, 0.85, fbm(x * 30, y * 30, z * 30, 4, seed=161)) * sstep(0.6, 0.95, nz) * (~PROP)
paint(np.arange(n), hexcol("#4d5059"), dust * 0.18, rough=0.7)
RGH[:] = np.clip(RGH + 0.05 * (fbm(x * 500, y * 500, z * 500, 2, seed=171) - 0.5), 0.03, 1)

# ------------------------------------------------------------------------------- salida
log("escribiendo mapas")


def to_img(vals, fill, dtype=np.float32):
    ch = 1 if vals.ndim == 1 else vals.shape[1]
    out = np.empty((RES * RES, ch), dtype)
    out[:] = fill
    out[idx] = vals.reshape(n, ch)
    return out.reshape(RES, RES, ch)[::-1]          # fila 0 = arriba de la imagen (v alto)


def save(name, arr, mode):
    a = np.clip(arr, 0, 1)
    if a.shape[2] == 1:
        a = a[..., 0]
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), mode).save(os.path.join(TEX, name))


if NO_MARKS:                                     # solo la capa base, nada mas se toca
    os.makedirs(os.path.join(TEX, "layers"), exist_ok=True)
    save("layers/x8_abisal_paint_base.png", to_img(COL, hexcol("#0b1322")), "RGB")
    log("FIN sin rotulos", RES)
    sys.exit(0)
for nm_, arr in (("marking_alpha", MARK_A), ("insignia_alpha", INS_A)):
    Image.fromarray(np.round(np.clip(to_img(arr, 0.0)[..., 0], 0, 1) * 65535).astype(np.uint16)).save(
        os.path.join(TEX, "masks", f"{nm_}.png"))
save("x8_abisal_base_color.png", to_img(COL, hexcol("#0b1322")), "RGB")
save("x8_abisal_roughness.png", to_img(RGH, 0.5), "L")
save("x8_abisal_metallic.png", to_img(MET, 0.0), "L")
save("x8_abisal_emission.png", to_img(EMI, 0.0), "RGB")
save("x8_abisal_iridescence.png", to_img(IRI, 0.0), "L")
save("x8_abisal_coat.png", to_img(COAT, 0.0), "L")
H = to_img(HGT, 0.0)[..., 0]
np.save(os.path.join(WORK, "height_mm.npy"), H.astype(np.float32))
# altura editable de 16 bits (0..65535 = -2..+2 mm): livery_bake_textures.py la usa si no hay
# carpeta de trabajo, asi se puede retocar el color a mano y volver a hornear sin repintar
Image.fromarray(np.round(np.clip((H + 2.0) / 4.0, 0, 1) * 65535).astype(np.uint16)).save(
    os.path.join(TEX, "x8_abisal_height.png"))
Image.fromarray(np.clip(H / 1.6 + 0.5, 0, 1) * 255).convert("L").save(
    os.path.join(TEX, "masks", "height_preview.png"))
for nm_, arr in (("chips", chips), ("grime", grime), ("scale_edges", SCALE_EDGE), ("seam", SEAM)):
    Image.fromarray((to_img(arr, 0.0)[..., 0] * 255).astype(np.uint8), "L").save(
        os.path.join(TEX, "masks", f"{nm_}.png"))
log("FIN", RES)
