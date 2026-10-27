extends RefCounted
class_name FlightStatisticsStore
## Bounded local snapshots for flight statistics. Snapshot bytes are object-free Godot variants.

const DEFAULT_ROOT: String = "user://flight_statistics"
const STORE_FORMAT: String = "openrc-flight-statistics"
const CODEC_VERSION: int = 1
const FENCE_FORMAT: String = "openrc-flight-statistics-deletion-fence"
const FENCE_VERSION: int = 1
const SNAPSHOT_MAGIC: String = "ORFSNP01"
const FENCE_MAGIC: String = "ORFDNC01"
const FRAME_HEADER_BYTES: int = 40
const MAX_SNAPSHOT_BYTES: int = 64 * 1024 * 1024
const MAX_FENCE_BYTES: int = 64 * 1024
const SLOT_A: String = "snapshot_a.bin"
const SLOT_B: String = "snapshot_b.bin"
const FENCE_A: String = "deletion_fence_a.bin"
const FENCE_B: String = "deletion_fence_b.bin"
const PREPARED_DELETE: String = "snapshot_delete_prepare.bin"
const NORMAL_TEMP: String = "snapshot_write.tmp"
const FENCE_TEMP: String = "deletion_fence_write.tmp"
const LOCK_DIR: String = ".writer_lock"

var data: Dictionary = {}
var note: String = ""
var writable: bool = false
var interruption_hook: Callable = Callable()

var _root_uri: String = ""
var _root_path: String = ""
var _lock_path: String = ""
var _lock_token: String = ""
var _owns_lock: bool = false
var _current_slot: String = ""
var _fence: Dictionary = {}
var _schema: Script
var _closed: bool = false


func open(root: String = DEFAULT_ROOT) -> bool:
	close()
	_closed = false
	data = {}
	note = ""
	writable = false
	_current_slot = ""
	_fence = {}
	_root_uri = root.strip_edges()
	if not _valid_root_uri(_root_uri):
		note = "Statistics storage must use a bounded user:// directory."
		return false
	_root_path = ProjectSettings.globalize_path(_root_uri)
	if _root_path.is_empty() or DirAccess.make_dir_recursive_absolute(_root_path) != OK:
		note = "Statistics storage directory could not be opened."
		return false
	_lock_path = _root_path.path_join(LOCK_DIR)
	_schema = load("res://statistics/schema.gd")
	if _schema == null:
		note = "Statistics schema is unavailable."
		return false
	var lock_result: Dictionary = _acquire_writer_lock()
	_owns_lock = bool(lock_result.get("owned", false))
	var lock_note: String = str(lock_result.get("note", ""))
	var fences_result: Dictionary = _read_fences()
	if bool(fences_result.get("blocked", false)):
		note = str(fences_result.get("note", "Deletion receipt is invalid; statistics are protected."))
		return false
	_fence = fences_result.get("fence", {})
	var snapshots_result: Dictionary = _read_snapshots()
	var has_snapshot_files: bool = bool(snapshots_result.get("has_files", false))
	var future_snapshot: Dictionary = snapshots_result.get("future", {})
	if not future_snapshot.is_empty():
		data = future_snapshot.get("data", {})
		writable = false
		note = "A newer statistics schema is present. This build opened it read-only and will not overwrite it."
		return not data.is_empty()
	var snapshot_entries: Array = snapshots_result.get("entries", [])
	var deletion_pending: bool = _deletion_pending(snapshot_entries)
	if _owns_lock and deletion_pending:
		return _recover_deletion(snapshot_entries)
	elif deletion_pending:
		var safe_snapshot: Dictionary = _newest_fence_safe_snapshot(snapshot_entries, _fence)
		if safe_snapshot.is_empty():
			var prepared: Dictionary = _read_snapshot_file(_root_path.path_join(PREPARED_DELETE))
			if bool(prepared.get("ok", false)) and _snapshot_satisfies_fence(prepared.data, _fence):
				data = prepared.data
				writable = false
				note = "History deletion is committed; cleanup will finish when the store can be written."
				return true
			note = "History deletion is committed but its survivor snapshot is unavailable. Deleted history remains hidden pending repair."
			return false
		data = safe_snapshot.data
		_current_slot = safe_snapshot.slot
		writable = false
		note = "History deletion is committed; cleanup requires the single writer."
		return true
	var chosen: Dictionary = _newest_snapshot(snapshot_entries) if _fence.is_empty() else _newest_fence_safe_snapshot(snapshot_entries, _fence)
	if chosen.is_empty():
		if has_snapshot_files:
			note = str(snapshots_result.get("note", "No valid statistics snapshot could be recovered; original files were retained."))
			return false
		if not _fence.is_empty():
			note = "A deletion receipt exists without a recoverable survivor snapshot. Statistics are unavailable; deleted data will not be shown."
			return false
		if not _owns_lock:
			note = lock_note if not lock_note.is_empty() else "Statistics store is being initialized by another process."
			return false
		var initial: Dictionary = _schema.create(_schema.new_id())
		data = initial
		writable = true
		if not commit(initial):
			data = {}
			writable = false
			if note.is_empty():
				note = "The initial statistics snapshot could not be saved."
			return false
		if not lock_note.is_empty():
			note = lock_note
		return true
	data = chosen.data
	_current_slot = str(chosen.slot)
	writable = _owns_lock
	var recovery_note: String = str(snapshots_result.get("note", ""))
	if not recovery_note.is_empty():
		note = recovery_note
	if not lock_note.is_empty():
		note = lock_note
	if _owns_lock and bool(snapshots_result.get("recover_corrupt", false)):
		if not _quarantine_bad_snapshots(snapshots_result.get("invalid_slots", [])):
			writable = false
			note = "Recovered a valid snapshot, but the damaged copy could not be preserved; store is read-only."
		elif note.is_empty():
			note = "Recovered the last valid statistics snapshot. A damaged copy was retained for diagnosis."
	if not _owns_lock:
		writable = false
		if note.is_empty():
			note = lock_note
	return true


