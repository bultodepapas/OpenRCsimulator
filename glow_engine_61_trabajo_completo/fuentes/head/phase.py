import json, numpy as np, sys
from PIL import Image
from proj import cam, proj
for v in ("D", "E", "T", "Ac"):
    d = cam(v)[0]
    im = np.asarray(Image.open(d['image']).convert('L'), dtype=float)
    res = []
    for z in (70.2, 70.7):
        for y in (-12, -9, -6, 6, 9, 12):
            xs = np.arange(-14, 14, 0.05)
            P = proj(v, [(x, y, z) for x in xs])
            ok = (P[:, 0] > 0) & (P[:, 0] < im.shape[1] - 1) & (P[:, 1] > 0) & (P[:, 1] < im.shape[0] - 1)
            if ok.sum() < len(xs) * 0.9:
                continue
            vals = im[P[ok, 1].astype(int), P[ok, 0].astype(int)]
            xx = xs[ok]
            vals = vals - vals.mean()
            w = 2 * np.pi / 3.5
            c = (vals * np.cos(w * xx)).sum(); s = (vals * np.sin(w * xx)).sum()
            amp = np.hypot(c, s) / len(xx)
            ph = np.degrees(np.arctan2(s, c)) % 360     # brightness max at x = ph/360*3.5 (mod 3.5)
            res.append((z, y, round(amp, 1), round(ph / 360 * 3.5, 2)))
    print(v, res)
