"""Portable export of the currently open packed g2.2 source. No authoring baseline needed."""
import bpy,json,struct,sys
from pathlib import Path
def export(path):
 S=bpy.context.scene;S.frame_set(100);bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
 for o in bpy.data.collections['EXPORT_aircraft'].objects:o.hide_set(False);o.hide_render=False;o.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_extras=True,export_cameras=False,export_lights=False,export_animations=False,export_materials='EXPORT',export_image_format='AUTO',export_texcoords=True,export_normals=True,export_tangents=True,export_current_frame=True,export_draco_mesh_compression_enable=False)
 S.frame_set(0)
 raw=Path(path).read_bytes();n=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+n]);unique=[];seen={};mapping={}
 for i,t in enumerate(g.get('textures',[])):
  key=json.dumps(t,sort_keys=True,separators=(',',':'))
  if key not in seen:seen[key]=len(unique);unique.append(t)
  mapping[i]=seen[key]
 def remap(v):
  if isinstance(v,dict):
   for k,x in v.items():
    if k.endswith('Texture')and isinstance(x,dict)and 'index'in x:x['index']=mapping[x['index']]
    remap(x)
  elif isinstance(v,list):
   for x in v:remap(x)
 remap(g.get('materials',[]));g['textures']=unique
 js=json.dumps(g,separators=(',',':'),ensure_ascii=False).encode();js+=b' '*((-len(js))%4);tail=raw[20+n:]
 out=struct.pack('<4sII',b'glTF',2,20+len(js)+len(tail))+struct.pack('<I4s',len(js),b'JSON')+js+tail;Path(path).write_bytes(out)
 return g
if __name__=='__main__':
 P=Path(__file__).resolve().parents[2];lid=bpy.context.scene.get('livery_id','midnight');name='aircraft'if lid=='midnight'else 'aircraft_'+lid
 export(P/'export'/(name+'.glb'))
