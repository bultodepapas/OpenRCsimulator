# Audit observation probe for OpenRCsimulator cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b.
# Run only with the repository's checked runner / isolated environment after reviewing this script.
# Set OPENRC_RACE_AUDIT_DIR to an isolated scratch directory; this script creates a fresh child there.
# It performs no cleanup and does not use user://race_results. A passing check demonstrates the
# BASELINE DEFECT, so these checks should fail (or be rewritten) after a correct repair.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const Track := preload("res://sim/race/track.gd")
const Director := preload("res://sim/race/race_director.gd")
const RaceModel := preload("res://sim/race/race_model.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const RB := preload("res://physics/rigid_body.gd")
const TRACK_PATH := "res://data/race/tracks/openrc-practice-oval-1.json"
const DT := 1.0 / 240.0

var field: Dictionary
var work_dir := ""
var checks := 0
var failures := 0
var sessions: Array[Node] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, value: bool, detail: String = "") -> void:
	checks += 1
	if not value:
		failures += 1
	print("%s %s %s" % ["OBSERVED" if value else "NOT OBSERVED", label, detail])

func _new_session(limit: float = 1.0) -> Node:
	var s: Node = Session.new()
	root.add_child(s)
	sessions.append(s)
	var ok: bool = s.prepare(field, {race_track = TRACK_PATH, throttle_limit = limit})
	_check("fixture prepares", ok and s.race != null, str(s.load_error))
	return s

func _start(s: Node) -> bool:
	return s.resume() and s.tick_once(FC.neutral_input(), Director.ACTION_START) \
		and s.sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_COUNTDOWN

func _point(gate: Dictionary, normal: float, across: float) -> PackedFloat64Array:
	var p := PackedFloat64Array()
	for i in 3:
		p.append(float(gate.c[i]) + normal * float(gate.n[i]) + across * float(gate.u[i]))
	return p

func _set_position(body: PackedFloat64Array, p: PackedFloat64Array) -> void:
	for i in 3:
		body[RB.POS + i] = p[i]

func _result_types(events: Array) -> String:
	var names := PackedStringArray()
	for event: Dictionary in events:
		names.append(str(event.get("type", "")))
	return ",".join(names)

# Uses the real prepared course and the real obstacle query and crash_reason; Director.advance
# receives the same chord and end-of-tick event timestamp the production wrapper uses.
# This isolates the ordering problem without assuming an input tape can reproduce that chord.
func _finish_after_earlier_contact(s: Node) -> void:
	var gate: Dictionary = s.course.gates.back()
	var radius: float = float(s._body_radius)
	var across: float = float(gate.w) - (radius - 0.0006)
	var p0 := _point(gate, -0.04, across)
	var p_contact := _point(gate, -0.034, across)
	var p1 := _point(gate, 0.06, across)
	var before: PackedFloat64Array = s.frame().body.duplicate()
	var after: PackedFloat64Array = before.duplicate()
	_set_position(before, p0)
	_set_position(after, p1)
	var clear_before: float = s.plant.obstacle.call(p0[0], p0[1], p0[2])
	var clear_contact: float = s.plant.obstacle.call(p_contact[0], p_contact[1], p_contact[2])
	var reason: String = s.plant.crash_reason(before, after, s.frame().continuous)
	var aux := Director.empty_aux(float(s.course.tag))
	var modes := Director.empty_modes()
	aux[Director.A_GO_TIME] = 1.0
	aux[Director.A_LAP_START] = 4.0
	aux[Director.A_LAP_DURATION] = 1.0
	aux[Director.A_LAP_DURATION + 1] = 2.0
	aux[Director.A_LAST_GATE_TIME] = 4.0
	modes[Director.D_PHASE] = Director.PHASE_RACING
	modes[Director.D_ATTEMPT] = 1
	modes[Director.D_VALID_LAPS] = 2
	modes[Director.D_NEXT_GATE] = int(s.course.gate_count) - 1
	modes[Director.D_GATES_TOTAL] = 3 * int(s.course.gate_count) - 1
	var p := {p0 = p0, t0 = 5.0, p1 = p1, t1 = 5.0 + DT, qualified = true}
	var physical := [{type = "crash", time_s = 5.0 + DT, reason = reason}]
	var out: Dictionary = Director.advance({aux = aux, modes = modes}, p, physical, s.course, Track.ruleset(), {tick = 1201})
	var f: Dictionary = s.frame()
	for i in Director.AUX_SIZE:
		f.aux[RaceModel.AUX_RACE + i] = out.aux_suffix[i]
	for i in Director.MODES_SIZE:
		f.modes[RaceModel.MODES_RACE + i] = out.modes_suffix[i]
	var projected: Dictionary = s.race.result(f)
	var events := _result_types(out.events)
	_check("finish is valid although gate-frame contact occurred before crossing",
		clear_before > radius and clear_contact < radius and reason == "Obstacle strike" \
		and out.modes_suffix[Director.D_PHASE] == Director.PHASE_FINISHED and bool(projected.valid) \
		and events == "race_gate,race_lap,race_finish,crash",
		"radius %.9f before %.9f contact %.9f reason=%s events=%s" % [radius, clear_before, clear_contact, reason, events])

