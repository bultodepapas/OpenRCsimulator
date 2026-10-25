"""4K woven-carbon and fluorescent-orange concept on the original Corsair UVs."""
from pathlib import Path
import sys,json,math,io,zipfile,ast,shutil,xml.etree.ElementTree as ET
P=Path(__file__).resolve().parents[2]
shared=Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0].replace('N=2048','N=4096')
exec(compile(shared,'shared_uv_painter','exec'))
lid='scarlet';D=P/'textures/liveries/carbon';D.mkdir(exist_ok=True)
# Restrict decal sampling to its UV footprint instead of allocating a full 4K
# interpolant for every small stencil. The same projection and prefilter are used.
_full_stamp=stamp
def stamp(arr,bitmap,uu,vv,mask):
 valid=mask&(uu>=0)&(uu<=1)&(vv>=0)&(vv<=1)
 rows,cols=np.nonzero(valid)
 if not len(rows):return
 y0=max(0,int(rows.min())-2);y1=min(N,int(rows.max())+3)
 x0=max(0,int(cols.min())-2);x1=min(N,int(cols.max())+3)
 sl=np.s_[y0:y1,x0:x1]
 _full_stamp(arr[sl],bitmap,uu[sl],vv[sl],mask[sl])
tree=ast.parse(Path(__file__).with_name('build_spectrum12.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name in ['fill','envelope']:exec(compile(ast.Module(body=[node],type_ignores=[]),'paint_helpers','exec'))
ORANGE=(255,83,3);IVORY=(218,226,230);INK=(12,16,20)
layers={n:np.zeros((N,N,4),np.uint8)for n in ['01 Woven carbon 2x2 twill','02 Fluorescent orange race lines','03 Satin protective panels','04 Racing identity 12','05 Technical stencils','06 Panel lines','07 Flush fasteners','08 Restrained local wear']}
base,accents,protection,identity,service,panels,rivets,weather=layers.values()
ax=abs(x);cowl=group(('cowl',));fin=group(('fin_fixed','rudder'));tail=group(('stabilizer','elevator'));skin=covered&~inside
upper=wing&covered&(nz>.45);lower=wing&covered&(nz<-.45)
exec(compile(Path(__file__).with_name('carbon_weave23.py').read_text(), 'carbon_weave23.py', 'exec'))
le,te=envelope(('wing_','flap_','aileron_'),1.25)
# Bridge local gun-port scallops so the race stripe has a smooth painted sweep.
samples=[float(np.median(le[wing&covered&(abs(ax-q)<.003)]))for q in [.58,.79]]
le=np.where((ax>.58)&(ax<.79),np.interp(ax,[.58,.79],samples),le)
chord=(le-y)/np.maximum(le-te,.02)
# Jet Orange design hierarchy: twin longitudinal ribbons, then finer edge accents.
orange=wing*band(.050,.073,chord,.006)
for lo,hi in [(1.04,1.09),(1.108,1.116)]:
 orange=np.maximum(orange,wing*band(lo+.10*chord,hi+.10*chord,ax,.002))
for center in [.505,.556]:
 orange=np.maximum(orange,wing*band(center+.04*chord,center+.024+.04*chord,ax,.002)*band(.12,.94,chord,.01))
for lo,hi in [(.415,.447),(.458,.464)]:orange=np.maximum(orange,tail*band(lo,hi,ax,.002))
orange=np.maximum(orange,fin*ramp(.353,.360,z))
orange=np.maximum(orange,fin*band(.336,.341,z,.001))
orange=np.maximum(orange,cowl*band(.260,.279,y,.0015))
side=(fuselage|(doors&~inside&(ax<.10)))&(ax>.025)
stripe=np.interp(y,[-1.60,-1.25,-.75,-.25,.30],[.025,.035,.025,.045,.065])
ribbon=side*band(-1.53,.20,y,.006)*band(-.009,.009,z-stripe,.0015)
ribbon*=1-band(-.865,-.610,y,.008)
pinstripe=side*band(-1.53,.20,y,.006)*band(-.026,-.023,z-stripe,.001)
pinstripe*=1-band(-.865,-.610,y,.008)
orange=np.maximum(orange,np.maximum(ribbon,pinstripe))
orange=np.maximum(orange,side*band(-1.33,-1.318,y,.0015))
# The two ribbons are separated by exposed carbon on both dorsal and ventral skins.
longitudinal=(fuselage|cowl)*band(-1.24,.29,y,.006)*band(.018,.044,ax,.0018)
longitudinal*=((z>.070)|(z<-.025))
longitudinal*=1-band(-.685,-.325,y,.002)*(z>.070)
orange=np.maximum(orange,longitudinal)
fill(accents,ORANGE,orange);rough=rough*(1-orange)+.24*orange;height*=1-orange
walk=wing&(ax>.19)&(ax<.29)&(y>-.395)&(y<-.145)&(nz>.55)
fill(protection,INK,walk*.94);rough[walk]=.76;height[walk]*=.05
glare=fuselage&(ax<.015)&(z>.12)&(y>-.33)&(y<.10)
fill(protection,(15,20,24),glare*.72);rough[glare]=.48

def side_stamp(dst,bitmap,front,width,top,height,mask=None):
 if mask is None:mask=fuselage&(ax>.03)&(abs(nx)>.40)
 u=np.where(x>0,(y-front+width)/width,(front-y)/width)
 stamp(dst,bitmap,u,(top-z)/height,mask&covered)
def text_bitmap(text,color=IVORY,size=280,outline=False):
 font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',size);b=font.getbbox(text);pad=22
 im=Image.new('RGBA',(b[2]-b[0]+pad*2,b[3]-b[1]+pad*2));d=ImageDraw.Draw(im)
 d.text((pad-b[0],pad-b[1]),text,font=font,fill=(*color,255),stroke_width=4 if outline else 0,stroke_fill=(*ORANGE,255));return np.asarray(im)
side_stamp(identity,text_bitmap('12',IVORY,outline=True),-.625,.208,.099,.130)
side_stamp(identity,text_bitmap('AERO SPORT',ORANGE),-.645,.185,-.048,.022)
side_stamp(identity,text_bitmap('12',ORANGE),-1.225,.160,.308,.118,fin&(ax>.002))
side_stamp(service,text_bitmap('CARBON / 12'),-1.035,.135,.078,.017)
side_stamp(service,text_bitmap('FUEL'),-.185,.055,.112,.012)
side_stamp(service,text_bitmap('EXPOSED CARBON / 2:2'),-.36,.15,-.033,.011)
for sign in [-1,1]:
 u=(sign*x-.195)/.083
 stamp(service,text_bitmap('NO STEP',ORANGE),u if sign>0 else 1-u,(-.23-y)/.018,upper&(sign*x>0))
 for face in [upper,lower]:
  u=(sign*x-.79)/.19
  if sign<0:u=1-u
  if face is lower:u=1-u
  stamp(identity,text_bitmap('12',IVORY,outline=True),u,(-.16-y)/.13,face&(sign*x>0))
# Original enamel-style badge: aviation identity, inspired by the car's small jewelry details.
badge=Image.new('RGBA',(840,250));bd=ImageDraw.Draw(badge)
bd.rounded_rectangle((8,8,831,241),radius=58,fill=(10,14,17,255),outline=(185,195,201,255),width=9)
bd.rounded_rectangle((26,26,813,223),radius=44,outline=(*ORANGE,255),width=4)
bd.text((420,126),'C12  /  AERO SPORT',font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',63),fill=(*IVORY,255),anchor='mm')
side_stamp(identity,np.asarray(badge),-.355,.155,.019,.043)
# Fine service marks stay within existing upper access skins and follow each side's orientation.
for sign in [-1,1]:
 uu=(sign*x-.665)/.13
 if sign<0:uu=1-uu
 stamp(service,text_bitmap('ACCESS  /  CF12',IVORY),uu,(-.225-y)/.012,upper&(sign*x>0))
 uu=(sign*x-.315)/.155
 if sign<0:uu=1-uu
 stamp(service,text_bitmap('AERO SPORT',ORANGE),uu,(-.295-y)/.018,upper&(sign*x>0))
 stamp(service,text_bitmap('CARBON 12',IVORY),1-uu,(-.28-y)/.018,lower&(sign*x>0))
for cy in [-.035,-.30,-1.02]:
 witness=(fuselage&(ax>.035)&(abs(nx)>.50))*band(cy-.001,cy+.001,y,.0006)*band(-.012,.001,z,.001)
 fill(service,ORANGE,witness)

# Reuse only panel, fastener and localized wear layers, at the new atlas resolution.
with zipfile.ZipFile(P/'textures/liveries/chrome/base_g1_15/source.ora')as archive:
 src=ET.fromstring(archive.read('stack.xml')).find('stack').findall('layer')
 for layer in reversed(src):
  name=layer.attrib['name'];a=np.asarray(Image.open(io.BytesIO(archive.read(layer.attrib['src']))).convert('RGBA').resize((N,N),Image.Resampling.BICUBIC)).copy()
  if name.startswith('02 '):panels[:]=a;panels[:,:,:3]=(6,9,13);panels[:,:,3]=(a[:,:,3]*.65).astype(np.uint8)
  if name.startswith('03 '):rivets[:]=a;rivets[:,:,3]=(a[:,:,3]*.55).astype(np.uint8)
  if name.startswith(('04 ','05 ','06 ','07 ')):fill(weather,a[:,:,:3],a[:,:,3].astype(np.float32)/255*(.13 if name.startswith('05 ')else .42))
dirt=np.asarray(Image.open(P/'textures/liveries/chrome/localized_dirt_mask.png').resize((N,N),Image.Resampling.BILINEAR)).astype(np.float32)/255
rough=rough*(1-dirt*.6)+.52*dirt*.6
# Suppress the weave below painted lettering, while keeping restrained existing fasteners.
paint_mask=np.maximum.reduce([orange,identity[:,:,3].astype(np.float32)/255,service[:,:,3].astype(np.float32)/255,protection[:,:,3].astype(np.float32)/255])
aniso_strength*=1-paint_mask
aniso_strength*=1-dirt*.8
aniso_strength[~skin]=0
height*=1-paint_mask
rough=rough*(1-paint_mask)+.24*paint_mask
emission=np.zeros((N,N,3),np.uint8)
emission[:]=(np.array(ORANGE)[None,None,:]*orange[...,None]).astype(np.uint8)
# Tangent-space microrelief uses the atlas's real spatial derivatives.
def derivative(axis):
 p1=np.roll(pos,-1,axis);p0=np.roll(pos,1,axis)
 valid=covered&(np.roll(part,-1,axis)==part)&(np.roll(part,1,axis)==part)
 valid&=(np.linalg.norm(p1-pos,axis=2)<.012)&(np.linalg.norm(p0-pos,axis=2)<.012)
 return (p1-p0)*.5,(np.roll(height,-1,axis)-np.roll(height,1,axis))*.5,valid
pu,hu,vu=derivative(1);pv,hv,vv=derivative(0)
pu-=normal*np.sum(pu*normal,axis=2)[...,None];lu=np.linalg.norm(pu,axis=2);tangent=pu/np.maximum(lu[...,None],1e-8)
vc=np.sum(pv*tangent,axis=2);vp=pv-vc[...,None]*tangent;lv=np.linalg.norm(vp,axis=2)
su=hu/np.maximum(lu,1e-6);sv=(hv-su*vc)/np.maximum(lv,1e-6);ok=vu&vv&(lu>1e-5)&(lv>1e-5)&skin
tn=np.asarray(Image.open(P/'textures/liveries/chrome/normal.png').resize((N,N),Image.Resampling.BILINEAR)).astype(np.float32)/127.5-1
tn[:,:,0]+=np.where(ok,-su,0);tn[:,:,1]+=np.where(ok,sv,0)
tn/=np.maximum(np.linalg.norm(tn,axis=2)[...,None],1e-8)
exec(compile(Path(__file__).with_name('carbon_direction23.py').read_text(), 'carbon_direction23.py', 'exec'))
del pu,hu,pv,hv,tangent,vc,vp,su,sv,lu,lv,paint_mask
colors=np.zeros((N,N,3),np.float32)
for a in layers.values():
 alpha=a[:,:,3].astype(np.float32)/255;colors=colors*(1-alpha[...,None])+a[:,:,:3]*alpha[...,None]
valid=covered.copy()
for _ in range(12):
 acc=np.zeros_like(colors);racc=np.zeros_like(rough);nacc=np.zeros_like(tn);weight=np.zeros_like(rough)
 for dy,dx in [(1,0),(-1,0),(0,1),(0,-1)]:
  m=np.roll(valid,(dy,dx),(0,1));acc+=np.roll(colors,(dy,dx),(0,1))*m[...,None];racc+=np.roll(rough,(dy,dx),(0,1))*m;nacc+=np.roll(tn,(dy,dx),(0,1))*m[...,None];weight+=m
 m=(~valid)&(weight>0);colors[m]=acc[m]/weight[m,None];rough[m]=racc[m]/weight[m];tn[m]=nacc[m]/weight[m,None];valid|=m
tn/=np.maximum(np.linalg.norm(tn,axis=2)[...,None],1e-8)
merged=Image.fromarray(np.clip(colors,0,255).astype(np.uint8)).convert('RGBA');merged.convert('RGB').save(D/'basecolor.png')
orm=np.zeros((N,N,3),np.uint8);orm[:,:,0]=255;orm[:,:,1]=(np.clip(rough,0,1)*255).round().astype(np.uint8)
Image.fromarray(orm).save(D/'orm.png');Image.fromarray(orm[:,:,1]).save(D/'roughness.png');Image.fromarray(emission).save(D/'emission.png')
Image.fromarray(((tn*.5+.5)*255).round().astype(np.uint8)).save(D/'normal.png')
Image.fromarray((dirt*255).round().astype(np.uint8)).save(D/'localized_dirt_mask.png')
Image.fromarray((np.clip(height/.00004,0,1)*65535).round().astype(np.uint16)).save(D/'weave_height_16bit.png')
bleed=np.zeros((N,N,4),np.uint8);bleed[:,:,:3]=np.asarray(merged)[:,:,:3];bleed[:,:,3]=(~covered)*255;layers['09 Atlas padding']=bleed
def ora(path,items,merged,title):
 root=ET.Element('image',w=str(merged.width),h=str(merged.height),name=title);stack=ET.SubElement(root,'stack')
 with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED)as archive:
  archive.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
  for i,(name,img)in reversed(list(enumerate(items))):
   b=io.BytesIO();img.save(b,format='PNG');src=f'data/layer{i}.png';archive.writestr(src,b.getvalue());ET.SubElement(stack,'layer',name=name,src=src,x='0',y='0',opacity='1.0',visibility='visible',**{'composite-op':'svg:src-over'})
  archive.writestr('stack.xml',ET.tostring(root));b=io.BytesIO();merged.save(b,format='PNG');archive.writestr('mergedimage.png',b.getvalue())
items=[]
for i,(name,a)in enumerate(layers.items()):
 im=Image.fromarray(a);im.save(D/f'layer_{i+1}.png');items.append((name,im))
ora(D/'source.ora',items,merged,'Carbon 12 / Aero Sport g1.23')
# Orange wheel webs keep tyre rubber and hardware intact.
G=D/'gear';gb=np.asarray(Image.open(P/'textures/gear/base_layer.png').convert('RGBA')).copy();gf=Image.open(P/'textures/gear/finish_layer.png').convert('RGBA')
yy,xx=np.mgrid[0:2048,0:2048];gv=1-yy/2047;rim=(gv>.52)&(gv<.78);gb[rim,:3]=(24,29,33)
# Radius is encoded in V on the existing revolved rims; open webs sample V=.67.
radius=(gv-.53)/.23
lip=rim&(radius>.91)&(radius<.975);gb[lip,:3]=ORANGE
marker=rim&(radius>.72)&(radius<.91)&(xx/2047>.225)&(xx/2047<.245);gb[marker,:3]=ORANGE
bg=Image.fromarray(gb);gear=Image.alpha_composite(bg,gf);gear.convert('RGB').save(G/'basecolor.png');bg.save(G/'base_layer.png');gf.save(G/'finish_layer.png')
shutil.copy2(P/'textures/gear/orm.png',G/'orm.png');ora(G/'source.ora',[('01 Graphite wheels with orange rim pinstripe',bg),('02 Preserved local finish',gf)],gear,'Carbon 12 wheels')
assert np.array_equal(np.asarray(gear)[~rim,:3],np.asarray(Image.open(P/'textures/gear/basecolor.png'))[~rim])
ph,pw=256,1024;yy,xx=np.mgrid[0:ph,0:pw];rad=xx/(pw-1)*.42
prop=np.empty((ph,pw,3),np.uint8);prop[:]=(22,26,29);prop[rad>.372]=ORANGE;prop[(rad>.357)&(rad<.362)]=IVORY
for r in [.159,.163,.167]:prop[(abs(rad-r)<.0007)&(yy>108)&(yy<148)]=IVORY
Image.fromarray(prop).save(D/'propeller_basecolor.png')
design={'id':'carbon','name':'Carbon 12 / Aero Sport','revision':'g1.23','resolution':[4096,4096],'layers':list(layers),'palette':{'orange':ORANGE,'carbon_dark':INK,'lettering':IVORY},'reference':'Bugatti Chiron Super Sport 300+: jet-black exposed carbon, twin Jet Orange stripes, dark wheels and small enamel badges; adapted to an original Corsair livery','sources':['https://newsroom.bugatti.com/en/press-releases/the-intricate-savoir-faire-in-carbon-fiber-at-bugatti','https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_anisotropy/README.md','https://newsroom.bugatti.com/en/press-releases/first-bugatti-chiron-super-sport-300-ready-for-launch','https://newsroom.bugatti.com/en/press-releases/bugatti-super-sport-legends','https://docs.blender.org/manual/en/latest/render/shader_nodes/shader/principled.html','https://github.com/KhronosGroup/glTF-Blender-IO/blob/main/docs/blender_docs/scene_gltf2.rst'],'interpretation':'Visual carbon composite finish, not a structural conversion. Orange fluorescence approximated in RGB with restrained masked emission; no spectral UV fluorescence simulation. Twill scale chosen for readability at model scale.','source_photo_pixels_used':False,'geometry_and_uv_preserved':True,'weave_pitch_design_m':pitch,'resin_clearcoat':1.0,'coat_roughness':.18,'anisotropy':'directional strength/rotation maps, maximum 0.45','orange_emission_strength':.08,'surface_finish':'Nonmetallic woven carbon under gloss resin, satin protective walkways, local deposits.','roughness_range':[float(rough[covered].min()),float(rough[covered].max())]}
design.update(weave_method='Continuous two-over/two-under floats, four subpixel samples, band-limited filament variation',orientation='Mirrored 45 degree layup; fuselage elliptical surface arc, gull-wing span arc; anisotropy aligned to the actual tow in UV tangent space',coat_normal='Smooth geometric normal independent of fibre normal',original_UVs_preserved=True)
(D/'design.json').write_text(json.dumps(design,ensure_ascii=False,indent=2),encoding='utf8');print('CARBON23_PAINT_DONE',json.dumps(design),flush=True)
