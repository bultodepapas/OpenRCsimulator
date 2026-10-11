# Static and cost screens for synthetic candidates. No physical acceptance thresholds.
extends SceneTree
const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Fixture := preload("res://tests/wing_polar_fixture.gd")
const Session := preload("res://sim/flight_session.gd")
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}


func state(alpha: float, p := 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(0,0,-300),M.v3(25*cos(alpha),0,25*sin(alpha)),M.q_identity(),M.v3(p,0,0))


func loads(model: Dictionary, alpha: float, p := 0.0) -> PackedFloat64Array:
	var s := state(alpha,p)
	return Aero.loads(s,Air.compute(s,M.v3(0,0,0)),ZERO,model,1.225)


func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://../docs/research/flight-robustness/D8b-R2/implementation")
	DirAccess.make_dir_recursive_absolute(folder)
	var report := {format = "openrc-polar-candidate-screen v1", engine = Engine.get_version_info().string,
		kind = "synthetic static and shared-host cost evidence; not aircraft validation", models = []}
	for name in ["legacy", "steep", "intermediate", "retained"]:
		var path: String = Fixture.PATH if name == "legacy" else "res://../research/flight-robustness/d8b-r2/candidates/%s.json" % name
		var data := AD.load_file(path)
		if not data.ok:
			printerr(data.errors)
			quit(1)
			return
		var model: Dictionary = data.model
		var record := {name = name, aircraft_sha256 = data.input_identity.sha256,
			maximum_cl = -INF, minimum_cl = INF, max_roll_derivative = -INF, max_roll_derivative_alpha_deg = 0.0, rows = []}
		for k in range(-900,901):
			var alpha := deg_to_rad(k/10.0)
			var value := loads(model,alpha)
			var cl: float = (value[0]*sin(alpha)-value[2]*cos(alpha))/(0.5*1.225*625.0*float(model.reference.S))
			var dp := 1e-5
			var derivative := (loads(model,alpha,dp)[3]-loads(model,alpha,-dp)[3])/(2.0*dp)
			if not is_finite(cl) or not is_finite(derivative):
				quit(1)
				return
			record.maximum_cl = maxf(record.maximum_cl,cl)
			record.minimum_cl = minf(record.minimum_cl,cl)
			if derivative > record.max_roll_derivative:
				record.max_roll_derivative = derivative
				record.max_roll_derivative_alpha_deg = k/10.0
			if k % 5 == 0:
				record.rows.append({alpha_deg = k/10.0, total_cl = cl, roll_nm_per_radps = derivative})
		# Same evolving 5 s abrupt pull work per sample; record every repetition, no timing assertion.
		var session := Session.new()
		session.setup(path)
		root.add_child(session)
		session.input_enabled = false
		session.sim.set_physics_process(false)
		session.set_physics_process(false)
		var costs: Array = []
		for repetition in 4:
			session.set_start_altitude(300.0)
			session.reset()
			var start := Time.get_ticks_usec()
			for tick in 1200:
				session.commands.pitch = 1.0 if tick >= 60 and tick < 540 else 0.0
				session.sim.inputs = session._inputs()
				session.sim.step()
			if repetition > 0:
				costs.append(float(Time.get_ticks_usec()-start)/1200.0)
			record.final_state = Array(session.sim.state)
			record.tick_count = session.sim.tick
			if not session.sim.fault_reason.is_empty() or session.sim.tick != 1200:
				quit(1)
				return
		record.whole_tick_us = costs
		session.free()
		report.models.append(record)
		print("%s: CL [%s,%s], maximum dMx/dp %s, whole tick us %s" % [name,record.minimum_cl,record.maximum_cl,record.max_roll_derivative,costs])
	var file := FileAccess.open(folder.path_join("candidate-screen.json"),FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report,"  ",true,true)+"\n")
	file.close()
	quit(0)