func _course_identity() -> void:
	var loaded: Dictionary = Track.load_file(TRACK_PATH)
	var flat := func(_n: float, _e: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var first: Dictionary = Track.prepare(loaded.track, field, flat)
	if not first.ok:
		_check("course fixture prepares", false, str(first.errors))
		return
	var post: Dictionary = first.course.frames[0]
	var altered := func(n: float, e: float) -> PackedFloat64Array:
		var height := 0.2 if absf(n - float(post.north)) < 1.0e-7 and absf(e - float(post.east)) < 1.0e-7 else 0.0
		return PackedFloat64Array([height, 0.0, 0.0])
	var second: Dictionary = Track.prepare(loaded.track, field, altered)
	_check("different ground at a post changes solid frame without changing course identity",
		second.ok and first.course.identity == second.course.identity \
		and var_to_bytes(first.course.frames[0]) != var_to_bytes(second.course.frames[0]),
		"first=%s second=%s" % [str(first.course.frames[0]), str(second.course.get("frames", [{}])[0]) if second.ok else str(second.errors)])

func _distinct_results_and_metadata() -> void:
	var a := _new_session(1.0)
	var b := _new_session(0.8)
	if not a.prepared or not b.prepared:
		return
	var matched := false
	var record_a := {}
	var record_b := {}
	var old_tick := 0
	# Construct real countdown/pad-reset aborts. The configuration differs, making the
	# records distinguishable while leaving the course and track_id unchanged.
	for _i in 12:
		if not (_start(a) and _start(b)):
			break
		if not a.tick_once(FC.neutral_input()):
			break
		old_tick = int(a.sim.tick)
		if not (a.reset_to_pad() and b.reset_to_pad()):
			break
		record_a = a.results.back().duplicate(true)
		record_b = b.results.back().duplicate(true)
		if record_a.created_utc == record_b.created_utc and record_a.sequence == record_b.sequence:
			matched = true
			break
		a.discard_results()
		b.discard_results()
	_check("reset abort attributes old attempt to tick zero and leaves the reason code as none",
		not record_a.is_empty() and old_tick > 0 and int(record_a.terminal_tick) == 0 \
		and str(record_a.reason) == "pad_reset" and int(record_a.reason_code) == Director.REASON_NONE,
		"actual old tick=%d record=%s" % [old_tick, str(record_a)])
	if not matched:
		_check("two aborts land in same UTC second", false, "timing inconclusive after 12 tries")
		return
	var dir := work_dir.path_join("filename-collision")
	var one: Dictionary = a.save_results(dir)
	var two: Dictionary = b.save_results(dir)
	var path_one := str(one.paths[0]) if one.paths.size() == 1 else ""
	var path_two := str(two.paths[0]) if two.paths.size() == 1 else ""
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_two)) if not path_two.is_empty() else null
	_check("two distinct sessions silently replace each other's result at the same filename",
		str(record_a.session.controller) != str(record_b.session.controller) \
		and int(one.saved) == 1 and int(two.saved) == 1 and not path_one.is_empty() and path_one == path_two \
		and typeof(stored) == TYPE_DICTIONARY and str(stored.session.controller) == str(record_b.session.controller),
		"first=%s second=%s" % [path_one, path_two])

