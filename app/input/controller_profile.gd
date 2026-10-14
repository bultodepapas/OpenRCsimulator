extends RefCounted
## Versioned controller bindings and scalar conditioning rules.

const SCHEMA_VERSION := 2
const AXIS_COUNT := 10
const VALID_KINDS := ["gamepad", "radio", "joystick"]
const VALID_THROTTLE_MODES := ["stick_rate", "trigger_absolute", "radio_absolute"]
const VALID_GLYPHS := ["auto", "xbox", "playstation", "nintendo", "generic"]
const SmokeAux := preload("res://input/smoke_aux.gd")

const DEFAULT_DEADZONE := 0.08
const DEFAULT_EXPO := 0.3
const DEFAULT_THROTTLE_RATE := 0.5


## Returns a complete, validated starter profile. `preset` is one of mode1,
## mode2, trigger_absolute, or radio_custom. Unknown combinations return {}.
static func defaults(kind: String = "gamepad", preset: String = "mode2") -> Dictionary:
	if preset == "custom" and kind in ["radio", "joystick"]:
		preset = "radio_custom"
	if not VALID_KINDS.has(kind):
		return {}
	if kind == "gamepad" and not ["mode1", "mode2", "trigger_absolute"].has(preset):
		return {}
	if kind == "radio" and preset != "radio_custom":
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
	if int(value.get("schema_version", 0)) == SCHEMA_VERSION:
		return value.duplicate(true) if validate(value).ok else {}
	var kind_value: Variant = value.get("kind", "")
	if typeof(kind_value) != TYPE_STRING or not ["radio", "gamepad"].has(kind_value):
		return {}
	var kind: String = kind_value
	var preset := "mode2" if kind == "gamepad" else "radio_custom"
	var throttle_mode := str(value.get("throttle_mode", "stick_rate" if kind == "gamepad" else "radio_absolute"))
	if kind == "gamepad":
		preset = "trigger_absolute" if throttle_mode == "trigger_absolute" else ("mode1" if str(value.get("preset", "mode2")) == "mode1" else "mode2")
	var result := defaults(kind, preset)
	if result.is_empty():
		return {}
	for channel_name in ["roll", "pitch", "yaw", "throttle"]:
		var old_channel: Variant = value.get(channel_name)
		if typeof(old_channel) != TYPE_DICTIONARY:
			return {}
		var copied: Dictionary = old_channel.duplicate(true)
		if kind == "gamepad":
			copied["range_kind"] = "absolute" if channel_name == "throttle" and throttle_mode == "trigger_absolute" else "centered"
			copied["deadzone"] = float(value.get("deadzone", DEFAULT_DEADZONE))
			copied["expo"] = float(value.get("expo", DEFAULT_EXPO))
		elif channel_name == "throttle":
			copied["range_kind"] = "absolute"
		else:
			copied["range_kind"] = "centered"
		result[channel_name] = copied
	result["throttle_mode"] = throttle_mode
	result["throttle_rate"] = value.get("throttle_rate", DEFAULT_THROTTLE_RATE)
	result["name"] = str(value.get("name", result.name))
	result["preset"] = str(value.get("preset", preset))
	result["association"] = association.duplicate(true) if not association.is_empty() else value.get("association", {}).duplicate(true) if typeof(value.get("association", {})) == TYPE_DICTIONARY else {}
	var aux_value: Variant = value.get("aux", {})
	if typeof(aux_value) == TYPE_DICTIONARY:
		result["aux"] = aux_value.duplicate(true)
	for key in value:
		if not ["kind", "roll", "pitch", "yaw", "throttle", "deadzone", "expo", "throttle_rate", "name", "preset", "schema_version", "profile_id", "aux", "association", "throttle_mode", "configured"].has(str(key)):
			result[key] = value[key].duplicate(true) if typeof(value[key]) in [TYPE_ARRAY, TYPE_DICTIONARY] else value[key]
	return result if validate(result).ok else {}


