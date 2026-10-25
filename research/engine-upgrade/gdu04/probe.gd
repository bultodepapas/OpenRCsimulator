## GDU-04: research-only cross-engine numeric comparison, never an ORFL exact replay.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Config := preload("res://physics/wind_config.gd")
const Wind := preload("res://physics/wind_turbulence.gd")
const FIELDS := ["state", "previous", "aux", "continuous", "inputs", "modes", "last_loads"]
const SEEDS := [0, 1, 12345, 20261011, 4294967295]
var output := ""
var baseline := ""
var ticks := 960
var report := {"format": "openrc-gdu04-numerical v1", "cases": [], "wind": []}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
		elif argument.begins_with("--baseline="):
			baseline = argument.trim_prefix("--baseline=")
		elif argument.begins_with("--ticks="):
			ticks = int(argument.trim_prefix("--ticks="))
	Engine.physics_ticks_per_second = 240
	if output.is_empty() or ticks < 1:
		_fail("missing output or invalid tick count")
		return
	report.engine = Engine.get_version_info()
	report.tick_hz = 240
	report.ticks_per_case = ticks
	for aircraft_id in Catalog.airplane_flyable_ids():
		for weather in ["calm", "turbulent"]:
			if not _flight(aircraft_id, weather):
				return
	if not _wind():
		return
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		_fail("cannot write report")
		return
	report.complete = true
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("GDU04|COMPLETE|cases=%d|ticks=%d" % [report.cases.size(), ticks])
	quit()


func _flight(aircraft_id: String, weather: String) -> bool:
	var id := aircraft_id + "-" + weather
	var session := Session.new()
	session.input_enabled = false
	if weather != "calm" and not session.setup_weather(Config.preset(weather)):
		return _fail(id + ": weather rejected")
	session.setup(str(Catalog.entry(aircraft_id).data))
	if not session.is_flyable():
		session.free()
		return _fail(id + ": setup failed")
	var tape: Array = []
	if baseline.is_empty():
		var checkpoint := session.checkpoint_json()
		if checkpoint.is_empty():
			session.free()
			return _fail(id + ": empty initial checkpoint")
		var cp_file := FileAccess.open(output.path_join(id + ".checkpoint.json"), FileAccess.WRITE)
		cp_file.store_string(checkpoint)
		cp_file.close()
		if not session.restore_checkpoint_json(checkpoint):
			session.free()
			return _fail(id + ": own frozen checkpoint rejected")
		for tick in ticks:
			var values: PackedFloat64Array = session.sim.inputs.duplicate()
			# Frozen demands downstream of device conditioning, preserving optional gear/flap slots.
			values[0] += 0.10 if tick >= 120 and tick < 240 else (-0.10 if tick >= 240 and tick < 360 else 0.0)
			values[1] += -0.08 if tick >= 360 and tick < 480 else (0.08 if tick >= 480 and tick < 600 else 0.0)
			values[2] += 0.08 if tick >= 600 and tick < 720 else (-0.08 if tick >= 720 and tick < 840 else 0.0)
			tape.append(Array(values))
		var tape_file := FileAccess.open(output.path_join(id + ".inputs.json"), FileAccess.WRITE)
		tape_file.store_string(JSON.stringify(tape, "", false, true))
		tape_file.close()
		tape = JSON.parse_string(FileAccess.get_file_as_string(output.path_join(id + ".inputs.json")))
	else:
		if not session.restore_checkpoint_json(FileAccess.get_file_as_string(baseline.path_join(id + ".checkpoint.json"))):
			session.free()
			return _fail(id + ": frozen checkpoint rejected")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline.path_join(id + ".inputs.json")))
		if typeof(parsed) != TYPE_ARRAY or parsed.size() != ticks:
			session.free()
			return _fail(id + ": frozen command tape rejected")
		tape = parsed
	var path := output.path_join(id + ".bin")
	var stream := FileAccess.open(path, FileAccess.WRITE)
	if stream == null:
		session.free()
		return _fail(id + ": cannot create stream")
	var layout: Array = []
	for field: String in FIELDS:
		var value: Variant = session.sim.get(field)
		layout.append({"field": field, "count": value.size(), "kind": "int64" if field == "modes" else "float64"})
	for tick in ticks + 1:
		if session.sim.tick != tick or not session.sim.fault_reason.is_empty():
			stream.close()
			session.free()
			return _fail(id + ": incomplete at tick %d" % tick)
		for field: String in FIELDS:
			var value: Variant = session.sim.get(field)
			stream.store_buffer(value.to_byte_array())
		if tick < ticks:
			session.sim.inputs = PackedFloat64Array(tape[tick])
			session.sim.step()
	stream.close()
	report.cases.append({"id": id, "ticks": session.sim.tick, "rows": ticks + 1,
		"layout": layout, "bytes": FileAccess.get_file_as_bytes(path).size(),
		"sha256": FileAccess.get_sha256(path), "input_sha256": FileAccess.get_sha256(
			(output if baseline.is_empty() else baseline).path_join(id + ".inputs.json"))})
	session.free()
	print("GDU04|CASE|", id, "|ticks=", ticks)
	return true


func _wind() -> bool:
	for seed_value: int in SEEDS:
		var path := output.path_join("wind-%d.bin" % seed_value)
		var stream := FileAccess.open(path, FileAccess.WRITE)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		stream.store_buffer(PackedInt64Array([rng.state]).to_byte_array())
		for index in 4096:
			var word := rng.randi()
			stream.store_buffer(PackedInt64Array([word, rng.state]).to_byte_array())
		stream.close()
		var ou_path := output.path_join("ou-%d.bin" % seed_value)
		stream = FileAccess.open(ou_path, FileAccess.WRITE)
		var sigma := PackedFloat64Array([0.7, 0.4, 0.9])
		var draw: Dictionary = Wind.initial(sigma, seed_value)
		for tick in 4097:
			if not draw.ok:
				stream.close()
				return _fail("OU rejected seed %d tick %d" % [seed_value, tick])
			stream.store_buffer(draw.values.to_byte_array())
			stream.store_buffer(PackedInt64Array([draw.rng_state]).to_byte_array())
			if tick < 4096:
				draw = Wind.step(draw.values, sigma, 0.5, 1.0 / 240.0, seed_value, draw.rng_state)
		stream.close()
		report.wind.append({"seed": seed_value, "words": 4096, "ou_steps": 4096,
			"raw_sha256": FileAccess.get_sha256(path), "ou_sha256": FileAccess.get_sha256(ou_path)})
	return true


func _fail(message: String) -> bool:
	printerr("GDU04|FAIL|", message)
	quit(1)
	return false
