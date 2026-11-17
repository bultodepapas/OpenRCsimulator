extends RefCounted
## One active saved Creator choice. It never resolves a library, substitutes a model or grants flight.
const R := preload("res://workshop/creator/result.gd")
const SourceRef := preload("res://workshop/creator/source_ref.gd")
const FORMAT := "openrc-home-creator-selection v1"
const CHANGE_FORMAT := "openrc-home-selection-change v1"
const SCHEMA := 8
const SECTION := "creator_selection"
const KEY := "selection"
const KEYS := ["format", "source_ref", "start_choice"]
const CHANGE_KEYS := ["format", "before", "after"]
const START_CHOICES := ["airborne", "hand_launch"]


static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _invalid()
	if value.is_empty():
		return R.ok({})
	if not _closed(value, KEYS) or typeof(value.get("format")) != TYPE_STRING or value.format != FORMAT \
			or typeof(value.get("start_choice")) != TYPE_STRING or value.start_choice not in START_CHOICES:
		return _invalid()
	var checked: Dictionary = SourceRef.validate(value.get("source_ref"))
	if not checked.ok:
		return checked
	return R.ok({"format": FORMAT, "source_ref": checked.value, "start_choice": value.start_choice})


static func make(reference: Variant, start_choice: Variant) -> Dictionary:
	return validate({"format": FORMAT, "source_ref": reference, "start_choice": start_choice})


## Schema 8 is deliberately future to old writers. Its active namespace is mandatory and closed.
## The old aircraft field remains compatibility memory, never the active Creator selection.
static func read_config(config: ConfigFile) -> Dictionary:
	var schema: Variant = config.get_value("meta", "schema", 0)
	if typeof(schema) == TYPE_INT and schema == SCHEMA:
		if not config.has_section(SECTION) or config.get_section_keys(SECTION) != PackedStringArray([KEY]):
			return _invalid()
		var checked: Dictionary = validate(config.get_value(SECTION, KEY))
		var activity: Variant = config.get_value("flight", "home_vehicle", "")
		if not checked.ok or checked.value.is_empty() or typeof(activity) != TYPE_STRING or not activity.is_empty():
			return _invalid()
		return checked
	if config.has_section(SECTION):
		return _invalid()
	return R.ok({})


## An explicit UI selection operation creates this intent; Fly and incidental settings use null/keep.
## A UI generation check must additionally discard stale asynchronous resolutions while stock is active.
static func change(before: Variant, after: Variant) -> Dictionary:
	var a: Dictionary = validate(before)
	var b: Dictionary = validate(after)
	if not a.ok or not b.ok:
		return _invalid()
	return R.ok({"format": CHANGE_FORMAT, "before": a.value, "after": b.value})


## Called under the existing preferences lock, AFTER recovery and validation of current/candidate.
static func check_transition(current: ConfigFile, candidate: ConfigFile, intent: Variant = null) -> Error:
	var a: Dictionary = read_config(current)
	var b: Dictionary = read_config(candidate)
	if not a.ok or not b.ok:
		return ERR_FILE_CORRUPT
	if intent == null:
		return OK if a.value == b.value else ERR_BUSY
	if not intent is Dictionary or not _closed(intent, CHANGE_KEYS) \
			or typeof(intent.get("format")) != TYPE_STRING or intent.format != CHANGE_FORMAT:
		return ERR_INVALID_DATA
	var before: Dictionary = validate(intent.get("before"))
	var after: Dictionary = validate(intent.get("after"))
	if not before.ok or not after.ok or b.value != after.value:
		return ERR_INVALID_DATA
	return OK if a.value == before.value else ERR_BUSY


static func _closed(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			return false
	return true


static func _invalid() -> Dictionary:
	return R.fail(R.RECORD_INVALID, "The saved aircraft selection is unavailable. Choose an aircraft again.", "creator_selection")
