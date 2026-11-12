# DR-40: the pilot's local race record book (vehicles/multirotor/race_records.gd): medal targets from the course
# geometry, the first finish, a new record, a slower finish, a best lap from an aborted attempt, a corrupt book kept
# aside, an atomic save/load round trip and the bounded book. Pure data; no session or rendering.
extends SceneTree

const RaceRecords := preload("res://vehicles/multirotor/race_records.gd")
const Track := preload("res://sim/race/track.gd")
const FieldLoader := preload("res://data/field_loader.gd")

const DIR := "user://test_race_records"

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _flat(_north: float, _east: float) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0])


func _result(total: float, laps: Array, finished := true, reason := "none") -> Dictionary:
	var rows: Array = []
	for i in laps.size():
		rows.append({lap = i + 1, duration_s = float(laps[i]), valid = true})
	return {phase = "FINISHED" if finished else "ABORTED", valid = finished, total_s = total if finished else 0.0, laps = rows,
		reason = reason}


func _clean() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for file: String in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(file))
		DirAccess.remove_absolute(DIR)


func _run() -> void:
	_clean()
	var field: Dictionary = FieldLoader.load_from().field
	var course: Dictionary = Track.prepare(Track.load_file("res://data/race/tracks/openrc-practice-oval-1.json").track, field,
		_flat).course
	var goals: Dictionary = RaceRecords.targets(course)
	_check("targets: the oval's three-lap gate path from the pad and a target per medal, faster for a better medal",
		absf(float(goals.distance_m) - 317.4) < 1.0 and float(goals.gold) < float(goals.silver) and float(goals.silver) < float(goals.bronze)
		and absf(float(goals.bronze) - ceilf(float(goals.distance_m) / 5.0 * 10.0) / 10.0) < 1e-9, str(goals))
	_check("medal_for: a total at or under a target earns that medal; slower earns none",
		RaceRecords.medal_for(float(goals.gold), goals) == "gold" and RaceRecords.medal_for(float(goals.gold) + 0.1, goals) == "silver"
		and RaceRecords.medal_for(float(goals.bronze) + 0.1, goals) == "" and RaceRecords.medal_for(NAN, goals) == "")
	_check("next_medal: bronze after none, gold after silver, nothing after gold",
		RaceRecords.next_medal("", goals).medal == "bronze" and RaceRecords.next_medal("silver", goals).medal == "gold"
		and RaceRecords.next_medal("gold", goals).is_empty())
	var first := RaceRecords.apply({}, course, _result(60.0, [21.0, 19.5, 19.5]))
	var entry: Dictionary = first.entry
	_check("the first finish is the best total, keeps its lap times and earns its medal", first.finished and first.new_best_total
		and float(first.previous_total_s) == 0.0 and float(entry.best_total_s) == 60.0 and float(entry.best_lap_s) == 19.5
		and first.best_lap_index == 1 and entry.medal == "bronze" and first.new_medal and int(entry.finishes) == 1
		and int(entry.attempts) == 1, str(entry))
	var faster := RaceRecords.apply(first.records, course, _result(float(goals.silver) - 1.0, [13.0, 12.0, 12.0]))
	_check("a faster finish is a new record against the previous best and raises the medal", faster.new_best_total
		and float(faster.previous_total_s) == 60.0 and faster.entry.medal == "silver" and faster.new_medal
		and float(faster.entry.best_lap_s) == 12.0, str(faster.entry))
	var slower := RaceRecords.apply(faster.records, course, _result(70.0, [24.0, 23.0, 23.0]))
	_check("a slower finish keeps the record and the medal, counts the attempt", not slower.new_best_total and not slower.new_medal
		and float(slower.entry.best_total_s) == float(goals.silver) - 1.0 and slower.entry.medal == "silver"
		and int(slower.entry.finishes) == 3 and int(slower.entry.attempts) == 3)
	var crash := RaceRecords.apply(slower.records, course, _result(0.0, [11.0], false, "crash"))
	_check("an aborted attempt earns no total or medal but its completed lap can be the best lap", not crash.finished
		and crash.new_best_lap and float(crash.entry.best_lap_s) == 11.0 and float(crash.entry.best_total_s) == float(goals.silver) - 1.0
		and int(crash.entry.attempts) == 4)
	var path := DIR.path_join(RaceRecords.FILE_NAME)
	_check("save then load returns the same book", RaceRecords.save_file(crash.records, path) == OK
		and var_to_str(RaceRecords.load_file(path).records.keys()) == var_to_str(crash.records.keys())
		and float(RaceRecords.load_file(path).records[course.identity].best_lap_s) == 11.0)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	var corrupt := RaceRecords.load_file(path)
	var aside := RaceRecords.set_aside(path)
	_check("an unreadable book reports itself and is kept aside, never overwritten", not corrupt.ok and corrupt.records.is_empty()
		and not aside.is_empty() and FileAccess.file_exists(aside) and not FileAccess.file_exists(path), aside)
	_check("a missing book is an empty book", RaceRecords.load_file(path).ok and RaceRecords.load_file(path).records.is_empty())
	var book := {}
	for i in RaceRecords.MAX_COURSES + 5:
		var other: Dictionary = course.duplicate()
		other.identity = "course-%03d" % i
		book = RaceRecords.apply(book, other, _result(60.0, [20.0, 20.0, 20.0])).records
	_check("the book is bounded and keeps the course just raced", book.size() == RaceRecords.MAX_COURSES
		and book.has("course-%03d" % (RaceRecords.MAX_COURSES + 4)))
	_clean()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
