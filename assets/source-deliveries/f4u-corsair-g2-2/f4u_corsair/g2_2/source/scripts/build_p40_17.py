"""Original sharkmouth livery adapted to the Corsair, using its unchanged UV atlas."""
from pathlib import Path
import sys,json,math,io,zipfile,ast,shutil,xml.etree.ElementTree as ET
P=Path(__file__).resolve().parents[2]
exec(compile(Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0],'shared_uv_painter','exec'))
lid='scarlet';D=P/'textures/liveries/p40';D.mkdir(exist_ok=True)
tree=ast.parse(Path(__file__).with_name('build_spectrum12.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name=='fill':exec(compile(ast.Module(body=[node],type_ignores=[]),'paint_helpers','exec'))
OLIVE=(86,94,68);GREY=(183,191,179);IVORY=(238,231,208);YELLOW=(231,180,35);RED=(205,39,23);INK=(16,23,27);NAVY=(24,38,53)
layers={n:np.zeros((N,N,4),np.uint8)for n in ['01 Olive and neutral grey','02 Protective coating','03 Shark mouth','04 Eyes','05 Numbers and star discs','06 Panel lines','07 Flush rivets','08 Local wear','09 Service lettering']}
base,protect,mouth,eyes,marks,panels,rivets,weather,service=layers.values()
ax=abs(x);cowl=group(('cowl',));fin=group(('fin_fixed','rudder'));tail=group(('stabilizer','elevator'))
upper=wing&covered&(nz>.45);lower=wing&covered&(nz<-.45)
colors=np.zeros((N,N,3),np.float32);colors[:]=OLIVE
low=body*(1-ramp(-.065,-.035,z))
low=np.maximum(low,horizontal*(1-ramp(-.35,.10,nz)))
low=np.maximum(low,doors&~inside)
colors=mix(colors,GREY,low)
fade=(2.1*np.sin(x*39+y*29)+1.4*np.cos(y*71-z*44)+2*np.sin(z*61))
colors=np.clip(colors+fade[...,None]+(2.5*np.clip(nz,0,1))[...,None],0,255)
base[:,:,:3]=colors.astype(np.uint8);base[:,:,3]=covered*255
rough=np.full((N,N),.47,np.float32)+.018*np.sin(x*57+y*43)
rough+=group(('aileron_','elevator','rudder'))*.06
walk=wing&(ax>.19)&(ax<.29)&(y>-.395)&(y<-.145)&(nz>.55)
fill(protect,INK,walk*.94);rough[walk]=.78
glare=fuselage&(ax<.045)&(z>.12)&(y>-.33)&(y<.08)
fill(protect,(48,55,39),glare*.9);rough[glare]=.61

def side_stamp(dst,bitmap,front,width,top,height,mask=None):
 if mask is None:mask=fuselage&(ax>.03)&(abs(nx)>.40)
 u=np.where(x>0,(y-front+width)/width,(front-y)/width)
 stamp(dst,bitmap,u,(top-z)/height,mask&covered)

def text_bitmap(text,color=IVORY,size=260):
 font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',size);b=font.getbbox(text)
 im=Image.new('RGBA',(b[2]-b[0]+18,b[3]-b[1]+18));d=ImageDraw.Draw(im)
 d.text((9-b[0],9-b[1]),text,font=font,fill=(*color,255));return np.asarray(im)

# Teeth and tongue are original artwork. Longitudinal projection mirrors the
# pictorial shape anatomically on the two sides, unlike readable text.
W,H=1800,1000;im=Image.new('RGBA',(W,H));d=ImageDraw.Draw(im)
def top(t):return .19+.10*t*t
def bottom(t):return .91-.62*t*t
ts=np.linspace(.07,.995,200)
outline=[(t*W,top(t)*H)for t in ts]+[(t*W,bottom(t)*H)for t in ts[::-1]]
outline += [((.015+.055*(2*s-1)**2)*W,((1-s)*bottom(.07)+s*top(.07))*H)for s in np.linspace(0,1,80)]
d.polygon(outline,fill=(*INK,255));d.line(outline+[outline[0]],fill=(*IVORY,255),width=25,joint='curve')
# Red lower gum and curled tongue remain visible between pointed teeth.
gum=[(t*W,(bottom(t)-.23*(1-t))*H)for t in ts]+[(t*W,(bottom(t)-.020)*H)for t in ts[::-1]]
d.polygon(gum,fill=(*RED,255))
for i in range(11):
 t=.080+i*.080;step=.065;span=bottom(t)-top(t)
 pts=[(t*W,(top(t)+.015)*H),((t+step)*W,(top(t+step)+.015)*H),((t+step*.75)*W,(top(t)+span*(.43 if i<8 else .37))*H),((t+.020)*W,(top(t)+span*.25)*H)]
 d.polygon(pts,fill=(*IVORY,255))
for i in range(10):
 t=.093+i*.083;step=.063;span=bottom(t)-top(t)
 pts=[(t*W,(bottom(t)-.017)*H),((t+.020)*W,(bottom(t)-span*.18)*H),((t+.040)*W,(bottom(t)-span*.36)*H),((t+step)*W,(bottom(t+step)-.017)*H)]
 d.polygon(pts,fill=(*IVORY,255))
d.line(outline+[outline[0]],fill=(*INK,255),width=8,joint='curve')
im.save(D/'sharkmouth_art.png')
stamp(mouth,np.asarray(im),(.300-y)/.405,(.055-z)/.210,(cowl|fuselage)&(ax>.035)&(abs(nx)>.22)&covered)

# Ivory sclera, dark pupil and sloping eyebrow on both sides of the cowl.
im=Image.new('RGBA',(800,440));d=ImageDraw.Draw(im)
d.ellipse((120,70,685,410),fill=(*INK,255));d.ellipse((151,90,653,379),fill=(*IVORY,255))
d.ellipse((207,108,419,353),fill=(*INK,255));d.ellipse((245,139,288,198),fill=(250,248,226,255))
d.polygon([(82,40),(720,210),(650,269),(130,161)],fill=(*OLIVE,255))
d.line([(99,94),(682,235)],fill=(*INK,255),width=40)
im.save(D/'eye_art.png')
stamp(eyes,np.asarray(im),(.258-y)/.108,(.113-z)/.065,(cowl|fuselage)&(ax>.04)&(abs(nx)>.35)&covered)

# Plain star discs evoke the period without importing another livery's bars.
im=Image.new('RGBA',(800,800));d=ImageDraw.Draw(im);d.ellipse((10,10,790,790),fill=(*NAVY,255))
pts=[]
for i in range(10):
 a=-math.pi/2+i*math.pi/5;r=345 if i%2==0 else 132
 pts.append((400+r*math.cos(a),400+r*math.sin(a)))
d.polygon(pts,fill=(*IVORY,255));star=np.asarray(im);im.save(D/'star_disc.png')
side_stamp(marks,star,-.91,.175,.091,.152)
stamp(marks,star,(x+1.04)/.27,(-.105-y)/.27,upper&(x<0))
stamp(marks,star,1-(x-.77)/.27,(-.105-y)/.27,lower&(x>0))
side_stamp(marks,text_bitmap('40'),-.64,.202,.095,.147)
side_stamp(marks,text_bitmap('36274',YELLOW),-1.238,.180,.329,.039,fin&(ax>.002))
fill(marks,YELLOW,fin*band(.415,.435,z,.002))
side_stamp(service,text_bitmap('FUEL',IVORY),-.245,.075,.121,.022)
side_stamp(service,text_bitmap('SHARK',YELLOW),-1.15,.12,.038,.021)
for sign in [-1,1]:
 u=(sign*x-.184)/.110
 stamp(service,text_bitmap('NO STEP',IVORY),u if sign>0 else 1-u,(-.23-y)/.023,upper&(sign*x>0))
 for i,xc in enumerate([.665,.825],1):
  u=(sign*x-(xc-.020))/.04
  stamp(service,text_bitmap(str(i).zfill(2),YELLOW),u if sign>0 else 1-u,(-.214-y)/.024,upper&(sign*x>0))

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
ora(D/'source.ora',items,merged,'P-40 inspired Shark Corsair g1.17')
# Yellow painted wheel webs, retaining tyres, bolts, dust and metal components.
G=D/'gear';G.mkdir(exist_ok=True)
gb=np.asarray(Image.open(P/'textures/gear/base_layer.png').convert('RGBA')).copy();gf=Image.open(P/'textures/gear/finish_layer.png').convert('RGBA')
yy,xx=np.mgrid[0:N,0:N];v=1-yy/(N-1);rim=(v>.52)&(v<.78);gb[rim,:3]=YELLOW
basegear=Image.fromarray(gb);gear=Image.alpha_composite(basegear,gf);gear.convert('RGB').save(G/'basecolor.png')
basegear.save(G/'base_layer.png');gf.save(G/'finish_layer.png');shutil.copy2(P/'textures/gear/orm.png',G/'orm.png')
ora(G/'source.ora',[('01 Yellow wheel webs',basegear),('02 Preserved localized finish',gf)],gear,'P40 inspired gear finish')
assert np.array_equal(np.asarray(gear)[~rim,:3],np.asarray(Image.open(P/'textures/gear/basecolor.png'))[~rim])
design={'id':'p40','name':'Sharkmouth P-40 Inspired Corsair','revision':'g1.17','palette':{'olive':OLIVE,'underside':GREY,'teeth':IVORY,'mouth_red':RED,'yellow':YELLOW},'layers':list(layers),'reference':'User-supplied photo codex-clipboard-36496db4-a84c-4fbd-b321-9192e67e5f2c.png','interpretation':'P-40-inspired original livery adapted to the existing F4U Corsair. Sharkmouth and eyes, olive/grey finish, plain star discs, yellow wheel webs and tips. Number 40 is an artistic identifier; tail 36274 follows the photo. Not a historical Corsair restoration.','source_photo_pixels_used':False,'geometry_and_uv_preserved':True,'surface_finish':'Nonmetallic satin paint; localized matte soot and retained flush rivet normal map.','mouth_coverage_pixels':int(np.sum(mouth[:,:,3]>0)),'eye_coverage_pixels':int(np.sum(eyes[:,:,3]>0)),'roughness_range':[float(rough[covered].min()),float(rough[covered].max())]}
(D/'design.json').write_text(json.dumps(design,indent=2));print('P40_17_PAINT_DONE',json.dumps(design),flush=True)
