"""Read uncompressed glTF node transforms without modifying the Blender scene."""
from mathutils import Matrix,Quaternion,Vector
import math
import struct
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
def world_matrices(g):
 parents={child:i for i,n in enumerate(g['nodes']) for child in n.get('children',[])};cache={}
 def visit(i):
  if i in cache:return cache[i]
  n=g['nodes'][i]
  if 'matrix' in n:M=Matrix([n['matrix'][j:j+4] for j in range(0,16,4)]).transposed()
  else:
   q=n.get('rotation',[0,0,0,1]);M=Matrix.LocRotScale(Vector(n.get('translation',[0,0,0])),Quaternion((q[3],*q[:3])),Vector(n.get('scale',[1,1,1])))
  cache[i]=visit(parents[i])@M if i in parents else M
  return cache[i]
 return {n['name']:C.inverted()@visit(i)@C for i,n in enumerate(g['nodes'])}
def compare(g,objects):
 actual=world_matrices(g);errors=[];maxpos=maxangle=0.
 for o in objects:
  if o.name not in actual:errors.append({'missing':o.name});continue
  M=actual[o.name];d=(M.translation-o.matrix_world.translation).length
  q=M.to_quaternion().rotation_difference(o.matrix_world.to_quaternion());a=abs((q.angle+math.pi)%(2*math.pi)-math.pi)
  maxpos=max(maxpos,d);maxangle=max(maxangle,math.degrees(a))
  if d>.0001 or a>math.radians(.01):errors.append({'node':o.name,'position_error_m':d,'angle_error_degrees':math.degrees(a)})
 return {'passed':not errors,'max_position_error_m':maxpos,'max_angle_error_degrees':maxangle,'errors':errors}
def geometry_bounds(g,data):
 worlds=world_matrices(g);inverse=C.inverted();start=28+struct.unpack_from('<I',data,12)[0];bounds={}
 for node in g['nodes']:
  if 'mesh' not in node:continue
  points=[]
  for primitive in g['meshes'][node['mesh']]['primitives']:
   a=g['accessors'][primitive['attributes']['POSITION']];view=g['bufferViews'][a['bufferView']]
   assert a['componentType']==5126 and a['type']=='VEC3' and 'sparse' not in a
   offset=start+view.get('byteOffset',0)+a.get('byteOffset',0);stride=view.get('byteStride',12)
   points.extend(worlds[node['name']]@inverse@Vector(struct.unpack_from('<3f',data,offset+i*stride)) for i in range(a['count']))
  bounds[node['name']]={'min':[min(v[j] for v in points) for j in range(3)],'max':[max(v[j] for v in points) for j in range(3)]}
 return bounds
