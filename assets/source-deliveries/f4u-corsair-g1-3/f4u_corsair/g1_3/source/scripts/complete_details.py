"""Optional master-based detail completion. Run once after derive, before export."""
import bpy,json,sys,math
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(__file__).resolve().parents[2];master=Path(sys.argv[sys.argv.index('--')+1]);meta=json.loads((P/'metadata.json').read_text());D=Vector(meta['D0_r59_m']);payload={};detail={}
bpy.ops.wm.open_mainfile(filepath=str(master));root=bpy.data.objects['F4U CORSAIR | avion completo']
for o in bpy.data.objects:
 if o.animation_data:o.animation_data.action=None
root.matrix_world=Matrix.Identity(4);root['gancho_cola_deg']=0.;root.update_tag();bpy.context.view_layer.update()
names=['Mando R7 | base','Mando R7 | columna','Mando R7 | empunadura','Mando R7 | pulsador','R27 | asta gancho','R27 | punta curva gancho']
def convert(v):return Vector((v.y,-(v.x-D.x),v.z-D.z))*.2
for name in names+['Luz de posicion R8 | izquierda','Luz de posicion R8 | derecha','R26 | cristal curvo luz']+[f'R43 | Escape unido {s} {i}'for s in [-1,1]for i in [1,2,3]]:
 o=bpy.data.objects.get(name)
 if not o:continue
 for m in o.modifiers:
  if m.type in {'SUBSURF','BEVEL'}:m.show_viewport=False
 bpy.context.view_layer.update();ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();vs=[convert(ev.matrix_world@v.co)for v in me.vertices]
 if name in names:payload[name]=([list(v)for v in vs],[list(p.vertices)for p in me.polygons])
 else:
  if name.startswith('R43'):
   end=min(v.y for v in vs);vs=[v for v in vs if v.y<end+.002]
  detail[name]=list(sum(vs,Vector())/len(vs))
 ev.to_mesh_clear()
bpy.ops.wm.open_mainfile(filepath=str(P/'source/aircraft_game.blend'));col=bpy.data.collections['EXPORT_aircraft'];root=bpy.data.objects['F4UCorsair'];mapping=json.loads((P/'export-map.json').read_text())
for target,prefix,material in [('cockpit_interior','Mando','cockpit'),('core_details','R27','alloy')]:
 vs=[];fs=[];sources=[]
 for name,(verts,faces)in payload.items():
  if not name.startswith(prefix):continue
  start=len(vs);vs.extend(verts);fs.extend([tuple(start+i for i in face)for face in faces]);sources.append(name)
 me=bpy.data.meshes.new('completion_mesh');me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new('completion',me);col.objects.link(o);o.data.materials.append(bpy.data.materials[material]);o['openrc_section']='core';o.parent=root
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 tri=sum(len(p.vertices)-2 for p in me.polygons)
 if tri>500:
  mod=o.modifiers.new('detail_budget','DECIMATE');mod.ratio=500/tri;bpy.ops.object.modifier_apply(modifier=mod.name)
 if target in bpy.data.objects:
  existing=bpy.data.objects[target];existing.select_set(True);bpy.context.view_layer.objects.active=existing;bpy.ops.object.join();o=existing
 else:o.name=target
 for row in mapping['objects']:
  if row['source']in sources:row.update(status='simplified',target=target,reason='neutral rigid cockpit control or stowed tailhook, locally reduced')
# A small original gunsight housing, with a thin reflective plate; fixed to core.
target=bpy.data.objects['cockpit_interior'];bpy.ops.object.select_all(action='DESELECT')
for loc,scale in [((0,-.425,.181),(.012,.015,.008)),((0,-.426,.195),(.013,.002,.009))]:
 bpy.ops.mesh.primitive_cube_add(size=2,location=loc);o=bpy.context.object;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(bpy.data.materials['cockpit']);target.select_set(True);bpy.context.view_layer.objects.active=target;bpy.ops.object.join();bpy.ops.object.select_all(action='DESELECT')
for o in col.objects:
 if o.type=='MESH'and not o.data.uv_layers:o.data.uv_layers.new(name='UVMap')
meta['landmarks_blender_m']['detail_lenses_and_exhaust_exits']=detail
meta['detail_notes']=['Gunsight is an original low-detail visual proxy, not a measured historical instrument.','Stowed tailhook and control stick retained from R59.','Flap 1 relief: left 0.5 mm aft, right 0.6 mm aft. Flap 2 relief: 2 mm aft and 1.1 mm down, in each hinge local frame. Pivots unchanged.']
meta['meshes']=[{'node':o.name,'section':o['openrc_section'],'triangles':sum(len(p.vertices)-2 for p in o.data.polygons),'surfaces':len(set(p.material_index for p in o.data.polygons))}for o in col.objects if o.type=='MESH'];meta['triangle_count']=sum(x['triangles']for x in meta['meshes']);meta['surface_count']=sum(x['surfaces']for x in meta['meshes'])
for section in meta['sections']:section['nodes']=[o.name for o in col.objects if o.get('openrc_section')==section['id']]
(P/'metadata.json').write_text(json.dumps(meta,indent=2));(P/'export-map.json').write_text(json.dumps(mapping,indent=2));bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'source/aircraft_game.blend'));print('DETAILS_DONE',meta['triangle_count'],flush=True)
