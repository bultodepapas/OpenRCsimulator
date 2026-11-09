extends RefCounted
## Radio menu eligibility and deliberate physical verification. No storage or UI dependencies.

const AXES := 10
const NAV_THRESHOLD := 0.65
const NAV_RELEASE := 0.4
const CENTER_THRESHOLD := 0.2
const VERIFY_STABLE_SECONDS := 0.15
const CHANNELS := ["roll", "pitch", "yaw", "throttle"]
const CHANNEL_FIELDS := ["axis", "min", "center", "max", "invert", "range_kind"]
const COMMANDS := ["accept", "back", "pause"]


## Exact inputs on which physical verification depends; presentation and expo do not affect it.
static func mapping_fingerprint(profile: Dictionary) -> Dictionary:
	if not profile.get("association", {}) is Dictionary: return {}
	var association := {}
	for key: String in ["guid", "vendor_id", "product_id", "serial_number"]:
		if profile.get("association", {}).has(key): association[key] = profile.association[key]
	var has_serial: bool = typeof(association.get("serial_number")) == TYPE_STRING and not association.serial_number.is_empty()
	var has_usb: bool = typeof(association.get("guid")) == TYPE_STRING and not association.guid.is_empty() \
		and typeof(association.get("vendor_id")) == TYPE_INT and association.vendor_id > 0 \
		and typeof(association.get("product_id")) == TYPE_INT and association.product_id > 0
	if not has_serial and not has_usb and profile.get("association", {}).has("legacy_device_key"):
		association["legacy_device_key"] = profile.association.legacy_device_key
	var result := {"kind": profile.get("kind"), "throttle_mode": profile.get("throttle_mode"),
		"association": association}
	for name: String in CHANNELS:
		var value: Variant = profile.get(name)
		if not value is Dictionary:
			return {}
		var channel: Dictionary = value
		var fields := {}
		for field: String in CHANNEL_FIELDS:
			if not channel.has(field): return {}
			fields[field] = channel[field]
		result[name] = fields
	return result


static func action_fingerprint(profile: Dictionary) -> Dictionary:
	var actions: Variant = profile.get("actions")
	if not actions is Dictionary: return {}
	var result := {}
	for name: String in COMMANDS:
		var binding: Variant = actions.get(name)
		if not binding is Dictionary: return {}
		result[name] = binding.duplicate(true)
	return result


## Disabled/absent navigation remains a valid ordinary profile.
static func validate(profile: Dictionary) -> Dictionary:
	var nav: Variant = profile.get("ui_navigation")
	if nav == null: return {"ok": true, "errors": []}
	if not nav is Dictionary: return {"ok": false, "errors": ["ui_navigation must be a Dictionary"]}
	if typeof(nav.get("enabled")) != TYPE_BOOL:
		return {"ok": false, "errors": ["ui_navigation.enabled must be a boolean"]}
	if not nav.enabled: return {"ok": true, "errors": []}
	var errors := _candidate_errors(profile)
	if typeof(nav.get("version")) != TYPE_INT or nav.version != 1:
		errors.append("ui_navigation.version must be 1")
	if typeof(nav.get("horizontal")) != TYPE_STRING or typeof(nav.get("vertical")) != TYPE_STRING \
			or nav.get("horizontal") != "roll" or nav.get("vertical") != "pitch":
		errors.append("ui_navigation requires roll horizontal and pitch vertical")
	if not nav.get("verified_mapping") is Dictionary or nav.get("verified_mapping") != mapping_fingerprint(profile):
		errors.append("radio menu mapping verification is missing or stale")
	if not nav.get("verified_actions") is Dictionary or nav.get("verified_actions") != action_fingerprint(profile):
		errors.append("radio menu action verification is missing or stale")
	return {"ok": errors.is_empty(), "errors": errors}


static func is_verified(profile: Dictionary) -> bool:
	var nav: Variant = profile.get("ui_navigation")
	return nav is Dictionary and typeof(nav.get("enabled")) == TYPE_BOOL and nav.enabled and bool(validate(profile).ok)


## The caller must only invoke this after its current-connection challenge reports done.
static func verified_profile(profile: Dictionary) -> Dictionary:
	if not _candidate_errors(profile).is_empty(): return {}
	var result := profile.duplicate(true)
	result["ui_navigation"] = {"version": 1, "enabled": true, "horizontal": "roll", "vertical": "pitch",
		"verified_mapping": mapping_fingerprint(profile), "verified_actions": action_fingerprint(profile)}
	return result


static func verification(profile: Dictionary) -> RefCounted:
	return Verification.new(profile, _candidate_errors, normalized, axis_action_active, mapping_fingerprint, action_fingerprint)


## Per-side centered calibration without gamepad deadzone or expo.
static func normalized(raw: float, channel: Dictionary) -> float:
	if not is_finite(raw) or not _valid_channel(channel, true): return 0.0
	var lo := float(channel.min)
	var center := float(channel.center)
	var hi := float(channel.max)
	var amount := (raw - center) / (hi - center) if raw >= center else (raw - center) / (center - lo)
	amount = clampf(amount, -1.0, 1.0)
	return -amount if channel.invert else amount


