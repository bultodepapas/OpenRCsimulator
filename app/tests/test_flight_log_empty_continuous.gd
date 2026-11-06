# External audit A6 F5: a valid aircraft whose kernel has no continuous state (here the Ugly Stik validated in memory,
# before its optional file-boundary wheel profile adds wheel spin states) must record, inspect and prepare replay.
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
	# Control: the file-loaded Stik has wheel spin states; its nonempty block is still compared and accepted.
	var full := _record("nonempty-continuous", {})
	check("the file-loaded Stik has a nonempty continuous block", full.continuous_size > 0, str(full.continuous_size))
	check("a nonempty continuous block still records, inspects and prepares replay", full.ok, full.error)
	print("Flight log empty continuous: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _record(label: String, frozen: Dictionary) -> Dictionary:
	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup(STIK, "", frozen)
	var out := {ok = false, error = "", continuous_size = flight.sim.continuous.size() if flight.sim != null else -1}
	if not flight.is_flyable():
		out.error = "not flyable"
		flight.free()
		return out
	var logger := Log.new(flight)
	var path := destination.path_join(label + ".orfl")
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
	flight.free()
	return out
