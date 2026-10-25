"""Comparable Eevee views. Render-time cameras and lights never enter the sources."""
import bpy,sys,math,json
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).parent))
import studio_world
studio_world.P=P
ids=[v for v in sys.argv[sys.argv.index('--')+1:]if not v.startswith('--')]if '--'in sys.argv else [l['id']for l in json.loads((P/'liveries.json').read_text())]
if not ids:ids=[l['id']for l in json.loads((P/'liveries.json').read_text())]
for lid in ids:
 name='aircraft_game'if lid=='midnight'else 'aircraft_'+lid
 bpy.ops.wm.open_mainfile(filepath=str(P/'source'/(name+'.blend')));S=bpy.context.scene;S.frame_set(0)
 S.render.engine='BLENDER_EEVEE';S.render.resolution_x=1920;S.render.resolution_y=1080;S.render.resolution_percentage=100;S.render.image_settings.file_format='PNG';S.render.film_transparent=False
 studio_world.chrome_world();S.view_settings.view_transform='AgX';S.view_settings.exposure=-.15
 for mat in bpy.data.materials:mat.use_backface_culling=True
 for name,loc,power,size in [('Key',(2,3,4),420,4),('Fill',(-3,0,2),300,3),('Rim',(1,-4,3),450,3),('Underside',(0,.5,-3),220,3)]:
  data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;o=bpy.data.objects.new(name,data);S.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,-.5,0))-o.location).to_track_quat('-Z','Y').to_euler()
 d=bpy.data.cameras.new('Preview');cam=bpy.data.objects.new('Preview',d);S.collection.objects.link(cam);S.camera=cam;d.clip_start=.003;d.clip_end=100;d.type='ORTHO'
 views=[('hero',(3,3.2,1.8),(0,-.45,-.05),4.15,0),('side',(-3,-.5,.14),(0,-.5,.05),3.1,0),('top',(0,-.60,4),(0,-.60,0),4.70,100),('underside',(2.3,2.5,-2),(0,-.5,-.08),4.15,100)]
 if '--top-only'in sys.argv:views=[v for v in views if v[0]=='top']
 dest=P/'previews'/lid;dest.mkdir(exist_ok=True)
 for view,loc,target,scale,frame in views:
  S.frame_set(frame);cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();d.ortho_scale=scale
  S.render.filepath=str(dest/(view+'.png'));bpy.ops.render.render(write_still=True);print('VIEW_COMPLETE',lid,view,flush=True)
