"""Eevee F1-F4 acceptance photographs. Temporary lighting only; never saves model."""
import bpy,math,json,sys
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parents[2];R=P.parent;S=bpy.context.scene
rows=[]
def setup(path):
 global S,cam
 bpy.ops.wm.open_mainfile(filepath=str(path));S=bpy.context.scene;S.frame_set(0)
 S.render.engine='BLENDER_EEVEE';S.render.resolution_x=1920;S.render.resolution_y=1080;S.render.resolution_percentage=100;S.render.image_settings.file_format='PNG'
 S.render.film_transparent=False;S.world=bpy.data.worlds.new('G21 Inspection');S.world.use_nodes=True
 bg=next(n for n in S.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.16,.19,.24,1);bg.inputs['Strength'].default_value=.45
 S.view_settings.view_transform='AgX';S.view_settings.exposure=.4
 for m in bpy.data.materials:m.use_backface_culling=True
 for name,loc,power,size in [('Key',(2,3,4),650,4),('Fill',(-3,0,2),500,3),('Rim',(1,-4,3),700,3),('Underside',(0,.5,-3),240,3)]:
  d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;o=bpy.data.objects.new(name,d);S.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,-.5,0))-o.location).to_track_quat('-Z','Y').to_euler()
 d=bpy.data.cameras.new('Inspection');cam=bpy.data.objects.new('Inspection',d);S.collection.objects.link(cam);S.camera=cam;d.lens=48;d.clip_start=.002;d.clip_end=100
def shot(name,loc,target,ortho=None):
 cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO'if ortho else 'PERSP'
 if ortho:cam.data.ortho_scale=ortho
 S.render.filepath=str(P/'previews'/(name+'.png'));bpy.ops.render.render(write_still=True)
 rows.append({'name':name,'file':name+'.png','frame':S.frame_current,'camera':list(loc),'target':list(target),'distance_m':(Vector(loc)-Vector(target)).length,'ortho_width':ortho,'Eevee_backface_culling':True});print('G21_VIEW',name,flush=True)
for rev in ['g1_24','g2_0','g2_1']:
 setup(R/rev/'source/aircraft_game.blend')
 for part,side in [('main_wheel','left'),('tail_wheel','tail')]:
  o=bpy.data.objects['gear_wheel_'+side];target=o.matrix_world.translation.copy();camera=target+Vector((-.40,.22,.10))
  shot(rev+'_'+part,camera,target,.37 if side=='left'else .18)
 if rev!='g2_1':continue
 shot('home_ground',(3.,3.2,1.8),(0,-.45,-.05),4.2)
 target=Vector((0,.48,.02));direction=Vector((1,1.22,.53)).normalized();shot('nose_1_5m',target+direction*1.5,target)
 shot('blade_front',(0,1.4,.31),(0,.4527,.31),.56)
 shot('blade_back',(0,-.25,.31),(0,.4527,.31),.56)
 shot('blade_tip_front',(0,1.0,.423),(0,.4527,.423),.14)
 shot('blade_tip_back',(0,-.05,.423),(0,.4527,.423),.14)
 shot('canopy_close',(-1.15,.1,.9),(0,-.53,.15),1.14)
 shot('underside_down',(2.3,2.5,-2.),(0,-.5,-.08),4.2)
(P/'previews/views.json').write_text(json.dumps(rows,indent=2));print('G21_VIEWS_COMPLETE',flush=True)