## Axis shortcuts use their saved raw threshold or calibrated OFF/ON range.
static func axis_action_active(raw: float, binding: Dictionary, was_active := false) -> bool:
	if not is_finite(raw) or not _valid_physical_binding(binding) or binding.get("type") != "axis": return false
	var threshold := float(binding.get("threshold", 0.65))
	if was_active: threshold = maxf(threshold * 0.5, threshold - 0.15)
	var amount: float
	if binding.has("off"):
		amount = clampf((raw - float(binding.off)) / (float(binding.on) - float(binding.off)), 0.0, 1.0)
	else:
		amount = raw * float(binding.get("sign", binding.get("direction", 0)))
	return amount >= threshold


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _valid_channel(value: Variant, centered: bool) -> bool:
	if not value is Dictionary: return false
	if typeof(value.get("axis")) != TYPE_INT or value.axis < 0 or value.axis >= AXES: return false
	if typeof(value.get("invert")) != TYPE_BOOL: return false
	if typeof(value.get("range_kind")) != TYPE_STRING or value.range_kind != ("centered" if centered else "absolute"): return false
	for field: String in ["min", "center", "max"]:
		if not _number(value.get(field)) or absf(float(value[field])) > 1.0: return false
	var lo := float(value.min)
	var center := float(value.center)
	var hi := float(value.max)
	return lo < center and center < hi if centered else lo < hi and lo <= center and center <= hi


static func _valid_physical_binding(value: Variant) -> bool:
	if not value is Dictionary or typeof(value.get("type")) != TYPE_STRING: return false
	if value.type == "button":
		return typeof(value.get("button")) == TYPE_INT and value.button >= 0 and value.button < JOY_BUTTON_MAX
	if value.type != "axis" or typeof(value.get("axis")) != TYPE_INT or value.axis < 0 or value.axis >= AXES:
		return false
	var sign_value: Variant = value.get("sign", value.get("direction"))
	if typeof(sign_value) != TYPE_INT or sign_value not in [-1, 1]: return false
	if value.has("sign") and value.has("direction") \
			and (typeof(value.direction) != TYPE_INT or value.sign != value.direction): return false
	var threshold: Variant = value.get("threshold", 0.65)
	if not _number(threshold) or float(threshold) <= 0.0 or float(threshold) > 1.0: return false
	if value.has("off") or value.has("on"):
		if not _number(value.get("off")) or not _number(value.get("on")) or typeof(value.get("invert")) != TYPE_BOOL: return false
		var off := float(value.off)
		var on := float(value.on)
		if absf(off) > 1.0 or absf(on) > 1.0 or absf(on - off) < 0.5 or value.invert != (on < off): return false
	return true


