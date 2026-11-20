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
	# A flight that ends in a terminal strike: the replay must end in the same strike at the same tick.
	var drop: Node = Session.new()
	root.add_child(drop)
	drop.set_collision_world(CollisionSetup.build(field).world)
	drop.prepare(field, {altitude_m = 1.2})
	var fast: PackedFloat64Array = drop.sim.state.duplicate()
	fast[5] = 3.0
	drop.sim.continuous = drop.start_continuous.duplicate()
	drop.sim.reset(fast)
	drop.resume(PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	var crash_path := DIR + "/crash.orfl"
	var third := AirshipLog.new(drop)
	third.start({field_path = FieldLoader.DEFAULT_PATH}, crash_path)
	for i in 480:
		if not drop.tick_once(PackedFloat64Array([0.0, 0.0, 0.0, 0.0])):
			break
	third.stop("after strike")
	var crash_read := AirshipLog.inspect(crash_path)
	var crash_report := AirshipLog.verify(crash_path)
	_check("a strike ends the recorded flight and replays as the same strike", not drop.crash.is_empty() and crash_report.ok
		and crash_report.recorded_crash == str(drop.crash.reason) and crash_report.replayed_crash == crash_report.recorded_crash, JSON.stringify(crash_report))
	var no_crash: Dictionary = crash_read.duplicate(true)
	no_crash.events = no_crash.events.filter(func(event: Dictionary) -> bool: return event.kind != "crash")
	probe = Session.new()
	var outcome := AirshipLog._replay(probe, field, crash_read.header, no_crash, {identity_match = false, exact = false, ok = false, first_mismatch_tick = -1, error = ""})
	probe.free()
	_check("a replay whose terminal outcome differs is refused", not outcome.ok, str(outcome.error))
	_check_refused_restore(s)
	_clean()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


# Audit 2026-11-19 F03: a refused checkpoint restore has no externally visible effect; an accepted
# one still announces the reset and closes the active log completely.
func _check_refused_restore(s: Node) -> void:
	var zero_sticks := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	s.resume(zero_sticks)
	for i in 60:
		s.tick_once(_sticks(i))
	var keep_path := DIR + "/restore_refused.orfl"
	var keeper := AirshipLog.new(s)
	_check("restore test: recording starts", keeper.start({field_path = FieldLoader.DEFAULT_PATH}, keep_path) == OK)
	for i in 30:
		s.tick_once(_sticks(60 + i))
	var resets := [0]
	var faults := [0]
	var on_reset := func() -> void: resets[0] += 1
	var on_fault := func(_reason: String) -> void: faults[0] += 1
	s.resetting.connect(on_reset)
	s.faulted.connect(on_fault)
	var live_state: PackedByteArray = s.sim.state.to_byte_array()
	var live_continuous: PackedByteArray = s.sim.continuous.to_byte_array()
	var live_inputs: PackedByteArray = s.sim.inputs.to_byte_array()
	var live_tape: PackedByteArray = s.tape.to_byte_array()
	var live_tick: int = s.sim.tick
	var live_time: float = s.sim.time()
	var good_continuous: PackedFloat64Array = s.continuous_snapshot()
	var nan_body: PackedFloat64Array = s.state_snapshot()
	nan_body[0] = NAN
	var zero_quaternion: PackedFloat64Array = s.state_snapshot()
	for i in 4:
		zero_quaternion[6 + i] = 0.0
	var short_body: PackedFloat64Array = s.state_snapshot().slice(0, 12)
	var nan_continuous: PackedFloat64Array = good_continuous.duplicate()
	nan_continuous[0] = NAN
	var refusals: Array[bool] = [s.restore_checkpoint(nan_body, good_continuous),
		s.restore_checkpoint(zero_quaternion, good_continuous), s.restore_checkpoint(short_body, good_continuous),
		s.restore_checkpoint(s.state_snapshot(), nan_continuous),
		s.restore_checkpoint(s.state_snapshot(), good_continuous.slice(0, good_continuous.size() - 1))]
	_check("malformed checkpoint bodies or continuous data are refused", not refusals.has(true), str(refusals))
	_check("a refused restore emits no reset and no fault", resets[0] == 0 and faults[0] == 0,
		"%d resets, %d faults" % [resets[0], faults[0]])
	_check("a refused restore leaves state, continuous, inputs, tape and clock unchanged",
		s.sim.state.to_byte_array() == live_state and s.sim.continuous.to_byte_array() == live_continuous
		and s.sim.inputs.to_byte_array() == live_inputs and s.tape.to_byte_array() == live_tape
		and s.sim.tick == live_tick and s.sim.time() == live_time)
	_check("a refused restore does not fault or pause the flight", s.fault_reason.is_empty()
		and s.sim.fault_reason.is_empty() and not s.paused and not s.sim.paused)
	_check("a refused restore leaves the recorder open", keeper.recording and keeper.failure.is_empty())
	_check("the flight and its recording continue after a refused restore", s.tick_once(_sticks(90)) and keeper.recording)
	var accepted: bool = s.restore_checkpoint(s.state_snapshot(), good_continuous)
	var kept := AirshipLog.inspect(keep_path)
	_check("a valid restore is accepted and keeps the flight running", accepted and s.sim.tick == 0
		and s.sim.inputs == zero_sticks and s.fault_reason.is_empty() and not s.paused and not s.sim.paused)
	_check("a valid restore announces the reset once and closes a complete log", resets[0] == 1 and faults[0] == 0
		and not keeper.recording and kept.ok and kept.complete and kept.ticks.size() == 31,
		"%d resets, %s" % [resets[0], str(kept.get("error", kept.get("ticks", []).size()))])
	s.resetting.disconnect(on_reset)
	s.faulted.disconnect(on_fault)


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
