import numpy as np,json
from pathlib import Path
W=Path(__file__).parent;P=W.parent.parent/'g2_1';d=np.load(W/'outlines.npz');rows=[]
def envelope(v,t,axes,y):
 xy=v[:,axes];ed=np.sort(np.concatenate([t[:,[0,1]],t[:,[1,2]],t[:,[2,0]]]),axis=1);ed=np.unique(ed,axis=0)
 lo=np.full(len(y),np.inf);hi=np.full(len(y),-np.inf)
 for ia,ib in ed:
  a,b=xy[ia],xy[ib]
  if abs(a[1]-b[1])<1e-12:continue
  j0=np.searchsorted(y,min(a[1],b[1]),'left');j1=np.searchsorted(y,max(a[1],b[1]),'right')
  if j0==j1:continue
  x=a[0]+(y[j0:j1]-a[1])*(b[0]-a[0])/(b[1]-a[1]);lo[j0:j1]=np.minimum(lo[j0:j1],x);hi[j0:j1]=np.maximum(hi[j0:j1],x)
 return lo,hi
for region in ['hub','blades','glass']:
 vs=[d[r+'_'+region+'_v'] for r in ['g2_0','g2_1']];ts=[d[r+'_'+region+'_t']for r in ['g2_0','g2_1']]
 for name,ax in [('front',(0,2)),('side',(1,2)),('top',(0,1))]:
  for axes in [ax,ax[::-1]]:
   aa=np.concatenate([v[np.unique(t)][:,axes]for v,t in zip(vs,ts)]);y=np.linspace(aa[:,1].min()+1e-9,aa[:,1].max()-1e-9,4096)
   a,b=[envelope(v,t,axes,y)for v,t in zip(vs,ts)];delta=max(np.max(np.abs(u[np.isfinite(u)&np.isfinite(v)]-v[np.isfinite(u)&np.isfinite(v)]))for u,v in zip(a,b));rows.append({'part':region,'view':name,'axes':axes,'sampled_envelope_delta_mm':float(delta*1000)})
   print(rows[-1],flush=True)
(P/'checks/outline_envelope.json').write_text(json.dumps({'method':'Exact segment interpolation of outer projected bounds at 4096 parallel cross-sections in both directions of each principal plane. Sampled envelope, not a proof for all directions.','rows':rows},indent=2))
