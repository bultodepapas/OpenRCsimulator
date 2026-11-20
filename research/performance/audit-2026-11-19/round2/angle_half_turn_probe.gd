extends SceneTree
const M=preload("res://physics/math3d.gd")
const RB=preload("res://physics/rigid_body.gd")
const FC=preload("res://physics/multirotor/flight_controller.gd")

func _initialize() -> void:
 var cfg: Dictionary={angle_max_tilt=deg_to_rad(55),angle_gain=6.0,angle_rate_limit=deg_to_rad(400)}
 var observations:=[]
 for q in [PackedFloat64Array([0,1,0,0]),PackedFloat64Array([0,-1,0,0]),PackedFloat64Array([1e-10,1,0,0]),PackedFloat64Array([-1e-10,-1,0,0])]:
  var body:=RB.make_state(M.v3(0,0,-5),M.v3(0,0,0),q,M.v3(0,0,0))
  observations.append({q=Array(q),rotated_up=Array(M.q_rotate(q,M.v3(0,0,-1))),heading=FC.heading(q),target=Array(FC._angle_rate_target(cfg,body,0,0))})
 print("HALF_TURN_CASES ",JSON.stringify(observations))
 if observations[0].rotated_up==observations[1].rotated_up and observations[0].target[0] == -observations[1].target[0] and observations[0].target[0]!=0 and observations[2].target[0]==observations[3].target[0]:
  print("half-turn representation dependence reproduced")
  quit(0)
 else:
  print("half-turn representation dependence not reproduced")
  quit(1)
