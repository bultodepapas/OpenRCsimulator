extends SceneTree
## UI-FS-03 store generation, recovery, locking, and deletion-fence regressions.

var _checks: int = 0
var _failures: int = 0
var _stop_stage: String = ""
var _roots: Array[String] = []


func _initialize() -> void:
	var schema: Script = load("res://statistics/schema.gd")
	var store_script: Script = load("res://statistics/store.gd")
	var reducer: Script = load("res://statistics/reducer.gd")
	if schema == null or store_script == null or reducer == null:
		_check("statistics modules load", false)
		_finish()
		return
	_test_initial_round_trip_and_lock(schema, store_script)
	_test_corrupt_generation_recovery(schema, store_script)
	_test_future_schema_protection(schema, store_script)
	_test_commit_interruptions(schema, store_script)
	_test_delete_fence_recovery(schema, store_script, reducer)
	for root_uri: String in _roots:
		_remove_fixture(root_uri)
	_finish()


func _test_initial_round_trip_and_lock(schema: Script, store_script: Script) -> void:
	var root_uri: String = _new_root("roundtrip")
	var writer: RefCounted = store_script.new()
	_check("new store opens writable", writer.open(root_uri) and writer.writable, writer.note)
	_check("new store schema is canonical", bool(schema.validate(writer.data).ok))
	var candidate: Dictionary = _fixture_data(schema, writer.data, true)
	_check("first fixture commit succeeds", writer.commit(candidate), writer.note)
	var pilot_id: String = str(writer.data.pilot_id)
	var generation: int = int(writer.data.generation)
	writer.close()
	var second: RefCounted = store_script.new()
	_check("stored generation reopens", second.open(root_uri), second.note)
	_check("round trip retains identity and generation", second.data.pilot_id == pilot_id and second.data.generation == generation)
	_check("packed detector values retain native type", typeof(second.data.active_context.samples) == TYPE_PACKED_FLOAT64_ARRAY)
	_check("packed detector values retain float64", absf(float(second.data.active_context.samples[1]) - 2.5) < 1e-12)
	var competing: RefCounted = store_script.new()
	_check("second live writer sees read-only data", competing.open(root_uri) and not competing.writable, competing.note)
	_check("read-only writer sees the same committed generation", competing.data.generation == generation and competing.data.pilot_id == pilot_id)
	competing.close()
	second.close()


func _test_corrupt_generation_recovery(schema: Script, store_script: Script) -> void:
	var root_uri: String = _new_root("corrupt")
	var writer: RefCounted = store_script.new()
	_check("corruption fixture opens", writer.open(root_uri), writer.note)
	var candidate: Dictionary = _fixture_data(schema, writer.data, false)
	_check("corruption fixture writes generation", writer.commit(candidate), writer.note)
	var newest: String = str(writer._current_slot)
	var root_path: String = ProjectSettings.globalize_path(root_uri)
	writer.close()
	var corrupted_path: String = root_path.path_join(newest)
	var bad_bytes: PackedByteArray = "{broken-snapshot".to_utf8_buffer()
	_check("corrupt fixture is written", _write_bytes(corrupted_path, bad_bytes))
	var recovered: RefCounted = store_script.new()
	_check("older valid generation recovers", recovered.open(root_uri), recovered.note)
	_check("recovery does not invent the uncommitted fixture", recovered.data.sequence == 0 and recovered.data.records.is_empty())
	_check("recovered store explains corruption", str(recovered.note).contains("Recovered"))
	_check("recovered store remains writable after preserving damage", recovered.writable)
	var quarantine: String = "snapshot_quarantine_a.bin" if newest == "snapshot_a.bin" else "snapshot_quarantine_b.bin"
	var retained: PackedByteArray = FileAccess.get_file_as_bytes(root_path.path_join(quarantine))
	_check("damaged bytes are retained for diagnosis", retained == bad_bytes)
	recovered.close()


func _test_future_schema_protection(schema: Script, store_script: Script) -> void:
	var root_uri: String = _new_root("future")
	var store: RefCounted = store_script.new()
	_check("future fixture opens", store.open(root_uri), store.note)
	var future: Dictionary = store.data.duplicate(true)
	future.schema_version = int(schema.SCHEMA_VERSION) + 1
	future.generation = int(store.data.generation) + 50
	future.future_extension = {"new_metric": PackedFloat64Array([8.0, 13.0])}
	var encoded: PackedByteArray = _encode_snapshot(schema, future)
	var root_path: String = ProjectSettings.globalize_path(root_uri)
	var future_path: String = root_path.path_join("snapshot_b.bin")
	store.close()
	_check("future snapshot fixture is written", _write_bytes(future_path, encoded))
	var protected: RefCounted = store_script.new()
	_check("future schema opens without replacement", protected.open(root_uri), protected.note)
	_check("future schema is read-only", not protected.writable and int(protected.data.schema_version) > int(schema.SCHEMA_VERSION), protected.note)
	_check("future schema produces a protection notice", str(protected.note).contains("newer"))
	protected.close()
	_check("future snapshot bytes remain untouched", FileAccess.get_file_as_bytes(future_path) == encoded)


