extends SceneTree
## UI-FS-03 serialized worker commits, receipts, and shutdown join.

class CommitGate:
	extends RefCounted
	var entered: Semaphore = Semaphore.new()
	var release: Semaphore = Semaphore.new()

	func hold(stage: String) -> bool:
		if stage == "after_snapshot_readback":
			entered.post()
			release.wait()
		return false


var _checks: int = 0
var _failures: int = 0
var _roots: Array[String] = []


func _initialize() -> void:
	var store_script: Script = load("res://statistics/store.gd")
	var writer_script: Script = load("res://statistics/writer.gd")
	if store_script == null or writer_script == null:
		_check("statistics store and writer load", false)
		_finish()
		return
	_test_success_and_serialization(store_script, writer_script)
	_test_read_only_failure(store_script, writer_script)
	for root_uri: String in _roots:
		_remove_root(root_uri)
	_finish()


func _test_success_and_serialization(store_script: Script, writer_script: Script) -> void:
	var root_uri: String = _new_root("success")
	var store: RefCounted = store_script.new()
	_check("writer store opens writable", store.open(root_uri) and store.writable, store.note)
	var prior_store: Dictionary = store.data.duplicate(true)
	var candidate: Dictionary = store.data.duplicate(true)
	var session_id: String = "writer-session"
	candidate.sessions.append({"id": session_id, "opened_utc": _utc(), "closed_utc": "", "status": "open"})
	candidate.current_session = session_id
	var unmodified_candidate: Dictionary = candidate.duplicate(true)
	var gate := CommitGate.new()
	store.interruption_hook = Callable(gate, "hold")
	var writer: RefCounted = writer_script.new()
	_check("writer starts detached commit", writer.start(store, candidate))
	gate.entered.wait()
	_check("writer reports pending during commit", writer.pending())
	_check("poll returns empty while worker is running", writer.poll().is_empty())
	_check("concurrent writer start is refused", not writer.start(store, candidate))
	_check("main store snapshot stays unchanged until join", store.data == prior_store)
	_check("caller snapshot stays unchanged during commit", candidate == unmodified_candidate)
	gate.release.post()
	var result: Dictionary = {}
	var deadline_msec: int = Time.get_ticks_msec() + 10000
	while result.is_empty() and Time.get_ticks_msec() < deadline_msec:
		result = writer.poll()
		if result.is_empty():
			OS.delay_msec(1)
	_check("poll joins completed successful commit", not result.is_empty() and bool(result.get("ok", false)), str(result))
	_check("success receipt reports generation and durable sequence", int(result.get("generation", -1)) == int(prior_store.generation) + 1 and int(result.get("durable_sequence", -1)) == int(candidate.sequence))
	_check("writer clears pending after join", not writer.pending())
	_check("store snapshot publishes only after joined commit", int(store.data.generation) == int(prior_store.generation) + 1 and store.data.current_session == session_id)
	_check("writer leaves caller snapshot unchanged", candidate == unmodified_candidate)
	store.close()


func _test_read_only_failure(store_script: Script, writer_script: Script) -> void:
	var root_uri: String = _new_root("read_only")
	var store: RefCounted = store_script.new()
	_check("read-only fixture opens", store.open(root_uri), store.note)
	var prior: Dictionary = store.data.duplicate(true)
	var candidate: Dictionary = store.data.duplicate(true)
	store.writable = false
	var writer: RefCounted = writer_script.new()
	_check("writer starts read-only commit attempt", writer.start(store, candidate))
	var result: Dictionary = writer.finish()
	_check("finish joins failed writable attempt", not result.is_empty() and not bool(result.get("ok", true)))
	_check("failure receipt carries the store error and durable cursor", str(result.get("note", "")).contains("read-only") and int(result.get("generation", -1)) == int(prior.generation) and int(result.get("durable_sequence", -1)) == int(prior.sequence))
	_check("failed commit preserves main snapshot and caller candidate", store.data == prior and candidate == prior)
	_check("finish clears pending", not writer.pending())
	store.close()


func _new_root(label: String) -> String:
	var root_uri: String = "user://flight_statistics_writer_%s_%d_%d" % [label, OS.get_process_id(), Time.get_ticks_usec()]
	_roots.append(root_uri)
	return root_uri


func _utc() -> String:
	return Time.get_datetime_string_from_system(true)


func _remove_root(root_uri: String) -> void:
	var root_path: String = ProjectSettings.globalize_path(root_uri)
	var user_path: String = ProjectSettings.globalize_path("user://")
	if not root_path.begins_with(user_path) or root_path == user_path:
		_check("writer fixture cleanup path is scoped", false, root_path)
		return
	_remove_tree(root_path)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	var files: PackedStringArray = directory.get_files()
	var directories: PackedStringArray = directory.get_directories()
	directory = null
	for filename: String in files:
		DirAccess.remove_absolute(path.path_join(filename))
	for child_name: String in directories:
		_remove_tree(path.path_join(child_name))
	DirAccess.remove_absolute(path)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL ", label, " ", detail)


func _finish() -> void:
	print("Flight statistics writer: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
