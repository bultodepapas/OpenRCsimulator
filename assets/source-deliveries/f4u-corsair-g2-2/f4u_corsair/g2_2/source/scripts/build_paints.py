"""Python 3 + numpy + Pillow. Shared UV painter. Scarlet reproduces the user-requested 57/SOHIO identity."""
import sys,json,zipfile,io
from pathlib import Path
try:import numpy as np;from PIL import Image,ImageDraw,ImageFont
except ImportError:
 for p in [Path(__file__).resolve().parents[5]/'work/plot_R58_deps']:sys.path.insert(0,str(p))
 import numpy as np
 from PIL import Image,ImageDraw,ImageFont
P=Path(__file__).resolve().parents[2];N=2048;layout=json.loads((P/'source/scripts/uv-layout.json').read_text());pos=np.zeros((N,N,3),np.float32);normal=np.zeros_like(pos);part=np.full((N,N),-1,np.int16);overlaps=0;inside=np.zeros((N,N),bool)
cache=P/'source/scripts'/f'paint-raster-{N}.npz'
if cache.exists():
 data=np.load(cache);pos=data['pos'];normal=data['normal'];part=data['part'];inside=data['inside']
else:
 for k,obj in enumerate(layout):
  for t in obj['triangles']:
   uv=np.array(t['uv']);uv[:,0]*=N-1;uv[:,1]=(1-uv[:,1])*(N-1);a,b,c=uv;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
   if abs(den)<1e-7:continue
   x0,x1=max(0,int(np.floor(uv[:,0].min()))),min(N-1,int(np.ceil(uv[:,0].max())));y0,y1=max(0,int(np.floor(uv[:,1].min()))),min(N-1,int(np.ceil(uv[:,1].max())));yy,xx=np.mgrid[y0:y1+1,x0:x1+1];w0=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den;w1=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den;w2=1-w0-w1;mask=(w0>=-1e-6)&(w1>=-1e-6)&(w2>=-1e-6);pp=pos[y0:y1+1,x0:x1+1];coords=np.array(t['xyz']);pp[mask]=(w0[...,None]*coords[0]+w1[...,None]*coords[1]+w2[...,None]*coords[2])[mask];nn=np.array(t.get('normals',[t['normal']]*3));smooth=w0[...,None]*nn[0]+w1[...,None]*nn[1]+w2[...,None]*nn[2];smooth/=np.maximum(np.linalg.norm(smooth,axis=2,keepdims=True),1e-9);normal[y0:y1+1,x0:x1+1][mask]=smooth[mask];inside[y0:y1+1,x0:x1+1][mask]=t.get('door_inner',False);part[y0:y1+1,x0:x1+1][mask]=k
  print('UV raster',obj['name'],flush=True)
 np.savez(cache,pos=pos,normal=normal,part=part,inside=inside)

covered=part>=0;x,y,z=pos[:,:,0],pos[:,:,1],pos[:,:,2];nz=normal[:,:,2];nx=normal[:,:,0]
names=[o['name']for o in layout]
def group(prefixes):return np.isin(part,[i for i,n in enumerate(names)if n.startswith(prefixes)])
body=group(('fuselage_core','cowl','canopy_frame'));fuselage=part==names.index('fuselage_core');wing=group(('wing_','flap_','aileron_','upper_fold_cover_'));horizontal=wing|group(('stabilizer','elevator'));vertical=group(('fin_fixed','rudder'));doors=group(('gear_door_',))
def ramp(a,b,v):
 t=np.clip((v-a)/(b-a),0,1);return t*t*(3-2*t)
def mix(colors,color,mask):
 a=np.asarray(mask,dtype=np.float32)
 return colors*(1-a[...,None])+np.asarray(color,dtype=np.float32)*a[...,None]
def band(lo,hi,v,feather=.0012):return ramp(lo-feather,lo+feather,v)*(1-ramp(hi-feather,hi+feather,v))
# Draw a clean star-and-bar symbol. A separate PNG/ORA layer makes it removable.
emblem=Image.new('RGBA',(800,500));ed=ImageDraw.Draw(emblem)
ed.rectangle((15,145,785,355),fill=(16,29,43,255))
ed.ellipse((150,0,650,500),fill=(16,29,43,255))
ed.rectangle((37,167,763,333),fill=(238,238,226,255))
ed.ellipse((169,19,631,481),fill=(16,29,43,255))
import math
pts=[]
for i in range(10):
 angle=-math.pi/2+i*math.pi/5;r=218 if i%2==0 else 83.3
 pts.append((400+r*math.cos(angle),250+r*math.sin(angle)))