func _test_commit_interruptions(schema: Script, store_script: Script) -> void:
	var root_uri: String = _new_root("commit_cuts")
	var store: RefCounted = store_script.new()
	_check("interruption fixture opens", store.open(root_uri), store.note)
	var candidate: Dictionary = store.data.duplicate(true)
	candidate.sessions.append(_session("cut-session", _utc()))
	candidate.current_session = "cut-session"
	_stop_stage = "after_snapshot_readback"
	store.interruption_hook = Callable(self, "_interrupt_at")
	_check("pre-publish interruption is reported", not store.commit(candidate), store.note)
	store.close()
	var before_publish: RefCounted = store_script.new()
	_check("pre-publish interruption keeps prior generation", before_publish.open(root_uri), before_publish.note)
	_check("pre-publish session is not visible", before_publish.data.current_session.is_empty() and before_publish.data.generation == 1)
	before_publish.close()
	var publisher: RefCounted = store_script.new()
	_check("post-publish fixture reopens", publisher.open(root_uri), publisher.note)
	var published: Dictionary = publisher.data.duplicate(true)
	published.sessions.append(_session("published-session", _utc()))
	published.current_session = "published-session"
	_stop_stage = "after_snapshot_publish"
	publisher.interruption_hook = Callable(self, "_interrupt_at")
	_check("post-publish interruption reports uncertain receipt", not publisher.commit(published), publisher.note)
	publisher.close()
	var after_publish: RefCounted = store_script.new()
	_check("post-publish generation recovers", after_publish.open(root_uri), after_publish.note)
	_check("published commit is present exactly once", after_publish.data.current_session == "published-session" and after_publish.data.generation == 2)
	after_publish.close()


func _test_delete_fence_recovery(schema: Script, store_script: Script, reducer: Script) -> void:
	var root_uri: String = _new_root("delete_fence")
	var store: RefCounted = store_script.new()
	_check("deletion fixture opens", store.open(root_uri), store.note)
	var seeded: Dictionary = _fixture_with_aircraft_records(schema, store.data)
	_check("deletion fixture writes", store.commit(seeded), store.note)
	var prior_b: Dictionary = {}
	for record: Dictionary in store.data.records:
		if record.aircraft_id == "stock:b" and record.kind == "flight":
			prior_b[record.id] = record.duplicate(true)
	var before_all: Dictionary = reducer.query(store.data, "", "lifetime")
	_check("fixture has three flights and a crash", before_all.started == 3 and before_all.crashes == 1)
	_check("aircraft B clean streak is independent", reducer.query(store.data, "stock:b", "lifetime").current_streak == 2)
	_stop_stage = "after_deletion_fence_publish"
	store.interruption_hook = Callable(self, "_interrupt_at")
	_check("post-fence interruption is surfaced", not store.delete_history("stock:a"), store.note)
	_check("post-fence interruption marks forward recovery", str(store.note).contains("after_deletion_fence_publish"))
	store.close()
	var recovered: RefCounted = store_script.new()
	_check("fenced deletion recovers forward", recovered.open(root_uri), recovered.note)
	var all_after: Dictionary = reducer.query(recovered.data, "", "lifetime")
	var a_after: Dictionary = reducer.query(recovered.data, "stock:a", "lifetime")
	var b_after: Dictionary = reducer.query(recovered.data, "stock:b", "lifetime")
	_check("deleted aircraft contributions stay hidden", all_after.started == 2 and all_after.crashes == 0 and a_after.started == 0)
	_check("surviving aircraft records are preserved", b_after.started == 2 and b_after.current_streak == 2)
	_check("account streak does not bridge the deletion gap", all_after.current_streak == 1 and all_after.best_streak == 1)
	_check("surviving B records are byte-equivalent as values", _has_records(recovered.data.records, prior_b))
	_check("recovery leaves both slots behind the fence", _both_slots_satisfy_fence(recovered, root_uri))
	recovered.close()


func _fixture_data(schema: Script, source: Dictionary, with_records: bool) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	var session_id: String = "session-fixture"
	result.sessions.append(_session(session_id, _utc()))
	result.current_session = session_id
	result.active_context = {"samples": PackedFloat64Array([1.25, 2.5, 10.125])}
	if with_records:
		result.records = [_flight("flight-fixture", 1, 2, session_id, "stock:a", "A", "completed", 60.25, 1, 2, 0, 0, 33.4, 29.1)]
		result.sequence = 2
	return result


