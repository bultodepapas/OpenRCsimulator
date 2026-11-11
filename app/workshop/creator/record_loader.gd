extends RefCounted
## The aircraft-record file boundary for bytes already in memory (AC-06).
##
## Does for captured bytes exactly what `AircraftData.load_file` does for a path: parse and hash
## the same bytes, validate and derive, apply the wheel-profile boundary, and record the input
## identity as the SHA-256 of those exact bytes. It lives here, built on the loader's public
## functions, so the physics source file keeps its bytes and every pinned solver identity.
## `test_creator_compiler.gd` proves it returns the same result as `load_file` for bundled records.

const AircraftData := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")


## `label` names the source in parse errors. Returns the `AircraftData.load_file` result shape.
static func load_bytes(bytes: PackedByteArray, label: String) -> Dictionary:
	if bytes.is_empty():
		return _fail("%s: no record bytes" % label)
	var text: String = bytes.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("%s: JSON error at line %d: %s" % [label, json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _fail("%s: top level must be an object" % label)
	var result: Dictionary = AircraftData.validate_and_derive(json.data)
	if result.ok:
		var profiled: Dictionary = WheelProfiles.apply_to_model(result.model)
		if not profiled.ok:
			result.ok = false
			result.errors.append_array(profiled.errors)
			result.model = {}
			return result
		result.model = profiled.model
		result.wheel_profile_identity = profiled.identity
		result.input_identity = {format = str(json.data.format), sha256 = CreatorBytes.sha256(bytes)}
	return result


static func _fail(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message]), warnings = PackedStringArray(), model = {}}