ed.polygon(pts,fill=(238,238,226,255));emblemarr=np.asarray(emblem)
def stamp(arr,bitmap,uu,vv,mask):
 # Area prefilter fine lettering before projection, using the local atlas footprint.
 if globals().get('lid') in {'scarlet','midnight'}:
  valid=mask&(uu>=0)&(uu<=1)&(vv>=0)&(vv<=1)
  if np.any(valid):
   du=np.maximum(abs(uu-np.roll(uu,1,0)),abs(uu-np.roll(uu,1,1)))
   dv=np.maximum(abs(vv-np.roll(vv,1,0)),abs(vv-np.roll(vv,1,1)))
   ow,oh=bitmap.shape[1],bitmap.shape[0]
   tw=min(ow,max(8,int(1.5/max(float(np.median(du[valid])),1e-5))))
   th=min(oh,max(8,int(1.5/max(float(np.median(dv[valid])),1e-5))))
   bitmap=np.asarray(Image.fromarray(bitmap).resize((tw,th),Image.Resampling.LANCZOS))
 h,w=bitmap.shape[:2];u=np.clip(uu,0,1)*(w-1);v=np.clip(vv,0,1)*(h-1)
 i=u.astype(int);j=v.astype(int);i2=np.minimum(i+1,w-1);j2=np.minimum(j+1,h-1);a=u-i;b=v-j
 sample=bitmap[j,i]*(1-a)[...,None]*(1-b)[...,None]+bitmap[j,i2]*a[...,None]*(1-b)[...,None]+bitmap[j2,i]*(1-a)[...,None]*b[...,None]+bitmap[j2,i2]*a[...,None]*b[...,None]
 mask=mask&(uu>=0)&(uu<=1)&(vv>=0)&(vv<=1);arr[mask]=sample[mask].astype(np.uint8)

