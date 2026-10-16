# FW-27: the Home time-of-day choice. Saved in user://settings.cfg (additive key, schema 1), shown on a Home button in
# English and Spanish, applied at once to the Home backdrop and to the flight Fly starts; "day" keeps the calibrated
# fixed sun. The direct route never reads it.
# Run: godot --headless --path . --script res://tests/test_ui_field_world_time_of_day.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const Conditions := preload("res://render/world/conditions.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_ui_time_of_day.cfg"

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
	root.size = Vector2i(1280, 720)
	_preference_cases()
	await _home_and_flight()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	Conditions.session_preset = ""
	Atmosphere.state = {}
	TranslationServer.set_locale("en")
	print("all UI time-of-day checks passed" if _failures == 0 else "%d UI time-of-day checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _preference_cases() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	_check("no preferences -> passing evening", Preferences.load_from(PREFS).time_of_day == "evening")
	for invalid: Variant in ["midnight", 3, true, "noon"]: # noon is a command-line preset, not a Home choice
		var cfg := ConfigFile.new()
		cfg.set_value("meta", "schema", 1)
		cfg.set_value("flight", "time_of_day", invalid)
		cfg.save(PREFS)
		_check("invalid time %s -> passing evening" % str(invalid), Preferences.load_from(PREFS).time_of_day == "evening")
	var p := Preferences.load_from(PREFS)
	p.time_of_day = "night"
	_check("time choice round-trips", Preferences.save_to(PREFS, p) == OK and Preferences.load_from(PREFS).time_of_day == "night")
	var seen := {}
	var c := "day"
	for i in Conditions.HOME_CHOICES.size():
		seen[c] = true
		c = Conditions.next_home_choice(c)
	_check("the button cycles every choice and wraps to day", c == "day" and seen.size() == Conditions.HOME_CHOICES.size())
	for choice: String in Conditions.HOME_CHOICES:
		_check("choice %s is day, a solvable preset or a flowing start" % choice, choice == "day" or Conditions.PRESETS.has(choice) or Conditions.FLOWING.has(choice))
	Conditions.session_preset = "sunset"
	_check("session choice applies without arguments", Conditions.resolve(PackedStringArray()).get("preset", "") == "sunset")
	_check("arguments win over the session choice",
		Conditions.resolve(PackedStringArray(["--time_of_day=night"])).get("preset", "") == "night")
	Conditions.session_preset = "day"
	_check("day keeps the fixed sun", not Conditions.resolve(PackedStringArray()).time_of_day)
	Conditions.session_preset = ""


func _tab_until(target: String, max_presses := 32) -> bool:
	for _step in max_presses:
		if ui.focus_name() == target:
			return true
		await ui.tap(KEY_TAB)
	return ui.focus_name() == target


func _home_and_flight() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", 1)
	cfg.set_value("ui", "language", "en")
	cfg.set_value("ui", "first_flight_hint_seen", true)
	cfg.set_value("flight", "time_of_day", "night_dark")
	cfg.set_value("night", "field_lighting", "airfield")
	cfg.set_value("night", "campfire", true)
	cfg.save(PREFS)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.set("user_args", PackedStringArray())
	app.set("preferences_path", PREFS)
	root.add_child(app)
	await ui.settle()
	root.size = Vector2i(1280, 720)
	await ui.settle()
	var home: Control = app.get("home")
	var button: Button = home.get("time_button")
	_check("Home shows the saved compact choice", button.text == "Time of day\nNew moon", button.text)
	_check("Home backdrop receives the saved field-lighting profile and campfire",
		app.home_scene.night_options == {"field_lighting": "airfield", "campfire": true})
	_check("the backdrop is night: stars and field lights", app.home_scene.get_node_or_null("Stars") != null
		and app.home_scene.get_node_or_null("FieldLights") != null)

	var time_reachable := await _tab_until("TimeOfDay")
	_check("time-of-day action is keyboard reachable", time_reachable, ui.focus_name())
	if not time_reachable:
		await ui.close_app(app)
		for _frame in 10:
			await process_frame
		return
	await ui.tap(KEY_ENTER) # next choice after night_dark wraps to day
	_check("the button advances and wraps to day",
		home.get("time_of_day") == "day" and button.text == "Time of day\nDay", button.text)
	_check("day backdrop: calibrated fixed sun, no stars", Atmosphere.state.is_empty() and app.home_scene.get_node_or_null("Stars") == null)
	_check("one backdrop, drawn under the menu", app.get_children().filter(func(n: Node) -> bool: return n.name == "HomeScene").size() == 1
		and app.home_scene.get_index() < home.get_index())
	_check("Home keeps the keyboard focus", button.has_focus())

	app.set_time_of_day("sunset")
	await ui.settle()
	_check("choice saved at once", Preferences.load_from(PREFS).time_of_day == "sunset")
	TranslationServer.set_locale("es")
	await ui.settle()
	_check("Spanish compact label", button.text == "Hora del día\nAtardecer", button.text)
	TranslationServer.set_locale("en")
	await ui.settle()

	app.start_flight()
	await ui.settle()
	_check("Fly uses the chosen hour", not Atmosphere.state.is_empty() and absf(float(Atmosphere.state.sun_elevation_deg) - 0.5) < 0.05,
		str(Atmosphere.state.get("sun_elevation_deg")))
	_check("the flight has the dusk field lights", app.flight.get_node_or_null("FieldLights") != null)
	_check("Fly uses the same night settings as the Home backdrop",
		app.flight.night_options == {"field_lighting": "airfield", "campfire": true})
	app.open_pause()
	await ui.settle()
	_check("field-world flights expose a Sky and lighting action", app.pause_menu.time_of_day_button.text == "Sky and lighting")
	await ui.tap(KEY_DOWN) # Restart
	await ui.tap(KEY_DOWN) # Session options
	await ui.tap(KEY_ENTER)
	await ui.tap(KEY_DOWN) # Workshop
	await ui.tap(KEY_DOWN) # Sky and lighting
	_check("Sky and lighting is reachable inside Session options", ui.focus_name() == "TimeOfDay", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var field_dialog: CanvasLayer = app.time_of_day_dialog
	var controls: VBoxContainer = field_dialog.get("controls") as VBoxContainer
	var field_picker: OptionButton = controls.find_child("FieldLighting", true, false) as OptionButton
	var campfire_picker: OptionButton = controls.find_child("Campfire", true, false) as OptionButton
	var numeric_time: LineEdit = controls.find_child("ExactTime", true, false) as LineEdit
	_check("Field lighting opens a compact selector without numeric time controls",
		field_dialog.night_only and field_picker.is_visible_in_tree() and campfire_picker.is_visible_in_tree()
		and not numeric_time.is_visible_in_tree()
		and ui.focus_name() == "FieldLighting")
	var paused_state: PackedFloat64Array = app.flight.session.sim.state.duplicate()
	var paused_tick: int = app.flight.session.sim.tick
	field_picker.select(0)
	campfire_picker.select(0)
	field_dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("paused field selection updates the flight and saves both choices",
		app.time_of_day_dialog == null and app.flight.night_options == Preferences.NIGHT_DEFAULTS
		and Preferences.load_from(PREFS).night_field_lighting == "club"
		and Preferences.load_from(PREFS).night_campfire == false)
	_check("field-lighting Apply leaves the paused simulation untouched",
		app.flight.session.sim.paused and app.flight.session.sim.tick == paused_tick
		and app.flight.session.sim.state == paused_state)
	await ui.close_app(app)
	for _frame in 10:
		await process_frame
