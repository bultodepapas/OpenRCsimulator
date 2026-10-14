# A radio flies the airplane; it never navigates menus. A selected gamepad can be bound to
# ui_* actions, but each generated event is limited to one Godot connection handle.
extends RefCounted

static var _selected_gamepad_id := -1


## Erases joypad events from ui_* actions. Keyboard and mouse navigation remain untouched.
static func isolate_joypads() -> int:
	_selected_gamepad_id = -1
	var removed := 0
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
				removed += 1
	return removed


## Routes GUI navigation from exactly one selected gamepad. Pass -1 to return to keyboard/mouse only.
static func set_gamepad(device_id: int) -> int:
	var removed := isolate_joypads()
	if device_id < 0:
		return removed
	_selected_gamepad_id = device_id
	_add_button("ui_accept", device_id, JOY_BUTTON_A)
	_add_button("ui_cancel", device_id, JOY_BUTTON_B)
	_add_button("ui_up", device_id, JOY_BUTTON_DPAD_UP)
	_add_button("ui_down", device_id, JOY_BUTTON_DPAD_DOWN)
	_add_button("ui_left", device_id, JOY_BUTTON_DPAD_LEFT)
	_add_button("ui_right", device_id, JOY_BUTTON_DPAD_RIGHT)
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
