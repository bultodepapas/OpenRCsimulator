# Records the live simulation into a flight trace (C7): start, stop, save. Fed by Simulation.stepped.
# 64-bit floats only (guarded).
extends RefCounted

const Trace := preload("res://sim/trace.gd")

var trace := Trace.new()
var recording := false
## Result of the last save, for the panel ("" before any).
var note := ""
var _sim: Node
var _mass_sample: Callable


func _init(sim: Node, electrical_sample: Callable = Callable(), mass_sample: Callable = Callable()) -> void:
	_sim = sim
	_mass_sample = mass_sample
	trace.electrical_sample = electrical_sample
	sim.stepped.connect(_on_stepped)


func start(meta: Dictionary) -> void:
	trace.clear()
	trace.meta = meta.duplicate(true)
	if _mass_sample.is_valid():
		trace.meta.mass_trace_schema = "openrc-mass-sample v1"
	recording = true
	trace.record(_sim.tick, _sim.time(), _sim.state, _sim.last_loads, _sim.inputs, _sim.aux, _sim.continuous.duplicate(),
		_mass_sample.call() if _mass_sample.is_valid() else {})


## Saves to `path`, by default user://traces/ (on Linux: ~/.local/share/godot/app_userdata/OpenRC Simulator/traces/).
func stop(path := "") -> Error:
	recording = false
	if path == "":
		path = "user://traces/trace-%s.csv" % Time.get_datetime_string_from_system(true).replace(":", "-")
	var err := trace.save(path)
	note = "trace saved: %s (%d rows)" % [ProjectSettings.globalize_path(path), trace.row_count()] if err == OK else "trace save failed: error %d" % err
	print(note)
	return err


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
