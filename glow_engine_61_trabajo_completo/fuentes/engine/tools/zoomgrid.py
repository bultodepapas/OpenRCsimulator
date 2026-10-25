"""zoomgrid.py IMG OUT x0 y0 x1 y1 [scale] [step] -> enlarged crop with a labelled pixel grid (original coords)."""
import sys
from PIL import Image, ImageDraw
img, out = sys.argv[1], sys.argv[2]
x0, y0, x1, y1 = map(int, sys.argv[3:7])
s = int(sys.argv[7]) if len(sys.argv) > 7 else 8
st = int(sys.argv[8]) if len(sys.argv) > 8 else 5
im = Image.open(img).convert("RGB").crop((x0, y0, x1, y1))
im = im.resize((im.width * s, im.height * s), Image.NEAREST if s >= 6 else Image.LANCZOS)
d = ImageDraw.Draw(im)
for x in range(x0 - x0 % st, x1 + 1, st):
    X = (x - x0) * s
    major = x % (st * 2) == 0
    d.line([(X, 0), (X, im.height)], fill=(255, 0, 0) if major else (0, 170, 255), width=1)
    if major:
        d.text((X + 2, 2), str(x), fill=(255, 0, 0))
for y in range(y0 - y0 % st, y1 + 1, st):
    Y = (y - y0) * s
    major = y % (st * 2) == 0
    d.line([(0, Y), (im.width, Y)], fill=(255, 0, 0) if major else (0, 170, 255), width=1)
    if major:
        d.text((2, Y + 2), str(y), fill=(255, 0, 0))
im.save(out)
