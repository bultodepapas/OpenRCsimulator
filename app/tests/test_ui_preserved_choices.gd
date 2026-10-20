# UI-32 (UI-30 audit AS-3, AS-4, AS-7, F8): browsing never overwrites a saved choice as a side effect.
# Real production shell with isolated preferences; selections go through the same app_root routes Home uses.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_preserved_choices.gd
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const Preferences := preload("res://app_state/preferences.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Landscapes := preload("res://landscapes/catalog.gd")
const PREFS := "user://test_ui_preserved_choices.cfg"
const HELICOPTER := "xcell-60-research"
const ELECTRIC := "turbo-lumber-evolution"

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
	await _run()
	print("UI preserved choices: %d failed" % _failures)
	quit(1 if _failures else 0)


func _new_app() -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	return app


func _close(app: Node) -> void:
	app.queue_free()
	await ui.settle()


func _run() -> void:
	TranslationServer.set_locale("en")
	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc", ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	var fixture: Dictionary = Preferences.DEFAULTS.duplicate(true)
	fixture.weather_config = WeatherSettings.GENTLE_PRACTICE.duplicate(true)
	_check("turbulent airplane weather fixture saves", WeatherSettings.has_turbulence(fixture.weather_config)
		and Preferences.save_to(PREFS, fixture) == OK)
	var app := await _new_app()
	var home: Control = app.home

	# --- AS-3: the helicopter shows and flies without turbulence, but never deletes the saved airplane turbulence.
	app.set_aircraft(HELICOPTER)
	await ui.settle()
	_check("helicopter Home summary hides unsupported turbulence", not WeatherSettings.has_turbulence(home.weather_config))
	_check("helicopter selection keeps the saved airplane turbulence",
		WeatherSettings.has_turbulence(app.preferences.weather_config)
		and WeatherSettings.has_turbulence(Preferences.load_from(PREFS).weather_config))
	app.set_aircraft(Catalog.DEFAULT_ID)
	await ui.settle()
	_check("returning to an airplane shows the turbulence again", WeatherSettings.has_turbulence(home.weather_config))

	# --- AS-7: each vehicle class keeps its own start; browsing never rewrites the other class.
	app.set_start_choice("airborne")
	app.set_aircraft(HELICOPTER)
	await ui.settle()
	_check("helicopter starts from its own default pad start", home.start_choice == "runway")
	app.set_start_choice("airborne") # practice hover
	app.set_aircraft(Catalog.DEFAULT_ID)
	await ui.settle()
	_check("airplane keeps the in-the-air start chosen before browsing", home.start_choice == "airborne",
		home.start_choice)
	app.set_aircraft(HELICOPTER)
	await ui.settle()
	_check("helicopter keeps its hover start", home.start_choice == "airborne", home.start_choice)
	_check("browsing alone saves no start change", Preferences.load_from(PREFS).start_choice == "runway")
	app.set_aircraft(Catalog.DEFAULT_ID)
	app.set_start_choice("runway")
	await ui.settle()
	var green := ""
	for id: String in Landscapes.ids():
		if id != app.landscape_id:
			green = id
	app.set_landscape(green)
	await ui.settle()
	_check("a landscape without a runway shows the in-the-air start", app.home.start_choice == "airborne")
	app.set_landscape(Landscapes.DEFAULT_ID)
	await ui.settle()
	home = app.home
	_check("returning to the club field restores the runway start", home.start_choice == "runway", home.start_choice)

	# --- F8: selecting an aircraft keeps Home's note (a failure debrief or a launch rejection).
	home.set_note("Kept note")
	app.set_aircraft(ELECTRIC)
	await ui.settle()
	_check("aircraft selection keeps the Home note", home.note_label.text == "Kept note", home.note_label.text)

	# --- AS-4: battery mode and fuel fill survive End flight and an application restart.
	home.set_battery_mode("ideal")
	home.fuel_button.pressed.emit() # full -> 75 %
	_check("electric aircraft shows the ideal battery choice", home.battery_mode == "ideal")
	app.start_flight()
	await ui.settle()
	_check("flight starts with the chosen battery mode", app.flight != null and app.flight.battery_mode == "ideal")
	app.end_flight()
	await ui.settle()
	_check("End flight keeps the battery choice", app.home.battery_mode == "ideal", app.home.battery_mode)
	app.set_aircraft("stik-glow-61fx-2t")
	await ui.settle()
	_check("glow aircraft shows the remembered fuel fill", Catalog.has_finite_fuel("stik-glow-61fx-2t")
		and is_equal_approx(app.home.fuel_start_fill, 0.75), str(app.home.fuel_start_fill))
	var saved := Preferences.load_from(PREFS)
	_check("Fly saved the battery and fuel choices", saved.battery_mode == "ideal" and is_equal_approx(float(saved.fuel_fill), 0.75),
		"%s %s" % [saved.battery_mode, saved.fuel_fill])
	await _close(app)
	app = await _new_app()
	_check("an application restart restores the fuel fill", is_equal_approx(app.home.fuel_start_fill, 0.75))
	app.set_aircraft(ELECTRIC)
	await ui.settle()
	_check("an application restart restores the battery mode", app.home.battery_mode == "ideal")
	await _close(app)
	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc", ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
