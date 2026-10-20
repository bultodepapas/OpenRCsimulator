extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"
const CAPTURE_TICKS := 960 # 4 seconds at the fixed 240 Hz tick rate.

var output_path := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_path = argument.trim_prefix("--out=")
	call_deferred("_capture")


func _capture() -> void:
	if output_path.is_empty():
		printerr("Missing --out=<new-orfl-path>")
		quit(2)
		return
	var flight: Node = Flight.new()
	flight.input_enabled = false
	if not flight.setup_shaft_integrator("coupled-rk4"):
		_fail(flight, "Could not select coupled-rk4: " + flight.shaft_error)
		return
	flight.setup(P51_PATH)
	if not flight.is_flyable():
		_fail(flight, "P-51 did not prepare: " + flight.start_error)
		return
	var shaft_index: int = flight._rotor_index()
	var initial_rpm: float = float(flight.sim.continuous[shaft_index])
	if not flight.engine_running or initial_rpm <= 0.0:
		_fail(flight, "Expected a powered P-51 start; running=%s rpm=%s" % [flight.engine_running, initial_rpm])
		return
	var logger: RefCounted = FlightLog.new(flight)
	if logger.start(output_path) != OK:
		_fail(flight, "Could not start ORFL recorder: " + logger.failure)
		return
	logger.mark("G2a powered P-51 control-tape start")
	for tick: int in CAPTURE_TICKS:
		flight.sim.inputs[0] = 0.04 if tick < 480 else -0.03
		flight.sim.inputs[1] = -0.02 if tick < 240 else 0.01
		flight.sim.inputs[2] = 0.0
		flight.sim.inputs[3] = 0.56
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			logger.stop("capture fault")
			_fail(flight, "Simulation fault at tick %d: %s" % [flight.sim.tick, flight.sim.fault_reason])
			return
		if tick == 479:
			logger.mark("G2a powered P-51 control-tape midpoint")
	if logger.stop("powered P-51 regression-control tape complete") != OK:
		_fail(flight, "Could not finalize ORFL recorder: " + logger.failure)
		return
	var final_rpm: float = float(flight.sim.continuous[shaft_index])
	if flight.sim.tick != CAPTURE_TICKS or not flight.engine_running or final_rpm <= 0.0:
		_fail(flight, "Powered capture boundary failed: tick=%d running=%s rpm=%s" % [flight.sim.tick, flight.engine_running, final_rpm])
		return
	print("P51_CAPTURE_COMPLETE ticks=%d duration_s=%.3f initial_rpm=%.3f final_rpm=%.3f" % [
		flight.sim.tick, flight.sim.time(), initial_rpm, final_rpm])
	flight.free()
	quit(0)


func _fail(flight: Node, message: String) -> void:
	printerr("P51_CAPTURE_FAILED: " + message)
	if flight != null:
		flight.free()
	quit(1)
