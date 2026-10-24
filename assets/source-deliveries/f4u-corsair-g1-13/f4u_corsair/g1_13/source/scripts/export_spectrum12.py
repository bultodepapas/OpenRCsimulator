"""Export the fourth livery from its self-contained packed Blender source."""
import bpy,json,hashlib,struct,sys
from pathlib import Path
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;S.frame_set(0);bpy.context.view_layer.update()
refresh='--refresh-paint'in sys.argv
def packed(name,relative,cs='sRGB'):
 if refresh and name in bpy.data.images:bpy.data.images.remove(bpy.data.images[name])
 im=bpy.data.images.get(name)
 if im is None:
  im=bpy.data.images.load(str(P/relative),check_existing=False);im.name=name;im.colorspace_settings.name=cs;im.pack()
 return im
for label,file,cs in [('basecolor','basecolor.png','sRGB'),('orm','orm.png','Non-Color')]:
 im=packed('spectrum_'+label,'textures/liveries/spectrum/'+file,cs)
 for m in bpy.data.materials:
  if m.name.startswith('paint_'):
   for n in m.node_tree.nodes:
    if n.name=='paint_'+label:n.image=im
im=packed('spectrum_interior_basecolor','textures/liveries/spectrum/interiors/basecolor.png')
bs=next(n for n in bpy.data.materials['gear_inner_coat'].node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].links[0].from_node.image=im
im=packed('spectrum_propeller_basecolor','textures/liveries/spectrum/propeller_basecolor.png')
mat=bpy.data.materials.get('spectrum_blade_paint')or bpy.data.materials['naval_blade_paint'];mat.name='spectrum_blade_paint'
for n in mat.node_tree.nodes:
 if n.type=='TEX_IMAGE':n.image=im
bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=.29
for name in ['g1_default_basecolor','g1_default_orm','naval10_interior_basecolor','naval_propeller_basecolor']:
 im=bpy.data.images.get(name)
 if im and im.users==0:bpy.data.images.remove(im)
S.frame_set(100);bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.collections['EXPORT_aircraft'].objects:o.hide_set(False);o.hide_render=False;o.select_set(True)
meta=json.loads((P/'metadata.json').read_text());settings=meta['export_settings'].copy();settings['filepath']=str(P/'export/aircraft_spectrum.glb');settings['export_current_frame']=True
bpy.ops.export_scene.gltf(**settings)
S.frame_set(0);bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT');o=bpy.data.objects['F4UCorsair'];o.select_set(True);bpy.context.view_layer.objects.active=o
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_spectrum.blend'))
raw=(P/'export/aircraft_spectrum.glb').read_bytes();g=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]])
record={'id':'spectrum','name':'Spectrum Wings','blend':'source/aircraft_spectrum.blend','glb':'export/aircraft_spectrum.glb','export_pose':100,'source_pose':0,'triangles':sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes']for p in m['primitives']),'surfaces':sum(len(m['primitives'])for m in g['meshes']),'materials':len(g['materials']),'images':len(g['images']),'glb_sha256':hashlib.sha256(raw).hexdigest(),'blend_sha256':hashlib.sha256((P/'source/aircraft_spectrum.blend').read_bytes()).hexdigest()}
meta['additional_spectrum_delivery']=record
if not any(l.get('id')=='spectrum'for l in meta['liveries']):meta['liveries'].append({'id':'spectrum','name':'Spectrum Wings','description':'White airframe with curved gold, orange, red, violet, blue and dark wing feathers; longitudinal side ribbons.','basecolor':'textures/liveries/spectrum/basecolor.png','orm':'textures/liveries/spectrum/orm.png','editable':'textures/liveries/spectrum/source.ora'})
(P/'metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf8');print('SPECTRUM12_EXPORTED',json.dumps(record),flush=True)
