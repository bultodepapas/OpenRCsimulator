import bpy
dg=bpy.context.evaluated_depsgraph_get()
for ob in sorted(bpy.data.objects,key=lambda o:o.name):
    if ob.type=='MESH' and ob.name.startswith(('CARB_','MUF_')) and not any(c.hide_viewport for c in ob.users_collection):
        ev=ob.evaluated_get(dg); me=ev.to_mesh(); vs=[ev.matrix_world@v.co for v in me.vertices]
        mn=[round(min(v[i] for v in vs)*1000,1) for i in range(3)]; mx=[round(max(v[i] for v in vs)*1000,1) for i in range(3)]
        print("N",ob.name,mn,mx); ev.to_mesh_clear()
# muffler can section near firewall
import bmesh
ob=bpy.data.objects['MUF_Can']; ev=ob.evaluated_get(dg); me=ev.to_mesh()
for y0 in (30,40,44,50,53,60,70,90):
    zs=[ (ev.matrix_world@v.co) for v in me.vertices]
    sel=[v for v in zs if abs(v.y*1000-y0)<2.0]
    if sel: print("SEC y",y0,"zmin",round(min(v.z for v in sel)*1000,1),"xmax",round(max(v.x for v in sel)*1000,1), "xmin", round(min(v.x for v in sel)*1000,1))
