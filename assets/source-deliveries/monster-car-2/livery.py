"""Pintura y calcomanías de la carrocería "LOCURA" (diseño propio; patrocinadores inventados).

Genera un atlas de 4096x4096 con proyección por caras (la misma que asigna build_body en Blender):
  filas    0-1100  lado derecho (visto desde la derecha: el frente queda a la derecha)
  filas 1100-2200  lado izquierdo (visto desde la izquierda: el frente queda a la izquierda)
  filas 2200-3300  techo/capó/caja vistos desde arriba (frente a la derecha, lado izquierdo arriba)
  filas 3300-4096  frente (cols 0-2048) y cola (cols 2048-3968); cols 3968-4096: zona neutra (interior)
Salidas: carroceria_color.jpg, carroceria_mr.png (G=rugosidad, B=metálico), carroceria_emision.png,
         banda_parabrisas.png, placa.png, fibra_carbono.png
Mezcla de cuatro estilos: verde esmeralda metalizado + llamas caramelo + negro con neón + camuflaje digital.
"""
import math, os, random
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tex")
FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")
os.makedirs(OUT, exist_ok=True)
random.seed(8)
np.random.seed(8)

def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name + ".ttf"), int(size))

# ---------------- geometría (coordenadas locales de la carrocería, metros) ----------------
X0, X1 = -0.335, 0.335          # largo cubierto por las bandas laterales y superior
Z0, Z1 = 0.140, 0.360           # alto de las bandas laterales / frente / cola
Y0, Y1 = -0.200, 0.200          # ancho de la banda superior / frente / cola
XA, HW = 0.200, 0.163
ARCO_Z, ARCO_R = 0.0915, 0.1255
BELT = 0.236                    # línea de cintura (base de la cabina)
CAB_B = dict(xf=0.068, xr=-0.097, y=0.150, z=0.236)
CAB_T = dict(xf=0.002, xr=-0.086, y=0.122, z=0.312)
CAJA = dict(x0=-0.259, x1=-0.108, piso=0.215, borde=0.242)
COLA_X = -0.2745

def capo_z(x):
    return 0.2165 + (0.270 - x) * (0.0195 / 0.202)

# ---------------- paleta ----------------
VERDE = (6, 120, 52)
VERDE_OSC = (2, 52, 22)
NEGRO = (14, 14, 16)
BLANCO = (246, 246, 240)
ROSA = (255, 36, 168)
VERDE_NEON = (60, 255, 70)
AMARILLO = (255, 214, 0)
NARANJA = (255, 110, 0)
ROJO = (214, 10, 18)
AZUL = (10, 70, 230)
CAMO = [(64, 66, 62), (120, 116, 98), (176, 164, 128), (30, 34, 30), (86, 98, 70)]

S = 6100.0                      # píxeles por metro al dibujar (isótropo)


class Tile:
    """Lienzo isótropo de una vista; color, rugosidad/metálico y emisión en capas paralelas."""
    def __init__(self, name, ua, ub, va, vb, flip=False):
        self.name, self.ua, self.ub, self.va, self.vb, self.flip = name, ua, ub, va, vb, flip
        self.W = int(round((ub - ua) * S))
        self.H = int(round((vb - va) * S))
        self.col = Image.new("RGB", (self.W, self.H), VERDE)
        self.rough = Image.new("L", (self.W, self.H), 64)        # 0.25
        self.metal = Image.new("L", (self.W, self.H), 150)       # 0.6 (pintura metalizada)
        self.emis = Image.new("RGB", (self.W, self.H), (0, 0, 0))

    def P(self, u, v):
        """Coordenadas del vehículo (u = x o y, v = z o y) a píxeles."""
        c = (u - self.ua) / (self.ub - self.ua) * self.W
        if self.flip:
            c = self.W - c
        r = (self.vb - v) / (self.vb - self.va) * self.H
        return (c, r)

    def L(self, d):
        return d * S

    def mask(self):
        return Image.new("L", (self.W, self.H), 0)

    def paint(self, m, color, rough=None, metal=None, emis=None):
        """Pinta 'color' (tupla o imagen RGB) donde la máscara m es blanca."""
        src = color if isinstance(color, Image.Image) else Image.new("RGB", (self.W, self.H), color)
        self.col = Image.composite(src, self.col, m)
        if rough is not None:
            self.rough = Image.composite(Image.new("L", m.size, int(rough * 255)), self.rough, m)
        if metal is not None:
            self.metal = Image.composite(Image.new("L", m.size, int(metal * 255)), self.metal, m)
        e = Image.new("RGB", m.size, (0, 0, 0)) if emis is None else (
            emis if isinstance(emis, Image.Image) else Image.new("RGB", m.size, emis))
        self.emis = Image.composite(e, self.emis, m)

    def paste_rgba(self, im, xy, rough=0.35, metal=0.0, emis=None):
        """Pega una calcomanía RGBA (vinilo) en la posición de píxel xy (esquina sup. izq.)."""
        m = self.mask()
        m.paste(im.split()[3], (int(xy[0]), int(xy[1])))
        big = Image.new("RGB", (self.W, self.H), (0, 0, 0))
        big.paste(im.convert("RGB"), (int(xy[0]), int(xy[1])))
        self.paint(m, big, rough, metal, emis)