func commit(candidate: Dictionary) -> bool:
	if not writable or not _owns_lock:
		if note.is_empty():
			note = "Statistics store is read-only."
		return false
	var validation: Dictionary = _schema.validate(candidate)
	if not bool(validation.get("ok", false)):
		note = "Statistics update was rejected: " + "; ".join(validation.get("errors", PackedStringArray()))
		return false
	if data.is_empty() or str(candidate.pilot_id) != str(data.pilot_id):
		note = "Statistics update cannot change the local pilot identity."
		return false
	if int(candidate.sequence) < int(data.sequence):
		note = "Statistics sequence cannot move backwards."
		return false
	if not _retains_existing_record_ids(candidate):
		note = "Normal commits cannot delete history; use the fenced history deletion operation."
		return false
	var next_generation: int = int(data.generation) + 1
	if next_generation > _schema.MAX_SEQUENCE:
		note = "Statistics generation limit reached."
		return false
	var committed: Dictionary = _schema.canonicalize(candidate.duplicate(true))
	committed.generation = next_generation
	validation = _schema.validate(committed)
	if not bool(validation.get("ok", false)):
		note = "Statistics update was rejected after generation assignment: " + "; ".join(validation.get("errors", PackedStringArray()))
		return false
	var target_slot: String = SLOT_A if _current_slot == SLOT_B or _current_slot.is_empty() else SLOT_B
	var target_path: String = _root_path.path_join(target_slot)
	var temp_path: String = _root_path.path_join(NORMAL_TEMP)
	var write_result: Dictionary = _write_snapshot_file(temp_path, committed)
	if not bool(write_result.get("ok", false)):
		note = "Statistics snapshot could not be written: " + str(write_result.get("error", "unknown error"))
		return false
	if _interrupt("after_snapshot_temp_write"):
		return false
	var readback: Dictionary = _read_snapshot_file(temp_path)
	if not bool(readback.get("ok", false)) or int(readback.data.generation) != next_generation:
		note = "Statistics snapshot readback validation failed; the previous generation remains active."
		return false
	if _interrupt("after_snapshot_readback"):
		return false
	if FileAccess.file_exists(target_path):
		var remove_error: Error = DirAccess.remove_absolute(target_path)
		if remove_error != OK:
			note = "The older inactive statistics snapshot could not be replaced (%s)." % error_string(remove_error)
			return false
	if _interrupt("after_snapshot_target_remove"):
		return false
	var publish_error: Error = DirAccess.rename_absolute(temp_path, target_path)
	if publish_error != OK:
		note = "Statistics snapshot could not be published (%s)." % error_string(publish_error)
		return false
	data = committed
	_current_slot = target_slot
	if _interrupt("after_snapshot_publish"):
		return false
	note = ""
	return true