from paint_details import add_details
from super57_paint import design57, markings57
from super57_details import race_details
from naval_details10 import paint_design as naval_design, details as naval_details
# Neutral aircraft-space pigment variation crosses part boundaries continuously.
fine=.45*np.sin(x*173+y*127+z*97)+.25*np.cos(y*211-z*139)
settings=[('midnight',(19,36,52),.28),('three_tone',(77,110,132),.46),('scarlet',(174,13,22),.23)]
if '--livery' in sys.argv: settings=[s for s in settings if s[0]==sys.argv[sys.argv.index('--livery')+1]]
old_check=json.loads((P/'source/scripts/uv-raster-check.json').read_text())
checks=[c for c in old_check['liveries'] if c['id'] not in [s[0] for s in settings]]
for lid,base,rough_base in settings:
 out=P/'textures/liveries'/lid;out.mkdir(parents=True,exist_ok=True);coat=np.empty((N,N,3),np.uint8);coat[:]=base;colors=coat.astype(np.float32)
 ivory=(237,227,202);navy=(20,36,55);warm=(181,158,111)
 if lid=='midnight':
  colors=naval_design(globals(),colors)
 elif lid=='three_tone':
  # Three distinct paint fields, with feathered boundaries independent of triangle tessellation on the body.
  low=(222,226,218);mid=(84,118,143);high=(25,49,73)
  colors[:]=mid
  colors=mix(colors,low,body*(1-ramp(-.055,-.018,z)));colors=mix(colors,high,body*ramp(.065,.105,z))
  colors=mix(colors,low,horizontal*(1-ramp(-.35,.10,nz)));colors=mix(colors,high,horizontal*ramp(.48,.82,nz))
  colors=mix(colors,high,vertical*ramp(.28,.315,z));colors=mix(colors,low,doors&~inside)
 else:
  colors=design57(globals(),colors)
 colors=np.clip(colors+fine[...,None],0,255)
 design=np.zeros((N,N,4),np.uint8);design[:,:,:3]=colors.astype(np.uint8);design[:,:,3]=covered*255
 # Replace one uniform gloss with separate surface responses, baked to standard metallic/roughness channels.
 rough=np.full((N,N),rough_base,np.float32);rough+=.012*np.sin(x*21+y*17+z*11)+fine*.003
 service=np.zeros((N,N,4),np.uint8)
 walk=wing&covered&(abs(x)>.19)&(abs(x)<.29)&(y>-.395)&(y<-.145)&(nz>.55)
 if lid=='scarlet':walk[:]=False
 glare=body&covered&(((x/.058)**2+((y+.17)/.28)**2)<1)&(z>.075)&(nz>.5)&(lid=='three_tone')
 for mask,color,r in [(walk,(18,23,25),.82),(glare,(26,34,40),.64),(covered&inside,(167,179,159),.58)]:
  service[mask]=(*color,255);colors[mask]=color;rough[mask]=r
 # Restrained panel and wear cues follow the actual assembled design coordinates.
 weather=np.zeros((N,N,4),np.uint8)
 lines=np.zeros_like(x)
 for st in (-.02,-.31,-.69,-1.02,-1.25,-1.43):
  lines=np.maximum(lines,1-ramp(.00065,.00155,abs(y-st)))
 lines*=fuselage&(z<.13)
 # A few access-panel outlines, not a grid drawn indiscriminately across the airframe.
 fixedwing=group(('wing_left_fixed','wing_right_fixed'))
 for xc in (.665,.825):
  dx=abs(abs(x)-xc);dy=abs(y+.17)
  rectangle=(np.maximum(dx/.045,dy/.055))
  lines=np.maximum(lines,fixedwing*(1-ramp(.012,.035,abs(rectangle-1)))*(abs(nz)>.62))
 # Exhaust residue trails aft from the cowling, feathered into the lower fuselage.
 streak=fuselage*band(-.63,.075,y,.035)*np.exp(-((z+.085)/.035)**2)*(abs(nx)>.5)
 amount=.16 if lid=='three_tone' else (.08 if lid=='midnight' else .035)
 weather_alpha=np.clip(lines*(.16 if lid!='scarlet' else .09)+streak*amount,0,.3)*covered
 weather[:,:,:3]=(36,35,32);weather[:,:,3]=(weather_alpha*255).astype(np.uint8)
 rough+=streak*.055
 # Matte control surfaces and root foot traffic are visibly distinct from metal skin.
 fabric=group(('aileron_','elevator','rudder'));rough+=fabric*(.07 if lid!='scarlet' else .025)
 # Fine abrasion only on walkways, not random bare metal across the paint.
 grain=(np.sin(x*1547+y*1163)+np.sin(x*891-y*1867))*.5
 abrasion=walk*np.maximum(grain-.55,0)*.16
 weather[:,:,3]=np.maximum(weather[:,:,3],(abrasion*255).astype(np.uint8))
 markings=np.zeros((N,N,4),np.uint8)
 insignia=np.zeros_like(markings)
 if lid!='scarlet':
  u=np.where(nx>0,(-.77-y)/.24,(y+1.01)/.24);v=(.095-z)/.15
  if lid=='midnight':u=np.where(nx>0,(-.73-y)/.33,(y+1.06)/.33);v=(.108-z)/.176
  stamp(insignia,emblemarr,u,v,covered&fuselage&(abs(nx)>.5))
  for side,top in [(-1,True),(1,False)]:
   u=(x*side-.72)/.35;v=(-.10-y)/.22
   stamp(insignia,emblemarr,u,v,covered&wing&(x*side>0)&((nz>.55)if top else(nz<-.55)))

 if lid=='scarlet':
  markings=markings57(globals())
 details,stencils,wear_detail,detail_stats=add_details(globals())
 naval_layers={}
 if lid=='midnight':
  stencils[:]=0
  naval_layers=naval_details(globals());detail_stats['naval_g1_10']=naval_stats
 race_layer=np.zeros_like(markings)
 if lid=='scarlet':race_layer=race_details(globals())
 # Paint the image first, then dilate final colours including lettering, to prevent dark fringes at UV island edges.
 for layer in [insignia,markings,weather,details,stencils,wear_detail,race_layer]+list(naval_layers.values()):
  alpha=layer[:,:,3].astype(np.float32)/255;colors=colors*(1-alpha[...,None])+layer[:,:,:3]*alpha[...,None]
 valid=covered.copy()
 for iteration in range(8):
  acc=np.zeros((N,N,3),np.float32);racc=np.zeros((N,N),np.float32);weight=np.zeros((N,N),np.float32)
  for dy,dx in [(0,1),(0,-1),(1,0),(-1,0)]:
   m=np.roll(valid,(dy,dx),(0,1));acc+=np.roll(colors,(dy,dx),(0,1))*m[...,None];racc+=np.roll(rough,(dy,dx),(0,1))*m;weight+=m
  fill=(~valid)&(weight>0);colors[fill]=acc[fill]/weight[fill,None];rough[fill]=racc[fill]/weight[fill];valid|=fill
 merged=Image.fromarray(np.clip(colors,0,255).astype(np.uint8),'RGB').convert('RGBA');merged.convert('RGB').save(out/'basecolor.png');Image.fromarray(markings).save(out/'markings.png');Image.fromarray(design).save(out/'paint_design.png');Image.fromarray(service).save(out/'service_finish.png');Image.fromarray(insignia).save(out/'insignia.png');Image.fromarray(weather).save(out/'weathering.png');Image.fromarray(details).save(out/'fasteners.png');Image.fromarray(stencils).save(out/'service_stencils.png');Image.fromarray(wear_detail).save(out/'localized_wear.png')
 if lid=='scarlet':Image.fromarray(race_layer).save(out/'race_details.png')
 for i,(name,layer)in enumerate(naval_layers.items()):Image.fromarray(layer).save(out/f'naval_{i+1}.png')
 rough=np.clip(rough,0,1);rough8=(rough*255).round().astype(np.uint8);Image.fromarray(rough8).save(out/'roughness.png');orm=np.zeros((N,N,3),np.uint8);orm[:,:,0]=255;orm[:,:,1]=rough8;Image.fromarray(orm).save(out/'orm.png')
 # The lowest bleed layer ensures compositing ORA layers reproduces the final base colour across island margins.
 bleed=np.zeros((N,N,4),np.uint8);bleed[:,:,:3]=np.asarray(merged)[:,:,:3];bleed[:,:,3]=(~covered)*255
 layers=[('Fine localized wear',Image.fromarray(wear_detail)),('Service stencils',Image.fromarray(stencils)),('Fasteners and access panels',Image.fromarray(details)),('Localized surface wear',Image.fromarray(weather)),('57 SOHIO N5588N' if lid=='scarlet' else 'Markings',Image.fromarray(markings)),('National insignia - optional',Image.fromarray(insignia)),('Walkways and protective coating',Image.fromarray(service)),('Paint design and pigment',Image.fromarray(design)),('Atlas edge padding',Image.fromarray(bleed)),('Base coat',Image.fromarray(coat,'RGB').convert('RGBA'))]
 if lid=='scarlet':layers.insert(0,('Race service details',Image.fromarray(race_layer)))
 if lid=='midnight':layers=[(name,Image.fromarray(layer))for name,layer in reversed(list(naval_layers.items()))]+layers
 with zipfile.ZipFile(out/'source.ora','w',zipfile.ZIP_DEFLATED)as archive:
  archive.writestr('mimetype','image/openraster');xml=['<image version="0.0.3" w="2048" h="2048" name="F4U g1.10 '+lid+'"><stack>']
  for i,(name,img)in enumerate(layers):
   buf=io.BytesIO();img.save(buf,format='PNG');archive.writestr(f'data/layer{i}.png',buf.getvalue());xml.append(f'<layer name="{name}" src="data/layer{i}.png" opacity="1.0" visibility="visible" composite-op="svg:src-over" x="0" y="0"/>')
  xml.append('</stack></image>');archive.writestr('stack.xml',''.join(xml));buf=io.BytesIO();merged.save(buf,format='PNG');archive.writestr('mergedimage.png',buf.getvalue())
 checks.append({'id':lid,'roughness_min':float(rough[covered].min()),'roughness_max':float(rough[covered].max()),'walkway_pixels':int(walk.sum()),'metallic':0,'padding_pixels':8,'details':detail_stats});print('LIVERY',lid,flush=True)
(P/'source/scripts/uv-raster-check.json').write_text(json.dumps({'atlas_size':[N,N],'painted_parts':len(layout),'occupied_pixels':int(covered.sum()),'islands_strategy':'existing shared UV layout preserved; 8-pixel final-colour padding','liveries':checks},indent=2))
