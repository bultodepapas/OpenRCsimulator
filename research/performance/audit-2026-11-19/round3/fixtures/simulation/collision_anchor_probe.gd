extends SceneTree
const C := preload("res://sim/scenery_collision.gd")
const RB := preload("res://physics/rigid_body.gd")
var failures := 0
func check(label:String, condition:bool, detail:String="") -> void:
 print(("ok " if condition else "FAIL ")+label+" "+detail)
 if not condition: failures += 1
func state(n:float) -> PackedFloat64Array:
 var s:=PackedFloat64Array(); s.resize(13)
 s[RB.POS]=n; s[RB.POS+2]=-4.0; s[RB.VEL]=10.0; s[RB.ATT]=1.0
 return s
func box(id:String, north:float, east:float, hx:float) -> Dictionary:
 return {id=id,kind="test_box",part="face",shape="box",radius=0.0,half_length=0.0,response_class="hard_terminal",damage_id="",damage_profile="none",north=north,east=east,down=-4.0,half_x=hx,half_down=1.0,half_z=1.0,sin_heading=0.0,cos_heading=1.0,bounds_north_min=north-1.0,bounds_north_max=north+1.0,bounds_east_min=east-hx,bounds_east_max=east+hx,bounds_down_min=-5.0,bounds_down_max=-3.0}
func world(delta:float) -> Dictionary:
 var proxies: Array=[box("a_box",1.0+5.0/240.0+delta,0.25,0.1),box("z_box",1.0+5.0/240.0,0.0,0.5)]
 var bins:Dictionary={}
 for n in [-1,0]:
  for e in [-1,0]:
   for d in [-1,0]: bins["%d,%d,%d" % [n,e,d]]=PackedInt64Array([0,1])
 return {format="openrc-collision-world v1",cell_size_m=32.0,proxies=proxies,bins=bins}
func _initialize() -> void:
 var s0:=state(0); var s1:=state(10.0/240.0); var inertia:=PackedFloat64Array([1,1,1,0,0,0]);
 var p0:=PackedFloat64Array([0.0,0.25,0]); var p1:=PackedFloat64Array([0.75e-12*10.0/240.0,-0.25,0]); var both:=p0.duplicate(); both.append_array(p1)
 var w:=world(0.75e-12*10.0/240.0)
 var hit0:=C.contacts(s0,s1,p0,w,1,2.0,inertia); var hit1:=C.contacts(s0,s1,p1,w,1,2.0,inertia); var all:=C.contacts(s0,s1,both,w,1,2.0,inertia)
 check("individual point sweeps yield two hits and one hit", hit0.size()==2 and hit1.size()==1 and all.size()==2)
 if hit0.size()==2 and hit1.size()==1 and all.size()==2:
  var a:C.Event; var z0:C.Event
  for hit:C.Event in hit0:
   if hit.obstacle_id=="a_box": a=hit
   else: z0=hit
  var z1:C.Event=hit1[0]
  print("WITNESS z1=%.15f z0=%.15f a=%.15f local_delta=%.15f global_delta=%.15f" % [z1.time_fraction,z0.time_fraction,a.time_fraction,z0.time_fraction-z1.time_fraction,a.time_fraction-z1.time_fraction])
  print("WITNESS ordered first=%s/%d second=%s/%d" % [all[0].obstacle_id,all[0].point_index,all[1].obstacle_id,all[1].point_index])
  check("global anchor places A outside tie window",z0.time_fraction-z1.time_fraction <= C.FRACTION_TIE and a.time_fraction-z1.time_fraction > C.FRACTION_TIE)
  check("per-obstacle reduction selects out-of-window A",all[0].obstacle_id=="a_box" and all[1].obstacle_id=="z_box" and all[1].point_index==0)
 var far:=C.contacts(s0,s1,both,world(4.0e-12*10.0/240.0),1,2.0,inertia)
 check("control: wider gap returns z",far.size()==2 and far[0].obstacle_id=="z_box")
 print("COLLISION_ANCHOR_COMPLETE failures=%d" % failures)
 quit(1 if failures else 0)
