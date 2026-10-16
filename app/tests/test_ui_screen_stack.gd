# UI-21: top-screen isolation and five real Home -> Fly -> End cycles without node growth.
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Home := preload("res://ui/home.gd")
const Screen := preload("res://ui/screen.gd")
const PREFS := "user://test_ui_screen_stack.cfg"
var _failures := 0
var ui: RefCounted


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run()


func _check(label: String, ok: bool) -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label)


func _run() -> void:
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	Preferences.save_to(PREFS, prefs)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	var initial_nodes := _count(app)
	_check("Home is the only screen", app.screens.size() == 1 and app.screens.top() == app.home)
	var duplicate := Home.new()
	_check("duplicate screen is rejected without attaching it", not app.screens.push("home", duplicate)
		and duplicate.get_parent() == null and app.screens.size() == 1)
	duplicate.free()
	_check("an attached screen cannot be registered under another ID", not app.screens.push("other", app.home)
		and app.screens.size() == 1 and app.screens.top() == app.home)
	var toast := Screen.new()
	toast.kind = Screen.Kind.TOAST
	_check("nonblocking overlays stay outside navigation", not app.screens.push("toast", toast)
		and app.screens.top() == app.home and root.gui_get_focus_owner() == app.home.fly_button)
	toast.free()

	app.home.help_button.grab_focus()
	await ui.tap(KEY_ENTER)
	var help: CanvasLayer = app.help
	app.open_help()
	app.open_weather()
	_check("a modal refuses repeated or lower-screen actions", app.screens.size() == 2
		and app.help == help and app.weather_dialog == null)
	for index in 8:
		await ui.tap(KEY_TAB)
		_check("Help keeps keyboard focus inside its surface (%d)" % index,
			help.is_ancestor_of(root.gui_get_focus_owner()))
	await _click(app.home.fly_button.get_global_rect().get_center())
	_check("clicking covered Fly leaves Home and Help intact", app.flight == null and app.help == help)
	await ui.tap(KEY_ESCAPE)
	_check("Help restores the opener", app.help == null and root.gui_get_focus_owner() == app.home.help_button)

	# Windows input injection can provide logical Escape with a different physical scan code.
	# It must still unwind only the top menu and restore its opener.
	app.open_settings(app.home.settings_button)
	await ui.settle()
	var settings: Node = app.screens.top()
	settings._show_category(1)
	var controls_opener: Control = settings._destinations.get_child(0)
	app.open_controls(controls_opener)
	await ui.settle()
	for pressed: bool in [true, false]:
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.physical_keycode = KEY_BACKSPACE
		escape.pressed = pressed
		Input.parse_input_event(escape)
	await ui.settle()
	_check("logical Escape closes nested Controls and restores Settings focus",
		app.screens.top() == settings and root.gui_get_focus_owner() == controls_opener)
	await ui.tap(KEY_ESCAPE)
	_check("closing Settings restores Home after logical Escape", app.screens.is_top("home")
		and root.gui_get_focus_owner() == app.home.settings_button)

	# Destroy a lower control while it is suspended (keyboard-layout/focus notifications rebuild key caps).
	app.open_help(app.home.help_button)
	app.home.call("_fill_legend")
	await ui.settle()
	app.close_help()
	await ui.settle()
	_check("rebuilt lower controls do not break focus return", root.gui_get_focus_owner() == app.home.help_button)

	for cycle in 5:
		app.home.fly_button.grab_focus()
		await ui.tap(KEY_ENTER)
		var session: Node = app.flight.session
		_check("Fly removes every menu (%d)" % cycle, app.screens.size() == 0)
		await ui.tap(KEY_ESCAPE)
		var tick: int = session.sim.tick
		app.pause_menu.help_button.grab_focus()
		await ui.tap(KEY_ENTER)
		for code: Key in [KEY_R, KEY_T, KEY_P, KEY_F5]:
			await ui.tap(code)
		app.continue_flight()
		app.restart_flight()
		app.end_flight()
		_check("nested Help blocks flight actions and keeps the session frozen (%d)" % cycle,
			app.help != null and app.flight.session == session and session.sim.tick == tick
			and session.holds.has("menu") and not app.flight.recorder.recording)
		await ui.tap(KEY_ESCAPE)
		_check("closing Help keeps Pause and its hold (%d)" % cycle, app.pause_menu != null
			and session.holds.has("menu") and session.sim.paused)
		app.pause_menu.exit_options_button.grab_focus()
		await ui.tap(KEY_ENTER) # reveal End inside Exit options
		await ui.tap(KEY_DOWN)
		await ui.tap(KEY_ENTER)
		await ui.settle()
		_check("End returns to one Home without node growth (%d, %d nodes)" % [cycle, _count(app)],
			app.flight == null and app.screens.size() == 1 and _count(app) == initial_nodes
			and root.gui_get_focus_owner() == app.home.fly_button)
	await ui.close_app(app)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("all UI screen stack checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(0 if _failures == 0 else 1)


func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		Input.parse_input_event(event)
	await ui.settle()


func _count(node: Node) -> int:
	var result := 1
	for child: Node in node.get_children():
		result += _count(child)
	return result
