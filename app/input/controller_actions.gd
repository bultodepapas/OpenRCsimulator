extends RefCounted

const SmokeAux := preload("res://input/smoke_aux.gd")
const OPTIONAL_ACTION_IDS: PackedStringArray = [
	"smoke_toggle", "flaps_up", "flaps_down", "flaps_cycle", "gear_toggle",
	"camera_previous", "camera_pilot", "camera_chase", "camera_orbit",
	"camera_zoom_in", "camera_zoom_out", "camera_auto_zoom", "lights_cycle", "rates_toggle",
	"helicopter_arm", "helicopter_hold", "helicopter_mode", "helicopter_trainer",
	"restart_flight",
]
const AUX_CHANNEL_IDS: PackedStringArray = ["smoke", "flaps", "gear"]
## Product defaults on standardized gamepads, scoped to implemented aircraft equipment.
## Profile/setup validation reserves equipment candidates; flight passes its actual capabilities.
const AUTOMATIC_BUTTONS := {
	"gear_toggle": {"channel": "gear", "button": JOY_BUTTON_B},
	"smoke_toggle": {"channel": "smoke", "button": JOY_BUTTON_RIGHT_SHOULDER},
	"flaps_cycle": {"channel": "flaps", "button": JOY_BUTTON_A},
	"restart_flight": {"channel": "", "button": JOY_BUTTON_BACK},
	"helicopter_arm": {"channel": "helicopter", "button": JOY_BUTTON_A},
	"helicopter_hold": {"channel": "helicopter", "button": JOY_BUTTON_B},
	"helicopter_mode": {"channel": "helicopter", "button": JOY_BUTTON_RIGHT_SHOULDER},
	"helicopter_trainer": {"channel": "helicopter", "button": JOY_BUTTON_LEFT_STICK},
}
const SUPPORTED_AUX := {"gear": true, "smoke": true, "flaps": true}
const HELICOPTER_CAPABILITIES := {"helicopter": true}
static var _definition_cache: Dictionary = {}

## Semantic gamepad actions are data, not synthetic keyboard events. The owning input router
## decides what each returned action means in its current flight or menu context.
const ACTIONS: Array[Dictionary] = [
	{"id": "accept", "label": "Accept / launch", "context": "menu", "mode": "press"},
	{"id": "back", "label": "Back / cancel", "context": "menu", "mode": "press"},
	{"id": "navigate_up", "label": "Navigate up", "context": "menu", "mode": "press"},
	{"id": "navigate_down", "label": "Navigate down", "context": "menu", "mode": "press"},
	{"id": "navigate_left", "label": "Navigate left", "context": "menu", "mode": "press"},
	{"id": "navigate_right", "label": "Navigate right", "context": "menu", "mode": "press"},
	{"id": "pause", "label": "Pause / resume", "context": "both", "mode": "press"},
	{"id": "restart_flight", "label": "Restart flight", "context": "flight", "mode": "press"},
	{"id": "camera_cycle", "label": "Cycle camera", "context": "flight", "mode": "press"},
	{"id": "view_reset", "label": "Reset view", "context": "flight", "mode": "press"},
	{"id": "trim_left", "label": "Trim left", "context": "flight", "mode": "press"},
	{"id": "trim_right", "label": "Trim right", "context": "flight", "mode": "press"},
	{"id": "trim_up", "label": "Trim up", "context": "flight", "mode": "press"},
	{"id": "trim_down", "label": "Trim down", "context": "flight", "mode": "press"},
	{"id": "overlay_preset", "label": "Cycle flight overlays", "context": "flight", "mode": "press"},
	{"id": "throttle_cut", "label": "Throttle cut (hold)", "context": "flight", "mode": "hold"},
	{"id": "calibrate", "label": "Calibrate controller", "context": "menu", "mode": "press"},
	{"id": "smoke_toggle", "label": "Toggle smoke pump", "context": "flight", "mode": "press"},
	{"id": "flaps_up", "label": "Flaps up", "context": "flight", "mode": "press"},
	{"id": "flaps_down", "label": "Flaps down", "context": "flight", "mode": "press"},
	{"id": "flaps_cycle", "label": "Cycle flaps", "context": "flight", "mode": "press"},
	{"id": "gear_toggle", "label": "Toggle landing gear", "context": "flight", "mode": "press"},
	{"id": "camera_previous", "label": "Previous camera", "context": "flight", "mode": "press"},
	{"id": "camera_pilot", "label": "Pilot camera", "context": "flight", "mode": "press"},
	{"id": "camera_chase", "label": "Chase camera", "context": "flight", "mode": "press"},
	{"id": "camera_orbit", "label": "Orbit camera", "context": "flight", "mode": "press"},
	{"id": "camera_zoom_in", "label": "Camera zoom in", "context": "flight", "mode": "press"},
	{"id": "camera_zoom_out", "label": "Camera zoom out", "context": "flight", "mode": "press"},
	{"id": "camera_auto_zoom", "label": "Toggle auto camera zoom", "context": "flight", "mode": "press"},
	{"id": "lights_cycle", "label": "Cycle lights", "context": "flight", "mode": "press"},
	{"id": "rates_toggle", "label": "Dual rates: normal / high", "context": "flight", "mode": "press"},
	{"id": "helicopter_arm", "label": "Helicopter: arm / disarm", "context": "flight", "mode": "press"},
	{"id": "helicopter_hold", "label": "Helicopter: toggle rotor hold", "context": "flight", "mode": "press"},
	{"id": "helicopter_mode", "label": "Helicopter: normal / idle-up", "context": "flight", "mode": "press"},
	{"id": "helicopter_trainer", "label": "Helicopter: toggle trainer", "context": "flight", "mode": "press"},
]