def grad(W, H, stops, horizontal=False):
    """Degradado RGB con paradas [(t, color)]."""
    n = W if horizontal else H
    t = np.linspace(0, 1, n)
    chans = []
    for k in range(3):
        chans.append(np.interp(t, [s[0] for s in stops], [s[1][k] for s in stops]))
    arr = np.stack(chans, -1).astype(np.uint8)
    if horizontal:
        arr = np.repeat(arr[None, :, :], H, 0)
    else:
        arr = np.repeat(arr[:, None, :], W, 1)
    return Image.fromarray(arr, "RGB")


def ring(m, px):
    """Anillo exterior de una máscara (para filetes y contornos)."""
    k = 2 * int(px) + 1
    return ImageChops.subtract(m.filter(ImageFilter.MaxFilter(k)), m)


def poly(tile, pts):
    m = tile.mask()
    ImageDraw.Draw(m).polygon([tile.P(*p) for p in pts], fill=255)
    return m


def text_img(txt, fnt, fill, outline=None, ow=0, shadow=None, sh_off=(0, 0), skew=0.0):
    """Texto RGBA con contorno, sombra desplazada e inclinación (itálica)."""
    bb = fnt.getbbox(txt)
    pad = ow * 2 + abs(sh_off[0]) + abs(sh_off[1]) + 8
    W, H = bb[2] - bb[0] + 2 * pad, bb[3] - bb[1] + 2 * pad
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    org = (pad - bb[0], pad - bb[1])
    if shadow:
        d.text((org[0] + sh_off[0], org[1] + sh_off[1]), txt, font=fnt, fill=shadow,
               stroke_width=ow, stroke_fill=shadow)
    d.text(org, txt, font=fnt, fill=fill, stroke_width=ow, stroke_fill=outline or fill)
    if skew:
        W2 = W + int(abs(skew) * H)
        im = im.transform((W2, H), Image.AFFINE, (1, skew, -skew * H if skew > 0 else 0, 0, 1, 0), Image.BICUBIC)
    return im.crop(im.getbbox())


def fit_text(txt, fname, w_max, h_max, **kw):
    size = 400
    while size > 6:
        f = font(fname, size)
        bb = f.getbbox(txt)
        if bb[2] - bb[0] <= w_max and bb[3] - bb[1] <= h_max:
            break
        size = int(size * 0.92)
    return text_img(txt, font(fname, size), **kw)


# ---------------- elementos gráficos ----------------
def camo_layer(tile, px=16):
    """Camuflaje digital: ruido de varias escalas, cuantizado a 5 tonos en celdas de 'px'."""
    w, h = tile.W // px + 2, tile.H // px + 2
    acc = np.zeros((h, w))
    for sc, amp in ((24, 1.0), (10, 0.6), (4, 0.35)):
        g = np.random.rand(h // sc + 2, w // sc + 2)
        g = np.array(Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)) / 255.0
        acc += amp * g
    acc = (acc - acc.min()) / (acc.max() - acc.min())
    idx = np.clip((acc * len(CAMO)).astype(int), 0, len(CAMO) - 1)
    arr = np.array(CAMO, dtype=np.uint8)[idx]
    im = Image.fromarray(arr, "RGB").resize((w * px, h * px), Image.NEAREST)
    return im.crop((0, 0, tile.W, tile.H))


