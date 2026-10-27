extends RefCounted
## Versioned controller bindings and scalar conditioning rules.

const SCHEMA_VERSION := 2
const AXIS_COUNT := 10
const VALID_KINDS := ["gamepad", "radio", "joystick"]
const VALID_THROTTLE_MODES := ["stick_rate", "trigger_absolute", "radio_absolute"]
const VALID_GLYPHS := ["auto", "xbox", "playstation", "nintendo", "generic"]
const SmokeAux := preload("res://input/smoke_aux.gd")
const ControllerActions := preload("res://input/controller_actions.gd")

const DEFAULT_DEADZONE := 0.08
const DEFAULT_EXPO := 0.3
const DEFAULT_THROTTLE_RATE := 0.5


## Returns a complete, validated starter profile. `preset` is one of mode1,
## mode2, trigger_absolute, radio_custom, or jeti_mode2. Unknown combinations return {}.
static func defaults(kind: String = "gamepad", preset: String = "mode2") -> Dictionary:
	if preset == "custom" and kind in ["radio", "joystick"]:
		preset = "radio_custom"
	if not VALID_KINDS.has(kind):
		return {}
	if kind == "gamepad" and not ["mode1", "mode2", "trigger_absolute"].has(preset):
		return {}
	if kind == "radio" and preset not in ["radio_custom", "jeti_mode2"]:
		return {}
	if kind == "joystick" and preset != "radio_custom":
		return {}

	var channels: Dictionary = {}
	var throttle_mode := "radio_absolute"
	if kind == "gamepad":
		throttle_mode = "trigger_absolute" if preset == "trigger_absolute" else "stick_rate"
		var throttle_axis := 1 if preset == "mode2" else (3 if preset == "mode1" else 5)
		channels = {
			"roll": _centered_channel(2, false, true),
			"pitch": _centered_channel(3 if preset != "mode1" else 1, false, true),
			"yaw": _centered_channel(0, false, true),
			"throttle": _absolute_channel(throttle_axis, false) if preset == "trigger_absolute" else _centered_channel(throttle_axis, true, true),
		}
	else:
		channels = {
			"roll": _centered_channel(0, false, false),
			"pitch": _centered_channel(1, true, false),
			"yaw": _centered_channel(3, false, false),
			"throttle": _absolute_channel(2, false, false, -1.0, 0.0, 1.0),
		}

	var name := "Gamepad Mode 2" if preset == "mode2" else ("Gamepad Mode 1" if preset == "mode1" else ("Gamepad Trigger Throttle" if preset == "trigger_absolute" else ("Radio Custom" if kind == "radio" else "Joystick Custom")))
	if preset == "jeti_mode2":
		name = "JETI USB Mode 2"
	var result: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"profile_id": _new_uuid(),
		"name": name,
		"kind": kind,
		"preset": preset,
		"preset_revision": 1,
		"throttle_mode": throttle_mode,
		"throttle_rate": DEFAULT_THROTTLE_RATE,
		"idle_threshold": 0.05,
		"neutral_duration_ms": 200,
		"require_release": true,
		"roll": channels.roll,
		"pitch": channels.pitch,
		"yaw": channels.yaw,
		"throttle": channels.throttle,
		"association": {},
		"actions": {},
		"presentation": {"glyph_family": "auto", "rumble_enabled": false, "rumble_intensity": 0.5},
		"aux": {},
	}
	result["configured"] = true
	if preset == "jeti_mode2":
		result.actions = ControllerActions.clean_radio_bindings()
	return result if validate(result).ok else {}


## Explicit draft operation. Preserve calibration, kind, identity and AUX; never save here.
static func clean_radio_actions(value: Dictionary) -> Dictionary:
	if value.get("kind", "") not in ["radio", "joystick"]:
		return {}
	var result := value.duplicate(true)
	result["actions"] = ControllerActions.clean_radio_bindings()
	return result if validate(result).ok else {}


## An unknown physical device has no flight mapping until a pilot configures it.
static func unconfigured() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"profile_id": "",
		"name": "Unconfigured controller",
		"kind": "joystick",
		"preset": "unconfigured",
		"preset_revision": 1,
		"throttle_mode": "radio_absolute",
		"configured": false,
	}


