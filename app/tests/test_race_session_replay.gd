# DR-17 for race sessions (REPLAY-01, RACE-15): a complete three-lap local race flown by the scripted pilot of
# test_race_session.gd is recorded with the multirotor flight log and verified by exact replay. The log carries the
# ten-value kernel input rows (pilot frame plus race action) and the race suffixes; the replay rebuilds the race
# session from the header, restores the recorded envelope and reruns controller and race director from the tape.
# Same build and platform only; local practice rules, no federation compliance claim.
extends SceneTree

const RaceTest := preload("res://tests/test_race_session.gd")
const Session := preload("res://sim/multirotor/session.gd")
const MultirotorLog := preload("res://sim/multirotor/flight_log.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const Director := preload("res://sim/race/race_director.gd")
const RaceModel := preload("res://sim/race/race_model.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")

const DIR := "user://test_race_session_replay"
const TICK_LIMIT := 240 * 100

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))
	DirAccess.remove_absolute(DIR)


func _run() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var world: Dictionary = CollisionSetup.build(loaded.field).world
	var s: Node = Session.new()
	root.add_child(s)
	s.set_collision_world(world)
	var prepared: bool = s.prepare(loaded.field, {race_track = RaceTest.TRACK, throttle_limit = RaceTest.THROTTLE_LIMIT})
	_check("a race session prepares for recording", prepared, s.load_error)
	if not prepared:
		_finish()
		return
	var laps: Array = []
	var finished := [false]
	s.race_event.connect(func(event: Dictionary) -> void:
		if event.type == "race_lap":
			laps.append(float(event.duration_s))
		elif event.type == "race_finish":
			finished[0] = true)
	var path := DIR + "/race.orfl"
	var recorder := MultirotorLog.new(s)
	_check("the recorder starts on the prepared race session with the race row widths", recorder.start(
		{field_path = FieldLoader.DEFAULT_PATH}, path) == OK and int(recorder.header.layout.pilot) == RaceModel.INPUT_SIZE
		and int(recorder.header.layout.aux) == RaceModel.AUX_SIZE and int(recorder.header.layout.modes) == RaceModel.MODES_SIZE,
		recorder.note)
	s.resume()
	var idle: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0, 1)
	var armed: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1, 1)
	var ok: bool = s.tick_once(idle, Director.ACTION_START)
	# Countdown: OFF observed, then the arm switch ON at low throttle; GO is sampled at countdown tick 720.
	for i in 720:
		ok = ok and s.tick_once(idle if i < 3 else armed)
	_check("the countdown ends in RACING", ok and s.sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_RACING)
	var pilot: RefCounted = RaceTest.Pilot.new()
	pilot.cruise_mps = RaceTest.CRUISE_MPS
	var pad := PackedFloat64Array([float(s.course.pad.north), float(s.course.pad.east)])
	pilot.fly(RaceTest.race_route(s.course, 3), pad)
	for _i in TICK_LIMIT:
		if finished[0] or not s.crash.is_empty() or not ok:
			break
		ok = ok and s.tick_once(pilot.command(s))
	_check("the scripted pilot finishes three laps while recording", ok and finished[0] and laps.size() == 3 and s.crash.is_empty(),
		"laps %s crash %s" % [str(laps), str(s.crash)])
	var final_tick: int = s.sim.tick
	var final_aux: PackedByteArray = s.sim.aux.to_byte_array()
	_check("the recording closes complete", recorder.stop("race finished") == OK and recorder.rows_written == final_tick,
		"%d rows of %d ticks %s" % [recorder.rows_written, final_tick, recorder.failure])
	var read: Dictionary = MultirotorLog.inspect(path)
	var actions := 0
	if read.ok:
		for i in read.ticks.size():
			if read.pilot[RaceModel.INPUT_SIZE * i + RaceModel.IN_RACE_ACTION] != 0.0:
				actions += 1
	_check("the log holds ten-value kernel rows with exactly the one start action", read.ok and read.complete
		and read.pilot.size() == RaceModel.INPUT_SIZE * final_tick and actions == 1, str(read.get("error", "")))
	var report: Dictionary = MultirotorLog.verify(path)
	_check("REPLAY-01 the whole race replays exactly from its pilot tape", report.ok and report.exact and report.complete
		and not report.solver_changed and report.identity_match and report.rows == final_tick and report.first_mismatch_tick == -1,
		str(report.get("error", "")))
	_check("the recorded final frame is the FINISHED frame with the three lap durations (bitwise)", read.ok
		and read.aux.slice(RaceModel.AUX_SIZE * (final_tick - 1)).to_byte_array() == final_aux
		and read.modes[RaceModel.MODES_SIZE * (final_tick - 1) + RaceModel.MODE_PHASE] == Director.PHASE_FINISHED
		and read.aux[RaceModel.AUX_SIZE * (final_tick - 1) + RaceModel.AUX_LAP_DURATION] == laps[0]
		and read.aux[RaceModel.AUX_SIZE * (final_tick - 1) + RaceModel.AUX_LAP_DURATION + 2] == laps[2])
	s.queue_free()
	_finish()


func _finish() -> void:
	_clean()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