func delete_history(aircraft_id: String = "") -> bool:
	if not writable or not _owns_lock:
		note = "Statistics store is read-only; history was not changed."
		return false
	if data.is_empty() or _has_active_activity(data):
		note = "History can only be deleted when no statistics activity is active."
		return false
	if not aircraft_id.is_empty() and not _schema._safe_id(aircraft_id):
		note = "Aircraft history scope is invalid."
		return false
	var candidate: Dictionary = _schema.canonicalize(data.duplicate(true))
	var removed_any: bool = false
	var candidate_records: Array = []
	if aircraft_id.is_empty():
		candidate.records = []
		candidate.sessions = []
		candidate.current_session = ""
		candidate.epochs = {"account": 0, "aircraft": {}, "account_utc": _schema.utc_now(), "aircraft_utc": {}}
		candidate.tracking_started_utc = _schema.utc_now()
		candidate.clean_exit = true
		if candidate.has("active_context"):
			candidate.active_context = {}
		removed_any = not data.records.is_empty() or not data.sessions.is_empty()
	else:
		for record_value: Variant in data.records:
			var record: Dictionary = record_value
			if str(record.aircraft_id) == aircraft_id and str(record.kind) != "gap":
				removed_any = true
				candidate_records.append(_gap_from(record))
			else:
				candidate_records.append(record.duplicate(true))
		candidate.records = candidate_records
		if not removed_any:
			note = "No retained statistics records match this aircraft."
			return true
	if not removed_any and aircraft_id.is_empty():
		note = "Statistics history is already empty."
		return true
	var next_generation: int = int(data.generation) + 1
	if next_generation > _schema.MAX_SEQUENCE:
		note = "Statistics generation limit reached; history was not changed."
		return false
	candidate.generation = next_generation
	var validation: Dictionary = _schema.validate(candidate)
	if not bool(validation.get("ok", false)):
		note = "History deletion candidate is invalid: " + "; ".join(validation.get("errors", PackedStringArray()))
		return false
	var prepared_path: String = _root_path.path_join(PREPARED_DELETE)
	var prepared_result: Dictionary = _write_snapshot_file(prepared_path, candidate)
	if not bool(prepared_result.get("ok", false)):
		note = "Survivor history could not be prepared; previous statistics remain usable."
		return false
	if _interrupt("after_delete_prepare_write"):
		return false
	var prepared_readback: Dictionary = _read_snapshot_file(prepared_path)
	if not bool(prepared_readback.get("ok", false)) or not _snapshot_satisfies_deletion(prepared_readback.data, aircraft_id, int(data.sequence)):
		note = "Prepared survivor history failed validation; previous statistics remain usable."
		return false
	if _interrupt("after_delete_prepare_readback"):
		return false
	var receipt: Dictionary = {
		"revision": _next_fence_revision(),
		"required_generation": next_generation,
		"cutoff_sequence": int(data.sequence),
		"operation_id": _schema.new_id(),
		"targets": ["*"] if aircraft_id.is_empty() else [aircraft_id],
		"phase": "committed",
	}
	if not _write_fence(receipt):
		note = "Deletion fence could not be committed; previous statistics remain usable."
		return false
	_fence = receipt.duplicate(true)
	if _interrupt("after_deletion_fence_publish"):
		writable = false
		return false
	if not _publish_deletion_to_both_slots(candidate):
		writable = false
		note = "History deletion is committed; forward cleanup will resume when the store reopens."
		return false
	data = candidate
	_current_slot = SLOT_A
	if _interrupt("after_delete_second_snapshot_publish"):
		writable = false
		return false
	if _interrupt("before_delete_purge"):
		writable = false
		return false
	if not _purge_pre_fence_copies():
		writable = false
		note = "History was removed from statistics; local backup cleanup is pending."
		return false
	if _interrupt("after_delete_purge"):
		writable = false
		return false
	receipt.revision = int(receipt.revision) + 1
	receipt.phase = "purge_complete"
	if not _write_fence(receipt):
		note = "History was removed; deletion receipt cleanup is pending."
		return false
	_fence = receipt.duplicate(true)
	if _interrupt("after_deletion_fence_complete"):
		writable = false
		return false
	note = ""
	return true


func close() -> void:
	if _closed:
		return
	_closed = true
	if _owns_lock:
		_release_writer_lock()
	_owns_lock = false
	writable = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _owns_lock:
		# Avoid dispatching another method on a RefCounted during PREDELETE.
		_release_writer_lock()
		_owns_lock = false
		writable = false


func _read_snapshots() -> Dictionary:
	var entries: Array = []
	var invalid_slots: Array[String] = []
	var has_files: bool = false
	var notes: Array[String] = []
	for slot: String in [SLOT_A, SLOT_B]:
		var path: String = _root_path.path_join(slot)
		if not FileAccess.file_exists(path):
			continue
		has_files = true
		var entry: Dictionary = _read_snapshot_file(path)
		entry.slot = slot
		if bool(entry.get("future", false)):
			var future_data: Dictionary = entry.get("data", {})
			return {"entries": entries, "future": {"data": future_data, "slot": slot}, "has_files": true}
		if bool(entry.get("ok", false)):
			entries.append(entry)
		else:
			invalid_slots.append(slot)
			notes.append("%s: %s" % [slot, str(entry.get("error", "invalid snapshot"))])
	return {
		"entries": entries,
		"has_files": has_files,
		"recover_corrupt": not invalid_slots.is_empty() and not entries.is_empty(),
		"invalid_slots": invalid_slots,
		"note": "Recovered a valid snapshot; damaged copy retained (%s)." % "; ".join(notes) if not notes.is_empty() else "",
	}


