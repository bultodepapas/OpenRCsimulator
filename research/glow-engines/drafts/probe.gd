extends SceneTree
const AD=preload("res://physics/aircraft_data.gd")
const Op=preload("res://physics/glow/operating_point.gd")
const Sc=preload("res://sim/scenarios.gd")
func _initialize():
	for id in ["55ax_2t","fs64v_4t"]:
		var data=AD.load_file("res://data/aircraft/stik_glow_"+id+".json")
		print(id,": ",data.ok," ",data.errors)
		if data.ok:
			for throttle in [0.,.2,.5,1.]:
				print(throttle," ",Op.solve(data.model.propulsion,throttle,0.,1.225,1.225))
			for speed in [17.,20.,23.]:
				print("trim ",speed," ",Sc.trimmed_level_across_view(data.model,9.80665,data.model.controls.throw_rad,speed,1.225,1.).ok)
	quit()
