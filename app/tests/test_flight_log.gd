## FL-04: full-session replay, observer preservation, bounded storage and hostile-file rejection.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Weather := preload("res://physics/wind_config.gd")
var checks := 0
var failures := 0
var destination := ""
var measurements: Array = []


func _initialize() -> void:
	destination = ProjectSettings.globalize_path("res://../tmp/flight-log-%d" % Time.get_ticks_usec())
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): destination = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(destination)
	call_deferred("_run")


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)


func _run() -> void:
	for path in ["res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/gp_extra_300s_60.json", "res://data/aircraft/p51d_mustang_120.json", "res://data/aircraft/sebart_avanti_s_a200.json", "res://data/aircraft/turbo_lumber_evolution.json", "res://data/aircraft/stik_glow_61fx_2t.json"]:
		if not FileAccess.file_exists(path):
			# Catalog paths are checked below by the caller; never silently invent a specimen.
			check("specimen exists: " + path, false)
			continue
		_flight(path)
	var file := FileAccess.open(destination.path_join("verification.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({checks = checks, failures = failures, measurements = measurements}, "\t", true, true))
	file.close()
	print("FL-04 flight logs: %d checks, %d failures; %s" % [checks, failures, destination])
	quit(1 if failures else 0)


func _flight(path: String) -> void:
	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup(path)
	if path.contains("extra_300"):
		check("turbulent configuration", flight.setup_weather(Weather.preset("turbulent")))
		flight.reset()
	check("prepared " + path, flight.is_flyable())
	if not flight.is_flyable():
		flight.free()
		return
	var initial: Dictionary = flight.checkpoint()
	var expected: Array = []
	var started := Time.get_ticks_usec()
	for tick in 260:
		_controls(flight, tick)
		flight.sim.step()
		expected.append(_numeric(flight))
	var baseline_usec := Time.get_ticks_usec() - started
	check("baseline restored", flight.restore_checkpoint(initial))
	var logger := Log.new(flight)
	var log_path := destination.path_join(path.get_file().get_basename() + ".orfl")
	check("log starts", logger.start(log_path) == OK)
	started = Time.get_ticks_usec()
	for tick in 260:
		_controls(flight, tick)
		flight.sim.step()
		check("read-only observer tick %d" % tick, _numeric(flight) == expected[tick])
		if tick == 55: logger.mark("roll reversal")
		if tick == 60:
			flight.sim.set_paused(true)
			flight.sim.set_paused(false)
	var recorded_usec := Time.get_ticks_usec() - started
	check("log stops", logger.stop() == OK)
	check("bounded rows", logger.peak_buffer_rows <= Log.CHUNK_TICKS)
	check("duration uses elapsed ticks", logger.seconds() == 260 * flight.sim.dt())
	check("no overwrite", logger.start(log_path) == ERR_ALREADY_EXISTS)
	var read: Dictionary = Reader.inspect(log_path)
	check("complete file accepted", read.ok)
	if read.ok:
		check("initial plus all ticks", read.rows == 261)
		var replay: Dictionary = Reader.prepare_replay(read.header)
		check("self contained replay prepares", replay.ok)
		if replay.ok:
			var stream := FileAccess.open(log_path, FileAccess.READ)
			stream.seek(8)
			Log.read_packet(stream)
			var first := true
			var observer := Log.new(replay.flight)
			while stream.get_position() < stream.get_length():
				var block: Dictionary = Log.read_packet(stream).value
				if block.kind == "footer": break
				for row: Dictionary in block.rows:
					if first:
						first = false
						continue
					for key in row.intervention: replay.flight.sim.set(key, row.intervention[key].duplicate())
					replay.flight.sim.inputs = row.inputs.duplicate()
					replay.flight.sim.step()
					check("exact replay tick %d" % row.tick, Reader.disagreement(row, observer._sample({})).is_empty())
			stream.close()
			replay.flight.free()
		_corruption(log_path)
	measurements.append({aircraft = path, ticks = 260, bytes = FileAccess.get_file_as_bytes(log_path).size(),
		baseline_usec = baseline_usec, recorded_usec = recorded_usec, observer_usec = logger.observer_usec,
		peak_buffer_rows = logger.peak_buffer_rows})
	# Mid-flight capture, reset close and empty recording cover lifecycle boundaries.
	check("second start after failed path", logger.start(log_path + ".reset") == OK)
	flight.reset()
	check("reset closes previous flight", not logger.recording and Reader.inspect(log_path + ".reset").ok)
	check("directory write failure reported", logger.start(destination) != OK and not logger.recording)
	check("can restart after disk failure", logger.start(log_path + ".limit") == OK)
	# Seek alone allocates no file payload; simulates the cap while no physics tick advances.
	logger._file.seek(Log.MAX_BYTES - 16)
	logger.mark("paused cap")
	logger._flush_rows()
	check("event-only cap stops logger", not logger.recording and not logger.failure.is_empty())
	check("cap failure cannot certify a replay", not Reader.inspect(log_path + ".limit").ok)
	flight.free()


func _controls(flight: Node, tick: int) -> void:
	flight.sim.inputs[0] = 0.12 if tick < 100 else -0.08
	flight.sim.inputs[1] = -0.04 if tick < 80 else 0.03
	flight.sim.inputs[2] = 0.02
	flight.sim.inputs[3] = 0.5 if tick < 130 else 0.35
	if tick == 170:
		if flight.glow_is_active(): flight.glow_cut()
		elif not flight.turbine_is_continuous(): flight.engine_running = false
	if flight.sim.inputs.size() == 6:
		flight.sim.inputs[4] = 1.0 if tick > 50 else 0.0
		flight.sim.inputs[5] = 0.1


func _numeric(flight: Node) -> PackedByteArray:
	return var_to_bytes([flight.sim.state, flight.sim.aux, flight.sim.continuous, flight.sim.modes, flight.sim.last_loads])


func _corruption(path: String) -> void:
	var original := FileAccess.get_file_as_bytes(path)
	for mutation in ["truncate", "bitflip", "trailing", "length"]:
		var bytes := original.duplicate()
		match mutation:
			"truncate": bytes.resize(bytes.size() - 100)
			"bitflip": bytes[50] = bytes[50] ^ 1
			"trailing": bytes.append(0)
			"length": bytes.encode_u32(8, 0xffffffff)
		var output := FileAccess.open(path + "." + mutation, FileAccess.WRITE)
		output.store_buffer(bytes)
		output.close()
		check("reject " + mutation, not Reader.inspect(path + "." + mutation).ok)
		if mutation == "truncate":
			var recovered: Dictionary = Reader.inspect(path + "." + mutation, true)
			check("explicit diagnostic recovery labels partial prefix", recovered.ok and not recovered.complete and recovered.rows > 0)