func _read_snapshot_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "snapshot is missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "snapshot could not be opened"}
	var length: int = file.get_length()
	if length <= 0 or length > MAX_SNAPSHOT_BYTES:
		file.close()
		return {"ok": false, "error": "snapshot length is outside the read limit"}
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return {"ok": false, "error": "snapshot ended before its declared length"}
	var payload_result: Dictionary = _unframe(SNAPSHOT_MAGIC, bytes)
	if not bool(payload_result.get("ok", false)):
		return {"ok": false, "error": str(payload_result.get("error", "snapshot frame is invalid"))}
	var wrapper: Variant = bytes_to_var(payload_result.payload)
	if typeof(wrapper) != TYPE_DICTIONARY:
		return {"ok": false, "error": "snapshot envelope is invalid"}
	if wrapper.size() != 4 or not wrapper.has_all(["format", "codec_version", "checksum_sha256", "data"]):
		return {"ok": false, "error": "snapshot envelope is incomplete"}
	if typeof(wrapper.codec_version) == TYPE_INT and int(wrapper.codec_version) > CODEC_VERSION:
		return {"ok": false, "future": true, "data": wrapper.data if typeof(wrapper.data) == TYPE_DICTIONARY else {}}
	if wrapper.format != STORE_FORMAT or typeof(wrapper.codec_version) != TYPE_INT or int(wrapper.codec_version) != CODEC_VERSION:
		return {"ok": false, "error": "snapshot format or codec is unsupported"}
	if typeof(wrapper.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "snapshot data is not a dictionary"}
	var schema_version: Variant = wrapper.data.get("schema_version", null)
	if typeof(schema_version) == TYPE_INT and int(schema_version) > int(_schema.SCHEMA_VERSION):
		return {"ok": false, "future": true, "data": wrapper.data}
	var canonical: Dictionary = _schema.canonicalize(wrapper.data)
	var expected_hash: String = _sha256(var_to_bytes(canonical))
	if typeof(wrapper.checksum_sha256) != TYPE_STRING or str(wrapper.checksum_sha256) != expected_hash:
		return {"ok": false, "error": "snapshot checksum does not match its data"}
	var validation: Dictionary = _schema.validate(canonical)
	if not bool(validation.get("ok", false)):
		if bool(validation.get("future", false)):
			return {"ok": false, "future": true, "data": canonical}
		return {"ok": false, "error": "; ".join(validation.get("errors", PackedStringArray()))}
	return {"ok": true, "data": canonical, "generation": int(canonical.generation)}


func _read_fences() -> Dictionary:
	var fences: Array[Dictionary] = []
	var any_file: bool = false
	for name: String in [FENCE_A, FENCE_B]:
		var path: String = _root_path.path_join(name)
		if not FileAccess.file_exists(path):
			continue
		any_file = true
		var result: Dictionary = _read_fence_file(path)
		if bool(result.get("future", false)):
			return {"blocked": true, "note": "A newer deletion receipt is present; writable access is disabled."}
		if not bool(result.get("ok", false)):
			return {"blocked": true, "note": "A deletion receipt is malformed; history is protected until repaired."}
		fences.append(result.receipt)
	if fences.is_empty():
		return {"blocked": any_file, "fence": {}, "note": "Deletion receipt is invalid." if any_file else ""}
	fences.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.revision) < int(b.revision))
	return {"blocked": false, "fence": fences.back()}


func _read_fence_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "receipt could not be opened"}
	var length: int = file.get_length()
	if length <= 0 or length > MAX_FENCE_BYTES:
		file.close()
		return {"ok": false, "error": "receipt length is outside the read limit"}
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return {"ok": false, "error": "receipt ended before its declared length"}
	var payload_result: Dictionary = _unframe(FENCE_MAGIC, bytes)
	if not bool(payload_result.get("ok", false)):
		return {"ok": false, "error": str(payload_result.get("error", "receipt frame is invalid"))}
	var wrapper: Variant = bytes_to_var(payload_result.payload)
	if typeof(wrapper) != TYPE_DICTIONARY or wrapper.size() != 4 or not wrapper.has_all(["format", "version", "checksum_sha256", "receipt"]):
		return {"ok": false, "error": "receipt envelope is invalid"}
	if typeof(wrapper.version) == TYPE_INT and int(wrapper.version) > FENCE_VERSION:
		return {"ok": false, "future": true}
	if wrapper.format != FENCE_FORMAT or typeof(wrapper.version) != TYPE_INT or int(wrapper.version) != FENCE_VERSION or typeof(wrapper.receipt) != TYPE_DICTIONARY:
		return {"ok": false, "error": "receipt format is unsupported"}
	var receipt: Dictionary = _schema.canonicalize(wrapper.receipt)
	if str(wrapper.checksum_sha256) != _sha256(var_to_bytes(receipt)):
		return {"ok": false, "error": "receipt checksum does not match"}
	var validation: Dictionary = _validate_fence_receipt(receipt)
	if not bool(validation.ok):
		return {"ok": false, "error": "; ".join(validation.errors)}
	return {"ok": true, "receipt": receipt}


