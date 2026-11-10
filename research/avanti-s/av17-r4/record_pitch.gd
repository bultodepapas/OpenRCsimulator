## AV-17-R4: accepted clean pitch pulse / loop-entry tape; no device shaping.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const RB := preload("res://physics/rigid_body.gd")

var output := ""
var maneuver := "pulse"
var aircraft_path := "res://data/aircraft/sebart_avanti_s_a200.json"


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
		elif argument.begins_with("--maneuver="):
			maneuver = argument.trim_prefix("--maneuver=")
		elif argument.begins_with("--aircraft="):
			aircraft_path = argument.trim_prefix("--aircraft=")
	if output.is_empty() or maneuver not in ["pulse", "loop_entry"]:
		printerr("requires --out=<new.orfl> --maneuver=pulse|loop_entry")
		quit(2)
		return
	Engine.physics_ticks_per_second = 240
	call_deferred("_run")


func _run() -> void:
	var flight := Flight.new()
	flight.input_enabled = false
	root.add_child(flight)
	flight.setup(aircraft_path)
	if not flight.is_flyable() or not flight.set_fuel_start_fill(0.5):
		printerr("pitch fixture refused")
		flight.free()
		quit(1)
		return
	flight.reset()
	# The checkpoint/CSV captures this research relocation. Reset-time
	# launch_state metadata still describes the preceding 30 m setup.
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	state[RB.POS + 2] = -500.0
	flight.sim.state = state
	flight.sim.previous = state.duplicate()
	var logger := FlightLog.new(flight)
	if logger.start(output) != OK:
		printerr(logger.failure)
		flight.free()
		quit(1)
		return
	var base: PackedFloat64Array = flight.sim.inputs.duplicate()
	# Retained tape marker "trim_hold" names the initial phase. For loop_entry,
	# full throttle starts immediately: this is one second of pre-acceleration.
	# raw/stick telemetry is not driven here; cmd_* is the accepted input tape.
	var segments: Array[Dictionary] = [
		{"name": "trim_hold", "seconds": 1.0, "pitch": 0.0},
		{"name": maneuver, "seconds": 0.5 if maneuver == "pulse" else 6.0,
			"pitch": 0.04 if maneuver == "pulse" else 0.10},
		{"name": "release", "seconds": 5.0, "pitch": 0.0},
	]
	var failed := false
	for segment: Dictionary in segments:
		logger.mark(segment.name)
		for _tick: int in roundi(float(segment.seconds) / flight.sim.dt()):
			var command := base.duplicate()
			command[1] = clampf(base[1] + float(segment.pitch), -1.0, 1.0)
			if maneuver == "loop_entry":
				command[3] = 1.0
			flight.sim.inputs = command
			var before: int = flight.sim.tick
			flight.sim.step()
			if flight.sim.tick != before + 1 or not flight.sim.fault_reason.is_empty() or not logger.failure.is_empty():
				failed = true
				break
		if failed:
			break
	if logger.recording and logger.stop("AV-17-R4 " + maneuver + (" failed" if failed else " complete")) != OK:
		failed = true
	print("AV-17-R4 %s: %d ticks; complete=%s; %s" % [maneuver, flight.sim.tick, not failed, logger.failure])
	flight.free()
	quit(1 if failed else 0)
