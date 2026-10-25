"""Native UV painting: white Corsair with curved chromatic feathers and side ribbons."""
from pathlib import Path
import sys,json,math,io,zipfile,xml.etree.ElementTree as ET
P=Path(__file__).resolve().parents[2]
source=Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0]
exec(compile(source,str(Path(__file__).with_name('build_paints.py')),'exec'))
lid='scarlet';D=P/'textures/liveries/spectrum';D.mkdir(parents=True,exist_ok=True)
WHITE=(240,242,237);GOLD=(255,178,8);ORANGE=(245,105,9);RED=(201,24,33);PURPLE=(114,33,109);BLUE=(26,70,159);DARK=(18,26,42)
palette=np.array([GOLD,ORANGE,RED,PURPLE,BLUE,DARK],np.float32)
layers={name:np.zeros((N,N,4),np.uint8)for name in ['01 Porcelain white','02 Wing feathers','03 Fuselage ribbons','04 Cowl crest','05 Tail feathers','06 Fine surface finish']}
base,wing_art,body_art,crest,tail_art,detail=layers.values();base[:,:,:3]=WHITE;base[:,:,3]=covered*255
rough=np.full((N,N),.275,np.float32)
def fill(dst,color,a):
 a=np.clip(a*covered,0,1).astype(np.float32);oa=dst[:,:,3].astype(np.float32)/255;out=a+oa*(1-a)
 rgb=np.asarray(color,dtype=np.float32)*a[...,None]+dst[:,:,:3].astype(np.float32)*oa[...,None]*(1-a[...,None])
 dst[:,:,:3]=np.clip(rgb/np.maximum(out[...,None],1e-8),0,255).astype(np.uint8);dst[:,:,3]=(out*255).round().astype(np.uint8)
def color_at(t):
 t=np.clip(t,0,1)*5;i=np.minimum(t.astype(int),4);f=t-i
 return palette[i]*(1-f[...,None])+palette[i+1]*f[...,None]
def footprint(v,minimum=.008,maximum=.12):
 d=[]
 for axis in [0,1]:
  good=covered&(part==np.roll(part,1,axis));d.append(np.where(good,abs(v-np.roll(v,1,axis)),0))
 return np.clip((d[0]+d[1])*.65,minimum,maximum)
def envelope(prefixes,maximum):
 # Exact projected triangle-edge intersections avoid a ragged envelope from UV texel sampling.
 tri=np.array([t['xyz']for o in layout if o['name'].startswith(prefixes)for t in o['triangles']],float)
 a=np.concatenate([tri[:,0],tri[:,1],tri[:,2]]);b=np.concatenate([tri[:,1],tri[:,2],tri[:,0]])
 a[:,0]=abs(a[:,0]);b[:,0]=abs(b[:,0]);dx=b[:,0]-a[:,0];good=abs(dx)>1e-9;a=a[good];b=b[good];dx=dx[good]
 stations=np.linspace(.0001,maximum-.0001,600);lo=[];hi=[]
 for s in stations:
  u=(s-a[:,0])/dx;hit=(u>=0)&(u<=1);ys=a[hit,1]+u[hit]*(b[hit,1]-a[hit,1])
  lo.append(float(ys.min())if len(ys)else np.nan);hi.append(float(ys.max())if len(ys)else np.nan)
 lo=np.array(lo);hi=np.array(hi);valid=np.isfinite(lo);lo=np.interp(stations,stations[valid],lo[valid]);hi=np.interp(stations,stations[valid],hi[valid])
 le=np.interp(abs(x),stations,hi);te=np.interp(abs(x),stations,lo)
 return le,te
def feathers(dst,mask,span,start,pitch,sweep,prefixes):
 ax=np.abs(x);le,te=envelope(prefixes,span);t=(le-y)/np.maximum(le-te,.015)
 swept=ax+sweep*(t-.5)+sweep*.65*np.sin(np.pi*np.clip(t,0,1))
 q=(swept-start)/pitch;index=np.floor(q+.5);phase=q-index
 # Rounded ends and gently curved white slots are the visual signature of the references.
 width=.425*np.sqrt(np.clip(1-((t-.5)/.46)**6,0,1))
 aa=footprint(q);ta=footprint(t,minimum=.006,maximum=.04)
 a=(1-ramp(width-aa,width+aa,abs(phase)))*band(.04,.96,t,ta)*band(start-.035,span-.007,ax,.003)*mask
 col=color_at((start+index*pitch-start)/(span-start-.04))
 fill(dst,col,a)
 return {'nominal_feathers_per_side':round((span-start)/pitch),'white_chord_margin':.04,'curved_gap_fraction':.15}
