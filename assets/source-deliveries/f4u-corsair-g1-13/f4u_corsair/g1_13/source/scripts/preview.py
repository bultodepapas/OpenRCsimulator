import bpy,math,json
from pathlib import Path
from mathutils import Vector,Matrix
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;S.frame_set(100)
K=10/9
S.render.engine='CYCLES';S.cycles.samples=12;S.cycles.use_denoising=True
S.render.resolution_x=1000;S.render.resolution_y=800;S.render.resolution_percentage=100
S.world=bpy.data.worlds.new('PreviewWorld');S.world.color=(.25,.25,.25)
S.view_settings.view_transform='AgX'
def area(name,loc,power,size):
 d=bpy.data.lights.new(name,'AREA');d.energy=power*K*K;d.shape='DISK';d.size=size*K;o=bpy.data.objects.new(name,d);S.collection.objects.link(o);o.location=Vector(loc)*K;o.rotation_euler=(Vector((0,-.5,0))*K-o.location).to_track_quat('-Z','Y').to_euler()
area('preview_key',(2,3,5),450,5);area('preview_fill',(-3,1,2),300,4);area('preview_rim',(0,-4,3),500,3)
d=bpy.data.cameras.new('preview_camera');c=bpy.data.objects.new('preview_camera',d);S.collection.objects.link(c);S.camera=c;d.type='ORTHO';d.ortho_scale=3.3*K
target=Vector((0,-.52,-.02))*K
def render(name,loc):
 c.location=Vector(loc)*K;c.rotation_euler=(target-c.location).to_track_quat('-Z','Y').to_euler();S.render.filepath=str(P/'previews'/f'{name}.png');bpy.ops.render.render(write_still=True);print('PREVIEW',name,flush=True)
for name,loc in [('front',(0,6,0)),('side',(6,-.52,0)),('top',(0,-.52,6)),('underside',(0,-.52,-6)),('three_quarter',(3,4,2.5))]:render(name,loc)
for f in (0,50,100):S.frame_set(f);render('gear_'+str(f),(3,4,-2))
S.frame_set(0)
meta=json.loads((P/'metadata.json').read_text());rest={a['node']:bpy.data.objects[a['node']].matrix_basis.copy()for a in meta['articulations']}
for angle in (0,20,40,50):
 for n,M in rest.items():
  if n.startswith('flap_'):bpy.data.objects[n].matrix_basis=M@Matrix.Rotation(math.radians(angle),4,'X')
 render('flaps_'+str(angle),(3,-4,-2))
for n,M in rest.items():bpy.data.objects[n].matrix_basis=M
for sign in (-1,1):
 for n,M in rest.items():
  if n.startswith(('aileron','elevator','rudder')):bpy.data.objects[n].matrix_basis=M@Matrix.Rotation(math.radians(sign*(35 if n.startswith('rudder')else 25)),4,'X')
 render('controls_'+str(sign),(3,-4,2))
for n,M in rest.items():bpy.data.objects[n].matrix_basis=M
bpy.context.view_layer.update()
saved={o:o.matrix_basis.copy()for o in bpy.data.collections['EXPORT_aircraft'].objects}
offsets={'wing_left':(-.42,0,0),'wing_right':(.42,0,0),'wing_center':(0,0,-.25),'horizontal_tail':(0,-.35,.2),'vertical_tail':(0,-.35,.45),'engine':(0,.4,0),'propeller':(0,.75,0),'gear':(0,0,-.5),'canopy':(0,0,.4)}
for o in bpy.data.collections['EXPORT_aircraft'].objects:
 if o.get('openrc_section')in offsets and (not o.parent or o.parent.get('openrc_section')!=o.get('openrc_section')):o.location+=Vector(offsets[o['openrc_section']])*K
d.ortho_scale=4.3*K;render('exploded',(3,4,2.5));d.ortho_scale=3.3*K
for o,M in saved.items():o.matrix_basis=M
bpy.context.view_layer.update()
S.frame_set(100)
for lid in ('three_tone','scarlet'):
 im=bpy.data.images.load(str(P/'textures/liveries'/lid/'basecolor.png'));orm=bpy.data.images.load(str(P/'textures/liveries'/lid/'orm.png'));orm.colorspace_settings.name='Non-Color'
 for m in bpy.data.materials:
  if m.name.startswith('paint_'):
   for n in m.node_tree.nodes:
    if n.name=='paint_basecolor':n.image=im
    if n.name=='paint_orm':n.image=orm
 render('livery_'+lid,(3,4,2.5))
# Close-up evidence for door finish and clearance.
for m in bpy.data.materials:
 if m.name.startswith('paint_'):
  for n in m.node_tree.nodes:
   if n.name=='paint_basecolor':n.image=bpy.data.images['g1_default_basecolor']
   if n.name=='paint_orm':n.image=bpy.data.images['g1_default_orm']
area('door_fill',(0,1,-2),250,2)
target=Vector((.40,-.25,-.20))*K;d.ortho_scale=.75*K
for f in (0,50,100):
 S.frame_set(f);render('door_detail_'+str(f),(1.3,.8,-1.1))
print('PREVIEWS_DONE',flush=True)
