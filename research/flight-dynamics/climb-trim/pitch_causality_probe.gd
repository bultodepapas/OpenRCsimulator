# Recorded-input power interventions and pitch-moment accounting. No production data writes.
extends SceneTree
const Session := preload("res://sim/flight_session.gd")
const Weather := preload("res://physics/wind_config.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Aero := preload("res://physics/aero.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("ugly-loop-inputs.json")))
	var samples := {}
	for row: Dictionary in source.samples:
		samples[int(row.tick)] = row
	var reports: Array = []
	for cap: float in [1.0, 0.85, 0.75, 0.5]:
		var session := Session.new()
		assert(session.setup_weather(Weather.GENTLE_PRACTICE))
		session.setup("res://data/aircraft/jensen_ugly_stik_60.json", "jensen-das-ugly-stik-60")
		root.add_child(session)
		session.set_physics_process(false)
		session.sim.set_physics_process(false)
		session.radio.connected = false
		var raw := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
		session.read_raw = func() -> Dictionary: return raw.duplicate()
		session.rate_profile = "normal"
		var rows: Array = []
		var first_inverted := -1.0
		var max_error := 0.0
		var max_moment_closure := 0.0
		var max_height := 30.0
		for tick in range(1, 3601):
			if samples.has(tick):
				# Dictionaries are shared: update the closure's original dictionary.
				for key: String in raw.keys():
					raw[key] = samples[tick].raw[key]
			session._physics_process(session.sim.dt())
			if session.sim.paused:
				break
			if session.commands.throttle > cap:
				session.commands.throttle = cap
				session.sim.inputs = session._inputs()
			session.sim.step()
			var s: PackedFloat64Array = session.sim.state
			max_height = maxf(max_height, -s[2])
			if first_inverted < 0.0 and M.q_rotate(RB._att(s), M.v3(0.0, 0.0, 1.0))[2] < 0.0:
				first_inverted = session.sim.time()
			if cap == 1.0 and samples.has(tick) and samples[tick].has("state"):
				for k in s.size():
					max_error = maxf(max_error, absf(s[k] - float(samples[tick].state[k])))
			if tick % 60 != 0:
				continue
			var model: Dictionary = session.aircraft.model
			var d: Dictionary = session._deflections(session.sim.aux)
			var lag: int = session.downwash_index()
			var cl_lag: float = session.sim.aux[lag] if lag >= 0 else NAN
			var e := Dynamics.evaluate(s, model, d, session.sim.aux[0], session.air_density(), session.wind_at(session.sim.time()), session.sim.gravity, PackedFloat64Array(), cl_lag)
			var a: Dictionary = model.aero
			var ref: Dictionary = model.reference
			var scale: float = e.air.qbar * ref.S * ref.c
			var global := Aero._global_loads(s, e.air, d, model, session.air_density(), cl_lag)
			var no_lag := Aero._global_loads(s, e.air, d, model, session.air_density())
			var arm := M.v3(-(ref.arp_le[0] - model.cg_le[0]), ref.arp_le[1] - model.cg_le[1], -(ref.arp_le[2] - model.cg_le[2]))
			var terms := {zero = scale * a.Cm0, alpha = scale * a.Cma * e.air.alpha,
				elevator = scale * a.Cmde * d.elevator, ailerons = scale * a.Cmda_each * (d.aileron_right + d.aileron_left),
				pitch_rate = 0.25 * session.air_density() * e.air.V * ref.c * ref.c * ref.S * a.Cmq * s[RB.RATE + 1],
				force_arm = arm[2] * no_lag[0] - arm[0] * no_lag[2], downwash = global[4] - no_lag[4],
				propulsion = e.propulsion_loads[4]}
			var reconstructed := 0.0
			for term: float in terms.values():
				reconstructed += term
			var blend: float = Aero.local_flow_weight(s, e.air, d, model, cl_lag)
			if blend == 0.0:
				max_moment_closure = maxf(max_moment_closure, absf(reconstructed - e.loads[4]))
			rows.append({time_s = session.sim.time(), throttle = session.commands.throttle, speed_mps = e.air.V,
				alpha_deg = rad_to_deg(e.air.alpha), pitch_deg = rad_to_deg(M.q_to_euler(RB._att(s))[1]), height_m = -s[2],
				pitch_rate_rad_s = s[RB.RATE + 1], pitch_accel_rad_s2 = e.derivative[RB.RATE + 1],
				blend = blend, total_pitch_moment_nm = e.loads[4], attached_pitch_terms_nm = terms,
				raw_pitch = raw.pitch, elevator_deg_up = -rad_to_deg(d.elevator), thrust_n = e.propulsion_loads[0]})
		reports.append({throttle_cap = cap, seconds = session.sim.time(), first_inverted_s = first_inverted,
			max_height_m = max_height, source_checkpoint_error = max_error if cap == 1.0 else null,
			attached_pitch_moment_closure_nm = max_moment_closure, fault = session.sim.fault_reason, crashed = not session.crash.is_empty(), rows = rows})
		session.free()
	print("PITCH_CAUSALITY ", JSON.stringify(reports))
	quit(0 if reports[0].source_checkpoint_error < 1e-8 else 1)
