# Investigation 15 probe: does an injected event move UI focus between two Buttons in headless Godot 4.7.2,
# and does a radio-like InputEventJoypadMotion navigate the UI through the built-in ui_* actions?
# It reports behaviour; it asserts nothing (exit 0 once everything is printed). Never run it with --path app.
# Run it from the repo root inside a throwaway minimal project, so the engine's built-in InputMap applies:
#   D=$(mktemp -d); printf 'config_version=5\n' > "$D/project.godot"
#   cp docs/research/menu-investigations/probes/15-focus-input-probe.gd "$D/"
#   .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path "$D" --script res://15-focus-input-probe.gd
# Without any project.godot, Godot 4.7.2 loads ~/.config/godot/editor_settings-4.7.tres instead and the ui_* actions
# came back keyboard-only (deadzone 0.20) on the dev VM: the joypad results then differ.
extends SceneTree

const FAKE_RADIO := 15 # same fake device id as app/tests/test_e2e_radio.gd

var _a: Button
var _b: Button
var _c: Button


func _initialize() -> void:
	_run()


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _owner() -> String:
	var f := root.gui_get_focus_owner()
	return f.name if f else "<none>"


func _reset() -> void:
	_a.grab_focus()
	await _frames()


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _action_event(action: StringName, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)


func _motion(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = FAKE_RADIO
	e.axis = axis as JoyAxis
	e.axis_value = value
	Input.parse_input_event(e)


func _case(label: String, inject: Callable, frames := 2) -> void:
	await _reset()
	var before := _owner()
	inject.call()
	var immediately := _owner()
	await _frames(frames)
	print("%-58s before=%s immediately=%s after_%d_frames=%s" % [label, before, immediately, frames, _owner()])


func _run() -> void:
	print("engine ", Engine.get_version_info().string, " display=", DisplayServer.get_name(), " project.godot=", FileAccess.file_exists("res://project.godot"))
	var box := VBoxContainer.new()
	root.add_child(box)
	for n in ["A", "B", "C"]:
		var btn := Button.new()
		btn.name = n
		btn.text = n
		btn.focus_mode = Control.FOCUS_ALL
		box.add_child(btn)
	_a = box.get_node("A")
	_b = box.get_node("B")
	_c = box.get_node("C")
	await _frames()
	for act in ["ui_down", "ui_up", "ui_accept", "ui_select"]:
		var evs := []
		for ev in InputMap.action_get_events(act):
			evs.append(ev.as_text())
		print("builtin %s: %s (deadzone %.2f)" % [act, ", ".join(evs), InputMap.action_get_deadzone(act)])

	print("-- keyboard / actions")
	await _case("parse KEY_DOWN press+release", func(): _key(KEY_DOWN, true); _key(KEY_DOWN, false))
	await _case("parse KEY_DOWN press+release, 0 frames awaited", func(): _key(KEY_DOWN, true); _key(KEY_DOWN, false), 0)
	await _frames() # the buffered events of the 0-frame case would otherwise move focus inside the next case
	print("%-58s focus=%s (events applied late, at the next frame flush)" % ["  ...same case, 2 frames later", _owner()])
	await _case("parse KEY_DOWN press only (no release)", func(): _key(KEY_DOWN, true))
	_key(KEY_DOWN, false)
	await _frames()
	await _case("parse KEY_TAB press+release", func(): _key(KEY_TAB, true); _key(KEY_TAB, false))
	await _case("parse InputEventAction ui_down press+release", func(): _action_event(&"ui_down", true); _action_event(&"ui_down", false))
	await _case("Input.action_press(ui_down) + action_release", func(): Input.action_press(&"ui_down"); Input.action_release(&"ui_down"))
	await _case("Input.action_press(ui_down) held 2 frames", func(): Input.action_press(&"ui_down"))
	Input.action_release(&"ui_down")
	await _frames()
	var pressed_count := [0]
	_b.pressed.connect(func(): pressed_count[0] += 1)
	_b.grab_focus()
	await _frames()
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await _frames()
	print("%-58s B.pressed emitted %d time(s)" % ["focus B, parse KEY_ENTER press+release", pressed_count[0]])

	print("-- radio-like joypad motion (device %d, no joy_connection_changed)" % FAKE_RADIO)
	await _case("JoypadMotion axis 1 (LEFT_Y) = +1.0", func(): _motion(1, 1.0))
	_motion(1, 0.0)
	await _case("JoypadMotion axis 1 = +0.4 (below 0.5 deadzone)", func(): _motion(1, 0.4))
	_motion(1, 0.0)
	await _case("JoypadMotion axis 0 (LEFT_X) = +1.0 (VBox: no right neighbour)", func(): _motion(0, 1.0))
	_motion(0, 0.0)
	_a.focus_neighbor_right = _a.get_path_to(_c) # give A a right neighbour: ui_right now has a target
	await _case("JoypadMotion axis 0 (LEFT_X) = +1.0 (A.right -> C)", func(): _motion(0, 1.0))
	_motion(0, 0.0)
	await _case("JoypadMotion axis 2 (RIGHT_X, EdgeTX throttle) = +1.0", func(): _motion(2, 1.0))
	_motion(2, 0.0)
	await _case("JoypadMotion axis 3 (RIGHT_Y) = +1.0", func(): _motion(3, 1.0))
	_motion(3, 0.0)
	# A held stick with sensor noise: three successive events, all above the deadzone.
	await _case("JoypadMotion axis 1: 0.98, 0.99, 1.0 (noisy held stick)", func(): _motion(1, 0.98); _motion(1, 0.99); _motion(1, 1.0), 3)
	_motion(1, 0.0)
	await _frames()

	print("-- after erasing joypad events from ui_* (the plan's UI-01 mitigation)")
	for act in InputMap.get_actions():
		if String(act).begins_with("ui_"):
			for ev in InputMap.action_get_events(act):
				if ev is InputEventJoypadMotion or ev is InputEventJoypadButton:
					InputMap.action_erase_event(act, ev)
	await _case("JoypadMotion axis 1 (LEFT_Y) = +1.0", func(): _motion(1, 1.0))
	_motion(1, 0.0)
	await _case("JoypadMotion axis 0 (LEFT_X) = +1.0 (A.right -> C)", func(): _motion(0, 1.0))
	_motion(0, 0.0)
	await _case("parse KEY_DOWN press+release (keyboard still works)", func(): _key(KEY_DOWN, true); _key(KEY_DOWN, false))
	_motion(1, 0.75)
	var same_frame := Input.get_joy_axis(FAKE_RADIO, JOY_AXIS_LEFT_Y)
	await _frames()
	print("Input.get_joy_axis(%d, LEFT_Y) after parsing +0.75: same frame %.2f, 2 frames later %.2f (raw axis still readable)" % [FAKE_RADIO, same_frame, Input.get_joy_axis(FAKE_RADIO, JOY_AXIS_LEFT_Y)])
	quit(0)
