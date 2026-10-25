"""Chrome material maps on the existing atlas. No geometry or UV changes."""
from pathlib import Path
import sys,json,math,io,zipfile,xml.etree.ElementTree as ET,ast
P=Path(__file__).resolve().parents[2]
exec(compile(Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0],'shared_uv_painter','exec'))
D=P/'textures/liveries/chrome';D.mkdir(parents=True,exist_ok=True)
tree=ast.parse(Path(__file__).with_name('build_spectrum12.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name in {'fill','footprint','envelope'}:exec(compile(ast.Module(body=[node],type_ignores=[]),'shared_helpers','exec'))
layers={n:np.zeros((N,N,4),np.uint8)for n in ['01 Polished chrome','02 Panel edges','03 Flush rivets','04 Gun residue','05 Exhaust heat tint','06 Exhaust soot','07 Local abrasion']}
base,panels,rivets,guns,heat,soot,wear=layers.values()
base[:,:,:3]=(221,224,226);base[:,:,3]=covered*255
rough=np.full((N,N),.075,np.float32);metal=np.ones_like(rough);height=np.zeros_like(rough)
ax=abs(x);ny=normal[:,:,1];cowl=group(('cowl',));tail=group(('stabilizer','elevator'));fin=group(('fin_fixed','rudder'))
fixedwing=group(('wing_left_fixed','wing_right_fixed'));skin=covered&~inside
periodic=lambda v,p:abs((v+p*.5)%p-p*.5)
theta=np.arctan2(z-.015,x);arc=theta*.13
line=np.zeros_like(x);rivet_d=np.full_like(x,10)
def row(distance,along,mask,spacing=.018):
 global rivet_d
 rivet_d=np.minimum(rivet_d,np.where(mask,np.hypot(distance,periodic(along,spacing)),10))
def seam(distance,mask):
 global line
 line=np.maximum(line,(1-ramp(.00025,.0010,abs(distance)))*mask)
for st in [-.045,-.295,-.655,-.775,-1.04,-1.265,-1.435]:
 mask=fuselage&(z<.135)&(ax>.014)
 seam(y-st,mask);row(y-st-.005,arc,mask)
for angle in [-2.55,-.58,.42,2.72]:
 dist=np.angle(np.exp(1j*(theta-angle)))*.13
 row(dist,y+.02,fuselage&(y<.095)&(z<.135))
for st in [.108,.280]:
 seam(y-st,cowl);row(y-st-.004,np.arctan2(z,x)*.15,cowl,.024)
for ang in [-2.6,-1.57,-.52,.52,1.57,2.6]:
 dist=np.angle(np.exp(1j*(np.arctan2(z,x)-ang)))*.15
 row(dist,y,cowl,.024)
le,te=envelope(('wing_','flap_','aileron_'),1.25)
for st in [.555,.80,.95,1.10]:
 mask=wing&(abs(nz)>.45)&(y<le-.025)&(y>te+.025)
 row(ax-st,y,mask,.018)
for chord in [.21,.66]:
 track=le-(le-te)*chord
 row(y-track,ax,wing&(ax>.54)&(ax<1.15)&(abs(nz)>.5))
for xc in [.665,.825]:
 dx=abs(ax-xc);dy=abs(y+.17);mask=fixedwing&(abs(nz)>.55)
 seam(dx-.045,mask&(dy<.055));seam(dy-.055,mask&(dx<.045))
 row(dx-.040,y+.17,mask&(dy<.049),.016)
 row(dy-.050,ax-xc,mask&(dx<.040),.016)
for st in [.15,.29,.42]:row(ax-st,y,tail&(abs(nz)>.5),.017)
row(y+1.34,z,fin,.018)
row(z-.25,y,fin,.018)
fill(panels,(119,125,131),line*.32)
head=(1-ramp(.0006,.0019,rivet_d))*skin
rim=np.exp(-((rivet_d-.00135)/.00036)**2)*skin
fill(rivets,(130,136,141),rim*.30)
fill(rivets,(233,235,237),head*.24)
height+=(-.000105*np.exp(-(rivet_d/.0011)**2)+.000025*np.exp(-((rivet_d-.0015)/.00040)**2))*skin
# Fine panel seams remain pigment-only: undersampled relief would make streaks.
rough+=head*.035+line*.025
# The model's six R8 bores are at the original 3.12/3.42/3.72 m stations.
# Their centers are read from the existing wing surface, not placed by eye.
gunmask=np.zeros_like(x);scuff=np.zeros_like(x);anchors=[]
for gx in [.624,.684,.744]:
 edge_sample=fixedwing&covered&(abs(ax-gx)>.010)&(abs(ax-gx)<.017)
 gy=float(np.percentile(y[edge_sample],99.0))
 nose_sample=edge_sample&(y>gy-.006)
 gz=float(np.median(z[nose_sample]))
 anchors.append({'span_abs':gx,'forward':gy,'height':gz,'design_space_scale':.9})
 # Soot begins at the port and trails aft. The bright rubbed lip stays local.
 aft=gy-y;w=.010+.019*np.clip(aft/.20,0,1)
 residue=np.exp(-((ax-gx)/w)**2)*np.exp(-np.maximum(aft,0)/.082)*band(-.008,.205,aft,.006)
 residue*=fixedwing*band(-.06,.075,z-gz,.01)
 core=np.exp(-((ax-gx)/.012)**2)*np.exp(-((y-(gy-.009))/.025)**2)*fixedwing
 gunmask=np.maximum(gunmask,np.clip(residue*.90+core*.40,0,.98))
 localrad=np.hypot(ax-gx,z-gz)
 lip=np.exp(-((localrad-.010)/.003)**2)*np.exp(-((y-gy)/.010)**2)*fixedwing
 scuff=np.maximum(scuff,lip*.55)
 # Suppress mirror glints inside the existing bore; this is finish only.
 bore=(1-ramp(.007,.0105,localrad))*band(-.004,.070,aft,.004)*fixedwing
 gunmask=np.maximum(gunmask,bore*.995)
grain=np.clip(.80+.12*np.sin(x*2800+y*415)+.08*np.sin(y*1827+x*997),.58,1)
gunmask*=np.where(gunmask>.95,1,grain)
fill(guns,(38,35,31),gunmask)
# Actual exit centers from the derivative's geometry audit. Paint space = world * .9.
meta=json.loads((P/'metadata.json').read_text())
exits={k:np.array(v,dtype=float)*.9 for k,v in meta['landmarks_blender_m']['detail_lenses_and_exhaust_exits'].items() if k.startswith('R43 | Escape unido')}
exhaust=np.zeros_like(x);hot=np.zeros_like(x)
for name,(ex,ey,ez) in exits.items():
 aft=ey-y
 # Arc-distance on the lower fuselage puts the plume around, not through, the skin.
 center_angle=math.atan2(ez-.015,ex)
 angular=np.angle(np.exp(1j*(theta-center_angle)))*.13
 width=.021+.032*np.clip(aft/.29,0,1)
 trail=np.exp(-(angular/width)**2)*np.exp(-np.maximum(aft,0)/.19)*band(-.007,.40,aft,.009)
 mask=(fuselage|cowl)&(z<-.035)
 exhaust=np.maximum(exhaust,trail*mask)
 hot=np.maximum(hot,np.exp(-(angular/.025)**2)*np.exp(-((aft+.004)/.045)**2)*mask)
exhaust*=np.clip(.84+.10*np.sin(theta*145+y*87)+.06*np.sin(y*540+theta*410),.62,1)
fill(heat,(124,92,61),hot*.66)
fill(heat,(84,94,132),hot*(1-ramp(.48,.80,hot))*.48)
fill(soot,(24,22,20),np.minimum(exhaust*1.12,.98))
fill(wear,(239,241,242),scuff*.78)
dirt=np.maximum(gunmask,exhaust*.95)*skin
rough=rough*(1-dirt)+(.63)*dirt
metal=metal*(1-dirt*.93)
rough=rough*(1-hot*.27)+.24*hot*.27
rough=rough*(1-scuff*.6)+.12*scuff*.6
# No global scratched noise: clean chrome keeps a coherent reflection.
height-=dirt*.000005
# Convert shallow relief to tangent-space normals, respecting UV stretch/skew.
def derivative(axis):
 p1=np.roll(pos,-1,axis);p0=np.roll(pos,1,axis)
 valid=covered&(np.roll(part,-1,axis)==part)&(np.roll(part,1,axis)==part)
 valid&=(np.linalg.norm(p1-pos,axis=2)<.012)&(np.linalg.norm(p0-pos,axis=2)<.012)
 dp=(p1-p0)*.5;dh=(np.roll(height,-1,axis)-np.roll(height,1,axis))*.5
 return dp,dh,valid
pu,hu,vu=derivative(1);pv,hv,vv=derivative(0)
pu-=normal*np.sum(pu*normal,axis=2)[...,None]
lu=np.linalg.norm(pu,axis=2);tangent=pu/np.maximum(lu[...,None],1e-8)
vucomponent=np.sum(pv*tangent,axis=2)
vperp=pv-vucomponent[...,None]*tangent
lv=np.linalg.norm(vperp,axis=2)
su=hu/np.maximum(lu,1e-6);sv=(hv-su*vucomponent)/np.maximum(lv,1e-6)
valid=vu&vv&(lu>1e-5)&(lv>1e-5)&skin
tn=np.zeros_like(pos);tn[:,:,2]=1;tn[:,:,0]=np.where(valid,-su,0);tn[:,:,1]=np.where(valid,sv,0)
tn/=np.linalg.norm(tn,axis=2)[...,None]
colors=np.zeros((N,N,3),np.float32)
for arr in layers.values():
 a=arr[:,:,3].astype(np.float32)/255;colors=colors*(1-a[...,None])+arr[:,:,:3]*a[...,None]
Image.fromarray((dirt*255).round().astype(np.uint8)).save(D/'localized_dirt_mask.png')
Image.fromarray((np.clip((height+.00016)/.00032,0,1)*65535).round().astype(np.uint16)).save(D/'relief_height_16bit.png')
valid=covered.copy()
for _ in range(8):
 acc=np.zeros_like(colors);racc=np.zeros_like(rough);macc=np.zeros_like(metal);nacc=np.zeros_like(tn);weight=np.zeros_like(rough)
 for dy,dx in [(1,0),(-1,0),(0,1),(0,-1)]:
  m=np.roll(valid,(dy,dx),(0,1));acc+=np.roll(colors,(dy,dx),(0,1))*m[...,None];racc+=np.roll(rough,(dy,dx),(0,1))*m;macc+=np.roll(metal,(dy,dx),(0,1))*m;nacc+=np.roll(tn,(dy,dx),(0,1))*m[...,None];weight+=m
 m=(~valid)&(weight>0);colors[m]=acc[m]/weight[m,None];rough[m]=racc[m]/weight[m];metal[m]=macc[m]/weight[m];tn[m]=nacc[m]/weight[m,None];valid|=m
tn/=np.maximum(np.linalg.norm(tn,axis=2)[...,None],1e-8)
merged=Image.fromarray(np.clip(colors,0,255).astype(np.uint8)).convert('RGBA');merged.convert('RGB').save(D/'basecolor.png')
orm=np.zeros((N,N,3),np.uint8);orm[:,:,0]=255;orm[:,:,1]=(np.clip(rough,0,1)*255).round().astype(np.uint8);orm[:,:,2]=(np.clip(metal,0,1)*255).round().astype(np.uint8)
Image.fromarray(orm).save(D/'orm.png');Image.fromarray(orm[:,:,1]).save(D/'roughness.png');Image.fromarray(orm[:,:,2]).save(D/'metallic.png')
Image.fromarray(((tn*.5+.5)*255).round().astype(np.uint8)).save(D/'normal.png')
bleed=np.zeros((N,N,4),np.uint8);bleed[:,:,:3]=np.asarray(merged)[:,:,:3];bleed[:,:,3]=(~covered)*255
editable=list(layers.items())+[('08 Atlas padding',bleed)]
root=ET.Element('image',w=str(N),h=str(N),name='Corsair Cromo Espejo g1.15');stack=ET.SubElement(root,'stack')
with zipfile.ZipFile(D/'source.ora','w',zipfile.ZIP_DEFLATED)as archive:
 archive.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
 for i,(name,arr)in reversed(list(enumerate(editable))):
  im=Image.fromarray(arr);im.save(D/f'layer_{i+1}.png');buf=io.BytesIO();im.save(buf,format='PNG');src=f'data/layer{i}.png';archive.writestr(src,buf.getvalue());ET.SubElement(stack,'layer',name=name,src=src,x='0',y='0',opacity='1.0',visibility='visible',**{'composite-op':'svg:src-over'})
 archive.writestr('stack.xml',ET.tostring(root));buf=io.BytesIO();merged.save(buf,format='PNG');archive.writestr('mergedimage.png',buf.getvalue())
stats={'clean_fraction':float(np.mean(dirt[skin]<.02)),'strong_dirt_fraction':float(np.mean(dirt[skin]>.3)),'clean_roughness_median':float(np.median(rough[skin&(dirt<.02)&(hot<.02)])),'clean_metallic_min':float(np.min(metal[skin&(dirt<.001)])),'rivet_pixels':int(np.sum(head>.2))}
(D/'design.json').write_text(json.dumps({'id':'chrome','name':'Cromo espejo','resolution':[N,N],'layers':[n for n,_ in editable],'palette':{'chrome':[221,224,226],'soot':[30,28,26]},'interpretation':'Custom mirror-chrome concept. Local soot follows the existing visual gun ports and measured exhaust exits. Flush rivets use shallow normal relief, not extra mesh. This is a graphic treatment, not a historical restoration.','sources':[],'source_photo_pixels_used':False,'geometry_and_uv_preserved':True,'gun_anchors_design_space':anchors,'exhaust_anchors_design_space':{k:v.tolist()for k,v in exits.items()},'normal_height_range_design_m':[-.00016,.00016],'stats':stats,'propeller':'Polished chrome blades and cone; rubber, glass and engine internals retain their functional material contrast.'},indent=2))
print('CHROME15_PAINT_DONE',json.dumps(stats),anchors,flush=True)
