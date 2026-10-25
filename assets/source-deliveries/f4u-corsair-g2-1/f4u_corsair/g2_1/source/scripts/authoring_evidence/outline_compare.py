from pathlib import Path
import numpy as np,json
from PIL import Image,ImageDraw,ImageFilter
W=Path(__file__).parent;P=W.parent.parent/'g2_1';d=np.load(W/'outlines.npz');rows=[]
N=4096
for region in ['hub','blades','glass']:
 vs=[d[r+'_'+region+'_v'] for r in ['g2_0','g2_1']];ts=[d[r+'_'+region+'_t']for r in ['g2_0','g2_1']]
 for name,axes in [('front',(0,2)),('side',(1,2)),('top',(0,1))]:
  used=np.concatenate([v[np.unique(t),:][:,axes] for v,t in zip(vs,ts)]);mn=used.min(0);extent=max(used.max(0)-mn)*1.02;mn-=extent*.01
  masks=[]
  for v,t in zip(vs,ts):
   pix=(v[:,axes]-mn)/extent*(N-1);im=Image.new('1',(N,N));draw=ImageDraw.Draw(im)
   for face in t:draw.polygon([tuple(p)for p in pix[face]],fill=1)
   masks.append(np.asarray(im,dtype=bool))
  a,b=masks;union=(a|b).sum();iou=(a&b).sum()/union
  ea=a^np.asarray(Image.fromarray(a.astype('uint8')).filter(ImageFilter.MinFilter(3)),dtype=bool)
  eb=b^np.asarray(Image.fromarray(b.astype('uint8')).filter(ImageFilter.MinFilter(3)),dtype=bool)
  da=ea.copy();db=eb.copy();max_px=0
  while ((eb&~da).any() or (ea&~db).any()) and max_px<128:
   da=np.logical_or.reduce([np.roll(np.roll(da,i,0),j,1)for i in [-1,0,1]for j in [-1,0,1]])
   db=np.logical_or.reduce([np.roll(np.roll(db,i,0),j,1)for i in [-1,0,1]for j in [-1,0,1]])
   max_px+=1
  row={'part':region,'view':name,'resolution':[N,N],'silhouette_IoU':float(iou),'max_outline_raster_distance_px':float(max_px),'max_outline_raster_distance_mm':float(max_px*extent/(N-1)*1000),'pixel_mm':float(extent/(N-1)*1000),'exact_pixels':bool(np.array_equal(a,b))};rows.append(row);print(row,flush=True)
 # World vertex-coordinate triplets give a strict unchanged blade triangle proof.
 if region=='blades':
  sets=[{tuple(sorted(tuple(float(x)for x in v[i])for i in face))for face in t}for v,t in zip(vs,ts)]
  blades_exact=sets[0]==sets[1]
report={'method':'Union of all projected triangle silhouettes, 4096 square binary masks, common bounds. Raster boundary Chebyshev distance is resolution-limited; not a certified continuous bound.','blade_triangles_exact':blades_exact,'rows':rows}
(P/'checks/outline_g2_0_comparison.json').write_text(json.dumps(report,indent=2));assert blades_exact
