import json, sys, numpy as np
from PIL import Image, ImageDraw
U = '/root/.claude/uploads/5aad6050-4747-5d68-bd16-c5cdce93a416/'
def cam(v):
    d = json.load(open(f'/home/claude/engine/cams/cam_{v}.json'))
    return d, np.array(d['R']), np.array(d['t']), d['f'], np.array(d['pp'])
def proj(v, P):
    d, R, t, f, pp = cam(v)
    X = (R @ np.array(P).T).T + t
    return np.c_[f * X[:, 0] / X[:, 2] + pp[0], f * X[:, 1] / X[:, 2] + pp[1]]
if __name__ == "__main__":
    v = sys.argv[1]
    d = cam(v)[0]
    im = Image.open(d['image']).convert('RGB')
    dr = ImageDraw.Draw(im)
    zt = 57.5 + 13.2
    for k, col in ((0.0, (255, 0, 0)), (1.75, (0, 160, 255))):
        for i in range(-6, 7):
            x = i * 3.5 + k
            if abs(x) > 19: continue
            L = (21.0 ** 2 - x * x) ** 0.5
            pts = proj(v, [(x, y, zt) for y in np.linspace(-L, L, 20)])
            dr.line([tuple(p) for p in pts], fill=col, width=2)
    # head rim circle at band top and at z0
    for z, col in ((57.5, (255, 255, 0)), (63.0, (0, 255, 0))):
        pts = proj(v, [(21.5 * np.cos(a), 21.5 * np.sin(a), z) for a in np.linspace(0, 2 * np.pi, 120)])
        dr.line([tuple(p) for p in pts], fill=col, width=2)
    box = [int(b) for b in sys.argv[2].split(',')] if len(sys.argv) > 2 else None
    (im.crop(box) if box else im).save(f'proj_{v}.jpg', quality=90)
