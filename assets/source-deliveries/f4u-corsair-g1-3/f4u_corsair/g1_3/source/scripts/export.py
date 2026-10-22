"""Re-export without R59: blender -b source/aircraft_game.blend --python source/scripts/export.py"""
import bpy,json,hashlib,sys
from pathlib import Path
P=Path(__file__).resolve().parents[2]
assert bpy.app.version[:3]==(5,2,2),bpy.app.version_string
col=bpy.data.collections['EXPORT_aircraft'];scene=bpy.context.scene;scene.frame_set(100);bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
for o in col.objects:o.hide_set(False);o.hide_render=False;o.select_set(True)
if not any(im.name=='g1_default_basecolor'for im in bpy.data.images):
 im=bpy.data.images.load(str(P/'textures/liveries/midnight/basecolor.png'));im.name='g1_default_basecolor';im.colorspace_settings.name='sRGB';im.pack()
else:im=bpy.data.images['g1_default_basecolor']
for name in ['paint_body','paint_wing','paint_wing_tip','paint_tail']:
 m=bpy.data.materials[name];bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');tex=next((n for n in m.node_tree.nodes if n.type=='TEX_IMAGE'),None)or m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
settings={'filepath':str(P/'export/aircraft.glb'),'export_format':'GLB','use_selection':True,'export_yup':True,'export_extras':True,'export_cameras':False,'export_lights':False,'export_animations':False,'export_materials':'EXPORT','export_image_format':'AUTO','export_texcoords':True,'export_normals':True,'export_tangents':False,'export_draco_mesh_compression_enable':False}
settings['export_current_frame']=True
rna=bpy.ops.export_scene.gltf.get_rna_type();settings={k:v for k,v in settings.items()if k in rna.properties};assert settings.get('export_extras')is True and settings.get('export_current_frame')is True
bpy.ops.export_scene.gltf(**settings)
meta=json.loads((P/'metadata.json').read_text());meta['glb_sha256']=hashlib.sha256((P/'export/aircraft.glb').read_bytes()).hexdigest();meta['export_settings']=settings.copy();meta['export_settings']['filepath']='export/aircraft.glb'
try:
 import io_scene_gltf2
 meta['exporter_version']=list(io_scene_gltf2.bl_info.get('version',[]))
except Exception:meta['exporter_version']='bundled Blender 5.2.2 glTF exporter'
meta['runtime_texture_count']=1;meta['runtime_image_count']=1;meta['runtime_export_frame']=100;meta['nodes']={o.name:{'parent':o.parent.name if o.parent else None,'section':o.get('openrc_section'),'pose_frame':100,'rest_matrix_blender':[list(row)for row in o.matrix_world],'rest_matrix_local':[list(row)for row in o.matrix_local]}for o in col.objects}
scene.frame_set(0);bpy.context.view_layer.update()
meta['nodes_down']={o.name:{'world_matrix_blender':[list(row)for row in o.matrix_world],'local_matrix_blender':[list(row)for row in o.matrix_local]}for o in col.objects}
(P/'metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf8')
bpy.ops.object.select_all(action='DESELECT');bpy.data.objects['F4UCorsair'].select_set(True);bpy.context.view_layer.objects.active=bpy.data.objects['F4UCorsair']
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'));print('G1_EXPORTED',flush=True)