def llamas(tile, x_ini, x_fin, z_lo, z_hi, n=6, seed=1, up=False):
    """Llamas de hot rod: lenguas que nacen juntas en el frente (raíz corta), se separan en abanico,
    ondulan en S y terminan en una punta fina curvada. Devuelve la máscara (L)."""
    rnd = random.Random(seed)
    m = tile.mask()
    d = ImageDraw.Draw(m)
    sgn = 1 if x_fin > x_ini else -1
    largo_tot = abs(x_fin - x_ini)
    alto = z_hi - z_lo
    paso = alto / n
    for i in range(n):
        frac = (i + 0.5) / n
        z0 = z_lo + alto * (0.5 + (frac - 0.5) * 0.80)
        largo = largo_tot * (0.50 + 0.50 * (1 - abs(frac - 0.55) * 1.5) ** 0.8) * (0.85 + 0.25 * rnd.random())
        largo = min(largo, largo_tot)
        w0 = paso * (1.45 + 0.35 * rnd.random())
        fase = rnd.uniform(0, 6.28)
        amp = alto * rnd.uniform(0.06, 0.11)
        abanico = (frac - 0.5) * alto * 0.45
        rizo = alto * rnd.uniform(0.10, 0.20) * (1 if frac > 0.4 else -0.7)
        top, bot = [], []
        N = 120
        for k in range(N + 1):
            t = k / N
            x = x_ini + sgn * largo * t
            zc = z0 + abanico * t + amp * math.sin(fase + 2.6 * math.pi * t) * t ** 0.9 + rizo * t ** 3
            w = w0 * (1 - t) ** 1.05 * (1 + 0.22 * math.sin(8.5 * t + fase)) + 0.0003
            top.append(tile.P(x, zc + w / 2))
            bot.append(tile.P(x, zc - w / 2))
        d.polygon(top + bot[::-1], fill=255)
    m = m.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.MinFilter(7))      # cierra huecos entre lenguas
    return m.filter(ImageFilter.GaussianBlur(1.5)).point(lambda p: 255 if p > 120 else 0)


def degradado_x(tile, x_ini, x_fin, stops):
    """Degradado según la coordenada x (o y) del vehículo, sin importar el espejo de la vista."""
    cols = np.arange(tile.W) + 0.5
    if tile.flip:
        cols = tile.W - cols
    xv = tile.ua + cols / tile.W * (tile.ub - tile.ua)
    t = np.clip((x_ini - xv) / (x_ini - x_fin), 0, 1)
    ch = [np.interp(t, [s_[0] for s_ in stops], [s_[1][k] for s_ in stops]) for k in range(3)]
    row = np.stack(ch, -1).astype(np.uint8)
    return Image.fromarray(np.repeat(row[None, :, :], tile.H, 0), "RGB")


def pintar_llamas(tile, m, x_ini, x_fin):
    """Relleno caramelo (amarillo en la raíz -> naranja -> rojo en las puntas), filete neón rosa,
    contorno negro y sombra."""
    if not m.getbbox():
        return
    g = degradado_x(tile, x_ini, x_fin, [(0.0, (255, 232, 70)), (0.12, (255, 182, 0)), (0.33, (255, 96, 0)),
                                          (0.58, (228, 18, 20)), (0.82, (176, 0, 44)), (1.0, (118, 0, 70))])
    sombra = ImageChops.offset(m, int(tile.L(0.0014)), int(tile.L(0.0014)))
    tile.paint(ImageChops.subtract(sombra, m), (8, 30, 14), 0.5, 0.0)
    tile.paint(ring(m, tile.L(0.0020)), NEGRO, 0.5, 0.0)
    tile.paint(m, g, 0.15, 0.4)
    tile.paint(ring(m, tile.L(0.0009)), ROSA, 0.3, 0.0, ROSA)


