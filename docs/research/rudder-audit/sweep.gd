# Research only: variants are fresh, in-memory aircraft dictionaries. No production files change.
# $(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/rudder-audit/sweep.gd"
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Recorder := preload("res://sim/recorder.gd")

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _metrics(trace: RefCounted) -> Dictionary:
	var out := { beta_peak_deg = 0.0, alpha_peak_deg = 0.0, roll_peak_deg = 0.0, r_peak_deg_s = 0.0, p_peak_deg_s = 0.0, servo_peak = 0.0 }
	for row in trace.row_count():
		var u: float = trace.value(row, "u_mps")
		var v: float = trace.value(row, "v_mps")
		var w: float = trace.value(row, "w_mps")
		out.beta_peak_deg = maxf(out.beta_peak_deg, absf(rad_to_deg(atan2(v, sqrt(u*u + w*w)))))
		out.alpha_peak_deg = maxf(out.alpha_peak_deg, absf(rad_to_deg(atan2(w, u))))
		out.roll_peak_deg = maxf(out.roll_peak_deg, absf(trace.value(row, "roll_deg")))
		out.r_peak_deg_s = maxf(out.r_peak_deg_s, absf(rad_to_deg(trace.value(row, "r_radps"))))
		out.p_peak_deg_s = maxf(out.p_peak_deg_s, absf(rad_to_deg(trace.value(row, "p_radps"))))
		out.servo_peak = maxf(out.servo_peak, absf(trace.value(row, "srv_yaw")))
	var last: int = trace.row_count() - 1
	out.altitude_loss_m = trace.value(0, "alt_m") - trace.value(last, "alt_m")
	out.r_final_deg_s = rad_to_deg(trace.value(last, "r_radps"))
	out.servo_final = trace.value(last, "srv_yaw")
	return out

func _fly(case: Dictionary) -> Dictionary:
	var session := Session.new()
	session.setup()
	root.add_child(session)
	session.set_process_input(false)
	var model: Dictionary = session.aircraft.model
	if case.has("coefficient"):
		model.aero[case.coefficient] *= case.factor
	if case.has("throw"):
		model.controls.throw_deg.rudder = case.throw
		model.controls.throw_rad.rudder = deg_to_rad(case.throw)
	if case.get("linear", false):
		model.envelope = {}
	if case.get("no_gyro", false):
		model.propulsion.rotor_inertia = 0.0
	assert(session.trim_at(case.get("speed", 15.0), case.get("mode", "level")).ok)
	session.reset()
	var device: String = case.get("device", "direct")
	session.input_enabled = device != "direct"
	if device == "radio":
		session.radio.connect_device(99, {name = "EdgeTX diagnostic", guid = "diagnostic"})
		session.radio.on_motion(99, 2, -1.0)
		session.radio.poll(func(_id: int, axis: int) -> float: return -1.0 if axis == 2 else 0.0, session.sim.dt())
	var rec := Recorder.new(session.sim)
	rec.start({case_name = case.name})
	for tick in 720:
		var t: float = session.sim.time()
		var yaw := 0.0
		if t >= 0.5 and t < 1.0:
			yaw = case.get("amplitude", 1.0)
		elif t >= 1.0 and t < 1.5 and not case.get("single", false):
			yaw = -case.get("amplitude", 1.0)
		if device == "keyboard":
			_key(KEY_D, yaw > 0.0)
			_key(KEY_A, yaw < 0.0)
			session._physics_process(session.sim.dt())
		elif device == "radio":
			var throttle: float = 2.0 * session.start.throttle - 1.0
			session.read_axis = func(_id: int, axis: int) -> float: return yaw if axis == 3 else (throttle if axis == 2 else 0.0)
			session._physics_process(session.sim.dt())
		else:
			session.commands = {roll = 0.0, pitch = 0.0, yaw = yaw, throttle = session.start.throttle}
			session.sim.inputs = session._inputs()
		session.sim.step()
	_key(KEY_D, false)
	_key(KEY_A, false)
	rec.detach()
	var result := _metrics(rec.trace)
	result.merge(case)
	var out := OS.get_environment("RUDDER_AUDIT_OUT")
	if not out.is_empty():
		assert(rec.trace.save(out.path_join(case.name + ".csv")) == OK)
	session.free()
	return result

func _initialize() -> void:
	Input.use_accumulated_input = false
	var cases := [
		{name = "baseline"}, {name = "repeat"},
		{name = "single", single = true}, {name = "left", amplitude = -1.0},
		{name = "quarter", amplitude = 0.25}, {name = "half", amplitude = 0.5},
		{name = "keyboard", device = "keyboard"}, {name = "radio", device = "radio"},
		{name = "linear", linear = true}, {name = "no_gyro", no_gyro = true},
		{name = "glide", mode = "glide"},
		{name = "Cndr_050", coefficient = "Cndr", factor = 0.5},
		{name = "Cndr_040", coefficient = "Cndr", factor = 0.4},
		{name = "Cndr_030", coefficient = "Cndr", factor = 0.3},
		{name = "Cnb_200", coefficient = "Cnb", factor = 2.0},
		{name = "Cnr_200", coefficient = "Cnr", factor = 2.0},
		{name = "throw_10", throw = 10.0},
		{name = "speed_12", speed = 12.0}, {name = "speed_20", speed = 20.0},
	]
	var results := []
	for case in cases:
		var result := _fly(case)
		results.append(result)
		print("RUDDER_CASE ", JSON.stringify(result))
	var out := OS.get_environment("RUDDER_AUDIT_OUT")
	if not out.is_empty():
		var file := FileAccess.open(out.path_join("results.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({engine = Engine.get_version_info().string, cases = results}, "\t") + "\n")
	quit()
