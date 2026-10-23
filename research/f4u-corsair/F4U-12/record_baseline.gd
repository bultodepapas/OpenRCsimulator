extends SceneTree
## F4U-12: records the Corsair's scripted software baseline (.orfl) from the catalog airborne start: a bounded
## 10 s tape of an aileron reversal, an elevator doublet, a rudder pulse and a throttle step, each on top of the
## start's trim inputs and marked. Exact replay and export go through tools/flight_log/flight_log.py. Not piloted.
## godot --headless --path app --audio-driver Dummy --script <repo>/research/f4u-corsair/F4U-12/record_baseline.gd -- --out=<new .orfl>
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const DATA := "res://data/aircraft/f4u_corsair_250.json"
const TICKS := 2400
## [first tick, last tick (exclusive), input channel, increment, mark]
const TAPE := [
	[240, 360, 0, 0.5, "aileron right"], [360, 480, 0, -0.5, "aileron reversal"],
	[720, 840, 1, 0.25, "elevator doublet"], [840, 960, 1, -0.25, ""],
	[1200, 1320, 2, 0.5, "rudder pulse"],
	[1680, 2160, 3, 1.0, "full throttle"],
]


func _initialize() -> void:
	var out := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
	if out.is_empty() or FileAccess.file_exists(out):
		printerr("F4U-12 baseline: pass --out=<new .orfl path>")
		quit(2)
		return
	call_deferred("_run", out)


func _run(out: String) -> void:
	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup(DATA)
	if not flight.is_flyable():
		printerr("F4U-12 baseline: the Corsair start is not flyable")
		flight.free()
		quit(1)
		return
	var trim: PackedFloat64Array = flight.sim.inputs.duplicate()
	var logger := Log.new(flight)
	if logger.start(out) != OK:
		printerr("F4U-12 baseline: cannot start the log at " + out)
		flight.free()
		quit(1)
		return
	for tick in TICKS:
		var inputs: PackedFloat64Array = trim.duplicate()
		for step: Array in TAPE:
			if tick >= int(step[0]) and tick < int(step[1]):
				var channel: int = step[2]
				inputs[channel] = clampf(trim[channel] + float(step[3]), 0.0 if channel == 3 else -1.0, 1.0)
			if tick == int(step[0]) and not str(step[4]).is_empty():
				logger.mark(str(step[4]))
		flight.sim.inputs = inputs
		flight.sim.step()
	var stopped := logger.stop()
	print("F4U-12 baseline: %d ticks, trim inputs %s, stop %s, %s" % [TICKS, trim, error_string(stopped), out])
	flight.free()
	quit(0 if stopped == OK else 1)