func _validate_fence_receipt(receipt: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var allowed: PackedStringArray = ["revision", "required_generation", "cutoff_sequence", "operation_id", "targets", "phase"]
	if receipt.size() != allowed.size() or not receipt.has_all(allowed):
		errors.append("Deletion receipt fields are invalid.")
		return {"ok": false, "errors": errors}
	if not _schema._bounded_integer(receipt.revision, 1, _schema.MAX_SEQUENCE):
		errors.append("Deletion receipt revision is invalid.")
	if not _schema._bounded_integer(receipt.required_generation, 1, _schema.MAX_SEQUENCE):
		errors.append("Deletion receipt generation is invalid.")
	if not _schema._bounded_integer(receipt.cutoff_sequence, 0, _schema.MAX_SEQUENCE):
		errors.append("Deletion receipt cutoff is invalid.")
	if not _schema._safe_id(receipt.operation_id):
		errors.append("Deletion receipt operation ID is invalid.")
	if typeof(receipt.targets) != TYPE_ARRAY or receipt.targets.is_empty() or receipt.targets.size() > 64:
		errors.append("Deletion receipt target list is invalid.")
	else:
		var target_ids: Dictionary = {}
		for target: Variant in receipt.targets:
			if typeof(target) != TYPE_STRING or (str(target) != "*" and not _schema._safe_id(target)) or target_ids.has(str(target)):
				errors.append("Deletion receipt target entry is invalid.")
			target_ids[str(target)] = true
		if receipt.targets.has("*") and receipt.targets.size() != 1:
			errors.append("Full-history deletion cannot mix target IDs.")
	if typeof(receipt.phase) != TYPE_STRING or str(receipt.phase) not in ["committed", "purge_complete"]:
		errors.append("Deletion receipt phase is invalid.")
	return {"ok": errors.is_empty(), "errors": errors}


## A purge_complete receipt stays on disk as a fence. Only an unfinished deletion, or a stale
## pre-fence slot that reappeared after it, needs forward recovery; otherwise open normally.
func _deletion_pending(entries: Array) -> bool:
	if _fence.is_empty():
		return false
	if str(_fence.get("phase", "")) != "purge_complete":
		return true
	for entry_value: Variant in entries:
		if typeof(entry_value) == TYPE_DICTIONARY and not _snapshot_satisfies_fence(entry_value.get("data", {}), _fence):
			return true
	return false


func _recover_deletion(entries: Array) -> bool:
	var safe: Dictionary = _newest_fence_safe_snapshot(entries, _fence)
	if safe.is_empty():
		var prepared: Dictionary = _read_snapshot_file(_root_path.path_join(PREPARED_DELETE))
		if not bool(prepared.get("ok", false)) or not _snapshot_satisfies_fence(prepared.data, _fence):
			data = {}
			writable = false
			note = "A deletion is committed, but no valid survivor snapshot is available. Deleted records remain hidden pending repair."
			return false
		safe = prepared
		safe.slot = ""
	data = safe.data
	_current_slot = str(safe.get("slot", ""))
	if not _owns_lock:
		writable = false
		note = "Deletion recovery is ready but requires the single writer."
		return true
	writable = true
	if not _ensure_both_slots_after_fence(data):
		writable = false
		note = "Deletion is committed; forward recovery could not finish and will retry on the next open."
		return false
	if not _purge_pre_fence_copies():
		writable = false
		note = "History is removed from statistics; local backup cleanup is pending."
		return false
	if str(_fence.get("phase", "")) != "purge_complete":
		var completed: Dictionary = _fence.duplicate(true)
		completed.revision = int(completed.revision) + 1
		completed.phase = "purge_complete"
		if not _write_fence(completed):
			writable = false
			note = "History is removed; deletion receipt cleanup is pending."
			return false
		_fence = completed
	_current_slot = SLOT_A
	if not str(safe.get("slot", "")).is_empty() and str(safe.slot) != SLOT_A:
		_current_slot = SLOT_B
	note = "Recovered and completed an interrupted history deletion."
	return true


func _newest_fence_safe_snapshot(entries: Array, receipt: Dictionary) -> Dictionary:
	var candidates: Array = []
	for entry_value: Variant in entries:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		if int(entry.get("generation", -1)) >= int(receipt.get("required_generation", 0)) and _snapshot_satisfies_fence(entry.data, receipt):
			candidates.append(entry)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.generation) < int(b.generation))
	return candidates.back()


