import bpy,json,sys,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;S.frame_set(0);bpy.context.view_layer.update();samples=json.loads((P/'source/scripts/reference-samples.json').read_text());report={}
for name,(wrapped,count)in samples.items():
 o=bpy.data.objects[name];tree=BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[list(p.vertices)for p in o.data.polygons]);dist=sorted(tree.find_nearest(Vector(v))[3]for v in wrapped);report[name]={'sample_count':len(dist),'maximum_distance_m':max(dist),'p95_distance_m':dist[int(.95*(len(dist)-1))]}
(P/'previews/surface-deviation.json').write_text(json.dumps(report,indent=2))
if '--'not in sys.argv:raise SystemExit(0)
cache=sys.argv[sys.argv.index('--')+1]
with bpy.data.libraries.load(cache,link=False)as(src,dst):dst.collections=['G1_REFERENCE']
ref=dst.collections[0];S.collection.children.link(ref)
# The optional cache contains the accepted 1:5 reference, scaled here in memory.
K=(1/4.5)/.2
from mathutils import Matrix
for data in {o.data for o in ref.objects if o.type=='MESH'}:data.transform(Matrix.Scale(K,4));data.update()
for o in ref.objects:
 o.location*=K;M=o.matrix_parent_inverse.copy();M.translation*=K;o.matrix_parent_inverse=M
bpy.context.view_layer.update()
game=bpy.data.collections['EXPORT_aircraft']
S.render.engine='BLENDER_WORKBENCH';S.display.shading.light='FLAT';S.display.shading.color_type='SINGLE';S.display.shading.single_color=(.03,.03,.03);S.display.shading.show_shadows=False;S.display.shading.show_cavity=False;S.display.shading.background_type='WORLD';S.world=bpy.data.worlds.new('comparison_world');S.world.color=(1,1,1);S.render.resolution_x=1000;S.render.resolution_y=800;S.render.resolution_percentage=100
d=bpy.data.cameras.new('comparison_camera');c=bpy.data.objects.new('comparison_camera',d);S.collection.objects.link(c);S.camera=c;d.type='ORTHO';d.ortho_scale=3.1*K;target=Vector((0,-.52,0))*K
# Matching selected exterior parts only; gear/interior omitted from both silhouette sets.
names=set(samples)
for view,loc in [('front',(0,6,0)),('side',(6,-.52,0)),('top',(0,-.52,6))]:
 c.location=Vector(loc)*K;c.rotation_euler=(target-c.location).to_track_quat('-Z','Y').to_euler()
 for variant in ('reference','g1'):
  for o in game.objects:o.hide_render=variant!='g1'or(o.type=='MESH'and o.name not in names)
  for o in ref.objects:o.hide_render=variant!='reference'or o.name.removeprefix('reference_')not in names
  S.render.filepath=str(P/'previews'/f'silhouette_{view}_{variant}.png');bpy.ops.render.render(write_still=True)
print('COMPARISON_DONE',flush=True)

