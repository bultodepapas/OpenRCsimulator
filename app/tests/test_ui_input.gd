# UI-01b: radio sticks and buttons never navigate menus; keyboard does; the flight still reads the raw axes.
# Uses the project's real InputMap (run with --path; without a project the engine defaults differ and the
# check would pass for the wrong reason).
# Run: godot --headless --path . --script res://tests/test_ui_input.gd
extends SceneTree

const Home := preload("res://ui/home.gd")
const UiInput := preload("res://ui/ui_input.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

var _failures := 0
var ui: RefCounted


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run()


func _run() -> void:
	InputMap.load_from_project_settings()
	var before := UiInput.joypad_ui_events()
	_check("precondition: the engine binds joypad events to ui_* (%d found)" % before.size(),
		before.size() >= 6 and "ui_down" in "\n".join(before))

	var home: Control = Home.new()
	root.add_child(home)
	await ui.settle()
	_check("focus starts on Fly", ui.focus_name() == "Fly", ui.focus_name())
	# Without isolation, a radio's elevator stick (axis 1) moves the focus: this is the bug UI-01b prevents.
	await ui.joy_axis(JOY_AXIS_LEFT_Y, 1.0)
	_check("precondition: unisolated, the elevator stick moves the focus", ui.focus_name() == "Language", ui.focus_name())
	await ui.joy_axis(JOY_AXIS_LEFT_Y, 0.0)
	home.fly_button.grab_focus()

	var removed := UiInput.isolate_joypads()
	_check("isolation removed %d joypad events, none left" % removed, removed == before.size() and UiInput.joypad_ui_events().is_empty(),
		"\n".join(UiInput.joypad_ui_events()))
	for axis in [JOY_AXIS_LEFT_Y, JOY_AXIS_LEFT_X]:
		for value in [1.0, -1.0]:
			await ui.joy_axis(axis, value)
			_check("axis %d = %+.0f does not move the focus" % [axis, value], ui.focus_name() == "Fly", ui.focus_name())
			await ui.joy_axis(axis, 0.0)
	for button in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_Y]:
		await ui.joy_button(button)
		_check("button %d does not move the focus" % button, ui.focus_name() == "Fly", ui.focus_name())
	_check("no radio event activated Fly", not home.fly_button.disabled)

	await ui.joy_axis(JOY_AXIS_LEFT_Y, 0.75)
	var axis := Input.get_joy_axis(UiDriver.FAKE_DEVICE, JOY_AXIS_LEFT_Y)
	_check("the flight still reads the raw axis (%.2f)" % axis, is_equal_approx(axis, 0.75))
	await ui.tap(KEY_DOWN)
	_check("keyboard still navigates: Down -> Language", ui.focus_name() == "Language", ui.focus_name())
	home.free()

	# The entry applies the isolation itself, before showing any menu.
	InputMap.load_from_project_settings()
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = "user://test_ui_input_settings.cfg" # never the player's own settings
	root.add_child(app)
	_check("app_root isolates joypads at startup", UiInput.joypad_ui_events().is_empty(), "\n".join(UiInput.joypad_ui_events()))
	app.free()

	print("all UI input checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)