wing_doors=doors&~inside&(abs(x)>.18)&(y>-.56)&(y<.02)
wing_spec=feathers(wing_art,wing|wing_doors,1.25,.16,.062,.095,('wing_','flap_','aileron_'))
tail_horizontal=group(('stabilizer','elevator'))
tail_spec=feathers(tail_art,tail_horizontal,.51,.045,.052,.044,('stabilizer','elevator'))

# Six longitudinal ribbons lie below the cockpit and taper into the tail.
# They wrap around the side of the body and reach matching exterior door portions.
ax=abs(x);side=(group(('fuselage_core','cowl'))|(doors&~inside))&(ax>.029)
top=np.interp(y,[-1.60,-1.24,-.70,-.20,.08,.30],[.072,.065,.056,.075,.090,.104])
height=np.interp(y,[-1.60,-1.24,-.70,-.20,.08,.30],[.014,.064,.140,.180,.158,.065])
q=(top-z)/height
qa=footprint(q,minimum=.006,maximum=.045)
length=band(-1.57,.22,y,.009)
stripe_colors=[DARK,BLUE,PURPLE,RED,ORANGE,GOLD]
for i,col in enumerate(stripe_colors):
 fill(body_art,col,side*length*band(i/6+.013,(i+1)/6-.013,q,qa))

# An understated blue hooked crest at the front leads into the upper blue ribbon.
def bezier(points,steps=45):
 p0,p1,p2,p3=[np.asarray(p,float)for p in points]
 return [tuple((1-t)**3*p0+3*(1-t)**2*t*p1+3*(1-t)*t*t*p2+t**3*p3)for t in np.linspace(0,1,steps)]
im=Image.new('RGBA',(1024,512));dr=ImageDraw.Draw(im)
segments=[[(.04,.78),(.05,.18),(.27,.08),(.43,.22)],[(.43,.22),(.61,.42),(.84,.39),(1,.43)],[(1,.43),(1,.61),(1,.73),(1,.77)],[(1,.77),(.75,.73),(.57,.59),(.42,.53)],[(.42,.53),(.25,.44),(.16,.50),(.04,.78)]]
pts=[(u*1024,v*512)for seg in segments for u,v in bezier(seg)]
dr.polygon(pts,fill=(*BLUE,255))
# Small white separation cut, rather than a cartoon eye or literal branding.
cut=bezier([(.25,.38),(.33,.27),(.39,.31),(.45,.43)])
dr.line([(u*1024,v*512)for u,v in cut],fill=(*WHITE,255),width=13)
uu=(.31-y)/.35
stamp(crest,np.asarray(im),uu,(.145-z)/.16,group(('fuselage_core','cowl'))&(ax>.045)&covered)
crest[:,:,3]=(crest[:,:,3]*(1-ramp(.72,1,uu))).astype(np.uint8)

# A short chromatic fan at the foot of the otherwise white fin, matching the reference balance.
fin=group(('fin_fixed','rudder'))
level=(z-.075)/.115
la=footprint(level,minimum=.007,maximum=.04)
for i,col in enumerate(reversed(stripe_colors)):
 fill(tail_art,col,fin*band(i/6+.015,(i+1)/6-.015,level,la)*band(-1.52,-1.19,y,.016))

# Restrained access hardware, not military markings; white remains the primary surface.
periodic=lambda v,p:abs((v+p*.5)%p-p*.5)
for st in [-.045,-.295,-.655,-1.04,-1.265]:
 a=(1-ramp(.0005,.0015,np.hypot(y-st,periodic(np.arctan2(z,x)*.13,.019))))*fuselage*(z<.13)
 fill(detail,(93,102,111),a*.18)
