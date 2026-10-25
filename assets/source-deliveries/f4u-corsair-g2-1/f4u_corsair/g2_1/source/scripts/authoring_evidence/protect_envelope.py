import numpy as np,json
from pathlib import Path
W=Path(__file__).parent;d=np.load(W/'outlines.npz');v=d['g2_0_hub_v'];t=d['g2_0_hub_t'];keep=set()
ed=np.sort(np.concatenate([t[:,[0,1]],t[:,[1,2]],t[:,[2,0]]]),axis=1);ed=np.unique(ed,axis=0)
for axes in [(0,1),(1,0),(0,2),(2,0),(1,2),(2,1)]:
 xy=v[:,axes];uv=xy[np.unique(t)];y=np.linspace(uv[:,1].min()+1e-10,uv[:,1].max()-1e-10,16384)
 lo=np.full(len(y),np.inf);hi=np.full(len(y),-np.inf);ilo=np.full(len(y),-1);ihi=np.full(len(y),-1)
 for ei,(ia,ib) in enumerate(ed):
  a,b=xy[ia],xy[ib]
  if abs(a[1]-b[1])<1e-12:continue
  j0=np.searchsorted(y,min(a[1],b[1]),'left');j1=np.searchsorted(y,max(a[1],b[1]),'right')
  if j0==j1:continue
  x=a[0]+(y[j0:j1]-a[1])*(b[0]-a[0])/(b[1]-a[1]);sl=slice(j0,j1)
  low=x<lo[sl];high=x>hi[sl];ilo[sl][low]=ei;ihi[sl][high]=ei;lo[sl]=np.minimum(lo[sl],x);hi[sl]=np.maximum(hi[sl],x)
 for i in np.unique(np.concatenate([ilo,ihi])):
  if i>=0:keep.update(int(j)for j in ed[i])
base=set(keep)
for face in t:
 if any(int(i)in base for i in face):keep.update(int(i)for i in face)
(W/'hub_envelope_protected.json').write_text(json.dumps(sorted(keep)));print('Protected hull + one-ring',len(keep))
