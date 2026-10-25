"""Thunderbirds-inspired Corsair: original paint artwork on the unchanged shared atlas."""
from pathlib import Path
import sys,json,math,io,zipfile,xml.etree.ElementTree as ET,ast
P=Path(__file__).resolve().parents[2]
source=Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0]
exec(compile(source,str(Path(__file__).with_name('build_paints.py')),'exec'))
lid='scarlet';D=P/'textures/liveries/thunderbirds';D.mkdir(parents=True,exist_ok=True)
WHITE=(242,243,240);RED=(199,24,39);BLUE=(16,30,60);GREY=(76,82,91)
layers={name:np.zeros((N,N,4),np.uint8)for name in ['01 Display white','02 Nose and side bands','03 Wing and tail tips','04 Ventral bird','05 Identity and insignia','06 Fin identity','07 Surface finish']}
base,nose,trim,bird,marks,tailmarks,detail=layers.values()
base[:,:,:3]=WHITE;base[:,:,3]=covered*255;rough=np.full((N,N),.27,np.float32)
tree=ast.parse(Path(__file__).with_name('build_spectrum12.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name in {'fill','footprint','envelope'}:exec(compile(ast.Module(body=[node],type_ignores=[]),'shared_paint_helpers','exec'))
ax=abs(x);cowl=group(('cowl',));fin=group(('fin_fixed','rudder'));tail_horizontal=group(('stabilizer','elevator'))
upper=wing&(nz>.15);lower=wing&(nz<-.15);wingdoors=doors&~inside&(ax>.18)&(y>-.56)&(y<.02)
le,te=envelope(('wing_','flap_','aileron_'),1.25);t=(le-y)/np.maximum(le-te,.015)
taa=footprint(t,.004,.025)
# Paint outlines follow the broad wing sweep, not small openings in its leading edge.
sx=np.linspace(.145,1.08,38)
sy=np.array([np.median(le[wing&covered&(abs(ax-s)<.018)])for s in sx])
valid_samples=np.isfinite(sy)
art_le=np.polyval(np.polyfit(sx[valid_samples],sy[valid_samples],3),ax)
bt=(art_le-y)/np.maximum(art_le-te,.015);btaa=footprint(bt,.004,.025)

# Red-white-blue scalloped bands wrap the round radial cowling.
phase=np.arctan2(z-.004,x);station=y+.021*np.cos(2*phase)
fill(nose,RED,cowl*ramp(.244,.250,station))
fill(nose,BLUE,cowl*band(.157,.196,station,.0025))
side=group(('fuselage_core','cowl'))&(ax>.030)&(abs(nx)>.25)
line=np.interp(y,[-1.54,-1.10,-.68,-.2,.14],[.053,.019,-.017,-.049,-.065])
width=np.interp(y,[-1.54,-1.10,-.68,-.2,.14],[.002,.006,.010,.012,.014])
fill(nose,RED,side*band(-1.50,.144,y,.005)*band(-width,width,z-line,.002))
fill(nose,BLUE,side*band(-1.50,.145,y,.005)*band(width+.007,width+.014,z-line,.002))
fill(nose,BLUE,group(('canopy_frame',))*ramp(.148,.156,z))

# Above: white fields, a navy band, white separator and red tips.
fill(trim,BLUE,wing*band(1.052,1.090,ax,.002))
fill(trim,RED,wing*ramp(1.148,1.153,ax))
fill(trim,BLUE,tail_horizontal*band(.390,.417,ax,.0018))
fill(trim,RED,tail_horizontal*ramp(.459,.464,ax))

def polygon_field(px,py,points):
 inside_poly=np.zeros((N,N),bool);distance=np.full((N,N),100,np.float32)
 for i,(a,b)in enumerate(points):
  c,d=points[(i+1)%len(points)];dx=c-a;dy=d-b
  u=np.clip(((px-a)*dx+(py-b)*dy)/(dx*dx+dy*dy),0,1)
  distance=np.minimum(distance,np.hypot(px-(a+u*dx),py-(b+u*dy)))
  if abs(dy)>1e-10:inside_poly^=((b>py)!=(d>py))&(px<(dx*(py-b)/dy+a))
 aa=footprint(px,.0007,.0035)+footprint(py,.0007,.0035)
 return ramp(-aa,aa,np.where(inside_poly,distance,-distance))

# Below: a dark blue bird, with a central head/body and rounded feather separations.
belly=group(('fuselage_core','cowl'))&(z<-.040)
body_points=[(0,.241),(.058,.181),(.036,.144),(.069,.065),(.108,-.135),(.109,-.390),(.060,-.925),(.071,-1.285),(0,-1.420),(-.071,-1.285),(-.060,-.925),(-.109,-.390),(-.108,-.135),(-.069,.065),(-.036,.144),(-.058,.181)]
fill(bird,BLUE,(belly|lower|wingdoors|(doors&~inside&(ax<.14)))*polygon_field(x,y,body_points))
q=(ax-.145)/.088;ph=q-np.floor(q)
trailing=.925-.135*np.exp(-((ph-.50)/.14)**2)
feathers=(lower|wingdoors)*band(.115,1.025,ax,.004)*band(.115,trailing,bt,btaa)
fill(bird,BLUE,feathers)
# A fine white inset articulates the feather perimeter without adding geometry.
outline=(lower|wingdoors)*band(.20,1.015,ax,.003)*band(.142,.149,bt,btaa*.55)
fill(bird,WHITE,outline*.90)
tle,tte=envelope(('stabilizer','elevator'),.51);tt=(tle-y)/np.maximum(tle-tte,.02)
tq=(ax-.09)/.065;tp=tq-np.floor(tq)
fill(bird,BLUE,tail_horizontal*(nz<-.15)*band(.065,.372,ax,.003)*band(.17,.88-.10*np.exp(-((tp-.5)/.15)**2),tt,.012))

def bitmap(text,color=BLUE,font='arialbd.ttf',size=240):
 f=ImageFont.truetype('C:/Windows/Fonts/'+font,size);b=f.getbbox(text);im=Image.new('RGBA',(b[2]-b[0]+16,b[3]-b[1]+16))
 ImageDraw.Draw(im).text((8-b[0],8-b[1]),text,font=f,fill=(*color,255));return np.asarray(im)
def sidetext(dst,text,front,width,upper,height,font='arialbd.ttf'):
 u=np.where(x<0,(front-y)/width,(y-(front-width))/width)
 stamp(dst,bitmap(text,font=font),u,(upper-z)/height,side&covered)
sidetext(marks,'Thunderbirds',.060,.405,.081,.065,font='segoescb.ttf')
sidetext(marks,'UNITED STATES AIR FORCE',-.715,.565,.088,.043)
stamp(marks,bitmap('USAF'),(x+.995)/.395,(-.153-y)/.147,upper&(x<0)&covered)

# Modern star-and-bar graphic is drawn locally, with removable identity layer.
im=Image.new('RGBA',(800,500));dr=ImageDraw.Draw(im)
dr.rectangle((15,145,785,355),fill=(*BLUE,255));dr.ellipse((150,0,650,500),fill=(*BLUE,255))
dr.rectangle((37,167,763,333),fill=(*WHITE,255));dr.rectangle((37,231,763,269),fill=(*RED,255));dr.ellipse((169,19,631,481),fill=(*BLUE,255))
points=[]
for i in range(10):
 angle=-math.pi/2+i*math.pi/5;r=218 if i%2==0 else 83.3;points.append((400+r*math.cos(angle),250+r*math.sin(angle)))
dr.polygon(points,fill=(*WHITE,255));insignia=np.asarray(im)
stamp(marks,insignia,(x-.600)/.395,(-.125-y)/.232,upper&(x>0)&covered)

# Fin crest and number: adapted to the Corsair's round fin rather than a jet outline.
crest=.442-.068*np.exp(-((y+1.205)/.10)**2)
fill(tailmarks,RED,fin*ramp(crest-.003,crest+.003,z))
fill(tailmarks,BLUE,fin*band(crest-.035,crest-.020,z,.002))
im=Image.new('RGBA',(512,512));dr=ImageDraw.Draw(im)
dr.ellipse((46,46,466,466),fill=(*BLUE,255));dr.ellipse((61,61,451,451),fill=(*WHITE,255))
f=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',340);box=f.getbbox('1');dr.text(((512-(box[2]-box[0]))/2-box[0],(512-(box[3]-box[1]))/2-box[1]),'1',font=f,fill=(*BLUE,255))
tu=np.where(x<0,(-1.234-y)/.174,(y+1.408)/.174)
stamp(tailmarks,np.asarray(im),tu,(.365-z)/.174,fin&covered)

# Restrained surface detail and matte footing preserve the airshow finish.
periodic=lambda v,p:abs((v+p*.5)%p-p*.5)
for st in [-.045,-.295,-.655,-1.04,-1.265]:
 a=(1-ramp(.0005,.0016,np.hypot(y-st,periodic(np.arctan2(z,x)*.13,.019))))*fuselage*(z<.135)
 fill(detail,(83,91,103),a*.16)
for st in [.108,.280]:
 a=(1-ramp(.0008,.002,np.hypot(y-st,periodic(phase*.15,.037))))*cowl
 fill(detail,(95,104,115),a*.22)
walk=wing&(ax>.19)&(ax<.28)&(y>-.39)&(y<-.20)&(nz>.55)
fill(detail,GREY,walk*.75);rough[walk]=.61
rough+=group(('aileron_','elevator','rudder'))*.025
rough+=.006*np.sin(y*21+x*16+z*9)
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
root=ET.Element('image',w=str(N),h=str(N),name='Corsair Thunderbirds g1.14');stack=ET.SubElement(root,'stack')
with zipfile.ZipFile(D/'source.ora','w',zipfile.ZIP_DEFLATED)as archive:
 archive.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
 for i,(name,arr)in reversed(list(enumerate(editable))):
  im=Image.fromarray(arr);im.save(D/f'layer_{i+1}.png');buf=io.BytesIO();im.save(buf,format='PNG');src=f'data/layer{i}.png';archive.writestr(src,buf.getvalue());ET.SubElement(stack,'layer',name=name,src=src,x='0',y='0',opacity='1.0',visibility='visible',**{'composite-op':'svg:src-over'})
 archive.writestr('stack.xml',ET.tostring(root));buf=io.BytesIO();merged.save(buf,format='PNG');archive.writestr('mergedimage.png',buf.getvalue())

# Coordinated propeller paint uses the existing extra UV set.
yy,xx=np.mgrid[:256,:1024];r=xx/1023*.42;chord=1-yy/255
pix=np.empty((256,1024,3),np.uint8);pix[:]=(27,32,40)
pix[(r>.355)&(r<.375)]=WHITE;pix[r>.388]=RED
e=((r-.228)/.010)**2+((chord-.5)/.10)**2;pix[e<1]=WHITE;pix[e<.65]=RED
Image.fromarray(pix).save(D/'propeller_basecolor.png')
(D/'design.json').write_text(json.dumps({'id':'thunderbirds','name':'Thunderbirds Corsair','resolution':[N,N],'layers':[n for n,_ in editable],'palette':{'white':WHITE,'red':RED,'navy':BLUE},'interpretation':'USAF Thunderbirds-inspired concept adapted to an F4U Corsair, not a historical aircraft reconstruction. Colours and bird silhouette are visual interpretations, not measured official specifications.','sources':['https://www.airforce.com/thunderbirds/overview','https://www.dvidshub.net/image/9578190/diamond-sky-thunderbirds-fly-over-luke-days-2026-airshow','https://www.dvidshub.net/image/9578188/diamond-sky-thunderbirds-fly-over-luke-days-2026-airshow'],'source_photo_pixels_used':False,'geometry_and_uv_preserved':True,'tail_number':'1','underside':'Dark navy bird body and feathered wings, including exterior gear doors in the closed pose.','propeller':'Existing three blades with graphite paint, white bands and red tips; red cone on existing connected component.'},indent=2))
print('THUNDERBIRDS14_PAINT_DONE',flush=True)
