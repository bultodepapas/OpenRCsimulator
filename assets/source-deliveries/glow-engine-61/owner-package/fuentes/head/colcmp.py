"""Median colour (sRGB) in small windows at projected 3D surface points: photo vs render."""
import sys, re
sys.path.insert(0, '/home/claude/head')
from proj import proj, cam
import numpy as np, math
from PIL import Image
dev, log = sys.argv[1], open(sys.argv[2]).read()
PTS = {
    'E': {'band_front': (0, -21.25, 61.5), 'band_front_l': (-9, -19.2, 61.0), 'fin_end_top': (0, -20.6, 70.2),
          'fin_crest_mid': (3.28, -10, 70.68), 'slot_floor': (1.64, -12, 64.35), 'cres_R_dome': (19.5, 2.5, 70.0),
          'cres_L_dome': (-19.5, -3, 70.0), 'band_right': (20.0, -7.3, 61.0)},
    'Ac': {'cres_face': (21.25, 0, 66.0), 'cres_dome': (20.0, 0, 70.0), 'band_low': (21.25, 0, 60.5),
           'fin_top': (9.84, 0, 70.68)},
    'D': {'fin_crest': (3.28, 9, 70.68), 'slot': (1.64, 9, 64.35), 'cres': (19.0, 3, 70.3)},
}
def med(im, u, v, r=3):
    u, v = int(round(u)), int(round(v))
    w = im[max(0, v - r):v + r + 1, max(0, u - r):u + r + 1].reshape(-1, 3)
    return np.median(w, axis=0).astype(int).tolist()
for v in sys.argv[3].split(','):
    m = re.search(r'view %s \[(\d+), (\d+), (\d+), (\d+)\]' % v, log)
    if not m: continue
    box = [int(g) for g in m.groups()]
    d = cam(v)[0]
    ph = np.asarray(Image.open(d['image']).convert('RGB'))
    rd = Image.open(f'{dev}/r_{v}.png').convert('RGBA')
    bg = Image.new('RGBA', rd.size, (232, 226, 214, 255)); bg.alpha_composite(rd)
    full = Image.new('RGB', (ph.shape[1], ph.shape[0]), (228, 228, 228)); full.paste(bg.convert('RGB'), (box[0], box[1]))
    rr = np.asarray(full)
    for k, P in PTS.get(v, {}).items():
        u, w = proj(v, [P])[0]
        print(v, f'{k:14s}', 'photo', med(ph, u, w), 'render', med(rr, u, w))
