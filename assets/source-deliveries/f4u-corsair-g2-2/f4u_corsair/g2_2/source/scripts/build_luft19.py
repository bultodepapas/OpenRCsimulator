"""Original fictional Luftwaffe captured-Corsair livery, preserving all geometry and UVs."""
from pathlib import Path
import sys,json,math,io,zipfile,ast,shutil,xml.etree.ElementTree as ET
P=Path(__file__).resolve().parents[2]
exec(compile(Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0],'shared_uv_painter','exec'))
lid='scarlet';D=P/'textures/liveries/luftwaffe';D.mkdir(exist_ok=True)
tree=ast.parse(Path(__file__).with_name('build_spectrum12.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name in ['fill','envelope']:exec(compile(ast.Module(body=[node],type_ignores=[]),'paint_helpers','exec'))
GREEN=(49,66,56);VIOLET=(86,89,92);GREY=(179,191,194);IVORY=(232,231,215);YELLOW=(231,177,28);INK=(20,25,25)
layers={n:np.zeros((N,N,4),np.uint8)for n in ['01 Splinter camouflage and pale blue grey','02 Yellow identification and protection','03 Repaint footprints','04 Six Balkenkreuz','05 Beute 10 markings','06 Panel lines','07 Flush rivets','08 Local wear','09 German service stencils']}
base,protect,overpaint,marks,identity,panels,rivets,weather,service=layers.values()
ax=abs(x);cowl=group(('cowl',));fin=group(('fin_fixed','rudder'));tail=group(('stabilizer','elevator'))
upper=wing&covered&(nz>.45);lower=wing&covered&(nz<-.45)
colors=np.zeros((N,N,3),np.float32);colors[:]=GREY
# Upper angular fields follow physical coordinates across separate wing pieces.
surface_top=np.maximum(horizontal*ramp(-.12,.18,nz),(body|cowl)*ramp(.025,.095,z))
uppercolor=np.zeros_like(colors);uppercolor[:]=VIOLET
cut=np.interp(ax,[.15,.45,.62,.95,1.25],[-.18,-.31,-.20,-.33,-.24])
splinter=(y>cut)|((ax>.60)&(ax<.87)&(y<-.30+.15*(ax-.60)))
uppercolor[splinter]=GREEN
bodydark=(body|cowl)&((y>-.04)|((y<-.29)&(y>-.63))|(y<-1.11));uppercolor[bodydark]=GREEN
uppercolor[tail&(y+.66*ax< -1.40)]=GREEN
colors=mix(colors,uppercolor,surface_top)
# Soft irregular mottling on the sides, never tied to atlas seams.
def cloud_field(seed):
 rng=np.random.default_rng(seed);out=np.zeros((512,1600),np.float32)
 for w,h,weight in [(29,10,.62),(67,21,.26),(13,5,.12)]:
  a=(rng.random((h,w))*255).astype(np.uint8)
  out+=np.asarray(Image.fromarray(a).resize((1600,512),Image.Resampling.BICUBIC)).astype(np.float32)/255*weight
 return out
iy=np.clip(((y+1.62)/1.98*1599).astype(int),0,1599);iz=np.clip(((z+.09)/.54*511).astype(int),0,511)
field=np.where(x>0,cloud_field(1919)[iz,iy],cloud_field(1944)[iz,iy])
mottle=ramp(.47,.70,field)*band(-.05,np.where(fin,.42,.14),z,.025)*(body|fin|cowl)*(1-ramp(.65,.95,abs(nz)))
mottle*=1-fin*band(-1.39,-1.19,y,.012)*band(.267,.340,z,.010)
colors=mix(colors,GREEN,mottle*.78)
fade=1.4*np.sin(x*39+y*29)+.8*np.cos(y*71-z*44)
colors=np.clip(colors+fade[...,None],0,255);base[:,:,:3]=colors.astype(np.uint8);base[:,:,3]=covered*255
rough=np.full((N,N),.53,np.float32)+.018*np.sin(x*57+y*43);rough+=group(('aileron_','elevator','rudder'))*.045
walk=wing&(ax>.19)&(ax<.29)&(y>-.395)&(y<-.145)&(nz>.55)
fill(protect,INK,walk*.95);rough[walk]=.79
glare=fuselage&(ax<.045)&(z>.12)&(y>-.33)&(y<.10)
fill(protect,INK,glare*.91);rough[glare]=.66
aft_band_surfaces=fuselage|(doors&~inside&(ax<.10))
yellow=np.maximum(cowl*np.maximum(1-ramp(-.015,.012,z),ramp(.235,.245,y)),aft_band_surfaces*band(-1.225,-1.125,y,.003))
yellow=np.maximum(yellow,group(('rudder',)));yellow=np.maximum(yellow,lower*ramp(1.06,1.075,ax))
fill(protect,YELLOW,yellow);rough[yellow>.5]=.46

def side_stamp(dst,bitmap,front,width,top,height,mask=None):
 if mask is None:mask=fuselage&(ax>.03)&(abs(nx)>.40)
 u=np.where(x>0,(y-front+width)/width,(front-y)/width)
 stamp(dst,bitmap,u,(top-z)/height,mask&covered)

def text_bitmap(text,color=IVORY,size=260,outline=False):
 font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',size);b=font.getbbox(text);pad=24
 im=Image.new('RGBA',(b[2]-b[0]+pad*2,b[3]-b[1]+pad*2));d=ImageDraw.Draw(im)
 d.text((pad-b[0],pad-b[1]),text,font=font,fill=(*color,255),stroke_width=10 if outline else 0,stroke_fill=(*INK,255));return np.asarray(im)

# Original US insignia positions are covered by slightly different repaint panels.
sidepatch=fuselage*(ax>.035)*band(-1.055,-.735,y,.004)*band(-.080,.105,z,.004)
fill(overpaint,(144,158,158),sidepatch*.87)
oldwing=((upper&(x<0))|(lower&(x>0)))*band(.737,1.060,ax,.006)*band(-.39,-.088,y,.006)
patchcolors=np.zeros((N,N,3),np.float32);patchcolors[:]=(87,96,86);patchcolors[lower]=(164,177,180)
fill(overpaint,patchcolors,oldwing*.82)

# Straight-edged Balkenkreuz artwork with white flanks and narrow dark keyline.
def cross_bitmap():
 im=Image.new('RGBA',(900,900));d=ImageDraw.Draw(im)
 def cross(a,b,color):
  d.rectangle((a,12,b,888),fill=(*color,255));d.rectangle((12,a,888,b),fill=(*color,255))
 cross(255,645,INK);cross(274,626,IVORY);cross(347,553,INK)
 return im
cross=cross_bitmap();cross.save(D/'balkenkreuz_art.png')
side_stamp(marks,np.asarray(cross),-.795,.178,.090,.158)
for sign in [-1,1]:
 stamp(marks,np.asarray(cross),(sign*x-.765)/.270,(-.105-y)/.270,upper&(sign*x>0))
 stamp(marks,np.asarray(cross),(sign*x-.765)/.270,(-.105-y)/.270,lower&(sign*x>0))
side_stamp(identity,text_bitmap('10',YELLOW,outline=True),-.55,.140,.095,.116)
side_stamp(identity,text_bitmap('V10',INK),-1.205,.165,.320,.043,fin&(ax>.002))
side_stamp(service,text_bitmap('BEUTE',INK),-.575,.110,-.043,.023)
side_stamp(service,text_bitmap('KRAFTSTOFF',INK),-.185,.140,.113,.022)
side_stamp(service,text_bitmap('V.10',INK),-1.00,.075,.033,.025)
for sign in [-1,1]:
 u=(sign*x-.195)/.083
 stamp(service,text_bitmap('NICHT BETRETEN'),u if sign>0 else 1-u,(-.23-y)/.018,upper&(sign*x>0))
 u=(sign*x-.61)/.055
 stamp(service,text_bitmap('10',IVORY),u if sign>0 else 1-u,(-.21-y)/.026,upper&(sign*x>0))
# Reuse the established surface-aligned rivets and local gun/exhaust deposits.
with zipfile.ZipFile(P/'textures/liveries/chrome/base_g1_15/source.ora')as archive:
 src=ET.fromstring(archive.read('stack.xml')).find('stack').findall('layer')
 for l in reversed(src):
  name=l.attrib['name'];a=np.asarray(Image.open(io.BytesIO(archive.read(l.attrib['src']))).convert('RGBA')).copy()
  if name.startswith('02 '):panels[:]=a;panels[:,:,3]=(panels[:,:,3]*.70).astype(np.uint8)
  if name.startswith('03 '):rivets[:]=a;rivets[:,:,3]=(rivets[:,:,3]*.65).astype(np.uint8)
  if name.startswith(('04 ','05 ','06 ','07 ')):
   fill(weather,a[:,:,:3],a[:,:,3].astype(np.float32)/255*(.4 if name.startswith('05 ')else .82))
dirt=np.asarray(Image.open(D/'localized_dirt_mask.png')).astype(np.float32)/255
rough=rough*(1-dirt*.7)+.69*dirt*.7
colors=np.zeros((N,N,3),np.float32)
for a in layers.values():
 alpha=a[:,:,3].astype(np.float32)/255;colors=colors*(1-alpha[...,None])+a[:,:,:3]*alpha[...,None]
valid=covered.copy()
for _ in range(8):
 acc=np.zeros_like(colors);racc=np.zeros_like(rough);weight=np.zeros_like(rough)
 for dy,dx in [(1,0),(-1,0),(0,1),(0,-1)]:
  m=np.roll(valid,(dy,dx),(0,1));acc+=np.roll(colors,(dy,dx),(0,1))*m[...,None];racc+=np.roll(rough,(dy,dx),(0,1))*m;weight+=m
 m=(~valid)&(weight>0);colors[m]=acc[m]/weight[m,None];rough[m]=racc[m]/weight[m];valid|=m
merged=Image.fromarray(np.clip(colors,0,255).astype(np.uint8)).convert('RGBA');merged.convert('RGB').save(D/'basecolor.png')
orm=np.zeros((N,N,3),np.uint8);orm[:,:,0]=255;orm[:,:,1]=(np.clip(rough,0,1)*255).round().astype(np.uint8)
Image.fromarray(orm).save(D/'orm.png');Image.fromarray(orm[:,:,1]).save(D/'roughness.png')
bleed=np.zeros((N,N,4),np.uint8);bleed[:,:,:3]=np.asarray(merged)[:,:,:3];bleed[:,:,3]=(~covered)*255
layers['10 Atlas padding']=bleed
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
ora(D/'source.ora',items,merged,'Luftwaffe Beute 10 concept g1.19')
# Yellow painted wheel webs, retaining tyres, bolts, dust and metal components.
G=D/'gear';G.mkdir(exist_ok=True)
gb=np.asarray(Image.open(P/'textures/gear/base_layer.png').convert('RGBA')).copy();gf=Image.open(P/'textures/gear/finish_layer.png').convert('RGBA')
yy,xx=np.mgrid[0:N,0:N];v=1-yy/(N-1);rim=(v>.52)&(v<.78);gb[rim,:3]=INK
basegear=Image.fromarray(gb);gear=Image.alpha_composite(basegear,gf);gear.convert('RGB').save(G/'basecolor.png')
basegear.save(G/'base_layer.png');gf.save(G/'finish_layer.png');shutil.copy2(P/'textures/gear/orm.png',G/'orm.png')
ora(G/'source.ora',[('01 Charcoal wheel webs',basegear),('02 Preserved localized finish',gf)],gear,'Beute 10 gear finish')
assert np.array_equal(np.asarray(gear)[~rim,:3],np.asarray(Image.open(P/'textures/gear/basecolor.png'))[~rim])
# Black-green propeller finish on the original blade UVs; spinner is yellow.
ph,pw=256,1024;yy,xx=np.mgrid[0:ph,0:pw];rad=xx/(pw-1)*.42
prop=np.empty((ph,pw,3),np.uint8);prop[:]=(26,34,27)
for r in [.159,.163,.167]:prop[(abs(rad-r)<.0007)&(yy>108)&(yy<148)]=IVORY
Image.fromarray(prop).save(D/'propeller_basecolor.png')
design={'id':'luftwaffe','name':'Beute 10 / Captured Corsair Concept','revision':'g1.19','palette':{'grey_green':GREEN,'grey_violet':VIOLET,'underside':GREY,'identification_yellow':YELLOW},'layers':list(layers),'reference':'WWII German aircraft museum references and IWM captured aircraft catalogue; original adaptation to the Corsair','sources':['https://www.rafmuseum.org.uk/research/collections/focke-wulf-fw190a-8-r6/','https://commons.wikimedia.org/wiki/File:Fw-190_D-13_%22Yellow_10%22.JPG','https://film.iwmcollections.org.uk/record/18815'],'interpretation':'Fictional captured and repainted F4U Corsair. Angular camouflage, mottled sides, six Balkenkreuz and yellow recognition areas. Number 10 and V10 are original artistic identifiers. Not a documented historical Corsair. Colors are artistic approximations, not certified RLM matches.','source_photo_pixels_used':False,'geometry_and_uv_preserved':True,'cross_count':6,'surface_finish':'Nonmetallic satin-matte paint, localized gun and exhaust deposits, preserved flush rivets.','marking_pixels':int(np.sum(marks[:,:,3]>0)),'roughness_range':[float(rough[covered].min()),float(rough[covered].max())]}
(D/'design.json').write_text(json.dumps(design,ensure_ascii=False,indent=2),encoding='utf8');print('LUFT19_PAINT_DONE',json.dumps(design),flush=True)
