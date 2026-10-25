"""gridview.py IMG OUT [scale] [step] [crop x0 y0 x1 y1] -> downscaled image with labelled grid in ORIGINAL coords."""
import sys
from PIL import Image, ImageDraw
img, out = sys.argv[1:3]
s = float(sys.argv[3]) if len(sys.argv) > 3 else 0.6
st = int(sys.argv[4]) if len(sys.argv) > 4 else 100
im = Image.open(img).convert("RGB")
c = list(map(int, sys.argv[5:9])) if len(sys.argv) > 8 else [0, 0, im.width, im.height]
im = im.crop(c).resize((round((c[2] - c[0]) * s), round((c[3] - c[1]) * s)), Image.LANCZOS)
d = ImageDraw.Draw(im)
for x in range(c[0] - c[0] % st + st, c[2], st):
    X = (x - c[0]) * s
    d.line([(X, 0), (X, im.height)], fill=(255, 0, 0) if x % (st * 2) == 0 else (0, 150, 255), width=1)
    d.text((X + 2, 2), str(x), fill=(200, 0, 0))
for y in range(c[1] - c[1] % st + st, c[3], st):
    Y = (y - c[1]) * s
    d.line([(0, Y), (im.width, Y)], fill=(255, 0, 0) if y % (st * 2) == 0 else (0, 150, 255), width=1)
    d.text((2, Y + 2), str(y), fill=(200, 0, 0))
im.save(out)