def roundel(tile, cx, cz, r, num="08"):
    c = tile.P(cx, cz)
    R = tile.L(r)
    for rr, col, em in ((1.18, VERDE_NEON, VERDE_NEON), (1.10, NEGRO, None), (1.0, BLANCO, None)):
        m = tile.mask()
        ImageDraw.Draw(m).ellipse([c[0] - R * rr, c[1] - R * rr, c[0] + R * rr, c[1] + R * rr], fill=255)
        tile.paint(m, col, 0.3, 0.0, em)
    t = fit_text(num, "racing-sans-one", R * 1.55, R * 1.25, fill=NEGRO + (255,), outline=NEGRO + (255,), ow=2,
                 shadow=ROSA + (255,), sh_off=(5, 4), skew=-0.18)
    tile.paste_rgba(t, (c[0] - t.width / 2, c[1] - t.height / 2))


ICONOS = {}

def icono(kind, s, col):
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if kind == "rayo":
        d.polygon([(s * .55, 0), (s * .15, s * .58), (s * .45, s * .58), (s * .30, s), (s * .85, s * .38),
                   (s * .55, s * .38), (s * .75, 0)], fill=col)
    elif kind == "llama":
        d.polygon([(s * .5, 0), (s * .8, s * .45), (s * .7, s * .3), (s * .9, s * .75), (s * .5, s),
                   (s * .1, s * .75), (s * .3, s * .3), (s * .2, s * .45)], fill=col)
    elif kind == "estrella":
        pts = []
        for k in range(10):
            a = -math.pi / 2 + k * math.pi / 5
            rr = s * (0.5 if k % 2 == 0 else 0.21)
            pts.append((s / 2 + rr * math.cos(a), s / 2 + rr * math.sin(a)))
        d.polygon(pts, fill=col)
    elif kind == "piston":
        d.rounded_rectangle([s * .2, s * .05, s * .8, s * .45], radius=s * .06, fill=col)
        d.rectangle([s * .45, s * .45, s * .55, s * .9], fill=col)
        d.ellipse([s * .35, s * .8, s * .65, s], fill=col)
    elif kind == "garra":
        for k in range(3):
            x = s * (0.22 + 0.25 * k)
            d.polygon([(x, s * .02), (x + s * .12, s * .02), (x + s * .02, s * .98), (x - s * .06, s * .98)], fill=col)
    elif kind == "mango":
        d.ellipse([s * .12, s * .2, s * .88, s * .95], fill=col)
        d.polygon([(s * .5, s * .22), (s * .7, 0), (s * .85, s * .08)], fill=(40, 160, 40, 255))
    elif kind == "condor":
        d.polygon([(0, s * .45), (s * .5, s * .3), (s, s * .45), (s * .6, s * .55), (s * .5, s * .8), (s * .4, s * .55)], fill=col)
    return im


PATROCINIOS = [
    ("NITRO LLAMA", "racing-sans-one", NARANJA, NEGRO, "llama", AMARILLO),
    ("TURBO MANGO", "bangers", (255, 200, 0), (20, 90, 30), "mango", (255, 120, 0)),
    ("RUGIDO RACING", "black-ops-one", NEGRO, ROJO, "garra", ROJO),
    ("PISTÓN LOCO", "russo-one", BLANCO, AZUL, "piston", AZUL),
    ("VOLTIO", "racing-sans-one", (20, 110, 255), AMARILLO, "rayo", AMARILLO),
    ("CHISPA", "bangers", ROSA, BLANCO, "estrella", BLANCO),
    ("ACEITE CÓNDOR", "russo-one", ROJO, BLANCO, "condor", BLANCO),
    ("GARRA 4X4", "black-ops-one", (40, 40, 44), VERDE_NEON, "garra", VERDE_NEON),
    ("TROPI-TORQUE", "racing-sans-one", (0, 150, 70), AMARILLO, "estrella", AMARILLO),
    ("MOTO-RAYO", "bangers", (120, 30, 200), BLANCO, "rayo", AMARILLO),
]


