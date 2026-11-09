# Records the live simulation into a flight trace (C7): start, stop, save. Fed by Simulation.stepped.
# 64-bit floats only (guarded).
extends RefCounted

const Trace := preload("res://sim/trace.gd")
const ManualTraceSave := preload("res://sim/manual_trace_save.gd")

var trace := Trace.new()
var recording := false
## Monotonic identity for each new manual recording, independent of saved trace data.
var recording_generation := 0
## Result of the last save, for the panel ("" before any).
var note := ""
var _unsaved := false
var _sim: Node
var _mass_sample: Callable


func _init(sim: Node, electrical_sample: Callable = Callable(), mass_sample: Callable = Callable()) -> void:
	_sim = sim
	_mass_sample = mass_sample
	trace.electrical_sample = electrical_sample
	sim.stepped.connect(_on_stepped)


func start(meta: Dictionary, use_chunks := false) -> void:
	if recording:
		note = "recording already in progress"
		return
	# T after a failed stop retries the old generation before starting another.
	if _unsaved and stop() != OK:
		note += " (T retries; exit to discard)"
		return
	var clear_error := trace.clear()
	if clear_error != OK:
		note = "trace cleanup failed: error %d; retry after releasing its files" % clear_error
		return
	recording_generation += 1
	if use_chunks:
		trace.enable_chunk_storage()
	trace.meta = meta.duplicate(true)
	if _mass_sample.is_valid():
		trace.meta.mass_trace_schema = "openrc-mass-sample v1"
	recording = true
	_unsaved = true
	trace.record(_sim.tick, _sim.time(), _sim.state, _sim.last_loads, _sim.inputs, _sim.aux, _sim.continuous.duplicate(),
		_mass_sample.call() if _mass_sample.is_valid() else {})
	_check_storage()
	if recording and trace.last_cleanup_error != OK:
		note = "recording; old trace cleanup pending: " + trace.last_cleanup_path
		print(note)


## Saves to `path`, by default user://traces/ (on Linux: ~/.local/share/godot/app_userdata/OpenRC Simulator/traces/).
func stop(path := "") -> Error:
	recording = false
	var err: Error
	if path == "":
		var result := _save_automatic()
		err = result.error
		path = result.path
	else:
		err = trace.save(path)
	if err == OK:
		_unsaved = false
		trace.mark_saved()
	note = "trace saved: %s (%d rows)" % [ProjectSettings.globalize_path(path), trace.row_count()] if err == OK else "trace save failed: error %d" % err
	if not trace.meta.get("trace_capture_complete", true):
		note = "INCOMPLETE " + note
	print(note)
	return err


func _save_automatic() -> Dictionary:
	return ManualTraceSave.save(trace, "trace")


func has_unsaved_recording() -> bool:
	return _unsaved


func discard_unsaved(expected_generation: int) -> bool:
	if recording or not _unsaved or expected_generation != recording_generation:
		return false
	var clear_error := trace.clear()
	if clear_error != OK:
		note = "trace discard failed: error %d; retry after releasing its files" % clear_error
		return false
	_unsaved = false
	note = "trace discarded"
	if trace.last_cleanup_error != OK:
		note += "; cleanup pending: " + trace.last_cleanup_path
		print(note)
	return true


## Stops listening to the simulation (a recorder made for one scripted flight).
func detach() -> void:
	recording = false
	if _sim.stepped.is_connected(_on_stepped):
		_sim.stepped.disconnect(_on_stepped)


## Recorded flight time.
func seconds() -> float:
	return trace.row_count() * _sim.dt()


func _on_stepped(tick: int, t: float, state: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	if recording:
		trace.record(tick, t, state, loads, inputs, aux, _sim.continuous.duplicate(),
			_mass_sample.call() if _mass_sample.is_valid() else {})
		_check_storage()


func _check_storage() -> void:
	var error := trace.storage_error()
	if error == OK:
		return
	recording = false
	trace.meta.trace_capture_complete = false
	trace.meta.trace_capture_stop_reason = "storage_backpressure" if error == ERR_BUSY else "storage_error_%d" % error
	trace.meta.trace_capture_last_tick = trace.value(trace.row_count() - 1, "tick") if trace.row_count() > 0 else -1
	note = "INCOMPLETE trace: storage error %d; %d rows retained. T retries saving. Recovery: %s" % [error, trace.row_count(), trace.recovery_directory()]
