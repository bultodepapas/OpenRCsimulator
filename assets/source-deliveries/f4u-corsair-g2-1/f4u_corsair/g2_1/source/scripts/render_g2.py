"""Back-face-culled inspection views, using the saved g2 source and exact rig poses."""
import bpy,math,json,sys
from pathlib import Path
from mathutils import Vector,Matrix
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;S.frame_set(0);col=bpy.data.collections['EXPORT_aircraft']
S.render.engine='CYCLES' if '--cycles' in sys.argv else 'CYCLES'
# Cycles does not cull opaque back faces. This inspection explicitly uses Eevee.
S.render.engine='CYCLES'
try:S.render.engine='BLENDER_EEVEE'
except TypeError:S.render.engine='BLENDER_EEVEE_NEXT'
S.render.resolution_x=1600;S.render.resolution_y=1080;S.render.resolution_percentage=100;S.render.image_settings.file_format='PNG'
S.world=bpy.data.worlds.new('InspectionWorld');S.world.use_nodes=True
bg=next(n for n in S.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.16,.19,.24,1);bg.inputs['Strength'].default_value=.45
S.view_settings.view_transform='AgX';S.view_settings.exposure=.4
for m in bpy.data.materials:
 if m.name!='glass':m.use_backface_culling=True
def light(name,loc,power,size):
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;o=bpy.data.objects.new(name,d);S.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,-.5,0))-o.location).to_track_quat('-Z','Y').to_euler()
light('Key',(2,3,4),650,4);light('Fill',(-3,0,2),500,3);light('Rim',(1,-4,3),700,3);light('Underside',(0,.5,-3),240,3)
d=bpy.data.cameras.new('InspectionCamera');cam=bpy.data.objects.new('InspectionCamera',d);S.collection.objects.link(cam);S.camera=cam;d.lens=48;d.clip_start=.01;d.clip_end=100
out=P/'previews';out.mkdir(exist_ok=True);rows=[]
def render(name,loc,target,ortho=None):
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO' if ortho else 'PERSP'
 if ortho:d.ortho_scale=ortho
 S.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True);rows.append({'file':name+'.png','frame':S.frame_current,'camera':list(loc),'target':list(target),'orthographic_width':ortho,'opaque_backface_culling':True});print('VIEW',name,flush=True)
def depth(o):
 n=0
 while o.parent:n+=1;o=o.parent
 return n
render('home_ground',(3.0,3.2,1.8),(0,-.45,-.05),3.6)
render('nose_close',(1.0,1.7,.55),(0,.48,.02),1.15)
render('cockpit_close',(-1.15,.1,.9),(0,-.53,.15),.95)
render('gear_close',(-1.25,.55,-.85),(-.48,-.18,-.28),.9)
render('tail_close',(1.05,-2.6,.5),(0,-1.65,.12),1.15)
render('underside_down',(2.3,2.5,-2.0),(0,-.5,-.08),3.5)
for name,loc in [('front',(0,6,0)),('side',(-6,-.55,0)),('top',(0,-.55,6))]:render(name,loc,(0,-.55,0),3.8 if name=='top' else 3.4)
S.frame_set(50);render('gear_transit',(2.3,2.5,-2),(0,-.45,-.08),3.5)
S.frame_set(100);render('underside_up',(2.3,2.5,-2),(0,-.5,-.08),3.5);render('chase',(2,-4,1.55),(0,-.6,0),3.6)
S.frame_set(0);rest={o.name:o.matrix_basis.copy() for o in col.objects if o.name.startswith(('flap_','aileron_')) and o.type=='EMPTY'}
for angle in [20,40,50]:
 for name,M in rest.items():
  if name.startswith('flap_'):bpy.data.objects[name].matrix_basis=M@Matrix.Rotation(math.radians(angle),4,'X')
 bpy.context.view_layer.update();render('flaps_'+str(angle),(2.4,-3,-1.4),(0,-.5,-.05),3.5)
for name,M in rest.items():bpy.data.objects[name].matrix_basis=M
bpy.context.view_layer.update()
controls={name:bpy.data.objects[name].matrix_basis.copy() for name in ['aileron_left_hinge','aileron_right_hinge','elevator_hinge','rudder_hinge','gear_steer_tail']}
for sign in [-1,1]:
 for name,M in controls.items():
  axis='Y' if name=='gear_steer_tail' else 'X';angle=30 if name=='gear_steer_tail' else 35 if name=='rudder_hinge' else 25
  bpy.data.objects[name].matrix_basis=M@Matrix.Rotation(math.radians(sign*angle),4,axis)
 bpy.context.view_layer.update();render('controls_'+('positive'if sign>0 else'negative'),(2.4,-3,1.3),(0,-.5,0),3.5)
for name,M in controls.items():bpy.data.objects[name].matrix_basis=M
bpy.context.view_layer.update();world_rest={o.name:o.matrix_world.copy()for o in col.objects}
# Runtime wing fold: rotate the fixed panel and its aileron/outer-flap pivot together.
for role,sign in [('left',-1),('right',1)]:
 # F4U-17 constants are Godot XYZ; convert to Blender X,-Z,Y once.
 p=Vector((sign*.560,-.121,-.141));axis=Vector((0,-.977,.215)).normalized();M=Matrix.Translation(p)@Matrix.Rotation(math.radians(sign*112),4,axis)@Matrix.Translation(-p)
 for name in ['wing_'+role+'_fixed','aileron_'+role+'_hinge','flap_'+role+'_3_hinge']:
  o=bpy.data.objects[name];o.matrix_world=M@o.matrix_world
bpy.context.view_layer.update();render('wings_folded_112',(3,3,1.4),(0,-.5,.35),3.35)
for o in sorted(col.objects,key=depth):o.matrix_world=world_rest[o.name]
bpy.context.view_layer.update()
offset={'wing_left':(-.42,0,.08),'wing_right':(.42,0,.08),'horizontal_tail':(0,-.25,.26),'vertical_tail':(0,-.10,.40),'canopy':(0,0,.40),'engine':(0,.45,0),'propeller':(0,.72,0),'gear':(0,0,-.28)}
for o in sorted(col.objects,key=depth):
 M=world_rest[o.name].copy();M.translation+=Vector(offset.get(o.get('openrc_section'),(0,0,0)));o.matrix_world=M
bpy.context.view_layer.update();render('exploded_sections',(3.4,3.7,2.4),(0,-.4,.05),4.3)
(out/'views.json').write_text(json.dumps(rows,indent=2));print('G2_VIEWS_DONE',flush=True)
