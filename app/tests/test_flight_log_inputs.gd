## GP-12: channel meaning survives CSV export and cannot change during replay.
extends SceneTree

const Reader := preload("res://tools/flight_log_cli.gd")
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
var checks := 0
var failures := 0
var destination := ""
var historical: Dictionary = {}


func _initialize() -> void:
	destination = ProjectSettings.globalize_path("res://../tmp/flight-log-inputs-%d" % Time.get_ticks_usec())
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			destination = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(destination)
	call_deferred("_run")


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL " + label)


func _run() -> void:
	_unit_contracts()
	for id: String in ["jensen-das-ugly-stik-60", "gp-extra-300s-60", "p51d-mustang-120", "sebart-avanti-s-a200-p100rx", "turbo-lumber-evolution", "stik-glow-61fx-2t", "moonrunner-x99"]:
		var entry: Dictionary = Catalog.entry(id)
		check("catalog identity " + id, not entry.is_empty())
		if not entry.is_empty():
			_flight(id, entry.data)
	var wing_entry: Dictionary = Catalog.entry("moonrunner-x99")
	check("catalog pack path available", not str(wing_entry.get("battery_data", "")).is_empty())
	if not str(wing_entry.get("battery_data", "")).is_empty():
		_flight("moonrunner-x99-pack", wing_entry.battery_data)
	print("GP-12 flight-log inputs: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _unit_contracts() -> void:
	var path := "res://tests/fixtures/flight_log_input_columns.json"
	var reference_text := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	check("frozen original columns, normalized LF", reference_text.sha256_text() == "bd2329a6ea1b01990459dbc7b8067ef000ff590fb22d08affefb3a42f713ba8f")
	historical = JSON.parse_string(reference_text).cases
	for width in [4, 5, 6, 7]:
		var layout := {state = 13, loads = 6, inputs = width, aux = 12, continuous = 8, modes = 2, mass = 4}
		var expected := PackedStringArray(["roll", "pitch", "yaw", "throttle"])
		if width in [6, 7]:
			expected.append_array(PackedStringArray(["gear_down", "wheel_brake"]))
		if width in [5, 7]:
			expected.append("flaps")
		var declared := {input_layout = JSON.stringify(Array(expected))}
		check("historical role fallback %d" % width, Reader.input_names(layout).names == expected)
		check("declared legacy roles %d" % width, Reader.input_names(layout, declared).names == expected)
		check("complete historical columns byte equal %d" % width, var_to_bytes(Reader.columns(layout, declared)) == var_to_bytes(PackedStringArray(historical[str(width)].columns)))
		var before := var_to_bytes([layout, declared])
		var changed: Dictionary = Reader.input_names(layout, declared)
		changed.names[0] = "changed"
		check("contract detaches input %d" % width, var_to_bytes([layout, declared]) == before and Reader.input_names(layout, declared).names == expected)
	for width: Variant in [0, 3, 8, 5.0, "5", null]:
		check("reject bad width " + str(width), not Reader.input_names({inputs = width}).ok)
	for raw: Variant in [null, [], ["roll"], "{}", "[", "[1,2,3,4]", '["pitch","roll","yaw","throttle"]', '["roll","roll","yaw","throttle"]', '["roll","pitch","yaw","throttle","brake"]', " ".repeat(257)]:
		check("reject malformed declaration " + str(raw).left(60), not Reader.input_names({inputs = 4}, {input_layout = raw}).ok)
	for width in [5, 6]:
		var names := ["roll", "pitch", "yaw", "throttle", "wheel_brake"]
		if width == 6:
			names.append("flaps")
		var metadata := {fixed_brake_input_law = Reader.FIXED_BRAKE_INPUT_LAW, wheel_brake_input_index = 4, input_layout = JSON.stringify(names)}
		check("named independent brake reader %d" % width, Reader.input_names({inputs = width}, metadata).names == PackedStringArray(names))
		check("same-width historical role set is distinct %d" % width, Reader.input_names({inputs = width}, metadata).names != Reader.input_names({inputs = width}).names)
		var layout := {inputs = width, aux = 4, continuous = 0, modes = 1}
		var columns: PackedStringArray = Reader.columns(layout, metadata)
		check("independent brake has no gear column %d" % width, columns[26] == "cmd_wheel_brake" and not columns.has("cmd_gear_down") and columns.has("cmd_flaps") == (width == 6))
		for key: String in ["fixed_brake_input_law", "wheel_brake_input_index", "input_layout"]:
			var partial := metadata.duplicate(true)
			partial.erase(key)
			check("reject partial fixed brake " + key, not Reader.input_names(layout, partial).ok)
		for key: String in ["gear_law", "gear_aux_index", "gear_trace_schema", "recording_start_gear"]:
			var conflict := metadata.duplicate(true)
			conflict[key] = null
			check("reject mixed retract/fixed " + key, not Reader.input_names(layout, conflict).ok)
		var wrong := metadata.duplicate(true)
		wrong.wheel_brake_input_index = 4.0
		check("index type is exact", not Reader.input_names(layout, wrong).ok)
		wrong = metadata.duplicate(true)
		wrong.fixed_brake_input_law = "future-unknown-law"
		check("refuse unknown brake input law", not Reader.input_names(layout, wrong).ok)
		for malformed: Variant in [null, true, [], {}, 1, 1.0, StringName(Reader.FIXED_BRAKE_INPUT_LAW)]:
			wrong = metadata.duplicate(true)
			wrong.fixed_brake_input_law = malformed
			check("brake input law has exact string type " + str(typeof(malformed)), not Reader.input_names(layout, wrong).ok)
	check("columns cannot quietly fall back from bad metadata", Reader.columns({inputs = 5}, {input_layout = "[]"}).is_empty())
	check("gear claim cannot label a base layout", not Reader.input_names({inputs = 4}, {gear_law = "declared"}).ok)
	check("flap claim cannot label a base layout", not Reader.input_names({inputs = 4}, {flap_law = "declared"}).ok)
	check("flap index must match role", not Reader.input_names({inputs = 5}, {flap_input_index = 3}).ok)
	check("flap index has exact type", not Reader.input_names({inputs = 5}, {flap_input_index = 4.0}).ok)


func _flight(id: String, path: String) -> void:
	var flight := Flight.new()
	flight.input_enabled = false
	flight.crash_auto_restart = false
	flight.setup(path)
	check("prepared " + id, flight.is_flyable())
	if not flight.is_flyable():
		flight.free()
		return
	var file_path := destination.path_join(id + ".orfl")
	var log := Log.new(flight)
	check("record current stock " + id, log.start(file_path) == OK)
	for tick in 16:
		flight.sim.inputs[0] = 0.08 if tick < 8 else -0.06
		flight.sim.inputs[1] = -0.02
		flight.sim.inputs[2] = 0.01
		flight.sim.inputs[3] = 0.45
		if flight.gear_is_retractable():
			flight.sim.inputs[4] = 1.0
			flight.sim.inputs[5] = 0.2
		if flight.flaps_available():
			flight.sim.inputs[flight.flap_input_index()] = 0.3
		flight.sim.step()
	check("stock recording finishes " + id, log.stop() == OK and flight.sim.tick == 16)
	var read: Dictionary = Reader.inspect(file_path)
	check("actual stock recording is complete " + id, read.ok and read.complete and read.rows == 17)
	if read.ok:
		_replay(id, file_path, read.header)
		var altered: Dictionary = read.header.duplicate(true)
		var names: Array = Array(Reader.input_names(altered.layout, altered.metadata).names)
		names[0] = "pitch"
		names[1] = "roll"
		altered.metadata.input_layout = JSON.stringify(names)
		var bad_path := file_path + ".roles"
		_rewrite_header(file_path, bad_path, altered)
		check("reader refuses role confusion before export " + id, not Reader.inspect(bad_path).ok)
		var refused: Dictionary = Reader.prepare_replay(altered)
		check("replay independently refuses role confusion " + id, not refused.ok)
		if refused.ok:
			refused.flight.free()

	flight.free()


func _replay(id: String, path: String, header: Dictionary) -> void:
	var prepared: Dictionary = Reader.prepare_replay(header)
	check("exact baseline replay prepares " + id, prepared.ok)
	if not prepared.ok:
		return
	var file := FileAccess.open(path, FileAccess.READ)
	file.seek(8)
	Log.read_packet(file)
	var observer := Log.new(prepared.flight)
	var initial := true
	var compared := 0
	while file.get_position() < file.get_length():
		var packet: Dictionary = Log.read_packet(file).value
		if packet.kind == "footer":
			break
		for row: Dictionary in packet.rows:
			if not initial:
				prepared.flight.sim.inputs = row.inputs.duplicate()
				prepared.flight.sim.step()
			check("full numeric exact replay %s tick%d" % [id, row.tick], Reader.disagreement(row, observer._sample({})).is_empty())
			initial = false
			compared += 1
	file.close()
	check("all recorded rows compared " + id, compared == 17)
	prepared.flight.free()


func _rewrite_header(source: String, target: String, header: Dictionary) -> void:
	var input := FileAccess.open(source, FileAccess.READ)
	input.seek(8)
	Log.read_packet(input)
	var output := FileAccess.open(target, FileAccess.WRITE)
	output.store_buffer(Log.MAGIC.to_ascii_buffer())
	var chain := Log.sha256(_packet(output, header))
	while input.get_position() < input.get_length():
		var value: Dictionary = Log.read_packet(input).value
		if value.kind == "footer":
			value.chain_sha256 = chain.hex_encode()
			_packet(output, value)
			break
		chain = Log.sha256(chain + _packet(output, value))
	input.close()
	output.close()


func _packet(file: FileAccess, value: Dictionary) -> PackedByteArray:
	var payload := var_to_bytes(value)
	var digest := Log.sha256(payload)
	file.store_32(payload.size())
	file.store_buffer(digest)
	file.store_buffer(payload)
	return digest
