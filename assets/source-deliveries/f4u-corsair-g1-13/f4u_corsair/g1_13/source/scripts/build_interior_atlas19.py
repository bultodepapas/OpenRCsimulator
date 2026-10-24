"""Author new UV-aligned interior paint maps; no photographic pixels are used."""
from pathlib import Path
import json,sys,math,zipfile,io,xml.etree.ElementTree as ET
P=Path(__file__).resolve().parents[2];W=P.parents[2];sys.path.insert(0,str(W/'work/plot_R58_deps'))
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageFont
D=P/'textures/interiors';rows=json.loads((D/'layout.json').read_text());N=2048;rng=np.random.default_rng(5719)
base=Image.new('RGBA',(N,N),(215,219,203,255));panel=Image.new('RGBA',(N,N));details=Image.new('RGBA',(N,N));wear=Image.new('RGBA',(N,N))
rough=np.full((N,N),151,dtype=np.float32);metal=np.zeros((N,N),dtype=np.uint8);height=np.zeros((N,N),dtype=np.float32)
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',13);small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',10)
records=[]
for row in rows:
 tile=row['tile'];ox=tile%4*512;oy=tile//4*1024;sc=row['scale']
 def xy(x,y):return(row['tx']+x*sc,row['ty']-y*sc)
 mask=Image.new('L',(512,1024));md=ImageDraw.Draw(mask)
 for p in row['polygons']:md.polygon([(x-ox,y-oy)for x,y in p],fill=255)
 # Work from the real mapped contour rather than a generic rectangular panel.
 a=np.asarray(mask)>0;eroded=[mask]
 for i in range(18):eroded.append(eroded[-1].filter(ImageFilter.MinFilter(3)))
 edge=a & ~(np.asarray(eroded[8])>0);seam=(np.asarray(eroded[8])>0)&~(np.asarray(eroded[10])>0)
 flange=Image.new('RGBA',(512,1024),(0,0,0,0));fa=np.array(flange);fa[edge]=[181,189,174,255];fa[seam]=[119,131,119,155];flange=Image.fromarray(fa);panel.alpha_composite(flange,(ox,oy))
 h=height[oy:oy+1024,ox:ox+512];h[edge]=.00012;h[seam]=-.00008
 rough[oy:oy+1024,ox:ox+512][edge]=164
 # Pale translucent dust gathers only at the recessed edge; broad skin stays clean.
 dust=Image.fromarray((edge*45).astype('uint8')).filter(ImageFilter.GaussianBlur(5));dl=Image.new('RGBA',(512,1024),(111,103,80,0));dl.putalpha(dust);wear.alpha_composite(dl,(ox,oy))
 rivets=[]
 for yy in np.linspace(40,984,16):
  yy=int(yy);xs=np.flatnonzero(np.asarray(eroded[5])[yy]>0)
  if len(xs)>24:
   for xx in (xs[0]+4,xs[-1]-4):rivets.append((ox+int(xx),oy+yy))
 for yy in [int(np.flatnonzero(a.any(axis=1))[0])+10,int(np.flatnonzero(a.any(axis=1))[-1])-10]:
  xs=np.flatnonzero(np.asarray(eroded[5])[yy]>0)
  if len(xs)>25:
   for xx in np.linspace(xs[0]+6,xs[-1]-6,5):rivets.append((ox+int(xx),oy+yy))
 spaced=[]
 for point in rivets:
  if all(math.dist(point,other)>=10 for other in spaced):spaced.append(point)
 rivets=spaced
 dd=ImageDraw.Draw(details);wd=ImageDraw.Draw(wear)
 for x,y in rivets:
  dd.ellipse((x-2.1,y-2.1,x+2.1,y+2.1),fill=(107,119,111,220));dd.ellipse((x-1.1,y-1.5,x+1.2,y+.8),fill=(229,232,219,255))
  Y,X=np.ogrid[max(0,y-4):min(N,y+5),max(0,x-4):min(N,x+5)];rr=np.sqrt((X-x)**2+(Y-y)**2)
  height[max(0,y-4):min(N,y+5),max(0,x-4):min(N,x+5)]+=np.maximum(0,1-rr/2.4)*.00015
 # Tonal outlines on the existing geometric stiffeners; no invented floating ribs.
 kind=row['kind'];cx={'front':.421,'inner':.361,'outer':.457}[kind];length=.060 if kind=='front'else .054
 for cy in ([-.10,-.17]if kind=='front'else[-.20,-.28,-.36]):
  s=-1 if row['role']=='left'else 1
  pts=[xy(s*(cx-length/2)/.9,cy/.9),xy(s*(cx+length/2)/.9,cy/.9)]
  # Clip the graphic to the mapped skin, and leave the geometric highlights intact.
  rib=Image.new('RGBA',(512,1024));rd=ImageDraw.Draw(rib);p=[(x-ox,y-oy)for x,y in pts]
  width=max(3,round(.007*sc));rd.line(p,fill=(116,129,116,90),width=width+3);rd.line(p,fill=(233,234,221,220),width=width)
  ra=np.array(rib);ra[~a,3]=0;panel.alpha_composite(Image.fromarray(ra),(ox,oy))
 # Support-plate finish and two painted washer/fastener seats on each real plate.
 for px,py in row['pads']:
  x,y=xy(px,py);w=.0044*sc;hh=.0069*sc
  dd.rectangle((x-w,y-hh,x+w,y+hh),fill=(191,201,185,230),outline=(123,137,124,255),width=1)
  for dy in (-.0036,.0036):
   qx,qy=xy(px,py+dy);rr=2.1
   dd.ellipse((qx-rr,qy-rr,qx+rr,qy+rr),fill=(84,98,93,255));dd.ellipse((qx-1,qy-1,qx+1,qy+1),fill=(177,190,181,255))
  dd.line([(x+.5,y-hh+1),(x+w-1,y-hh+1)],fill=(146,43,34,240),width=2)
 # Compact service identification, interpreted for this game model, not factory labels.
 cxp=ox+256;cyp=oy+550;label=None
 if a[min(1023,cyp-oy),256]:
  label=f"57 / {'LH' if row['role']=='left' else 'RH'}"
  dd.text((cxp,cyp),label,font=font,fill=(64,78,70,225),anchor='mm')
  dd.text((cxp,cyp+17),f"DOOR {tile%3+1:02d}",font=small,fill=(85,97,87,200),anchor='mm')
 # Sparse short handling scratches on the mounting flange, not random global weathering.
 candidates=np.argwhere(edge)
 for j in range(28):
  yy,xx=candidates[rng.integers(len(candidates))];x=ox+int(xx);y=oy+int(yy)
  wd.line((x,y,x+int(rng.integers(1,4)),y+int(rng.integers(-1,2))),fill=(158,165,153,145),width=1)
 records.append({'door':row['name'],'flush_fastener_marks':len(rivets),'plates':len(row['pads']),'paint_label':label if 'label'in locals()else None})
