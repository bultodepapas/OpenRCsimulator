## Linux disk-failure regression. Run through tools/flight_log/check_packet_writes.py.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FixedLog := preload("res://sim/flight_log.gd")
const Airship := preload("res://sim/airship/session.gd")
const AirshipLog := preload("res://sim/airship/flight_log.gd")
const Quad := preload("res://sim/multirotor/session.gd")
const QuadLog := preload("res://sim/multirotor/flight_log.gd")
const PREFIX := 65536
const DISK_ERROR := "Flight log disk write failed; file is incomplete."

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] not in ["limited", "control"]:
		printerr("Expected limited/control and a fresh output directory.")
		quit(2)
		return
	var limited := args[0] == "limited"
	for family: String in ["fixed", "airship", "quad"]:
		var session: Node
		var recorder: RefCounted
		if family == "fixed":
			session = Flight.new()
			session.input_enabled = false
			session.crash_auto_restart = false
			session.setup("res://data/aircraft/turbo_lumber_evolution.json")
			recorder = FixedLog.new(session)
		elif family == "airship":
			session = Airship.new()
			_check(session.prepare({}, {}), "prepare airship")
			recorder = AirshipLog.new(session)
		else:
			session = Quad.new()
			_check(session.prepare({}, {}), "prepare quad")
			recorder = QuadLog.new(session)
		for size: int in [0, 32768]:
			var label := "%s-%s-%d" % [args[0], family, size]
			var path := args[1].path_join(label + ".orfl")
			var started: Error = recorder.start(path) if family == "fixed" else recorder.start({}, path)
			_check(started == OK, label + " starts")
			if started == OK:
				_exercise(recorder, path, size, limited, 5 if family == "airship" else 6)
		session.free()
	print("ORFL write probe %s: %d failures" % [args[0], failures])
	quit(1 if failures else 0)


func _exercise(recorder: RefCounted, path: String, size: int, limited: bool, subscriptions: int) -> void:
	var file: FileAccess = recorder._file
	var chain: PackedByteArray = recorder._chain.duplicate()
	_check(chain.size() == 32 and recorder.get_incoming_connections().size() == subscriptions, path + " seeded and subscribed")
	var prefix := PackedByteArray()
	var remaining := PREFIX - file.get_position()
	if remaining < 0:
		_check(false, path + " header too large for fixture")
		recorder.stop()
		return
	prefix.resize(remaining)
	_check(file.store_buffer(prefix), path + " primes prefix")
	file.flush()
	_check(file.get_position() == PREFIX and file.get_length() == PREFIX, path + " prefix persisted")
	var data := PackedByteArray()
	data.resize(size)
	var value := {data = data}
	var frame_size := 36 + var_to_bytes(value).size()
	var wrote: bool = recorder._write_packet(value)
	var reopened := FileAccess.open(path, FileAccess.READ)
	var length := reopened.get_length() if reopened != null else -1
	if reopened != null:
		reopened.close()
	if limited:
		_check(not wrote and recorder.failure == DISK_ERROR and recorder.note == DISK_ERROR, path + " reports write failure")
		_check(not recorder.recording and recorder._file == null and not file.is_open(), path + " closed handle")
		_check(recorder.get_incoming_connections().is_empty(), path + " disconnected session")
		_check(recorder._chain == chain, path + " retained chain")
		_check(length == PREFIX, path + " still has only prefix")
	else:
		_check(wrote and recorder.recording and recorder.failure.is_empty() and file.is_open(), path + " accepted frame")
		_check(recorder._chain != chain and recorder._chain.size() == 32, path + " advanced chain")
		_check(recorder.get_incoming_connections().size() == subscriptions, path + " retained subscriptions")
		_check(length == PREFIX + frame_size, path + " wrote entire frame")
	print("%s wrote=%s prefix=%d frame=%d reopened=%d" % [path.get_file(), wrote, PREFIX, frame_size, length])
	if recorder.recording:
		recorder.stop()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL " + label)
