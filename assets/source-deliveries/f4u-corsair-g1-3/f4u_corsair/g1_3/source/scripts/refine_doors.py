import bpy,json,math
from pathlib import Path
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;col=bpy.data.collections['EXPORT_aircraft'];S.frame_set(0);report=[]
for o in col.objects:
 if o.type!='MESH'or not o.name.startswith('gear_door_')or '_mesh_'not in o.name:continue
 before=len(o.data.polygons);bpy.context.view_layer.objects.active=o
 mod=o.modifiers.new('Door edge highlight','BEVEL');mod.width=.00035;mod.segments=2;mod.limit_method='ANGLE';mod.angle_limit=math.radians(40)
 bpy.ops.object.modifier_apply(modifier=mod.name);o.data.set_sharp_from_angle(angle=math.radians(40));report.append({'name':o.name,'edge_radius_m':.00035,'faces_before':before,'faces_after':len(o.data.polygons)})
for m in bpy.data.materials:
 if m.name.startswith('paint_'):
  bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Roughness'].default_value=.36;bs.inputs['Metallic'].default_value=.05
# Rebuild the paint raster input from final meshes and existing UVs. Classify inner door faces in the closed pose.
S.frame_set(100);bpy.context.view_layer.update();closed={o.name:o.matrix_world.to_3x3().copy()for o in col.objects if o.type=='MESH'};S.frame_set(0);bpy.context.view_layer.update();records=[]
for o in col.objects:
 if o.type!='MESH'or not any(m and m.name.startswith('paint_')for m in o.data.materials):continue
 o.data.calc_loop_triangles();triangles=[]
 for t in o.data.loop_triangles:
  p=o.data.polygons[t.polygon_index]
  if not o.data.materials[p.material_index].name.startswith('paint_'):continue
  inner=o.name.startswith('gear_door_')and(closed[o.name]@t.normal).z>0
  triangles.append({'uv':[list(o.data.uv_layers['UVMap'].data[l].uv)for l in t.loops],'xyz':[list(o.matrix_world@o.data.vertices[v].co)for v in t.vertices],'normal':list(o.matrix_world.to_3x3()@t.normal),'door_inner':inner})
 records.append({'name':o.name,'triangles':triangles})
(P/'source/scripts/uv-layout.json').write_text(json.dumps(records));(P/'previews/door-refinement.json').write_text(json.dumps(report,indent=2));meta=json.loads((P/'metadata.json').read_text());meta['revision']='g1.1';meta['meshes']=[{'node':o.name,'section':o['openrc_section'],'triangles':sum(len(p.vertices)-2 for p in o.data.polygons),'surfaces':len(set(p.material_index for p in o.data.polygons))}for o in col.objects if o.type=='MESH'];meta['triangle_count']=sum(m['triangles']for m in meta['meshes']);meta['surface_count']=sum(m['surfaces']for m in meta['meshes']);meta['door_refinement']='0.35 mm edge bevels; interior faces classified from closed-pose normals; same sampled rigid carriers';(P/'metadata.json').write_text(json.dumps(meta,indent=2));
for im in list(bpy.data.images):
 if im.name=='g1_default_basecolor':bpy.data.images.remove(im)
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'));print('DOORS_DONE',meta['triangle_count'],flush=True)
