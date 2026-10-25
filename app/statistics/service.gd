## UI-FS: app-owned observation service. No inputs, forces or solver checkpoint mutation.
extends Node

signal changed
var note := ""
var revision: int = 0
var data: Dictionary = {}
var store: RefCounted
var detector: RefCounted
var adapter: RefCounted
var persistent := false
var _session: Node
var _aircraft_id := ""
var _aircraft_name := ""
var _metadata: Dictionary = {}
var _active_record: Dictionary = {}
var _generation := ""
var _last_operation := -1
var _last_flush_time := 0.0
var _dirty := false
var _flush_requested := false
var _suspended := false
var _branch := false
var _closed := false
var _query_cache: Dictionary = {}
var _summary_cache: Dictionary = {}
var _query_bucket := -1
var _retry_after_msec := 0
var _writer: RefCounted
var _write_revision := -1
var _write_time := 0.0
var _write_tick := 0
var _durable_tick := 0
var _save_error := ""
var _available := true


func setup(path: String = "user://flight_statistics", save: bool = true) -> bool:
	persistent = save
	store = load("res://statistics/store.gd").new()
	_writer = load("res://statistics/writer.gd").new()
	if save:
		store.open(path)
		_available = not store.data.is_empty()
		data = store.data.duplicate(true)
		note = store.note
	else:
		data = load("res://statistics/schema.gd").create(_uuid())
	if data.is_empty():
		data = load("res://statistics/schema.gd").create(_uuid())
	if not save or store.writable:
		_recover()
	return not save or store.writable


func _uuid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func _next_sequence() -> int:
	data.sequence = int(data.get("sequence", 0)) + 1
	return int(data.sequence)


func _utc() -> String:
	return Time.get_datetime_string_from_system(true)


func _recover() -> void:
	var recovered := false
	for record: Dictionary in data.records:
		if record.get("kind") == "flight" and record.get("outcome") == "active":
			record.outcome = "interrupted"
			record.complete_observation = false
			record.end_seq = _next_sequence()
			record.ended_utc = _utc()
			recovered = true
	data.active_context = {}
	if bool(data.get("clean_exit", true)):
		data.current_session = ""
	if recovered:
		note = "Interrupted flight recovered. Only saved airborne time is included."
		_mark_dirty()
		flush()


func _ensure_session() -> void:
	if not str(data.get("current_session", "")).is_empty():
		return
	data.current_session = _uuid()
	data.sessions.append({id = data.current_session, opened_utc = _utc(), closed_utc = "", status = "open"})


func begin_activity(session: Node, aircraft_id: String, aircraft_name: String, metadata: Dictionary = {}) -> void:
	if session == null or (persistent and not store.writable):
		return
	if _session == session:
		resume_activity()
		return
	if not end_activity("abandoned"):
		return
	_ensure_session()
	_session = session
	_aircraft_id = aircraft_id
	_aircraft_name = aircraft_name
	_metadata = metadata.duplicate(true)
	_generation = _uuid()
	_last_operation = -1
	_branch = false
	_suspended = false
	data.clean_exit = false
	adapter = load("res://statistics/fixed_wing_adapter.gd").new()
	adapter.configure(session, aircraft_id, Callable(self, "_observe"))
	detector = load("res://statistics/detector.gd").new()
	detector.configure(adapter.profile, session.start_choice != "runway")
	_session.statistics_lifecycle.connect(_lifecycle)
	_session.sim.paused_changed.connect(_paused)
	adapter.attach()
	_last_flush_time = float(session.sim.time())
	_mark_dirty()
	_flush_requested = true


func _observe(sample: Dictionary) -> void:
	if _suspended or _branch or detector == null:
		return
	_ingest(detector.observe(sample))
	var bucket: int = int(sample.get("tick", 0)) / 24
	if bucket != _query_bucket:
		_query_cache.clear()
		_query_bucket = bucket
	if is_instance_valid(_session) and float(_session.sim.time()) - _last_flush_time >= 5.0:
		_flush_requested = true


func _record(kind: String) -> Dictionary:
	return {kind = kind, id = _uuid(), seq = _next_sequence(), session_id = data.current_session,
		aircraft_id = _aircraft_id, aircraft_name = _aircraft_name, utc = _utc(),
		account_epoch = int(data.epochs.get("account", 0)),
		aircraft_epoch = int(data.epochs.get("aircraft", {}).get(_aircraft_id, 0)),
		metadata = _metadata.duplicate(true)}


