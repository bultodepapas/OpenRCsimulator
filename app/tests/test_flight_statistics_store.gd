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
	_test_string_name_keys(schema, store_script)
	_test_corrupt_generation_recovery(schema, store_script)
	_test_future_schema_protection(schema, store_script)
	_test_commit_interruptions(schema, store_script)
	_test_delete_fence_recovery(schema, store_script, reducer)
	_test_malformed_shapes_fail_closed(schema, store_script)
	_test_completed_deletion_reopens_normally(schema, store_script, reducer)
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


func _test_string_name_keys(schema: Script, store_script: Script) -> void:
	var root_uri: String = _new_root("string_name_keys")
	var store: RefCounted = store_script.new()
	_check("StringName-key fixture opens", store.open(root_uri), store.note)
	var candidate: Dictionary = store.data.duplicate(true)
	var session_id: String = "session-string-name"
	candidate.sessions.append({id = session_id, opened_utc = _utc(), closed_utc = "", status = "open"})
	candidate.current_session = session_id
	candidate.records.append({
		kind = "flight", id = "flight-string-name", seq = 1, end_seq = 2,
		session_id = session_id, aircraft_id = "stock:a", aircraft_name = "A", utc = _utc(),
		account_epoch = 0, aircraft_epoch = 0, airborne_seconds = 12.5, outcome = "completed",
		start_kind = "takeoff", full_stops = 1, touch_and_go = 0, failed_landings = 0,
		unknown_landings = 0, max_tas_mps = 27.0, max_groundspeed_mps = 23.0,
		complete_observation = true, config_hash = "", rules_version = "flight-statistics-v1",
		ended_utc = _utc(), metadata = {source = "test", detail = {surface = "grass"}},
	})
	candidate.sequence = 2
	_check("StringName keys validate with nested metadata", bool(schema.validate(candidate).ok))
	_check("StringName-key commit succeeds", store.commit(candidate), store.note)
	var persisted_session: Dictionary = store.data.sessions.back()
	var persisted_record: Dictionary = store.data.records.back()
	_check("committed StringName keys canonicalize to strings", typeof(persisted_session.keys()[0]) == TYPE_STRING and typeof(persisted_record.keys()[0]) == TYPE_STRING and typeof(persisted_record.metadata.keys()[0]) == TYPE_STRING)
	store.close()
	var reopened: RefCounted = store_script.new()
	_check("StringName-key snapshot reopens", reopened.open(root_uri), reopened.note)
	_check("nested metadata survives canonical persistence", reopened.data.records.back().metadata.detail.surface == "grass")
	reopened.close()


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


## A checksum covers only the data, so a self-consistent snapshot with wrong field types reaches
## the validator. Each shape must be refused with a reason, without engine errors.
func _test_malformed_shapes_fail_closed(schema: Script, store_script: Script) -> void:
	var root_uri: String = _new_root("malformed_shapes")
	var store: RefCounted = store_script.new()
	_check("malformed-shape fixture opens", store.open(root_uri), store.note)
	var valid: Dictionary = _fixture_with_aircraft_records(schema, store.data)
	valid.records[1].outcome = "interrupted"
	valid.records[1].complete_observation = false
	_check("malformed-shape base document validates", bool(schema.validate(valid).get("ok", false)), str(schema.validate(valid).get("errors", [])))
	var shapes: Dictionary = {
		"epochs array": func(doc: Dictionary) -> void: doc.epochs = [],
		"epochs scalar": func(doc: Dictionary) -> void: doc.epochs = 7,
		"epochs without aircraft": func(doc: Dictionary) -> void: doc.epochs = {"account": 0},
		"aircraft epochs list": func(doc: Dictionary) -> void: doc.epochs.aircraft = [],
		"account epoch dictionary": func(doc: Dictionary) -> void: doc.epochs.account = {},
		"sequence dictionary": func(doc: Dictionary) -> void: doc.sequence = {},
		"sequence array": func(doc: Dictionary) -> void: doc.sequence = [],
		"record sequence array": func(doc: Dictionary) -> void: doc.records[0].seq = [],
		"flight terminal sequence dictionary": func(doc: Dictionary) -> void: doc.records[0].end_seq = {},
		"interrupted observation flag dictionary": func(doc: Dictionary) -> void: doc.records[1].complete_observation = {},
	}
	for label: String in shapes.keys():
		var doc: Dictionary = valid.duplicate(true)
		shapes[label].call(doc)
		var result: Variant = schema.validate(doc)
		var refused: bool = typeof(result) == TYPE_DICTIONARY and result.has("ok") and result.ok == false
		var reasons: PackedStringArray = result.get("errors", PackedStringArray()) if typeof(result) == TYPE_DICTIONARY else PackedStringArray()
		_check("malformed %s is refused" % label, refused, str(result))
		_check("malformed %s reports a reason" % label, not reasons.is_empty(), str(result))
	# End to end: a newer self-consistent snapshot with malformed epochs is refused with its reason.
	var bad: Dictionary = store.data.duplicate(true)
	bad.generation = int(store.data.generation) + 1
	bad.epochs = []
	var root_path: String = ProjectSettings.globalize_path(root_uri)
	var bad_slot: String = "snapshot_b.bin" if str(store._current_slot) == "snapshot_a.bin" else "snapshot_a.bin"
	store.close()
	_check("malformed-epoch snapshot fixture is written", _write_bytes(root_path.path_join(bad_slot), _encode_snapshot(schema, bad)))
	var reopened: RefCounted = store_script.new()
	_check("malformed-epoch snapshot falls back to the valid generation", reopened.open(root_uri) and int(reopened.data.generation) == int(bad.generation) - 1, reopened.note)
	_check("malformed-epoch snapshot refusal names its reason", str(reopened.note).contains("epochs"), reopened.note)
	reopened.close()