# Small material variation across the entire new coating, kept below a paint mottling effect.
arr=np.array(base);noise=rng.normal(0,.7,(N,N));arr[:,:,:3]=np.clip(arr[:,:,:3].astype(float)+noise[:,:,None],0,255).astype('uint8');base=Image.fromarray(arr)
rough+=rng.normal(0,1.3,(N,N));rough=np.clip(rough,140,169).astype('uint8')
merged=base
layers=[('01 Coating',base),('02 Flanges and ribs',panel),('03 Fasteners and marks',details),('04 Local wear',wear)]
for _,l in layers[1:]:merged=Image.alpha_composite(merged,l)
merged.convert('RGB').save(D/'basecolor.png');Image.fromarray(np.dstack([np.full_like(rough,255),rough,metal])).save(D/'orm.png')
# Tangent-space relief is authored from shallow paint/flush-head height, not displacement.
norm=np.zeros((N,N,3),dtype=np.float32);norm[:,:,2]=1
for row in rows:
 ox=row['tile']%4*512;oy=row['tile']//4*1024;hh=height[oy:oy+1024,ox:ox+512];gy,gx=np.gradient(hh);n=np.dstack([-gx*row['scale'],gy*row['scale'],np.ones_like(hh)]);n/=np.linalg.norm(n,axis=2,keepdims=True);norm[oy:oy+1024,ox:ox+512]=n
Image.fromarray(np.clip((norm*.5+.5)*255,0,255).astype('uint8')).save(D/'normal.png')
for i,(_,l)in enumerate(layers):l.save(D/f'layer_{i+1}.png')
root=ET.Element('image',w=str(N),h=str(N),name='Corsair 57 inner doors g1.9');stack=ET.SubElement(root,'stack')
with zipfile.ZipFile(D/'source.ora','w',zipfile.ZIP_DEFLATED)as z:
 z.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
 for i,(name,l)in reversed(list(enumerate(layers))):
  src=f'data/layer{i}.png';buf=io.BytesIO();l.save(buf,format='PNG');z.writestr(src,buf.getvalue());ET.SubElement(stack,'layer',name=name,src=src,x='0',y='0',opacity='1.0',visibility='visible',**{'composite-op':'svg:src-over'})
 z.writestr('stack.xml',ET.tostring(root));buf=io.BytesIO();merged.save(buf,format='PNG');z.writestr('mergedimage.png',buf.getvalue())
(D/'authoring.json').write_text(json.dumps({'resolution':[2048,2048],'layers':4,'normal':'OpenGL tangent, UV set DoorInteriorUV','detail_interpretation':'Coating, support-plate finish, perimeter fasteners and maintenance IDs are visual detailing, not documented factory markings.','doors':records},indent=2))
print('INTERIOR_ATLAS19_DONE',json.dumps(records))
