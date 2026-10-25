import bpy, sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree
a_name, b_name = sys.argv[sys.argv.index("--")+1:][:2]
eps = 0.0002
def tris(ob):
    me = ob.data; me.calc_loop_triangles(); mw = ob.matrix_world
    V = [mw @ v.co for v in me.vertices]
    T = [tuple(t.vertices) for t in me.loop_triangles]
    return V, T
Va, Ta = tris(bpy.data.objects[a_name]); Vb, Tb = tris(bpy.data.objects[b_name])
bvh = BVHTree.FromPolygons(Vb, Tb, epsilon=0.0)
hits = []
for t in Ta:
    a,b,c = (Va[i] for i in t); n = (b-a).cross(c-a)
    if n.length < 1e-12: continue
    n.normalize(); cen = (a+b+c)/3
    for loc, nb, idx, d in bvh.find_nearest_range(cen, eps):
        if abs(n.dot(nb)) > 0.999: hits.append((tuple(round(x*1000,2) for x in cen), tuple(round(x,2) for x in n), n.dot(nb) > 0))
print("hits", len(hits))
for h in hits[:15]: print(h)
