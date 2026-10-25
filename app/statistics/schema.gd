extends RefCounted
class_name FlightStatisticsSchema
## Canonical versioned flight-statistics data and validation.

const SCHEMA_VERSION: int = 1
const MAX_SESSIONS: int = 10000
const MAX_RECORDS: int = 100000
const MAX_SEQUENCE: int = 9007199254740991
const MAX_FLIGHT_SECONDS: float = 315576000.0
const MAX_SPEED_MPS: float = 1000.0
const MAX_ID_LENGTH: int = 128
const MAX_NAME_LENGTH: int = 192
const MAX_TREE_DEPTH: int = 16
const MAX_TREE_NODES: int = 20000
const MAX_METADATA_BYTES: int = 64 * 1024
const MAX_CHECKPOINT_BYTES: int = 256 * 1024

const ROOT_REQUIRED: PackedStringArray = [
	"schema_version", "pilot_id", "generation", "sequence", "tracking_started_utc",
	"current_session", "sessions", "records", "epochs", "clean_exit",
]
const ROOT_ALLOWED: PackedStringArray = [
	"schema_version", "pilot_id", "generation", "sequence", "tracking_started_utc",
	"current_session", "sessions", "records", "epochs", "clean_exit", "active_context",
]
const SESSION_REQUIRED: PackedStringArray = ["id", "opened_utc", "closed_utc", "status"]
const SESSION_ALLOWED: PackedStringArray = ["id", "opened_utc", "closed_utc", "status", "metadata"]
const RECORD_COMMON: PackedStringArray = [
	"kind", "id", "seq", "session_id", "aircraft_id", "aircraft_name", "utc",
	"account_epoch", "aircraft_epoch",
]
const FLIGHT_FIELDS: PackedStringArray = [
	"end_seq", "airborne_seconds", "outcome", "start_kind", "full_stops", "touch_and_go",
	"failed_landings", "unknown_landings", "max_tas_mps", "max_groundspeed_mps",
	"complete_observation", "config_hash", "rules_version",
]
const FLIGHT_OPTIONAL: PackedStringArray = ["metadata", "detector_checkpoint", "ended_utc"]
const EVENT_OPTIONAL: PackedStringArray = ["metadata"]
const OUTCOMES: PackedStringArray = [
	"active", "completed", "crashed", "restarted", "abandoned", "damaged_stop", "interrupted",
]
const START_KINDS: PackedStringArray = ["takeoff", "air_start"]
const RECORD_KINDS: PackedStringArray = ["flight", "crash", "restart", "gap"]
const SESSION_STATUSES: PackedStringArray = ["open", "closed", "interrupted"]


static func create(pilot_id: String, tracking_started_utc: String = "") -> Dictionary:
	var resolved_pilot: String = pilot_id.strip_edges()
	if resolved_pilot.is_empty():
		resolved_pilot = new_id()
	var started: String = tracking_started_utc if not tracking_started_utc.is_empty() else utc_now()
	return {
		"schema_version": SCHEMA_VERSION,
		"pilot_id": resolved_pilot,
		"generation": 0,
		"sequence": 0,
		"tracking_started_utc": started,
		"current_session": "",
		"sessions": [],
		"records": [],
		"epochs": {"account": 0, "aircraft": {}, "account_utc": started, "aircraft_utc": {}},
		"clean_exit": false,
		"active_context": {},
	}


static func new_id() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	if bytes.size() == 16:
		return bytes.hex_encode()
	# This fallback is only for platforms that cannot provide random bytes.
	return "%08x%08x%08x%08x" % [
		OS.get_process_id(), Time.get_ticks_usec() & 0xffffffff,
		Time.get_ticks_msec() & 0xffffffff, randi() & 0xffffffff,
	]


static func utc_now() -> String:
	return Time.get_datetime_string_from_system(true)


