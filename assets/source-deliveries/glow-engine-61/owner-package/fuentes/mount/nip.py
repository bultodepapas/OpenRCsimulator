import bpy, numpy as np
dg=bpy.context.evaluated_depsgraph_get()
for n in ("CARB_Fuel_Nipple","MUF_Pressure_Nipple","ENG_Cylinder_Fins","ENG_Crankcase"):
    ob=bpy.data.objects[n]; ev=ob.evaluated_get(dg); me=ev.to_mesh()
    P=np.array([tuple(ev.matrix_world@v.co) for v in me.vertices])*1000; ev.to_mesh_clear()
    c=P.mean(0); w,V=np.linalg.eigh(np.cov((P-c).T)); ax=V[:,-1]
    t=(P-c)@ax
    print(n, "centre",c.round(2),"axis",ax.round(3),"extent",t.min().round(2),t.max().round(2), "bbox",P.min(0).round(1),P.max(0).round(1))
    if "Nipple" in n:
        for end in (t.max(), t.min()):
            sel=P[np.abs(t-end)<1.0]; rad=np.linalg.norm((sel-c)-np.outer((sel-c)@ax,ax),axis=1)
            print("   end",round(end,2),"pt",(c+ax*end).round(2),"r max",rad.max().round(2))
        # radius profile along axis
        for s in np.linspace(t.min(),t.max(),9):
            sel=P[np.abs(t-s)<0.5]
            if len(sel): print("   s",round(s,2),"r",np.linalg.norm((sel-c)-np.outer((sel-c)@ax,ax),axis=1).max().round(2))
