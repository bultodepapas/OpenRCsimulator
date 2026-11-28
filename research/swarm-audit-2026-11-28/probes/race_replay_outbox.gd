# Run against the pinned project, with a fresh output directory passed as --out=PATH.
# Exercises the session and the live scene's save-before-start operation without rendering.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const Log := preload("res://sim/multirotor/flight_log.gd")
const Director := preload("res://sim/race/race_director.gd")
const Wrapper := preload("res://sim/race/race_model.gd")
const Field := preload("res://data/field_loader.gd")
const Obstacles := preload("res://scenery/collision_setup.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const TRACK := "res://data/race/tracks/openrc-practice-oval-1.json"

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	printerr("AUDIT PROBE SETUP FAILED: " + message)
	quit(2)

func _run() -> void:
	var directory := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			directory = argument.trim_prefix("--out=")
	if directory.is_empty() or DirAccess.dir_exists_absolute(directory) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		_fail("provide a new --out directory")
		return
	var field := Field.load_from(Field.DEFAULT_PATH)
	var session := Session.new()
	root.add_child(session)
	if not field.ok or not session.set_collision_world(Obstacles.build(field.field).world) or not session.prepare(field.field, {race_track = TRACK, throttle_limit = 0.45}) or not session.resume():
		_fail("stock field/track preparation: " + session.load_error)
		return
	var idle := Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0, 1)
	var unavailable := directory.path_join("temporary-blocker")
	var file := FileAccess.open(unavailable, FileAccess.WRITE)
	if file == null:
		_fail("could not create storage fault fixture")
		return
	file.store_line("An ordinary file cannot be a results directory.")
	file.close()
	for attempt: int in Session.MAX_PENDING_RESULTS:
		if not session.tick_once(idle, Director.ACTION_START) or session.sim.modes[Wrapper.MODE_PHASE] != Director.PHASE_COUNTDOWN or not session.reset_to_pad() or not session.resume():
			_fail("pre-recording pad reset %d" % attempt)
			return
		var blocked := session.save_results(unavailable)
		if blocked.failed != attempt + 1:
			_fail("expected each pending result to remain after a failed save")
			return
	var orfl := directory.path_join("full-outbox.orfl")
	var log_owner := Log.new(session)
	if session.sim.modes[Wrapper.MODE_PHASE] != Director.PHASE_IDLE or log_owner.start({field_path = Field.DEFAULT_PATH}, orfl) != OK:
		_fail("could not begin live IDLE/on-pad F10 capture")
		return
	var pending_at_start: int = session.results.size()
	# request_race() retries a full queue before admitting a start on an already idle pad.
	var saved := session.save_results(directory.path_join("recovered-storage"))
	var live_accepted := session.tick_once(idle, Director.ACTION_START)
	if saved.saved != pending_at_start or not session.results.is_empty() or not live_accepted or log_owner.stop() != OK:
		_fail("the restored storage did not allow the live start")
		return
	var report := Log.verify(orfl)
	var control_path := directory.path_join("empty-outbox.orfl")
	if not session.reset_to_pad() or session.save_results(directory.path_join("recovered-storage")).failed != 0 or not session.resume():
		_fail("could not reset for the positive control")
		return
	var control_owner := Log.new(session)
	if control_owner.start({field_path = Field.DEFAULT_PATH}, control_path) != OK or not session.tick_once(idle, Director.ACTION_START) or control_owner.stop() != OK:
		_fail("could not record the empty-outbox control")
		return
	var control := Log.verify(control_path)
	var receipt := {pending_at_start = pending_at_start, live_saved = saved.saved, live_accepted = live_accepted, full = report, empty = control}
	print("RACE_OUTBOX_RECEIPT " + JSON.stringify(receipt))
	session.free()
	var observed: bool = report.complete and report.rows == 1 and report.identity_match and not report.solver_changed and not report.ok and not report.exact and report.first_mismatch_tick == 1 and control.ok and control.exact
	print("RACE_OUTBOX_COUNTEREXAMPLE=", observed)
	quit(0 if observed else 1)
