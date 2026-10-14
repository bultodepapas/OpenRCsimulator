extends SceneTree
const V = preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const D = preload("res://physics/ground_vehicle/vehicle_data.gd")
const M = preload("res://physics/math3d.gd")
func road(_n:float,_e:float)->Dictionary:
	return {"height_m":0.0,"normal_ned":PackedFloat64Array([0.0,0.0,-1.0]),"mu":0.85,"rolling":1.0,"surface_id":"flat"}
func _initialize():
	var base:Dictionary=D.load_default().model
	for fade in [60.0,80.0,100.0]:
		var model:Dictionary=base.duplicate(true)
		model.drive_torque_fade_rad_s=fade
		var state:PackedFloat64Array=V.initialize(model,road,0.0,0.0).state
		for i in 1440:state=V.step(state,model,{"throttle":1.0,"steering":0.0,"brake":0.0,"reverse":false},1.0/240,road)
		var entry:PackedFloat64Array=state.duplicate()
		for brake in [0.4,0.6,0.75,1.0]:
			state=entry.duplicate()
			var yaw_max:=0.0
			var min_up:=1.0
			var tick:=0
			for i in 1440:
				tick=i+1
				state=V.step(state,model,{"throttle":0.0,"steering":0.0,"brake":brake,"reverse":false},1.0/240,road)
				if state.size()!=31:quit(1);return
				var q:=state.slice(6,10)
				yaw_max=maxf(yaw_max,absf(M.q_to_euler(q)[0]))
				min_up=minf(min_up,-M.q_rotate(q,PackedFloat64Array([0.0,0.0,-1.0]))[2])
				if M.norm(state.slice(3,6))<0.1:break
			print(JSON.stringify({"fade":fade,"entry_mps":entry[3],"brake":brake,"peak_yaw_deg":rad_to_deg(yaw_max),"min_up":min_up,"stop_s":tick/240.0,"residual_mps":M.norm(state.slice(3,6))}))
	quit(0)
