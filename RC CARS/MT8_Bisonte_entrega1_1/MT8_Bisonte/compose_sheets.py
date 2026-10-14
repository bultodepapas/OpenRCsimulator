"""Compone hojas de contacto JPG con las capturas para el documento (out/sheets)."""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
R = os.path.join(HERE, "out", "renders")
O = os.path.join(HERE, "out", "sheets")
os.makedirs(O, exist_ok=True)
FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)


def sheet(name, items, cols=2, w=800):
    ims = []
    for fn, label in items:
        im = Image.open(os.path.join(R, fn + ".png")).convert("RGB")
        h = int(im.height * w / im.width)
        im = im.resize((w, h), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        tw = d.textlength(label, font=FONT)
        d.rectangle((12, 12, 12 + tw + 20, 48), fill=(255, 255, 255))
        d.text((22, 16), label, fill=(20, 20, 20), font=FONT)
        ims.append(im)
    rows = (len(ims) + cols - 1) // cols
    gap = 8
    W = cols * w + (cols - 1) * gap
    H = rows * ims[0].height + (rows - 1) * gap
    out = Image.new("RGB", (W, H), (255, 255, 255))
    for i, im in enumerate(ims):
        out.paste(im, ((i % cols) * (w + gap), (i // cols) * (im.height + gap)))
    out.save(os.path.join(O, name + ".jpg"), quality=86)


def single(fn, w=1280):
    im = Image.open(os.path.join(R, fn + ".png")).convert("RGB")
    im.save(os.path.join(O, fn + ".jpg"), quality=88)


single("01_tres_cuartos_delantero")
single("02_tres_cuartos_trasero")
sheet("vistas_ortogonales", [("03_frontal", "Frontal"), ("04_lateral_izquierdo", "Lateral izquierda"),
                             ("05_superior", "Superior"), ("06_inferior", "Inferior")])
single("07_bajos_tres_cuartos")
sheet("extremos_suspension_direccion", [("10_compresion_max_giro_izq_30", "Compresión máx. + giro izq. 30°"),
                                        ("11_extension_max_giro_der_30", "Extensión máx. + giro der. 30°"),
                                        ("12_frontal_extension_max", "Frontal, extensión máx."),
                                        ("13_frontal_compresion_max", "Frontal, compresión máx."),
                                        ("14_superior_giro_izq_30", "Superior, giro izq. 30°"),
                                        ("15_articulacion_cruzada", "Articulación cruzada")])
sheet("volcado", [("20_volcado_techo", "Sobre el techo"), ("21_volcado_costado", "Sobre el costado")])
single("30_proxies_colision")
print(sorted(os.listdir(O)))
