import bpy, math
ob=bpy.data.objects["ENG_Crankcase"]; me=ob.data
print("MW", [round(x,4) for x in ob.matrix_world.translation], len(me.vertices))
pts=[tuple(c*1000 for c in (ob.matrix_world@v.co)) for v in me.vertices]
sel=[p for p in pts if 22<p[0]<30 and 10<p[1]<19 and abs(p[2]-0.3)<0.2]
import statistics
ring=[p for p in sel if 1.5<math.hypot(p[0]-26,p[1]-14.5)<2.3 or 1.5<math.hypot(p[0]-25.5,p[1]-14.0)<2.3]
for c in ((26,14.5),(25.5,14.0)):
    d=[math.hypot(p[0]-c[0],p[1]-c[1]) for p in sel]
    near=[x for x in d if x<2.6]
    print("C",c,"n",len(near),"r",round(min(near),3) if near else None, round(max(near),3) if near else None)
