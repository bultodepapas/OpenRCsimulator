## DR-40: the pilot's local race record book, one entry per prepared course (its identity: a moved gate or another
## field is another course): best three-lap total and its lap times, best single lap, best medal, finishes and attempts.
## Medal targets are game targets derived from the course geometry (the gate-to-gate path flown three times from the
## pad at a mean speed per medal), not measured pilot data. Presentation state only: nothing here feeds a session, and
## the per-attempt result files (DR-26) stay the authoritative record of every attempt.
extends RefCounted

const FORMAT := "openrc-race-records v1"
const FILE_NAME := "records.json"
## Bounded book: the least recently raced courses leave first.
const MAX_COURSES := 64
## [medal, mean speed (m/s) along the straight gate-to-gate path], best first. Beginners fly about 5 m/s on these
## courses in Angle mode; a fast pilot well above 10 m/s.
const MEDALS := [["gold", 11.0], ["silver", 8.0], ["bronze", 5.0]]
const MEDAL_RANK := {"": 0, "bronze": 1, "silver": 2, "gold": 3}


## The record book at `path`: {ok, records: {course identity: entry}, dropped (invalid entries left out), error}. A
## missing file is an empty book; an unreadable one, or one with dropped entries, is reported (the caller keeps it
## aside rather than overwrite it).
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {ok = true, records = {}, dropped = 0, error = ""}
	# A JSON instance reports a parse error by its return value (JSON.parse_string would also log an engine error).
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY or str(parsed.get("format", "")) != FORMAT or typeof(parsed.get("courses")) != TYPE_DICTIONARY:
		return {ok = false, records = {}, dropped = 0, error = "unreadable record book %s" % path}
	var records := {}
	var dropped := 0
	for identity: Variant in parsed.courses:
		var entry: Variant = parsed.courses[identity]
		if typeof(identity) == TYPE_STRING and typeof(entry) == TYPE_DICTIONARY and _entry_is_valid(entry):
			records[identity] = entry
		else:
			dropped += 1
	return {ok = true, records = records, dropped = dropped, error = ""}


static func _entry_is_valid(entry: Dictionary) -> bool:
	for key: String in ["best_total_s", "best_lap_s"]:
		var value: Variant = entry.get(key, 0.0)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or float(value) < 0.0:
			return false
	return str(entry.get("medal", "")) in MEDAL_RANK and typeof(entry.get("best_laps", [])) == TYPE_ARRAY


## Write the book atomically (a complete temporary file, then a rename in the same directory).
static func save_file(records: Dictionary, path: String) -> Error:
	var made: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if made != OK:
		return made
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({format = FORMAT, courses = records}, "\t", true) + "\n")
	file.flush()
	var written: Error = file.get_error()
	file.close()
	if written != OK:
		return written
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temporary, path)


## Keep an unreadable book aside (never overwritten): returns the path it was moved to, or "".
static func set_aside(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "")
	var aside := "%s.unreadable-%s" % [path, stamp]
	var n := 1
	while FileAccess.file_exists(aside) and n < 100:
		n += 1
		aside = "%s.unreadable-%s-%d" % [path, stamp, n]
	return aside if not FileAccess.file_exists(aside) and DirAccess.rename_absolute(path, aside) == OK else ""


## Medal target totals (s) for a prepared course ({gates[{c}], pad {north, east, down}, laps}): {distance_m, gold,
## silver, bronze}. The path: the pad to gate 1, then every gate in order for each lap (the last gate leads back to
## gate 1 between laps). Rounded up to a tenth of a second. {} for a course without gates.
static func targets(course: Dictionary) -> Dictionary:
	var gates: Array = course.get("gates", [])
	if gates.is_empty() or typeof(course.get("pad")) != TYPE_DICTIONARY:
		return {}
	var laps := maxi(1, int(course.get("laps", 3)))
	var pad: Dictionary = course.pad
	var points: Array[Vector3] = []
	for gate: Dictionary in gates:
		var c: PackedFloat64Array = gate.c
		points.append(Vector3(c[0], c[1], c[2]))
	var lap := 0.0
	for i in points.size() - 1:
		lap += points[i].distance_to(points[i + 1])
	var start := Vector3(float(pad.north), float(pad.east), float(pad.down)).distance_to(points[0])
	var distance := start + float(laps) * lap + float(laps - 1) * points[points.size() - 1].distance_to(points[0])
	var result := {distance_m = distance}
	for medal: Array in MEDALS:
		result[medal[0]] = ceilf(distance / float(medal[1]) * 10.0) / 10.0
	return result