func _ingest(events: Array) -> void:
	for event: Dictionary in events:
		match str(event.get("type", "")):
			"started":
				_active_record = _record("flight")
				_active_record.end_seq = -1
				_active_record.merge(event.get("flight", {}), true)
				_active_record.config_hash = str(_metadata.get("config_hash", ""))
				_active_record.rules_version = "flight-statistics-v1"
				_active_record.start_kind = event.get("start_kind", "takeoff")
				_active_record.metadata.events = []
				_append_event(event)
				_update_active()
			"landing":
				_append_event(event)
			"closed":
				if not _active_record.is_empty():
					_append_event(event)
					_active_record.merge(event.get("flight", {}), true)
					_active_record.outcome = str(event.get("outcome", _active_record.get("outcome", "interrupted")))
					if _active_record.outcome == "interrupted":
						_active_record.complete_observation = false
					_active_record.end_seq = _next_sequence()
					_active_record.ended_utc = _utc()
					_upsert(_active_record)
					_active_record = {}
			"crash":
				var crash: Dictionary = _record("crash")
				crash.metadata.ground = bool(event.get("ground", false))
				data.records.append(crash)
		_mark_dirty()
		_flush_requested = true


func _append_event(event: Dictionary) -> void:
	if _active_record.is_empty():
		return
	var timeline: Array = _active_record.metadata.get("events", [])
	# Bounded event detail: aggregate counters continue after the detail limit.
	if timeline.size() >= 128:
		_active_record.metadata.events_omitted = int(_active_record.metadata.get("events_omitted", 0)) + 1
		return
	var entry: Dictionary = {}
	for key: String in ["type", "kind", "outcome", "reason", "tick", "first_contact_tick", "start_kind"]:
		if event.has(key): entry[key] = event[key]
	timeline.append(entry)
	_active_record.metadata.events = timeline


func _update_active() -> void:
	if _active_record.is_empty() or detector == null or detector.flight.is_empty():
		return
	_active_record.merge(detector.flight, true)
	# A live observation has no terminal boundary yet; detector continuity is retained
	# in its checkpoint and copied into the record only when the flight closes.
	_active_record.complete_observation = false
	_upsert(_active_record)


func _upsert(record: Dictionary) -> void:
	for i: int in range(data.records.size() - 1, -1, -1):
		if data.records[i].id == record.id:
			data.records[i] = record.duplicate(true)
			return
	data.records.append(record.duplicate(true))


func _mark_dirty() -> void:
	_dirty = true
	revision += 1
	_query_cache.clear()
	_summary_cache.clear()
	changed.emit()


func _paused(_paused_value: bool) -> void:
	_flush_requested = true


func _lifecycle(receipt: Dictionary) -> void:
	var operation: int = int(receipt.get("operation_id", -1))
	if operation <= _last_operation or not receipt.get("success", false):
		return
	_last_operation = operation
	var cause: String = str(receipt.get("cause", "restart"))
	if cause == "checkpoint_restore":
		_ingest(detector.end("interrupted"))
		_branch = true
		note = "Checkpoint experiment: flight statistics are not recorded until Restart."
	else:
		if not _branch:
			_ingest(detector.end("restarted"))
			var restart: Dictionary = _record("restart")
			restart.metadata.cause = cause
			data.records.append(restart)
		_branch = false
		_generation = _uuid()
		adapter.configure(_session, _aircraft_id, Callable(self, "_observe"))
		_metadata.config_hash = str(_session.aircraft.get("input_identity", {}).get("sha256", ""))
		detector.configure(adapter.profile, _session.start_choice != "runway")
		_last_flush_time = float(_session.sim.time())
	_mark_dirty()
	_flush_requested = true


func suspend_activity() -> void:
	if adapter != null:
		adapter.detach()
	_suspended = true
	flush()


func resume_activity() -> void:
	_suspended = false
	if adapter != null and not _branch:
		adapter.attach()


