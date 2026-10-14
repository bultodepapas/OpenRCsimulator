extends RefCounted

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
	{"id": "camera_cycle", "label": "Cycle camera", "context": "flight", "mode": "press"},
	{"id": "view_reset", "label": "Reset view", "context": "flight", "mode": "press"},
	{"id": "trim_left", "label": "Trim left", "context": "flight", "mode": "press"},
	{"id": "trim_right", "label": "Trim right", "context": "flight", "mode": "press"},
	{"id": "trim_up", "label": "Trim up", "context": "flight", "mode": "press"},
	{"id": "trim_down", "label": "Trim down", "context": "flight", "mode": "press"},
	{"id": "overlay_preset", "label": "Cycle flight overlays", "context": "flight", "mode": "press"},
	{"id": "throttle_cut", "label": "Throttle cut (hold)", "context": "flight", "mode": "hold"},
	{"id": "calibrate", "label": "Calibrate controller", "context": "menu", "mode": "press"},
]

const _DEFINITIONS: Dictionary = {
	"accept": {"label": "Accept / launch", "context": "menu", "mode": "press"},
	"back": {"label": "Back / cancel", "context": "menu", "mode": "press"},
	"navigate_up": {"label": "Navigate up", "context": "menu", "mode": "press"},
	"navigate_down": {"label": "Navigate down", "context": "menu", "mode": "press"},
	"navigate_left": {"label": "Navigate left", "context": "menu", "mode": "press"},
	"navigate_right": {"label": "Navigate right", "context": "menu", "mode": "press"},
	"pause": {"label": "Pause / resume", "context": "both", "mode": "press"},
	"camera_cycle": {"label": "Cycle camera", "context": "flight", "mode": "press"},
	"view_reset": {"label": "Reset view", "context": "flight", "mode": "press"},
	"trim_left": {"label": "Trim left", "context": "flight", "mode": "press"},
	"trim_right": {"label": "Trim right", "context": "flight", "mode": "press"},
	"trim_up": {"label": "Trim up", "context": "flight", "mode": "press"},
	"trim_down": {"label": "Trim down", "context": "flight", "mode": "press"},
	"overlay_preset": {"label": "Cycle flight overlays", "context": "flight", "mode": "press"},
	"throttle_cut": {"label": "Throttle cut (hold)", "context": "flight", "mode": "hold"},
	"calibrate": {"label": "Calibrate controller", "context": "menu", "mode": "press"},
}