## Normalizes an old in-memory radio/gamepad shape without writing any storage.
## Invalid or incomplete legacy data returns {}.
static func upgrade_legacy(value: Variant, association: Dictionary = {}) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var schema_version: Variant = value.get("schema_version")
	if typeof(schema_version) == TYPE_INT and schema_version == SCHEMA_VERSION:
		# Runtime callers sometimes construct nested bindings with GDScript's
		# `key = value` shorthand, which creates StringName keys. Normalize those
		# keys at the API boundary while keeping validate() strict for raw V2 data.
		var normalized := _normalize_schema_keys(value, 0)
		if not normalized.ok or typeof(normalized.value) != TYPE_DICTIONARY:
			return {}
		# Historical optional smoke corruption may be sanitized, but malformed new
		# switch groups must not silently turn into a different saved configuration.
		var aux_value: Variant = normalized.value.get("aux", {})
		if aux_value is Dictionary:
			for aux_id in ["smoke", "flaps", "gear"]:
				var aux_binding: Variant = aux_value.get(aux_id, {})
				if _string_field(aux_binding, "type") == "switch" and not SmokeAux.valid_binding(aux_binding):
					return {}
		var current: Dictionary = SmokeAux.sanitize_profile(normalized.value, false)
		return current if validate(current).ok else {}
	if value.has("schema_version"):
		return {}
	var legacy_result := _legacy_tree(value, 0)
	if not legacy_result.ok or typeof(legacy_result.value) != TYPE_DICTIONARY:
		return {}
	var legacy: Dictionary = legacy_result.value
	var kind_value: Variant = legacy.get("kind", "")
	if typeof(kind_value) != TYPE_STRING or not ["radio", "gamepad"].has(kind_value):
		return {}
	var kind: String = kind_value
	var preset := "mode2" if kind == "gamepad" else "radio_custom"
	var throttle_mode := str(legacy.get("throttle_mode", "stick_rate" if kind == "gamepad" else "radio_absolute"))
	if kind == "gamepad":
		preset = "trigger_absolute" if throttle_mode == "trigger_absolute" else ("mode1" if str(legacy.get("preset", "mode2")) == "mode1" else "mode2")
	var result := defaults(kind, preset)
	if result.is_empty():
		return {}
	var deadzone: Variant = legacy.get("deadzone", DEFAULT_DEADZONE)
	var expo: Variant = legacy.get("expo", DEFAULT_EXPO)
	if kind == "gamepad" and (not _is_number(deadzone) or not _is_number(expo)):
		return {}
	for channel_name in ["roll", "pitch", "yaw", "throttle"]:
		var old_channel: Variant = legacy.get(channel_name)
		if typeof(old_channel) != TYPE_DICTIONARY:
			return {}
		var copied: Dictionary = old_channel.duplicate(true)
		if kind == "gamepad":
			copied["range_kind"] = "absolute" if channel_name == "throttle" and throttle_mode == "trigger_absolute" else "centered"
			copied["deadzone"] = float(deadzone)
			copied["expo"] = float(expo)
		elif channel_name == "throttle":
			copied["range_kind"] = "absolute"
		else:
			copied["range_kind"] = "centered"
		result[channel_name] = copied
	result["throttle_mode"] = throttle_mode
	result["throttle_rate"] = legacy.get("throttle_rate", DEFAULT_THROTTLE_RATE)
	result["name"] = str(legacy.get("name", result.name))
	result["preset"] = str(legacy.get("preset", preset))
	result["association"] = association.duplicate(true) if not association.is_empty() else legacy.get("association", {}).duplicate(true) if typeof(legacy.get("association", {})) == TYPE_DICTIONARY else {}
	var aux_value: Variant = legacy.get("aux", {})
	if typeof(aux_value) == TYPE_DICTIONARY:
		result["aux"] = aux_value.duplicate(true)
	for key in legacy:
		if not ["kind", "roll", "pitch", "yaw", "throttle", "deadzone", "expo", "throttle_rate", "name", "preset", "schema_version", "profile_id", "aux", "association", "throttle_mode", "configured"].has(str(key)):
			result[key] = legacy[key].duplicate(true) if typeof(legacy[key]) in [TYPE_ARRAY, TYPE_DICTIONARY] else legacy[key]
	return result if validate(result).ok else {}