static func validate(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("Statistics data must be a dictionary.")
		return _result(false, errors)
	var data: Dictionary = value
	var version_value: Variant = data.get("schema_version", null)
	if _is_integer(version_value) and int(version_value) > SCHEMA_VERSION:
		return {"ok": false, "future": true, "errors": PackedStringArray(["Statistics schema is newer than this build."])}
	if data.size() < ROOT_REQUIRED.size() or not data.has_all(ROOT_REQUIRED):
		errors.append("Statistics data has missing required fields.")
		return _result(false, errors)
	if not _has_only_keys(data, ROOT_ALLOWED):
		errors.append("Statistics data has unknown fields.")
	if not _is_integer(data["schema_version"]) or int(data["schema_version"]) != SCHEMA_VERSION:
		errors.append("Statistics schema version is unsupported.")
	if not _safe_id(data["pilot_id"]):
		errors.append("Statistics pilot ID is invalid.")
	if not _bounded_integer(data["generation"], 0, MAX_SEQUENCE):
		errors.append("Statistics generation is invalid.")
	if not _bounded_integer(data["sequence"], 0, MAX_SEQUENCE):
		errors.append("Statistics sequence is invalid.")
	if not _valid_utc(data["tracking_started_utc"]):
		errors.append("Statistics tracking timestamp is invalid.")
	if typeof(data["current_session"]) != TYPE_STRING or str(data["current_session"]).length() > MAX_ID_LENGTH:
		errors.append("Current session ID is invalid.")
	if typeof(data["clean_exit"]) != TYPE_BOOL:
		errors.append("Statistics clean-exit flag must be boolean.")
	if typeof(data["sessions"]) != TYPE_ARRAY or data["sessions"].size() > MAX_SESSIONS:
		errors.append("Statistics session list is invalid or exceeds its limit.")
	if typeof(data["records"]) != TYPE_ARRAY or data["records"].size() > MAX_RECORDS:
		errors.append("Statistics record list is invalid or exceeds its limit.")
	var epoch_result: Dictionary = _validate_epochs(data["epochs"])
	if not epoch_result.ok:
		errors.append_array(epoch_result.errors)
	var session_ids: Dictionary = {}
	var open_session_count: int = 0
	if typeof(data["sessions"]) == TYPE_ARRAY:
		for i: int in range(data["sessions"].size()):
			var session: Variant = data["sessions"][i]
			var session_result: Dictionary = _validate_session(session, i)
			if not session_result.ok:
				errors.append_array(session_result.errors)
				continue
			var session_id: String = str(session.id)
			if session_ids.has(session_id):
				errors.append("Session IDs must be unique.")
			session_ids[session_id] = true
			if session.status == "open":
				open_session_count += 1
		if open_session_count > 1:
			errors.append("At most one statistics session may be open.")
	var current_session: String = str(data["current_session"])
	if not current_session.is_empty() and not session_ids.has(current_session):
		errors.append("Current session does not exist in the session list.")
	var record_result: Dictionary = _validate_records(data, session_ids)
	if not record_result.ok:
		errors.append_array(record_result.errors)
	if data.has("active_context"):
		var context_result: Dictionary = _validate_dictionary_tree(data.active_context, MAX_CHECKPOINT_BYTES)
		if not context_result.ok:
			errors.append("Active context is invalid or exceeds its limit.")
	return _result(errors.is_empty(), errors)


static func canonicalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort()
			var result: Dictionary = {}
			for key: Variant in keys:
				result[key] = canonicalize(value[key])
			return result
		TYPE_ARRAY:
			var result: Array = []
			for item: Variant in value:
				result.append(canonicalize(item))
			return result
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return value.duplicate()
		_:
			return value


static func _validate_epochs(value: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY or value.size() < 2 or not value.has_all(PackedStringArray(["account", "aircraft"])):
		errors.append("Statistics epochs must contain account and aircraft values.")
		return _result(false, errors)
	if not _has_only_keys(value, ["account", "aircraft", "account_utc", "aircraft_utc"]):
		errors.append("Statistics epochs have unknown fields.")
	if not _bounded_integer(value.account, 0, MAX_SEQUENCE):
		errors.append("Account counter epoch is invalid.")
	if value.has("account_utc") and not _valid_utc(value.account_utc):
		errors.append("Account counter epoch timestamp is invalid.")
	if typeof(value.aircraft) != TYPE_DICTIONARY:
		errors.append("Aircraft counter epochs must be a dictionary.")
	else:
		for key: Variant in value.aircraft.keys():
			if not _safe_id(key) or not _bounded_integer(value.aircraft[key], 0, MAX_SEQUENCE):
				errors.append("Aircraft counter epoch entry is invalid.")
	if value.has("aircraft_utc"):
		if typeof(value.aircraft_utc) != TYPE_DICTIONARY:
			errors.append("Aircraft counter epoch timestamps must be a dictionary.")
		else:
			for key: Variant in value.aircraft_utc.keys():
				if not _safe_id(key) or not _valid_utc(value.aircraft_utc[key]):
					errors.append("Aircraft counter epoch timestamp entry is invalid.")
	return _result(errors.is_empty(), errors)


static func _validate_session(value: Variant, index: int) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY or not value.has_all(SESSION_REQUIRED):
		errors.append("Session %d must be a complete dictionary." % index)
		return _result(false, errors)
	if not _has_only_keys(value, SESSION_ALLOWED):
		errors.append("Session %d has unknown fields." % index)
	if not _safe_id(value.id):
		errors.append("Session %d ID is invalid." % index)
	if not _valid_utc(value.opened_utc):
		errors.append("Session %d opening timestamp is invalid." % index)
	if typeof(value.closed_utc) != TYPE_STRING or (not str(value.closed_utc).is_empty() and not _valid_utc(value.closed_utc)):
		errors.append("Session %d closing timestamp is invalid." % index)
	if typeof(value.status) != TYPE_STRING or not SESSION_STATUSES.has(str(value.status)):
		errors.append("Session %d status is invalid." % index)
	elif value.status == "open" and not str(value.closed_utc).is_empty():
		errors.append("Open session %d cannot have a closing timestamp." % index)
	elif value.status != "open" and str(value.closed_utc).is_empty():
		errors.append("Closed session %d requires a closing timestamp." % index)
	if value.has("metadata"):
		var metadata_result: Dictionary = _validate_dictionary_tree(value.metadata, MAX_METADATA_BYTES)
		if not metadata_result.ok:
			errors.append("Session %d metadata is invalid or exceeds its limit." % index)
	return _result(errors.is_empty(), errors)


static func _validate_records(data: Dictionary, session_ids: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(data.records) != TYPE_ARRAY:
		return _result(false, PackedStringArray(["Statistics records must be an array."]))
	var ids: Dictionary = {}
	var last_sequence: int = -1
	var active_flights: int = 0
	var aircraft_epochs: Dictionary = data.epochs.aircraft
	for i: int in range(data.records.size()):
		var record: Variant = data.records[i]
		var record_result: Dictionary = _validate_record(record, i, session_ids, data, aircraft_epochs)
		if not record_result.ok:
			errors.append_array(record_result.errors)
			continue
		if ids.has(str(record.id)):
			errors.append("Record IDs must be unique.")
		ids[str(record.id)] = true
		if int(record.seq) <= last_sequence:
			errors.append("Record sequence values must be strictly increasing.")
		last_sequence = int(record.seq)
		if record.kind == "flight" and record.outcome == "active":
			active_flights += 1
	if active_flights > 1:
		errors.append("At most one flight record may be active in a store.")
	return _result(errors.is_empty(), errors)


static func _validate_record(value: Variant, index: int, session_ids: Dictionary, data: Dictionary, aircraft_epochs: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(value) != TYPE_DICTIONARY or not value.has_all(RECORD_COMMON):
		errors.append("Record %d is missing common fields." % index)
		return _result(false, errors)
	var kind: String = str(value.get("kind", ""))
	if not RECORD_KINDS.has(kind):
		errors.append("Record %d kind is invalid." % index)
		return _result(false, errors)
	var allowed: PackedStringArray = RECORD_COMMON.duplicate()
	allowed.append_array(FLIGHT_FIELDS if kind == "flight" else EVENT_OPTIONAL)
	if kind == "flight":
		allowed.append_array(FLIGHT_OPTIONAL)
	if not _has_only_keys(value, allowed):
		errors.append("Record %d has unknown fields." % index)
	if not _safe_id(value.id):
		errors.append("Record %d ID is invalid." % index)
	if not _bounded_integer(value.seq, 1, int(data.sequence)):
		errors.append("Record %d sequence is invalid." % index)
	var session_id: String = str(value.session_id)
	if not session_ids.has(session_id) and not (kind == "gap" and session_id.is_empty()):
		errors.append("Record %d references a missing session." % index)
	if typeof(value.aircraft_id) != TYPE_STRING or str(value.aircraft_id).length() > MAX_ID_LENGTH:
		errors.append("Record %d aircraft ID is invalid." % index)
	elif kind != "gap" and not _safe_id(value.aircraft_id):
		errors.append("Record %d aircraft ID is invalid." % index)
	if typeof(value.aircraft_name) != TYPE_STRING or str(value.aircraft_name).length() > MAX_NAME_LENGTH:
		errors.append("Record %d aircraft name is invalid." % index)
	if not _valid_utc(value.utc):
		errors.append("Record %d timestamp is invalid." % index)
	if not _bounded_integer(value.account_epoch, 0, int(data.epochs.account)):
		errors.append("Record %d account epoch is invalid." % index)
	var current_aircraft_epoch: int = int(aircraft_epochs.get(str(value.aircraft_id), 0))
	if not _bounded_integer(value.aircraft_epoch, 0, current_aircraft_epoch):
		errors.append("Record %d aircraft epoch is invalid." % index)
	if value.has("metadata"):
		var metadata_result: Dictionary = _validate_dictionary_tree(value.metadata, MAX_METADATA_BYTES)
		if not metadata_result.ok:
			errors.append("Record %d metadata is invalid or exceeds its limit." % index)
	if kind == "flight":
		errors.append_array(_validate_flight_fields(value, index))
		if str(value.get("outcome", "")) != "active" and int(value.get("end_seq", -1)) > int(data.sequence):
			errors.append("Flight record %d terminal sequence exceeds the store sequence." % index)
	elif value.has("detector_checkpoint"):
		errors.append("Only a flight record may contain a detector checkpoint.")
	return _result(errors.is_empty(), errors)


static func _validate_flight_fields(record: Dictionary, index: int) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in FLIGHT_FIELDS:
		if not record.has(key):
			errors.append("Flight record %d is missing %s." % [index, key])
	if not record.has_all(FLIGHT_FIELDS):
		return errors
	if not _bounded_integer(record.end_seq, -1, MAX_SEQUENCE):
		errors.append("Flight record %d terminal sequence is invalid." % index)
	if not _is_finite_number(record.airborne_seconds) or float(record.airborne_seconds) < 0.0 or float(record.airborne_seconds) > MAX_FLIGHT_SECONDS:
		errors.append("Flight record %d airborne time is invalid." % index)
	if typeof(record.outcome) != TYPE_STRING or not OUTCOMES.has(str(record.outcome)):
		errors.append("Flight record %d outcome is invalid." % index)
	if typeof(record.start_kind) != TYPE_STRING or not START_KINDS.has(str(record.start_kind)):
		errors.append("Flight record %d start kind is invalid." % index)
	for key: String in ["full_stops", "touch_and_go", "failed_landings", "unknown_landings"]:
		if not _bounded_integer(record[key], 0, MAX_SEQUENCE):
			errors.append("Flight record %d %s count is invalid." % [index, key])
	for key: String in ["max_tas_mps", "max_groundspeed_mps"]:
		var speed: Variant = record[key]
		if not _is_finite_number(speed) or float(speed) < -1.0 or float(speed) > MAX_SPEED_MPS:
			errors.append("Flight record %d %s is invalid." % [index, key])
	if typeof(record.complete_observation) != TYPE_BOOL:
		errors.append("Flight record %d observation flag must be boolean." % index)
	if typeof(record.config_hash) != TYPE_STRING or (not str(record.config_hash).is_empty() and not _lower_hex(str(record.config_hash), 64)):
		errors.append("Flight record %d configuration hash is invalid." % index)
	if typeof(record.rules_version) != TYPE_STRING and not _bounded_integer(record.rules_version, 1, 1000000):
		errors.append("Flight record %d rules version is invalid." % index)
	elif typeof(record.rules_version) == TYPE_STRING and (str(record.rules_version).strip_edges().is_empty() or str(record.rules_version).length() > 64):
		errors.append("Flight record %d rules version is invalid." % index)
	var seq: int = int(record.seq)
	var outcome: String = str(record.outcome)
	if outcome == "active":
		if int(record.end_seq) != -1:
			errors.append("Active flight record %d must not have a terminal sequence." % index)
		if bool(record.complete_observation):
			errors.append("Active flight record %d cannot be fully observed." % index)
	else:
		if int(record.end_seq) <= seq or int(record.end_seq) > MAX_SEQUENCE:
			errors.append("Closed flight record %d requires a later terminal sequence." % index)
		if record.has("ended_utc") and not _valid_utc(record.ended_utc):
			errors.append("Closed flight record %d end timestamp is invalid." % index)
		if outcome == "interrupted" and bool(record.complete_observation):
			errors.append("Interrupted flight record %d cannot be fully observed." % index)
	if record.has("detector_checkpoint"):
		var checkpoint_result: Dictionary = _validate_dictionary_tree(record.detector_checkpoint, MAX_CHECKPOINT_BYTES)
		if not checkpoint_result.ok:
			errors.append("Flight record %d checkpoint is invalid or exceeds its limit." % index)
	return errors


static func _validate_dictionary_tree(value: Variant, max_bytes: int) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false}
	return _validate_tree(value, max_bytes)


static func _validate_tree(value: Variant, max_bytes: int) -> Dictionary:
	var state: Dictionary = {"nodes": 0, "ok": true}
	if not _walk_tree(value, 0, state):
		return {"ok": false}
	var serialized: PackedByteArray = var_to_bytes(value)
	return {"ok": serialized.size() <= max_bytes}


static func _walk_tree(value: Variant, depth: int, state: Dictionary) -> bool:
	state.nodes = int(state.nodes) + 1
	if depth > MAX_TREE_DEPTH or int(state.nodes) > MAX_TREE_NODES:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return typeof(value) != TYPE_STRING or str(value).length() <= 4096
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_DICTIONARY:
			for key: Variant in value.keys():
				if typeof(key) != TYPE_STRING or str(key).length() > 128:
					return false
				if not _walk_tree(value[key], depth + 1, state):
					return false
			return true
		TYPE_ARRAY:
			if value.size() > MAX_TREE_NODES:
				return false
			for item: Variant in value:
				if not _walk_tree(item, depth + 1, state):
					return false
			return true
		TYPE_PACKED_BYTE_ARRAY:
			return value.size() <= MAX_TREE_NODES * 8
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			return value.size() <= MAX_TREE_NODES
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			if value.size() > MAX_TREE_NODES:
				return false
			for number: float in value:
				if not is_finite(number):
					return false
			return true
		TYPE_PACKED_STRING_ARRAY:
			if value.size() > MAX_TREE_NODES:
				return false
			for string_value: String in value:
				if string_value.length() > 4096:
					return false
			return true
		_:
			return false


static func _has_only_keys(value: Dictionary, allowed: PackedStringArray) -> bool:
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not allowed.has(str(key)):
			return false
	return true


static func _safe_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text_value: String = str(value)
	if text_value.is_empty() or text_value.length() > MAX_ID_LENGTH or text_value.strip_edges() != text_value:
		return false
	for index: int in range(text_value.length()):
		var code: int = text_value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or
				(code >= 97 and code <= 122) or code in [45, 46, 58, 95]):
			return false
	return true


static func _valid_utc(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text_value: String = str(value)
	if text_value.length() < 19 or text_value.length() > 40:
		return false
	if text_value[4] != "-" or text_value[7] != "-" or text_value[10] not in ["T", " "] or text_value[13] != ":" or text_value[16] != ":":
		return false
	for index: int in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]:
		var code: int = text_value.unicode_at(index)
		if code < 48 or code > 57:
			return false
	var month: int = int(text_value.substr(5, 2))
	var day: int = int(text_value.substr(8, 2))
	var hour: int = int(text_value.substr(11, 2))
	var minute: int = int(text_value.substr(14, 2))
	var second: int = int(text_value.substr(17, 2))
	if month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 or second > 60:
		return false
	return true


static func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


static func _bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


static func _lower_hex(value: String, length: int) -> bool:
	if value.length() != length:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _result(ok: bool, errors: PackedStringArray) -> Dictionary:
	return {"ok": ok, "future": false, "errors": errors}