## Defaults follow the common Xbox / DualSense face-button convention. Device IDs are
## connection handles and are deliberately never stored in profile bindings.
static func default_bindings(_device_id: int = -1) -> Dictionary:
	return {
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


## Validate shape, require a back and pause recovery path, and reject collisions whose contexts overlap.
static func validate(bindings: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	for action_id in ["back", "pause"]:
		if not bindings.has(action_id) or not _valid_binding(bindings[action_id]):
			errors.append("Missing recovery binding: %s" % action_id)
	for action_id: Variant in bindings:
		if not _DEFINITIONS.has(str(action_id)):
			errors.append("Unknown action: %s" % str(action_id))
		elif not _valid_binding(bindings[action_id]):
			errors.append("Invalid binding: %s" % str(action_id))
	var ids: Array = bindings.keys()
	for i in ids.size():
		var left_id := str(ids[i])
		if not _DEFINITIONS.has(left_id) or not _valid_binding(bindings[ids[i]]):
			continue
		for j in range(i + 1, ids.size()):
			var right_id := str(ids[j])
			if not _DEFINITIONS.has(right_id) or not _valid_binding(bindings[ids[j]]):
				continue
			if _contexts_overlap(_DEFINITIONS[left_id].context, _DEFINITIONS[right_id].context) \
					and _same_binding(bindings[ids[i]], bindings[ids[j]]):
				errors.append("Binding conflict: %s and %s" % [left_id, right_id])
	return {"ok": errors.is_empty(), "errors": errors}


## Store an InputEvent as profile-safe data. No current device ID is persisted.
static func binding_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
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
		if not button_event.pressed:
			return {}
		return {"type": "button", "button": button_event.button_index}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) >= 0.65:
			return {"type": "axis", "axis": motion.axis, "sign": 1 if motion.axis_value > 0.0 else -1, "threshold": 0.65}
	return {}


static func binding_text(binding: Dictionary) -> String:
	match str(binding.get("type", "")):
		"key":
			var keycode := int(binding.get("physical_keycode", 0))
			if keycode == 0:
				keycode = int(binding.get("keycode", 0))
			return OS.get_keycode_string(keycode) if keycode != 0 else TranslationServer.translate("Keyboard key")
		"button":
			return _button_name(int(binding.get("button", -1)))
		"axis":
			var sign_text := "+" if int(binding.get("sign", binding.get("direction", 1))) > 0 else "−"
			return TranslationServer.translate("Axis %d %s") % [int(binding.get("axis", -1)), sign_text]
	return TranslationServer.translate("Unbound")


## Returns semantic action IDs for one event. Joypad events from every other device are ignored.
## `context` is `flight`, `menu`, or `both`; keyboard events remain available to the caller's own route.
static func resolve_event(event: InputEvent, bindings: Dictionary, selected_device_id: int, context := "flight") -> PackedStringArray:
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
	for action_id: Variant in bindings:
		var id := str(action_id)
		if not _DEFINITIONS.has(id) or not _context_applies(str(_DEFINITIONS[id].context), context):
			continue
		if matches_binding(bindings[action_id], event, selected_device_id):
			resolved.append(id)
	return resolved


static func matches_binding(binding: Dictionary, event: InputEvent, selected_device_id: int) -> bool:
	match str(binding.get("type", "")):
		"key":
			if not event is InputEventKey:
				return false
			var key_event := event as InputEventKey
			var physical := int(binding.get("physical_keycode", 0))
			var logical := int(binding.get("keycode", 0))
			return ((physical != 0 and key_event.physical_keycode == physical) or (logical != 0 and key_event.keycode == logical)) \
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
			var direction := 1 if motion.axis_value > 0.0 else -1
			return motion.axis == int(binding.get("axis", -1)) and direction == int(binding.get("sign", binding.get("direction", 0))) \
				and absf(motion.axis_value) >= float(binding.get("threshold", 0.65))
	return false


static func action_definition(action_id: String) -> Dictionary:
	return _DEFINITIONS.get(action_id, {}).duplicate(true)


static func _valid_binding(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var binding: Dictionary = value
	match str(binding.get("type", "")):
		"key":
			return int(binding.get("physical_keycode", 0)) != 0 or int(binding.get("keycode", 0)) != 0
		"button":
			return int(binding.get("button", -1)) >= 0 and int(binding.get("button", -1)) < JOY_BUTTON_MAX
		"axis":
			var threshold := float(binding.get("threshold", 0.65))
			var sign := int(binding.get("sign", binding.get("direction", 0)))
			return int(binding.get("axis", -1)) >= 0 and int(binding.get("axis", -1)) < JOY_AXIS_MAX \
				and absf(sign) == 1 and threshold > 0.0 and threshold <= 1.0
	return false


static func _same_binding(left: Dictionary, right: Dictionary) -> bool:
	if left.type != right.type:
		return false
	match str(left.type):
		"key":
			var left_physical := int(left.get("physical_keycode", 0))
			var right_physical := int(right.get("physical_keycode", 0))
			if left_physical != 0 and right_physical != 0:
				return left_physical == right_physical
			return int(left.get("keycode", 0)) == int(right.get("keycode", 0))
		"button":
			return int(left.get("button", -1)) == int(right.get("button", -2))
		"axis":
			return int(left.get("axis", -1)) == int(right.get("axis", -2)) \
				and int(left.get("sign", left.get("direction", 0))) == int(right.get("sign", right.get("direction", 2)))
	return false


static func _contexts_overlap(left: String, right: String) -> bool:
	return left == "both" or right == "both" or left == right


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
