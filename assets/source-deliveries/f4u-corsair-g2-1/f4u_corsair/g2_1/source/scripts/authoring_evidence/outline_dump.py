import bpy,numpy as np,json
from pathlib import Path
R=Path(__file__).parents[2];W=Path(__file__).parent
result={}
for rev in ['g2_0','g2_1']:
 bpy.ops.wm.open_mainfile(filepath=str(R/rev/'source/aircraft_game.blend'));bpy.context.scene.frame_set(0)
 for part in ['propeller_rotor','canopy_glass']:
  o=bpy.data.objects[part];me=o.data;me.calc_loop_triangles();v=np.array([o.matrix_world@p.co for p in me.vertices])
  for region in (['hub','blades']if part=='propeller_rotor'else['glass']):
   t=np.array([p.vertices[:]for p in me.loop_triangles if part!='propeller_rotor' or (me.materials[p.material_index].name=='alloy')==(region=='hub')]);result[rev+'_'+region+'_v']=v;result[rev+'_'+region+'_t']=t
np.savez_compressed(W/'outlines.npz',**result)
print('OUTLINES_DUMPED',flush=True)
