"""Fin crest brightness peaks along lines y = const on the photo and on the render (same solved camera)."""
import sys, re, json
sys.path.insert(0, '/home/claude/head')
from proj import proj, cam
import numpy as np, math
from PIL import Image
from scipy.signal import find_peaks
dev = sys.argv[1]
log = open(sys.argv[2]).read()
R = 21.2
xs = np.arange(-18, 18.01, 0.05)
def peaks(im, v):
    out = []
    for y in (-12, -9, 9, 12):
        uv = proj(v, [(x, y, 70.6) for x in xs])
        ok = (np.hypot(xs, y) < R - 0.8)
        b = np.array([im[int(round(q)), int(round(p))] if 0 <= int(round(q)) < im.shape[0] and 0 <= int(round(p)) < im.shape[1] else np.nan for p, q in uv])
        b[~ok] = np.nan
        bs = np.convolve(np.nan_to_num(b, nan=np.nanmean(b)), np.ones(5) / 5, 'same')
        pk, _ = find_peaks(bs, distance=45, prominence=6)
        out += [round(float(xs[p]), 2) for p in pk if ok[p]]
    return np.array(sorted(out))
for v in sys.argv[3].split(','):
    m = re.search(r'view %s \[(\d+), (\d+), (\d+), (\d+)\]' % v, log)
    box = [int(g) for g in m.groups()]
    d = cam(v)[0]
    ph = np.asarray(Image.open(d['image']).convert('L')).astype(float)
    rd = Image.open(f'{dev}/r_{v}.png').convert('RGBA')
    bg = Image.new('RGBA', rd.size, (232, 226, 214, 255)); bg.alpha_composite(rd)
    full = Image.new('L', (ph.shape[1], ph.shape[0]), 228); full.paste(bg.convert('L'), (box[0], box[1]))
    rr = np.asarray(full).astype(float)
    a, b = peaks(ph, v), peaks(rr, v)
    # mean distance from each photo peak to the nearest render peak
    dd = [np.min(np.abs(b - x)) for x in a] if len(b) else [9]
    print(v, 'photo peaks', len(a), 'render peaks', len(b), 'mean |photo-render| mm', round(float(np.mean(dd)), 3),
          'median', round(float(np.median(dd)), 3))
