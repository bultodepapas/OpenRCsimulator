"""Number 07 and original graphic decals over the preserved mirror-chrome maps."""
from pathlib import Path
import sys,json,math,io,zipfile,xml.etree.ElementTree as ET,ast
P=Path(__file__).resolve().parents[2]
exec(compile(Path(__file__).with_name('build_paints.py').read_text().split('settings=[')[0],'shared_uv_painter','exec'))
lid='scarlet';D=P/'textures/liveries/chrome';I=D/'base_g1_15'
tree=ast.parse(Path(__file__).with_name('build_spectrum12.py').read_text())
for node in tree.body:
 if isinstance(node,ast.FunctionDef)and node.name in {'fill','footprint'}:exec(compile(ast.Module(body=[node],type_ignores=[]),'paint_helpers','exec'))
BLACK=(17,23,29);RED=(202,37,34);WHITE=(240,238,227);GOLD=(228,185,62)
layers={}
with zipfile.ZipFile(I/'source.ora')as arc:
 for layer in reversed(ET.fromstring(arc.read('stack.xml')).find('stack').findall('layer')):
  if 'padding'not in layer.attrib['name'].lower():layers[layer.attrib['name']]=np.asarray(Image.open(io.BytesIO(arc.read(layer.attrib['src']))).convert('RGBA')).copy()
for name in ['08 Race numbers','09 Winged emblems','10 Service decals','11 Red pinstripes']:layers[name]=np.zeros((N,N,4),np.uint8)
numbers,badges,service,trim=[layers[k]for k in list(layers)[-4:]]
ax=abs(x);cowl=group(('cowl',));fin=group(('fin_fixed','rudder'));tail=group(('stabilizer','elevator'))
side=fuselage&covered&(abs(nx)>.40)&(ax>.03)
upper=wing&covered&(nz>.45);lower=wing&covered&(nz<-.45)
def text_bitmap(text,color=BLACK,size=280,outline=False,font='arialbd.ttf'):
 f=ImageFont.truetype('C:/Windows/Fonts/'+font,size);box=f.getbbox(text);pad=28 if outline else 8
 im=Image.new('RGBA',(box[2]-box[0]+pad*2,box[3]-box[1]+pad*2));dr=ImageDraw.Draw(im)
 if outline:
  dr.text((pad-box[0]+7,pad-box[1]+5),text,font=f,fill=(*RED,255),stroke_width=18,stroke_fill=(*RED,255))
  dr.text((pad-box[0],pad-box[1]),text,font=f,fill=(*color,255),stroke_width=11,stroke_fill=(*WHITE,255))
 else:dr.text((pad-box[0],pad-box[1]),text,font=f,fill=(*color,255))
 return np.asarray(im)
def side_stamp(dst,bitmap,front,width,top,height,mask=side):
 # Choose the physical side: some legacy atlas normals are inverted.
 u=np.where(x>0,(y-front+width)/width,(front-y)/width)
 stamp(dst,bitmap,u,(top-z)/height,mask&covered)
def label_bitmap(text,color=BLACK,bg=WHITE,accent=RED):
 f=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',110);box=f.getbbox(text)
 im=Image.new('RGBA',(box[2]+70,box[3]-box[1]+65),(*bg,255));dr=ImageDraw.Draw(im)
 dr.rounded_rectangle((3,3,im.width-4,im.height-4),radius=12,outline=(*color,255),width=6)
 dr.rectangle((3,im.height-17,im.width-4,im.height-5),fill=(*accent,255))
 dr.text((35,24-box[1]),text,font=f,fill=(*color,255));return np.asarray(im)
num=text_bitmap('07',outline=True,font='arialbd.ttf')
side_stamp(numbers,num,-.65,.30,.102,.167)
stamp(numbers,num,(x-.805)/.285,(-.118-y)/.162,upper&(x>0))
stamp(numbers,num,(-x-.805)/.285,(-.118-y)/.162,lower&(x<0))
# An original winged roundel, drawn as flat graphic artwork.
im=Image.new('RGBA',(1000,560));dr=ImageDraw.Draw(im)
for s in [-1,1]:
 for i in range(4):
  xa=500+s*120;xb=500+s*(475-i*70);yc=135+i*62
  dr.polygon([(xa,yc),(xb,yc-25),(xb-s*38,yc+15),(xa,yc+35)],fill=(*BLACK,255))
