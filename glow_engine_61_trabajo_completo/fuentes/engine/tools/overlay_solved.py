"""overlay_solved.py photo render out [crop x0 y0 x1 y1 in photo px] -> outline + 50% blend sheet."""
import sys
from PIL import Image, ImageFilter
ph, rn, out = sys.argv[1:4]
P = Image.open(ph).convert("RGB")
R = Image.open(rn).convert("RGBA")
k = R.width / P.width
P = P.resize(R.size, Image.LANCZOS)
white = Image.new("RGBA", R.size, (255, 255, 255, 255))
Rw = Image.alpha_composite(white, R).convert("RGB")
blend = Image.blend(P, Rw, 0.5)
alpha = R.split()[3].point(lambda v: 255 if v > 20 else 0)
edge = alpha.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(3))
outl = P.copy(); outl.paste(Image.new("RGB", R.size, (230, 0, 0)), (0, 0), edge)
if len(sys.argv) > 4:
    x0, y0, x1, y1 = [round(float(v) * k) for v in sys.argv[4:8]]
    outl, blend = outl.crop((x0, y0, x1, y1)), blend.crop((x0, y0, x1, y1))
W, H = outl.size
s = Image.new("RGB", (W * 2 + 10, H), (255, 255, 255)); s.paste(outl, (0, 0)); s.paste(blend, (W + 10, 0)); s.save(out)