def sticker(i, w_px, h_px):
    txt, fname, bg, fg, ic, icol = PATROCINIOS[i % len(PATROCINIOS)]
    im = Image.new("RGBA", (w_px, h_px), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rad = int(h_px * 0.22)
    d.rounded_rectangle([0, 0, w_px - 1, h_px - 1], radius=rad, fill=BLANCO + (255,))
    b = max(2, int(h_px * 0.07))
    d.rounded_rectangle([b, b, w_px - 1 - b, h_px - 1 - b], radius=rad - b, fill=bg + (255,))
    s_ic = int(h_px * 0.72)
    ic_im = icono(ic, s_ic, icol + (255,))
    im.alpha_composite(ic_im, (int(h_px * 0.16), (h_px - s_ic) // 2))
    t = fit_text(txt, fname, w_px - s_ic - h_px * 0.45, h_px * 0.62, fill=fg + (255,),
                 outline=NEGRO + (255,), ow=max(1, h_px // 40), skew=-0.12)
    im.alpha_composite(t, (int(s_ic + h_px * 0.28 + (w_px - s_ic - h_px * 0.45 - t.width) / 2),
                           int((h_px - t.height) / 2)))
    return im


def tablero(tile, x0, x1, v0, v1, cell, horizontal=True):
    """Bandera a cuadros entre (x0, v0) y (x1, v1) en coordenadas del vehículo."""
    m = tile.mask()
    d = ImageDraw.Draw(m)
    nx = int(abs(x1 - x0) / cell + 0.5)
    nv = int(abs(v1 - v0) / cell + 0.5)
    for i in range(nx):
        for j in range(nv):
            if (i + j) % 2 == 0:
                a = tile.P(x0 + (x1 - x0) * i / nx, v0 + (v1 - v0) * j / nv)
                b = tile.P(x0 + (x1 - x0) * (i + 1) / nx, v0 + (v1 - v0) * (j + 1) / nv)
                d.rectangle([min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])], fill=255)
    zona = poly(tile, [(x0, v0), (x1, v0), (x1, v1), (x0, v1)])
    tile.paint(zona, BLANCO, 0.35, 0.0)
    tile.paint(m, NEGRO, 0.35, 0.0)


def garras(tile, xc, zc, h, ang=0.55):
    """Tres zarpazos que 'rompen' la pintura y dejan ver el interior negro con brillo neón."""
    m = tile.mask()
    d = ImageDraw.Draw(m)
    for k in range(3):
        cx = xc + (k - 1) * h * 0.38
        pts_l, pts_r = [], []
        N = 14
        for i in range(N + 1):
            t = i / N
            w = h * 0.075 * math.sin(math.pi * t) ** 0.8
            jag = (0.35 if i % 2 else -0.35) * w
            x = cx + (t - 0.5) * h * math.tan(ang)
            z = zc + (0.5 - t) * h
            pts_l.append(tile.P(x - w + jag, z))
            pts_r.append(tile.P(x + w + jag, z))
        d.polygon(pts_l + pts_r[::-1], fill=255)
    tile.paint(ring(m, tile.L(0.0016)), (200, 200, 205), 0.15, 1.0)     # borde de metal rasgado
    interior = grad(tile.W, tile.H, [(0, (5, 30, 8)), (0.5, (20, 140, 30)), (1, (5, 30, 8))])
    tile.paint(m, interior, 0.6, 0.0, (10, 120, 20))


# ---------------- lados ----------------
def lado(flip):
    t = Tile("lado_izq" if flip else "lado_der", X0, X1, Z0, Z1, flip)
    # base: verde esmeralda con degradado (más claro arriba) y destellos del metalizado
    base = grad(t.W, t.H, [(0.0, (16, 170, 78)), (0.45, VERDE), (1.0, VERDE_OSC)])
    t.paint(Image.new("L", (t.W, t.H), 255), base, 0.22, 0.65)
    # banda inferior negra + camuflaje digital bajo una línea que sube hacia atrás
    def linea_baja(x):
        return 0.176 + (0.272 - x) * (0.024 / 0.55)
    pts = [(X1, linea_baja(X1)), (X0, linea_baja(X0)), (X0, Z0), (X1, Z0)]
    zona = poly(t, pts)
    t.paint(zona, camo_layer(t, 16), 0.6, 0.0)
    filo = poly(t, [(X1, linea_baja(X1) + 0.0035), (X0, linea_baja(X0) + 0.0035),
                    (X0, linea_baja(X0)), (X1, linea_baja(X1))])
    t.paint(filo, VERDE_NEON, 0.3, 0.0, VERDE_NEON)
    filo2 = poly(t, [(X1, linea_baja(X1) + 0.0055), (X0, linea_baja(X0) + 0.0055),
                     (X0, linea_baja(X0) + 0.0042), (X1, linea_baja(X1) + 0.0042)])
    t.paint(filo2, NEGRO, 0.4, 0.0)
    # llamas desde el frente hasta la puerta
    m = llamas(t, 0.292, 0.036, 0.186, 0.234, n=6, seed=11)
    pintar_llamas(t, m, 0.292, 0.036)
    # líneas de la puerta (separación de paneles) y cerradura
    for x in (0.064, -0.071):
        t.paint(poly(t, [(x - 0.0004, 0.161), (x + 0.0004, 0.161), (x + 0.0004, 0.300), (x - 0.0004, 0.300)]),
                (5, 10, 6), 0.6, 0.0)
    t.paint(poly(t, [(0.064, 0.1606), (-0.071, 0.1606), (-0.071, 0.1614), (0.064, 0.1614)]), (5, 10, 6), 0.6, 0.0)
    # número en la puerta
    roundel(t, -0.004, 0.206, 0.024)
    # zarpazos y nombre en la caja
    garras(t, -0.098, 0.213, 0.046)
    nombre = text_img("LOCURA", font("bangers", t.L(0.034)), fill=BLANCO + (255,), outline=NEGRO + (255,),
                      ow=int(t.L(0.0015)), shadow=ROSA + (255,), sh_off=(int(t.L(0.0020)), int(t.L(0.0018))),
                      skew=-0.15)
    c = t.P(-0.200, 0.2225)
    t.paste_rgba(nombre, (c[0] - nombre.width / 2, c[1] - nombre.height / 2), 0.3, 0.0)
    # calcomanías: guardabarros delantero (abajo y arriba), puerta, guardabarros trasero
    pos = [(0.030, 0.1775, 0.048, 0.0125, 0), (0.030, 0.1645, 0.044, 0.011, 1), (-0.040, 0.1645, 0.044, 0.011, 2),
           (0.104, 0.1715, 0.032, 0.0095, 3), (0.104, 0.1825, 0.032, 0.0095, 4), (-0.040, 0.1775, 0.044, 0.011, 9),
           (-0.290, 0.272, 0.046, 0.0125, 6)]
    for x, z, w, h, i in pos:
        st = sticker(i + (0 if not flip else 2), int(t.L(w)), int(t.L(h)))
        c = t.P(x, z)
        t.paste_rgba(st, (c[0] - st.width / 2, c[1] - st.height / 2))
    # placas de la cabina sobre la ventana trasera: "4X4" y tanque
    t4 = text_img("4X4", font("black-ops-one", t.L(0.012)), fill=BLANCO + (255,), outline=NEGRO + (255,), ow=3)
    c = t.P(0.036, 0.2455)
    t.paste_rgba(t4, (c[0] - t4.width / 2, c[1] - t4.height / 2))
    # aletas del alerón (zona sobre la caja): cuadros + "08"
    t.paint(poly(t, [(-0.335, 0.258), (-0.240, 0.258), (-0.240, 0.350), (-0.335, 0.350)]), NEGRO, 0.4, 0.0)
    tablero(t, -0.335, -0.240, 0.333, 0.346, 0.0065)
    em = text_img("08", font("racing-sans-one", t.L(0.030)), fill=VERDE_NEON + (255,), outline=NEGRO + (255,),
                  ow=4, skew=-0.2)
    c = t.P(-0.300, 0.3175)
    t.paste_rgba(em, (c[0] - em.width / 2, c[1] - em.height / 2), 0.3, 0.0, VERDE_NEON)
    return t


# ---------------- techo / capó / caja ----------------
def arriba():
    t = Tile("arriba", X0, X1, Y0, Y1)
    base = grad(t.W, t.H, [(0.0, VERDE), (0.5, (14, 150, 66)), (1.0, VERDE)])
    t.paint(Image.new("L", (t.W, t.H), 255), base, 0.22, 0.65)
    # caja: recubrimiento texturizado negro
    caja = poly(t, [(CAJA["x1"], -0.153), (CAJA["x0"], -0.153), (CAJA["x0"], 0.153), (CAJA["x1"], 0.153)])
    ruido = Image.fromarray((np.random.rand(t.H, t.W) * 26 + 20).astype(np.uint8), "L").convert("RGB")
    t.paint(caja, ruido, 0.9, 0.0)
    # franjas de carrera negras con filete rosa: capó y techo
    for y0, y1 in ((0.010, 0.032), (-0.032, -0.010)):
        for xa, xb in ((0.068, 0.300), (-0.097, 0.068)):
            f = poly(t, [(xa, y0), (xb, y0), (xb, y1), (xa, y1)])
            t.paint(f, NEGRO, 0.35, 0.0)
            t.paint(ring(f, t.L(0.0010)), ROSA, 0.3, 0.0, ROSA)
    # llamas en el capó (hacia atrás desde la nariz), simétricas
    for lo_, hi_ in ((0.036, 0.152), (-0.152, -0.036)):
        m = llamas(t, 0.292, 0.098, lo_, hi_, n=5, seed=31)
        pintar_llamas(t, m, 0.292, 0.098)
    # techo: cuadros atrás + número grande
    tablero(t, -0.088, -0.062, -0.124, 0.124, 0.0062)
    roundel(t, -0.030, 0.0, 0.033)
    return t


# ---------------- frente y cola ----------------
def frente():
    t = Tile("frente", Y0, Y1, Z0, Z1)
    base = grad(t.W, t.H, [(0.0, (16, 170, 78)), (0.5, VERDE), (1.0, VERDE_OSC)])
    t.paint(Image.new("L", (t.W, t.H), 255), base, 0.22, 0.65)
    # labio inferior con franjas de peligro amarillo/negro y filo neón
    lab = poly(t, [(-0.20, 0.140), (0.20, 0.140), (0.20, 0.170), (-0.20, 0.170)])
    t.paint(lab, AMARILLO, 0.4, 0.0)
    m = t.mask()
    d = ImageDraw.Draw(m)
    for k in range(-30, 30):
        y = k * 0.012
        d.polygon([t.P(y, 0.140), t.P(y + 0.006, 0.140), t.P(y + 0.006 + 0.03, 0.170), t.P(y + 0.03, 0.170)], fill=255)
    t.paint(ImageChops.multiply(m, lab), NEGRO, 0.4, 0.0)
    t.paint(poly(t, [(-0.20, 0.170), (0.20, 0.170), (0.20, 0.1735), (-0.20, 0.1735)]), VERDE_NEON, 0.3, 0.0, VERDE_NEON)
    # marco del parabrisas: negro
    t.paint(poly(t, [(-0.20, 0.236), (0.20, 0.236), (0.20, 0.36), (-0.20, 0.36)]), NEGRO, 0.35, 0.0)
    return t


def cola():
    t = Tile("cola", Y0, Y1, Z0, Z1, flip=True)
    base = grad(t.W, t.H, [(0.0, (16, 170, 78)), (0.5, VERDE), (1.0, VERDE_OSC)])
    t.paint(Image.new("L", (t.W, t.H), 255), base, 0.22, 0.65)
    camo = poly(t, [(-0.20, 0.140), (0.20, 0.140), (0.20, 0.176), (-0.20, 0.176)])
    t.paint(camo, camo_layer(t, 16), 0.6, 0.0)
    t.paint(poly(t, [(-0.20, 0.176), (0.20, 0.176), (0.20, 0.1795), (-0.20, 0.1795)]), VERDE_NEON, 0.3, 0.0, VERDE_NEON)
    tablero(t, -0.160, 0.160, 0.224, 0.236, 0.006)
    nm = text_img("LOCURA", font("bangers", t.L(0.040)), fill=BLANCO + (255,), outline=NEGRO + (255,),
                  ow=int(t.L(0.0016)), shadow=ROSA + (255,), sh_off=(int(t.L(0.0022)), int(t.L(0.002))), skew=-0.15)
    c = t.P(0.0, 0.201)
    t.paste_rgba(nm, (c[0] - nm.width / 2, c[1] - nm.height / 2))
    for i, y in ((8, 0.115), (9, -0.115)):
        st = sticker(i, int(t.L(0.050)), int(t.L(0.013)))
        c = t.P(y, 0.186)
        t.paste_rgba(st, (c[0] - st.width / 2, c[1] - st.height / 2))
    # cabina trasera: negro con filo rosa
    t.paint(poly(t, [(-0.20, 0.242), (0.20, 0.242), (0.20, 0.36), (-0.20, 0.36)]), NEGRO, 0.35, 0.0)
    return t


# ---------------- atlas ----------------
def atlas():
    W = H = 4096
    col = Image.new("RGB", (W, H), (20, 20, 20))
    mr = Image.new("RGB", (W, H), (0, 230, 0))
    em = Image.new("RGB", (W, H), (0, 0, 0))
    slots = [(lado(False), (0, 0, 4096, 1100)), (lado(True), (0, 1100, 4096, 2200)),
             (arriba(), (0, 2200, 4096, 3300)), (frente(), (0, 3300, 2048, 4096)), (cola(), (2048, 3300, 3968, 4096))]
    for t, (a, b, c, d) in slots:
        size = (c - a, d - b)
        col.paste(t.col.resize(size, Image.LANCZOS), (a, b))
        mrt = Image.merge("RGB", (Image.new("L", t.rough.size, 0), t.rough, t.metal)).resize(size, Image.LANCZOS)
        mr.paste(mrt, (a, b))
        em.paste(t.emis.resize(size, Image.LANCZOS), (a, b))
    # zona neutra (interiores): negro mate
    col.paste((22, 22, 24), (3968, 3300, 4096, 3428))
    mr.paste((0, 200, 0), (3968, 3300, 4096, 3428))
    col.save(os.path.join(OUT, "carroceria_color.jpg"), quality=93, subsampling=0)
    mr.save(os.path.join(OUT, "carroceria_mr.png"), optimize=True)
    em.save(os.path.join(OUT, "carroceria_emision.png"), optimize=True)
    # vista previa reducida para revisar el diseño
    col.resize((2048, 2048), Image.LANCZOS).save(os.path.join(OUT, "vista_atlas.jpg"), quality=88)


def extras():
    # banda del parabrisas
    W, H = 2048, 256
    im = Image.new("RGB", (W, H), NEGRO)
    t = text_img("LOCURA 4X4", font("bangers", 190), fill=BLANCO + (255,), outline=NEGRO + (255,), ow=4,
                 shadow=ROSA + (255,), sh_off=(10, 8), skew=-0.15)
    t = t.resize((int(t.width * min(1, (W - 120) / t.width)), int(t.height * min(1, (W - 120) / t.width))))
    im.paste(t, ((W - t.width) // 2, (H - t.height) // 2), t)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, 10], fill=VERDE_NEON)
    d.rectangle([0, H - 11, W, H], fill=VERDE_NEON)
    im.save(os.path.join(OUT, "banda_parabrisas.png"))
    # placa
    W, H = 1024, 512
    im = Image.new("RGB", (W, H), (235, 235, 228))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([12, 12, W - 12, H - 12], radius=40, outline=NEGRO, width=14)
    d.rectangle([12, 12, W - 12, 110], fill=VERDE)
    tt = text_img("TIERRA DE MONSTRUOS", font("russo-one", 58), fill=BLANCO + (255,))
    im.paste(tt, ((W - tt.width) // 2, 35), tt)
    tp = text_img("LOKO-08", font("russo-one", 210), fill=NEGRO + (255,))
    im.paste(tp, ((W - tp.width) // 2, 165), tp)
    im.save(os.path.join(OUT, "placa.png"))
    # fibra de carbono (sarga 2x2), repetible
    N = 512
    y, x = np.mgrid[0:N, 0:N]
    cell = 32
    u, v = (x // cell), (y // cell)
    tw = ((u + v) // 2) % 2
    fx = np.sin((x % cell) / cell * np.pi)
    fy = np.sin((y % cell) / cell * np.pi)
    shade = np.where(tw == 0, 0.55 + 0.45 * fy, 0.55 + 0.45 * fx)
    arr = (np.stack([shade * 46, shade * 48, shade * 54], -1) + 6).clip(0, 255).astype(np.uint8)
    Image.fromarray(arr, "RGB").save(os.path.join(OUT, "fibra_carbono.png"))


if __name__ == "__main__":
    atlas()
    extras()
    print("listo:", sorted(os.listdir(OUT)))
