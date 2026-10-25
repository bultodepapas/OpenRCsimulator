"""Original Italian desert livery; all graphics mapped in physical surface coordinates."""
from pathlib import Path
import sys,json,math,io,zipfile,ast,shutil,xml.etree.ElementTree as ET
P=Path(__file__).resolve().parents[2]
exec(compile(Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0],'shared_uv_painter','exec'))
lid='scarlet';D=P/'textures/liveries/italy';D.mkdir(exist_ok=True)
tree=ast.parse(Path(__file__).with_name('build_spectrum12.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name in ['fill','envelope']:exec(compile(ast.Module(body=[node],type_ignores=[]),'paint_helpers','exec'))
SAND=(180,136,76);GREEN=(48,64,34);GREY=(173,180,175);IVORY=(230,225,208);INK=(27,30,24);RED=(140,34,27)
layers={n:np.zeros((N,N,4),np.uint8)for n in ['01 Sand olive camouflage and grey underside','02 White recognition and protective paint','03 Local repaint and sun fade','04 Italian period wing emblems and tail crosses','05 Deserto 11 identification','06 Panel lines','07 Flush rivets','08 Local desert weathering','09 Italian service stencils']}
base,protect,overpaint,marks,identity,panels,rivets,weather,service=layers.values()
ax=abs(x);cowl=group(('cowl',));fin=group(('fin_fixed','rudder'));tail=group(('stabilizer','elevator'))
upper=wing&covered&(nz>.45);lower=wing&covered&(nz<-.45)
colors=np.zeros((N,N,3),np.float32);colors[:]=GREY

def noise3(scale,seed,warp=False):
 # Smooth lattice noise is continuous across UV seams and across separate flaps.
 coords=(x,y,z)
 if warp:coords=(x+.027*np.sin(y*39+z*21)+.013*np.sin(z*69+y*17),y+.032*np.sin(x*37+z*22),z+.020*np.sin(x*29-y*31))
 p=[coords[0]*scale+seed*.731,coords[1]*scale+seed*.173,coords[2]*scale+seed*.391]
 a=[np.floor(q).astype(np.float32)for q in p];t=[q-i for q,i in zip(p,a)];t=[q*q*(3-2*q)for q in t]
 out=np.zeros((N,N),np.float32)
 for i in [0,1]:
  for j in [0,1]:
   for k in [0,1]:
    h=np.sin((a[0]+i)*127.1+(a[1]+j)*311.7+(a[2]+k)*74.7)*43758.5453;h=h-np.floor(h)
    out+=h*(t[0]if i else 1-t[0])*(t[1]if j else 1-t[1])*(t[2]if k else 1-t[2])
 return out

field=noise3(22,11,True)*.77+noise3(55,31,True)*.23
mottle=ramp(.54,.635,field)
top=np.maximum(horizontal*ramp(-.08,.16,nz),(body|cowl)*ramp(-.075,-.025,z));top=np.maximum(top,fin)
coat=np.zeros_like(colors);coat[:]=SAND;coat=mix(coat,GREEN,mottle)
sun=np.clip(nz,0,1)*(2.8+noise3(8,7)*2.5)
coat=np.clip(coat+sun[...,None],0,255);colors=mix(colors,coat,top)
base[:,:,:3]=colors.astype(np.uint8);base[:,:,3]=covered*255
rough=np.full((N,N),.58,np.float32)+.025*field;rough+=group(('aileron_','elevator','rudder'))*.035
walk=wing&(ax>.19)&(ax<.29)&(y>-.395)&(y<-.145)&(nz>.55)
fill(protect,(52,54,38),walk*.94);rough[walk]=.81
glare=fuselage&(ax<.045)&(z>.12)&(y>-.33)&(y<.10)
fill(protect,(48,57,33),glare*.90)
aft_band_surfaces=fuselage|(doors&~inside&(ax<.10))
white=aft_band_surfaces*band(-1.225,-1.125,y,.002)
fill(protect,IVORY,white);rough[white>.5]=.49
# Small maintenance repaint panels, not ghost national emblems.
panel=fuselage*band(-.15,-.03,y,.003)*band(-.018,.058,z,.004)*(ax>.07)
fill(overpaint,(181,142,85),panel*.20)
dust=np.clip((1-top)*.45+walk*.35,0,1)*(.25+.75*noise3(37,101))

def side_stamp(dst,bitmap,front,width,top,height,mask=None):
 if mask is None:mask=fuselage&(ax>.03)&(abs(nx)>.40)
 u=np.where(x>0,(y-front+width)/width,(front-y)/width)
 stamp(dst,bitmap,u,(top-z)/height,mask&covered)

def text_bitmap(text,color=IVORY,size=260,outline=False):
 font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',size);b=font.getbbox(text);pad=24
 im=Image.new('RGBA',(b[2]-b[0]+pad*2,b[3]-b[1]+pad*2));d=ImageDraw.Draw(im)
 d.text((pad-b[0],pad-b[1]),text,font=font,fill=(*color,255),stroke_width=6 if outline else 0,stroke_fill=(*IVORY,255));return np.asarray(im)

def wing_emblem(white_disc=False):
 # Original vector interpretation of period Regia Aeronautica aircraft markings.
 im=Image.new('RGBA',(900,900));d=ImageDraw.Draw(im)
 if white_disc:d.ellipse((25,25,875,875),fill=(*IVORY,255))
 d.ellipse((25,25,875,875),outline=(*INK,255),width=30)
 for cx,top,bottom in [(245,290,660),(450,200,700),(655,290,660)]:
  d.rounded_rectangle((cx-22,top,cx+22,bottom),radius=5,fill=(*INK,255))
  d.rectangle((cx-33,top+110,cx+33,top+129),fill=(*INK,255));d.rectangle((cx-33,bottom-70,cx+33,bottom-51),fill=(*INK,255))
  d.polygon([(cx+18,top+20),(cx+73,top+2),(cx+102,top+28),(cx+102,top+84),(cx+72,top+112),(cx+18,top+92)],fill=(*INK,255))
 return im

for lowerdisc in [False,True]:wing_emblem(lowerdisc).save(D/('wing_emblem_lower.png'if lowerdisc else 'wing_emblem_upper.png'))
for sign in [-1,1]:
 u=(sign*x-.765)/.270
 stamp(marks,np.asarray(wing_emblem()),u,(-.105-y)/.270,upper&(sign*x>0))
 stamp(marks,np.asarray(wing_emblem(True)),u,(-.105-y)/.270,lower&(sign*x>0))

def tail_cross():
 im=Image.new('RGBA',(720,900));d=ImageDraw.Draw(im)
 d.rectangle((273,30,447,870),fill=(*IVORY,255));d.rectangle((30,344,690,518),fill=(*IVORY,255))
 # Small Savoy-inspired shield integrated into the white tail cross.
 shield=[(294,360),(426,360),(426,459),(410,489),(360,522),(310,489),(294,459)]
 d.polygon(shield,fill=(*RED,255));d.line(shield+[shield[0]],fill=(*INK,255),width=6)
 d.rectangle((348,368,372,501),fill=(*IVORY,255));d.rectangle((301,410,419,434),fill=(*IVORY,255))
 return im
tc=tail_cross();tc.save(D/'tail_cross_art.png')
side_stamp(marks,np.asarray(tc),-1.225,.165,.370,.280,fin&(ax>.002))
side_stamp(identity,text_bitmap('11',INK,outline=True),-.62,.155,.092,.127)
side_stamp(service,text_bitmap('DESERTO',INK),-.64,.135,-.047,.022)
side_stamp(service,text_bitmap('D.11',INK),-1.00,.075,.033,.025)
side_stamp(service,text_bitmap('BENZINA',INK),-.185,.065,.113,.012)
side_stamp(service,text_bitmap('OLIO',INK),-.08,.033,.025,.010)
for sign in [-1,1]:
 u=(sign*x-.195)/.083
 stamp(service,text_bitmap('NON CALPESTARE'),u if sign>0 else 1-u,(-.23-y)/.018,upper&(sign*x>0))
 u=(sign*x-.61)/.055
 stamp(service,text_bitmap('11',INK),u if sign>0 else 1-u,(-.21-y)/.026,upper&(sign*x>0))
# Reuse the established surface-aligned rivets and local gun/exhaust deposits.
with zipfile.ZipFile(P/'textures/liveries/chrome/base_g1_15/source.ora')as archive:
 src=ET.fromstring(archive.read('stack.xml')).find('stack').findall('layer')
 for l in reversed(src):
  name=l.attrib['name'];a=np.asarray(Image.open(io.BytesIO(archive.read(l.attrib['src']))).convert('RGBA')).copy()
  if name.startswith('02 '):panels[:]=a;panels[:,:,3]=(panels[:,:,3]*.70).astype(np.uint8)
  if name.startswith('03 '):rivets[:]=a;rivets[:,:,3]=(rivets[:,:,3]*.65).astype(np.uint8)
  if name.startswith(('04 ','05 ','06 ','07 ')):
   fill(weather,a[:,:,:3],a[:,:,3].astype(np.float32)/255*(.4 if name.startswith('05 ')else .82))
# Warm dust remains localized on the underside, joints and walkways.
fill(weather,(159,128,82),dust*.25)
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
ora(D/'source.ora',items,merged,'Italian Deserto 11 concept g1.20')
# Yellow painted wheel webs, retaining tyres, bolts, dust and metal components.
G=D/'gear';G.mkdir(exist_ok=True)
gb=np.asarray(Image.open(P/'textures/gear/base_layer.png').convert('RGBA')).copy();gf=Image.open(P/'textures/gear/finish_layer.png').convert('RGBA')
yy,xx=np.mgrid[0:N,0:N];v=1-yy/(N-1);rim=(v>.52)&(v<.78);gb[rim,:3]=(177,184,157)
basegear=Image.fromarray(gb);gear=Image.alpha_composite(basegear,gf);gear.convert('RGB').save(G/'basecolor.png')
basegear.save(G/'base_layer.png');gf.save(G/'finish_layer.png');shutil.copy2(P/'textures/gear/orm.png',G/'orm.png')
ora(G/'source.ora',[('01 Grey green wheel webs',basegear),('02 Preserved localized finish',gf)],gear,'Deserto 11 gear finish')
assert np.array_equal(np.asarray(gear)[~rim,:3],np.asarray(Image.open(P/'textures/gear/basecolor.png'))[~rim])
# Dark propeller with restrained yellow tips and original UV inspection bars.
ph,pw=256,1024;yy,xx=np.mgrid[0:ph,0:pw];rad=xx/(pw-1)*.42
prop=np.empty((ph,pw,3),np.uint8);prop[:]=(29,31,26);prop[rad>.386]=(223,174,45)
for r in [.159,.163,.167]:prop[(abs(rad-r)<.0007)&(yy>108)&(yy<148)]=IVORY
Image.fromarray(prop).save(D/'propeller_basecolor.png')
design={'id':'italy','name':'Deserto 11 / Italian desert concept','revision':'g1.20','palette':{'sand':SAND,'olive_mottles':GREEN,'underside':GREY,'recognition_white':IVORY},'layers':list(layers),'reference':'Macchi C.202 North African sand and green camouflage documented by Smithsonian; original adaptation to F4U','sources':['https://www.smithsonianmag.com/air-space-magazine/in-the-museum-italian-lighting-39663529/','https://airandspace.si.edu/collection-objects/aeronautica-macchi-c202-folgore/nasm_A19600332000'],'interpretation':'Fictional Italian desert F4U Corsair. Original 3D coordinate camouflage, period-inspired four wing fasces emblems, white tail cross with Savoy-inspired shield, white aft recognition band and number 11. Not an actual documented Italian Corsair, unit or certified historic color match.','source_photo_pixels_used':False,'geometry_and_uv_preserved':True,'wing_emblem_count':4,'surface_finish':'Nonmetallic sun-faded satin matte paint, localized dust, gun and exhaust deposits, preserved flush rivets.','marking_pixels':int(np.sum(marks[:,:,3]>0)),'roughness_range':[float(rough[covered].min()),float(rough[covered].max())]}
(D/'design.json').write_text(json.dumps(design,ensure_ascii=False,indent=2),encoding='utf8');print('ITALY20_PAINT_DONE',json.dumps(design),flush=True)
