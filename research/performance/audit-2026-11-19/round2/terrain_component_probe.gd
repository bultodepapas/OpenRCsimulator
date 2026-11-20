extends SceneTree
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Data = preload("res://physics/multirotor_data.gd")
const Plant = preload("res://physics/multirotor/controlled_plant.gd")
const Rates = preload("res://physics/multirotor/rates.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
const Track = preload("res://physics/ground_vehicle/airfield_track.gd")

func _initialize() -> void:
 var source := Data.load_file("res://data/multirotors/openrc-fpv5-x1.json")
 if not source.ok:
  print("LOAD_FAILURE ",source.errors); quit(1); return
 var doc := Data.prepare(source.data,source.sha256)
 if not doc.ok:
  print("PREP_FAILURE ",doc.errors); quit(1); return
 var built := Plant.create(doc.prepared,Rates.default_profile(),FC.THROTTLE_ABSOLUTE)
 if not built.ok:
  print("PLANT_FAILURE ",built.errors); quit(1); return
 var track_out := Track.load_default()
 if not track_out.ok:
  print("TRACK_FAILURE ",track_out); quit(1); return
 var track: Dictionary=track_out.track
 track.ramps[0].height_m=1.2
 track.ramps[0].approach_m=0.1
 print("TRACK_VALID ",Track.valid(track))
 var p: RefCounted = built.plant
 p.ground = func(n: float,e: float) -> PackedFloat64Array:
  var s := Track.sample(track,n,e)
  return PackedFloat64Array([s.height_m,s.dn,s.de])
 var north := 39.0
 var east := -4.327
 var center: PackedFloat64Array = p.ground.call(north,east)
 var q:=M.q_identity()
 var axis:=M.q_rotate(q,M.v3(0,0,-1))
 var lowest:=M.sub(M.v3(0,0,1),M.scale(axis,axis[2]))
 var cases:=[]
 for height in [0.59,0.7]:
  var position:=M.v3(north,east,-center[0]-float(height))
  var body:=RB.make_state(position,M.v3(0,0,0),q,M.v3(0,0,0))
  var deepest: float=-INF
  var deep_point:=PackedFloat64Array()
  for point in p._points:
   var g: PackedFloat64Array=p.ground.call(north+point[0],east+point[1])
   var depth: float=position[2]+point[2]+g[0]
   if depth>deepest:
    deepest=depth
    deep_point=point
  var rotor_witnesses:=[]
  for i in 4:
   if p._disc_in_ground(i,position,q,axis,lowest,M.norm(lowest)): rotor_witnesses.append(i)
  var values:=PackedFloat64Array([1000,1000,1000,1000])
  var forces: Dictionary=p._contact_loads(body,q,M.v3(0,0,0),M.v3(0,0,0))
  var reason: String=p.crash_reason(body,body,values)
  var frame: Dictionary=p.initial_frame(body)
  for i in 4: frame.continuous[i]=1000
  var out: Dictionary={body=body.duplicate(),continuous=frame.continuous.duplicate(),events=[],reason=""}
  p._graded_ground(body,out,0.0)
  cases.append({height_above_cg_ground_m=height,body=Array(body),max_point_depth_m=deepest,deep_point=Array(deep_point),rotor_witnesses=rotor_witnesses,force=Array(forces.force),moment=Array(forces.moment),strict_crash_reason=reason,graded_health=Array(out.continuous.slice(Plant.C_HEALTH,Plant.C_HEALTH+4)),graded_events=out.events})
 print("TERRAIN_CENTER ",center)
 print("TERRAIN_CASES ",JSON.stringify(cases))
 var near: Dictionary=cases[0]
 var far: Dictionary=cases[1]
 if Track.valid(track) and near.max_point_depth_m>0 and far.max_point_depth_m>0 and near.rotor_witnesses.size()>0 and far.rotor_witnesses.size()>0 and near.force!=[0.0,0.0,0.0] and far.force==[0.0,0.0,0.0] and near.strict_crash_reason=="Propeller strike" and far.strict_crash_reason.is_empty():
  print("terrain early-out reproduced")
  quit(0)
 else:
  print("terrain witness not established")
  quit(1)
