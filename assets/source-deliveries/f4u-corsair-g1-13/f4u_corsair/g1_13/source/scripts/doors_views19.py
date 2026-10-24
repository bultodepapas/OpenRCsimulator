import bpy,sys
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parents[2]
if '--runtime'in sys.argv:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(P/'export/aircraft_super57.glb'))
exec(compile((P/'source/scripts/preview.py').read_text().split('for name,loc in')[0],str(P/'source/scripts/preview.py'),'exec'))
S.cycles.samples=32;S.render.resolution_x=1300;S.render.resolution_y=1000
try:S.view_settings.look='AgX - Medium High Contrast'
except TypeError:pass
area('door_softbox',(-1,1,-2),120,2);area('door_rim',(2,-2,-1),90,2)
if '--runtime'in sys.argv:
 target=Vector((0,-.52,-.02))*K;d.ortho_scale=3.3*K;render('doors19_runtime',(-3,2,-3))
 # Inspect the imported GLB interior in the supplied deployed pose, using local matrices.
 meta=json.loads((P/'metadata.json').read_text())
 for name,spec in meta['nodes_down'].items():
  o=bpy.data.objects[name];o.matrix_parent_inverse.identity();o.matrix_basis=Matrix(spec['local_matrix_blender'])
 bpy.context.view_layer.update()
 error=max((bpy.data.objects[name].matrix_world.translation-Matrix(spec['world_matrix_blender']).translation).length for name,spec in meta['nodes_down'].items());assert error<.0001,error
 target=Vector((.46,-.29,-.27));d.ortho_scale=.62;render('doors19_runtime_interior',(1,-.8,-.68))
 (P/'previews/runtime-interior-pose.json').write_text(json.dumps({'passed':True,'maximum_world_translation_error_m':error,'pose_source':'Delivery metadata nodes_down local transforms applied to the actual reimported racing GLB; no geometry or material changes.'},indent=2))
else:
 S.frame_set(0);bpy.context.view_layer.update();target=Vector((.46,-.29,-.27));d.ortho_scale=.62
 if '--force'in sys.argv or not (P/'previews/doors19_overview.png').exists():render('doors19_overview',(1,-.8,-.68))
 for role in ['right','left']:
  o=bpy.data.objects['gear_door_inner_mesh_'+role];ps=[p for p in o.data.polygons if o.data.materials[p.material_index].name=='gear_inner_coat'];total=sum(p.area for p in ps)
  target=sum(((o.matrix_world@p.center)*p.area for p in ps),Vector())/total;normal=sum(((o.matrix_world.to_3x3()@p.normal)*p.area for p in ps),Vector()).normalized();cam=target+normal*.8+Vector((.08,.06,-.06));d.ortho_scale=.39;render('doors19_inner_'+role,cam/K)
 if '--quick'not in sys.argv:
  target=Vector((0,-.52,-.02))*K;d.ortho_scale=3.3*K;render('doors19_hero',(3,4,1.5))
  target=Vector((.4,-.25,-.20))*K;d.ortho_scale=.95*K
  for f in (0,50,100):S.frame_set(f);render('doors19_motion_'+str(f),(1.3,.8,-1.1))
print('DOORS19_VIEWS_DONE',flush=True)
