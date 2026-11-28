extends SceneTree

const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const Session := preload("res://sim/multirotor/session.gd")
const Book := preload("res://vehicles/multirotor/race_records.gd")


func _initialize() -> void:
	_run.call_deferred()


func _open(directory: String) -> Node3D:
	var scene := Activity.new()
	scene.results_directory = directory
	scene.session = Session.new()
	scene.add_child(scene.session)
	# Course HUD entry normally performs this initial read. No world or physics is required.
	scene._load_records()
	return scene


func _finish(scene: Node3D, identity: String, publication: String, total: float) -> void:
	var course := {identity = identity, track_id = identity, track_name = identity}
	var lap := {valid = true, duration_s = total / 3.0}
	var record := {records_identity = identity, track_id = identity, publication_id = publication,
		created_utc = "2026-11-28T12:00:00", valid = true, phase = "FINISHED", reason = "none",
		total_s = total, laps = [lap, lap, lap], saved = false}
	scene.session.results.append(record)
	# This is the production terminal-result handler. The unprepared fixture skips the results card.
	scene._on_race_result(record, course)


func _scenario(root_directory: String, label: String, overlap: bool, shared_course: bool) -> Dictionary:
	var directory := root_directory.path_join(label)
	var first := _open(directory)
	var second: Node3D = _open(directory) if overlap else null
	_finish(first, "oval", "a", 60.0)
	if second == null:
		second = _open(directory)
	_finish(second, "oval" if shared_course else "tower", "b", 75.0)
	var loaded: Dictionary = Book.load_file(first.records_path())
	var attempts := 0
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.begins_with("race-") and file_name.ends_with(".json"):
			attempts += 1
	var entry: Dictionary = loaded.records.get("oval", {})
	var observation := {book_ok = loaded.ok, courses = loaded.records.size(), attempts_on_disk = attempts,
		oval_best = float(entry.get("best_total_s", 0)), oval_finishes = int(entry.get("finishes", 0))}
	first.free()
	second.free()
	return observation


func _run() -> void:
	var directory := "user://r2-book-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var stale := _scenario(directory, "overlap-same", true, true)
	var serial := _scenario(directory, "serial-same", false, true)
	var different := _scenario(directory, "overlap-different", true, false)
	var serial_different := _scenario(directory, "serial-different", false, false)
	var ok: bool = stale.oval_best == 75.0 and stale.oval_finishes == 1 \
		and serial.oval_best == 60.0 and serial.oval_finishes == 2 \
		and different.courses == 1 and different.oval_finishes == 0 and serial_different.courses == 2
	for row: Dictionary in [stale, serial, different, serial_different]:
		ok = ok and row.book_ok and row.attempts_on_disk == 2
	print("R2_RACE_BOOK ", JSON.stringify({overlap_same = stale, serial_same = serial,
		overlap_different = different, serial_different = serial_different, reproduced = ok}))
	quit(0 if ok else 1)
