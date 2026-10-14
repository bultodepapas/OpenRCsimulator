## Direct Cartesian limits: two paths approaching the same pure-spanwise flow.
extends SceneTree
const Data := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

func _initialize() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty():
		quit(1)
		return
	var report := {method = "No propulsion, zero rates, zero controls, rho=1.225. Each pair approaches the identical Cartesian velocity [0,20,0] from [epsilon,20,0] and [0,20,epsilon]. No trigonometric velocity construction.", aircraft = []}
	var controls := {aileron_left = 0.0, aileron_right = 0.0, elevator = 0.0, rudder = 0.0}
	for path in ["res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/sebart_avanti_s_a200.json"]:
		var data: Dictionary = Data.load_file(path)
		if not data.ok:
			printerr("LOAD_FAIL ", path)
			quit(1)
			return
		var rows: Array = []
		for epsilon in [0.01, 0.0001, 0.000001, 0.000000001, 0.0]:
			for direction in ["forward", "down"]:
				var velocity := M.v3(epsilon if direction == "forward" else 0.0, 20.0, epsilon if direction == "down" else 0.0)
				var state := RB.make_state(M.v3(0,0,-300), velocity, M.quat(1,0,0,0), M.v3(0,0,0))
				var air := Air.compute(state, M.v3(0,0,0), 1.225)
				var loads := Aero.loads(state, air, controls, data.model, 1.225)
				var wings := PackedFloat64Array([0,0,0,0,0,0])
				var strips := Aero.wing_strip_loads(state, air, controls, data.model, 1.225)
				for strip in strips:
					for at in 3:
						wings[at] += strip.force_body_n[at]
						wings[3 + at] += strip.moment_body_nm[at]
				rows.append({epsilon_mps = epsilon, approach = direction, velocity_mps = Array(velocity),
					alpha_rad = air.alpha, beta_rad = air.beta, blend = Aero.local_flow_weight(state, air, controls, data.model),
					total_loads_n_nm = Array(loads), wing_loads_n_nm = Array(wings),
					mechanical_power_w = loads[0]*velocity[0]+loads[1]*velocity[1]+loads[2]*velocity[2]})
		report.aircraft.append({id = data.model.id, input_sha256 = data.input_identity.sha256, rows = rows})
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("AERO_EDGES_COMPLETE ", output)
	quit(0)
