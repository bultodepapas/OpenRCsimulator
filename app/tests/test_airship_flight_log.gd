# BL-08: RC blimp flight log. A recording started mid-flight on the real field (terrain and obstacles) replays
# byte-exactly from its checkpoint; corruption, truncation, a changed session identity and a changed stick row are
# all detected; a reset closes a complete file; fixed-wing tools refuse the airship format.
extends SceneTree

const Session := preload("res://sim/airship/session.gd")
const AirshipLog := preload("res://sim/airship/flight_log.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const FlightLogCli := preload("res://tools/flight_log_cli.gd")

const DIR := "user://test_airship_flight_log"

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


static func _sticks(i: int) -> PackedFloat64Array:
	var t := float(i) / 240.0
	return PackedFloat64Array([0.3 * sin(t), 0.4 * sin(0.6 * t), 0.05 * cos(0.4 * t), clampf(0.5 + 0.4 * sin(0.3 * t), 0.0, 1.0)])


func _initialize() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var s: Node = Session.new()
	root.add_child(s)
	s.set_collision_world(CollisionSetup.build(field).world)
	_check("session prepares on the real field", s.prepare(field, {wind_speed_mps = 1.5, wind_from_deg = 250.0}), str(s.load_error))
	s.resume(PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	for i in 480:
		s.tick_once(_sticks(i))
	var log_path := DIR + "/flight.orfl"
	var recorder := AirshipLog.new(s)
	_check("recording starts mid-flight", recorder.start({field_path = FieldLoader.DEFAULT_PATH}, log_path) == OK and s.sim.tick == 480)
	for i in range(480, 2400):
		if i == 1200:
			s.pause("pilot pause")
			recorder.mark("after pause")
			s.resume(PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
		s.tick_once(_sticks(i))
	var final_state: PackedByteArray = s.sim.state.to_byte_array()
	_check("recording stops cleanly", recorder.stop("test end") == OK and not recorder.recording and recorder.rows_written == 1920,
		"%d rows" % recorder.rows_written)
	var read := AirshipLog.inspect(log_path)
	_check("complete file with checksummed blocks and chain", read.ok and read.complete and read.ticks.size() == 1920, str(read.get("error", "")))
	var kinds: Array = []
	for event: Dictionary in read.get("events", []):
		kinds.append(event.kind)
	_check("pause, marker, resume and stop events are kept", kinds.has("pause") and kinds.has("marker") and kinds.has("resume") and kinds.has("stop"), str(kinds))
	_check("last recorded row is the live final state",
		read.states.slice(read.states.size() - 13).to_byte_array() == final_state)
	var report := AirshipLog.verify(log_path)
	_check("exact replay from the mid-flight checkpoint", report.ok and report.exact and report.identity_match and not report.solver_changed
		and report.rows == 1920, JSON.stringify(report))
	# Changed identity and changed sticks are detected.
	var head: Dictionary = read.header.duplicate(true)
	head.session.law = "another-law"
	var probe: Node = Session.new()
	var mismatch := AirshipLog._replay(probe, field, head, read, {identity_match = false, exact = false, ok = false, first_mismatch_tick = -1, error = ""})
	probe.free()
	_check("a different session identity is refused", not mismatch.identity_match and not mismatch.ok, str(mismatch.error))
	var tampered: Dictionary = read.duplicate(true)
	tampered.sticks[4 * 700 + 2] = 0.9
	probe = Session.new()
	var diverged := AirshipLog._replay(probe, field, read.header, tampered, {identity_match = false, exact = false, ok = false, first_mismatch_tick = -1, error = ""})
	probe.free()
	_check("a changed stick row is found at its tick", not diverged.exact and int(diverged.first_mismatch_tick) == int(read.ticks[700]),
		"%s at %d" % [diverged.error, diverged.first_mismatch_tick])
	# Corruption and truncation.
	var bytes := FileAccess.get_file_as_bytes(log_path)
	var corrupt := bytes.duplicate()
	corrupt[bytes.size() / 2] = corrupt[bytes.size() / 2] ^ 0xFF
	_write(DIR + "/corrupt.orfl", corrupt)
	_check("a flipped byte is refused", not AirshipLog.verify(DIR + "/corrupt.orfl").ok)
	_write(DIR + "/truncated.orfl", bytes.slice(0, bytes.size() - 200))
	var truncated := AirshipLog.verify(DIR + "/truncated.orfl")
	_check("a truncated file is refused as incomplete", not truncated.ok and not truncated.complete, str(truncated.error))
	_check("fixed-wing tools refuse the airship format", not FlightLogCli.inspect(log_path).ok)
	# A reset closes the file completely.
	var reset_path := DIR + "/reset.orfl"
	var second := AirshipLog.new(s)
	second.start({field_path = FieldLoader.DEFAULT_PATH}, reset_path)
	for i in 120:
		s.tick_once(_sticks(i))
	s.reset()
	var closed := AirshipLog.inspect(reset_path)
	_check("a reset closes a complete log", not second.recording and closed.ok and closed.complete and closed.ticks.size() == 120)
	_check("refuses to overwrite an existing log", AirshipLog.new(s).start({}, log_path) == ERR_ALREADY_EXISTS)
	_clean()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _write(file_path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _clean() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(dir):
		for name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(name))
		DirAccess.remove_absolute(dir)
