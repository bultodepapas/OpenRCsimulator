extends RefCounted
## Pure registry for observed connection handles and explicit device ownership.

signal selection_changed(role: String, id: int)
signal devices_changed

const ROLES := ["flight", "ui"]
const IDENTITY_FIELDS := ["guid", "vendor_id", "product_id", "serial_number", "raw_name", "backend", "transport"]

var _devices: Dictionary = {} # current connection handle -> copied device record
var _selections: Dictionary = {"flight": -1, "ui": -1}


## Replaces the observed snapshot. A newly connected device is registered only;
## it never takes flight or UI ownership automatically.
func update_devices(observations: Array) -> Dictionary:
	var errors: Array[String] = []
	var incoming: Dictionary = {}
	for observation in observations:
		if typeof(observation) != TYPE_DICTIONARY:
			errors.append("Ignored a device observation that was not a Dictionary.")
			continue
		var raw_id: Variant = observation.get("id")
		if typeof(raw_id) != TYPE_INT or int(raw_id) < 0:
			errors.append("Ignored a device observation without a valid connection ID.")
			continue
		var id: int = raw_id
		if incoming.has(id):
			errors.append("Ignored duplicate device observation for connection ID %d." % id)
			continue
		incoming[id] = observation

	var changed := false
	var lost_selections: Array[String] = []
	for key in _devices.keys():
		var id: int = int(key)
		var previous: Dictionary = _devices[id]
		if previous.get("connected", false) and not incoming.has(id):
			previous = previous.duplicate(true)
			previous["connected"] = false
			_devices[id] = previous
			changed = true
			for role in ROLES:
				if int(_selections[role]) == id:
					_selections[role] = -1
					lost_selections.append(role)

	for key in incoming.keys():
		var id: int = int(key)
		var observed: Dictionary = incoming[id]
		var previous: Dictionary = _devices.get(id, {})
		var record := _normalize_observation(observed, id)
		var was_connected: bool = previous.get("connected", false)
		var identity_changed := was_connected and not _same_identity(previous, record)
		var reconnected := not previous.is_empty() and not was_connected
		var generation := int(previous.get("generation", 0))
		if previous.is_empty():
			generation = 1
		elif reconnected or identity_changed:
			generation += 1
		if identity_changed:
			for role in ROLES:
				if int(_selections[role]) == id:
					_selections[role] = -1
					lost_selections.append(role)
		record["generation"] = generation
		record["connected"] = true
		if previous != record:
			changed = true
		_devices[id] = record

	changed = _apply_ambiguity_flags() or changed
	for role in lost_selections:
		selection_changed.emit(role, -1)
	if changed:
		devices_changed.emit()
	return {"ok": errors.is_empty(), "errors": errors}


## Applies a backend disconnect edge immediately, even if enumeration reuses the same ID next frame.
func disconnect_device(id: int) -> bool:
	if id < 0 or not _devices.has(id):
		return false
	var record: Dictionary = _devices[id]
	if not record.get("connected", false):
		return true
	record = record.duplicate(true)
	record["connected"] = false
	_devices[id] = record
	var changed_roles: Array[String] = []
	for role in ROLES:
		if int(_selections[role]) == id:
			_selections[role] = -1
			changed_roles.append(role)
	_apply_ambiguity_flags()
	for role in changed_roles:
		selection_changed.emit(role, -1)
	devices_changed.emit()
	return true


## A negative ID explicitly clears the role. Selecting a device is never implicit.
func select_device(role: String, id: int) -> bool:
	if not ROLES.has(role):
		return false
	if id != -1 and (not _devices.has(id) or not bool(_devices[id].get("connected", false))):
		return false
	if int(_selections[role]) == id:
		return true
	_selections[role] = id
	selection_changed.emit(role, id)
	return true


func selected_device_id(role: String) -> int:
	return int(_selections.get(role, -1))


## Returns the current or last-seen record. Unknown IDs, including -1, return {}.
func device_for_id(id: int) -> Dictionary:
	if id < 0 or not _devices.has(id):
		return {}
	return _devices[id].duplicate(true)


## Returns a detached, stable ID-ordered copy for setup screens.
func get_devices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _devices.keys()
	ids.sort()
	for id in ids:
		result.append(_devices[id].duplicate(true))
	return result


func connection_generation(id: int) -> int:
	return int(_devices.get(id, {}).get("generation", 0))


func _normalize_observation(info: Dictionary, id: int) -> Dictionary:
	var name := _string_field(info, "name", "joystick %d" % id)
	var raw_name := _string_field(info, "raw_name", name)
	var kind_value: Variant = info.get("kind", "")
	var kind := str(kind_value) if typeof(kind_value) == TYPE_STRING and kind_value in ["gamepad", "radio", "joystick"] else ("gamepad" if info.get("known", false) else "joystick")
	return {
		"id": id,
		"guid": _string_field(info, "guid"),
		"name": name,
		"raw_name": raw_name,
		"known": bool(info.get("known", false)) if typeof(info.get("known", false)) == TYPE_BOOL else false,
		"vendor_id": _uint_field(info, "vendor_id"),
		"product_id": _uint_field(info, "product_id"),
		"serial_number": _string_field(info, "serial_number"),
		"platform": _string_field(info, "platform"),
		"backend": _string_field(info, "backend"),
		"transport": _string_field(info, "transport"),
		"profile_id": _string_field(info, "profile_id"),
		"kind": kind,
		"connected": true,
		"generation": 0,
		"ambiguous": false,
	}


func _apply_ambiguity_flags() -> bool:
	var changed := false
	var fingerprints: Dictionary = {}
	for id in _devices:
		var device: Dictionary = _devices[id]
		if not device.get("connected", false):
			continue
		var fingerprint := _fingerprint(device)
		if fingerprint.is_empty():
			continue
		fingerprints[fingerprint] = int(fingerprints.get(fingerprint, 0)) + 1
	for id in _devices:
		var device: Dictionary = _devices[id]
		var ambiguous := bool(device.get("connected", false)) and not _fingerprint(device).is_empty() and int(fingerprints.get(_fingerprint(device), 0)) > 1
		if bool(device.get("ambiguous", false)) != ambiguous:
			device["ambiguous"] = ambiguous
			_devices[id] = device
			changed = true
	return changed


func _fingerprint(device: Dictionary) -> String:
	var guid := str(device.get("guid", ""))
	var vendor_id := int(device.get("vendor_id", 0))
	var product_id := int(device.get("product_id", 0))
	if not guid.is_empty() and vendor_id > 0 and product_id > 0:
		return "%s|%04x:%04x" % [guid.to_lower(), vendor_id, product_id]
	if not guid.is_empty():
		return "guid:" + guid.to_lower()
	var raw_name := str(device.get("raw_name", "")).strip_edges().to_lower()
	return "name:" + raw_name if not raw_name.is_empty() else ""


func _same_identity(left: Dictionary, right: Dictionary) -> bool:
	for field in IDENTITY_FIELDS:
		if left.get(field, "") != right.get(field, ""):
			return false
	return true


func _string_field(info: Dictionary, field: String, fallback: String = "") -> String:
	var value: Variant = info.get(field, fallback)
	return value.substr(0, 256) if typeof(value) == TYPE_STRING else fallback


func _uint_field(info: Dictionary, field: String) -> int:
	var value: Variant = info.get(field, 0)
	var normalized := -1
	if typeof(value) == TYPE_INT:
		normalized = int(value)
	elif typeof(value) == TYPE_STRING and value.strip_edges().is_valid_int():
		normalized = value.strip_edges().to_int()
	if normalized < 0 or normalized > 65535:
		return 0
	return normalized