func _fixture_with_aircraft_records(schema: Script, source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	var session_id: String = "session-delete"
	result.sessions.append(_session(session_id, _utc()))
	result.current_session = session_id
	result.records = [
		_flight("a-flight-1", 1, 2, session_id, "stock:a", "A", "completed", 20.0, 1, 0, 0, 0, 30.0, 25.0),
		_flight("b-flight-1", 3, 4, session_id, "stock:b", "B", "completed", 40.0, 1, 0, 0, 0, 32.0, 26.0),
		_event("a-crash", 5, session_id, "stock:a", "A", "crash"),
		_flight("b-flight-2", 6, 7, session_id, "stock:b", "B", "completed", 12.0, 1, 0, 0, 0, 35.0, 30.0),
	]
	result.sequence = 7
	return result


func _flight(id: String, seq: int, end_seq: int, session_id: String, aircraft_id: String, name: String,
		outcome: String, seconds: float, full_stops: int, touch_and_go: int, failed: int, unknown: int,
		tas: float, groundspeed: float) -> Dictionary:
	return {
		"kind": "flight", "id": id, "seq": seq, "end_seq": end_seq,
		"session_id": session_id, "aircraft_id": aircraft_id, "aircraft_name": name, "utc": _utc(),
		"account_epoch": 0, "aircraft_epoch": 0,
		"airborne_seconds": seconds, "outcome": outcome, "start_kind": "takeoff",
		"full_stops": full_stops, "touch_and_go": touch_and_go,
		"failed_landings": failed, "unknown_landings": unknown,
		"max_tas_mps": tas, "max_groundspeed_mps": groundspeed,
		"complete_observation": true, "config_hash": "", "rules_version": "flight-statistics-v1",
		"ended_utc": _utc(), "metadata": {"source": "test", "scenario": "fixture"},
	}


func _event(id: String, seq: int, session_id: String, aircraft_id: String, name: String, kind: String) -> Dictionary:
	return {
		"kind": kind, "id": id, "seq": seq, "session_id": session_id,
		"aircraft_id": aircraft_id, "aircraft_name": name, "utc": _utc(),
		"account_epoch": 0, "aircraft_epoch": 0, "metadata": {"source": "test"},
	}


func _session(id: String, opened_utc: String) -> Dictionary:
	return {"id": id, "opened_utc": opened_utc, "closed_utc": "", "status": "open"}


func _encode_snapshot(schema: Script, snapshot: Dictionary) -> PackedByteArray:
	var canonical: Dictionary = schema.canonicalize(snapshot)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(canonical))
	var wrapper: Dictionary = {
		"format": "openrc-flight-statistics",
		"codec_version": 1,
		"checksum_sha256": context.finish().hex_encode(),
		"data": canonical,
	}
	var payload: PackedByteArray = var_to_bytes(wrapper)
	var frame: PackedByteArray = "ORFSNP01".to_ascii_buffer()
	var frame_context := HashingContext.new()
	frame_context.start(HashingContext.HASH_SHA256)
	frame_context.update(payload)
	frame.append_array(frame_context.finish())
	frame.append_array(payload)
	return frame


func _both_slots_satisfy_fence(store: RefCounted, root_uri: String) -> bool:
	var fence: Dictionary = store._fence
	if fence.is_empty():
		return false
	var root_path: String = ProjectSettings.globalize_path(root_uri)
	for slot: String in ["snapshot_a.bin", "snapshot_b.bin"]:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(root_path.path_join(slot))
		var frame: Dictionary = store._unframe("ORFSNP01", bytes)
		if not bool(frame.get("ok", false)):
			return false
		var wrapper: Variant = bytes_to_var(frame.payload)
		if typeof(wrapper) != TYPE_DICTIONARY or not wrapper.has("data"):
			return false
		if int(wrapper.data.generation) < int(fence.required_generation):
			return false
		for record: Dictionary in wrapper.data.records:
			if record.kind != "gap" and record.aircraft_id == "stock:a" and int(record.seq) <= int(fence.cutoff_sequence):
				return false
	return true


func _has_records(records: Array, expected: Dictionary) -> bool:
	for id: String in expected.keys():
		var found: bool = false
		for record: Dictionary in records:
			if record.id == id and record == expected[id]:
				found = true
				break
		if not found:
			return false
	return true


func _interrupt_at(stage: String) -> bool:
	return stage == _stop_stage


func _new_root(label: String) -> String:
	var root_uri: String = "user://flight_statistics_store_%s_%d_%d" % [label, OS.get_process_id(), Time.get_ticks_usec()]
	_roots.append(root_uri)
	return root_uri


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	return ok


func _utc() -> String:
	return Time.get_datetime_string_from_system(true)


func _remove_fixture(root_uri: String) -> void:
	var root_path: String = ProjectSettings.globalize_path(root_uri)
	var user_path: String = ProjectSettings.globalize_path("user://")
	if not root_path.begins_with(user_path) or root_path == user_path:
		_check("fixture cleanup path is scoped", false, root_path)
		return
	_remove_tree(root_path)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	var files: PackedStringArray = directory.get_files()
	var directories: PackedStringArray = directory.get_directories()
	directory = null
	for file_name: String in files:
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name: String in directories:
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s %s" % [label, detail])


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
