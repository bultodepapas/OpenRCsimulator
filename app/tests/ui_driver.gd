# UI test driver (MENU-PLAN UI-00, research 15): real input events, the way a player produces them.
# - tap(): a fresh InputEventKey with keycode AND physical_keycode (the flight reads physical keys), press + release,
#   then two process frames: parse_input_event is applied at the next frame flush, never inside the same call.
# - joy(): a joypad axis or button event on a fake device, for radio isolation checks.
# Input.action_press() does not move GUI focus and button.pressed.emit() bypasses it: neither is used here.
extends RefCounted

const FAKE_DEVICE := 15 # a device index no real pad uses in CI

var _tree: SceneTree


func _init(tree: SceneTree) -> void:
	_tree = tree


func tap(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	await settle()


func joy_axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = FAKE_DEVICE
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	await settle()


func joy_button(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = FAKE_DEVICE
		e.button_index = button
		e.pressed = pressed
		Input.parse_input_event(e)
	await settle()


## Name of the control with GUI focus, or "" when none.
func focus_name() -> String:
	var f := _tree.root.gui_get_focus_owner()
	return f.name if f != null else ""


## Two process frames: queued events are flushed and focus changes are applied.
func settle() -> void:
	await _tree.process_frame
	await _tree.process_frame
