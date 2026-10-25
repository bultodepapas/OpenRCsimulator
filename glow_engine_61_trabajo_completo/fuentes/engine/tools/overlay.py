import sys, json
from PIL import Image, ImageChops, ImageFilter, ImageOps
ref, ren, out = sys.argv[1], sys.argv[2], sys.argv[3]
m = json.loads(sys.argv[4])  # {"ref":[[x,y],[x,y]] (plug tip, case bottom at cyl axis), "ren":[[...],[...]], "axis_ref_x":..,"axis_ren_x":..}
R = Image.open(ren).convert("RGBA")
P = Image.open(ref).convert("RGB")
s = (m["ren"][1][1] - m["ren"][0][1]) / (m["ref"][1][1] - m["ref"][0][1])
P2 = P.resize((round(P.width * s), round(P.height * s)), Image.LANCZOS)
ox = m["ren_axis_x"] - m["ref_axis_x"] * s
oy = m["ren"][0][1] - m["ref"][0][1] * s
canvas = Image.new("RGB", R.size, (255, 255, 255))
canvas.paste(P2, (round(ox), round(oy)))
white = Image.new("RGBA", R.size, (255, 255, 255, 255))
Rw = Image.alpha_composite(white, R).convert("RGB")
blend = Image.blend(canvas, Rw, 0.5)
# silhouette outline of the render in red over the photo
alpha = R.split()[3].point(lambda v: 255 if v > 20 else 0)
edge = alpha.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(3))
red = Image.new("RGB", R.size, (230, 0, 0))
outl = canvas.copy(); outl.paste(red, (0, 0), edge)
W, H = R.size
sheet = Image.new("RGB", (W * 2, H), (255, 255, 255))
sheet.paste(outl, (0, 0)); sheet.paste(blend, (W, 0))
sheet.save(out)
print("scale", round(s, 3), "offset", round(ox, 1), round(oy, 1))
