"""Contact sheet of the prop renders (JPG): python3 sheet.py renders_dir out.jpg"""
import sys
from PIL import Image, ImageDraw, ImageFont
D, OUT = sys.argv[1], sys.argv[2]
cells = [("catalogo", "Biblioteca: 9 hélices y 4 spinners para el O.S. 61SF"),
         ("a_hero", "A · APC Sport 12x6 + Tru-Turn Standard 2-1/2\""),
         ("b_hero", "B · Master Airscrew 3 palas 11x7 + Dubro 2-3/4\""),
         ("c_detalle", "C · APC Sport 11x7 + Dubro 2-1/2\""),
         ("d_detalle", "D · MA Scimitar 11x7 + Tru-Turn Ultimate 2-1/4\""),
         ("a_frente", "A de frente"), ("detalle_raices", "Raíz y buje APC 11x8"),
         ("spinners", "Spinners: Tru-Turn Standard y Ultimate (aluminio), Dubro 2-1/2\" y 2-3/4\" tripala (nylon)")]
W = 900
f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
ims = []
for n, t in cells:
    im = Image.open(f"{D}/{n}.png").convert("RGB")
    im = im.resize((W, int(im.height * W / im.width)))
    c = Image.new("RGB", (W, im.height + 40), (250, 250, 248))
    c.paste(im, (0, 40))
    ImageDraw.Draw(c).text((10, 8), t, fill=(20, 20, 20), font=f)
    ims.append(c)
def full(i):
    im = Image.open(f"{D}/{cells[i][0]}.png").convert("RGB")
    im = im.resize((W * 2, int(im.height * W * 2 / im.width)))
    c = Image.new("RGB", (W * 2, im.height + 40), (250, 250, 248))
    c.paste(im, (0, 40))
    ImageDraw.Draw(c).text((10, 8), cells[i][1], fill=(20, 20, 20), font=f)
    return c


rows = [full(0)]
pairs = ims[1:-1]
for a, b in zip(pairs[0::2], pairs[1::2]):
    r = Image.new("RGB", (W * 2, max(a.height, b.height)), (250, 250, 248))
    r.paste(a, (0, 0))
    r.paste(b, (W, 0))
    rows.append(r)
rows.append(full(len(cells) - 1))
H = sum(r.height for r in rows)
sheet = Image.new("RGB", (W * 2, H), (250, 250, 248))
y = 0
for r in rows:
    sheet.paste(r, (0, y))
    y += r.height
sheet.save(OUT, quality=88)
print("sheet", sheet.size)