static func _candidate_errors(profile: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not profile.get("association", {}) is Dictionary:
		errors.append("radio menu association must be a Dictionary")
	if typeof(profile.get("kind")) != TYPE_STRING or typeof(profile.get("throttle_mode")) != TYPE_STRING \
			or profile.get("kind") != "radio" or profile.get("throttle_mode") != "radio_absolute":
		errors.append("radio menu navigation requires a radio with absolute throttle")
	var used_axes := {}
	for name: String in CHANNELS:
		var channel: Variant = profile.get(name)
		if not _valid_channel(channel, name != "throttle"):
			errors.append("invalid calibrated channel: " + name)
			continue
		if used_axes.has(channel.axis):
			errors.append("radio primary controls must use distinct axes")
		used_axes[channel.axis] = true
	var actions: Variant = profile.get("actions")
	if not actions is Dictionary:
		errors.append("radio menu actions are missing")
		return errors
	var sources := {}
	for name: String in COMMANDS:
		var binding: Variant = actions.get(name)
		if not _valid_physical_binding(binding):
			errors.append("radio menu action needs a physical button or axis: " + name)
			continue
		var source := "%s:%d" % [binding.type, int(binding.button if binding.type == "button" else binding.axis)]
		if sources.has(source): errors.append("radio menu actions must use distinct physical sources")
		sources[source] = true
		if binding.type == "axis" and used_axes.has(binding.axis):
			errors.append("radio menu actions cannot use primary flight axes")
	return errors


class Verification extends RefCounted:
	const STEPS := ["center", "right", "center_after_right", "left", "center_after_left", "down", "center_after_down", "up", "center_after_up", "accept_on", "accept_off", "back_on", "back_off", "pause_on", "pause_off"]
	const INSTRUCTIONS := {
		"center": "Center roll and pitch and release Accept, Back, and Pause.",
		"right": "Move the roll stick RIGHT and hold it.",
		"center_after_right": "Return roll and pitch to center.",
		"left": "Move the roll stick LEFT and hold it.",
		"center_after_left": "Return roll and pitch to center.",
		"down": "Move the pitch stick DOWN and hold it.",
		"center_after_down": "Return roll and pitch to center.",
		"up": "Move the pitch stick UP and hold it.",
		"center_after_up": "Return roll and pitch to center.",
		"accept_on": "Release Accept, then press it.", "accept_off": "Release Accept.",
		"back_on": "Release Back, then press it.", "back_off": "Release Back.",
		"pause_on": "Release Pause, then press it.", "pause_off": "Release Accept, Back, and Pause, then center roll and pitch.",
	}
	var _profile: Dictionary
	var _index := 0
	var _stable := 0.0
	var _matched_previous := false
	var _command_off_seen := false
	var _error := ""
	var _normalize: Callable
	var _axis_active: Callable
	var _mapping_fingerprint: Callable
	var _action_fingerprint: Callable

	func _init(profile: Dictionary, validate_fn: Callable, normalize_fn: Callable, axis_active_fn: Callable,
			mapping_fn: Callable, action_fn: Callable) -> void:
		_profile = profile.duplicate(true)
		_normalize = normalize_fn
		_axis_active = axis_active_fn
		_mapping_fingerprint = mapping_fn
		_action_fingerprint = action_fn
		var errors: Array[String] = validate_fn.call(profile)
		if not errors.is_empty(): _error = "; ".join(errors)

	func instruction() -> String:
		return "" if _index >= STEPS.size() else str(INSTRUCTIONS[STEPS[_index]])

	## Reject completion if the draft's verified inputs changed during the modal challenge.
	func matches(profile: Dictionary) -> bool:
		return _mapping_fingerprint.call(profile) == _mapping_fingerprint.call(_profile) \
			and _action_fingerprint.call(profile) == _action_fingerprint.call(_profile)

	func sample(axes: PackedFloat64Array, buttons: Dictionary, delta: float) -> Dictionary:
		if not _error.is_empty(): return _result()
		if _index >= STEPS.size(): return _result()
		if axes.size() != AXES or not is_finite(delta) or delta < 0.0 or delta > 1.0:
			_error = "Invalid or interrupted radio menu verification."
			return _result()
		for value: float in axes:
			if not is_finite(value) or absf(value) > 1.0:
				_error = "Invalid or interrupted radio menu verification."
				return _result()
		for name: String in COMMANDS:
			var binding: Dictionary = _profile.actions[name]
			if binding.type == "button" and buttons.has(binding.button) and typeof(buttons[binding.button]) != TYPE_BOOL:
				_error = "Invalid radio button sample."
				return _result()
		var horizontal: float = _normalize.call(axes[int(_profile.roll.axis)], _profile.roll)
		var vertical: float = _normalize.call(axes[int(_profile.pitch.axis)], _profile.pitch)
		var step: String = STEPS[_index]
		var matched := false
		if step.begins_with("center"):
			matched = absf(horizontal) <= CENTER_THRESHOLD and absf(vertical) <= CENTER_THRESHOLD
			if step == "center":
				for name: String in COMMANDS:
					matched = matched and _off(name, axes, buttons)
		elif step == "right": matched = horizontal >= NAV_THRESHOLD and absf(vertical) <= NAV_RELEASE
		elif step == "left": matched = horizontal <= -NAV_THRESHOLD and absf(vertical) <= NAV_RELEASE
		elif step == "down": matched = vertical >= NAV_THRESHOLD and absf(horizontal) <= NAV_RELEASE
		elif step == "up": matched = vertical <= -NAV_THRESHOLD and absf(horizontal) <= NAV_RELEASE
		else:
			var parts := step.split("_")
			var command: String = parts[0]
			if parts[1] == "on":
				if not _command_off_seen:
					_command_off_seen = _off(command, axes, buttons)
					return _result()
				matched = _on(command, axes, buttons)
			else:
				matched = _off(command, axes, buttons)
				if step == "pause_off":
					matched = matched and absf(horizontal) <= CENTER_THRESHOLD and absf(vertical) <= CENTER_THRESHOLD
					for name: String in COMMANDS:
						matched = matched and _off(name, axes, buttons)
		# One isolated sample cannot prove a position persisted for the previous frame.
		_stable = _stable + delta if matched and _matched_previous else 0.0
		_matched_previous = matched
		if _stable >= VERIFY_STABLE_SECONDS:
			_index += 1
			_stable = 0.0
			_matched_previous = false
			_command_off_seen = false
		return _result()

	func _on(name: String, axes: PackedFloat64Array, buttons: Dictionary) -> bool:
		var binding: Dictionary = _profile.actions[name]
		if binding.type == "button": return buttons.has(binding.button) and buttons[binding.button] == true
		return _axis_active.call(axes[binding.axis], binding, false)

	func _off(name: String, axes: PackedFloat64Array, buttons: Dictionary) -> bool:
		var binding: Dictionary = _profile.actions[name]
		if binding.type == "button": return buttons.has(binding.button) and buttons[binding.button] == false
		return not _axis_active.call(axes[binding.axis], binding, true)

	func _result() -> Dictionary:
		return {"done": _index >= STEPS.size() and _error.is_empty(), "error": _error,
			"step": "done" if _index >= STEPS.size() else STEPS[_index], "index": _index, "total": STEPS.size()}
