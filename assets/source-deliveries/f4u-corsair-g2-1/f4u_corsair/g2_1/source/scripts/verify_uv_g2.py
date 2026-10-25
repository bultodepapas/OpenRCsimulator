"""UV pixel-centre overlap audit on painted exterior faces only. Read-only."""
import bpy,json,hashlib
import numpy as np
from pathlib import Path
P=Path(__file__).resolve().parents[2];N=2048;count=np.zeros((N,N),np.uint16);outside=0;triangles=0;area=0;collisions={};owners=np.zeros((N,N),np.int32);names=['none']
for o in bpy.data.collections['EXPORT_aircraft'].objects:
 if o.type!='MESH':continue
 o.data.calc_loop_triangles();uv=o.data.uv_layers.get('UVMap')
 names.append(o.name);oid=len(names)-1
 if uv is None:raise RuntimeError('Missing UVMap: '+o.name)
 for t in o.data.loop_triangles:
  if not o.data.materials[t.material_index].name.startswith('paint_'):continue
  v=np.array([uv.data[i].uv[:]for i in t.loops],dtype=np.float64);triangles+=1
  outside+=int((v< -1e-6).any()or(v>1+1e-6).any());v*=N
  x0,y0=np.maximum(0,np.floor(v.min(0)).astype(int));x1,y1=np.minimum(N-1,np.ceil(v.max(0)).astype(int))
  if x1<x0 or y1<y0:continue
  a,b,c=v;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1]);area+=abs(den)/2/N/N
  if abs(den)<1e-9:continue
  yy,xx=np.mgrid[y0:y1+1,x0:x1+1];xx=xx+.5;yy=yy+.5
  u=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
  w=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den
  hit=(u>1e-6)&(w>1e-6)&((1-u-w)>1e-6);region=count[y0:y1+1,x0:x1+1];own=owners[y0:y1+1,x0:x1+1];old=own[hit&(region>0)]
  for other in np.unique(old):
   key=names[int(other)]+' / '+o.name;collisions[key]=collisions.get(key,0)+int((old==other).sum())
  region+=hit.astype(np.uint16);own[hit]=oid
r={'method':'painted triangle interiors at 2048x2048 pixel centres, barycentric edge epsilon 1e-6; finite sampling does not prove absence of subpixel overlaps','painted_triangles':triangles,'outside_unit_square':outside,'UV_area_sum':area,'occupied_pixels':int((count>0).sum()),'multiply_covered_pixels':int((count>1).sum()),'max_layers':int(count.max()),'source_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()}
r['collisions_by_parts']=collisions;r['passed']=r['outside_unit_square']==0 and r['multiply_covered_pixels']==0
(P/'checks/uv_overlap.json').write_text(json.dumps(r,indent=2));print('UV_CHECK',r,flush=True)
if not r['passed']:raise SystemExit(1)
