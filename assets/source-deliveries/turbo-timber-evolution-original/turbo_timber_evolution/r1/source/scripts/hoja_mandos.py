"""Hoja de contacto de extremos de mando: previews/_ctrl_*.png -> previews/control_extremes.png"""
import sys, os, json
from PIL import Image, ImageDraw, ImageFont
P = os.path.join(sys.argv[1], "previews")
et = json.load(open(os.path.join(P, "_ctrl_labels.json")))
ims = [Image.open(os.path.join(P, f"_ctrl_{i}.png")).convert("RGB") for i in range(len(et))]
w, h = ims[0].size; cols = 3; filas = (len(ims) + cols - 1)//cols
hoja = Image.new("RGB", (cols*w, filas*(h + 40)), (255, 255, 255)); d = ImageDraw.Draw(hoja)
try: f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
except Exception: f = ImageFont.load_default()
for i, (im, t) in enumerate(zip(ims, et)):
    x, y = (i % cols)*w, (i//cols)*(h + 40)
    hoja.paste(im, (x, y + 40)); d.text((x + 12, y + 8), t, fill=(20, 20, 20), font=f)
hoja.save(os.path.join(P, "control_extremes.png"))
for i in range(len(et)): os.remove(os.path.join(P, f"_ctrl_{i}.png"))
os.remove(os.path.join(P, "_ctrl_labels.json"))
print("HOJA OK", hoja.size)