theta=np.arctan2(z-.004,x)
for st in [.108,.280]:
 a=(1-ramp(.0008,.002,np.hypot(y-st,periodic(theta*.15,.037))))*group(('cowl',))
 fill(detail,(93,102,111),a*.25)
rough+=group(('aileron_','elevator','rudder'))*.025
colors=np.zeros((N,N,3),np.float32)
for arr in layers.values():
 a=arr[:,:,3].astype(np.float32)/255;colors=colors*(1-a[...,None])+arr[:,:,:3]*a[...,None]
valid=covered.copy()
for _ in range(8):
 acc=np.zeros_like(colors);racc=np.zeros_like(rough);weight=np.zeros_like(rough)
 for dy,dx in [(1,0),(-1,0),(0,1),(0,-1)]:
  m=np.roll(valid,(dy,dx),(0,1));acc+=np.roll(colors,(dy,dx),(0,1))*m[...,None];racc+=np.roll(rough,(dy,dx),(0,1))*m;weight+=m
 mask=(~valid)&(weight>0);colors[mask]=acc[mask]/weight[mask,None];rough[mask]=racc[mask]/weight[mask];valid|=mask
merged=Image.fromarray(np.clip(colors,0,255).astype(np.uint8)).convert('RGBA');merged.convert('RGB').save(D/'basecolor.png')
orm=np.zeros((N,N,3),np.uint8);orm[:,:,0]=255;orm[:,:,1]=(np.clip(rough,0,1)*255).round().astype(np.uint8);Image.fromarray(orm).save(D/'orm.png');Image.fromarray(orm[:,:,1]).save(D/'roughness.png')
bleed=np.zeros((N,N,4),np.uint8);bleed[:,:,:3]=np.asarray(merged)[:,:,:3];bleed[:,:,3]=(~covered)*255
editable=list(layers.items())+[('07 Atlas padding',bleed)]
root=ET.Element('image',w=str(N),h=str(N),name='Corsair Spectrum g1.12');stack=ET.SubElement(root,'stack')
with zipfile.ZipFile(D/'source.ora','w',zipfile.ZIP_DEFLATED)as archive:
 archive.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
 for i,(name,arr)in reversed(list(enumerate(editable))):
  im=Image.fromarray(arr);im.save(D/f'layer_{i+1}.png');buf=io.BytesIO();im.save(buf,format='PNG');src=f'data/layer{i}.png';archive.writestr(src,buf.getvalue());ET.SubElement(stack,'layer',name=name,src=src,x='0',y='0',opacity='1.0',visibility='visible',**{'composite-op':'svg:src-over'})
 archive.writestr('stack.xml',ET.tostring(root));buf=io.BytesIO();merged.save(buf,format='PNG');archive.writestr('mergedimage.png',buf.getvalue())
# Repaint the existing three blades using their existing UV1. Hub remains polished metal.
yy,xx=np.mgrid[:256,:1024];r=xx/1023*.42;chord=1-yy/255
pix=np.empty((256,1024,3),np.uint8);pix[:]=(63,73,87)
pix[(r>.355)&(r<.368)]=WHITE;pix[r>.382]=WHITE
e=((r-.228)/.010)**2+((chord-.5)/.10)**2;pix[e<1]=(219,223,222);pix[e<.65]=BLUE
Image.fromarray(pix).save(D/'propeller_basecolor.png')
(D/'design.json').write_text(json.dumps({'id':'spectrum','name':'Spectrum Wings','resolution':[N,N],'layers':[n for n,_ in editable],'palette':{'white':WHITE,'gold':GOLD,'orange':ORANGE,'red':RED,'purple':PURPLE,'blue':BLUE,'dark':DARK},'reference':'Three user supplied photos of a white aerobatic biplane with chromatic feather graphics. Adapted to the Corsair, no photo pixels or aircraft identity copied.','geometry_and_uv_preserved':True,'wing_feathers':wing_spec,'tail_feathers':tail_spec,'underside':'Same feather graphic on both wing faces; white belly and exterior doors with side-ribbon continuations.','propeller':'Existing three-blade geometry, graphite grey paint with white tip bands, polished original hub.'},indent=2))
print('SPECTRUM12_PAINT_DONE',flush=True)
