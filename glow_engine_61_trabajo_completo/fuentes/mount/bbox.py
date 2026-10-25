import bpy, json
from mathutils import Vector
dg=bpy.context.evaluated_depsgraph_get()
res={}
for ob in bpy.data.objects:
    if ob.type!='MESH': continue
    hid=any(c.hide_viewport or c.hide_render for c in ob.users_collection)
    ev=ob.evaluated_get(dg); me=ev.to_mesh()
    if not me.vertices: ev.to_mesh_clear(); continue
    vs=[ev.matrix_world@v.co for v in me.vertices]
    mn=[min(v[i] for v in vs)*1000 for i in range(3)]; mx=[max(v[i] for v in vs)*1000 for i in range(3)]
    res[ob.name]=(mn,mx,hid); ev.to_mesh_clear()
grp={}
for n,(mn,mx,h) in res.items():
    g=n.split('_')[0]+('_hidden' if h else '')
    if g not in grp: grp[g]=[mn[:],mx[:]]
    else:
        grp[g][0]=[min(a,b) for a,b in zip(grp[g][0],mn)]; grp[g][1]=[max(a,b) for a,b in zip(grp[g][1],mx)]
for g,(mn,mx) in grp.items(): print("GRP",g,[round(x,1) for x in mn],[round(x,1) for x in mx])
for n in sorted(res):
    if n.startswith(('MUF_Can','MUF_Arm','MUF_Flange','ENG_Crankcase','ENG_Backplate','ENG_Prop','ENG_Spinner','CARB_Body','ENG_Head','PIVOT')) or 'Needle' in n:
        mn,mx,h=res[n]; print(n,[round(x,1) for x in mn],[round(x,1) for x in mx],'hidden' if h else '')
print("OBJS",[o.name for o in bpy.data.objects if o.type!='MESH'][:40])
