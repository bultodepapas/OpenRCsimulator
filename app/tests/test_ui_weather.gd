# UI weather settings: draft/cancel/apply, schema-1 preference validation, radio isolation, and Home -> Fly handoff.
# Run: godot --headless --path . --script res://tests/test_ui_weather.gd
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_ui_weather_settings.cfg"

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


func _run() -> void:
	TranslationServer.set_locale("en")
	_preferences_contract()
	_night_preference_contract()
	await _draft_dialog()
	await _future_schema_apply()
	await _home_to_flight()
	await _direct_route_is_calm()
	for path in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("all UI weather checks passed" if _failures == 0 else "%d UI weather checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _preferences_contract() -> void:
	for path in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var prefs := Preferences.load_from(PREFS)
	_check("fresh defaults include the gentle practice config", prefs.weather_config == WeatherSettings.GENTLE_PRACTICE)
	prefs.weather_config.speed_mps = 3.0
	_check("nested defaults are detached between loads", Preferences.load_from(PREFS).weather_config == WeatherSettings.GENTLE_PRACTICE)

	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", 1)
	cfg.set_value("flight", "aircraft", "jensen-das-ugly-stik-60")
	_check("old schema-1 file without weather remains readable", cfg.save(PREFS) == OK
		and Preferences.load_from(PREFS).weather_config == WeatherSettings.GENTLE_PRACTICE)

	var malformed := WeatherSettings.defaults()
	malformed["gust_period_s"] = 0.25
	cfg.set_value("flight", "weather_config", malformed)
	_check("invalid saved weather falls back to gentle practice", cfg.save(PREFS) == OK
		and Preferences.load_from(PREFS).weather_config == WeatherSettings.GENTLE_PRACTICE)
	prefs = Preferences.load_from(PREFS)
	prefs.weather_config["unknown"] = 1.0
	_check("saving an invalid weather object is rejected", Preferences.save_to(PREFS, prefs) == ERR_INVALID_DATA)

	var weather := WeatherSettings.defaults()
	weather.speed_mps = 2.75
	prefs.weather_config = weather
	_check("valid weather saves and reloads", Preferences.save_to(PREFS, prefs) == OK
		and Preferences.load_from(PREFS).weather_config == weather)

	var future_text := "[meta]\nschema=99\n[ui]\nlanguage=\"es\"\n[flight]\nweather_config=%s\n" % var_to_str(weather)
	var file := FileAccess.open(PREFS, FileAccess.WRITE)
	file.store_string(future_text)
	file.close()
	prefs = Preferences.load_from(PREFS)
	_check("future schema reads valid weather but becomes read-only", not prefs.writable and prefs.language == "es"
		and prefs.weather_config == weather)
	prefs.weather_config.speed_mps = 4.0
	_check("future schema settings are never overwritten", Preferences.save_to(PREFS, prefs) == ERR_FILE_NO_PERMISSION
		and FileAccess.get_file_as_string(PREFS) == future_text)


func _night_preference_contract() -> void:
	for path in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var prefs := Preferences.load_from(PREFS)
	_check("night defaults select the club profile, automatic activation and no campfire",
		prefs.night_field_lighting == "club" and prefs.night_campfire == false
		and prefs.night_field_activation == "auto")
	var legacy_options: Dictionary = Preferences.validate_night_options({"field_lighting": "airfield", "campfire": true})
	_check("legacy two-key night options migrate to automatic activation",
		legacy_options.ok and legacy_options.options == {"field_lighting": "airfield", "campfire": true, "field_activation": "auto"})
	var master_off_options: Dictionary = Preferences.validate_night_options({
		"field_lighting": "off", "campfire": false, "field_activation": "on",
	})
	_check("activation is preserved independently when the legacy master-off profile is selected",
		master_off_options.ok and master_off_options.options.field_lighting == "off"
		and master_off_options.options.field_activation == "on")
	prefs.night_field_lighting = "airfield"
	prefs.night_campfire = true
	prefs.night_field_activation = "on"
	_check("field profile, activation and campfire preference save independently",
		Preferences.save_to(PREFS, prefs) == OK
		and Preferences.load_from(PREFS).night_field_lighting == "airfield"
		and Preferences.load_from(PREFS).night_campfire == true
		and Preferences.load_from(PREFS).night_field_activation == "on")
	var invalid := Preferences.load_from(PREFS)
	invalid.night_field_lighting = "bright"
	_check("preference save rejects an unknown field-lighting value",
		Preferences.save_to(PREFS, invalid) == ERR_INVALID_DATA)
	invalid = Preferences.load_from(PREFS)
	invalid.night_campfire = "on"
	_check("preference save requires a boolean campfire value",
		Preferences.save_to(PREFS, invalid) == ERR_INVALID_DATA)
	invalid = Preferences.load_from(PREFS)
	invalid.night_field_activation = "sometimes"
	_check("preference save rejects an unknown field-activation value",
		Preferences.save_to(PREFS, invalid) == ERR_INVALID_DATA)
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", 1)
	cfg.set_value("night", "field_lighting", "airfield")
	cfg.set_value("night", "campfire", true)
	_check("legacy two-key night preferences load with automatic activation",
		cfg.save(PREFS) == OK and Preferences.load_from(PREFS).night_field_activation == "auto")
	cfg.set_value("night", "field_lighting", "bright")
	cfg.set_value("night", "campfire", "on")
	_check("invalid saved night values independently recover to strict defaults",
		cfg.save(PREFS) == OK
		and Preferences.load_from(PREFS).night_field_lighting == "club"
		and Preferences.load_from(PREFS).night_campfire == false
		and Preferences.load_from(PREFS).night_field_activation == "auto")
	var omitted: Dictionary = Preferences.night_options_from_args({})
	_check("direct arguments default to club lighting with the campfire off",
		omitted.get("ok", false) and omitted.options == Preferences.NIGHT_DEFAULTS)
	var selected: Dictionary = Preferences.night_options_from_args({"field-lighting": "airfield", "campfire": "on", "field-activation": "on"})
	_check("direct arguments accept the profile, activation and campfire choices",
		selected.get("ok", false) and selected.options == {"field_lighting": "airfield", "campfire": true, "field_activation": "on"})
	_check("direct arguments reject unknown field profiles", not Preferences.night_options_from_args({"field-lighting": "bright"}).ok)
	_check("direct arguments reject non-enum campfire values", not Preferences.night_options_from_args({"campfire": true}).ok)
	_check("direct arguments reject unknown field activation", not Preferences.night_options_from_args({"field-activation": "sometimes"}).ok)


func _draft_dialog() -> void:
	var precise := WeatherSettings.defaults()
	precise.speed_mps = 3.141592653589793
	precise.from_deg = 123.45678901234567
	precise.gust_mps = 1.2345678901234567
	precise.gust_up_mps = -2.345678901234567
	precise.gust_duration_s = 4.123456789012345
	precise.gust_period_s = 12.3456789012345
	precise.gust_delay_s = 9.87654321098765
	var prefs := Preferences.load_from(PREFS)
	prefs.writable = true
	prefs.language = "en"
	prefs.weather_config = precise
	_check("precision fixture valid", Preferences.save_to(PREFS, prefs) == OK)
	var app: Node = await _app()
	var home: Control = app.home
	_check("Home presents a weather button next to Fly", home.weather_button != null and home.weather_button.text.contains("Conditions"), home.weather_button.text)
	_check("Home initially focuses Fly", ui.focus_name() == "Fly", ui.focus_name())
	for step in 40:
		if ui.focus_name() == "Weather": break
		await ui.tap(KEY_TAB)
	_check("Weather remains reachable in the Home keyboard cycle", ui.focus_name() == "Weather", ui.focus_name())
	await ui.joy_axis(JOY_AXIS_LEFT_X, 1.0)
	_check("radio axis cannot move Home focus", ui.focus_name() == "Weather", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var dialog: CanvasLayer = app.weather_dialog
	_check("Enter opens a modal draft", dialog != null and dialog.name == "WeatherDialog")
	if dialog == null:
		await _close(app)
		return
	var night_controls: VBoxContainer = dialog.get("time_of_day_controls") as VBoxContainer
	var field_picker: OptionButton = night_controls.find_child("FieldLighting", true, false) as OptionButton
	var activation_picker: OptionButton = night_controls.find_child("FieldActivation", true, false) as OptionButton
	var campfire_picker: OptionButton = night_controls.find_child("Campfire", true, false) as OptionButton
	_check("Home conditions expose profile, activation and separate campfire choices",
		field_picker != null and field_picker.item_count == 3 and field_picker.selected == 0
		and activation_picker != null and activation_picker.item_count == 3 and activation_picker.selected == 0
		and campfire_picker != null and campfire_picker.item_count == 2 and campfire_picker.selected == 0)
	var dialog_panel: Control = dialog.find_children("WeatherPanel", "PanelContainer", true, false)[0]
	var dialog_minimum := dialog_panel.get_combined_minimum_size()
	_check("weather dialog panel fits the 1280×720 base layout", dialog_minimum.x <= 1280.0 and dialog_minimum.y <= 720.0,
		str(dialog_minimum))
	_check("all six requested weather fields are available", dialog.field_inputs.size() == 6)
	for key: String in ["speed_mps", "from_deg", "gust_mps", "gust_up_mps", "gust_duration_s", "gust_period_s"]:
		var edit: LineEdit = dialog.field_inputs[key]
		_check("%s field round-trips the complete float64" % key, edit.text.to_float() == precise[key], edit.text)
	var speed_edit: LineEdit = dialog.field_inputs["speed_mps"]
	_check("gust delay stays hidden from the form", not dialog.field_inputs.has("gust_delay_s"))
	await ui.joy_axis(JOY_AXIS_LEFT_X, -1.0)
	_check("radio axis cannot move modal focus", ui.focus_name() == "WeatherPreset", ui.focus_name())

	# Change a draft, then cancel with Esc. Neither the in-memory choice nor the saved config changes.
	speed_edit.text = "8.5"
	field_picker.select(1)
	activation_picker.select(1)
	campfire_picker.select(1)
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("Esc cancels and returns focus to Weather", app.weather_dialog == null and ui.focus_name() == "Weather", ui.focus_name())
	_check("cancel leaves the original persisted config untouched", Preferences.load_from(PREFS).weather_config == precise)
	_check("cancel also discards night-option drafts", Preferences.load_from(PREFS).night_field_lighting == "club"
		and Preferences.load_from(PREFS).night_campfire == false
		and Preferences.load_from(PREFS).night_field_activation == "auto")

	await ui.tap(KEY_ENTER)
	await ui.settle()
	dialog = app.weather_dialog
	_check("reopen begins from the committed precision values", dialog.field_inputs["speed_mps"].text.to_float() == precise.speed_mps)
	night_controls = dialog.get("time_of_day_controls") as VBoxContainer
	field_picker = night_controls.find_child("FieldLighting", true, false) as OptionButton
	activation_picker = night_controls.find_child("FieldActivation", true, false) as OptionButton
	campfire_picker = night_controls.find_child("Campfire", true, false) as OptionButton
	speed_edit = dialog.field_inputs["speed_mps"]
	speed_edit.text = "999"
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("out-of-range edit displays an error and stays in the draft", dialog.error_label.visible and app.weather_dialog == dialog)
	_check("invalid draft does not change the committed config", Preferences.load_from(PREFS).weather_config == precise)
	speed_edit.text = String(dialog._initial_text["speed_mps"])
	field_picker.select(1)
	activation_picker.select(1)
	campfire_picker.select(1)
	# Apply untouched text through the focused button to verify the hidden full-precision config survives serialization.
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var saved: Dictionary = Preferences.load_from(PREFS).weather_config
	_check("Apply preserves every unedited value and hidden gust delay", saved == precise, str(saved))
	_check("Apply saves the independent airfield and campfire selections",
		Preferences.load_from(PREFS).night_field_lighting == "airfield"
		and Preferences.load_from(PREFS).night_campfire == true
		and Preferences.load_from(PREFS).night_field_activation == "on")
	_check("Apply returns focus and closes the modal", app.weather_dialog == null and ui.focus_name() == "Weather", ui.focus_name())

	# A preset updates only the draft until Apply, and Apply uses the validated preset values.
	await ui.tap(KEY_ENTER)
	await ui.settle()
	dialog = app.weather_dialog
	dialog._on_preset_selected(2) # Steady breeze; only selection is synthetic, Apply still uses the real button/key path.
	_check("preset fills the draft without changing saved preferences", dialog.field_inputs["speed_mps"].text.to_float() == 3.0
		and dialog.preset_picker.selected == 2 and Preferences.load_from(PREFS).weather_config == precise)
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Apply commits the chosen preset", Preferences.load_from(PREFS).weather_config.speed_mps == 3.0)

	app.set_language("es")
	await ui.settle()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	dialog = app.weather_dialog
	_check("Spanish localizes Home and the modal preset list", home.weather_button.text.begins_with("Condiciones")
		and dialog.preset_picker.get_item_text(1) == "Calma", "%s / %s" % [home.weather_button.text, dialog.preset_picker.get_item_text(1)])
	_check("Spanish localizes the compact night profile and campfire choices",
		dialog.time_of_day_controls.field_lighting_picker.get_item_text(0) == "Club suave"
		and dialog.time_of_day_controls.field_lighting_picker.get_item_text(1) == "Aeropuerto"
		and dialog.time_of_day_controls.field_activation_picker.get_item_text(0) == "Automática"
		and dialog.time_of_day_controls.field_activation_picker.get_item_text(1) == "Siempre encendidas"
		and dialog.time_of_day_controls.field_activation_picker.get_item_text(2) == "Siempre apagadas"
		and dialog.time_of_day_controls.campfire_picker.get_item_text(0) == "Apagada"
		and dialog.time_of_day_controls.campfire_picker.get_item_text(1) == "Encendida")
	var untranslated := PackedStringArray()
	for control in dialog.find_children("*", "", true, false):
		if (control is Label or control is Button) and control.can_auto_translate() and control.text != "" and control.atr(control.text) == control.text:
			untranslated.append(control.text)
	_check("Spanish modal has no untranslated focusable or instructional text", untranslated.is_empty(), str(untranslated))
	await ui.tap(KEY_ESCAPE)
	await _close(app)


func _home_to_flight() -> void:
	for path in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var prefs := Preferences.load_from(PREFS)
	var weather := WeatherSettings.defaults()
	weather.speed_mps = 1.0
	weather.from_deg = 270.0
	prefs.weather_config = weather
	prefs.night_field_lighting = "airfield"
	prefs.night_campfire = true
	prefs.night_field_activation = "on"
	_check("non-calm Home-to-Fly fixture saves", Preferences.save_to(PREFS, prefs) == OK)
	var app: Node = await _app()
	_check("Home backdrop receives the saved field and campfire choices",
		app.home_scene.night_options == {"field_lighting": "airfield", "campfire": true, "field_activation": "on"})
	await ui.tap(KEY_ENTER)
	await ui.settle()
	if app.flight == null:
		_check("mild non-calm Home flight starts", false, str(app.home))
		await _close(app)
		return
	if app.flight.get_script() == null:
		_check("flight scene script loads for the Home handoff", false, "main.gd did not load")
		await _close(app)
		return
	_check("successful Fly passes the chosen config to main before adding the flight", app.flight.weather_config == weather)
	_check("Home to Fly passes the same saved night options",
		app.flight.night_options == {"field_lighting": "airfield", "campfire": true, "field_activation": "on"})
	_check("session received the same weather configuration", app.flight.session.weather_configuration() == weather)
	_check("successful Fly remembers the weather and night options",
		Preferences.load_from(PREFS).weather_config == weather
		and Preferences.load_from(PREFS).night_field_lighting == "airfield"
		and Preferences.load_from(PREFS).night_campfire == true
		and Preferences.load_from(PREFS).night_field_activation == "on")
	await _close(app)


func _future_schema_apply() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", 99)
	cfg.set_value("ui", "language", "en")
	cfg.set_value("flight", "weather_config", WeatherSettings.defaults())
	_check("future-schema UI fixture saves", cfg.save(PREFS) == OK)
	var original := FileAccess.get_file_as_string(PREFS)
	var app: Node = await _app()
	for step in 40:
		if ui.focus_name() == "Weather": break
		await ui.tap(KEY_TAB)
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var dialog: CanvasLayer = app.weather_dialog
	var speed_edit: LineEdit = dialog.field_inputs["speed_mps"]
	speed_edit.text = "2.5"
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("future schema Apply takes effect for this session", app.preferences.weather_config.speed_mps == 2.5
		and app.home.weather_config.speed_mps == 2.5)
	_check("future schema save failure is visible on Home", app.home.note_label.visible
		and app.home.note_label.text.begins_with("Could not save settings"), app.home.note_label.text)
	_check("future schema Apply leaves the original file byte-for-byte unchanged", FileAccess.get_file_as_string(PREFS) == original)
	await _close(app)


func _direct_route_is_calm() -> void:
	var prefs := Preferences.load_from(PREFS)
	var saved_weather: Dictionary = prefs.weather_config.duplicate(true)
	prefs.night_field_lighting = "off"
	prefs.night_campfire = false
	prefs.night_field_activation = "off"
	_check("prepare different saved night settings for direct CLI override",
		Preferences.save_to(PREFS, prefs) == OK)
	var original := FileAccess.get_file_as_string(PREFS)
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray(["--quick-flight", "--field-lighting=airfield", "--field-activation=on", "--campfire=on"])
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	if app.flight == null or app.flight.get_script() == null:
		_check("direct flight script starts without reading player weather", false)
		await _close(app)
		return
	_check("direct route keeps the calm default", app.flight.session.weather_configuration() == WeatherSettings.defaults())
	_check("direct CLI options override and ignore different saved night preferences",
		app.flight.night_options == {"field_lighting": "airfield", "campfire": true, "field_activation": "on"}
		and Preferences.load_from(PREFS).night_field_lighting == "off"
		and Preferences.load_from(PREFS).night_campfire == false
		and Preferences.load_from(PREFS).night_field_activation == "off")
	_check("direct route leaves stored non-calm preference bytes alone", FileAccess.get_file_as_string(PREFS) == original
		and Preferences.load_from(PREFS).weather_config == saved_weather)
	await _close(app)


func _app() -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	return app


func _close(app: Node) -> void:
	await ui.close_app(app)
