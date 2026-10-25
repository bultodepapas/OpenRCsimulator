import bpy, numpy as np, sys
A=sys.argv[sys.argv.index("--")+1:]; names=A[0].split(","); out=A[1]
dg=bpy.context.evaluated_depsgraph_get(); V=[];T=[];off=0
for n in names:
    ob=bpy.data.objects[n]; ev=ob.evaluated_get(dg); me=ev.to_mesh(); me.calc_loop_triangles()
    v=np.array([tuple(ob.matrix_world@x.co) for x in me.vertices])*1000; t=np.array([tuple(l.vertices) for l in me.loop_triangles])+off
    V.append(v);T.append(t);off+=len(v); ev.to_mesh_clear()
np.savez(out,V=np.vstack(V),T=np.vstack(T)); print("SAVED",off)
