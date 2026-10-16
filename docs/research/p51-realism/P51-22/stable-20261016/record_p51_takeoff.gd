extends "res://tests/p51_envelope_base.gd"

const FlightLogRecorder := preload("res://sim/flight_log.gd")

var _record_next_takeoff := false
var _output_path := ""


func _run() -> void:
	if OS.get_cmdline_user_args().has("--parse-only"):
		print("P51 takeoff recorder parsed; no flight executed.")
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=")
	if _output_path.is_empty():
		push_error("Pass --out=<new absolute .orfl path>.")
		_failures += 1
		return
	_ground()
	_record_next_takeoff = true
	_takeoff()


func fly(state: PackedFloat64Array, rpm: float, seconds: float, pilot: Callable, every := 12, gear_down := false) -> Dictionary:
	if not _record_next_takeoff or seconds != 12.0:
		return super.fly(state, rpm, seconds, pilot, every, gear_down)
	_record_next_takeoff = false
	return _record_flight(state, rpm, seconds, pilot, every, gear_down)


func _record_flight(state: PackedFloat64Array, rpm: float, seconds: float, pilot: Callable, every: int, gear_down: bool) -> Dictionary:
	var on_runway := not runway_launch.is_empty() and state == runway_launch
	session.start_choice = FlightSession.START_RUNWAY if on_runway else FlightSession.START_AIRBORNE
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		var reset_reason := str(session.pause_reason)
		if reset_reason.is_empty():
			reset_reason = str(session.sim.fault_reason)
		if reset_reason.is_empty():
			reset_reason = "session is not flyable"
		return {rows = [], crashed = "session reset failed: " + reset_reason, state = session.sim.state.duplicate()}
	if session._weather.has_turbulence():
		return {rows = [], crashed = "P-51 fixture does not initialize turbulent weather state", state = session.sim.state.duplicate()}
	if session.anchor_count() > 0 and not on_runway and _wheels_down(state) > 0:
		return {rows = [], crashed = "P-51 fixture: ground poses start from the qualified runway start (park())", state = session.sim.state.duplicate()}
	if on_runway and session.sim.state != runway_launch:
		return {rows = [], crashed = "P-51 runway start did not reproduce the parked launch: " + session.start_error, state = session.sim.state.duplicate()}
	session.engine_running = rpm > 0.0
	if gear_down and session.gear_is_retractable():
		session._gear_requested_down = true
	session.commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	var first: Dictionary = pilot.call(0.0, state)
	session.commands = first
	session.sim.inputs = session._inputs()
	var inputs: PackedFloat64Array = session.sim.inputs
	var aux: PackedFloat64Array = session.sim.aux.duplicate()
	if aux.size() < 4:
		return {rows = [], crashed = "session reset failed: auxiliary layout has fewer than four base slots", state = session.sim.state.duplicate()}
	aux[0] = rpm
	aux[1] = inputs[0]
	aux[2] = inputs[1]
	aux[3] = inputs[2]
	if gear_down and session.gear_is_retractable():
		aux[session.gear_aux_index()] = 1.0
		aux[session.gear_aux_index() + 1] = 1.0
	if session.downwash_index() >= 0:
		aux[session.downwash_index()] = session._wing_cl(state, aux, 0.0)
	session.sim.aux = aux
	session.sim.continuous = session._settled_continuous(state, aux)
	if not session.sim.reset(state):
		return {rows = [], crashed = "simulation reset failed: " + session.sim.fault_reason, state = session.sim.state.duplicate()}
	session.sim.set_paused(false)
	var logger := FlightLogRecorder.new(session)
	var log_error: int = logger.start(_output_path)
	if log_error != OK:
		return {rows = [], crashed = "flight log start failed: %d %s" % [log_error, logger.failure], state = session.sim.state.duplicate()}
	var dt: float = session.sim.dt()
	var rows := []
	var crashed := ""
	for k in roundi(seconds / dt):
		var current_state: PackedFloat64Array = session.sim.state
		var t := k * dt
		var command: Dictionary = pilot.call(t, current_state)
		session.commands = {roll = clampf(command.roll, -1.0, 1.0), pitch = clampf(command.pitch, -1.0, 1.0), yaw = clampf(command.yaw, -1.0, 1.0), throttle = clampf(command.throttle, 0.0, 1.0)}
		session.sim.inputs = session._inputs()
		session._physics_process(dt)
		if not session.crash.is_empty():
			crashed = session.pause_reason
			break
		if not session.sim.fault_reason.is_empty():
			crashed = "simulation fault: " + session.sim.fault_reason
			break
		if not Sim.state_is_valid(session.sim.state):
			crashed = "simulation produced an invalid state"
			break
		if k % every == 0:
			rows.append({t = t, s = current_state.duplicate(), rpm = session.sim.aux[0], cmd = session.commands.duplicate()})
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			crashed = "simulation fault: " + session.sim.fault_reason
			break
	var stop_error: int = logger.stop("P51-22 powered runway takeoff baseline")
	if stop_error != OK and crashed.is_empty():
		crashed = "flight log stop failed: %d %s" % [stop_error, logger.failure]
	print("P51 takeoff ORFL: ticks=%d duration=%.3f s status=%s path=%s" % [session.sim.tick, session.sim.time(), "complete" if stop_error == OK else "incomplete", logger.path])
	return {rows = rows, crashed = crashed, state = session.sim.state.duplicate()}
