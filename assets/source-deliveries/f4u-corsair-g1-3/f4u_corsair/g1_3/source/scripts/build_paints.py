"""Python 3 + numpy + Pillow. Original procedural liveries on the shared g1 UV atlas."""
import sys,json,zipfile,io
from pathlib import Path
try:import numpy as np;from PIL import Image,ImageDraw,ImageFont
except ImportError:
 for p in [Path(__file__).resolve().parents[5]/'work/plot_R58_deps']:sys.path.insert(0,str(p))
 import numpy as np
 from PIL import Image,ImageDraw,ImageFont
P=Path(__file__).resolve().parents[2];N=2048;layout=json.loads((P/'source/scripts/uv-layout.json').read_text());pos=np.zeros((N,N,3),np.float32);normal=np.zeros_like(pos);part=np.full((N,N),-1,np.int16);overlaps=0;inside=np.zeros((N,N),bool)
for k,obj in enumerate(layout):
 for t in obj['triangles']:
  uv=np.array(t['uv']);uv[:,0]*=N-1;uv[:,1]=(1-uv[:,1])*(N-1);a,b,c=uv;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
  if abs(den)<1e-7:continue
  x0,x1=max(0,int(np.floor(uv[:,0].min()))),min(N-1,int(np.ceil(uv[:,0].max())));y0,y1=max(0,int(np.floor(uv[:,1].min()))),min(N-1,int(np.ceil(uv[:,1].max())));yy,xx=np.mgrid[y0:y1+1,x0:x1+1];w0=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den;w1=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den;w2=1-w0-w1;mask=(w0>=-1e-6)&(w1>=-1e-6)&(w2>=-1e-6);pp=pos[y0:y1+1,x0:x1+1];coords=np.array(t['xyz']);pp[mask]=(w0[...,None]*coords[0]+w1[...,None]*coords[1]+w2[...,None]*coords[2])[mask];normal[y0:y1+1,x0:x1+1][mask]=t['normal'];inside[y0:y1+1,x0:x1+1][mask]=t.get('door_inner',False);part[y0:y1+1,x0:x1+1][mask]=k
 print('UV raster',obj['name'],flush=True)
covered=part>=0;x,y,z=pos[:,:,0],pos[:,:,1],pos[:,:,2];nz=normal[:,:,2];nx=normal[:,:,0]
try:font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',110)
except OSError:font=ImageFont.load_default(size=110)
label=Image.new('RGBA',(360,150));dr=ImageDraw.Draw(label);dr.text((180,73),'308',font=font,fill=(244,233,200,255),stroke_width=2,stroke_fill=(55,28,24,255),anchor='mm');labelarr=np.asarray(label)
body_index=next(i for i,o in enumerate(layout)if o['name']=='fuselage_core')
for lid,base in [('midnight',(17,36,61)),('three_tone',(79,111,134)),('scarlet',(176,23,31))]:
 out=P/'textures/liveries'/lid;out.mkdir(parents=True,exist_ok=True);coat=np.empty((N,N,3),np.uint8);coat[:]=base;colors=coat.copy()
 if lid=='midnight':colors[covered&(abs(x)>1.15)]=(223,214,185)
 elif lid=='three_tone':
  blend=np.clip((nz+.25)/.5,0,1);body=(part==body_index);blend[body]=np.clip((z[body]+.04)/.13,0,1);blend=blend*blend*(3-2*blend);colors[:]=(np.array([224,228,223])[None,None,:]*(1-blend[...,None])+np.array([29,56,83])[None,None,:]*blend[...,None]).astype(np.uint8)
 else:
  stripe=covered&(((abs(x)>.77)&(abs(x)<.82))|((abs(x)>.88)&(abs(x)<.96)));colors[stripe]=(235,222,188);colors[covered&(part==body_index)&(nz>.72)]=(235,222,188)
 # Restrained painted finish and contrasting inner door coating; no sponsor artwork.
 colors[covered&inside]=(173,184,166)
 variation=1+.008*np.sin(x*83+y*57+z*31)+.004*np.cos(y*121-z*93)
 colors=np.clip(colors.astype(np.float32)*variation[...,None],0,255).astype(np.uint8)
 # Four pixels of colour bleed without changing the authored UV islands.
 valid=covered.copy()
 for _ in range(4):
  acc=np.zeros((N,N,3),np.float32);weight=np.zeros((N,N),np.float32)
  for dy,dx in [(0,1),(0,-1),(1,0),(-1,0)]:
   mask=np.roll(valid,(dy,dx),(0,1));acc+=np.roll(colors,(dy,dx),(0,1))*mask[...,None];weight+=mask
  fill=(~valid)&(weight>0);colors[fill]=(acc[fill]/weight[fill,None]).astype(np.uint8);valid|=fill
 markings=np.zeros((N,N,4),np.uint8)
 if lid=='scarlet':
  mask=covered&(part==body_index)&(abs(nx)>.55)&(y>-.84)&(y<-.43)&(z>-.055)&(z<.08)
  u=np.clip(((y+.84)/.41*359).astype(int),0,359);u=np.where(nx>0,359-u,u);v=np.clip(((.08-z)/.135*149).astype(int),0,149);markings[mask]=labelarr[v[mask],u[mask]]
 design=np.zeros((N,N,4),np.uint8);design[:,:,:3]=colors;design[:,:,3]=np.any(colors!=coat,axis=2)*255
 merged=Image.fromarray(colors,'RGB').convert('RGBA');merged.alpha_composite(Image.fromarray(markings));merged.convert('RGB').save(out/'basecolor.png');Image.fromarray(markings).save(out/'markings.png');Image.fromarray(design).save(out/'paint_design.png')
 layers=[('Markings',Image.fromarray(markings)),('Paint design',Image.fromarray(design)),('Base coat',Image.fromarray(coat,'RGB').convert('RGBA'))]
 with zipfile.ZipFile(out/'source.ora','w',zipfile.ZIP_DEFLATED)as archive:
  archive.writestr('mimetype','image/openraster');xml=['<image version="0.0.3" w="2048" h="2048" name="F4U g1 '+lid+'"><stack>']
  for i,(name,img)in enumerate(layers):
   buf=io.BytesIO();img.save(buf,format='PNG');archive.writestr(f'data/layer{i}.png',buf.getvalue());xml.append(f'<layer name="{name}" src="data/layer{i}.png" opacity="1.0" visibility="visible" composite-op="svg:src-over" x="0" y="0"/>')
  xml.append('</stack></image>');archive.writestr('stack.xml',''.join(xml));buf=io.BytesIO();merged.save(buf,format='PNG');archive.writestr('mergedimage.png',buf.getvalue())
 print('LIVERY',lid,flush=True)
(P/'source/scripts/uv-raster-check.json').write_text(json.dumps({'atlas_size':[N,N],'painted_parts':len(layout),'occupied_pixels':int(covered.sum()),'islands_strategy':'per-part disjoint padded rectangles, smart-project packed islands inside each rectangle'},indent=2))
