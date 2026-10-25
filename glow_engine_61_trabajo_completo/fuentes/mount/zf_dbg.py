import bpy, sys
from mathutils.bvhtree import BVHTree
from mathutils import Vector
names=sys.argv[sys.argv.index("--")+1].split(",")
eps=0.0002
dg=bpy.context.evaluated_depsgraph_get()
verts=[];tris=[];meta=[]
for oi,n in enumerate(names):
    ob=bpy.data.objects[n]; ev=ob.evaluated_get(dg); me=ev.to_mesh(); me.calc_loop_triangles()
    off=len(verts); verts+= [ob.matrix_world@v.co for v in me.vertices]
    for t in me.loop_triangles:
        tris.append(tuple(i+off for i in t.vertices)); a,b,c=(verts[i] for i in tris[-1]); meta.append((oi,(b-a).cross(c-a).normalized()))
    ev.to_mesh_clear()
bvh=BVHTree.FromPolygons(verts,tris)
def pit(q,a,b,c,n):
    for p0,p1 in ((a,b),(b,c),(c,a)):
        if (p1-p0).cross(q-p0).dot(n)<-1e-12: return False
    return True
cnt=0
for ti,t in enumerate(tris):
    a,b,c=(verts[i] for i in t); n=meta[ti][1]; cen=(a+b+c)/3
    for p in (cen, cen.lerp(a,.6), cen.lerp(b,.6), cen.lerp(c,.6)):
        for _,_,tj,_ in bvh.find_nearest_range(p,eps):
            if tj is None or tj==ti or set(t)&set(tris[tj]): continue
            n2=meta[tj][1]; d=n.dot(n2)
            if d<0.999: continue
            a2,b2,c2=(verts[i] for i in tris[tj]); q=p-n2*n2.dot(p-a2)
            if pit(q,a2,b2,c2,n2):
                cnt+=1
                if cnt<12: print("ZF", names[meta[ti][0]], (cen*1000).to_tuple(2), (n).to_tuple(2), names[meta[tj][0]], ((a2+b2+c2)/3*1000).to_tuple(2))
print("count",cnt)