## Defaults follow the common Xbox / DualSense face-button convention. Device IDs are
## connection handles and are deliberately never stored in profile bindings.
static func default_bindings(_device_id: int = -1) -> Dictionary:
	var bindings := {
		"accept": {"type": "button", "button": JOY_BUTTON_A},
		"back": {"type": "button", "button": JOY_BUTTON_B},
		"navigate_up": {"type": "button", "button": JOY_BUTTON_DPAD_UP},
		"navigate_down": {"type": "button", "button": JOY_BUTTON_DPAD_DOWN},
		"navigate_left": {"type": "button", "button": JOY_BUTTON_DPAD_LEFT},
		"navigate_right": {"type": "button", "button": JOY_BUTTON_DPAD_RIGHT},
		"pause": {"type": "button", "button": JOY_BUTTON_START},
		"camera_cycle": {"type": "button", "button": JOY_BUTTON_Y},
		"view_reset": {"type": "button", "button": JOY_BUTTON_RIGHT_STICK},
		"trim_left": {"type": "button", "button": JOY_BUTTON_DPAD_LEFT},
		"trim_right": {"type": "button", "button": JOY_BUTTON_DPAD_RIGHT},
		"trim_up": {"type": "button", "button": JOY_BUTTON_DPAD_UP},
		"trim_down": {"type": "button", "button": JOY_BUTTON_DPAD_DOWN},
		"overlay_preset": {"type": "button", "button": JOY_BUTTON_X},
		"throttle_cut": {"type": "button", "button": JOY_BUTTON_LEFT_SHOULDER},
		"calibrate": {"type": "button", "button": JOY_BUTTON_LEFT_STICK},
	}
	for action_id in OPTIONAL_ACTION_IDS:
		bindings[action_id] = {"type": "unbound"}
	return bindings


## Explicit overrides are essential: an empty map inherits gamepad buttons.
## Radios keep independent keyboard recovery without assigning maintained switches.
static func clean_radio_bindings() -> Dictionary:
	var bindings: Dictionary = {}
	for definition in ACTIONS:
		bindings[str(definition.id)] = {"type": "unbound"}
	bindings.back = {"type": "key", "physical_keycode": KEY_BACKSPACE}
	bindings.pause = {"type": "key", "physical_keycode": KEY_ESCAPE}
	return bindings