func _snapshot_satisfies_fence(snapshot: Dictionary, receipt: Dictionary) -> bool:
	if int(snapshot.get("generation", -1)) < int(receipt.get("required_generation", 0)):
		return false
	var targets: Array = receipt.get("targets", [])
	var all_history: bool = targets.has("*")
	var cutoff: int = int(receipt.get("cutoff_sequence", -1))
	for record_value: Variant in snapshot.get("records", []):
		if typeof(record_value) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = record_value
		if int(record.get("seq", _schema.MAX_SEQUENCE)) > cutoff or str(record.get("kind", "")) == "gap":
			continue
		if all_history or targets.has(str(record.get("aircraft_id", ""))):
			return false
	return true


func _snapshot_satisfies_deletion(snapshot: Dictionary, aircraft_id: String, cutoff: int) -> bool:
	for record_value: Variant in snapshot.get("records", []):
		var record: Dictionary = record_value
		if int(record.seq) <= cutoff and (aircraft_id.is_empty() or str(record.aircraft_id) == aircraft_id) and str(record.kind) != "gap":
			return false
	return true


func _ensure_both_slots_after_fence(snapshot: Dictionary) -> bool:
	for slot: String in [SLOT_A, SLOT_B]:
		var path: String = _root_path.path_join(slot)
		var existing: Dictionary = _read_snapshot_file(path)
		if bool(existing.get("ok", false)) and _snapshot_satisfies_fence(existing.data, _fence):
			continue
		if FileAccess.file_exists(path):
			# A committed deletion must purge every pre-fence copy, including damaged slots.
			if DirAccess.remove_absolute(path) != OK:
				return false
		if not _write_snapshot_slot(slot, snapshot, "delete_recovery"):
			return false
	return true


func _publish_deletion_to_both_slots(snapshot: Dictionary) -> bool:
	var first_slot: String = SLOT_A if _current_slot != SLOT_A else SLOT_B
	var second_slot: String = SLOT_B if first_slot == SLOT_A else SLOT_A
	if not _write_snapshot_slot(first_slot, snapshot, "delete_first"):
		return false
	_current_slot = first_slot
	if _interrupt("after_delete_first_snapshot_publish"):
		return false
	if not _write_snapshot_slot(second_slot, snapshot, "delete_second"):
		return false
	_current_slot = second_slot
	return true


func _write_snapshot_slot(slot: String, snapshot: Dictionary, label: String) -> bool:
	var temp_path: String = _root_path.path_join(PREPARED_DELETE if label.begins_with("delete") or label == "delete_recovery" else NORMAL_TEMP)
	var target_path: String = _root_path.path_join(slot)
	# Use a separate recovery temp after the original prepared file has been consumed.
	if label == "delete_second" or label == "delete_recovery":
		temp_path = _root_path.path_join("snapshot_recovery.tmp")
	var write_result: Dictionary = _write_snapshot_file(temp_path, snapshot)
	if not bool(write_result.get("ok", false)):
		return false
	var readback: Dictionary = _read_snapshot_file(temp_path)
	if not bool(readback.get("ok", false)) or not _snapshot_satisfies_fence(readback.data, _fence):
		return false
	if FileAccess.file_exists(target_path) and DirAccess.remove_absolute(target_path) != OK:
		return false
	if DirAccess.rename_absolute(temp_path, target_path) != OK:
		return false
	return true


func _purge_pre_fence_copies() -> bool:
	for name: String in [
		NORMAL_TEMP, PREPARED_DELETE, FENCE_TEMP, "snapshot_recovery.tmp",
		"snapshot_quarantine_a.bin", "snapshot_quarantine_b.bin",
	]:
		var path: String = _root_path.path_join(name)
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			return false
	return true


