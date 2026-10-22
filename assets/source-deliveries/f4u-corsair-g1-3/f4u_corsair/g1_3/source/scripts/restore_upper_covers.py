import bpy,json,math
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(__file__).resolve().parents[2];ROOT=P.parents[1];meta=json.loads((P/'metadata.json').read_text());D=Vector(meta['D0_r59_m']);payload={}
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'flaps_R59/F4U_Corsair_flaps_R59.blend'))
for o in bpy.data.objects:
 if o.animation_data:o.animation_data.action=None
root=bpy.data.objects['F4U CORSAIR | avion completo'];root.matrix_world=Matrix.Identity(4);root['flaps_deg']=0;root.update_tag();control=bpy.data.objects['R51 | CONTROL ALAS']
for side in ['derecha','izquierda']:control['plegado_'+side]=0.;control['bloqueo_'+side]=1.
control.update_tag();bpy.context.view_layer.update()
for side in ['derecha','izquierda']:
 for i in range(3):
  name=f'R55 | {side} tapa enrasada bisagra {i}';o=bpy.data.objects[name];ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();vs=[]
  for v in me.vertices:
   w=ev.matrix_world@v.co;vs.append((.2*w.y,-.2*(w.x-D.x),.2*(w.z-D.z)))
  payload[name]=(vs,[list(p.vertices)for p in me.polygons]);ev.to_mesh_clear()
bpy.ops.wm.open_mainfile(filepath=str(P/'source/aircraft_game.blend'));col=bpy.data.collections['EXPORT_aircraft'];records=json.loads((P/'source/scripts/uv-layout.json').read_text());occupied=[]
for r in records:
 uvs=[uv for t in r['triangles']for uv in t['uv']];occupied.append((min(v[0]for v in uvs),min(v[1]for v in uvs),max(v[0]for v in uvs),max(v[1]for v in uvs)))
def tile():
 for yi in range(24):
  for xi in range(24):
   x=.005+xi*.041;y=.005+yi*.041;box=(x,y,x+.035,y+.035)
   if not any(not(box[2]<a or box[0]>c or box[3]<b or box[1]>d)for a,b,c,d in occupied):occupied.append(box);return box
 raise RuntimeError('No free UV tile')
cover_names=[];coverreport=[]
for index,(src,(vs,fs))in enumerate(payload.items()):
 name='upper_fold_cover_'+str(index);me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new(name,me);col.objects.link(o);o.data.materials.append(bpy.data.materials['paint_wing']);o['openrc_section']='wing_center';o.parent=bpy.data.objects['F4UCorsair'];bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 count=sum(len(p.vertices)-2 for p in me.polygons)
 if count>350:
  mod=o.modifiers.new('Cover budget','DECIMATE');mod.ratio=350/count;bpy.ops.object.modifier_apply(modifier=mod.name)
 for p in o.data.polygons:p.use_smooth=True
 o.data.set_sharp_from_angle(angle=math.radians(40));o.data.uv_layers.new(name='UVMap');bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.025);bpy.ops.object.mode_set(mode='OBJECT');a,b,c,d=tile()
 for uv in o.data.uv_layers.active.data:uv.uv=(a+.002+uv.uv.x*(c-a-.004),b+.002+uv.uv.y*(d-b-.004))
 o.data.calc_loop_triangles();triangles=[{'uv':[list(o.data.uv_layers.active.data[l].uv)for l in t.loops],'xyz':[list(o.data.vertices[v].co)for v in t.vertices],'normal':list(t.normal),'door_inner':False}for t in o.data.loop_triangles];records.append({'name':name,'triangles':triangles});coverreport.append({'source':src,'target':'wing_center_fixed','triangles':len(triangles),'uv_tile':[a,b,c,d]});cover_names.append(o.name)
bpy.ops.object.select_all(action='DESELECT');target=bpy.data.objects['wing_center_fixed'];target.select_set(True)
for n in cover_names:bpy.data.objects[n].select_set(True)
bpy.context.view_layer.objects.active=target;bpy.ops.object.join();mapping=json.loads((P/'export-map.json').read_text())
for row in mapping['objects']:
 if row['source']in payload:row.update(status='simplified',target='wing_center_fixed',reason='Restored closed flush wing-fold cover omitted from g1; fixed spread-wing game configuration')
for im in list(bpy.data.images):
 if im.name=='g1_default_basecolor':bpy.data.images.remove(im)
meta['revision']='g1.2';meta['upper_cover_restoration']=coverreport;meta['meshes']=[{'node':o.name,'section':o['openrc_section'],'triangles':sum(len(p.vertices)-2 for p in o.data.polygons),'surfaces':len(set(p.material_index for p in o.data.polygons))}for o in col.objects if o.type=='MESH'];meta['triangle_count']=sum(x['triangles']for x in meta['meshes']);meta['surface_count']=sum(x['surfaces']for x in meta['meshes']);(P/'metadata.json').write_text(json.dumps(meta,indent=2));(P/'export-map.json').write_text(json.dumps(mapping,indent=2));(P/'source/scripts/uv-layout.json').write_text(json.dumps(records));(P/'previews/upper-cover-restoration.json').write_text(json.dumps(coverreport,indent=2));bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'));print('COVERS_RESTORED',meta['triangle_count'],flush=True)

