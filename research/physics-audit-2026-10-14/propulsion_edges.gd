## Independent lead probes of propulsion joins and point-velocity kinematics.
extends SceneTree
const Data := preload("res://physics/aircraft_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Turbine := preload("res://physics/turbine.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

func _initialize() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty():
		quit(1)
		return
	var jet: Dictionary = Data.load_file("res://data/aircraft/sebart_avanti_s_a200.json")
	var stik: Dictionary = Data.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	if not jet.ok or not stik.ok:
		quit(1)
		return
	var report := {crossflow_join = [], intake_point_velocity = [], stopped_propeller = []}
	var prop: Dictionary = jet.model.propulsion
	for rpm in [float(prop.idle_rpm), float(prop.max_rpm)]:
		for lateral in [true, false]:
			for u in [-0.001, -0.000001, 0.0, 0.000001, 0.001]:
				var flow := M.v3(u, 20.0 if lateral else 0.0, 0.0 if lateral else 20.0)
				var loads := Turbine.loads(flow, rpm, prop, 1.225)
				report.crossflow_join.append({rpm = rpm, flow_mps = Array(flow), loads_n_nm = Array(loads)})
	var r_structural: PackedFloat64Array = prop.intake_offset
	var r_body := M.v3(-r_structural[0], r_structural[1], -r_structural[2])
	var zero_controls := {aileron_left = 0.0, aileron_right = 0.0, elevator = 0.0, rudder = 0.0}
	for q in [-2.0, 0.0, 2.0]:
		var velocity := M.v3(29.0, 0.0, 0.0)
		var omega := M.v3(0.0, q, 0.0)
		var state := RB.make_state(M.v3(0,0,-300), velocity, M.quat(1,0,0,0), omega)
		var evaluated := Dynamics.evaluate(state, jet.model, zero_controls, prop.max_rpm, 1.225, M.v3(0,0,0), 9.80665)
		var local_velocity := M.add(velocity, M.cross(omega, r_body))
		var cg_flow: float = Turbine.mass_flow(prop.max_rpm, prop, 1.225, velocity[0])
		# Kinematic isolation: keep the mass-flow scalar fixed. This is a missing momentum
		# term under the CURRENT inlet model, not a validated replacement engine model.
		var missing_force := M.scale(M.sub(local_velocity, velocity), -cg_flow)
		report.intake_point_velocity.append({q_rad_s = q, intake_body_m = Array(r_body),
			cg_velocity_mps = Array(velocity), inlet_velocity_mps = Array(local_velocity),
			actual_propulsion_loads_n_nm = Array(evaluated.propulsion_loads),
			kinematic_ram_correction_n = Array(missing_force),
			kinematic_ram_correction_nm = Array(M.cross(r_body, missing_force))})
	for speed in [0.0, 15.0, 30.0]:
		for rpm in [0.0, 0.999, 1.0, 1.001, 2800.0]:
			report.stopped_propeller.append({speed_mps = speed, rpm = rpm,
				loads_n_nm = Array(Propulsion.loads(M.v3(speed,0,0), rpm, stik.model.propulsion, 1.225))})
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("PROPULSION_EDGES_COMPLETE ", output)
	quit(0)
