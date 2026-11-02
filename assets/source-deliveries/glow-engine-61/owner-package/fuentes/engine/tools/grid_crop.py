"""grid_crop.py IMAGE x0 y0 x1 y1 OUT [step] [scale] : crop with a labelled pixel grid (original coordinates)."""
import sys
from PIL import Image, ImageDraw
f, x0, y0, x1, y1, out = sys.argv[1], *map(int, sys.argv[2:6]), sys.argv[6]
step = int(sys.argv[7]) if len(sys.argv) > 7 else 50
sc = float(sys.argv[8]) if len(sys.argv) > 8 else 1.0
im = Image.open(f).convert("RGB").crop((x0, y0, x1, y1))
im = im.resize((round(im.width * sc), round(im.height * sc)))
d = ImageDraw.Draw(im)
for x in range((x0 // step + 1) * step, x1, step):
    X = (x - x0) * sc
    d.line([(X, 0), (X, im.height)], fill=(0, 255, 255) if x % (step * 2) else (255, 0, 255), width=1)
    d.text((X + 2, 2), str(x), fill=(255, 0, 0))
for y in range((y0 // step + 1) * step, y1, step):
    Y = (y - y0) * sc
    d.line([(0, Y), (im.width, Y)], fill=(0, 255, 255) if y % (step * 2) else (255, 0, 255), width=1)
    d.text((2, Y + 2), str(y), fill=(255, 0, 0))
im.save(out)