## The medal a finished total earns against `goals` (targets()), or "".
static func medal_for(total_s: float, goals: Dictionary) -> String:
	if not is_finite(total_s) or total_s <= 0.0:
		return ""
	for medal: Array in MEDALS:
		if goals.has(medal[0]) and total_s <= float(goals[medal[0]]):
			return medal[0]
	return ""


## The next medal above `medal` and its target total, or {} at gold (or without targets).
static func next_medal(medal: String, goals: Dictionary) -> Dictionary:
	var rank: int = MEDAL_RANK.get(medal, 0)
	for i in range(MEDALS.size() - 1, -1, -1):
		var name: String = MEDALS[i][0]
		if MEDAL_RANK[name] > rank and goals.has(name):
			return {medal = name, total_s = float(goals[name])}
	return {}


## Fold one terminal race record into the book for `course` (`count_attempt` false when the pilot left the attempt:
## its completed laps still compete for the best lap). Pure: returns {records (a new book), entry, finished,
## new_best_total, new_best_lap, previous_total_s, previous_lap_s (0 when there was none), medal, new_medal,
## best_lap_index (this attempt's fastest completed lap)}.
static func apply(records: Dictionary, course: Dictionary, result: Dictionary, count_attempt := true) -> Dictionary:
	var book: Dictionary = records.duplicate(true)
	var identity := str(course.get("identity", result.get("course_identity", "")))
	var entry: Dictionary = book.get(identity, {track_id = str(course.get("track_id", "")),
		track_name = str(course.get("track_name", "")), best_total_s = 0.0, best_laps = [], best_lap_s = 0.0, medal = "",
		finishes = 0, attempts = 0, best_utc = ""}).duplicate(true)
	entry.attempts = int(entry.get("attempts", 0)) + (1 if count_attempt else 0)
	var summary := {finished = false, new_best_total = false, new_best_lap = false,
		previous_total_s = float(entry.best_total_s), previous_lap_s = float(entry.best_lap_s), medal = "",
		new_medal = false, best_lap_index = -1}
	var total := float(result.get("total_s", 0.0))
	var finished: bool = bool(result.get("valid", false)) and str(result.get("phase", "")) == "FINISHED" \
		and is_finite(total) and total > 0.0
	var laps: Array = result.get("laps", [])
	var fastest := INF
	for i in laps.size():
		var duration := float((laps[i] as Dictionary).get("duration_s", 0.0))
		if bool((laps[i] as Dictionary).get("valid", false)) and is_finite(duration) and duration > 0.0 and duration < fastest:
			fastest = duration
			summary.best_lap_index = i
	if is_finite(fastest) and (float(entry.best_lap_s) <= 0.0 or fastest < float(entry.best_lap_s)):
		summary.new_best_lap = true
		entry.best_lap_s = fastest
	if finished:
		summary.finished = true
		entry.finishes = int(entry.get("finishes", 0)) + 1
		var medal := medal_for(total, targets(course))
		summary.medal = medal
		if MEDAL_RANK.get(medal, 0) > MEDAL_RANK.get(str(entry.medal), 0):
			summary.new_medal = true
			entry.medal = medal
		if float(entry.best_total_s) <= 0.0 or total < float(entry.best_total_s):
			summary.new_best_total = true
			entry.best_total_s = total
			var times: Array = []
			for lap: Dictionary in laps:
				times.append(float(lap.get("duration_s", 0.0)))
			entry.best_laps = times
			entry.best_utc = Time.get_datetime_string_from_system(true)
	entry.updated_unix = Time.get_unix_time_from_system()
	book[identity] = entry
	_bound(book, identity)
	summary.records = book
	summary.entry = entry
	return summary


## Drop the least recently updated courses beyond MAX_COURSES (never `keep`).
static func _bound(book: Dictionary, keep: String) -> void:
	while book.size() > MAX_COURSES:
		var oldest := ""
		var oldest_at := INF
		for identity: String in book:
			var at := float((book[identity] as Dictionary).get("updated_unix", 0.0))
			if identity != keep and at < oldest_at:
				oldest_at = at
				oldest = identity
		if oldest.is_empty():
			return
		book.erase(oldest)