## Old RcCalibration profiles use StringName keys in some in-memory/ConfigFile paths.
## Normalize only that legacy input; schema-v2 candidates stay strictly validated as supplied.
static func _legacy_tree(value: Variant, depth: int) -> Dictionary:
	if depth > 16:
		return {"ok": false, "value": null}
	if typeof(value) == TYPE_DICTIONARY:
		if value.size() > 4096:
			return {"ok": false, "value": null}
		var result: Dictionary = {}
		for key in value:
			if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT]:
				return {"ok": false, "value": null}
			var normalized_key: Variant = str(key) if typeof(key) == TYPE_STRING_NAME else key
			if result.has(normalized_key):
				return {"ok": false, "value": null}
			var child := _legacy_tree(value[key], depth + 1)
			if not child.ok:
				return {"ok": false, "value": null}
			result[normalized_key] = child.value
		return {"ok": true, "value": result}
	if typeof(value) == TYPE_ARRAY:
		if value.size() > 4096:
			return {"ok": false, "value": null}
		var result: Array = []
		for child_value in value:
			var child := _legacy_tree(child_value, depth + 1)
			if not child.ok:
				return {"ok": false, "value": null}
			result.append(child.value)
		return {"ok": true, "value": result}
	if typeof(value) == TYPE_STRING_NAME:
		return {"ok": true, "value": str(value)}
	if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING]:
		return {"ok": true, "value": value}
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)):
		return {"ok": true, "value": value}
	return {"ok": false, "value": null}