func _write_snapshot_file(path: String, snapshot: Dictionary) -> Dictionary:
	var canonical: Dictionary = _schema.canonicalize(snapshot)
	var validation: Dictionary = _schema.validate(canonical)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": "; ".join(validation.get("errors", PackedStringArray()))}
	var data_payload: PackedByteArray = var_to_bytes(canonical)
	var wrapper: Dictionary = {
		"format": STORE_FORMAT,
		"codec_version": CODEC_VERSION,
		"checksum_sha256": _sha256(data_payload),
		"data": canonical,
	}
	var wrapper_payload: PackedByteArray = var_to_bytes(wrapper)
	var bytes: PackedByteArray = _frame(SNAPSHOT_MAGIC, wrapper_payload)
	if bytes.is_empty() or bytes.size() > MAX_SNAPSHOT_BYTES:
		return {"ok": false, "error": "snapshot exceeds the 64 MiB limit"}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "file open failed (%s)" % error_string(FileAccess.get_open_error())}
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "error": "file write failed (%s)" % error_string(write_error)}
	return {"ok": true, "bytes": bytes.size()}


func _write_fence(receipt: Dictionary) -> bool:
	var validation: Dictionary = _validate_fence_receipt(receipt)
	if not bool(validation.ok):
		return false
	var canonical: Dictionary = _schema.canonicalize(receipt)
	var wrapper: Dictionary = {
		"format": FENCE_FORMAT,
		"version": FENCE_VERSION,
		"checksum_sha256": _sha256(var_to_bytes(canonical)),
		"receipt": canonical,
	}
	var payload: PackedByteArray = var_to_bytes(wrapper)
	var bytes: PackedByteArray = _frame(FENCE_MAGIC, payload)
	if bytes.is_empty() or bytes.size() > MAX_FENCE_BYTES:
		return false
	var temp_path: String = _root_path.path_join(FENCE_TEMP)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return false
	var readback: Dictionary = _read_fence_file(temp_path)
	if not bool(readback.get("ok", false)) or int(readback.receipt.revision) != int(receipt.revision):
		return false
	var target_name: String = FENCE_A if int(receipt.revision) % 2 == 1 else FENCE_B
	var target_path: String = _root_path.path_join(target_name)
	if FileAccess.file_exists(target_path) and DirAccess.remove_absolute(target_path) != OK:
		return false
	if DirAccess.rename_absolute(temp_path, target_path) != OK:
		return false
	return true


func _next_fence_revision() -> int:
	var highest: int = int(_fence.get("revision", 0))
	var read_result: Dictionary = _read_fences()
	if not bool(read_result.get("blocked", false)):
		highest = maxi(highest, int(read_result.get("fence", {}).get("revision", 0)))
	return highest + 1


func _retains_existing_record_ids(candidate: Dictionary) -> bool:
	var candidate_ids: Dictionary = {}
	for record: Dictionary in candidate.get("records", []):
		candidate_ids[str(record.get("id", ""))] = true
	for record: Dictionary in data.get("records", []):
		if not candidate_ids.has(str(record.get("id", ""))):
			return false
	return true


func _has_active_activity(snapshot: Dictionary) -> bool:
	if typeof(snapshot.get("active_context", {})) == TYPE_DICTIONARY and not snapshot.get("active_context", {}).is_empty():
		return true
	for record: Dictionary in snapshot.get("records", []):
		if str(record.get("kind", "")) == "flight" and str(record.get("outcome", "")) == "active":
			return true
	return false


func _gap_from(record: Dictionary) -> Dictionary:
	return {
		"kind": "gap",
		"id": _schema.new_id(),
		"seq": int(record.seq),
		"session_id": str(record.session_id),
		"aircraft_id": str(record.aircraft_id),
		"aircraft_name": str(record.aircraft_name),
		"utc": str(record.utc),
		"account_epoch": int(record.account_epoch),
		"aircraft_epoch": int(record.aircraft_epoch),
	}


func _newest_snapshot(entries: Array) -> Dictionary:
	if entries.is_empty():
		return {}
	var sorted: Array = entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.generation) < int(b.generation))
	return sorted.back()


func _quarantine_bad_snapshots(slots: Array) -> bool:
	for slot_value: Variant in slots:
		var slot: String = str(slot_value)
		var source: String = _root_path.path_join(slot)
		var quarantine_name: String = "snapshot_quarantine_a.bin" if slot == SLOT_A else "snapshot_quarantine_b.bin"
		var target: String = _root_path.path_join(quarantine_name)
		if FileAccess.file_exists(target):
			return false
		var file := FileAccess.open(source, FileAccess.READ)
		if file == null:
			return false
		var length: int = file.get_length()
		if length <= 0 or length > MAX_SNAPSHOT_BYTES:
			file.close()
			return false
		var bytes: PackedByteArray = file.get_buffer(length)
		file.close()
		if bytes.size() != length:
			return false
		var copy := FileAccess.open(target, FileAccess.WRITE)
		if copy == null:
			return false
		copy.store_buffer(bytes)
		copy.flush()
		var write_error: Error = copy.get_error()
		copy.close()
		if write_error != OK:
			return false
	return true