func _restore_discards_newer_pending() -> void:
	var s := _new_session()
	if not s.prepared or not _start(s):
		_check("restore fixture starts", false, str(s.load_error))
		return
	var old: Dictionary = s.checkpoint()
	var reset: bool = s.tick_once(FC.neutral_input()) and s.reset_to_pad()
	var had_one: bool = reset and s.results.size() == 1
	var restored: bool = s.restore_checkpoint(old)
	_check("restoring an older checkpoint silently drops a newer unsaved result",
		had_one and restored and s.results.is_empty(), "had_one=%s restored=%s" % [had_one, restored])

# Mimics the activity's one save attempt per result with an initially blocked path.
# Source inspection establishes that the actual activity has no independent retry UI.
func _full_outbox_after_write_failure() -> void:
	var s := _new_session()
	if not s.prepared:
		return
	var blocked := work_dir.path_join("blocked-destination")
	var file := FileAccess.open(blocked, FileAccess.WRITE)
	if file == null:
		_check("create blocked destination", false, error_string(FileAccess.get_open_error()))
		return
	file.store_string("a regular file, not a directory")
	file.close()
	var failures_seen := []
	s.race_result.connect(func(_result: Dictionary) -> void:
		var report: Dictionary = s.save_results(blocked)
		failures_seen.append(int(report.failed)))
	var ok := true
	for _i in Session.MAX_PENDING_RESULTS:
		ok = ok and _start(s) and s.reset_to_pad()
	var pending: int = s.results.size()
	var removed: Error = DirAccess.remove_absolute(blocked)
	var made: Error = DirAccess.make_dir_recursive_absolute(blocked)
	var resumed: bool = s.resume()
	var accepted: bool = s.tick_once(FC.neutral_input(), Director.ACTION_START)
	_check("full outbox still refuses starts after storage becomes writable",
		ok and failures_seen.size() == Session.MAX_PENDING_RESULTS and pending == Session.MAX_PENDING_RESULTS \
		and removed == OK and made == OK and resumed and not accepted and s.results.size() == pending,
		"save failures=%s pending=%d start accepted=%s" % [str(failures_seen), pending, accepted])

func _run() -> void:
	var output_root := OS.get_environment("OPENRC_RACE_AUDIT_DIR")
	if output_root.is_empty() or not output_root.is_absolute_path():
		print("Set OPENRC_RACE_AUDIT_DIR to an absolute, isolated scratch directory.")
		quit(2)
		return
	work_dir = output_root.path_join("race-repro-%s" % str(Time.get_ticks_usec()))
	var made: Error = DirAccess.make_dir_recursive_absolute(work_dir)
	var loaded: Dictionary = FieldLoader.load_from()
	if made != OK or not loaded.ok:
		print("Fixture setup failed: directory=%s field=%s" % [error_string(made), str(loaded.get("errors", []))])
		quit(2)
		return
	field = loaded.field
	var s := _new_session()
	if s.prepared:
		_finish_after_earlier_contact(s)
	_course_identity()
	_distinct_results_and_metadata()
	_restore_discards_newer_pending()
	_full_outbox_after_write_failure()
	for item: Node in sessions:
		item.queue_free()
	print("%d checks, %d not observed; outputs: %s" % [checks, failures, work_dir])
	quit(1 if failures > 0 else 0)