## Normalize only dictionary keys. V2 values remain subject to the strict tree validator.
static func _normalize_schema_keys(value: Variant, depth: int) -> Dictionary:
	if depth > 16:
		return {"ok": false, "value": null}
	if typeof(value) == TYPE_DICTIONARY:
		if value.size() > 4096:
			return {"ok": false, "value": null}
		var result: Dictionary = {}
		for key in value:
			if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT]:
				return {"ok": false, "value": null}
			var normalized_key: Variant = str(key) if typeof(key) == TYPE_STRING_NAME else key
			if result.has(normalized_key):
				return {"ok": false, "value": null}
			var child := _normalize_schema_keys(value[key], depth + 1)
			if not child.ok:
				return {"ok": false, "value": null}
			result[normalized_key] = child.value
		return {"ok": true, "value": result}
	if typeof(value) == TYPE_ARRAY:
		if value.size() > 4096:
			return {"ok": false, "value": null}
		var result: Array = []
		for child_value in value:
			var child := _normalize_schema_keys(child_value, depth + 1)
			if not child.ok:
				return {"ok": false, "value": null}
			result.append(child.value)
		return {"ok": true, "value": result}
	return {"ok": true, "value": value}


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	var issues: Array[Dictionary] = []
	if typeof(value) != TYPE_DICTIONARY:
		var error: String = "profile must be a Dictionary"
		_append_validation_issue(errors, issues, "profile_invalid", ["profile"], error)
		return {"ok": false, "errors": errors, "issues": issues}
	if not _valid_variant_tree(value, 0):
		var error: String = "profile contains a non-finite or unsupported value"
		_append_validation_issue(errors, issues, "profile_invalid", [_invalid_variant_path(value, "", 0)], error)
	if typeof(value.get("schema_version")) != TYPE_INT or value.get("schema_version") != SCHEMA_VERSION:
		var error: String = "schema_version must be 2"
		_append_validation_issue(errors, issues, "profile_invalid", ["schema_version"], error)
	var profile_id: Variant = value.get("profile_id")
	if typeof(profile_id) != TYPE_STRING or not _is_uuid(profile_id):
		var error: String = "profile_id must be a UUID"
		_append_validation_issue(errors, issues, "profile_invalid", ["profile_id"], error)
	var profile_name: Variant = value.get("name")
	if typeof(profile_name) != TYPE_STRING or profile_name.strip_edges().is_empty() or profile_name.length() > 80:
		var error: String = "name must contain 1 to 80 characters"
		_append_validation_issue(errors, issues, "name_invalid", ["name"], error)
	var kind_value: Variant = value.get("kind")
	if typeof(kind_value) != TYPE_STRING or not VALID_KINDS.has(kind_value):
		var error: String = "kind must be gamepad, radio, or joystick"
		_append_validation_issue(errors, issues, "profile_invalid", ["kind"], error)
	var configured: Variant = value.get("configured", true)
	if typeof(configured) != TYPE_BOOL or not configured:
		var error: String = "unconfigured profile cannot drive flight commands"
		_append_validation_issue(errors, issues, "profile_invalid", ["configured"], error)
	var preset: Variant = value.get("preset")
	if typeof(preset) != TYPE_STRING or preset.is_empty() or preset.length() > 40:
		var error: String = "preset must be a non-empty string"
		_append_validation_issue(errors, issues, "profile_invalid", ["preset"], error)
	if typeof(value.get("preset_revision")) != TYPE_INT or int(value.get("preset_revision", 0)) < 1:
		var error: String = "preset_revision must be a positive integer"
		_append_validation_issue(errors, issues, "profile_invalid", ["preset_revision"], error)
	var mode_value: Variant = value.get("throttle_mode")
	if typeof(mode_value) != TYPE_STRING or not VALID_THROTTLE_MODES.has(mode_value):
		var error: String = "throttle_mode is unsupported"
		_append_validation_issue(errors, issues, "profile_invalid", ["throttle_mode"], error)
	elif typeof(kind_value) == TYPE_STRING:
		if kind_value == "radio" and mode_value != "radio_absolute":
			var error: String = "radio profiles require radio_absolute throttle"
			_append_validation_issue(errors, issues, "profile_invalid", ["throttle_mode"], error)
		if kind_value == "gamepad" and not ["stick_rate", "trigger_absolute"].has(mode_value):
			var error: String = "gamepad profiles require stick_rate or trigger_absolute throttle"
			_append_validation_issue(errors, issues, "profile_invalid", ["throttle_mode"], error)
		if kind_value == "joystick" and mode_value == "trigger_absolute":
			var error: String = "trigger_absolute is reserved for gamepad profiles"
			_append_validation_issue(errors, issues, "profile_invalid", ["throttle_mode"], error)
	# Later comparisons use typed copies: `==` between unlike Variant types raises a script
	# error, which would abort validation after the type error above was recorded.
	var kind := _string_field(value, "kind")
	var throttle_mode := _string_field(value, "throttle_mode")
	for numeric_field in ["throttle_rate", "idle_threshold", "rumble_intensity"]:
		if value.has(numeric_field) and not _is_number(value[numeric_field]):
			var error: String = numeric_field + " must be finite"
			_append_validation_issue(errors, issues, "profile_invalid", [numeric_field], error)
	if value.has("throttle_rate") and _is_number(value.throttle_rate) and (float(value.throttle_rate) <= 0.0 or float(value.throttle_rate) > 5.0):
		var error: String = "throttle_rate must be greater than 0 and at most 5"
		_append_validation_issue(errors, issues, "profile_invalid", ["throttle_rate"], error)
	if value.has("idle_threshold") and _is_number(value.idle_threshold) and (float(value.idle_threshold) < 0.0 or float(value.idle_threshold) > 0.2):
		var error: String = "idle_threshold must be between 0 and 0.2"
		_append_validation_issue(errors, issues, "profile_invalid", ["idle_threshold"], error)
	if typeof(value.get("neutral_duration_ms")) != TYPE_INT or int(value.get("neutral_duration_ms", -1)) < 1 or int(value.get("neutral_duration_ms", -1)) > 5000:
		var error: String = "neutral_duration_ms must be from 1 to 5000"
		_append_validation_issue(errors, issues, "profile_invalid", ["neutral_duration_ms"], error)
	if typeof(value.get("require_release")) != TYPE_BOOL:
		var error: String = "require_release must be a boolean"
		_append_validation_issue(errors, issues, "profile_invalid", ["require_release"], error)
	if typeof(value.get("association")) != TYPE_DICTIONARY:
		var error: String = "association must be a Dictionary"
		_append_validation_issue(errors, issues, "profile_invalid", ["association"], error)
	elif not _valid_association(value.get("association")):
		var error: String = "association contains invalid device identity data"
		_append_validation_issue(errors, issues, "profile_invalid", ["association"], error)
	var action_values: Variant = value.get("actions")
	if typeof(action_values) != TYPE_DICTIONARY:
		var error: String = "actions must be a Dictionary"
		_append_validation_issue(errors, issues, "profile_invalid", ["actions"], error)
	else:
		for action_id in action_values:
			if typeof(action_id) != TYPE_STRING or ControllerActions.action_definition(str(action_id)).is_empty():
				var error: String = "actions contains an unknown semantic action"
				_append_validation_issue(errors, issues, "action_unknown", ["actions.%s" % str(action_id)], error)
				continue
			if not _valid_action_binding(action_values[action_id]):
				var error: String = "actions.%s has an invalid binding" % str(action_id)
				_append_validation_issue(errors, issues, "binding_invalid", ["actions.%s" % str(action_id)], error)
		var action_validation: Dictionary = ControllerActions.validate_profile_bindings(value)
		for action_error in action_validation.errors:
			errors.append("actions: " + str(action_error))
		for action_issue in action_validation.issues:
			issues.append(action_issue.duplicate(true))
	var presentation: Variant = value.get("presentation")
	if typeof(presentation) != TYPE_DICTIONARY:
		var error: String = "presentation must be a Dictionary"
		_append_validation_issue(errors, issues, "profile_invalid", ["presentation"], error)
	else:
		if typeof(presentation.get("glyph_family")) != TYPE_STRING or not VALID_GLYPHS.has(presentation.get("glyph_family")):
			var error: String = "presentation.glyph_family is unsupported"
			_append_validation_issue(errors, issues, "profile_invalid", ["presentation.glyph_family"], error)
		if typeof(presentation.get("rumble_enabled")) != TYPE_BOOL:
			var error: String = "presentation.rumble_enabled must be a boolean"
			_append_validation_issue(errors, issues, "profile_invalid", ["presentation.rumble_enabled"], error)
		if not _is_number(presentation.get("rumble_intensity")) or float(presentation.get("rumble_intensity", -1.0)) < 0.0 or float(presentation.get("rumble_intensity", 2.0)) > 1.0:
			var error: String = "presentation.rumble_intensity must be between 0 and 1"
			_append_validation_issue(errors, issues, "profile_invalid", ["presentation.rumble_intensity"], error)

	var axes: Dictionary = {}
	var axis_channels: Dictionary = {}
	for channel_name in ["roll", "pitch", "yaw", "throttle"]:
		var channel: Variant = value.get(channel_name)
		if typeof(channel) != TYPE_DICTIONARY:
			var error: String = channel_name + " must be a Dictionary"
			_append_validation_issue(errors, issues, "channel_invalid", [str(channel_name)], error)
			continue
		var range_kind := _string_field(channel, "range_kind")
		if typeof(channel.get("axis")) != TYPE_INT or int(channel.get("axis", -1)) < 0 or int(channel.get("axis", 99)) >= AXIS_COUNT:
			var error: String = channel_name + ".axis must be an integer from 0 to 9"
			_append_validation_issue(errors, issues, "axis_invalid", ["%s.axis" % channel_name], error)
		else:
			var source_axis: int = channel.axis
			if axes.has(source_axis):
				var error: String = "flight channels must use separate source axes"
				errors.append(error)
				var conflict_paths: Array[String] = []
				for participant in axis_channels[source_axis]:
					conflict_paths.append("%s.axis" % participant)
				conflict_paths.append("%s.axis" % channel_name)
				_append_issue(issues, "axis_conflict", conflict_paths, error)
			axes[source_axis] = channel_name
			if not axis_channels.has(source_axis):
				axis_channels[source_axis] = []
			axis_channels[source_axis].append(channel_name)
		if typeof(channel.get("invert")) != TYPE_BOOL:
			var error: String = channel_name + ".invert must be a boolean"
			_append_validation_issue(errors, issues, "channel_invalid", ["%s.invert" % channel_name], error)
		if typeof(channel.get("range_kind")) != TYPE_STRING or not ["centered", "absolute"].has(channel.get("range_kind")):
			var error: String = channel_name + ".range_kind must be centered or absolute"
			_append_validation_issue(errors, issues, "range_invalid", ["%s.range_kind" % channel_name], error)
		for endpoint in ["min", "center", "max"]:
			if not _is_number(channel.get(endpoint)) or float(channel.get(endpoint, 2.0)) < -1.0 or float(channel.get(endpoint, 2.0)) > 1.0:
				var error: String = channel_name + "." + endpoint + " must be finite and within -1 to 1"
				_append_validation_issue(errors, issues, "range_invalid", ["%s.%s" % [channel_name, endpoint]], error)
		if _is_number(channel.get("min")) and _is_number(channel.get("center")) and _is_number(channel.get("max")):
			var lo: float = float(channel.min)
			var center: float = float(channel.center)
			var hi: float = float(channel.max)
			if lo >= hi:
				var error: String = channel_name + " has zero or reversed range"
				_append_validation_issue(errors, issues, "range_invalid", ["%s.min" % channel_name, "%s.max" % channel_name], error)
			elif channel.get("range_kind") == "centered" and channel_name != "throttle" and not (lo < center and center < hi):
				var error: String = channel_name + " requires travel on both sides of center"
				_append_validation_issue(errors, issues, "range_invalid", ["%s.min" % channel_name, "%s.center" % channel_name, "%s.max" % channel_name], error)
			elif channel.get("range_kind") == "centered" and channel_name == "throttle" and mode_value == "stick_rate" and not (lo < center and center < hi):
				var error: String = "stick_rate throttle requires travel on both sides of center"
				_append_validation_issue(errors, issues, "range_invalid", ["throttle.min", "throttle.center", "throttle.max"], error)
			elif channel.get("range_kind") == "centered" and channel_name == "throttle" and mode_value != "stick_rate" and not (lo <= center and center <= hi):
				var error: String = "throttle center must be within its endpoints"
				_append_validation_issue(errors, issues, "range_invalid", ["throttle.min", "throttle.center", "throttle.max"], error)
			elif channel.get("range_kind") == "absolute" and not (lo <= center and center <= hi):
				var error: String = channel_name + " absolute range requires center within endpoints"
				_append_validation_issue(errors, issues, "range_invalid", ["%s.min" % channel_name, "%s.center" % channel_name, "%s.max" % channel_name], error)
		if kind_value == "gamepad" and channel.get("range_kind") == "centered":
			if not _is_number(channel.get("deadzone")) or float(channel.get("deadzone", -1.0)) < 0.0 or float(channel.get("deadzone", 2.0)) >= 1.0:
				var error: String = channel_name + ".deadzone must be in [0, 1)"
				_append_validation_issue(errors, issues, "deadzone_invalid", ["%s.deadzone" % channel_name], error)
			if not _is_number(channel.get("expo")) or float(channel.get("expo", -1.0)) < 0.0 or float(channel.get("expo", 2.0)) > 1.0:
				var error: String = channel_name + ".expo must be in [0, 1]"
				_append_validation_issue(errors, issues, "expo_invalid", ["%s.expo" % channel_name], error)
	if typeof(mode_value) == TYPE_STRING and mode_value == "stick_rate" and typeof(value.get("throttle")) == TYPE_DICTIONARY and value.throttle.get("range_kind") != "centered":
		var error: String = "stick_rate throttle must use a centered range"
		_append_validation_issue(errors, issues, "range_invalid", ["throttle.range_kind"], error)
	if typeof(mode_value) == TYPE_STRING and mode_value == "trigger_absolute" and typeof(value.get("throttle")) == TYPE_DICTIONARY and value.throttle.get("range_kind") != "absolute":
		var error: String = "trigger_absolute throttle must use an absolute range"
		_append_validation_issue(errors, issues, "range_invalid", ["throttle.range_kind"], error)
	if typeof(mode_value) == TYPE_STRING and mode_value == "radio_absolute" and typeof(value.get("throttle")) == TYPE_DICTIONARY and value.throttle.get("range_kind") != "absolute":
		var error: String = "radio_absolute throttle must use an absolute range"
		_append_validation_issue(errors, issues, "range_invalid", ["throttle.range_kind"], error)
	if value.has("aux") and typeof(value.get("aux")) != TYPE_DICTIONARY:
		var error: String = "aux must be a Dictionary"
		_append_validation_issue(errors, issues, "aux_invalid", ["aux"], error)
	elif typeof(value.get("aux", {})) == TYPE_DICTIONARY:
		var aux: Dictionary = value.get("aux", {})
		if aux.has("smoke") and not SmokeAux.valid_binding(aux.smoke, axes.keys()):
			var error: String = "aux.smoke is invalid or overlaps a flight axis"
			errors.append(error)
			_append_issue(issues, "aux_invalid", ControllerActions._aux_invalid_paths("smoke", aux.smoke, value), error)
	return {"ok": errors.is_empty(), "errors": errors, "issues": issues}


