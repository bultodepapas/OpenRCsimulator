extends SceneTree

const Preferences := preload("res://workshop/library_preferences.gd")
const MAX_FAVORITES: int = Preferences.MAX_FAVORITES

var _checks: int = 0
var _failures: int = 0
var _root: String = ""


func _initialize() -> void:
	_root = "user://workshop_library_preferences_test_%d_%d" % [int(Time.get_unix_time_from_system()), int(Time.get_ticks_usec())]
	_test_read_is_non_mutating()
	_test_round_trip_and_noop()
	_test_invalid_ids_and_roots()
	_test_strict_schema_and_corruption_preservation()
	_test_bound_and_unknown_uuid_preservation()
	_test_backup_recovery()
	_test_atomic_failure_guards()
	_finish()


func _test_read_is_non_mutating() -> void:
	var root: String = _root.path_join("uncreated")
	var absolute_root: String = ProjectSettings.globalize_path(root)
	var loaded: Dictionary = Preferences.load_state(root)
	_check("missing preferences load as an empty state", bool(loaded["ok"]) and loaded["favorites"].is_empty(), str(loaded["errors"]))
	_check("reading a missing preferences file creates no root or file",
		not DirAccess.dir_exists_absolute(absolute_root)
		and not FileAccess.file_exists(absolute_root.path_join(Preferences.FILE_NAME)))


func _test_round_trip_and_noop() -> void:
	var root: String = _root.path_join("round_trip")
	var first_id: String = _uuid(1)
	var unknown_id: String = _uuid(2)
	var first: Dictionary = Preferences.set_favorite(first_id, true, root)
	_check("first favorite writes successfully", bool(first["ok"]) and first["favorites"] == [first_id], str(first["errors"]))
	var state_path: String = _absolute_state_path(root)
	var before_noop: PackedByteArray = FileAccess.get_file_as_bytes(state_path)
	var repeated: Dictionary = Preferences.set_favorite(first_id, true, root)
	_check("repeating the current favorite is a successful no-op", bool(repeated["ok"]) and repeated["favorites"] == [first_id])
	_check("no-op leaves exact persisted bytes unchanged", FileAccess.get_file_as_bytes(state_path) == before_noop)
	var added_unknown: Dictionary = Preferences.set_favorite(unknown_id, true, root)
	_check("valid UUID remains favorite even when it has no live variant", bool(added_unknown["ok"]) and added_unknown["favorites"] == [first_id, unknown_id])
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state_path))
	_check("file contains only closed data-only preference fields",
		parsed.size() == 3 and parsed.has("format") and parsed.has("version") and parsed.has("favorites")
		and parsed["format"] == Preferences.FORMAT and parsed["favorites"] == [first_id, unknown_id])
	var removed: Dictionary = Preferences.set_favorite(first_id, false, root)
	_check("removing a favorite persists the remaining UUID", bool(removed["ok"]) and removed["favorites"] == [unknown_id])
	var reloaded: Dictionary = Preferences.load_state(root)
	_check("preference state reloads exactly after round trip", bool(reloaded["ok"]) and reloaded["favorites"] == [unknown_id])


func _test_invalid_ids_and_roots() -> void:
	var root: String = _root.path_join("invalid")
	var invalid_ids: Array[String] = ["../variant", "jensen-das-ugly-stik-60", "abcdef00-0000-4000-8000-000000000003".to_upper(), "00000000-0000-1000-8000-000000000001"]
	for id: String in invalid_ids:
		var result: Dictionary = Preferences.set_favorite(id, true, root)
		_check("invalid favorite IDs are rejected: " + id, not bool(result["ok"]))
	_check("invalid IDs do not create preference files", not FileAccess.file_exists(_absolute_state_path(root)))
	for unsafe_root: String in ["res://data", "user://../outside", "user://bad:name", "user://bad\\name"]:
		var rejected: Dictionary = Preferences.load_state(unsafe_root)
		_check("unsafe preferences root rejected: " + unsafe_root, not bool(rejected["ok"]))


