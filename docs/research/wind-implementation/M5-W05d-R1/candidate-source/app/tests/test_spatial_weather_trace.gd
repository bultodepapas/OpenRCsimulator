## Spatial observers: endpoint/k1 locations, fail-closed receipts, and exact ORFL replay.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Recorder = preload("res://sim/recorder.gd")
const Trace = preload("res://sim/trace.gd")
const Config = preload("res://physics/wind_config.gd")
const Log = preload("res://sim/flight_log.gd")
const Reader = preload("res://tools/flight_log_cli.gd")
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var flight := Session.new()
	flight.input_enabled = false
	flight.setup()
	var weather := Config.spatial_defaults()
	weather.spatial_wind.profile.reference_speed_mps = 1.5
	weather.spatial_wind.profile.reference_from_deg = 90.0
	weather.spatial_wind.profile.free_air_wind_ned_mps = [0.0, -2.0, 0.0]
	weather.spatial_wind.identity.epoch_offset_s = 7.0
	check("spatial weather accepted", flight.setup_weather(weather))
	flight.reset()
	check("spatial initial state flyable", flight.is_flyable())
	var recorder := Recorder.new(flight.sim)
	recorder.start(flight.trace_meta())
	for i in 24:
		flight.sim.inputs[1] = 0.02
		flight.sim.step()
	check("accepted every tick", flight.sim.tick == 24)
	check("one row per accepted endpoint", recorder.trace.row_count() == 25)
	check("explicit spatial trace boundary", recorder.trace.to_csv().begins_with("# format: openrc-trace v16\n"))
	check("spatial columns present", recorder.trace.columns().has("loads_north_m") and recorder.trace.columns().has("weather_epoch_time_s"))
	if recorder.trace.row_count() == 25:
		for row in range(1, 25):
			check("endpoint epoch time %d" % row, recorder.trace.value(row, "weather_epoch_time_s") == recorder.trace.value(row, "t_s") + 7.0)
			check("k1 epoch time %d" % row, recorder.trace.value(row, "loads_weather_epoch_time_s") == recorder.trace.value(row, "loads_t_s") + 7.0)
			for axis in ["north", "east", "down"]:
				check("k1 position %s %d" % [axis, row], recorder.trace.value(row, "loads_" + axis + "_m") == recorder.trace.value(row - 1, axis + "_m"))
			# Independent neutral logarithmic profile, in the surface-layer interior.
			for prefix in ["", "loads_"]:
				var z: float = -recorder.trace.value(row, prefix + "down_m")
				check("oracle lies inside log region", z > 0.3 and z < 80.0)
				var expected: float = -1.5 * log(z / 0.03) / log(10.0 / 0.03)
				check("local analytic wind " + prefix, absf(recorder.trace.value(row, prefix + "wind_east_mps") - expected) < 1e-12)
	recorder.detach()
	for defect in ["receipt", "weather", "law", "domain"]:
		var trace := Trace.new()
		trace.meta = flight.trace_meta()
		var body: PackedFloat64Array = flight.sim.state.duplicate()
		match defect:
			"receipt": trace.meta.spatial_weather_receipt = "{}"
			"weather": trace.meta.erase("weather_config")
			"law": trace.meta.spatial_aero_model = "unrecorded-law"
			"domain": body[2] = -2000.0
		trace.record(flight.sim.tick, flight.sim.time(), body, flight.sim.last_loads, flight.sim.inputs, flight.sim.aux)
		check("refuse malformed spatial observer " + defect, trace.to_csv().is_empty() and trace.row_count() == 0)
	# Preserve a same-input baseline before enabling the bounded observer.
	var initial := flight.checkpoint()
	var expected_states: Array = []
	for i in 60:
		_controls(flight, i)
		flight.sim.step()
		expected_states.append(_numeric(flight))
	check("restore before recording", flight.restore_checkpoint(initial))
	var out := ProjectSettings.globalize_path("res://../tmp/spatial-log-%d.orfl" % Time.get_ticks_usec())
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
	var logger := Log.new(flight)
	check("ORFL starts", logger.start(out) == OK)
	for i in 60:
		_controls(flight, i)
		flight.sim.step()
		check("read-only observer %d" % i, _numeric(flight) == expected_states[i])
	check("ORFL stops", logger.stop() == OK)
	var read := Reader.inspect(out)
	check("complete spatial log", read.ok and read.get("complete", false) and read.get("rows", 0) == 61)
	if read.ok:
		var replay := Reader.prepare_replay(read.header)
		check("spatial replay prepares", replay.ok)
		if replay.ok:
			var stream := FileAccess.open(out, FileAccess.READ)
			stream.seek(8)
			Log.read_packet(stream)
			var first := true
			var observer := Log.new(replay.flight)
			while stream.get_position() < stream.get_length():
				var packet: Dictionary = Log.read_packet(stream).value
				if packet.kind == "footer": break
				for row: Dictionary in packet.rows:
					if first:
						first = false
						continue
					for key in row.intervention: replay.flight.sim.set(key, row.intervention[key].duplicate())
					replay.flight.sim.inputs = row.inputs.duplicate()
					replay.flight.sim.step()
					check("spatial exact replay %d" % row.tick, Reader.disagreement(row, observer._sample({})).is_empty())
			stream.close()
			replay.flight.free()
	flight.free()
	print("spatial weather trace: %d checks, %d failures; %s" % [checks, failures, out])
	quit(1 if failures else 0)

func _controls(flight: Node, tick: int) -> void:
	flight.sim.inputs[0] = 0.05 if tick < 30 else -0.05
	flight.sim.inputs[1] = 0.01
	flight.sim.inputs[2] = -0.01
	flight.sim.inputs[3] = 0.4

func _numeric(flight: Node) -> PackedByteArray:
	return var_to_bytes([flight.sim.state, flight.sim.aux, flight.sim.continuous, flight.sim.modes, flight.sim.last_loads])
