## Read-only audit of current production aircraft, controls and load callbacks.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var destination := ""
var failures := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			destination = arg.trim_prefix("--out=")
	if destination.is_empty():
		printerr("--out is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	call_deferred("_run")

func _run() -> void:
	var report := {method = "Current unmodified data; native 240 Hz live keyboard sampler; each independent case resets trim at 300 m; 0.5 s pulse from t=0.5 to 1.0, then released; trim throttle held.", aircraft = []}
	for pair in [["stik", "res://data/aircraft/jensen_ugly_stik_60.json"], ["jet", "res://data/aircraft/sebart_avanti_s_a200.json"]]:
		var s := Flight.new()
		s.setup(pair[1])
		root.add_child(s)
		s.set_physics_process(false)
		s.sim.set_physics_process(false)
		s.radio.connected = false
		s.crash_auto_restart = false
		if not s.is_flyable():
			failures += 1
			printerr("Aircraft rejected: ", pair[1])
			s.free()
			continue
		var model: Dictionary = s.aircraft.model
		var result := {name = pair[0], path = pair[1], mass_kg = model.mass_kg,
			inertia_kgm2 = Array(model.inertia), cg_le_m = Array(model.cg_le),
			start_speed_mps = model.start_speed, reference = model.reference,
			controls = model.controls, has_slipstream = not model.propulsion.get("slipstream", {}).is_empty(),
			shaft_integrator = s.shaft_integrator(), turbine_continuous = s.turbine_is_continuous(),
			static_control_authority = _authority(model), altitude_samples = [], flights = []}
		for altitude in [50.0, 500.0, 1000.0]:
			s.set_start_altitude(altitude)
			s.reset()
			result.altitude_samples.append({altitude_m = altitude, rho_kgm3 = s.air_density(),
				gravity_mps2 = s.sim.gravity, loads_n_nm = Array(s.sim.last_loads)})
		for profile in ["normal", "full"]:
			for axis in ["neutral", "roll", "pitch", "yaw"]:
				for direction in ([0.0] if axis == "neutral" else [-1.0, 1.0]):
					var case_result := _flight(s, str(pair[0]), profile, axis, direction)
					result.flights.append(case_result)
		report.aircraft.append(result)
		s.free()
	var file := FileAccess.open(destination.path_join("session-results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("SESSION_PROBE_COMPLETE failures=", failures)
	quit(0 if failures == 0 else 1)

func _authority(model: Dictionary) -> Array:
	var rows: Array = []
	var neutral := {aileron_left = 0.0, aileron_right = 0.0, elevator = 0.0, rudder = 0.0}
	for speed in [0.0, 5.0, 15.0, 29.0]:
		var state := RB.make_state(M.v3(0, 0, -300), M.v3(speed, 0, 0), M.quat(1, 0, 0, 0), M.v3(0, 0, 0))
		for rpm in [0.0, float(model.propulsion.max_rpm)]:
			var base := Dynamics.loads(state, model, neutral, rpm, 1.225, M.v3(0, 0, 0))
			for axis in ["elevator", "rudder"]:
				var deflected: Dictionary = neutral.duplicate()
				deflected[axis] = deg_to_rad(10.0)
				var loads := Dynamics.loads(state, model, deflected, rpm, 1.225, M.v3(0, 0, 0))
				var delta: Array = []
				for at in 6: delta.append(loads[at] - base[at])
				rows.append({speed_mps = speed, rpm = rpm, control = axis, deflection_deg = 10.0,
					delta_loads_n_nm = delta, baseline_loads_n_nm = Array(base)})
	return rows

func _flight(s: Node, name_: String, profile: String, axis: String, direction: float) -> Dictionary:
	s.rate_profile = profile
	s.trim_at(float(s.aircraft.model.start_speed))
	s.set_start_altitude(300.0)
	s.reset()
	s.read_raw = func() -> Dictionary:
		var sample := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
		if axis != "neutral" and s.sim.time() >= 0.5 and s.sim.time() < 1.0:
			sample[axis] = direction
		return sample
	var should_record := profile == "normal" and axis == "yaw" and direction == 1.0
	var recorder := Log.new(s)
	if should_record:
		if recorder.start(destination.path_join(name_ + "-normal-yaw.orfl")) != OK:
			failures += 1
		recorder.mark("independent reset; keyboard normal rates; right rudder from 0.5 to 1 s")
	var row := {profile = profile, axis = axis, direction = direction, duration_s = 6.0,
		max_rate_deg_s = [0.0, 0.0, 0.0], alpha_abs_max_deg = 0.0, beta_abs_max_deg = 0.0,
		airspeed_min_mps = INF, altitude_min_m = INF, max_abs_normal_load_g = 0.0,
		finite = true, samples = []}
	for tick in 1440:
		s._physics_process(s.sim.dt())
		if s.sim.paused: break
		s.sim.step()
		var state: PackedFloat64Array = s.sim.state
		var air: Dictionary = s.air_data(state)
		for value in state: row.finite = row.finite and is_finite(value)
		for at in 3: row.max_rate_deg_s[at] = maxf(row.max_rate_deg_s[at], absf(rad_to_deg(state[RB.RATE + at])))
		row.alpha_abs_max_deg = maxf(row.alpha_abs_max_deg, absf(rad_to_deg(air.alpha)))
		row.beta_abs_max_deg = maxf(row.beta_abs_max_deg, absf(rad_to_deg(air.beta)))
		row.airspeed_min_mps = minf(row.airspeed_min_mps, air.V)
		row.altitude_min_m = minf(row.altitude_min_m, -state[2])
		row.max_abs_normal_load_g = maxf(row.max_abs_normal_load_g, absf(s.sim.last_loads[2] / (s.sim.mass * s.sim.gravity)))
		if tick % 12 == 0:
			row.samples.append({tick = s.sim.tick, state = Array(state), inputs = Array(s.sim.inputs),
				surfaces_deg = s.surface_angles_deg(), alpha_deg = rad_to_deg(air.alpha), beta_deg = rad_to_deg(air.beta),
				airspeed_mps = air.V})
		if not row.finite or not s.sim.fault_reason.is_empty() or not s.crash.is_empty(): break
	if should_record:
		recorder.mark("end of prescribed six-second observation")
		if recorder.stop("audit case finished") != OK: failures += 1
	row.completed = s.sim.tick == 1440 and row.finite and s.sim.fault_reason.is_empty() and s.crash.is_empty()
	row.final_tick = s.sim.tick
	row.final_state = Array(s.sim.state)
	row.fault_reason = s.sim.fault_reason
	if not row.completed: failures += 1
	var brief: Dictionary = row.duplicate()
	brief.erase("samples")
	print(name_, " ", JSON.stringify(brief))
	return row