static func _append_validation_issue(errors: Array[String], issues: Array[Dictionary], code: String,
		paths: Array, message: String) -> void:
	errors.append(message)
	_append_issue(issues, code, paths, message)


static func _append_issue(issues: Array[Dictionary], code: String, paths: Array, message: String) -> void:
	var issue_paths: Array[String] = []
	for path in paths:
		issue_paths.append(str(path))
	issues.append({"code": code, "paths": issue_paths, "message": message})


static func _invalid_variant_path(value: Variant, path: String, depth: int) -> String:
	if depth > 16:
		return path if not path.is_empty() else "profile"
	match typeof(value):
		TYPE_FLOAT:
			if not is_finite(float(value)):
				return path if not path.is_empty() else "profile"
		TYPE_ARRAY:
			if value.size() > 4096:
				return path if not path.is_empty() else "profile"
			for index in value.size():
				var child_path := "%s.%d" % [path, index] if not path.is_empty() else str(index)
				var invalid_path := _invalid_variant_path(value[index], child_path, depth + 1)
				if not invalid_path.is_empty():
					return invalid_path
		TYPE_DICTIONARY:
			if value.size() > 4096:
				return path if not path.is_empty() else "profile"
			for key in value:
				if typeof(key) not in [TYPE_STRING, TYPE_INT]:
					return path if not path.is_empty() else "profile"
				var child_path := str(key) if path.is_empty() else "%s.%s" % [path, str(key)]
				var invalid_path := _invalid_variant_path(value[key], child_path, depth + 1)
				if not invalid_path.is_empty():
					return invalid_path
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return ""
		_:
			return path if not path.is_empty() else "profile"
	return ""