func end_activity(reason: String = "abandoned", discard_unsaved: bool = false, close_session: bool = false) -> bool:
	_finish_write()
	if detector == null:
		if close_session and not discard_unsaved:
			_close_session_record()
			return flush(false)
		return true
	var previous_data: Dictionary = data.duplicate(true)
	var previous_record: Dictionary = _active_record.duplicate(true)
	var previous_detector: Dictionary = detector.snapshot()
	if detector != null:
		_ingest(detector.end(reason))
	data.active_context = {}
	if close_session:
		_close_session_record()
	if not discard_unsaved and not flush(false):
		data = previous_data
		_active_record = previous_record
		detector.restore(previous_detector)
		_query_cache.clear()
		_summary_cache.clear()
		return false
	if adapter != null:
		adapter.detach()
	if is_instance_valid(_session):
		if _session.statistics_lifecycle.is_connected(_lifecycle):
			_session.statistics_lifecycle.disconnect(_lifecycle)
		if _session.sim.paused_changed.is_connected(_paused):
			_session.sim.paused_changed.disconnect(_paused)
	_session = null
	adapter = null
	detector = null
	_active_record = {}
	data.active_context = {}
	_query_cache.clear()
	_summary_cache.clear()
	if discard_unsaved:
		_flush_requested = false
		_dirty = false
		if persistent:
			data = store.data.duplicate(true)
			for record: Dictionary in data.records:
				if record.get("outcome") == "active":
					record.outcome = "interrupted"
					record.complete_observation = false
					record.end_seq = _next_sequence()
			data.active_context = {}
	return true


func _process(_delta: float) -> void:
	if _writer != null:
		_accept_write(_writer.poll())
	if _flush_requested and Time.get_ticks_msec() >= _retry_after_msec:
		if _writer != null and _writer.pending(): return
		_flush_requested = false
		if not persistent:
			flush()
		else:
			_update_active()
			_capture_context()
			_write_revision = revision
			_write_time = float(_session.sim.time()) if is_instance_valid(_session) else 0.0
			_write_tick = int(_session.sim.tick) if is_instance_valid(_session) else 0
			if not _writer.start(store, _write_snapshot()):
				_flush_requested = true


func _capture_context() -> void:
	if detector != null and is_instance_valid(_session):
		data.active_context = {generation_id = _generation, aircraft_id = _aircraft_id,
			tick = int(_session.sim.tick), detector = detector.snapshot(), suspended = _suspended}


func _write_snapshot() -> Dictionary:
	# Ledger entries are immutable after insertion: _upsert replaces the dictionary.
	# Copy the array, not every historical record, so the worker owns a stable view.
	# Mutable root containers and active checkpoint are detached explicitly.
	var snapshot := data.duplicate(false)
	snapshot.records = data.records.duplicate(false)
	snapshot.sessions = data.sessions.duplicate(true)
	snapshot.epochs = data.epochs.duplicate(true)
	snapshot.active_context = data.get("active_context", {}).duplicate(true)
	return snapshot


func _accept_write(result: Dictionary) -> void:
	if result.is_empty(): return
	if bool(result.get("ok", false)):
		data.generation = int(result.generation)
		_dirty = revision != _write_revision
		_last_flush_time = _write_time
		_durable_tick = _write_tick
		if note == _save_error: note = ""
		_save_error = ""
	else:
		note = str(result.get("note", "Statistics could not be saved."))
		_save_error = note
		_retry_after_msec = Time.get_ticks_msec() + 5000
		_flush_requested = true
	_query_cache.clear()
	changed.emit()


func _finish_write() -> void:
	if _writer != null: _accept_write(_writer.finish())


func flush(capture_context: bool = true) -> bool:
	_finish_write()
	if data.is_empty():
		return true
	_update_active()
	if capture_context: _capture_context()
	var ok: bool = not persistent or store.commit(data)
	if ok:
		_dirty = false
		_flush_requested = false
		_retry_after_msec = 0
		if persistent:
			data = store.data.duplicate(true)
		if is_instance_valid(_session):
			_last_flush_time = float(_session.sim.time())
			_durable_tick = int(_session.sim.tick)
		if note == _save_error: note = ""
		_save_error = ""
	else:
		note = store.note
		_save_error = note
		_retry_after_msec = Time.get_ticks_msec() + 5000
	_query_cache.clear()
	return ok


