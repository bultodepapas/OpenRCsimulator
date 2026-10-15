## Deterministic AV-09 open-loop flap tape for FlightLog sensitivity replay.
## Run with Godot --path app --script <this file> -- --out=<new .orfl> --aircraft=<model.json>.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")

var _out_path: String = ""
var _aircraft_path: String = ""
var _physics_ticks: int = 240
var _flight: Node
var _logger: RefCounted
var _base_inputs: PackedFloat64Array = PackedFloat64Array()
var _flap_index: int = -1
var _failed: bool = false
var _segments: Array[Dictionary] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out_path = argument.trim_prefix("--out=")
		elif argument.begins_with("--aircraft="):
			_aircraft_path = argument.trim_prefix("--aircraft=")
		elif argument.begins_with("--physics-ticks="):
			_physics_ticks = int(argument.trim_prefix("--physics-ticks="))
	if _out_path.is_empty() or _aircraft_path.is_empty():
		printerr("record_tape.gd requires --out=<new .orfl> and --aircraft=<model.json>")
		quit(2)
		return
	if _physics_ticks not in [240, 480]:
		printerr("AV-09 refinement accepts only --physics-ticks=240 or 480")
		quit(2)
		return
	Engine.physics_ticks_per_second = _physics_ticks
	call_deferred("_run")


func _run() -> void:
	_flight = Flight.new()
	_flight.input_enabled = false
	root.add_child(_flight)
	_flight.setup(_aircraft_path)
	if not _flight.is_flyable() or not _flight.flaps_available():
		printerr("AV-09 recording requires a flyable aircraft with simulated flaps: ", _aircraft_path)
		_flight.free()
		quit(1)
		return
	_flap_index = _flight.flap_input_index()
	if _flight.sim.inputs.size() != 7 or _flap_index != 6:
		printerr("unexpected AV-09 command layout: inputs=", _flight.sim.inputs.size(), " flap_index=", _flap_index)
		_flight.free()
		quit(1)
		return
	_base_inputs = _flight.sim.inputs.duplicate()
	_logger = FlightLog.new(_flight)
	if _logger.start(_out_path) != OK:
		printerr("FlightLog refused the AV-09 sensitivity tape: ", _logger.failure)
		_flight.free()
		quit(1)
		return
	var dt: float = _flight.sim.dt()
	var tick_plan: Array[Dictionary] = [
		{"name": "clean_hold", "seconds": 3.0, "flap": 0.0, "pitch_delta": 0.0},
		{"name": "takeoff_flap_20deg", "seconds": 3.0, "flap": 0.4, "pitch_delta": 0.0},
		{"name": "landing_flap_50deg", "seconds": 7.0, "flap": 1.0, "pitch_delta": 0.0},
		{"name": "same_tape_pitch_pulse", "seconds": 1.5, "flap": 1.0, "pitch_delta": 0.15},
		{"name": "open_loop_recovery", "seconds": 2.5, "flap": 1.0, "pitch_delta": 0.0},
		{"name": "flap_retraction", "seconds": 4.0, "flap": 0.0, "pitch_delta": 0.0},
		{"name": "clean_return", "seconds": 2.0, "flap": 0.0, "pitch_delta": 0.0},
	]
	for segment: Dictionary in tick_plan:
		var count: int = roundi(float(segment.seconds) / dt)
		if not _segment(str(segment.name), count, float(segment.flap), float(segment.pitch_delta)):
			_failed = true
			break
	if _logger.recording and _logger.stop("AV-09 paired flap tape complete") != OK:
		_failed = true
	if _failed:
		printerr("AV-09 recording stopped with a physics or recorder error: ", _flight.sim.fault_reason,
			" ", _logger.failure)
		_flight.free()
		quit(1)
		return
	var manifest: Dictionary = {
		"evidence_step": "AV-09",
		"tape_id": "av09-flaps-open-loop-v1",
		"aircraft_id": _flight.aircraft.model.id,
		"aircraft_path": _aircraft_path,
		"aircraft_input_sha256": _flight.aircraft.get("input_identity", {}).get("sha256", "unavailable"),
		"dt_s": dt,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"ticks": _flight.sim.tick,
		"rows_including_initial": _flight.sim.tick + 1,
		"flap_input_index": _flap_index,
		"flap_aux_index": _flight.flap_aux_index(),
		"flap_law": str(_flight.trace_meta().get("flap_law", "")),
		"accepted_start_inputs": Array(_base_inputs),
		"segments": _segments,
		"interpretation": "The source log contains one accepted command tape. Candidate replay reuses its tick-indexed accepted inputs; it is open-loop and is not an adapted piloted flight.",
		"recorder_observer_usec": _logger.observer_usec,
		"recorder_peak_buffer_rows": _logger.peak_buffer_rows,
	}
	var manifest_path: String = _out_path.get_basename() + ".manifest.json"
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write tape manifest: ", manifest_path)
		_flight.free()
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t", true, true) + "\n")
	file.close()
	print("AV-09 tape complete: %d ticks, dt %.9f s, %s" % [_flight.sim.tick, dt, _out_path])
	_flight.free()
	quit(0)


func _segment(name: String, count: int, flap_request: float, pitch_delta: float) -> bool:
	_logger.mark(name)
	var first_tick: int = _flight.sim.tick + 1
	for _tick: int in count:
		var accepted: PackedFloat64Array = _base_inputs.duplicate()
		accepted[1] = clampf(_base_inputs[1] + pitch_delta, -1.0, 1.0)
		accepted[_flap_index] = flap_request
		_flight.sim.inputs = accepted
		_flight.sim.step()
		if not _flight.sim.fault_reason.is_empty() or not _logger.failure.is_empty():
			printerr("tape failed in segment '", name, "' at tick ", _flight.sim.tick)
			return false
	_segments.append({
		"name": name,
		"first_tick": first_tick,
		"last_tick": _flight.sim.tick,
		"duration_s": float(count) * _flight.sim.dt(),
		"cmd_flaps": flap_request,
		"pitch_offset_from_trim_command": pitch_delta,
	})
	return true
