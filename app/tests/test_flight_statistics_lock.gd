extends SceneTree
## Cross-process writer exclusion and interrupted-owner recovery.

const Store := preload("res://statistics/store.gd")
const TIMEOUT_MSEC := 20000
var _checks: int = 0
var _failures: int = 0
var _root_uri: String = ""
var _root_path: String = ""
var _children: Array[int] = []


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if not arguments.is_empty() and arguments[0] == "worker":
		_worker(arguments)
		return
	_root_uri = "user://flight_statistics_lock_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_root_path = ProjectSettings.globalize_path(_root_uri)
	_check("fixture directory creates", DirAccess.make_dir_recursive_absolute(_root_path) == OK)
	_test_protected_records()
	var scope_probe: RefCounted = Store.new()
	if scope_probe._current_lock_scope().is_empty():
		print("No qualified local process namespace: automatic recovery remains disabled.")
	else:
		_test_independent_writers()
	for pid: int in _children:
		if OS.is_process_running(pid):
			OS.kill(pid)
	for filename: String in DirAccess.get_files_at(_root_path):
		if filename.ends_with(".log"):
			var log: String = FileAccess.get_file_as_string(_root_path.path_join(filename))
			_check("worker log has no engine or script errors: " + filename, not log.contains("SCRIPT ERROR:") and not log.contains("\nERROR:"), log)
	if _failures == 0:
		_remove_tree(_root_path)
	else:
		print("Retained statistics lock fixture: ", _root_path)
	print("Flight statistics lock: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_protected_records() -> void:
	var store: RefCounted = Store.new()
	_check("fixture initializes a valid snapshot", store.open(_root_uri) and store.writable, store.note)
	var identity: String = str(store.data.pilot_id)
	store.close()
	var lock_dir: String = _root_path.path_join(".writer_lock")
	_check("empty lock fixture creates", DirAccess.make_dir_absolute(lock_dir) == OK)
	var observer: RefCounted = Store.new()
	_check("incomplete lock remains read-only", observer.open(_root_uri) and not observer.writable and str(observer.data.pilot_id) == identity, observer.note)
	observer.close()
	var legacy: Dictionary = {format = "openrc-flight-statistics-lock", pid = 999999, token = "legacy-owner"}
	var legacy_bytes: PackedByteArray = JSON.stringify(legacy).to_utf8_buffer()
	_check("legacy JSON owner writes", _write(lock_dir.path_join("owner.json"), legacy_bytes))
	observer = Store.new()
	_check("legacy JSON PID does not authorize reclaim", observer.open(_root_uri) and not observer.writable, observer.note)
	observer.close()
	_check("legacy owner remains unchanged", FileAccess.get_file_as_bytes(lock_dir.path_join("owner.json")) == legacy_bytes)
	_check("fixture lock owner removes", DirAccess.remove_absolute(lock_dir.path_join("owner.json")) == OK)
	_check("fixture lock directory removes", DirAccess.remove_absolute(lock_dir) == OK)


func _test_independent_writers() -> void:
	var alive_pid: int = _launch("alive", "alive_start", "alive_release")
	_check("writer arrives", _wait_file("alive_arrived"))
	_touch("alive_start")
	_check("writer responds", _wait_file("alive_result"))
	var alive: Dictionary = _read_json("alive_result")
	_check("independent writer is writable", alive.get("opened", false) and alive.get("writable", false), str(alive))
	_check("independent writer commits a snapshot", alive.get("committed", false), str(alive))
	_check("worker PID is its actual process", int(alive.get("pid", -1)) == alive_pid, str(alive))
	var snapshot_a: PackedByteArray = FileAccess.get_file_as_bytes(_root_path.path_join("snapshot_a.bin"))
	var snapshot_b: PackedByteArray = FileAccess.get_file_as_bytes(_root_path.path_join("snapshot_b.bin"))
	_check("both snapshot generations exist", not snapshot_a.is_empty() and not snapshot_b.is_empty())
	var other_pid: int = _launch("other", "other_start", "other_release")
	_check("independent reader arrives", _wait_file("other_arrived"))
	_touch("other_start")
	_check("independent reader responds", _wait_file("other_result"))
	var other: Dictionary = _read_json("other_result")
	_check("live independent owner is excluded", other.get("opened", false) and not other.get("writable", true), str(other))
	_check("reader preserves committed identity", other.get("pilot", "") == alive.get("pilot", "") and int(other.get("generation", -1)) == int(alive.get("generation", -2)), str(other))
	_touch("other_release")
	_wait_stopped(other_pid)
	_check("writer is forcibly terminated", OS.kill(alive_pid) == OK)
	_children.erase(alive_pid)
	_check("terminated writer PID becomes absent", _wait_absent(alive_pid))
	var owner_path: String = _root_path.path_join(".writer_lock/owner.json")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(owner_path)
	var owner: Variant = JSON.parse_string(original.get_string_from_utf8())
	var helper: RefCounted = Store.new()
	helper._schema = load("res://statistics/schema.gd")
	_check("completed owner record has versioned lease", typeof(owner) == TYPE_DICTIONARY and helper._valid_lease_owner(owner), str(owner))
	if typeof(owner) == TYPE_DICTIONARY and helper._valid_lease_owner(owner):
		_check("JSON integer PID is accepted", helper._lock_integer(owner.pid, 1, 4294967295))
		_check("fractional PID is rejected", not helper._lock_integer(1.5, 1, 4294967295))
		var invalid: Dictionary = owner.duplicate(true)
		invalid.port = 1 if int(invalid.port) != 1 else 2
		var invalid_bytes: PackedByteArray = JSON.stringify(invalid).to_utf8_buffer()
		_check("damaged owner fixture writes", _write(owner_path, invalid_bytes))
		var damaged: RefCounted = Store.new()
		_check("damaged owner cannot be reclaimed", damaged.open(_root_uri) and not damaged.writable, damaged.note)
		damaged.close()
		_check("damaged owner remains unchanged", FileAccess.get_file_as_bytes(owner_path) == invalid_bytes)
		invalid = owner.duplicate(true)
		invalid.scope = "other-host-or-namespace"
		invalid.checksum = helper._lease_checksum(invalid)
		invalid_bytes = JSON.stringify(invalid).to_utf8_buffer()
		_check("foreign scope fixture writes", _write(owner_path, invalid_bytes))
		var foreign: RefCounted = Store.new()
		_check("foreign scope cannot be reclaimed", foreign.open(_root_uri) and not foreign.writable and str(foreign.note).contains("unverified"), foreign.note)
		foreign.close()
		_check("foreign scope owner remains unchanged", FileAccess.get_file_as_bytes(owner_path) == invalid_bytes)
		owner.pid = OS.get_process_id() # An unrelated live process reused the recorded PID.
		owner.checksum = helper._lease_checksum(owner)
		var altered: PackedByteArray = JSON.stringify(owner).to_utf8_buffer()
		_check("reused PID fixture writes", _write(owner_path, altered))
		var reused: RefCounted = Store.new()
		_check("reused live PID refuses recovery", reused.open(_root_uri) and not reused.writable, reused.note)
		reused.close()
		_check("PID refusal retains owner record", FileAccess.get_file_as_bytes(owner_path) == altered)
		_check("original owner record restores", _write(owner_path, original))
		var extra_path: String = _root_path.path_join(".writer_lock/unknown")
		_check("unknown lock entry fixture writes", _write(extra_path, "preserve".to_utf8_buffer()))
		var unknown: RefCounted = Store.new()
		_check("unknown lock entry prevents reclaim", unknown.open(_root_uri) and not unknown.writable, unknown.note)
		unknown.close()
		_check("unknown entry remains untouched", FileAccess.get_file_as_bytes(extra_path) == "preserve".to_utf8_buffer())
		_check("unknown fixture entry removes", DirAccess.remove_absolute(extra_path) == OK)
	for round: int in range(3):
		var prefix: String = "race%d" % round
		var left_pid: int = _launch(prefix + "a", prefix + "start", prefix + "release")
		var right_pid: int = _launch(prefix + "b", prefix + "start", prefix + "release")
		_check(prefix + " contenders arrive", _wait_file(prefix + "a_arrived") and _wait_file(prefix + "b_arrived"))
		_touch(prefix + "start")
		_check(prefix + " contenders respond", _wait_file(prefix + "a_result") and _wait_file(prefix + "b_result"))
		var left: Dictionary = _read_json(prefix + "a_result")
		var right: Dictionary = _read_json(prefix + "b_result")
		var writers: int = int(bool(left.get("writable", false))) + int(bool(right.get("writable", false)))
		_check(prefix + " elects exactly one writer", writers == 1 and left.get("opened", false) and right.get("opened", false), str([left, right]))
		_check(prefix + " retains the snapshot", left.get("pilot", "") == alive.get("pilot", "") and right.get("pilot", "") == alive.get("pilot", "") and int(left.get("generation", -1)) == int(alive.get("generation", -2)) and int(right.get("generation", -1)) == int(alive.get("generation", -2)), str([left, right]))
		var winner: int = left_pid if left.get("writable", false) else right_pid
		var loser: int = right_pid if winner == left_pid else left_pid
		_check(prefix + " writer is killed", OS.kill(winner) == OK)
		_children.erase(winner)
		_check(prefix + " writer exits before next reclaim", _wait_absent(winner))
		_touch(prefix + "release")
		_wait_stopped(loser)
	var final: RefCounted = Store.new()
	_check("next launch recovers after a killed writer", final.open(_root_uri) and final.writable, final.note)
	_check("recovery preserves snapshot identity and generation", final.data.get("pilot_id", "") == alive.get("pilot", "") and int(final.data.get("generation", -1)) == int(alive.get("generation", -2)))
	final.close()
	_check("reclaims preserve both snapshot files byte-for-byte", FileAccess.get_file_as_bytes(_root_path.path_join("snapshot_a.bin")) == snapshot_a and FileAccess.get_file_as_bytes(_root_path.path_join("snapshot_b.bin")) == snapshot_b)


func _launch(name: String, start: String, release: String) -> int:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--audio-driver", "Dummy", "--log-file", _root_path.path_join(name + ".log"), "--script", "res://tests/test_flight_statistics_lock.gd", "--", "worker", _root_uri, name, start, release])
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	_check("launch " + name, pid > 0, str(pid))
	if pid > 0:
		_children.append(pid)
	return pid


func _worker(args: PackedStringArray) -> void:
	if args.size() != 5:
		quit(2)
		return
	_root_uri = args[1]
	_root_path = ProjectSettings.globalize_path(_root_uri)
	var name: String = args[2]
	_touch(name + "_arrived")
	if not _wait_file(args[3]):
		quit(3)
		return
	var store: RefCounted = Store.new()
	var opened: bool = store.open(_root_uri)
	var committed: bool = false
	if name == "alive" and opened and store.writable:
		var candidate: Dictionary = store.data.duplicate(true)
		candidate.clean_exit = not bool(candidate.clean_exit)
		committed = store.commit(candidate)
	var result: Dictionary = {opened = opened, writable = store.writable, committed = committed, pid = OS.get_process_id(), note = store.note, pilot = store.data.get("pilot_id", ""), generation = store.data.get("generation", -1)}
	if not _write(_root_path.path_join(name + "_result.tmp"), JSON.stringify(result).to_utf8_buffer()) or DirAccess.rename_absolute(_root_path.path_join(name + "_result.tmp"), _root_path.path_join(name + "_result")) != OK:
		quit(4)
		return
	_wait_file(args[4])
	store.close()
	quit()


func _wait_absent(pid: int) -> bool:
	var probe: RefCounted = Store.new()
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if probe._process_proven_absent(pid):
			return true
		OS.delay_msec(20)
	return false


func _wait_stopped(pid: int) -> void:
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if not OS.is_process_running(pid):
			_children.erase(pid)
			return
		OS.delay_msec(20)
	OS.kill(pid)
	_children.erase(pid)
	_check("worker exits after release", false, str(pid))


func _wait_file(name: String) -> bool:
	var path: String = _root_path.path_join(name)
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path):
			return true
		OS.delay_msec(20)
	return false


func _touch(name: String) -> void:
	_check("write " + name, _write(_root_path.path_join(name), "ready".to_utf8_buffer()))


func _read_json(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_root_path.path_join(name)))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _write(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	return ok


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for filename: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in dir.get_directories():
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: %s %s" % [label, detail])
