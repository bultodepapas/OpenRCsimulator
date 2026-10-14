# A radio flies the airplane; it never navigates menus. A selected gamepad can be bound to
# ui_* actions, but each generated event is limited to one Godot connection handle.
extends RefCounted

static var _selected_gamepad_id := -1
static var _original_action_deadzones: Dictionary = {}
static var _generated_key_events: Dictionary = {}


## Erases joypad events from ui_* actions. Keyboard and mouse navigation remain untouched.
static func isolate_joypads() -> int:
	_selected_gamepad_id = -1
	_restore_action_deadzones()
	var removed := 0
	for action: Variant in _generated_key_events:
		var action_name := str(action)
		if not InputMap.has_action(action_name):
			continue
		for event: Variant in _generated_key_events[action]:
			InputMap.action_erase_event(action_name, event)
			removed += 1
	_generated_key_events.clear()
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
				removed += 1
	return removed


## Routes GUI navigation from exactly one selected gamepad. Accept/back and D-pad semantic
## remaps apply to the native GUI actions; the left stick stays available as a navigation fallback.
## Pass -1 to return to keyboard/mouse only.
static func set_gamepad(device_id: int, bindings: Dictionary = {}) -> int:
	var removed := isolate_joypads()
	if device_id < 0:
		return removed
	_selected_gamepad_id = device_id
	_add_action_binding("ui_accept", device_id, bindings.get("accept", {}), JOY_BUTTON_A)
	_add_action_binding("ui_cancel", device_id, bindings.get("back", {}), JOY_BUTTON_B)
	_add_action_binding("ui_up", device_id, bindings.get("navigate_up", {}), JOY_BUTTON_DPAD_UP)
	_add_action_binding("ui_down", device_id, bindings.get("navigate_down", {}), JOY_BUTTON_DPAD_DOWN)
	_add_action_binding("ui_left", device_id, bindings.get("navigate_left", {}), JOY_BUTTON_DPAD_LEFT)
	_add_action_binding("ui_right", device_id, bindings.get("navigate_right", {}), JOY_BUTTON_DPAD_RIGHT)
	_add_axis("ui_left", device_id, JOY_AXIS_LEFT_X, -1.0)
	_add_axis("ui_right", device_id, JOY_AXIS_LEFT_X, 1.0)
	_add_axis("ui_up", device_id, JOY_AXIS_LEFT_Y, -1.0)
	_add_axis("ui_down", device_id, JOY_AXIS_LEFT_Y, 1.0)
	return removed


static func selected_gamepad_id() -> int:
	return _selected_gamepad_id


## Joypad UI bindings, with device IDs included for selected-device isolation checks.
static func joypad_ui_events() -> PackedStringArray:
	var found := PackedStringArray()
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			for event in InputMap.action_get_events(action):
				if event is InputEventJoypadButton or event is InputEventJoypadMotion:
					found.append("%s: %s [device %d]" % [action, event.as_text(), event.device])
	return found


static func _add_action_binding(action: String, device_id: int, value: Variant, fallback_button: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	if not value is Dictionary or value.is_empty():
		_add_button(action, device_id, fallback_button)
		return
	var binding: Dictionary = value
	match str(binding.get("type", "")):
		"button":
			var button := int(binding.get("button", -1))
			if button >= 0 and button < JOY_BUTTON_MAX:
				_add_button(action, device_id, button as JoyButton)
		"axis":
			var axis := int(binding.get("axis", -1))
			var sign := int(binding.get("sign", binding.get("direction", 0)))
			var threshold := float(binding.get("threshold", 0.65))
			if axis >= 0 and axis < JOY_AXIS_MAX and absf(sign) == 1 and threshold > 0.0 and threshold <= 1.0:
				_add_axis(action, device_id, axis as JoyAxis, float(sign))
				_capture_action_deadzone(action)
				InputMap.action_set_deadzone(action, threshold)
		"key":
			var keycode := int(binding.get("keycode", 0))
			var physical_keycode := int(binding.get("physical_keycode", 0))
			if keycode != 0 or physical_keycode != 0:
				_add_key(action, keycode, physical_keycode, binding)


static func _add_button(action: String, device_id: int, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	var event := InputEventJoypadButton.new()
	event.device = device_id
	event.button_index = button
	event.pressed = true
	InputMap.action_add_event(action, event)


static func _add_axis(action: String, device_id: int, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		return
	var event := InputEventJoypadMotion.new()
	event.device = device_id
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)


static func _add_key(action: String, keycode: int, physical_keycode: int, binding: Dictionary) -> void:
	if not InputMap.has_action(action):
		return
	var event := InputEventKey.new()
	# InputMap prefers logical keys when both are set. Match the semantic router's
	# physical-first contract for captured bindings across keyboard layouts.
	event.keycode = (0 if physical_keycode != 0 else keycode) as Key
	event.physical_keycode = physical_keycode as Key
	event.ctrl_pressed = bool(binding.get("ctrl", false))
	event.alt_pressed = bool(binding.get("alt", false))
	event.shift_pressed = bool(binding.get("shift", false))
	event.meta_pressed = bool(binding.get("meta", false))
	# Only own newly inserted events: cleanup must not erase keyboard recovery
	# bindings that were already present before this controller was selected.
	if InputMap.action_has_event(action, event):
		return
	InputMap.action_add_event(action, event)
	var events: Array = _generated_key_events.get(action, [])
	events.append(event)
	_generated_key_events[action] = events


static func _capture_action_deadzone(action: String) -> void:
	if not _original_action_deadzones.has(action) and InputMap.has_action(action):
		_original_action_deadzones[action] = InputMap.action_get_deadzone(action)


static func _restore_action_deadzones() -> void:
	for action: Variant in _original_action_deadzones:
		if InputMap.has_action(str(action)):
			InputMap.action_set_deadzone(str(action), float(_original_action_deadzones[action]))
	_original_action_deadzones.clear()
