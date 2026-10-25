"""Paint the existing Corsair UV atlas with original vector splash graphics.
Only the supplied images' visual vocabulary is used; no photo pixels are embedded.
"""
from pathlib import Path
import sys,json,math,io,zipfile,xml.etree.ElementTree as ET
P=Path(__file__).resolve().parents[2]
# Reuse the established unmodified UV/aircraft-space raster, never re-unwrap the model.
source=Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0]
exec(compile(source,str(Path(__file__).with_name('build_paints.py')),'exec'))
lid='scarlet' # Enables footprint-aware antialiasing in the existing stamp helper.
D=P/'textures/liveries/splash';D.mkdir(parents=True,exist_ok=True)
YELLOW=(255,194,4);BLUE=(19,35,177);GREEN=(106,228,12);CYAN=(0,185,239);RED=(239,37,47);PINK=(222,19,124);INK=(29,29,64);WHITE=(247,242,222)
layers={name:np.zeros((N,N,4),np.uint8)for name in ['01 Sun yellow','02 Red belly and white targets','03 Blue cowl sweep','04 Wing splashes','05 Fuselage splashes','06 Tail splashes','07 Subtle surface details']}
base,belly,cowl_art,wing_art,body_art,tail_art,detail=layers.values()
base[:,:,:3]=YELLOW;base[:,:,3]=covered*255
rough=np.full((N,N),.29,np.float32)

def fill(dst,color,a):
 a=np.clip(a*covered,0,1).astype(np.float32);oa=dst[:,:,3].astype(np.float32)/255;out=a+oa*(1-a)
 rgb=np.asarray(color,dtype=np.float32)*a[...,None]+dst[:,:,:3].astype(np.float32)*oa[...,None]*(1-a[...,None])
 dst[:,:,:3]=np.clip(rgb/np.maximum(out[...,None],1e-8),0,255).astype(np.uint8);dst[:,:,3]=(out*255).round().astype(np.uint8)

def splat(color,seed,tail=1):
 rng=np.random.default_rng(seed);size=1024;im=Image.new('RGBA',(size,size));dr=ImageDraw.Draw(im)
 # Alternating sharp tips and rounded concave valleys, intentionally asymmetric.
 count=9;angles=np.linspace(0,math.tau,count,endpoint=False)+rng.uniform(-.11,.11,count)
 points=[]
 for i,a in enumerate(angles):
  r=rng.uniform(.36,.49);points.append(np.array([.51+math.cos(a)*r,.50+math.sin(a)*r]))
  b=a+(math.tau/count)*.48;r=rng.uniform(.18,.25);points.append(np.array([.51+math.cos(b)*r,.50+math.sin(b)*r]))
 curve=[]
 for i,p in enumerate(points):
  p0=points[(i-1)%len(points)];p1=p;p2=points[(i+1)%len(points)];p3=points[(i+2)%len(points)]
  # Low tension keeps the tips pointed while forming scalloped valleys.
  for t in np.linspace(0,1,18,endpoint=False):
   q=.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
   curve.append(tuple(q*size))
 dr.polygon(curve,fill=(*color,255));dr.line(curve+[curve[0]],fill=(*INK,255),width=6,joint='curve')
 # Long paint streak, satellite droplets and tiny white glints as in the references.
 if tail:
  dr.line([(int(.52*size),int(.51*size)),(int(.10*size),int(.58*size))],fill=(*color,255),width=9)
  dr.ellipse((.07*size,.566*size,.10*size,.592*size),fill=(*color,255))
 for u,v,rx,ry in [(.80,.18,.012,.023),(.19,.80,.018,.012),(.89,.74,.009,.017),(.23,.14,.012,.008)]:
  dr.ellipse(((u-rx)*size,(v-ry)*size,(u+rx)*size,(v+ry)*size),fill=(*color,255))
 dr.arc((.40*size,.42*size,.48*size,.53*size),190,260,fill=(*WHITE,230),width=7)
 dr.arc((.57*size,.59*size,.64*size,.67*size),10,80,fill=(*WHITE,210),width=5)
 return np.asarray(im)

def project(dst,color,seed,u,v,mask,tail=1):
 tmp=np.zeros_like(dst);stamp(tmp,splat(color,seed,tail),u,v,mask&covered)
 a=tmp[:,:,3].astype(np.float32)/255;oa=dst[:,:,3].astype(np.float32)/255;out=a+oa*(1-a)
 rgb=tmp[:,:,:3].astype(np.float32)*a[...,None]+dst[:,:,:3].astype(np.float32)*oa[...,None]*(1-a[...,None])
 dst[:,:,:3]=np.clip(rgb/np.maximum(out[...,None],1e-8),0,255).astype(np.uint8);dst[:,:,3]=(out*255).round().astype(np.uint8)

fixed=group(('wing_',));all_wing=wing;ax=abs(x)
upper=all_wing&(nz>.12);lower=all_wing&(nz<-.12)
body_side=fuselage&(abs(x)>.034)&(abs(nx)>.28)
tail=group(('stabilizer','elevator','fin_fixed','rudder'))
tail_horizontal=group(('stabilizer','elevator'))
bottom=((fuselage&(z<-.045))|lower|(tail_horizontal&(nz<-.12))|(doors&~inside))&covered
fill(belly,RED,bottom)
rho=np.sqrt(x*x+((y+.245)*1.03)**2)
target=np.zeros((N,N),np.float32)
for lo,hi in [(0,.055),(.11,.16),(.24,.29),(.38,.43)]:target=np.maximum(target,band(lo,hi,rho,.003))
fill(belly,WHITE,target*bottom*((all_wing|fuselage|doors)&(y>-.72)))
fill(belly,WHITE,bottom*all_wing*band(.74,.82,ax,.002))
fill(belly,WHITE,bottom*tail_horizontal*band(.20,.245,ax,.0015))

