# FW-27: the Home time-of-day choice. Saved in user://settings.cfg (additive key, schema 1), shown on a Home button in
# English and Spanish, applied at once to the Home backdrop and to the flight Fly starts; "day" keeps the calibrated
# fixed sun. The direct route never reads it.
# Run: godot --headless --path . --script res://tests/test_ui_time_of_day.gd
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
	_check("no preferences -> day", Preferences.load_from(PREFS).time_of_day == "day")
	for invalid: Variant in ["midnight", 3, true, "noon"]: # noon is a command-line preset, not a Home choice
		var cfg := ConfigFile.new()
		cfg.set_value("meta", "schema", 1)
		cfg.set_value("flight", "time_of_day", invalid)
		cfg.save(PREFS)
		_check("invalid time %s -> day" % str(invalid), Preferences.load_from(PREFS).time_of_day == "day")
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


func _home_and_flight() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", 1)
	cfg.set_value("ui", "language", "en")
	cfg.set_value("ui", "first_flight_hint_seen", true)
	cfg.set_value("flight", "time_of_day", "night_dark")
	cfg.save(PREFS)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.set("user_args", PackedStringArray())
	app.set("preferences_path", PREFS)
	root.add_child(app)
	await ui.settle()
	var home: Control = app.get("home")
	var button: Button = home.get("time_button")
	_check("Home shows the saved choice", button.text == "Time of day: Night, no moon", button.text)
	_check("the backdrop is night: stars and field lights", app.home_scene.get_node_or_null("Stars") != null
		and app.home_scene.get_node_or_null("FieldLights") != null)

	button.grab_focus()
	await ui.settle()
	button.pressed.emit() # next choice after night_dark wraps to day
	await ui.settle()
	_check("the button advances and wraps to day", home.get("time_of_day") == "day" and button.text == "Time of day: Day", button.text)
	_check("day backdrop: calibrated fixed sun, no stars", Atmosphere.state.is_empty() and app.home_scene.get_node_or_null("Stars") == null)
	_check("one backdrop, drawn under the menu", app.get_children().filter(func(n: Node) -> bool: return n.name == "HomeScene").size() == 1
		and app.home_scene.get_index() < home.get_index())
	_check("Home keeps the keyboard focus", button.has_focus())

	app.set_time_of_day("sunset")
	await ui.settle()
	_check("choice saved at once", Preferences.load_from(PREFS).time_of_day == "sunset")
	TranslationServer.set_locale("es")
	await ui.settle()
	_check("Spanish label", button.text == "Hora del día: Atardecer", button.text)
	TranslationServer.set_locale("en")
	await ui.settle()

	app.start_flight()
	await ui.settle()
	_check("Fly uses the chosen hour", not Atmosphere.state.is_empty() and absf(float(Atmosphere.state.sun_elevation_deg) - 0.5) < 0.05,
		str(Atmosphere.state.get("sun_elevation_deg")))
	_check("the flight has the dusk field lights", app.flight.get_node_or_null("FieldLights") != null)
	app.queue_free()
	await process_frame
	await process_frame
