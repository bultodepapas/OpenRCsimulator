"""mark.py IMG OUT 'name:x,y;name:x,y;...' [crop x0 y0 x1 y1] [scale] -> draws labelled markers (orig coords)."""
import sys
from PIL import Image, ImageDraw
img, out, spec = sys.argv[1:4]
im = Image.open(img).convert("RGB")
pts = []
for item in spec.split(";"):
    if item.strip():
        n, xy = item.split(":")
        x, y = map(float, xy.split(","))
        pts.append((n, x, y))
crop = list(map(int, sys.argv[4:8])) if len(sys.argv) >= 8 else [0, 0, im.width, im.height]
s = float(sys.argv[8]) if len(sys.argv) >= 9 else 1.0
im = im.crop(crop).resize((round((crop[2] - crop[0]) * s), round((crop[3] - crop[1]) * s)), Image.LANCZOS)
d = ImageDraw.Draw(im)
cols = [(255, 0, 0), (0, 160, 255), (0, 200, 0), (255, 0, 255), (255, 140, 0), (0, 0, 0)]
for i, (n, x, y) in enumerate(pts):
    X, Y = (x - crop[0]) * s, (y - crop[1]) * s
    c = cols[i % len(cols)]
    d.ellipse([X - 5, Y - 5, X + 5, Y + 5], outline=c, width=2)
    d.line([X - 9, Y, X + 9, Y], fill=c); d.line([X, Y - 9, X, Y + 9], fill=c)
    d.text((X + 8, Y - 14), n, fill=c)
im.save(out)
