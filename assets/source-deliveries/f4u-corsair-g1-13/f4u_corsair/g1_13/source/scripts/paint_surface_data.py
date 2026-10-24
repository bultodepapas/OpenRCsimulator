"""Refresh paint sampling data with smooth corner normals; does not change meshes or UVs. Paint design coordinates use the original 1:5 design space (world x 0.9), while delivered geometry remains 1:4.5."""
import bpy,json
from pathlib import Path
P=Path(__file__).resolve().parents[2];S=bpy.context.scene;col=bpy.data.collections['EXPORT_aircraft'];S.frame_set(100);bpy.context.view_layer.update();closed={o.name:o.matrix_world.copy()for o in col.objects if o.type=='MESH'};S.frame_set(0);bpy.context.view_layer.update();records=[]
for o in col.objects:
 if o.type!='MESH'or not any(m and m.name.startswith('paint_')for m in o.data.materials):continue
 o.data.calc_loop_triangles();M=closed[o.name] if o.name.startswith('gear_door_') else o.matrix_world;N=M.to_3x3();triangles=[]
 for t in o.data.loop_triangles:
  p=o.data.polygons[t.polygon_index]
  if not o.data.materials[p.material_index].name.startswith('paint_'):continue
  normals=[list((N@o.data.corner_normals[l].vector).normalized())for l in t.loops]
  triangles.append({'uv':[list(o.data.uv_layers['UVMap'].data[l].uv)for l in t.loops],'xyz':[list((M@o.data.vertices[v].co)*0.9)for v in t.vertices],'normal':list(N@t.normal),'normals':normals,'door_inner':o.name.startswith('gear_door_')and(closed[o.name].to_3x3()@t.normal).z>0})
 records.append({'name':o.name,'triangles':triangles})
(P/'source/scripts/uv-layout.json').write_text(json.dumps(records));print('SMOOTH_PAINT_SAMPLING',len(records),flush=True)
