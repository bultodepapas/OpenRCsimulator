# AE-27-00b: internal attachment contract. No current Workshop/profile/flight caller.
# The catalogue digest pins registration metadata only; integration must also prove
# factories/assets in the presentation source closure and enforce launch admission.
extends RefCounted

const Parameters := preload("res://workshop/parameters.gd")
const FORMAT := "openrc-aircraft-attachment-selection"
const VERSION := 1
const SLOT_IDS := ["wheels", "landing_gear", "propeller", "spinner"]
const ORIGINAL := "original"
const PILOT_ID := "jensen-das-ugly-stik-60"
const TWIN_GROOVE_ID := "stik_twin_groove_v1"
const PREVIEW_REASON := "Internal tread study; native fit and Workshop lifecycle are not qualified."
const DOCUMENT_KEYS := ["format", "version", "catalog_sha256", "selections"]


## A defensive copy of trusted metadata, never a catalogue accepted from a save file.
static func catalog() -> Dictionary:
	return {
		"format": "openrc-aircraft-attachment-catalog", "version": 1,
		"slots": SLOT_IDS.duplicate(), "original_id": ORIGINAL,
		"scale_domain": [Parameters.MIN_SCALE, Parameters.MAX_SCALE],
		"original_availability": "cosmetic_flight",
		"options": [{
			"slot": "wheels", "id": TWIN_GROOVE_ID, "label": "Twin-groove study",
			"aircraft_ids": [PILOT_ID], "scale_domain": [1.0, 1.0],
			"availability": "preview_only", "reason": PREVIEW_REASON,
			"factory_id": "stik_native_twin_groove_v1",
			"qualification": "internal_unqualified",
		}],
	}


static func catalog_sha256() -> String:
	return JSON.stringify(_canonical(catalog()), "", true, true).sha256_text()


## Explicit constructor, not a legacy migration or a fallback for malformed input.
static func original() -> Dictionary:
	var selections: Dictionary = {}
	for slot: String in SLOT_IDS:
		selections[slot] = ORIGINAL
	return {"format": FORMAT, "version": VERSION,
		"catalog_sha256": catalog_sha256(), "selections": selections}


## Validate an already-parsed, bounded data shape. Future JSON I/O must separately
## reject duplicate keys before parsing; a Dictionary cannot preserve that evidence.
static func validate(value: Variant) -> Dictionary:
	if not _exact_keys(value, DOCUMENT_KEYS):
		return _failure("ATTACHMENT_SHAPE", "$", "An explicit attachment selection document is required.")
	if typeof(value.format) != TYPE_STRING or value.format != FORMAT:
		return _failure("ATTACHMENT_FORMAT", "$.format", "Unknown attachment selection format.")
	if not _number(value.version) or float(value.version) != VERSION:
		return _failure("ATTACHMENT_VERSION", "$.version", "Unsupported attachment selection version.")
	if typeof(value.catalog_sha256) != TYPE_STRING or value.catalog_sha256 != catalog_sha256():
		return _failure("ATTACHMENT_CATALOG_STALE", "$.catalog_sha256", "The attachment catalogue has changed or is missing.")
	if not _exact_keys(value.selections, SLOT_IDS):
		return _failure("ATTACHMENT_SLOTS", "$.selections", "All four attachment slots must be explicit; unknown slots are refused.")
	var accepted := original()
	for slot: String in SLOT_IDS:
		var option: Variant = value.selections[slot]
		if typeof(option) != TYPE_STRING or not _identifier(option, "^[a-z][a-z0-9_]{0,79}$"):
			return _failure("ATTACHMENT_OPTION_ID", "$.selections." + slot, "An option must be a bounded stable ID.")
		if option != ORIGINAL and _option(slot, option).is_empty():
			return _failure("ATTACHMENT_OPTION_UNKNOWN", "$.selections." + slot, "Unknown option for this attachment slot.")
		accepted.selections[slot] = option
	return {"ok": true, "errors": PackedStringArray(), "diagnostics": [], "selection": accepted}


## Compatibility only, never flight authorization. Callers must supply the verified
## base aircraft ID/scale, then perform source-proof, installation and start checks.
## Unregistered aircraft retain explicit Original only; no family/alias inference.
static func resolve(value: Variant, aircraft_id: Variant, scale: Variant = null) -> Dictionary:
	var checked := validate(value)
	if not checked.ok:
		return checked
	if typeof(aircraft_id) != TYPE_STRING or not _identifier(aircraft_id, "^[a-z0-9][a-z0-9_.-]{0,127}$"):
		return _failure("ATTACHMENT_AIRCRAFT", "$.aircraft_id", "A verified base aircraft ID is required.")
	if not _number(scale) or float(scale) < Parameters.MIN_SCALE or float(scale) > Parameters.MAX_SCALE:
		return _failure("ATTACHMENT_SCALE", "$.scale", "The virtual scale must be a finite value in the Workshop domain.")
	var availability := "cosmetic_flight"
	var reasons := PackedStringArray()
	var options: Array[Dictionary] = []
	for slot: String in SLOT_IDS:
		var id: String = checked.selection.selections[slot]
		if id == ORIGINAL:
			continue
		var option := _option(slot, id)
		if not option.aircraft_ids.has(aircraft_id):
			return _failure("ATTACHMENT_INCOMPATIBLE", "$.selections." + slot, "This option is not registered for this aircraft configuration.")
		if float(scale) < float(option.scale_domain[0]) or float(scale) > float(option.scale_domain[1]):
			return _failure("ATTACHMENT_SCALE_UNSUPPORTED", "$.selections." + slot, "This option is not registered at the selected virtual scale.")
		if option.availability == "preview_only":
			availability = "preview_only"
			reasons.append(option.reason)
		options.append(option)
	return {"ok": true, "errors": PackedStringArray(), "diagnostics": [],
		"selection": checked.selection, "availability": availability, "reasons": reasons, "options": options}


static func _option(slot: String, id: String) -> Dictionary:
	for option: Dictionary in catalog().options:
		if option.slot == slot and option.id == id:
			return option
	return {}


static func _exact_keys(value: Variant, keys: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != keys.size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not keys.has(key):
			return false
	return true


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _identifier(value: String, pattern: String) -> bool:
	if value.length() > 128:
		return false
	var expression := RegEx.new()
	expression.compile(pattern)
	var matched := expression.search(value)
	return matched != null and matched.get_end() == value.length()


static func _canonical(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var keys: Array = value.keys()
		keys.sort()
		var result: Dictionary = {}
		for key: String in keys:
			result[key] = _canonical(value[key])
		return result
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonical(item))
		return result
	return value


static func _failure(code: String, path: String, message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message]),
		"diagnostics": [{"code": code, "path": path, "message": message}],
		"selection": {}, "availability": "unavailable", "options": []}
