extends SceneTree
const M=preload("res://physics/math3d.gd")
const RB=preload("res://physics/rigid_body.gd")
const Track=preload("res://physics/ground_vehicle/airfield_track.gd")
const Fields=preload("res://data/field_loader.gd")
const Session=preload("res://sim/multirotor/session.gd")
const FC=preload("res://physics/multirotor/flight_controller.gd")
const Plant=preload("res://physics/multirotor/controlled_plant.gd")

func _initialize() -> void:
 _run.call_deferred()

func _run() -> void:
 var track_out:=Track.load_default()
 var field_out:=Fields.load_from()
 if not track_out.ok or not field_out.ok:
  print("ADMISSION FAILURE ",track_out," ",field_out); quit(1); return
 var track: Dictionary=track_out.track
 track.ramps[0].height_m=1.2
 track.ramps[0].approach_m=0.1
 print("ADMISSION track_valid=",Track.valid(track)," field_match=",Track.matches_field(field_out.field))
 var observations:=[]
 var all_ok:=true
 for mode in ["strict","graded"]:
  var s:=Session.new()
  root.add_child(s)
  var setup: bool=s.prepare(field_out.field,{rc_track=track,start="air",altitude_m=0.7,north_offset_m=39.0,east_offset_m=-4.327,crash_model=mode})
  if not setup:
   print("SESSION PREP REFUSED ",s.load_error)
   all_ok=false
   s.free()
   continue
  var body: PackedFloat64Array=s.sim.state.duplicate()
  var q:=RB._att(body)
  var p: RefCounted=s.plant
  var position:=RB._slice3(body,RB.POS)
  var axis:=M.q_rotate(q,M.v3(0,0,-1))
  var lowest:=M.sub(M.v3(0,0,1),M.scale(axis,axis[2]))
  var center: PackedFloat64Array=p.ground.call(position[0],position[1])
  var deepest: float=-INF
  var deep_point:=PackedFloat64Array()
  for point in p._points:
   var off:=M.q_rotate(q,point)
   var ground: PackedFloat64Array=p.ground.call(position[0]+off[0],position[1]+off[1])
   var depth: float=position[2]+off[2]+ground[0]
   if depth>deepest:
    deepest=depth
    deep_point=point
  var rotor_hits:=[]
  for i in 4:
   if p._disc_in_ground(i,position,q,axis,lowest,M.norm(lowest)): rotor_hits.append(i)
  var loads: Dictionary=p._contact_loads(body,q,RB._slice3(body,RB.VEL),RB._slice3(body,RB.RATE))
  var initial_rate: PackedFloat64Array=s.sim.continuous.slice(0,4)
  var reason: String=p.crash_reason(body,body,s.sim.continuous)
  var substeps: int=p.substeps(body,s.sim.continuous,0)
  var global_bound: float=s.environment.ground_max_height()
  var resume_ok:=s.resume()
  var ok:=s.tick_once(FC.neutral_input())
  var row: Dictionary={mode=mode,prepared=setup,initial_body=Array(body),rotor_speeds=Array(initial_rate),cg_ground=Array(center),cg_clearance_m=-position[2]-center[0],global_ground_max=global_bound,point_depth_m=deepest,point=Array(deep_point),rotor_hits=rotor_hits,contact_force=Array(loads.force),strict_crash_reason=reason,substeps=substeps,resumed=resume_ok,advanced=ok,tick=s.sim.tick,crash=s.crash,fault=s.fault_reason,post_health=Array(s.sim.continuous.slice(Plant.C_HEALTH,Plant.C_HEALTH+4))}
  observations.append(row)
  all_ok=all_ok and setup and deepest>0 and rotor_hits.size()>0 and loads.force==PackedFloat64Array([0,0,0]) and reason.is_empty() and substeps==1 and resume_ok and ok and s.sim.tick==1 and s.crash.is_empty() and s.fault_reason.is_empty()
  s.free()
 print("SESSION_TERRAIN_CASES ",JSON.stringify(observations))
 if all_ok and observations.size()==2:
  print("session terrain early-out reproduced")
  quit(0)
 else:
  print("session terrain witness not established")
  quit(1)
