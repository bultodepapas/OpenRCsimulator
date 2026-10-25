"""Convert regenerated authoring maps to g2.1-compatible runtime PBR maps.
Run after the livery painters. Uses Pillow/numpy; never changes UVs or meshes.
"""
from pathlib import Path
import json,shutil,sys,zipfile,io,xml.etree.ElementTree as ET
import numpy as np
from PIL import Image
P=Path(__file__).resolve().parents[2]
PALETTES={'scarlet':(210,215,200),'three_tone':(155,170,142),'splash':(210,217,207),'spectrum':(217,221,210),'blueangels':(192,202,183),'thunderbirds':(215,219,211),'chrome':(145,154,157),'p40':(149,163,114),'japan':(130,153,124),'luftwaffe':(143,155,133),'italy':(174,182,149),'carbon':(39,47,51)}
def png_array(a,path):Image.fromarray(np.clip(a,0,255).round().astype(np.uint8)).save(path)
def scaled_normal(path,size,strength):
 a=np.asarray(Image.open(path).convert('RGB').resize(size,Image.Resampling.BILINEAR),dtype=np.float32)/127.5-1
 a[...,:2]*=strength;a[...,2]=1+(a[...,2]-1)*strength
 a/=np.maximum(np.linalg.norm(a,axis=2,keepdims=True),1e-8);return a
def build(lid):
 D=P/'textures/liveries'/lid;T=D/'runtime';T.mkdir(exist_ok=True)
 size=(2048,2048)
 # Naval 308 is kept pixel-for-pixel as accepted.
 if lid=='midnight':
  for name in ['basecolor','orm']:shutil.copy2(D/(name+'.png'),T/(name+'.png'))
  shutil.copy2(P/'textures/shared/normal.png',T/'normal.png')
  return {'id':lid,'accepted_maps_unchanged':True,'normal_strength':.65,'runtime_resolution':size}
 author=Image.open(D/'basecolor.png').convert('RGB');N=author.width
 raster=np.load(P/'source/scripts'/f'paint-raster-{N}.npz');inner=raster['inside'];part=raster['part'];mask=inner&(part>=0)
 rgb=np.asarray(author).copy();pos=raster['pos'];color=np.array(PALETTES[lid],np.float32)
 variation=1+.012*np.sin(pos[...,1]*170)*np.sin(pos[...,0]*91)
 coat=np.clip(color*variation[...,None],0,255).astype(np.uint8);rgb[mask]=coat[mask]
 merged=Image.fromarray(rgb)
 # Add the new compartment finish as a removable top layer in the editable source.
 ora=D/'source.ora'
 with zipfile.ZipFile(ora)as z:entries={i.filename:z.read(i.filename)for i in z.infolist()}
 root=ET.fromstring(entries['stack.xml']);stack=root.find('stack')
 layer=np.zeros((N,N,4),np.uint8);layer[mask,:3]=rgb[mask];layer[mask,3]=255
 b=io.BytesIO();Image.fromarray(layer).save(b,format='PNG');entries['data/g22_compartments.png']=b.getvalue()
 for old in list(stack):
  if old.get('src')=='data/g22_compartments.png':stack.remove(old)
 stack.insert(0,ET.Element('layer',name='g2.2 Interior compartment coating',src='data/g22_compartments.png',x='0',y='0',opacity='1.0',visibility='visible',**{'composite-op':'svg:src-over'}))
 root.set('name','F4U g2.2 / '+lid);entries['stack.xml']=ET.tostring(root)
 b=io.BytesIO();merged.convert('RGBA').save(b,format='PNG');entries['mergedimage.png']=b.getvalue()
 with zipfile.ZipFile(ora.with_suffix('.tmp'),'w',zipfile.ZIP_DEFLATED)as z:
  for name,data in entries.items():z.writestr(name,data,compress_type=zipfile.ZIP_STORED if name=='mimetype' else zipfile.ZIP_DEFLATED)
 ora.with_suffix('.tmp').replace(ora);merged.save(D/'basecolor.png')
 merged.resize(size,Image.Resampling.LANCZOS).save(T/'basecolor.png')
 author_orm=np.asarray(Image.open(D/'orm.png').convert('RGB')).copy();author_orm[mask,1]=int(.48*255);author_orm[mask,2]=int((.4 if lid=='chrome'else .07)*255)
 orm=np.asarray(Image.fromarray(author_orm).resize(size,Image.Resampling.BILINEAR)).copy()
 base_orm=np.asarray(Image.open(P/'textures/liveries/midnight/orm.png').convert('RGB'))
 orm[:,:,0]=base_orm[:,:,0];png_array(orm,T/'orm.png')
 # Blend detail normals in tangent space (whiteout). G2's broad surface bake is retained.
 if (D/'normal.png').exists():
  a=scaled_normal(P/'textures/shared/normal.png',size,.65);b=scaled_normal(D/'normal.png',size,.5 if lid=='carbon'else .35)
  n=np.dstack((a[...,:2]+b[...,:2],a[...,2]*b[...,2]));n/=np.maximum(np.linalg.norm(n,axis=2,keepdims=True),1e-8)
  png_array((n*.5+.5)*255,T/'normal.png');strength=1.0
 else:shutil.copy2(P/'textures/shared/normal.png',T/'normal.png');strength=.65
 for f in ['emission.png','anisotropy_strength.png']:
  if (D/f).exists():Image.open(D/f).resize(size,Image.Resampling.LANCZOS).save(T/f)
 if (D/'anisotropy_rotation.png').exists():
  raw_angle=np.asarray(Image.open(D/'anisotropy_rotation.png'));den=65535 if raw_angle.dtype.itemsize>1 else 255
  angle=raw_angle.astype(np.float32)/den*4*np.pi
  c=np.asarray(Image.fromarray(np.cos(angle)).resize(size,Image.Resampling.BILINEAR));s=np.asarray(Image.fromarray(np.sin(angle)).resize(size,Image.Resampling.BILINEAR))
  png_array(np.remainder(np.arctan2(s,c)/(4*np.pi),.5)*255,T/'anisotropy_rotation.png')
 prop=D/'propeller_basecolor.png'
 if not prop.exists():
  legacy=P.parent/'g1_24/textures/liveries'/lid/'propeller_basecolor.png'
  shutil.copy2(legacy if legacy.exists()else P/'textures/shared/propeller_basecolor.png',prop)
 row={'id':lid,'authoring_resolution':[N,N],'runtime_resolution':size,'normal_strength':strength,'inner_painted_pixels':int(mask.sum()),'interior_srgb':PALETTES[lid],'shared_AO_exact':bool(np.array_equal(orm[:,:,0],base_orm[:,:,0]))}
 (D/'adaptation.json').write_text(json.dumps(row,indent=2));return row
if __name__=='__main__':
 ids=sys.argv[1:]or [x['id']for x in json.loads((P/'liveries.json').read_text())]
 rows=[build(lid)for lid in ids];(P/'checks/runtime_maps.json').write_text(json.dumps(rows,indent=2));print('RUNTIME_MAPS',len(rows),flush=True)