func _test_strict_schema_and_corruption_preservation() -> void:
	var cases: Array[PackedByteArray] = [
		"{\"format\":\"openrc-aircraft-library-preferences\",\"version\":1,\"favorites\":[],\"extra\":true}".to_utf8_buffer(),
		"{\"format\":\"openrc-aircraft-library-preferences\",\"version\":1,\"version\":1,\"favorites\":[]}".to_utf8_buffer(),
		JSON.stringify({"format": Preferences.FORMAT, "version": 2, "favorites": []}).to_utf8_buffer(),
		JSON.stringify({"format": Preferences.FORMAT, "version": 1, "favorites": [_uuid(4), _uuid(4)]}).to_utf8_buffer(),
		JSON.stringify({"format": Preferences.FORMAT, "version": 1, "favorites": ["not-a-uuid"]}).to_utf8_buffer(),
		"{not json".to_utf8_buffer(),
	]
	for index: int in range(cases.size()):
		var root: String = _root.path_join("corrupt_%d" % index)
		var path: String = _absolute_state_path(root)
		_check("write corrupt fixture %d" % index, _write_bytes(path, cases[index]))
		var read_before: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var loaded: Dictionary = Preferences.load_state(root)
		_check("reject malformed/unknown/duplicate state %d" % index, not bool(loaded["ok"]))
		var attempted: Dictionary = Preferences.set_favorite(_uuid(5), true, root)
		_check("corrupt state prevents replacement %d" % index, not bool(attempted["ok"]))
		_check("corrupt fixture bytes remain unchanged %d" % index, FileAccess.get_file_as_bytes(path) == read_before)
	var oversized_root: String = _root.path_join("oversized")
	var oversized_path: String = _absolute_state_path(oversized_root)
	var oversized: PackedByteArray = PackedByteArray()
	oversized.resize(Preferences.MAX_STATE_BYTES + 1)
	oversized.fill(32)
	_check("write oversized fixture", _write_bytes(oversized_path, oversized))
	var oversized_result: Dictionary = Preferences.load_state(oversized_root)
	_check("oversized preference file is rejected", not bool(oversized_result["ok"]))
	var oversized_write: Dictionary = Preferences.set_favorite(_uuid(6), true, oversized_root)
	_check("oversized file cannot be overwritten", not bool(oversized_write["ok"]) and FileAccess.get_file_as_bytes(oversized_path) == oversized)


func _test_bound_and_unknown_uuid_preservation() -> void:
	var root: String = _root.path_join("bounded")
	var ids: Array[String] = []
	for index: int in range(MAX_FAVORITES):
		ids.append(_uuid(index + 100))
	ids.sort()
	var fixture: Dictionary = {"format": Preferences.FORMAT, "version": Preferences.VERSION, "favorites": ids}
	var path: String = _absolute_state_path(root)
	var bytes: PackedByteArray = (JSON.stringify(fixture, "\t", true, true) + "\n").to_utf8_buffer()
	_check("write exact max-size favorite fixture", _write_bytes(path, bytes))
	var maximum: Dictionary = Preferences.load_state(root)
	_check("all favorites through the cap load", bool(maximum["ok"]) and maximum["favorites"].size() == MAX_FAVORITES)
	var rejected: Dictionary = Preferences.set_favorite(_uuid(999), true, root)
	_check("adding beyond the favorite cap refuses", not bool(rejected["ok"]) and rejected["favorites"].size() == MAX_FAVORITES)
	_check("cap refusal preserves exact file bytes", FileAccess.get_file_as_bytes(path) == bytes)
	var removed: Dictionary = Preferences.set_favorite(ids[0], false, root)
	_check("removing at the cap succeeds", bool(removed["ok"]) and removed["favorites"].size() == MAX_FAVORITES - 1)
	var restored: Dictionary = Preferences.set_favorite(_uuid(999), true, root)
	_check("slot opens after removal and stale UUID metadata is retained", bool(restored["ok"]) and restored["favorites"].size() == MAX_FAVORITES)
	_check("valid favorites stay unique and sorted", restored["favorites"] == _sorted_unique(restored["favorites"]))


