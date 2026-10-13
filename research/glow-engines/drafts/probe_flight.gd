extends SceneTree
const F=preload("res://sim/flight_session.gd")
func _initialize():
	for id in ["55ax_2t","fs64v_4t"]:
		var f=F.new()
		f.setup("res://data/aircraft/stik_glow_"+id+".json")
		f.input_enabled=false
		print(id," flyable=",f.is_flyable()," ",f.sim.fault_reason)
		if f.is_flyable():
			print("initial ",f.glow_state())
			for i in 480:
				if i==120:f.sim.inputs[3]=1.
				if i==360:f.engine_running=false
				f.sim.step()
				if not f.sim.fault_reason.is_empty():break
			print("end tick ",f.sim.tick," ",f.sim.fault_reason," ",f.sim.continuous)
		f.free()
	quit()