## Validate shape, require a back and pause recovery path, and reject collisions whose contexts overlap.
static func validate(bindings: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var issues: Array[Dictionary] = []
	var definitions := _definition_map()
	for action_id in ["back", "pause"]:
		if not bindings.has(action_id) or not _valid_binding(bindings[action_id]) or _is_unbound(bindings.get(action_id)):
			var error: String = "Missing recovery binding: %s" % action_id
			errors.append(error)
			_append_issue(issues, "recovery_binding_missing", ["actions.%s" % action_id], error)
	for action_id: Variant in bindings:
		if not definitions.has(str(action_id)):
			var error: String = "Unknown action: %s" % str(action_id)
			errors.append(error)
			_append_issue(issues, "action_unknown", ["actions.%s" % str(action_id)], error)
		elif not _valid_binding(bindings[action_id]):
			var error: String = "Invalid binding: %s" % str(action_id)
			errors.append(error)
			_append_issue(issues, "binding_invalid", ["actions.%s" % str(action_id)], error)
	var ids: Array = bindings.keys()
	for i in ids.size():
		var left_id := str(ids[i])
		if not definitions.has(left_id) or not _valid_binding(bindings[ids[i]]) or _is_unbound(bindings[ids[i]]):
			continue
		for j in range(i + 1, ids.size()):
			var right_id := str(ids[j])
			if not definitions.has(right_id) or not _valid_binding(bindings[ids[j]]) or _is_unbound(bindings[ids[j]]):
				continue
			if _contexts_overlap(definitions[left_id].context, definitions[right_id].context) \
					and _same_binding(bindings[ids[i]], bindings[ids[j]]):
				var error: String = "Binding conflict: %s and %s" % [left_id, right_id]
				errors.append(error)
				_append_issue(issues, "binding_conflict", ["actions.%s" % left_id, "actions.%s" % right_id], error)
	return {"ok": errors.is_empty(), "errors": errors, "issues": issues}


## Resolve saved overrides against the current defaults. Only inherited flight-only defaults
## that alias a configured auxiliary control are silenced; explicit actions and recovery paths stay.
static func effective_bindings(profile: Dictionary, capabilities: Dictionary = SUPPORTED_AUX) -> Dictionary:
	var bindings := default_bindings()
	var explicit_actions: Variant = _dict_value(profile, "actions", {})
	var explicit_ids: Dictionary = {}
	if explicit_actions is Dictionary:
		for action_key: Variant in explicit_actions:
			var action_id := str(action_key)
			var value: Variant = explicit_actions[action_key]
			bindings[action_id] = value.duplicate(true) if value is Dictionary or value is Array else value
			explicit_ids[action_id] = true
	var definitions := _definition_map()
	var aux_bindings := _configured_aux_bindings(profile)
	for action_key: Variant in bindings.keys():
		var action_id := str(action_key)
		if not definitions.has(action_id) or not _valid_binding(bindings[action_key]) or _is_unbound(bindings[action_key]):
			continue
		if definitions[action_id].context != "flight" or explicit_ids.has(action_id):
			continue
		for aux_entry in aux_bindings:
			if _same_aux_control(bindings[action_key], aux_entry.binding):
				bindings[action_key] = {"type": "unbound"}
				break
	# Legacy radios and custom joysticks may have AUX on SDL button 6, which is
	# also the inherited gamepad Pause button. Keep the radio AUX assignment and
	# retain recovery through Escape; an explicitly mapped Pause is never changed.
	var kind := str(_dict_value(profile, "kind", ""))
	if kind in ["radio", "joystick"] and not explicit_ids.has("pause"):
		for aux_entry in aux_bindings:
			if _same_aux_control(bindings.pause, aux_entry.binding):
				bindings.pause = {"type": "key", "physical_keycode": KEY_ESCAPE}
				break
	_add_automatic_buttons(profile, bindings, explicit_ids, aux_bindings, capabilities)
	return bindings


## Additive only: a saved Clear is intentional, and AUX/other actions always own their source.
## Unknown joysticks/radios have no standardized button layout and never gain inferred buttons.
static func _add_automatic_buttons(profile: Dictionary, bindings: Dictionary, explicit_ids: Dictionary,
		aux_bindings: Array[Dictionary], capabilities: Dictionary) -> void:
	if str(_dict_value(profile, "kind", "")) != "gamepad":
		return
	var definitions := _definition_map()
	for action_id: String in AUTOMATIC_BUTTONS:
		var entry: Dictionary = AUTOMATIC_BUTTONS[action_id]
		if explicit_ids.has(action_id) or (not str(entry.channel).is_empty() and not bool(capabilities.get(entry.channel, false))):
			continue
		var candidate := {"type": "button", "button": int(entry.button)}
		var reserved := false
		for aux_entry in aux_bindings:
			if aux_entry.name == entry.channel or _same_aux_control(candidate, aux_entry.binding):
				reserved = true
		for other_id: Variant in bindings:
			if not definitions.has(str(other_id)) or not _valid_binding(bindings[other_id]) or _is_unbound(bindings[other_id]):
				continue
			if _contexts_overlap("flight", str(definitions[other_id].context)) and _same_binding(candidate, bindings[other_id]):
				reserved = true
		if not reserved:
			bindings[action_id] = candidate


## Validate the whole calibrated profile's semantic bindings and reserved AUX sources.
## `bindings` in the result is the merged action map suitable for the input router.
static func validate_profile_bindings(profile: Dictionary, capabilities: Dictionary = SUPPORTED_AUX) -> Dictionary:
	var errors: Array[String] = []
	var issues: Array[Dictionary] = []
	var actions_value: Variant = _dict_value(profile, "actions", {})
	if not actions_value is Dictionary:
		var error: String = "actions must be a dictionary"
		errors.append(error)
		_append_issue(issues, "profile_invalid", ["actions"], error)
	var aux_value: Variant = _dict_value(profile, "aux", {})
	if not aux_value is Dictionary:
		var error: String = "aux must be a dictionary"
		errors.append(error)
		_append_issue(issues, "aux_invalid", ["aux"], error)
	var bindings := effective_bindings(profile, capabilities)
	var action_report := validate(bindings)
	for error in action_report.errors:
		_append_error(errors, str(error))
	for issue in action_report.issues:
		issues.append(issue.duplicate(true))
	var flight_axes := SmokeAux.flight_axes(profile)
	var configured_aux: Array[Dictionary] = _configured_aux_bindings(profile)
	if aux_value is Dictionary:
		for aux_id in AUX_CHANNEL_IDS:
			var aux_binding: Variant = _dict_value(aux_value, aux_id, null)
			if _has_key(aux_value, aux_id) and not SmokeAux.valid_binding(aux_binding, flight_axes):
				var error: String = "aux.%s is invalid or overlaps a flight axis" % aux_id
				_append_error(errors, error)
				_append_issue(issues, "aux_invalid", _aux_invalid_paths(str(aux_id), aux_binding, profile), error)
	for i in configured_aux.size():
		for j in range(i + 1, configured_aux.size()):
			if _same_aux_control(configured_aux[i].binding, configured_aux[j].binding):
				var error: String = "AUX binding conflict: aux.%s and aux.%s" % [
					configured_aux[i].name, configured_aux[j].name,
				]
				_append_error(errors, error)
				_append_issue(issues, "aux_conflict", [
					_aux_control_path(configured_aux[i].name, configured_aux[i].binding),
					_aux_control_path(configured_aux[j].name, configured_aux[j].binding),
				], error)
	var definitions := _definition_map()
	for action_key: Variant in bindings:
		var action_id := str(action_key)
		if not definitions.has(action_id):
			continue
		var binding: Variant = bindings[action_key]
		if not _valid_binding(binding) or _is_unbound(binding):
			continue
		var context := str(definitions[action_id].context)
		if context not in ["flight", "both"]:
			continue
		if str(binding.get("type", "")) == "axis" and flight_axes.has(int(binding.axis)):
			var error: String = "Action %s uses primary flight axis %d" % [action_id, int(binding.axis)]
			_append_error(errors, error)
			var axis_paths := _flight_axis_paths(profile, int(binding.axis))
			axis_paths.push_front("actions.%s" % action_id)
			_append_issue(issues, "action_flight_axis_conflict", axis_paths, error)
		for aux_entry in configured_aux:
			if _same_aux_control(binding, aux_entry.binding):
				var error: String = "Action %s conflicts with aux.%s" % [action_id, aux_entry.name]
				_append_error(errors, error)
				_append_issue(issues, "action_aux_source_conflict", [
					"actions.%s" % action_id,
					_aux_control_path(aux_entry.name, aux_entry.binding),
				], error)
		for aux_id in AUX_CHANNEL_IDS:
			if _aux_is_configured(aux_value, aux_id) and _action_aux_semantic_conflict(action_id, aux_id):
				var error: String = "Action %s conflicts with aux.%s" % [action_id, aux_id]
				_append_error(errors, error)
				var aux_binding: Variant = _dict_value(aux_value, aux_id, null)
				_append_issue(issues, "action_aux_conflict", [
					"actions.%s" % action_id,
					_aux_control_path(aux_id, aux_binding),
				], error)
	return {"ok": errors.is_empty(), "errors": errors, "issues": issues, "bindings": bindings}


## Store an InputEvent as profile-safe data. No current device ID is persisted.
static func binding_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo or (key_event.keycode == 0 and key_event.physical_keycode == 0):
			return {}
		return {
			"type": "key",
			"keycode": key_event.keycode,
			"physical_keycode": key_event.physical_keycode,
			"ctrl": key_event.ctrl_pressed,
			"alt": key_event.alt_pressed,
			"shift": key_event.shift_pressed,
			"meta": key_event.meta_pressed,
		}
	if event is InputEventJoypadButton:
		var button_event := event as InputEventJoypadButton
		if not button_event.pressed or button_event.button_index < 0 or button_event.button_index >= JOY_BUTTON_MAX:
			return {}
		return {"type": "button", "button": button_event.button_index}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis >= 0 and motion.axis < JOY_AXIS_MAX and is_finite(motion.axis_value) and absf(motion.axis_value) >= 0.65:
			return {"type": "axis", "axis": motion.axis, "sign": 1 if motion.axis_value > 0.0 else -1, "threshold": 0.65}
	return {}


static func binding_text(binding: Dictionary) -> String:
	match str(binding.get("type", "")):
		"key":
			var keycode := int(binding.get("physical_keycode", 0))
			if keycode == 0:
				keycode = int(binding.get("keycode", 0))
			var parts := PackedStringArray()
			for modifier in ["ctrl", "alt", "shift", "meta"]:
				if bool(binding.get(modifier, false)): parts.append("Ctrl" if modifier == "ctrl" else modifier.capitalize())
			parts.append(OS.get_keycode_string(keycode) if keycode != 0 else TranslationServer.translate("Keyboard key"))
			return "+".join(parts)
		"button":
			return _button_name(int(binding.get("button", -1)))
		"axis":
			var sign_text := "+" if int(binding.get("sign", binding.get("direction", 1))) > 0 else "−"
			return TranslationServer.translate("Axis %d %s") % [int(binding.get("axis", -1)), sign_text]
	return TranslationServer.translate("Unbound")


## Returns semantic action IDs for one event. Joypad events from every other device are ignored.
## `context` is `flight`, `menu`, or `both`; keyboard events remain available to the caller's own route.
static func resolve_event(event: InputEvent, bindings: Dictionary, selected_device_id: int, context := "flight",
		previous_actions: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var resolved := PackedStringArray()
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if selected_device_id < 0 or event.device != selected_device_id:
			return resolved
		if event is InputEventJoypadButton and not (event as InputEventJoypadButton).pressed:
			return resolved
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return resolved
	var definitions := _definition_map()
	for action_id: Variant in bindings:
		var id := str(action_id)
		if not definitions.has(id) or not _context_applies(str(definitions[id].context), context) or not valid_binding(bindings[action_id]):
			continue
		if matches_binding(bindings[action_id], event, selected_device_id, previous_actions.has(id)):
			resolved.append(id)
	return resolved


static func matches_binding(binding: Dictionary, event: InputEvent, selected_device_id: int,
		previously_active: bool = false) -> bool:
	match str(binding.get("type", "")):
		"key":
			if not event is InputEventKey:
				return false
			var key_event := event as InputEventKey
			var physical := int(binding.get("physical_keycode", 0))
			var logical := int(binding.get("keycode", 0))
			return (key_event.physical_keycode == physical if physical != 0 else logical != 0 and key_event.keycode == logical) \
				and key_event.ctrl_pressed == bool(binding.get("ctrl", false)) \
				and key_event.alt_pressed == bool(binding.get("alt", false)) \
				and key_event.shift_pressed == bool(binding.get("shift", false)) \
				and key_event.meta_pressed == bool(binding.get("meta", false))
		"button":
			return event is InputEventJoypadButton and selected_device_id >= 0 and event.device == selected_device_id \
				and event.button_index == int(binding.get("button", -1))
		"axis":
			if not event is InputEventJoypadMotion or selected_device_id < 0 or event.device != selected_device_id:
				return false
			var motion := event as InputEventJoypadMotion
			if not is_finite(motion.axis_value):
				return false
			var direction := 1 if motion.axis_value > 0.0 else -1
			var threshold := float(binding.get("threshold", 0.65))
			if previously_active:
				threshold = maxf(threshold * 0.5, threshold - 0.15)
			return motion.axis == int(binding.get("axis", -1)) and direction == int(binding.get("sign", binding.get("direction", 0))) \
				and absf(motion.axis_value) >= threshold
	return false


static func action_definition(action_id: String) -> Dictionary:
	return _definition_map().get(action_id, {}).duplicate(true)


## Releases and presses share one source, including synthetic logical-only keys.
static func event_source(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return "key:%d" % code if code > 0 else ""
	if event is InputEventJoypadButton and event.button_index >= 0 and event.button_index < JOY_BUTTON_MAX:
		return "%d:button:%d" % [event.device, event.button_index]
	if event is InputEventJoypadMotion and event.axis >= 0 and event.axis < JOY_AXIS_MAX:
		return "%d:axis:%d" % [event.device, event.axis]
	return ""


static func _definition_map() -> Dictionary:
	if _definition_cache.is_empty():
		for definition in ACTIONS:
			_definition_cache[str(definition.id)] = definition
	return _definition_cache


static func _valid_binding(value: Variant) -> bool:
	return valid_binding(value)


## One strict shape contract for the profile loader, setup and direct action API.
static func valid_binding(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or typeof(value.get("type")) != TYPE_STRING:
		return false
	var binding: Dictionary = value
	match binding.type:
		"unbound":
			return binding.size() == 1
		"key":
			var logical: Variant = binding.get("keycode", 0)
			var physical: Variant = binding.get("physical_keycode", 0)
			if typeof(logical) != TYPE_INT or typeof(physical) != TYPE_INT or logical < 0 or physical < 0:
				return false
			if logical == 0 and physical == 0: return false
			for modifier in ["ctrl", "alt", "shift", "meta"]:
				if binding.has(modifier) and typeof(binding[modifier]) != TYPE_BOOL: return false
			return not binding.has("modifiers")
		"button":
			return typeof(binding.get("button")) == TYPE_INT and binding.button >= 0 and binding.button < JOY_BUTTON_MAX
		"axis":
			if typeof(binding.get("axis")) != TYPE_INT or binding.axis < 0 or binding.axis >= JOY_AXIS_MAX: return false
			var direction: Variant = binding.get("sign", binding.get("direction", 0))
			if typeof(direction) != TYPE_INT or direction not in [-1, 1]: return false
			if binding.has("sign") and binding.has("direction") and binding.sign != binding.direction: return false
			var threshold: Variant = binding.get("threshold", 0.65)
			return typeof(threshold) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(threshold)) and threshold > 0.0 and threshold <= 1.0
	return false


static func _same_binding(left: Dictionary, right: Dictionary) -> bool:
	if left.type != right.type:
		return false
	match str(left.type):
		"key":
			for modifier in ["ctrl", "alt", "shift", "meta"]:
				if bool(left.get(modifier, false)) != bool(right.get(modifier, false)): return false
			var left_physical := int(left.get("physical_keycode", 0))
			var right_physical := int(right.get("physical_keycode", 0))
			if left_physical != 0 and right_physical != 0:
				return left_physical == right_physical
			var left_logical := int(left.get("keycode", 0))
			var right_logical := int(right.get("keycode", 0))
			if left_physical != 0: return left_physical == right_logical or (left_logical != 0 and left_logical == right_logical)
			if right_physical != 0: return right_physical == left_logical or (right_logical != 0 and right_logical == left_logical)
			return left_logical == right_logical
		"button":
			return int(left.get("button", -1)) == int(right.get("button", -2))
		"axis":
			return int(left.get("axis", -1)) == int(right.get("axis", -2)) \
				and int(left.get("sign", left.get("direction", 0))) == int(right.get("sign", right.get("direction", 2)))
	return false


static func _contexts_overlap(left: String, right: String) -> bool:
	return left == "both" or right == "both" or left == right


static func _is_unbound(value: Variant) -> bool:
	return value is Dictionary and str(value.get("type", "")) == "unbound"


static func _configured_aux_bindings(profile: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var aux: Variant = _dict_value(profile, "aux", {})
	if not aux is Dictionary:
		return result
	var flight_axes := SmokeAux.flight_axes(profile)
	for aux_id in AUX_CHANNEL_IDS:
		if not _has_key(aux, aux_id):
			continue
		var binding: Variant = _dict_value(aux, aux_id, null)
		if SmokeAux.valid_binding(binding, flight_axes):
			result.append({"name": aux_id, "binding": binding})
	return result


static func _same_aux_control(action_binding: Dictionary, aux_binding: Dictionary) -> bool:
	var action_type := str(action_binding.get("type", ""))
	var aux_type := str(aux_binding.get("type", ""))
	# A detent group reserves every member button, including inactive positions.
	if action_type in ["button", "switch"] and aux_type in ["button", "switch"]:
		var left_buttons: Array = SmokeAux.bound_buttons(action_binding) if action_type == "switch" else [action_binding.get("button", -1)]
		var right_buttons: Array = SmokeAux.bound_buttons(aux_binding) if aux_type == "switch" else [aux_binding.get("button", -2)]
		for button in left_buttons:
			if right_buttons.has(button):
				return true
		return false
	if action_type != aux_type:
		return false
	match action_type:
		"button":
			return int(action_binding.get("button", -1)) == int(aux_binding.get("button", -2))
		"axis":
			# AUX reserves the whole calibrated axis; direction/sign never frees it for an action.
			return int(action_binding.get("axis", -1)) == int(aux_binding.get("axis", -2))
	return false


static func _aux_is_configured(aux: Variant, aux_id: String) -> bool:
	if not aux is Dictionary or not _has_key(aux, aux_id):
		return false
	var value: Variant = _dict_value(aux, aux_id, null)
	return not (value is Dictionary and value.is_empty()) and value != null


static func _action_aux_semantic_conflict(action_id: String, aux_id: String) -> bool:
	match aux_id:
		"smoke":
			return action_id == "smoke_toggle"
		"flaps":
			return action_id in ["flaps_up", "flaps_down", "flaps_cycle"]
		"gear":
			return action_id == "gear_toggle"
	return false


static func _flight_axis_paths(profile: Dictionary, axis: int) -> Array[String]:
	var paths: Array[String] = []
	for channel_name in ["roll", "pitch", "yaw", "throttle"]:
		var channel: Variant = _dict_value(profile, channel_name, null)
		if channel is Dictionary and typeof(channel.get("axis")) == TYPE_INT and int(channel.axis) == axis:
			paths.append("%s.axis" % channel_name)
	return paths


static func _aux_control_path(aux_id: String, binding: Variant) -> String:
	var path := "aux.%s" % aux_id
	if not binding is Dictionary:
		return path
	match str(binding.get("type", "")):
		"axis":
			return path + ".axis"
		"button":
			return path + ".button"
		"switch":
			return path + ".buttons"
	return path


static func _aux_invalid_paths(aux_id: String, binding: Variant, profile: Dictionary) -> Array[String]:
	var root := "aux.%s" % aux_id
	var paths: Array[String] = []
	if not binding is Dictionary:
		return [root]
	match str(binding.get("type", "")):
		"axis":
			var raw_axis: Variant = binding.get("axis")
			if typeof(raw_axis) != TYPE_INT or int(raw_axis) < 0 or int(raw_axis) >= SmokeAux.AXES:
				_append_path(paths, root + ".axis")
			elif _flight_axis_paths(profile, int(raw_axis)).size() > 0:
				_append_path(paths, root + ".axis")
				for flight_path in _flight_axis_paths(profile, int(raw_axis)):
					_append_path(paths, flight_path)
			if typeof(binding.get("invert")) != TYPE_BOOL:
				_append_path(paths, root + ".invert")
			for endpoint in ["off", "on"]:
				var raw_endpoint: Variant = binding.get(endpoint)
				if typeof(raw_endpoint) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw_endpoint)) \
						or float(raw_endpoint) < -1.0 or float(raw_endpoint) > 1.0:
					_append_path(paths, root + "." + endpoint)
			if binding.has("off") and binding.has("on") \
					and typeof(binding.off) in [TYPE_INT, TYPE_FLOAT] and typeof(binding.on) in [TYPE_INT, TYPE_FLOAT]:
				if is_finite(float(binding.off)) and is_finite(float(binding.on)) \
						and absf(float(binding.on) - float(binding.off)) < SmokeAux.MIN_AXIS_SPAN:
					_append_path(paths, root + ".off")
					_append_path(paths, root + ".on")
				if typeof(binding.get("invert")) == TYPE_BOOL and binding.invert != (float(binding.on) < float(binding.off)):
					_append_path(paths, root + ".invert")
		"button":
			var raw_button: Variant = binding.get("button")
			if typeof(raw_button) != TYPE_INT or int(raw_button) < 0 or int(raw_button) >= SmokeAux.MAX_BUTTONS:
				_append_path(paths, root + ".button")
			if typeof(binding.get("mode")) != TYPE_STRING or str(binding.get("mode", "")) not in ["level", "toggle_edge"]:
				_append_path(paths, root + ".mode")
		"switch":
			if typeof(binding.get("invert")) != TYPE_BOOL:
				_append_path(paths, root + ".invert")
			if binding.has("label") and (typeof(binding.label) != TYPE_STRING or binding.label.strip_edges().is_empty() or binding.label.length() > 24):
				_append_path(paths, root + ".label")
			var buttons: Variant = binding.get("buttons")
			if typeof(buttons) != TYPE_ARRAY:
				_append_path(paths, root + ".buttons")
			else:
				var button_ids: Array = SmokeAux._switch_buttons(binding)
				if button_ids.size() not in [2, 3]:
					_append_path(paths, root + ".buttons")
				for i in button_ids.size():
					if typeof(button_ids[i]) != TYPE_INT or int(button_ids[i]) < 0 or int(button_ids[i]) >= SmokeAux.MAX_BUTTONS:
						_append_path(paths, root + ".buttons")
					for j in range(i + 1, button_ids.size()):
						if button_ids[i] == button_ids[j]:
							_append_path(paths, root + ".buttons")
		_:
			_append_path(paths, root)
	if paths.is_empty():
		paths.append(root)
	return paths


static func _append_path(paths: Array[String], path: String) -> void:
	if not paths.has(path):
		paths.append(path)


static func _append_issue(issues: Array[Dictionary], code: String, paths: Array, message: String) -> void:
	var issue_paths: Array[String] = []
	for path in paths:
		issue_paths.append(str(path))
	issues.append({"code": code, "paths": issue_paths, "message": message})


static func _has_key(value: Variant, key: String) -> bool:
	return value is Dictionary and (value.has(key) or value.has(StringName(key)))


static func _dict_value(value: Variant, key: String, fallback: Variant) -> Variant:
	if not value is Dictionary:
		return fallback
	if value.has(key):
		return value[key]
	var string_name := StringName(key)
	return value[string_name] if value.has(string_name) else fallback


static func _append_error(errors: Array[String], message: String) -> void:
	if not errors.has(message):
		errors.append(message)


static func _context_applies(action_context: String, active_context: String) -> bool:
	return action_context == "both" or active_context == "both" or action_context == active_context


static func _button_name(button: int) -> String:
	match button:
		JOY_BUTTON_A:
			return "A / Cross"
		JOY_BUTTON_B:
			return "B / Circle"
		JOY_BUTTON_X:
			return "X / Square"
		JOY_BUTTON_Y:
			return "Y / Triangle"
		JOY_BUTTON_BACK:
			return TranslationServer.translate("Back / Share")
		JOY_BUTTON_START:
			return TranslationServer.translate("Menu / Options")
		JOY_BUTTON_LEFT_STICK:
			return TranslationServer.translate("Left stick press")
		JOY_BUTTON_RIGHT_STICK:
			return TranslationServer.translate("Right stick press")
		JOY_BUTTON_LEFT_SHOULDER:
			return TranslationServer.translate("Left shoulder")
		JOY_BUTTON_RIGHT_SHOULDER:
			return TranslationServer.translate("Right shoulder")
		JOY_BUTTON_DPAD_UP:
			return TranslationServer.translate("D-pad up")
		JOY_BUTTON_DPAD_DOWN:
			return TranslationServer.translate("D-pad down")
		JOY_BUTTON_DPAD_LEFT:
			return TranslationServer.translate("D-pad left")
		JOY_BUTTON_DPAD_RIGHT:
			return TranslationServer.translate("D-pad right")
		_:
			return TranslationServer.translate("Button %d") % button
