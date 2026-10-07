# F3b: synthetic event-processing cost, not USB timing or stick-to-photon latency.
extends SceneTree

const Main = preload("res://main.gd")
const FRAMES: int = 1200
const FPS: int = 60
const EVENTS_PER_SECOND: int = 4000 # four axes, each reporting at 1 kHz
const ROUNDS: int = 7
var events: Array[InputEventJoypadMotion] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Input.use_accumulated_input = false
	var flight: Node = Main.new()
	root.add_child(flight)
	flight.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight.session.radio.connect_device(15, {name = "Fake EdgeTX"})
	flight.session.radio.armed = true
	var result: Dictionary = {format = "openrc-radio-event-bench v1", godot = Engine.get_version_info().string, os = OS.get_name(), cpu = OS.get_processor_name(), frames_per_round = FRAMES, modeled_fps = FPS, events_per_second = EVENTS_PER_SECOND, rounds = ROUNDS, event_construction_timed = false, physics_and_render_timed = false, measurements = {}}
	for mode: String in ["handler", "dispatch"]:
		_measure(flight, mode, 120) # warm caches and seen state, discarded
		var samples: Array[float] = []
		for round_index: int in ROUNDS:
			samples.append(_measure(flight, mode, FRAMES))
		var sorted: Array[float] = samples.duplicate()
		sorted.sort()
		result.measurements[mode] = {us_per_modeled_frame_samples = samples, median_us_per_modeled_frame = sorted[ROUNDS >> 1], median_us_per_event = sorted[ROUNDS >> 1] * FPS / EVENTS_PER_SECOND}
	# Both paths must update all axes, despite an already-armed throttle and repeated axes.
	for axis: int in 4:
		if not flight.session.radio.has_axis_sample(axis) or flight.session.radio.axes[axis] != events[events.size() - 4 + axis].axis_value:
			printerr("FAIL benchmark did not deliver axis ", axis)
			flight.free()
			quit(1)
			return
	print("F3B_RESULT ", JSON.stringify(result))
	flight.free()
	quit(0)


func _measure(flight: Node, mode: String, frames: int) -> float:
	@warning_ignore("integer_division") # Benchmark windows are whole seconds: exact event count.
	var total: int = frames * EVENTS_PER_SECOND / FPS
	# Godot forbids reusing parsed events. Allocate outside the timed section, once per measured event.
	events.clear()
	for i: int in total:
		var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
		event.device = 15
		event.axis = i % 4
		event.axis_value = float((i >> 2) % 100) / 50.0 - 1.0
		events.append(event)
	var start: int = Time.get_ticks_usec()
	if mode == "handler":
		for event: InputEventJoypadMotion in events:
			flight.session._input(event)
	else:
		for event: InputEventJoypadMotion in events:
			Input.parse_input_event(event)
	return float(Time.get_ticks_usec() - start) / frames
