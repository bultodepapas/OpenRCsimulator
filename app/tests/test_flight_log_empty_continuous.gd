# External audit A6 F5: a valid aircraft whose kernel has no continuous state (here the Ugly Stik validated in memory,
# before its optional file-boundary wheel profile adds wheel spin states) must record, inspect and replay exactly.
# The kernel checkpoint omits an empty `continuous` block by format (restore reads absence as empty), while every row
# carries `continuous = []`; the reader required the key and rejected its own file:
# "Initial sample disagrees with checkpoint: continuous". Nonempty blocks must still be compared exactly.
# Run: godot --headless --path . --script res://tests/test_flight_log_empty_continuous.gd
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"

var checks := 0
var failures := 0
var destination := ""


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	destination = ProjectSettings.globalize_path("res://../tmp/flight-log-empty-continuous-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(destination)
	_run.call_deferred()


func _run() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(STIK))
	var derived: Dictionary = AircraftData.validate_and_derive(raw) if raw is Dictionary else {}
	check("in-memory Stik validates", derived.get("ok", false), str(derived.get("errors", "")))
	var empty := _record("empty-continuous", derived)
	check("the in-memory Stik has an empty continuous block (the audit's specimen)", empty.continuous_size == 0,
		str(empty.continuous_size))
	check("an empty continuous block records, inspects and prepares replay", empty.ok, empty.error)
	if empty.ok:
		check("legacy checkpoint omits its empty continuous block", not Reader.inspect(empty.path).header.checkpoint.simulation.has("continuous"))
		_replay(empty.path)
		var explicit_empty := _rewrite_continuous(empty.path, PackedFloat64Array(), "explicit-empty")
		check("explicit empty block inspects", Reader.inspect(explicit_empty).get("ok", false))
		_replay(explicit_empty)
		for mutation: Dictionary in [{name = "wrong-type", value = []},
			{name = "unexpected-state", value = PackedFloat64Array([1.0])}]:
			var refused: Dictionary = Reader.inspect(_rewrite_continuous(empty.path, mutation.value, mutation.name))
			check("reject " + mutation.name, not refused.get("ok", false) and str(refused.get("error", "")).contains("continuous"))
	# Control: the file-loaded Stik has wheel spin states; its nonempty block is still compared and accepted.
	var full := _record("nonempty-continuous", {})
	check("the file-loaded Stik has a nonempty continuous block", full.continuous_size > 0, str(full.continuous_size))
	check("a nonempty continuous block still records, inspects and prepares replay", full.ok, full.error)
	if full.ok:
		_replay(full.path)
		var changed: PackedFloat64Array = Reader.inspect(full.path).header.checkpoint.simulation.continuous.duplicate()
		changed[0] += 1.0
		var refused: Dictionary = Reader.inspect(_rewrite_continuous(full.path, changed, "changed-state"))
		check("nonempty initial-state disagreement refuses", not refused.get("ok", false) and str(refused.get("error", "")).contains("continuous"))
	print("Flight log empty continuous: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _record(label: String, frozen: Dictionary) -> Dictionary:
	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup(STIK, "", frozen)
	var out := {ok = false, error = "", path = "", continuous_size = flight.sim.continuous.size() if flight.sim != null else -1}
	if not flight.is_flyable():
		out.error = "not flyable"
		flight.free()
		return out
	var logger := Log.new(flight)
	var path := destination.path_join(label + ".orfl")
	out.path = path
	if logger.start(path) != OK:
		out.error = "log did not start"
		flight.free()
		return out
	for tick in 30:
		flight.sim.step()
	if logger.stop() != OK:
		out.error = "log did not stop"
		flight.free()
		return out
	var read: Dictionary = Reader.inspect(path)
	if not read.get("ok", false):
		out.error = "inspect: " + str(read.get("error", ""))
	elif read.rows != 31:
		out.error = "rows %d" % read.rows
	else:
		var replay: Dictionary = Reader.prepare_replay(read.header)
		out.ok = replay.get("ok", false)
		out.error = "" if out.ok else "prepare_replay: " + str(replay.get("error", replay.get("errors", "")))
		if replay.get("ok", false): replay.flight.free()
	flight.free()
	return out


func _replay(path: String) -> void:
	var read: Dictionary = Reader.inspect(path)
	check("complete replay input", read.get("ok", false) and read.get("complete", false))
	if not read.get("ok", false): return
	var replay: Dictionary = Reader.prepare_replay(read.header)
	check("exact replay prepares", replay.get("ok", false), str(replay.get("error", "")))
	if not replay.get("ok", false): return
	var stream := FileAccess.open(path, FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var observer := Log.new(replay.flight)
	var replayed := 0
	while stream.get_position() < stream.get_length():
		var packet: Dictionary = Log.read_packet(stream)
		check("replay packet verifies", packet.get("ok", false))
		if not packet.get("ok", false): break
		var block: Dictionary = packet.value
		if block.kind == "footer": break
		for row: Dictionary in block.get("rows", []):
			if row.tick == read.first_tick:
				check("exact initial replay sample", Reader.disagreement(row, observer._sample({})).is_empty())
				continue
			for key: String in row.intervention:
				replay.flight.sim.set(key, row.intervention[key].duplicate())
			replay.flight.sim.inputs = row.inputs.duplicate()
			replay.flight.sim.step()
			check("replay accepts tick %d" % row.tick, replay.flight.sim.tick == row.tick
				and replay.flight.sim.fault_reason.is_empty())
			check("exact replay tick %d" % row.tick, Reader.disagreement(row, observer._sample({})).is_empty())
			replayed += 1
	check("every recorded tick replayed", replayed == 30 and replay.flight.sim.tick == 30)
	stream.close()
	replay.flight.free()


## Change only the checkpoint field and regenerate packet/footer integrity.
func _rewrite_continuous(path: String, value: Variant, suffix: String) -> String:
	var input := FileAccess.open(path, FileAccess.READ)
	input.seek(8)
	var packet: Dictionary = Log.read_packet(input)
	var header: Dictionary = packet.value
	header.checkpoint.simulation.continuous = value
	var target := path + "." + suffix
	var output := FileAccess.open(target, FileAccess.WRITE)
	output.store_buffer(Log.MAGIC.to_ascii_buffer())
	var chain := Log.sha256(_store_packet(output, header))
	while input.get_position() < input.get_length():
		packet = Log.read_packet(input)
		var block: Dictionary = packet.value
		if block.kind == "footer":
			block.chain_sha256 = chain.hex_encode()
			_store_packet(output, block)
			break
		chain = Log.sha256(chain + _store_packet(output, block))
	input.close()
	output.close()
	return target


func _store_packet(output: FileAccess, value: Dictionary) -> PackedByteArray:
	var payload := var_to_bytes(value)
	var digest := Log.sha256(payload)
	output.store_32(payload.size())
	output.store_buffer(digest)
	output.store_buffer(payload)
	return digest
