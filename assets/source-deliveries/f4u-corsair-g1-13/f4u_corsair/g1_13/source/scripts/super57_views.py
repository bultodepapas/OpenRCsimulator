"""Racing-specific inspection: source, moving parts and actual exported GLB."""
import bpy,sys,math,json
from pathlib import Path
from mathutils import Matrix,Vector
P=Path(__file__).resolve().parents[2]
runtime='--runtime' in sys.argv
if runtime:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(P/'export/aircraft_super57.glb'))
setup=(P/'source/scripts/preview.py').read_text().split('for name,loc in')[0]
exec(compile(setup,str(P/'source/scripts/preview.py'),'exec'))
base_render=render
def render(name,loc):
 if '--beauty-only' in sys.argv and name not in {'super57_rear','super57_front','super57_flaps40'}:return
 base_render(name,loc)
S.cycles.samples=40;S.render.resolution_x=1500;S.render.resolution_y=1050
try:S.view_settings.look='AgX - Medium High Contrast'
except TypeError:pass
area('racing_belly',(0,1,-3),140,3)
if runtime:
 S.frame_set(100)
 render('super57_runtime',(3,-3,1.6))
 area('runtime_belly_key',(-2,1,-4),210,4)
 render('super57_runtime_underside',(-3,2,-3))
 print('SUPER57_RUNTIME_VIEWS_DONE',flush=True)
else:
 S.frame_set(100)
 render('super57_rear',(3,-3,1.8))
 target=Vector((.0,-.89,.015))*K;d.ortho_scale=1.18*K
 render('super57_identity',(-4,-.90,.25))
 target=Vector((0,-.52,-.02))*K;d.ortho_scale=3.3*K
 render('super57_front',(3,4,2.5))
 for f in (0,50,100):
  S.frame_set(f);target=Vector((.40,-.25,-.20))*K;d.ortho_scale=.95*K
  render('super57_doors_'+str(f),(1.3,.8,-1.1))
 S.frame_set(0)
 meta=json.loads((P/'metadata.json').read_text())
 rest={a['node']:bpy.data.objects[a['node']].matrix_basis.copy()for a in meta['articulations'] if a['node'].startswith('flap_')}
 for n,M in rest.items():bpy.data.objects[n].matrix_basis=M@Matrix.Rotation(math.radians(40),4,'X')
 target=Vector((0,-.52,-.02))*K;d.ortho_scale=3.3*K
 render('super57_flaps40',(3,-3,1.6))
 for n,M in rest.items():bpy.data.objects[n].matrix_basis=M
 print('SUPER57_SOURCE_VIEWS_DONE',flush=True)
