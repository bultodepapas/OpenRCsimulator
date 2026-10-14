extends SceneTree
const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS := "user://test_controller_menu.cfg"
var failures := 0
var checks := 0
var app: Node
var ui: RefCounted

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func button(index: JoyButton, device := 15) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = index
		event.pressed = pressed
		Input.parse_input_event(event)
	await ui.settle()

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for suffix in ["", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	ui = UiDriver.new(self)
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	var observed: Array = [{"id": 15, "name": "Synthetic Xbox", "guid": "synthetic-xbox", "vendor_id": 1118, "product_id": 765, "known": true}]
	app.controllers.enumerate_devices = func() -> Array: return observed
	app.controllers.refresh()
	check("one pad defaults to flight and menus without opening settings", app.controllers.registry.selected_device_id("flight") == 15 and app.controllers.registry.selected_device_id("ui") == 15 and app.screens.is_top("home"))
	app.home.fly_button.grab_focus()
	await button(JOY_BUTTON_A)
	await create_timer(0.25).timeout
	check("first A on Fly launches using the automatic pad and neutral gate", app.flight != null and app.pause_menu != null and app.flight.session.radio.device_id == 15 and not app.flight.session.radio.armed and app.flight.session.sim.paused)
	check("automatic launch creates no saved controller profile", app.controllers.store.load_all().profiles.is_empty())
	app.pause_menu.end_button.grab_focus()
	await button(JOY_BUTTON_A)
	check("automatic-controller flight can return Home", app.flight == null and app.screens.is_top("home"))
	observed.append({"id": 14, "name": "Fake EdgeTX", "kind": "radio", "known": true})
	app.controllers.refresh()
	check("Home automatically selects radio flight and gamepad menus", app.controllers.registry.selected_device_id("flight") == 14 and app.controllers.registry.selected_device_id("ui") == 15)
	await button(JOY_BUTTON_A, 14)
	check("radio cannot activate menus", app.screens.is_top("home") and app.flight == null and app.controllers.registry.selected_device_id("ui") == 15)
	app.home.controls_button.grab_focus()
	await button(JOY_BUTTON_A)
	check("automatically selected gamepad opens focused Controls", app.screens.is_top("controls") and app.flight == null)
	var setup: Node = app.screens.top()
	setup.flight_device_picker.grab_focus()
	await button(JOY_BUTTON_A)
	await button(JOY_BUTTON_DPAD_DOWN) # automatic radio 14 -> gamepad 15
	await button(JOY_BUTTON_A)
	check("native gamepad events choose flight controller", setup.selected_flight_device_id() == 15)
	check("choosing a controller waits for Save", app.controllers.registry.selected_device_id("flight") == 14)
	setup.save_button.grab_focus()
	await button(JOY_BUTTON_A)
	check("one Save stores and activates the selected controller", app.controllers.registry.selected_device_id("flight") == 15 and app.controllers.store.load_all().profiles.size() == 1)
	check("Save returns to Home without launching and restores focus", app.screens.is_top("home") and app.flight == null and root.gui_get_focus_owner() == app.home.controls_button)
	check("Home launch displays selected controller glyph", app.home.fly_button.icon != null)
	app.home.fly_button.grab_focus()
	await button(JOY_BUTTON_A)
	await create_timer(0.25).timeout
	check("A launches into paused controller arming", app.flight != null and app.pause_menu != null and app.flight.session.sim.paused)
	check("Pause continue displays selected controller glyph", app.pause_menu.continue_button.icon != null)
	var session: Node = app.flight.session
	var hint: Node = app.flight.get_node_or_null("FirstFlightHint")
	check("controller flight hides the inapplicable keyboard flight hint", hint == null or not hint.visible)
	check("paused initial flight shows declared resume power", app.pause_menu.controller_value_label.visible and app.pause_menu.controller_value_label.text.contains("%.0f%%" % (session._pending_controller_start * 100.0)))
	for axis: JoyAxis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		await ui.joy_axis(axis, 0.0)
	await create_timer(0.25).timeout
	check("mapped axis evidence arms selected pad while menu holds flight", session.radio.armed and session.sim.paused)
	app.pause_menu.continue_button.grab_focus()
	await button(JOY_BUTTON_A)
	check("A Continue resumes only after arming", app.pause_menu == null and not session.sim.paused)
	var old_view: String = app.flight._rig.view
	await button(JOY_BUTTON_Y, 14)
	check("other controller cannot change camera", app.flight._rig.view == old_view)
	await button(JOY_BUTTON_Y)
	check("selected controller changes camera", app.flight._rig.view != old_view)
	await button(JOY_BUTTON_START)
	check("Menu opens Pause", app.pause_menu != null and session.sim.paused)
	var trim: float = session.trims.roll
	await button(JOY_BUTTON_DPAD_RIGHT)
	check("menu D-pad cannot trim aircraft", session.trims.roll == trim)
	app.pause_menu.controls_button.grab_focus()
	await button(JOY_BUTTON_A)
	check("Controls is reachable from Pause", app.screens.is_top("controls"))
	setup = app.screens.top()
	check("gamepad cannot enter radio calibration", not setup.calibrate_button.visible)
	setup.flight_device_picker.grab_focus()
	await button(JOY_BUTTON_A)
	await button(JOY_BUTTON_DPAD_UP) # gamepad 15 -> radio 14
	await button(JOY_BUTTON_A)
	check("draft radio exposes calibration without an Apply step", session.radio.profile.kind == "gamepad" and setup.calibrate_button.visible and not setup.calibrate_button.disabled)
	setup.calibrate_button.grab_focus()
	await button(JOY_BUTTON_A)
	check("Calibrate saves the chosen radio and starts its wizard in one action", session.radio.profile.kind == "radio" and session.calibration != null and app.pause_menu == null and session.sim.paused)
	await button(JOY_BUTTON_A)
	check("selected menu pad advances radio wizard", session.calibration != null and session.calibration.step == 1)
	await button(JOY_BUTTON_B)
	check("wizard cancel restores Pause without resuming", session.calibration == null and app.screens.is_top("pause") and session.sim.paused)
	app.pause_menu.end_button.grab_focus()
	await button(JOY_BUTTON_A)
	check("gamepad can end flight and return Home", app.flight == null and app.screens.is_top("home"))
	app.free()
	for suffix in ["", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	print("Controller menu: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
