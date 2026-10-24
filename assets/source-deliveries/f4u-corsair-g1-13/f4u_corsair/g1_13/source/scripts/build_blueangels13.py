"""Blue Angels-inspired Corsair paint; original artwork, preserved shared UV atlas."""
from pathlib import Path
import sys,json,math,io,zipfile,xml.etree.ElementTree as ET,ast
P=Path(__file__).resolve().parents[2]
source=Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0]
exec(compile(source,str(Path(__file__).with_name('build_paints.py')),'exec'))
lid='scarlet';D=P/'textures/liveries/blueangels';D.mkdir(parents=True,exist_ok=True)
BLUE=(12,38,112);YELLOW=(255,194,24);DARK=(8,20,48)
layers={name:np.zeros((N,N,4),np.uint8)for name in ['01 Cobalt blue','02 Yellow trim','03 Fuselage lettering','04 Tail number','05 Wing lettering','06 Belly arrow','07 Service finish']}
base,trim,letters,tailmarks,wingmarks,arrow,detail=layers.values()
base[:,:,:3]=BLUE;base[:,:,3]=covered*255;rough=np.full((N,N),.245,np.float32)
# Shared mathematical helpers are kept in the editable source bundle.
tree=ast.parse(Path(__file__).with_name('build_spectrum12.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name in {'fill','footprint','envelope'}:exec(compile(ast.Module(body=[node],type_ignores=[]),'shared_paint_helpers','exec'))
ax=abs(x);cowl=group(('cowl',));fin=group(('fin_fixed','rudder'));tail_horizontal=group(('stabilizer','elevator'))
le,te=envelope(('wing_','flap_','aileron_'),1.25)
fill(trim,YELLOW,wing*band(-.008,.025,le-y,.0025))
fill(trim,YELLOW,wing*ramp(1.125,1.131,ax))
tle,tte=envelope(('stabilizer','elevator'),.51)
fill(trim,YELLOW,tail_horizontal*band(-.008,.012,tle-y,.002))
fill(trim,YELLOW,tail_horizontal*ramp(.430,.436,ax))
fill(trim,YELLOW,fin*ramp(.434,.439,z))
fill(trim,YELLOW,cowl*ramp(.284,.290,y))
# The slim gold side stripe sits above the large lettering, below the cockpit sill.
stripe_z=np.interp(y,[-1.52,-1.20,-.72,-.32,.12],[.060,.074,.105,.119,.108])
side=group(('fuselage_core','cowl'))&(ax>.033)&(abs(nx)>.25)
width=np.interp(y,[-1.5,-1.2,-.3,.2],[.0015,.0034,.0045,.005])
fill(trim,YELLOW,side*band(-1.50,.286,y,.004)*(1-ramp(width,width+.0025,abs(z-stripe_z))))
fill(trim,YELLOW,group(('canopy_frame',))*ramp(.150,.155,z))

def bitmap(text,font='arialbd.ttf',size=240):
 f=ImageFont.truetype('C:/Windows/Fonts/'+font,size);b=f.getbbox(text);im=Image.new('RGBA',(b[2]-b[0]+16,b[3]-b[1]+16))
 ImageDraw.Draw(im).text((8-b[0],8-b[1]),text,font=f,fill=(*YELLOW,255));return np.asarray(im)
def sidetext(dst,text,front,width,upper,height,mask=side,font='arialbd.ttf'):
 u=np.where(nx>0,(front-y)/width,(y-(front-width))/width)
 stamp(dst,bitmap(text,font),u,(upper-z)/height,mask&covered)
sidetext(letters,'Blue Angels',.055,.355,.078,.065,font='segoescb.ttf')
sidetext(letters,'U.S. NAVY',-.765,.465,.077,.080)
# Fin normals have the opposite orientation to the existing fuselage paint layout.
tu=np.where(nx>0,(-1.245-y)/.135,(y+1.380)/.135)
stamp(tailmarks,bitmap('1'),1-tu,(.407-z)/.202,fin&covered)

# The two wing surfaces are independently oriented so the words read correctly from above/below.
upper=wing&(nz>.15);lower=wing&(nz<-.15)
stamp(wingmarks,bitmap('U.S.'),(x+1.055)/.36,(-.185-y)/.125,upper&(x<0)&covered)
stamp(wingmarks,bitmap('NAVY'),(x-.555)/.50,(-.185-y)/.125,upper&(x>0)&covered)
stamp(wingmarks,bitmap('U.S.'),(1.055-x)/.36,(-.185-y)/.125,lower&(x>0)&covered)
stamp(wingmarks,bitmap('NAVY'),(-.555-x)/.50,(-.185-y)/.125,lower&(x<0)&covered)

# A gold arrow spans the assembled underside, including closed exterior gear doors.
im=Image.new('RGBA',(1024,2048));dr=ImageDraw.Draw(im)
points=[(0,.155),(.238,-.315),(.055,-.205),(.039,-1.285),(-.039,-1.285),(-.055,-.205),(-.238,-.315)]
dr.polygon([((a+.25)/.5*1023,(.18-b)/1.48*2047)for a,b in points],fill=(*YELLOW,255))
bottom=(group(('fuselage_core','cowl'))&(z<-.042))|lower|(doors&~inside)
inpoly=np.zeros((N,N),bool);dist=np.full((N,N),100,np.float32)
for i,(px,py)in enumerate(points):
 qx,qy=points[(i+1)%len(points)];dx=qx-px;dy=qy-py
 u=np.clip(((x-px)*dx+(y-py)*dy)/(dx*dx+dy*dy),0,1)
 dist=np.minimum(dist,np.hypot(x-(px+u*dx),y-(py+u*dy)))
 if abs(dy)>1e-10:inpoly^=((py>y)!=(qy>y))&(x<(dx*(y-py)/dy+px))
signed=np.where(inpoly,dist,-dist);aa=footprint(x,.0007,.004)+footprint(y,.0007,.004)
fill(arrow,YELLOW,bottom*ramp(-aa,aa,signed))

# Airshow finish: quiet fasteners and service surfaces, without combat-weathering graphics.
periodic=lambda v,p:abs((v+p*.5)%p-p*.5)
for st in [-.045,-.295,-.655,-1.04,-1.265]:
 a=(1-ramp(.0005,.0016,np.hypot(y-st,periodic(np.arctan2(z,x)*.13,.019))))*fuselage*(z<.135)
 fill(detail,(104,130,167),a*.18)
theta=np.arctan2(z-.004,x)
for st in [.108,.280]:
 a=(1-ramp(.0008,.002,np.hypot(y-st,periodic(theta*.15,.037))))*cowl
 fill(detail,(156,172,183),a*.30)
walk=wing&(ax>.19)&(ax<.28)&(y>-.39)&(y<-.20)&(nz>.55)
fill(detail,DARK,walk*.78);rough[walk]=.61
rough+=group(('aileron_','elevator','rudder'))*.025
# Modest material variation keeps the large blue fields from looking like flat plastic.
rough+=.007*np.sin(y*21+x*16+z*9)
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
root=ET.Element('image',w=str(N),h=str(N),name='Corsair Blue Angels g1.13');stack=ET.SubElement(root,'stack')
with zipfile.ZipFile(D/'source.ora','w',zipfile.ZIP_DEFLATED)as archive:
 archive.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
 for i,(name,arr)in reversed(list(enumerate(editable))):
  im=Image.fromarray(arr);im.save(D/f'layer_{i+1}.png');buf=io.BytesIO();im.save(buf,format='PNG');src=f'data/layer{i}.png';archive.writestr(src,buf.getvalue());ET.SubElement(stack,'layer',name=name,src=src,x='0',y='0',opacity='1.0',visibility='visible',**{'composite-op':'svg:src-over'})
 archive.writestr('stack.xml',ET.tostring(root));buf=io.BytesIO();merged.save(buf,format='PNG');archive.writestr('mergedimage.png',buf.getvalue())
(D/'design.json').write_text(json.dumps({'id':'blueangels','name':'Blue Angels Corsair','resolution':[N,N],'layers':[n for n,_ in editable],'palette':{'cobalt_blue':BLUE,'yellow':YELLOW,'walkway':DARK},'interpretation':'Blue Angels-inspired concept applied to an F4U Corsair; not a historical aircraft reconstruction. Display RGB colours are visual choices, not measured paint specifications. Script lettering is a typographic interpretation.','sources':['https://www.dvidshub.net/news/376027/fleet-readiness-center-southeast-plays-critical-part-providing-blue-angels-with-new-super-hornet-aircraft','https://www.blueangels.navy.mil/history/events.htm','https://www.history.navy.mil/browse-by-topic/communities/naval-aviation/notable-squadrons/blue-angels/blue-angels-aircraft.html'],'source_photo_pixels_used':False,'geometry_and_uv_preserved':True,'tail_number':'1','underside':'Gold forward arrow continuous across closed doors; U.S. NAVY wing lettering','propeller':'Existing black/yellow-tip blades; new yellow cone material on the existing connected component.'},indent=2))
print('BLUEANGELS13_PAINT_DONE',flush=True)