func query(aircraft_id: String = "", period: String = "session") -> Dictionary:
	if period == "since_reset": period = "counters"
	var key: String = aircraft_id + ":" + period
	if not _query_cache.has(key):
		_update_active()
		var result: Dictionary = load("res://statistics/reducer.gd").query(data, aircraft_id, period)
		result.revision = revision
		result.available = _available and bool(result.get("available", false))
		result.has_lifetime_history = not data.get("records", []).is_empty()
		result.tracking_started_utc = str(data.get("tracking_started_utc", ""))
		result.durable_tick = _durable_tick
		result.save_pending = _dirty or (_writer != null and _writer.pending())
		_query_cache[key] = result
	return _query_cache[key].duplicate(true)


## HUD summaries retain the event rollup, adding only current-flight scalar deltas.
## The complete ledger is not validated/copied for every rendered HUD refresh.
func summary(aircraft_id: String = "", period: String = "session") -> Dictionary:
	if period == "since_reset": period = "counters"
	var key := aircraft_id + ":" + period
	if not _summary_cache.has(key):
		_update_active()
		var result: Dictionary = load("res://statistics/reducer.gd").query(data, aircraft_id, period, "", false)
		var included := not _active_record.is_empty() and (aircraft_id.is_empty() or aircraft_id == _aircraft_id)
		_summary_cache[key] = {"result": result, "active_id": str(_active_record.get("id", "")) if included else "",
			"seconds": float(_active_record.get("airborne_seconds", 0.0)) if included else 0.0}
	var cached: Dictionary = _summary_cache[key]
	var result: Dictionary = cached.result.duplicate(true)
	if detector != null and not detector.flight.is_empty() and not str(cached.active_id).is_empty() \
			and str(cached.active_id) == str(_active_record.get("id", "")):
		var delta_seconds := maxf(0.0, float(detector.flight.airborne_seconds) - float(cached.seconds))
		result.airborne_seconds = float(result.airborne_seconds) + delta_seconds
		result.current_clean_seconds = float(result.current_clean_seconds) + delta_seconds
		result.best_clean_seconds = maxf(float(result.best_clean_seconds), float(result.current_clean_seconds))
		result.max_tas_mps = maxf(float(result.max_tas_mps), float(detector.flight.max_tas_mps))
		result.max_groundspeed_mps = maxf(float(result.max_groundspeed_mps), float(detector.flight.max_groundspeed_mps))
	result.revision = revision
	result.available = _available and bool(result.get("available", false))
	return result


func aircraft_choices() -> Array:
	var choices: Array = []
	var seen: Dictionary = {}
	for record: Dictionary in data.get("records", []):
		var id: String = str(record.get("aircraft_id", ""))
		if not id.is_empty() and not seen.has(id):
			seen[id] = true
			choices.append({id = id, name = str(record.get("aircraft_name", id))})
	return choices


func can_manage() -> bool:
	return _session == null and not _dirty and (not persistent or store.writable)


func reset_counters(scope: String, aircraft_id: String = "") -> bool:
	if not can_manage():
		return false
	var candidate: Dictionary = load("res://statistics/reducer.gd").reset(data, scope, aircraft_id, _uuid(), _utc())
	if candidate.is_empty():
		return false
	if persistent and not store.commit(candidate):
		note = store.note
		return false
	data = store.data.duplicate(true) if persistent else candidate
	_query_cache.clear()
	_summary_cache.clear()
	revision += 1
	changed.emit()
	return true


func delete_history(aircraft_id: String = "") -> bool:
	if not can_manage():
		return false
	if not persistent:
		# Sandbox UI exercises the same deletion reducer through an isolated temporary store in tests.
		note = "History management is unavailable in this temporary session."
		return false
	if not store.delete_history(aircraft_id):
		note = store.note
		return false
	data = store.data.duplicate(true)
	_query_cache.clear()
	_summary_cache.clear()
	revision += 1
	changed.emit()
	return true


func finish(discard_unsaved: bool = false) -> bool:
	return end_activity("abandoned", discard_unsaved, true)


func _close_session_record() -> void:
	data.clean_exit = true
	for entry: Dictionary in data.get("sessions", []):
		if entry.id == data.current_session:
			entry.closed_utc = _utc()
			entry.status = "closed"


func close() -> void:
	if _closed:
		return
	_closed = true
	_finish_write()
	end_activity("interrupted", true)
	if store != null:
		store.close()


func _exit_tree() -> void:
	close()