func _acquire_writer_lock() -> Dictionary:
	_lock_token = _schema.new_id()
	if DirAccess.make_dir_absolute(_lock_path) == OK:
		if _write_lock_owner():
			return {"owned": true, "note": ""}
		DirAccess.remove_absolute(_lock_path)
		return {"owned": false, "note": "Statistics writer lock could not be initialized; opened read-only."}
	var owner_path: String = _lock_path.path_join("owner.json")
	if not FileAccess.file_exists(owner_path):
		return {"owned": false, "note": "Statistics writer lock has no valid owner record; opened read-only."}
	var owner_file := FileAccess.open(owner_path, FileAccess.READ)
	if owner_file == null or owner_file.get_length() > 2048:
		return {"owned": false, "note": "Statistics writer lock owner is ambiguous; opened read-only."}
	var owner_parser := JSON.new()
	var parse_error: Error = owner_parser.parse(owner_file.get_as_text())
	owner_file.close()
	if parse_error != OK or typeof(owner_parser.data) != TYPE_DICTIONARY:
		return {"owned": false, "note": "Statistics writer lock owner is malformed; opened read-only."}
	var owner: Dictionary = owner_parser.data
	if owner.size() != 3 or not owner.has_all(["pid", "token", "format"]) or owner.format != "openrc-flight-statistics-lock" or typeof(owner.pid) != TYPE_INT or not _schema._safe_id(owner.token):
		return {"owned": false, "note": "Statistics writer lock owner is malformed; opened read-only."}
	if OS.is_process_running(int(owner.pid)):
		return {"owned": false, "note": "Another process owns the statistics store; opened read-only."}
	# Only a well-formed lock whose recorded process has exited is eligible for reclaim.
	for entry: String in _directory_entries(_lock_path):
		if entry != "owner.json":
			return {"owned": false, "note": "Stale statistics lock contains unknown files; opened read-only."}
	if DirAccess.remove_absolute(owner_path) != OK or DirAccess.remove_absolute(_lock_path) != OK:
		return {"owned": false, "note": "Stale statistics lock could not be reclaimed; opened read-only."}
	if DirAccess.make_dir_absolute(_lock_path) != OK or not _write_lock_owner():
		return {"owned": false, "note": "Statistics writer lock was claimed by another process; opened read-only."}
	return {"owned": true, "note": "Recovered a stale statistics lock after verifying its process exited."}


func _write_lock_owner() -> bool:
	var owner: Dictionary = {
		"format": "openrc-flight-statistics-lock",
		"pid": OS.get_process_id(),
		"token": _lock_token,
	}
	var path: String = _lock_path.path_join("owner.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(owner))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return write_error == OK


func _release_writer_lock() -> void:
	var owner_path: String = _lock_path.path_join("owner.json")
	if not FileAccess.file_exists(owner_path):
		return
	var owner_file := FileAccess.open(owner_path, FileAccess.READ)
	if owner_file == null or owner_file.get_length() > 2048:
		return
	var parser := JSON.new()
	var parse_error: Error = parser.parse(owner_file.get_as_text())
	owner_file.close()
	if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	if str(parser.data.get("token", "")) != _lock_token or int(parser.data.get("pid", -1)) != OS.get_process_id():
		return
	DirAccess.remove_absolute(owner_path)
	DirAccess.remove_absolute(_lock_path)


func _directory_entries(path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			result.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	return result


func _valid_root_uri(root: String) -> bool:
	if not root.begins_with("user://") or root.length() > 256 or root.contains("..") or root.contains("\\"):
		return false
	return true


func _interrupt(stage: String) -> bool:
	if not interruption_hook.is_valid():
		return false
	var should_interrupt: bool = bool(interruption_hook.call(stage))
	if should_interrupt:
		writable = false
		note = "Injected interruption at %s; reopen the store to resolve the durable state." % stage
	return should_interrupt


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _frame(magic: String, payload: PackedByteArray) -> PackedByteArray:
	var result: PackedByteArray = magic.to_ascii_buffer()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	result.append_array(context.finish())
	result.append_array(payload)
	return result


func _unframe(magic: String, bytes: PackedByteArray) -> Dictionary:
	if bytes.size() <= FRAME_HEADER_BYTES or bytes.slice(0, magic.length()).get_string_from_ascii() != magic:
		return {"ok": false, "error": "binary frame header is invalid"}
	var expected_digest: PackedByteArray = bytes.slice(magic.length(), FRAME_HEADER_BYTES)
	var payload: PackedByteArray = bytes.slice(FRAME_HEADER_BYTES, bytes.size())
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	if context.finish() != expected_digest:
		return {"ok": false, "error": "binary frame checksum does not match"}
	return {"ok": true, "payload": payload}