static func is_valid(value: Variant) -> bool:
	return bool(validate(value).ok)


## Maps a finite raw Godot axis through calibrated endpoints and inversion.
static func normalize_axis(value: float, channel: Dictionary) -> float:
	if not is_finite(value) or not _is_number(channel.get("min")) or not _is_number(channel.get("center")) or not _is_number(channel.get("max")):
		return 0.0
	var lo: float = float(channel.min)
	var center: float = float(channel.center)
	var hi: float = float(channel.max)
	if channel.get("range_kind", "centered") == "absolute":
		var absolute: float = clampf((value - lo) / maxf(hi - lo, 0.000001), 0.0, 1.0)
		return 1.0 - absolute if channel.get("invert", false) else absolute
	var normalized := (value - center) / maxf(hi - center, 0.000001) if value >= center else (value - center) / maxf(center - lo, 0.000001)
	normalized = clampf(normalized, -1.0, 1.0)
	return -normalized if channel.get("invert", false) else normalized


## Applies scalar, rescaled deadzone then a single cubic expo stage.
static func condition_axis(value: float, channel: Dictionary, kind: String) -> float:
	if not is_finite(value):
		return 0.0
	var x: float = clampf(value, -1.0, 1.0)
	if kind != "gamepad":
		return x
	var dz: float = float(channel.get("deadzone", DEFAULT_DEADZONE))
	var expo: float = float(channel.get("expo", DEFAULT_EXPO))
	if not is_finite(dz) or not is_finite(expo) or dz < 0.0 or dz >= 1.0 or expo < 0.0 or expo > 1.0:
		return 0.0
	var rescaled: float = maxf(0.0, absf(x) - dz) / (1.0 - dz)
	return signf(x) * ((1.0 - expo) * rescaled + expo * rescaled * rescaled * rescaled)