dr.ellipse((310,55,690,435),fill=(*WHITE,255),outline=(*RED,255),width=24)
f=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',215);b=f.getbbox('07');dr.text(((1000-(b[2]-b[0]))/2-b[0],220-(b[1]+b[3])/2),'07',font=f,fill=(*BLACK,255))
dr.rounded_rectangle((228,405,772,535),radius=18,fill=(*BLACK,255))
f=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',90);dr.text((500,470),'CORSAIR',anchor='mm',font=f,fill=(*WHITE,255))
emblem=np.asarray(im);Image.fromarray(emblem).save(D/'winged_emblem.png')
stamp(badges,emblem,1-(-x-.78)/.31,(-.115-y)/.174,upper&(x<0))
stamp(badges,emblem,1-(x-.78)/.31,(-.115-y)/.174,lower&(x>0))
# Tail roundel and compact cowl decal fit completely on their own metal panels.
im=Image.new('RGBA',(512,512));dr=ImageDraw.Draw(im)
dr.ellipse((14,14,498,498),fill=(*WHITE,255),outline=(*RED,255),width=24)
dr.ellipse((48,48,464,464),outline=(*BLACK,255),width=8)
f=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',265);dr.text((256,240),'07',font=f,anchor='mm',fill=(*BLACK,255))
f=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',42);dr.text((256,395),'CHROME',font=f,anchor='mm',fill=(*RED,255))
side_stamp(badges,np.asarray(im),-1.236,.153,.382,.153,fin&(abs(nx)>.30))
side_stamp(badges,label_bitmap('CORSAIR'),.258,.116,.048,.047,cowl&(abs(nx)>.55))
side_stamp(badges,text_bitmap('CHROME',font='arialbi.ttf'),.030,.260,.092,.045)
side_stamp(badges,text_bitmap('EDITION 07',color=RED),-.016,.181,.037,.019)
side_stamp(service,text_bitmap('C-07'),-1.065,.175,.050,.040)
# Restrained accent lines leave most of each panel as exposed mirror metal.
zline=np.interp(y,[-1.47,-1.15,-.98],[.035,.005,-.018])
line_mask=side*band(-1.47,-.98,y,.004)*band(-.003,.003,z-zline,.0015)
fill(trim,RED,line_mask)
fill(trim,BLACK,side*band(-1.40,-1.005,y,.004)*band(.007,.009,z-zline,.001))
fill(trim,RED,fin*band(.423,.435,z,.0015))
fill(trim,BLACK,fin*band(.412,.416,z,.0012))
# Service stickers are aesthetic markings, not operating instructions.
side_stamp(service,label_bitmap('FUEL',bg=GOLD,accent=BLACK),-.245,.075,.129,.027)
side_stamp(service,label_bitmap('ACCESS'),-.464,.103,-.010,.029)
side_stamp(service,label_bitmap('PROP',bg=RED,color=WHITE,accent=BLACK),.063,.081,-.027,.026)
for sign in [-1,1]:
 u=(sign*x-.187)/.107
 stamp(service,label_bitmap('NO STEP'),u if sign>0 else 1-u,(-.231-y)/.036,upper&(sign*x>0))
 for i,xc in enumerate([.665,.825],1):
  u=(sign*x-(xc-.020))/.040
  stamp(service,label_bitmap(str(i).zfill(2)),u if sign>0 else 1-u,(-.212-y)/.026,upper&(sign*x>0))
 # Small lifting-point triangles on both aft wing panels.
 im=Image.new('RGBA',(256,256));dr=ImageDraw.Draw(im)
 dr.polygon([(128,10),(245,232),(11,232)],fill=(*GOLD,255),outline=(*BLACK,255),width=15)
 dr.line((128,175,128,64),fill=(*BLACK,255),width=15);dr.polygon([(128,47),(94,98),(162,98)],fill=(*BLACK,255))
 stamp(service,np.asarray(im),(sign*x-.94)/.055,(-.300-y)/.055,(upper|lower)&(sign*x>0))
decal=np.zeros((N,N),np.float32)
for arr in [numbers,badges,service,trim]:
 a=arr[:,:,3].astype(np.float32)/255;decal=1-(1-decal)*(1-a)
colors=np.zeros((N,N,3),np.float32)
for arr in layers.values():
 a=arr[:,:,3].astype(np.float32)/255;colors=colors*(1-a[...,None])+arr[:,:,:3]*a[...,None]
