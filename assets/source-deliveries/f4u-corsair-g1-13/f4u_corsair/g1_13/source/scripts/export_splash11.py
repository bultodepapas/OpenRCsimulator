"""Standalone packed Blender export for the Splash livery, preserving other variants."""
import bpy,json,hashlib,struct,sys
from pathlib import Path
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;S.frame_set(0);bpy.context.view_layer.update()
refresh='--refresh-paint'in sys.argv
for label,file,cs in [('basecolor','basecolor.png','sRGB'),('orm','orm.png','Non-Color')]:
 name='splash_'+label
 if refresh and name in bpy.data.images:bpy.data.images.remove(bpy.data.images[name])
 im=bpy.data.images.get(name)
 if im is None:
  im=bpy.data.images.load(str(P/'textures/liveries/splash'/file),check_existing=False);im.name=name;im.colorspace_settings.name=cs;im.pack()
 for m in bpy.data.materials:
  if m.name.startswith('paint_'):
   for n in m.node_tree.nodes:
    if n.name=='paint_'+label:n.image=im
name='splash_interior_basecolor'
if refresh and name in bpy.data.images:bpy.data.images.remove(bpy.data.images[name])
im=bpy.data.images.get(name)
if im is None:
 im=bpy.data.images.load(str(P/'textures/liveries/splash/interiors/basecolor.png'),check_existing=False);im.name=name;im.colorspace_settings.name='sRGB';im.pack()
bs=next(n for n in bpy.data.materials['gear_inner_coat'].node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].links[0].from_node.image=im
# The cone is a separate connected component of the existing rotor mesh.
rotor=bpy.data.objects['propeller_rotor'];mesh=rotor.data
if 'splash_spinner_paint'not in bpy.data.materials:
 adjacency={v.index:set()for v in mesh.vertices}
 for e in mesh.edges:a,b=e.vertices;adjacency[a].add(b);adjacency[b].add(a)
 seed=max(mesh.vertices,key=lambda v:(rotor.matrix_world@v.co).y).index;todo=[seed];component={seed}
 while todo:
  i=todo.pop()
  for j in adjacency[i]:
   if j not in component:component.add(j);todo.append(j)
 assert len(component)==561,len(component)
 mat=bpy.data.materials.new('splash_spinner_paint');mat.use_nodes=True
 bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 def linear(c):c=c/255;return c/12.92 if c<=.04045 else((c+.055)/1.055)**2.4
 color=tuple(linear(c)for c in (255,194,4))+(1,);bs.inputs['Base Color'].default_value=color;bs.inputs['Roughness'].default_value=.285;bs.inputs['Metallic'].default_value=0;mat.diffuse_color=color
 mesh.materials.append(mat);index=len(mesh.materials)-1
 for p in mesh.polygons:
  if all(i in component for i in p.vertices):p.material_index=index
for name in ['g1_default_basecolor','g1_default_orm','naval10_interior_basecolor']:
 im=bpy.data.images.get(name)
 if im and im.users==0:bpy.data.images.remove(im)
S.frame_set(100);bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.collections['EXPORT_aircraft'].objects:o.hide_set(False);o.hide_render=False;o.select_set(True)
meta=json.loads((P/'metadata.json').read_text());settings=meta['export_settings'].copy();settings['filepath']=str(P/'export/aircraft_splash.glb');settings['export_current_frame']=True
bpy.ops.export_scene.gltf(**settings)
S.frame_set(0);bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT');o=bpy.data.objects['F4UCorsair'];o.select_set(True);bpy.context.view_layer.objects.active=o
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_splash.blend'))
raw=(P/'export/aircraft_splash.glb').read_bytes();g=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
record={'id':'splash','name':'Sunburst Splash','blend':'source/aircraft_splash.blend','glb':'export/aircraft_splash.glb','export_pose':100,'source_pose':0,'triangles':sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes']for p in m['primitives']),'surfaces':sum(len(m['primitives'])for m in g['meshes']),'materials':len(g['materials']),'images':len(g['images']),'glb_sha256':hashlib.sha256(raw).hexdigest(),'blend_sha256':hashlib.sha256((P/'source/aircraft_splash.blend').read_bytes()).hexdigest()}
meta['additional_splash_delivery']=record
if not any(l.get('id')=='splash'for l in meta['liveries']):meta['liveries'].append({'id':'splash','name':'Sunburst Splash','description':'Golden yellow, cobalt nose, asymmetric coloured splashes and red/white target underside.','basecolor':'textures/liveries/splash/basecolor.png','orm':'textures/liveries/splash/orm.png','editable':'textures/liveries/splash/source.ora'})
(P/'metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf8');print('SPLASH11_EXPORTED',json.dumps(record),flush=True)
