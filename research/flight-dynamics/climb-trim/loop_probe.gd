# Actual user-input replay and controlled counterfactuals; never changes aircraft data.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Weather = preload("res://physics/wind_config.gd")
const Aero = preload("res://physics/aero.gd")
const Dynamics = preload("res://physics/dynamics.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
var raw := {roll=0.0,pitch=0.0,yaw=0.0,throttle=0.0}
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("ugly-loop-inputs.json")))
	var samples := {}
	for row: Dictionary in source.samples: samples[int(row.tick)] = row
	var cases: Array = ["actual", "calm", "trim22", "trim25", "half", "quarter", "neutral"]
	if "--isolate-trim" in OS.get_cmdline_user_args(): cases = ["manual22at5", "no_gyro"]
	if "--replay-only" in OS.get_cmdline_user_args(): cases = ["actual"]
	for case in cases:
		var session = Session.new()
		if case != "calm": assert(session.setup_weather(Weather.GENTLE_PRACTICE))
		session.setup("res://data/aircraft/jensen_ugly_stik_60.json", "jensen-das-ugly-stik-60")
		root.add_child(session)
		session.set_physics_process(false)
		session.sim.set_physics_process(false)
		session.radio.connected = false
		session.read_raw = func() -> Dictionary: return raw.duplicate()
		session.rate_profile = "normal"
		var correction_deg := 0.0
		if case == "manual22at5":
			var old_start: Dictionary = session.start.duplicate(true)
			var old_trims: Dictionary = session.trims.duplicate(true)
			var target: Dictionary = session.trim_at(22.0)
			assert(target.ok)
			correction_deg = (float(target.pitch_command) - float(old_trims.pitch)) * 20.0
			session.start = old_start
			session.trims = old_trims
		if case == "no_gyro": session.aircraft.model.propulsion.rotor_inertia = 0.0
		if case.begins_with("trim"):
			assert(session.trim_at(22.0 if case == "trim22" else 25.0).ok)
			session.reset()
		var initial_power: float = session.commands.throttle
		var max_error := 0.0
		var max_q := 0.0
		var inverted_ticks := 0
		var max_height := 30.0
		var rows: Array = []
		raw = {roll=0.0,pitch=0.0,yaw=0.0,throttle=0.0}
		for tick in range(1, int(source.last_tick) + 1):
			if case == "manual22at5" and tick == 1201: assert(session.adjust_elevator_trim(correction_deg))
			if samples.has(tick): raw = samples[tick].raw
			if case in ["half", "quarter", "neutral"]:
				raw = {roll=0.0,pitch=0.0,yaw=0.0,throttle=0.0}
				session.commands.throttle = 0.5 if case == "half" else (0.25 if case == "quarter" else initial_power)
			session._physics_process(session.sim.dt())
			if session.sim.paused: break
			session.sim.step()
			var state: PackedFloat64Array = session.sim.state
			max_q = maxf(max_q, absf(state[11]))
			max_height = maxf(max_height, -state[2])
			if M.q_rotate(RB._att(state),M.v3(0,0,1))[2] < 0.0: inverted_ticks += 1
			if case == "actual" and samples.has(tick) and samples[tick].has("state"):
				for i in state.size(): max_error = maxf(max_error, absf(state[i]-float(samples[tick].state[i])))
			if tick % 240 == 0:
				var air: Dictionary = session.air_data(state,session.sim.time())
				var d: Dictionary = session._deflections(session.sim.aux)
				var components: Dictionary = Dynamics.evaluate(state,session.aircraft.model,d,session.sim.aux[0],session.air_density(),session.wind_at(session.sim.time()),session.sim.gravity)
				rows.append({t=session.sim.time(),height=-state[2],speed=air.V,alpha_deg=rad_to_deg(air.alpha),pitch_deg=rad_to_deg(M.q_to_euler(RB._att(state))[1]),q=state[11],blend=Aero.local_flow_weight(state,air,d,session.aircraft.model),throttle=session.commands.throttle,trim=session.trims.pitch,aero=Array(components.aero_loads),prop=Array(components.propulsion_loads)})
		if case == "actual" and (max_error > 1e-8 or session.sim.tick != int(source.last_tick)):
			printerr("Observed replay mismatch: ", max_error, " tick ", session.sim.tick)
			quit(1)
			return
		print("LOOP_RESULT ",JSON.stringify({case=case,seconds=session.sim.time(),completed=session.sim.tick == int(source.last_tick),fault=session.sim.fault_reason,crashed=not session.crash.is_empty(),initial_power=initial_power,trim_deg=session.trims.pitch*20.0,max_q=max_q,inverted_seconds=inverted_ticks*session.sim.dt(),max_height=max_height,max_state_error=max_error,rows=rows}))
		session.free()
	quit()