## Convenience for live previews: raw calibration, then one conditioning stage.
static func conditioned_axis(raw: float, channel: Dictionary, kind: String) -> float:
	return condition_axis(normalize_axis(raw, channel), channel, kind)


static func _centered_channel(axis: int, invert: bool, shape: bool, lo: float = -1.0, center: float = 0.0, hi: float = 1.0) -> Dictionary:
	var channel := {"axis": axis, "invert": invert, "min": lo, "center": center, "max": hi, "range_kind": "centered"}
	if shape:
		channel["deadzone"] = DEFAULT_DEADZONE
		channel["expo"] = DEFAULT_EXPO
	return channel


static func _absolute_channel(axis: int, invert: bool, shape: bool = false, lo: float = 0.0, center: float = 0.0, hi: float = 1.0) -> Dictionary:
	var channel := {"axis": axis, "invert": invert, "min": lo, "center": center, "max": hi, "range_kind": "absolute"}
	if shape:
		channel["deadzone"] = DEFAULT_DEADZONE
		channel["expo"] = DEFAULT_EXPO
	return channel


static func _valid_variant_tree(value: Variant, depth: int) -> bool:
	if depth > 16:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			if value.size() > 4096:
				return false
			for child in value:
				if not _valid_variant_tree(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 4096:
				return false
			for key in value:
				if typeof(key) not in [TYPE_STRING, TYPE_INT]:
					return false
				if not _valid_variant_tree(value[key], depth + 1):
					return false
			return true
	return false


static func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _valid_association(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for field in ["serial_number", "guid", "legacy_device_key"]:
		if not value.has(field):
			continue
		var identity: Variant = value[field]
		var limit := 1024 if field == "legacy_device_key" else 256
		if typeof(identity) != TYPE_STRING or identity.length() > limit:
			return false
	for field in ["vendor_id", "product_id"]:
		if not value.has(field):
			continue
		var raw_id: Variant = value[field]
		var normalized_id := -1
		if typeof(raw_id) == TYPE_INT:
			normalized_id = int(raw_id)
		elif typeof(raw_id) == TYPE_STRING and raw_id.length() <= 10 and raw_id.strip_edges().is_valid_int():
			normalized_id = raw_id.strip_edges().to_int()
		if normalized_id < 0 or normalized_id > 65535:
			return false
	for field: Variant in value:
		if typeof(field) != TYPE_STRING or not ["serial_number", "guid", "legacy_device_key", "vendor_id", "product_id"].has(field):
			return false
	return true


static func _valid_action_binding(value: Variant) -> bool:
	return ControllerActions.valid_binding(value)


static func _is_uuid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 36:
		return false
	for index in value.length():
		if index in [8, 13, 18, 23]:
			if value.substr(index, 1) != "-":
				return false
		elif not "0123456789abcdefABCDEF".contains(value.substr(index, 1)):
			return false
	return true


static func _new_uuid() -> String:
	var random := RandomNumberGenerator.new()
	random.randomize()
	var bytes := PackedByteArray()
	bytes.resize(16)
	for index in bytes.size():
		bytes[index] = random.randi_range(0, 255)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := ""
	for byte in bytes:
		hex += "%02x" % int(byte)
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
