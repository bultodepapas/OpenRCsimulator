extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const FlightLogRecorder := preload("res://sim/flight_log.gd")
const DATA := "res://data/aircraft/p51d_mustang_120.json"

var _output_path := ""


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--parse-only"):
		print("P51 loop recorder parsed; no flight executed.")
		quit(0)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=")
	if _output_path.is_empty():
		push_error("Pass --out=<new absolute .orfl path>.")
		quit(2)
		return
	var session := FlightSession.new()
	session.setup(DATA)
	root.add_child(session)
	session.input_enabled = false
	if not session.aircraft.ok or not session.start.get("ok", false):
		push_error("P-51 setup/trim failed: " + str(session.start.get("message", "")))
		quit(1)
		return
	var model: Dictionary = session.aircraft.model
	var v0: float = model.start_speed
	var hands_off := func(_t: float, _s: PackedFloat64Array) -> Dictionary: return Maneuvers._hands_off()
	Maneuvers.fly(session, {mode = "level", speed = v0, duration = 30.0, sticks = hands_off})
	for speed in [v0, 27.0]:
		var roll := {mode = "level", speed = speed, duration = 3.0, sticks = func(t: float, s: PackedFloat64Array) -> Dictionary:
			return Maneuvers._coordinated(Maneuvers._pulse(t, 0.25, 1.75, {roll = 1.0}), s)}
		Maneuvers.fly(session, roll)
	var loop := {mode = "level", speed = 27.0, altitude = 150.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.2, 8.0, {pitch = 0.7, throttle_delta = 1.0})}
	var reference: RefCounted = Maneuvers.fly(session, loop)
	_summarize_trace("test helper reference", reference, session.sim.dt())
	var trim: Dictionary = session.trim_at(loop.speed, loop.mode)
	if not trim.ok:
		push_error("Loop trim failed: " + str(trim.message))
		quit(1)
		return
	session.set_start_altitude(loop.altitude)
	session.reset()
	var sim: Node = session.sim
	# Match the first test command in the initial log boundary, then repeat the test's exact per-tick command loop.
	var first: Dictionary = loop.sticks.call(sim.time(), sim.state)
	session.commands = {roll = first.roll, pitch = first.pitch, yaw = first.yaw, throttle = clampf(session.start.throttle + first.throttle_delta, 0.0, 1.0)}
	sim.inputs = session._inputs()
	var logger := FlightLogRecorder.new(session)
	var log_error: int = logger.start(_output_path)
	if log_error != OK:
		push_error("Flight log start failed: %d %s" % [log_error, logger.failure])
		quit(1)
		return
	for _i in roundi(loop.duration / sim.dt()):
		var command: Dictionary = loop.sticks.call(sim.time(), sim.state)
		session.commands = {roll = command.roll, pitch = command.pitch, yaw = command.yaw, throttle = clampf(session.start.throttle + command.throttle_delta, 0.0, 1.0)}
		sim.inputs = session._inputs()
		sim.step()
	var stop_error: int = logger.stop("P51-22 inside-loop baseline")
	_summarize_log(session, stop_error, logger)
	quit(0 if stop_error == OK and sim.fault_reason.is_empty() else 1)


func _summarize_trace(label: String, trace: RefCounted, dt: float) -> void:
	var turned := 0.0
	var loop_time := NAN
	var top := -1.0e30
	var slip := 0.0
	var minimum_speed := INF
	for row in trace.row_count():
		turned += float(trace.value(row, "q_radps")) * dt
		if is_nan(loop_time) and turned >= TAU:
			loop_time = row * dt
		top = maxf(top, float(trace.value(row, "pitch_deg")))
		if is_nan(loop_time) or row * dt <= loop_time:
			var u: float = trace.value(row, "u_mps")
			var v: float = trace.value(row, "v_mps")
			var w: float = trace.value(row, "w_mps")
			slip = maxf(slip, absf(rad_to_deg(atan2(v, sqrt(u * u + w * w)))))
			minimum_speed = minf(minimum_speed, float(trace.value(row, "speed_mps")))
	print("%s: rows=%d turned_deg=%.6f loop_time_s=%.6f pitch_max_deg=%.6f beta_max_deg=%.6f min_speed_mps=%.6f" % [label, trace.row_count(), rad_to_deg(turned), loop_time, top, slip, minimum_speed])


func _summarize_log(session: Node, stop_error: int, logger: RefCounted) -> void:
	print("P51 loop ORFL: ticks=%d duration=%.3f s status=%s path=%s fault=%s" % [session.sim.tick, session.sim.time(), "complete" if stop_error == OK else "incomplete", logger.path, session.sim.fault_reason])
