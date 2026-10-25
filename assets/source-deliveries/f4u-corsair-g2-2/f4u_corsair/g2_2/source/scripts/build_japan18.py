"""Fictional captured Corsair repaint, original graphics on preserved UVs."""
from pathlib import Path
import sys,json,math,io,zipfile,ast,shutil,xml.etree.ElementTree as ET
P=Path(__file__).resolve().parents[2]
exec(compile(Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0],'shared_uv_painter','exec'))
lid='scarlet';D=P/'textures/liveries/japan';D.mkdir(exist_ok=True)
tree=ast.parse(Path(__file__).with_name('build_spectrum12.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name in ['fill','envelope']:exec(compile(ast.Module(body=[node],type_ignores=[]),'paint_helpers','exec'))
GREEN=(36,66,51);GREY=(175,183,168);IVORY=(237,229,200);YELLOW=(237,176,26);RED=(187,27,31);INK=(16,23,27)
layers={n:np.zeros((N,N,4),np.uint8)for n in ['01 Naval green and ash grey','02 Black cowl and yellow identification','03 Field overpaint','04 Six hinomaru','05 Japanese identity','06 Panel lines','07 Flush rivets','08 Local wear','09 Service lettering']}
base,protect,overpaint,marks,identity,panels,rivets,weather,service=layers.values()
ax=abs(x);cowl=group(('cowl',));fin=group(('fin_fixed','rudder'));tail=group(('stabilizer','elevator'))
upper=wing&covered&(nz>.45);lower=wing&covered&(nz<-.45)
colors=np.zeros((N,N,3),np.float32);colors[:]=GREEN
low=body*(1-ramp(-.065,-.035,z));low=np.maximum(low,horizontal*(1-ramp(-.35,.10,nz)));low=np.maximum(low,doors&~inside)
colors=mix(colors,GREY,low)
fade=(1.2*np.sin(x*39+y*29)+.9*np.cos(y*71-z*44)+1.4*np.sin(z*61))
colors=np.clip(colors+fade[...,None]+(2*np.clip(nz,0,1))[...,None],0,255)
base[:,:,:3]=colors.astype(np.uint8);base[:,:,3]=covered*255
rough=np.full((N,N),.48,np.float32)+.018*np.sin(x*57+y*43)
rough+=group(('aileron_','elevator','rudder'))*.055
walk=wing&(ax>.19)&(ax<.29)&(y>-.395)&(y<-.145)&(nz>.55)
fill(protect,INK,walk*.94);rough[walk]=.78
fill(protect,INK,cowl.astype(float));rough[cowl]=.42
glare=fuselage&(ax<.045)&(z>.12)&(y>-.33)&(y<.10)
fill(protect,INK,glare*.96);rough[glare]=.64
le,te=envelope(('wing_','flap_','aileron_'),1.25)
chord=(le-y)/np.maximum(le-te,.015)
yellow=wing*band(.22,.78,ax,.003)*(1-ramp(.105,.12,chord))
fill(protect,YELLOW,yellow);rough[yellow>.5]=.46

def side_stamp(dst,bitmap,front,width,top,height,mask=None):
 if mask is None:mask=fuselage&(ax>.03)&(abs(nx)>.40)
 u=np.where(x>0,(y-front+width)/width,(front-y)/width)
 stamp(dst,bitmap,u,(top-z)/height,mask&covered)

def text_bitmap(text,color=IVORY,size=260):
 font=ImageFont.truetype('C:/Windows/Fonts/YuGothB.ttc',size);b=font.getbbox(text)
 im=Image.new('RGBA',(b[2]-b[0]+18,b[3]-b[1]+18));d=ImageDraw.Draw(im)
 d.text((9-b[0],9-b[1]),text,font=font,fill=(*color,255));return np.asarray(im)

# Subtle rectangular repaint footprints suggest original insignia covered over.
sidepatch=fuselage*(ax>.035)*band(-1.055,-.735,y,.004)*band(-.080,.105,z,.004)
fill(overpaint,(31,59,46),sidepatch*.90)
oldwing=((upper&(x<0))|(lower&(x>0)))*band(.737,1.060,ax,.006)*band(-.39,-.088,y,.006)
patchcolors=np.zeros((N,N,3),np.float32);patchcolors[:]=(30,59,45);patchcolors[lower]=(162,172,157)
fill(overpaint,patchcolors,oldwing*.88)

def roundel(ring):
 im=Image.new('RGBA',(900,900));d=ImageDraw.Draw(im)
 d.ellipse((8,8,892,892),fill=(*(IVORY if ring else RED),255))
 d.ellipse((44,44,856,856)if ring else(8,8,892,892),fill=(*RED,255))
 return im
rt=roundel(True);rb=roundel(False);rt.save(D/'hinomaru_bordered.png');rb.save(D/'hinomaru_plain.png')
side_stamp(marks,np.asarray(rt),-.785,.185,.092,.161)
for sign in [-1,1]:
 stamp(marks,np.asarray(rt),(sign*x-.755)/.280,(-.100-y)/.280,upper&(sign*x>0))
 stamp(marks,np.asarray(rb),(sign*x-.755)/.280,(-.100-y)/.280,lower&(sign*x>0))
side_stamp(identity,text_bitmap('日本'),-.415,.165,.064,.058)
side_stamp(identity,text_bitmap('コ-09',YELLOW),-1.205,.165,.320,.043,fin&(ax>.002))
# Two understated command chevrons on the tail, rather than another insignia.
q=z+.10*(y+1.37)
fill(identity,YELLOW,fin*band(.375,.386,q,.001))
fill(identity,IVORY,fin*band(.394,.400,q,.001))
side_stamp(service,text_bitmap('燃料'),-.225,.075,.113,.025)
for sign in [-1,1]:
 u=(sign*x-.195)/.083
 stamp(service,text_bitmap('足乗禁止'),u if sign>0 else 1-u,(-.23-y)/.022,upper&(sign*x>0))
 u=(sign*x-.61)/.055
 stamp(service,text_bitmap('09',YELLOW),u if sign>0 else 1-u,(-.21-y)/.026,upper&(sign*x>0))
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
ora(D/'source.ora',items,merged,'Japan 09 captured Corsair concept g1.18')
# Yellow painted wheel webs, retaining tyres, bolts, dust and metal components.
G=D/'gear';G.mkdir(exist_ok=True)
gb=np.asarray(Image.open(P/'textures/gear/base_layer.png').convert('RGBA')).copy();gf=Image.open(P/'textures/gear/finish_layer.png').convert('RGBA')
yy,xx=np.mgrid[0:N,0:N];v=1-yy/(N-1);rim=(v>.52)&(v<.78);gb[rim,:3]=GREEN
basegear=Image.fromarray(gb);gear=Image.alpha_composite(basegear,gf);gear.convert('RGB').save(G/'basecolor.png')
basegear.save(G/'base_layer.png');gf.save(G/'finish_layer.png');shutil.copy2(P/'textures/gear/orm.png',G/'orm.png')
ora(G/'source.ora',[('01 Green wheel webs',basegear),('02 Preserved localized finish',gf)],gear,'Japan 09 gear finish')
assert np.array_equal(np.asarray(gear)[~rim,:3],np.asarray(Image.open(P/'textures/gear/basecolor.png'))[~rim])
# Japanese-style brown blades and yellow tips, using the original blade UV set.
ph,pw=256,1024;yy,xx=np.mgrid[0:ph,0:pw];rad=xx/(pw-1)*.42
prop=np.empty((ph,pw,3),np.uint8);prop[:]=(68,44,31);prop[rad>.371]=YELLOW
for r in [.159,.163,.167]:prop[(abs(rad-r)<.0007)&(yy>105)&(yy<151)]=IVORY
Image.fromarray(prop).save(D/'propeller_basecolor.png')
design={'id':'japan','name':'Captured Corsair / Japan 09','revision':'g1.18','palette':{'green':GREEN,'underside':GREY,'red':RED,'yellow':YELLOW,'cowl':INK},'layers':list(layers),'reference':'Smithsonian A6M5 Model 52c color description and A6M5 collection; artistic adaptation to existing Corsair','sources':['https://airandspace.si.edu/collection-objects/model-static-mitsubishi-a6m5-model-52c-zero/nasm_A19981590000','https://airandspace.si.edu/collection-objects/mitsubishi-a6m5-reisen-zero-fighter-model-52-zeke/nasm_A19600335000','https://www.awm.gov.au/collection/C1189243'],'interpretation':'Fictional captured and repainted F4U, not a documented Japanese Corsair. Six hinomaru, yellow leading edges, Japanese identity lettering and fictional code コ-09. Dark green/light grey palette inspired by museum references; placement and finish are original artwork.','source_photo_pixels_used':False,'geometry_and_uv_preserved':True,'surface_finish':'Nonmetallic satin repaint, matte walkways, localized gun/exhaust weather, flush rivets.','hinomaru_count':6,'marking_pixels':int(np.sum(marks[:,:,3]>0)),'roughness_range':[float(rough[covered].min()),float(rough[covered].max())]}
(D/'design.json').write_text(json.dumps(design,ensure_ascii=False,indent=2),encoding='utf8');print('JAPAN18_PAINT_DONE',json.dumps(design),flush=True)

