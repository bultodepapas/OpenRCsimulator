"""Open and export a relocated two-file copy, then re-import the GLB in Blender.
Run with Blender -b --python this_script.py. No master is read.
"""
import bpy,json,hashlib,shutil,tempfile,runpy,math,struct
import numpy as np
from pathlib import Path
from mathutils import Matrix
P=Path(__file__).resolve().parents[2];M=json.loads((P/'metadata.json').read_text())
root=Path(tempfile.mkdtemp(prefix='g2_standalone_'))
(root/'source/scripts').mkdir(parents=True);(root/'export').mkdir()
shutil.copy2(P/'source/aircraft_game.blend',root/'source/aircraft_game.blend')
shutil.copy2(P/'source/scripts/export_g2.py',root/'source/scripts/export_g2.py')
bpy.ops.wm.open_mainfile(filepath=str(root/'source/aircraft_game.blend'))
packed=[im.name for im in bpy.data.images if im.packed_file]
assert len(packed)==M['runtime_image_count'] and not bpy.data.libraries
assert all(im.packed_file for im in bpy.data.images if im.source=='FILE')
runpy.run_path(str(root/'source/scripts/export_g2.py'),run_name='__main__')
new_hash=hashlib.sha256((root/'export/aircraft.glb').read_bytes()).hexdigest()
def chunks(path):
 raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];return json.loads(raw[20:20+n]),raw[28+n:]
ja,ba=chunks(P/'export/aircraft.glb');jb,bb=chunks(root/'export/aircraft.glb')
assert ja==jb,'Exported glTF hierarchy/material/accessor metadata changed'
tangents={p['attributes']['TANGENT'] for m in ja['meshes'] for p in m['primitives'] if 'TANGENT' in p['attributes']}
formats={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'};sizes={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16};tangent_delta=0.;tangent_values=0
for i,ac in enumerate(ja['accessors']):
 v=ja['bufferViews'][ac['bufferView']];off=v.get('byteOffset',0)+ac.get('byteOffset',0);n=ac['count']*sizes[ac['type']];x=np.frombuffer(ba,dtype=formats[ac['componentType']],count=n,offset=off);y=np.frombuffer(bb,dtype=formats[ac['componentType']],count=n,offset=off)
 if i in tangents:
  delta=float(np.max(np.abs(x.astype(float)-y)));tangent_delta=max(tangent_delta,delta);tangent_values+=int((x!=y).sum());assert delta<=.00011,(i,delta)
 else:assert np.array_equal(x,y),('Changed non-tangent accessor',i)
for im in ja['images']:
 v=ja['bufferViews'][im['bufferView']];off=v.get('byteOffset',0);n=v['byteLength'];assert ba[off:off+n]==bb[off:off+n]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/'export/aircraft.glb'))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];triangles=0
for o in meshes:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
expected=M['nodes'];names={o.name for o in bpy.context.scene.objects}
assert names==set(expected),(names-set(expected),set(expected)-names)
max_delta=0.
for name,node in expected.items():
 o=bpy.data.objects[name];e=Matrix(node['rest_matrix_blender'])
 max_delta=max(max_delta,max(abs(o.matrix_world[r][c]-e[r][c])for r in range(4)for c in range(4)))
 assert (o.parent.name if o.parent else None)==node['parent']
 assert o.get('openrc_section')==node['section']
assert max_delta<1e-5,max_delta
verts=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
span=max(v.x for v in verts)-min(v.x for v in verts)
assert abs(span-M['span_m'])<.0001,(span,M['span_m'])
assert triangles==M['triangle_count']
r={'passed':True,'test':'Relocated native with packed maps plus export script only; clean Blender GLB import','R59_used':False,'runtime_map_count':len(packed),'reexport_glb_sha256':new_hash,'delivered_glb_sha256':M['glb_sha256'],'byte_identical':new_hash==M['glb_sha256'],'geometry_UV_normals_indices_images_and_JSON_identical':True,'tangent_max_component_difference':tangent_delta,'tangent_values_differing':tangent_values,'tangent_note':'Bundled MikkTSpace export can round a few tangent components differently across processes; tolerance 0.00011. All positions, normals, UVs, indices, images and glTF JSON must be exact.','reimport_meshes':len(meshes),'reimport_triangles':triangles,'reimport_span_m':span,'reimport_max_matrix_element_delta':max_delta,'isolated_directory':str(root)}
(P/'checks/standalone_reexport.json').write_text(json.dumps(r,indent=2));print('STANDALONE_PASS',r,flush=True)