orm=np.asarray(Image.open(I/'orm.png')).copy();rough=orm[:,:,1].astype(np.float32)/255;metal=orm[:,:,2].astype(np.float32)/255
rough=rough*(1-decal)+.31*decal;metal=metal*(1-decal)
valid=covered.copy()
for _ in range(8):
 acc=np.zeros_like(colors);racc=np.zeros_like(rough);macc=np.zeros_like(metal);weight=np.zeros_like(rough)
 for dy,dx in [(1,0),(-1,0),(0,1),(0,-1)]:
  m=np.roll(valid,(dy,dx),(0,1));acc+=np.roll(colors,(dy,dx),(0,1))*m[...,None];racc+=np.roll(rough,(dy,dx),(0,1))*m;macc+=np.roll(metal,(dy,dx),(0,1))*m;weight+=m
 m=(~valid)&(weight>0);colors[m]=acc[m]/weight[m,None];rough[m]=racc[m]/weight[m];metal[m]=macc[m]/weight[m];valid|=m
merged=Image.fromarray(np.clip(colors,0,255).astype(np.uint8)).convert('RGBA');merged.convert('RGB').save(D/'basecolor.png')
orm[:,:,1]=(np.clip(rough,0,1)*255).round().astype(np.uint8);orm[:,:,2]=(np.clip(metal,0,1)*255).round().astype(np.uint8)
Image.fromarray(orm).save(D/'orm.png');Image.fromarray(orm[:,:,1]).save(D/'roughness.png');Image.fromarray(orm[:,:,2]).save(D/'metallic.png')
Image.fromarray((decal*255).round().astype(np.uint8)).save(D/'decal_mask.png')
bleed=np.zeros((N,N,4),np.uint8);bleed[:,:,:3]=np.asarray(merged)[:,:,:3];bleed[:,:,3]=(~covered)*255
editable=list(layers.items())+[('12 Atlas padding',bleed)]
root=ET.Element('image',w=str(N),h=str(N),name='Corsair Chrome 07 g1.16');stack=ET.SubElement(root,'stack')
with zipfile.ZipFile(D/'source.ora','w',zipfile.ZIP_DEFLATED)as archive:
 archive.writestr('mimetype','image/openraster',compress_type=zipfile.ZIP_STORED)
 for i,(name,arr)in reversed(list(enumerate(editable))):
  im=Image.fromarray(arr);im.save(D/f'layer_{i+1}.png');buf=io.BytesIO();im.save(buf,format='PNG');src=f'data/layer{i}.png';archive.writestr(src,buf.getvalue());ET.SubElement(stack,'layer',name=name,src=src,x='0',y='0',opacity='1.0',visibility='visible',**{'composite-op':'svg:src-over'})
 archive.writestr('stack.xml',ET.tostring(root));buf=io.BytesIO();merged.save(buf,format='PNG');archive.writestr('mergedimage.png',buf.getvalue())
old=np.asarray(Image.open(I/'basecolor.png'));new=np.asarray(merged.convert('RGB'));untouched=covered&(decal==0)
original_orm=np.asarray(Image.open(I/'orm.png'))
checks={'covered_decal_fraction':float(np.mean(decal[covered]>.02)),'unchanged_basecolor_outside_decals':bool(np.array_equal(old[untouched],new[untouched])),'unchanged_orm_outside_decals':bool(np.array_equal(original_orm[untouched],orm[untouched])),'fully_opaque_sticker_pixels':int(np.sum(decal>.995)),'sticker_roughness_median':float(np.median(rough[decal>.995])),'sticker_metallic_max':float(np.max(metal[decal>.995]))}
assert checks['unchanged_basecolor_outside_decals']and checks['unchanged_orm_outside_decals'],checks
design=json.loads((I/'design.json').read_text());design.update({'name':'Chrome 07','revision':'g1.16','layers':[n for n,_ in editable],'race_number':'07','decals':['Outlined 07 numbers on both fuselage sides and opposite upper/lower wings','Original winged Corsair emblem','Round tail badge and cowl label','CHROME EDITION 07 wordmark','FUEL, ACCESS, PROP, NO STEP and numbered access labels','Fine red and black tail accents'],'decals_are_original_artwork':True,'decal_checks':checks,'palette':{'chrome':[221,224,226],'black':BLACK,'red':RED,'ivory':WHITE,'service_yellow':GOLD}})
(D/'design.json').write_text(json.dumps(design,indent=2))
print('CHROME16_DECALS_DONE',json.dumps(checks),flush=True)