static func validate(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["profile must be a Dictionary"]}
	if not _valid_variant_tree(value, 0):
		errors.append("profile contains a non-finite or unsupported value")
	if typeof(value.get("schema_version")) != TYPE_INT or value.get("schema_version") != SCHEMA_VERSION:
		errors.append("schema_version must be 2")
	var profile_id: Variant = value.get("profile_id")
	if typeof(profile_id) != TYPE_STRING or not _is_uuid(profile_id):
		errors.append("profile_id must be a UUID")
	var profile_name: Variant = value.get("name")
	if typeof(profile_name) != TYPE_STRING or profile_name.strip_edges().is_empty() or profile_name.length() > 80:
		errors.append("name must contain 1 to 80 characters")
	var kind_value: Variant = value.get("kind")
	if typeof(kind_value) != TYPE_STRING or not VALID_KINDS.has(kind_value):
		errors.append("kind must be gamepad, radio, or joystick")
	var configured: Variant = value.get("configured", true)
	if typeof(configured) != TYPE_BOOL or not configured:
		errors.append("unconfigured profile cannot drive flight commands")
	var preset: Variant = value.get("preset")
	if typeof(preset) != TYPE_STRING or preset.is_empty() or preset.length() > 40:
		errors.append("preset must be a non-empty string")
	if typeof(value.get("preset_revision")) != TYPE_INT or int(value.get("preset_revision", 0)) < 1:
		errors.append("preset_revision must be a positive integer")
	var mode_value: Variant = value.get("throttle_mode")
	if typeof(mode_value) != TYPE_STRING or not VALID_THROTTLE_MODES.has(mode_value):
		errors.append("throttle_mode is unsupported")
	elif typeof(kind_value) == TYPE_STRING:
		if kind_value == "radio" and mode_value != "radio_absolute":
			errors.append("radio profiles require radio_absolute throttle")
		if kind_value == "gamepad" and not ["stick_rate", "trigger_absolute"].has(mode_value):
			errors.append("gamepad profiles require stick_rate or trigger_absolute throttle")
		if kind_value == "joystick" and mode_value == "trigger_absolute":
			errors.append("trigger_absolute is reserved for gamepad profiles")
	for numeric_field in ["throttle_rate", "idle_threshold", "rumble_intensity"]:
		if value.has(numeric_field) and not _is_number(value[numeric_field]):
			errors.append(numeric_field + " must be finite")
	if value.has("throttle_rate") and _is_number(value.throttle_rate) and (float(value.throttle_rate) <= 0.0 or float(value.throttle_rate) > 5.0):
		errors.append("throttle_rate must be greater than 0 and at most 5")
	if value.has("idle_threshold") and _is_number(value.idle_threshold) and (float(value.idle_threshold) < 0.0 or float(value.idle_threshold) > 0.2):
		errors.append("idle_threshold must be between 0 and 0.2")
	if typeof(value.get("neutral_duration_ms")) != TYPE_INT or int(value.get("neutral_duration_ms", -1)) < 1 or int(value.get("neutral_duration_ms", -1)) > 5000:
		errors.append("neutral_duration_ms must be from 1 to 5000")
	if typeof(value.get("require_release")) != TYPE_BOOL:
		errors.append("require_release must be a boolean")
	if typeof(value.get("association")) != TYPE_DICTIONARY:
		errors.append("association must be a Dictionary")
	if typeof(value.get("actions")) != TYPE_DICTIONARY:
		errors.append("actions must be a Dictionary")
	var presentation: Variant = value.get("presentation")
	if typeof(presentation) != TYPE_DICTIONARY:
		errors.append("presentation must be a Dictionary")
	else:
		if typeof(presentation.get("glyph_family")) != TYPE_STRING or not VALID_GLYPHS.has(presentation.get("glyph_family")):
			errors.append("presentation.glyph_family is unsupported")
		if typeof(presentation.get("rumble_enabled")) != TYPE_BOOL:
			errors.append("presentation.rumble_enabled must be a boolean")
		if not _is_number(presentation.get("rumble_intensity")) or float(presentation.get("rumble_intensity", -1.0)) < 0.0 or float(presentation.get("rumble_intensity", 2.0)) > 1.0:
			errors.append("presentation.rumble_intensity must be between 0 and 1")

	var axes: Dictionary = {}
	for channel_name in ["roll", "pitch", "yaw", "throttle"]:
		var channel: Variant = value.get(channel_name)
		if typeof(channel) != TYPE_DICTIONARY:
			errors.append(channel_name + " must be a Dictionary")
			continue
		if typeof(channel.get("axis")) != TYPE_INT or int(channel.get("axis", -1)) < 0 or int(channel.get("axis", 99)) >= AXIS_COUNT:
			errors.append(channel_name + ".axis must be an integer from 0 to 9")
		else:
			var source_axis: int = channel.axis
			if axes.has(source_axis):
				errors.append("flight channels must use separate source axes")
			axes[source_axis] = channel_name
		if typeof(channel.get("invert")) != TYPE_BOOL:
			errors.append(channel_name + ".invert must be a boolean")
		if typeof(channel.get("range_kind")) != TYPE_STRING or not ["centered", "absolute"].has(channel.get("range_kind")):
			errors.append(channel_name + ".range_kind must be centered or absolute")
		for endpoint in ["min", "center", "max"]:
			if not _is_number(channel.get(endpoint)) or float(channel.get(endpoint, 2.0)) < -1.0 or float(channel.get(endpoint, 2.0)) > 1.0:
				errors.append(channel_name + "." + endpoint + " must be finite and within -1 to 1")
		if _is_number(channel.get("min")) and _is_number(channel.get("center")) and _is_number(channel.get("max")):
			var lo: float = float(channel.min)
			var center: float = float(channel.center)
			var hi: float = float(channel.max)
			if lo >= hi:
				errors.append(channel_name + " has zero or reversed range")
			elif channel.get("range_kind") == "centered" and channel_name != "throttle" and not (lo < center and center < hi):
				errors.append(channel_name + " requires travel on both sides of center")
			elif channel.get("range_kind") == "centered" and channel_name == "throttle" and not (lo <= center and center <= hi):
				errors.append("throttle center must be within its endpoints")
			elif channel.get("range_kind") == "absolute" and not (lo <= center and center <= hi):
				errors.append(channel_name + " absolute range requires center within endpoints")
		if kind_value == "gamepad" and channel.get("range_kind") == "centered":
			if not _is_number(channel.get("deadzone")) or float(channel.get("deadzone", -1.0)) < 0.0 or float(channel.get("deadzone", 2.0)) >= 1.0:
				errors.append(channel_name + ".deadzone must be in [0, 1)")
			if not _is_number(channel.get("expo")) or float(channel.get("expo", -1.0)) < 0.0 or float(channel.get("expo", 2.0)) > 1.0:
				errors.append(channel_name + ".expo must be in [0, 1]")
	if typeof(mode_value) == TYPE_STRING and mode_value == "stick_rate" and typeof(value.get("throttle")) == TYPE_DICTIONARY and value.throttle.get("range_kind") != "centered":
		errors.append("stick_rate throttle must use a centered range")
	if typeof(mode_value) == TYPE_STRING and mode_value == "trigger_absolute" and typeof(value.get("throttle")) == TYPE_DICTIONARY and value.throttle.get("range_kind") != "absolute":
		errors.append("trigger_absolute throttle must use an absolute range")
	if typeof(mode_value) == TYPE_STRING and mode_value == "radio_absolute" and typeof(value.get("throttle")) == TYPE_DICTIONARY and value.throttle.get("range_kind") != "absolute":
		errors.append("radio_absolute throttle must use an absolute range")
	if typeof(value.get("aux")) != TYPE_DICTIONARY:
		errors.append("aux must be a Dictionary")
	else:
		var aux: Dictionary = value.aux
		if aux.has("smoke") and not SmokeAux.valid_binding(aux.smoke, axes.keys()):
			errors.append("aux.smoke is invalid or overlaps a flight axis")
	return {"ok": errors.is_empty(), "errors": errors}


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
