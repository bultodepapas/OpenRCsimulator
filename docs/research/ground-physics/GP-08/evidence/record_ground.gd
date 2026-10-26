## GP-08 retained baseline fixture; uses existing session, ground start and native recorder.
## Software behavior only, not measured physical validation. --out=<fresh-directory>
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Field := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
var destination := ""
var results: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): destination = argument.trim_prefix("--out=")
	call_deferred("_run")

func _run() -> void:
	if destination.is_empty() or DirAccess.dir_exists_absolute(destination):
		printerr("Requires fresh --out directory")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	var loaded: Dictionary = Field.load_from()
	if not loaded.ok:
		printerr("Field rejected")
		quit(1)
		return
	var spot: Dictionary = GroundStart.threshold(loaded.field)
	var valid: bool = spot.ok
	for path: String in ["res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/p51d_mustang_120.json"]:
		var flight := Flight.new()
		flight.input_enabled = false
		flight.crash_auto_restart = false
		flight.setup(path)
		var ready: bool = flight.is_flyable() and flight.set_field(loaded.field)
		ready = ready and spot.ok and flight.reset_on_runway(spot.north, spot.east, spot.heading)
		if not ready:
			printerr("Ground preparation rejected: ", path)
			valid = false
			flight.free()
			continue
		var recorder := Log.new(flight)
		var log_path: String = destination.path_join(path.get_file().get_basename() + "-ground.orfl")
		if recorder.start(log_path) != OK:
			printerr("Recorder rejected: ", recorder.failure)
			valid = false
			flight.free()
			continue
		recorder.mark("GP-08 baseline: runway support, idle, throttle ramp, steering; gear stays down")
		for tick in 480:
			flight.sim.inputs[0] = 0.0
			flight.sim.inputs[1] = 0.0
			flight.sim.inputs[2] = 0.05 if tick >= 300 else 0.0
			flight.sim.inputs[3] = 0.0 if tick < 120 else 0.15
			if flight.gear_is_retractable():
				flight.sim.inputs[4] = 1.0
				flight.sim.inputs[5] = 0.15 if tick < 120 else 0.0
			flight.sim.step()
			if not flight.sim.fault_reason.is_empty() or flight.sim.tick != tick + 1:
				valid = false
				break
		var stopped: Error = recorder.stop("GP-08 two-second ground tape")
		var complete: bool = stopped == OK and flight.sim.tick == 480 and flight.sim.fault_reason.is_empty()
		valid = valid and complete
		results.append({path = log_path, complete = complete, ticks = flight.sim.tick,
			fault = flight.sim.fault_reason, solver_sha256 = Log.solver_identity(),
			aircraft_identity = flight.aircraft.input_identity, initial_metadata = recorder.header.metadata,
			final_body = Array(flight.sim.state)})
		flight.free()
	var output := FileAccess.open(destination.path_join("scenario.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({complete = valid, engine = Engine.get_version_info().string, results = results}, "\t", true, true))
	output.close()
	print("GP-08 ground recordings: ", results.size(), " tapes; complete=", valid)
	quit(0 if valid else 1)
