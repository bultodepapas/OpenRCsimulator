# DR-23/24/25/26/26a/31 (FPV audit 2026-11-16, A10-A17): race validity, result retention and saved preferences.
# A crash on a tick's endpoint voids that tick's finish (composed RK4/session/race tick); unsaved results recover once
# the storage is repaired and are never dropped silently on leaving; result files have a stable unique identity and are
# never replaced; the record book survives a failed replacement and loads only complete entries; a pad reset keeps its
# terminal context; a course's identity follows its resolved solids; a failed OSD save is reported. Isolated user://
# folders; graceful-session guarantees only (no fsync, power-loss or native OS rename qualification).
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const Hud := preload("res://vehicles/multirotor/multirotor_hud.gd")
const Track := preload("res://sim/race/track.gd")
const Gates := preload("res://sim/race/gate_crossing.gd")
const Director := preload("res://sim/race/race_director.gd")
const RaceModel := preload("res://sim/race/race_model.gd")
const RaceRecords := preload("res://vehicles/multirotor/race_records.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const RB := preload("res://physics/rigid_body.gd")
const TRACK := "res://data/race/tracks/openrc-practice-oval-1.json"
const DIR := "user://test_mr_race_integrity"
const DT := 1.0 / 240.0

var _count := 0
var _failures := 0
var _field: Dictionary = {}
var _nodes: Array[Node] = []


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(DIR)
	_field = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	_same_tick_crash()
	_pad_reset_context()
	_publication_identity()
	_book_replacement()
	_book_entries()
	_course_identity()
	await _outbox_recovery()
	_osd_save()
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_clean(ProjectSettings.globalize_path(DIR))
	print("race integrity: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _clean(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in DirAccess.get_directories_at(path):
		_clean(path.path_join(child))
	DirAccess.remove_absolute(path)


func _session() -> Node:
	var s: Node = Session.new()
	root.add_child(s)
	_nodes.append(s)
	_check("race session prepares", s.prepare(_field, {race_track = TRACK}) and s.race != null, str(s.load_error))
	return s


## Start a countdown, hold it `ticks` accepted ticks, then abort it with a pad reset: one pending record.
func _abort(s: Node, ticks: int) -> bool:
	var ok: bool = s.resume() and s.tick_once(FC.neutral_input(), Director.ACTION_START)
	for i in ticks - 1:
		ok = ok and s.tick_once(FC.neutral_input())
	return ok and s.reset_to_pad()


## A10: the audit's composed witness (initialized final-lap state, one real session tick through RK4, the plant
## endpoint and the race wrapper): the crash is decided on the tick's endpoint, so the finish on that chord is void.
func _same_tick_crash() -> void:
	var s := _session()
	var gate: Dictionary = s.course.gates.back()
	var across: float = float(gate.w) - (float(s._body_radius) - 0.0006)
	var envelope: Dictionary = s.checkpoint()
	var body: PackedFloat64Array = envelope.kernel.state.duplicate()
	for i in 3:
		body[RB.POS + i] = float(gate.c[i]) - 0.04 * float(gate.n[i]) + across * float(gate.u[i])
		body[RB.VEL + i] = 24.0 * float(gate.n[i])
		body[RB.RATE + i] = 0.0
	body[RB.ATT] = 1.0
	for i in range(1, 4):
		body[RB.ATT + i] = 0.0
	envelope.kernel.state = body.duplicate()
	envelope.kernel.previous = body.duplicate()
	envelope.kernel.tick = 1200
	var aux: PackedFloat64Array = envelope.kernel.aux.duplicate()
	aux[RaceModel.AUX_GO_TIME] = 1.0
	aux[RaceModel.AUX_LAP_START] = 4.0
	aux[RaceModel.AUX_LAP_DURATION] = 1.0
	aux[RaceModel.AUX_LAP_DURATION + 1] = 2.0
	aux[RaceModel.AUX_LAST_GATE_TIME] = 4.0
	aux[RaceModel.AUX_ATTEMPT_START] = 1.0
	envelope.kernel.aux = aux
	var modes: PackedInt64Array = envelope.kernel.modes.duplicate()
	modes[RaceModel.MODE_PHASE] = Director.PHASE_RACING
	modes[RaceModel.MODE_ATTEMPT] = 1
	modes[RaceModel.MODE_VALID_LAPS] = 2
	modes[RaceModel.MODE_NEXT_GATE] = int(s.course.gate_count) - 1
	modes[RaceModel.MODE_GATES_TOTAL] = 3 * int(s.course.gate_count) - 1
	envelope.kernel.modes = modes
	if not s.restore_checkpoint(envelope) or not s.resume():
		_check("A10 setup: initialized final-lap state restores", false, str(s.load_error))
		return
	var p0: PackedFloat64Array = s.frame().body.slice(RB.POS, RB.POS + 3)
	var ticked: bool = s.tick_once(FC.neutral_input())
	var p1: PackedFloat64Array = s.frame().body.slice(RB.POS, RB.POS + 3)
	var crossing: Dictionary = Gates.crossing(gate, p0, 5.0, p1, 5.0 + DT, 1.0e-3)
	_check("A10 premise: the accepted chord crosses the finish gate and the endpoint is an obstacle strike",
		ticked and crossing.crossed and str(s.crash.get("reason", "")) == "Obstacle strike", str(s.crash))
	var names := PackedStringArray()
	for event: Dictionary in s.sim.last_events:
		names.append(str(event.get("type", "")))
	var result: Dictionary = s.results[0] if s.results.size() == 1 else {}
	_check("A10 the same-tick finish is void: crash then abort, an invalid ABORTED result",
		",".join(names) == "crash,race_abort" and not bool(result.get("valid", true)) and str(result.get("phase", "")) == "ABORTED"
		and str(result.get("reason", "")) == "crash", ",".join(names) + " " + str(result.get("phase", "")))


## A14: the pad reset's published record keeps the aborted attempt's terminal tick and has a consistent reason code.
func _pad_reset_context() -> void:
	var s := _session()
	var published: Array = []
	s.race_result.connect(func(record: Dictionary) -> void: published.append(record))
	_abort(s, 3)
	var record: Dictionary = published[0] if published.size() == 1 else {}
	_check("A14 a pad-reset abort keeps its terminal tick (3, not the new tick 0) and time", int(record.get("terminal_tick", -1)) == 3
		and float(record.get("terminal_time_s", 0.0)) > 0.0 and int(s.sim.tick) == 0, str(record.get("terminal_tick", "")))
	_check("A14 reason and reason code agree", str(record.get("reason", "")) == "pad_reset"
		and int(record.get("reason_code", -1)) == Director.REASON_PAD_RESET
		and Director.REASON_NAMES[int(record.reason_code)] == str(record.reason))


## A12/A13 (results): two sessions with the same course, second and sequence never share a file; a retry keeps its id
## and is idempotent; another payload under an existing name is a conflict that keeps the record pending.
func _publication_identity() -> void:
	var a := _session()
	var b := _session()
	_abort(a, 2)
	_abort(b, 3)
	a.results[0].created_utc = "2026-01-01T00:00:00"
	b.results[0].created_utc = "2026-01-01T00:00:00"
	var shared := DIR + "/shared"
	var ra: Dictionary = a.save_results(shared)
	var rb: Dictionary = b.save_results(shared)
	_check("A12 two sessions in the same second save two distinct files", ra.saved == 1 and rb.saved == 1
		and ra.paths[0] != rb.paths[0] and DirAccess.get_files_at(shared).size() == 2, str(DirAccess.get_files_at(shared)))
	var first: Variant = JSON.parse_string(FileAccess.get_file_as_string(ra.paths[0]))
	_check("A12 each file keeps its own payload", typeof(first) == TYPE_DICTIONARY and int(first.terminal_tick) == 2)

	var c := _session()
	c.publication_id_source = func() -> String: return "0123456789abcdef0123456789abcdef"
	_abort(c, 2)
	var pending: Dictionary = c.results[0].duplicate(true)
	var blocker := DIR + "/blocker"
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("a file where the results folder should be")
	file.close()
	var failed: Dictionary = c.save_results(blocker)
	_check("A11/A12 a failed save keeps the record and its id", failed.failed == 1 and c.results.size() == 1
		and str(c.results[0].publication_id) == "0123456789abcdef0123456789abcdef")
	var retry := DIR + "/retry"
	var saved: Dictionary = c.save_results(retry)
	var bytes := FileAccess.get_file_as_bytes(saved.paths[0]) if saved.paths.size() == 1 else PackedByteArray()
	c.results.append(pending.duplicate(true))
	var again: Dictionary = c.save_results(retry)
	_check("A12 the retry of the same record is an idempotent success with unchanged bytes", saved.saved == 1 and again.saved == 1
		and again.paths == saved.paths and FileAccess.get_file_as_bytes(saved.paths[0]) == bytes
		and DirAccess.get_files_at(retry).size() == 1)
	var conflicting: Dictionary = pending.duplicate(true)
	conflicting.terminal_tick = 99
	c.results.append(conflicting)
	var clash: Dictionary = c.save_results(retry)
	_check("A12/A13 another payload under an existing name is never written over it", clash.failed == 1 and c.results.size() == 1
		and FileAccess.get_file_as_bytes(saved.paths[0]) == bytes)
	c.discard_results()
	c.publication_id_source = func() -> String: return ""
	_abort(c, 2)
	var no_id: Dictionary = c.save_results(DIR + "/no-id")
	c.publication_id_source = func() -> String: return "fedcba9876543210fedcba9876543210"
	var later: Dictionary = c.save_results(DIR + "/no-id")
	_check("A12 a failed id generation keeps the result pending until it has an id", no_id.failed == 1 and later.saved == 1
		and c.results.is_empty() and "fedcba9876543210fedcba9876543210" in str(later.paths[0]))


func _course() -> Dictionary:
	var loaded: Dictionary = Track.load_file(TRACK)
	var flat := func(_n: float, _e: float) -> PackedFloat64Array: return PackedFloat64Array([0.0, 0.0, 0.0])
	return Track.prepare(loaded.track, _field, flat).course


func _result(total: float, laps: Array) -> Dictionary:
	var lap_records: Array = []
	for lap: float in laps:
		lap_records.append({valid = true, duration_s = lap})
	return {valid = true, phase = "FINISHED", total_s = total, laps = lap_records}


## A13 (book): a failed publication after the target was removed restores the previous book; an interrupted
## replacement (target gone, previous copy present) is recovered by the loader.
func _book_replacement() -> void:
	var course := _course()
	var path := DIR + "/book/" + RaceRecords.FILE_NAME
	var first: Dictionary = RaceRecords.apply({}, course, _result(70.0, [23.0, 23.0, 24.0])).records
	var better: Dictionary = RaceRecords.apply(first, course, _result(60.0, [20.0, 20.0, 20.0])).records
	_check("A13 setup: the first book is saved", RaceRecords.save_file(first, path) == OK)
	var remove_then_fail := func(_temporary: String, target: String) -> int:
		DirAccess.remove_absolute(target) # the engine's delete-before-move, then the move fails
		return ERR_FILE_CANT_WRITE
	var failed: Error = RaceRecords.save_file(better, path, remove_then_fail)
	var after: Dictionary = RaceRecords.load_file(path)
	_check("A13 a failed replacement reports the error and the previous book is still the readable book", failed != OK
		and FileAccess.file_exists(path) and after.ok and not after.recovered
		and float(after.records[course.identity].best_total_s) == 70.0 and not FileAccess.file_exists(path + ".tmp"))
	DirAccess.remove_absolute(path)
	var recovered: Dictionary = RaceRecords.load_file(path)
	_check("A13 an interrupted replacement (book missing, previous copy present) is recovered", recovered.ok and recovered.recovered
		and float(recovered.records[course.identity].best_total_s) == 70.0)
	_check("A13 a normal save after recovery publishes the new book", RaceRecords.save_file(better, path) == OK
		and float(RaceRecords.load_file(path).records[course.identity].best_total_s) == 60.0)


## A16: an empty or partial entry is dropped on load (no script error), and the next result updates the book.
func _book_entries() -> void:
	var course := _course()
	var path := DIR + "/entries/" + RaceRecords.FILE_NAME
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({format = RaceRecords.FORMAT, courses = {str(course.identity): {},
		"partial": {best_total_s = 1.0, best_lap_s = 1.0}}}))
	file.close()
	var loaded: Dictionary = RaceRecords.load_file(path)
	_check("A16 empty and partial entries are dropped, not filled with defaults", loaded.ok and loaded.records.is_empty()
		and int(loaded.dropped) == 2, str(loaded))
	var applied: Dictionary = RaceRecords.apply(loaded.records, course, _result(60.0, [20.0, 20.0, 20.0]))
	_check("A16 the next valid result updates the book", applied.finished and float(applied.entry.best_total_s) == 60.0)
	var direct: Dictionary = RaceRecords.apply({str(course.identity): {}}, course, _result(61.0, [20.0, 20.0, 21.0]))
	_check("A16 apply over an in-memory empty entry does not reach a missing key", direct.finished
		and float(direct.entry.best_total_s) == 61.0)


## A15: the course identity follows the resolved post solids (terrain under one post); an unchanged course is stable.
func _course_identity() -> void:
	var loaded: Dictionary = Track.load_file(TRACK)
	var flat := func(_n: float, _e: float) -> PackedFloat64Array: return PackedFloat64Array([0.0, 0.0, 0.0])
	var first: Dictionary = Track.prepare(loaded.track, _field, flat)
	var again: Dictionary = Track.prepare(loaded.track, _field, flat)
	var post: Dictionary = first.course.frames[0]
	var altered := func(n: float, e: float) -> PackedFloat64Array:
		var height := 0.2 if absf(n - float(post.north)) < 1.0e-7 and absf(e - float(post.east)) < 1.0e-7 else 0.0
		return PackedFloat64Array([height, 0.0, 0.0])
	var second: Dictionary = Track.prepare(loaded.track, _field, altered)
	_check("A15 an unchanged course keeps its identity", first.ok and again.ok and first.course.identity == again.course.identity)
	_check("A15 different ground at one post (different solid) is a different course", second.ok
		and var_to_bytes(first.course.frames[0]) != var_to_bytes(second.course.frames[0])
		and first.course.identity != second.course.identity)
	_check("A10/A15 the ruleset record declares the terminal policy (part of the identity)",
		str(first.course.ruleset.get("terminal_policy", "")) == Track.TERMINAL_POLICY)


## A11: eight unsaved results; once the storage is repaired the activity saves them without another race and starts;
## leaving with unsaved results takes a second, informed Home.
func _outbox_recovery() -> void:
	var blocked := DIR + "/activity-results"
	var file := FileAccess.open(blocked, FileAccess.WRITE)
	file.store_string("a file where the results folder should be")
	file.close()
	var activity: Node3D = Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.results_directory = blocked
	root.add_child(activity)
	_nodes.append(activity)
	activity.set_physics_process(false)
	var s: Node = activity.session
	for i in Session.MAX_PENDING_RESULTS:
		_abort(s, 2)
	_check("A11 setup: eight results are pending behind failed saves", s.results.size() == Session.MAX_PENDING_RESULTS)
	activity.request_race()
	_check("A11 a full outbox with the storage still broken names the problem and the count", activity.hud.message.text.contains("8 pending"),
		activity.hud.message.text)
	DirAccess.remove_absolute(blocked)
	activity.request_race()
	_check("A11 after the storage is repaired the activity saves all eight without another race and stages the start",
		s.results.is_empty() and DirAccess.get_files_at(blocked).size() == Session.MAX_PENDING_RESULTS
		and activity._race_action == Director.ACTION_START, "%d pending" % s.results.size())
	activity.restart_on_pad()
	var gone := DIR + "/activity-results-2"
	file = FileAccess.open(gone, FileAccess.WRITE)
	file.store_string("blocked again")
	file.close()
	activity.results_directory = gone
	_abort(s, 2)
	var homes := [0]
	activity.home_requested.connect(func() -> void: homes[0] += 1)
	activity.handle_action("home")
	_check("A11 Home with an unsaved result stays and says how to discard it", homes[0] == 0 and s.results.size() == 1
		and activity.hud.message.text.contains("not saved"), activity.hud.message.text)
	activity.handle_action("home")
	_check("A11 a second Home is the informed discard and leaves", homes[0] == 1 and s.results.is_empty())


## A17: a failed OSD save keeps the change and says so; once the storage works the next change is saved.
func _osd_save() -> void:
	var hud := Hud.new()
	root.add_child(hud)
	_nodes.append(hud)
	hud.set_prefs_path(DIR + "/missing-folder/osd.cfg")
	var before := str(hud.osd_config.layout)
	hud.cycle_layout()
	_check("A17 a failed OSD save keeps the new layout and reports it", hud.osd_unsaved and str(hud.osd_config.layout) != before
		and hud.message.text.contains("not saved"), hud.message.text)
	DirAccess.make_dir_recursive_absolute(DIR + "/missing-folder")
	hud.cycle_layout()
	_check("A17 the next change saves the current layout", not hud.osd_unsaved and FileAccess.file_exists(DIR + "/missing-folder/osd.cfg"))
