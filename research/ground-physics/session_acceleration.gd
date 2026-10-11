# GP-04: full-session acceleration from actual static support; fixed neutral controls, no pilot tuning.
extends SceneTree
const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Fields := preload("res://data/field_loader.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Weather := preload("res://physics/wind_config.gd")
func _initialize() -> void:
	var support_path := ""
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--support="): support_path = arg.trim_prefix("--support=")
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	var supports: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(support_path))
	var rows: Array = []
	for sample: Dictionary in supports.aircraft:
		var path := ""
		for entry in Catalog.ENTRIES:
			if entry.id == sample.id: path = entry.data
		for surface in ["runway", "rough"]:
			for windy in [false, true]:
				var session := Session.new()
				session.setup(path)
				root.add_child(session)
				session.input_enabled = false
				session.crash_auto_restart = false
				session.set_field(Fields.load_from().field)
				var weather := Weather.defaults()
				weather.speed_mps = 5.0 if windy else 0.0
				weather.from_deg = 0.0
				if not session.setup_weather(weather):
					quit(1)
					return
				session.reset()
				var pose := PackedFloat64Array(sample.support[surface + "_east_state"])
				session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
				for i in 4: session.sim.aux[i] = 0.0
				session.sim.aux[0] = session.aircraft.model.propulsion.idle_rpm
				session.sim.reset(pose)
				session.sim.set_paused(false)
				session.sim.inputs[3] = 1.0
				var samples: Array = []
				for tick in 961:
					session._physics_process(session.sim.dt()) # same hull/travel crash checks as the app
					if tick % 120 == 0 or not session.crash.is_empty():
						var state: PackedFloat64Array = session.sim.state
						var eval := Ground.evaluate(state, session.aircraft.model.landing_gear, session.sim.aux[3],
							session.ground_surfaces, PackedFloat64Array(), session.sim.continuous.slice(session.wheel_index()))
						var normal := 0.0
						var contact_count := 0
						for wheel: Dictionary in eval.wheels:
							normal += wheel.normal_load
							if wheel.normal_load > 0.0: contact_count += 1
						samples.append({time_s = session.sim.time(), body_speed_mps = sqrt(state[3]*state[3]+state[4]*state[4]+state[5]*state[5]),
							north_m = state[0], east_m = state[1], altitude_m = -state[2], yaw_rate_radps = state[12],
							wheel_load_over_weight = normal / (session.sim.mass * session.sim.gravity), contacts = contact_count})
					if tick == 960 or not session.crash.is_empty(): break
					session.sim.step()
					if not session.sim.fault_reason.is_empty():
						printerr(session.sim.fault_reason)
						quit(1)
						return
				rows.append({aircraft = sample.id, surface = surface, crosswind_mps = weather.speed_mps,
					controls = "full throttle; zero roll/pitch/yaw; no stabilizing pilot", samples = samples,
					crashed = not session.crash.is_empty(), outcome = session.pause_reason, final_time_s = session.sim.time()})
				session.free()
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify({engine = Engine.get_version_info().string, aerodynamics = "full session", scenarios = rows}, "\t") + "\n")
	print("GP acceleration: ", rows.size(), " cases; outcomes are measurements, not pilot acceptance")
	quit()