## The purge_complete receipt stays on disk as a fence. Recovery runs once for an interrupted
## deletion; later opens take the normal path, so corruption is quarantined, not purged.
func _test_completed_deletion_reopens_normally(schema: Script, store_script: Script, reducer: Script) -> void:
	var root_uri: String = _new_root("delete_complete")
	var root_path: String = ProjectSettings.globalize_path(root_uri)
	var store: RefCounted = store_script.new()
	_check("completed-deletion fixture opens", store.open(root_uri), store.note)
	_check("completed-deletion fixture writes", store.commit(_fixture_with_aircraft_records(schema, store.data)), store.note)
	var pre_delete: Dictionary = store.data.duplicate(true)
	_stop_stage = "after_deletion_fence_publish"
	store.interruption_hook = Callable(self, "_interrupt_at")
	_check("completed-deletion fixture is interrupted after its fence", not store.delete_history("stock:a"), store.note)
	store.close()
	var recovered: RefCounted = store_script.new()
	_check("interrupted deletion still recovers forward", recovered.open(root_uri) and recovered.writable, recovered.note)
	_check("interrupted deletion recovery is reported once", str(recovered.note).contains("interrupted history deletion"), recovered.note)
	_check("forward recovery completes the receipt", str(recovered._fence.get("phase", "")) == "purge_complete")
	recovered.close()
	var reopened: RefCounted = store_script.new()
	_check("completed deletion reopens writable", reopened.open(root_uri) and reopened.writable, reopened.note)
	_check("completed deletion is not reported as recovered again", str(reopened.note).is_empty(), reopened.note)
	var competing: RefCounted = store_script.new()
	_check("read-only opener after a completed deletion sees committed data", competing.open(root_uri) and not competing.writable, competing.note)
	_check("read-only opener does not report pending deletion cleanup", not str(competing.note).contains("deletion"), competing.note)
	competing.close()
	var next: Dictionary = reopened.data.duplicate(true)
	next.clean_exit = not bool(next.clean_exit)
	_check("completed deletion accepts a later commit", reopened.commit(next), reopened.note)
	var newest: String = str(reopened._current_slot)
	var older_generation: int = int(reopened.data.generation) - 1
	reopened.close()
	var bad_bytes: PackedByteArray = "{broken-after-deletion".to_utf8_buffer()
	_check("post-deletion corruption fixture is written", _write_bytes(root_path.path_join(newest), bad_bytes))
	var damaged: RefCounted = store_script.new()
	_check("post-deletion corruption recovers the older generation", damaged.open(root_uri) and int(damaged.data.generation) == older_generation, damaged.note)
	_check("post-deletion corruption is reported as damage", str(damaged.note).contains("damaged copy"), damaged.note)
	var quarantine: String = "snapshot_quarantine_a.bin" if newest == "snapshot_a.bin" else "snapshot_quarantine_b.bin"
	_check("post-deletion damaged bytes are quarantined", FileAccess.get_file_as_bytes(root_path.path_join(quarantine)) == bad_bytes)
	_check("deleted aircraft stays hidden behind the completed fence", reducer.query(damaged.data, "stock:a", "lifetime").started == 0
		and reducer.query(damaged.data, "stock:b", "lifetime").started == 2)
	damaged.close()
	# A stale pre-fence copy reappearing with a higher generation is never promoted; it is repaired forward.
	var stale: Dictionary = pre_delete.duplicate(true)
	stale.generation = 1000
	_check("stale pre-fence slot fixture is written", _write_bytes(root_path.path_join(newest), _encode_snapshot(schema, stale)))
	var repaired: RefCounted = store_script.new()
	_check("stale pre-fence slot opens behind the completed fence", repaired.open(root_uri) and int(repaired.data.generation) == older_generation, repaired.note)
	_check("stale pre-fence slot does not resurrect deleted history", reducer.query(repaired.data, "stock:a", "lifetime").started == 0)
	_check("stale pre-fence slot is replaced behind the fence", _both_slots_satisfy_fence(repaired, root_uri))
	repaired.close()


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