func _test_backup_recovery() -> void:
	var root: String = _root.path_join("recovery")
	var path: String = _absolute_state_path(root)
	var id_one: String = _uuid(11)
	var id_two: String = _uuid(12)
	var id_three: String = _uuid(13)
	var created: Dictionary = Preferences.set_favorite(id_one, true, root)
	_check("recovery fixture first write succeeds", bool(created["ok"]))
	var backup_path: String = path + ".bak"
	_check("move current preferences to simulate interrupted replacement",
		DirAccess.rename_absolute(path, backup_path) == OK)
	var recovered: Dictionary = Preferences.load_state(root)
	_check("missing current file reads its valid backup", bool(recovered["ok"])
		and bool(recovered["recovered_from_backup"]) and recovered["favorites"] == [id_one])
	_check("backup recovery is read-only", not FileAccess.file_exists(path) and FileAccess.file_exists(backup_path))
	var repaired: Dictionary = Preferences.set_favorite(id_two, true, root)
	_check("next explicit edit publishes recovered state", bool(repaired["ok"]) and repaired["favorites"] == [id_one, id_two])
	_check("recovery backup remains after publishing", FileAccess.file_exists(backup_path))
	var good_current: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var corrupt_current: PackedByteArray = "{corrupt current".to_utf8_buffer()
	_check("write corrupt current beside valid backup", _write_bytes(path, corrupt_current))
	var rejected: Dictionary = Preferences.load_state(root)
	_check("corrupt current does not silently fall back to backup", not bool(rejected["ok"]))
	var failed_edit: Dictionary = Preferences.set_favorite(id_three, true, root)
	_check("corrupt current prevents overwrite despite valid backup", not bool(failed_edit["ok"]))
	_check("corrupt current and valid backup remain untouched",
		FileAccess.get_file_as_bytes(path) == corrupt_current and FileAccess.file_exists(backup_path)
		and not good_current.is_empty())


func _test_atomic_failure_guards() -> void:
	var busy_root: String = _root.path_join("busy")
	var absolute_busy: String = ProjectSettings.globalize_path(busy_root)
	_check("create preferences lock fixture", DirAccess.make_dir_recursive_absolute(absolute_busy.path_join("_locks/_favorites")) == OK)
	var busy: Dictionary = Preferences.set_favorite(_uuid(21), true, busy_root)
	_check("busy lock refuses a write", not bool(busy["ok"]) and not FileAccess.file_exists(_absolute_state_path(busy_root)))
	var obstruction_root: String = _root.path_join("backup_obstruction")
	var id_one: String = _uuid(31)
	var first: Dictionary = Preferences.set_favorite(id_one, true, obstruction_root)
	var state_path: String = _absolute_state_path(obstruction_root)
	var original: PackedByteArray = FileAccess.get_file_as_bytes(state_path)
	var backup_path: String = state_path + ".bak"
	var backup_dir_error: Error = DirAccess.make_dir_recursive_absolute(backup_path.path_join("nonempty"))
	_check("create nonempty backup obstruction", backup_dir_error == OK)
	var failed: Dictionary = Preferences.set_favorite(_uuid(32), true, obstruction_root)
	_check("backup obstruction makes replacement fail closed", not bool(failed["ok"]) and bool(first["ok"]))
	_check("failed replacement preserves prior state and removes temporary data",
		FileAccess.get_file_as_bytes(state_path) == original and _temporary_files(obstruction_root) == 0)


func _absolute_state_path(root: String) -> String:
	return ProjectSettings.globalize_path(root.path_join(Preferences.FILE_NAME))


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var directory: String = path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK and not DirAccess.dir_exists_absolute(directory):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	return ok


func _temporary_files(root: String) -> int:
	var directory: DirAccess = DirAccess.open(ProjectSettings.globalize_path(root))
	if directory == null:
		return 0
	var count: int = 0
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with(Preferences.FILE_NAME + ".tmp-"):
			count += 1
	directory.list_dir_end()
	return count


func _uuid(index: int) -> String:
	return "00000000-0000-4000-8000-%012d" % index


func _sorted_unique(values: Array[String]) -> Array[String]:
	var result: Array[String] = values.duplicate()
	result.sort()
	var unique: Array[String] = []
	for value: String in result:
		if not unique.has(value):
			unique.append(value)
	return unique


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finish() -> void:
	_remove_tree(ProjectSettings.globalize_path(_root))
	print("Workshop library preferences: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _remove_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var child: String = path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(path)
