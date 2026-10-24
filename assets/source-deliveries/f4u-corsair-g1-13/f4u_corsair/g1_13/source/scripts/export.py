"""Re-export without R59: blender -b source/aircraft_game.blend --python source/scripts/export.py"""
import bpy,json,hashlib,sys,struct
from pathlib import Path
P=Path(__file__).resolve().parents[2]
assert bpy.app.version[:3]==(5,2,2),bpy.app.version_string
col=bpy.data.collections['EXPORT_aircraft'];scene=bpy.context.scene;scene.frame_set(100);bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
for o in col.objects:o.hide_set(False);o.hide_render=False;o.select_set(True)
images={}
for label,file,color_space in [('basecolor','basecolor.png','sRGB'),('orm','orm.png','Non-Color')]:
 name='g1_default_'+label
 if '--refresh-paint' in sys.argv and name in bpy.data.images:bpy.data.images.remove(bpy.data.images[name])
 im=bpy.data.images.get(name)
 if im is None:im=bpy.data.images.load(str(P/'textures/liveries/midnight'/file));im.name=name;im.colorspace_settings.name=color_space;im.pack()
 images[label]=im
for name in ['paint_body','paint_wing','paint_wing_tip','paint_tail']:
 m=bpy.data.materials[name];nodes=m.node_tree.nodes;links=m.node_tree.links;bs=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
 for n in list(nodes):
  if n.type not in {'BSDF_PRINCIPLED','OUTPUT_MATERIAL'}:nodes.remove(n)
 tex=nodes.new('ShaderNodeTexImage');tex.name='paint_basecolor';tex.image=images['basecolor'];links.new(tex.outputs['Color'],bs.inputs['Base Color'])
 orm=nodes.new('ShaderNodeTexImage');orm.name='paint_orm';orm.image=images['orm'];sep=nodes.new('ShaderNodeSeparateColor');sep.mode='RGB';links.new(orm.outputs['Color'],sep.inputs['Color']);links.new(sep.outputs['Green'],bs.inputs['Roughness']);links.new(sep.outputs['Blue'],bs.inputs['Metallic'])
 bs.inputs['Metallic'].default_value=0.;bs.inputs['Roughness'].default_value=.31
settings={'filepath':str(P/'export/aircraft.glb'),'export_format':'GLB','use_selection':True,'export_yup':True,'export_extras':True,'export_cameras':False,'export_lights':False,'export_animations':False,'export_materials':'EXPORT','export_image_format':'AUTO','export_texcoords':True,'export_normals':True,'export_tangents':False,'export_draco_mesh_compression_enable':False}
sys.path.insert(0,str(Path(__file__).resolve().parent))
from naval_prop10 import bind_naval_prop
bind_naval_prop(P,'--refresh-paint' in sys.argv)
name='naval10_interior_basecolor'
if '--refresh-paint' in sys.argv and name in bpy.data.images:bpy.data.images.remove(bpy.data.images[name])
im=bpy.data.images.get(name)
if im is None:
 im=bpy.data.images.load(str(P/'textures/liveries/midnight/interiors/basecolor.png'),check_existing=False);im.name=name;im.colorspace_settings.name='sRGB';im.pack()
inner=bpy.data.materials['gear_inner_coat'];bs=next(n for n in inner.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
color_node=bs.inputs['Base Color'].links[0].from_node;color_node.image=im
old=bpy.data.images.get('interior19_basecolor')
if old is not None and old.users==0:bpy.data.images.remove(old)
settings['export_current_frame']=True
rna=bpy.ops.export_scene.gltf.get_rna_type();settings={k:v for k,v in settings.items()if k in rna.properties};assert settings.get('export_extras')is True and settings.get('export_current_frame')is True
bpy.ops.export_scene.gltf(**settings)
meta=json.loads((P/'metadata.json').read_text());meta['glb_sha256']=hashlib.sha256((P/'export/aircraft.glb').read_bytes()).hexdigest();meta['export_settings']=settings.copy();meta['export_settings']['filepath']='export/aircraft.glb'
try:
 import io_scene_gltf2
 meta['exporter_version']=list(io_scene_gltf2.bl_info.get('version',[]))
except Exception:meta['exporter_version']='bundled Blender 5.2.2 glTF exporter'
meta['revision']='g1.10';raw=(P/'export/aircraft.glb').read_bytes();gltf=json.loads(raw[20:20+struct.unpack_from('<I',raw,12)[0]]);meta['runtime_texture_count']=len(gltf.get('textures',[]));meta['runtime_image_count']=len(gltf.get('images',[]));meta.setdefault('paint_finish',{});meta['paint_finish'].update({'basecolor':'sRGB atlas','roughness':'orm.png green channel, linear','metallic':'0 on airframe paint; wheel atlas distinguishes bare metal from tyre and paint','default':'midnight','shared_airframe_uv_preserved':True});meta['runtime_export_frame']=100;meta['nodes']={o.name:{'parent':o.parent.name if o.parent else None,'section':o.get('openrc_section'),'pose_frame':100,'rest_matrix_blender':[list(row)for row in o.matrix_world],'rest_matrix_local':[list(row)for row in o.matrix_local]}for o in col.objects}
scene.frame_set(0);bpy.context.view_layer.update()
meta['nodes_down']={o.name:{'world_matrix_blender':[list(row)for row in o.matrix_world],'local_matrix_blender':[list(row)for row in o.matrix_local]}for o in col.objects}
(P/'metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf8')
bpy.ops.object.select_all(action='DESELECT');bpy.data.objects['F4UCorsair'].select_set(True);bpy.context.view_layer.objects.active=bpy.data.objects['F4UCorsair']
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'));print('G1_EXPORTED',flush=True)