# Cobalt nose with three forward-reaching yellow lobes wrapped around the cowl.
theta=np.arctan2(z-.004,x);edge=.045+.19*np.maximum(0,np.cos(theta*3+.5))**3
nose=body&(y>-.025)
fill(cowl_art,BLUE,nose*ramp(edge-.0015,edge+.0015,y))
outline=nose*(1-ramp(.001,.0035,abs(y-edge)))
fill(cowl_art,INK,outline*.92)
rough[nose&(y>edge)]=.255

# Top: cool splashes on the left, warm splashes on the right. Crosses flap seams.
project(wing_art,GREEN,18,(ax-.28)/.68,(.055-y)/.59,upper&(x<0))
project(wing_art,CYAN,27,(ax-.86)/.48,(.015-y)/.49,upper&(x<0))
project(wing_art,PINK,41,(ax-.31)/.60,(.055-y)/.59,upper&(x>0))
project(wing_art,RED,56,(ax-.82)/.53,(.040-y)/.56,upper&(x>0))
# Outboard underside keeps small colour splashes clear of the central target.
project(wing_art,GREEN,29,(ax-.85)/.44,(-.03-y)/.40,lower&(x<0))
project(wing_art,BLUE,33,(ax-1.06)/.26,(-.09-y)/.31,lower&(x<0))
project(wing_art,PINK,62,(ax-.91)/.41,(-.035-y)/.37,lower&(x>0))

# Fuselage graphics follow longitudinal positions on both sides; no text to mirror.
for center,width,height,zc,color,seed in [(-.22,.36,.32,.035,RED,63),(-.77,.45,.30,.035,GREEN,72),(-1.24,.31,.23,.055,PINK,84)]:
 u=(center+width*.5-y)/width;v=(zc+height*.5-z)/height
 project(body_art,color,seed,u,v,body_side)
# Small longitudinal streaks give the body a lively connection between splashes.
fill(body_art,RED,body_side*band(-.51,-.29,y,.006)*(1-ramp(.0007,.0023,abs(z-.033))))
fill(body_art,GREEN,body_side*band(-1.10,-.86,y,.006)*(1-ramp(.0007,.002,abs(z-.025))))

# Tail graphics use the same palette and remain continuous across elevator/rudder cuts.
project(tail_art,BLUE,97,(y+1.55)/.45,(.50-z)/.40,group(('fin_fixed','rudder')))
project(tail_art,GREEN,109,(ax-.01)/.49,(-1.25-y)/.36,tail_horizontal&(x<0)&(nz>.12))
project(tail_art,PINK,117,(ax-.01)/.49,(-1.25-y)/.36,tail_horizontal&(x>0)&(nz>.12))
project(tail_art,BLUE,124,(ax-.28)/.25,(-1.28-y)/.30,tail_horizontal&(x<0)&(nz>.12))

# Finish details are quieter than the artwork: thin fasteners and satin control surfaces.
rough+=group(('aileron_','elevator','rudder'))*.025
periodic=lambda v,p:abs((v+p*.5)%p-p*.5)
for st in [-.045,-.295,-.655,-1.04,-1.265]:
 dots=(1-ramp(.0005,.0015,np.hypot(y-st,periodic(np.arctan2(z,x)*.13,.019))))*fuselage*(z<.13)
 fill(detail,(107,91,47),dots*.16)
for st in [.108,.280]:
 dots=(1-ramp(.0008,.002,np.hypot(y-st,periodic(theta*.15,.037))))*group(('cowl',))
 fill(detail,(215,214,196),dots*.30)
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
editable=list(layers.items())+[('08 Atlas padding',bleed)]
root=ET.Element('image',w=str(N),h=str(N),name='Corsair Splash g1.11');stack=ET.SubElement(root,'stack')
with zipfile.ZipFile(D/'source.ora','w',zipfile.ZIP_DEFLATED)as archive:
 archive.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
 for i,(name,arr)in reversed(list(enumerate(editable))):
  im=Image.fromarray(arr);im.save(D/f'layer_{i+1}.png');buf=io.BytesIO();im.save(buf,format='PNG');src=f'data/layer{i}.png';archive.writestr(src,buf.getvalue());ET.SubElement(stack,'layer',name=name,src=src,x='0',y='0',opacity='1.0',visibility='visible',**{'composite-op':'svg:src-over'})
 archive.writestr('stack.xml',ET.tostring(root));buf=io.BytesIO();merged.save(buf,format='PNG');archive.writestr('mergedimage.png',buf.getvalue())
(D/'design.json').write_text(json.dumps({'id':'splash','name':'Sunburst Splash','resolution':[N,N],'layers':[n for n,_ in editable],'palette':{'yellow':YELLOW,'blue':BLUE,'green':GREEN,'cyan':CYAN,'red':RED,'pink':PINK,'outline':INK},'reference':'Five user-supplied RC aerobatic aircraft photographs. Graphic language adapted to the Corsair, no photograph pixels.','geometry_and_uv_preserved':True,'underside':'red with concentric white recognition rings','surface_coordinates':'rest design space, world metres multiplied by 0.9','layer_pixels':{n:int((arr[:,:,3]>0).sum())for n,arr in editable}},indent=2))
print('SPLASH11_PAINT_DONE',flush=True)
