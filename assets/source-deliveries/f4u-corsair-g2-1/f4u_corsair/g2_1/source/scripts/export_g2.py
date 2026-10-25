"""Standalone re-export. Open source/aircraft_game.blend and run this script."""
import bpy,json,struct
from pathlib import Path
P=Path(__file__).resolve().parents[2];S=bpy.context.scene
assert bpy.app.version[:3]==(5,2,2)
S.frame_set(100);bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.collections['EXPORT_aircraft'].objects:o.hide_set(False);o.hide_render=False;o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(P/'export/aircraft.glb'),export_format='GLB',use_selection=True,export_yup=True,export_extras=True,export_cameras=False,export_lights=False,export_animations=False,export_materials='EXPORT',export_image_format='AUTO',export_texcoords=True,export_normals=True,export_tangents=True,export_current_frame=True,export_draco_mesh_compression_enable=False)
S.frame_set(0)
# Blender can emit duplicate texture descriptors for one shared image/sampler.
# Canonicalize descriptors only; all pixel data, geometry and scene nodes stay exact.
path=P/'export/aircraft.glb';raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0]
g=json.loads(raw[20:20+n]);unique=[];seen={};mapping={}
for i,t in enumerate(g.get('textures',[])):
 key=json.dumps(t,sort_keys=True,separators=(',',':'))
 if key not in seen:seen[key]=len(unique);unique.append(t)
 mapping[i]=seen[key]
def remap(value):
 if isinstance(value,dict):
  for k,v in value.items():
   if k.endswith('Texture') and isinstance(v,dict) and 'index'in v:v['index']=mapping[v['index']]
   remap(v)
 elif isinstance(value,list):
  for v in value:remap(v)
remap(g.get('materials',[]));g['textures']=unique
js=json.dumps(g,separators=(',',':'),ensure_ascii=False).encode('utf-8');js+=b' '*((-len(js))%4)
tail=raw[20+n:];out=struct.pack('<4sII',b'glTF',2,20+len(js)+len(tail))+struct.pack('<I4s',len(js),b'JSON')+js+tail
path.write_bytes(out)
print('G21_CANONICAL_TEXTURES',len(unique),flush=True)
