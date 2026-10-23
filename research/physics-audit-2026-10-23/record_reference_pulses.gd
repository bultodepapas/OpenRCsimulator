## FUEL-04-R1: four normal-rate pitch pulses for the isolated inertia comparison.
## Input timing/conditioning intentionally matches session_probe.gd.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const RB := preload("res://physics/rigid_body.gd")

var destination := ""
var stik_path := ""
var jet_path := ""
var failures := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			destination = arg.trim_prefix("--out=")
		elif arg.begins_with("--stik-baseline="):
			stik_path = arg.trim_prefix("--stik-baseline=")
		elif arg.begins_with("--jet-data="):
			jet_path = arg.trim_prefix("--jet-data=")
	if destination.is_empty() or stik_path.is_empty() or jet_path.is_empty():
		printerr("--out, --stik-baseline and --jet-data are required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	call_deferred("_run")


func _run() -> void:
	var report := {
		method = "Current solver; two explicit aircraft JSON inputs; 240 Hz; independent trim reset at 300 m; normal profile; signed pitch pulses from t=0.5 inclusive to 1.0 exclusive; trim throttle held; six seconds (1440 ticks).",
		solver_sha256 = Log.solver_identity(),
		aircraft = []
	}
	for pair in [["stik", stik_path], ["jet", jet_path]]:
		var session := Flight.new()
		session.setup(str(pair[1]))
		root.add_child(session)
		session.set_physics_process(false)
		session.sim.set_physics_process(false)
		session.radio.connected = false
		session.crash_auto_restart = false
		if not session.is_flyable():
			failures += 1
			printerr("Aircraft rejected: ", pair[1], " reason=", session.start_error)
			session.free()
			continue
		var model: Dictionary = session.aircraft.model
		var aircraft_result := {
			name = pair[0], path = pair[1], input_identity = session.aircraft.get("input_identity", {}),
			mass_kg = model.mass_kg, inertia_kgm2 = Array(model.inertia), cg_le_m = Array(model.cg_le),
			start_speed_mps = model.start_speed, rate_profile_available = model.controls.has("rates"), flights = []
		}
		for profile in ["normal"]:
			for axis in ["pitch"]:
				for direction in ([0.0] if axis == "neutral" else [-1.0, 1.0]):
					var case_result := _flight(session, str(pair[0]), profile, axis, direction)
					aircraft_result.flights.append(case_result)
		report.aircraft.append(aircraft_result)
		session.free()
	var result_path := destination.path_join("session-results.json")
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if file == null:
		failures += 1
		printerr("Cannot write session results: ", result_path)
	else:
		file.store_string(JSON.stringify(report, "\t", true, true))
		file.close()
	print("ALL_AXIS_PULSE_RECORDING_COMPLETE failures=", failures, " aircraft=", report.aircraft.size())
	quit(0 if failures == 0 else 1)


func _flight(session: Node, name_: String, profile: String, axis: String, direction: float) -> Dictionary:
	session.rate_profile = profile
	session.trim_at(float(session.aircraft.model.start_speed))
	session.set_start_altitude(300.0)
	session.reset()
	session.read_raw = func() -> Dictionary:
		var sample := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
		if axis != "neutral" and session.sim.time() >= 0.5 and session.sim.time() < 1.0:
			sample[axis] = direction
		return sample
	var case_name := _case_name(name_, profile, axis, direction)
	var recording_path := destination.path_join(case_name + ".orfl")
	var recorder := Log.new(session)
	if recorder.start(recording_path) != OK:
		failures += 1
		printerr("Could not start recorder for ", case_name)
		return {name = case_name, completed = false, error = "recorder start failed"}
	recorder.mark("independent reset; " + profile + " rates; " + axis + " pulse=" + str(direction) + " from 0.5 to 1 s")
	var row := {
		name = case_name, profile = profile, axis = axis, direction = direction, duration_s = 6.0,
		max_rate_deg_s = [0.0, 0.0, 0.0], alpha_abs_max_deg = 0.0, beta_abs_max_deg = 0.0,
		airspeed_min_mps = INF, altitude_min_m = INF, max_abs_normal_load_g = 0.0,
		finite = true
	}
	for tick in 1440:
		session._physics_process(session.sim.dt())
		if session.sim.paused:
			break
		session.sim.step()
		var state: PackedFloat64Array = session.sim.state
		var air: Dictionary = session.air_data(state)
		for value in state:
			row.finite = row.finite and is_finite(value)
		for at in 3:
			row.max_rate_deg_s[at] = maxf(row.max_rate_deg_s[at], absf(rad_to_deg(state[RB.RATE + at])))
		row.alpha_abs_max_deg = maxf(row.alpha_abs_max_deg, absf(rad_to_deg(air.alpha)))
		row.beta_abs_max_deg = maxf(row.beta_abs_max_deg, absf(rad_to_deg(air.beta)))
		row.airspeed_min_mps = minf(row.airspeed_min_mps, air.V)
		row.altitude_min_m = minf(row.altitude_min_m, -state[2])
		row.max_abs_normal_load_g = maxf(row.max_abs_normal_load_g,
			absf(session.sim.last_loads[2] / (session.sim.mass * session.sim.gravity)))
		if not row.finite or not session.sim.fault_reason.is_empty() or not session.crash.is_empty():
			break
	recorder.mark("end of prescribed six-second observation")
	if recorder.stop("all-axis catalog pulse finished") != OK:
		failures += 1
	row.completed = session.sim.tick == 1440 and row.finite and session.sim.fault_reason.is_empty() and session.crash.is_empty()
	row.final_tick = session.sim.tick
	row.final_state = Array(session.sim.state)
	row.fault_reason = session.sim.fault_reason
	row.crash = session.crash
	row.recording = recording_path
	if not row.completed:
		failures += 1
	print("PULSE_CASE_COMPLETE ", case_name, " completed=", row.completed, " tick=", row.final_tick,
		" fault=", row.fault_reason, " crash=", row.crash)
	return row


func _case_name(name_: String, profile: String, axis: String, direction: float) -> String:
	var suffix := "neutral" if axis == "neutral" else ("negative" if direction < 0.0 else "positive")
	return name_ + "-" + profile + "-" + axis + "-" + suffix
