import sys; sys.path.insert(0,'/home/claude/head')
from proj import proj, cam
import numpy as np, math
from PIL import Image
from scipy.signal import find_peaks
R=21.2
xs=np.arange(-18,18.01,0.05)
for v in ('E','D','T'):
    try: d=cam(v)[0]
    except Exception as e: print(v,e); continue
    im=np.asarray(Image.open(d['image']).convert('L')).astype(float)
    acc=[]
    for y in (-16,-12,-9,9,12,15):
        P=[(x,y,70.6) for x in xs]
        uv=proj(v,P)
        ok=(np.hypot(xs,y)<R-0.8)
        b=np.array([im[int(round(q)),int(round(p))] if 0<=int(round(q))<im.shape[0] and 0<=int(round(p))<im.shape[1] else np.nan for p,q in uv])
        b[~ok]=np.nan
        bs=np.convolve(np.nan_to_num(b,nan=np.nanmean(b)),np.ones(5)/5,'same')
        pk,_=find_peaks(bs,distance=45,prominence=8)
        pk=[p for p in pk if ok[p] and not (abs(y)<8 and abs(xs[p])<7)]
        x_pk=xs[pk]
        acc.append((y,np.round(x_pk,2).tolist()))
        # fit pitch: for pitch p in range, phase that best fits
    allx=np.concatenate([np.array(a[1]) for a in acc])
    best=None
    for p in np.arange(3.0,3.8,0.01):
        for ph in np.arange(0,p,0.02):
            r=((allx-ph)/p); err=np.abs(r-np.round(r))*p
            s=np.mean(np.minimum(err,0.6))
            if best is None or s<best[0]: best=(s,p,ph)
    print(v,'best pitch',round(best[1],3),'phase',round(best[2],2),'mean err',round(best[0],3))
    for a in acc: print('  y',a[0],a[1])
